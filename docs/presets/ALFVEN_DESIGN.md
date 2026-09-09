# Alfvén — Design

**Status:** design locked 2026-09-08. Concept gate cleared (`preset-concept`, four artifacts);
three-part bar cleared with Matt's answers of 2026-09-08. Implementation not started.
**Family:** hypnotic · **Rubric:** lightweight · **Paradigm:** staged (persistent + iterated)
**Named for:** Hannes Alfvén, whose waves are the transverse magnetic-tension motion the
preset renders. ASCII identifier `alfven` (`Alfven.metal`, `alfven_*_fragment`); display
name keeps the diacritic.

Companion documents: `ALFVEN_CONCEPT_2026-09-08.md` (the concept gate and its evidence),
`ALFVEN_PORT_SURVEY_2026-09-08.md` (what exists in the wild, licences, the falsified
architecture). Visual references: `docs/VISUAL_REFERENCES/alfven/README.md` — **read its
provenance caveat before judging any render.**

---

## 1. What it is

A full-screen field of marbled liquid: broad lobes of two opposed colours separated by thin
white-hot seams. It is the 1960s oil-wheel liquid light show, with real magnetohydrodynamics
underneath instead of a sine hack. The picture is the **current density** `J = ∇²ψ` — not the
mass density, not the velocity. Where two lobes of opposite magnetic polarity press together,
the seam between them thins into a bright filament, snaps, and the lobes re-braid. That cycle
is magnetic reconnection, and it is also the oil-wheel gesture.

Alfvén exists because `Plasma` is a demoscene sine-interference hack. This is the honest
version of that idea, and it is deliberately the *only* 2D-field preset that earns its
flatness from physics.

## 2. Musical role (Part 2 gate — one sentence)

> **When the track crosses a section boundary the entire magnetic field dissolves and
> re-braids into a new arrangement, and between boundaries the bass envelope sets how hard
> the field is stirred, so seam density rises and falls with the low end.**

The structural channel is the primary one, and it is what makes this preset an instrument
rather than a wallpaper: **the visual architecture turns the page when the song does.**

## 3. Temporal contract

| Horizon | What happens |
|---|---|
| ~30 ms | Seam bloom flickers with treble transients |
| ~100 ms | Seam density thickens/thins with the bass envelope |
| per bar | A bounded reconnection flash on the downbeat (D-157: bounded footprint, steady global luminance) |
| seconds | Palette hue centre drifts with spectral centroid |
| **20–30 s (the cycle)** | **One complete braid-to-filament arc: a fresh seed folds, sharpens into filaments, and dissolves into the next seed on a section boundary** |

The 20–30 s arc is not a stylistic choice — see §5.

## 4. Physics

2D incompressible MHD in vorticity / flux-function form:

```
omega = lap(phi),  u = (-phi_y,  phi_x)        psi = flux function
J     = lap(psi),  B = (-psi_y,  psi_x)

d_t omega = -{phi,omega} + {psi,J} + nu lap(omega) - alpha omega + f
d_t psi   = -{phi,psi}              + eta lap(psi)
{a,b}     = a_x b_y - a_y b_x
```

On the GPU this becomes, per frame: advect ω and ψ semi-Lagrangian → add the Lorentz term
`{ψ,J}` and the forcing → **solve `∇²φ = −ω`** → derive `u` from `φ` → diffuse → render `J`.
The Poisson solve is the new engine surface (§6).

`J` is what the fragment shader colours. `ω` supplies nothing visual on its own; it is state.

## 5. The condensate — why this is a sequence of transients

**2D MHD inverse-cascades the mean-square flux potential ⟨ψ²⟩ to the largest available scale
and condenses there** (Biskamp, *Magnetohydrodynamic Turbulence*, ch. 7). Once ψ condenses
into a box-scale mode the magnetic field is a static crystal and the flow is frozen along it.
The picture becomes a regular quilted lattice and stops evolving.

This was verified empirically, twice, during concept work: a driven steady state produced
exactly that lattice at ~12 s (`06_anti_static_quilt.png`), and lowering the drag, widening
the forcing shell and decorrelating the forcing phases faster did not fix it. **A sustained
driven MHD state cannot be the look. This is physics, not a tuning problem — do not spend
increments trying to hold a steady state.**

The architecture that works: seed a fresh braid, let the fold-to-filament arc run, and
dissolve into the next braid *before the condensate forms*, with a raised-cosine crossfade in
(ω, ψ) so there is no cut. Each cycle is a genuine decaying MHD evolution from real initial
conditions. The re-seed is triggered by a section boundary, with a hard ceiling of ~35 s so
a section-free track still never reaches the condensate.

## 6. Engine surface required (ALFVEN.1 — infrastructure, lands first)

The existing `staged` paradigm (`PresetStage`, V.ENGINE.1) is the right shape but is missing
two things. Both are small, generic extensions, not a bespoke pipeline:

| Need | Why staged can't do it today | Extension |
|---|---|---|
| State that survives across frames (ω, ψ) | Stages render to fresh per-stage textures each frame | `"persistent": true` — the stage owns a ping-pong pair; reads previous frame's output, writes the next |
| N Jacobi sweeps for the Poisson solve | A stage runs exactly once | `"iterations": N` — the stage runs N times, ping-ponging its own output |
| Precision for a Poisson solve | Stages are hardcoded `.rgba16Float` | `"pixel_format"` per stage — Alfvén's state stages need `rgba32Float` |

The projection itself is a **port**, not a derivation:
[PavelDoGreat/WebGL-Fluid-Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation)
(**MIT**) already ships divergence, the Jacobi pressure iteration and gradient-subtract as
short GLSL fragment shaders. Adopt them verbatim in structure; adapt only context (Metal
syntax, texture bindings, our coordinate convention). Do not re-derive — FA #73/#65.
Read Harris, *Fast Fluid Dynamics Simulation on the GPU* (GPU Gems ch. 38) alongside it so
the pass structure is understood, not just transcribed.

## 7. Audio routing (one primitive per layer — FA #67)

| Visual layer | Primitive | Kind | Timescale |
|---|---|---|---|
| Re-seed — the field dissolves and re-braids | section boundary | `structural` | tens of seconds |
| Stirring vigour → seam density | `bassDev` | `continuous` | ~100 ms |
| Seam bloom / sizzle | `trebRel` | `continuous` | ~30 ms |
| Palette hue centre | spectral centroid | `continuous` | seconds |
| Reconnection flash (bounded footprint) | `barPhase01` | `accent` | per bar |

No primitive appears twice; no two layers share a timescale. Every driver reads a deviation
primitive (D-026); absolute thresholds on AGC-normalised energy are forbidden (FA #31).

**Cold start.** Continuous energy and deviation primitives are live from frame 1, so the
field stirs correctly immediately. The cached `BeatGrid` may install with the wrong phase, so
the per-bar reconnection flash is **suppressed for the first 4 bars** and faded in — a
wrong-phase flash on a full-screen field is far more noticeable than a wrong-phase accent on
a local element. Section boundaries are not available at cold start either, so the first
re-seed falls back to the ~35 s ceiling.

**Silence (D-037).** With drive near zero the field relaxes to two or three broad, slow,
fully-coloured lobes — `05_atmosphere_relaxed_state.png`. Never black, never flat.

## 8. Stability — designed in at commit one, not retrofitted

Three NaN blow-ups occurred while building the CPU spike. On stage that is a P0 black frame.
The mitigations are requirements, not nice-to-haves:

1. **Smooth spectral / heat-kernel damping** at the top of the wavenumber range. On the CPU
   spike the Hou–Li filter `exp(-36 (k/k_max)^36)` is what finally held it; the GPU analogue
   is a small explicit diffusion pass with a strongly scale-dependent coefficient.
2. **Hard clamps** on ω and ψ each frame, at a bound derived from the seed amplitude.
3. **Non-finite watchdog** — if any state texture goes non-finite, silently re-seed. It must
   be silent: a visible reset is worse than the artefact it replaces.
4. **CFL-bounded advection** — the semi-Lagrangian back-trace must be clamped to a maximum
   displacement in texels; an unbounded trace on a spiking field is how it diverges.

## 9. Sidecar sketch (ALFVEN.2 lands this; not authoritative until then)

```json
{
  "name": "Alfvén", "family": "hypnotic", "duration": 30,
  "passes": ["staged"],
  "stages": [
    { "name": "advect",     "fragment_function": "alfven_advect_fragment",
      "persistent": true, "pixel_format": "rgba32Float" },
    { "name": "divergence", "fragment_function": "alfven_divergence_fragment",
      "samples": ["advect"] },
    { "name": "pressure",   "fragment_function": "alfven_pressure_fragment",
      "samples": ["divergence"], "persistent": true, "iterations": 24,
      "pixel_format": "rgba32Float" },
    { "name": "project",    "fragment_function": "alfven_project_fragment",
      "samples": ["advect", "pressure"] },
    { "name": "compose",    "fragment_function": "alfven_compose_fragment",
      "samples": ["project"] }
  ],
  "fatigue_risk": "high",
  "section_suitability": ["ambient", "breakdown"],
  "rubric_profile": "lightweight",
  "certified": false,
  "audio_routes": [ /* §7, declared only after auditing the code reads them */ ]
}
```

## 10. Increment plan

| ID | Type | Scope | Gate |
|---|---|---|---|
| **ALFVEN.1** | infrastructure | `PresetStage` persistent/iterated/pixel_format + staged encoder + harness template + a `PoissonSandbox` diagnostic that converges against an analytic solution | Convergence assertion + harness green. **No Alfvén, no art.** |
| **ALFVEN.2** | preset | `Alfven.metal` + sidecar, MHD advance, silence state, re-seed cycle. **No audio routing.** | Still sheet + motion gate against the reference set; the §11 open risk resolved |
| **ALFVEN.3** | preset | Audio routing per §7, `audio_routes` manifest, cold-start suppression | `RouteCoverageTests` green on the canonical fixtures; M7 |

Infrastructure lands before the preset and is never bundled with it.

## 11. The open risk that decides ALFVEN.2

**Does a GPU Jacobi projection at 256² reproduce the CPU spectral spike's look?** It is a
different numerical scheme and materially more diffusive; the filaments may come out softer.
This cannot be settled by argument. ALFVEN.2's first task is a silence-state render compared
against `05_atmosphere_relaxed_state.png` and `01_macro_braided_lobes.png` — *before* any
tuning, and before any audio work. If the seams read as soft glow rather than lines, the
options are: raise the grid to 512², reduce projection diffusion (BFECC / MacCormack
advection), or accept a softer look and re-shoot the reference set. That decision goes to
Matt; it is not Claude's to make silently.

## 12. Grounding levels (Part 2 "design is upstream of testing")

| Mechanism | Level | Note |
|---|---|---|
| GPU pressure projection | **1 — working code reference** | WebGL-Fluid-Simulation, MIT, port it |
| MHD induction + Lorentz term | **2 — published math** | Textbook; Athena++ (BSD-3) for cross-checking |
| Re-seed crossfade in (ω, ψ) | **2 — validated in the CPU spike** | Not a published technique; the spike is the only evidence |
| **The combination** — projection-solver MHD at 60 fps | **3 — no precedent found** | **Surfaced explicitly.** No real-time GPU MHD exists in the wild (see the port survey). This is the Aurora Veil failure shape (a pairing no published demo used) and is the reason ALFVEN.2 gates on a look comparison before any tuning |
