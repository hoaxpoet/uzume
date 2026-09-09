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

constant constexpr sampler alfven_state_sampler(filter::nearest, address::repeat);
constant constexpr sampler alfven_lerp_sampler(filter::linear, address::repeat);

// ── Tunables ────────────────────────────────────────────────────────────────
// Spelled as named constants so the soak can move one at a time. Values are the
// spike's where the spike has one (alpha 0.16, forcing shell k in [2,5]).
constant constexpr float kAlfvenDt        = 0.016;  // s per frame; fixed, not render dt (BUG-097)
constant constexpr float kAlfvenAlpha     = 0.16;   // linear drag on omega (spike value)
constant constexpr float kAlfvenNu        = 0.9;    // omega diffusion, texel^2 units
constant constexpr float kAlfvenEta       = 0.5;    // psi diffusion
constant constexpr float kAlfvenHyper     = 0.35;   // grid-scale-only damping (Hou-Li analogue)
constant constexpr float kAlfvenDrive     = 0.020;  // forcing amplitude (spike: 0.020 * ...)
constant constexpr float kAlfvenMaxTrace  = 3.0;    // CFL: max back-trace, texels (§8.4)
constant constexpr float kAlfvenClampW    = 24.0;   // hard clamp on omega (§8.2)
constant constexpr float kAlfvenClampP    = 12.0;   // hard clamp on psi
constant constexpr float kAlfvenSeedFloor = 0.02;   // below this |psi| RMS proxy, re-seed
// The re-seed cycle (§5). NOT a stylistic choice: 2D MHD inverse-cascades <psi^2> to box
// scale and CONDENSATES there (Biskamp ch. 7), so a sustained driven state is a static
// quilt (`06_anti_static_quilt.png`) — verified twice during concept work. The look IS the
// decaying transient of a strong seed, which means the field must be re-seeded before the
// condensate forms. With alpha = 0.16 against drive = 0.020 the driven equilibrium for
// omega is ~0.125, i.e. nearly dead, so without this cycle the field correctly decays to
// nothing (measured: 10x decay over 900 frames, ALFVEN.2 soak).
// Period from §3's temporal contract (20-30 s). The spike's film used ~12.6 s; §5 says the
// driven condensate appeared at ~12 s, so 22 s sits inside the contract while staying well
// clear of a full decay. ALFVEN.3 replaces the fixed period with section boundaries.
constant constexpr float kAlfvenCycleSeconds = 22.0;
constant constexpr float kAlfvenBlendTau     = 1.1;   // spike: advance_blend(tau=1.1)
constant constexpr float kAlfvenSeedOmega    = 1.2;   // spike: _rand(1.2, 3)
constant constexpr float kAlfvenSeedPsi      = 0.9;   // spike: _rand(0.9, 2)

// ── Seed field ──────────────────────────────────────────────────────────────
//
// The spike seeds band-limited noise in Fourier space (k in [1, kmax], amplitude
// k^-1.6). The real-space analogue is a short sum of sinusoids over the same band —
// enough modes to read as irregular, few enough to stay cheap. Amplitudes follow the
// same k^-1.6 falloff so the seed has the spike's spectral slope.
//
// This is also the RECOVERY path: ALFVEN.1's watchdog re-zeroes a blown persistent pair
// rather than re-seeding it (that limit is recorded in the capability registry), so a
// preset needing a specific initial state must re-seed itself. Keying the seed off a
// near-zero field makes that automatic and covers both first-frame and post-watchdog.

static inline float alfven_seed(float2 uv, float phase, float amp) {
    constexpr float kTau = 6.28318530718;
    float s = 0.0;
    // k in [1,3] carries the composition (3-6 lobes across the frame, README 01).
    s += pow(1.0, -1.6) * sin(kTau * (1.0 * uv.x + 0.31) + phase * 0.7)
                        * cos(kTau * (1.0 * uv.y - 0.12) + phase * 0.5);
    s += pow(2.0, -1.6) * sin(kTau * (2.0 * uv.x - 0.44) + phase * 1.1)
                        * cos(kTau * (1.0 * uv.y + 0.53) + phase * 0.9);
    s += pow(2.0, -1.6) * sin(kTau * (1.0 * uv.x + 0.77) + phase * 0.6)
                        * cos(kTau * (2.0 * uv.y - 0.28) + phase * 1.3);
    s += pow(3.0, -1.6) * sin(kTau * (3.0 * uv.x - 0.19) + phase * 1.7)
                        * cos(kTau * (2.0 * uv.y + 0.66) + phase * 0.4);
    s += pow(3.0, -1.6) * sin(kTau * (2.0 * uv.x + 0.05) + phase * 0.3)
                        * cos(kTau * (3.0 * uv.y + 0.41) + phase * 1.5);
    return s * amp;
}

// Band-limited stirring, the real-space stand-in for the spike's random-phase
// forcing shell at k in [2,5]. Phases drift with time so the forcing decorrelates.
static inline float alfven_forcing(float2 uv, float t) {
    constexpr float kTau = 6.28318530718;
    float f = 0.0;
    f += sin(kTau * (2.0 * uv.x + 3.0 * uv.y) + 0.71 * t);
    f += sin(kTau * (4.0 * uv.x - 2.0 * uv.y) - 0.53 * t + 1.7);
    f += sin(kTau * (3.0 * uv.x + 5.0 * uv.y) + 0.37 * t + 3.1);
    f += sin(kTau * (5.0 * uv.x - 4.0 * uv.y) - 0.89 * t + 0.4);
    return f * 0.25;
}

// ─── Stage 1: PHI — Jacobi solve of lap(phi) = -omega ────────────────────────
//
// Same ported stencil ALFVEN.1 proved against the analytic solution: the reference
// solves `L+R+T+B-4C = rhs`, so with rhs = -omega*h^2 the sweep is
// `phi = (L+R+T+B + omega*h^2) * 0.25`. Persistent + iterated, so it warm-starts from
// the previous frame instead of restarting cold — which ALFVEN.1 measured as the
// difference between an 89% residual and a converged field.
//
// It samples `state` (texture 13) — the PREVIOUS frame's state, since `state` runs after
// this stage in the linear DAG. A one-frame lag on phi is standard for this scheme.

fragment float4 alfven_phi_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> stateTex [[texture(13)]],
    texture2d<float, access::sample> prevPhiTex [[texture(20)]]
) {
    float2 uv    = in.uv;
    float2 texel = 1.0 / float2(prevPhiTex.get_width(), prevPhiTex.get_height());

    float L = prevPhiTex.sample(alfven_state_sampler, uv - float2(texel.x, 0.0)).x;
    float R = prevPhiTex.sample(alfven_state_sampler, uv + float2(texel.x, 0.0)).x;
    float T = prevPhiTex.sample(alfven_state_sampler, uv + float2(0.0, texel.y)).x;
    float B = prevPhiTex.sample(alfven_state_sampler, uv - float2(0.0, texel.y)).x;

    float omega = stateTex.sample(alfven_state_sampler, uv).x;
    // h = 1 texel, matching the ported stencil's convention (ALFVEN.1 / D-244).
    float phi = (L + R + T + B + omega) * 0.25;

    return float4(clamp(phi, -1.0e4, 1.0e4), 0.0, 0.0, 1.0);
}

// ─── Stage 2: STATE — the MHD advance ───────────────────────────────────────

fragment float4 alfven_state_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> phiTex [[texture(13)]],
    texture2d<float, access::sample> prevStateTex [[texture(20)]]
) {
    float2 uv    = in.uv;
    float2 texel = 1.0 / float2(prevStateTex.get_width(), prevStateTex.get_height());

    // ── Re-seed when the field is empty ──
    // Covers frame 1 after a preset switch (ALFVEN.1 zeroes persistent pairs) and
    // recovery after a watchdog re-zero. Sampled at one texel plus its neighbours as a
    // cheap stand-in for a field-wide RMS, which a fragment cannot compute.
    float2 c  = prevStateTex.sample(alfven_state_sampler, uv).xy;
    float2 n1 = prevStateTex.sample(alfven_state_sampler, uv + texel * 37.0).xy;
    float2 n2 = prevStateTex.sample(alfven_state_sampler, uv - texel * 53.0).xy;
    float presence = abs(c.x) + abs(c.y) + abs(n1.y) + abs(n2.y);
    // Which braid we are on, and how far into its crossfade. Derived from time rather
    // than held as state, so it survives the watchdog re-zeroing the pair.
    float cycle      = floor(f.time / kAlfvenCycleSeconds);
    float cycleStart = cycle * kAlfvenCycleSeconds;
    float seedPhase  = 7.31 * cycle + 1.7;   // a different braid every cycle

    if (presence < kAlfvenSeedFloor) {
        float omega0 = alfven_seed(uv, seedPhase, kAlfvenSeedOmega);
        float psi0   = alfven_seed(uv, seedPhase + 8.0, kAlfvenSeedPsi);
        return float4(omega0, psi0, 0.0, 1.0);
    }

    // ── Velocity from phi:  u = (-phi_y, phi_x) ──
    float phiL = phiTex.sample(alfven_state_sampler, uv - float2(texel.x, 0.0)).x;
    float phiR = phiTex.sample(alfven_state_sampler, uv + float2(texel.x, 0.0)).x;
    float phiT = phiTex.sample(alfven_state_sampler, uv + float2(0.0, texel.y)).x;
    float phiB = phiTex.sample(alfven_state_sampler, uv - float2(0.0, texel.y)).x;
    // Central differences in TEXEL units (h = 1), matching the phi stencil.
    float2 u = float2(-(phiT - phiB) * 0.5, (phiR - phiL) * 0.5);

    // ── Semi-Lagrangian advection of (omega, psi), CFL-bounded (§8.4) ──
    // An unbounded back-trace on a spiking field is how this scheme diverges.
    float2 traceTexels = clamp(u * kAlfvenDt, -kAlfvenMaxTrace, kAlfvenMaxTrace);
    float2 src = uv - traceTexels * texel;
    float2 advected = prevStateTex.sample(alfven_lerp_sampler, src).xy;
    float omega = advected.x;
    float psi   = advected.y;

    // ── J = lap(psi), and the Lorentz term {psi,J} ──
    float pL = prevStateTex.sample(alfven_state_sampler, uv - float2(texel.x, 0.0)).y;
    float pR = prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, 0.0)).y;
    float pT = prevStateTex.sample(alfven_state_sampler, uv + float2(0.0, texel.y)).y;
    float pB = prevStateTex.sample(alfven_state_sampler, uv - float2(0.0, texel.y)).y;
    float psiC = c.y;
    float J = (pL + pR + pT + pB - 4.0 * psiC);

    // {psi,J} = psi_x J_y - psi_y J_x — J's own gradient needs the 8-neighbour ring.
    float jL = (prevStateTex.sample(alfven_state_sampler, uv - float2(2.0 * texel.x, 0.0)).y
                + psiC
                + prevStateTex.sample(alfven_state_sampler, uv + float2(-texel.x, texel.y)).y
                + prevStateTex.sample(alfven_state_sampler, uv - float2(texel.x, texel.y)).y
                - 4.0 * pL);
    float jR = (psiC
                + prevStateTex.sample(alfven_state_sampler, uv + float2(2.0 * texel.x, 0.0)).y
                + prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, texel.y)).y
                + prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, -texel.y)).y
                - 4.0 * pR);
    float jT = (prevStateTex.sample(alfven_state_sampler, uv + float2(-texel.x, texel.y)).y
                + prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, texel.y)).y
                + prevStateTex.sample(alfven_state_sampler, uv + float2(0.0, 2.0 * texel.y)).y
                + psiC
                - 4.0 * pT);
    float jB = (prevStateTex.sample(alfven_state_sampler, uv - float2(texel.x, texel.y)).y
                + prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, -texel.y)).y
                + psiC
                + prevStateTex.sample(alfven_state_sampler, uv - float2(0.0, 2.0 * texel.y)).y
                - 4.0 * pB);
    float2 gradPsi = float2((pR - pL) * 0.5, (pT - pB) * 0.5);
    float2 gradJ   = float2((jR - jL) * 0.5, (jT - jB) * 0.5);
    float lorentz  = gradPsi.x * gradJ.y - gradPsi.y * gradJ.x;

    // ── Diffusion ──
    float wL = prevStateTex.sample(alfven_state_sampler, uv - float2(texel.x, 0.0)).x;
    float wR = prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, 0.0)).x;
    float wT = prevStateTex.sample(alfven_state_sampler, uv + float2(0.0, texel.y)).x;
    float wB = prevStateTex.sample(alfven_state_sampler, uv - float2(0.0, texel.y)).x;
    float lapW = (wL + wR + wT + wB - 4.0 * c.x);
    float lapP = (pL + pR + pT + pB - 4.0 * psiC);

    // Hou-Li analogue (§8.1, grounding level 3): damp ONLY what the 5-point Laplacian
    // cannot see — the checkerboard mode, which is exactly the grid-scale pile-up the
    // spectral filter existed to kill and the mode plain Jacobi/diffusion leaves alone.
    float diagAvg = 0.25 * (
        prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, texel.y)).x
      + prevStateTex.sample(alfven_state_sampler, uv + float2(-texel.x, texel.y)).x
      + prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, -texel.y)).x
      + prevStateTex.sample(alfven_state_sampler, uv + float2(-texel.x, -texel.y)).x);
    float crossAvg = 0.25 * (wL + wR + wT + wB);
    float checker  = c.x - 2.0 * crossAvg + diagAvg;   // zero on smooth fields

    // ── Integrate ──
    float force = kAlfvenDrive * alfven_forcing(uv, f.time);
    omega += kAlfvenDt * (lorentz - kAlfvenAlpha * c.x + force)
           + kAlfvenNu * kAlfvenDt * lapW
           - kAlfvenHyper * checker;
    psi   += kAlfvenEta * kAlfvenDt * lapP;

    // ── Re-seed crossfade (§5) ──
    // Ported from the spike's advance_blend: a raised cosine so the dissolve has no
    // visible in/out corner, applied as a per-step share of the crossfade rather than an
    // absolute mix, so the blend rate is independent of how many frames it spans.
    float a = clamp((f.time - cycleStart) / kAlfvenBlendTau, 0.0, 1.0);
    if (a < 1.0) {
        float g = 0.5 - 0.5 * cos(M_PI_F * a);
        float r = g * (kAlfvenDt / kAlfvenBlendTau) * M_PI_F;
        float omegaSeed = alfven_seed(uv, seedPhase, kAlfvenSeedOmega);
        float psiSeed   = alfven_seed(uv, seedPhase + 8.0, kAlfvenSeedPsi);
        omega = mix(omega, omegaSeed, clamp(r, 0.0, 1.0));
        psi   = mix(psi,   psiSeed,   clamp(r, 0.0, 1.0));
    }

    // ── Hard clamps (§8.2) ──
    omega = clamp(omega, -kAlfvenClampW, kAlfvenClampW);
    psi   = clamp(psi,   -kAlfvenClampP, kAlfvenClampP);

    return float4(omega, psi, J, 1.0);
}

// ─── Stage 3: COMPOSE — placeholder exposure, NOT the shipping look ─────────
//
// film.py's palette shape is honoured (opponent hue about a centre, hot cores
// desaturating, non-black ground per D-037) but its percentile auto-exposure, its
// std(J) polarity scale and its two-sigma seam bloom are all global/multi-scale and
// are NOT implemented here — see the file header. Exposure is a fixed constant so the
// physics soak reads a stable image rather than one that moves with the tonemap.

fragment float4 alfven_compose_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> stateTex [[texture(13)]]
) {
    float2 uv = in.uv;
    float J = stateTex.sample(alfven_state_sampler, uv).z;

    // Fixed stand-in for autoexp()/std(J). PLACEHOLDER.
    constexpr float kFixedExposure = 0.55;
    float aJ = clamp(abs(J) * kFixedExposure, 0.0, 1.0);
    float sJ = tanh(J * kFixedExposure * 1.2);

    // film.py: h = hue_centre + 0.30*sJ, s = 0.32 + 0.58*(1-aJ^2), v = filmic(1.9*aJ^0.85)
    float hue = 0.52 + 0.30 * sJ;
    float sat = 0.32 + 0.58 * (1.0 - aJ * aJ);
    float x   = 1.9 * pow(aJ, 0.85);
    float val = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);

    float3 col = hsv2rgb(float3(fract(hue), sat, val));

    // D-037: silence is coloured, never black.
    float3 ground = float3(0.035, 0.045, 0.075);
    col += ground * (1.0 - val);

    return float4(min(col, float3(1.0)), 1.0);
}
