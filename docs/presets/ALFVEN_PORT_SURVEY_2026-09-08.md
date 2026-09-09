# Alfvén — port survey and revised architecture

**Date:** 2026-09-08 (same session as `ALFVEN_CONCEPT_2026-09-08.md`)
**Answers logged:** rubric = option (a), 2D field / lightweight · Poisson solve approved ·
Matt knows of no real-time GPU MHD shader.

---

## 1. Port survey — what exists in the wild (FA #73)

**Finding: there is no real-time GPU magnetohydrodynamics shader to port. I looked and did not
find one, and neither did you.** Every real-time GPU fluid in the wild solves Navier–Stokes only;
every MHD implementation is an offline scientific code. That gap is the honest headline, and it
changes what "port, don't rebuild" means here: **the physics is a derivation, the infrastructure
is a port.**

| Candidate | What it is | License | Verdict |
|---|---|---|---|
| [PavelDoGreat/WebGL-Fluid-Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation) | The canonical real-time GPU fluid: semi-Lagrangian advection, divergence, **Jacobi pressure solve**, gradient-subtract, curl/vorticity confinement, bloom — all short GLSL fragment shaders | **MIT** | **PORT THIS.** It is exactly the new engine surface you approved. Every pass we need for the projection step already exists, tested, in ~30 lines each |
| [Athena++](https://github.com/PrincetonUniversity/athena) | Production astrophysical MHD; constrained transport, Riemann solvers | **BSD-3** | Reference for the **induction / constrained-transport** half. Read for correctness, port selectively |
| [pmocz/constrainedtransport-python](https://github.com/pmocz/constrainedtransport-python) | The Orszag–Tang solver I watched for artifact 1 | **GPL-3** | **Watch-only. Do not copy a line into an MIT repo** |
| Harris, *Fast Fluid Dynamics Simulation on the GPU* (GPU Gems ch. 38) | The published description of the Jacobi-projection method the above implements | Text | Read alongside the port so the pass structure is understood, not just transcribed |
| Shadertoy | Could not be searched — Cloudflare bot check in the browser, domain blocked by this session's egress policy | — | **Unresolved.** Worth five minutes in your own browser before we commit |

**Consequence for the grounding level.** With the Poisson solve as a port, the derivation shrinks
to the induction equation and the Lorentz force — two terms added to a working solver, which is a
far smaller unproven surface than "write an MHD solver." Grounding moves from a weak level 2 to a
level 1 port plus a level 2 delta.

---

## 2. The steady-state architecture is falsified — and the cause is physics

I built the driven version, ran it against `so_what.m4a` for 24 seconds, and **it fails in the
second half.** It organises into a stationary quilted lattice: regular cells, frozen flow, no
further evolution. Lowering the drag, widening the forcing shell and decorrelating the forcing
phases faster did not fix it — the lattice came back with concentric ringing on top.

**The cause is not a bug.** 2D MHD inverse-cascades the mean-square flux potential ⟨ψ²⟩ to the
largest available scale and **condenses** there (Biskamp, *MHD Turbulence*, ch. 7). Once ψ
condenses into a box-scale mode the magnetic field is a static crystal and the flow is frozen
along it. Any sustained drive in a periodic box ends there. **A steady driven MHD state cannot
be the look.** This is the same lesson the Orszag–Tang reference gave me on the first day — the
beauty lives in the transient — and I had to learn it twice.

## 3. Revised architecture: a sequence of transients

Seed a fresh braid, let the fold-to-filament arc run for ~20–30 s, and dissolve into the next
braid **before the condensate forms** — a raised-cosine crossfade in (ω, ψ) so there is no cut.
Each cycle is a genuine decaying MHD evolution from real initial conditions; the condensate never
gets time to win.

This is better than a patch, because it upgrades the musical role:

| Visual layer | Primitive | Kind | Timescale |
|---|---|---|---|
| **Re-seed — the whole field dissolves and re-braids** | section boundary | **structural** | tens of seconds |
| Stirring vigour → seam density | `bassDev` | continuous | ~100 ms |
| Seam bloom / sizzle | `trebRel` | continuous | ~30 ms |
| Palette hue centre | spectral centroid | continuous | seconds |
| Reconnection flash (bounded footprint, D-157) | `barPhase01` | accent | per bar |

The preset's architecture now tracks the *song's* architecture, which is a much stronger answer to
"how is this another instrument in the band" than "it stirs harder on the bass." It also supplies
the temporal contract the checklist demands: what carries a listener through 30 seconds is one
complete braid-to-filament arc, and the section change is what turns the page.

## 4. Engine surface to build (the increment you approved)

1. **`PoissonProjection` pass** — ported from WebGL-Fluid-Simulation: divergence → N Jacobi
   iterations → gradient subtract. New generic engine surface, reusable beyond this preset.
2. **Two ping-pong state pairs** (ω, ψ) at 256², `rg32Float` or `rgba16Float`.
3. **Alfvén advance kernel** — the induction equation and Lorentz force, the level-2 delta.
4. **Stability, designed in from commit one, not retrofitted:** a smooth spectral/heat-kernel
   filter (the Hou–Li filter is what finally stabilised the CPU spike), hard clamps on ω/ψ, and a
   non-finite watchdog that silently re-seeds. I hit NaN three times building the spike; on stage
   that is a P0 black frame.
5. **Multi-frame harness first**, per Part 2 — the `feedback` template (`FeedbackPathHarnessTemplate`),
   extended for a two-state ping-pong, written before any shader work.

## 5. What I still do not know

- Whether a GPU Jacobi projection at 256² reproduces the CPU spectral spike's *look*. It is a
  different numerical scheme; spectral methods are far less diffusive. The filaments may come out
  softer. That is the single biggest open risk and it cannot be settled by argument — the first
  increment should be the projection pass plus a silence-state render, compared against the spike
  frames, before any audio routing is wired.
- Whether Shadertoy holds a real-time MHD shader that would make points 1–3 unnecessary.
