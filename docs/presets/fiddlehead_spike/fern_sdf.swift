// fern_sdf.swift — FH.13 look-spike (throwaway; not engine code).
//
// Matt's reference (docs/VISUAL_REFERENCES/fiddlehead/01_reference_matt_2026-10-05.webp) is a LIT 3-D object: a thick
// translucent tube rising and rolling into a nautilus, its outer rim studded with miniature croziers (each a copy of the
// whole), backlit amber from a glowing core, iridescent rims with sparkle beads, depth of field over a bokeh garden.
// Every 2-D point/line build (FH.6–FH.12) failed shape, light, detail and mood together, so this one is RAY-MARCHED:
//
//   • the crozier = a tube along a log spiral r = R0·e^{b(φ−φ0)} (closed-form distance: nearest winding), radius ∝ r, so
//     it thins self-similarly into the eye; below its outer end a curved stalk runs to the bottom of the frame
//   • rim croziers = the SAME crozier scaled to the local radius, attached on the outer rim, leaving it along the outward
//     normal — and theirs, and theirs (iterative descent into the nearest child: depth = fractal levels)
//   • shading: green translucency, an amber point light in the coil's eye shining through the tissue, Fresnel rims with
//     an iridescent hue, sparkle beads on the rims, a glow halo, a bokeh garden behind
//
// Build:  swiftc -O -swift-version 5 fern_sdf.swift -o fernsdf
// Usage:  fernsdf still <unfurl 0…1> <out.png>        (env vars = knobs)

import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let env = ProcessInfo.processInfo.environment
func envF(_ k: String, _ d: Float) -> Float { env[k].flatMap(Float.init) ?? d }
let W = Int(envF("W", 1672)), H = Int(envF("H", 940))

// MARK: - Shader

let msl = """
#include <metal_stdlib>
using namespace metal;

struct P { float4 sp; float4 rim; float4 cam; float4 lit; float4 stalk; float4 misc; float4 misc2; float4 q; float4 stalk2; float4 x2; };   // x2: leaflet slant, leaflet width   // stalk2: stalk-pinna spiral growth, band-width scale, upward lean   // q: supersamples   // misc2: pinna count, pinna scale
// sp:    R0 (outer coil radius), b (spiral growth per radian), k (tube radius / spiral radius), φ0 (outer end angle)
// rim:   child scale (× local spiral radius), child spacing (rad), depth (levels), child lean (rad)
// cam:   centre x, y (scene units), view half-height, perspective
// lit:   core light gain, rim/iridescence gain, sparkle density, glow gain
// stalk: base x, base y, bend (control-point offset), radius growth to the base
// misc:  time, band width (× r), band thickness (× r), leaflets per radian

constant float PI = 3.14159265;

static uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16; return x; }
static float h1(float2 q) { return float(hash(uint(q.x * 1973.0 + 7.0) ^ hash(uint(q.y * 9277.0 + 3.0)))) / 4294967296.0; }
static float2x2 rot2(float a) { float c = cos(a), s = sin(a); return float2x2(float2(c, s), float2(-s, c)); }

struct Hit { float d; float phi; float lvl; float rr; float v; float ws; };   // ws: world scale of the copy hit (on-screen LOD)   // v: across the band, −1 inner edge … +1 outer edge

// Distance to the spiral tube (one crozier, local units). Returns also the winding's φ and spiral radius at the nearest point.
static Hit spiralTube(float3 p, constant P& P_, float bo, float kws) {
    float R0 = P_.sp.x, b = bo > 0.0 ? bo : P_.sp.y, k = P_.sp.z, phi0 = P_.sp.w, cosA = 1.0 / sqrt(1.0 + b * b);
    float r = length(p.xy), ph = atan2(p.y, p.x);
    float t = (log(max(r, 1e-6) / R0) / b + phi0 - ph) / (2.0 * PI);
    Hit h; h.d = 1e9; h.phi = phi0; h.rr = R0; h.lvl = 0.0; h.v = 0.0; h.ws = 1.0;
    float KW = P_.misc.y * kws, KT = P_.misc.z;
    float kmax = floor((phi0 - ph) / (2.0 * PI));                 // the outermost winding that exists at this angle
    for (int dk = 0; dk <= 1; dk++) {
        float phk = ph + 2.0 * PI * min(floor(t) + float(dk), kmax);   // (no windings past the outer end: it was a tunnel)
        float rr = R0 * exp(b * (phk - phi0));
        // the coil is a broad flat BAND of leaves (reference), not a round tube: elliptical cross-section
        float tp = smoothstep(phi0, phi0 - (bo > 0.0 ? 0.3 : 1.4), phk);   // root taper: short on pinnae (a long one left only thin spikes)
        // LEAFLETS CUT INTO THE OUTLINE: the band swells at each leaflet and notches between them (toothed, not a printed strip);
        // leaflet spacing follows log-radius, so it is the same count per scale on the coil and on every pinna
        float sig = log(rr / R0) / b, cu = fract(sig * P_.misc.w);   // by this spiral's OWN growth: pinnae had 2.25× too many leaflets (rope)
        float jit = 0.85 + 0.3 * h1(float2(floor(sig * P_.misc.w), floor(phi0 * 7.0)));   // each leaflet its own size (bead-chain read)
        float notch = mix(1.0, jit, 0.5);
        float a = mix(k, KW * notch, tp) * rr, dr = (r - rr) * cosA, vv0 = clamp(dr / max(a, 1e-6), -1.0, 1.0);
        float lobe = pow(sin(PI * cu), 0.8) * (1.0 - vv0 * vv0 * 0.6);           // each leaflet a puffed glass lobe (printed herringbone read flat)
        float c = mix(k, KT * (0.55 + 0.5 * lobe * smoothstep(0.02, 0.10, rr / R0)), tp) * rr;   // flatter leaflets (puffed lobes read as dragon scales)
        float d = (length(float2(dr / a, p.z / c)) - 1.0) * min(a, c);
        // LEAFLETS CUT OUT OF THE BAND in its own (along, across) coordinates: separate lance-shaped leaflets slanting toward
        // the tip, joined only by a thin midrib (notching the outline gave scales or saw-teeth, never leaves)
        float lodC = smoothstep(0.02, 0.06, rr / R0) * tp;
        if (lodC > 0.01) {
            float cellL = rr / (P_.misc.w * cosA), ax = clamp(abs(dr) / a, 0.0, 1.0);
            float uu = fract(sig * P_.misc.w + P_.x2.x * ax) - 0.5;
            float wl = P_.x2.y * (1.0 - pow(ax, 1.6)) + 0.03;
            float cut = min((abs(uu) - wl) * cellL * 0.8, abs(dr) - 0.1 * a);
            d = max(d, mix(-1.0, cut, lodC));
        }
        if (d < h.d) { h.d = d; h.phi = sig; h.rr = rr; h.v = clamp(dr / a, -1.0, 1.0); }   // phi: leaflet coordinate
    }
    // (no end-cap ball: Matt — "branches should not be connected to the tree with a circle"; the band already tapers to its root)
    return h;
}

// Quadratic Bézier distance (2-D, sampled + refined) for the stalk below the coil.
static float2 bez(float2 a, float2 c, float2 e, float t) { float u = 1.0 - t; return u * u * a + 2.0 * u * t * c + t * t * e; }
static float stalkDist(float3 p, constant P& P_, thread float& tOut) {
    float R0 = P_.sp.x, phi0 = P_.sp.w, b = P_.sp.y;
    float2 a = R0 * float2(cos(phi0), sin(phi0));
    float2 u0 = float2(cos(phi0), sin(phi0)), tout = normalize(b * u0 + float2(-u0.y, u0.x));   // outward along the spiral
    float2 e = P_.stalk.xy, c = a + tout * P_.stalk.z + float2(-0.55, 0.0);   // bowed, like the reference's stalk
    float best = 1e9, bt = 0.0;
    for (int i = 0; i <= 24; i++) { float t = float(i) / 24.0; float dd = length(p.xy - bez(a, c, e, t)); if (dd < best) { best = dd; bt = t; } }
    for (int it = 0; it < 4; it++) {
        float dt = 0.5 / 24.0 / float(1 << it);
        float t1 = clamp(bt - dt, 0.0, 1.0), t2 = clamp(bt + dt, 0.0, 1.0);
        float d1 = length(p.xy - bez(a, c, e, t1)), d2 = length(p.xy - bez(a, c, e, t2));
        if (d1 < best) { best = d1; bt = t1; } if (d2 < best) { best = d2; bt = t2; }
    }
    tOut = bt;
    float rad = P_.misc2.w * P_.rim.x * R0 * (1.0 + P_.stalk.w * bt);   // the rachis continued, thickening toward the base
    return length(float2(best, p.z)) - rad;
}

// The whole scene: the crozier + its stalk, and rim croziers (copies) descended into level by level.
// THE FIDDLEHEAD = ONE RULE: a rachis that rolls into a log spiral and continues as the stalk, lined on both sides with
// pinnae — small croziers (the same leaf band, its own looser spiral) scaled to the local coil radius. The outer pinnae's
// curled tips ARE the ring of rim croziers; the inner pinnae are the amber-lit leaves; down the stalk the same pinnae,
// longer, curl at their tips. (A separate band + rim + pipe stalk read as an assembled object.)
static float rachisSpiral(float3 p, constant P& P_, thread float2& ph2) {
    float R0 = P_.sp.x, b = P_.sp.y, phi0 = P_.sp.w, cosA = 1.0 / sqrt(1.0 + b * b);
    float r = length(p.xy), ph = atan2(p.y, p.x);
    float t = (log(max(r, 1e-6) / R0) / b + phi0 - ph) / (2.0 * PI), kmax = floor((phi0 - ph) / (2.0 * PI));
    float best = 1e9;
    for (int dk = 0; dk <= 1; dk++) {
        float phk = ph + 2.0 * PI * min(floor(t) + float(dk), kmax), rr = R0 * exp(b * (phk - phi0));
        float d = length(float2((r - rr) * cosA, p.z)) - P_.rim.x * rr;
        ph2[dk] = phk;
        best = min(best, d);
    }
    return best;
}

static Hit pinna(float3 p, float2 attach, float2 dir, float s, float side, float mir, float bp, float kws, constant P& P_) {
    float R0 = P_.sp.x, phi0 = P_.sp.w;
    float2 u0 = float2(cos(phi0), sin(phi0)), P0 = R0 * u0, tinB = -normalize(bp * u0 + float2(-u0.y, u0.x));
    float ang = atan2(dir.y, dir.x) - atan2(tinB.y, tinB.x);
    float2 ql = rot2(-ang) * (p.xy - attach) / s;
    if (side * mir < 0.0) { ql = reflect(ql, normalize(float2(-tinB.y, tinB.x))); }   // mirrored pair (mir picks which side curls which way)
    Hit ch = spiralTube(float3(ql + P0, p.z / s), P_, bp, kws);
    ch.d *= s; ch.ws = s; ch.lvl = 0.0;
    return ch;
}

static Hit scene(float3 p, constant P& P_) {
    float R0 = P_.sp.x, b = P_.sp.y, phi0 = P_.sp.w;
    Hit best; best.d = 1e9; best.phi = phi0; best.rr = R0; best.lvl = -1.0; best.v = 0.0; best.ws = 1.0;
    // the rachis: spiral + stalk (smoothly joined)
    float2 ph2; float dr = rachisSpiral(p, P_, ph2);
    float tS; float ds = stalkDist(p, P_, tS);
    float hk = clamp(0.5 + 0.5 * (ds - dr) / 0.05, 0.0, 1.0);
    best.d = mix(ds, dr, hk) - 0.05 * hk * (1.0 - hk);
    // coil pinnae (reference close-up): BIG leafy croziers hang INWARD from the rachis, ~9 per outer turn; a separate,
    // denser ring of SMALL glassy curls sits on the OUTSIDE (one shared spacing made the inside a mesh)
    for (int w = 0; w <= 1; w++) {
        for (int sd = 0; sd <= 1; sd++) {
            float side = sd == 0 ? 1.0 : -1.0, sp = side > 0.0 ? P_.q.w : P_.rim.y, sc = side > 0.0 ? P_.q.z : 1.0;
            float cf = floor((ph2[w] - phi0) / sp);
            for (int j = -1; j <= 1; j++) {
                float phc = phi0 + min(cf + float(j) + 0.5, -1.0) * sp, rc = R0 * exp(b * (phc - phi0));
                float2 uc = float2(cos(phc), sin(phc)), C = uc * rc, Tin = -normalize(b * uc + float2(-uc.y, uc.x));
                float s = P_.rim.z * rc / R0 * sc;
                if (length(p.xy - C) > s * R0 * 3.0) { continue; }
                float2 dir = normalize(side * uc + Tin * P_.rim.w);
                Hit ch = pinna(p, C + side * uc * P_.rim.x * rc, dir, s, side, -1.0, P_.misc2.z, 1.0, P_);
                if (ch.d < best.d) { best = ch; best.v = side > 0.0 ? ch.v : -ch.v; best.lvl = side > 0.0 ? 1.0 : 0.0; }
            }
        }
    }
    // stalk pinnae: longer down the stalk, alternating sides, leaning up toward the coil
    {
        float2 u0 = float2(cos(phi0), sin(phi0)), a = R0 * u0, tout = normalize(b * u0 + float2(-u0.y, u0.x));
        float2 e = P_.stalk.xy, c = a + tout * P_.stalk.z + float2(-0.55, 0.0);
        float NP = P_.misc2.x, dt = 0.85 / max(NP - 1.0, 1.0), STB = P_.stalk2.x, STW = P_.stalk2.y, STL = P_.stalk2.z;
        for (int j = 0; j < 12; j++) {
            if (float(j) >= NP) { break; }
            float tp = 0.06 + float(j) * dt, side = fmod(float(j), 2.0) < 0.5 ? 1.0 : -1.0;
            float2 B = bez(a, c, e, tp), T = normalize(2.0 * (1.0 - tp) * (c - a) + 2.0 * tp * (e - c)), Nn = float2(-T.y, T.x);
            float s = P_.misc2.y * (1.0 + 1.2 * tp);
            if (length(p.xy - B) > s * R0 * 2.6) { continue; }
            Hit ch = pinna(p, B + side * Nn * P_.rim.x * R0, normalize(side * Nn - STL * T), s, side, 1.0, STB, STW, P_);   // stalk: feathery lances (looser spiral, narrower band), curling only at the tip
            if (ch.d < best.d) { best = ch; }
        }
    }
    return best;
}

static float3 nrm(float3 p, constant P& P_) {
    const float e = 0.0004;
    float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * scene(p + k.xyy * e, P_).d + k.yyx * scene(p + k.yyx * e, P_).d +
                     k.yxy * scene(p + k.yxy * e, P_).d + k.xxx * scene(p + k.xxx * e, P_).d);
}

static float3 hsv(float h, float s, float v) { float3 k = clamp(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0); return v * mix(float3(1.0), k, s); }

static float3 shade(float3 p, float3 rd, Hit h, constant P& P_, thread float& fresOut) {
        float3 n = nrm(p, P_), vv = -rd;
        float fres = pow(1.0 - clamp(dot(n, vv), 0.0, 1.0), 3.0);
        // LEAF PATTERN on the band: a herringbone of leaflets, a fixed number per radian (they shrink with the spiral),
        // each with a midrib and a bright edge, separated by dark gaps; outer half green, inner half backlit
        float N = P_.misc.w, cu = fract(h.phi * N), side = h.v >= 0.0 ? 1.0 : -1.0, av = abs(h.v);
        float lj = h1(float2(floor(h.phi * N), h.lvl * 5.0 + 1.0));
        float across = fract(h.phi * N + P_.x2.x * av) - 0.5;          // the same slanted leaflet cells the geometry is cut on
        float wl = P_.x2.y * (1.0 - pow(av, 1.6)) + 0.03;
        float lod = smoothstep(0.02, 0.10, h.rr * h.ws / P_.sp.x);   // pattern fades where leaflets go sub-pixel ON SCREEN
        float inLeaf = mix(0.7, smoothstep(wl, wl - 0.06, abs(across)), lod);
        float edgeL = smoothstep(0.06, 0.0, abs(abs(across) - wl + 0.03));
        float vein = smoothstep(0.035, 0.0, abs(across)) + smoothstep(0.03, 0.0, av) * 0.6
                   + smoothstep(0.06, 0.0, abs(fract(av * 6.0 - abs(across) * 4.0) - 0.5) - 0.44) * 0.35;   // pinnate side veins
        // BACKLIT GLASS: a warm light behind the frond shines through the thin leaves — bodies glow lime-gold where lit through,
        // deep green where not; hue ranges emerald/teal (outer, left) → gold → amber toward the core (reference)
        float3 Lb = normalize(float3(0.25, 0.35, 1.0));
        float backlit = clamp(0.35 + 0.65 * dot(-n, -Lb) * 0.5 + 0.5 * fres, 0.0, 1.0);
        float warmth = smoothstep(0.30, 0.03, length(p.xy)), cool = smoothstep(-0.4, -1.6, p.x);   // warm only at the eye
        float3 deep = mix(float3(0.07, 0.14, 0.02), float3(0.04, 0.13, 0.05), cool);   // warm olive (reference subject: 61 % of hues are red→yellow)
        float3 lit = mix(mix(float3(0.55, 0.80, 0.12), float3(0.35, 0.75, 0.30), cool), float3(1.0, 0.48, 0.10), warmth);   // lime-gold, not emerald/teal   // emerald; ORANGE backlit leaves at the core
        float3 green = mix(deep, lit, backlit);
        float3 tissue = green * (0.35 + 0.65 * inLeaf) + float3(0.55, 0.85, 0.30) * (edgeL * 0.6 + vein * 0.35) * inLeaf;
        float key = 0.55 + 0.45 * dot(n, normalize(float3(-0.4, 0.6, -0.7)));   // wrap: glass undersides aren't black
        // light from the coil's eye shining THROUGH the tissue: strongest near the eye and on the band's inner half
        float de = length(p.xy);
        float through = exp(-de * 7.0) * P_.lit.x;                    // amber only right at the eye (it gilded the whole coil)
        float3 amber = float3(1.0, 0.52, 0.12) * through * (0.4 + 0.6 * inLeaf) * (1.0 + 0.8 * vein);
        float3 irid = min(hsv(0.50 + 0.35 * fres + 0.05 * h.phi, 0.7, 1.0) * (fres * 0.6 + smoothstep(0.75, 1.0, h.v)) * P_.lit.y, 0.8);   // below the bloom threshold: edges bloomed into a violet fur
        // sparkle beads along the outer edge and on the rim croziers
        float2 sc2 = float2(fract(h.phi * N * 2.0) - 0.5, (abs(h.v) - 0.9) * 2.5);   // beads on BOTH leaf edges
        float cellId = floor(h.phi * N * 2.0) + h.lvl * 997.0;
        float bead = smoothstep(0.32, 0.10, length(sc2)) * step(1.0 - P_.lit.z, h1(float2(cellId, 7.0)));
        bead += (h.lvl > 0.5 ? step(0.86, h1(float2(floor(h.phi * 6.0) + h.lvl * 13.0, 3.0))) * smoothstep(0.4, 0.9, fres) : 0.0);
        float tipz = smoothstep(0.12, 0.03, h.rr / P_.sp.x) * step(0.55, h1(float2(floor(h.phi * 3.0), floor(p.x * 40.0) + floor(p.y * 40.0) * 7.0)));
        bead += tipz * smoothstep(0.2, 0.7, fres + 0.3);                       // beads on the curled tips
        float3 spark = mix(float3(1.0, 0.85, 0.6), float3(0.85, 0.7, 1.0), h1(float2(cellId, 2.0))) * bead * 2.9;
        // GLASS FACETS: fine relief on the tissue breaks the highlight into glitter (the reference sparkles at fine scale)
        float3 cf = floor(p * 220.0);
        float3 bump = float3(h1(cf.xy + cf.z), h1(cf.yz + 3.1), h1(cf.zx + 7.7)) - 0.5;
        float3 nb = normalize(n + bump * 0.9);
        float spec = pow(clamp(dot(reflect(normalize(float3(0.4, -0.6, 0.7)), nb), vv), 0.0, 1.0), 60.0) * 2.0
                   + pow(clamp(dot(reflect(normalize(float3(-0.3, -0.2, 0.9)), nb), vv), 0.0, 1.0), 80.0) * 1.5;
        float midrib = smoothstep(0.05, 0.0, av) * 0.5 + smoothstep(0.04, 0.0, abs(fract(h.phi * N) - 0.5)) * 0.25 * lod;   // subtle veins only
        // LIGHT FROM THE CORE AND THE RIMS (reference): leaf bodies are dark translucent green, lit by the coil's eye (falloff +
        // facing); edges glow bright at grazing angles; crevices go deep — evenly lit leaves read as a flat illustration
        float3 toC = normalize(float3(0.0, 0.0, 0.15) - p); float dC = length(p.xy);
        float coreLit = (0.35 + 0.65 * clamp(dot(n, toC) * 0.5 + 0.5, 0.0, 1.0)) * (0.35 + 0.8 * exp(-dC * 2.2));
        float rimL = smoothstep(0.15, 0.85, fres);
        tissue = green * (0.12 + 1.1 * coreLit) + mix(float3(0.55, 1.0, 0.45), float3(1.0, 0.8, 0.35), max(warmth, 0.6)) * (rimL * 2.2 + midrib * 0.3);
        tissue += float3(1.0, 0.55, 0.15) * smoothstep(0.9, 0.2, av) * 0.5 * warmth;   // warm light through leaf centres ONLY near the core (orange on green = yellow)
        // THE RACHIS (reference, close up): a thick glossy glass tube on each turn's OUTER edge, carrying a string of cyan / magenta /
        // white bead lights; green glass below the coil
        if (h.lvl < -0.5) {
            float ang = atan2(p.y, p.x), inCoil = smoothstep(1.6, 0.9, length(p.xy));
            float3 tube = deep * 0.5 + lit * 0.06 * key + hsv(0.55 + 0.25 * sin(ang * 1.5 + length(p.xy) * 4.0), 0.7, 1.0) * (0.15 + fres * 1.8) * inCoil
                        + float3(1.0, 0.8, 0.4) * fres * 1.4 * (1.0 - inCoil);   // gold-lit stalk edges
            float bc = fract(ang * 38.0 / 6.2831853 * (1.0 + 2.0 * (1.0 - length(p.xy)))), bid = floor(ang * 38.0 / 6.2831853 * (1.0 + 2.0 * (1.0 - length(p.xy))));
            float bl = smoothstep(0.12, 0.03, abs(bc - 0.5)) * smoothstep(0.35, 0.75, fres) * step(0.45, h1(float2(bid, 11.0))) * inCoil;   // sparse bead lights on the tube's flanks (full-width bands read as candy stripes)
            tube += mix(float3(0.4, 0.95, 1.0), float3(1.0, 0.45, 0.95), h1(float2(bid, 9.0))) * bl * 2.6 + float3(1.0) * bl * step(0.8, h1(float2(bid, 4.0))) * 1.5;
            tissue = tube; amber *= 0.3;
        }
        if (h.lvl > 0.5) { tissue = green * 0.35 + mix(float3(1.0, 0.68, 0.28), float3(0.7, 0.5, 1.0), 0.25 * h1(float2(floor(h.phi * 3.0), 5.0))) * (0.12 + 0.5 * edgeL + 1.8 * fres); }   // rim curls: green glass, gold-lit edges   // rim croziers: glowing gold/violet beads
        float ao = 1.0;                                                // depth: crevices go dark (it read as a flat sticker)
        for (int k = 1; k <= 4; k++) { float hh = 0.02 * float(k); ao -= (hh - scene(p + n * hh, P_).d) * (0.9 / float(k)) * 4.5; }
        ao = clamp(ao, 0.15, 1.0);
        float3 gc = floor(p * 140.0); float gl = h1(gc.xy + gc.z * 17.0);                  // glints hashed in 3-D, on edges
        float glint = step(0.88, gl) * smoothstep(0.15, 0.7, fres) * 2.8;
        float fall = 1.0;                                             // (falloff now lives in coreLit)
        fresOut = fres;
        return (tissue * key * fall + irid) * ao + amber + spark * 2.0 + float3(1.0, 0.95, 0.85) * (spec * 2.5 + glint);
}

static float3 renderPix(float2 pix, constant P& P_) {
    float2 res = float2(\(W).0, \(H).0), uv = (pix - 0.5 * res) / res.y * float2(1.0, -1.0);
    float3 ro = float3(P_.cam.xy + uv * 2.0 * P_.cam.z, -3.0), rd = normalize(float3(uv * P_.cam.w, 1.0));
    float t = 0.0, glow = 0.0; Hit h; h.d = 1e9; bool hit = false;
    for (int i = 0; i < 160; i++) {
        float3 p = ro + rd * t; h = scene(p, P_);
        glow += exp(-max(h.d, 0.0) * 60.0) * 0.012;
        if (h.d < 0.0006 * (1.0 + t)) { hit = true; break; }
        t += h.d * 0.7;
        if (t > 8.0) { break; }
    }
    // BACKGROUND (reference, measured): near-black navy above (sRGB ~8–20), faint trunks, a lower garden of out-of-focus glass
    // fern domes with iridescent warm rims (sRGB 35–130), scattered warm/cool bokeh
    float2 q = pix / res;
    float3 bg = mix(float3(0.0008, 0.0012, 0.002), float3(0.002, 0.0035, 0.0045), q.y);
    for (int k = 0; k < 6; k++) {                                    // soft dark trunks
        uint hk = hash(uint(k) * 3571u + 101u);
        float xk = float(hk & 1023u) / 1023.0, wk = 0.015 + 0.03 * float((hk >> 10) & 255u) / 255.0;
        bg += float3(0.0025, 0.004, 0.006) * exp(-pow((q.x - xk) / wk, 2.0)) * smoothstep(0.95, 0.1, q.y);
    }
    for (int k = 0; k < 7; k++) {                                    // glass fern domes, out of focus, along the bottom
        uint hk = hash(uint(k) * 7919u + 29u);
        float xk = (float(k) + 0.2 + 0.6 * float(hk & 255u) / 255.0) / 7.0 * 1.2 - 0.1;
        if (abs(xk - 0.42) < 0.08) { continue; }     // the stalk stands there
        float rad = res.y * (0.16 + 0.12 * float((hk >> 8) & 255u) / 255.0);
        float2 cp = float2(xk * res.x, res.y * (1.0 + 0.08 + 0.1 * float((hk >> 16) & 255u) / 255.0));
        float dd = length(pix - cp) / rad, an = atan2(pix.y - cp.y, pix.x - cp.x);
        float3 ir = hsv(0.08 + 0.75 * float((hk >> 24) & 255u) / 255.0 + 0.15 * sin(an * 3.0), 0.6, 1.0);
        float body = smoothstep(1.0, 0.6, dd) * (0.7 + 0.3 * sin(an * 7.0 + dd * 6.0));   // frond mass, out of focus (sharp stripes read as umbrellas)
        bg += mix(float3(0.05, 0.05, 0.02), ir * 0.03, 0.4) * body + ir * 0.07 * exp(-pow((dd - 0.95) / 0.09, 2.0));
        bg += float3(1.0, 0.75, 0.4) * 0.05 * exp(-pow((dd - 0.97) / 0.03, 2.0)) * step(0.6, fract(an * 6.0 + float(k)));   // warm glints on the rims
    }
    for (int k = 0; k < 40; k++) {                                   // bokeh
        uint hk = hash(uint(k) * 7919u + 13u);
        float2 cp = float2(float(hk & 1023u) / 1023.0, 0.3 + 0.7 * float((hk >> 10) & 1023u) / 1023.0) * res;
        float rad = res.y * (0.012 + 0.03 * float((hk >> 20) & 255u) / 255.0), dd = length(pix - cp) / rad;
        const float3 bk[4] = { float3(0.3, 0.7, 0.75), float3(0.6, 0.35, 0.85), float3(1.0, 0.6, 0.25), float3(0.5, 0.8, 0.3) };
        bg += bk[hk % 4u] * 0.03 * q.y * smoothstep(1.0, 0.8, dd) * (0.6 + 0.4 * smoothstep(0.4, 0.95, dd));
    }
    float3 col = bg;
    // THE CORE: a star of backlit, veined amber leaves radiating from the eye between the inner turns (reference), drawn
    // in a plane just behind the band — the band occludes it; between the turns it glows
    {
        float tz = (0.12 - ro.z) / rd.z; float2 cp = (ro + rd * tz).xy;
        float rc = length(cp), ac = atan2(cp.y, cp.x), RS = P_.lit.w * 0.0 + 0.62 * P_.sp.x;
        float cell = fract(ac / (2.0 * PI) * 14.0) - 0.5, rn = clamp(rc / RS, 0.0, 1.0);
        float wl = 0.40 * pow(sin(PI * clamp((rn - 0.06) / 0.94, 0.0, 1.0)), 0.7);
        float leaf = smoothstep(wl, wl - 0.05, abs(cell)) * step(rc, RS);
        float vein = smoothstep(0.03, 0.0, abs(cell)) + smoothstep(0.08, 0.0, abs(fract(rn * 9.0 + abs(cell) * 3.0) - 0.5) - 0.42) * 0.5;
        float heat = exp(-rn * 2.6);
        float inside = smoothstep(RS, RS * 0.8, rc);                 // nothing outside the star (it lifted the whole frame)
        col += float3(1.0, 0.45, 0.08) * P_.lit.x * (leaf * (0.5 + 1.5 * vein)) * (0.25 + heat) * inside;   // ring of backlit orange leaves between the turns (reference)
        col += float3(1.0, 0.6, 0.25) * exp(-rc * rc / (0.012 * RS * RS)) * 5.0 * P_.lit.x;   // a small warm glow in the eye
    }
    float3 coreP = float3(0.0, 0.0, 0.25);                            // amber light in the coil's eye, a little behind
    // GLASS: up to 3 surface layers composited front to back — each partly see-through across its face, opaque and bright
    // at grazing edges — so inner turns glow through outer leaves (opaque surfaces read as a printed sticker)
    float3 acc = 0.0; float Tr = 1.0; float tl = 0.0;
    for (int layer = 0; layer < 3; layer++) {
        bool lh = false;
        if (layer == 0) { lh = hit; tl = t; }
        else {
            for (int i = 0; i < 90; i++) { Hit hh = scene(ro + rd * tl, P_); if (hh.d < 0.0006 * (1.0 + tl)) { h = hh; lh = true; break; } tl += hh.d * 0.7; if (tl > 8.0) { break; } }
        }
        if (!lh) { break; }
        float fr; float3 S = shade(ro + rd * tl, rd, h, P_, fr) * (layer == 0 ? 1.0 : 0.6);   // turns seen through glass sit back
        float al = mix(0.78, 0.97, fr);   // leaf bodies GLOW (mostly opaque); see-through only at grazing edges — centres went dark
        acc += Tr * al * S; Tr *= (1.0 - al);
        for (int i = 0; i < 40; i++) { float dd = scene(ro + rd * tl, P_).d; if (dd > 0.0015) { break; } tl += max(-dd, 0.002); }   // through the tissue
        tl += 0.002;
        if (Tr < 0.03) { break; }
    }
    col = acc + Tr * col;
    col += float3(1.0, 0.6, 0.25) * glow * P_.lit.w;
    return col;
}

// 4× supersampling (aliased hard edges read as CG/cartoon next to the reference's soft photographic look)
kernel void render(constant P& P_ [[buffer(0)]], texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {   // writes HDR
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    float3 c = 0.0;
    if (P_.q.x > 1.5) {
        const float2 o[4] = { float2(0.25, 0.25), float2(0.75, 0.25), float2(0.25, 0.75), float2(0.75, 0.75) };
        for (int k = 0; k < 4; k++) { c += renderPix(float2(gid) + o[k], P_); }
        c *= 0.25;
    } else { c = renderPix(float2(gid) + 0.5, P_); }
    out.write(float4(c, 1.0), gid);
}



// BLOOM: bright parts → quarter resolution → separable Gaussian → added back before the tone map (light must glow)
kernel void bright(texture2d<float> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float3 a = 0.0;
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) { a += src.read(gid * 4u + uint2(i, j)).rgb; }
    a /= 16.0;
    dst.write(float4(max(a - 3.0, 0.0), 1.0), gid);   // only the hot core blooms (edge beads bloomed into fur rays)
}
kernel void blur(texture2d<float> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], constant int2& dir [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float3 a = 0.0; float ws = 0.0;
    for (int k = -16; k <= 16; k++) {
        int2 c = clamp(int2(gid) + dir * k, int2(0), int2(dst.get_width() - 1, dst.get_height() - 1));
        float w = exp(-float(k * k) / 72.0); a += src.read(uint2(c)).rgb * w; ws += w;
    }
    dst.write(float4(a / ws, 1.0), gid);
}
constexpr sampler lin(filter::linear, address::clamp_to_edge);
kernel void compose(texture2d<float> hdr [[texture(0)]], texture2d<float> bl [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                    constant float4& g [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());
    float3 c = hdr.read(gid).rgb + bl.sample(lin, uv).rgb * g.x;
    float Y = dot(c, float3(0.299, 0.587, 0.114));
    c = max(mix(float3(Y), c, g.y), 0.0);                            // saturation lift (median 0.32 vs the reference's 0.59)
    c = c / (1.0 + dot(c, float3(0.299, 0.587, 0.114)));            // luminance tone map (hue-safe)
    out.write(float4(pow(clamp(c, 0.0, 1.0), float3(1.0 / 2.2)), 1.0), gid);
}
"""

struct Params { var sp: SIMD4<Float>; var rim: SIMD4<Float>; var cam: SIMD4<Float>; var lit: SIMD4<Float>; var stalk: SIMD4<Float>; var misc: SIMD4<Float>; var misc2: SIMD4<Float>; var q = SIMD4<Float>(1, 0, 0, 0); var stalk2 = SIMD4<Float>(0, 0, 0, 0); var x2 = SIMD4<Float>(0, 0, 0, 0) }

let device = MTLCreateSystemDefaultDevice()!
let lib = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
let pso = try! device.makeComputePipelineState(function: lib.makeFunction(name: "render")!)
let brightPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "bright")!)
let blurPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "blur")!)
let composePSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "compose")!)
func tex(_ f: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)!
}
let hdrTex = tex(.rgba16Float, W, H), bA = tex(.rgba16Float, W / 4, H / 4), bB = tex(.rgba16Float, W / 4, H / 4), outTex = tex(.rgba8Unorm, W, H)
let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared)!
var lastMs = 0.0

func render(unfurl u: Float, time t: Float) {
    // unfurl: the spiral loosens (b grows) and its outer end unrolls
    let b = envF("B", 0.11) + envF("B_O", 0.45) * u
    var p = Params(sp: [envF("R0", 1.0), b, envF("K", 0.085), envF("PHI0", Float.pi * 1.05)],
                   rim: [envF("RIMS", 0.05), envF("RIMD", 0.55), envF("DEPTH", 0.3), envF("RIMLEAN", 3.5)],
                   cam: [envF("CX", -0.3), envF("CY", -0.3), envF("VIEW", 1.25), envF("PERSP", 0.15)],
                   lit: [envF("CORE", 2.4), envF("IRID", 0.5), envF("SPARK", 0.9), envF("GLOW", 0.08)],
                   stalk: [envF("SBX", -0.6), envF("SBY", -2.1), envF("SBEND", 1.0), envF("SGROW", 0.8)],
                   misc: [t, envF("KW", 0.4), envF("KT", 0.07), envF("LEAFN", 6)], misc2: [envF("NPIN", 12), envF("PINS", 0.38), envF("PINB", 0.18), envF("STALKR", 1.0)])
    p.q.x = envF("SS", 4); p.q.y = envF("MIRS", 1); p.q.z = envF("OSC", 0.35); p.q.w = envF("OSP", 0.3)
    p.stalk2 = [envF("STB", 0.6), envF("STW", 0.7), envF("STL", 1.5), envF("ND", 0.7)]
    p.x2 = [envF("SL", 0.3), envF("LW", 0.45), 0, 0]
    let cb = queue.makeCommandBuffer()!, ce = cb.makeComputeCommandEncoder()!
    let full = MTLSize(width: W, height: H, depth: 1), quarter = MTLSize(width: W / 4, height: H / 4, depth: 1), tg = MTLSize(width: 16, height: 16, depth: 1)
    ce.setComputePipelineState(pso); ce.setBytes(&p, length: MemoryLayout<Params>.stride, index: 0); ce.setTexture(hdrTex, index: 0)
    ce.dispatchThreads(full, threadsPerThreadgroup: tg)
    ce.setComputePipelineState(brightPSO); ce.setTexture(hdrTex, index: 0); ce.setTexture(bA, index: 1); ce.dispatchThreads(quarter, threadsPerThreadgroup: tg)
    var dh = SIMD2<Int32>(1, 0), dv = SIMD2<Int32>(0, 1)
    ce.setComputePipelineState(blurPSO)
    ce.setTexture(bA, index: 0); ce.setTexture(bB, index: 1); ce.setBytes(&dh, length: 8, index: 0); ce.dispatchThreads(quarter, threadsPerThreadgroup: tg)
    ce.setTexture(bB, index: 0); ce.setTexture(bA, index: 1); ce.setBytes(&dv, length: 8, index: 0); ce.dispatchThreads(quarter, threadsPerThreadgroup: tg)
    var g = SIMD4<Float>(envF("BLOOM", 2.0), envF("SATL", 1.5), 0, 0)
    ce.setComputePipelineState(composePSO); ce.setTexture(hdrTex, index: 0); ce.setTexture(bA, index: 1); ce.setTexture(outTex, index: 2)
    ce.setBytes(&g, length: 16, index: 0); ce.dispatchThreads(full, threadsPerThreadgroup: tg)
    ce.endEncoding()
    let bb = cb.makeBlitCommandEncoder()!
    bb.copy(from: outTex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: W, height: H, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: W * 4, destinationBytesPerImage: W * H * 4)
    bb.endEncoding()
    cb.commit(); cb.waitUntilCompleted()
    lastMs = (cb.gpuEndTime - cb.gpuStartTime) * 1000
}

func writePNG(_ path: String) {
    let ctx = CGContext(data: readback.contents(), width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, ctx.makeImage()!, nil); CGImageDestinationFinalize(dst)
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "still":
    render(unfurl: Float(args[2])!, time: 1); render(unfurl: Float(args[2])!, time: 1)
    FileHandle.standardError.write(String(format: "gpu %.1f ms\n", lastMs).data(using: .utf8)!)
    writePNG(args[3])
default:
    print("usage: fernsdf still <unfurl> <out.png>")
}
