# Equation-derived preset candidates — brainstorm

**Date:** 2026-09-09 · **Status:** candidate list, **not** pitches. Nothing here has cleared
`preset-concept`; three have been spiked and the spikes are the useful part.

Alfvén opened a lane the roster didn't have: presets whose subject is the *solution of a PDE*
rather than a geometric construction. The `psychedelic_geometry` slate (PG.1–PG.5) is
kaleidoscopes, Droste, Mandelbox, hyperbolic tiling — pure geometry. This is the other lane.

---

## The selection filter (earned the hard way, 2026-09-08)

Four tests. A candidate that fails any one of them is not worth a gate run.

1. **Does the system have a boring attractor?** Almost every pretty PDE relaxes to something
   static — MHD condensates at box scale, reaction-diffusion settles to spots, Cahn-Hilliard
   coarsens. A preset loops forever. Either the system is provably non-settling, or you
   architect a transient cycle (Alfvén's re-seed). **Check this first; it kills most candidates.**
2. **Is the obvious field the right field?** Alfvén's mass density is mush; the *current
   density* is the picture. Look for the derivative, curl or Laplacian of the state, not the
   state.
3. **Does it hand you an iconic subject, or just texture?** "Beautiful colours everywhere" is
   wallpaper. The three-part bar wants something a viewer can name.
4. **Is there a legible audio handle?** One parameter that visibly changes the picture in a way
   a listener pairs with what they hear.

---

## Spiked — frames exist, look at them before believing any of this

| Candidate | What it is | Spike verdict |
|---|---|---|
| **Complex Ginzburg–Landau**, defect-turbulence regime | `dA/dt = A + (1+ic₁)∇²A − (1+ic₂)\|A\|²A`. With `c₁c₂ > 1` (Benjamin–Feir unstable) it is **provably** non-settling — the one candidate where "never repeats" is a theorem, not a hope. One complex field, one Laplacian, no Poisson solve. Phase → hue is the canonical mapping. | **Best of the three, but not yet a concept.** Genuinely psychedelic and never settles (test 1 ✓). Fails test 3 as configured: at its natural scale it reads as fine-grained confetti — texture, not subject. A second pass at coarser scale made it *worse* (more cells, not fewer). Needs a scale-and-composition answer — a handful of large cells with a strong defect-core treatment — before it goes to the gate. |
| **Barkley excitable medium**, spiral breakup | `du/dt = ε⁻¹u(1−u)(u−(v+b)/a) + ∇²u`, `dv/dt = u−v`. Rotating spiral waves; low `a` should give sustained breakup. | **Killed as configured.** At `a=0.75` it locks into a symmetric neon spiral lattice that stops evolving — the same wallpaper failure as Alfvén's condensate, and it looks like it. Dropping to `a=0.50` broke up only a local patch and left the rest frozen: worse. Uniform breakup is a real parameter hunt, and the payoff is a two-tone poster. |
| **Kuramoto–Battogtokh chimera** | Nonlocally coupled phase oscillators; with `α` just under π/2 a coherent domain and an incoherent domain **coexist**. The best *concept* on the list — the screen visibly synchronises and shatters. | **Killed on looks.** The physics works (you can see the chimera). The picture is grey mush with RGB static: the incoherent domain is per-pixel random, so it renders as TV snow. It would need a rendering invention — draw the smoothed local order parameter, not the raw phase — and that is a different project. |

**All three sounded excellent as prose and two died on contact.** That is the whole argument for
spiking before pitching.

---

## Not yet spiked — ranked by the filter

**1. Faraday waves / parametric surface instability — the strongest musical role on the list.**
A fluid surface driven by vertical vibration. As drive rises the pattern selects stripes →
squares → hexagons → quasipatterns → oscillons. **The drive amplitude is literally the sound**,
so loudness changes the *symmetry* of the pattern, not merely its brightness — a listener pairs
that instantly. Iconic subject: the surface of a liquid dancing to the music. Cheap: a damped
driven Mathieu-type surface equation, no Poisson solve. **Risk: Matt should rule on overlap with
Cymatic Resonance.** My read is they are different — Chladni is linear standing modes on a plate,
Faraday is a nonlinear instability with pattern selection and oscillons — but that is his call,
not mine.

**2. Rayleigh–Bénard convection, spiral-defect-chaos regime — the infrastructure bargain.**
Convection rolls that provably never settle in the SDC regime. Iconic subject (convection cells),
and hot-rising/cold-sinking makes a warm/cool palette physically honest rather than decorative.
Audio → Rayleigh number, which walks it from lazy rolls to churning chaos. **It needs a Poisson
solve — which ALFVEN.1 is already building.** Near-zero marginal engine cost if Alfvén lands.

**3. Gross–Pitaevskii / superfluid vortex tangle.** Phase → hue, vortices as dark cores that
survive collisions. Driven quantum turbulence does not settle. Iconic subject: vortices. Needs a
stable real-space integrator (a split-step FFT is the usual route and we have no GPU FFT).

**4. Dielectric breakdown / Lichtenberg figures.** Per-beat lightning across the frame. Maximally
iconic, maximally legible. It *settles* — the tree finishes growing — so it needs a per-strike
architecture, which is the same shape as Alfvén's re-seed and now a known pattern.

**5. Soliton systems (sine-Gordon breathers, KdV).** Pulses that pass through each other intact.
Each onset launches one; collisions are the interest. Legible, cheap, and unlike anything on the
roster. Weakest on "fills a frame."

**6. Cahn–Hilliard spinodal decomposition.** Marbling. Coarsens and settles — but the coarsening
arc is a natural 20–30 s cycle, so the Alfvén transient architecture ports directly.

**Considered and set aside:** Belousov–Zhabotinsky / Oregonator (overlaps the existing `reaction`
family — Mitosis / Cytokinesis); Swift–Hohenberg (settles to labyrinths); Ising at criticality
(reads as noise); Kerr geodesics and accretion disks (cinematic rather than psychedelic, and
expensive); Lorenz/Thomas attractor particle flows (generic, and the particle lane is Murmuration's).

---

## Recommendation

**Take Faraday waves through the gate next**, on the strength of its musical role — nothing else
here lets the music change the *symmetry* of what is on screen. Before it is pitched it needs a
spike, and the spike must answer one question: does the pattern hold a readable composition at
frame scale, or does it go fine-grained like CGLE did?

**If ALFVEN.1 lands cleanly, Rayleigh–Bénard is the cheap follow-on** — it reuses the projection
solver outright.

And do not let CGLE go: it is the only candidate whose non-settling behaviour is guaranteed by
the mathematics rather than by tuning. It needs a composition answer, not a physics answer.
