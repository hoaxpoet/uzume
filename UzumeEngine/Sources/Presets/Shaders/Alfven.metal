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

// ── Catmull-Rom advection sampling ──────────────────────────────────────────
//
// WHY, measured. A negative control (advection disabled, everything else identical)
// isolated the semi-Lagrangian BILINEAR interpolation as the dominant loss of psi:
// over 900 frames psi RMS fell 10.6% with advection on and only 1.3% with it off, so
// interpolation accounts for ~9 of the ~10 points. The explicit eta = 0.5 term accounts
// for the rest, matching the arithmetic (a k=2 mode loses ~2.6% over a 22 s cycle).
//
// Advection is BOTH the engine and the leak — with it on, jRMS climbs to 0.0128; with it
// off, J never forms at all (0.0011, flat), because current sheets only exist where the
// flow stretches psi. So the lever is not less advection but less diffusion per unit
// stretching, which is the option §11 names: "reduce projection diffusion (BFECC /
// MacCormack advection)".
//
// Catmull-Rom is the cheap end of that lever and needs no extra stage: a cubic filter
// over the 4x4 neighbourhood, third-order accurate against bilinear's first-order, so it
// removes most of the per-step smoothing while staying a single-pass local read. If this
// is not enough, the next step up is a true MacCormack corrector, which needs the
// forward-advected field as its own staged pass. Standard formulation (Catmull-Rom
// spline weights); the same filter Selle et al. 2008 use as the base for MacCormack.
static inline float2 alfven_sample_catrom(texture2d<float, access::sample> tex,
                                          float2 uv, float2 texel) {
    float2 coord = uv / texel - 0.5;
    float2 base  = floor(coord);
    float2 t     = coord - base;
    float2 t2 = t * t;
    float2 t3 = t2 * t;
    // Catmull-Rom basis (tension 0.5).
    float2 w0 = -0.5 * t3 + t2 - 0.5 * t;
    float2 w1 =  1.5 * t3 - 2.5 * t2 + 1.0;
    float2 w2 = -1.5 * t3 + 2.0 * t2 + 0.5 * t;
    float2 w3 =  0.5 * t3 - 0.5 * t2;

    float2 acc = float2(0.0);
    float wx[4] = { w0.x, w1.x, w2.x, w3.x };
    float wy[4] = { w0.y, w1.y, w2.y, w3.y };
    for (int j = 0; j < 4; ++j) {
        for (int i = 0; i < 4; ++i) {
            float2 tap = (base + float2(float(i) - 1.0, float(j) - 1.0) + 0.5) * texel;
            acc += tex.sample(alfven_state_sampler, tap).xy * (wx[i] * wy[j]);
        }
    }
    return acc;
}

// ── Tunables ────────────────────────────────────────────────────────────────
// Spelled as named constants so the soak can move one at a time. Values are the
// spike's where the spike has one (alpha 0.16, forcing shell k in [2,5]).
// SUBSTEP timestep, not the frame time. Restoring the Lorentz coupling made the Alfven
// wave speed the binding CFL constraint, and one step of 0.016 s per frame pinned omega at
// its clamp (measured: omegaMax 24.0, wRMS ~21). The spike runs dt <= 0.005 with many
// substeps per output frame; we do the same by giving the `state` stage `iterations: 8`,
// which is exactly what ALFVEN.1's iterated-stage surface is for. 0.016/8 = 0.002 sits
// inside the spike's bound. Fixed, never the render dt (BUG-097).
constant constexpr float kAlfvenDt        = 0.002;
constant constexpr int   kAlfvenSubsteps  = 8;      // must match the sidecar's iterations
constant constexpr float kAlfvenAlpha     = 0.16;   // linear drag on omega (spike value)
constant constexpr float kAlfvenNu        = 0.9;    // omega diffusion, texel^2 units
constant constexpr float kAlfvenEta       = 0.5;    // psi diffusion
// Grid-scale damping expressed as a RATE (per second), not a per-step fraction. Every
// other term here carries `* dt`; these did not, so introducing substeps multiplied the
// damping by the substep count and collapsed psi from 0.90 to 0.046 in a single soak. The
// rates reproduce the previously-tuned per-FRAME fractions (0.35 and 0.30 at 1/0.016 s)
// independently of how many substeps a frame is split into.
constant constexpr float kAlfvenHyperRate    = 0.35 / 0.016;   // omega, Hou-Li analogue
// ...and on psi — the spike filters BOTH (alfven.py:104-105). Applied through a 3x3 tent
// high-pass whose eigenvalue is 1 on the checkerboard and falls smoothly to 0 on smooth
// fields, so h is a direct per-step damping fraction of the top of the spectrum and is
// stable for any h <= 1.
constant constexpr float kAlfvenHyperPsiRate = 0.30 / 0.016;   // psi — the spike filters BOTH
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
constant constexpr int   kAlfvenSeedKOmega   = 3;     // spike: _rand(_, 3)
constant constexpr int   kAlfvenSeedKPsi     = 2;     // spike: _rand(_, 2)

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

// Deterministic per-mode phase. Standard hash; only needs to decorrelate modes.
static inline float alfven_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Band-limited random-phase seed over INTEGER wavevectors.
//
// The spike seeds in Fourier space: random phase per mode on an annulus 1 <= |k| <= kmax,
// amplitude k^-1.6, normalised to std = amp. The first port approximated that with five
// separable sin(x)*cos(y) products, which is inherently symmetric under reflection and
// produced a visible 4-fold cross late in the arc — the "never a regular grid, never
// radially symmetric" anti-reference in the reference README.
//
// This sums plane waves over integer (m,n) instead, so wavevectors point at arbitrary
// angles rather than along the axes, with an independent hashed phase per mode. Integer
// (m,n) keeps the field periodic on the unit box, which `address::repeat` requires.
// Amplitudes follow the spike's k^-1.6, and the sum is normalised by its own analytic RMS
// (sqrt(sum a^2 / 2) for random phases) so `amp` means what it means in the spike.
static inline float alfven_seed_band(float2 uv, float seedPhase, float amp, int kmax) {
    constexpr float kTau = 6.28318530718;
    float s = 0.0;
    float norm = 0.0;
    // Half-plane only: the field is real, so (m,n) and (-m,-n) are the same mode.
    for (int m = -kmax; m <= kmax; ++m) {
        for (int n = 0; n <= kmax; ++n) {
            if (n == 0 && m <= 0) { continue; }      // skip DC and the duplicate half-row
            float k2 = float(m * m + n * n);
            if (k2 < 1.0 || k2 > float(kmax * kmax)) { continue; }
            float a = pow(k2, -0.8);                  // k^-1.6
            float ph = kTau * alfven_hash(float2(float(m), float(n)) + seedPhase);
            s += a * sin(kTau * (float(m) * uv.x + float(n) * uv.y) + ph);
            norm += a * a * 0.5;
        }
    }
    return s * amp / sqrt(max(norm, 1e-9));
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
        float omega0 = alfven_seed_band(uv, seedPhase, kAlfvenSeedOmega, kAlfvenSeedKOmega);
        float psi0   = alfven_seed_band(uv, seedPhase + 8.0, kAlfvenSeedPsi, kAlfvenSeedKPsi);
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
    // Cubic rather than bilinear — the measured fix for the interpolation loss above.
    float2 advected = alfven_sample_catrom(prevStateTex, src, texel);
    // Catmull-Rom can overshoot at a sharp front; clamp to the bilinear neighbourhood so
    // a current sheet cannot ring into a new extremum and seed an instability.
    float2 lin = prevStateTex.sample(alfven_lerp_sampler, src).xy;
    float2 lo = min(lin, advected), hi = max(lin, advected);
    advected = clamp(advected, lo - abs(lin) - 1.0e-3, hi + abs(lin) + 1.0e-3);
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

    // UNIT SCALING — the Lorentz term is the one place this port silently lost its
    // physics. Every derivative above is in TEXEL units (h = 1), so:
    //     J_texel       = lap_texel(psi)          = h^2 * lap_phys(psi)
    //     gradPsi_texel = h   * grad_phys(psi)
    //     gradJ_texel   = h^3 * grad_phys(J_phys)
    // and therefore the texel-space bracket is h^4 times the physical {psi,J}. With the
    // spike's 2*pi box, h = 2*pi/N = 0.0245 at N = 256, so h^4 = 3.6e-7: the term came out
    // 2.45e-5 of the drag term, i.e. ZERO. Without it there is no Lorentz force, no
    // reconnection, and no "M" in MHD — the preset was advecting two passive scalars.
    //
    // h is derived from the texture width rather than hardcoded, because staged textures
    // are drawable-sized. Note the consequence: 1/h^4 grows as N^4, so the Alfven-wave CFL
    // limit tightens fast with resolution — this term, not the flow speed, is what sets
    // the stable timestep.
    float h = 6.28318530718 / float(prevStateTex.get_width());
    float invH4 = 1.0 / (h * h * h * h);
    float lorentz = (gradPsi.x * gradJ.y - gradPsi.y * gradJ.x) * invH4;

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

    // The same operator on psi. The spike applies FILT to BOTH w and p (alfven.py:104-105);
    // the first port applied it only to omega, leaving psi with NO grid-scale filter at
    // all. That omission is what let psi sharpen to texel-scale gradients, and since
    // J = lap(psi) those gradients become |J| spikes ~1000x the smooth background — which
    // autoexp then normalises against, crushing the broad lobes to black. The references
    // have the opposite topology: in `05_atmosphere_relaxed_state.png` whole lobes are
    // BRIGHT and only the sign-change lines are dark, i.e. |J| is large and smooth across
    // the field. Filtering psi is what produces that.
    float pDiagAvg = 0.25 * (
        prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, texel.y)).y
      + prevStateTex.sample(alfven_state_sampler, uv + float2(-texel.x, texel.y)).y
      + prevStateTex.sample(alfven_state_sampler, uv + float2(texel.x, -texel.y)).y
      + prevStateTex.sample(alfven_state_sampler, uv + float2(-texel.x, -texel.y)).y);
    // A BAND high-pass, not the checkerboard operator. Measured: damping only the exact
    // k = k_max mode (eigenvalue-4 operator, h = 0.2) left the |J| dynamic range at 1518x
    // versus 1613x undamped — no effect, because a thin current sheet is a few texels
    // wide, not one. The spike's FILT = exp(-36 (k/kmax)^36) is ~1 below 0.85 k_max and
    // ~0 above, i.e. it removes a BAND. The real-space analogue of that is
    // `psi - blur(psi)` with a 3x3 tent: eigenvalue 1 on the checkerboard, falling
    // smoothly to 0 on smooth fields, so it damps the whole top of the spectrum and is
    // unconditionally stable for h <= 1.
    float pTent = (4.0 * psiC + 2.0 * (pL + pR + pT + pB) + 4.0 * pDiagAvg) / 16.0;
    float pHighPass = psiC - pTent;

    // ── Integrate ──
    float force = kAlfvenDrive * alfven_forcing(uv, f.time);
    omega += kAlfvenDt * (lorentz - kAlfvenAlpha * c.x + force)
           + kAlfvenNu * kAlfvenDt * lapW
           - kAlfvenHyperRate * kAlfvenDt * checker;
    psi   += kAlfvenEta * kAlfvenDt * lapP - kAlfvenHyperPsiRate * kAlfvenDt * pHighPass;

    // ── Re-seed crossfade (§5) ──
    // Ported from the spike's advance_blend: a raised cosine so the dissolve has no
    // visible in/out corner, applied as a per-step share of the crossfade rather than an
    // absolute mix, so the blend rate is independent of how many frames it spans.
    float a = clamp((f.time - cycleStart) / kAlfvenBlendTau, 0.0, 1.0);
    if (a < 1.0) {
        float g = 0.5 - 0.5 * cos(M_PI_F * a);
        float r = g * (kAlfvenDt / kAlfvenBlendTau) * M_PI_F;
        float omegaSeed = alfven_seed_band(uv, seedPhase, kAlfvenSeedOmega, kAlfvenSeedKOmega);
        float psiSeed   = alfven_seed_band(uv, seedPhase + 8.0, kAlfvenSeedPsi, kAlfvenSeedKPsi);
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
