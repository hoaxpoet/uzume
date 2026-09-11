// AlfvenSolver.metal — compute kernels for Alfvén's MHD solver (ALFVEN.4).
//
// WHY COMPUTE. ALFVEN.2 built this solver on the `staged` fragment path and measured
// three limits that are architectural, not tuning:
//
//   1. SUBSTEPS. Derivative spectra are computed once per frame upstream, so substeps
//      2..N evaluate the brackets against stale derivatives — measured psi 0.90 -> 0.049.
//      A Swift-side loop with barriers has no such problem.
//   2. ADAPTIVE dt. The blow-up is a CFL violation that DEVELOPS as the enstrophy cascade
//      energises the field (u*k_max*dt: 0.10 at omega 1.2, 2.56 at omega 30). The spike
//      handles it with dt = min(0.005, 0.25*dx/max(|u|,|B|)) recomputed from a field-wide
//      max. A staged DAG cannot feed a global reduction back into the same frame.
//   3. COST. A 2D FFT as fragment passes is 16 render passes (8 butterflies per axis).
//      A threadgroup-memory FFT does an entire row in ONE dispatch, because all log2(N)
//      butterfly stages can run in shared memory with barriers between them.
//
// This file starts with (3), because it is the piece the other two depend on and it is
// independently verifiable against the already-proven fragment FFT (FFTSandboxTests).
//
// Complex values are packed (re, im). N must be a power of two and <= kAlfvenMaxFFT.

#include <metal_stdlib>
using namespace metal;

// Largest transform length one threadgroup handles. 1024 floats2 = 8 KB of threadgroup
// memory, comfortably inside the 32 KB Apple-silicon limit.
constant constexpr uint kAlfvenMaxFFT = 1024;

static inline float2 alf_cmul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

/// In-place Cooley-Tukey over threadgroup memory: bit-reversal permutation, then
/// log2(n) butterfly stages with a barrier between each. One threadgroup transforms one
/// line of the image, so a full axis is a single dispatch instead of log2(n) passes.
static inline void alf_fft_threadgroup(threadgroup float2* buf, uint tid, uint tcount,
                                       uint n, bool forward) {
    // Bit-reversal permutation, STRIDED over all n elements.
    //
    // There are only n/2 threads (one per butterfly), but the permutation has to touch
    // every one of the n elements. Indexing it by `tid` alone silently leaves the upper
    // half unpermuted — the forward transform still satisfies Parseval, because that is
    // invariant under a permutation of the outputs, so only the ROUND-TRIP gate catches
    // it. It did: 2.07 relative error against a 1e-4 bar.
    uint bits = uint(log2(float(n)));
    for (uint i = tid; i < n; i += tcount) {
        uint rev = reverse_bits(i) >> (32u - bits);
        if (rev > i) {
            float2 tmp = buf[i];
            buf[i] = buf[rev];
            buf[rev] = tmp;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    float sign = forward ? -1.0 : 1.0;
    for (uint len = 2; len <= n; len <<= 1) {
        // Named `span`: the obvious name here is an MSL keyword (the 16-bit float
        // type), and shadowing it is Failed Approach #44 — which this file hit on
        // its very first compile.
        uint span = len >> 1;
        uint group = tid / span;
        uint slot  = tid % span;
        uint i0 = group * len + slot;
        uint i1 = i0 + span;
        if (i1 < n) {
            float ang = sign * 6.28318530718 * float(slot) / float(len);
            float2 w  = float2(cos(ang), sin(ang));
            float2 a  = buf[i0];
            float2 b  = alf_cmul(w, buf[i1]);
            buf[i0] = a + b;
            buf[i1] = a - b;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
}

/// One dispatch transforms every ROW: threadgroup y = row index, threads = columns/2.
kernel void alfven_fft_rows(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant uint& forward             [[buffer(0)]],
    uint2 gid                          [[threadgroup_position_in_grid]],
    uint2 tid2                         [[thread_position_in_threadgroup]],
    uint2 tcount2                      [[threads_per_threadgroup]]
) {
    threadgroup float2 buf[kAlfvenMaxFFT];
    uint tid = tid2.x, tcount = tcount2.x;
    uint n = src.get_width();
    for (uint i = tid; i < n; i += tcount) {
        buf[i] = src.read(uint2(i, gid.y)).xy;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    alf_fft_threadgroup(buf, tid, tcount, n, forward != 0u);

    float scale = (forward != 0u) ? 1.0 : (1.0 / float(n));
    for (uint i = tid; i < n; i += tcount) {
        dst.write(float4(buf[i] * scale, 0.0, 1.0), uint2(i, gid.y));
    }
}

/// One dispatch transforms every COLUMN.
kernel void alfven_fft_cols(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant uint& forward             [[buffer(0)]],
    uint2 gid                          [[threadgroup_position_in_grid]],
    uint2 tid2                         [[thread_position_in_threadgroup]],
    uint2 tcount2                      [[threads_per_threadgroup]]
) {
    threadgroup float2 buf[kAlfvenMaxFFT];
    uint tid = tid2.x, tcount = tcount2.x;
    uint n = src.get_height();
    for (uint i = tid; i < n; i += tcount) {
        buf[i] = src.read(uint2(gid.x, i)).xy;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    alf_fft_threadgroup(buf, tid, tcount, n, forward != 0u);

    float scale = (forward != 0u) ? 1.0 : (1.0 / float(n));
    for (uint i = tid; i < n; i += tcount) {
        dst.write(float4(buf[i] * scale, 0.0, 1.0), uint2(gid.x, i));
    }
}

// ─── Solver kernels ─────────────────────────────────────────────────────────
//
// The physics is ALFVEN.2's, unchanged and already validated — spectral Poisson with the
// correct sign (phi_h = -omega_h/k^2), spectral Poisson brackets, Hou-Li filter, the 2/3
// dealias mask and the spike's integrating factor. Only the ORCHESTRATION moves: a Swift
// substep loop with barriers instead of a per-frame staged DAG, which is what makes
// substeps and adaptive dt possible at all.
//
// State packing: .r = omega, .g = psi, .b = J (cached for the fragment), .a = 1.

struct AlfvenParams {
    float dt;
    float alpha;        // linear drag on omega
    float nu4;          // k^4 hyperdiffusion
    float drive;        // forcing amplitude
    float time;         // seconds, for forcing phase + the re-seed cycle
    float cutoff;       // spectral filter cutoff in mode numbers
    float clampW;
    float clampP;
    uint  gridEdge;     // grid edge
    uint  seedKOmega;
    uint  seedKPsi;
    float seedAmpOmega;
    float seedAmpPsi;
    float seedPhase;
    float blendRate;    // per-substep share of the re-seed crossfade
    float jCutoff;      // band limit for the DISPLAY quantity J; see alfven_j_spectrum
    float expoAlpha;    // EMA coefficient for mean|J|, from REAL dt (ALFVEN.3g)
    float expoBeta;     // partial-adaptation exponent; 0 = fixed, 1 = film.py
};

static inline float2 alf_wavenumber(uint2 gid, uint n) {
    int kx = int(gid.x); if (kx > int(n) / 2) { kx -= int(n); }
    int ky = int(gid.y); if (ky > int(n) / 2) { ky -= int(n); }
    return float2(float(kx), float(ky));
}

static inline void alf_unpack(float2 fk, float2 fmk, thread float2& aH, thread float2& bH) {
    aH = 0.5 * float2(fk.x + fmk.x, fk.y - fmk.y);
    float2 d = 0.5 * float2(fk.x - fmk.x, fk.y + fmk.y);
    bH = float2(d.y, -d.x);
}

static inline float alf_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

/// Band-limited random-phase seed over integer wavevectors, amplitude k^-1.6, normalised
/// by its own analytic RMS so `amp` keeps the spike's meaning.
static inline float alf_seed(float2 uv, float phase, float amp, uint kmax) {
    constexpr float kTau = 6.28318530718;
    float s = 0.0, norm = 0.0;
    int km = int(kmax);
    for (int m = -km; m <= km; ++m) {
        for (int nn = 0; nn <= km; ++nn) {
            if (nn == 0 && m <= 0) { continue; }
            float k2 = float(m * m + nn * nn);
            if (k2 < 1.0 || k2 > float(km * km)) { continue; }
            float a = pow(k2, -0.8);
            float ph = kTau * alf_hash(float2(float(m), float(nn)) + phase);
            s += a * sin(kTau * (float(m) * uv.x + float(nn) * uv.y) + ph);
            norm += a * a * 0.5;
        }
    }
    return s * amp / sqrt(max(norm, 1e-9));
}

kernel void alfven_seed_state(
    texture2d<float, access::write> dst [[texture(0)]],
    constant AlfvenParams& p            [[buffer(0)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float2 uv = (float2(gid) + 0.5) / float(p.gridEdge);
    dst.write(float4(alf_seed(uv, p.seedPhase, p.seedAmpOmega, p.seedKOmega),
                     alf_seed(uv, p.seedPhase + 8.0, p.seedAmpPsi, p.seedKPsi),
                     0.0, 1.0), gid);
}

/// Hou-Li filter + the spike's integrating factor. omega carries the drag, psi does not
/// (Ew vs Ep in alfven.py), so the packed spectrum is unpacked, scaled separately, repacked.
// The integrating factor. Split out of the old `alfven_spectral_filter`, which fused it
// with the Hou-Li filter AND used `p.dt` (the fixed 0.005 ceiling) rather than the adaptive
// dt the step actually advances by — so the dissipation applied never matched the step.
// The spike keeps them separate too: Ew/Ep act INSIDE the RK2 stages (alfven.py:98-99),
// FILT acts once at the end (alfven.py:104-105).
//
//   Ew = exp(-(nu4 k^4 + alpha) dt)   on omega
//   Ep = exp(- nu4 k^4        dt)     on psi   — no drag on psi (alfven.py:99)
kernel void alfven_efactor(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant AlfvenParams& p            [[buffer(0)]],
    device const float* dtBuf           [[buffer(1)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    uint2 mir = uint2((p.gridEdge - gid.x) % p.gridEdge, (p.gridEdge - gid.y) % p.gridEdge);
    float2 omegaH, psiH;
    alf_unpack(src.read(gid).xy, src.read(mir).xy, omegaH, psiH);

    float2 k = alf_wavenumber(gid, p.gridEdge);
    float k2 = dot(k, k);
    float dt = dtBuf[0];
    float hyper = exp(-p.nu4 * k2 * k2 * dt);
    omegaH *= hyper * exp(-p.alpha * dt);
    psiH   *= hyper;

    dst.write(float4(omegaH.x - psiH.y, omegaH.y + psiH.x, 0.0, 1.0), gid);
}

// Hou-Li smooth spectral filter, applied once per substep to the STATE (alfven.py:104-105).
// `p.cutoff` is the Nyquist wavenumber, matching the spike's `kmax = N/2`.
kernel void alfven_houli(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant AlfvenParams& p            [[buffer(0)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    uint2 mir = uint2((p.gridEdge - gid.x) % p.gridEdge, (p.gridEdge - gid.y) % p.gridEdge);
    float2 omegaH, psiH;
    alf_unpack(src.read(gid).xy, src.read(mir).xy, omegaH, psiH);

    float2 k = alf_wavenumber(gid, p.gridEdge);
    float kr = clamp(sqrt(dot(k, k)) / p.cutoff, 0.0, 1.0);
    float filt = exp(-36.0 * pow(kr, 36.0));
    omegaH *= filt;
    psiH   *= filt;

    dst.write(float4(omegaH.x - psiH.y, omegaH.y + psiH.x, 0.0, 1.0), gid);
}

/// Spectrum of (a_x + i a_y) for one of the four fields. `mode` selects which:
/// 0 = phi (phi_h = -omega_h/k^2), 1 = omega, 2 = psi, 3 = J (J_h = -k^2 psi_h).
kernel void alfven_grad_spectrum(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant AlfvenParams& p            [[buffer(0)]],
    constant uint& mode                 [[buffer(1)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    uint2 mir = uint2((p.gridEdge - gid.x) % p.gridEdge, (p.gridEdge - gid.y) % p.gridEdge);
    float2 omegaH, psiH;
    alf_unpack(src.read(gid).xy, src.read(mir).xy, omegaH, psiH);
    float2 k = alf_wavenumber(gid, p.gridEdge);
    float k2 = dot(k, k);

    float2 field;
    switch (mode) {
        // omega = lap(phi) => phi_h = -omega_h/k^2. The sign here is the one that cost
        // ALFVEN.2 most of its investigation; see that increment's history.
        case 0:  field = (k2 < 0.5) ? float2(0.0) : (-omegaH / k2); break;
        case 1:  field = omegaH; break;
        case 2:  field = psiH;   break;
        default: field = -k2 * psiH; break;
    }
    // (i*kx + i*i*ky) * field = (-ky + i*kx) * field
    float2 g = float2(-k.y * field.x - k.x * field.y,
                      -k.y * field.y + k.x * field.x);
    dst.write(float4(g, 0.0, 1.0), gid);
}

/// The two nonlinear terms, packed as one complex field for a single transform pair.
kernel void alfven_brackets(
    texture2d<float, access::read>  gPhi [[texture(0)]],
    texture2d<float, access::read>  gOme [[texture(1)]],
    texture2d<float, access::read>  gPsi [[texture(2)]],
    texture2d<float, access::read>  gJ   [[texture(3)]],
    texture2d<float, access::write> dst  [[texture(4)]],
    constant AlfvenParams& p             [[buffer(0)]],
    uint2 gid                            [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float2 a = gPhi.read(gid).xy, b = gOme.read(gid).xy;
    float2 c = gPsi.read(gid).xy, d = gJ.read(gid).xy;
    float brPhiOmega = a.x * b.y - a.y * b.x;
    float brPsiJ     = c.x * d.y - c.y * d.x;
    float brPhiPsi   = a.x * c.y - a.y * c.x;
    dst.write(float4(-brPhiOmega + brPsiJ, -brPhiPsi, 0.0, 1.0), gid);
}

/// Orszag 2/3 dealias mask — every bracket needs it (alfven.py:79).
kernel void alfven_dealias(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant AlfvenParams& p            [[buffer(0)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float2 k = alf_wavenumber(gid, p.gridEdge);
    float cut = (2.0 / 3.0) * float(p.gridEdge / 2);
    float mask = (abs(k.x) < cut && abs(k.y) < cut) ? 1.0 : 0.0;
    dst.write(float4(src.read(gid).xy * mask, 0.0, 1.0), gid);
}

/// One explicit step, plus the re-seed crossfade and the safety clamps. `dtBuf` carries
/// the CFL-adapted timestep computed by `alfven_cfl_reduce`, so the timestep tracks the
/// field instead of being fixed at authoring time.
// The band-limited stirring force, in real space. Low-k by construction (|k| <= 7), so
// the spike's `f_h * Ew` in the corrector stage differs from `f_h` by exp(-alpha*dt) ~
// 0.9997 at these wavenumbers — below single precision's grip on the result, so the
// corrector reuses the same force.
static inline float alf_force(float2 uv, constant AlfvenParams& p) {
    constexpr float kTau = 6.28318530718;
    return p.drive * 0.25 * (
          sin(kTau * (2.0 * uv.x + 3.0 * uv.y) + 0.71 * p.time)
        + sin(kTau * (4.0 * uv.x - 2.0 * uv.y) - 0.53 * p.time + 1.7)
        + sin(kTau * (3.0 * uv.x + 5.0 * uv.y) + 0.37 * p.time + 3.1)
        + sin(kTau * (5.0 * uv.x - 4.0 * uv.y) - 0.89 * p.time + 0.4));
}

// dst = base + coef*dt*(nl + force). Both RK2 stages are this same axpy; `coef` is 1.0
// for the predictor and 0.5 for the corrector base (alfven.py:100-103).
kernel void alfven_accumulate(
    texture2d<float, access::read>  base [[texture(0)]],
    texture2d<float, access::read>  nl   [[texture(1)]],
    texture2d<float, access::write> dst  [[texture(2)]],
    constant AlfvenParams& p             [[buffer(0)]],
    device const float* dtBuf            [[buffer(1)]],
    constant float& coef                 [[buffer(2)]],
    uint2 gid                            [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float2 uv = (float2(gid) + 0.5) / float(p.gridEdge);
    float dt = dtBuf[0] * coef;
    float2 c = base.read(gid).xy;
    float2 n = nl.read(gid).xy;
    dst.write(float4(c.x + dt * (n.x + alf_force(uv, p)), c.y + dt * n.y, 0.0, 1.0), gid);
}

// Re-seed crossfade, clamp backstop, and the J channel the fragment colours.
//
// J arrives already computed SPECTRALLY (alfven_j_spectrum) from the filtered spectrum,
// so it carries nothing above the Hou-Li cutoff. It used to be a local 5-point stencil on
// the RAW state — that is what put grid-scale content into the one quantity the fragment
// colours. The stencil was not "amplifying" the grid scale: its effective wavenumber is
// (2/h^2)(1-cos kh), which UNDER-reads curvature at high k (4/h^2 vs pi^2/h^2 at Nyquist).
// Spectral J therefore reads slightly HIGHER than the stencil did even though it is the
// smoother field — do not read that rise as a regression.
kernel void alfven_finalize(
    texture2d<float, access::read>  src    [[texture(0)]],
    texture2d<float, access::read>  jField [[texture(1)]],
    texture2d<float, access::write> dst    [[texture(2)]],
    constant AlfvenParams& p               [[buffer(0)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float2 uv = (float2(gid) + 0.5) / float(p.gridEdge);
    float2 c = src.read(gid).xy;
    float omega = c.x, psi = c.y;

    if (p.blendRate > 0.0) {
        float r = clamp(p.blendRate, 0.0, 1.0);
        omega = mix(omega, alf_seed(uv, p.seedPhase, p.seedAmpOmega, p.seedKOmega), r);
        psi   = mix(psi,   alf_seed(uv, p.seedPhase + 8.0, p.seedAmpPsi, p.seedKPsi), r);
    }

    omega = clamp(omega, -p.clampW, p.clampW);
    psi   = clamp(psi,   -p.clampP, p.clampP);
    dst.write(float4(omega, psi, jField.read(gid).x, 1.0), gid);
}

/// CFL reduction: the field-wide max of max(|u|, |B|), then dt = min(dtMax, 0.25*dx/c).
/// This is the mechanism a staged DAG could not express — the timestep depends on a
/// global reduction over the CURRENT state, fed back into the same frame's stepping.
/// Matches the spike (alfven.py:86, 149-151).
kernel void alfven_cfl_reduce(
    texture2d<float, access::read> gPhi [[texture(0)]],
    texture2d<float, access::read> gPsi [[texture(1)]],
    device atomic_uint* scratch         [[buffer(0)]],
    constant AlfvenParams& p            [[buffer(1)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float u = length(gPhi.read(gid).xy);     // |grad phi| = |u|
    float b = length(gPsi.read(gid).xy);     // |grad psi| = |B|
    float c = max(u, b);
    // Monotonic bit pattern for non-negative floats, so an integer atomic max works.
    atomic_fetch_max_explicit(scratch, as_type<uint>(c), memory_order_relaxed);
}

kernel void alfven_cfl_finish(
    device const atomic_uint* scratch [[buffer(0)]],
    device float* dtOut               [[buffer(1)]],
    constant AlfvenParams& p          [[buffer(2)]],
    uint tid                          [[thread_position_in_grid]]
) {
    if (tid != 0) { return; }
    float c = as_type<float>(atomic_load_explicit(scratch, memory_order_relaxed));
    float dx = 6.28318530718 / float(p.gridEdge);
    dtOut[0] = min(p.dt, 0.25 * dx / max(c, 1e-3));
}

/// ALFVEN.3g — auto-exposure reduction: the field-wide mean of |J|.
///
/// film.py normalises by `1 / (p99.6 - p2)` of |J| (`autoexp`), which a fragment cannot
/// compute. Measured across drive 5…24 — a 4.8x span of field energy — that percentile
/// range tracks mean|J| at a ratio of 0.163 +/- 6 %, so the mean substitutes for it and is
/// reachable by exactly the reduction the CFL timestep already performs each substep.
///
/// Fixed-point accumulation: `atomic_fetch_add` on floats is not universally available, so
/// |J| is scaled by 64 and summed as integers. Headroom check at the production grid:
/// 256^2 texels * |J| ~ 200 worst case * 64 = 2.1e8, an order of magnitude under UINT_MAX.
kernel void alfven_exposure_reduce(
    texture2d<float, access::read> state [[texture(0)]],
    device atomic_uint* scratch          [[buffer(0)]],
    constant AlfvenParams& p             [[buffer(1)]],
    uint2 gid                            [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float aj = fabs(state.read(gid).z);          // J rides in .z
    atomic_fetch_add_explicit(scratch, uint(aj * 64.0), memory_order_relaxed);
}

/// Turns that sum into the exposure FACTOR the display multiplies its calibrated constant
/// by. Writes `[0] = factor, [1] = the mean|J| EMA` so the EMA persists across frames.
///
/// Two deliberate departures from film.py, both because it renders STILLS and we render a
/// TIMELINE:
///   1. The EMA. Per-frame normalisation is fine for independent stills; at 60 fps an
///      exposure that jumps between frames IS a flash, which D-157 governs.
///   2. `expoBeta` < 1. film.py's job is to remove brightness variation; ours is partly to
///      CARRY it, because the loudness cue is signal. beta = 1 reproduces film.py exactly
///      and measured 1.25x loud/quiet response against 1.56x fixed; beta = 0.65 keeps 1.35x
///      while removing 82 % of the clipping.
kernel void alfven_exposure_finish(
    device const atomic_uint* scratch [[buffer(0)]],
    device float* out                 [[buffer(1)]],
    constant AlfvenParams& p          [[buffer(2)]],
    uint tid                          [[thread_position_in_grid]]
) {
    if (tid != 0) { return; }
    float n = float(p.gridEdge) * float(p.gridEdge);
    float mean = float(atomic_load_explicit(scratch, memory_order_relaxed)) / (64.0 * n);
    mean = max(mean, 1e-4);
    float prev = out[1];
    float ema = (prev <= 0.0) ? mean : prev + p.expoAlpha * (mean - prev);
    out[1] = ema;
    // 1.917 = the mean|J| at which the ALFVEN.4d calibration of `displayExposure` is
    // correct; at beta = 1 this reproduces film.py's 0.163 / mean|J| exactly.
    out[0] = clamp(pow(1.917 / ema, p.expoBeta), 0.25, 2.0);
}

// ─── Display ────────────────────────────────────────────────────────────────
//
// The shipping look is docs/presets/alfven_spike/film.py, and the spike's README is
// explicit that the Metal fragment should reproduce THAT rather than invent its own.
// film.py's percentile auto-exposure and two-sigma seam bloom are global/multi-scale and
// still need a reduction surface, so this is film.py's PALETTE with a fixed exposure —
// the same placeholder the staged version used, and diagnosable in the same way.
//
// Palette centre 0.72: the late magenta<->teal end of film.py's drift, which is the
// fourth column of the concept sheet and Matt's pick (2026-09-09).

struct AlfvenDisplayParams {
    float exposure;
    float polarityScale;
    float hueCentre;
    float bloomAmount;
};

struct AlfvenVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex AlfvenVertexOut alfven_display_vertex(uint vid [[vertex_id]]) {
    AlfvenVertexOut out;
    out.uv = float2((vid << 1) & 2, vid & 2);
    out.position = float4(out.uv * 2.0 - 1.0, 0.0, 1.0);
    out.uv.y = 1.0 - out.uv.y;
    return out;
}

static inline float3 alf_hsv2rgb(float3 c) {
    float3 p = abs(fract(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// ── Seam bloom (ALFVEN.4f) ───────────────────────────────────────────────────
// film.py takes the brightest decile of |J|, blurs it at two scales and adds it back
// tinted by current-sheet polarity. It was deferred as needing "the same reduction
// surface as the percentile auto-exposure" — which conflated two different things. The
// AUTO-EXPOSURE needs a whole-frame reduction (percentiles). The BLOOM needs a BLUR,
// which is local and separable, and the solver already owns a compute pipeline and
// textures. Only the exposure stays a fixed stand-in.
//
//   core = clip((aJ - 0.72) / 0.28, 0, 1)^1.5      film.py's threshold, verbatim
//   b0   = gaussian(core, 2.0)
//   b1   = gaussian(core, 7.0)
kernel void alfven_bloom_core(
    texture2d<float, access::read>  state [[texture(0)]],
    texture2d<float, access::write> dst   [[texture(1)]],
    constant AlfvenParams& p              [[buffer(0)]],
    constant float& exposure              [[buffer(1)]],
    uint2 gid                             [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    float aJ = clamp(abs(state.read(gid).z) * exposure, 0.0, 1.0);
    float core = pow(clamp((aJ - 0.72) / 0.28, 0.0, 1.0), 1.5);
    dst.write(float4(core, 0.0, 0.0, 1.0), gid);
}

// One axis of a separable Gaussian. `dir` is (1,0) or (0,1); the field wraps, so the
// taps wrap with it — the domain is periodic and a clamped edge would darken the border.
kernel void alfven_blur(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant AlfvenParams& p            [[buffer(0)]],
    constant float2& dir                [[buffer(1)]],
    constant float& sigma               [[buffer(2)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    int radius = int(ceil(3.0 * sigma));
    float inv2s2 = 1.0 / (2.0 * sigma * sigma);
    int n = int(p.gridEdge);
    float sum = 0.0, wsum = 0.0;
    for (int i = -radius; i <= radius; ++i) {
        float w = exp(-float(i * i) * inv2s2);
        int2 o = int2(gid) + int2(dir * float(i));
        uint2 c = uint2(uint((o.x % n + n) % n), uint((o.y % n + n) % n));
        sum += w * src.read(c).x;
        wsum += w;
    }
    dst.write(float4(sum / max(wsum, 1e-9), 0.0, 0.0, 1.0), gid);
}

fragment float4 alfven_display_fragment(
    AlfvenVertexOut in [[stage_in]],
    constant AlfvenDisplayParams& p [[buffer(0)]],
    texture2d<float, access::sample> stateTex [[texture(0)]],
    texture2d<float, access::sample> bloomNear [[texture(1)]],
    texture2d<float, access::sample> bloomFar  [[texture(2)]],
    device const float* expo                   [[buffer(1)]]
) {
    constexpr sampler smp(filter::linear, address::repeat);
    float J = stateTex.sample(smp, in.uv).z;

    // film.py normalises these by TWO DIFFERENT quantities and they must stay separate:
    //   aJ = autoexp(|J|)              -> 1/(p99.6 - p2)   (value / brightness)
    //   sJ = tanh(J / (std(J) * 1.2))  -> 1/(std * 1.2)    (current-sheet POLARITY -> hue)
    // This collapsed both onto `exposure`, so any exposure low enough not to blow the
    // value out also drove sJ to ~0.09, killing the hue opponency and leaving a flat
    // lavender frame. Both are fixed stand-ins for percentile/std reductions the fragment
    // cannot do, so both are calibrated against the measured field (ALFVEN.4d).
    // ALFVEN.3g: `exposure` stays the ALFVEN.4d reference-matched calibration; the field
    // statistic only SCALES it, so the two concerns remain separable. Polarity is left on
    // the fixed scale on purpose — it is a hue signal, not a brightness one, and 4d's
    // collapse of the two onto one constant is the trap this keeps closed.
    float aJ = clamp(abs(J) * p.exposure * expo[0], 0.0, 1.0);
    float sJ = tanh(J * p.polarityScale);

    // film.py: h = centre + 0.30*sJ, s = 0.32 + 0.58*(1-aJ^2), v = filmic(1.9*aJ^0.85)
    float hue = p.hueCentre + 0.30 * sJ;
    float sat = 0.32 + 0.58 * (1.0 - aJ * aJ);
    float x   = 1.9 * pow(aJ, 0.85);
    float val = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);

    float3 col = alf_hsv2rgb(float3(fract(hue), sat, val));

    // Seam bloom, film.py's own weights and tints. `amt` is its silence value: the
    // treble term (`0.85 * sizzle`) needs audio, so it arrives with ALFVEN.3.
    float b0 = bloomNear.sample(smp, in.uv).x;
    float b1 = bloomFar.sample(smp, in.uv).x;
    float glow = 0.75 * b0 + 0.55 * b1;
    float split = 0.5 + 0.5 * sJ;
    float3 tintA = float3(1.00, 0.72, 0.42);
    float3 tintB = float3(0.45, 0.72, 1.00);
    col += p.bloomAmount * glow * (tintA * split + tintB * (1.0 - split));

    col += float3(0.035, 0.045, 0.075) * (1.0 - val);   // D-037: never black
    return float4(min(col, float3(1.0)), 1.0);
}

/// Spectrum of J = lap(psi), i.e. J_h = -k^2 psi_h, taken from the FILTERED spectrum.
///
/// J is what the fragment colours (§4), and it was the one quantity in an otherwise fully
/// spectral solver still computed with a local 5-point stencil on the RAW state. That
/// stencil is a high-pass: it amplifies grid-scale content by 1/h^2 and deviates from -k^2
/// exactly where the seams live, so it manufactured aliasing at the sharpest seams — the
/// localised `07_anti_grid_speckle` signature in the rendered frames. Computed spectrally
/// from the filtered spectrum, J carries nothing above the filter cutoff by construction.
kernel void alfven_j_spectrum(
    texture2d<float, access::read>  src [[texture(0)]],
    texture2d<float, access::write> dst [[texture(1)]],
    constant AlfvenParams& p            [[buffer(0)]],
    uint2 gid                           [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    uint2 mir = uint2((p.gridEdge - gid.x) % p.gridEdge, (p.gridEdge - gid.y) % p.gridEdge);
    float2 omegaH, psiH;
    alf_unpack(src.read(gid).xy, src.read(mir).xy, omegaH, psiH);
    float2 k = alf_wavenumber(gid, p.gridEdge);
    float k2 = dot(k, k);

    // Band-limit J to where psi actually HAS content. This is not taste, it is the
    // single-precision noise floor made visible by the k^2 in J = lap(psi):
    //
    //   psi carries 99.9% of its energy below k = 8 and its peak (k = 2) has power
    //   ~1.9e-3. Measured anomalous energy on the ky = 0 row at k = 32..128 is ~1.5e-10,
    //   i.e. 1e-7 of the peak — float32 epsilon exactly. It sits on ky = 0 because the
    //   transform is separable: the row pass leaves round-off of order eps*|psi| at high
    //   kx, and the column pass averages it over y straight into the ky = 0 bin. J then
    //   multiplies it by k^4 in power (1.7e7 at k = 64), lifting round-off to J's own
    //   scale — visible as fine VERTICAL stripes over the whole frame, i.e. exactly the
    //   `07_anti_grid_speckle` anti-reference. The float64 spike never shows it.
    //
    // So this filters numerical noise, not physics; the state itself is untouched.
    float kr = clamp(sqrt(k2) / max(p.jCutoff, 1.0), 0.0, 1.0);
    dst.write(float4(-k2 * psiH * exp(-36.0 * pow(kr, 36.0)), 0.0, 1.0), gid);
}
