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
constant constexpr float kAlfvenDt        = 0.016;
// NOTE: the `state` stage must run ONCE per frame. Substepping is invalid in this
// architecture: the four derivative spectra are computed once per frame upstream, so
// substeps 2..N would evaluate the brackets against STALE derivatives. Measured — 8
// substeps collapsed psi 0.90 -> 0.049 while appearing to "improve" omega, because the
// stale RHS suppressed growth rather than resolving it.
constant constexpr int   kAlfvenSubsteps  = 1;
constant constexpr float kAlfvenAlphaW    = 0.16;   // linear drag on omega (spike value),
                                                    // now applied via the integrating factor
constant constexpr float kAlfvenNu4       = 2.5e-7; // k^4 hyperdiffusion (spike's nu4)
constant constexpr float kAlfvenSpectralCutoff = 100.0;  // ~0.85x => effective k_max ~35
constant constexpr float kAlfvenNu        = 0.002;  // omega diffusion, PHYSICAL units
                                                    // (was 0.9 in texel^2; derivatives are
                                                    // physical now and the spectral filter
                                                    // carries the grid-scale load)
constant constexpr float kAlfvenEta       = 0.001;  // psi diffusion, PHYSICAL units
// Grid-scale damping expressed as a RATE (per second), not a per-step fraction. Every
// other term here carries `* dt`; these did not, so introducing substeps multiplied the
// damping by the substep count and collapsed psi from 0.90 to 0.046 in a single soak. The
// rates reproduce the previously-tuned per-FRAME fractions (0.35 and 0.30 at 1/0.016 s)
// independently of how many substeps a frame is split into.
constant constexpr float kAlfvenHyperRate    = 0.35 / 0.016;   // omega, Hou-Li analogue
// psi hyperdiffusion coefficient — the spike's `nu4 * k^4` (alfven.py), applied as a rate.
// Sized so the per-FRAME damping at the checkerboard (discrete biharmonic response 64) is
// ~0.30, matching the grid-scale control the tent achieved, while touching mid-k ~3x less:
//   0.30 = nu4 * dt_frame * 64  =>  nu4 ~ 0.29
constant constexpr float kAlfvenNu4Psi    = 0.29;
constant constexpr float kAlfvenDrive     = 0.020;  // forcing amplitude (spike: 0.020 * ...)
constant constexpr float kAlfvenMaxTrace  = 3.0;    // CFL: max back-trace, texels (§8.4)
constant constexpr float kAlfvenClampW    = 24.0;   // hard clamp on omega (§8.2)
constant constexpr float kAlfvenClampP    = 12.0;   // hard clamp on psi
constant constexpr float kAlfvenSeedFloor = 0.02;   // below this |psi| RMS proxy, re-seed
constant constexpr float kAlfvenHueCentre = 0.72;   // late/magenta-teal end (Matt, 2026-09-09)
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


// ─── Spectral stabiliser (ALFVEN.1c) ────────────────────────────────────────
//
// The Hou-Li filter, applied where it belongs. ALFVEN.2 measured that no local operator
// reproduces it — the 3x3 tent leaves mid-k at 0.75 and the biharmonic at 0.25, so both
// eat the band the lobes live in, and J came out ~100x the reference either way. In
// k-space the same filter leaves low-k at 1.000000 and kills the Nyquist corner to
// 3.5e-21 (FFTSandboxTests). Transform helpers live in the shared preamble.
//
// The chain runs on the PREVIOUS frame's psi and the `state` stage picks the filtered
// result up on its first substep — one frame of lag, which is standard for this scheme.

fragment float4 alfven_fft_rows_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> stateTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(stateTex.get_width());
    int j, wing; float angle;
    uz_fft_indices(int(gid.x), p.index, j, wing, angle);
    float2 a, b;
    if (p.index == 0) {
        // BOTH fields in one transform: omega as the real part, psi as the imaginary
        // part. The filter is real and the DFT is linear, so filtering the complex field
        // (omega + i*psi) filters the two independently and exactly — one chain, not two.
        // The spike filters both w and p (alfven.py:104-105); filtering only psi left
        // omega free to cascade, which measured as an effective k ~ 19 in J while the
        // filter's cutoff sits at k ~ 109, i.e. it never saw the energy that mattered.
        a = stateTex.read(uint2(uint(j), gid.y)).xy;
        b = stateTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    } else {
        a = prevTex.read(uint2(uint(j), gid.y)).xy;
        b = prevTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    }
    return float4(uz_fft_combine(a, b, angle, wing, true), 0.0, 1.0);
}

fragment float4 alfven_fft_cols_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_height());
    int j, wing; float angle;
    uz_fft_indices(int(gid.y), p.index, j, wing, angle);
    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(gid.x, uint(j))).xy;
        b = inputTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    } else {
        a = prevTex.read(uint2(gid.x, uint(j))).xy;
        b = prevTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    }
    return float4(uz_fft_combine(a, b, angle, wing, true), 0.0, 1.0);
}

fragment float4 alfven_fft_filter_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    int w = int(specTex.get_width()), h = int(specTex.get_height());
    float2 k = uz_wavenumber(gid, w, h);
    float k2 = dot(k, k);

    // INTEGRATING FACTOR, the spike's Ew/Ep (alfven.py `step`): exp(-(nu4 k^4 + alpha) dt).
    //
    // This is the damping the port was missing, and it is what makes an explicit scheme
    // survive here at all. Alfven waves are purely oscillatory, and BOTH Euler and Heun
    // are unconditionally unstable on the imaginary axis — |R(iy)| = sqrt(1 + y^4/4) > 1
    // for Heun — so no explicit integrator fixes this on its own. What the spike relies on
    // is k^4 damping that bites precisely where the oscillation is fastest: at N = 256 it
    // is x1.0000 per frame at k = 2 and x0.81 at k = 85, i.e. invisible to the lobes and
    // strong at the grid scale. Design §4 descoped it to plain `nu lap`, which is
    // negligible at high k; that descope is what left the scheme unstable.
    //
    // Applied here rather than inside the step because the spectrum is already computed:
    // it costs nothing, and once per frame is the right cadence for a per-frame dt.
    // omega and psi need DIFFERENT factors — the spike has Ew = exp(-(nu4 k^4 + alpha) dt)
    // but Ep = exp(-nu4 k^4 dt), i.e. only omega carries the linear drag. They ride one
    // packed transform, so unpack, scale separately, repack. Applying omega's drag to psi
    // as well decayed psi 0.90 -> 0.076 over a soak: psi has no drag term in the equations
    // at all, and the reference conserves it.
    uint2 mir = uint2(uint((w - int(gid.x)) % w), uint((h - int(gid.y)) % h));
    float2 omegaH, psiH;
    uz_unpack_pair(specTex.read(gid).xy, specTex.read(mir).xy, omegaH, psiH);

    // Hou-Li shape, but the cutoff is chosen from OUR CFL limit rather than copied from
    // the spike's. The spike's cutoff (~0.85 * N/2 = 109) is matched to its adaptive
    // dt ~ 0.0027; at our fixed dt = 0.016 the Alfven CFL dt*k*B stays below ~1 only for
    // k < ~35, and above that an explicit scheme grows the mode faster than any k^4
    // damping removes it. Band-limiting to the stable range is the honest alternative to
    // pretending the timestep is smaller than it is.
    float kr    = clamp(sqrt(k2) / kAlfvenSpectralCutoff, 0.0, 1.0);
    float filt  = exp(-36.0 * pow(kr, 36.0));
    float hyper = exp(-kAlfvenNu4 * k2 * k2 * kAlfvenDt);
    omegaH *= filt * hyper * exp(-kAlfvenAlphaW * kAlfvenDt);
    psiH   *= filt * hyper;

    // Repack: F = omega_h + i * psi_h.
    return float4(omegaH.x - psiH.y, omegaH.y + psiH.x, 0.0, 1.0);
}

fragment float4 alfven_ifft_cols_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_height());
    int j, wing; float angle;
    uz_fft_indices(int(gid.y), p.index, j, wing, angle);
    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(gid.x, uint(j))).xy;
        b = inputTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    } else {
        a = prevTex.read(uint2(gid.x, uint(j))).xy;
        b = prevTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    }
    float2 r = uz_fft_combine(a, b, angle, wing, false);
    if (p.index == p.count - 1) { r /= float(n); }
    return float4(r, 0.0, 1.0);
}

fragment float4 alfven_ifft_rows_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_width());
    int j, wing; float angle;
    uz_fft_indices(int(gid.x), p.index, j, wing, angle);
    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(uint(j), gid.y)).xy;
        b = inputTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    } else {
        a = prevTex.read(uint2(uint(j), gid.y)).xy;
        b = prevTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    }
    float2 r = uz_fft_combine(a, b, angle, wing, false);
    if (p.index == p.count - 1) { r /= float(n); }
    return float4(r, 0.0, 1.0);
}

// ─── Derivative spectra for the spectral Poisson brackets ───────────────────
//
// ALFVEN.2 established by measurement that the semi-Lagrangian back-trace was the
// non-conservative term: it drove omega to saturation and psi to decay, and it ran the
// <psi^2> cascade UP in k when 2D MHD inverse-cascades it DOWN (Biskamp ch. 7). No
// filter fixes a cascade direction. So the advection is replaced outright by the spike's
// own formulation — Poisson brackets evaluated with spectral derivatives:
//
//     d_t omega = -{phi,omega} + {psi,J} - alpha omega + nu lap(omega) + f
//     d_t psi   = -{phi,psi}              + eta lap(psi)
//     {a,b}     = a_x b_y - a_y b_x
//
// Each stage below emits the spectrum of (a_x + i a_y) for one field, so ONE inverse
// transform yields both of that field's partials. Four fields — phi, omega, psi, J — is
// four transforms, and all four spectra derive from the single packed (omega + i psi)
// transform already computed upstream.

static inline void alfven_field_spectra(texture2d<float, access::read> specTex, uint2 gid,
                                        thread float2& omegaH, thread float2& psiH,
                                        thread float2& k) {
    int w = int(specTex.get_width()), h = int(specTex.get_height());
    uint2 mir = uint2(uint((w - int(gid.x)) % w), uint((h - int(gid.y)) % h));
    uz_unpack_pair(specTex.read(gid).xy, specTex.read(mir).xy, omegaH, psiH);
    k = uz_wavenumber(gid, w, h);
}

fragment float4 alfven_grad_phi_fragment(
    VertexOut in [[stage_in]], constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    float2 omegaH, psiH, k;
    alfven_field_spectra(specTex, gid, omegaH, psiH, k);
    // lap(phi) = -omega  =>  phi_h = omega_h / k^2, the exact Poisson solve.
    float k2 = dot(k, k);
    float2 phiH = (k2 < 0.5) ? float2(0.0) : omegaH / k2;
    return float4(uz_grad_spectrum(phiH, k), 0.0, 1.0);
}

fragment float4 alfven_grad_omega_fragment(
    VertexOut in [[stage_in]], constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    float2 omegaH, psiH, k;
    alfven_field_spectra(specTex, gid, omegaH, psiH, k);
    return float4(uz_grad_spectrum(omegaH, k), 0.0, 1.0);
}

fragment float4 alfven_grad_psi_fragment(
    VertexOut in [[stage_in]], constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    float2 omegaH, psiH, k;
    alfven_field_spectra(specTex, gid, omegaH, psiH, k);
    return float4(uz_grad_spectrum(psiH, k), 0.0, 1.0);
}

fragment float4 alfven_grad_j_fragment(
    VertexOut in [[stage_in]], constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    float2 omegaH, psiH, k;
    alfven_field_spectra(specTex, gid, omegaH, psiH, k);
    // J = lap(psi)  =>  J_h = -k^2 psi_h.
    return float4(uz_grad_spectrum(-dot(k, k) * psiH, k), 0.0, 1.0);
}

// ─── Nonlinear terms: brackets, then DEALIASED ─────────────────────────────
//
// The brackets are quadratic products formed in real space, so they alias. The spike
// masks every bracket with the Orszag 2/3 rule (alfven.py:79); omitting it left aliased
// energy accumulating across the spectrum and was measured as omega pinned at its clamp
// with psi's energy sitting at k~15 instead of k~2.
//
// So the two nonlinear terms are evaluated here, packed as one complex field
// (d_omega_nl + i*d_psi_nl), transformed, masked, and transformed back before `state`
// integrates them. Packing means one transform pair covers both.

fragment float4 alfven_brackets_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::sample> gradPhiTex [[texture(13)]],
    texture2d<float, access::sample> gradOmegaTex [[texture(14)]],
    texture2d<float, access::sample> gradPsiTex [[texture(15)]],
    texture2d<float, access::sample> gradJTex [[texture(16)]]
) {
    float2 uv = in.uv;
    // Spectral derivatives: .x = d/dx, .y = d/dy.
    float2 gPhi   = gradPhiTex.sample(alfven_state_sampler, uv).xy;
    float2 gOmega = gradOmegaTex.sample(alfven_state_sampler, uv).xy;
    float2 gPsi   = gradPsiTex.sample(alfven_state_sampler, uv).xy;
    float2 gJ     = gradJTex.sample(alfven_state_sampler, uv).xy;

    // {a,b} = a_x b_y - a_y b_x
    float brPhiOmega = gPhi.x * gOmega.y - gPhi.y * gOmega.x;
    float brPsiJ     = gPsi.x * gJ.y     - gPsi.y * gJ.x;
    float brPhiPsi   = gPhi.x * gPsi.y   - gPhi.y * gPsi.x;

    // omega's nonlinear term as the real part, psi's as the imaginary part.
    return float4(-brPhiOmega + brPsiJ, -brPhiPsi, 0.0, 1.0);
}

/// Forward FFT rows for a field already packed as complex in .xy (the brackets), as
/// distinct from the state transform which lifts psi out of .g.
fragment float4 alfven_fft_rows_xy_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_width());
    int j, wing; float angle;
    uz_fft_indices(int(gid.x), p.index, j, wing, angle);
    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(uint(j), gid.y)).xy;
        b = inputTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    } else {
        a = prevTex.read(uint2(uint(j), gid.y)).xy;
        b = prevTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    }
    return float4(uz_fft_combine(a, b, angle, wing, true), 0.0, 1.0);
}

fragment float4 alfven_dealias_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    int w = int(specTex.get_width()), h = int(specTex.get_height());
    return float4(specTex.read(gid).xy * uz_dealias_23(gid, w, h), 0.0, 1.0);
}

// ─── STATE — the MHD advance, pseudo-spectral ───────────────────────────────
//
// No back-trace. Both nonlinear terms are Poisson brackets built from spectral
// derivatives, which is the spike's own formulation and the only version that respects
// the inverse cascade. Everything here is in PHYSICAL units: the spectral derivatives
// come out as d/dx and d/dy directly, so no h-scaling appears in the brackets — the
// class of unit bug that cost this port the Lorentz coupling earlier simply cannot arise.

fragment float4 alfven_state_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::sample> filteredTex [[texture(13)]],
    texture2d<float, access::sample> nonlinearTex [[texture(14)]],
    texture2d<float, access::sample> prevStateTex [[texture(20)]]
) {
    float2 uv    = in.uv;
    float2 texel = 1.0 / float2(prevStateTex.get_width(), prevStateTex.get_height());

    float cycle      = floor(f.time / kAlfvenCycleSeconds);
    float cycleStart = cycle * kAlfvenCycleSeconds;
    float seedPhase  = 7.31 * cycle + 1.7;

    // Re-seed when the field is empty: frame 1 after a preset switch (ALFVEN.1 zeroes
    // persistent pairs) and recovery after a watchdog re-zero.
    float2 c  = prevStateTex.sample(alfven_state_sampler, uv).xy;
    float2 n1 = prevStateTex.sample(alfven_state_sampler, uv + texel * 37.0).xy;
    float2 n2 = prevStateTex.sample(alfven_state_sampler, uv - texel * 53.0).xy;
    if (abs(c.x) + abs(c.y) + abs(n1.y) + abs(n2.y) < kAlfvenSeedFloor) {
        return float4(alfven_seed_band(uv, seedPhase, kAlfvenSeedOmega, kAlfvenSeedKOmega),
                      alfven_seed_band(uv, seedPhase + 8.0, kAlfvenSeedPsi, kAlfvenSeedKPsi),
                      0.0, 1.0);
    }
    // Both fields arrive spectrally filtered: .x = omega, .y = psi.
    c = filteredTex.sample(alfven_state_sampler, uv).xy;

    // The nonlinear terms, already dealiased: .x = omega's, .y = psi's.
    float2 nl = nonlinearTex.sample(alfven_state_sampler, uv).xy;

    // Physical Laplacians for the explicit diffusion (texel stencil / h^2).
    float hPhys = 6.28318530718 / float(prevStateTex.get_width());
    float invH2 = 1.0 / (hPhys * hPhys);
    // Neighbours MUST come from the same (filtered) field as the centre. Sampling the
    // centre from filteredTex while taking neighbours from prevStateTex made the stencil
    // differ by exactly the content the spectral filter had just removed — and the
    // Laplacian multiplies that residue by 1/h^2 = 1661 at N = 256. It injected the
    // filtered-out grid scale straight back into both diffusion terms and into the cached
    // J that compose and the soak read, which is why jRMS measured ~216 against the
    // reference's 4.5.
    float4 nL = filteredTex.sample(alfven_state_sampler, uv - float2(texel.x, 0.0));
    float4 nR = filteredTex.sample(alfven_state_sampler, uv + float2(texel.x, 0.0));
    float4 nT = filteredTex.sample(alfven_state_sampler, uv + float2(0.0, texel.y));
    float4 nB = filteredTex.sample(alfven_state_sampler, uv - float2(0.0, texel.y));
    float wL = nL.x, wR = nR.x, wT = nT.x, wB = nB.x;
    float pL = nL.y, pR = nR.y, pT = nT.y, pB = nB.y;
    float lapW = (wL + wR + wT + wB - 4.0 * c.x) * invH2;
    float lapP = (pL + pR + pT + pB - 4.0 * c.y) * invH2;

    float force = kAlfvenDrive * alfven_forcing(uv, f.time);

    // Drag and diffusion are NOT here any more: both are folded into the spectral
    // integrating factor in the filter stage, which is where the spike puts them and the
    // only place k^4 damping can be expressed.
    float omega = c.x + kAlfvenDt * (nl.x + force);
    float psi   = c.y + kAlfvenDt * nl.y;

    // Re-seed crossfade (§5), raised cosine, as a per-step share of the blend.
    float a = clamp((f.time - cycleStart) / kAlfvenBlendTau, 0.0, 1.0);
    if (a < 1.0) {
        float g = 0.5 - 0.5 * cos(M_PI_F * a);
        float r = clamp(g * (kAlfvenDt / kAlfvenBlendTau) * M_PI_F, 0.0, 1.0);
        omega = mix(omega, alfven_seed_band(uv, seedPhase, kAlfvenSeedOmega, kAlfvenSeedKOmega), r);
        psi   = mix(psi,   alfven_seed_band(uv, seedPhase + 8.0, kAlfvenSeedPsi, kAlfvenSeedKPsi), r);
    }

    omega = clamp(omega, -kAlfvenClampW, kAlfvenClampW);
    psi   = clamp(psi,   -kAlfvenClampP, kAlfvenClampP);

    // J is cached for the compose stage: J = lap(psi), physical.
    float J = (pL + pR + pT + pB - 4.0 * c.y) * invH2;
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
    // Palette centre 0.72 — the LATE end of film.py's drift (magenta <-> teal), which is
    // the fourth column of the concept sheet and Matt's pick (2026-09-09).
    // `04_palette_opponent_drift.png`: "Left = early (acid green <-> violet), right = late
    // (magenta <-> teal)". film.py maps hue = 0.46 + 0.26*centroid01, so 0.72 is the top of
    // that range. ALFVEN.3 will drive the centre from spectral centroid; if only this end
    // is wanted, that routing's range narrows rather than spanning the full drift.
    float hue = kAlfvenHueCentre + 0.30 * sJ;
    float sat = 0.32 + 0.58 * (1.0 - aJ * aJ);
    float x   = 1.9 * pow(aJ, 0.85);
    float val = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);

    float3 col = hsv2rgb(float3(fract(hue), sat, val));

    // D-037: silence is coloured, never black.
    float3 ground = float3(0.035, 0.045, 0.075);
    col += ground * (1.0 - val);

    return float4(min(col, float3(1.0)), 1.0);
}
