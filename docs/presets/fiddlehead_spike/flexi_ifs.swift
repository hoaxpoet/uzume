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
           float4 hue; float4 sv; float4 core; };   // hue per nesting level 0..3+; sat/val; core glow (screen x, y, radius px, gain)   // ext: leaflet reach-back, stipe length (segments), stipe share   // sd: seed half-width (0 = Flexi's disc), side scale

static uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16; return x; }
static float rnd(thread uint& s) { s = hash(s); return float(s) * (1.0 / 4294967296.0); }
static float2 rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(v.x * c - v.y * s, v.x * s + v.y * c); }

kernel void chaos(device atomic_uint* img [[buffer(0)]], constant P& p [[buffer(1)]], uint gid [[thread_position_in_grid]]) {
    uint s = hash(gid * 9781u + p.seed);
    const float R = 0.0217;                                          // Flexi's seed radius (frame units)
    float ss = p.sd.y, as = 1.0 / (ss * ss), pm = 0.797 / (0.797 + 2.0 * as);   // area-weighted picks
    float2 tm = 0.042 * float2(sin(p.w), cos(p.w)), ts = float2(0.08 * sin(p.w), 0.045 * cos(p.w));
    float2 x1 = rot(-tm, -p.ww) / 1.12;                              // main map's image of the seed centre = the next stalk step
    float2 x = 0.0; float c = 0.0, a = 1.0; int n = 0, lvl = 0; bool chainStart = true;
    for (int i = 0; i < p.iters; i++) {
        if (i % 70 == 0) {
            if (p.sd.x > 0.0) {                                      // stem-segment seed: copies join into a continuous stalk
                // a ∈ [0,1] the segment; a < 0 extends a chain's free end backward: −ext.x reaches a leaflet's base back to its
                // parent stalk (Flexi's fat disc bridged that gap), and the frond's own base continues as a straight stipe.
                a = rnd(s) < p.ext.z ? -p.ext.x - rnd(s) * (p.ext.y - p.ext.x) : mix(-p.ext.x, 1.0, rnd(s));
                float l = rnd(s) * 2.0 - 1.0; float2 d = normalize(x1), nrm = float2(-d.y, d.x);
                x = x1 * a + nrm * l * p.sd.x * mix(1.0, 0.89, a); c = 1.0 - abs(l);
            } else { float r = R * sqrt(rnd(s)), th = 6.2831853 * rnd(s); x = r * float2(cos(th), sin(th)); c = 1.0 - r / R; }
            n = 0; lvl = 0; chainStart = true;
        }
        else {
            float u = rnd(s);
            if (n == 0) { chainStart = u >= pm; }                    // a chain's free end: the seed not continued by the main arm
            if (u >= pm) { lvl++; }
            if (u < pm) { x = rot(x - tm, -p.ww) / 1.12; }
            else if (u < pm + 0.5 * (1.0 - pm)) { x = rot(x - ts, -p.sd.z) / ss; }
            else { x = rot(x - ts, p.sd.z) / ss; }
            n++;
        }
        if ((a < 0.0 && !chainStart) || (a < -p.ext.x && n > 0)) { continue; }   // only free ends extend; only the frond base gets the stipe
        float b = (a < -p.ext.x ? c * smoothstep(-p.ext.y, -0.5 * p.ext.y, a) : c) * (a < 0.0 ? p.tone.w : 1.0) - 0.015 * float(n);   // stipe fades; reach-back dim like the stalk
        if (b <= 0.0) { continue; }
        float2 q = (rot(float2(x.x * p.mirror, -x.y), p.ext.w) - p.centre) * p.scale + float2(\(W / 2).0, \(H / 2).0);
        if (q.x < 0.0 || q.y < 0.0 || q.x >= \(W).0 || q.y >= \(H).0) { continue; }
        uint idx = uint(\(H).0 - 1.0 - q.y) * \(W)u + uint(q.x);
        atomic_fetch_max_explicit(&img[idx], (uint(b * 65535.0) << 16) | (uint(min(n, 1023)) << 6) | uint(min(lvl, 63)), memory_order_relaxed);
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
    float b = float(v >> 16) / 65535.0, age = float((v >> 6) & 1023u);
    uint lvl = v & 63u;
    float3 col;
    if (p.hue.x < 0.0) { col = palette(age / p.tone.x); }                   // FH.6 palette (hue.x < 0)
    else {
        // colour by nesting level: the deepest copies ARE the rims of every lobe (self-similarity), so level 3+ carries the
        // reference's iridescence (hue cycling with path length); a lobe's body is level 1–2; level 0 the stalk.
        float h = lvl == 0u ? p.hue.x : lvl == 1u ? p.hue.y : lvl == 2u ? p.hue.z : p.hue.w + 0.11 * age;
        col = hsv2rgb(fract(h), p.sv.x, 1.0);
    }
    col *= pow(b, p.tone.y) * p.tone.z * (lvl == 0u ? p.tone.w : 1.0);    // main stalk dimmer
    float2 d = (float2(gid) - p.core.xy) / max(p.core.z, 1.0);
    col += float3(1.0, 0.55, 0.18) * p.core.w * exp(-dot(d, d)) * (0.4 + 0.6 * b);   // warm light inside the coil
    out.write(float4(col, b), gid);
}

constexpr sampler lin(filter::linear, address::clamp_to_zero);

kernel void glow(texture2d<float> src [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                 constant float4& g [[buffer(0)]], constant float4& t [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    float2 sz = float2(\(W).0, \(H).0), uv = (float2(gid) + 0.5) / sz;
    float4 c0 = src.read(gid); float3 c = c0.rgb, b = float3(0.0); float wsum = 0.0, cov = 0.0;
    for (int j = -3; j <= 3; j++) for (int i = -3; i <= 3; i++) {
        float w = exp(-float(i * i + j * j) / 6.0);
        float4 s = src.sample(lin, uv + float2(i, j) * g.x / sz);
        b += s.rgb * w; cov += step(0.12, s.a) * w; wsum += w;
    }
    cov /= wsum;                                                 // local fill: 1 deep inside a blade, ~0.5 on its rim
    c *= mix(1.0, g.z, smoothstep(0.55, 0.95, cov)) * (1.0 + g.w * 4.0 * cov * (1.0 - cov));   // dark interiors, glowing rims
    uint h = hash(gid.x * 7919u + gid.y * 104729u + uint(t.x * 60.0) / 6u);                       // sparkle: sparse, ~10 Hz
    c += (rnd(h) < t.y && c0.a > 0.35) ? float3(1.0, 0.95, 0.85) * t.z * c0.a : float3(0.0);
    c += b / wsum * g.y + float3(0.004, 0.005, 0.008);
    c = c / (1.0 + c);
    out.write(float4(pow(c, float3(1.0 / 1.8)), 1.0), gid);
}
"""

// MARK: - Flexi's frond

struct Params { var ww: Float; var w: Float; var scale: Float; var mirror: Float; var centre: SIMD2<Float>; var iters: Int32; var seed: UInt32
                var tone: SIMD4<Float>; var sd: SIMD4<Float>; var ext: SIMD4<Float>; var hue: SIMD4<Float>; var sv: SIMD4<Float>; var core: SIMD4<Float> }

/// unfurl 0 = Understory's one-turn fiddlehead curl (KAPPA), 1 = open; plus Flexi-like sway.
func curl(_ u: Float, _ t: Float) -> (ww: Float, w: Float) {
    let ww = envF("KAPPA", 0.75) * (1 - u) + envF("KAPPA_O", 0.08) * u + envF("SWAY", 0.01) * (sin(t * 0.9) + 0.5 * sin(t * 1.7 + 1.3))
    return (ww, envF("HEAD", 0) - 5 * ww)
}

func rot(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> { SIMD2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)) }

/// Frame-space bbox of the visible frond (CPU chaos game, same maps; points brighter than 0.1).
func extent(ww: Float, w: Float, theta: Float) -> (SIMD2<Float>, SIMD2<Float>) {
    let ss = envF("SIDE", 3.3), tm = 0.042 * SIMD2<Float>(sin(w), cos(w)), ts = SIMD2<Float>(0.08 * sin(w), 0.045 * cos(w)), pm: Float = 0.797 / (0.797 + 2 / (ss * ss))
    var lo = SIMD2<Float>(repeating: 9), hi = SIMD2<Float>(repeating: -9), x = SIMD2<Float>(0, 0), n = 0
    let mir = envF("MIRROR", 1)
    for i in 0..<300_000 {
        if i % 70 == 0 { x = .zero; n = 0 } else {
            let u = Float.random(in: 0..<1)
            x = u < pm ? rot(x - tm, -ww) / 1.12 : rot(x - ts, u < pm + (1 - pm) / 2 ? -envF("ANG", .pi / 4) : envF("ANG", .pi / 4)) / ss; n += 1
        }
        if 1 - 0.015 * Float(n) > 0.1 { let q = rot(SIMD2(x.x * mir, -x.y), theta); lo = simd_min(lo, q); hi = simd_max(hi, q) }
    }
    let pad: Float = 0.0217
    return (lo - pad, hi + pad)
}

// MARK: - Metal

let device = MTLCreateSystemDefaultDevice()!
let lib = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
let chaosPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "chaos")!)
let tonePSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "tone")!)
let glowPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "glow")!)
let img = device.makeBuffer(length: W * H * 4, options: .storageModePrivate)!
func tex(_ fmt: MTLPixelFormat) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: W, height: H, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)!
}
let hdr = tex(.rgba16Float), outTex = tex(.rgba8Unorm)
let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared)!
var lastMs = 0.0

func render(unfurl u: Float, time t: Float) {
    let (ww, w) = curl(u, t)
    // Upright: turn the display so the stipe (the seed segment continued backward, −x1) points straight down the screen.
    let tm0 = 0.042 * SIMD2<Float>(sin(w), cos(w)), x1 = rot(-tm0, -ww) / 1.12, mir = envF("MIRROR", 1)
    let sd = SIMD2(-x1.x * mir, x1.y)                                    // stipe direction in display space (+y up)
    let theta = envF("UPRIGHT", 1) * (-.pi / 2 - atan2(sd.y, sd.x)) + envF("LEAN", 0)
    let (lo, hi) = extent(ww: ww, w: w, theta: theta), fill = envF("FILL", 0.9)
    let scale = min(Float(H) * fill / (hi.y - lo.y), Float(W) * fill / (hi.x - lo.x))
    var p = Params(ww: ww, w: w, scale: scale, mirror: envF("MIRROR", 1), centre: (lo + hi) * 0.5, iters: Int32(envF("ITERS", 280)),
                   seed: UInt32(t * 1000) &+ 17, tone: [envF("AGESPAN", 45), envF("GAMMA", 1.4), envF("EXPO", 0.8), envF("STALKB", 0.45)],
                   sd: [envF("SEEDW", 0.002), envF("SIDE", 3.3), envF("ANG", .pi / 4), envF("TAPER", 0.8)],
                   ext: [envF("REACH", 1.0), envF("STIPE", 6), envF("PSTIPE", 0.05), theta],
                   hue: [envF("H0", 0.11), envF("H1", 0.08), envF("H2", 0.13), envF("H3", 0.78)], sv: [envF("SAT", 1.0), 0, 0, 0],
                   core: [0, 0, 0, 0])
    var fp = SIMD2<Float>(0, 0)                                           // spiral centre = main map's fixed point
    let tm = 0.042 * SIMD2<Float>(sin(w), cos(w))
    for _ in 0..<400 { fp = rot(fp - tm, -ww) / 1.12 }
    let fs = (rot(SIMD2(fp.x * p.mirror, -fp.y), theta) - p.centre) * scale + SIMD2(Float(W / 2), Float(H / 2))
    p.core = [fs.x, Float(H) - 1 - fs.y, envF("CORER", 0.08) * Float(H), envF("CORE", 0.7) * (1 - u)]
    let cb = queue.makeCommandBuffer()!
    let bl = cb.makeBlitCommandEncoder()!; bl.fill(buffer: img, range: 0..<img.length, value: 0); bl.endEncoding()
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(chaosPSO)
    ce.setBuffer(img, offset: 0, index: 0); ce.setBytes(&p, length: MemoryLayout<Params>.stride, index: 1)
    ce.dispatchThreads(MTLSize(width: Int(envF("THREADS", 65536)), height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    ce.setComputePipelineState(tonePSO)
    ce.setBuffer(img, offset: 0, index: 0); ce.setBytes(&p, length: MemoryLayout<Params>.stride, index: 1); ce.setTexture(hdr, index: 0)
    ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    ce.setComputePipelineState(glowPSO)
    var gp = SIMD4<Float>(envF("GLOWR", 2.5), envF("GLOW", 0.25), envF("INNER", 0.45), envF("RIM", 1.0))
    var sp = SIMD4<Float>(t, envF("SPARK", 0.003), envF("SPARKI", 1.5), 0)
    ce.setTexture(hdr, index: 0); ce.setTexture(outTex, index: 1); ce.setBytes(&gp, length: 16, index: 0); ce.setBytes(&sp, length: 16, index: 1)
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
default:
    print("usage: flexiifs still <unfurl> <out.png> | flexiifs film <seconds> <out.mp4>")
}
