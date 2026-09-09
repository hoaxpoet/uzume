# Faraday — Design

**Status:** design locked 2026-09-09. Spiked (`FARADAY_SPIKE_2026-09-09.md`) and through the
diagnostic pass. Implementation not started.
**Family:** hypnotic · **Rubric:** lightweight · **Paradigm:** compute solver (spectral)
**Working name:** **Tacoma**, after the bridge — parametric resonance made visible. ASCII
identifier `tacoma`; the file is `Tacoma.metal`, the solver `TacomaSolver`. Suggestion only;
"Faraday" is the physics, not necessarily the preset name.

Companion: `FARADAY_SPIKE_2026-09-09.md` — the spike, the four bugs, the corrected metric, and
the diagnostic results. Visual references: `docs/VISUAL_REFERENCES/faraday/README.md`.

---

## 1. What it is

A liquid film vibrated vertically. Above a threshold the flat surface goes unstable and stands
up in waves — the Faraday instability. **Which** waves appear is decided by the frequency
content of the shaking, because a surface mode grows only when its natural frequency sits at
half a drive frequency. So the music does not brighten this preset or push it around: it
decides what geometry is on screen. Rendered as a soap film, so every ripple is a saturated
iridescent contour.

## 2. Musical role (Part 2 gate — one sentence)

> **The interval between the track's two strongest pitch classes sets the ratio of the two
> drive frequencies, and that ratio selects the symmetry of the pattern — so when the harmony
> moves, the geometry on screen re-orders — while the bass envelope decides whether the film
> is below the instability threshold and glassy, or above it and erupting.**

Two-frequency forcing is the classic route to squares, hexagons, superlattices and
quasipatterns (Edwards & Fauve 1994). Mapping the ratio to a musical interval in just
intonation — a fifth is 2:3, a fourth 3:4, a major third 4:5, a minor third 5:6 — is what makes
the harmony legible as geometry. Measured against the fixture set: "So What", built on stacked
fourths, lands 40% on fourths; "There There" lands 39% on fifths.

## 3. Temporal contract

| Horizon | What happens |
|---|---|
| ~30 ms | Specular glints flare with treble transients |
| ~100 ms | Wave amplitude rises and falls with the bass envelope; below threshold the film goes glassy |
| seconds | Film thickness drifts with spectral centroid — the whole interference palette shifts |
| **seconds, held (the cycle)** | **A harmonic change re-symmetrises the pattern: the cells re-order into a new lattice** |
| tens of seconds | The field dissolves and re-braids when the order parameter says the pattern has gone stale (§5) — brought forward to a section boundary where one is available |

## 4. Physics

Each Fourier mode of the surface height obeys a damped Mathieu equation:

```
h_k'' + 2 gamma_k h_k' + omega_k^2 (1 + F(t)) h_k = NL_k
omega_k^2 = g k + sigma k^3            gravity-capillary dispersion
gamma_k   = nu k^2                     viscous damping
F(t)      = A [ a cos(phi_1) + b cos(phi_2) ],  phi_i integrated, never recomputed (§8.2)
NL        = -lambda h^3 / (1 + (h/h_max)^2)     saturating (§8.1)
```

**Render the envelope, not the height.** A subharmonic Faraday wave oscillates at `omega/2` and
so passes through flat twice per cycle; rendering instantaneous height strobes to nothing. The
eye at a real drive frequency sees the amplitude. So does this preset:

```
A = sqrt(h^2 + (h_dot / omega_sub)^2)
```

**The envelope's spatial frequency is `2 * k0`.** Because the envelope of `cos(kx)cos(wt)` is
`|cos(kx)|`. So `k0` is half the number of visible wavelengths across the frame. **`k0 = 3`**
gives six, which is the composition target. The spike's first film ran at `k0 = 8` — sixteen
wavelengths — which is why it read as fabric.

## 5. Orientational ordering — and the re-seed that answers it

Left alone the polycrystalline cellular state anneals: defects annihilate, one roll orientation
wins, and the frame becomes parallel stripes. The metric is the nematic order parameter in the
dominant shell, `S = |sum P e^{2i.theta}| / sum P`, and **it tracks the look almost exactly** —
S = 0.05 is rich cellular, S = 0.36 is visibly aligning, S > 0.8 is pure diagonal stripes.

Three mitigations were tested and **all three failed.** Symmetry switching (0.03 → 0.60 against
0.03 → 0.55 for fixed — within noise), a slow large-scale perturbation (→ 0.61), and higher
drive (0.41 / 0.47 / 0.46 at amp 0.42 / 0.58 / 0.70). **The symmetry channel changes fine
structure but not orientation, so it injects no disorder** — an assumption in the original
concept that turned out to be false.

Over a full-length audio-driven run at `k0 = 3`, N = 256, **S climbs monotonically to 0.99**.
An earlier reading of "slow and non-monotonic" came from runs that were simply too short. So:

> **The re-seed is required, not held in reserve.** Without it the preset is beautiful for
> about the first third of a track and wallpaper thereafter.

**But unlike Alfvén's, this re-seed is closed-loop.** `S` is a cheap reduction over a spectrum
the solver already computes, so the preset can re-seed *when the picture is measurably going
stale* rather than on a fixed clock. Measured with a trigger at S > 0.32 and a minimum gap: the
run re-seeds twice and S is held in the 0.3–0.5 band instead of reaching 0.99. That is a better
mechanism than a timer and it is the one to ship — a section boundary should be allowed to
*bring the re-seed forward* so it lands musically, with S as the backstop that guarantees it
happens at all.

`S` ships as a standing diagnostic, not a one-off measurement.

## 6. Why this is a better fit for the compute solver than Alfvén was

ALFVEN.2 measured that real-time MHD is out of reach on the fragment path: stable only at
`dt ~ 5e-4`, 33 substeps at ~137 passes each, and Heun provably cannot rescue it because
`|R(iy)| > 1` on the imaginary axis. Faraday does not inherit any of that:

| | Alfvén | Faraday |
|---|---|---|
| Advection | yes — CFL tightens as the cascade energises (`u k dt`: 0.10 → 2.56) | **none** |
| Stiffness | field-dependent, must be measured each frame | **fixed**: `omega_k` is known ahead of time |
| Adaptive dt | required → needs a mid-frame global reduction | **not required** |
| Poisson solve | every substep | **none** |
| Linear part | Alfvén waves, imaginary axis, no cheap exact solution | **a damped oscillator — exact propagator per mode** |
| Per substep | ~137 passes | inverse FFT → cubic → forward FFT → propagator ≈ **2 FFTs** |

The entire linear operator has a closed-form propagator (rotation plus damping, per mode), so
only the parametric coefficient and the cubic need explicit treatment, and the drive period —
not the grid — sets the timestep. **Estimate, unmeasured on hardware:** the spike ran plain
explicit Euler at `dt = 0.008`; with the exact propagator the limit becomes resolving the
drive, so order 20–40 substeps per frame at roughly 8 dispatches each. That is a comparable
substep count to Alfvén at a small fraction of the per-substep cost. It must be measured, not
assumed — this is the same class of claim that ALFVEN.2 falsified.

## 7. Engine surface required

**Nothing new.** ALFVEN.4 built the expensive piece: a threadgroup-memory compute FFT
(`alfven_fft_rows` / `alfven_fft_cols`), gated on round-trip (8.9e-07) and Parseval
(1.000000), forward + inverse 2D in four dispatches. Alongside it are `alfven_houli`,
`alfven_efactor` and `alfven_dealias`, all of which are generic spectral operations wearing an
Alfvén prefix, plus a Swift substep spine (`AlfvenSolver+Ops`: `encode` / `fft` / `spectral` /
`finalize` / `copy`).

**What Faraday needs is that spine extracted, not rebuilt** (FA #73). The Alfvén-specific parts
— `grad_spectrum`, `brackets`, `j_spectrum`, `cfl_reduce`/`cfl_finish` — stay behind; Faraday
uses none of them, including the CFL reduction. A branch `claude/alfven-1c-fft` already appears
to be doing part of this split, and **the extraction increment must start by reading it rather
than duplicating it.**

## 8. Stability — four measured requirements, not preferences

Each of these was a real failure in the spike, with a measurement:

1. **Saturating nonlinearity.** A bare `-lambda h^3` diverged to NaN on the first bass hit
   (frame 70). Use `-lambda h^3 / (1 + (h/h_max)^2)` plus a soft global RMS limiter.
2. **Integrated drive phase.** Recomputing `cos(p w t)` from absolute time after a ratio change
   steps the phase, dephases the parametric resonance and kills the pattern outright — measured
   `hrms` 0.53 → 0.03 across one switch. **The headline feature is symmetry switching, and the
   naive implementation makes symmetry switching destroy the picture.** Integrate `phi_1`,
   `phi_2`; a ratio change alters the rate, never the phase.
3. **Cap the total forcing below 1.** With `mix = 0.28` the two tones sum to `1.33 A`, so any
   drive above ~0.75 sends `(1 + F)` negative for part of the cycle, the restoring force
   inverts, and whole frames become RGB static. Cap, do not scale.
4. **The second tone is a perturbation, not a co-drive.** At `mix = 0.5` the drive beats and the
   surface dies at the envelope nulls. `mix ≈ 0.28`. This is also how Edwards–Fauve works.

Plus the standard guards: non-finite watchdog with a silent re-seed, and hard clamps.

## 9. Audio routing (one primitive per layer — FA #67)

| Visual layer | Primitive | Kind | Timescale |
|---|---|---|---|
| **Pattern symmetry** — the lattice re-orders | chroma interval (two strongest pitch classes, adjacent excluded) | `structural` | seconds, with dwell |
| Instability threshold — glassy ↔ cellular ↔ chaotic | `bassRel` | `continuous` | ~100 ms |
| Specular glint gain | `trebRel` | `continuous` | ~30 ms |
| Film thickness → interference colour centre | spectral centroid | `continuous` | seconds |

The symmetry channel needs **dwell hysteresis** — the spike uses 1.5 s to commit and 4 s
between changes — or it flickers between geometries and reads as strobe. Note from §5 that the
switch does *not* disturb orientation, so it may read subtler live than the ratio sheet implies;
that is an M7 question.

**Silence (D-037):** below threshold the film is glassy and slow-drifting, still fully
coloured by interference. Never black.

## 10. The look

Thin-film interference computed properly: two-beam reflectance integrated against the CIE 1931
colour matching functions and tabulated against optical path difference. **In the shader this
is one 1D texture fetch indexed by OPD** — the standard iridescence technique, and Uzume
already has thin-film machinery from Ferrofluid (D-124).

Working values from the spike: base thickness 420 nm, swing 240 nm, `OPD = 2 n d cos(theta)`
with `n = 1.34`. Two things that killed the colour and must not recur: normalising the slope
field by the height's scale (it crushes `cos(theta)` and collapses the OPD spread to a single
hue), and letting the OPD sweep past ~1400 nm (high fringe orders desaturate to grey).

## 11. Increment plan

| ID | Type | Scope | Gate |
|---|---|---|---|
| **FARADAY.1** | infrastructure | Extract the generic spectral spine out of `AlfvenSolver` into a shared core; re-point Alfvén at it. **No Faraday.** | Alfvén's existing gates stay green: FFT round-trip + Parseval, `AlfvenSolverTests`, dHash goldens |
| **FARADAY.2** | preset | `TacomaSolver` + `Tacoma.metal` + sidecar; exact propagator, the §8 guards, silence state, **and the closed-loop re-seed** — it is load-bearing, not a later polish. **No audio routing.** | Still sheet + motion gate against the reference set; `S` reported per frame and shown to stay below ~0.5 over a full-length soak |
| **FARADAY.3** | preset | Audio routing per §9, `audio_routes` manifest, dwell hysteresis | `RouteCoverageTests` green; M7 |

## 12. Grounding levels

| Mechanism | Level | Note |
|---|---|---|
| Compute FFT + spectral spine | **1 — working code in this repo** | ALFVEN.4, gated |
| Faraday / damped Mathieu physics | **1 — a working spike** | `docs/presets/faraday_spike/`, plus Edwards & Fauve for the two-frequency route |
| Exact propagator for the linear part | **2 — standard method, not yet applied here** | Textbook; the spike used explicit Euler |
| Chroma-interval → drive ratio | **2 — validated on two fixtures only** | Two tracks is not a genre sweep |
| Closed-loop re-seed on `S` | **1 — measured in the spike** | Holds S in 0.3–0.5 against 0.99 unmitigated |
| **Real-time at 60 fps** | **3 — estimate only** | §6. ALFVEN.2 falsified exactly this class of claim for MHD. Measure before believing |
