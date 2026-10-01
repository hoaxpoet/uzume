// Understory.metal — a bed of feedback-IFS fern fronds (UND.1 look-spike).
//
//   fronds  (persistent rgba16Float)  Flexi's three-map feedback IFS, one per atlas tile
//   bed     (samples fronds)          composite (UND.1: identity — one frond, one tile)
//   present (drawable, samples bed)   flat colour on a dark ground (colour is UND.3)
//
// ── Provenance (docs/presets/UNDERSTORY_DESIGN.md §3) ────────────────────────────
// The fronds stage is PORTED VERBATIM from Flexi, "flexi - fractal seafood" (Milkdrop 2
// original pack), as converted in butterchurn-presets@2.4.7 (sha256 d0ca386c…d9): the warp
// shader's three maps — `// main arm of the fern`, `// the fractals left arm`, `// the right
// arm` in the .milk — with their constants (1.12, 3.3, ±π/4, 0.042, 0.08, −0.015), and the
// additive seed (shape 0: radius 0.0578, red, alpha 1 → 0 centre to edge). The q-variable
// names below are Flexi's, so the port can be read against the source line by line.
//
// Adapted (context only, FA #65):
//   1. The frond lives in a TILE of the drawable instead of the whole frame. `t` is the
//      tile-local uv; sampling is clamped half a texel inside the tile so the bilinear
//      footprint never crosses into a neighbour (Flexi clamps to the frame, [0, 1]).
//   2. fp16 instead of Milkdrop's 8-bit target: values are clamped to [0, 1] to match.
//   3. `ww` / `w` arrive from the CPU springs (UnderstoryField, buffer 6), not frame eqs.
// Metal's uv and GL's uv_orig address texture memory identically here (our fullscreen
// vertex flips y, and the render target's row 0 is uv.y = 0), so the maps are unflipped.

constant uint kUnderstoryMaxFronds = 12;

struct UnderstoryHeader {
    uint frond_count;
    uint pad0;
    uint pad1;
    uint pad2;
};

struct UnderstoryFrond {
    float4 tile;        // drawable uv: origin.xy, size.xy
    float bend;         // Flexi's ww
    float direction;    // Flexi's w
    float pad0;
    float pad1;
};

struct UnderstoryFieldGPU {
    UnderstoryHeader header;
    UnderstoryFrond fronds[kUnderstoryMaxFronds];
};

constant constexpr sampler understory_linear(filter::linear, address::clamp_to_edge);

// Flexi's `texture(sampler_main, clamp(c, 0, 1)).x`, confined to one tile.
static float understory_tap(texture2d<float> prev, float4 tile, float2 halfTexel, float2 c) {
    float2 local = clamp(c, halfTexel, 1.0 - halfTexel);
    return prev.sample(understory_linear, tile.xy + local * tile.zw).x;
}

// MARK: - fronds (persistent)

fragment float4 understory_fronds_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> prev [[texture(20)]]
) {
    float2 size = float2(prev.get_width(), prev.get_height());
    uint count = min(field.header.frond_count, kUnderstoryMaxFronds);
    for (uint i = 0; i < count; i++) {
        UnderstoryFrond fr = field.fronds[i];
        float2 t = (in.uv - fr.tile.xy) / fr.tile.zw;
        if (any(t < 0.0) || any(t > 1.0)) { continue; }

        // Milkdrop's aspect = (aspectx, aspecty, 1/aspectx, 1/aspecty) for this tile.
        float2 px = fr.tile.zw * size;
        float4 aspect = px.x >= px.y ? float4(1.0, px.y / px.x, 1.0, px.x / px.y)
                                     : float4(px.x / px.y, 1.0, px.y / px.x, 1.0);
        float2 halfTexel = 0.5 / px;

        float ww = fr.bend;
        float w = fr.direction;
        float q1 = cos(ww), q2 = sin(ww), q3 = 1.12;
        float q4 = 0.042 * sin(w), q5 = 0.042 * cos(w);
        float a = 0.5 * asin(1.0);
        float d = 0.08;
        float q6 = cos(a), q7 = sin(a), q8 = 3.3;
        float q9 = cos(-w + asin(1.0)) * d * aspect.x;
        float q10 = sin(-w + asin(1.0)) * d * aspect.y;
        float q11 = cos(-a), q12 = sin(-a), q13 = q8;
        float q14 = q9, q15 = q10;

        float2 fa = (t - 0.5) * aspect.xy;
        float2 r3 = float2(fa.x * q1 - fa.y * q2, fa.x * q2 + fa.y * q1);
        float2 r5 = float2(fa.x * q6 - fa.y * q7, fa.x * q7 + fa.y * q6);
        float2 r7 = float2(fa.x * q11 - fa.y * q12, fa.x * q12 + fa.y * q11);

        float main_arm  = understory_tap(prev, fr.tile, halfTexel, 0.5 + r3 * aspect.zw * q3 + float2(q4, q5) * aspect.zw);
        float left_arm  = understory_tap(prev, fr.tile, halfTexel, 0.5 + r5 * aspect.zw * q8 + float2(q9, q10));
        float right_arm = understory_tap(prev, fr.tile, halfTexel, 0.5 + r7 * aspect.zw * q13 + float2(q14, q15));
        float density = max(max(main_arm, max(left_arm, right_arm)) - 0.015, 0.0);

        // Seed: butterchurn draws shape 0 as a triangle fan, radius 0.0578 in clip units
        // (x scaled by aspecty), centre alpha 1 → edge 0, additively blended.
        float2 seedRadius = 0.5 * 0.0578 * float2(aspect.y, aspect.x);
        float seed = max(1.0 - length((t - 0.5) / seedRadius), 0.0);
        return float4(min(density + seed, 1.0), 0.0, 0.0, 1.0);
    }
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - bed

fragment float4 understory_bed_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float> fronds [[texture(13)]]
) {
    // ponytail: identity composite while there is one frond in one tile (UND.2 places fronds).
    return float4(fronds.sample(understory_linear, in.uv).x, 0.0, 0.0, 1.0);
}

// MARK: - present

fragment float4 understory_present_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float> bed [[texture(13)]]
) {
    // UND.1: a flat colour on a dark ground — never black (D-037). Palette is UND.3.
    float density = bed.sample(understory_linear, in.uv).x;
    float3 ground = float3(0.020, 0.024, 0.040);
    float3 frond = float3(0.86, 0.93, 0.90);
    return float4(mix(ground, frond, density), 1.0);
}
