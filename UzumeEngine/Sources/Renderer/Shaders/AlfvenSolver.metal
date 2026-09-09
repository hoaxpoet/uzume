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
