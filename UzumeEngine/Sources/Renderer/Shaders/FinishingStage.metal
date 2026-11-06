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
//   (VQ.2) finish_region_kernel   — on HDR only: the transformed image's mean light (brightest
//                                   channel) below and above SDR white in a 6×6 grid of cells, so
//                                   the composite caps every ninth of the screen (any 2×2 block of
//                                   cells) at an average of SDR white — HDR highlights stay small.
//   (VQ.2b) finish_clamp_fragment — a display-referred scene only (a legacy scene's own colour, written
//                                   unclamped): its SDR part, clamped into an 8-bit target at the legacy
//                                   codes; the composite stretches that and adds the HDR ramp of the rest.
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
    float headroom;          // display peak / SDR white (VQ.2: the display's, capped; 1 on SDR)
    float lottesA;           // curve contrast
    float lottesD;           // curve shoulder
    float lottesB;           // solved on the CPU
    float lottesC;           // solved on the CPU
    float ditherLSB;         // one output code value in encoded units (1/255), 0 = off
    float bloomLevels;       // number of chain levels summed into the base
    uint  frame;             // temporal dither index
    uint  useLUT;            // 1 = sample the 3D LUT at texture(2)
    uint  hdrOutput;         // 1 = linear float output: light above SDR white kept, region-capped (VQ.2); 2 = uncapped (tests' negative control)
    uint  displayReferred;   // 1 = the scene's light is already display-referred (VQ.2b): no grade, no curve below white
    float overRise;          // most a cell's mean light above white may change this frame (VQ.2b); 0 = not eased
};

/// Region grid (VQ.2): 6×6 cells, so a ninth of the screen (FlashAnalyzer v2's 3×3 grid and its
/// half-shifted 2×2) is a 2×2 block of cells; the cap holds for all 25 such blocks.
static constant int kRegionCells = 6;
/// Samples per cell side in the region kernel (one 16×16 threadgroup, 4×4 samples per thread).
static constant int kRegionSamples = 64;

static constant float3 kFinishLuma = float3(0.2126, 0.7152, 0.0722);
static constant float kMidGrey = 0.18;
/// HDR highlight ramp (VQ.2a), mirrors `FinishingStage.hdrKneeIn` / `lottesHDRMax`: graded scene
/// light below the knee shows exactly as on SDR; from it to the curve's max it ramps to the peak.
static constant float kHDRKneeIn = 1.0;
static constant float kLottesHDRMax = 8.0;
/// Most the eased light (VQ.2b) may lift what is left above white when the scene's own dips.
static constant float kOverEaseMaxGain = 2.0;

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

/// Grade (scene-referred: exposure, contrast about mid-grey, saturation) then the Lottes display
/// transform, per channel: linear scene light → linear display light in [0, headroom]. On HDR the
/// SDR curve is kept and only light above the knee gains the extra headroom (VQ.2a: scaling the
/// whole curve lifted every upper midtone — Ferrofluid's spike sides doubled, not its glints).
/// (A display-referred scene, VQ.2b, skips it: `finish_display_referred_over`.)
static inline float3 finish_tone(float3 c, constant FinishUniforms& u) {
    c = max(c * u.exposure, 0.0);
    c = kMidGrey * pow(c / kMidGrey, u.contrast);
    c = max(mix(float3(dot(c, kFinishLuma)), c, u.saturation), 0.0);
    float3 z = pow(c, u.lottesA);
    float3 y = z / (pow(z, u.lottesD) * u.lottesB + u.lottesC);
    if (u.headroom > 1.0) {
        y += (u.headroom - 1.0) * smoothstep(log2(kHDRKneeIn), log2(kLottesHDRMax), log2(max(c, 1e-6)));
    }
    return y;
}

/// The scene plus its bloom, as the composite and the region kernel both read it.
static inline float3 finish_scene(texture2d<float> scene, texture2d<float> bloom, sampler samp,
                                  float2 uv, constant FinishUniforms& u) {
    float3 c = scene.sample(samp, uv, level(0)).rgb;
    if (u.bloomStrength > 0.0) {
        c += bloom.sample(samp, uv, level(0)).rgb * (u.bloomStrength / u.bloomLevels);
    }
    return c;
}

/// The light above SDR white of a display-referred scene (VQ.2b) at `uv`: the HDR ramp per texel of the
/// float frame target, THEN interpolated. Interpolating its unclamped light first would let a texel at 10×
/// white bleed into its dark neighbours on a stretch (tier-1: the scene at 2560×1440 into 4K). 0 on SDR.
static inline float3 finish_display_referred_over(texture2d<float> scene, float2 uv, constant FinishUniforms& u) {
    if (u.headroom <= 1.0) { return 0.0; }
    int2 hi = int2(scene.get_width(), scene.get_height()) - 1;
    float2 p = uv * float2(hi + 1) - 0.5;
    float2 f = fract(p);
    int2 i = int2(floor(p));
    float3 t[4];
    for (int k = 0; k < 4; k++) {
        float3 c = max(scene.read(uint2(clamp(i + int2(k & 1, k >> 1), int2(0), hi))).rgb, 1e-6);
        t[k] = (u.headroom - 1.0) * smoothstep(log2(kHDRKneeIn), log2(kLottesHDRMax), log2(c));
    }
    return mix(mix(t[0], t[1], f.x), mix(t[2], t[3], f.x), f.y);
}

/// The share of a pixel's light above SDR white that may stay (VQ.2): for every ninth of the
/// screen (2×2 block of cells) containing the pixel's cell, the largest k with
/// mean(min(c,1)) + k · mean(max(c−1,0)) ≤ 1 (brightest channel; it bounds every channel's mean),
/// then the smallest of those. 1 when nothing is capped. The light above white is the cell's eased mean,
/// which is the measured one for every scene but a display-referred one (VQ.2b).
static inline float finish_region_keep(float2 uv, constant float3* cells) {
    int2 cell = min(int2(uv * float(kRegionCells)), int2(kRegionCells - 1));
    float keep = 1.0;
    for (int wy = max(cell.y - 1, 0); wy <= min(cell.y, kRegionCells - 2); wy++) {
        for (int wx = max(cell.x - 1, 0); wx <= min(cell.x, kRegionCells - 2); wx++) {
            float3 m = (cells[wy * kRegionCells + wx] + cells[wy * kRegionCells + wx + 1]
                      + cells[(wy + 1) * kRegionCells + wx] + cells[(wy + 1) * kRegionCells + wx + 1]) * 0.25;
            if (m.z > 1e-6) { keep = min(keep, saturate((1.0 - m.x) / m.z)); }
        }
    }
    return keep;
}

/// How much of a display-referred scene's light above white shows this frame (VQ.2b, Matt: "Shine eases
/// in"): the eased mean over the measured mean, each interpolated between cell centres. The ratio of the
/// interpolated means, not the interpolated ratios: an empty cell beside a bright one would otherwise let
/// the bright cell's light through near their edge at full strength.
static inline float finish_over_ease(float2 uv, constant float3* cells) {
    float2 p = uv * float(kRegionCells) - 0.5;
    float2 f = fract(p);
    int2 i = int2(floor(p));
    float3 c[4];
    for (int k = 0; k < 4; k++) {
        int2 cell = clamp(i + int2(k & 1, k >> 1), int2(0), int2(kRegionCells - 1));
        c[k] = cells[cell.y * kRegionCells + cell.x];
    }
    float3 m = mix(mix(c[0], c[1], f.x), mix(c[2], c[3], f.x), f.y);
    return m.y > 1e-6 ? min(m.z / m.y, kOverEaseMaxGain) : 1.0;
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

// MARK: - Region cells (VQ.2, HDR only)

/// One threadgroup per cell: the transformed image's mean light below and above SDR white, in its
/// BRIGHTEST channel (so a saturated-red flash is capped like a white one, not let through by red's
/// small share of luminance), from a 64×64 grid of bilinear samples (each a 2×2 average) — the cap
/// concerns a ninth of the screen, so a sampled mean is enough.
/// `cells[i]` = (mean max-channel of min(c,1), mean max-channel of max(c−1,0), eased over-white mean).
/// The eased mean (VQ.2b) moves by at most `overRise` a frame, either way: a ninth's light above white
/// cannot swing fast, so it cannot turn a swing of the SDR picture's into a flash.
kernel void finish_region_kernel(
    constant FinishUniforms& u                  [[buffer(0)]],
    device float3* cells                        [[buffer(1)]],
    texture2d<float> scene                      [[texture(0)]],
    texture2d<float> bloom                      [[texture(1)]],
    texture2d<float> sdr                        [[texture(3)]],
    sampler samp                                [[sampler(0)]],
    uint2 group                                 [[threadgroup_position_in_grid]],
    uint2 tid                                   [[thread_position_in_threadgroup]],
    uint lane                                   [[thread_index_in_simdgroup]],
    uint simd                                   [[simdgroup_index_in_threadgroup]]
) {
    float2 sum = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            float2 s = float2(tid * 4 + uint2(x, y)) + 0.5;
            float2 uv = (float2(group) + s / float(kRegionSamples)) / float(kRegionCells);
            float3 c = u.displayReferred != 0
                ? sdr.sample(samp, uv, level(0)).rgb + finish_display_referred_over(scene, uv, u)
                : finish_tone(finish_scene(scene, bloom, samp, uv, u), u);
            c = min(c, u.headroom);
            sum += float2(finish_max3(min(c, 1.0)), finish_max3(max(c - 1.0, 0.0)));
        }
    }
    threadgroup float2 partial[8];
    sum = simd_sum(sum);
    if (lane == 0) { partial[simd] = sum; }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid.x == 0 && tid.y == 0) {
        float2 total = 0.0;
        for (int i = 0; i < 8; i++) { total += partial[i]; }
        total /= float(kRegionSamples * kRegionSamples);
        int cell = group.y * kRegionCells + group.x;
        float eased = cells[cell].z;
        cells[cell] = float3(total, u.overRise > 0.0 ? eased + clamp(total.y - eased, -u.overRise, u.overRise) : total.y);
    }
}

// MARK: - Pass 4: Composite (transform + grade + dither, fused)

/// Writes the output (the drawable, or a finished image when something follows the finish).
/// The SDR part (up to SDR white) is graded, LUT-mapped and dithered exactly as before VQ.2. On an
/// `_srgb` output the hardware encodes on write, so the dither is applied to the ENCODED value and
/// decoded back — dithering linear values would put ±1 LSB of noise in the wrong place, too small
/// exactly in the dark gradients it is for. On an HDR (linear float) output the light above SDR
/// white is added back after, scaled by the regional cap (VQ.2).
fragment float4 finish_composite_fragment(
    VertexOut in                    [[stage_in]],
    constant FinishUniforms& u      [[buffer(0)]],
    constant float3* cells          [[buffer(1)]],
    texture2d<float> scene          [[texture(0)]],
    texture2d<float> bloom          [[texture(1)]],
    texture3d<float> lut            [[texture(2)]],
    texture2d<float> sdr            [[texture(3)]],
    sampler samp                    [[sampler(0)]]
) {
    // VQ.2b: a display-referred scene's SDR part is its clamped light at the legacy frame target's own
    // 8-bit codes (finish_clamp_fragment), stretched by the sampler as the legacy present step does — the
    // legacy picture, codes and all; only the light above white comes from the float target.
    bool displayReferred = u.displayReferred != 0;
    float3 c = displayReferred ? sdr.sample(samp, in.uv, level(0)).rgb
                               : finish_tone(finish_scene(scene, bloom, samp, in.uv, u), u);

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
    float3 decoded = finish_srgb_decode(encoded);
    if (u.hdrOutput == 0) { return float4(decoded, 1.0); }
    // Per pixel at most the headroom (the curve rises slightly past hdrMax); per ninth, the cap.
    float3 over = displayReferred ? finish_display_referred_over(scene, in.uv, u) : max(c - 1.0, 0.0);
    if (u.overRise > 0.0) { over *= finish_over_ease(in.uv, cells); }
    over = min(over, u.headroom - 1.0);
    if (u.hdrOutput == 1) { over *= finish_region_keep(in.uv, cells); }
    return float4(decoded + over, 1.0);
}

// MARK: - Display-referred SDR part (VQ.2b)

/// A display-referred scene's frame target, clamped to SDR white into an 8-bit sRGB target: the hardware
/// store gives each pixel the code the legacy frame target stored (exact rounding does not — it missed the
/// legacy oracle by 2 codes, measured).
fragment float4 finish_clamp_fragment(VertexOut in [[stage_in]], texture2d<float> scene [[texture(0)]]) {
    return float4(saturate(scene.read(uint2(in.position.xy)).rgb), 1.0);
}
