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
    float4 colour;  // hue offset (turns), saturation, seconds since this frond's shimmer, unused
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

// The beat shimmer (design §4.3, UND.4): a bright band climbing the frond's full path age, so it
// rises through the stem and runs out into every leaflet. ~12 generations of bright frond at 40
// generations/s ≈ 0.3 s base → tip (the design's ~0.35 s); gone by 0.9 s.
constant float kUnderstoryShimmerSpeed = 40.0;   // generations per second
constant float kUnderstoryShimmerWidth = 1.6;    // generations

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
        float age = rgb.y / max(rgb.x, 1e-3);
        // The shimmer: a white-hot band with the palette turned half a turn under it, and a
        // short afterglow behind it. One frond, a travelling band: never a whole-frond flash.
        float since = fr.colour.z;
        float front = since * kUnderstoryShimmerSpeed;
        float fade = smoothstep(0.9, 0.45, since);
        float band = exp(-pow((age - front) / kUnderstoryShimmerWidth, 2.0)) * fade;
        float trail = (age < front ? 0.30 * exp(-(front - age) / 3.0) : 0.0) * fade;
        // Hue bands run up the stem and across its leaflets; each frond has its own place on
        // the wheel; harmony turns the whole field.
        float hue = fract(rotation + fr.colour.x + stem * kUnderstoryBandsPerGeneration + 0.5 * band);
        float3 tint = understory_hsv(hue, fr.colour.y, fr.look.w) * (1.0 + trail);
        tint = mix(tint, float3(1.25, 1.22, 1.15) * max(fr.look.w, 0.6), 0.75 * band);
        color = mix(color, tint, density);
        coverage = mix(coverage, 1.0, density);
    }
    // Afterglow (design §4.5): max(bed, prev · decay), the decay per 1/60 s from arousal,
    // made frame-rate independent.
    float decay = pow(clamp(field.header.trail_decay, 0.0, 0.99), clamp(f.delta_time * 60.0, 0.0, 4.0));
    float4 trail = prev.sample(understory_linear, in.uv) * decay;
    return max(float4(color, coverage), trail);
}

// MARK: - backdrop (the forest floor, ray-marched once and cached)
//
// Matt, 2026-10-01: "We need a beautiful background for these ferns - they are just floating in
// space", then his reference photo — "a fallen tree, covered in moss with a bunch of ferns in the
// foreground, not all of which are moving - only a subset would move to the beat" — and his picks:
// psychedelic moving ferns, a DIM GREEN DAYLIGHT forest. A first pass drawn as 2D layers read
// "low fidelity overall" (Matt); his call: keep it drawn, push detail. So the forest is a real
// 3D scene, ray-marched — perspective, ambient occlusion, distance haze, supersampled edges and a
// shallow depth of field — which a live frame could never afford, but which this stage renders
// ONCE: it is persistent, builds each pixel in one frame of `kUnderstoryBuildTurns`, and then
// only carries itself. One forest for every track.
//   ground   a hillside rising away from a low camera, needle litter and moss patches
//   trunks   redwoods on a jittered 4.5 m grid: fluted bark, root flare, lichen, moss at the foot
//   log      a fallen trunk lying on the slope across the middle distance: plated grey bark, moss
//            cushions on top (Matt's photo)
//   ferns    sword-fern clumps on a 0.9 m grid, each frond an alpha-tested card (the standard
//            vegetation technique), found by walking the ground grid along the ray
// Units are metres, y up. References: docs/VISUAL_REFERENCES/understory/07, 11–14.

constant int kUnderstoryBuildTurns = 96;
constant int kUnderstorySamples = 3;
constant float kUnderstoryTrunkCell = 4.5;
constant float kUnderstoryFernCell = 0.9;

// Two octaves of 2D noise: the terrain is evaluated at every march step, so it stays cheap.
static float understory_terrain(float2 xz) {
    return 0.075 * max(xz.y, 0.0) + 0.28 * perlin2d(xz * 0.17 + 1.7) + 0.10 * perlin2d(xz * 0.41 + 5.3);
}

// One trunk per grid cell (most cells): xz centre, radius, exists.
static float4 understory_trunk_cell(float2 cell) {
    float2 jitter = float2(hash_f01_2(cell * 1.31 + 0.7), hash_f01_2(cell * 2.17 + 3.1)) - 0.5;
    float2 centre = (cell + 0.5 + jitter * 0.75) * kUnderstoryTrunkCell;
    float radius = 0.30 + 1.05 * pow(hash_f01_2(cell + 9.4), 2.2);
    float exists = hash_f01_2(cell + 5.5) < 0.70 ? 1.0 : 0.0;
    if (centre.y < 4.5 && abs(centre.x) < 3.2) { exists = 0.0; }   // keep the foreground open
    if (centre.y < 0.5) { exists = 0.0; }                          // nothing behind the camera
    return float4(centre, radius, exists);
}

// Trunk SDF; `bark` returns (angle around the trunk, height above its foot, radius).
static float understory_trunks_sdf(float3 p, thread float3& bark) {
    // The 2×2 cells nearest p: a trunk sits within ±0.375 cells of its cell centre and is far
    // thinner than a cell, so the two cells beyond the nearest corner can never be closest.
    float2 g = p.xz / kUnderstoryTrunkCell - 0.5;
    float2 cell = floor(g);
    float best = 1e5;
    for (int dz = 0; dz <= 1; dz++) {
        for (int dx = 0; dx <= 1; dx++) {
            float4 tr = understory_trunk_cell(cell + float2(dx, dz));
            if (tr.w < 0.5) { continue; }
            float2 d2 = p.xz - tr.xy;
            float y = p.y - understory_terrain(tr.xy);
            float angle = atan2(d2.y, d2.x);
            float flare = 1.0 + 0.85 * exp(-max(y, 0.0) / (0.55 * tr.z + 0.25));
            // Shallow, irregular fluting: deep regular flutes read as stage curtains (UND.3).
            float flutes = 0.018 * sin(angle * 7.0 + y * 0.25 + tr.x) + 0.010 * sin(angle * 19.0 + y * 0.6 + tr.y);
            float d = (length(d2) - tr.z * flare * (1.0 + flutes)) * 0.75;
            if (d < best) { best = d; bark = float3(angle, y, tr.z); }
        }
    }
    return best;
}

// The fallen log: a capsule lying on the slope.
// Its ends rest on the terrain; computed once per ray, not per march step.
struct UnderstoryLog { float3 a, b; };
static UnderstoryLog understory_log() {
    UnderstoryLog log;
    log.a = float3(-3.6, 0.0, 3.6); log.a.y = understory_terrain(log.a.xz) + 0.40;
    log.b = float3(4.8, 0.0, 8.5);  log.b.y = understory_terrain(log.b.xz) + 0.36;
    return log;
}

static float understory_log_sdf(float3 p, UnderstoryLog log, thread float2& along_v) {
    float3 a = log.a, b = log.b;
    float3 ab = b - a;
    float h = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    float3 axis = a + ab * h;
    float radius = mix(0.46, 0.38, h);
    along_v = float2(h * length(ab), atan2((p - axis).y, length((p - axis).xz) * sign(dot((p - axis).xz, float2(-ab.z, ab.x)))));
    return length(p - axis) - radius;
}

// Scene SDF: material 1 ground, 2 trunk, 3 log.
static float understory_scene(float3 p, UnderstoryLog log, thread int& material, thread float3& detail) {
    float ground = (p.y - understory_terrain(p.xz)) * 0.7;
    float3 bark;
    float trunks = understory_trunks_sdf(p, bark);
    float2 logUV;
    float log_d = understory_log_sdf(p, log, logUV);
    material = 1; detail = float3(p.xz, 0.0);
    float d = ground;
    if (trunks < d) { d = trunks; material = 2; detail = bark; }
    if (log_d < d) { d = log_d; material = 3; detail = float3(logUV, 0.0); }
    return d;
}

static float understory_scene_d(float3 p, UnderstoryLog log) { int m; float3 x; return understory_scene(p, log, m, x); }

static float3 understory_normal(float3 p, float t, UnderstoryLog log) {
    float e = 0.002 * max(t, 1.0);
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * understory_scene_d(p + k.xyy * e, log) + k.yyx * understory_scene_d(p + k.yyx * e, log)
                   + k.yxy * understory_scene_d(p + k.yxy * e, log) + k.xxx * understory_scene_d(p + k.xxx * e, log));
}

static float understory_ao(float3 p, float3 n, UnderstoryLog log) {
    float occlusion = 0.0, weight = 1.0;
    for (int i = 1; i <= 3; i++) {
        float h = 0.10 * float(i * i);
        occlusion += (h - understory_scene_d(p + n * h, log)) * weight;
        weight *= 0.55;
    }
    return clamp(1.0 - 1.3 * occlusion, 0.0, 1.0);
}

// Overcast green daylight from above, its bounce from the floor, a faint warm shaft.
static float3 understory_light(float3 n, float ao) {
    float3 sky = float3(0.32, 0.40, 0.30) * (0.55 + 0.45 * n.y);
    float3 bounce = float3(0.035, 0.045, 0.028) * (0.5 - 0.5 * n.y);
    // A soft key from the upper left through a canopy gap: what gives the bark its relief.
    float3 shaft = float3(0.30, 0.28, 0.20) * max(dot(n, normalize(float3(-0.65, 0.55, -0.35))), 0.0) * 0.55;
    return (sky + bounce + shaft) * ao;
}

constant float3 kUnderstoryHaze = float3(0.060, 0.085, 0.064);

static float3 understory_fog(float3 color, float t, float3 rd) {
    float amount = 1.0 - exp(-t * 0.034);
    float3 haze = kUnderstoryHaze * (0.8 + 0.4 * saturate(rd.y * 3.0 + 0.5));
    return mix(color, haze, amount);
}

// Surface colour of a solid hit.
static float3 understory_surface(int material, float3 detail, float3 p, float3 n) {
    if (material == 2) {
        // Redwood: deep vertical furrows in fibrous red-brown bark, lichen, moss at the foot.
        float angle = detail.x, y = detail.y, radius = detail.z;
        float circ = angle * radius * 6.0;
        // Stringy ridges: ridged noise, warped so no furrow runs ruler-straight, dark crevices.
        float warp = 0.9 * fbm4(float3(circ * 0.6, y * 0.18, 2.0 + radius));
        float ridge = 1.0 - abs(fbm4(float3(circ * 1.5 + warp, y * 0.16, radius * 3.0)));
        float crevice = smoothstep(0.62, 0.92, ridge);
        float strands = fbm4(float3(circ * 9.0 + warp * 3.0, y * 0.9, 1.0)) * 0.5 + 0.5;
        float3 bark = mix(float3(0.008, 0.005, 0.004), float3(0.270, 0.135, 0.085), crevice);
        bark *= 0.55 + 0.75 * strands;
        // Grey-green lichen in irregular patches up the trunk (Matt's photo A).
        float lichen = smoothstep(0.25, 0.55, fbm4(float3(circ * 0.9, y * 0.45, 4.0 + radius)) * 0.5 + 0.5 - 0.15);
        bark = mix(bark, float3(0.150, 0.165, 0.135) * (0.6 + 0.6 * strands), lichen * 0.45 * crevice);
        float moss = smoothstep(1.4, 0.0, y) * smoothstep(0.2, 0.6, fbm4(float3(circ * 3.0, y * 2.0, 7.0)) * 0.5 + 0.5);
        return mix(bark, float3(0.070, 0.120, 0.030), moss);
    }
    if (material == 3) {
        // The log: grey bark broken into long plates, moss cushions on the upper side.
        float along = detail.x, around = detail.y;
        float2 warp = float2(fbm4(float3(along * 0.8, around, 3.0)), fbm4(float3(along * 0.8, around, 8.0))) * 0.4;
        float2 cells = worley2d(float2(along * 2.2, around * 2.6) + warp);
        float crack = smoothstep(0.04, 0.16, cells.y - cells.x);
        float tone = fbm4(float3(floor(along * 2.2 + warp.x), floor(around * 2.6), 1.0)) * 0.5 + 0.5;
        float grain = fbm4(float3(along * 18.0, around * 10.0, 3.0)) * 0.5 + 0.5;
        // Plates domed: brighter at their centres, falling into the cracks.
        float dome = smoothstep(0.0, 0.35, cells.y - cells.x);
        float3 bark = mix(float3(0.012, 0.011, 0.010),
                          float3(0.290, 0.278, 0.250) * (0.55 + 0.55 * tone) * (0.75 + 0.35 * grain) * (0.6 + 0.4 * dome),
                          crack);
        float tufts = fbm8(float3(along * 9.0, around * 6.0, 0.5)) * 0.5 + 0.5;
        float mossy = smoothstep(0.05, 0.55, n.y + 0.35 * fbm4(float3(along * 1.4, around, 2.0)));
        float3 moss = mix(float3(0.030, 0.055, 0.012), float3(0.140, 0.230, 0.050), smoothstep(0.35, 0.75, tufts));
        return mix(bark, moss, mossy * smoothstep(0.30, 0.55, tufts + 0.2));
    }
    // Ground: redwood needle litter, darker hollows, moss patches.
    float2 xz = detail.xy;
    float litter = fbm4(float3(xz * 3.5, 2.0)) * 0.5 + 0.5;
    float needles = fbm4(float3(xz * 24.0, 5.0)) * 0.5 + 0.5;
    float3 floor_color = mix(float3(0.030, 0.020, 0.014), float3(0.105, 0.060, 0.035), litter * (0.7 + 0.3 * needles));
    float moss = smoothstep(0.55, 0.75, fbm4(float3(xz * 0.9, 9.0)) * 0.5 + 0.5);
    return mix(floor_color, float3(0.055, 0.100, 0.028) * (0.7 + 0.5 * needles), moss);
}

// A sword-fern frond on its card: (coverage, shade) at card coords u (along) and w (across).
static float2 understory_frond_card(float u, float w, float len, float bend) {
    if (u < 0.0 || u > len) { return float2(0.0); }
    float t = u / len;
    float side = w - bend * u * u / len;
    float half_leaf = len * 0.15 * pow(sin(3.14159 * min(t * 1.05, 1.0)), 0.75) * smoothstep(0.06, 0.18, t);
    float a = abs(side);
    float rachis = a < len * 0.006 ? 1.0 : 0.0;
    if (a > half_leaf && rachis < 0.5) { return float2(0.0); }
    float spacing = len * 0.048;
    float swept = u - a * 0.6 + (side > 0.0 ? 0.0 : 0.5 * spacing);
    float d = abs(fract(swept / spacing) - 0.5) * spacing;
    float taper = 1.0 - a / max(half_leaf, 1e-4);
    float pinna = (d < 0.44 * spacing * taper && a <= half_leaf) ? 1.0 : 0.0;
    float cover = max(pinna, rachis);
    float shade = (0.6 + 0.4 * min(a / max(half_leaf, 1e-4), 1.0)) * (0.35 + 0.65 * smoothstep(0.0, 0.45, t));
    return float2(cover, shade);
}

// Walk the fern grid along the ray up to `limit`; nearest frond hit → (t, shade, tone, 0).
static float4 understory_ferns(float3 ro, float3 rd, float limit) {
    float4 best = float4(limit, 0.0, 0.0, 0.0);
    float2 rd2 = rd.xz;
    if (length(rd2) < 1e-5) { return best; }
    float cs = kUnderstoryFernCell;
    float2 cell = floor(ro.xz / cs);
    float2 stepDir = sign(rd2);
    float2 nextEdge = (cell + max(stepDir, 0.0)) * cs;
    float2 tMax = (nextEdge - ro.xz) / rd2;
    float2 tDelta = abs(cs / rd2);
    float tEnter = 0.0;
    for (int i = 0; i < 44; i++) {
        if (tEnter > min(best.x, 26.0)) { break; }
        float2 key = cell;
        if (hash_f01_2(key * 0.71 + 4.4) < 0.78 && (key.y * cs > 0.6 || abs(key.x * cs) > 1.5)) {
            float2 jitter = float2(hash_f01_2(key + 0.3), hash_f01_2(key + 7.9)) - 0.5;
            float2 c = (key + 0.5 + jitter * 0.6) * cs;
            float3 base = float3(c.x, understory_terrain(c) + 0.03, c.y);
            float size = 0.75 + 0.55 * hash_f01_2(key + 2.6);
            // Skip the clump unless the ray passes within its reach.
            float3 toBase = base + float3(0.0, 0.35 * size, 0.0) - ro;
            float along = dot(toBase, rd);
            if (length(toBase - rd * along) < 1.25 * size && along > 0.0) {
                for (int f = 0; f < 9; f++) {
                    float2 fk = key + float2(float(f) * 1.37, 0.5);
                    float phi = (float(f) + hash_f01_2(fk)) * (6.28318 / 9.0);
                    float incline = 0.45 + 0.45 * hash_f01_2(fk + 1.9);
                    float len = size * (0.75 + 0.4 * hash_f01_2(fk + 3.3));
                    float3 U = float3(cos(phi) * cos(incline), sin(incline), sin(phi) * cos(incline));
                    float3 W = float3(-sin(phi), 0.0, cos(phi));
                    float3 N = cross(U, W);
                    float denom = dot(rd, N);
                    if (abs(denom) < 1e-4) { continue; }
                    float tt = dot(base - ro, N) / denom;
                    if (tt <= 0.05 || tt >= best.x) { continue; }
                    float3 hp = ro + rd * tt - base;
                    float2 frond = understory_frond_card(dot(hp, U), dot(hp, W), len, (hash_f01_2(fk + 6.1) - 0.5) * 0.5);
                    if (frond.x > 0.5) {
                        // Light through and onto the blade: brighter facing the sky, tips bright.
                        float facing = abs(N.y);
                        best = float4(tt, frond.y * (0.55 + 0.45 * facing), 0.7 + 0.6 * hash_f01_2(fk + 4.2), 1.0);
                    }
                }
            }
        }
        // Next cell.
        if (tMax.x < tMax.y) { tEnter = tMax.x; tMax.x += tDelta.x; cell.x += stepDir.x; }
        else { tEnter = tMax.y; tMax.y += tDelta.y; cell.y += stepDir.y; }
    }
    return best;
}

// One camera ray through the forest → colour.
static float3 understory_forest_ray(float3 ro, float3 rd, UnderstoryLog log) {
    float t = 0.2;
    int material = 0;
    float3 detail = float3(0.0);
    bool hit = false;
    for (int i = 0; i < 128; i++) {
        float3 p = ro + rd * t;
        float d = understory_scene(p, log, material, detail);
        if (d < 0.002 * t) { hit = true; break; }
        t += d;
        if (t > 70.0) { break; }
    }
    float limit = hit ? t : 90.0;
    float4 fern = understory_ferns(ro, rd, limit);
    if (fern.w > 0.5) {
        float3 green = float3(0.050, 0.150, 0.045) * fern.z * fern.y;
        float3 lit = green * (float3(0.55, 0.62, 0.48) + float3(0.20, 0.30, 0.08));   // sky + light through the blade
        return understory_fog(lit, fern.x, rd);
    }
    if (!hit) { return kUnderstoryHaze * (0.9 + 0.5 * saturate(rd.y * 2.0)); }
    float3 p = ro + rd * t;
    float3 n = understory_normal(p, t, log);
    float ao = understory_ao(p, n, log);
    float3 albedo = understory_surface(material, detail, p, n);
    return understory_fog(albedo * understory_light(n, ao), t, rd);
}

// The forest seen through the camera at drawable uv `uv` (y down), supersampled with a small
// lens for anti-aliasing and a shallow depth of field.
static float3 understory_forest(float2 uv, float2 size, uint2 px) {
    float aspect = size.x / size.y;
    float3 ro = float3(0.0, understory_terrain(float2(0.0, 0.0)) + 1.30, 0.0);
    float pitch = -0.10;
    float3 forward = normalize(float3(0.0, sin(pitch), cos(pitch)));
    float3 right = float3(1.0, 0.0, 0.0);
    float3 up = cross(forward, right);   // (0, cos pitch, −sin pitch): world up, tilted with the camera
    float tanHalf = tan(0.5 * 52.0 * 3.14159 / 180.0);
    float focus = 5.0, aperture = 0.008;
    UnderstoryLog log = understory_log();
    float3 color = float3(0.0);
    for (int s = 0; s < kUnderstorySamples; s++) {
        float2 r = fract(float2(0.7548777, 0.5698403) * float(s + 1) + hash_f01_2(float2(px)) );
        float2 jitter = (r - 0.5) / size;
        float2 ndc = float2((uv.x + jitter.x) * 2.0 - 1.0, 1.0 - (uv.y + jitter.y) * 2.0);
        float3 rd = normalize(forward + right * ndc.x * tanHalf * aspect + up * ndc.y * tanHalf);
        float angle = 6.28318 * r.y, radius = aperture * sqrt(r.x);
        float3 lens = right * cos(angle) * radius + up * sin(angle) * radius;
        float3 target = ro + rd * (focus / dot(rd, forward));
        float3 origin = ro + lens;
        color += understory_forest_ray(origin, normalize(target - origin), log);
    }
    color /= float(kUnderstorySamples);
    return color * 0.62;   // low-key exposure: the forest is dim, the moving ferns are the light
}

fragment float4 understory_backdrop_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant UnderstoryFieldGPU& field [[buffer(6)]],
    texture2d<float> prev [[texture(20)]]
) {
    float4 cached = prev.read(uint2(in.position.xy));
    if (cached.a > 0.5) { return cached; }                       // built: carry it
    // Not yet built: this pixel's 8×8 TILE has its turn one frame in kUnderstoryBuildTurns (a
    // ~1.6 s dissolve-in). Tiles, not pixels: the GPU runs pixels in groups of 32, and a per-pixel
    // turn pattern put a live pixel in nearly every group every frame, so the whole screen paid
    // the full forest cost each build frame (2.9 s at 1080p, measured). Coherent tiles pay 1/96.
    // The build stretches with the pixel count so a 4K frame pays the same per-frame share as
    // 1080p (96 turns at 1080p, 384 at 4K): ~7.7 ms of build per frame, measured.
    float2 size = float2(prev.get_width(), prev.get_height());
    uint turns = uint(clamp(float(kUnderstoryBuildTurns) * size.x * size.y / (1920.0 * 1080.0), 96.0, 400.0));
    uint2 px = uint2(in.position.xy);
    uint2 tile = px / 8u;
    uint turn = (tile.x * 37u + tile.y * 91u + (tile.x * tile.y) % 7u) % turns;
    if (turn != uint(field.header.frame_index) % turns) { return float4(0.0); }
    return float4(understory_forest(in.uv, size, px), 1.0);
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
    float3 scene = forest.a > 0.5 ? forest.rgb : kUnderstoryHaze * 0.45;
    float3 ground = scene * (1.0 + 2.2 * understory_fern_light(in.uv, aspect, field)) * vignette;

    float3 color = ground * (1.0 - field4.a) + field4.rgb + glow * 0.25;
    color = color / (1.0 + 0.18 * color);   // soft shoulder so the glow never clips flat
    // Interleaved-gradient-noise dither, ±half an 8-bit step: the dark vignette bands otherwise.
    float dither = (fract(52.9829189 * fract(dot(in.position.xy, float2(0.06711056, 0.00583715)))) - 0.5) / 255.0;
    return float4(color + dither, 1.0);
}
