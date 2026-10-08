// fiddlehead.swift — FH look-spike (throwaway; not engine code, imports nothing from Uzume).
//
// FH.3: the botanical fern rule, generated EXACTLY down to the pixel, toward Matt's 2026-10-05
// reference (docs/VISUAL_REFERENCES/fiddlehead/01_reference_matt_2026-10-05.webp). Matt's gap:
// "the level of FRACTAL detail". The feedback IFS (fiddlehead_ifs.swift) resamples every frame and
// smears its fine levels. Here the CPU walks the branching rule every frame until elements are a
// pixel wide, and the GPU draws each element as a crisp signed-distance shape — every level stays
// sharp and outlined. (A per-pixel walk of the same tree gave the same image but cost thousands of
// steps per pixel; the GPU watchdog killed it.)
//
// Botany (research 2026-10-05; Vasco/Moran/Ambrose 2013; ABOP §5.3; Prusinkiewicz et al. SIGGRAPH 93):
//   - every pinna is itself a crozier, every pinnule too: ONE rule at every level
//   - the rachis coils as a log spiral (each link σ× shorter, turned by the local curl), toward its
//     inner face; pinnae flank it and curl the same way as their parent; packed tightest at the centre
//   - unfurling travels base → tip; a pinna starts unrolling only once the front has passed its
//     junction (the ABOP delay), pinnules after their pinna; the coil rises as the stalk lengthens
//   - sway: stiff base, whippy tip — bend grows along the frond and lags behind the base
//   - colour by age: young (coiled) tissue paler/warmer and more translucent, opened tissue deeper green
// Rendering (HDR fractal-art practice): a thin bright rim on every element at every scale, beads,
// warm light inside the coil, 2× supersampling, bloom, x/(1+x) tone.
//
// Build:  swiftc -O -swift-version 5 fiddlehead.swift -o /tmp/fiddlehead
// Usage:  fiddlehead still <unfurl 0…1> <out.png>
//         fiddlehead film <seconds> <out.mp4>

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
    float4 view;   // render-target size (xy), world units per render pixel (z), time (w)
    float4 cam;    // world centre of the view (xy), unused, unused
    float4 light;  // coil eye in world (xy), radius (z), intensity (w)
    float4 look;   // body, rim, bead, debug
};

// a: origin (world xy), heading (rad, clockwise from up; world y is down), link length (world)
// b: half-width (× link length), leafiness, level, f (fraction of its chain travelled)
// c: hash, spin, curl (0 open … 1 coiled), age
struct Elem { float4 a; float4 b; float4 c; };

struct VOut {
    float4 pos [[position]];
    float2 local;                 // in link units: x across, y along (0 → 1)
    float2 world;
    float4 a [[flat]]; float4 b [[flat]]; float4 c [[flat]];
};

vertex VOut elem_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                        const device Elem* es [[buffer(0)]], constant U& u [[buffer(1)]]) {
    Elem e = es[iid];
    float L = e.a.w;
    float2 dir = float2(sin(e.a.z), -cos(e.a.z)), nrm = float2(cos(e.a.z), sin(e.a.z));
    float pad = e.b.x + 2.0 * u.view.z / L;                     // half-width + 2 px, in link units
    const float2 corners[6] = { float2(-1, 0), float2(1, 0), float2(1, 1), float2(-1, 0), float2(1, 1), float2(-1, 1) };
    float2 k = corners[vid];
    float2 local = float2(k.x * pad, mix(-pad, 1.0 + pad, k.y));
    float2 w = e.a.xy + (dir * local.y + nrm * local.x) * L;
    float2 s = (w - u.cam.xy) / u.view.z + 0.5 * u.view.xy;
    VOut o;
    o.pos = float4(s.x / u.view.x * 2.0 - 1.0, 1.0 - s.y / u.view.y * 2.0, 0.0, 1.0);
    o.local = local; o.world = w; o.a = e.a; o.b = e.b; o.c = e.c;
    return o;
}

// Signed distance (link units) to one link (0,0)→(0,1): a pointed blade (leafy=1) or a capsule
// (leafy=0). Returns (sd, lateral −1…1, along 0…1).
static float3 linkSD(float2 p, float hw, float leafy) {
    float y = clamp(p.y, 0.0, 1.0);
    // Leaf: broadest ~40 % out, pointed tip, serrated margin (teeth toward the tip).
    float serr = 1.0 - 0.12 * leafy * pow(fract(y * 11.0), 1.5);
    float prof = mix(1.0, pow(max(sin(3.14159 * pow(mix(0.03, 0.97, y), 0.8)), 0.0), 0.75) * serr, leafy);
    float w = hw * max(prof, 0.06);
    float d = length(float2(p.x, p.y - y));
    return float3(d - w, clamp(p.x / w, -1.0, 1.0), y);
}

static float hash11(float x) { return fract(sin(x * 91.3458) * 47453.5453); }

// The reference's rim colours, cycled: violet → blue → cyan → gold → magenta → violet.
static float3 irid(float t) {
    const float3 k[5] = { float3(0.55, 0.20, 1.00), float3(0.15, 0.40, 1.00), float3(0.10, 0.95, 0.90),
                          float3(1.00, 0.65, 0.10), float3(1.00, 0.25, 0.70) };
    float x = fract(t) * 5.0;
    int i = int(x);
    return mix(k[i % 5], k[(i + 1) % 5], smoothstep(0.0, 1.0, fract(x)));
}

fragment float4 elem_fragment(VOut in [[stage_in]], constant U& u [[buffer(1)]]) {
    float L = in.a.w, px = u.view.z;
    float hwRel = in.b.x, level = in.b.z, f = in.b.w;
    float hashv = in.c.x, spin = in.c.y, curl = in.c.z, age = in.c.w;
    float3 e = linkSD(in.local, hwRel, in.b.y);
    float sd = e.x * L;
    float a = 1.0 - smoothstep(-0.6 * px, 0.6 * px, sd);
    if (a <= 0.0) { discard_fragment(); }
    float t = u.view.w;
    float2 dl = (in.world - u.light.xy) / u.light.z;
    float L2 = u.light.w * exp(-dot(dl, dl));
    float s = e.y, as = abs(s);
    float sizePx = hwRel * L / px;
    float detail = smoothstep(1.0, 4.0, sizePx);
    // Colour by age: young (coiled) tissue paler, warmer, more translucent; opened tissue deep green.
    float young = saturate(curl * 0.8 + (1.0 - saturate(age)) * 0.2);
    float3 warmSide = mix(float3(0.16, 0.46, 0.04), float3(0.48, 0.70, 0.10), young);
    float3 coolSide = mix(float3(0.02, 0.28, 0.20), float3(0.08, 0.50, 0.34), young);
    float3 green = mix(coolSide, warmSide, smoothstep(-0.8, 0.8, s * spin));
    float tube = sqrt(saturate(1.0 - as * as));
    float midrib = (1.0 - smoothstep(0.0, 0.16, as)) * detail * step(0.5, level);
    float vein = smoothstep(0.80, 1.0, 1.0 - abs(fract(e.z * 6.0 - as * 1.3) - 0.5) * 2.0) * (1.0 - as) * detail * step(0.5, level);
    float3 col = green * u.look.x * (0.30 + 0.55 * tube + 0.35 * midrib + 0.25 * vein);
    // Light from inside the coil passes through: warm transmission, more through young tissue.
    col = mix(col, float3(0.95, 0.40, 0.05) * (0.55 + 0.5 * tube + 0.4 * vein), saturate(L2) * mix(0.35, 0.95, young));
    // The rim: every element, at every level, carries a thin bright iridescent edge.
    float rimW = max(0.9 * px, 0.14 * hwRel * L);
    float rim = 1.0 - smoothstep(0.0, rimW, -sd);
    if (in.b.y < 0.5) { rim *= smoothstep(0.35, 0.8, as); }    // stems: rims along the sides only, no joint dashes
    float3 ir = irid(hashv * 1.7 + level * 0.21 + f * 0.5 + t * 0.03);
    col = mix(col, ir * (0.75 + 0.6 * L2), rim * u.look.y * mix(0.12, 0.95, detail));   // tiny elements are all rim: keep them green
    // Beads: a bright drop on the points of the small curled elements.
    float tip = smoothstep(0.8, 1.0, e.z) * (1.0 - smoothstep(0.2, 0.7, as)) * curl * step(0.5, level);
    float tw = 0.6 + 0.4 * sin(t * (1.3 + 2.0 * hashv) + hashv * 40.0);
    col += float3(1.0, 0.88, 0.66) * tip * tw * u.look.z * step(0.55, hash11(hashv * 31.0 + f * 17.0));
    return float4(col * a, a);
}

// MARK: present: the out-of-focus garden, the lit fern, bloom

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

kernel void present(texture2d<float> lit [[texture(0)]],
                    texture2d<float, access::write> out [[texture(1)]],
                    constant U& u [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]]) {
    float2 size = float2(out.get_width(), out.get_height());
    if (any(float2(gid) >= size)) { return; }
    float2 s = float2(gid) + 0.5;
    float2 uv = s / size;
    float aspect = size.x / size.y;
    float t = u.view.w;
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
    const float4 gx[3] = { float4(0.08, 1.02, 1.5, -1.0), float4(0.92, 1.05, 1.7, -1.0), float4(0.55, 1.22, 1.3, 1.0) };
    for (int i = 0; i < 3; i++) {
        float2 g = (uv - gx[i].xy) / gx[i].z;
        g.x *= gx[i].w;
        bg += blur(lit, float2(0.45, 0.55) + g, 4.0).rgb * 0.22 * float3(0.75, 0.7, 1.0) * smoothstep(0.45, 0.95, uv.y);
    }
    float2 world = u.cam.xy + (s - 0.5 * size) * (u.view.z * u.view.x / size.x);
    float2 dl = (world - u.light.xy) / (u.light.z * 1.8);
    bg += float3(0.9, 0.38, 0.06) * 0.22 * u.light.w * exp(-dot(dl, dl));
    float4 fern = lit.sample(lin, uv, level(1.0));             // lit is 2× supersampled
    float3 col = bg * (1.0 - fern.a) + fern.rgb;
    col += blur(lit, uv, 2.0).rgb * 0.30 + blur(lit, uv, 4.0).rgb * 0.25 + blur(lit, uv, 6.0).rgb * 0.30;
    float2 v = uv - 0.5; col *= 1.0 - 0.6 * dot(v, v);
    col = col / (1.0 + col) * 1.35;                            // x/(1+x) tone
    col = pow(max(col, 0.0), float3(1.0 / 1.05));
    if (int(u.look.w) >= 1) { col = fern.rgb; }
    out.write(float4(saturate(col), 1.0), gid);
}
"""

// MARK: - Host

let args = CommandLine.arguments
let env = ProcessInfo.processInfo.environment
func envF(_ k: String, _ d: Float) -> Float { env[k].flatMap(Float.init) ?? d }

struct Uniforms { var view: SIMD4<Float>; var cam: SIMD4<Float>; var light: SIMD4<Float>; var look: SIMD4<Float> }
struct Elem { var a: SIMD4<Float>; var b: SIMD4<Float>; var c: SIMD4<Float> }

let outW = Int(envF("W", 1920)), outH = Int(envF("H", 1080)), ss = 2

let device = MTLCreateSystemDefaultDevice()!
let library = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
let presentPSO = try! device.makeComputePipelineState(function: library.makeFunction(name: "present")!)
let elemPSO: MTLRenderPipelineState = {
    let d = MTLRenderPipelineDescriptor()
    d.vertexFunction = library.makeFunction(name: "elem_vertex")
    d.fragmentFunction = library.makeFunction(name: "elem_fragment")
    let c = d.colorAttachments[0]!
    c.pixelFormat = .rgba16Float
    c.isBlendingEnabled = true                                  // premultiplied "over"
    c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
    c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    return try! device.makeRenderPipelineState(descriptor: d)
}()

func tex(_ w: Int, _ h: Int, _ fmt: MTLPixelFormat, mips: Bool) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: mips)
    d.usage = [.shaderRead, .shaderWrite, .renderTarget]
    d.storageMode = .private
    return device.makeTexture(descriptor: d)!
}
let litTex = tex(outW * ss, outH * ss, .rgba16Float, mips: true)
let outTex = tex(outW, outH, .rgba8Unorm, mips: false)
let readback = device.makeBuffer(length: outW * outH * 4, options: .storageModeShared)!
let maxElems = 3_000_000
let elemBuf = device.makeBuffer(length: maxElems * MemoryLayout<Elem>.stride, options: .storageModeShared)!

func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = min(1, max(0, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t)
}
func fract(_ x: Float) -> Float { x - x.rounded(.down) }

// MARK: the fern rule

struct Rule {
    var sig = envF("SIG", 0.93), sigS = envF("SIGS", 0.30)          // link shrink; branch scale
    var alpha = envF("ALPHA", 1.05), attach = envF("ATTACH", 0.5)   // branch angle; where on a link it leaves
    var maxTurn = envF("TURN", 0.31), ramp = envF("RAMP", 0.10)     // coil turn per link; open → coiled width
    var baseTurn = envF("BT", -0.02), delay = envF("DELAY", 0.15)     // open-part bend; branch front delay
    var hw = envF("HW", 0.22), leafy = envF("LEAFY", 0.85), spinChild = envF("SPIN", 1)
    var swayGain = envF("SWAY", 0.0), swayLag = envF("SWLAG", 1.2)
    var maxLevel = Int(envF("MAXL", 2))                               // this level is drawn as single leaf blades
    var stemW: [Float] = [envF("SW0", 0.10), envF("SW1", 0.14), envF("SW2", 0.16)]   // stem half-width × link
    var leafLen = envF("LEAFLEN", 0.30), leafW = envF("LEAFW", 0.30), leafCurl = envF("LEAFCURL", 0.5)
    var leafAlpha = envF("LALPHA", 0.95)                              // pinnule angle off its pinna
    var immature = envF("IMM", 0.35)                                  // branch size in the coil ÷ open size
}
let rule = Rule()
var elems = UnsafeMutablePointer<Elem>(OpaquePointer(elemBuf.contents()))
var count = 0
var px: Float = 0
var swayPhase: Float = 0

/// One chain (rachis, pinna, pinnule …): walk its links, emitting each, branching on both sides.
func chain(_ p0: SIMD2<Float>, heading h0: Float, link S0: Float, front: Float, spin: Float, level: Int, hash: Float, age: Float) {
    let total = 1 / (1 - rule.sig)
    // The finest level is a real leaf: one pointed, serrated blade (the reference's pinnules), bent
    // toward the coil while its parent is still curled.
    if level >= rule.maxLevel {
        let len = total * S0 * rule.leafLen
        guard len * rule.leafW > 0.3 * px, count < maxElems - 1 else { return }
        elems[count] = Elem(a: [p0.x, p0.y, h0 + spin * rule.leafCurl * (1 - front / 0.75), len],
                            b: [rule.leafW, 1, Float(level), 0], c: [hash, spin, 1 - front / 0.75, age + 0.5])
        count += 1
        return
    }
    var p = p0, h = h0, S = S0
    var k = 0
    while total * S > 0.5 * px && count < maxElems - 4 && k < 400 {
        let f = 1 - pow(rule.sig, Float(k))
        let c = smooth(front, front + rule.ramp, f)
        let bend = rule.swayGain * sin(swayPhase - rule.swayLag * f) * f * (level == 0 ? 1 : 0.4)
        let turn = spin * (rule.baseTurn * (1 - c) + rule.maxTurn * c) + bend * (1 - rule.sig)
        let hwRel = rule.stemW[min(level, 2)]
        let elAge = age + (1 - c) * 0.5
        if hwRel * S > 0.2 * px {
            elems[count] = Elem(a: [p.x, p.y, h, S], b: [hwRel, 0, Float(level), f],
                                c: [hash, spin, c, elAge])
            count += 1
        }
        // Branches: the same rule one level down, curling the same way as the parent; a branch's own
        // front starts only once the parent's front has passed this junction (ABOP delay).
        // Branches near the coiled tip are immature: smaller than the open ones below (botany: the coil
        // holds the youngest tissue). Measured on the reference: rim croziers ≈ ⅓ the open-rule size.
        let bS = S * rule.sigS * (1 - (1 - rule.immature) * c)
        if total * bS > 0.5 * px {
            let passed = min(1, max(0, (front - f) / max(rule.delay, 1e-3)))
            let dir = SIMD2<Float>(sin(h), -cos(h))
            let at = p + dir * (rule.attach * S)
            for side: Float in [-1, 1] {
                let bh = fract(hash * 7.31 + Float(k) * 0.618 + (side > 0 ? 0.29 : 0.71))
                let ang = (level + 1 >= rule.maxLevel ? rule.leafAlpha : rule.alpha) * (1 - 0.25 * c)
                chain(at, heading: h + side * ang, link: bS, front: passed * 0.75,
                      spin: spin * rule.spinChild, level: level + 1, hash: bh, age: elAge)
            }
        }
        p += SIMD2<Float>(sin(h), -cos(h)) * S
        h += turn
        S *= rule.sig
        k += 1
    }
    if level == 0 { eye = p }
}
var eye = SIMD2<Float>(0, 0)

func render(unfurl: Float, phase: Float, time: Float) {
    let zoom = 1 + (envF("ZOOM", 1.5) - 1) * unfurl * unfurl
    px = zoom / Float(outH * ss)
    swayPhase = phase
    let front = envF("F0", 0.30) + (1 - envF("F0", 0.30)) * unfurl
    let base = SIMD2<Float>(envF("BX", -0.30), envF("BY", 0.62))
    let seg0 = envF("SEG", 0.13) * (1 + envF("GROW", 0.25) * unfurl)   // the stalk lengthens as it opens
    count = 0
    chain(base, heading: envF("LEAN", 0.05), link: seg0, front: front, spin: envF("HAND", 1), level: 0, hash: 0.37, age: 0)
    var u = Uniforms(view: [Float(outW * ss), Float(outH * ss), px, time],
                     cam: [envF("CX", 0.0), envF("CY", 0.0), 0, 0],
                     light: [eye.x, eye.y, envF("LR", 0.10) * (1 + 2 * unfurl), envF("LI", 1.0) * (1 - 0.6 * unfurl)],
                     look: [envF("BODY", 1.0), envF("RIM", 1.0), envF("BEAD", 2.5), envF("DBG", 0)])
    let cb = queue.makeCommandBuffer()!
    let rp = MTLRenderPassDescriptor()
    rp.colorAttachments[0].texture = litTex
    rp.colorAttachments[0].loadAction = .clear
    rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    rp.colorAttachments[0].storeAction = .store
    let re = cb.makeRenderCommandEncoder(descriptor: rp)!
    re.setRenderPipelineState(elemPSO)
    re.setVertexBuffer(elemBuf, offset: 0, index: 0)
    re.setVertexBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
    re.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 1)
    if count > 0 { re.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count) }
    re.endEncoding()
    let mb = cb.makeBlitCommandEncoder()!; mb.generateMipmaps(for: litTex); mb.endEncoding()
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(presentPSO)
    ce.setTexture(litTex, index: 0); ce.setTexture(outTex, index: 1)
    ce.setBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
    ce.dispatchThreads(MTLSize(width: outW, height: outH, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    ce.endEncoding()
    let bb = cb.makeBlitCommandEncoder()!
    bb.copy(from: outTex, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
            sourceSize: MTLSize(width: outW, height: outH, depth: 1), to: readback,
            destinationOffset: 0, destinationBytesPerRow: outW * 4, destinationBytesPerImage: outW * outH * 4)
    bb.endEncoding()
    cb.commit(); cb.waitUntilCompleted()
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
    let t0 = Date()
    render(unfurl: Float(args[2])!, phase: 0, time: 3)
    FileHandle.standardError.write("frame: \(Int(Date().timeIntervalSince(t0) * 1000)) ms, elements: \(count)\n".data(using: .utf8)!)
    writePNG(args[3])
case "film":
    let seconds = Float(args[2])!, fps: Float = 30
    let ff = Process()
    ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", "\(outW)x\(outH)",
                    "-r", "30", "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", args[3]]
    let pipeIn = Pipe(); ff.standardInput = pipeIn
    try! ff.run()
    for i in 0..<Int(seconds * fps) {
        let t = Float(i) / fps
        let unfurl = 0.5 - 0.5 * cos(2 * Float.pi * t / seconds)
        render(unfurl: unfurl, phase: 2 * Float.pi * t / 4.0, time: t)
        pipeIn.fileHandleForWriting.write(Data(bytes: readback.contents(), count: outW * outH * 4))
    }
    try! pipeIn.fileHandleForWriting.close()
    ff.waitUntilExit()
default:
    print("usage: fiddlehead still <unfurl 0…1> <out.png>  |  fiddlehead film <seconds> <out.mp4>")
}
