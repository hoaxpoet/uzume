// Fireflies.metal — the meadow the swarm flashes in, as a 3D place drawn as a screenprint (FF.2).
//
// THE LOOK (D-258, `docs/presets/FIREFLIES_DESIGN.md` §3; hero FF.R2 `07`): a stylized
// screenprint rendered from a real 3D scene. The rules, and where each is implemented:
//   • Ink, not paint — every pixel resolves to one of six inks sampled from `07` (`ff_ink`);
//     tone between two inks is expressed as COVERAGE of the lighter ink, never as a blend.
//   • Line, not fill — the coverage pattern is a line screen: grass blades on the ground,
//     hatching on the tree-line cards, stipple grain in the sky and the mist. Threshold
//     hatching after Freudenberg (2001) / Webb et al. (2002) §3.2: a pattern "height" h is
//     compared with the tone's fraction through a soft threshold of slope 1/fwidth(h).
//   • Value is depth — tone rises with distance (`ff_depth_tone`), so the near ground and the
//     near tree are darkest and the far tree line and the sky are lightest.
//   • Lights are the event — the brightest ink (5) is left to the fireflies' light (FF.3).
// Strokes are ANCHORED IN THE WORLD, not the screen, so they parallax with the camera; their
// world spacing doubles with distance (two octaves blended, the tonal-art-map mip rule of
// Praun et al. 2001) so they keep a constant on-screen density at every depth.
//
// THE PLACE (§4.1): one ray per pixel through the camera `FirefliesWorld` computes (buffer 6)
// — sky; a ground plane receding to the horizon; three tree-line cards (vertical planes at
// 115 / 160 / 230 m with ragged crown silhouettes, `05`'s layers); exponential height mist
// pooled in the low distance. The branching trees in front of the cards are real 3D segments
// drawn by `FirefliesGeometry` through the same camera; the fireflies after them.
//
// Silence (D-037): nothing here reads the music but the breath (FF.2 Task 5), so the world is
// lit at silence and its wind and mist keep moving — it coasts, never black.
//
// buffer(6) is `FFWorldGPU` (FirefliesWorld.swift). A ZEROED buffer (a generic harness that
// binds a blank slot 6) falls back to the rest camera and `features.time`.

struct FFWorld {
    float4 cam_pos;        // xyz, w = tan(half vertical FOV)
    float4 right;          // xyz, w = aspect
    float4 up;             // xyz, w = world time (s)
    float4 fwd;            // xyz, w = world breath 0…1
};

// MARK: - Inks and tone

/// The ink ladder sampled from `07` (k-means over its pixels), sRGB → linear. 0 near-black …
/// 4 the pale sky above the trees; 5 (the glow) is reserved for the light (FF.3). Mirrors
/// `ff_ink` in `Renderer/Shaders/Fireflies.metal` — keep the two in step.
static inline float3 ff_ink(int i) {
    const float3 inks[6] = { float3(2, 7, 22), float3(4, 16, 47), float3(9, 26, 73),
                             float3(18, 49, 114), float3(28, 80, 173), float3(79, 154, 233) };
    return pow(inks[clamp(i, 0, 5)] / 255.0, 2.2);
}

/// Value is depth: tone on the ink ladder of a surface `dist` metres away. Mirrors the branch
/// shader's `ff_depth_tone`.
static inline float ff_depth_tone(float dist) { return 3.4 * (1.0 - exp(-dist / 90.0)); }

/// Screenprint quantiser: `tone` on the 0…5 ladder, `h` the line-screen height (0 inks first),
/// `aa` its screen derivative. Returns the lower ink with the next ink printed where h < f —
/// continuous across every ink boundary, so a smooth gradient never shows a contour seam.
static inline float3 ff_print(float tone, float h, float aa) {
    tone = clamp(tone, 0.0, 4.999);
    int i = int(floor(tone));
    float f = tone - float(i);
    float cov = saturate((f - h) / max(aa, 0.02) + 0.5);
    return mix(ff_ink(i), ff_ink(i + 1), cov);
}

// MARK: - Noise

static inline float ff_hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float ff_noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(ff_hash(i), ff_hash(i + float2(1, 0)), u.x),
               mix(ff_hash(i + float2(0, 1)), ff_hash(i + float2(1, 1)), u.x), u.y);
}

/// fbm, 0…~1, `octaves` ≥ 4 on every hero surface (SHADER_CRAFT §12.1).
static inline float ff_fbm(float2 p, int octaves) {
    float sum = 0.0, amp = 0.5;
    for (int o = 0; o < octaves; o++) {
        sum += amp * ff_noise(p);
        p = p * 2.03 + float2(17.1, 9.3);
        amp *= 0.5;
    }
    return sum;
}

/// Interleaved gradient noise (Jimenez 2014): a blue-ish per-pixel threshold — the paper grain.
static inline float ff_grain(float2 px) {
    return fract(52.9829189 * fract(dot(px, float2(0.06711056, 0.00583715))));
}

// MARK: - Surfaces

/// Grass blades on the ground. A ground point is addressed by its bearing and inverse range
/// from the world origin — the rest camera's foot — so blade columns stand vertical on screen and
/// rows stay a constant height at every distance (a line screen in the rest camera's own frame),
/// yet the coordinates belong to the GROUND: a drifting camera sees them parallax like the
/// meadow they are. `col` / `row` are already in blade units; returns the pattern height (0 on
/// a blade's spine, 1 between blades).
static inline float ff_blades(float col, float row, float t, float breath) {
    float c = floor(col);
    float jitter = ff_hash(float2(c, 3.7)) - 0.5;
    float stagger = ff_hash(float2(c, 8.1));
    float r = row + stagger;
    float along = 1.0 - fract(r);                          // 0 root (near) … 1 tip (up the frame)
    float cell = floor(r);
    float size = 0.6 + 0.8 * ff_hash(float2(c, cell));     // blades differ in length
    // Wind leans each blade by its height; the breath widens the sway (Task 5).
    float gust = sin(0.8 * t + 0.05 * c + 0.9 * cell) + 0.5 * sin(2.3 * t + 0.21 * c);
    float lean = (0.25 * jitter + gust * (0.35 + 0.5 * breath)) * along;
    float across = abs(fract(col) - 0.5 - 0.3 * jitter - lean) * 2.0;
    float taper = max(1.0 - along / size, 0.0);           // blades narrow to a point
    return saturate(across / (0.55 * taper + 1e-3));
}

/// The crown line of tree-line card `k` at world x: height above the ground, metres. A row of
/// rounded crowns (one per ~7 m cell, each its own height and spread — a TREE line, not a
/// ridge), over a slow fbm swell, with a fine fbm fringe for the twigs.
static inline float ff_crown(float x, int k) {
    float seed = float(k) * 31.7;
    float cell_w = 6.0 + 2.0 * float(k);
    float c = floor(x / cell_w);
    float top = 0.0;
    for (int n = -1; n <= 1; n++) {
        float id = c + float(n);
        float cx = (id + 0.2 + 0.6 * ff_hash(float2(id, seed))) * cell_w;
        float r = cell_w * (0.55 + 0.5 * ff_hash(float2(id, seed + 1.0)));
        float ch = 4.0 + 9.0 * ff_hash(float2(id, seed + 2.0));
        float dx = (x - cx) / r;
        top = max(top, ch + r * 0.8 * sqrt(max(1.0 - dx * dx, 0.0)));
    }
    float swell = 6.0 * ff_fbm(float2(x / 60.0, seed + 3.0), 4);
    float twigs = 2.0 * ff_fbm(float2(x / 1.3, seed + 11.0), 6);
    return 3.0 * float(k) + top + swell + twigs;
}

/// Lace along a crown edge: inside the top `fringe` metres of a card, only where fine noise
/// clears the depth into the fringe — the see-through twig mass of `03`.
static inline bool ff_inside_card(float x, float y, int k) {
    float top = ff_crown(x, k);
    if (y >= top) return false;
    const float fringe = 2.5;
    float into = (top - y) / fringe;
    if (into >= 1.0) return true;
    return ff_fbm(float2(x * 2.2, y * 2.2) + float(k) * 7.0, 4) > 0.62 - 0.35 * into;
}

// MARK: - Fragment

fragment float4 fireflies_world_fragment(VertexOut in [[stage_in]],
                                         constant FeatureVector& features [[buffer(0)]],
                                         constant FFWorld& world [[buffer(6)]]) {
    // Camera (the rest camera if slot 6 is blank).
    float3 ro = world.cam_pos.xyz, right = world.right.xyz, up = world.up.xyz, fwd = world.fwd.xyz;
    float tan_y = world.cam_pos.w, aspect = world.right.w, t = world.up.w, breath = world.fwd.w;
    if (dot(fwd, fwd) < 0.5) {
        const float pitch = 6.6 * 3.14159265 / 180.0;
        ro = float3(0, 1.5, 0);
        fwd = float3(0, sin(pitch), cos(pitch));
        right = float3(1, 0, 0);
        up = cross(fwd, right);
        tan_y = tan(20.0 * 3.14159265 / 180.0);
        aspect = features.aspect_ratio > 0.0 ? features.aspect_ratio : 16.0 / 9.0;
        t = features.time;
        breath = 0.0;
    }
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float3 rd = normalize(fwd + ndc.x * tan_y * aspect * right + ndc.y * tan_y * up);
    float2 px = in.position.xy;
    float height_px = 1.0 / max(abs(dfdy(in.uv.y)), 1e-5);
    float fpx = 0.5 * height_px / tan_y;                    // px per metre at 1 m

    float grain = 0.65 * ff_grain(px) + 0.35 * ff_hash(floor(px * 0.5));
    // Each surface yields a tone and the line screen at two octaves (ha, hb, weight `blend`):
    // the two octaves are PRINTED separately and their colours blended — the tonal-art-map rule
    // (Praun et al. 2001), which keeps strokes whole instead of averaging two screens into mush.
    float tone, ha, hb, blend = 0.0, dist;
    // The grass is a second, CUT layer over the ground's halftone: blades printed ~1.7 inks
    // lighter wherever the blade screen clears `blade_density` (0 off the ground).
    float blade_h = 1.0, blade_density = 0.0;

    // Nearest surface: the ground, or a tree-line card standing on it.
    float t_ground = rd.y < -1e-4 ? -ro.y / rd.y : 1e9;
    const float card_z[3] = { 115.0, 160.0, 230.0 };
    int card = -1;
    float t_card = 1e9, card_y = 0.0, card_x = 0.0;
    if (rd.z > 1e-3) {
        for (int k = 0; k < 3; k++) {
            float tk = (card_z[k] - ro.z) / rd.z;
            if (tk <= 0.0 || tk >= t_ground) continue;
            float3 p = ro + rd * tk;
            if (ff_inside_card(p.x, p.y, k)) { card = k; t_card = tk; card_y = p.y; card_x = p.x; break; }
        }
    }

    if (card >= 0) {
        // A far tree line: hatched diagonally, the stroke spacing constant on screen.
        dist = t_card;
        float spacing = 3.5 * dist / fpx;                   // ~3.5 px between lines
        float level = log2(spacing / 0.25), lo = floor(level);
        blend = level - lo;
        float c = card_x + 0.6 * card_y;
        ha = abs(fract(c / (0.25 * exp2(lo))) - 0.5) * 2.0 * 0.8 + 0.2 * grain;
        hb = abs(fract(c / (0.25 * exp2(lo + 1.0))) - 0.5) * 2.0 * 0.8 + 0.2 * grain;
        // Crowns darker than the foot of the card, where the mist gathers.
        tone = ff_depth_tone(dist) - 0.35 * saturate(card_y / 18.0);
    } else if (t_ground < 1e8) {
        // The meadow: grass blades cut two inks lighter than the dark ground they grow from.
        // Their coverage is the tone's fraction, so the near ground is darkest (value is depth).
        dist = t_ground;
        float3 p = ro + rd * dist;
        float range = max(length(p.xz), 0.5);
        float col = atan2(p.x, p.z) * fpx / 6.0;           // a blade every ~6 px across
        float row = 1.5 * fpx / range / 16.0;              // ~16 px tall
        blade_h = ff_blades(col, row, t, breath) * 0.9 + 0.1 * grain;
        float patchy = ff_fbm(p.xz / 14.0, 4);
        blade_density = 0.30 + 0.35 * patchy;
        tone = 0.2 + ff_depth_tone(dist) * 0.6 + 0.4 * (patchy - 0.5);
        ha = grain;
        hb = grain;
    } else {
        // The sky: brightest just above the tree line, deepening overhead; stipple grain.
        dist = 1e4;
        float e = max(rd.y, 0.0);
        tone = mix(3.7, 1.7, smoothstep(0.0, 0.42, e));
        tone += 0.25 * (ff_fbm(float2(rd.x / max(rd.y + 0.2, 0.05), rd.y) * 3.0 + float2(0.01 * t, 0.0), 4) - 0.5);
        ha = grain;
        hb = grain;
    }

    // Mist: exponential height fog pooled in the low ground (scale height 2.2 m), thickest far
    // off where the rays graze the meadow; drifting with the wind. It lifts the tone toward the
    // pale ink and dissolves the line screen into grain.
    float b = 1.0 / 2.2;
    float tt = min(dist, 400.0);
    float3 mid = ro + rd * min(tt, 140.0);
    float density = 0.014 * (0.55 + 0.9 * ff_fbm(float2(mid.x + 0.7 * t * (1.0 + breath), mid.z) / 45.0, 4));
    float ry = abs(rd.y) < 1e-4 ? 1e-4 : rd.y;
    float optical = density * exp(-b * ro.y) * (1.0 - exp(-b * ry * tt)) / (b * ry);
    float mist = 1.0 - exp(-max(optical, 0.0));
    tone = mix(tone, 3.3, mist);
    ha = mix(ha, grain, mist);
    hb = mix(hb, grain, mist);

    float3 col_a = ff_print(tone, ha, clamp(fwidth(ha), 0.02, 0.5));
    float3 col_b = ff_print(tone, hb, clamp(fwidth(hb), 0.02, 0.5));
    float3 misted = ff_print(tone, grain, 0.02);
    float3 col = mix(col_a, col_b, blend);
    float blade = saturate((blade_density * (1.0 - mist) - blade_h) / clamp(fwidth(blade_h), 0.05, 0.5) + 0.5);
    col = mix(col, ff_print(tone + 1.7, grain, 0.02), blade);
    return float4(mix(col, misted, smoothstep(0.35, 0.75, mist)), 1.0);
}
