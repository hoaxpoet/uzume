# BUG-176 — fresh local-file preparation memory diagnosis

**Date:** 2026-10-08

**Commit:** `17782edd` plus the preserved dirty Understory worktree

**Build:** Debug, 1920×1080, Apple M2 Pro

**Bundle:** `/private/tmp/uzume-understory-diag-17782edd/Build/Products/Debug/Uzume.app`

**Executable SHA-256:** `bb16e95c1d87ba494d4eee26d6d2ee2586078da9a55cea061cb1ab9bd021a28a`

**Debug payload SHA-256:** `b045c372a9c75f358552c632a17d1e118e4005b45e12b1aecd549cd7f04fb9ea`

**Dirty-worktree fingerprint:** `754371db0ca1e68eca4e4f5d2c2aaf1cd3b16bfb1f8f6fd515ff3d6d65d06f53`

## Reproduction

`Scripts/memrepro.sh` moved the content-addressed cache entry for
`/Users/Shared/memrepro/01 Dance Yrself Clean.mp3` aside, launched the exact
bundle with Understory pinned, sampled `phys_footprint` every two seconds, and
restored the original cache from its exit trap. PID `74931` and binary path were
confirmed by `ps`. The session was
`~/Documents/uzume_sessions/2026-10-09T01-22-55Z`.

The watchdog stopped the process at 8,519 MB after 127 seconds. The app never
reached `startLocalFiles→ready`; `features.csv` and `stems.csv` contain headers
only. This run therefore failed during fresh preparation, before playback and
before any recorded Understory frame.

Raw footprint samples: `docs/diagnostics/BUG176/bug176-diagnosis-17782edd.csv`.

| Elapsed | Footprint |
|---:|---:|
| 0 s | 648 MB |
| 60 s | 916 MB |
| 98 s | 1,254 MB |
| 108 s | 2,076 MB |
| 112 s | 3,223 MB |
| 118 s | 5,275 MB |
| 123 s | 7,415 MB |
| 127 s | 8,519 MB (watchdog) |

From 98–127 seconds, footprint grew by 7,265 MB. Linear regression over the 15
samples in that interval is approximately 271 MB/s.

## Stage correlation

`session.log` records the cache miss at 20:23:01 and the completed loudness
profile at 20:23:20. The deterministic pipeline then enters `analyzePreview`,
followed by the full-file stem-series sweep.

The macOS unified log supplies the decisive correlation:

- the first one-window STFT began at 20:23:20;
- the repeated full-file sweep began at 20:24:39, matching the start of steep
  footprint growth;
- 71 forward STFT dispatches and 568 inverse dispatches completed before the
  watchdog (eight inverse dispatches per separation: four stems × two channels);
- dispatch IDs advanced from 12 through 710;
- all 71 forward calls used the same 7,061,504-byte input buffer and the same
  pair of 3,532,476-byte outputs;
- all 568 inverse calls likewise used one unchanged buffer set.

The track duration is 538.15 seconds. At the sweep's two-second hop,
`analyzeStemSeries` schedules about 270 calls to `StemSeparator.separate`.

## Root cause

**Failure class:** `resource-management` in the full-file stem-series analysis,
not an Understory geometry or render-state allocation.

`SessionPreparer.analyzeStemSeries` runs the entire long-lived loop inside one
detached task without a per-window `autoreleasepool`. Every iteration calls
`StemSeparator.separate`; the fixed Metal buffers are reused, but the MPSGraph
paths create fresh Objective-C wrapper and result objects on every call:

- `StemFFTEngine.runForwardGraph` creates three `MPSGraphTensorData` objects and
  feed/result dictionaries;
- `StemModelEngine.predict` creates input tensor data, a feed dictionary and a
  result dictionary whose tensors are read back;
- `StemFFTEngine.runInverseGraph` repeats tensor-data and dictionary creation
  eight times per separation.

Those temporary objects are not drained at the window boundary. Their lifetime
therefore follows the long detached task rather than one separation window.
The measured monotonic growth is proportional to repeated graph dispatch while
the underlying Metal buffer identities remain constant.

This diagnosis does not claim the expensive Understory fragment shader meets
its frame budget. It shows that the P0 memory event reproduces before playback,
and that the first fix must bound the fresh-preparation sweep independently of
the preset renderer.

## Fix boundary and pre-written verification

The fix increment should:

1. establish one explicit autorelease boundary per separation window;
2. keep the existing fixed Metal buffers and graph/queue objects reusable;
3. avoid accumulating result collections or encoded-but-unfinished ML work;
4. add a production-path long-sweep regression that samples footprint at fixed
   intervals and fails on monotonic growth;
5. re-run this exact track under `Scripts/memrepro.sh` before evaluating
   Understory playback or GPU frame cost.

The live gate remains: peak below 3 GB, at least five playback minutes, and
footprint flat within ±50 MB after minute one. The separate headless 1080p
Understory soak and Release frame-budget gates remain required after preparation
can complete.
