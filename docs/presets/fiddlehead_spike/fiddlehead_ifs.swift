// fiddlehead.swift — FH look-spike (throwaway; not engine code, imports nothing from Uzume).
//
// One large fern, grown by Flexi's three-map feedback IFS ("flexi - fractal seafood", the maps
// and constants as ported in Understory.metal), with the per-generation bend `ww` as a CURL
// control: large ww rolls the frond into a crozier whose leaflets are themselves croziers;
// small ww opens it. Shaded toward Matt's 2026-10-05 reference
// (docs/VISUAL_REFERENCES/fiddlehead/01_reference_matt_2026-10-05.webp).
//
// FH.1 adaptations (context only; the three maps are Flexi's):
//   - the branches along the stalk are the SAME recursive fern at a looser curl: open fronds that
//     curl at the tip, whose leaflets curl at theirs (the reference's lower branches)
//   - recursion depth bounded only by what pixels can show (LMAX side-arm hops)
//   - a pointed leaf-shaped seed, and a second channel texture carrying each element's own
//     leaf coordinates (lateral −1…1, along −1…1) through the feedback, so every leaf can draw
//     a midrib, a two-tone glass surface, an iridescent margin, and a bead at its tip
//   - Flexi's fade restored for shading (dnOf), seams from the density Laplacian
//
// Build:  swiftc -O -swift-version 5 fiddlehead.swift -o /tmp/fiddlehead
// Usage:  fiddlehead still <curl> <out.png>
//         fiddlehead film <seconds> <out.mp4>        (curl tight → open → tight, slow sway)
//         fiddlehead raw <curl> <out.png>            (blade IFS density only, geometry checks)

import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Shaders

let msl = """
#include <metal_stdlib>
using namespace metal;

struct P {
    float4 a;      // ww (curl), w (heading), time (s), max side-arm hops (LMAX)
    float4 g;      // seed leaf width, length; seed radius scale, main-arm contraction (Flexi 1.12)
    float4 view;   // (raw mode) frame uv at screen centre (xy), frame-v per screen height (z), debug mode
    float4 blade;  // blade seed in q (xy), lean (rad, clockwise), frame-heights per screen-height
    float4 stalk;  // stalk base (xy) and Bezier control (zw), in q
    float4 look;   // stalk radius base, top; branch scale multiplier first, step
    float4 thr2;   // body brightness, rim brightness, camera zoom (1 = tight framing), bokeh brightness
    float4 thr;    // outline: body threshold, interior start, seam probe (px), seam Laplacian scale
    float4 light;  // the light inside the coil: eye in q (xy), radius (z), intensity (w)
    float4 coil;   // blade coil eye (xy), branch-fern coil eye (zw), frame uv
    float4 size;   // outW, outH, ifsW, ifsH (of the fern being stepped)
    float4 k;      // chain caps K1, K2 (999 = off: the full self-similar fern), unused, unused
    float4 ex2;    // leaflet scale q8 (Flexi 3.3), branch curl side (±1), branch angle off the stalk (rad), blurred-garden brightness
    float4 ex;     // stem threshold (level 0 draws thin), edge band width, LOD radius (px), small-coil warmth
};

constexpr sampler lin(filter::linear, mip_filter::linear, address::clamp_to_zero);

static float4 tap(texture2d<float> t, float2 c) {
    if (any(c < 0.0) || any(c > 1.0)) { return float4(0.0); }
    return t.sample(lin, c, level(0.0));
}

// MARK: IFS step
// t0: R density, G age·R, B stem·R, A level·R   (level = side-arm hops: 0 rachis, 1 pinna, 2 pinnule)
// t1: R lateral·R, G along·R, B own·R          (leaf coordinates −1…1; own = link index along its chain)

kernel void ifs_step(texture2d<float> prev0 [[texture(0)]],
                     texture2d<float> prev1 [[texture(1)]],
                     texture2d<float, access::write> next0 [[texture(2)]],
                     texture2d<float, access::write> next1 [[texture(3)]],
                     constant P& p [[buffer(0)]],
                     uint2 gid [[thread_position_in_grid]]) {
    float2 size = p.size.zw;
    if (any(float2(gid) >= size)) { return; }
    float2 uv = (float2(gid) + 0.5) / size;
    const float4 aspect = float4(1.0, 0.75, 1.0, 4.0 / 3.0);   // Flexi's 4:3 frame

    // Flexi's maps, q-names as in the source (see Understory.metal provenance).
    float ww = p.a.x, w = p.a.y;
    float q1 = cos(ww), q2 = sin(ww), q3 = p.g.w;
    float q4 = 0.042 * sin(w), q5 = 0.042 * cos(w);
    float a = 0.5 * asin(1.0);
    float d = 0.08;
    float q6 = cos(a), q7 = sin(a), q8 = p.ex2.x;   // Flexi: 3.3 (FH.1 tests longer leaflets)
    float q9 = cos(-w + asin(1.0)) * d * aspect.x;
    float q10 = sin(-w + asin(1.0)) * d * aspect.y;
    float q11 = cos(-a), q12 = sin(-a);

    float2 fa = (uv - 0.5) * aspect.xy;
    float2 r3 = float2(fa.x * q1 - fa.y * q2, fa.x * q2 + fa.y * q1);
    float2 r5 = float2(fa.x * q6 - fa.y * q7, fa.x * q7 + fa.y * q6);
    float2 r7 = float2(fa.x * q11 - fa.y * q12, fa.x * q12 + fa.y * q11);
    float2 cm = 0.5 + r3 * aspect.zw * q3 + float2(q4, q5) * aspect.zw;
    float2 cl = 0.5 + r5 * aspect.zw * q8 + float2(q9, q10);
    float2 cr = 0.5 + r7 * aspect.zw * q8 + float2(q9, q10);

    // A pixel is the seed after a path of maps (newest outermost). Channels track: age = path
    // length; stem = the LEADING run of main-arm maps (where along the parent this branch sits);
    // own = the TRAILING run (position along the pixel's own innermost chain); level = side hops.
    // Prepending a map: own grows only while the whole path is main-arm (level 0).
    float4 m0 = tap(prev0, cm), l0 = tap(prev0, cl), r0 = tap(prev0, cr);
    float4 m1 = tap(prev1, cm), l1 = tap(prev1, cl), r1 = tap(prev1, cr);
    float im = 1.0 / max(m0.x, 1e-4), il = 1.0 / max(l0.x, 1e-4), ir = 1.0 / max(r0.x, 1e-4);
    float mLvl = m0.w * im, lLvl = l0.w * il + 1.0, rLvl = r0.w * ir + 1.0;
    float mOwn = m1.z * im + (mLvl < 0.5 ? 1.0 : 0.0), lOwn = l1.z * il, rOwn = r1.z * ir;
    // Depth and length caps (FH.1): at most LMAX side hops; a level-1 chain stops after K1 links
    // (a leaflet still curls into a small crozier), a level-2 chain after K2 (a short leaf blade).
    float kL = lLvl > 1.5 ? p.k.y : p.k.x, kR = rLvl > 1.5 ? p.k.y : p.k.x;
    float kM = mLvl > 1.5 ? p.k.y : p.k.x;
    if (lLvl > p.a.w + 0.5 || lOwn > kL) { l0 = float4(0.0); }
    if (rLvl > p.a.w + 0.5 || rOwn > kR) { r0 = float4(0.0); }
    if (mLvl > 0.5 && mOwn > kM) { m0 = float4(0.0); }
    float4 won = m0, won1 = m1; float lvl = mLvl, own = mOwn; bool viaMain = true;
    if (l0.x > won.x) { won = l0; won1 = l1; lvl = lLvl; own = lOwn; viaMain = false; }
    if (r0.x > won.x) { won = r0; won1 = r1; lvl = rLvl; own = rOwn; viaMain = false; }
    float inv = 1.0 / max(won.x, 1e-4);
    float density = max(won.x - 0.015, 0.0);
    float age = won.y * inv + 1.0;
    float stem = viaMain ? won.z * inv + 1.0 : 0.0;
    float2 leaf = won1.xy * inv;

    // Seed: a pointed leaf (FH.1), long along the growth axis (+v), cone 1 at the centre → 0 at the edge.
    float2 seedRadius = 0.5 * 0.0578 * p.g.z * float2(aspect.y * p.g.x, aspect.x * p.g.y);
    float2 n = (uv - 0.5) / seedRadius;
    float halfWidth = max(1.0 - n.y * n.y, 0.05);
    float lat = n.x / halfWidth;
    float seed = max(1.0 - length(float2(lat, n.y)), 0.0);
    float total = min(density + seed, 1.0);
    float share = density / max(density + seed, 1e-4);
    next0.write(float4(total, total * age * share, total * stem * share, total * lvl * share), gid);
    float2 leafOut = share * leaf + (1.0 - share) * float2(clamp(lat, -1.0, 1.0), n.y);
    next1.write(float4(total * leafOut, total * own * share, 0.0), gid);
}

// MARK: shading helpers

static float hash21(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }

// The reference's rim colours, cycled: violet → blue → cyan → gold → magenta → violet.
static float3 irid(float t) {
    const float3 k[5] = { float3(0.55, 0.20, 1.00), float3(0.15, 0.40, 1.00), float3(0.10, 0.95, 0.90),
                          float3(1.00, 0.65, 0.10), float3(1.00, 0.25, 0.70) };
    float x = fract(t) * 5.0;
    int i = int(x);
    return mix(k[i % 5], k[(i + 1) % 5], smoothstep(0.0, 1.0, fract(x)));
}

static float2 frameToTex(float2 f) { return float2(f.x, 1.0 - f.y); }
static float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }

// MARK: the plant: stalk + blade + pinnae, in screen-height space q (y down)

static float2 bez(constant P& p, float t) {
    // Ends at the blade's seed; the seed blob fades in over the first generation (see alpha).
    float2 a = p.stalk.xy, b = p.stalk.zw, c = p.blade.xy + float2(sin(p.blade.z), -cos(p.blade.z)) * 0.0;
    return mix(mix(a, b, t), mix(b, c, t), t);
}

// Winner of the composite: IFS channels, leaf channels, frame uv, which (0 blade, 1 branch copy, 2 stalk).
struct Hit { float4 c; float4 l; float2 f; float which; };

static void copyAt(texture2d<float> t0, texture2d<float> t1, float which, float2 q, float2 at, float ang,
                   float scale, float mirror, thread Hit& h) {
    float2 r = rot(q - at, -ang);
    float2 f = 0.5 + float2(mirror * r.x * 0.75, -r.y) * scale;
    float2 tc = frameToTex(f);
    float4 c = tap(t0, tc);
    if (c.x > h.c.x) { h.c = c; h.l = tap(t1, tc); h.l.x *= mirror; h.f = f; h.which = which; }
}

static Hit plant(texture2d<float> b0, texture2d<float> b1, texture2d<float> p0, texture2d<float> p1,
                 constant P& p, float2 q) {
    Hit h; h.c = float4(0.0); h.l = float4(0.0); h.f = float2(-9.0); h.which = -1.0;
    float mirror = -1.0;   // the reference coils clockwise; Flexi's frond coils anticlockwise
    // Stalk: a tapered tube along the quadratic Bezier, base → blade seed.
    float best = 1e9, bt = 0.0, side = 1.0;
    float2 prev = bez(p, 0.0);
    for (int i = 1; i <= 24; i++) {
        float t = float(i) / 24.0;
        float2 cur = bez(p, t);
        float2 pa = q - prev, ba = cur - prev;
        float u = saturate(dot(pa, ba) / dot(ba, ba));
        float d = length(pa - ba * u);
        if (d < best) { best = d; bt = (float(i - 1) + u) / 24.0; side = sign(ba.x * pa.y - ba.y * pa.x); }
        prev = cur;
    }
    float rad = mix(p.look.x, p.look.y, bt);
    float sd = saturate(1.0 - best / rad);
    if (sd > 0.0) {
        float D = sqrt(sd);
        h.c = float4(D, 0.0, 0.0, 0.0); h.l = float4(D * side * best / rad, 0.0, 0.0, 0.0); h.which = 2.0;
    }
    copyAt(b0, b1, 0.0, q, p.blade.xy, p.blade.z, p.blade.w, mirror, h);
    // Branches: the SAME recursive fern (uncapped: its leaflets curl at their tips, and theirs do),
    // grown at a looser curl — open fronds that curl at the tip, as the reference's lower branches.
    for (int k = 0; k < 6; k++) {
        float t = 0.18 + 0.135 * float(k);
        float2 at = bez(p, t), tg = normalize(bez(p, t + 0.01) - at);
        float up = atan2(tg.x, -tg.y);                 // stalk direction as a clockwise angle from up
        float s = (k % 2 == 0) ? 1.0 : -1.0;
        float sc = p.blade.w * (p.look.z + p.look.w * float(k));
        copyAt(p0, p1, 1.0, q, at, up + s * p.ex2.z, sc, -s * mirror * p.ex2.y, h);
    }
    return h;
}

// Flexi's fade subtracts 0.015 per generation; adding it back makes every element the same cone.
static float dnOf(float4 c) { return c.x > 0.0 ? c.x + 0.015 * (c.y / max(c.x, 1e-4)) : 0.0; }

static float2 screenQ(constant P& p, float2 s, float2 sz) {
    float2 q = (s - 0.5 * sz) / sz.y;
    return float2(0.0, 0.5) + (q - float2(0.0, 0.5)) * p.thr2.z;   // camera eases back as the frond opens
}

// The lit fern (premultiplied rgb, alpha) at one screen pixel.
kernel void shade(texture2d<float> b0 [[texture(0)]], texture2d<float> b1 [[texture(1)]],
                  texture2d<float> p0 [[texture(2)]], texture2d<float> p1 [[texture(3)]],
                  texture2d<float, access::write> lit [[texture(4)]],
                  constant P& p [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    // Supersampled: `lit` is 2× the output; present() reads mip 1 (a 2×2 box) — the finest
    // leaflets are narrower than an output pixel and alias into speckle without it.
    float2 sz = float2(lit.get_width(), lit.get_height());
    if (any(float2(gid) >= sz)) { return; }
    float2 s = float2(gid) + 0.5;
    float2 q = screenQ(p, s, sz);
    float px = 2.0 * p.thr2.z / sz.y;   // probes and LOD stay in OUTPUT pixels
    Hit h = plant(b0, b1, p0, p1, p, q);
    float4 c = h.c;
    float D = c.x;
    float inv = 1.0 / max(D, 1e-4);
    float age = c.y * inv, stem = c.z * inv, lvl = c.w * inv;
    float lat = clamp(h.l.x * inv, -1.0, 1.0), along = clamp(h.l.y * inv, -1.0, 1.0);

    // Normal + seams from the composite, fade-restored density. Overlapping leaflets are a max of
    // cones: where two meet, Dn dips (Laplacian > 0) — the dark seams between leaflets.
    float e = p.thr.z * px;
    float nx0 = dnOf(plant(b0, b1, p0, p1, p, q + float2(e, 0)).c), nx1 = dnOf(plant(b0, b1, p0, p1, p, q - float2(e, 0)).c);
    float ny0 = dnOf(plant(b0, b1, p0, p1, p, q + float2(0, e)).c), ny1 = dnOf(plant(b0, b1, p0, p1, p, q - float2(0, e)).c);
    float Dn = dnOf(c);
    float lap = (nx0 + nx1 + ny0 + ny1) - 4.0 * Dn;
    float3 n = normalize(float3(-(nx0 - nx1) * 6.0, (ny0 - ny1) * 6.0, 1.0));

    // Level of detail: Dn falls 1 → 0 across an element's radius, so 1/|∇Dn| is that radius in
    // pixels. Outlines, margins and seams only draw on elements big enough to carry them; smaller
    // ones read as solid leaf (drawn on every element they turned the frond into lace).
    float grad = length(float2(nx0 - nx1, ny0 - ny1)) / (2.0 * p.thr.z);
    float detail = smoothstep(p.ex.z, 2.0 * p.ex.z, 1.0 / max(grad, 1e-3));
    // An element NARROWER than the probe has empty space on both sides: the gradient cancels to ~0
    // and reads as "huge". Its neighbours' mean is far below its centre (lap ≪ 0) — that is small.
    detail *= 1.0 - smoothstep(1.0, 2.5, -lap / max(Dn, 1e-3));
    float seam = smoothstep(0.0, p.thr.w, lap) * step(0.0, Dn) * detail;
    // One seed stamps every level, but the reference wants a THIN stem and BROAD leaflets: the
    // density is a cone, so the threshold sets the drawn width — high for the rachis, low for leaves.
    float th = mix(p.ex.x, p.thr.x, saturate(lvl));
    float body = smoothstep(th, th + 0.06, Dn);
    float edge = body * (1.0 - smoothstep(th + 0.06, th + 0.06 + p.ex.y, Dn));
    float core = smoothstep(p.thr.y, 1.0, Dn);
    bool isStalk = h.which > 1.5;

    // Leaf anatomy from the element's own coordinates: a pale midrib, a thin margin, a glassy sheen
    // band to one side of the rib, and two tones across the blade (light catches one half).
    float alat = abs(lat);
    float midrib = 1.0 - smoothstep(0.0, 0.14, alat);
    float margin = smoothstep(0.62, 0.92, alat) * body * detail;
    float sheen = pow(saturate(1.0 - abs(lat + 0.40) * 2.6), 2.0);
    float3 warmSide = float3(0.30, 0.62, 0.06), coolSide = float3(0.04, 0.42, 0.34);
    float3 green = mix(coolSide, warmSide, smoothstep(-0.6, 0.6, lat));
    green *= mix(0.55, 1.0, saturate(lvl * 0.5 + 0.3));                    // rachis darker than leaflets
    if (isStalk) { green = mix(float3(0.06, 0.24, 0.04), float3(0.20, 0.45, 0.10), 1.0 - alat); }

    // The light inside the coil: inner leaflets glow orange through, hottest at the eye.
    float2 dl = (q - p.light.xy) / p.light.z;
    float L = p.light.w * exp(-dot(dl, dl));
    // Each small crozier's own eye (frame uv) gets a little of the same warmth.
    float2 eye = h.which < 0.5 ? p.coil.xy : p.coil.zw;
    float2 dc = (h.f - eye) * float2(1.333, 1.0);
    float warm = (h.which < 1.5) ? p.ex.w * exp(-dot(dc, dc) / (0.05 * 0.05)) : 0.0;
    float transmit = saturate(L + warm);
    green = mix(green, float3(0.78, 0.20, 0.01), transmit * (isStalk || lvl < 0.5 ? 0.4 : 1.0));   // rachis stays green

    float key = saturate(dot(n, normalize(float3(-0.4, 0.5, 0.75))));
    float3 col = green * p.thr2.x * (0.35 + 0.65 * key) * (1.0 + 0.5 * core + 0.35 * sheen + 0.45 * midrib);
    col += float3(1.0, 0.33, 0.04) * (L + warm) * (0.35 + 0.8 * core + 0.9 * midrib);

    // Iridescence lives on the margins and the silhouette only: one hue per leaflet, nudged by the
    // edge direction, so the leaf bodies stay green (an all-edge rim washed the open frond white).
    float ang = atan2(n.y, n.x + 1e-5) / 6.2831;   // atan2(0, 0) is NaN off the frond
    float3 ir = irid(fract(stem * 0.07 + lvl * 0.31 + ang * 0.35 * detail + p.a.z * 0.03));   // ang is noise on tiny leaves
    float seamLine = seam * (1.0 - seam) * 4.0;
    col *= 1.0 - 0.85 * seam;
    col += ir * p.thr2.y * (margin * 0.9 + edge * mix(0.08, 0.6, detail) + seamLine * 0.5);


    // Beads: a bright drop at the tip of every leaflet, twinkling per leaflet.
    // The tip of a chain is its last link (own == cap): a bead sits there, on the leaf's point.
    float own = h.l.z * inv;
    float2 caps = p.k.xy;
    float cap = lvl > 1.5 ? caps.y : caps.x;
    float lastLink = smoothstep(cap - 1.5, cap - 0.5, own);
    // Rim light from behind: the silhouette (any neighbour off the fern) catches cool iridescence.
    float outside = 1.0 - min(min(nx0, nx1), min(ny0, ny1)) / max(th, 1e-3);
    float sil = body * smoothstep(0.0, 1.0, outside) * detail;
    col += mix(ir, float3(0.45, 0.35, 1.0), 0.35) * sil * p.thr2.y * 0.9;
    // Beads ride the elements (so they never swim as the fern moves): every chain's last link gets
    // one; other links get one by chance, far more often on the silhouette (the reference's beaded rim).
    float tipShape = smoothstep(0.35, 0.85, along) * (1.0 - smoothstep(0.3, 0.75, alat)) * body;
    float id = hash21(float2(floor(age + 0.5) + 3.1 * floor(own + 0.5), floor(stem + 0.5) + 17.0 * floor(lvl + 0.5) + 41.0 * h.which));
    float tw = 0.55 + 0.45 * sin(p.a.z * (1.5 + 3.0 * id) + id * 40.0);
    float chance = step(1.0 - mix(0.12, 0.7, sil), id);
    float bead = isStalk ? 0.0 : tipShape * max(lastLink, chance) * step(0.5, lvl) * tw;
    col += mix(float3(1.0, 0.85, 0.6), ir, 0.3) * bead * p.thr2.y * 6.0;

    float alpha = body * (h.which < 1.5 ? smoothstep(0.0, 1.2, age) : 1.0);   // the IFS seed itself is not a leaf
    lit.write(alpha > 0.0 ? float4(col * alpha, alpha) : float4(0.0), gid);
}

// 3×3 tent over a mip level: hides the box-filter squares a single mip read shows.
static float4 blur(texture2d<float> t, float2 uv, float lod) {
    float2 o = exp2(lod) / float2(t.get_width(), t.get_height());
    float4 acc = float4(0.0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float w = (2.0 - abs(float(i))) * (2.0 - abs(float(j)));
        acc += t.sample(lin, uv + float2(i, j) * o, level(lod)) * w;
    }
    return acc / 16.0;
}

// One parallax layer of bokeh (technique after knarkowicz's "Bokeh Paralax", Shadertoy 4s2yW1,
// written fresh): a staggered grid of cells, each holding at most one out-of-focus highlight — a
// flat disc with a soft edge and a faint glow halo. `soft` widens the edge for nearer layers.
static float3 bokehLayer(float2 p, float cellSize, float soft, float seed, float p_density) {
    float row = floor(p.y / cellSize + 0.5);
    if (fmod(abs(row), 2.0) > 0.5) { p.x += 0.5 * cellSize; }
    float2 cell = floor(p / cellSize + 0.5);
    float2 local = p - cell * cellSize;
    float h0 = hash21(cell + seed), h1 = hash21(cell + seed + 7.1), h2 = hash21(cell + seed + 13.7);
    if (h0 > p_density) { return float3(0.0); }                        // not every cell has a light
    local += (float2(h1, h2) - 0.5) * cellSize * 0.4;              // break the grid
    float r = cellSize * mix(0.16, 0.34, h1);
    float sdf = length(local) - r;
    float disc = 1.0 - smoothstep(-soft * r, soft * r * 0.3, sdf);
    float rimLift = 1.0 + 0.35 * smoothstep(-0.35 * r, -0.05 * r, sdf) * disc;
    float glow = 0.18 * exp(-max(sdf, 0.0) / (0.5 * r)) * (1.0 - disc);
    float3 hue = h2 < 0.30 ? float3(0.10, 0.55, 0.50) : (h2 < 0.55 ? float3(0.45, 0.52, 0.12)
               : (h2 < 0.80 ? float3(0.45, 0.22, 0.70) : float3(0.95, 0.50, 0.12)));
    return hue * (disc * rimLift + glow) * mix(0.35, 1.0, fract(h0 * 7.77));
}

// Final: the out-of-focus garden behind, the lit fern, bloom.
kernel void present(texture2d<float> lit [[texture(0)]],
                    texture2d<float> b0 [[texture(1)]],
                    texture2d<float, access::write> out [[texture(4)]],
                    constant P& p [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    if (any(float2(gid) >= p.size.xy)) { return; }
    float2 s = float2(gid) + 0.5;
    float2 uv = s / p.size.xy;
    float aspect = p.size.x / p.size.y;
    float t = p.a.z;

    // Ground: near-black, faint dark verticals up top (distant stems), a low green-teal haze below.
    float3 bg = float3(0.008, 0.011, 0.016) * (0.75 + 0.25 * sin(uv.x * 31.0 + sin(uv.x * 9.0) * 2.0));
    bg += float3(0.010, 0.030, 0.026) * smoothstep(0.35, 1.0, uv.y);

    // Out-of-focus ferns: copies of the fern, heavily blurred, tinted, at depth.
    const float3 tints[5] = { float3(0.30, 0.16, 0.50), float3(0.08, 0.36, 0.40), float3(0.45, 0.34, 0.10),
                              float3(0.14, 0.40, 0.16), float3(0.25, 0.20, 0.55) };
    // centre uv, size (screen heights per frame height), mirror, which fern
    const float4 xf[5] = { float4(0.08, 0.92, 0.55, 1.0), float4(0.93, 0.86, 0.65, -1.0), float4(0.70, 1.08, 0.45, -1.0),
                           float4(0.30, 1.12, 0.40, 1.0), float4(0.97, 0.45, 0.30, -1.0) };
    for (int i = 0; i < 5; i++) {
        float2 q = (uv - xf[i].xy) * float2(aspect, 1.0) / xf[i].z;
        q.x *= xf[i].w;
        q = rot(q, 0.15 * sin(t * 0.21 + float(i)));        // a slow drift: the garden breathes
        float2 tc = frameToTex(float2(0.5 + q.x * 0.75, 0.50 - q.y));
        float g = blur(b0, tc, i % 2 == 0 ? 5.0 : 4.0).x;
        bg += tints[i] * g * 0.55;
    }
    // Bokeh in four parallax depths: far = small, many, crisp, slow; near = large, few, soft, faster.
    // Mostly in the lower two thirds, where the lit foliage would be.
    float2 pb = (uv - 0.5) * float2(aspect, 1.0);
    float3 bk = float3(0.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 pl = rot(pb, 0.3 + 0.7 * fi) + float2(t * 0.004 * (1.0 + 1.5 * fi), 0.37 * fi);
        bk += bokehLayer(pl, 0.11 + 0.09 * fi, 0.25 + 0.25 * fi, 11.0 * fi, 0.30 - 0.06 * fi) * mix(1.0, 0.6, fi / 2.0);
    }
    // Lights gather low and at the sides (the garden), and fade out behind the fern's crown.
    float side = smoothstep(0.15, 0.45, abs(uv.x - 0.5));
    bg += bk * p.thr2.w * smoothstep(0.25, 0.85, uv.y) * (0.45 + 0.55 * side);

    // The out-of-focus garden: THIS frame's lit fern, mirrored, enlarged and blurred hard, low in the
    // corners — so the background always shares the fern's colours and glints.
    const float4 gx[3] = { float4(0.08, 1.02, 1.5, -1.0), float4(0.92, 1.05, 1.7, -1.0), float4(0.55, 1.22, 1.3, 1.0) };
    for (int i = 0; i < 3; i++) {
        float2 g = (uv - gx[i].xy) / gx[i].z;
        g.x *= gx[i].w;
        float2 guv = float2(0.45, 0.55) + g;
        float3 gl = blur(lit, guv, 4.0).rgb;
        bg += gl * p.ex2.w * float3(0.75, 0.7, 1.0) * smoothstep(0.45, 0.95, uv.y);
    }

    // The coil's light spills onto the air behind the fern.
    float2 q = screenQ(p, s, p.size.xy);
    float2 dl = (q - p.light.xy) / (p.light.z * 1.8);
    bg += float3(0.9, 0.38, 0.06) * 0.22 * p.light.w * exp(-dot(dl, dl));

    float4 fern = lit.sample(lin, uv, level(1.0));
    float3 col = bg * (1.0 - fern.a) + fern.rgb;
    // The fern's outer silhouette (sharp alpha minus blurred alpha) catches a rim light whose hue
    // turns around the coil's eye — violet, blue, cyan, gold — the reference's kaleidoscope rim.
    float rimBand = saturate((fern.a - blur(lit, uv, 2.0).a) * 2.0);
    float2 ql = screenQ(p, s, p.size.xy) - p.light.xy;
    float3 rimHue = irid(atan2(ql.y, ql.x) / 6.2831 + 0.55 + 0.02 * t);
    col = mix(col, col * 0.7 + rimHue * 0.55, rimBand * 0.6);   // tint, don't add: thin leaflets are ALL rim
    float3 bloom = blur(lit, uv, 2.0).rgb * 0.30 + blur(lit, uv, 4.0).rgb * 0.25 + blur(lit, uv, 6.0).rgb * 0.30;
    col += bloom;

    // Foreground: two very blurred fronds across the bottom corners, in front of everything.
    for (int i = 0; i < 2; i++) {
        float sx = i == 0 ? 1.0 : -1.0;
        float2 qf = (uv - float2(i == 0 ? 0.02 : 0.98, 1.18)) * float2(aspect, 1.0) / 0.55;
        qf.x *= sx;
        qf = rot(qf, -0.5 * sx + 0.04 * sin(t * 0.3 + float(i)));
        float2 tc = frameToTex(float2(0.5 + qf.x * 0.75, 0.50 - qf.y));
        float4 fg = blur(b0, tc, 4.5);
        float3 tint = i == 0 ? float3(0.40, 0.20, 0.55) : float3(0.55, 0.40, 0.12);
        col = mix(col, tint * 0.5, saturate(fg.x * 0.55)) + tint * fg.x * 0.25;
    }

    float2 v = uv - 0.5; col *= 1.0 - 0.6 * dot(v, v);
    col = 1.0 - exp(-col * 1.1);
    col = pow(max(col, 0.0), float3(1.0 / 1.1));
    int dbg = int(p.view.w);   // DBG env: 1 lit rgb only, 3 background only
    if (dbg == 1) { col = fern.rgb; }
    if (dbg == 3) { col = bg * 3.0; }
    out.write(float4(col, 1.0), gid);
}

kernel void raw(texture2d<float> b0 [[texture(0)]],
                texture2d<float, access::write> out [[texture(4)]],
                constant P& p [[buffer(0)]],
                uint2 gid [[thread_position_in_grid]]) {
    if (any(float2(gid) >= p.size.xy)) { return; }
    float2 q = (float2(gid) + 0.5 - 0.5 * p.size.xy) / p.size.y;
    float2 f = p.view.xy + float2(q.x * 0.75, -q.y) * p.view.z;
    float4 c = tap(b0, frameToTex(f));
    float lvl = c.w / max(c.x, 1e-4);
    out.write(float4(c.x, c.x * saturate(lvl * 0.5), c.x * saturate(lvl - 1.0), 1.0), gid);
}
"""

// MARK: - Host

struct Params {
    var a: SIMD4<Float>; var g: SIMD4<Float>; var view: SIMD4<Float>; var blade: SIMD4<Float>
    var stalk: SIMD4<Float>; var look: SIMD4<Float>; var thr2: SIMD4<Float>; var thr: SIMD4<Float>
    var light: SIMD4<Float>; var coil: SIMD4<Float>; var size: SIMD4<Float>; var k: SIMD4<Float>; var ex2: SIMD4<Float>; var ex: SIMD4<Float>
}

let args = CommandLine.arguments
let env = ProcessInfo.processInfo.environment
func envF(_ k: String, _ d: Float) -> Float { env[k].flatMap(Float.init) ?? d }

let outW = 1920, outH = 1080

let device = MTLCreateSystemDefaultDevice()!
let library = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
func pipe(_ name: String) -> MTLComputePipelineState {
    try! device.makeComputePipelineState(function: library.makeFunction(name: name)!)
}
let ifsPSO = pipe("ifs_step"), shadePSO = pipe("shade"), presentPSO = pipe("present"), rawPSO = pipe("raw")

func tex(_ w: Int, _ h: Int, _ fmt: MTLPixelFormat, mips: Bool) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: mips)
    d.usage = [.shaderRead, .shaderWrite, .renderTarget]   // renderTarget: blit mip generation
    d.storageMode = .private
    return device.makeTexture(descriptor: d)!
}

/// One feedback-IFS fern: ping-pong pairs of the two channel textures.
final class Fern {
    let w: Int, h: Int
    var cur: (MTLTexture, MTLTexture), nxt: (MTLTexture, MTLTexture)
    init(_ w: Int, _ h: Int) {
        self.w = w; self.h = h
        cur = (tex(w, h, .rgba16Float, mips: true), tex(w, h, .rgba16Float, mips: false))
        nxt = (tex(w, h, .rgba16Float, mips: true), tex(w, h, .rgba16Float, mips: false))
    }
    func step(_ cb: MTLCommandBuffer, _ p: Params, generations: Int) {
        var p = p
        p.size.z = Float(w); p.size.w = Float(h)
        for _ in 0..<generations {
            let enc = cb.makeComputeCommandEncoder()!
            enc.setTexture(cur.0, index: 0); enc.setTexture(cur.1, index: 1)
            enc.setTexture(nxt.0, index: 2); enc.setTexture(nxt.1, index: 3)
            enc.setBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
            dispatch(enc, ifsPSO, w, h)
            enc.endEncoding()
            swap(&cur, &nxt)
        }
        let mb = cb.makeBlitCommandEncoder()!; mb.generateMipmaps(for: cur.0); mb.endEncoding()
    }
}

let blade = Fern(3200, 2400), branch = Fern(2400, 1800)
let litTex = tex(outW * 2, outH * 2, .rgba16Float, mips: true)   // 2× supersampled fern
let outTex = tex(outW, outH, .rgba8Unorm, mips: false)
let readback = device.makeBuffer(length: outW * outH * 4, options: .storageModeShared)!

func dispatch(_ enc: MTLComputeCommandEncoder, _ pso: MTLComputePipelineState, _ w: Int, _ h: Int) {
    enc.setComputePipelineState(pso)
    enc.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
}

/// Main-arm fixed point (a coil's eye) in FRAME uv. The main arm samples prev at
/// M(u) = 0.5 + inv·(q3·R(ww)·(asp·(u−0.5)) + o), so content contracts toward M's fixed point:
/// with y = asp·(u−0.5), y = (I − q3·R)⁻¹·o.
func coilEye(ww: Float, q3: Float) -> SIMD2<Float> {
    let c = q3 * cos(ww), s = q3 * sin(ww)
    let a = 1 - c, b = s, cc = -s, d = 1 - c
    let o = SIMD2<Float>(0, 0.042)
    let det = a * d - b * cc
    let y = SIMD2<Float>((d * o.x - b * o.y) / det, (-cc * o.x + a * o.y) / det)
    let t = 0.5 + y * SIMD2<Float>(1, 4.0 / 3.0)     // texture uv
    return SIMD2<Float>(t.x, 1 - t.y)
}

let view = SIMD4<Float>(envF("VX", 0.5), envF("VY", 0.62), envF("VS", 0.75), envF("DBG", 0))
let tight = envF("CURL_TIGHT", 0.40), openCurl = envF("CURL_OPEN", 0.08)

func frame(curl: Float, sway: Float, time: Float, generations: Int, rawOnly: Bool) {
    let q3 = envF("Q3", 1.07)
    let branchCurl = curl * envF("BC", 0.5)
    let open01 = min(1, max(0, (tight - curl) / (tight - openCurl)))
    // The plant in q (screen heights, origin centre, y down). Sway turns everything about the base.
    let base = SIMD2<Float>(envF("BX", -0.30), 0.62)
    func turn(_ v: SIMD2<Float>) -> SIMD2<Float> {
        let d = v - base
        return base + SIMD2<Float>(cos(sway) * d.x - sin(sway) * d.y, sin(sway) * d.x + cos(sway) * d.y)
    }
    let lean = envF("LEAN", 0.25)
    let seed0 = SIMD2<Float>(envF("SX", -0.12), envF("SY", -0.05))
    let ctrl0 = seed0 - SIMD2<Float>(sin(lean), -cos(lean)) * 0.32
    let seed = turn(seed0), ctrl = turn(ctrl0)
    // The blade coil's eye on screen: invert the blade's copyAt transform at the IFS fixed point.
    let bs = envF("BS", 0.5), ang = lean + sway
    let fe = coilEye(ww: curl, q3: q3), be = coilEye(ww: branchCurl, q3: q3)
    let r = SIMD2<Float>((fe.x - 0.5) / (0.75 * bs * -1), -(fe.y - 0.5) / bs)
    let eye = seed + SIMD2<Float>(cos(ang) * r.x - sin(ang) * r.y, sin(ang) * r.x + cos(ang) * r.y)
    var p = Params(a: [curl, 0, time, envF("LMAX", 3)],
                   g: [envF("SEEDX", 1.1), envF("SEEDY", 1.6), envF("SEED", 1.3), q3], view: view,
                   blade: [seed.x, seed.y, ang, bs],
                   stalk: [base.x, base.y, ctrl.x, ctrl.y],
                   look: [envF("R0", 0.045), envF("R1", 0.02), envF("P0", 2.6), envF("PS", 0.45)],
                   thr2: [envF("BODY", 1.1), envF("RIM", 1.6), 1 + (envF("ZOOM", 1.6) - 1) * open01 * open01, envF("BOKEH", 0.35)],
                   thr: [envF("T0", 0.08), envF("T1", 0.40), envF("SE", 4.0), envF("SL", 0.08)],
                   light: [eye.x, eye.y, envF("LR", 0.12) * (1 + open01), envF("LI", 0.5) * (1 - 0.5 * open01)],
                   coil: [fe.x, fe.y, be.x, be.y],
                   size: [Float(outW), Float(outH), 0, 0],
                   k: [envF("K1", 999), envF("K2", 999), 0, 0],
                   ex2: [envF("Q8", 3.3), envF("PM", -1), envF("PA", 1.3), envF("GARDEN", 0.22)],
                   ex: [envF("TS", 0.55), envF("EB", 0.10), envF("LOD", 8.0), envF("CW", 0.25)])
    let cb = queue.makeCommandBuffer()!
    blade.step(cb, p, generations: generations)
    var pb = p; pb.a.x = branchCurl
    branch.step(cb, pb, generations: generations)
    var enc = cb.makeComputeCommandEncoder()!
    enc.setBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
    if rawOnly {
        enc.setTexture(blade.cur.0, index: 0); enc.setTexture(outTex, index: 4)
        dispatch(enc, rawPSO, outW, outH)
        enc.endEncoding()
    } else {
        enc.setTexture(blade.cur.0, index: 0); enc.setTexture(blade.cur.1, index: 1)
        enc.setTexture(branch.cur.0, index: 2); enc.setTexture(branch.cur.1, index: 3)
        enc.setTexture(litTex, index: 4)
        dispatch(enc, shadePSO, outW * 2, outH * 2)
        enc.endEncoding()
        let lb = cb.makeBlitCommandEncoder()!; lb.generateMipmaps(for: litTex); lb.endEncoding()
        enc = cb.makeComputeCommandEncoder()!
        enc.setBytes(&p, length: MemoryLayout<Params>.stride, index: 0)
        enc.setTexture(litTex, index: 0); enc.setTexture(blade.cur.0, index: 1)
        enc.setTexture(outTex, index: 4)
        dispatch(enc, presentPSO, outW, outH)
        enc.endEncoding()
    }
    let bb = cb.makeBlitCommandEncoder()!
    bb.copy(from: outTex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
            sourceSize: MTLSize(width: outW, height: outH, depth: 1), to: readback,
            destinationOffset: 0, destinationBytesPerRow: outW * 4, destinationBytesPerImage: outW * outH * 4)
    bb.endEncoding()
    cb.commit(); cb.waitUntilCompleted()
}

func writePNG(_ path: String) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: readback.contents(), width: outW, height: outH, bitsPerComponent: 8,
                        bytesPerRow: outW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let img = ctx.makeImage()!
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
}

// MARK: - Main

switch args.count > 1 ? args[1] : "" {
case "still", "raw":
    frame(curl: Float(args[2])!, sway: 0, time: 3, generations: 300, rawOnly: args[1] == "raw")
    writePNG(args[3])
case "film":
    let seconds = Float(args[2])!, fps: Float = 30
    let ff = Process()
    ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(outW)x\(outH)",
                    "-r", "30", "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", args[3]]
    let pipeIn = Pipe(); ff.standardInput = pipeIn
    try! ff.run()
    frame(curl: tight, sway: 0, time: 0, generations: 300, rawOnly: false)
    for i in 0..<Int(seconds * fps) {
        let t = Float(i) / fps
        let phase = 0.5 - 0.5 * cos(2 * Float.pi * t / seconds)          // 0 → 1 → 0 over the film
        let curl = tight + (openCurl - tight) * phase
        let sway = 0.06 * sin(2 * Float.pi * t / 5.3) + 0.03 * sin(2 * Float.pi * t / 2.9)
        frame(curl: curl, sway: sway, time: t, generations: 2, rawOnly: false)
        pipeIn.fileHandleForWriting.write(Data(bytes: readback.contents(), count: outW * outH * 4))
    }
    try! pipeIn.fileHandleForWriting.close()
    ff.waitUntilExit()
default:
    print("usage: fiddlehead still|raw <curl> <out.png>  |  fiddlehead film <seconds> <out.mp4>")
}
