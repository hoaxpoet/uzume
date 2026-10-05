// Inari.metal — a night shrine drawn twice by the artist; only its light changes.
//
// The moonlit drawing (texture 9) is the scene: every line and texture comes from it. Each pixel
// belongs to at most one light source (texture 11, g = source id, r = its rank down that light's
// drawn falloff, 0 faint … 1 hot core) whose level this frame sits at buffer(6). A pixel is
// brightened smoothly by the drawn light's own ratio — blurred lit / blurred unlit luminance,
// read off mip ~2.8 so the two drawings' different fine texture never shows — raised to the
// level, and takes on the lit drawing's hue as it rises. The hot cores (lit paper, the eyes) fade
// from one drawing to the other, as glows do. Level 0 = the moonlit drawing; 1 = the lit drawing.
// See `InariState.swift` for which stem drives which light, and docs/presets/INARI_DESIGN.md.
//
// Unbound fallback: generic harnesses bind neither the drawings nor slot 6. `is_null_texture`
// catches that before buffer(6) is read, and a still night-teal field is returned (D-037: never
// black; never animated on `features.time`, which production never reads — the Fireflies FF.2
// lesson).

constant float kInariImageAspect = 1.5;          // 1536 × 1024
constant float kInariBlurMip = 2.8;
constant float kInariLevels = 64;                // InariState.maxLights

static inline float inari_lum(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

fragment float4 inari_fragment(VertexOut in [[stage_in]],
                               constant FeatureVector& features [[buffer(0)]],
                               constant float* levels [[buffer(6)]],
                               texture2d<float> unlitT [[texture(9)]],
                               texture2d<float> litT [[texture(10)]],
                               texture2d<float> lightsT [[texture(11)]]) {
    if (is_null_texture(unlitT) || is_null_texture(litT) || is_null_texture(lightsT)) {
        return float4(mix(float3(0.006, 0.012, 0.018), float3(0.02, 0.04, 0.055), 1.0 - in.uv.y), 1.0);
    }
    // Fill the drawable with the drawing, cropping the overflow. A wide screen crops top and
    // bottom, weighted toward the bottom so the foxes' ears and the moon stay in.
    float aspect = features.aspect_ratio > 0.0 ? features.aspect_ratio : 16.0 / 9.0;
    float2 uv = in.uv;
    if (aspect > kInariImageAspect) {
        float sy = kInariImageAspect / aspect;
        uv.y = (1.0 - sy) * 0.2 + uv.y * sy;
    } else {
        float sx = aspect / kInariImageAspect;
        uv.x = (1.0 - sx) * 0.5 + uv.x * sx;
    }

    constexpr sampler smooth(filter::linear, mip_filter::linear, address::clamp_to_edge);
    constexpr sampler exact(filter::nearest, address::clamp_to_edge);
    float3 un = unlitT.sample(smooth, uv, level(0)).rgb;
    float4 m = lightsT.sample(exact, uv);
    int id = int(m.g * 255.0 + 0.5);
    if (id <= 0 || id > int(kInariLevels)) return float4(un, 1.0);

    float L = max(levels[id - 1], 0.0);
    float3 li = litT.sample(smooth, uv, level(0)).rgb;
    float3 unB = unlitT.sample(smooth, uv, level(kInariBlurMip)).rgb;
    float3 liB = litT.sample(smooth, uv, level(kInariBlurMip)).rgb;
    const float e = 0.004;
    float g = clamp((inari_lum(liB) + e) / (inari_lum(unB) + e), 1.0, 32.0);

    // Smooth light: brightness × g^L; hue toward the lit drawing's where the drawn light is strong.
    float yU = max(inari_lum(un), 1e-5);
    float3 hueU = un / yU, hueL = liB / max(inari_lum(liB), 1e-4);
    float3 lit = yU * pow(g, L) * mix(hueU, hueL, saturate(L) * smoothstep(1.0, 1.6, g));

    // Hot cores: a crossfade between the drawings, pushed past the drawing above 1.
    float3 glow = mix(un, li, saturate(L)) + max(li - un, 0.0) * max(L - 1.0, 0.0) * 0.8;
    float3 col = mix(lit, glow, smoothstep(0.75, 0.9, m.r));
    return float4(col, 1.0);
}
