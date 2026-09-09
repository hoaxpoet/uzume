// PoissonSandbox.metal — ALFVEN.1 diagnostic preset (D-244).
//
// Proves the three staged-composition capabilities added in ALFVEN.1 —
// `persistent`, `iterations` and `pixel_format` — by running a real pressure
// projection: an analytic divergent velocity field is made divergence-free by
// solving ∇²p = ∇·u with Jacobi relaxation and subtracting ∇p.
//
//   velocity   (rgba32Float)                      analytic divergent field
//   divergence (rgba32Float, samples velocity)    ported ∇·u
//   pressure   (rgba32Float, persistent,          ported Jacobi sweep, 24×/frame,
//               iterations 24, samples divergence) warm-started from last frame
//   project    (rgba32Float, samples velocity,    ported u -= ∇p
//               pressure)
//   compose    (drawable, samples pressure,       what a human looks at
//               project)
//
// This is a DIAGNOSTIC (`is_diagnostic: true`), the same class as StagedSandbox:
// it exists to prove the engine surface, not to look good. No audio is read —
// audio routing for the preset that motivated this surface is ALFVEN.3.
//
// ── Provenance ───────────────────────────────────────────────────────────────
//
// The divergence, Jacobi-pressure and gradient-subtract fragments are PORTED
// from PavelDoGreat/WebGL-Fluid-Simulation (MIT), `script.js` — `divergenceShader`,
// `pressureShader`, `gradientSubtractShader` — adopted verbatim in structure per
// FA #73/#65. See `docs/CREDITS.md`. Pass structure cross-read against Harris,
// *Fast Fluid Dynamics Simulation on the GPU* (GPU Gems 3 ch. 38).
//
// Exactly three things were adapted, all CONTEXT, none of them numerics:
//
//   1. Metal syntax and our binding convention. The reference's `vL`/`vR`/`vT`/`vB`
//      varyings (computed in its base vertex shader as `vUv ± texelSize`) become
//      per-fragment offsets from `in.uv`, since our shared `fullscreen_vertex`
//      carries only `uv`. Same texel offsets, computed one stage later.
//   2. Boundary condition. The reference clamps to a bounded box and reflects
//      velocity at the walls (`if (vL.x < 0.0) { L = -C.x; }`) — free-slip. Our
//      domain is DOUBLY PERIODIC (ALFVEN_DESIGN.md §6), so those four clauses are
//      replaced by an `address::repeat` sampler, which is the periodic BC. This is
//      a different boundary condition, deliberately, not a dropped component.
//   3. Our `fullscreen_vertex` flips uv.y, so "top"/"bottom" are swapped relative
//      to GL. The flip is consistent across divergence and gradient-subtract, so
//      the projection is unaffected; the names are kept as the reference has them.
//
// NOT adapted, deliberately: the reference's divergence carries a 0.5 factor
// while gradient-subtract uses an unscaled central difference. That asymmetry is
// what the reference ships and what its behaviour is tuned around (FA #65 — a
// redundancy/consistency argument against a working reference needs a rendering
// test, not algebra). The Jacobi stencil is therefore solving
// `L + R + T + B - 4C = divergence`, i.e. ∇²p = f in units where the grid spacing
// is one texel — which is the convention `PoissonProjectionConvergenceTests`
// asserts against an analytic solution.
//
// ── Bindings (docs/ARCHITECTURE.md §GPU Contract Details) ─────────────────────
//   [[texture(13)]], [[texture(14)]] … = this stage's `samples`, in declared order
//   [[texture(20)]]                    = this stage's PREVIOUS state
//                                        (previous frame / previous iteration)

// Periodic, unfiltered. Nearest is what the stencil wants: every read lands on a
// texel centre, and 32-bit float filtering is not universally supported.
constant constexpr sampler poisson_grid_sampler(filter::nearest,
                                                address::repeat);

// Display gain for the pressure field in `compose`. Diagnostic presentation only
// — it scales nothing the solver sees.
//
// Sized against the CONVERGED field, not the first frame. The pressure stage is
// persistent, so its amplitude grows by ~50x over the first second as the solve
// warm-starts toward the answer (measured RMS 0.051 at frame 1, 2.78 at frame 60
// at 256^2). A gain tuned to frame 1 clips the answer to flat white and hides the
// very thing this diagnostic exists to show. At 0.25 the converged field sits in
// the middle of the ramp, and the early frames read as a faint, unfinished field —
// which is what an unconverged solve honestly looks like.
//
// KNOWN LIMITATION, not worth engineering away: this gain is calibrated at 256^2.
// Staged textures are drawable-sized, and both the converged pressure amplitude
// and the time to reach it grow with resolution, so at 1080p the field brightens
// over minutes rather than seconds and would eventually clip again. Normalising
// it would mean adding a reduction pass to the diagnostic, which would prove
// nothing about the engine surface this preset exists to prove. If a future
// consumer needs a resolution-independent readout, normalise then — and measure
// the scaling rather than deriving it.
constant constexpr float kPoissonDisplayGain = 0.25;

// ─── Stage 1: VELOCITY ───────────────────────────────────────────────────────
//
// An analytic, doubly-periodic velocity field with deliberately non-zero
// divergence, so the projection has real work to do. Static: this diagnostic is
// about the solver, not about motion.

fragment float4 poisson_sandbox_velocity_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    constexpr float kTau = 6.28318530718;
    float2 uv = in.uv;

    // Solenoidal part (a single cell of counter-rotating shear) …
    float2 u = float2(sin(kTau * uv.y), sin(kTau * uv.x)) * 0.5;
    // … plus a compressible part, which is what the projection has to remove.
    u += float2(sin(kTau * uv.x), sin(kTau * uv.y)) * 0.35;

    return float4(u, 0.0, 1.0);
}

// ─── Stage 2: DIVERGENCE ─────────────────────────────────────────────────────
//
// Port of `divergenceShader`. Reference body, verbatim in structure:
//
//     float L = texture2D(uVelocity, vL).x;   float R = texture2D(uVelocity, vR).x;
//     float T = texture2D(uVelocity, vT).y;   float B = texture2D(uVelocity, vB).y;
//     … boundary reflection …
//     float div = 0.5 * (R - L + T - B);

fragment float4 poisson_sandbox_divergence_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> velocityTex [[texture(13)]]
) {
    float2 uv    = in.uv;
    float2 texel = 1.0 / float2(velocityTex.get_width(), velocityTex.get_height());

    float L = velocityTex.sample(poisson_grid_sampler, uv - float2(texel.x, 0.0)).x;
    float R = velocityTex.sample(poisson_grid_sampler, uv + float2(texel.x, 0.0)).x;
    float T = velocityTex.sample(poisson_grid_sampler, uv + float2(0.0, texel.y)).y;
    float B = velocityTex.sample(poisson_grid_sampler, uv - float2(0.0, texel.y)).y;

    float div = 0.5 * (R - L + T - B);
    return float4(div, 0.0, 0.0, 1.0);
}

// ─── Stage 3: PRESSURE (Jacobi) ──────────────────────────────────────────────
//
// Port of `pressureShader`. Reference body, verbatim:
//
//     float pressure = (L + R + B + T - divergence) * 0.25;
//
// Run `iterations: 24` times per frame against its own previous iterate at
// [[texture(20)]], and `persistent: true` so iteration 1 of frame N+1 warm-starts
// from frame N's answer instead of restarting from zero.

fragment float4 poisson_sandbox_pressure_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> divergenceTex [[texture(13)]],
    texture2d<float, access::sample> prevPressureTex [[texture(20)]]
) {
    float2 uv    = in.uv;
    float2 texel = 1.0 / float2(prevPressureTex.get_width(), prevPressureTex.get_height());

    float L = prevPressureTex.sample(poisson_grid_sampler, uv - float2(texel.x, 0.0)).x;
    float R = prevPressureTex.sample(poisson_grid_sampler, uv + float2(texel.x, 0.0)).x;
    float T = prevPressureTex.sample(poisson_grid_sampler, uv + float2(0.0, texel.y)).x;
    float B = prevPressureTex.sample(poisson_grid_sampler, uv - float2(0.0, texel.y)).x;

    float divergence = divergenceTex.sample(poisson_grid_sampler, uv).x;
    float pressure   = (L + R + B + T - divergence) * 0.25;

    return float4(pressure, 0.0, 0.0, 1.0);
}

// ─── Stage 4: PROJECT (gradient subtract) ────────────────────────────────────
//
// Port of `gradientSubtractShader`. Reference body, verbatim:
//
//     vec2 velocity = texture2D(uVelocity, vUv).xy;
//     velocity.xy -= vec2(R - L, T - B);

fragment float4 poisson_sandbox_project_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> velocityTex [[texture(13)]],
    texture2d<float, access::sample> pressureTex [[texture(14)]]
) {
    float2 uv    = in.uv;
    float2 texel = 1.0 / float2(pressureTex.get_width(), pressureTex.get_height());

    float L = pressureTex.sample(poisson_grid_sampler, uv - float2(texel.x, 0.0)).x;
    float R = pressureTex.sample(poisson_grid_sampler, uv + float2(texel.x, 0.0)).x;
    float T = pressureTex.sample(poisson_grid_sampler, uv + float2(0.0, texel.y)).x;
    float B = pressureTex.sample(poisson_grid_sampler, uv - float2(0.0, texel.y)).x;

    float2 velocity = velocityTex.sample(poisson_grid_sampler, uv).xy;
    velocity -= float2(R - L, T - B);

    return float4(velocity, 0.0, 1.0);
}

// ─── Stage 5: COMPOSE ────────────────────────────────────────────────────────
//
// What a human looks at. A solved pressure field must not be black — a black
// diagnostic teaches nothing — so pressure goes through a diverging ramp whose
// zero is a mid-tone, and the projected velocity modulates brightness so the
// two halves of the answer are visible at once.

fragment float4 poisson_sandbox_compose_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> pressureTex [[texture(13)]],
    texture2d<float, access::sample> projectedTex [[texture(14)]]
) {
    float2 uv = in.uv;

    float pressure = pressureTex.sample(poisson_grid_sampler, uv).x;
    float2 vel     = projectedTex.sample(poisson_grid_sampler, uv).xy;

    // Diverging ramp: teal (negative) → slate mid-tone (zero) → amber (positive).
    float t = tanh(pressure * kPoissonDisplayGain) * 0.5 + 0.5;
    float3 negCol = float3(0.10, 0.52, 0.58);
    float3 midCol = float3(0.22, 0.24, 0.30);
    float3 posCol = float3(0.86, 0.58, 0.18);
    float3 col = (t < 0.5) ? mix(negCol, midCol, t * 2.0)
                           : mix(midCol, posCol, (t - 0.5) * 2.0);

    // Projected-velocity magnitude as a brightness lift, so a dead projection
    // reads as a flat field rather than as a plausible one. Kept under 1.0 so it
    // modulates the ramp instead of driving it into clipping.
    col *= 0.70 + 0.30 * saturate(length(vel));

    // Thin iso-contours on the pressure field — the cheapest way to see whether
    // the solve is smooth or still noisy after N sweeps.
    float band = abs(fract(t * 12.0) - 0.5);
    col += float3(0.9, 0.94, 1.0) * smoothstep(0.06, 0.0, band) * 0.10;

    return float4(min(col, float3(1.0)), 1.0);
}
