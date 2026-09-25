// Kagura.metal — the point-light dancer's look B (KAG.2; KAGURA_DESIGN §8).
//
// A port of the KAG.0 spike's `render()` (docs/presets/kagura_spike/kagura.py), which Matt chose
// as look B from reference 01 (docs/VISUAL_REFERENCES/kagura/01_macro_twist_point_light_trails.png):
//
//   trail *= 0.05^(dt / 0.4 s)                       (per ELAPSED time, not per frame — BUG-097)
//   trail += amber Gaussian splats along each joint's path since the last frame
//   img    = ground + trail + halo + core            (warm-white points: σ 9 px ×0.22, σ 2.6 px ×1)
//   out    = 1 − exp(−1.6 · img)                     (soft filmic shoulder)
//
// The spike splatted six sub-samples per 30 fps frame (180 splats a second, amplitude 0.22,
// σ 2.4 px). Here each joint deposits one LINE SEGMENT per frame, prev → current, whose
// cross-section is the exact integral of those splats along the segment: the deposit is
// `rate · dt` spread over the segment's length. That is what makes the trail frame-rate
// independent — at 30, 60 or 120 fps the same motion leaves the same trail (KaguraTrailDecayTests).
//
// Nothing here reads audio. The beat moves the pose; it never brightens anything (D-157).
// `VertexOut` / `fullscreen_vertex` come from Common.metal (same compilation unit).

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared layouts (mirror of Swift KaguraConfig / KaguraJoint)

struct KaguraConfig {
    float4 frame;      // x,y: target size px; z: this frame's trail multiplier; w: deposit (splats)
    float4 sigmas;     // x: trail σ px; y: core σ px; z: halo σ px; w: shoulder gain
    float4 amps;       // x: core amplitude; y: halo amplitude
    float4 ground;     // rgb, pre-shoulder
    float4 trail_rgb;  // amber
    float4 dot_rgb;    // warm white
};

struct KaguraJoint {
    float4 ends;       // xy: previous-frame position px, zw: current position px (y down)
};

// MARK: - Helpers

/// Standard normal CDF via Abramowitz–Stegun 7.1.26 (|error| < 1.5e-7). MSL has no erf.
static inline float kagura_phi(float z) {
    float x = fabs(z) * 0.70710678;
    float t = 1.0 / (1.0 + 0.3275911 * x);
    float poly = ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t
                  + 0.254829592) * t;
    float erf_abs = 1.0 - poly * exp(-x * x);
    return 0.5 * (1.0 + sign(z) * erf_abs);
}

static inline float2 kagura_to_ndc(float2 px, float2 size) {
    return float2(px.x / size.x * 2.0 - 1.0, 1.0 - px.y / size.y * 2.0);
}

/// sRGB-encoded value → linear. The spike wrote its values straight into 8-bit video; the drawable
/// is `_srgb`, so decoding here makes the displayed bytes equal the spike's.
static inline float3 kagura_srgb_to_linear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// MARK: - Trail: decay

fragment float4 kagura_trail_decay_fragment(VertexOut in [[stage_in]],
                                            constant KaguraConfig& cfg [[buffer(0)]],
                                            texture2d<float, access::read> src [[texture(0)]]) {
    uint2 p = uint2(in.position.xy);
    return float4(src.read(p).rgb * cfg.frame.z, 1.0);
}

// MARK: - Trail: deposit one segment per joint

struct KaguraSegOut {
    float4 position [[position]];
    float2 a;          // segment start, px
    float2 b;          // segment end, px
};

vertex KaguraSegOut kagura_segment_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                          device const KaguraJoint* joints [[buffer(0)]],
                                          constant KaguraConfig& cfg [[buffer(1)]]) {
    KaguraSegOut o;
    float2 a = joints[iid].ends.xy, b = joints[iid].ends.zw;
    float2 d = b - a;
    float len = length(d);
    float2 dir = len > 1e-4 ? d / len : float2(1.0, 0.0);
    float2 nrm = float2(-dir.y, dir.x);
    float reach = 3.0 * cfg.sigmas.x + 1.0;
    // Triangle-strip corners: along ∈ {−reach, len + reach}, across ∈ {−reach, +reach}.
    float along = (vid & 1u) ? len + reach : -reach;
    float across = (vid & 2u) ? reach : -reach;
    float2 px = a + dir * along + nrm * across;
    o.position = float4(kagura_to_ndc(px, cfg.frame.xy), 0.0, 1.0);
    o.a = a;
    o.b = b;
    return o;
}

/// ∫₀¹ exp(−|p − s(τ)|² / 2σ²) dτ along the segment a→b, times this frame's deposit.
fragment float4 kagura_segment_fragment(KaguraSegOut in [[stage_in]],
                                        constant KaguraConfig& cfg [[buffer(0)]]) {
    float sigma = cfg.sigmas.x;
    float2 p = in.position.xy;
    float2 d = in.b - in.a;
    float len = length(d);
    float value;
    if (len < 0.05 * sigma) {
        float2 r = p - (in.a + in.b) * 0.5;
        value = exp(-dot(r, r) / (2.0 * sigma * sigma));
    } else {
        float2 dir = d / len;
        float2 pa = p - in.a;
        float x = dot(pa, dir);
        float perp = pa.x * dir.y - pa.y * dir.x;
        float along = kagura_phi((len - x) / sigma) - kagura_phi(-x / sigma);
        value = exp(-perp * perp / (2.0 * sigma * sigma)) * along * (2.5066283 * sigma / len);
    }
    return float4(cfg.trail_rgb.rgb * (value * cfg.frame.w), 0.0);
}

// MARK: - Composite: ground + trail, then the points on top (additive)

fragment float4 kagura_composite_fragment(VertexOut in [[stage_in]],
                                          constant KaguraConfig& cfg [[buffer(0)]],
                                          texture2d<float, access::read> trail [[texture(0)]]) {
    uint2 p = uint2(in.position.xy);
    return float4(cfg.ground.rgb + trail.read(p).rgb, 1.0);
}

struct KaguraDotOut {
    float4 position [[position]];
    float2 centre;     // px
};

vertex KaguraDotOut kagura_dot_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                      device const KaguraJoint* joints [[buffer(0)]],
                                      constant KaguraConfig& cfg [[buffer(1)]]) {
    KaguraDotOut o;
    float2 c = joints[iid].ends.zw;
    float reach = 3.0 * cfg.sigmas.z + 1.0;
    float2 corner = float2((vid & 1u) ? reach : -reach, (vid & 2u) ? reach : -reach);
    o.position = float4(kagura_to_ndc(c + corner, cfg.frame.xy), 0.0, 1.0);
    o.centre = c;
    return o;
}

fragment float4 kagura_dot_fragment(KaguraDotOut in [[stage_in]],
                                    constant KaguraConfig& cfg [[buffer(0)]]) {
    float2 r = in.position.xy - in.centre;
    float r2 = dot(r, r);
    float core = exp(-r2 / (2.0 * cfg.sigmas.y * cfg.sigmas.y)) * cfg.amps.x;
    float halo = exp(-r2 / (2.0 * cfg.sigmas.z * cfg.sigmas.z)) * cfg.amps.y;
    return float4(cfg.dot_rgb.rgb * (core + halo), 0.0);
}

// MARK: - Display: the soft filmic shoulder

fragment float4 kagura_display_fragment(VertexOut in [[stage_in]],
                                        constant KaguraConfig& cfg [[buffer(0)]],
                                        texture2d<float, access::sample> composite [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear, coord::normalized);
    float3 img = composite.sample(s, in.uv).rgb;
    float3 shouldered = 1.0 - exp(-cfg.sigmas.w * max(img, 0.0));
    return float4(kagura_srgb_to_linear(clamp(shouldered, 0.0, 1.0)), 1.0);
}
