# Dragon Bloom — the feedback field is fine; the defect is in the comp

**Date:** 2026-09-08 · **Matt:** *"rebuild the port properly against the oracle"*, then *"proceed to dragon bloom"*

---

## The premise behind two days of failed attempts was false

Eleven hypotheses were tried against this preset, all resting on one assumption: **the feedback
field never fills**, so `bInvert` turns empty accumulator into white. Every one of them died.

The assumption was never measured. It was inferred from the DISPLAY — 84 % of pixels clipped, mostly
white — by reasoning backwards through the comp stage. The accumulator itself is `.private` storage,
so nothing could read it, and nobody tried.

`HARNESS_DUMP_ACCUMULATOR=1` blits the warp texture to the readable output and reads it directly.

| | our **accumulator** | oracle (final image) |
|---|---:|---:|
| clipped | 0.117 | 0.000 |
| saturation | 0.634 | 0.947 |
| mean luma | **0.294** | **0.307** |
| near-empty | 0.002 | 0.000 |

**The field is full, textured and stable.** Luma within 0.02 of the oracle's. Essentially nothing
near-black. The fine ripple structure visible in the dump is the warp field working.

And it converges — luma 0.11 → 0.34 by frame 90, then holds 0.28–0.32 for the remaining 800 frames,
saturation 0.61–0.74. No runaway, no starvation, no slow decay.

**PR.5's first measurement said this on day one** — *"the accumulator is not blown. It is dark and
richly saturated (0.655)"* — and today's figure is 0.634. That was correct, and everything since
re-derived past it.

---

## What that leaves

A field at luma **0.30** becomes a display at luma **0.91** with **84 %** of pixels clipped. The
transformation between them is four lines in `mvWarp_blit_fragment`:

```
ret = mix(base, echo, 0.5)      // video echo, horizontal mirror
ret *= 1.07                     // gamma
ret = 1.0 - ret                 // bInvert
ret *= (1.0 + 0.12 * beat)      // beat brighten
```

Something there blows out a good field. That is a four-line search with the field measured on both
sides of it, rather than a search across the whole preset.

---

## Why this took so long, recorded so it does not repeat

Every attempt compared FINAL IMAGES and then guessed which side of the comp was wrong. The comp is
not invertible by eye — the echo mixes in a mirrored copy — so no amount of looking at the output
could separate "the field is wrong" from "the comp is wrong". The instrument to tell them apart is
three lines (a blit) and did not exist until now.

The same shape of error runs through this whole week: BeatBench compared arms over different spans,
`drift_ms` was read as error when it is the correction, and here the field was inferred through a
stage that could not be inverted. In each case the measurement was of something adjacent to the
question.

---

## Next

Put the oracle's accumulator beside ours with the comp disabled on both — `invert=0, echo_alpha=0,
gammaadj=1` in the oracle's `baseVals`, which `__loadVariant` in the harness already supports. Two
measured fields, not one measured image and one inference.
