// Alfven.metal — ALFVEN.2. Driven 2D incompressible MHD in vorticity / flux-function
// (reduced-MHD) form, on the persistent+iterated staged surface added at ALFVEN.1 (D-244).
//
// STATE, NOT ART, AT THIS STAGE. This increment ports the PHYSICS and renders it with a
// fixed placeholder exposure. The shipping look is `docs/presets/alfven_spike/film.py`,
// whose `autoexp` (2nd/99.6th percentile of |J|), `std(J)` and two Gaussian blurs are all
// GLOBAL/multi-scale operations a fragment shader cannot perform — they need a mip or
// reduction surface Uzume does not have yet. Porting film.py is deliberately deferred
// until that surface exists; a fixed exposure is fully diagnosable and lets the physics
// be measured first. See the ALFVEN.2 closeout.
//
// ── Physics (ALFVEN_DESIGN.md §4) ────────────────────────────────────────────
//   omega = lap(phi),   u = (-phi_y,  phi_x)
//   psi   = flux fn,    B = (-psi_y,  psi_x),   J = lap(psi)
//   d_t omega = -{phi,omega} + {psi,J} + nu lap(omega) - alpha omega + f
//   d_t psi   = -{phi,psi}              + eta lap(psi)
//   {a,b}     = a_x b_y - a_y b_x
//
// Per frame: solve lap(phi) = -omega (Jacobi, previous frame's omega) -> derive u ->
// semi-Lagrangian advect (omega, psi) -> add Lorentz {psi,J} + forcing -> diffuse -> clamp.
//
// `J` is what the fragment colours; `omega` is state and supplies nothing visual (§4).
//
// ── Divergences from the spike, all forced by the scheme, all recorded ───────
// The spike is PSEUDO-SPECTRAL. Three of its stabilisers have no real-space port:
//   1. `FILT = exp(-36 (k/kmax)^36)` (Hou-Li) — the spike's comment says it is "what
//      finally held it" after two blow-ups. §8.1 calls the GPU version "the analogue":
//      an explicit diffusion pass with a strongly scale-dependent coefficient. That is
//      grounding level 3 (design-doc assertion only) and is the single largest risk in
//      this preset. Implemented below as `alfven_hyperdiffuse`.
//   2. `nu4 k^4` hyperdiffusion — §4 already descopes this to plain `nu lap`, which damps
//      the LOBES as well as the grid scale. Kept at §4's spelling, with the biharmonic
//      term available separately so the soak can A/B them.
//   3. 2/3 dealiasing — no real-space analogue; the diffusion carries that load instead.
//
// ── Bindings (docs/ARCHITECTURE.md §GPU Contract Details) ────────────────────
//   [[texture(13)]]+ = this stage's `samples`, in declared order
//   [[texture(20)]]  = this stage's own previous state (frame N-1, or previous iteration)
//
// State packing in the `state` stage's rgba32Float texture:
//   .r = omega    .g = psi    .b = J (cached for the compose stage)    .a = 1

// The solver draws the field itself (AlfvenSolver.render). This ground exists because the
// particles path draws the preset's own fragment first; it is the D-037 non-black floor
// and nothing more. All the physics that used to live in this file moved to the compute
// solver at ALFVEN.4 — see AlfvenSolver.swift for why.

fragment float4 alfven_ground_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    return float4(0.035, 0.045, 0.075, 1.0);
}
