// flexi_ifs.swift — FH.7 look-spike (throwaway; not engine code).
//
// Flexi's frond ("flexi - fractal seafood", Milkdrop 2; the three maps and constants as ported VERBATIM in
// UzumeEngine/Sources/Presets/Shaders/Understory.metal), drawn CRISP: instead of Flexi's feedback texture
// (resampled every frame → the fine levels smear, FH.1), the same three maps run as a chaos game on the GPU.
//
// Flexi composites by MAX with a per-generation fade (density = max(won − 0.015, 0)) over an additive cone
// seed, so a pixel's brightness is (seed cone − 0.015 · generations) of the SHORTEST path that reaches it.
// Here every walker restarts from a random seed point, applies random forward maps (the inverses of Flexi's
// pull maps) and atomic-maxes (brightness, age) per pixel — the same image, point-exact.
//
// Forward maps in Flexi's 4:3 frame coordinates X (x ∈ ±0.5, y ∈ ±0.375, seed at 0; +y points DOWN the screen —
// texture uv — so the frond grows UP from its seed; drawing +y up turned it upside down):
//   main       X' = R(−ww) (X − t_m) / 1.12        t_m = 0.042 (sin w, cos w)
//   left/right X' = R(∓π/4) (X − t_s) / 3.3        t_s = (0.08 sin w, 0.045 cos w)
// with ww = curl (Understory: 0 open … ~0.45 a one-turn fiddlehead) and w = −5·ww (Understory's heading).
//
// Build:  swiftc -O -swift-version 5 flexi_ifs.swift -o flexiifs
// Usage:  flexiifs still <unfurl 0…1> <out.png>   |   flexiifs film <seconds> <out.mp4>   (env vars = knobs)

import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let env = ProcessInfo.processInfo.environment
func envF(_ k: String, _ d: Float) -> Float { env[k].flatMap(Float.init) ?? d }
let W = Int(envF("W", 1672)), H = Int(envF("H", 941))

// MARK: - Shaders

let msl = """
#include <metal_stdlib>
using namespace metal;

struct P { float ww; float w; float scale; float mirror; float2 centre; int iters; uint seed; float4 tone; float4 sd; float4 ext;
           float4 hue; float4 sv; float4 core; float4 fp; float4 uf; float4 uf2; float4 mo; float4 wave; float4 fg; float4 pulse; float4 pl2; float4 lf; };
// lf: leaflet primitive — length (× chain size), width (× length), samples per leaf, curl-in openness threshold
// sd: seed half-width, side scale, side angle, —   ext: —, stipe length (segments), stipe share, display turn
// hue: hue per nesting level 0..3+   sv: sat, rim level   core: warm light (screen x, y, radius px, gain)
// uf: unfurl u, joints to open (JN), front half-width (joints), child lag (joints)
// uf2: curl closed (KAPPA), curl open, per-branch timing jitter (u units), attach point along the joint (0..1)
// mo: time, global sway (rad), per-branch sway (rad), —   wave: travelling bend amplitude (rad), speed (rad/s), joints per radian, —
// fg: near-focus foreground coils (scale px/unit, coil-eye x, y in frame units, brightness)   pulse: seconds since the last 4 beats
// pl2: pulse speed (generations/s), width (generations), gain, —

static uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16; return x; }
static float rnd(thread uint& s) { s = hash(s); return float(s) * (1.0 / 4294967296.0); }
static float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(v.x * c - v.y * s, v.x * s + v.y * c); }
static float2x2 rotm(float a) { float c = cos(a), s = sin(a); return float2x2(float2(c, s), float2(-s, c)); }

// Curl of joint j (1 = the chain's base) of a chain whose own unfurl is ul: the chain unrolls from its BASE up — a
// front at F sweeps tipward; joints behind it are open, ahead of it still coiled (a real fiddlehead's unrolling).
// The front moves at constant LENGTH, not constant joints: joints shrink ×1/1.12 each, so a joint-linear front had opened
// 72 % of the frond by mid-unfurl.
static float frontAt(float ul, constant P& p) {
    float L = 1.0 - pow(1.0 / 1.12, p.uf.y);
    return -p.uf.z + (p.uf.y + 2.0 * p.uf.z) * log(1.0 - pow(ul, 0.7) * L) / (p.uf.y * -0.1133287);   // u^0.7: 0…0.25 was dead
}
static float curlAt(float ul, float j, constant P& p) {
    float W = p.uf.z, F = frontAt(ul, p);
    return mix(p.uf2.x, p.uf2.y, 1.0 - smoothstep(F - W, F + W, j));
}

// Flexi's frond built OUTER-FIRST: each walk composes T = T ∘ map from the top-level frond inward, so every map knows
// where it sits — joint j of its chain, nesting level, which branch — and its curl can vary along the chain and per
// branch (a plain IFS shares ONE curl everywhere: everything curled in lockstep, "mechanical"). Each depth plots the
// seed piece of the current joint through T: a log-spiral arc of that joint's own curl (the main map's continuous flow),
// so stalks stay smooth. A side branch is attached exactly ON its parent's arc (Flexi's offsets floated it off).
kernel void chaos(device atomic_uint* img [[buffer(0)]], constant P& p [[buffer(1)]], device atomic_uint* bg [[buffer(2)]],
                  constant float4* jt [[buffer(3)]], uint gid [[thread_position_in_grid]]) {
    uint s = hash(gid * 9781u + p.seed);
    const float lam = 1.0 / 1.12, ln = -0.1133287;                   // ln(1/1.12)
    float ss = p.sd.y, pm = 0.797 / (0.797 + 2.0 / (ss * ss));       // area-weighted picks
    int i = 0;
    while (i < p.iters) {
        float2x2 A = float2x2(1.0); float2 T = 0.0;
        int lvl = 0, run = 0, n = 0, side0 = 0, j0 = 0; float ul = p.uf.x; uint bh = 0x2545u; bool leafy = false;
        float F = frontAt(ul, p), swb = p.mo.y + p.mo.z * sin(p.mo.x * 1.3), ph = 0.0;   // per chain: front, sway, wave phase
        for (; i < p.iters; i++) {
            // the current chain's next joint: its curl, then Flexi's main map λR(X − tm) (heading w = −5·ww) and its fixed
            // point C, from a table over ww (built on the CPU: this was most of the cost)
            // + a bending wave travelling up each chain (the frond sways like a plant, not a hinge)
            float ww = mix(p.uf2.x, p.uf2.y, 1.0 - smoothstep(F - p.uf.z, F + p.uf.z, float(run) + 1.0)) + swb
                     + p.wave.x * (lvl < 2 ? 1.0 : 0.15) * sin(p.mo.x * p.wave.y - (float(run) + 1.0) / p.wave.z + ph);   // leaflets keep an even herringbone
            float fi = clamp((ww + 0.4) / 1.8, 0.0, 1.0) * 511.0; int k0 = min(int(fi), 510); float fr = fi - float(k0);
            float4 m4 = mix(jt[2 * k0], jt[2 * k0 + 2], fr), tc = mix(jt[2 * k0 + 1], jt[2 * k0 + 3], fr);
            float2x2 M = float2x2(m4.xy, m4.zw); float2 tmv = tc.xy, C = tc.zw;
            // LEAFLET PRIMITIVE (curled pinnae, Matt: "smooth when curled"): a sub-leaflet of a curled pinna is stamped as ONE
            // filled lance — serrated margin, bright rim, lime → amber base to tip — placed and turned by the same maps, its
            // AREA sampled (the fractal skeleton inside a few-pixel leaflet rendered as needles/moss at any point count).
            if (leafy) {
                float2 t0 = normalize(ln * (-C) - ww * float2(C.y, -C.x)), nm = float2(-t0.y, t0.x);
                float L = length(C) * p.lf.x;
                for (int k = 0; k < int(p.lf.z) && i < p.iters; k++, i++) {
                    float uu = rnd(s), vv = rnd(s) * 2.0 - 1.0;
                    float wdt = p.lf.y * L * sqrt(4.0 * uu * (1.0 - uu)) * pow(1.0 - uu, 0.8) * (0.8 + 0.2 * abs(sin(uu * 21.99)));   // broad base, POINTED tip
                    float2 lp = rot(t0 * uu * L + nm * vv * wdt, 0.35 * uu * uu);
                    float2 x = A * lp + T, q = (rot(float2(x.x * p.mirror, -x.y), p.ext.w) - p.centre) * p.scale + float2(\(W / 2).0 + p.wave.w, \(H / 2).0);
                    float b = (0.8 + 0.2 * (1.0 - abs(vv))) - 0.015 * float(n);   // opaque: a leaf's body outshines the rims of leaves behind it
                    if (b > 0.0 && q.x >= 0.0 && q.y >= 0.0 && q.x < \(W).0 && q.y < \(H).0) {
                        uint idx = uint(\(H).0 - 1.0 - q.y) * \(W)u + uint(q.x);
                        atomic_fetch_max_explicit(&img[idx], (uint(b * 4095.0) << 20) | (uint(min(j0, 127)) << 13) | (uint(min(lvl, 15)) << 9) | (uint(uu < 0.8 ? int(uu * 5.0) : 8) << 3) | (uint(side0) << 2), memory_order_relaxed);
                    }
                }
                break;
            }
            // seed piece: the arc from this joint to the next (a ∈ [0,1]); the frond's own base continues as a stipe
            bool stipe = n == 0 && rnd(s) < p.ext.z;
            float a = stipe ? -rnd(s) * p.ext.y : rnd(s), l = rnd(s) * 2.0 - 1.0;
            float aa = max(a, 0.0), g = exp(ln * aa);
            float2 rv = rot(-C, -aa * ww), pos = C + g * rv, tn = g * (ln * rv - ww * float2(-rv.y, rv.x));
            float2 d = normalize(tn); pos += d * length(tn) * (a - aa);
            // leaf TISSUE: at leaflet depth the repeated piece is a filled lens-shaped blade (half-width ∝ sin πa, in units of
            // the segment's length), so a chain of them is a row of overlapping leaflets — lines alone read as filigree
            float lance = pow(sin(3.14159 * aa), 0.7) * (1.0 - 0.6 * aa) * (0.72 + 0.28 * abs(sin(9.42478 * aa)));   // pointed, toothed
            // curled, a pinna is ONE smooth leaf: its own chain drawn as a blade, thinning back to a line as it opens (Matt)
            // one CONSTANT local width along the pinna's chain = a single smooth stroke that tapers with the chain itself
            // (a lens per segment drew facets: ivy/stained-glass shards)
            float bw = (lvl == 1 && a >= 0.0) ? p.fp.w * smoothstep(0.5, 0.15, ul) * length(C) * 0.06 * smoothstep(0.0, 1.2, float(run) + aa) : 0.0;   // only strongly curled pinnae; base tapers
            float hw = bw > p.sd.x ? bw : p.sd.x * (lvl == 0 ? p.sd.w : 1.0);
            float2 x = A * (pos + float2(-d.y, d.x) * l * hw * min(g, 1.0)) + T;
            float cc = lvl == 0 ? 1.0 - pow(abs(l), 4.0) : (bw > p.sd.x) ? 0.3 : 1.0 - abs(l);   // stalk flat; the blade is only a faint under-glow — the leaf is its sub-leaflets
            float b = (stipe ? cc * smoothstep(-p.ext.y, -0.5 * p.ext.y, a) * p.tone.w : cc) * (lvl == 0 ? 0.6 : 1.0) - 0.015 * float(n);   // stalk loses the max to leaves: drawn behind
            if (b > 0.0) {
                float2 q = (rot(float2(x.x * p.mirror, -x.y), p.ext.w) - p.centre) * p.scale + float2(\(W / 2).0 + p.wave.w, \(H / 2).0);
                if (q.x >= 0.0 && q.y >= 0.0 && q.x < \(W).0 && q.y < \(H).0) {
                    // packed: brightness 12 | stalk joint the point hangs from 7 | level 4 | joint along its own chain 6 | side 1
                    uint idx = uint(\(H).0 - 1.0 - q.y) * \(W)u + uint(q.x);
                    atomic_fetch_max_explicit(&img[idx], (uint(b * 4095.0) << 20) | (uint(min(lvl == 0 ? run : j0, 127)) << 13) | (uint(min(lvl, 15)) << 9) | (uint(min(run, 63)) << 3) | (uint(side0) << 2) | (bw > p.sd.x ? 2u : 0u), memory_order_relaxed);   // bit 1: blade pixel
                }
            }
            if (n >= 66) { i++; break; }                                // Flexi's fade has reached zero
            float u = rnd(s);
            if (u < pm) { T = A * tmv + T; A = A * M; run++; }          // main arm: X' = λR(X − tm)
            else {                                                     // side branch, attached ON this joint's arc
                float sg = u < pm + 0.5 * (1.0 - pm) ? -1.0 : 1.0, a0 = p.uf2.w, pul = ul;   // pul: the parent chain's openness
                float2 att = C + exp(ln * a0) * rot(-C, -a0 * ww);
                // OUTB: while coiled, one side's pinnae swing further out, studding the coil's outer rim (reference)
                float ang = lvl >= 1 ? mix(0.45, p.sd.z, ul) : p.sd.z + (sg == p.sv.w ? p.fp.z * (1.0 - smoothstep(0.0, 0.6, ul)) : 0.0);   // sub-leaflets of a curled pinna lie tight along it
                // 3-D FOLD: a rolled pinna also folds out of the picture plane, over the coil's side. Drawn flat, each rolled
                // pinna showed its whole circle (a wheel/rosette); tilted by φ about the parent stalk's direction at the
                // attachment, it projects squashed along the stalk — elongated, lying along the coil, overlapping like scales.
                // φ grows as the parent closes (open = flat), so the fern unfolds in depth as it unfurls.
                float2 rva = rot(-C, -a0 * ww), dt = normalize(ln * rva - ww * float2(-rva.y, rva.x));
                float cphi = cos(p.pl2.w * (1.0 - ul));
                float2x2 Rt = float2x2(dt, float2(-dt.y, dt.x)), Fold = Rt * float2x2(float2(1.0, 0.0), float2(0.0, cphi)) * transpose(Rt);
                // bilateral symmetry: the left pinna is the MIRROR of the right about the parent stalk (Flexi rotates one chiral
                // frond both ways, so one side curled away and the other hugged the stalk — the frond looked lopsided)
                float2x2 Refl = Rt * float2x2(float2(1.0, 0.0), float2(0.0, -1.0)) * transpose(Rt);
                // sub-leaflets of a curled pinna are a small FRINGE on the leaf's edge; full size again as the pinna opens
                float sc = lvl >= 1 ? ss * mix(p.ext.x, 1.0, ul) : mix(ss, p.fp.y, ul);   // pinnae: big when curled (pack the coil), smaller when open (keep its gaps)
                T = A * att + T; float ms = p.fp.x > 1.5 ? 1.0 : -1.0;   // which side is the mirror image (MIRRORSIDE 1: left, 2: right)
                A = (p.fp.x > 0.5 && sg == ms) ? A * Refl * Fold * (rotm(ms * ang) / sc) : A * Fold * (rotm(-sg * ang) / sc);
                // the branch opens after the parent's front passes its joint, each branch on its own schedule
                bh = hash(bh ^ (uint(run) * 2u + (sg > 0.0 ? 1u : 0u) + 0x9e37u * uint(lvl + 1)));
                if (lvl == 0) { side0 = sg > 0.0 ? 1 : 0; j0 = run; }
                ph = float(bh & 1023u) * 0.00614;                     // each branch sways on its own phase
                ul = clamp((F - float(run) - a0) / p.uf.w + p.uf2.z * ul * (float(bh & 1023u) / 1023.0 - 0.5), p.mo.w, 1.0);   // jitter ∝ parent's openness; floor: even closed, a pinna is a leaf (straight base, curled tip), not a wheel
                if (lvl >= 1) { ul = max(ul, 0.85); }      // ...and stay nearly straight: a serrated row, not curl glyphs
                // crossfade by a FIXED per-leaflet threshold (branch hash), so each leaflet switches once as its pinna opens —
                // a per-path random draw flickered leaves in and out every frame near the threshold
                leafy = lvl == 1 && float(hash(bh ^ 0x51edu) & 1023u) / 1023.0 < smoothstep(p.lf.w + 0.2, p.lf.w - 0.2, pul);
                F = frontAt(ul, p); swb = p.mo.y + p.mo.z * sin(p.mo.x * 1.3 + float(bh & 1023u) * 0.0061);
                lvl++; run = 0;
            }
            n++;
        }
    }
}

static float3 palette(float c) {
    // gold stalk → green/emerald tissue → teal → violet tips
    const float3 k[5] = { float3(0.95, 0.65, 0.20), float3(0.35, 0.75, 0.15), float3(0.10, 0.70, 0.35),
                          float3(0.10, 0.65, 0.75), float3(0.65, 0.35, 0.95) };
    float x = clamp(c, 0.0, 1.0) * 4.0; int i = min(int(x), 3);
    return mix(k[i], k[i + 1], fract(x));
}

static float3 hsv2rgb(float h, float s, float v) {
    float3 k = clamp(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0);
    return v * mix(float3(1.0), k, s);
}

kernel void tone(device const uint* img [[buffer(0)]], constant P& p [[buffer(1)]],
                 texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    uint v = img[gid.y * \(W)u + gid.x];
    float b = float(v >> 20) / 4095.0, j0 = float((v >> 13) & 127u);   // j0: the stalk joint this point hangs from
    uint lvl = (v >> 9) & 15u, run = (v >> 3) & 63u, side = (v >> 2) & 1u;
    // The reference's psychedelic palette shifts ALONG each chain: lime at a pinna's base → gold → orange → violet/pink at
    // its crozier tip; the stalk gold; the deepest copies' tips (the lobe rims) cyan or violet; left pinnae lean cyan,
    // right lean orange.
    float t = clamp(float(run) / p.sv.z, 0.0, 1.0), h;
    if (lvl == 0u) { h = p.hue.x; }
    else {
        h = t < 0.6 ? mix(0.32, 0.27, t / 0.6) : mix(0.27, 0.08, (t - 0.6) / 0.4);   // emerald body → lime → amber toward the tip
        h += side == 1u ? -0.015 : 0.02;
        if (float(lvl) >= p.sv.y && t > 0.7) { h = side == 1u ? 0.86 : 0.78; }   // thin pink/violet accents on the deepest tips
    }
    // veins (stalk + pinna rachis lines, not blades) brighter, fine leaflet tissue a little darker: open fronds get structure
    float vein = (lvl <= 1u && (v & 2u) == 0u) ? p.tone.x / 30.0 : (lvl >= 2u ? 0.8 : 1.0);   // tone.x (was AGESPAN) = 30 × vein gain
    float3 col = hsv2rgb(fract(h + 1.0), p.sv.x, 1.0) * pow(b, p.tone.y) * p.tone.z * (lvl == 0u ? p.tone.w : 1.0) * vein;
    // light flowing along: each beat launches a pulse from the base that travels out through every chain (age = generations)
    float pl = 0.0;
    for (int k = 0; k < 4; k++) {
        float e = p.pulse[k];
        // veins only: the stalk (level 0) and each pinna's rachis (level 1)
        if (e >= 0.0 && (v & 2u) == 0u && lvl <= 1u) { float z = (j0 + 0.35 * float(lvl == 0u ? 0u : run) - p.pl2.x * e) / p.pl2.y; pl += exp(-z * z) * exp(-e / 3.0); }
    }
    col += float3(1.0, 0.95, 0.82) * pl * p.pl2.z * b;
    // warm light AT THE TIP: points hanging from the stalk's last joints (the coil's eye) emit amber; the glow pass blooms
    // it. Attached to the structure, it follows the tip however hard the frond moves (a CPU-placed glow lagged the sway).
    float tip = smoothstep(p.core.z - 3.0, p.core.z + 3.0, j0);
    col = mix(col, float3(1.0, 0.55, 0.18) * pow(b, p.tone.y) * p.tone.z, 0.7 * tip) + float3(1.0, 0.5, 0.15) * p.core.w * tip * b;
    out.write(float4(col, b), gid);
}

constexpr sampler lin(filter::linear, address::clamp_to_zero);

// The ghost layer, blurred wide at quarter resolution (≈ 40 px at full resolution): out-of-focus ferns.
// The whole background at QUARTER resolution (it is soft by nature; per full-res pixel it cost ~80 M disc tests a frame):
// to the measured reference brief — a near-black forest night (top cooler and darkest), faint far TRUNKS, midground fern
// silhouettes (the ghost layer blurred ≈ 1.5 % of width, dim teal left → violet right), and 50 dim coloured bokeh discs in
// the middle band on the left and right thirds. Values are reference output RGB taken back through the final tone curve.
kernel void bgblur(device const uint* bg [[buffer(0)]], constant float4& t [[buffer(1)]], texture2d<float, access::write> out [[texture(0)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W / 4)u || gid.y >= \(H / 4)u) { return; }
    float2 sz = float2(\(W).0, \(H).0), px = (float2(gid) + 0.5) * 4.0, uv = px / sz;
    float3 back = mix(float3(0.003, 0.003, 0.002), float3(0.0005, 0.002, 0.005), smoothstep(0.0, 0.5, uv.y));
    back = mix(back, float3(0.001, 0.001, 0.001), smoothstep(0.6, 1.0, uv.y));
    for (int k = 0; k < 6; k++) {                                 // far trunks: very faint, irregular soft verticals
        uint hk = hash(uint(k) * 3001u + 7u); float xk = float(hk & 1023u) / 1023.0, wk = 0.008 + 0.03 * float((hk >> 10) & 255u) / 255.0;
        float z = (uv.x - xk - 0.01 * sin(uv.y * 9.0 + float(k))) / wk, amp = 0.3 + 0.7 * float((hk >> 18) & 255u) / 255.0;
        back += float3(0.007, 0.008, 0.007) * amp * exp(-z * z) * smoothstep(0.75, 0.1, uv.y) * (0.6 + 0.4 * sin(uv.y * 23.0 + float(k) * 3.0));
    }
    const float3 bkc[4] = { float3(80, 150, 160), float3(120, 80, 170), float3(200, 140, 70), float3(110, 160, 80) };
    for (int k = 0; k < 16; k++) {                                // bokeh: few, large, soft (3–7 % of width), 15–35 % opacity
        uint hk = hash(uint(k) * 7919u + 13u);
        float fx = float(hk & 1023u) / 1023.0, bx = fx < 0.5 ? fx * 0.66 : 0.34 + fx * 0.66;   // left and right thirds
        float2 cpos = float2(bx, 0.30 + 0.50 * float((hk >> 10) & 1023u) / 1023.0) * sz
                    + 25.0 * float2(sin(t.x * 0.05 + float(k)), cos(t.x * 0.04 + float(k) * 1.7));
        float rad = sz.x * (0.015 + 0.02 * float((hk >> 20) & 255u) / 255.0), dd = length(px - cpos) / rad;
        float disc = smoothstep(1.0, 0.6, dd) * (0.8 + 0.2 * smoothstep(0.5, 0.9, dd));
        float op = 0.15 + 0.20 * float((hk >> 28) & 15u) / 15.0;
        back += pow(bkc[hk % 4u] / 255.0 * op, float3(1.8)) * disc * t.w;
    }
    out.write(float4(back, 1.0), gid);
}

kernel void glow(texture2d<float> src [[texture(0)]], texture2d<float, access::write> out [[texture(1)]], texture2d<float> bgt [[texture(2)]],
                 constant float4& g [[buffer(0)]], constant float4& t [[buffer(1)]], constant float4& rm [[buffer(2)]], device const uint* img [[buffer(3)]],
                 uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    float2 sz = float2(\(W).0, \(H).0), uv = (float2(gid) + 0.5) / sz;
    float4 c0 = src.read(gid); float3 c = c0.rgb, b = float3(0.0); float wsum = 0.0, cov = 0.0;
    for (int j = -3; j <= 3; j++) for (int i = -3; i <= 3; i++) {
        float w = exp(-float(i * i + j * j) / 6.0);
        float4 s = src.sample(lin, uv + float2(i, j) * g.x / sz);
        b += s.rgb * w; cov += step(0.12, s.a) * w; wsum += w;
    }
    cov /= wsum;                                                 // local fill: 1 deep inside a blade, ~0.5 on its rim
    // Coherent colour zones: keep this pixel's brightness, take its hue from the neighbourhood (max-composited paths
    // differ pixel to pixel — per-point hues averaged to mud).
    // (tight 3×3 at 1 px: a wide neighbourhood averaged green and orange zones to beige)
    const float3 Y = float3(0.299, 0.587, 0.114); float3 hb = 0.0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) { hb += src.read(uint2(clamp(int2(gid) + int2(i, j), int2(0), int2(\(W - 1), \(H - 1))))).rgb; }
    float Lb = dot(hb, Y);
    if (Lb > 1e-4) { c = hb * (dot(c, Y) / Lb); }
    c *= mix(1.0, g.z, smoothstep(0.55, 0.95, cov)) * (1.0 + g.w * 4.0 * cov * (1.0 - cov));   // dark interiors, glowing rims
    // LEAFLET OUTLINES: each pixel knows which pinna it belongs to (stalk joint + side). Where a lit neighbour belongs to a
    // different pinna, this is a leaflet boundary: a crisp bright edge, so packed pinnae read as discrete leaflets.
    uint v0 = img[gid.y * \(W)u + gid.x], id0 = ((v0 >> 13) & 127u) * 2u + ((v0 >> 2) & 1u); float edge = 0.0;
    if ((v0 >> 20) > 200u && ((v0 >> 9) & 15u) == 1u) {   // whole pinnae only: leaflet outlines drew pale lines through the leaves
        for (int k = 0; k < 4; k++) {
            int2 o = int2(gid) + int2(k == 0 ? 1 : k == 1 ? -1 : 0, k == 2 ? 1 : k == 3 ? -1 : 0);
            if (o.x < 0 || o.y < 0 || o.x >= \(W) || o.y >= \(H)) { continue; }
            uint vn = img[uint(o.y) * \(W)u + uint(o.x)];
            if ((vn >> 20) > 200u && ((vn >> 9) & 15u) == 1u && ((vn >> 13) & 127u) * 2u + ((vn >> 2) & 1u) != id0) { edge = 1.0; }
        }
    }
    c = mix(c, c * 1.6 + float3(0.55, 0.75, 0.35) * rm.z * c0.a, edge);
    // (no amber edge light: amber + green bodies mixed to yellow — the reference keeps them as separate zones)
    // sparkle beads ALONG THE RIMS (reference: hundreds of 1–3 px white-to-orange beads on every edge), ~10 Hz twinkle
    uint h = hash(gid.x * 7919u + gid.y * 104729u + uint(t.x * 60.0) / 6u); float rimw = 4.0 * cov * (1.0 - cov);
    float r1 = rnd(h), r2 = rnd(h);
    c += (r1 < t.y * 6.0 * smoothstep(0.5, 0.9, rimw) && c0.a > 0.2) ? mix(float3(1.0, 0.95, 0.85), float3(1.0, 0.55, 0.15), r2) * t.z * c0.a : float3(0.0);
    c += b / wsum * g.y;
    float3 back = bgt.sample(lin, uv).rgb;                          // the background (built at quarter res in bgblur)
    c += back;
    c = max(mix(float3(dot(c, Y)), c, t.w), 0.0);                 // saturation lift: x/(1+x) washes colour toward white
    c = min(c / (1.0 + dot(c, Y)), 1.0);                          // compress LUMINANCE: per-channel x/(1+x) turned bright orange yellow
    out.write(float4(pow(c, float3(1.0 / 1.8)), 1.0), gid);
}
"""

// MARK: - Flexi's frond

struct Params { var ww: Float; var w: Float; var scale: Float; var mirror: Float; var centre: SIMD2<Float>; var iters: Int32; var seed: UInt32
                var tone: SIMD4<Float>; var sd: SIMD4<Float>; var ext: SIMD4<Float>; var hue: SIMD4<Float>; var sv: SIMD4<Float>; var core: SIMD4<Float>
                var fp = SIMD4<Float>(0, 0, 0, 0); var uf = SIMD4<Float>(0, 0, 0, 0); var uf2 = SIMD4<Float>(0, 0, 0, 0); var mo = SIMD4<Float>(0, 0, 0, 0)
                var wave = SIMD4<Float>(0, 0, 1, 0); var fg = SIMD4<Float>(0, 0, 0, 0); var pulse = SIMD4<Float>(-1, -1, -1, -1); var pl2 = SIMD4<Float>(0, 1, 0, 0)
                var lf = SIMD4<Float>(0, 0, 0, 0) }

var driveSway: Float?, driveSpark: Float?   // per-frame overrides from a music drive (film `drive` mode)
var driveEnergy: Float = 0.5, drivePulses = SIMD4<Float>(-1, -1, -1, -1)   // music intensity 0…1; seconds since the last 4 beats
var fixedFrame: (SIMD2<Float>, SIMD2<Float>)?

let KAPPA = envF("KAPPA", 0.75), KAPPA_O = envF("KAPPA_O", 0.03), JN = envF("JN", 22), WFRONT = envF("WFRONT", 3), LAGJ = envF("LAGJ", 8)
let JIT = envF("JIT", 0.6), ATTACH = envF("ATTACH", 0.4), SIDE = envF("SIDE", 2.6), ANG = envF("ANG", .pi / 4)

/// Whole-frond sway: a slow wind that never stops, plus the bass pushing it (drive).
func sway(_ t: Float) -> Float { envF("WIND", 0.05) * (sin(t * 0.45) + 0.6 * sin(t * 1.1 + 1.0)) + (driveSway ?? 0) }

/// = the kernel's curlAt: joint j (1 = base) of a chain with unfurl ul; the front sweeps from the base tipward.
func frontAt(_ ul: Float) -> Float {   // = the kernel's: constant-length front
    let L = 1 - pow(1 / 1.12, JN); return -WFRONT + (JN + 2 * WFRONT) * log(1 - pow(ul, 0.7) * L) / (JN * -0.1133287)
}
func curlAt(_ ul: Float, _ j: Float) -> Float {
    let F = frontAt(ul), x = min(max((j - (F - WFRONT)) / (2 * WFRONT), 0), 1)
    return KAPPA + (KAPPA_O - KAPPA) * (1 - x * x * (3 - 2 * x))
}

func rot(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> { SIMD2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)) }
func rotm(_ a: Float) -> simd_float2x2 { simd_float2x2(columns: (SIMD2(cos(a), sin(a)), SIMD2(-sin(a), cos(a)))) }

/// One joint of a chain: Flexi's main map λR(X − tm) for curl ww, and its fixed point.
func joint(_ ww: Float) -> (M: simd_float2x2, t: SIMD2<Float>, C: SIMD2<Float>) {
    let w = -5 * ww, tm = 0.042 * SIMD2<Float>(sin(w), cos(w)), M = (1 / 1.12) * rotm(-ww)
    let t = -(M * tm), C = (matrix_identity_float2x2 - M).inverse * t
    return (M, t, C)
}

/// CPU mirror of the kernel's outer-first walk (joint points only), for framing: display-space bbox.
func extent(u: Float, t: Float, theta: Float) -> (SIMD2<Float>, SIMD2<Float>) {
    let pm: Float = 0.797 / (0.797 + 2 / (SIDE * SIDE)), mir = envF("MIRROR", 1)
    var lo = SIMD2<Float>(repeating: 9), hi = SIMD2<Float>(repeating: -9)
    var rng: UInt64 = 0x9E3779B97F4A7C15   // deterministic: the same bounds for the same frond (a random sample jittered the camera)
    func r01() -> Float { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Float(rng >> 40) / Float(1 << 24) }
    for _ in 0..<5000 {
        var A = matrix_identity_float2x2, T = SIMD2<Float>(0, 0), run: Float = 0, ul = u, lvl = 0, ph: Float = 0
        let wa = envF("WAVEA", 0.035) * (0.5 + driveEnergy), wsp = envF("WAVES", 1.6), wj = envF("WAVEJ", 3.0)
        for n in 0..<60 {
            let j = joint(curlAt(ul, run + 1) + sway(t) + wa * sin(t * wsp - (run + 1) / wj + ph))   // = the kernel's bending wave
            // frame the LEAVES (level ≥ 1): the bare stalk below the coil may run off the bottom, as in the reference
            if lvl >= 1 && 1 - 0.015 * Float(n) > envF("EXTB", 0.35) { let q = rot(SIMD2(T.x * mir, -T.y), theta); lo = simd_min(lo, q); hi = simd_max(hi, q) }
            let x = r01()
            if x < pm { T = A * j.t + T; A = A * j.M; run += 1 } else {
                let sg: Float = x < pm + (1 - pm) / 2 ? -1 : 1, g = exp(-0.1133287 * ATTACH)
                T = A * (j.C + g * rot(-j.C, -ATTACH * curlAt(ul, run + 1))) + T; A = A * ((1 / SIDE) * rotm(-sg * ANG))
                let F = frontAt(ul); ul = min(max((F - run - ATTACH) / LAGJ, 0), 1); run = 0; lvl += 1; ph = r01() * 6.283
            }
        }
    }
    let pad = 0.04 * simd_reduce_max(hi - lo)   // proportional: a fixed 0.03 was 40 % of a coiled frond's height
    return (lo - pad, hi + pad + SIMD2(0, 0.05 * (hi.y - lo.y)))   // + headroom where the tip swings (branch sway phases are hashed on the GPU)
}

/// Upright turn: the stipe (−x1 of the base joint) points straight down the screen.
func uprightTheta(_ u: Float, _ t: Float) -> Float {
    let j = joint(curlAt(u, 1) + sway(t)), x1 = j.t, mir = envF("MIRROR", 1)   // x1 = base joint's image of 0
    let sd = SIMD2(-x1.x * mir, x1.y)
    return envF("UPRIGHT", 1) * (-.pi / 2 - atan2(sd.y, sd.x)) + envF("LEAN", 0)
}

// MARK: - Metal

let device = MTLCreateSystemDefaultDevice()!
let lib = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
let chaosPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "chaos")!)
let tonePSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "tone")!)
let glowPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "glow")!)
let bgPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "bgblur")!)
let bgBuf = device.makeBuffer(length: (W / 4) * (H / 4) * 4, options: .storageModePrivate)!
let bgTex: MTLTexture = { let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: W / 4, height: H / 4, mipmapped: false); d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)! }()
let img = device.makeBuffer(length: W * H * 4, options: .storageModePrivate)!
/// Joint table over ww ∈ [−0.4, 1.4] (512 entries): columns of M, then (t, C) — the kernel interpolates.
let jointTable: MTLBuffer = {
    var v: [SIMD4<Float>] = []
    for k in 0..<512 { let j = joint(-0.4 + 1.8 * Float(k) / 511); v += [SIMD4(lowHalf: j.M.columns.0, highHalf: j.M.columns.1), SIMD4(lowHalf: j.t, highHalf: j.C)] }
    return device.makeBuffer(bytes: v, length: v.count * 16, options: .storageModeShared)!
}()
func tex(_ fmt: MTLPixelFormat) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: W, height: H, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)!
}
let hdr = tex(.rgba16Float), outTex = tex(.rgba8Unorm)
let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared)!
var lastMs = 0.0

func render(unfurl u: Float, time t: Float) {
    let theta = uprightTheta(u, t)
    let (lo, hi) = fixedFrame ?? extent(u: u, t: t, theta: theta), fill = envF("FILL", 0.9)   // films: eased frame (no re-framing jitter)
    let scale = min(Float(H) * fill / (hi.y - lo.y), Float(W) * fill / (hi.x - lo.x))
    if envF("DEBUGEXT", 0) > 0 { FileHandle.standardError.write("extent lo \(lo) hi \(hi) scale \(scale)\n".data(using: .utf8)!) }
    var p = Params(ww: 0, w: 0, scale: scale, mirror: envF("MIRROR", 1), centre: (lo + hi) * 0.5, iters: Int32(envF("ITERS", 280)),
                   seed: 17 /* fixed: same random paths every frame, so detail moves instead of fizzing */, tone: [envF("AGESPAN", 45), envF("GAMMA", 1.4), envF("EXPO", 1.2), envF("STALKB", 1.0)],
                   sd: [envF("SEEDW", 0.002), SIDE, ANG, envF("STALKW", 0.75)],
                   ext: [0, envF("STIPE", 6), envF("PSTIPE", 0.3), theta],
                   hue: [envF("H0", 0.1), envF("H1", 0.13), envF("H2", 0.3), envF("H3", 0.38)], sv: [envF("SAT", 0.85), envF("RIMLVL", 3), 0, 0],
                   core: [0, 0, 0, 0])
    p.uf = [u, JN, WFRONT, LAGJ]; p.uf2 = [KAPPA, KAPPA_O, JIT, ATTACH]; p.mo = [t, sway(t), envF("SWAYB", 0.05), envF("CHILDMIN", 0.15)]
    p.lf = [envF("LEAFLEN", 0.75), envF("LEAFW", 0.4), envF("LEAFS", 24), envF("LEAFT", 0.45)]
    p.sv.z = envF("RUNSPAN", 9); p.sv.w = envF("OUTSG", 1); p.fp.z = envF("OUTB", 0.6); p.fp.w = envF("BLADE", 8); p.ext.x = envF("FRINGE", 1.7); p.fp.y = envF("SIDE_O", 3.6); p.fp.x = envF("MIRRORSIDE", 1)
    p.wave = [envF("WAVEA", 0.035) * (0.5 + driveEnergy), envF("WAVES", 1.6), envF("WAVEJ", 3.0), envF("HEROX", -0.12) * Float(W)]   // .w: hero left of centre (reference)   // bending wave, bigger when loud
    p.pulse = drivePulses; p.pl2 = [envF("PSPEED", 9), envF("PWIDTH", 0.9), envF("PGAIN", 3.75), envF("FOLD", 0.9)]   // .w: pinna fold angle when closed (rad)
    // warm light at the coil's eye: the limit of the top chain's joints
    var A = matrix_identity_float2x2, T = SIMD2<Float>(0, 0)
    for k in 0..<80 { let j = joint(curlAt(u, Float(k) + 1) + sway(t)); T = A * j.t + T; A = A * j.M }
    let fs = (rot(SIMD2(T.x * p.mirror, -T.y), theta) - p.centre) * scale + SIMD2(Float(W / 2) + envF("HEROX", -0.12) * Float(W), Float(H / 2))
    p.core = [fs.x, Float(H) - 1 - fs.y, envF("TIPJ", 14), envF("CORE", 1.2) * (1 - 0.6 * u)]   // .z: stalk joint where the tip glow starts
    let cb = queue.makeCommandBuffer()!
    let bl = cb.makeBlitCommandEncoder()!; bl.fill(buffer: img, range: 0..<img.length, value: 0); bl.fill(buffer: bgBuf, range: 0..<bgBuf.length, value: 0); bl.endEncoding()
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(chaosPSO)
    ce.setBuffer(img, offset: 0, index: 0); ce.setBytes(&p, length: MemoryLayout<Params>.stride, index: 1); ce.setBuffer(bgBuf, offset: 0, index: 2); ce.setBuffer(jointTable, offset: 0, index: 3)
    ce.dispatchThreads(MTLSize(width: Int(envF("THREADS", 65536)), height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    ce.setComputePipelineState(tonePSO)
    ce.setBuffer(img, offset: 0, index: 0); ce.setBytes(&p, length: MemoryLayout<Params>.stride, index: 1); ce.setTexture(hdr, index: 0)
    ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    var bgp = SIMD4<Float>(t, 0, 0, envF("BGI", 1.0))
    ce.setComputePipelineState(bgPSO); ce.setBuffer(bgBuf, offset: 0, index: 0); ce.setBytes(&bgp, length: 16, index: 1); ce.setTexture(bgTex, index: 0)
    ce.dispatchThreads(MTLSize(width: W / 4, height: H / 4, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    ce.setComputePipelineState(glowPSO)
    var gp = SIMD4<Float>(envF("GLOWR", 2.5), envF("GLOW", 0.25), envF("INNER", 0.2), envF("RIM", 1.5))
    var sp = SIMD4<Float>(t, driveSpark ?? envF("SPARK", 0.003), envF("SPARKI", 1.5), envF("SATLIFT", 1.0))
    var rmp = SIMD4<Float>(p.core.x, p.core.y, envF("RIMI", 0.5), envF("BGI", 1.0))
    ce.setTexture(hdr, index: 0); ce.setTexture(outTex, index: 1); ce.setBytes(&gp, length: 16, index: 0); ce.setBytes(&sp, length: 16, index: 1); ce.setBytes(&rmp, length: 16, index: 2); ce.setTexture(bgTex, index: 2); ce.setBuffer(img, offset: 0, index: 3)
    ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
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
    if let pe = env["PULSES"] { let v = pe.split(separator: ",").compactMap { Float($0) }; drivePulses = SIMD4((0..<4).map { $0 < v.count ? v[$0] : -1 }) }
    render(unfurl: Float(args[2])!, time: 1)
    FileHandle.standardError.write(String(format: "gpu %.1f ms, points %.1fM\n", lastMs, envF("THREADS", 65536) * envF("ITERS", 280) / 1e6).data(using: .utf8)!)
    writePNG(args[3])
case "film":
    let secs = Float(args[2])!, fps: Float = 30
    let ff = Process(); ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(W)x\(H)", "-r", "30", "-i", "-",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", args[3]]
    let pipe = Pipe(); ff.standardInput = pipe; try! ff.run()
    var worst = 0.0
    for i in 0..<Int(secs * fps) {
        let t = Float(i) / fps
        render(unfurl: 0.5 - 0.5 * cos(2 * .pi * t / secs), time: t); worst = max(worst, lastMs)
        pipe.fileHandleForWriting.write(Data(bytes: readback.contents(), count: W * H * 4))
    }
    try! pipe.fileHandleForWriting.close(); ff.waitUntilExit()
    FileHandle.standardError.write(String(format: "worst gpu %.1f ms\n", worst).data(using: .utf8)!)
case "drive":   // drive <csv: u,sway,spark per 30 fps frame> <audio> <out.mp4>  — unfurl/sway/sparkle from the music
    let rows = try! String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").map { $0.split(separator: ",").compactMap { Float($0) } }
    let ff = Process(); ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(W)x\(H)", "-r", "30", "-i", "-", "-i", args[3],
                    "-map", "0:v", "-map", "1:a", "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", "-c:a", "aac", args[4]]
    let pipe = Pipe(); ff.standardInput = pipe; try! ff.run()
    let follow = envF("FOLLOW", 1) > 0.5                                // slow camera: frame the frond itself, bounds eased ~1.5 s
    var worst = 0.0, total = 0.0, uS = rows.first?[0] ?? 0, cam: (SIMD2<Float>, SIMD2<Float>)? = nil
    var onsetTimes: [Float] = []
    for (i, r) in rows.enumerated() where r.count >= 3 {
        let umax = envF("UMAX", 0.006)                                  // a fern can't snap open: ≥ ~1.7 s closed → open
        uS += min(max((r[0] - uS) * envF("USLEW", 0.08), -umax), umax)   // ponytail: slew; the engine would use its section envelope
        driveSway = r[1]; driveSpark = r[2]
        if r.count >= 5 {                                               // beats launch light pulses; energy drives the sway wave
            if r[3] > 0.5 { onsetTimes.insert(Float(i) / 30, at: 0); onsetTimes = Array(onsetTimes.prefix(4)) }
            driveEnergy = r[4]
            drivePulses = SIMD4((0..<4).map { $0 < onsetTimes.count ? Float(i) / 30 - onsetTimes[$0] : -1 })
        }
        if follow {
            // frame for where the frond CAN be soon: unfurl speed is capped, so 0.12 ahead (~0.7 s at the cap) is a safe bound —
            // the camera then eases instead of snapping outward when the frond opens fast
            let tt = Float(i) / 30, ua = min(uS + 0.12, 1), e0 = extent(u: uS, t: tt, theta: uprightTheta(uS, tt)), e1 = extent(u: ua, t: tt, theta: uprightTheta(ua, tt))
            let e = (simd_min(e0.0, e1.0), simd_max(e0.1, e1.1))
            // zoom OUT fast (the frond must never outgrow the frame), zoom IN slowly (no pumping); a symmetric 1.5 s ease
            // let an opening frond run off the top in 329 of 897 frames
            func ease(_ c: Float, _ t: Float, grow: Bool) -> Float { c + (t - c) * (grow ? 0.15 : 0.022) }
            cam = cam.map { c in
                (SIMD2(ease(c.0.x, e.0.x, grow: e.0.x < c.0.x), ease(c.0.y, e.0.y, grow: e.0.y < c.0.y)),
                 SIMD2(ease(c.1.x, e.1.x, grow: e.1.x > c.1.x), ease(c.1.y, e.1.y, grow: e.1.y > c.1.y)))
            } ?? e
            fixedFrame = cam
        }
        render(unfurl: uS, time: Float(i) / 30); worst = max(worst, lastMs); total += lastMs
        pipe.fileHandleForWriting.write(Data(bytes: readback.contents(), count: W * H * 4))
    }
    try! pipe.fileHandleForWriting.close(); ff.waitUntilExit()
    FileHandle.standardError.write(String(format: "frames %d, mean gpu %.1f ms, worst %.1f ms\n", rows.count, total / Double(max(rows.count, 1)), worst).data(using: .utf8)!)
default:
    print("usage: flexiifs still <unfurl> <out.png> | flexiifs film <seconds> <out.mp4> | flexiifs drive <csv> <audio> <out.mp4>")
}
