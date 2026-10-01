// Understory.metal — a field of feedback-IFS fern fronds (UND.1 look-spike → UND.2 field).
//
//   fronds  (persistent rgba16Float)  Flexi's three-map feedback IFS, one frond per atlas tile
//   bed     (samples fronds)          the field: each frond placed, leaned and scaled on screen,
//                                     composited far → near with a flat per-layer tint
//   present (drawable, samples bed)   the field over a dark ground (palette is UND.3)
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
//   1. The frond lives in a TILE of the drawable. A tile holds a crop of Flexi's 4:3 frame
//      (`crop`, from UnderstoryLayout: full width, from just below the seed upward) — the
//      maps run in frame coordinates, so cropping changes resolution, not the frond. Sampling
//      is clamped to the frame as Flexi does, then half a texel inside the tile so the
//      bilinear footprint never crosses into a neighbour.
//   2. fp16 instead of Milkdrop's 8-bit target: values are clamped to [0, 1] to match.
//   3. `ww` / `w` arrive from the CPU springs (UnderstoryField, buffer 6), not frame eqs.
// Metal's uv and GL's uv_orig address texture memory identically here (our fullscreen
// vertex flips y, and the render target's row 0 is uv.y = 0), so the maps are unflipped.

constant uint kUnderstoryMaxFronds = 14;

struct UnderstoryHeader {
    uint frond_count;
    uint pad0;
    uint pad1;
    uint pad2;
};

struct UnderstoryFrond {
    float4 tile;    // drawable uv: origin.xy, size.xy
    float4 crop;    // Flexi frame uv held by the tile: x0, y0, x1, y1
    float4 place;   // seed on screen (uv), frame height in screen heights, lean (rad)
    float4 look;    // Flexi's ww, Flexi's w, layer (0 far … 2 near), brightness
};

struct UnderstoryFieldGPU {
    UnderstoryHeader header;
    UnderstoryFrond fronds[kUnderstoryMaxFronds];
};

constant constexpr sampler understory_linear(filter::linear, address::clamp_to_edge);

// Flexi's frame is 4:3: aspect = (aspectx, aspecty, 1/aspectx, 1/aspecty).
constant float4 kFlexiAspect = float4(1.0, 0.75, 1.0, 4.0 / 3.0);

// Flexi's `texture(sampler_main, clamp(c, 0, 1)).x`, with `c` in frame uv, read from this
// frond's tile. Frame uv OUTSIDE the tile's crop reads black: that is the part of Flexi's frame
// the tile does not hold, and it is empty there. Clamping to the crop edge instead (UND.2, first
// try) smeared a coil that touched the edge back through the maps until the whole tile filled
// with a grey ring pattern — Flexi's own clamp is to the frame edge, far from the frond.
static float understory_tap(texture2d<float> prev, UnderstoryFrond fr, float2 halfTexel, float2 c) {
    float2 local = (clamp(c, 0.0, 1.0) - fr.crop.xy) / (fr.crop.zw - fr.crop.xy);
    if (any(local < 0.0) || any(local > 1.0)) { return 0.0; }
    local = clamp(local, halfTexel, 1.0 - halfTexel);
    return prev.sample(understory_linear, fr.tile.xy + local * fr.tile.zw).x;
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

        float4 aspect = kFlexiAspect;
        float2 halfTexel = 0.5 / (fr.tile.zw * size);
        float2 uv = mix(fr.crop.xy, fr.crop.zw, t);   // this pixel in Flexi's frame

        float ww = fr.look.x;
        float w = fr.look.y;
        float q1 = cos(ww), q2 = sin(ww), q3 = 1.12;
        float q4 = 0.042 * sin(w), q5 = 0.042 * cos(w);
        float a = 0.5 * asin(1.0);
        float d = 0.08;
        float q6 = cos(a), q7 = sin(a), q8 = 3.3;
        float q9 = cos(-w + asin(1.0)) * d * aspect.x;
        float q10 = sin(-w + asin(1.0)) * d * aspect.y;
        float q11 = cos(-a), q12 = sin(-a), q13 = q8;
        float q14 = q9, q15 = q10;

        float2 fa = (uv - 0.5) * aspect.xy;
        float2 r3 = float2(fa.x * q1 - fa.y * q2, fa.x * q2 + fa.y * q1);
        float2 r5 = float2(fa.x * q6 - fa.y * q7, fa.x * q7 + fa.y * q6);
        float2 r7 = float2(fa.x * q11 - fa.y * q12, fa.x * q12 + fa.y * q11);

        float main_arm  = understory_tap(prev, fr, halfTexel, 0.5 + r3 * aspect.zw * q3 + float2(q4, q5) * aspect.zw);
        float left_arm  = understory_tap(prev, fr, halfTexel, 0.5 + r5 * aspect.zw * q8 + float2(q9, q10));
        float right_arm = understory_tap(prev, fr, halfTexel, 0.5 + r7 * aspect.zw * q13 + float2(q14, q15));
        float density = max(max(main_arm, max(left_arm, right_arm)) - 0.015, 0.0);

        // Seed: butterchurn draws shape 0 as a triangle fan, radius 0.0578 in clip units
        // (x scaled by aspecty), centre alpha 1 → edge 0, additively blended.
        float2 seedRadius = 0.5 * 0.0578 * float2(aspect.y, aspect.x);
        float seed = max(1.0 - length((uv - 0.5) / seedRadius), 0.0);
        return float4(min(density + seed, 1.0), 0.0, 0.0, 1.0);
    }
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - bed

// Catmull-Rom read of one frond's tile (9 bilinear taps, the standard separable trick). The
// atlas is upscaled ~2× to the screen (design §5.4), and bilinear magnification is what made
// the leaflets read soft at UND.2; Catmull-Rom keeps their edges. Taps are clamped inside the
// tile so the wider footprint never reads a neighbouring frond.
static float understory_catmull_rom(texture2d<float> atlas, float4 tile, float2 size, float2 t) {
    float2 tilePx = tile.zw * size;
    float2 lo = 0.5 / tilePx, hi = 1.0 - lo;
    float2 p = t * tilePx - 0.5;
    float2 base = floor(p) + 0.5;
    float2 f = p - floor(p);
    float2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    float2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    float2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    float2 w3 = f * f * (-0.5 + 0.5 * f);
    float2 w12 = w1 + w2;
    float2 c0 = clamp((base - 1.0) / tilePx, lo, hi);
    float2 c12 = clamp((base + w2 / w12) / tilePx, lo, hi);
    float2 c3 = clamp((base + 2.0) / tilePx, lo, hi);
    float sum = 0.0;
    float xs[3] = { c0.x, c12.x, c3.x }, xw[3] = { w0.x, w12.x, w3.x };
    float ys[3] = { c0.y, c12.y, c3.y }, yw[3] = { w0.y, w12.y, w3.y };
    for (int j = 0; j < 3; j++) {
        for (int i = 0; i < 3; i++) {
            sum += atlas.sample(understory_linear, tile.xy + float2(xs[i], ys[j]) * tile.zw).x * xw[i] * yw[j];
        }
    }
    return clamp(sum, 0.0, 1.0);
}

// Flat per-layer tints until UND.3's palette: far fronds cooler and dimmer, so depth reads.
constant float3 kUnderstoryLayerTint[3] = {
    float3(0.55, 0.70, 0.95),   // far
    float3(0.75, 0.88, 0.95),   // mid
    float3(0.90, 0.97, 0.92)    // near
};

fragment float4 understory_bed_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> fronds [[texture(13)]]
) {
    float2 size = float2(fronds.get_width(), fronds.get_height());
    float screenAspect = size.x / size.y;
    float3 color = float3(0.0);
    float coverage = 0.0;
    uint count = min(field.header.frond_count, kUnderstoryMaxFronds);
    // Painter's order: the CPU orders fronds far → near.
    for (uint i = 0; i < count; i++) {
        UnderstoryFrond fr = field.fronds[i];
        // Screen → frond frame: offset from the seed in screen heights, un-leaned, unscaled.
        float2 q = float2((in.uv.x - fr.place.x) * screenAspect, in.uv.y - fr.place.y);
        float c = cos(fr.place.w), s = sin(fr.place.w);
        q = float2(c * q.x + s * q.y, -s * q.x + c * q.y);
        float2 uv = float2(0.5 + q.x * 0.75 / fr.place.z, 0.5 + q.y / fr.place.z);
        float2 t = (uv - fr.crop.xy) / (fr.crop.zw - fr.crop.xy);
        if (any(t < 0.0) || any(t > 1.0)) { continue; }   // outside this frond's box
        float density = understory_catmull_rom(fronds, fr.tile, size, t);
        uint layer = min(uint(fr.look.z), 2u);
        color = mix(color, kUnderstoryLayerTint[layer] * fr.look.w, density);
        coverage = mix(coverage, 1.0, density);
    }
    return float4(color, coverage);
}

// MARK: - present

fragment float4 understory_present_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    texture2d<float> bed [[texture(13)]]
) {
    // Dark ground, never black (D-037), a slight vignette; the field over it. Palette is UND.3.
    float4 field = bed.sample(understory_linear, in.uv);
    float2 centred = in.uv - 0.5;
    float vignette = 1.0 - 0.35 * dot(centred, centred) * 2.0;
    float3 ground = float3(0.020, 0.024, 0.040) * vignette;
    // Interleaved-gradient-noise dither, ±half an 8-bit step: the dark vignette bands otherwise.
    float dither = (fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715)))) - 0.5) / 255.0;
    return float4(ground * (1.0 - field.a) + field.rgb + dither, 1.0);
}
