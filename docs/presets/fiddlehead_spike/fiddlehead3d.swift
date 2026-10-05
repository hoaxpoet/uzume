// fiddlehead3d.swift — FH.4 look-spike (throwaway; not engine code, imports nothing from Uzume).
//
// A LIVE 3D fern toward Matt's 2026-10-05 reference
// (docs/VISUAL_REFERENCES/fiddlehead/01_reference_matt_2026-10-05.webp). The 2D versions (FH.0–FH.3,
// fiddlehead.swift / fiddlehead_ifs.swift) all read flat: the reference's richness is 3D light —
// every leaflet faces a slightly different way, so each catches the coil glow, the rim light and the
// specular differently. Here the botanical rule builds real 3D geometry every frame (rasterised, the
// way games render foliage): tube stems, curved cupped leaf blades, bead sprites; lit with an orange
// point light inside the coil (transmission), a cool back/rim light and a key; thin-film iridescence
// by view angle; HDR + bloom; 4× MSAA. Must hold a 60 fps budget (measured below, not assumed).
//
// Botany (research 2026-10-05): each pinna is a crozier (one rule at every level); the rachis coils as
// a log spiral; unfurling travels base → tip and a pinna starts unrolling only after the front passes
// its junction; branches at the coil are immature (smaller); colour by age.
//
// Build:  swiftc -O -swift-version 5 fiddlehead3d.swift -o /tmp/fh3d
// Usage:  fh3d still <unfurl 0…1> <out.png>      |   fh3d film <seconds> <out.mp4>

import Foundation
import simd
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Shaders

let msl = """
#include <metal_stdlib>
using namespace metal;

struct U {
    float4x4 viewProj;
    float4 eye;        // camera position (xyz), time (w)
    float4 coil;       // coil light position (xyz), intensity (w)
    float4 coilCol;    // colour (rgb), radius (w)
    float4 keyDir;     // key light direction TO the light (xyz), intensity (w)
    float4 backDir;    // back/rim light direction TO the light (xyz), intensity (w)
    float4 look;       // body, iridescence, bead gain, debug
    float4 mat;        // transmission gain, gold rim gain, warm/cool rim split, transmission tint by albedo
    float4 bgk;        // coil haze on the background, 0, 0, 0
    float4 tex;        // scallops per lobe, fibre gain, hair gain, rim-line gain
    float4 warmc;      // gold rim colour (g, b; r = 1), LBEND
    float4 glass;      // body alpha, film on cool bodies, rim width px, glint gain
    float4 stem;       // helix stripes around, helix pitch, fibre lines around, band strength
};

// Leaf instance: origin+length, dir+width, normal+cup, (young, hash, bend, level)
struct Leaf { float4 o; float4 d; float4 n; float4 q; };
// Tube instance: p0+r0, p1+r1, normal+young, (hash, level, 0, 0)
struct Tube { float4 a; float4 b; float4 n; float4 q; };
// Bead: pos+radius, colour+intensity
struct Bead { float4 p; float4 c; };

struct VOut {
    float4 pos [[position]];
    float3 wpos; float3 nrm; float3 tng;
    float2 uv;                 // leaf: u along 0…1, v across −1…1 ; tube: u along, v around −1…1
    float4 q [[flat]];
    float kind [[flat]];       // 0 tube, 1 leaf
};

static float3 irid(float t) {
    const float3 k[5] = { float3(0.55, 0.20, 1.00), float3(0.15, 0.40, 1.00), float3(0.10, 0.95, 0.90),
                          float3(1.00, 0.65, 0.10), float3(1.00, 0.25, 0.70) };
    float x = fract(t) * 5.0;
    int i = int(x);
    return mix(k[i % 5], k[(i + 1) % 5], smoothstep(0.0, 1.0, fract(x)));
}

constant int NU = 10, NV = 4;                     // leaf grid (along × across halves)

static float leafProfile(float u) {               // reference pinnules: rounded oblong glass lobes, blunt tip
    return pow(max(sin(3.14159 * pow(clamp(u, 0.0, 1.0), 0.7)), 0.0), 0.45);
}

vertex VOut leaf_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        const device Leaf* L [[buffer(0)]], constant U& u [[buffer(1)]]) {
    Leaf l = L[iid];
    int quad = int(vid) / 6, corner = int(vid) % 6;
    int qi = quad % NU, qj = quad / NU;           // qj 0…2NV-1
    const int2 cs[6] = { int2(0,0), int2(1,0), int2(1,1), int2(0,0), int2(1,1), int2(0,1) };
    float uu = float(qi + cs[corner].x) / float(NU);
    float vv = float(qj + cs[corner].y) / float(NV) - 1.0;      // −1 … 1
    float3 d = l.d.xyz, n = l.n.xyz, w = normalize(cross(d, n));
    float len = l.o.w, wid = l.d.w * leafProfile(uu), cup = l.n.w, bend = l.q.z;
    // Shape: cupped across (a shallow U), bent along (tip curls toward the normal).
    float hook = l.q.w;                            // signed in-plane hook toward the parent's tip
    float3 p = l.o.xyz + d * (uu * len) + w * (vv * wid + hook * uu * uu * len) + n * (cup * vv * vv * wid + bend * uu * uu * len);
    float3 dpdu = d * len + n * (2.0 * bend * uu * len) + w * (2.0 * hook * uu * len);
    float3 dpdv = w * wid + n * (2.0 * cup * vv * wid);
    VOut o;
    o.pos = u.viewProj * float4(p, 1.0);
    o.wpos = p; o.nrm = normalize(cross(dpdu, dpdv)); o.tng = normalize(dpdu);
    o.uv = float2(uu, vv); o.q = l.q; o.kind = 1.0;
    return o;
}

constant int NS = 8;                               // tube sides
vertex VOut tube_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        const device Tube* T [[buffer(0)]], constant U& u [[buffer(1)]]) {
    Tube t = T[iid];
    int quad = int(vid) / 6, corner = int(vid) % 6;
    const int2 cs[6] = { int2(0,0), int2(1,0), int2(1,1), int2(0,0), int2(1,1), int2(0,1) };
    float along = float(cs[corner].y);
    float ang = 6.2831853 * float(quad + cs[corner].x) / float(NS);
    float3 a = t.a.xyz, b = t.b.xyz, ax = normalize(b - a);
    float3 s1 = normalize(cross(ax, t.n.xyz)), s2 = cross(s1, ax);
    float r = mix(t.a.w, t.b.w, along) * (1.0 + 0.15 * along);   // slight overlap into the next link
    float3 radial = s1 * cos(ang) + s2 * sin(ang);
    float3 p = mix(a, b + ax * t.b.w * 0.5, along) + radial * r;
    VOut o;
    o.pos = u.viewProj * float4(p, 1.0);
    o.wpos = p; o.nrm = radial; o.tng = ax;
    o.uv = float2(along, ang / 6.2831853); o.q = float4(t.q.x, t.q.y, t.q.z, t.n.w); o.kind = 0.0;
    return o;
}

// Glass shading (FH.5 look pass). The reference is coloured GLASS lit from inside the coil: bodies are
// dark and see-through, the light lives in the rims (~2–3 px, warm white-gold), colour stays saturated.
// Order-independent transparency: weighted blended OIT (McGuire & Bavoil, JCGT 2013) — attachments
// 0 = Σ premultiplied colour·w and Σ α·w, 1 = Π(1−α) (revealage), 2 = additive emission (beads, hairs).
struct FOut { float4 accum [[color(0)]]; float reveal [[color(1)]]; float4 add [[color(2)]]; };

static float2 hash22(float2 p) { p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3))); return fract(sin(p) * 43758.5453); }
static float cellEdge(float2 p) {                 // distance to the nearest Voronoi cell wall
    float2 i = floor(p), f = fract(p); float d1 = 8.0, d2 = 8.0;
    for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
        float2 g = float2(x, y), o = hash22(i + g); float d = length(g + o - f);
        if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
    }
    return d2 - d1;
}

static FOut oit(float3 premul, float alpha, float zview, float camZ, float3 emit) {
    float w = alpha * clamp(pow(camZ / max(zview, 1e-3), 12.0), 1e-3, 1e3);   // nearer layers dominate
    FOut o; o.accum = float4(premul * w, alpha * w); o.reveal = alpha; o.add = float4(emit, 0.0); return o;
}

fragment FOut fern_fragment(VOut in [[stage_in]], constant U& u [[buffer(1)]]) {
    float t = u.eye.w;
    float3 n = normalize(in.nrm);
    float3 V = normalize(u.eye.xyz - in.wpos);
    float zview = in.pos.w;
    // Light from the core: amber, falls off with distance; 'warm' = how much this point faces the core light.
    float3 Lc = u.coil.xyz - in.wpos;
    float dc = length(Lc); Lc /= max(dc, 1e-4);
    float att = u.coil.w / (1.0 + (dc / u.coilCol.w) * (dc / u.coilCol.w) * 4.0);
    float warm = saturate(att / (att + u.mat.z));
    float3 amber = u.coilCol.rgb * att;
    if (dot(n, V) < 0.0) { n = -n; }               // two-sided
    float cosv = saturate(dot(n, V));
    float fres = pow(1.0 - cosv, 3.0);
    float3 rimWarm = float3(1.0, u.warmc.x, u.warmc.y), rimCool = float3(0.80, 0.90, 1.0);
    float3 spec = float3(0.0);
    {   // glints from key + back lights
        float3 L1 = normalize(u.keyDir.xyz), L2 = normalize(u.backDir.xyz);
        float s1 = pow(saturate(dot(n, normalize(L1 + V))), 120.0), s2 = pow(saturate(dot(n, normalize(L2 + V))), 60.0);
        spec = (s1 * u.keyDir.w + s2 * u.backDir.w * float3(0.7, 0.75, 1.0)) * u.glass.w;
    }
    if (in.kind > 0.5) {
        // ---- Lobe / leaflet: rounded, scalloped, glass edge, veins, cell web.
        float prof = leafProfile(in.uv.x);
        if (prof < 0.02) { discard_fragment(); }
        float serr = 0.80 + 0.20 * sqrt(abs(sin(3.14159 * in.uv.x * u.tex.x)));
        float edge = abs(in.uv.y) / max(serr, 1e-3);
        float fw = max(fwidth(edge), 1e-4);
        float cov = saturate((1.0 - edge) / fw + 0.5);                 // analytic edge coverage (no stair-steps)
        if (cov <= 0.0) { discard_fragment(); }
        float dpx = (1.0 - edge) / fw;                                  // distance to the margin in pixels
        float rim = exp(-dpx / u.glass.z);                              // the glass edge, ~2–3 px
        float midrib = 1.0 - smoothstep(0.0, 0.08, abs(in.uv.y));
        float sec = smoothstep(0.80, 1.0, 1.0 - abs(fract(in.uv.x * 7.0 - abs(in.uv.y) * 1.4) - 0.5) * 2.0) * (1.0 - edge);
        float2 cuv = float2(in.uv.x * 7.0, in.uv.y * 2.5) + in.q.y * 17.0;
        float cells = 1.0 - smoothstep(0.0, 0.08, cellEdge(cuv));
        cells *= saturate(1.0 - 3.0 * fwidth(cuv.x));                  // fade where cells would alias
        float curled = saturate(in.q.z / max(u.warmc.z, 1e-3) - 0.4);   // curled lobes: green glass; open: orange vellum
        float3 green = mix(float3(0.10, 0.45, 0.06), float3(0.35, 0.62, 0.08), in.q.x);
        green = mix(green, float3(0.05, 0.42, 0.36), 0.35 * (0.5 + 0.5 * sin(in.q.y * 37.0)));     // teal variety
        float3 film = irid(cosv * 1.1 + in.uv.x * 0.6 + in.q.y * 0.35 + t * 0.02);                // hue drifts ACROSS the surface
        float3 tintCool = mix(green, film * 0.6, u.glass.y * (1.0 - warm));
        float3 tint = mix(float3(1.0, 0.55, 0.20), tintCool * 2.0, saturate(u.mat.w + curled * 0.8));
        tint = mix(tint, green * 2.0, (1.0 - warm) * 0.5);
        // Body: light through the blade (amber near the core) + a little cool fill; veins: midrib bright, secondaries dark.
        float3 body = (amber * u.mat.x * (0.6 + 0.4 * in.q.x) + float3(0.05, 0.07, 0.10) * u.look.x) * tint;
        body *= (1.0 + 0.9 * midrib + 0.35 * cells) * (1.0 - 0.45 * sec);
        float3 rimC = mix(rimCool * u.look.y * 0.5, rimWarm * u.mat.y, warm) * (0.6 + 0.6 * saturate(att));
        float3 C = body + rimC * (u.tex.w * rim + 0.6 * fres) + spec;
        float alpha = cov * mix(u.glass.x, 1.0, saturate(rim + 0.5 * fres));
        return oit(C * alpha, alpha, zview, u.eye.z, float3(0.0));
    }
    // ---- Stem / tube.
    if (in.q.z > 0.5) {                                 // hair: a thin lit filament (emissive only)
        FOut o; o.accum = float4(0.0); o.reveal = 0.0;
        o.add = float4(mix(rimCool * 0.6, float3(1.0, 0.55, 0.18), warm) * u.tex.z, 0.0); return o;
    }
    float ang = in.uv.y * 6.2831853;
    float edgeV = 1.0 - cosv;
    float rim = pow(edgeV, 2.5);
    // Helical cyan/magenta striping (reference outer band) where the stem faces away from the core;
    // fine fibre lines along the stem everywhere, faded where they would alias.
    float helix = ang * u.stem.x + dot(in.wpos, float3(9.0, 7.0, 0.0)) * u.stem.y + in.q.x * 31.0;
    float stripe = smoothstep(-0.25, 0.25, sin(helix));
    float fa = ang * u.stem.z;
    float fib = pow(0.5 + 0.5 * cos(fa), 10.0) * saturate(1.0 - 1.5 * fwidth(fa));
    float3 band = mix(float3(0.10, 0.70, 1.00), float3(0.80, 0.18, 0.85), stripe);
    float3 green = mix(float3(0.10, 0.40, 0.06), float3(0.35, 0.60, 0.10), in.q.w);
    float3 tint = mix(green * 2.0, band * 1.6, u.stem.w * (1.0 - warm));
    float3 body = (amber * u.mat.x * 0.5 + float3(0.05, 0.07, 0.10) * u.look.x) * tint * (1.0 + 1.2 * fib);
    float lit = saturate(dot(n, Lc) * 0.5 + 0.5);                       // the side facing the core carries the gold rim
    float3 rimC = mix(rimCool * u.look.y * 0.5 * mix(float3(1.0), band * 1.5, u.stem.w), rimWarm * u.mat.y * 1.3, warm * lit);
    float3 C = body + rimC * rim * 1.6 + spec;
    float alpha = mix(u.glass.x * 1.4, 1.0, rim);
    return oit(C * alpha, alpha, zview, u.eye.z, float3(0.0));
}

kernel void resolve_oit(texture2d<float> accum [[texture(0)]], texture2d<float> reveal [[texture(1)]],
                        texture2d<float> add [[texture(2)]], texture2d<float, access::write> out [[texture(3)]],
                        uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float4 a = accum.read(gid); float r = reveal.read(gid).r; float3 e = add.read(gid).rgb;
    float3 avg = a.rgb / max(a.a, 1e-5);
    out.write(float4(avg * (1.0 - r) + e, 1.0 - r), gid);
}

// Beads: tiny bright drops (dew / guttation in the reference), drawn as additive sprites.
struct BOut { float4 pos [[position]]; float2 uv; float4 c [[flat]]; };
vertex BOut bead_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        const device Bead* B [[buffer(0)]], constant U& u [[buffer(1)]]) {
    Bead b = B[iid];
    const float2 cs[6] = { float2(-1,-1), float2(1,-1), float2(1,1), float2(-1,-1), float2(1,1), float2(-1,1) };
    float4 c = u.viewProj * float4(b.p.xyz, 1.0);
    float2 k = cs[vid];
    float r = b.p.w;
    BOut o;
    o.pos = c + float4(k * r * u.viewProj[1][1], 0.0, 0.0) * float4(1.0, 1.0, 0, 0);
    o.pos.x = c.x + k.x * r * u.viewProj[0][0];
    o.pos.y = c.y + k.y * r * u.viewProj[1][1];
    o.uv = k; o.c = b.c;
    return o;
}
fragment FOut bead_fragment(BOut in [[stage_in]], constant U& u [[buffer(1)]]) {
    float d = length(in.uv);
    float core = exp(-d * d * 9.0) + 0.25 * exp(-d * d * 2.0);      // pearl + soft halo
    float tw = 0.65 + 0.35 * sin(u.eye.w * (1.5 + 2.0 * fract(in.c.a * 7.1)) + in.c.a * 40.0);
    FOut o; o.accum = float4(0.0); o.reveal = 0.0; o.add = float4(in.c.rgb * core * u.look.z * tw, 0.0); return o;
}

// MARK: present: background, fern, bloom, tone

constexpr sampler lin(filter::linear, mip_filter::linear, address::clamp_to_zero);
static float hash21(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
static float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
static float4 blur(texture2d<float> t, float2 uv, float lod) {
    float2 o = exp2(lod) / float2(t.get_width(), t.get_height());
    float4 acc = float4(0.0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float w = (2.0 - abs(float(i))) * (2.0 - abs(float(j)));
        acc += t.sample(lin, uv + float2(i, j) * o, level(lod)) * w;
    }
    return acc / 16.0;
}
// One parallax layer of bokeh (technique after knarkowicz's "Bokeh Paralax", Shadertoy 4s2yW1, written fresh).
static float3 bokehLayer(float2 p, float cellSize, float soft, float seed, float density) {
    float row = floor(p.y / cellSize + 0.5);
    if (fmod(abs(row), 2.0) > 0.5) { p.x += 0.5 * cellSize; }
    float2 cell = floor(p / cellSize + 0.5);
    float2 local = p - cell * cellSize;
    float h0 = hash21(cell + seed), h1 = hash21(cell + seed + 7.1), h2 = hash21(cell + seed + 13.7);
    if (h0 > density) { return float3(0.0); }
    local += (float2(h1, h2) - 0.5) * cellSize * 0.4;
    float r = cellSize * mix(0.16, 0.34, h1);
    float sdf = length(local) - r;
    float disc = 1.0 - smoothstep(-soft * r, soft * r * 0.3, sdf);
    float rimLift = 1.0 + 0.35 * smoothstep(-0.35 * r, -0.05 * r, sdf) * disc;
    float glow = 0.18 * exp(-max(sdf, 0.0) / (0.5 * r)) * (1.0 - disc);
    float3 hue = h2 < 0.30 ? float3(0.10, 0.55, 0.50) : (h2 < 0.55 ? float3(0.45, 0.52, 0.12)
               : (h2 < 0.80 ? float3(0.45, 0.22, 0.70) : float3(0.95, 0.50, 0.12)));
    return hue * (disc * rimLift + glow) * mix(0.35, 1.0, fract(h0 * 7.77));
}
static float3 aces(float3 x) { return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14)); }

kernel void present(texture2d<float> hdr [[texture(0)]],
                    texture2d<float, access::write> out [[texture(1)]],
                    constant U& u [[buffer(0)]],
                    constant float4& coilScreen [[buffer(1)]],
                    uint2 gid [[thread_position_in_grid]]) {
    float2 size = float2(out.get_width(), out.get_height());
    if (any(float2(gid) >= size)) { return; }
    float2 uv = (float2(gid) + 0.5) / size;
    float aspect = size.x / size.y;
    float t = u.eye.w;
    float3 bg = float3(0.008, 0.011, 0.016) * (0.75 + 0.25 * sin(uv.x * 31.0 + sin(uv.x * 9.0) * 2.0));
    bg += float3(0.010, 0.030, 0.026) * smoothstep(0.35, 1.0, uv.y);
    float2 pb = (uv - 0.5) * float2(aspect, 1.0);
    float3 bk = float3(0.0);
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 pl = rot(pb, 0.3 + 0.7 * fi) + float2(t * 0.004 * (1.0 + 1.5 * fi), 0.37 * fi);
        bk += bokehLayer(pl, 0.11 + 0.09 * fi, 0.25 + 0.25 * fi, 11.0 * fi, 0.30 - 0.06 * fi) * mix(1.0, 0.6, fi / 2.0);
    }
    float side = smoothstep(0.15, 0.45, abs(uv.x - 0.5));
    bg += bk * 0.35 * smoothstep(0.25, 0.85, uv.y) * (0.45 + 0.55 * side);
    // The out-of-focus garden: this frame's fern, mirrored, enlarged, blurred hard, low in the corners.
    const float4 gx[3] = { float4(0.08, 1.02, 1.5, -1.0), float4(0.92, 1.05, 1.7, -1.0), float4(0.55, 1.22, 1.3, 1.0) };
    for (int i = 0; i < 3; i++) {
        float2 g = (uv - gx[i].xy) / gx[i].z;
        g.x *= gx[i].w;
        float4 gs = blur(hdr, float2(0.45, 0.55) + g, 4.0);
        bg += gs.rgb / (1.0 + gs.rgb) * 0.25 * float3(0.75, 0.7, 1.0) * smoothstep(0.45, 0.95, uv.y);
    }
    // The coil's light spills onto the air behind the fern.
    float2 dl = (uv - coilScreen.xy) * float2(aspect, 1.0) / coilScreen.z;
    bg += float3(0.9, 0.38, 0.06) * u.bgk.x * coilScreen.w * exp(-dot(dl, dl));
    float4 f = hdr.sample(lin, uv, level(0.0));
    float3 col = bg * (1.0 - f.a) + f.rgb;
    col += blur(hdr, uv, 1.0).rgb * u.bgk.y + blur(hdr, uv, 2.0).rgb * u.bgk.z
         + blur(hdr, uv, 3.0).rgb * 0.12 + blur(hdr, uv, 5.0).rgb * 0.18 + blur(hdr, uv, 7.0).rgb * 0.15;
    float2 v = uv - 0.5; col *= 1.0 - 0.55 * dot(v, v);
    // Hue-preserving tone map (x/(1+x) on the brightest channel) so hot rims stay saturated;
    // only the very hottest cores bleach toward white.
    col *= u.bgk.w;
    float m = max(col.r, max(col.g, col.b));
    float3 tm = col * ((m / (1.0 + m)) / max(m, 1e-4));
    col = mix(tm, float3(m / (1.0 + m)), smoothstep(3.0, 12.0, m) * 0.6);
    col = pow(col, float3(1.0 / 1.1));
    out.write(float4(col, 1.0), gid);
}
"""

// MARK: - Host setup

let args = CommandLine.arguments
let env = ProcessInfo.processInfo.environment
func envF(_ k: String, _ d: Float) -> Float { env[k].flatMap(Float.init) ?? d }

struct Uniforms {
    var viewProj: simd_float4x4; var eye: SIMD4<Float>; var coil: SIMD4<Float>; var coilCol: SIMD4<Float>
    var keyDir: SIMD4<Float>; var backDir: SIMD4<Float>; var look: SIMD4<Float>
    var mat: SIMD4<Float>; var bgk: SIMD4<Float>; var tex: SIMD4<Float>; var warmc: SIMD4<Float>; var glass: SIMD4<Float>; var stem: SIMD4<Float>
}
struct Leaf { var o: SIMD4<Float>; var d: SIMD4<Float>; var n: SIMD4<Float>; var q: SIMD4<Float> }
struct Tube { var a: SIMD4<Float>; var b: SIMD4<Float>; var n: SIMD4<Float>; var q: SIMD4<Float> }
struct Bead { var p: SIMD4<Float>; var c: SIMD4<Float> }

let outW = Int(envF("W", 1920)), outH = Int(envF("H", 1080))
let device = MTLCreateSystemDefaultDevice()!
let library = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
let msaa = 4

func renderPSO(_ v: String, _ f: String, additive: Bool) -> MTLRenderPipelineState {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = library.makeFunction(name: v)
    d.fragmentFunction = library.makeFunction(name: f)
    d.rasterSampleCount = msaa
    d.depthAttachmentPixelFormat = .depth32Float
    // Weighted blended OIT: 0 accum (Σ, Σ), 1 revealage (Π 1−α), 2 additive emission.
    for (i, fmt) in [MTLPixelFormat.rgba16Float, .r16Float, .rgba16Float].enumerated() {
        let c = d.colorAttachments[i]!
        c.pixelFormat = fmt; c.isBlendingEnabled = true
        c.sourceRGBBlendFactor = i == 1 ? .zero : .one
        c.destinationRGBBlendFactor = i == 1 ? .oneMinusSourceColor : .one
        c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .one
    }
    _ = additive
    return try! device.makeRenderPipelineState(descriptor: d)
}
let leafPSO = renderPSO("leaf_vertex", "fern_fragment", additive: false)
let tubePSO = renderPSO("tube_vertex", "fern_fragment", additive: false)
let beadPSO = renderPSO("bead_vertex", "bead_fragment", additive: true)
let presentPSO = try! device.makeComputePipelineState(function: library.makeFunction(name: "present")!)
let depthOn: MTLDepthStencilState = {
    let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = .less; d.isDepthWriteEnabled = true
    return device.makeDepthStencilState(descriptor: d)!
}()
let depthRead: MTLDepthStencilState = {
    let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = .less; d.isDepthWriteEnabled = false
    return device.makeDepthStencilState(descriptor: d)!
}()

func tex(_ w: Int, _ h: Int, _ fmt: MTLPixelFormat, mips: Bool = false, samples: Int = 1, priv: Bool = true) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: mips)
    if samples > 1 { d.textureType = .type2DMultisample; d.sampleCount = samples; d.usage = [.renderTarget] }
    else { d.usage = [.shaderRead, .shaderWrite, .renderTarget] }
    d.storageMode = samples > 1 ? .memoryless : .private
    if samples > 1 && !device.supportsFamily(.apple1) { d.storageMode = .private }
    return device.makeTexture(descriptor: d)!
}
let colorMS = tex(outW, outH, .rgba16Float, samples: msaa)
let revealMS = tex(outW, outH, .r16Float, samples: msaa), addMS = tex(outW, outH, .rgba16Float, samples: msaa)
let accumTex = tex(outW, outH, .rgba16Float), revealTex = tex(outW, outH, .r16Float), addTex = tex(outW, outH, .rgba16Float)
let resolvePSO = try! device.makeComputePipelineState(function: library.makeFunction(name: "resolve_oit")!)
let depthMS = tex(outW, outH, .depth32Float, samples: msaa)
let hdrTex = tex(outW, outH, .rgba16Float, mips: true)
let outTex = tex(outW, outH, .rgba8Unorm)
let readback = device.makeBuffer(length: outW * outH * 4, options: .storageModeShared)!
let maxLeaves = 400_000, maxTubes = 200_000, maxBeads = 100_000
let leafBuf = device.makeBuffer(length: maxLeaves * MemoryLayout<Leaf>.stride, options: .storageModeShared)!
let tubeBuf = device.makeBuffer(length: maxTubes * MemoryLayout<Tube>.stride, options: .storageModeShared)!
let beadBuf = device.makeBuffer(length: maxBeads * MemoryLayout<Bead>.stride, options: .storageModeShared)!
let leaves = leafBuf.contents().bindMemory(to: Leaf.self, capacity: maxLeaves)
let tubes = tubeBuf.contents().bindMemory(to: Tube.self, capacity: maxTubes)
let beads = beadBuf.contents().bindMemory(to: Bead.self, capacity: maxBeads)
var nLeaves = 0, nTubes = 0, nBeads = 0

// MARK: - The fern rule (3D)

// FH.5 defaults are FITTED to the reference (fit0.py / fitpinna in the spike notes), not hand-tuned:
// the level-0 rachis (SEG LEAN F0 TURN SIG BT BX BY) fits the traced centreline to ~15 px RMS at 941 px
// frame height; SIGS 0.093 is the measured lower-pinna ÷ remaining-rachis ratio (FH.4's 0.30 made each
// pinna ~900 px, i.e. the big triangle frond, and pushed recursion 4–5 levels deep into a needle carpet).
struct Rule {
    var sig = envF("SIG", 0.9568), sigS = envF("SIGS", 0.168)
    var alpha = envF("ALPHA", 1.37)
    var maxTurn = envF("TURN", 0.276), ramp = envF("RAMP", 0.001), baseTurn = envF("BT", -0.0187)
    var delay = envF("DELAY", 0.15), immature = envF("IMM", 0.5)
    var pRamp = envF("PRAMP", 0.077)               // pinnae shrink toward immature over this much length below the front
    var tilt = envF("TILT", 0.45)                 // pinna planes tip out of the frond plane (rad)
    var stemR: [Float] = [envF("SR0", 0.18), envF("SR1", 0.30)]   // stem radius × link length
    var leafLen = envF("LEAFLEN", 1.0), leafW = envF("LEAFW", 0.327), leafCup = envF("CUP", 0.35)
    var leafBend = envF("LBEND", 0.25), leafJitter = envF("LJIT", 0.35)
    var minPx = envF("MINPX", 0.5)
    var beadSize = envF("BEADSZ", 0.10)
    var beadP = envF("BEADP", 0.45)               // fraction of lobes carrying a tip bead
    var leafPx = envF("LEAFPX", 60)            // a chain shorter than this many pixels becomes one leaf
    var pinOpen = envF("PINOPEN", 0.10)        // even in the coil a pinna's base is open; only its tip curls
    var pinFront = envF("PINF", 0.46)          // a mature pinna's own unfurl front (its tip crozier starts here)
    var alt = envF("ALT", 0.79)
    var rampP = envF("RAMPP", 0.35)             // pinna curl ramps in over this much of its length (curls more toward the tip)
    var outS = envF("OUTS", 0.6), inS = envF("INS", 1.4)   // coil: outer-side / inner-side pinna size
    var hook = envF("HOOK", 0.25)
    var crz = envF("CRZ", 1.3), crzC = envF("CRZC", 0.5), beadC = envF("BEADC", 0.45)   // crozier tube thickening, curl threshold, bead size ÷ r
    var hairP = envF("HAIRP", 0.284), hairL = envF("HAIRL", 0.6)   // hairs: fraction of lobes, length ÷ lobe               // lobe tips hook toward the pinna tip                 // left/right pinnae alternate by this fraction of a link
}
var dump: [String] = []
let dumping = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "dump"                        // "dump" mode: level-0/1 skeletons in image px
let rule = Rule()
var pxWorld: Float = 0.001
var eyePos = SIMD3<Float>(0, 0, 0)

func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float { let t = min(1, max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t) }
func hashf(_ x: Float) -> Float { let s = sin(x * 91.3458) * 47453.5453; return s - s.rounded(.down) }
func rotate(_ v: SIMD3<Float>, about a: SIMD3<Float>, _ ang: Float) -> SIMD3<Float> {
    v * cos(ang) + cross(a, v) * sin(ang) + a * dot(a, v) * (1 - cos(ang))
}

/// One chain in its own plane (normal N): walk links, emitting a tube per link, branching on both
/// sides; level 2 (pinnules) is emitted as single curved leaf blades.
func chain(_ p0: SIMD3<Float>, dir d0: SIMD3<Float>, normal N0: SIMD3<Float>, link S0: Float, front: Float,
           level: Int, hash: Float, young0: Float, side: Float = 0) {
    let total = 1 / (1 - rule.sig)
    // Fractal depth is set by the screen, not a fixed level: a branch keeps branching (the same rule)
    // while it is big enough to show its own sub-branches; below that it is drawn as one leaf blade.
    if level >= 1 && (total * S0 < rule.leafPx * pxWorld || level >= 5) {
        // A pinnule: one cupped, serrated blade, bent toward the coil while its pinna is curled.
        let len = total * S0 * rule.leafLen
        guard len * rule.leafW > rule.minPx * pxWorld, nLeaves < maxLeaves else { return }
        let curled = 1 - (front - rule.pinOpen) / (rule.pinFront - rule.pinOpen)
        let jit = (hashf(hash * 13.7) - 0.5) * 2 * rule.leafJitter
        let n = rotate(N0, about: d0, jit)
        let d = rotate(d0, about: N0, -0.35 * curled)
        leaves[nLeaves] = Leaf(o: SIMD4(p0, len), d: SIMD4(d, len * rule.leafW), n: SIMD4(n, rule.leafCup),
                               q: [young0, hash, rule.leafBend * (0.4 + curled), -side * rule.hook])
        nLeaves += 1
        if hashf(hash * 5.9) < rule.hairP && nTubes + 3 < maxTubes {
            // A hair: a fine filament curling off the lobe margin, catching the orange light.
            let hu = 0.3 + 0.6 * hashf(hash * 8.1), hs: Float = hashf(hash * 2.7) > 0.5 ? 1 : -1
            let w = normalize(cross(d, n))
            let prof = pow(max(sin(Float.pi * pow(hu, 0.7)), 0), 0.45)          // = leafProfile in the shader
            var hp = p0 + d * (hu * len) + w * (hs * len * rule.leafW * prof * 0.85)
            var hd = normalize(w * hs + d * 0.6), hl = len * rule.hairL / 3
            for _ in 0..<3 {
                let hq = hp + hd * hl
                tubes[nTubes] = Tube(a: SIMD4(hp, 0.5 * pxWorld), b: SIMD4(hq, 0.4 * pxWorld), n: SIMD4(n, young0), q: [hash, Float(level), 1, 0])
                nTubes += 1; hp = hq; hd = rotate(hd, about: n, 0.7 * hs); hl *= 0.8
            }
        }
        if hashf(hash * 3.3) < rule.beadP && nBeads < maxBeads {           // a bead on some leaf tips
            let tip = p0 + d * len * 0.97 + n * (rule.leafBend * (0.4 + curled) * len * 0.9)
            beads[nBeads] = Bead(p: SIMD4(tip, max(len * rule.beadSize, 1.6 * pxWorld)), c: [1.0, 0.85, 0.6, hash])
            nBeads += 1
        }
        return
    }
    var p = p0, d = d0, N = N0, S = S0, prev = p0
    var k = 0
    while total * S > rule.minPx * pxWorld && k < 300 && nTubes < maxTubes {
        let f = 1 - pow(rule.sig, Float(k))
        let c = smooth(front, front + (level == 0 ? rule.ramp : rule.rampP), f)
        let young = min(1, young0 * 0.5 + c)
        // Croziers (a pinna's curled tip) are one thick tapering glass tube (reference: 8–15 px → ~3 px).
        let r = S * rule.stemR[min(level, 1)] * (level >= 2 ? 0.8 : 1) * (level >= 1 ? 1 + rule.crz * c : 1)
        let p1 = p + d * S
        if level <= 1 && dumping { dump.append("\(level) \(hash) \(p.x) \(p.y) \(p.z) \(S)") }
        if r > 1.5 * pxWorld {
            // Thick stems: a smooth quadratic through the link midpoints (no kinks at the joints).
            let a0 = k == 0 ? p : (prev + p) * 0.5, a2 = (p + p1) * 0.5, ctrl = k == 0 ? (a0 + a2) * 0.5 : p
            var q0 = a0
            for j in 1...4 where nTubes < maxTubes {
                let t = Float(j) / 4, q = (1 - t) * (1 - t) * a0 + 2 * (1 - t) * t * ctrl + t * t * a2
                let rr = r * (1 + (rule.sig - 1) * t)
                tubes[nTubes] = Tube(a: SIMD4(q0, rr / (1 + (rule.sig - 1) / 4)), b: SIMD4(q, rr), n: SIMD4(N, young), q: [hash, Float(level), 0, 0])
                nTubes += 1; q0 = q
            }
        } else if r > 0.3 * pxWorld {
            tubes[nTubes] = Tube(a: SIMD4(p, r), b: SIMD4(p1, r * rule.sig), n: SIMD4(N, young), q: [hash, Float(level), 0, 0])
            nTubes += 1
        }
        // Branches: same rule one level down; immature (smaller) where the chain is still coiled;
        // each starts unrolling only once this chain's front has passed the junction.
        let mature = 1 - smooth(front - rule.pRamp, front + rule.ramp, f)
        let bS0 = S * rule.sigS * (rule.immature + (1 - rule.immature) * mature)
        if level >= 1 && c > rule.crzC {
            // In the crozier the pinnules are replaced by a string of beads on the outer edge (every link).
            if nBeads < maxBeads {
                let outer = normalize(cross(N, d))
                beads[nBeads] = Bead(p: SIMD4(p + outer * (r * 1.15), max(r * rule.beadC, 1.2 * pxWorld)), c: [1.0, 0.72, 0.42, hashf(hash + Float(k))])
                nBeads += 1
            }
        } else if total * bS0 > rule.minPx * pxWorld {
            let passed = min(1, max(0, (front - f) / max(rule.delay, 1e-3)))
            for side: Float in [-1, 1] {
                let at = p + d * (S * (0.5 + 0.5 * side * rule.alt))
                let bS = bS0 * (1 + ((side < 0 ? rule.outS : rule.inS) - 1) * c * (level == 0 ? 1 : 0))
                let ang = rule.alpha * (1 - 0.25 * c)
                let bd = rotate(d, about: N, -side * ang)                 // in-plane: right is −about N
                let bN = rotate(N, about: bd, side * rule.tilt * (level == 0 ? 1 : 0.4))
                let bh = (hash * 7.31 + Float(k) * 0.618 + (side > 0 ? 0.29 : 0.71)).truncatingRemainder(dividingBy: 1)
                chain(at, dir: bd, normal: bN, link: bS, front: rule.pinOpen + (rule.pinFront - rule.pinOpen) * passed, level: level + 1, hash: bh, young0: young, side: side)
            }
        }
        let turn = rule.baseTurn * (1 - c) + rule.maxTurn * c
        d = rotate(d, about: N, -turn)                                  // curl clockwise seen from +N
        prev = p; p = p1
        S *= rule.sig
        k += 1
    }
    if level == 0 { eyePos = p }
}

// MARK: - Render

func lookAt(_ eye: SIMD3<Float>, _ at: SIMD3<Float>, _ up: SIMD3<Float>) -> simd_float4x4 {
    let f = normalize(at - eye), s = normalize(cross(f, up)), u = cross(s, f)
    return simd_float4x4(rows: [SIMD4(s, -dot(s, eye)), SIMD4(u, -dot(u, eye)), SIMD4(-f, dot(f, eye)), SIMD4(0, 0, 0, 1)])
}
func perspective(_ fovy: Float, _ aspect: Float, _ n: Float, _ f: Float) -> simd_float4x4 {
    let y = 1 / tan(fovy / 2), x = y / aspect
    return simd_float4x4(rows: [SIMD4(x, 0, 0, 0), SIMD4(0, y, 0, 0), SIMD4(0, 0, f / (n - f), n * f / (n - f)), SIMD4(0, 0, -1, 0)])
}

var lastBuildMs = 0.0, lastGpuMs = 0.0
var lastVP = matrix_identity_float4x4

var camVH: Float = 0, camCX: Float = 0                // smoothed auto-framing (live: follows the frond)
func render(unfurl: Float, sway: Float, time: Float, dt: Float = 0) {
    // Camera: unfurl 0 is the reference framing (fitted). As the frond opens, the camera pulls back so
    // the whole frond stays in frame, the frame bottom stays on the stalk, and it re-centres sideways.
    let viewH = envF("VIEWH", 1.4), camD = envF("CAMD", 3.0)
    let fov: Float = 2 * atan(0.5 * viewH / camD)                // VIEWH: world height in frame at the fern
    let aspect = Float(outW) / Float(outH)
    let front = envF("F0", 0.1235) + (envF("FMAX", 1.0) - envF("F0", 0.1235)) * unfurl
    let base = SIMD3<Float>(envF("BX", -0.377), envF("BY", -0.700), 0)
    let lean = envF("LEAN", 0.037) + sway
    let seg0 = envF("SEG", 0.193) * (1 + envF("GROW", 0.0) * unfurl)
    let dir0 = SIMD3<Float>(sin(lean), cos(lean), 0)
    let tb = Date()
    // Coarse pre-pass for the frond's extent (big pixels → shallow recursion).
    pxWorld = 12 * viewH / Float(outH)
    nLeaves = 0; nTubes = 0; nBeads = 0
    chain(base, dir: dir0, normal: SIMD3(0, 0, 1), link: seg0, front: front, level: 0, hash: 0.37, young0: 0)
    var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
    for i in 0..<nTubes { let q = SIMD2(tubes[i].b.x, tubes[i].b.y); lo = simd_min(lo, q); hi = simd_max(hi, q) }
    for i in 0..<nLeaves { let q = SIMD2(leaves[i].o.x, leaves[i].o.y); lo = simd_min(lo, q); hi = simd_max(hi, q) }
    let cx0 = envF("CX", 0.0), bottom = envF("CY", 0.0) - viewH / 2, margin = envF("FRAMEM", 0.06)
    let needH = max(viewH, hi.y + margin - bottom, (hi.x - lo.x + 2 * margin) / aspect)
    let needX = min(max(cx0, hi.x + margin - needH * aspect / 2), lo.x - margin + needH * aspect / 2)
    let k = dt > 0 ? 1 - exp(-dt / envF("CAMTAU", 1.5)) : 1
    camVH += (needH - camVH) * k; camCX += (needX - camCX) * k
    let camDist = camD * camVH / viewH
    let target = SIMD3<Float>(camCX, bottom + camVH / 2, 0)
    let cam = target + SIMD3<Float>(envF("CAMX", 0.0), envF("CAMY", 0.0), camDist)
    pxWorld = camDist * 2 * tan(fov / 2) / Float(outH)
    nLeaves = 0; nTubes = 0; nBeads = 0; dump = []
    chain(base, dir: dir0, normal: SIMD3(0, 0, 1), link: seg0, front: front, level: 0, hash: 0.37, young0: 0)
    lastBuildMs = Date().timeIntervalSince(tb) * 1000
    let vp = perspective(fov, Float(outW) / Float(outH), 0.1, 50) * lookAt(cam, target, SIMD3(0, 1, 0))
    lastVP = vp
    let coilPos = eyePos + SIMD3<Float>(0, 0, -envF("LZ", 0.06))
    var u = Uniforms(viewProj: vp, eye: SIMD4(cam, time),
                     coil: SIMD4(coilPos, envF("LI", 1.842) * (1 - 0.5 * unfurl)),
                     coilCol: SIMD4(1.0, envF("LCG", 0.192), envF("LCB", 0.102), envF("LR", 0.295) * (1 + unfurl)),
                     keyDir: SIMD4(normalize(SIMD3<Float>(-0.5, 0.7, 0.6)), envF("KEY", 0.422)),
                     backDir: SIMD4(normalize(SIMD3<Float>(0.4, 0.5, -0.8)), envF("BACK", 1.633)),
                     look: [envF("BODY", 0.667), envF("IRID", 1.376), envF("BEAD", 7.719), envF("DBG", 0)],
                     mat: [envF("TRANS", 1.152), envF("RIMG", 1.174), envF("WARMK", 0.532), envF("TALB", 0.314)],
                     bgk: [envF("HAZE", 0.03), envF("BLOOM1", 0.25), envF("BLOOM2", 0.18), envF("EXPO", 1.6)],
                     tex: [envF("SCAL", 3.768), envF("FIB", 0.429), envF("HAIRG", 2.222), envF("LINE", 0.879)],
                     warmc: [envF("RIMCG", 0.562), envF("RIMCB", 0.236), rule.leafBend, 0],
                     glass: [envF("GA", 0.35), envF("FILMB", 0.5), envF("RIMPX", 2.2), envF("GLINT", 1.0)],
                     stem: [envF("HELIX", 4), envF("PITCH", 1.0), envF("FIBN", 24), envF("BAND", 1.0)])
    let clip = vp * SIMD4<Float>(eyePos, 1)
    var coilScreen = SIMD4<Float>(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5, 0.35 * (1 + unfurl), u.coil.w / 2.2)

    let cb = queue.makeCommandBuffer()!
    let rp = MTLRenderPassDescriptor()
    for (i, (ms, rs)) in [(colorMS, accumTex), (revealMS, revealTex), (addMS, addTex)].enumerated() {
        rp.colorAttachments[i].texture = ms; rp.colorAttachments[i].resolveTexture = rs
        rp.colorAttachments[i].loadAction = .clear; rp.colorAttachments[i].storeAction = .multisampleResolve
        rp.colorAttachments[i].clearColor = i == 1 ? MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1) : MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }
    rp.depthAttachment.texture = depthMS
    rp.depthAttachment.loadAction = .clear; rp.depthAttachment.clearDepth = 1; rp.depthAttachment.storeAction = .dontCare
    let re = cb.makeRenderCommandEncoder(descriptor: rp)!
    re.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
    re.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
    re.setDepthStencilState(depthRead)
    re.setCullMode(.none)
    if nTubes > 0 {
        re.setRenderPipelineState(tubePSO); re.setVertexBuffer(tubeBuf, offset: 0, index: 0)
        re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 8 * 6, instanceCount: nTubes)
    }
    if nLeaves > 0 {
        re.setRenderPipelineState(leafPSO); re.setVertexBuffer(leafBuf, offset: 0, index: 0)
        re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 10 * 8 * 6, instanceCount: nLeaves)
    }
    if nBeads > 0 {
        re.setDepthStencilState(depthRead)
        re.setRenderPipelineState(beadPSO); re.setVertexBuffer(beadBuf, offset: 0, index: 0)
        re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: nBeads)
    }
    re.endEncoding()
    let rc = cb.makeComputeCommandEncoder()!
    rc.setComputePipelineState(resolvePSO)
    rc.setTexture(accumTex, index: 0); rc.setTexture(revealTex, index: 1); rc.setTexture(addTex, index: 2); rc.setTexture(hdrTex, index: 3)
    rc.dispatchThreads(MTLSize(width: outW, height: outH, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    rc.endEncoding()
    let mb = cb.makeBlitCommandEncoder()!; mb.generateMipmaps(for: hdrTex); mb.endEncoding()
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(presentPSO)
    ce.setTexture(hdrTex, index: 0); ce.setTexture(outTex, index: 1)
    ce.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
    ce.setBytes(&coilScreen, length: 16, index: 1)
    ce.dispatchThreads(MTLSize(width: outW, height: outH, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    ce.endEncoding()
    let bb = cb.makeBlitCommandEncoder()!
    bb.copy(from: outTex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
            sourceSize: MTLSize(width: outW, height: outH, depth: 1), to: readback,
            destinationOffset: 0, destinationBytesPerRow: outW * 4, destinationBytesPerImage: outW * outH * 4)
    bb.endEncoding()
    cb.commit(); cb.waitUntilCompleted()
    lastGpuMs = (cb.gpuEndTime - cb.gpuStartTime) * 1000
    if let e = cb.error { FileHandle.standardError.write("GPU error: \(e)\n".data(using: .utf8)!) }
}

func writePNG(_ path: String) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: readback.contents(), width: outW, height: outH, bitsPerComponent: 8,
                        bytesPerRow: outW * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, ctx.makeImage()!, nil); CGImageDestinationFinalize(dst)
}

switch args.count > 1 ? args[1] : "" {
case "still":
    render(unfurl: Float(args[2])!, sway: 0, time: 3)
    render(unfurl: Float(args[2])!, sway: 0, time: 3)          // second run: warm timings
    FileHandle.standardError.write(String(format: "build %.1f ms, gpu %.1f ms; tubes %d leaves %d beads %d\n",
                                          lastBuildMs, lastGpuMs, nTubes, nLeaves, nBeads).data(using: .utf8)!)
    writePNG(args[3])
case "film":
    let seconds = Float(args[2])!, fps: Float = 30
    let ff = Process()
    ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(outW)x\(outH)",
                    "-r", "30", "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", args[3]]
    let pipeIn = Pipe(); ff.standardInput = pipeIn
    try! ff.run()
    var worst = 0.0
    for i in 0..<Int(seconds * fps) {
        let t = Float(i) / fps
        let unfurl = 0.5 - 0.5 * cos(2 * Float.pi * t / seconds)
        let sway = 0.04 * sin(2 * Float.pi * t / 5.3) + 0.02 * sin(2 * Float.pi * t / 2.9)
        render(unfurl: unfurl, sway: sway, time: t, dt: i == 0 ? 0 : 1 / fps)
        worst = max(worst, lastBuildMs + lastGpuMs)
        pipeIn.fileHandleForWriting.write(Data(bytes: readback.contents(), count: outW * outH * 4))
    }
    try! pipeIn.fileHandleForWriting.close()
    ff.waitUntilExit()
    FileHandle.standardError.write(String(format: "worst frame build+gpu %.1f ms\n", worst).data(using: .utf8)!)
case "dump":
    // level-0/1 chain links projected to image px: level hash x y linkPx
    render(unfurl: Float(args[2])!, sway: 0, time: 3)
    for line in dump {
        let v = line.split(separator: " ").map { Float($0)! }
        let c = lastVP * SIMD4<Float>(v[2], v[3], v[4], 1)
        print(Int(v[0]), v[1], (c.x / c.w * 0.5 + 0.5) * Float(outW), (0.5 - c.y / c.w * 0.5) * Float(outH), v[5] / pxWorld)
    }
default:
    print("usage: fh3d still <unfurl 0…1> <out.png>  |  fh3d film <seconds> <out.mp4>")
}
