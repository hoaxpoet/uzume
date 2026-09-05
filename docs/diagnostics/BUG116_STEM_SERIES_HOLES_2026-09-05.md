# BUG-116 — the stem series is dead 0.4 s in every 2 s, and the cause is a sample rate

**Date:** 2026-09-05 · **Reported by:** Matt, mid-session — *"Now there are issues with Ferrofluid
Ocean - screen goes dark every few seconds."* · **Session:** `2026-09-05T18-17-12Z`

---

## 1. It is not the renderer, and it is not today's merges

Two things worth ruling out before anything else, because both were plausible.

**The renderer is presenting every frame.** `DRAWABLE_LIFECYCLE` heartbeats across the whole
Ferrofluid Ocean window report `failures=0 unpresented=0`, with `unique_presented` tracking
`frames` exactly. Nothing is being dropped; the darkness is in the content.

**Nothing that shipped today touches this path.** `SessionPreparer+StemSeries.swift` was last
modified at RN.2 — a rename. PR.17 changed `BeatGrid.downbeats`; PR.5 changed the mv_warp blit's
invert. Neither is upstream of stems.

`CHAIN_HEALTH: verdict=clean` — the audio chain was healthy, so this is a real signal defect and not
a degraded capture (D-184).

---

## 2. What the session shows

All four stems — `drums`, `bass`, `vocals`, `other` — decay smoothly to **exactly 0.000** and snap
back, **68 times**, **2.00 s ± 0.03** apart, each lasting **~0.37 s**.

```
t=61.26  drums 0.126  bass 0.144  vocals 0.225  other 0.219
t=61.41  drums 0.022  bass 0.023  vocals 0.050  other 0.047
t=61.56  drums 0.004  bass 0.004  vocals 0.012  other 0.011
t=61.86  drums 0.000  bass 0.000  vocals 0.001  other 0.001
t=61.96  drums 0.032  bass 0.035  vocals 0.091  other 0.080   ← snap back
```

Four independently separated stems do not fall together on an exponential and recover in lockstep
because of anything musical. And `stem_series_pos_s` advances smoothly the whole way — the playback
clock is right, so the series is being read at the correct position and the data there is empty.

**The holes are on disk.** Reading `stem_series.bin` straight out of the persistent cache for that
track finds 60 near-zero spans at the same cadence. This is an offline analysis artifact, not a
playback race.

---

## 3. Root cause

`StemSeparator.separate(audio:channelCount:sampleRate:)` resamples any input to its own
`modelSampleRate` (44,100) and then pads-or-truncates to exactly `requiredMonoSamples` (440,320).
**Its output is always in the model's time base.**

`SessionPreparer.analyzeStemSeries` slices that output at offsets computed in the **input's** rate:

```swift
let offset = absolute - windowStart                            // input-rate samples
let slice  = stems.map { Array($0[offset..<(offset + hop)]) }  // model-rate samples
```

At 48 kHz those two disagree. A 440,320-sample input window is 9.17 s of audio; resampled to
44.1 kHz it occupies 404,544 samples, and the remaining **35,776 samples are zero padding**. The
function deliberately places each kept 2 s span at the very END of the separation window — one
analysis frame of room, no more — so the span lands squarely in the padding.

That placement is not a mistake in itself; it is what keeps each span's frames maximally
context-fed. It just makes the rate mismatch maximally damaging.

---

## 4. The A/B — one variable

`UZUME_STEM_SERIES_PROBE=1 UZUME_STEM_SERIES_RATE=<rate> UZUME_STEM_TAIL_AUDIO=<file> swift test --filter StemWindowTailProbe`

| input rate | near-zero frames | holes |
|---|---:|---|
| **44,100** | **0 of 1722** | none |
| **48,000** | **279 of 1875 (14.9 %)** | 9.62–10.01 s, 11.63–12.01 s, 13.65–14.02 s, 15.66–16.00 s, … |

The 48 kHz run reproduces the cached series that fed Matt's session **frame for frame** — 451–469,
545–563, 639–657, 734–750, 826–844, 921–938.

**Why this was never caught:** every committed fixture is 44.1 kHz, which is the one rate at which
the bug cannot occur. The tap on this machine reports 48,000.

---

## 5. A hypothesis falsified on the way

The first suspect was the separator's own window edge — a model attenuating its output near the
boundary would produce exactly this shape. It does not. Per-100 ms RMS across a full window:

| stem | tail / mid |
|---|---:|
| drums | 0.784 |
| bass | 0.757 |
| vocals | 0.632 |
| other | 0.784 |

The input's own envelope falls by about the same ratio over that stretch, so the model is tracking
the music, not fading. Recorded because it is the difference between fixing the separator (wrong)
and fixing the offset arithmetic (right).

---

## 6. What a fix has to do

**The cached entries are poisoned.** The holes are baked into `stem_series.bin`. A code fix alone
leaves every already-analysed track broken, so the fix must invalidate or version the persistent
stem cache.

**Verification criteria, written before the fix:**

1. `analyzeStemSeries` at 48 kHz produces zero near-zero frames on real audio, and its frame count
   and `hopSeconds` still map correctly to playback seconds. **Rate-parameterised** — a 44.1 kHz-only
   test cannot see this defect, which is precisely how it shipped.
2. A poisoned cache entry is not reused after the fix.
3. **Manual:** Matt watches Ferrofluid Ocean on a 48 kHz local file and the periodic darkening is gone.
