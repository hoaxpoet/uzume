// Understory.metal — a field of feedback-IFS fern fronds (UND.1 look-spike → UND.2 field).
//
//   fronds  (persistent rgba16Float)  Flexi's three-map feedback IFS, one frond per atlas tile
//   bed     (persistent, samples      the field: each frond placed, leaned and scaled on screen,
//            fronds)                  coloured along its path length, composited far → near,
//                                     then max(bed, prev·decay) — the afterglow trails (UND.3)
//   backdrop (persistent)             the forest floor, CACHED: built once over 16 frames, then
//                                     carried (one forest for every track)
//   present (drawable, samples bed,   the forest, each moving fern's light pooled around its
//            backdrop)                root, the field over it, a wide glow
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
//   4. Path length (design §5.3, UND.3). Flexi's G channel fed the dropped Julia layer; here G
//      carries each pixel's AGE in generations, premultiplied by density (G = R · age). Every
//      map copies the age of the tap that won the max on R, plus one; the seed is age 0. So
//      `G / R` is the path length from the seed — base → tip and out through every leaflet —
//      which the colour bands (and UND.4's shimmer) ride on. The design's frame-index stamp
//      (`frameNow − G` mod 1024) is the same quantity; counting age instead has no wrap.
//      Premultiplying keeps bilinear reads honest at the frond's edge: empty texels weigh 0.
//   5. Stem position (UND.3), B = R · S. S counts only the main-arm generations OUTSIDE the
//      first branch: the main arm winning adds one, a side arm winning resets it to 0. So a
//      leaflet carries the stem position it grows from, and the colour bands run across stem
//      and leaflets together. Colouring by full age (4) gave every leaflet its own rainbow,
//      which read as speckle and hid the fern (UND.3, first render).
// Metal's uv and GL's uv_orig address texture memory identically here (our fullscreen
// vertex flips y, and the render target's row 0 is uv.y = 0), so the maps are unflipped.

constant uint kUnderstoryMaxFronds = 14;

struct UnderstoryHeader {
    uint frond_count;
    float palette_rotation;   // turns, from harmony (UnderstoryField)
    float trail_decay;        // per 1/60 s, from arousal
    float frame_index;        // frames published: paces the backdrop's build
    float clear_fronds;       // 1 → clear the frond atlas (a new track's field regrows)
    float pad0, pad1, pad2;
};

struct UnderstoryFrond {
    float4 tile;    // drawable uv: origin.xy, size.xy
    float4 crop;    // Flexi frame uv held by the tile: x0, y0, x1, y1
    float4 place;   // seed on screen (uv), frame height in screen heights, lean (rad)
    float4 look;    // Flexi's ww, Flexi's w, layer (0 far … 2 near), brightness
    float4 colour;  // hue offset (turns), saturation, (UND.4 shimmer), (UND.4 shimmer)
};

struct UnderstoryFieldGPU {
    UnderstoryHeader header;
    UnderstoryFrond fronds[kUnderstoryMaxFronds];
};

constant constexpr sampler understory_linear(filter::linear, address::clamp_to_edge);

// Flexi's frame is 4:3: aspect = (aspectx, aspecty, 1/aspectx, 1/aspecty).
constant float4 kFlexiAspect = float4(1.0, 0.75, 1.0, 4.0 / 3.0);

// Colour bands along the path: turns of hue per generation. Age is a GENERATION count, and
// each generation covers less of the remaining length (the main arm contracts 1/1.12), so the
// bright frond spans ~12 generations (measured, UND.3): one turn over the frond, each stem bead
// its own hue, and every leaflet a small rainbow starting at its junction's hue.
constant float kUnderstoryBandsPerGeneration = 1.0 / 12.0;

// Flexi's `texture(sampler_main, clamp(c, 0, 1))` (R density, G age·R, B stem·R), with `c` in frame
// uv, read from this frond's tile. Frame uv OUTSIDE the tile's crop reads black: that is the
// part of Flexi's frame the tile does not hold, and it is empty there. Clamping to the crop edge
// instead (UND.2, first try) smeared a coil that touched the edge back through the maps until
// the whole tile filled with a grey ring pattern — Flexi's own clamp is to the frame edge.
static float3 understory_tap(texture2d<float> prev, UnderstoryFrond fr, float2 halfTexel, float2 c) {
    float2 local = (clamp(c, 0.0, 1.0) - fr.crop.xy) / (fr.crop.zw - fr.crop.xy);
    if (any(local < 0.0) || any(local > 1.0)) { return float3(0.0); }
    local = clamp(local, halfTexel, 1.0 - halfTexel);
    return prev.sample(understory_linear, fr.tile.xy + local * fr.tile.zw).xyz;
}

// MARK: - fronds (persistent)

fragment float4 understory_fronds_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> prev [[texture(20)]]
) {
    float2 size = float2(prev.get_width(), prev.get_height());
    if (field.header.clear_fronds > 0.5) { return float4(0.0, 0.0, 0.0, 1.0); }   // new track: regrow
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

        float3 main_arm  = understory_tap(prev, fr, halfTexel, 0.5 + r3 * aspect.zw * q3 + float2(q4, q5) * aspect.zw);
        float3 left_arm  = understory_tap(prev, fr, halfTexel, 0.5 + r5 * aspect.zw * q8 + float2(q9, q10));
        float3 right_arm = understory_tap(prev, fr, halfTexel, 0.5 + r7 * aspect.zw * q13 + float2(q14, q15));
        // The winner of Flexi's max carries its age forward (adaptation 4) and its stem
        // position: +1 through the main arm, reset to 0 through a side arm (adaptation 5).
        float3 won = main_arm;
        bool viaMain = true;
        if (left_arm.x > won.x) { won = left_arm; viaMain = false; }
        if (right_arm.x > won.x) { won = right_arm; viaMain = false; }
        float density = max(won.x - 0.015, 0.0);
        float age = won.y / max(won.x, 1e-4) + 1.0;
        float stem = viaMain ? won.z / max(won.x, 1e-4) + 1.0 : 0.0;

        // Seed: butterchurn draws shape 0 as a triangle fan, radius 0.0578 in clip units
        // (x scaled by aspecty), centre alpha 1 → edge 0, additively blended. Age 0.
        float2 seedRadius = 0.5 * 0.0578 * float2(aspect.y, aspect.x);
        float seed = max(1.0 - length((uv - 0.5) / seedRadius), 0.0);
        float total = min(density + seed, 1.0);
        float share = density / max(density + seed, 1e-4);
        return float4(total, total * age * share, total * stem * share, 1.0);
    }
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - bed (persistent)

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

// Smooth HSV → RGB (iq): no hard kinks at the primaries, so the bands glide.
static float3 understory_hsv(float h, float s, float v) {
    float3 rgb = clamp(abs(fmod(h * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    rgb = rgb * rgb * (3.0 - 2.0 * rgb);
    return v * mix(float3(1.0), rgb, s);
}

fragment float4 understory_bed_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> fronds [[texture(13)]],
    texture2d<float> prev [[texture(20)]]
) {
    float2 size = float2(fronds.get_width(), fronds.get_height());
    float screenAspect = size.x / size.y;
    float rotation = field.header.palette_rotation;
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
        if (density <= 0.0) { continue; }
        // Stem position (adaptation 5): bilinear B/R, density-weighted.
        float2 halfTexel = 0.5 / (fr.tile.zw * size);
        float3 rgb = fronds.sample(understory_linear, fr.tile.xy + clamp(t, halfTexel, 1.0 - halfTexel) * fr.tile.zw).xyz;
        float stem = rgb.z / max(rgb.x, 1e-3);
        // Hue bands run up the stem and across its leaflets; each frond has its own place on
        // the wheel; harmony turns the whole field.
        float hue = fract(rotation + fr.colour.x + stem * kUnderstoryBandsPerGeneration);
        float3 tint = understory_hsv(hue, fr.colour.y, fr.look.w);
        color = mix(color, tint, density);
        coverage = mix(coverage, 1.0, density);
    }
    // Afterglow (design §4.5): max(bed, prev · decay), the decay per 1/60 s from arousal,
    // made frame-rate independent.
    float decay = pow(clamp(field.header.trail_decay, 0.0, 0.99), clamp(f.delta_time * 60.0, 0.0, 4.0));
    float4 trail = prev.sample(understory_linear, in.uv) * decay;
    return max(float4(color, coverage), trail);
}

// MARK: - backdrop (the forest floor, cached)
//
// Matt, 2026-10-01: "We need a beautiful background for these ferns - they are just floating in
// space", then his reference photo — "a fallen tree, covered in moss with a bunch of ferns in the
// foreground, not all of which are moving - only a subset would move to the beat" — and his two
// picks: the moving ferns keep their psychedelic glow; the forest is in DIM GREEN DAYLIGHT.
// Back to front (docs/VISUAL_REFERENCES/understory/07, 11, 12–14):
//   light     overcast green from above, no sky; the canopy is out of frame
//   trunks    four depths of redwood-scale trunks, furrowed bark, fading into green haze
//   floor     dark loam rising toward the back, and a carpet of STILL sword ferns in depth
//             rows — a different fern from the movers, as a real understory mixes species
//   log       a fallen, moss-covered trunk across the middle distance, ferns in front of it
// It never moves, so it is drawn ONCE: the `backdrop` stage is persistent, computes each pixel
// in one of 16 frames (a quick dissolve-in) and afterwards only carries its previous state.

constant float kUnderstoryFloor = 0.40;   // drawable y where the far floor meets the trunks

// Green forest haze by height: the light comes from above.
static float3 understory_haze(float y) {
    return mix(float3(0.046, 0.068, 0.050), float3(0.012, 0.020, 0.014), smoothstep(0.0, 0.85, y));
}

// One depth of trunks over `color`. `p` is in screen heights (x scaled by aspect).
static float3 understory_trunks(float3 color, float2 p, float aspect, int layer) {
    const int counts[4] = { 16, 10, 6, 3 };
    const float widths[4] = { 0.008, 0.018, 0.036, 0.075 };
    const float bases[4] = { 0.43, 0.48, 0.58, 0.95 };
    const float hazes[4] = { 0.62, 0.40, 0.18, 0.04 };
    int count = counts[layer];
    float base = bases[layer];
    if (p.y > base + 0.02) { return color; }
    for (int j = 0; j < count; j++) {
        float2 key = float2(float(j) * 7.13 + float(layer) * 31.7, 3.0 + float(layer));
        float slot = (float(j) + 0.1 + 0.8 * hash_f01_2(key)) / float(count);
        float x0 = (slot * 1.1 - 0.05) * aspect;
        float width = widths[layer] * (0.7 + 0.6 * hash_f01_2(key + 3.1));
        float lean = (hash_f01_2(key + 5.7) - 0.5) * 0.04;
        float rise = base - p.y;
        float flare = 1.0 + 1.2 * exp(-rise / (width * 3.0));
        float half_width = width * (0.9 + 0.2 * p.y) * flare;
        float dx = p.x - (x0 + lean * rise);
        if (abs(dx) > half_width * 1.5) { continue; }
        float edge = half_width * (1.0 + 0.06 * perlin2d(float2(p.y * 30.0, float(j) * 3.7)));
        float inside = smoothstep(edge + 0.0015, edge - 0.0015, abs(dx)) * smoothstep(base + 0.02, base - 0.005, p.y);
        // Redwood bark: deep vertical furrows, plates between them, a rounded body, moss low down.
        float across = dx / max(edge, 1e-4);
        float furrows = fbm4(float3(across * 3.5 + float(j), p.y * 2.5 / max(width * 8.0, 0.3), float(layer)));
        float plates = smoothstep(-0.15, 0.35, furrows);
        float body = sqrt(max(1.0 - across * across, 0.0));
        float3 bark = mix(float3(0.012, 0.010, 0.009), float3(0.070, 0.058, 0.047), plates) * (0.35 + 0.65 * body);
        // Grey-green lichen streaks (Matt's photo), moss climbing from the base.
        float lichen = smoothstep(0.35, 0.75, fbm4(float3(across * 6.0, p.y * 1.5, 7.0 + float(j))));
        bark = mix(bark, float3(0.060, 0.072, 0.062) * (0.4 + 0.6 * body), lichen * 0.35);
        float moss = smoothstep(0.55, 0.85, fbm4(float3(p * 14.0, float(j)))) * smoothstep(base - 0.25, base, p.y);
        bark = mix(bark, float3(0.050, 0.085, 0.032) * (0.5 + 0.5 * body), moss * 0.7);
        float3 trunk = mix(bark, understory_haze(p.y), hazes[layer]);
        color = mix(color, trunk, inside);
    }
    return color;
}

// One sword-fern frond (simply pinnate, the species in Matt's photo): coverage and shade at `p`.
// `b` its base, `a` its lean from vertical, `len` its length, `bend` its droop.
static float2 understory_sword(float2 p, float2 b, float a, float len, float bend) {
    float c = cos(a), s = sin(a);
    float2 q = float2(c * (p.x - b.x) + s * (p.y - b.y), -s * (p.x - b.x) + c * (p.y - b.y));
    float along = -q.y;                                   // up the rachis
    if (along < 0.0 || along > len) { return float2(0.0); }
    float t = along / len;
    float side = q.x - bend * along * along / len;        // distance from the drooping rachis
    float half_leaf = len * 0.17 * pow(sin(3.14159 * min(t * 1.05, 1.0)), 0.75) * smoothstep(0.04, 0.16, t);
    float u = abs(side);
    float rachis = smoothstep(len * 0.007, len * 0.004, u);
    if (u > half_leaf && rachis <= 0.0) { return float2(0.0); }
    float spacing = len * 0.050;
    float swept = along - u * 0.55 + (side > 0.0 ? 0.0 : 0.5 * spacing);   // alternate, swept to the tip
    float d = abs(fract(swept / spacing) - 0.5) * spacing;
    float taper = 1.0 - u / max(half_leaf, 1e-4);
    float pinna = smoothstep(0.46 * spacing * taper + len * 0.002, 0.46 * spacing * taper - len * 0.002, d)
                * step(u, half_leaf);
    float cover = max(pinna, rachis);
    // Leaflet tips catch the light. Clamped: at the stalk the leaf width is ~0, and an unclamped
    // ratio lit the stalk into bright dashes all over the carpet (UND.3).
    float shade = (0.55 + 0.45 * min(u / max(half_leaf, 1e-4), 1.0)) * (0.65 + 0.35 * t);
    return float2(cover, shade);
}

// One depth row of still fern clumps over `color`.
static float3 understory_carpet(float3 color, float2 p, float aspect, int row) {
    const float crowns[6] = { 0.44, 0.50, 0.58, 0.68, 0.81, 0.99 };
    const float sizes[6] = { 0.050, 0.072, 0.100, 0.145, 0.205, 0.290 };
    const int counts[6] = { 44, 30, 22, 15, 11, 8 };
    const float hazes[6] = { 0.55, 0.40, 0.26, 0.15, 0.06, 0.0 };
    float size = sizes[row];
    if (abs(p.y - crowns[row] + size * 0.45) > size * 1.0) { return color; }
    int count = counts[row];
    for (int k = 0; k < count; k++) {
        float2 key = float2(float(k) * 3.31 + float(row) * 17.9, 11.0 + float(row));
        float x = ((float(k) + 0.15 + 0.7 * hash_f01_2(key)) / float(count) * 1.15 - 0.075) * aspect;
        float2 crown = float2(x, crowns[row] + (hash_f01_2(key + 1.3) - 0.5) * size * 0.25);
        float clump = size * (0.8 + 0.4 * hash_f01_2(key + 2.9));
        if (length(p - crown) > clump * 1.15) { continue; }
        for (int i = 0; i < 9; i++) {
            float2 fk = key + float2(float(i) * 1.7, 0.0);
            float spread = -1.35 + 2.7 * (float(i) + 0.2 + 0.6 * hash_f01_2(fk)) / 9.0;
            float len = clump * (0.75 + 0.35 * hash_f01_2(fk + 0.4)) * (1.0 - 0.22 * abs(spread));
            float droop = sign(spread) * (0.35 + 0.5 * hash_f01_2(fk + 0.8));
            float2 frond = understory_sword(p, crown, spread, len, droop);
            if (frond.x <= 0.0) { continue; }
            float tone = 0.7 + 0.6 * hash_f01_2(fk + 2.2);
            // Fronds near the camera catch more light (Matt's photo: bright foreground ferns).
            float lit = 0.55 + 0.45 * float(row) / 5.0;
            float3 green = float3(0.040, 0.135, 0.050) * tone * frond.y * lit;
            color = mix(color, mix(green, understory_haze(p.y), hazes[row]), frond.x);
        }
    }
    return color;
}

// The fallen log: a moss-covered trunk across the middle distance (Matt's photo).
static float3 understory_log(float3 color, float2 p, float aspect) {
    float2 a = float2(0.02 * aspect, 0.70), b = float2(1.05 * aspect, 0.43);
    float2 ab = b - a;
    float h = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    float2 axis = a + ab * h;
    float radius = mix(0.078, 0.052, h);
    float2 normal = normalize(float2(-ab.y, ab.x));          // points down-screen
    float v = dot(p - axis, normal) / radius;                // −1 top … +1 underside
    if (abs(v) > 1.0) { return color; }
    float along = h * length(ab);
    float body = sqrt(max(1.0 - v * v, 0.0));
    float light = 0.20 + 0.80 * smoothstep(1.0, -0.7, v);   // lit from above, the underside in shadow
    // Bark broken into plates (Matt's photo: grey scales with dark cracks between them).
    // Cells stretched along the trunk and wrapped round it with the cylinder's curvature.
    float wrap = asin(clamp(v, -1.0, 1.0));
    // Long scales: cells stretched along the trunk, warped so no two match, each its own tone.
    float2 warp = float2(fbm4(float3(along * 6.0, wrap, 3.0)), fbm4(float3(along * 6.0, wrap, 8.0))) * 0.35;
    float2 cells = worley2d(float2(along * 16.0, wrap * 6.5) + warp);
    float crack = smoothstep(0.015, 0.07, cells.y - cells.x);
    float tone = fbm4(float3(floor(along * 16.0 + warp.x * 2.0), floor(wrap * 6.5), 1.0)) * 0.5 + 0.5;
    float grain = fbm4(float3(along * 140.0, wrap * 20.0, 2.0)) * 0.5 + 0.5;
    float3 plate = float3(0.082, 0.080, 0.070) * (0.55 + 0.6 * tone) * (0.8 + 0.4 * grain);
    float3 bark = mix(float3(0.012, 0.011, 0.010), plate, crack) * light * (0.45 + 0.55 * body);
    // Moss: heavy on the top side, patchy, cushiony.
    float mossy = smoothstep(0.25, -0.65, v + 0.55 * fbm4(float3(along * 6.0, 1.7, 2.0)));
    float tufts = fbm8(float3(along * 55.0, wrap * 11.0, 0.5)) * 0.5 + 0.5;
    float clumps = fbm4(float3(along * 14.0, wrap * 3.0, 6.0)) * 0.5 + 0.5;
    // Cushions: bright where a tuft rises, dark in the hollows between them.
    float3 moss = mix(float3(0.016, 0.030, 0.010), float3(0.075, 0.130, 0.035), smoothstep(0.30, 0.75, tufts))
                * (0.6 + 0.6 * clumps) * light;
    float3 log_color = mix(bark, moss, mossy * smoothstep(0.30, 0.60, tufts * 0.6 + clumps * 0.6));
    float coverage = smoothstep(1.0, 0.92, abs(v));
    return mix(color, mix(log_color, understory_haze(p.y), 0.12), coverage);
}

static float3 understory_forest(float2 uv, float aspect) {
    float2 p = float2(uv.x * aspect, uv.y);
    // Overcast green light from above; foliage glimpsed between the far trunks.
    float3 color = understory_haze(uv.y);
    float dapple = fbm4(float3(p * float2(5.0, 3.0), 9.0)) * 0.5 + 0.5;
    color *= 0.85 + 0.3 * dapple * smoothstep(0.5, 0.0, uv.y);
    color = understory_trunks(color, p, aspect, 0);
    color = understory_trunks(color, p, aspect, 1);
    // The floor: dark loam and litter from the far line down.
    if (uv.y > kUnderstoryFloor) {
        float litter = fbm4(float3(p * float2(18.0, 30.0), 5.0)) * 0.5 + 0.5;
        float3 loam = mix(float3(0.008, 0.010, 0.007), float3(0.032, 0.034, 0.022), litter);
        color = mix(loam, understory_haze(uv.y), exp(-(uv.y - kUnderstoryFloor) / 0.05) * 0.8);
    }
    color = understory_carpet(color, p, aspect, 0);
    color = understory_carpet(color, p, aspect, 1);
    color = understory_trunks(color, p, aspect, 2);
    color = understory_carpet(color, p, aspect, 2);
    color = understory_log(color, p, aspect);
    color = understory_carpet(color, p, aspect, 3);
    color = understory_trunks(color, p, aspect, 3);
    color = understory_carpet(color, p, aspect, 4);
    color = understory_carpet(color, p, aspect, 5);
    return color;
}

fragment float4 understory_backdrop_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> prev [[texture(20)]]
) {
    float4 cached = prev.read(uint2(in.position.xy));
    if (cached.a > 0.5) { return cached; }                       // built: carry it
    // Not yet built: this pixel's turn is one frame in 16 (a quick dissolve-in, no hitch).
    uint2 px = uint2(in.position.xy);
    uint turn = (px.x * 7u + px.y * 13u + (px.x * px.y) % 5u) % 16u;
    if (turn != uint(field.header.frame_index) % 16u) { return float4(0.0); }
    float2 size = float2(prev.get_width(), prev.get_height());
    return float4(understory_forest(in.uv, size.x / size.y), 1.0);
}

// Each moving fern's light pooled around its root, in its own colour, on whatever is behind it.
static float3 understory_fern_light(float2 uv, float aspect, constant UnderstoryFieldGPU& field) {
    float3 light = float3(0.0);
    uint count = min(field.header.frond_count, kUnderstoryMaxFronds);
    for (uint i = 0; i < count; i++) {
        UnderstoryFrond fr = field.fronds[i];
        float2 root = float2(fr.place.x, min(fr.place.y, 0.995) - 0.08 * fr.place.z);
        float2 q = float2((uv.x - root.x) * aspect / (0.22 * fr.place.z), (uv.y - root.y) / (0.12 * fr.place.z));
        float pool = exp(-dot(q, q));
        float hue = fract(field.header.palette_rotation + fr.colour.x + 4.0 * kUnderstoryBandsPerGeneration);
        light += understory_hsv(hue, fr.colour.y, 1.0) * pool * fr.look.w;
    }
    return light;
}

// MARK: - present

fragment float4 understory_present_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> bed [[texture(13)]],
    texture2d<float> backdrop [[texture(14)]]
) {
    float2 size = float2(bed.get_width(), bed.get_height());
    float aspect = size.x / size.y;
    float4 field4 = bed.sample(understory_linear, in.uv);

    // A cheap wide glow: two rings of 8 taps (≈0.8 % and 2.2 % of the height). The fronds read
    // as luminous, and it softens the atlas upscale (design §5.4).
    float3 glow = float3(0.0);
    for (int k = 0; k < 8; k++) {
        float angle = float(k) * 0.785398 + 0.39;
        float2 dir = float2(cos(angle) * size.y / size.x, sin(angle));
        glow += bed.sample(understory_linear, in.uv + dir * 0.008).rgb * 0.6;
        glow += bed.sample(understory_linear, in.uv + dir * 0.022).rgb * 0.4;
    }
    glow /= 8.0;

    // The forest (cached), lit around each moving fern; a slight vignette. While the forest is
    // still dissolving in, unbuilt pixels show the haze, never black (D-037).
    float2 centred = in.uv - 0.5;
    float vignette = 1.0 - 0.45 * dot(centred, centred) * 2.0;
    float4 forest = backdrop.sample(understory_linear, in.uv);
    float3 scene = forest.a > 0.5 ? forest.rgb : understory_haze(in.uv.y) * 0.6;
    float3 ground = scene * (1.0 + 2.2 * understory_fern_light(in.uv, aspect, field)) * vignette;

    float3 color = ground * (1.0 - field4.a) + field4.rgb + glow * 0.25;
    color = color / (1.0 + 0.18 * color);   // soft shoulder so the glow never clips flat
    // Interleaved-gradient-noise dither, ±half an 8-bit step: the dark vignette bands otherwise.
    float dither = (fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715)))) - 0.5) / 255.0;
    return float4(color + dither, 1.0);
}
