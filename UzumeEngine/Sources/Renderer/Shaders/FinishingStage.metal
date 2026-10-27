// FinishingStage.metal — the cinematic finish (VQ.1, Phase VQ).
//
// A scene in `cinematic` finish mode renders linear HDR into an `.rgba16Float` frame target;
// these passes turn it into the displayed image. Legacy scenes never run them.
//
//   1. finish_prefilter_kernel    — frame target → bloom base (fixed 540 px tall), box-averaged
//                                   over the footprint, Karis-weighted, soft-knee threshold
//   2. finish_downsample_kernel   — 13-tap downsample, base → … → coarsest level
//   3. finish_upsample_kernel     — 3×3 tent upsample, ADDED in place into the finer level
//   4. finish_composite_fragment  — scene + bloom → exposure / contrast / saturation → Lottes
//                                   display transform (explicit headroom) → optional 3D LUT →
//                                   TPDF dither in the encoded (sRGB) domain → output
//
// Sources ported:
//   - Bloom chain: J. Jimenez, "Next Generation Post Processing in Call of Duty: Advanced
//     Warfare", SIGGRAPH 2014 Advances — the 13-tap downsample (weights 0.5 inner box +
//     4 × 0.125 outer boxes), the Karis average on the first downsample, the 3×3 tent upsample.
//   - Soft knee: the quadratic knee of Unity's PostProcessing v2 bloom (after Karis).
//   - Display transform: T. Lottes, "Advanced Techniques and Optimization of HDR Color
//     Pipelines", GDC 2016 — y = xᵃ / (xᵃᵈ·b + c), b and c solved on the CPU from
//     (hdrMax, midIn, midOut). The headroom input scales the output range and keeps mid-grey.
//   - Dither noise: interleaved gradient noise with the golden-ratio temporal step, the same
//     generator as Presets/Shaders/Utilities/Noise/BlueNoise.metal `ign_temporal` (the renderer
//     library is a separate compilation unit, so it is restated here), remapped to a triangular
//     PDF.
//
// Every spatial constant is relative to frame HEIGHT: the chain starts at a fixed 540-px base
// whatever the frame size, so one base texel is 1/540 of the height at 1080p, 1440p and 4K
// alike and the glow covers the same fraction of the screen on every display.
//
// 1–3 run as compute in one encoder; 4 is one render pass using `fullscreen_vertex` / `VertexOut`
// from Common.metal (concatenated ahead by ShaderLibrary).

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniforms

/// Mirrors `FinishUniforms` in FinishingStage.swift. Keep the two in step.
struct FinishUniforms {
    float bloomStrength;     // bloom added to the scene (× the normalised chain)
    float bloomThreshold;    // linear brightness where bloom starts
    float bloomKnee;         // soft-knee half-width, as a fraction of the threshold
    float exposure;          // linear scale, 2^stops
    float contrast;          // power about mid-grey (1 = none)
    float saturation;        // 0 = grey, 1 = none
    float headroom;          // display peak / SDR white; 1.0 until VQ.2 feeds EDR headroom
    float lottesA;           // curve contrast
    float lottesD;           // curve shoulder
    float lottesB;           // solved on the CPU
    float lottesC;           // solved on the CPU
    float ditherLSB;         // one output code value in encoded units (1/255), 0 = off
    float bloomLevels;       // number of chain levels summed into the base
    uint  frame;             // temporal dither index
    uint  useLUT;            // 1 = sample the 3D LUT at texture(2)
    uint  pad;
};

static constant float3 kFinishLuma = float3(0.2126, 0.7152, 0.0722);
static constant float kMidGrey = 0.18;

// MARK: - Helpers

static inline float finish_max3(float3 c) { return max(c.r, max(c.g, c.b)); }

/// Karis average weight: 1 / (1 + luma) — damps single-pixel fireflies before they bloom.
static inline float finish_karis(float3 c) { return 1.0 / (1.0 + dot(c, kFinishLuma)); }

static inline float3 finish_srgb_encode(float3 c) {
    c = max(c, 0.0);
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

static inline float3 finish_srgb_decode(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

/// IGN with the golden-ratio temporal step (BlueNoise.metal `ign_temporal`).
static inline float finish_ign_temporal(float2 pixel, uint frame) {
    float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    float base = fract(magic.z * fract(dot(pixel, magic.xy)));
    return fract(base + float(frame) * 0.6180339887);
}

/// Uniform [0,1) → triangular PDF on (−1, 1), keeping the noise's spectrum.
static inline float finish_tpdf(float u) {
    float o = u * 2.0 - 1.0;
    return sign(o) * (1.0 - sqrt(1.0 - abs(o)));
}

// MARK: - Bloom chain (compute — one encoder for all eleven steps; as render passes each small
// level cost ~75 µs of fixed pass overhead, measured, 0.6 ms of the chain at 4K)

/// Frame target → bloom base. Each base texel box-averages its footprint in the source with up
/// to 4×4 bilinear taps (each tap averages a 2×2 quad), so a 4K frame is not point-sampled into
/// the 540-px base, then the soft knee thresholds the average. A plain average: the Karis weight
/// belongs to the first downsample, where its footprint is the same at every frame size (weighting
/// per tap here made 4K's glow ~6 % smaller than 1080p's, measured).
kernel void finish_prefilter_kernel(
    constant FinishUniforms& u                  [[buffer(0)]],
    texture2d<float> scene                      [[texture(0)]],
    texture2d<float, access::write> base        [[texture(1)]],
    sampler samp                                [[sampler(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    if (gid.x >= base.get_width() || gid.y >= base.get_height()) { return; }
    float2 baseTexel = 1.0 / float2(base.get_width(), base.get_height());
    float2 uv = (float2(gid) + 0.5) * baseTexel;
    float footprint = float(scene.get_height()) * baseTexel.y;   // source texels per base texel
    // − 1e-3: 1080 × (1/540) rounds to just above 2, which must stay ONE 2×2 tap, not four.
    int taps = clamp(int(ceil(footprint * 0.5 - 1e-3)), 1, 4);
    float3 sum = 0.0;
    for (int y = 0; y < 4; y++) {
        if (y >= taps) { break; }
        for (int x = 0; x < 4; x++) {
            if (x >= taps) { break; }
            float2 offset = (float2(x, y) + 0.5) / float(taps) - 0.5;
            sum += scene.sample(samp, uv + offset * baseTexel, level(0)).rgb;
        }
    }
    float3 c = sum / float(taps * taps);

    // Soft knee: quadratic ramp across [threshold − knee, threshold + knee], linear above.
    float knee = max(u.bloomThreshold * u.bloomKnee, 1e-4);
    float brightness = finish_max3(c);
    float rq = clamp(brightness - (u.bloomThreshold - knee), 0.0, 2.0 * knee);
    rq = rq * rq * (0.25 / knee);
    float contribution = max(rq, brightness - u.bloomThreshold) / max(brightness, 1e-4);
    base.write(float4(c * contribution, 1.0), gid);
}

/// Jimenez 13-tap downsample: weights 0.5 for the inner 2×2 box, 0.125 for each of four outer
/// boxes; on the first level (`karis` = 1) each box is weighted by its Karis average, so a single
/// bright pixel cannot dominate the glow.
kernel void finish_downsample_kernel(
    texture2d<float> src                        [[texture(0)]],
    texture2d<float, access::write> dst         [[texture(1)]],
    constant uint& karis                        [[buffer(1)]],
    sampler samp                                [[sampler(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float2 t = 1.0 / float2(src.get_width(), src.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
    float3 a = src.sample(samp, uv + t * float2(-2,  2), level(0)).rgb;
    float3 b = src.sample(samp, uv + t * float2( 0,  2), level(0)).rgb;
    float3 c = src.sample(samp, uv + t * float2( 2,  2), level(0)).rgb;
    float3 d = src.sample(samp, uv + t * float2(-2,  0), level(0)).rgb;
    float3 e = src.sample(samp, uv, level(0)).rgb;
    float3 f = src.sample(samp, uv + t * float2( 2,  0), level(0)).rgb;
    float3 g = src.sample(samp, uv + t * float2(-2, -2), level(0)).rgb;
    float3 h = src.sample(samp, uv + t * float2( 0, -2), level(0)).rgb;
    float3 i = src.sample(samp, uv + t * float2( 2, -2), level(0)).rgb;
    float3 j = src.sample(samp, uv + t * float2(-1,  1), level(0)).rgb;
    float3 k = src.sample(samp, uv + t * float2( 1,  1), level(0)).rgb;
    float3 l = src.sample(samp, uv + t * float2(-1, -1), level(0)).rgb;
    float3 m = src.sample(samp, uv + t * float2( 1, -1), level(0)).rgb;
    float3 inner = (j + k + l + m) * 0.25;
    float3 boxes[4] = { (a + b + d + e) * 0.25, (b + c + e + f) * 0.25,
                        (d + e + g + h) * 0.25, (e + f + h + i) * 0.25 };
    float wInner = 0.5 * (karis != 0 ? finish_karis(inner) : 1.0);
    float3 sum = inner * wInner;
    float weight = wInner;
    for (int n = 0; n < 4; n++) {
        float w = 0.125 * (karis != 0 ? finish_karis(boxes[n]) : 1.0);
        sum += boxes[n] * w;
        weight += w;
    }
    dst.write(float4(sum / weight, 1.0), gid);
}

/// 3×3 tent upsample of the coarser level, ADDED into the finer level in place.
kernel void finish_upsample_kernel(
    texture2d<float> src                        [[texture(0)]],
    texture2d<float, access::read_write> dst    [[texture(1)]],
    sampler samp                                [[sampler(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float2 t = 1.0 / float2(src.get_width(), src.get_height());
    float2 uv = (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height());
    float3 s = src.sample(samp, uv, level(0)).rgb * 4.0;
    s += src.sample(samp, uv + t * float2(-1,  0), level(0)).rgb * 2.0;
    s += src.sample(samp, uv + t * float2( 1,  0), level(0)).rgb * 2.0;
    s += src.sample(samp, uv + t * float2( 0, -1), level(0)).rgb * 2.0;
    s += src.sample(samp, uv + t * float2( 0,  1), level(0)).rgb * 2.0;
    s += src.sample(samp, uv + t * float2(-1, -1), level(0)).rgb;
    s += src.sample(samp, uv + t * float2( 1, -1), level(0)).rgb;
    s += src.sample(samp, uv + t * float2(-1,  1), level(0)).rgb;
    s += src.sample(samp, uv + t * float2( 1,  1), level(0)).rgb;
    dst.write(float4(dst.read(gid).rgb + s * (1.0 / 16.0), 1.0), gid);
}

// MARK: - Pass 4: Composite (transform + grade + dither, fused)

/// Writes the output (the drawable, or a finished image when something follows the finish).
/// The output is an `_srgb` target: the hardware encodes on write, so the dither is applied to
/// the ENCODED value and decoded back — dithering linear values would put ±1 LSB of noise in
/// the wrong place, too small exactly in the dark gradients it is for.
fragment float4 finish_composite_fragment(
    VertexOut in                    [[stage_in]],
    constant FinishUniforms& u      [[buffer(0)]],
    texture2d<float> scene          [[texture(0)]],
    texture2d<float> bloom          [[texture(1)]],
    texture3d<float> lut            [[texture(2)]],
    sampler samp                    [[sampler(0)]]
) {
    float3 c = scene.sample(samp, in.uv).rgb;
    if (u.bloomStrength > 0.0) {
        c += bloom.sample(samp, in.uv).rgb * (u.bloomStrength / u.bloomLevels);
    }

    // Grade (scene-referred): exposure, contrast about mid-grey, saturation.
    c = max(c * u.exposure, 0.0);
    c = kMidGrey * pow(c / kMidGrey, u.contrast);
    c = max(mix(float3(dot(c, kFinishLuma)), c, u.saturation), 0.0);

    // Lottes display transform, per channel; output range [0, headroom].
    float3 z = pow(c, u.lottesA);
    c = u.headroom * z / (pow(z, u.lottesD) * u.lottesB + u.lottesC);

    // Optional creative LUT, indexed by the encoded colour (the .cube convention).
    float3 encoded = finish_srgb_encode(min(c, 1.0));
    if (u.useLUT != 0) {
        float n = float(lut.get_width());
        float3 coord = encoded * ((n - 1.0) / n) + 0.5 / n;
        encoded = lut.sample(samp, coord).rgb;
    }

    // TPDF dither, ±1 LSB of the output, in the encoded domain — then rounded to the output code
    // here: the GPU's own sRGB store does not round exactly (it disagreed with exact rounding on
    // ~10 % of pixels, measured), and that bias put back the banding the dither removes. A value
    // decoded from an exact code value round-trips through the store to that code.
    if (u.ditherLSB > 0.0) {
        float noise = finish_tpdf(finish_ign_temporal(in.position.xy, u.frame));
        encoded = saturate(encoded + noise * u.ditherLSB);
        encoded = floor(encoded / u.ditherLSB + 0.5) * u.ditherLSB;
    }
    return float4(finish_srgb_decode(encoded), 1.0);
}
