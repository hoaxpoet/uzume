// FFTSandbox.metal — ALFVEN.1c diagnostic: a GPU 2D FFT on the staged surface.
//
// WHY THIS EXISTS. Alfvén needs the spike's spectral stabiliser
// `FILT = exp(-36 (k/kmax)^36)` — a near-brick-wall low-pass. ALFVEN.2 measured that no
// LOCAL real-space operator reproduces it: a 3x3 tent high-pass and the spike's own
// biharmonic hyperdiffusion were both swept, and each either bleeds the mid-k band the
// lobes live in or lets the grid scale explode (J came out ~100x the reference either
// way). A brick wall in k-space has to be applied in k-space.
//
// This is the transform, proven standalone before anything depends on it. A wrong FFT
// fails silently and would poison every downstream measurement, so the gate is a
// round-trip identity plus known-signal assertions (`FFTSandboxTests`).
//
// ── Algorithm ───────────────────────────────────────────────────────────────
// Stockham auto-sort radix-2, GATHER form — no bit-reversal pass, and out-of-place,
// which is what the staged ping-pong gives us. The scatter form is
//     y[(j/Ns)*2Ns + (j%Ns)]      = x[j] + w*x[j + N/2]
//     y[(j/Ns)*2Ns + (j%Ns) + Ns] = x[j] - w*x[j + N/2]      for j in [0, N/2)
// with w = exp(-2*pi*i * (j%Ns) / (2Ns)). Inverting the index map gives the gather form
// used below: from output o, recover blk/lo/wing and hence j.
//
// One pass per stage ITERATION, with the butterfly span Ns = 1 << pass.index. That is
// exactly what ALFVEN.1c's `StagedPassInfo` was added for — before it, `iterations` ran
// byte-identical passes and an FFT was not expressible at all.
//
// ── Layout and constraints ──────────────────────────────────────────────────
//   Complex data packed as (re, im) in .rg of an rgba32Float target.
//   Requires POWER-OF-TWO dimensions. Staged textures are drawable-sized, so a preset
//   using this must run its solver on a fixed power-of-two grid rather than at drawable
//   resolution — which is independently what D-244's N^2 finding recommends.
//   Reads use access::read at integer coordinates: no sampler, no filtering, no
//   wing-texel ambiguity in the index math.

// MARK: - Complex helpers

static inline float2 fft_cmul(float2 a, float2 b) {
    return float2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

/// One radix-2 Stockham butterfly, gathered. `o` is this fragment's index along the
/// transform axis, `n` the transform length, `pass` the 0-based pass index.
/// `forward` selects the twiddle sign; the 1/N scaling is applied once, on the final
/// inverse pass, by the caller.
static inline void fft_indices(int o, int n, int pass, thread int& j, thread int& wing,
                               thread float& angle) {
    int ns   = 1 << pass;          // butterfly span for this pass
    int span = ns << 1;
    int blk  = o / span;
    int r    = o - blk * span;
    int lo   = r & (ns - 1);
    wing     = r / ns;             // 0 = additive output, 1 = subtractive
    // Named `wing`, NOT `half`: `half` is an MSL keyword (the 16-bit float
    // type) and shadowing it is Failed Approach #44 verbatim.
    j        = blk * ns + lo;      // partner index, always in [0, n/2)
    angle    = -6.28318530718 * float(lo) / float(span);
}

// MARK: - Stages

/// A known, non-trivial test signal. Real-valued (imaginary part zero), so its transform
/// is conjugate-symmetric and the round-trip has something structured to preserve.
fragment float4 fft_sandbox_source_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    constexpr float kTau = 6.28318530718;
    float2 uv = in.uv;
    float v = sin(kTau * (3.0 * uv.x + 1.0 * uv.y) + 0.7)
            + 0.5 * sin(kTau * (1.0 * uv.x - 5.0 * uv.y) + 2.1)
            + 0.25 * sin(kTau * (11.0 * uv.x + 7.0 * uv.y));
    return float4(v, 0.0, 0.0, 1.0);
}

fragment float4 fft_sandbox_rows_fwd_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_width());
    int j, wing; float angle;
    fft_indices(int(gid.x), n, p.index, j, wing, angle);

    // Pass 0 reads the stage INPUT; later passes read this stage's previous iteration.
    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(uint(j), gid.y)).xy;
        b = inputTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    } else {
        a = prevTex.read(uint2(uint(j), gid.y)).xy;
        b = prevTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    }
    float2 w  = float2(cos(angle), sin(angle));
    float2 wb = fft_cmul(w, b);
    float2 r  = (wing == 0) ? (a + wb) : (a - wb);
    return float4(r, 0.0, 1.0);
}

fragment float4 fft_sandbox_cols_fwd_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_height());
    int j, wing; float angle;
    fft_indices(int(gid.y), n, p.index, j, wing, angle);

    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(gid.x, uint(j))).xy;
        b = inputTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    } else {
        a = prevTex.read(uint2(gid.x, uint(j))).xy;
        b = prevTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    }
    float2 w  = float2(cos(angle), sin(angle));
    float2 wb = fft_cmul(w, b);
    float2 r  = (wing == 0) ? (a + wb) : (a - wb);
    return float4(r, 0.0, 1.0);
}

// Inverse passes: conjugate twiddle. The 1/N normalisation is folded into the LAST pass
// of each axis, which `pass.count` makes knowable without another constant.
fragment float4 fft_sandbox_cols_inv_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_height());
    int j, wing; float angle;
    fft_indices(int(gid.y), n, p.index, j, wing, angle);

    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(gid.x, uint(j))).xy;
        b = inputTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    } else {
        a = prevTex.read(uint2(gid.x, uint(j))).xy;
        b = prevTex.read(uint2(gid.x, uint(j + n / 2))).xy;
    }
    float2 w  = float2(cos(-angle), sin(-angle));
    float2 wb = fft_cmul(w, b);
    float2 r  = (wing == 0) ? (a + wb) : (a - wb);
    if (p.index == p.count - 1) { r /= float(n); }
    return float4(r, 0.0, 1.0);
}

fragment float4 fft_sandbox_rows_inv_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StagedPassInfo& p [[buffer(9)]],
    texture2d<float, access::read> inputTex [[texture(13)]],
    texture2d<float, access::read> prevTex [[texture(20)]]
) {
    uint2 gid = uint2(in.position.xy);
    int n = int(inputTex.get_width());
    int j, wing; float angle;
    fft_indices(int(gid.x), n, p.index, j, wing, angle);

    float2 a, b;
    if (p.index == 0) {
        a = inputTex.read(uint2(uint(j), gid.y)).xy;
        b = inputTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    } else {
        a = prevTex.read(uint2(uint(j), gid.y)).xy;
        b = prevTex.read(uint2(uint(j + n / 2), gid.y)).xy;
    }
    float2 w  = float2(cos(-angle), sin(-angle));
    float2 wb = fft_cmul(w, b);
    float2 r  = (wing == 0) ? (a + wb) : (a - wb);
    if (p.index == p.count - 1) { r /= float(n); }
    return float4(r, 0.0, 1.0);
}

/// The Hou-Li filter itself: `exp(-36 (k/kmax)^36)`, the spike's stabiliser, applied where
/// it belongs — in k-space. Frequencies are in FFT order (0 .. N/2 then negative), so the
/// wavenumber wraps at the halfway point.
fragment float4 fft_sandbox_filter_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> specTex [[texture(13)]]
) {
    uint2 gid = uint2(in.position.xy);
    int w = int(specTex.get_width()), h = int(specTex.get_height());
    int kx = int(gid.x); if (kx > w / 2) { kx -= w; }
    int ky = int(gid.y); if (ky > h / 2) { ky -= h; }
    float kmax = float(w / 2);
    float kr = clamp(sqrt(float(kx * kx + ky * ky)) / kmax, 0.0, 1.0);
    float filt = exp(-36.0 * pow(kr, 36.0));
    return float4(specTex.read(gid).xy * filt, 0.0, 1.0);
}

/// Diagnostic view: round-trip error against the source, amplified so any deviation is
/// visible rather than merely small.
fragment float4 fft_sandbox_compose_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float, access::read> sourceTex [[texture(13)]],
    texture2d<float, access::read> roundTripTex [[texture(14)]]
) {
    uint2 gid = uint2(in.position.xy);
    float src = sourceTex.read(gid).x;
    float rt  = roundTripTex.read(gid).x;
    float err = abs(src - rt);
    float3 col = float3(0.05, 0.06, 0.09) + float3(0.35, 0.75, 0.55) * (src * 0.5 + 0.5);
    col += float3(1.0, 0.2, 0.2) * saturate(err * 1000.0);   // error in red, 1e-3 = full
    return float4(min(col, float3(1.0)), 1.0);
}
