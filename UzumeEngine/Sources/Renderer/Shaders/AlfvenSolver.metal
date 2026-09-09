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
    float _pad;
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
kernel void alfven_spectral_filter(
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
    float kr = clamp(sqrt(k2) / p.cutoff, 0.0, 1.0);
    float filt  = exp(-36.0 * pow(kr, 36.0));
    float hyper = exp(-p.nu4 * k2 * k2 * p.dt);
    omegaH *= filt * hyper * exp(-p.alpha * p.dt);
    psiH   *= filt * hyper;

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
kernel void alfven_integrate(
    texture2d<float, access::read>  state [[texture(0)]],
    texture2d<float, access::read>  nl    [[texture(1)]],
    texture2d<float, access::read>  gPsi  [[texture(2)]],
    texture2d<float, access::write> dst   [[texture(3)]],
    constant AlfvenParams& p              [[buffer(0)]],
    device const float* dtBuf             [[buffer(1)]],
    uint2 gid                             [[thread_position_in_grid]]
) {
    if (gid.x >= p.gridEdge || gid.y >= p.gridEdge) { return; }
    constexpr float kTau = 6.28318530718;
    float2 uv = (float2(gid) + 0.5) / float(p.gridEdge);
    float dt = dtBuf[0];

    float2 c = state.read(gid).xy;
    float2 n = nl.read(gid).xy;

    float force = p.drive * 0.25 * (
          sin(kTau * (2.0 * uv.x + 3.0 * uv.y) + 0.71 * p.time)
        + sin(kTau * (4.0 * uv.x - 2.0 * uv.y) - 0.53 * p.time + 1.7)
        + sin(kTau * (3.0 * uv.x + 5.0 * uv.y) + 0.37 * p.time + 3.1)
        + sin(kTau * (5.0 * uv.x - 4.0 * uv.y) - 0.89 * p.time + 0.4));

    float omega = c.x + dt * (n.x + force);
    float psi   = c.y + dt * n.y;

    if (p.blendRate > 0.0) {
        float r = clamp(p.blendRate, 0.0, 1.0);
        omega = mix(omega, alf_seed(uv, p.seedPhase, p.seedAmpOmega, p.seedKOmega), r);
        psi   = mix(psi,   alf_seed(uv, p.seedPhase + 8.0, p.seedAmpPsi, p.seedKPsi), r);
    }

    omega = clamp(omega, -p.clampW, p.clampW);
    psi   = clamp(psi,   -p.clampP, p.clampP);

    // J = lap(psi), recovered from psi's spectral gradient magnitude is not available
    // here, so use the local stencil in PHYSICAL units for the cached diagnostic value.
    float h = kTau / float(p.gridEdge);
    float invH2 = 1.0 / (h * h);
    uint2 l = uint2((gid.x + p.gridEdge - 1) % p.gridEdge, gid.y), r2 = uint2((gid.x + 1) % p.gridEdge, gid.y);
    uint2 u = uint2(gid.x, (gid.y + 1) % p.gridEdge),       d = uint2(gid.x, (gid.y + p.gridEdge - 1) % p.gridEdge);
    float J = (state.read(l).y + state.read(r2).y + state.read(u).y + state.read(d).y
               - 4.0 * c.y) * invH2;

    dst.write(float4(omega, psi, J, 1.0), gid);
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
    float hueCentre;
    float _pad0;
    float _pad1;
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

fragment float4 alfven_display_fragment(
    AlfvenVertexOut in [[stage_in]],
    constant AlfvenDisplayParams& p [[buffer(0)]],
    texture2d<float, access::sample> stateTex [[texture(0)]]
) {
    constexpr sampler smp(filter::linear, address::repeat);
    float J = stateTex.sample(smp, in.uv).z;

    float aJ = clamp(abs(J) * p.exposure, 0.0, 1.0);
    float sJ = tanh(J * p.exposure * 1.2);

    // film.py: h = centre + 0.30*sJ, s = 0.32 + 0.58*(1-aJ^2), v = filmic(1.9*aJ^0.85)
    float hue = p.hueCentre + 0.30 * sJ;
    float sat = 0.32 + 0.58 * (1.0 - aJ * aJ);
    float x   = 1.9 * pow(aJ, 0.85);
    float val = clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0);

    float3 col = alf_hsv2rgb(float3(fract(hue), sat, val));
    col += float3(0.035, 0.045, 0.075) * (1.0 - val);   // D-037: never black
    return float4(min(col, float3(1.0)), 1.0);
}
