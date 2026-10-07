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
        let s = Float(j) / Float(NS - 1), r = sigma(s) * envF("BBR", 1.6) + 0.03
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
        // a rendered child sits in state round(x + shift) where its parent sits in round(x): that is st + floor(shift) OR
        // st + ceil(shift). Take BOTH, so T bounds whichever the renderer picks (one assumed state pruned real tips)
        // state 0 is CLAMPED (fronds bigger than the screen are all 'fully open'), so its children can be in any state up to j1
        int j0 = min(st + int(floor(c.shift)), NSTC - 1), j1 = min(j0 + 1, NSTC - 1);
        float2 qc = toChild(q, c);
        float tc = 1e9;
        for (int j = (st == 0 ? 0 : j0); j <= j1; j++) { tc = min(tc, sampleT(T, qc, j, P)); }
        best = min(best, tc * c.scale);
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
        int j0 = min(st + int(floor(c.shift)), NSTC - 1), j1 = min(j0 + 1, NSTC - 1);
        float2 qc = toChild(q, c);
        float d = 1e9;
        for (int j = (st == 0 ? 0 : j0); j <= j1; j++) { d = min(d, sampleT(T, qc, j, P)); }
        d *= c.scale;
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
struct Res { float d; float lvl; float s; float vein; float across; float h; float id; float nvein; float phi; float phiC; float scaleC; float flag; };   // flag (debug DBG=2): 1 sure-fill, 2 alt won, 3 outside bbox, 4 no child, 5 far   // phiC/scaleC: the frond that is a visible UNIT on screen (colour comes from it)
// THE DESCENT is a bounded depth-first search: every child whose subtree could still hold the point (its tree distance
// is under a pixel) is explored, nearest surface wins. Following one path (plus a runner-up) clipped overlapping
// siblings along hard edges — 'cut-off tips'. Candidates: the children near the lookup's pick along the stem (fast) or
// ALL children (P.cam... debug ground truth, ALLCH=1).
struct Fr { float2 q; float scale; float phi; float id; float phiC; float scaleC; int L; };
static Res descendFrom(float2 q0, float scale0, float phi0, float viewH, texture2d_array<float> F, texture2d_array<float> T, texture2d_array<float> C,
                       constant Child* ch, constant Params& P, float pix) {
    Res r; r.d = 1e9; r.lvl = -1.0; r.s = 0.0; r.vein = 0.0; r.across = 0.0; r.h = 0.0; r.id = 0.0; r.nvein = 0.0; r.phi = phi0;
    r.phiC = phi0; r.scaleC = scale0; r.flag = 0.0;
    float sure = 1e9, surePhi = phi0, sureS = 0.0, sureL = 0.0, sureId = 0.0, surePhiC = phi0, sureScaleC = scale0;
    float texel = 2.5 * (P.bmax.x - P.bmin.x) / float(\(TR));
    float slack = texel * \(envF("SLACK", 2));
    int maxL = int(P.misc.y), Wn = int(P.misc.w);
    bool all = P.au.w < 0.0;                                              // (sign of the hue spread doubles as the ground-truth switch)
    Fr stack[\(Int(envF("STACK", 64)))]; int sp = 0;
    Fr root; root.q = q0; root.scale = scale0; root.phi = phi0; root.id = 0.0; root.phiC = phi0; root.scaleC = scale0; root.L = 0;
    stack[sp++] = root;
    int budget = \(Int(envF("BUDGET", 64)));
    while (sp > 0 && budget-- > 0) {
        Fr fr = stack[--sp];
        float2 q = fr.q; float scale = fr.scale;
        int st = stateFor(scale, viewH, P);
        float2 uv = uvOf(q, P); float o = outside(q, P);
        float tq = T.sample(lin, uv, uint(st)).x + o;
        // prune only when the subtree is far even allowing for the texture's error (≈ a texel, times this frond's size:
        // without the slack, whole screen-filling fronds were pruned)
        if ((tq - slack) * scale > min(r.d, pix * 1.5)) { continue; }
        float4 f = F.sample(lin, uv, uint(st)); f.x += o; f.w += o;
        float phiC = fr.phiC, scaleC = fr.scaleC;
        if (scale >= viewH * P.curl.w) { phiC = fr.phi + f.y; scaleC = scale; }
        bool fine = texel * scale < pix * 1.5;
        if (fine && tq < -texel && tq * scale < sure) { sure = tq * scale; surePhi = fr.phi + f.y; sureS = f.y; sureL = float(fr.L) + 0.5;
                                                       sureId = fr.id; surePhiC = phiC; sureScaleC = scaleC; }
        float rach = f.w * scale;
        r.vein = max(r.vein, smoothstep(pix * 1.2, -pix * 0.5, rach) * (1.0 - 0.12 * float(fr.L)));
        if (rach < r.d) { r.d = rach; r.lvl = float(fr.L); r.s = f.y; r.across = 0.0; r.phi = fr.phi + f.y; r.id = fr.id; r.phiC = phiC; r.scaleC = scaleC; }
        { float wr = width(f.y, P); r.h = max(r.h, sqrt(max(wr * wr - f.x * f.x, 0.0)) * scale * 1.2); }
        bool last = (fr.L == maxL) || (scale * sigma(f.y, P) < pix * \(envF("LASTPX", 2.5))) || o > 0.0;
        if (last) {
            float blade = tq * scale;
            if (blade < r.d) { r.d = blade; r.lvl = float(fr.L) + 0.5; r.s = f.y; r.phi = fr.phi + f.y; r.id = fr.id; r.phiC = phiC; r.scaleC = scaleC;
                               float lw = sigma(f.y, P) * 0.5 + width(f.y, P); r.across = clamp(f.x / lw, 0.0, 1.0) * f.z; }
            float ub = clamp(-tq / max(sigma(f.y, P) * 0.15, 1e-4), 0.0, 1.0);
            r.h = max(r.h, sigma(f.y, P) * 0.12 * sqrt(ub) * scale);
            continue;
        }
        int k0 = int(C.read(uint2(clamp(uv, 0.0, 0.9999) * float(\(TR))), uint(st)).x + 0.5);
        int lo = all ? 0 : max((k0 & ~1) - Wn, 0), hi = all ? NCHC - 1 : min((k0 & ~1) + Wn + 1, NCHC - 1);
        // push candidates; the nearest is pushed LAST so it is explored first (tightens the bound for the rest)
        int kb = -1; float db = 1e9;
        for (int kk = lo; kk <= hi; kk++) {
            constant Child& cc = ch[st * NCHC + kk];
            float2 qc = toChild(q, cc);
            float dk = (T.sample(lin, uvOf(qc, P), uint(stateFor(scale * cc.scale, viewH, P))).x + outside(qc, P)) * scale * cc.scale;
            if (dk - slack * scale * cc.scale > min(r.d, pix * 1.5)) { continue; }
            if (dk < db) {
                if (kb >= 0 && sp < \(Int(envF("STACK", 64)))) { constant Child& cb = ch[st * NCHC + kb]; Fr c; c.q = toChild(q, cb); c.scale = scale * cb.scale; c.phi = fr.phi + cb.s;
                    c.id = fract(fr.id * 7.31 + float(kb) * 0.1373 + 0.17); c.phiC = phiC; c.scaleC = scaleC; c.L = fr.L + 1; stack[sp++] = c; }
                kb = kk; db = dk;
            } else if (sp < \(Int(envF("STACK", 64)))) {
                Fr c; c.q = qc; c.scale = scale * cc.scale; c.phi = fr.phi + cc.s; c.id = fract(fr.id * 7.31 + float(kk) * 0.1373 + 0.17);
                c.phiC = phiC; c.scaleC = scaleC; c.L = fr.L + 1; stack[sp++] = c;
            }
        }
        if (kb >= 0 && sp < \(Int(envF("STACK", 64)))) { constant Child& cb = ch[st * NCHC + kb]; Fr c; c.q = toChild(q, cb); c.scale = scale * cb.scale; c.phi = fr.phi + cb.s;
            c.id = fract(fr.id * 7.31 + float(kb) * 0.1373 + 0.17); c.phiC = phiC; c.scaleC = scaleC; c.L = fr.L + 1; stack[sp++] = c; }
        else if (kb < 0 && tq < 0.0 && fine) {                          // no candidate holds the point, yet this level's outline does
            float blade = tq * scale;
            if (blade < r.d) { r.d = blade; r.lvl = float(fr.L) + 0.5; r.s = f.y; r.phi = fr.phi + f.y; r.across = 0.0; r.id = fr.id; r.phiC = phiC; r.scaleC = scaleC; r.flag = 5.0; }
        }
    }
    if (budget <= 0 || sp >= \(Int(envF("STACK", 64)))) { r.flag = 4.0; }   // ran out: flagged (DBG=2 magenta)
    if (r.d > 0.0 && sure < 0.0) { r.d = sure; r.phi = surePhi; r.s = sureS; r.lvl = sureL; r.id = sureId; r.phiC = surePhiC; r.scaleC = sureScaleC; r.flag = 1.0; }
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
// the palette: 6 sRGB anchors walked as a PING-PONG gradient (no hard wrap back to the start), converted to linear
static float3 pal(float x, constant float4* PL) {
    float u = abs(fract(x * 0.5) * 2.0 - 1.0) * 5.0; int i = min(int(u), 4); float f = smoothstep(0.0, 1.0, u - float(i));
    float3 c = pow(mix(PL[i].rgb, PL[i + 1].rgb, f), float3(2.2));
    float Y = dot(c, float3(0.2126, 0.7152, 0.0722));
    return c * clamp(\(envF("LUM", 0.08)) / max(Y, 1e-3), 0.3, 1.3);                   // even brightness: bright hues come DOWN to the dark ones                     // even brightness along the palette (gold/emerald ran 2-3× brighter than cobalt)
}
static float hsh(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

kernel void render(texture2d_array<float> F [[texture(0)]], texture2d_array<float> T [[texture(1)]], texture2d_array<float> C [[texture(2)]],
                   texture2d<float, access::write> out [[texture(3)]],   // HDR
                   constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], constant float2* pulses [[buffer(2)]], constant float4* PL [[buffer(3)]],
                   uint2 gid [[thread_position_in_grid]], ushort lane [[thread_index_in_simdgroup]]) {
    // no early return: every lane must reach the shuffles below (out-of-range threads compute, then skip the write)
    float2 res = float2(\(W).0, \(H).0);
    float t = P.tm.x, hue0 = P.au.z;
    float3 acc = 0.0;
    const float2 o4[4] = { float2(0.25, 0.25), float2(0.75, 0.25), float2(0.25, 0.75), float2(0.75, 0.75) };
    const int NSS = \(Int(envF("SS", 1)));
    for (int a = 0; a < NSS; a++) {
        float2 uv = (float2(gid) + (NSS > 1 ? o4[a] : float2(0.5)) - 0.5 * res) / res.y * float2(1.0, -1.0);
        float pix;
        Res r = look(uv, P, F, T, C, ch, res.y, pix);
        // RELIEF NORMAL from the neighbouring pixels' heights: a 16-wide threadgroup puts two pixel rows in one SIMD
        // group, so lane^1 is the horizontal neighbour and lane^16 the vertical one (two extra descents per pixel before)
        float hn = simd_shuffle_xor(r.h, ushort(1)), hv = simd_shuffle_xor(r.h, ushort(16));
        float dhx = (lane & 1) ? r.h - hn : hn - r.h, dhy = (lane & 16) ? hv - r.h : r.h - hv;   // +x right, +y up
        float3 n = normalize(float3(-dhx / pix, -dhy / pix, 1.0));
        float3 Ld = normalize(float3(-0.5, 0.55, 0.65));
        float dif = clamp(dot(n, Ld), 0.0, 1.0);
        float spec = pow(clamp(dot(reflect(-Ld, n), float3(0.0, 0.0, 1.0)), 0.0, 1.0), 30.0);
        float cov = smoothstep(pix * 0.7, -pix * 0.7, r.d);
        // NERVE IMPULSES: each pulse is a front moving down PHI (trunk → branches → leaflet tips): sharp head, glowing tail
        float pulse = 0.0;
        int np = int(P.tm.w);
        for (int i = 0; i < np; i++) {
            float dphi = pulses[i].x - r.phi;
            float head = exp(-dphi * dphi / 0.0016), tail = dphi > 0.0 ? exp(-dphi / 0.08) : 0.0;
            pulse += pulses[i].y * (head * 1.0 + tail * 0.25);
        }
        float ripple = 0.5 + 0.5 * sin(6.2831853 * (r.phiC * abs(P.au.w) * 2.0 - P.tm.z * t * 2.0));   // light rides the colour bands
        float shimmer = step(1.0 - 0.25 * P.au.y, hsh(float2(r.id * 97.0 + floor(r.s * 9.0), floor(t * 18.0))));
        // COLOUR BATH: the fern GLOWS (emissive, not lit) in a curated psychedelic palette. Hue runs along the impulse path
        // and steps per level, so the branching reads as bands of colour; it flows outward over time (colour pours down
        // the branches); each leaflet its own small offset. Palette chosen in sRGB, converted to linear (gamma washed
        // linear-space hues to pastel).
        // hue from the visible unit: its path position + its on-screen size (continuous, so the loop is seamless and
        // colour shifts as each frond grows toward the camera); finer levels vary brightness, not hue (sub-pixel hue mixing → grey)
        float viewH = pix * res.y;
        float hue = hue0 + abs(P.au.w) * r.phiC - 0.17 * log(r.scaleC / viewH) - P.tm.z * t;   // bands of colour pour down the branches
        float mid = 1.0 - abs(r.across);
        float3 c0 = pal(hue, PL), c1 = pal(hue + 0.12, PL), cv = mix(pal(hue + 0.06, PL), float3(1.0), 0.2);
        float relief = 0.25 + 0.75 * dif;
        // jewel read: dark translucent body, glowing toward its midrib; the LIGHT lives on edges and veins
        float3 tissue = c0 * relief * (0.18 + 0.45 * mid * mid) * (0.5 + 0.9 * ripple) * (0.8 + 0.4 * P.au.x);
        float wv = max(r.vein, r.nvein * 0.7);
        float3 glow = cv * wv * (0.7 + 2.2 * P.au.x * ripple + 7.0 * pulse);   // bass swells the ripple light
        float rim = smoothstep(-pix * 2.5, -pix * 0.2, r.d) * cov;
        float3 edge = c1 * rim * (1.1 + 3.0 * pulse + 2.0 * shimmer);
        float3 col = tissue * (1.0 + 2.5 * pulse) + glow + edge + float3(1.0, 0.95, 0.9) * spec * 0.4;
        if (P.misc.z > 0.5) { col = float3(0.2, 0.55, 0.15) * (0.35 + 0.8 * dif) + float3(0.5, 0.8, 0.3) * r.vein * 0.3; }   // plain fern (structure check)
        if (P.misc.z > 1.5) { const float3 fc[6] = { float3(0.15), float3(1, 0, 0), float3(0, 0.4, 1), float3(1, 1, 0), float3(1, 0, 1), float3(0, 1, 1) };
                              col = mix(col, fc[int(r.flag)], 0.6); cov = 1.0; }
        // the bath behind: a slow drifting fog of palette light (black read as a void, not a bath)
        float fog = 0.5 + 0.5 * sin(uv.x * 2.3 + t * 0.21) * sin(uv.y * 1.7 - t * 0.17 + 1.3 * sin(uv.x * 1.1 + t * 0.09));
        float3 bg = P.misc.z > 0.5 ? float3(0.01, 0.012, 0.015) : pal(hue0 + 0.35 * uv.x + 0.25 * fog - P.tm.z * t, PL) * (0.012 + 0.05 * fog * fog);
        acc += mix(bg, col, cov);
    }
    acc /= float(NSS);
    if (gid.x < \(W)u && gid.y < \(H)u) { out.write(float4(acc, 1.0), gid); }
}

// BLOOM: bright parts → quarter resolution → wide separable Gaussian, added back; the light spills into the dark (a bath)
kernel void bright(texture2d<float> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float3 a = 0.0;
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) { a += src.read(gid * 4u + uint2(i, j)).rgb; }
    dst.write(float4(max(a / 16.0 - 0.25, 0.0), 1.0), gid);   // the light spills into the gaps (a bath), but only the brighter half blooms
}
kernel void blur(texture2d<float> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]], constant int2& dir [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float3 a = 0.0; float ws = 0.0;
    for (int k = -24; k <= 24; k++) {
        int2 c = clamp(int2(gid) + dir * k, int2(0), int2(dst.get_width() - 1, dst.get_height() - 1));
        float w = exp(-float(k * k) / 160.0); a += src.read(uint2(c)).rgb * w; ws += w;
    }
    dst.write(float4(a / ws, 1.0), gid);
}
kernel void compose(texture2d<float> hdr [[texture(0)]], texture2d<float> bl [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                    constant float4& g [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float2 uv = (float2(gid) + 0.5) / float2(out.get_width(), out.get_height());
    float3 c = hdr.read(gid).rgb * g.z + bl.sample(lin, uv).rgb * g.x;
    float m = max(c.r, max(c.g, c.b));
    c *= (1.0 + m / (g.y * g.y)) / (1.0 + m) ;                             // tone map on the MAX channel: hues stay saturated
    out.write(float4(pow(clamp(c, 0.0, 1.0), float3(1.0 / 2.2)), 1.0), gid);
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
               shape: [W0, CS, SINF, envF("NALT", 3)],
               misc: [Float(NCH), envF("MAXL", 14), envF("DBG", 0), envF("CW", 4)],   // CW: candidate window either side
               curl: [LOPEN, LCURL, 0, envF("CUNIT", 0.15)], lift: [0, 0, 0, 1], zc: .zero, tm: .zero, au: [0, 0, envF("HUE", 0.33), envF("HSPREAD", 1.4) * (envF("ALLCH", 0) > 0.5 ? -1 : 1)])

let F = tex(.rgba32Float, TR, TR, slices: NST), T = tex(.r32Float, TR, TR, slices: NST), C = tex(.rgba32Float, TR, TR, slices: NST)
let TA = tex(.r32Float, TR, TR), outT = tex(.rgba8Unorm, W, H)
let hdrT = tex(.rgba16Float, W, H), bA = tex(.rgba16Float, W / 4, H / 4), bB = tex(.rgba16Float, W / 4, H / 4)
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
let renderPSO = pso("render"), brightPSO = pso("bright"), blurPSO = pso("blur"), composePSO = pso("compose")
// PALETTES, each anchored to a named look (PAL=n)
let palettes: [[SIMD4<Float>]] = [
    // 0 psychedelic: violet → magenta → amber → emerald → cyan → blue
    [[0.42, 0.12, 0.95, 0], [0.98, 0.12, 0.62, 0], [1.0, 0.58, 0.06, 0], [0.15, 0.92, 0.38, 0], [0.05, 0.82, 0.98, 0], [0.18, 0.30, 1.0, 0]],
    // 1 bioluminescent night forest (Pandora): ink blue → electric cyan → aqua → violet → magenta bloom
    [[0.05, 0.10, 0.45, 0], [0.0, 0.45, 0.95, 0], [0.0, 0.95, 0.90, 0], [0.35, 0.95, 0.75, 0], [0.55, 0.25, 1.0, 0], [0.95, 0.20, 0.80, 0]],
    // 2 Klimt gold (The Tree of Life): deep teal → emerald → olive gold → gold leaf → amber → ember red
    [[0.02, 0.30, 0.35, 0], [0.05, 0.55, 0.40, 0], [0.55, 0.62, 0.15, 0], [1.0, 0.80, 0.25, 0], [1.0, 0.52, 0.08, 0], [0.80, 0.15, 0.08, 0]],
    // 3 aurora borealis: deep violet → rose → magenta → teal → emerald → lime-white
    [[0.25, 0.10, 0.55, 0], [0.85, 0.25, 0.55, 0], [0.60, 0.20, 0.85, 0], [0.05, 0.70, 0.75, 0], [0.10, 0.95, 0.45, 0], [0.75, 1.0, 0.55, 0]],
    // 4 Sainte-Chapelle stained glass: cobalt → ultramarine → ruby → crimson → gold → emerald
    [[0.05, 0.15, 0.75, 0], [0.20, 0.25, 1.0, 0], [0.85, 0.05, 0.25, 0], [1.0, 0.25, 0.10, 0], [1.0, 0.75, 0.10, 0], [0.05, 0.65, 0.35, 0]],
]
var palSel = palettes[min(Int(envF("PAL", 4)), palettes.count - 1)]
let palBuf = device.makeBuffer(bytes: &palSel, length: MemoryLayout<SIMD4<Float>>.stride * 6, options: .storageModeShared)!
let pulseBuf = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * 32, options: .storageModeShared)!
var exposure: Float = envF("EXPO", 2.8)
func renderFrame() -> Double {
    let cb = queue.makeCommandBuffer()!, ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(renderPSO); ce.setTexture(F, index: 0); ce.setTexture(T, index: 1); ce.setTexture(C, index: 2); ce.setTexture(hdrT, index: 3)
    ce.setBuffer(chBuf, offset: 0, index: 0); ce.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1); ce.setBuffer(pulseBuf, offset: 0, index: 2); ce.setBuffer(palBuf, offset: 0, index: 3)
    ce.dispatchThreadgroups(MTLSize(width: (W + 15) / 16, height: (H + 15) / 16, depth: 1), threadsPerThreadgroup: tg)   // whole groups: the lane layout the normals rely on
    let q4 = MTLSize(width: W / 4, height: H / 4, depth: 1)
    ce.setComputePipelineState(brightPSO); ce.setTexture(hdrT, index: 0); ce.setTexture(bA, index: 1); ce.dispatchThreads(q4, threadsPerThreadgroup: tg)
    var dh = SIMD2<Int32>(1, 0), dv = SIMD2<Int32>(0, 1)
    ce.setComputePipelineState(blurPSO)
    ce.setTexture(bA, index: 0); ce.setTexture(bB, index: 1); ce.setBytes(&dh, length: 8, index: 0); ce.dispatchThreads(q4, threadsPerThreadgroup: tg)
    ce.setTexture(bB, index: 0); ce.setTexture(bA, index: 1); ce.setBytes(&dv, length: 8, index: 0); ce.dispatchThreads(q4, threadsPerThreadgroup: tg)
    var g = SIMD4<Float>(envF("BLOOM", 1.0), envF("WHITE", 2.5), exposure, 0)
    ce.setComputePipelineState(composePSO); ce.setTexture(hdrT, index: 0); ce.setTexture(bA, index: 1); ce.setTexture(outT, index: 2)
    ce.setBytes(&g, length: 16, index: 0); ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: tg)
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
    P.tm.x = t; P.tm.y = (cyc - Float(lifts)) * sStar; P.tm.z = envF("FLOW", 0.12)
}
// MUSIC. DRIVE=<prefix> reads tools/fern_drive.py output: <prefix>.csv (per 30 fps frame: bass dev, treble dev, energy)
// and <prefix>.beats (grid beat time, accent). Without it: a stand-in beat at BPM.
// Continuous energy is the primary driver (ripple ← bass, shimmer ← treble, overall glow ← loudness); pulses ride the
// fitted beat GRID (never raw onsets), each as strong as its beat's accent.
var driveRows: [SIMD3<Float>] = [], driveBeats: [SIMD2<Float>] = []
if let pre = env["DRIVE"] {
    func rows(_ path: String) -> [[Float]] {
        (try? String(contentsOfFile: path, encoding: .utf8))?.split(separator: "\n").map { $0.split(separator: ",").compactMap { Float($0) } } ?? []
    }
    driveRows = rows(pre + ".csv").filter { $0.count == 3 }.map { SIMD3($0[0], $0[1], $0[2]) }
    driveBeats = rows(pre + ".beats").filter { $0.count == 2 }.map { SIMD2($0[0], $0[1]) }
    FileHandle.standardError.write("drive: \(driveRows.count) frames, \(driveBeats.count) beats\n".data(using: .utf8)!)
}
func setMusic(time t: Float) {
    var arr: [SIMD2<Float>] = []
    if driveBeats.isEmpty {
        let beat = 60 / envF("BPM", 112)
        var tb = floor(t / beat) * beat
        while tb > t - 8 && arr.count < 32 {
            let n = Int(tb / beat + 0.5), amp: Float = n % 4 == 0 ? 1.0 : (n % 2 == 0 ? 0.55 : 0.3)
            arr.append(SIMD2((tb / zoomPeriod - 1) * sStar + pulseSpeed * (t - tb), amp)); tb -= beat
        }
        let ph = t.truncatingRemainder(dividingBy: beat)
        P.au.x = exp(-ph / 0.3); P.au.y = 0.5 + 0.5 * sin(t * 3.1) * sin(t * 1.7)
    } else {
        for b in driveBeats.reversed() where b.x <= t && b.x > t - 8 && arr.count < 32 {
            arr.append(SIMD2((b.x / zoomPeriod - 1) * sStar + pulseSpeed * (t - b.x + envF("LEAD", 0.0)), b.y * b.y * 0.7))   // accents squared: downbeats stand out
        }
        let r = driveRows[min(max(Int(t * 30), 0), driveRows.count - 1)]
        P.au.x = r.x; P.au.y = r.y
        exposure = envF("EXPO", 2.8) * (0.55 + 0.55 * r.z)               // quiet passages dim, loud ones bloom
    }
    memcpy(pulseBuf.contents(), arr, MemoryLayout<SIMD2<Float>>.stride * max(arr.count, 1))
    P.tm.w = Float(arr.count)
    P.au.z = envF("HUE", 0.33)
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
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(W)x\(H)", "-r", "30", "-i", "-"]
        + (env["AUDIO"].map { ["-i", $0, "-c:a", "aac", "-b:a", "192k", "-shortest"] } ?? [])
        + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", args[2]]
    let pipe = Pipe(); ff.standardInput = pipe; try! ff.run()
    var worst = 0.0, times: [Double] = []
    for i in 0..<Int(secs * fps) {
        let t = Float(i) / fps + envF("T0", 0)
        setZoom(time: t); setMusic(time: t)
        let ms = renderFrame(); worst = max(worst, ms); times.append(ms)
        pipe.fileHandleForWriting.write(Data(bytes: readback.contents(), count: W * H * 4))
    }
    try! pipe.fileHandleForWriting.close(); ff.waitUntilExit()
    times.sort()
    FileHandle.standardError.write(String(format: "frame p50 %.1f  p95 %.1f  worst %.1f ms\n", times[times.count / 2], times[times.count * 95 / 100], worst).data(using: .utf8)!)
} else {
    print("usage: fernd still <out.png> | fernd video <out.mp4> <seconds>")
}
