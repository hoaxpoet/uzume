// FH.15 spike — the fiddlehead as a TRUE self-similar fractal, drawn by per-pixel descent, UNFURLING as the camera dives.
//
// Matt: "a deeply intricate pattern … the fractal pattern at different levels of zoom — a staggering amount of detail";
// "the camera is on a continuous zoom into the details of the fern, which reveals the same pattern repeating and
// unfolding"; "the fern should be uncurling as the camera zooms in"; music = "shimmers or rippling waves down the body …
// like a nerve impulse travelling along trunks and branches"; "a vibrant light show. A bath of color".
//
// ONE element — a frond: a stem that runs gently curved, then rolls into a log-spiral crozier, lined on both sides with
// children that are the SAME frond, scaled to the local width. The whole fiddlehead is that element; so is every pinna,
// pinnule, and so on down. Each pixel walks down the tree, at every level stepping into the one child whose region it
// lies in (a precomputed lookup), until the children are smaller than a pixel; there the subtree's silhouette is drawn.
//
// UNFURL: a frond's curl is a function of how big it is ON SCREEN — tiny = tightly rolled, filling the view = open (the
// coil rolls out from the base, the tip last, like a real fiddlehead). As the camera dives, each frond it approaches grows
// and unrolls. Because the curl depends only on on-screen size, the picture one zoom cycle later is the same picture:
// the dive loops forever. Fields are precomputed for NST curl states.
//
//   swiftc -O -swift-version 5 fern_descent.swift -o fernd
//   fernd still <out.png>                 (ZOOMMODE=1 T=<s> for a frame of the dive; DBG=1 plain green fern)
//   fernd video <out.mp4> <seconds>
// ponytail: stand-in music (a synthetic beat) until it is wired to real analysis; offline only.

import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Knobs

let env = ProcessInfo.processInfo.environment
func envF(_ k: String, _ d: Float) -> Float { env[k].flatMap(Float.init) ?? d }
let W = Int(envF("W", 1672)), H = Int(envF("H", 940))
let NS = 768                       // spine samples
let TR = Int(envF("TR", 640))      // lookup texture resolution
let NST = Int(envF("NST", 20))     // curl states (0 = open … NST-1 = tightly rolled)

// shape (all in units of the frond's own length)
let K0 = envF("K0", 0.35)          // gentle bow of the stem part
let ACURL = envF("ACURL", 3.0)     // crozier tightness (log-spiral 1/b)
let SINF = envF("SINF", 1.02)      // where the spiral's eye sits in arc length (>1)
let S0C = envF("S0C", 0.3)         // rolled: where the stem starts rolling
let S0O = envF("S0O", 0.9)         // open: only the very tip still curls
let W0 = envF("W0", 0.006)         // rachis half-width at the base
let CS = envF("CS", 0.34)          // child length at the base (× parent length)
let SP = envF("SP", 0.32)          // child spacing (× child length)
let LEAN = envF("LEAN", 0.55)      // child lean toward the tip (rad off the normal)
let MIR = envF("MIR", 1)           // which side's children are mirrored (curl toward the tip)
let LOPEN = envF("LOPEN", log(0.9))    // log(on-screen length / view height) at which a frond is fully open
let LCURL = envF("LCURL", log(0.05))   // … and fully rolled

// MARK: - Spines and children, per curl state (CPU)

func curlOf(_ i: Int) -> Float { let x = Float(i) / Float(NST - 1); return x * x * (3 - 2 * x) }
func kappa(_ s: Float, _ c: Float) -> Float {
    let s0 = S0O + (S0C - S0O) * c
    let t = min(max((s - (s0 - 0.15)) / 0.3, 0), 1), bl = t * t * (3 - 2 * t)
    return K0 + bl * ACURL / (SINF - s)
}
func buildSpine(_ c: Float) -> ([SIMD2<Float>], [Float]) {
    var p = [SIMD2<Float>](repeating: .zero, count: NS), th = [Float](repeating: 0, count: NS)
    let ds = 1 / Float(NS - 1)
    for i in 1..<NS {
        let s = Float(i - 1) * ds
        th[i] = th[i - 1] + kappa(s + ds * 0.5, c) * ds
        let tm = (th[i - 1] + th[i]) * 0.5
        p[i] = p[i - 1] + SIMD2(cos(tm), sin(tm)) * ds
    }
    return (p, th)
}
func sigma(_ s: Float) -> Float { CS * (SINF - s) / SINF }              // children shrink with the local coil radius
func width(_ s: Float) -> Float { W0 * (1 - 0.85 * s) }

// child sites are the same in every state (fixed arc positions); only where they land moves as the stem unrolls
var sites: [Float] = []
do { var s: Float = 0.05; while s < 0.985 && sites.count < 127 { sites.append(s); s += SP * sigma(s) } }
let NCH = sites.count * 2

struct ChildGPU { var root: SIMD2<Float>; var ang: Float; var scale: Float; var mirror: Float; var s: Float; var shift: Float; var p2: Float = 0 }
var spines: [SIMD2<Float>] = [], chg: [ChildGPU] = []
var bmin = SIMD2<Float>(repeating: 1e9), bmax = SIMD2<Float>(repeating: -1e9)
let stateSpan = LOPEN - LCURL
for i in 0..<NST {
    let (p, th) = buildSpine(curlOf(i))
    spines += p
    for j in 0..<NS {
        let s = Float(j) / Float(NS - 1), r = sigma(s) * 1.6 + 0.03
        bmin = simd_min(bmin, p[j] - SIMD2(r, r)); bmax = simd_max(bmax, p[j] + SIMD2(r, r))
    }
    func at(_ s: Float) -> (SIMD2<Float>, Float) {
        let f = s * Float(NS - 1), k = min(Int(f), NS - 2), u = f - Float(k)
        return (p[k] * (1 - u) + p[k + 1] * u, th[k] * (1 - u) + th[k + 1] * u)
    }
    for s in sites {
        let (P0, t0) = at(s), N = SIMD2<Float>(-sin(t0), cos(t0)), sg = sigma(s)
        let shift = -log(sg) / stateSpan * Float(NST - 1)                 // a child is this many states more rolled
        for side: Float in [1, -1] {
            let mirror: Float = (side > 0) == (MIR > 0) ? 1 : 0
            chg.append(ChildGPU(root: P0 + N * side * width(s) * 0.8, ang: t0 + side * (Float.pi / 2 - LEAN), scale: sg, mirror: mirror, s: s, shift: shift))
        }
    }
}
FileHandle.standardError.write("children \(NCH) × \(NST) states  bbox \(bmin) \(bmax)\n".data(using: .utf8)!)

// MARK: - Shader

struct Params {
    var bmin: SIMD2<Float>; var bmax: SIMD2<Float>
    var cam: SIMD4<Float>          // stills: centre x, y, view half-height, flip
    var top: SIMD4<Float>          // stills: top frond root x, y, angle, length
    var shape: SIMD4<Float>        // W0, CS, SINF, unused
    var misc: SIMD4<Float>         // children per state, max levels, debug, candidate window
    var curl: SIMD4<Float>         // LOPEN, LCURL, zoom on, unused
    var lift: SIMD4<Float>         // zoom: level-0 → lifted ancestor: offset x, y, rotation, scale
    var zc: SIMD4<Float>           // zoom: centre x, y (level-0 frame), view half-height, view rotation
    var tm: SIMD4<Float>           // time, phi of the lifted ancestor's root, unused, pulse count
    var au: SIMD4<Float>           // bass, treble, hue base, unused
}

let msl = """
#include <metal_stdlib>
using namespace metal;

struct Params { float2 bmin; float2 bmax; float4 cam; float4 top; float4 shape; float4 misc; float4 curl; float4 lift; float4 zc; float4 tm; float4 au; };
struct Child { float2 root; float ang; float scale; float mirror; float s; float shift; float pad; };

constant int NCHC = \(NCH);
constant int NSTC = \(NST);
static float width(float s, constant Params& P) { return P.shape.x * (1.0 - 0.85 * s); }
static float sigma(float s, constant Params& P) { return P.shape.y * (P.shape.z - s) / P.shape.z; }
static float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
static float2 toChild(float2 q, constant Child& c) {
    float2 r = rot(q - c.root, -c.ang) / c.scale;
    return c.mirror > 0.5 ? float2(r.x, -r.y) : r;
}
constexpr sampler lin(filter::linear, address::clamp_to_edge);
static float2 uvOf(float2 q, constant Params& P) { return (q - P.bmin) / (P.bmax - P.bmin); }
static float outside(float2 q, constant Params& P) { return length(max(max(P.bmin - q, q - P.bmax), 0.0)); }

// PASS 1 — per state, per texel: distance to the spine, its arc parameter, side, distance to the stem
kernel void spineField(constant float2* sp [[buffer(0)]], constant Params& P [[buffer(1)]], constant int& st [[buffer(2)]],
                       texture2d_array<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float2 q = P.bmin + (float2(gid) + 0.5) / float(\(TR)) * (P.bmax - P.bmin);
    constant float2* s = sp + st * \(NS);
    float best = 1e9, bs = 0.0, side = 1.0;
    for (int i = 0; i < \(NS - 1); i++) {
        float2 a = s[i], b = s[i + 1], ab = b - a;
        float u = clamp(dot(q - a, ab) / dot(ab, ab), 0.0, 1.0);
        float d = length(q - a - ab * u);
        if (d < best) { best = d; bs = (float(i) + u) / float(\(NS - 1)); side = (ab.x * (q - a).y - ab.y * (q - a).x) >= 0.0 ? 1.0 : -1.0; }
    }
    out.write(float4(best, bs, side, best - width(bs, P)), gid, uint(st));
}

// PASS 2 — the TRUE distance to each state's whole infinite tree: T_i(q) = min(stem, min_k σ_k·T_j(child frame)), where a
// child lives in state j = i + its shift (it is smaller on screen, so more rolled). The rolled-tight state iterates on itself.
kernel void treeSeed(texture2d_array<float> F [[texture(0)]], texture2d_array<float, access::write> T [[texture(1)]],
                     constant int& st [[buffer(2)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    T.write(float4(F.read(gid, uint(st)).w), gid, uint(st));
}
static float sampleT(texture2d_array<float> T, float2 q, int st, constant Params& P) {
    return T.sample(lin, uvOf(q, P), uint(st)).x + outside(q, P);
}
kernel void treeStep(texture2d_array<float> F [[texture(0)]], texture2d_array<float> T [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                     constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], constant int& st [[buffer(2)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float2 q = P.bmin + (float2(gid) + 0.5) / float(\(TR)) * (P.bmax - P.bmin);
    float best = F.read(gid, uint(st)).w;
    for (int k = 0; k < NCHC; k++) {
        constant Child& c = ch[st * NCHC + k];
        int j = min(st + int(c.shift + 0.5), NSTC - 1);
        best = min(best, sampleT(T, toChild(q, c), j, P) * c.scale);
    }
    out.write(float4(best), gid);
}
// PASS 3 — per state, per texel: whose subtree is nearest (the descent's lookup)
kernel void childField(texture2d_array<float> T [[texture(0)]], texture2d_array<float, access::write> out [[texture(1)]],
                       constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], constant int& st [[buffer(2)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float2 q = P.bmin + (float2(gid) + 0.5) / float(\(TR)) * (P.bmax - P.bmin);
    float best = 1e9; int bi = -1;
    for (int k = 0; k < NCHC; k++) {
        constant Child& c = ch[st * NCHC + k];
        int j = min(st + int(c.shift + 0.5), NSTC - 1);
        float d = sampleT(T, toChild(q, c), j, P) * c.scale;
        if (d < best) { best = d; bi = k; }
    }
    out.write(float4(float(bi), best, 0.0, 0.0), gid, uint(st));
}

// on-screen size → curl state (0 open … NST-1 rolled)
static int stateFor(float len, float viewH, constant Params& P) {
    float l = log(max(len / viewH, 1e-6));
    return clamp(int((P.curl.x - l) / (P.curl.x - P.curl.y) * float(NSTC - 1) + 0.5), 0, NSTC - 1);
}

// THE DESCENT — from a frame `q` whose frond has length `scale` (output units). PHI is the nerve-impulse path
// coordinate: Σ arc fractions along each stem from the starting root (an impulse crosses every stem in the same time)
struct Res { float d; float lvl; float s; float vein; float across; float h; float id; float nvein; float phi; };
static Res descendFrom(float2 q, float scale, float phi0, float viewH, texture2d_array<float> F, texture2d_array<float> T, texture2d_array<float> C,
                       constant Child* ch, constant Params& P, float pix) {
    Res r; r.d = 1e9; r.lvl = -1.0; r.s = 0.0; r.vein = 0.0; r.across = 0.0; r.h = 0.0; r.id = 0.0; r.nvein = 0.0; r.phi = phi0;
    float phi = phi0, sure = 1e9, surePhi = phi0, sureS = 0.0; float sureL = 0.0;
    float texel = 2.5 * (P.bmax.x - P.bmin.x) / float(\(TR));
    int maxL = int(P.misc.y);
    for (int L = 0; L <= maxL; L++) {
        int st = stateFor(scale, viewH, P);
        float2 uv = uvOf(q, P); float o = outside(q, P);
        float4 f = F.sample(lin, uv, uint(st)); f.x += o; f.w += o;
        float tq = T.sample(lin, uv, uint(st)).x + o;
        if (tq < -texel && tq * scale < sure) { sure = tq * scale; surePhi = phi + f.y; sureS = f.y; sureL = float(L) + 0.5; }   // this level is SURE the point is in the tree
        float rach = f.w * scale;                                          // this level's stem (a vein)
        r.vein = max(r.vein, smoothstep(pix * 1.2, -pix * 0.5, rach) * (1.0 - 0.12 * float(L)));
        if (rach < r.d) { r.d = rach; r.lvl = float(L); r.s = f.y; r.across = 0.0; r.phi = phi + f.y; }
        { float wr = width(f.y, P); r.h = max(r.h, sqrt(max(wr * wr - f.x * f.x, 0.0)) * scale * 1.2); }   // stems are round
        bool last = (L == maxL) || (scale * sigma(f.y, P) < pix * 2.5);  // children below ~2 px: draw the subtree's silhouette
        if (last) {
            float blade = tq * scale;
            if (blade < r.d) { r.d = blade; r.lvl = float(L) + 0.5; r.s = f.y; r.phi = phi + f.y;
                               float lw = sigma(f.y, P) * 0.5 + width(f.y, P); r.across = clamp(f.x / lw, 0.0, 1.0) * f.z; }
            float ub = clamp(-tq / max(sigma(f.y, P) * 0.15, 1e-4), 0.0, 1.0);
            r.h = max(r.h, sigma(f.y, P) * 0.12 * sqrt(ub) * scale);      // each leaflet a shallow dome
            break;
        }
        if (o > 0.0) { break; }
        float4 c = C.read(uint2(clamp(uv, 0.0, 0.9999) * float(\(TR))), uint(st));
        int k0 = int(c.x + 0.5);
        if (k0 < 0 || c.y > 0.5) { break; }
        // the lookup is texel-coarse: re-decide EXACTLY among its neighbours along the stem, both sides
        int k = k0; float bd = 1e9;
        int Wn = int(P.misc.w);
        for (int j = -Wn; j <= Wn + 1; j++) {
            int kk = (k0 & ~1) + j;
            if (kk < 0 || kk >= NCHC) { continue; }
            constant Child& cc = ch[st * NCHC + kk];
            int sj = stateFor(scale * cc.scale, viewH, P);
            float2 qc = toChild(q, cc);
            float dk = (T.sample(lin, uvOf(qc, P), uint(sj)).x + outside(qc, P)) * cc.scale;
            if (dk < bd) { bd = dk; k = kk; }
        }
        if (bd > 0.25) { break; }
        constant Child& K = ch[st * NCHC + k];
        phi += K.s;
        q = toChild(q, K);
        scale *= K.scale;
        r.id = fract(r.id * 7.31 + float(k) * 0.1373 + 0.17);
    }
    // a coarser level was sure it is inside but the path fell into a gap (texture-resolution dead end): trust the coarse level
    if (r.d > 0.0 && sure < 0.0) { r.d = sure; r.phi = surePhi; r.s = sureS; r.lvl = sureL; }
    return r;
}

// screen uv → descent. Stills: the top frond placed in the world. ZOOM: the camera rides the dive point (host-computed),
// the frame lifted a few ancestors up so the surroundings exist at every depth
static Res look(float2 uv, constant Params& P, texture2d_array<float> F, texture2d_array<float> T, texture2d_array<float> C,
                constant Child* ch, float res_y, thread float& pixOut) {
    if (P.curl.z > 0.5) {
        float half_ = P.zc.z;
        float2 q0 = P.zc.xy + rot(uv * 2.0 * half_, P.zc.w);
        float pix = 2.0 * half_ / res_y; pixOut = pix;
        float2 q = P.lift.xy + rot(q0 * P.lift.w, P.lift.z);
        return descendFrom(q, 1.0 / P.lift.w, P.tm.y, 2.0 * half_, F, T, C, ch, P, pix);
    }
    float pix = 2.0 * P.cam.z / res_y; pixOut = pix;
    float2 pw = P.cam.xy + uv * 2.0 * P.cam.z;
    float2 q = rot(pw - P.top.xy, -P.top.z) / P.top.w;
    if (P.cam.w > 0.5) { q.y = -q.y; }                                   // coil rolls clockwise (reference)
    return descendFrom(q, P.top.w, 0.0, 2.0 * P.cam.z, F, T, C, ch, P, pix);
}

static float3 hsv(float h, float s, float v) { float3 k = clamp(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0); return v * mix(float3(1.0), k, s); }
static float hsh(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

kernel void render(texture2d_array<float> F [[texture(0)]], texture2d_array<float> T [[texture(1)]], texture2d_array<float> C [[texture(2)]],
                   texture2d<float, access::write> out [[texture(3)]],
                   constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], constant float2* pulses [[buffer(2)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    float2 res = float2(\(W).0, \(H).0);
    float t = P.tm.x, hue0 = P.au.z;
    float3 acc = 0.0;
    const float2 o4[4] = { float2(0.25, 0.25), float2(0.75, 0.25), float2(0.25, 0.75), float2(0.75, 0.75) };
    for (int a = 0; a < 4; a++) {
        float2 uv = (float2(gid) + o4[a] - 0.5 * res) / res.y * float2(1.0, -1.0);
        float pix;
        Res r = look(uv, P, F, T, C, ch, res.y, pix);
        float px1 = 1.0 / res.y, pd;
        Res rx = look(uv + float2(px1, 0.0), P, F, T, C, ch, res.y, pd), ry = look(uv + float2(0.0, px1), P, F, T, C, ch, res.y, pd);
        float3 n = normalize(float3(-(rx.h - r.h) / pix, -(ry.h - r.h) / pix, 1.0));
        float3 Ld = normalize(float3(-0.5, 0.55, 0.65));
        float dif = clamp(dot(n, Ld), 0.0, 1.0);
        float spec = pow(clamp(dot(reflect(-Ld, n), float3(0.0, 0.0, 1.0)), 0.0, 1.0), 30.0);
        float cov = smoothstep(pix * 0.7, -pix * 0.7, r.d);
        // NERVE IMPULSES: each pulse is a front moving down PHI (trunk → branches → leaflet tips): sharp head, glowing tail
        float pulse = 0.0;
        int np = int(P.tm.w);
        for (int i = 0; i < np; i++) {
            float dphi = pulses[i].x - r.phi;
            float head = exp(-dphi * dphi / 0.0016), tail = dphi > 0.0 ? exp(-dphi / 0.18) : 0.0;
            pulse += pulses[i].y * (head * 1.6 + tail * 0.5);
        }
        float ripple = 0.5 + 0.5 * sin(6.2831853 * (r.phi * 2.0 - t * 0.6));
        float shimmer = step(1.0 - 0.25 * P.au.y, hsh(float2(r.id * 97.0 + floor(r.s * 9.0), floor(t * 18.0))));
        // COLOUR BATH: hue drifts along the impulse path and by level, so the branching reads as bands of colour
        float hue = hue0 + 0.22 * r.phi + 0.09 * floor(r.lvl) + 0.03 * sin(t * 0.2);   // wide spread: several colours in every frame
        float mid = 1.0 - abs(r.across);
        float3 body = hsv(hue, 0.92, 0.05 + 0.40 * dif * (0.55 + 0.45 * mid));
        float wv = max(r.vein, r.nvein * 0.7);
        float3 glow = hsv(hue + 0.08, 0.6, 1.0) * wv * (0.25 + 0.6 * P.au.x * ripple + 3.0 * pulse);
        float rim = smoothstep(-pix * 3.0, -pix * 0.3, r.d) * cov;
        float3 edge = hsv(hue + 0.33, 0.8, 1.0) * rim * (0.08 + 0.6 * pulse + 0.25 * shimmer);
        float3 col = body * (1.0 + 1.2 * pulse) + glow + edge + float3(1.0, 0.95, 0.9) * spec * 0.25;
        if (P.misc.z > 0.5) { col = float3(0.2, 0.55, 0.15) * (0.35 + 0.8 * dif) + float3(0.5, 0.8, 0.3) * r.vein * 0.3; }   // plain fern (structure check)
        float3 bg = P.misc.z > 0.5 ? float3(0.01, 0.012, 0.015)
                  : hsv(hue0 + 0.5 + 0.15 * uv.x + 0.05 * sin(t * 0.13 + uv.y * 2.0), 0.95, 0.012 + 0.012 * sin(uv.x * 2.0 + t * 0.2));   // deep, saturated, dark: the fern carries the light
        acc += mix(bg, col, cov);
    }
    acc *= 0.25;
    acc = acc / (1.0 + dot(acc, float3(0.299, 0.587, 0.114)) * 0.6);
    out.write(float4(pow(clamp(acc, 0.0, 1.0), float3(1.0 / 2.2)), 1.0), gid);
}
"""

// MARK: - Host

let device = MTLCreateSystemDefaultDevice()!
let lib: MTLLibrary
do { lib = try device.makeLibrary(source: msl, options: nil) } catch { FileHandle.standardError.write("\(error)\n".data(using: .utf8)!); exit(1) }
let queue = device.makeCommandQueue()!
func pso(_ n: String) -> MTLComputePipelineState { try! device.makeComputePipelineState(function: lib.makeFunction(name: n)!) }
func tex(_ f: MTLPixelFormat, _ w: Int, _ h: Int, slices: Int = 0) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
    if slices > 0 { d.textureType = .type2DArray; d.arrayLength = slices }
    d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)!
}

let chBuf = device.makeBuffer(bytes: &chg, length: MemoryLayout<ChildGPU>.stride * chg.count, options: .storageModeShared)!
let spBuf = device.makeBuffer(bytes: &spines, length: MemoryLayout<SIMD2<Float>>.stride * spines.count, options: .storageModeShared)!

var P = Params(bmin: bmin, bmax: bmax,
               cam: [envF("ZX", 0.0), envF("ZY", 0.0), envF("VIEW", 1.0) / envF("ZOOM", 1), envF("FLIP", 1)],
               top: [envF("TX", -0.5), envF("TY", -1.55), envF("TA", 1.75), envF("TL", 3.4)],
               shape: [W0, CS, SINF, 0],
               misc: [Float(NCH), envF("MAXL", 14), envF("DBG", 0), envF("CW", 4)],   // CW: candidate window either side
               curl: [LOPEN, LCURL, 0, 0], lift: [0, 0, 0, 1], zc: .zero, tm: .zero, au: [0, 0, envF("HUE", 0.33), 0])

let F = tex(.rgba32Float, TR, TR, slices: NST), T = tex(.r32Float, TR, TR, slices: NST), C = tex(.rgba32Float, TR, TR, slices: NST)
let TA = tex(.r32Float, TR, TR), outT = tex(.rgba8Unorm, W, H)
let tg = MTLSize(width: 16, height: 16, depth: 1), grid = MTLSize(width: TR, height: TR, depth: 1)
do {
    let t0 = Date()
    let cb = queue.makeCommandBuffer()!
    func perState(_ name: String, _ i: Int, _ texs: [MTLTexture]) {
        var st = Int32(i)
        let e = cb.makeComputeCommandEncoder()!
        e.setComputePipelineState(pso(name))
        for (n, t) in texs.enumerated() { e.setTexture(t, index: n) }
        e.setBuffer(name == "spineField" ? spBuf : chBuf, offset: 0, index: 0); e.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1)
        e.setBytes(&st, length: 4, index: 2); e.dispatchThreads(grid, threadsPerThreadgroup: tg); e.endEncoding()
    }
    func step(_ i: Int) {                                                // one level more of state i's tree, from T as it stands
        perState("treeStep", i, [F, T, TA])
        let b = cb.makeBlitCommandEncoder()!
        b.copy(from: TA, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: TR, height: TR, depth: 1),
               to: T, destinationSlice: i, destinationLevel: 0, destinationOrigin: MTLOrigin())
        b.endEncoding()
    }
    for i in 0..<NST { perState("spineField", i, [F]) }
    for i in 0..<NST { perState("treeSeed", i, [F, T]) }
    for _ in 0..<Int(envF("TITER", 8)) { step(NST - 1) }                // the rolled-tight state converges on itself
    for i in stride(from: NST - 2, through: 0, by: -1) { step(i) }      // each looser state from its (already final) children
    for i in 0..<NST { perState("childField", i, [T, C]) }
    cb.commit(); cb.waitUntilCompleted()
    FileHandle.standardError.write(String(format: "fields %.0f ms\n", Date().timeIntervalSince(t0) * 1000).data(using: .utf8)!)
}

let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared)!
let renderPSO = pso("render")
let pulseBuf = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * 32, options: .storageModeShared)!
func renderFrame() -> Double {
    let cb = queue.makeCommandBuffer()!, ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(renderPSO); ce.setTexture(F, index: 0); ce.setTexture(T, index: 1); ce.setTexture(C, index: 2); ce.setTexture(outT, index: 3)
    ce.setBuffer(chBuf, offset: 0, index: 0); ce.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1); ce.setBuffer(pulseBuf, offset: 0, index: 2)
    ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: tg)
    ce.endEncoding()
    let bb = cb.makeBlitCommandEncoder()!
    bb.copy(from: outT, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(), sourceSize: MTLSize(width: W, height: H, depth: 1),
            to: readback, destinationOffset: 0, destinationBytesPerRow: W * 4, destinationBytesPerImage: W * H * 4)
    bb.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    return (cb.gpuEndTime - cb.gpuStartTime) * 1000
}
func writePNG(_ path: String) {
    let ctx = CGContext(data: readback.contents(), width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, ctx.makeImage()!, nil); CGImageDestinationFinalize(dst)
}

// MARK: - The dive

// child k* (non-mirrored, so one cycle maps the picture onto itself)
var kstar = min(Int(envF("KSTAR", 5)), NCH - 1)
if chg[kstar].mirror > 0.5 { kstar ^= 1 }
let sigStar = chg[kstar].scale, sStar = chg[kstar].s
let lifts = Int(envF("LIFTS", 3))
let zoomPeriod = envF("TZ", 7)                     // seconds per level dived
let V0 = envF("V0", 0.55)
let pulseSpeed = envF("SPD", 0.5)
func stateFor(_ len: Float, _ viewH: Float) -> Int {
    let l = log(max(len / viewH, 1e-6))
    return min(max(Int((LOPEN - l) / (LOPEN - LCURL) * Float(NST - 1) + 0.5), 0), NST - 1)
}
struct Sim { var o: SIMD2<Float>; var a: Float; var s: Float }        // x ↦ o + R(a)·s·x
func rot2(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> { SIMD2(cos(a) * v.x - sin(a) * v.y, sin(a) * v.x + cos(a) * v.y) }
func G(level n: Int, frac: Float) -> Sim {                              // child k* of the level-n frond, in its state now
    let len = pow(sigStar, Float(n)), viewH = 2 * V0 * pow(sigStar, frac)
    let c = chg[stateFor(len, viewH) * NCH + kstar]
    return Sim(o: c.root, a: c.ang, s: c.scale)
}
func apply(_ g: Sim, _ x: SIMD2<Float>) -> SIMD2<Float> { g.o + rot2(x * g.s, g.a) }
func setZoom(time t: Float) {
    let u = t / zoomPeriod, cyc = floor(u), frac = u - cyc
    // the dive point: G0∘G1∘…(·) — each level in the state its on-screen size gives it now
    var x = SIMD2<Float>(0.3, 0.1)
    for n in stride(from: 9, through: 0, by: -1) { x = apply(G(level: n, frac: frac), x) }
    // the view turns with the dive: over one cycle by the angle the level-0 frond hands its child at the cycle's end
    let rotEnd = G(level: 0, frac: 1).a
    // lift: level-0 frame → the frame `lifts` ancestors up
    var L = Sim(o: .zero, a: 0, s: 1)
    if lifts > 0 { for m in 1...lifts { let g = G(level: -m, frac: frac); L = Sim(o: apply(g, L.o), a: g.a + L.a, s: g.s * L.s) } }
    P.curl.z = 1
    P.lift = [L.o.x, L.o.y, L.a, L.s]
    P.zc = [x.x, x.y, V0 * pow(sigStar, frac), rotEnd * frac]
    P.tm.x = t; P.tm.y = (cyc - Float(lifts)) * sStar
}
// stand-in music: a beat at BPM with accents, a bass envelope, treble shimmer
func setMusic(time t: Float) {
    let bpm = envF("BPM", 112), beat = 60 / bpm
    var arr: [SIMD2<Float>] = []
    var tb = floor(t / beat) * beat
    while tb > t - 8 && arr.count < 32 {
        let n = Int(tb / beat + 0.5), amp: Float = n % 4 == 0 ? 1.0 : (n % 2 == 0 ? 0.55 : 0.3)
        arr.append(SIMD2((tb / zoomPeriod - 1) * sStar + pulseSpeed * (t - tb), amp))
        tb -= beat
    }
    memcpy(pulseBuf.contents(), arr, MemoryLayout<SIMD2<Float>>.stride * arr.count)
    P.tm.w = Float(arr.count)
    let ph = t.truncatingRemainder(dividingBy: beat)
    P.au.x = exp(-ph / 0.3); P.au.y = 0.5 + 0.5 * sin(t * 3.1) * sin(t * 1.7)
    P.au.z = envF("HUE", 0.33) + 0.01 * t
}

let args = CommandLine.arguments
if args.count > 2 && args[1] == "still" {
    if envF("ZOOMMODE", 0) > 0.5 { setZoom(time: envF("T", 0)); setMusic(time: envF("T", 0)) }
    _ = renderFrame(); let ms = renderFrame()
    FileHandle.standardError.write(String(format: "frame %.1f ms\n", ms).data(using: .utf8)!)
    writePNG(args[2])
} else if args.count > 3 && args[1] == "video" {
    let secs = Float(args[3])!, fps: Float = 30
    let ff = Process(); ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(W)x\(H)", "-r", "30", "-i", "-",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", args[2]]
    let pipe = Pipe(); ff.standardInput = pipe; try! ff.run()
    var worst = 0.0
    for i in 0..<Int(secs * fps) {
        let t = Float(i) / fps + envF("T0", 0)
        setZoom(time: t); setMusic(time: t)
        worst = max(worst, renderFrame())
        pipe.fileHandleForWriting.write(Data(bytes: readback.contents(), count: W * H * 4))
    }
    try! pipe.fileHandleForWriting.close(); ff.waitUntilExit()
    FileHandle.standardError.write(String(format: "worst frame %.1f ms\n", worst).data(using: .utf8)!)
} else {
    print("usage: fernd still <out.png> | fernd video <out.mp4> <seconds>")
}
