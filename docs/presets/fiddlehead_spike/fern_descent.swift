// FH.15 spike — the fiddlehead as a TRUE self-similar fractal, drawn by per-pixel descent.
//
// Matt: "a deeply intricate pattern … the fractal pattern at different levels of zoom — a staggering amount of detail";
// first it must read as a fern in shape and texture (light show later).
//
// ONE element — a frond: a stem that runs gently curved, then rolls into a log-spiral crozier, lined on both sides with
// children that are the SAME frond, scaled to the local width. The whole fiddlehead is that element; so is every pinna,
// pinnule, and so on down. Each pixel walks down the tree, at every level stepping into the one child whose region it
// lies in (a precomputed lookup), until the children are smaller than a pixel; there the frond is drawn as a solid
// leaflet blade. Cost grows by one step per level, so detail holds at any zoom (the 3-D ray march multiplied per level).
//
//   swiftc -O -swift-version 5 fern_descent.swift -o fernd
//   fernd still <out.png>            env: ZOOM, ZX, ZY (zoom centre in world units), plus shape knobs below
// ponytail: stills only; motion (unfurl = curl amount, sway) comes after the look is approved.

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
let NS = 1024                      // spine samples
let TR = 1024                      // lookup texture resolution

// shape (all in units of the frond's own length)
let K0 = envF("K0", 0.35)          // gentle bow of the stem part
let ACURL = envF("ACURL", 3.0)     // crozier tightness (log-spiral 1/b)
let SINF = envF("SINF", 1.02)      // where the spiral's eye sits in arc length (>1)
let S0 = envF("S0", 0.3)           // where the stem starts rolling
let W0 = envF("W0", 0.006)         // rachis half-width at the base
let CS = envF("CS", 0.34)          // child length at the base (× parent length)
let SP = envF("SP", 0.32)          // child spacing (× child length)
let LEAN = envF("LEAN", 0.55)      // child lean toward the tip (rad off the normal)
let MIR = envF("MIR", 1)           // which side's children are mirrored (curl toward the tip)
let LWF = envF("LWF", 0.5)         // leaflet blade half-width (× child length)

// MARK: - Spine (CPU)

struct Spine { var p: [SIMD2<Float>]; var th: [Float] }
func kappa(_ s: Float) -> Float {
    let t = min(max((s - (S0 - 0.15)) / 0.3, 0), 1), bl = t * t * (3 - 2 * t)
    return K0 + bl * ACURL / (SINF - s)
}
func buildSpine() -> Spine {
    var p = [SIMD2<Float>](repeating: .zero, count: NS), th = [Float](repeating: 0, count: NS)
    let ds = 1 / Float(NS - 1)
    for i in 1..<NS {
        let s = Float(i - 1) * ds
        let km = kappa(s + ds * 0.5)
        th[i] = th[i - 1] + km * ds
        let tm = (th[i - 1] + th[i]) * 0.5
        p[i] = p[i - 1] + SIMD2(cos(tm), sin(tm)) * ds
    }
    return Spine(p: p, th: th)
}
func sigma(_ s: Float) -> Float { CS * (SINF - s) / SINF }              // children shrink with the local coil radius
func width(_ s: Float) -> Float { W0 * (1 - 0.85 * s) }

struct Child { var root: SIMD2<Float>; var ang: Float; var scale: Float; var mirror: Float; var s: Float }
func buildChildren(_ sp: Spine) -> [Child] {
    var out: [Child] = []
    var s: Float = 0.05
    func at(_ s: Float) -> (SIMD2<Float>, Float) {
        let f = s * Float(NS - 1), i = min(Int(f), NS - 2), u = f - Float(i)
        return (sp.p[i] * (1 - u) + sp.p[i + 1] * u, sp.th[i] * (1 - u) + sp.th[i + 1] * u)
    }
    while s < 0.985 && out.count < 254 {
        let (P, th) = at(s), N = SIMD2<Float>(-sin(th), cos(th)), sg = sigma(s)
        for side: Float in [1, -1] {
            let ang = th + side * (Float.pi / 2 - LEAN)
            let mirror: Float = (side > 0) == (MIR > 0) ? 1 : 0
            out.append(Child(root: P + N * side * width(s) * 0.8, ang: ang, scale: sg, mirror: mirror, s: s))
        }
        s += SP * sg
    }
    return out
}

let spine = buildSpine()
let children = buildChildren(spine)
// bounding box of the whole subtree in the frond's frame: spine ± child reach
var bmin = SIMD2<Float>(repeating: 1e9), bmax = SIMD2<Float>(repeating: -1e9)
for i in 0..<NS {
    let s = Float(i) / Float(NS - 1), r = sigma(s) * 1.6 + 0.03
    bmin = simd_min(bmin, spine.p[i] - SIMD2(r, r)); bmax = simd_max(bmax, spine.p[i] + SIMD2(r, r))
}
FileHandle.standardError.write("children \(children.count)  bbox \(bmin) \(bmax)\n".data(using: .utf8)!)

// MARK: - Shader

struct Params {
    var bmin: SIMD2<Float>; var bmax: SIMD2<Float>
    var cam: SIMD4<Float>          // centre x, y, half-height of view, unused
    var top: SIMD4<Float>          // top frond root x, y, angle, length
    var shape: SIMD4<Float>        // W0, CS, SINF, LWF
    var misc: SIMD4<Float>         // child count, max levels, debug, unused
    var zm: SIMD4<Float> = .zero   // zoom: child k*, cycle fraction, ancestor lifts, on
    var zc: SIMD4<Float> = .zero   // zoom: fixed point x, y, view half-height at frac 0, unused
    var tm: SIMD4<Float> = .zero   // time, phi of the lifted ancestor's root, unused, pulse count
    var au: SIMD4<Float> = .zero   // bass, treble, hue base, unused
}

let msl = """
#include <metal_stdlib>
using namespace metal;

struct Params { float2 bmin; float2 bmax; float4 cam; float4 top; float4 shape; float4 misc; float4 zm; float4 zc; float4 tm; float4 au; };
struct Child { float2 root; float ang; float scale; float mirror; float s; float pad1; float pad2; };   // s: where it sits on its parent

static float width(float s, constant Params& P) { return P.shape.x * (1.0 - 0.85 * s); }
static float sigma(float s, constant Params& P) { return P.shape.y * (P.shape.z - s) / P.shape.z; }

// PASS 1 — per texel of the frond's frame: distance to the spine, its arc parameter, side, and distance to the
// SUBTREE (spine minus how far its children reach there)
kernel void spineField(constant float2* sp [[buffer(0)]], constant Params& P [[buffer(1)]],
                       texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float2 q = P.bmin + (float2(gid) + 0.5) / float(\(TR)) * (P.bmax - P.bmin);
    float best = 1e9, bs = 0.0, side = 1.0;
    for (int i = 0; i < \(NS - 1); i++) {
        float2 a = sp[i], b = sp[i + 1], ab = b - a;
        float u = clamp(dot(q - a, ab) / dot(ab, ab), 0.0, 1.0);
        float d = length(q - a - ab * u);
        if (d < best) { best = d; bs = (float(i) + u) / float(\(NS - 1)); side = (ab.x * (q - a).y - ab.y * (q - a).x) >= 0.0 ? 1.0 : -1.0; }
    }
    float reach = sigma(bs, P) * 1.05 + width(bs, P);
    out.write(float4(best, bs, side, best - reach), gid);
}

static float2 toChild(float2 q, constant Child& c) {
    float cs = cos(-c.ang), sn = sin(-c.ang);
    float2 d = q - c.root;
    float2 r = float2(cs * d.x - sn * d.y, sn * d.x + cs * d.y) / c.scale;
    return c.mirror > 0.5 ? float2(r.x, -r.y) : r;
}
constexpr sampler lin(filter::linear, address::clamp_to_edge);
static float4 field(texture2d<float> F, float2 q, constant Params& P) {
    float2 uv = (q - P.bmin) / (P.bmax - P.bmin);
    float4 f = F.sample(lin, uv);
    float2 o = max(max(P.bmin - q, q - P.bmax), 0.0);
    float out = length(o);
    return out > 0.0 ? float4(f.x + out, f.y, f.z, f.w + out) : f;
}

// PASS 1b — the TRUE distance to the whole infinite tree, by iterating its own definition on the texture:
// T(q) = min( this stem, min over children σ·T(child frame of q) ); each pass adds one level, converging geometrically.
// (A sausage-shaped reach estimate mis-assigned regions near the dive point and blanked the zoom.)
kernel void treeInit(texture2d<float> F [[texture(0)]], texture2d<float, access::write> T [[texture(1)]], constant Params& P [[buffer(1)]],
                     uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float4 f = F.read(gid);
    T.write(float4(f.x - width(f.y, P)), gid);
}
static float sampleT(texture2d<float> T, float2 q, constant Params& P) {
    float2 uv = (q - P.bmin) / (P.bmax - P.bmin);
    float2 o = max(max(P.bmin - q, q - P.bmax), 0.0);
    return T.sample(lin, uv).x + length(o);
}
kernel void treeIter(texture2d<float> F [[texture(0)]], texture2d<float> Tin [[texture(1)]], texture2d<float, access::write> Tout [[texture(2)]],
                     constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float2 q = P.bmin + (float2(gid) + 0.5) / float(\(TR)) * (P.bmax - P.bmin);
    float4 f = F.read(gid);
    float best = f.x - width(f.y, P);
    int n = int(P.misc.x);
    for (int k = 0; k < n; k++) { best = min(best, sampleT(Tin, toChild(q, ch[k]), P) * ch[k].scale); }
    Tout.write(float4(best), gid);
}
kernel void treeStore(texture2d<float> T [[texture(0)]], texture2d<float, access::read_write> F [[texture(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float4 f = F.read(gid); f.w = T.read(gid).x; F.write(f, gid);
}

// PASS 2 — per texel: which child's subtree is nearest (the descent's lookup)
kernel void childField(texture2d<float> F [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                       constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(TR)u || gid.y >= \(TR)u) { return; }
    float2 q = P.bmin + (float2(gid) + 0.5) / float(\(TR)) * (P.bmax - P.bmin);
    float best = 1e9; int bi = -1;
    int n = int(P.misc.x);
    for (int k = 0; k < n; k++) {
        float2 qc = toChild(q, ch[k]);
        float d = field(F, qc, P).w * ch[k].scale;
        if (d < best) { best = d; bi = k; }
    }
    out.write(float4(float(bi), best, 0.0, 0.0), gid);
}

// THE DESCENT — from a frame `q` whose frond has length `scale` (output units): signed distance (<0 inside), what was hit,
// and PHI — the nerve-impulse path coordinate: Σ (arc fraction along each stem) from the starting root, so an impulse
// crosses every stem in the same time (conduction ∝ size) and fans out from trunk to every leaflet tip
struct Res { float d; float lvl; float s; float vein; float across; float h; float id; float nvein; float phi; };
static Res descendFrom(float2 q, float scale, float phi0, texture2d<float> F, texture2d<float> C, constant Child* ch, constant Params& P, float pix) {
    Res r; r.d = 1e9; r.lvl = -1.0; r.s = 0.0; r.vein = 0.0; r.across = 0.0; r.h = 0.0; r.id = 0.0; r.nvein = 0.0; r.phi = phi0;
    float phi = phi0;
    int maxL = int(P.misc.y);
    for (int L = 0; L <= maxL; L++) {
        float4 f = field(F, q, P);
        float rach = (f.x - width(f.y, P)) * scale;                      // this level's rachis (a vein)
        r.vein = max(r.vein, smoothstep(pix * 1.2, -pix * 0.5, rach) * (1.0 - 0.12 * float(L)));
        if (rach < r.d) { r.d = rach; r.lvl = float(L); r.s = f.y; r.across = 0.0; r.phi = phi + f.y; }
        { float wr = width(f.y, P); r.h = max(r.h, sqrt(max(wr * wr - f.x * f.x, 0.0)) * scale * 1.2); }   // stems are round
        bool last = (L == maxL) || (scale * sigma(f.y, P) < pix * 2.5);  // children below ~2 px: this frond is a leaflet
        if (last) {
            float lw = sigma(f.y, P) * P.shape.w + width(f.y, P);
            float blade = f.w * scale;                                     // the blade = the whole subtree's true silhouette
            if (blade < r.d) { r.d = blade; r.lvl = float(L) + 0.5; r.s = f.y; r.across = clamp(f.x / lw, 0.0, 1.0) * f.z; r.phi = phi + f.y; }
            float ub = clamp(f.x / lw, 0.0, 1.0);
            r.h = max(r.h, lw * 0.3 * sqrt(max(1.0 - ub * ub, 0.0)) * scale);   // each leaflet a shallow dome
            // VENATION: the next level's stems, drawn as fine veins inside the blade (the detail one zoom step ahead)
            uint2 tv = uint2(clamp((q - P.bmin) / (P.bmax - P.bmin), 0.0, 0.9999) * float(\(TR)));
            int kv = int(C.read(tv).x + 0.5);
            if (kv >= 0) { float4 fc = field(F, toChild(q, ch[kv]), P); float vd = (fc.x - width(fc.y, P) * 0.6) * scale * ch[kv].scale;
                           r.nvein = smoothstep(pix * 0.9, -pix * 0.2, vd); }
            break;
        }
        if (f.w * scale > r.d && r.d < 0.0) { break; }                   // already inside something nearer
        uint2 t = uint2(clamp((q - P.bmin) / (P.bmax - P.bmin), 0.0, 0.9999) * float(\(TR)));
        float4 c = C.read(t);
        int k0 = int(c.x + 0.5);
        if (k0 < 0 || c.y > 0.5) { break; }                               // not inside any child's reach
        // the lookup is texel-coarse (blocky at deep zoom): re-decide EXACTLY among its neighbours along the stem, both sides
        int n = int(P.misc.x), k = k0; float bd = 1e9;
        for (int j = -4; j <= 5; j++) {
            int kk = (k0 & ~1) + j;                                       // children are stored in (left, right) pairs
            if (kk < 0 || kk >= n) { continue; }
            float dk = field(F, toChild(q, ch[kk]), P).w * ch[kk].scale;
            if (dk < bd) { bd = dk; k = kk; }
        }
        if (bd > 0.25) { break; }                                       // far from every child (the reach estimate is crude near tips: a tight cut-off blanked lifted views)
        phi += ch[k].s;
        q = toChild(q, ch[k]);
        scale *= ch[k].scale;
        r.id = fract(r.id * 7.31 + float(k) * 0.1373 + 0.17);
    }
    return r;
}

static float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
// screen uv → descent. Stills: the top frond placed in the world. ZOOM: the camera dives toward the fixed point of child k*
// (the point that child k* maps onto itself): after one cycle the view is exactly the same picture one level down, so
// the zoom loops seamlessly forever; the frame is LIFTED a few ancestors up so siblings surround the view at every depth
static Res look(float2 uv, constant Params& P, texture2d<float> F, texture2d<float> C, constant Child* ch, float res_y, thread float& pixOut) {
    if (P.zm.w > 0.5) {
        constant Child& K = ch[int(P.zm.x)];
        float half_ = P.zc.z * pow(K.scale, P.zm.y);
        float2 q = P.zc.xy + rot(uv * 2.0 * half_, K.ang * P.zm.y);
        float pix = 2.0 * half_ / res_y; pixOut = pix;
        float scale = 1.0;
        int lifts = int(P.zm.z);
        for (int m = 0; m < lifts; m++) { q = K.root + rot(q * K.scale, K.ang); scale /= K.scale; }   // child → parent
        return descendFrom(q, scale, P.tm.y, F, C, ch, P, pix);
    }
    float pix = 2.0 * P.cam.z / res_y; pixOut = pix;
    float2 pw = P.cam.xy + uv * 2.0 * P.cam.z;
    float2 q = rot(pw - P.top.xy, -P.top.z) / P.top.w;
    if (P.cam.w > 0.5) { q.y = -q.y; }                                   // coil rolls clockwise (reference)
    return descendFrom(q, P.top.w, 0.0, F, C, ch, P, pix);
}

static float3 hsv(float h, float s, float v) { float3 k = clamp(abs(fract(h + float3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0) - 1.0, 0.0, 1.0); return v * mix(float3(1.0), k, s); }
static float hsh(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

kernel void render(texture2d<float> F [[texture(0)]], texture2d<float> C [[texture(1)]], texture2d<float, access::write> out [[texture(2)]],
                   constant Child* ch [[buffer(0)]], constant Params& P [[buffer(1)]], constant float2* pulses [[buffer(2)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    float2 res = float2(float(\(W)u), float(\(H)u));
    float t = P.tm.x, hue0 = P.au.z;
    float3 acc = 0.0;
    const float2 o4[4] = { float2(0.25, 0.25), float2(0.75, 0.25), float2(0.25, 0.75), float2(0.75, 0.75) };
    for (int a = 0; a < 4; a++) {
        float2 uv = (float2(gid) + o4[a] - 0.5 * res) / res.y * float2(1.0, -1.0);
        float pix;
        Res r = look(uv, P, F, C, ch, res.y, pix);
        float px1 = 1.0 / res.y;
        float pd; Res rx = look(uv + float2(px1, 0.0), P, F, C, ch, res.y, pd), ry = look(uv + float2(0.0, px1), P, F, C, ch, res.y, pd);
        float3 n = normalize(float3(-(rx.h - r.h) / pix, -(ry.h - r.h) / pix, 1.0));
        float3 Ld = normalize(float3(-0.5, 0.55, 0.65));
        float dif = clamp(dot(n, Ld), 0.0, 1.0);
        float spec = pow(clamp(dot(reflect(-Ld, n), float3(0.0, 0.0, 1.0)), 0.0, 1.0), 30.0);
        float cov = smoothstep(pix * 0.7, -pix * 0.7, r.d);
        // NERVE IMPULSES: each pulse is a front moving down PHI (trunk → branches → leaflet tips): sharp head, glowing tail
        float pulse = 0.0;
        int np = int(P.tm.w);
        for (int i = 0; i < np; i++) {
            float dphi = pulses[i].x - r.phi;                             // > 0: the front has passed this point
            float head = exp(-dphi * dphi / 0.0016), tail = dphi > 0.0 ? exp(-dphi / 0.18) : 0.0;
            pulse += pulses[i].y * (head * 1.6 + tail * 0.5);
        }
        float ripple = 0.5 + 0.5 * sin(6.2831853 * (r.phi * 2.0 - t * 0.6));    // a slow wave rolling down the body (bass)
        float shimmer = step(1.0 - 0.25 * P.au.y, hsh(float2(r.id * 97.0 + floor(r.s * 9.0), floor(t * 18.0))));   // treble glitter, per leaflet
        // COLOUR BATH: hue drifts along the impulse path and by level, so the branching reads as bands of colour
        float hue = hue0 + 0.11 * r.phi + 0.05 * floor(r.lvl) + 0.03 * sin(t * 0.2);
        float mid = 1.0 - abs(r.across);
        float3 body = hsv(hue, 0.75, 0.10 + 0.28 * dif * (0.6 + 0.4 * mid));
        float wv = max(r.vein, r.nvein * 0.7);                            // stems and veins at every level carry the light
        float3 glow = hsv(hue + 0.08, 0.55, 1.0) * wv * (0.12 + 0.35 * P.au.x * ripple + 2.2 * pulse);
        float rim = smoothstep(-pix * 3.0, -pix * 0.3, r.d) * cov;        // leaflet edges catch the light
        float3 edge = hsv(hue + 0.33, 0.8, 1.0) * rim * (0.08 + 0.6 * pulse + 0.25 * shimmer);
        float3 col = body * (1.0 + 1.2 * pulse) + glow + edge + float3(1.0, 0.95, 0.9) * spec * 0.25;
        if (P.misc.z > 0.5) { col = float3(fract(r.lvl * 0.37), fract(r.lvl * 0.61 + 0.3), fract(r.lvl * 0.17 + 0.6)) * (0.4 + 0.6 * dif); }
        // the bath behind: slow fields of colour, never black
        float3 bg = hsv(hue0 + 0.5 + 0.15 * uv.x + 0.05 * sin(t * 0.13 + uv.y * 2.0), 0.85, 0.035 + 0.02 * sin(uv.x * 2.0 + t * 0.2));
        acc += mix(bg, col, cov);
    }
    acc *= 0.25;
    acc = acc / (1.0 + dot(acc, float3(0.299, 0.587, 0.114)) * 0.6);     // soft shoulder for the hot pulses
    out.write(float4(pow(clamp(acc, 0.0, 1.0), float3(1.0 / 2.2)), 1.0), gid);
}
"""

// MARK: - Host

let device = MTLCreateSystemDefaultDevice()!
let lib: MTLLibrary
do { lib = try device.makeLibrary(source: msl, options: nil) } catch { FileHandle.standardError.write("\(error)\n".data(using: .utf8)!); exit(1) }
let queue = device.makeCommandQueue()!
func pso(_ n: String) -> MTLComputePipelineState { try! device.makeComputePipelineState(function: lib.makeFunction(name: n)!) }
func tex(_ f: MTLPixelFormat, _ w: Int, _ h: Int) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: w, height: h, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)!
}

struct ChildGPU { var root: SIMD2<Float>; var ang: Float; var scale: Float; var mirror: Float; var p0: Float = 0; var p1: Float = 0; var p2: Float = 0 }
var chg = children.map { ChildGPU(root: $0.root, ang: $0.ang, scale: $0.scale, mirror: $0.mirror, p0: $0.s) }
let chBuf = device.makeBuffer(bytes: &chg, length: MemoryLayout<ChildGPU>.stride * max(chg.count, 1), options: .storageModeShared)!
var spts = spine.p
let spBuf = device.makeBuffer(bytes: &spts, length: MemoryLayout<SIMD2<Float>>.stride * NS, options: .storageModeShared)!

let zoom = envF("ZOOM", 1)
var P = Params(bmin: bmin, bmax: bmax,
               cam: [envF("ZX", 0.0), envF("ZY", 0.0), envF("VIEW", 1.0) / zoom, envF("FLIP", 1)],
               top: [envF("TX", -0.5), envF("TY", -1.55), envF("TA", 1.75), envF("TL", 3.4)],
               shape: [W0, CS, SINF, LWF],
               misc: [Float(children.count), envF("MAXL", 12), envF("DBG", 0), 0])

let F = tex(.rgba32Float, TR, TR), C = tex(.rgba32Float, TR, TR), outT = tex(.rgba8Unorm, W, H)
let TA = tex(.r32Float, TR, TR), TB = tex(.r32Float, TR, TR)
let tg = MTLSize(width: 16, height: 16, depth: 1)
do {
    let cb = queue.makeCommandBuffer()!, ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(pso("spineField")); ce.setBuffer(spBuf, offset: 0, index: 0); ce.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1)
    ce.setTexture(F, index: 0); ce.dispatchThreads(MTLSize(width: TR, height: TR, depth: 1), threadsPerThreadgroup: tg)
    ce.setComputePipelineState(pso("treeInit")); ce.setTexture(F, index: 0); ce.setTexture(TA, index: 1); ce.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1)
    ce.dispatchThreads(MTLSize(width: TR, height: TR, depth: 1), threadsPerThreadgroup: tg)
    var src = TA, dst = TB
    for _ in 0..<Int(envF("TITER", 8)) {
        ce.setComputePipelineState(pso("treeIter")); ce.setTexture(F, index: 0); ce.setTexture(src, index: 1); ce.setTexture(dst, index: 2)
        ce.setBuffer(chBuf, offset: 0, index: 0); ce.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1)
        ce.dispatchThreads(MTLSize(width: TR, height: TR, depth: 1), threadsPerThreadgroup: tg)
        swap(&src, &dst)
    }
    ce.setComputePipelineState(pso("treeStore")); ce.setTexture(src, index: 0); ce.setTexture(F, index: 1)
    ce.dispatchThreads(MTLSize(width: TR, height: TR, depth: 1), threadsPerThreadgroup: tg)
    ce.setComputePipelineState(pso("childField")); ce.setTexture(F, index: 0); ce.setTexture(C, index: 1); ce.setBuffer(chBuf, offset: 0, index: 0)
    ce.setBytes(&P, length: MemoryLayout<Params>.stride, index: 1); ce.dispatchThreads(MTLSize(width: TR, height: TR, depth: 1), threadsPerThreadgroup: tg)
    ce.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    FileHandle.standardError.write(String(format: "fields %.1f ms\n", (cb.gpuEndTime - cb.gpuStartTime) * 1000).data(using: .utf8)!)
}
let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared)!
let renderPSO = pso("render")
let pulseBuf = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * 32, options: .storageModeShared)!

// MARK: - Zoom loop

// child k* (a non-mirrored one, so one cycle maps the picture onto itself) and its fixed point x* = root + σR·x*
var kstar = min(Int(envF("KSTAR", 17)), children.count - 1)
if children[kstar].mirror > 0.5 { kstar = kstar ^ 1 }
let K = children[kstar]
let fixedPoint: SIMD2<Float> = {
    let c = cos(K.ang) * K.scale, sn = sin(K.ang) * K.scale
    let a = 1 - c, det = a * a + sn * sn
    return SIMD2((a * K.root.x - sn * K.root.y) / det, (sn * K.root.x + a * K.root.y) / det)
}()
let lifts: Float = envF("LIFTS", 3)
let zoomPeriod = envF("TZ", 7)                     // seconds per level dived
let pulseSpeed = envF("SPD", 0.5)                  // path units per second (≈ one stem per 2 s)
func setZoom(time t: Float) {
    let u = t / zoomPeriod, cyc = floor(u)
    P.zm = [Float(kstar), u - cyc, lifts, 1]
    P.zc = [fixedPoint.x, fixedPoint.y, envF("V0", 0.55), 0]
    P.tm.x = t; P.tm.y = (cyc - lifts) * K.s
}
// stand-in music until it is wired to real analysis: a beat at BPM with accents, a bass envelope, treble shimmer
func setMusic(time t: Float) {
    let bpm = envF("BPM", 112), beat = 60 / bpm
    var arr: [SIMD2<Float>] = []
    var tb = floor(t / beat) * beat
    while tb > t - 8 && arr.count < 32 {
        let n = Int(tb / beat + 0.5), amp: Float = n % 4 == 0 ? 1.0 : (n % 2 == 0 ? 0.55 : 0.3)
        let emit = (tb / zoomPeriod - 1) * K.s                           // emitted into the trunk just above the view
        arr.append(SIMD2(emit + pulseSpeed * (t - tb), amp))
        tb -= beat
    }
    memcpy(pulseBuf.contents(), arr, MemoryLayout<SIMD2<Float>>.stride * arr.count)
    P.tm.w = Float(arr.count)
    let ph = t.truncatingRemainder(dividingBy: beat)
    P.au.x = exp(-ph / 0.3); P.au.y = 0.5 + 0.5 * sin(t * 3.1) * sin(t * 1.7)
    P.au.z = envF("HUE", 0.33) + 0.01 * t
}
FileHandle.standardError.write("k* \(kstar)  σ \(K.scale)  ang \(K.ang)  s \(K.s)  x* \(fixedPoint)\n".data(using: .utf8)!)
func renderFrame() -> Double {
    let cb = queue.makeCommandBuffer()!, ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(renderPSO); ce.setTexture(F, index: 0); ce.setTexture(C, index: 1); ce.setTexture(outT, index: 2)
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

let args = CommandLine.arguments
if args.count > 2 && args[1] == "still" {
    if envF("ZOOMMODE", 0) > 0.5 { setZoom(time: envF("T", 0)); setMusic(time: envF("T", 0)) } else { P.au.z = envF("HUE", 0.33) }
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
