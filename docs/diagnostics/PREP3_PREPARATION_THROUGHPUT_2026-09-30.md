# PREP.3 — the sweep stops waiting on itself

**Date:** 2026-09-30 · **Increment:** PREP.3 (Phase PREP, third) · **Decision it feeds:** [D-242] · **Artifacts:** `docs/diagnostics/PREP3/`

Every wall-clock number here is **Release** (`swift build -c release`, `PrepTimingRunner`), Mac mini
**Apple M2 Pro, 16 GB**, macOS 26.5.1, **cold cache** (a fresh `mktemp -d` scratch `--cache` per run;
Matt's persistent stem cache was never read, written, moved or cleared). Every timing run waited for
the 1-minute load average to sit under 4 for three consecutive checks: peer sessions were compiling
at load averages of 20–46 during the day, and timing taken then would have measured them.

---

## The headline

**Bowie *Low* (11 FLAC, 2,328.6 s of audio): 166.6 s → 58.5 s to prepare, 2.85× faster. Stem values
are unchanged to float rounding.** Peak memory footprint went from **12.9 GB** to **2.6 GB**.

**Does 40 tracks fully prepare inside 300 s? Yes, projected at 241 s.** At 0.0251 s of preparation
per second of audio, 40 × 4-minute tracks (9,600 s) is 241 s, with no change to the sweep's
`hopSeconds`, window length or kept-span placement (Option 2 not taken). It is a projection from an
11-track album, linear in duration as PREP.1 showed. A real 40-track run is task 7.

**Start now** (D-056 threshold kept at three tracks): the first three *Low* tracks are ready
after **11.3 s**, down from **31.0 s**. Projected for three 4-minute tracks: **18.1 s**, down from
51.5 s.

---

## 1. Baseline vs final, per stage

`base-serial/` (unmodified main) vs `final-serial/` (this branch). `cores` = CPU-seconds per wall
second.

| stage | base wall s | base share | final wall s | final share | final cores |
|---|---|---|---|---|---|
| `stem_series_sweep` | **144.8** | 87.0 % | **55.7** | 67.8 % | 0.81 |
| `beat_grid` | 6.3 | 3.8 % | 7.0 | 8.6 % | 0.75 |
| `mir` | 5.1 | 3.0 % | 5.1 | 6.3 % | 1.52 |
| `instrument_family` | 3.7 | 2.2 % | 5.1 | 6.2 % | 1.30 |
| `decode` | 2.7 | 1.6 % | 4.7 | 5.7 % | 1.86 |
| `stem_separation` | 1.7 | 1.0 % | 2.3 | 2.8 % | 1.11 |
| `grid_onset_calibration` | 0.7 | 0.4 % | 0.7 | 0.9 % | 1.52 |
| `content_hash` | 0.4 | 0.3 % | 0.6 | 0.7 % | 1.14 |
| `stem_warmup` | 0.4 | 0.2 % | 0.4 | 0.4 % | 1.88 |
| `loudness_profile` | 0.2 | 0.1 % | 0.2 | 0.3 % | 1.46 |
| `cache_write` | 0.3 | 0.2 % | 0.1 | 0.2 % | 0.67 |
| **sum of stages** | **166.5** | | **82.2** | | |
| **per-track wall (`TRACK_TOTAL`)** | **166.5** | | **58.5** | | |
| peak RSS / peak footprint | 4.65 GB / 12.93 GB | | 1.44 GB / 2.62 GB | | |

**The sum of stages is now 23.7 s (29 %) larger than the wall clock**, which is how much task 5 hides.
The preview analysis (`beat_grid`, `mir`, `instrument_family`, `stem_separation`, …) runs alongside
the sweep, and hash and decode run one track ahead. Stages that now overlap the sweep read slightly
slower than at baseline (`beat_grid` 6.3 → 7.0 s, `decode` 2.7 → 4.7 s) because they share the
machine with it. Their wall time no longer adds to the track's.

**The sweep's sub-stages and one separation, split** (`base-serial/summary.txt`, `final-serial/summary.txt`):

| | base | final |
|---|---|---|
| `sweep_separate` / `sweep_analyze` | 136.8 s / 7.7 s | 55.3 s / 7.6 s (the analyzer overlaps the next group's separation) |
| model run | 88.9 ms per window | **225 ms per run of 8 = 28.1 ms per window** |
| inverse STFT | 19.9 ms per window | 8.3 ms |
| readback | 2.6 ms × 2 per window | 16.1 ms per run of 8 |
| STFT | 2.5 ms | 2.4 ms |

**The sweep was still dominant at baseline** (87 %, task 1's stop condition did not fire). The
model run was 77 % of each separation, and the analyzer only 5 % of the sweep.

---

## 2. Each task's own contribution, measured

The album was run after each task with that task's binary. These are single runs except where noted,
and PREP.1 measured ~4 % run-to-run spread.

| after | album wall | Δ | peak RSS / footprint | artifact |
|---|---|---|---|---|
| baseline (main @ 42007250) | 166.6 s | | 4.65 / 12.93 GB | `base-serial/` |
| task 2: BUG-177 (#345) + pre-allocated model outputs + pools | 161.5 s | −5.1 s | 0.93 / 1.18 GB | `album-task2/` |
| task 3: mono 4 inverse transforms, one batched inverse run | 147.4 s | −14.1 s | 1.05 / 1.34 GB | `album-task3/` |
| task 4: 8 windows per model run, analysis behind the GPU | 71.0 s | **−76.4 s** | 1.49 / 2.45 GB | `nsweep/N8/` |
| task 5a: `analyzePreview` alongside the sweep | 58.5 s | −12.5 s | 1.55 / 2.46 GB | `album-task5a-noprefetch/` |
| task 5b: next file read one track ahead | 57.9 s (mean of 3) | −0.3 s (mean of 3 pairs) | 1.44–1.77 / 2.54–2.62 GB | `ab5b-*`, `final-serial/` |

**Task 5b is real but marginal.** Three alternated pairs, without vs with the lookahead: 58.5 / 57.9 /
58.2 s vs 58.5 / 57.4 / 57.7 s. Hash and decode now run during the previous track, but the
per-track critical path is the sweep, and the prefetch's decode competes with it for CPU (`decode`
reads 1.86 cores, contended). It is kept because it is tested, bounded to one file, and costs nothing
measurable. If it ever costs something, it is the first thing to remove.

---

## 3. Memory: the hypothesis, the scaling test, and BUG-177

**The hypothesis held, and another session got there first.** Today BR.MEM (#345, merged mid-session)
filed and fixed BUG-177 from Matt's listening session 1. Each `separate` call left about 32 MB of
MPSGraph autoreleased objects that the sweep's synchronous loop never drained. It is the same defect
PREP.1 §5 saw as 23–45 GB at four workers. PREP.3 measured the per-length curve and added the parts
#345 left: `StemModelEngine.predict()` writes through `resultsDictionary` into pre-allocated buffers
(no four ~7 MB result tensors per call, no `readBytes` copy), and the Beat This! and PANNs per-call
bodies drain their own pools. No new BUG ID; BUG-177's entry carries the addition.

One track per process, Release (`scaling-before/`, `scaling-after-bug177/`, `scaling-after-prep3/`):

| track | audio | windows | footprint before | after #345 | after PREP.3 task 2 |
|---|---|---|---|---|---|
| Breaking Glass | 112.9 s | 58 | 2.78 GB | 1.18 GB | 1.10 GB |
| Sound And Vision | 183.4 s | 93 | 3.97 GB | 1.24 GB | 1.14 GB |
| Art Decade | 227.2 s | 115 | 4.75 GB | 1.27 GB | 1.15 GB |
| Subterraneans | 339.3 s | 171 | **11.93 GB** | 1.39 GB | 1.22 GB |
| Warszawa | 383.7 s | 193 | 9.23 GB | 1.42 GB | 1.24 GB |

What remains grows by ~0.5 MB per second of audio, about three copies of the track's decoded mono PCM.
That is the track's own data, not a per-call leak (an estimate, not attributed allocation by
allocation). **Four tracks at once (`--concurrency 4`), killed by `memorystatus` at 23–45 GB in
PREP.1, now completes: 80.8 s, peak footprint 3.1 GB** (`mem-concurrency4/`). That was measured
after task 2 and before batching.

**The goldens were bit-identical after task 2** (`parity-2-memory/`), as required. The golden
capture itself was killed (exit 137) on its third track before the fix: three whole-track sweeps in
one synchronous stretch.

⚠ `StemSeparatorMemoryTests` (#345's gate) reads *process-wide* footprint. In a filtered parallel run
on unmodified main it failed one time in two (170 MB against its 150 MB bound) because other suites
allocate in the same process. Alone it passes every time. It was made deterministic in #346
(minimum growth over up to three batches; bound unchanged).

**What batching costs in memory.** The batched model is a separate graph from live's batch-1 graph,
built on first use from a second load of the weights. Against task 3 (1.34 GB album footprint):
**+0.32 GB at N = 1** (the duplicated weights and the compiled executable), **+1.1 GB at N = 8**
(buffers and intermediates for eight windows). A shape-polymorphic single graph was not built: a
fixed batch with padding for the last group is simple, and the N table below prices the alternative
(at N = 1 the second graph costs 0.32 GB).

---

## 4. The N sweep

Release, full album, cold, quiet machine (`nsweep/nsweep.csv`):

| N (windows per model run) | album wall | sweep | sweep ms per audio-s | peak RSS | peak footprint |
|---|---|---|---|---|---|
| 1 | 143.3 s | 122.5 s | 52.6 | 1.27 GB | 1.66 GB |
| 2 | 107.3 s | 87.1 s | 37.4 | 1.34 GB | 1.75 GB |
| 4 | 82.2 s | 61.8 s | 26.5 | 1.41 GB | 1.91 GB |
| **8** | **71.0 s** | **50.6 s** | **21.7** | 1.49 GB | **2.45 GB** |
| 16 | 60.2 s | 39.9 s | 17.1 | 2.01 GB | 3.65 GB |

**N = 8 chosen.** Each doubling still helps: Open-Unmix's bidirectional LSTM walks 431 steps in
sequence whatever the batch, so more windows per run fill the GPU. N = 16 buys a further 15 % for
+1.2 GB, on a 16 GB machine that is rendering while the walk runs. Memory is what the next increment
needs for cross-track workers (`--concurrency 2` below already reaches 4.3 GB). N is
`SessionPreparer.sweepBatchSize`, so revisiting it is a one-constant change.

---

## 5. Parity against the goldens

**Goldens** (`UzumeEngine/Tests/Fixtures/prep3_goldens/`, gitignored): the full `StemFeatureSeries`
and the stems of sweep window 10, captured by `PrepTimingRunner --golden-capture` on unmodified
main. Three tracks: Breaking Glass (44.1 kHz FLAC, 113 s), *!!!* — Hammerhead (**48 kHz** AAC,
307 s), Warszawa (44.1 kHz, **384 s**). Re-running the capture code before any change reproduced them
bit for bit (`parity-0-determinism/`), so the sweep is deterministic and any difference is the change.

**Tolerance rule, pre-registered** (written into `PrepTimingRunner+Golden.swift`'s header before
the first comparison ran): a field passes when, on every frame, |new − golden| ≤ **1 % of that
field's median non-zero frame-to-frame change in the golden**. A field that never changes frame to
frame must match exactly.

| after | series | window stems | fields within tolerance |
|---|---|---|---|
| task 2 | **bit-identical** | **bit-identical** | 64 / 64 |
| task 3 | differs | max \|Δ\| 2.4e-7 (peak 0.96) | 64 / 64 |
| task 4 (N = 4, then N = 8) and task 5 | differs | max \|Δ\| 2.4e-7 (unchanged from task 3) | 64 / 64 |

All three tracks, every frame. **Worst observed difference per field** at the final configuration
(`parity-5-final-N8/parity.csv`, the eight closest to their tolerance):

| field | worst \|Δ\| | tolerance | share of tolerance |
|---|---|---|---|
| `bassCentroid` | 5.4e-7 | 2.0e-5 | 2.7 % |
| `drumsCentroid` | 5.4e-7 | 3.3e-5 | 1.6 % |
| `otherEnergySlope` | 1.6e-6 | 1.2e-4 | 1.3 % |
| `vocalsEnergySlope` | 1.9e-6 | 1.5e-4 | 1.3 % |
| `drumsEnergySlope` | 1.3e-6 | 1.1e-4 | 1.2 % |
| `vocalsCentroid` | 3.6e-7 | 3.1e-5 | 1.2 % |
| `otherCentroid` | 3.0e-7 | 2.7e-5 | 1.1 % |
| `otherBand1` | 7.5e-9 | 7.7e-7 | 1.0 % |

The 25 zero-step fields (beat fields, family activities, padding) match exactly. Batching the model
changed nothing on its own: the batched graph's output on the golden window is bit-identical to
batch 1. Every difference comes from task 3's mono inverse, which averages magnitudes before the
transform instead of averaging waveforms after it, so rounding differs.
`StemSeparatorReconstructTests` pins that path against the 8-transform one at ≤ 1e-6 of peak.

---

## 6. Live separation (batch 1) did not get slower

`PrepTimingRunner --bench-separate 60`: one call on 10 s of real audio, after a warm-up, alternated
build against build (`latency-task3/ab.txt`, `latency-final/ab.txt`). The "before" build is task 2's,
which has the separator as main had it.

| | before (median, two runs) | final (median, two runs) |
|---|---|---|
| **stereo — the live path** | 114.7 / 114.6 ms | **108.7 / 109.3 ms** |
| mono — the sweep's path | 112.7 / 112.6 ms | 101.7 / 102.8 ms |

Live separation keeps its batch-1 graph, buffers and call. It gained ~5 % from task 3's single
batched inverse run (8 transforms in one graph run, with sin/cos computed once per channel). Task 3's
mono shortcut does not apply live: live passes stereo. A live call and a prep batch hold the same
separator lock across their model sections. `liveBatch1AndPrepBatch_interleave_raceFree` requires
every interleaved result to equal the same call made alone, and it passes in the normal suite and
under TSan (`Scripts/tsan_stress.sh`: TSAN CLEAN).

---

## 7. Against D-242's two budgets

| | baseline | PREP.3 | budget |
|---|---|---|---|
| *Time to Start now* — *Low*'s first three tracks (measured) | 31.0 s | **11.3 s** | ≤ 300 s ✅ (already met at PREP.2) |
| *Time to Start now* — three 4-min tracks (projected) | 51.5 s | **18.1 s** | |
| *Fully prepared* — 40 × 4 min (projected, 0.0251 s per audio-s) | 686 s | **241 s** | ≤ 300 s ✅ **yes** |
| `--concurrency 2`, reference only (not shipped) | — | 41.4 s album (0.018 s/audio-s → 171 s for 40 × 4 min), footprint 4.3 GB | |

**Measured, not only projected: the 37-track task-7 playlist** (`PREP3/task7_live_37_tracks.m3u`:
Fever Ray, Portishead, *!!!*, *Blue Lines*; 189.6 min of audio, more than 40 × 4 min, two of the four
albums 48 kHz) **prepares in 276.0 s** headless (Release, cold, flat out; first three tracks ready at
18.3 s; peak footprint 2.9 GB; `PREP3/task7-headless-37/`).

**The 300 s question: yes**, on this machine, in Release, serial, without Option 2. The margin is
about 8 % on that playlist and 20 % on the 40 × 4 min projection. A slower machine or longer tracks
will eat into it. In the app, once the listener presses Start now, the walk deliberately paces at
2× realtime (PREP.2), so *fully prepared* during a playing session is set by pacing, not by this
speed. Task 7's live run is the real-world check.

---

## 8. What was not done, and what is next

- **Not done:** model precision, `hopSeconds`, window length and kept-span placement are unchanged.
  The beat grid, `BeatGridResolver`, `BeatActivationDecoder` and `DefaultBeatGridAnalyzer` compute
  exactly what they did; the only change near them is an `autoreleasepool` around Beat This!'s
  per-call body. **No behavioural change to beat sync.** Cross-track workers are not shipped. The
  Start-now threshold stays at three.
- **The next lever inside the sweep** is the CPU work still in series with the GPU inside each group:
  inverse STFT 9.8 s, STFT 2.8 s, readback 3.1 s, against a 38.5 s model run. Pipelining two groups
  (one in the model while the other runs its transforms) would leave the sweep close to model-bound,
  about 40 s instead of 55 s on this album.
- **Cross-track workers** (the next increment's question): two workers now take the album to 41.4 s at
  a 4.3 GB peak, with the memory question answered. Measure again with any change to N.
- **`pacingRate` 2.0** is still arithmetic. A faster walk changes the duty cycle behind it; tune it
  against a live frame-time measurement on the MacBook Pro (AUDIT.2 I13).

## 9. Reproducing this

```bash
swift build -c release --package-path UzumeEngine --product PrepTimingRunner
R=./UzumeEngine/.build/release/PrepTimingRunner
LOW="/Volumes/Extreme SSD/B/Bowie, David/[1977] - Low"

# album, with peak memory
UZUME_PREP_TIMING=1 /usr/bin/time -l $R --cache "$(mktemp -d)" --out docs/diagnostics/PREP3/<run> --folder "$LOW"
# N sweep / lookahead off / two workers
UZUME_PREP_TIMING=1 $R --sweep-batch 16 …   # or --no-prefetch, --concurrency 2
# goldens: capture on a reference build, compare on any later one (exit 1 on a tolerance miss)
$R --disable-probe --cache "$(mktemp -d)" --out /tmp/g --golden-capture UzumeEngine/Tests/Fixtures/prep3_goldens <files…>
$R --disable-probe --cache "$(mktemp -d)" --out docs/diagnostics/PREP3/<run> --golden-compare UzumeEngine/Tests/Fixtures/prep3_goldens
# separate() latency, stereo (live) and mono (sweep)
$R --disable-probe --cache "$(mktemp -d)" --out <dir> --bench-separate 60 "$LOW/02 - Breaking Glass.flac"
```
