# Concept — "Alfvén": a magnetohydrodynamics preset

**Date:** 2026-09-08
**Gate:** `preset-concept` (four artifacts) → then `PRESET_SESSION_CHECKLIST.md` Part 2 three-part bar.
**Status:** artifacts 1–4 produced. **Not yet cleared for build** — three open questions for Matt at the end.
**Ask that produced this:** "a new preset based on equations from magnetohydrodynamics… unequivocally psychedelic and perfect for stoners to space out."

---

## The point of view, in one paragraph

MHD is not a texture idea, it is a *motion* idea, and the motion it produces has a specific
name in the visual record: the **1960s liquid light show** — the oil-and-water wheel projected
behind a band. That is not an analogy I reached for; it is what the equations render when you
plot the right field. Two immiscible-looking regions of opposite magnetic polarity shear past
each other, the boundary between them thins into a bright seam, the seam snaps, and the regions
re-braid. That cycle is what magnetic reconnection *is*, and it is also exactly the oil-wheel
gesture. The preset should therefore not be a "plasma" preset (we already have one, uncertified,
lightweight, sine-interference — `Plasma.json`) and not a scientific visualisation. It should be
the oil wheel, with real MHD underneath instead of a sine hack, driven so that it never resets
and never repeats. **Recommendation: build it. Render the current density, not the density.**

---

## Artifact 1 — the watched moving source

**Philip Mocz, *Create Your Own Constrained Transport Magnetohydrodynamics Simulation (With Python)* (2023)** —
[`pmocz/constrainedtransport-python`](https://github.com/pmocz/constrainedtransport-python), a finite-volume
constrained-transport solver of the **Orszag–Tang vortex**, the canonical 2D MHD test problem
(Orszag & Tang 1979; the CT scheme is Evans & Hawley 1988).

I ran it locally at N=256 to t=1.0 and watched 50 frames — I did not take its word or a still.

**LICENSE GATE: the repo is GPL-3. Nothing from it may be ported into Uzume (MIT).** It was used
to *watch*, which is what artifact 1 asks for. The scheme itself is textbook and re-derivable;
if any solver code is adopted, take it from a BSD/MIT source (Athena++ is BSD-3) or write it
from the published equations.

Shadertoy was unreachable from this session (Cloudflare bot check on the desktop browser; the
cloud container's egress policy blocks the domain), so I could **not** confirm whether a
real-time GPU MHD shader exists to port. That is a genuine gap — see Open question 3.

## Artifact 2 — the look verified across the sequence, not from one frame

Watching all 50 frames rather than the thumbnail changed the concept twice:

1. **The density field is the wrong field.** `rho` gives bold structure only between t≈0.16 and
   t≈0.30 and is a low-contrast noise wash by t=0.72. **`|J| = |∇²ψ|`, the current density, is the
   picture** — silky filamentary sheets, satin folds, bright ribbons on black. Holds far longer.
2. **Orszag–Tang is a *decaying* problem.** It has a beginning, a middle and a heat death. A
   visualiser preset loops indefinitely. Any concept that ports OT straight is dead on arrival
   after ~30 s. This is the same class of failure as Truchet Loom (D-194): a curated still hid a
   temporal reality.

## Artifact 3 — the three-sentence story (each sentence checkable)

- **See** — A full-screen field of marbled liquid: broad lobes of two opposed colours, separated
  by thin white-hot seams. *Checkable against the look-spike frames f41–f48.*
- **Move** — Over ~30 s the lobes stretch, fold and shear past one another; where two lobes press
  together the seam between them thins into a bright filament, snaps, and the lobes re-braid into
  an arrangement that has not occurred before — continuously, with no reset. *Checkable: the
  motion gate over 91 frames returns 0 spikes >3× median and 0 frozen frames, and no frame
  recurs.*
- **Music** — The bass envelope (`bassDev`) sets how hard the field is stirred, so seam density
  tracks the low end: quiet passages relax to two or three broad slow lobes, dense passages fill
  the frame with braided filaments. *Checkable: per-route firing evidence from `features.csv` plus
  frame extracts at the bass events, per QG.1.*

## Artifact 4 — the running look-spike, motion-gated

A CPU stand-in for the eventual GPU sim: **driven 2D incompressible MHD in vorticity /
flux-function (reduced-MHD) form**, pseudo-spectral, 2/3 dealiasing, integrating-factor RK2,
hyperdiffusion — the standard formulation (Biskamp, *Magnetohydrodynamic Turbulence*, ch. 7).

```
omega = lap(phi),  u = (-phi_y,  phi_x)          psi = flux fn,  B = (-psi_y, psi_x),  J = lap(psi)
d_t omega = -{phi,omega} + {psi,J} - nu4 k^4 omega + f
d_t psi   = -{phi,psi}              - eta4 k^4 psi
```

Two spikes were **killed before the third worked**, and the kills are the load-bearing part of
this document:

| # | Configuration | Result | Verdict |
|---|---|---|---|
| 1 | Driven, forcing on 6 fixed integer modes | Locks onto the forcing lattice (visible bars); then collapses to grid-scale speckle | **Killed** |
| 2 | Unforced decay from the Orszag–Tang braid | Beautiful f3–f45, then numerical ringing and hash; the symmetric IC reads as wallpaper | **Killed** |
| 3 | Asymmetric random large-scale IC; forcing on the k=1–2 shell with slowly-redrawn random phases; strong hyperviscosity + large-scale drag | Holds the look across the full 91-frame run; energy saturates (J rms 2.5 → 2.0, flat) | **Passes** |

**Motion gate on spike 3** (91 frames, the `Scripts/motion_gate.sh` signal computed the same way):

```
mode D:  90 inter-frame diffs   mean 6.95   stdev 0.83   median 7.04   max 8.92
         spikes >3x median: 0     frozen (~0): 0
mode F:  90 inter-frame diffs   mean 6.23   stdev 0.88   median 6.24   max 7.88
         spikes >3x median: 0     frozen (~0): 0
```

Read as a sequence (frames 41–48 consecutive, not sampled): continuous advection, no pop, no
strobe, no freeze. **Motion verdict: smooth, on-concept, and — unlike the reference — sustained.**

Three palettes were rendered against the same simulation. **Recommendation: mode D.** Opponent
hue on current-sheet polarity, luminance on `|J|` through a filmic curve, saturation falling
toward white at the seam cores so the filaments read as *hot* rather than merely bright. Mode F
(warm sheets over a cool ground) is prettier and calmer; it is the safer choice and the less
psychedelic one. The ask was "unequivocally psychedelic", so D.

---

## Against the three-part bar (`PRESET_SESSION_CHECKLIST.md` Part 2)

**1. Iconic visual subject deliverable at fidelity — QUALIFIED PASS.** The subject is a 2D field,
not a rendered object, so the historical fidelity gaps (Arachne's spider, Ferrofluid's spikes)
do not apply. The look-spike demonstrates the subject at fidelity today. **But** it is a flat
2D field: no detail cascade, no material response, two hues. It will not clear SHADER_CRAFT §12.1
M1/M2/M3 as written. See Open question 1.

**2. Clear musical role — PASS.** One primitive per layer, distinct timescales (FA #67):

| Visual layer | Primitive | Kind | Timescale |
|---|---|---|---|
| Stirring vigour → seam density | `bassDev` | continuous | ~100 ms |
| Seam luminance / sharpness | `trebRel` | continuous | ~30 ms |
| Palette centre (hue rotation) | spectral centroid | continuous | seconds |
| Reconnection flash (bounded footprint, D-157) | `barPhase01` on the cached BeatGrid | accent | per bar |
| Resistivity η → how fast structure smooths back out | slow arousal / section energy | structural | tens of seconds |

**Silence state (D-037):** unforced, the field relaxes to two or three broad slow-drifting
coloured lobes — evidenced in spike-3 frames f5 and f17. Never black, and genuinely nice to look
at, which matters for a preset whose audience is not paying close attention.

**3. Infrastructure-feasible — NOT ESTABLISHED. This is the decision.** See Open question 2.

---

## Open questions for Matt — I am not building until these are answered

**1. Which rubric does this run under?** The honest read is that Alfvén is a `direct`/`feedback`
2D field preset, structurally closer to `Plasma.json` (`rubric_profile: lightweight`) than to
Lumen Mosaic. Either (a) ship it lightweight with a stylisation contract instead of the full
detail-cascade/material-count gates, or (b) lift it into 3D — light the flux surfaces as a relief
so `|J|` becomes a specular ridge on a material, which would earn the full rubric but is a much
bigger increment and risks losing the oil-wheel flatness that makes it read as psychedelic.
**My recommendation: (a).** The quality floor exists to stop shortcuts; here the flatness is the
concept, not a shortcut.

**2. Are you willing to add a Poisson solve to the GPU contract?** The scheme needs
`∇²φ = −ω` inverted every frame. Uzume has no Poisson/pressure-projection surface today. At 256²
this is ~20–30 Jacobi iterations (or a short multigrid V-cycle) of tiny full-screen passes — cheap
next to a ray march, but it is new engine surface and a new ping-pong state pair (ω, ψ) in
`rgba16Float` or `rg32Float`. Per bar item 3 that is your call, not mine. If the answer is no,
this concept dies here — a curl-noise fake would not be MHD, and faking it is exactly the move
this repo's record punishes.

**3. Do you know of a real-time GPU MHD shader I should port instead of deriving?** FA #73 says
don't rebuild what exists. I could not check Shadertoy from this session. If one exists, reading
and porting it beats my derivation, and I would rather find that out now than after three tuning
rounds.

---

## Risks I am carrying into the build, stated up front

- **Numerical blow-up is a live failure mode, not a theoretical one.** I hit NaN twice in this
  session (bad forcing normalisation; a wavenumber-scaling bug). On stage that is a P0 black
  frame. Mitigation: hard clamps on ω/ψ, an energy watchdog, and a silent re-seed if the field
  goes non-finite — designed in from the first commit, not retrofitted.
- **Grounding is level 2, not level 1** (`PRESET_SESSION_CHECKLIST.md` Part 2, "Design is upstream
  of testing"). The physics has implementable published math; what it does not have is a working
  shader reference in a comparable visual context. My look-spike is CPU-spectral, and a GPU
  Jacobi-Poisson port is a *different numerical scheme* — the pairing is not one a published demo
  has done. That is the same shape as the Aurora Veil failure (mv_warp layered on nimitz's
  recipe), and it should be priced in.
- **Fatigue risk: high.** Full-screen, high-contrast, continuous churn, no rest. Sidecar should
  say so; `section_suitability` probably `["ambient", "breakdown"]` rather than drops.
- **Naming.** "Alfvén" after Hannes Alfvén, whose waves are the transverse magnetic-tension
  motion you are literally watching. ASCII identifier `alfven` for `Alfven.metal` /
  `alfven_fragment`; display name keeps the diacritic. Suggestion only.

## Evidence produced this session

- `evidence_trail.png` — the watched reference, and the two killed spikes.
- `look_sus_b.png` — three palettes on the same passing simulation (D, E, F).
- `mhd_look_spike.gif` — 91 frames of the passing spike, mode D. **This is the pitch.**
- Spike source: `rmhd.py` / `sustain.py` (scratch, not repo code — no Uzume dependency).
