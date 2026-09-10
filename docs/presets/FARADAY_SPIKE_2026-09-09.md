# Faraday spike — report

**Date:** 2026-09-09 · **Status:** spiked, four artifacts in hand, **not yet pitched.**
Working name: **Tacoma** (after the bridge — parametric resonance made visible). Suggestion only.

---

## The idea in one paragraph

A liquid film vibrated vertically goes unstable and stands up in waves — the Faraday
instability. Which waves appear is set by the *frequency content* of the shaking, because a
surface mode grows only when its natural frequency sits at half a drive frequency. So the
music does not brighten this preset or push it around: **it decides what geometry exists on
screen.** Louder crosses the instability threshold and the film erupts; the harmonic content
picks the symmetry. Rendered as a soap film — real thin-film interference — every ripple
becomes a saturated iridescent contour.

## What the spike establishes

**1. The amplitude channel works.** The drive amplitude walks the surface through three
distinct regimes with no tuning tricks: flat and quiescent below the instability threshold,
a clean cellular lattice just above it, and spatiotemporal chaos well above. That is a
three-state visual with a single physical knob, and the bottom state is a genuinely good
D-037 silence state — a calm iridescent film, not a black screen.

**2. The symmetry channel works — and this is the headline.** Two-frequency forcing is the
classic route to squares, hexagons, superlattices and quasipatterns (Edwards & Fauve 1994).
The spike confirms the *ratio* of the two drive tones visibly changes the pattern: 1:2 gives
parallel rolls, 4:5 gives stripes with a second finer scale superposed, 6:7 gives broken
domains, single-tone gives a square lattice. Six ratios, six distinguishable looks.

**3. The musical mapping — the interval between the two strongest pitch classes becomes the
drive ratio.** A fifth is 2:3, a fourth 3:4, a major third 4:5, a minor third 5:6. So the
*harmony* selects the geometry. Two feature designs failed before this one:

- *"The two strongest partials"* — always an octave apart, on every track. Those are
  harmonics, not harmony. 100% of frames landed on 1:2.
- *Chroma without exclusion* — the second-strongest pitch class is almost always adjacent to
  the strongest, which is binning leakage. 87–98% of frames landed in one bucket.

Excluding adjacent pitch classes fixed it, and the result validates against the material:
**"So What" — modal jazz built on stacked-fourths voicings — lands 40% on fourths and 56% on
major thirds. "There There" lands 39% on fifths, 35% on fourths.** The feature is reading
harmony, not noise.

**4. The look.** Thin-film interference, computed properly: two-beam reflectance integrated
against the CIE 1931 colour matching functions and tabulated against optical path difference.
In a shader that is a **single 1D texture fetch indexed by OPD** — the standard iridescence
technique, and Uzume already has thin-film machinery from Ferrofluid. Two earlier looks were
thrown away: a refraction/caustic render that came out monochrome blue, and a first
interference attempt that came out sepia because the slope normalisation was crushing the
view-angle term and collapsing the OPD spread.

## CORRECTION — there is no scale ratchet (2026-09-09, same day)

**An earlier revision of this document reported that the pattern scale "ratchets finer and
never comes back." That was wrong, and it was wrong because I measured the wrong quantity.**

I reported *mean* wavenumber, which rose 11.3 -> 16.7 over the run. Re-measuring the
**dominant** wavenumber — the peak of the radial power spectrum — gives this:

| frame | drive | interval | **peak k** | mean k | power above k=25 |
|---|---|---|---|---|---|
| 20 | 0.33 | septimal 6:7 | **16.0** | 11.4 | 2.3% |
| 80 | 0.46 | fourth 3:4 | **16.0** | 13.5 | 3.0% |
| 140 | 0.29 | fourth 3:4 | **16.0** | 15.9 | 3.2% |
| 220 | 0.26 | maj third 4:5 | **16.0** | 16.7 | 3.9% |

**The dominant scale is pinned at k = 16.0 for the entire run and never moves.** Power above
k=25 stays flat at 2–4%. The mean rose only because the broad low-k launch transient decayed
away while the pattern locked onto its true resonant wavenumber — a moving mean over a
narrowing distribution, not a drift in the pattern. Mean wavenumber is a bad metric for this
system and should not be used again; **report peak k and an orientational order parameter.**

## The real failure — the pattern anneals into single-domain rolls

What actually goes wrong in the late frames is different and more tractable. Two things:

1. **k0 = 16 is too fine for composition.** Sixteen wavelengths across the frame reads as
   texture. The early frames that look good are the ones where the launch transient still has
   low-k content in it. The frame wants roughly 6–9 wavelengths. This is a parameter, not a
   problem.
2. **The pattern orders.** Over ~40 s the cellular, polycrystalline state anneals — defects
   annihilate, one roll orientation wins, and the frame ends as parallel stripes. That is
   ordinary pattern-forming behaviour and it is the same family as the Alfven condensate:
   left alone, the system relaxes toward a boring ordered attractor.

Neither is established as fatal. Both are the subject of the next pass.

## Diagnostic pass — results (2026-09-09)

Metrics were defined before the runs this time. **PEAK_K** = peak of the radial power spectrum
of the envelope field; because the envelope of a standing wave `cos(kx)cos(wt)` is `|cos(kx)|`,
PEAK_K is exactly the number of visible wavelengths across the frame, and it is `2 * k0`.
**S** = nematic order in the dominant shell, `|sum P e^{2i.theta}| / sum P`. S ~ 0 is
polycrystalline and cellular; S -> 1 is one roll orientation winning. Rising S *is* the annealing.

**Q1 — does a coarser k0 restore composition? YES, decisively.**

| k0 | PEAK_K (wavelengths across frame) |
|---|---|
| 2.5 | 5 |
| 3.0 | **6** |
| 6.0 | 12 |
| 8.0 | 15 |

The shipped film ran at k0 = 8, i.e. sixteen wavelengths — which is why it read as texture.
**k0 = 3 is the setting**, and the visual difference is not subtle: large iridescent cells with
real composition instead of fine stripe fabric.

**Q2 — does it anneal, and do the symmetry switches reset it?** It anneals; the switches do
**not** reset it. S over an identical long run:

| condition | S trajectory |
|---|---|
| fixed symmetry | 0.03 → 0.55 |
| switching symmetry | 0.03 → 0.60 |
| switching + large-scale perturbation | 0.03 → 0.61 |

The three curves are within noise of each other. **The symmetry channel changes the pattern's
fine structure but not its orientation, so it contributes no disorder** — an assumption in the
original design that turns out to be false.

**Q3 — does a different regime help? No.** Drive amplitude is irrelevant to annealing:
S reaches 0.41 / 0.47 / 0.46 at amp 0.42 / 0.58 / 0.70. Neither perturbation nor extra drive
is a fix.

**But at the corrected scale the annealing is slow and non-monotonic.** At k0 = 3, N = 256, S
wanders 0.26 → 0.08 → 0.04 → 0.20 → 0.38 across a long run rather than marching to 1, and the
picture stays cellular and good through nearly all of it. At N = 192 the same parameters
annealed harder (to 0.55). **The annealing rate is resolution-dependent and not tightly
determined** — that is an honest gap, not a solved problem.

### Verdict

Faraday clears the diagnostic. Composition is fixed by one parameter. Annealing is real but at
k0 = 3 it is slow enough to live with, and the standing remedy if a long session drifts is the
Alfven re-seed — now a known, reusable pattern rather than new invention. **The concept is
ready for the three-part bar.**

## Four bugs the spike caught that would have cost days in Metal

1. **A bare `-λh³` nonlinearity diverges the moment the bass hits.** Measured: NaN at frame 70
   on the first audio-driven run. Fixed with a saturating force `-λh³/(1+(h/h_max)²)` plus a
   soft global RMS limiter. Physically right too — a real film cannot deform without bound.
2. **Recomputing the drive phase from absolute time kills the pattern on every symmetry
   change.** When the ratio switches, `cos(p·w·t)` steps discontinuously, the parametric
   resonance dephases, and the field decays: measured `hrms` 0.53 → 0.03 across one switch.
   The drive phases must be **integrated**, so a ratio change alters the drive's *rate* and
   never its phase. This is the single most important finding in the spike — the headline
   feature is symmetry switching, and the naive implementation makes symmetry switching
   destroy the picture.
3. **Once the total forcing exceeds 1 the restoring force inverts and the field scrambles to
   noise.** With `mix = 0.28` the two tones sum to `1.33 × amp`, so any drive above ~0.75 sends
   `(1 + F)` negative for part of the cycle; measured as whole frames of RGB static at the loud
   moments. The audio-to-drive map must be capped, not merely scaled.
4. **Equal-weight two-tone forcing beats, and the pattern dies at the envelope nulls.** With
   `mix = 0.5` the drive periodically cancels and the surface collapses between beats. The
   second tone must be a *perturbation* (mix ≈ 0.28), which is also how Edwards–Fauve works:
   a weak second frequency selects the pattern, it does not co-drive it.

## Audio routing (one primitive per layer, FA #67)

| Visual layer | Primitive | Kind | Timescale |
|---|---|---|---|
| **Pattern symmetry** — the whole field re-orders | chroma interval (two strongest pitch classes) | `structural` | seconds, with dwell |
| Instability threshold — flat ↔ patterned ↔ chaotic | `bassRel` | `continuous` | ~100 ms |
| Specular glint gain | `trebRel` | `continuous` | ~30 ms |
| Film thickness → interference colour centre | spectral centroid | `continuous` | seconds |

The symmetry channel needs **dwell hysteresis** — a minimum hold before committing and a
minimum gap between changes — or it flickers between geometries and reads as strobe rather
than as harmony. The spike uses 1.5 s to commit and 4 s between changes.

## Pushing Apple Silicon — where the headroom actually is

The spike is pseudo-spectral because the gravity-capillary dispersion `ω² = gk + σk³` is not a
local operator. Two honest routes on the GPU:

- **A Metal compute FFT** (Stockham autosort, 256²–1024²). This is real new engine capability
  and it would also unlock a spectral Alfvén, which is sharper than the projection version.
  Bigger lift, bigger payoff, and reusable.
- **The weakly-nonlinear local reduction** (Zhang–Viñals / parametrically-driven
  Swift–Hohenberg): expand the dispersion about the resonant band and you get biharmonic
  stencils only — no FFT, tile-memory resident, trivially fast. The cost is that only one
  band is resonant, which flattens the "different frequencies excite different scales" idea.

**The version that genuinely works the hardware — and it is the better preset, not just the
heavier one — is a bank of coupled films.** Three or four surface fields, each tuned to a
different resonant wavenumber, each parametrically driven by its own audio band: bass raises
large slow cells, mids a medium lattice, treble a fine glittering ripple, all superposed on
one film and competing nonlinearly. That is several 512² fields advanced per frame at 60 fps
with fp16 storage and fp32 accumulation, stencil passes kept in tile memory, one iridescence
LUT fetch at composite. It is also the most audio-legible version of the concept: you would
*see* the spectrum as spatial scale.

**Caveat: I have measured none of this on a Mac.** The numbers above are a plan, not a result.

## Feasibility against the roster

- **No Poisson solve.** Faraday is fully explicit — it does **not** depend on ALFVEN.1 and
  could be built in parallel or first.
- Needs the same `persistent` staged-stage surface (two state fields: `h` and `ḣ`).
- `rubric_profile: lightweight`, same argument as Alfvén — a 2D field preset.
- **Overlap with Cymatic Resonance is yours to rule on.** My read: Chladni is linear standing
  modes on a plate with static nodal lines; Faraday is a nonlinear parametric instability that
  selects among competing symmetries and never repeats. Different mechanism, different motion,
  different musical role. But you own that call.

## What I still do not know

- **How fast the annealing actually runs at shipping resolution.** It is resolution-dependent
  (N=192 annealed to S=0.55, N=256 wandered around 0.2) and that difference is unexplained.
  Measure S on the real GPU path before deciding whether the re-seed is needed at all.
- Whether the symmetry switches are **legible as musical events** to a casual viewer. Now known
  not to disturb the pattern's orientation, which may make them subtler than intended.
- Whether the symmetry changes are **legible as musical events** to someone watching casually,
  or read as the picture simply reorganising for no reason. That is a live-eye judgment.
- Whether a GPU explicit integrator at 60 fps hits the same regimes at a workable timestep.
