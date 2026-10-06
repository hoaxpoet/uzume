// fern_ifs.swift — FH.6 look-spike (throwaway; not engine code).
//
// Matt's definition of the intricacy (2026-10-06): COMPLETE self-similarity — zoom into any part and it is
// another whole fern (leaflets are miniature fronds with their own leaflets; rim croziers are whole croziers),
// down to sparkle. Piece-by-piece geometry (FH.4/FH.5) can't afford that live and substituted stand-ins below
// ~2 levels. An iterated function system IS that definition: the fern is a few affine copies of itself.
//
// Rendering: the chaos game on the GPU (millions of points/frame), log-density tone map with flame colouring
// (Draves & Reckase, "The Fractal Flame Algorithm"). Fern shape: Barnsley's fern maps, generalised to a
// two-node graph-directed IFS so the whole frond (node W) and its pinnae (node P) can curl differently:
//   A_W = stem ∪ main_W(A_W) ∪ pinL_W(A_P) ∪ pinR_W(A_P)      (whole frond: coils as a crozier)
//   A_P = stem ∪ main_P(A_P) ∪ pinL_P(A_P) ∪ pinR_P(A_P)      (pinna: itself a fern with its own curl)
//
// Build:  swiftc -O -swift-version 5 fern_ifs.swift -o fernifs
// Usage:  fernifs still <unfurl 0…1> <out.png>   |   fernifs film <seconds> <out.mp4>   (env vars = knobs)

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

struct Map { float2x2 m; float2 t; float p; int from; int to; float col; float pad; };   // x' = m·x + t
struct P { int nMaps; int iters; float scale; float2 centre; float time; uint seed; float pad0; float pad1; };

static uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16; return x; }
static float rnd(thread uint& s) { s = hash(s); return float(s) * (1.0 / 4294967296.0); }

kernel void chaos(device const Map* maps [[buffer(0)]], constant P& p [[buffer(1)]],
                  device atomic_uint* hist [[buffer(2)]], uint gid [[thread_position_in_grid]]) {
    // Two walkers: xP wanders the pinna attractor A_P (maps P→P); xW samples the frond A_W, whose maps are
    // either W→W (stem, stalk continuation) or pinna maps that take a point of A_P (from xP) into W.
    // (A single walker can go P→W but never back, so it collapsed onto the stalk curve.)
    uint s = hash(gid * 9781u + p.seed);
    float2 xP = float2(rnd(s) - 0.5, rnd(s) * 3.0), xW = xP;
    float cP = 0.5, cW = 0.5;
    float totP = 0.0, totW = 0.0;
    for (int j = 0; j < p.nMaps; j++) { if (maps[j].to == 1) { totP += maps[j].p; } else { totW += maps[j].p; } }
    for (int i = 0; i < p.iters; i++) {
        float r = rnd(s) * totP, acc = 0.0; int k = 0;            // advance the pinna walker
        for (int j = 0; j < p.nMaps; j++) { if (maps[j].to != 1) { continue; } acc += maps[j].p; k = j; if (r <= acc) { break; } }
        xP = maps[k].m * xP + maps[k].t; cP = 0.5 * (cP + maps[k].col);
        r = rnd(s) * totW; acc = 0.0;                              // advance the frond walker
        for (int j = 0; j < p.nMaps; j++) { if (maps[j].to != 0) { continue; } acc += maps[j].p; k = j; if (r <= acc) { break; } }
        Map mp = maps[k];
        if (mp.from == 1) { xW = mp.m * xP + mp.t; cW = 0.5 * (cP + mp.col); }
        else { xW = mp.m * xW + mp.t; cW = 0.5 * (cW + mp.col); }
        if (i < 20) { continue; }
        float2 q = (xW - p.centre) * p.scale + float2(\(W / 2).0, \(H / 2).0);
        if (q.x < 0.0 || q.y < 0.0 || q.x >= \(W).0 || q.y >= \(H).0) { continue; }
        uint idx = (uint(\(H).0 - 1.0 - q.y) * \(W)u + uint(q.x)) * 2u;
        atomic_fetch_add_explicit(&hist[idx], 1u, memory_order_relaxed);
        atomic_fetch_add_explicit(&hist[idx + 1u], uint(cW * 255.0), memory_order_relaxed);
    }
}

static float3 palette(float c) {
    // deep green stem → lime/emerald tissue → gold rims/tips (warm light), a touch of teal
    const float3 k[5] = { float3(0.05, 0.25, 0.08), float3(0.20, 0.65, 0.15), float3(0.55, 0.85, 0.20),
                          float3(1.00, 0.75, 0.30), float3(1.00, 0.95, 0.70) };
    float x = clamp(c, 0.0, 1.0) * 4.0; int i = min(int(x), 3);
    return mix(k[i], k[i + 1], fract(x));
}

kernel void tone(device const uint* hist [[buffer(0)]], constant float4& t [[buffer(1)]],
                 texture2d<float, access::write> out [[texture(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    uint idx = (gid.y * \(W)u + gid.x) * 2u;
    float n = float(hist[idx]);
    float a = log(1.0 + n) / log(1.0 + t.x);                  // log-density (flame) brightness
    float3 col = n > 0.0 ? palette(float(hist[idx + 1u]) / max(n, 1.0) / 255.0) : float3(0.0);
    col *= pow(a, t.y) * t.z;
    out.write(float4(col, 1.0), gid);
}

constexpr sampler lin(filter::linear, address::clamp_to_zero);
kernel void glow(texture2d<float> src [[texture(0)]], texture2d<float, access::write> out [[texture(1)]],
                 constant float4& g [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= \(W)u || gid.y >= \(H)u) { return; }
    float2 sz = float2(\(W).0, \(H).0), uv = (float2(gid) + 0.5) / sz;
    float3 c = src.read(gid).rgb, b = float3(0.0); float wsum = 0.0;
    for (int j = -3; j <= 3; j++) for (int i = -3; i <= 3; i++) {
        float w = exp(-float(i * i + j * j) / 6.0);
        b += src.sample(lin, uv + float2(i, j) * g.x / sz).rgb * w; wsum += w;
    }
    c += b / wsum * g.y;
    float3 bg = float3(0.006, 0.010, 0.014) + float3(0.0, 0.012, 0.010) * (1.0 - uv.y);
    c = bg + c;
    c = c / (1.0 + c);                                          // soft shoulder
    out.write(float4(pow(c, float3(1.0 / 1.8)), 1.0), gid);
}
"""

// MARK: - IFS (Barnsley's fern, generalised)

struct Map { var m: simd_float2x2; var t: SIMD2<Float>; var p: Float; var from: Int32; var to: Int32; var col: Float; var pad: Float = 0 }
struct Params { var nMaps: Int32; var iters: Int32; var scale: Float; var centre: SIMD2<Float>; var time: Float; var seed: UInt32; var pad0: Float = 0; var pad1: Float = 0 }

func rs(_ s: Float, _ a: Float, flip: Bool = false) -> simd_float2x2 {   // scale·rotation (optionally mirrored)
    let c = cos(a) * s, n = sin(a) * s
    let m = simd_float2x2(columns: (SIMD2(c, n), SIMD2(-n, c)))
    return flip ? m * simd_float2x2(columns: (SIMD2(-1, 0), SIMD2(0, 1))) : m
}

/// Fern maps for unfurl u (0 = tight crozier, 1 = open frond). Node 0 = whole frond W, node 1 = pinna P.
func fernMaps(_ u: Float, _ t: Float) -> [Map] {
    let sway = envF("SWAY", 0.03) * sin(t * 0.9) + envF("SWAY", 0.03) * 0.5 * sin(t * 1.7 + 1.3)
    // whole-frond curl per step: coil (tight) → nearly straight (open)
    let curlW = envF("CURLW", 0.30) * (1 - u) + envF("CURLW_O", 0.04) * u + sway
    // pinna curl: pinnae are croziers too; they open later (lag) than the frond
    let up = max(0, min(1, (u - 0.25) / 0.75))
    let curlP = envF("CURLP", 0.30) * (1 - up) + envF("CURLP_O", 0.06) * up
    let sMain = envF("SMAIN", 0.86), sPin = envF("SPIN", 0.30) * (0.75 + 0.25 * u)     // arms puff out as it opens
    let aPin = envF("APIN", 0.85), hMain = envF("HMAIN", 1.6), hPin = envF("HPIN", 1.6)
    let sP = envF("SMAINP", 0.84), sPP = envF("SPINP", 0.30), aPP = envF("APINP", 0.9)
    var m: [Map] = []
    // node 0 (whole frond)
    m.append(Map(m: simd_float2x2(columns: (SIMD2(0, 0), SIMD2(0, 0.16))), t: [0, 0], p: 0.02, from: 0, to: 0, col: 0.05))
    m.append(Map(m: rs(sMain, -curlW), t: [0, hMain], p: 0.80, from: 0, to: 0, col: 0.45))
    m.append(Map(m: rs(sPin, aPin), t: [0, hPin], p: 0.09, from: 1, to: 0, col: 0.75))
    m.append(Map(m: rs(sPin, -aPin, flip: true), t: [0, hPin * 0.95], p: 0.09, from: 1, to: 0, col: 0.75))
    // node 1 (pinna — itself a fern with its own curl)
    m.append(Map(m: simd_float2x2(columns: (SIMD2(0, 0), SIMD2(0, 0.16))), t: [0, 0], p: 0.02, from: 1, to: 1, col: 0.10))
    m.append(Map(m: rs(sP, -curlP), t: [0, hMain], p: 0.80, from: 1, to: 1, col: 0.55))
    m.append(Map(m: rs(sPP, aPP), t: [0, hPin], p: 0.09, from: 1, to: 1, col: 0.95))
    m.append(Map(m: rs(sPP, -aPP, flip: true), t: [0, hPin * 0.95], p: 0.09, from: 1, to: 1, col: 0.95))
    for i in m.indices { m[i].p = max(abs(m[i].m.determinant), envF("PFLOOR", 0.03)) }   // area-proportional picks
    return m
}

func extent(_ maps: [Map]) -> (SIMD2<Float>, SIMD2<Float>) {
    var xP = SIMD2<Float>(0, 0), xW = SIMD2<Float>(0, 0), xs: [Float] = [], ys: [Float] = []
    let mp = maps.filter { $0.to == 1 }, mw = maps.filter { $0.to == 0 }
    func pick(_ a: [Map]) -> Map { var r = Float.random(in: 0..<a.reduce(0) { $0 + $1.p }); for c in a { r -= c.p; if r <= 0 { return c } }; return a[0] }
    for i in 0..<40000 {
        let a = pick(mp); xP = a.m * xP + a.t
        let b = pick(mw); xW = b.m * (b.from == 1 ? xP : xW) + b.t
        if i > 50 { xs.append(xW.x); ys.append(xW.y) }
    }
    xs.sort(); ys.sort()
    func q(_ a: [Float], _ f: Float) -> Float { a[min(a.count - 1, Int(Float(a.count) * f))] }
    return ([q(xs, 0.005), q(ys, 0.005)], [q(xs, 0.995), q(ys, 0.995)])
}

// MARK: - Metal setup

let device = MTLCreateSystemDefaultDevice()!
let lib = try! device.makeLibrary(source: msl, options: nil)
let queue = device.makeCommandQueue()!
let chaosPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "chaos")!)
let tonePSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "tone")!)
let glowPSO = try! device.makeComputePipelineState(function: lib.makeFunction(name: "glow")!)
let hist = device.makeBuffer(length: W * H * 2 * 4, options: .storageModePrivate)!
let mapsBuf = device.makeBuffer(length: 64 * MemoryLayout<Map>.stride, options: .storageModeShared)!
func tex(_ fmt: MTLPixelFormat) -> MTLTexture {
    let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: W, height: H, mipmapped: false)
    d.usage = [.shaderRead, .shaderWrite]; return device.makeTexture(descriptor: d)!
}
let hdr = tex(.rgba16Float), outTex = tex(.rgba8Unorm)
let readback = device.makeBuffer(length: W * H * 4, options: .storageModeShared)!
var lastMs = 0.0

func render(unfurl u: Float, time t: Float) {
    let maps = fernMaps(u, t)
    let mp = mapsBuf.contents().bindMemory(to: Map.self, capacity: 64)
    for (i, m) in maps.enumerated() { mp[i] = m }
    // framing: a quick CPU chaos game finds the attractor's extent (2–98 % quantiles), fitted with a margin
    let (lo, hi) = extent(maps)
    let fill = envF("FILL", 0.86)
    let scale = min(Float(H) * fill / (hi.y - lo.y), Float(W) * fill / (hi.x - lo.x))
    var p = Params(nMaps: Int32(maps.count), iters: Int32(envF("ITERS", 256)), scale: scale,
                   centre: (lo + hi) * 0.5, time: t, seed: UInt32(t * 1000) &+ 17)
    let threads = Int(envF("THREADS", 65536))
    let cb = queue.makeCommandBuffer()!
    let bl = cb.makeBlitCommandEncoder()!; bl.fill(buffer: hist, range: 0..<hist.length, value: 0); bl.endEncoding()
    let ce = cb.makeComputeCommandEncoder()!
    ce.setComputePipelineState(chaosPSO)
    ce.setBuffer(mapsBuf, offset: 0, index: 0); ce.setBytes(&p, length: MemoryLayout<Params>.stride, index: 1); ce.setBuffer(hist, offset: 0, index: 2)
    ce.dispatchThreads(MTLSize(width: threads, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 256, height: 1, depth: 1))
    ce.setComputePipelineState(tonePSO)
    var tp = SIMD4<Float>(envF("NMAX", 400), envF("GAMMA", 0.55), envF("EXPO", 2.2), 0)
    ce.setBuffer(hist, offset: 0, index: 0); ce.setBytes(&tp, length: 16, index: 1); ce.setTexture(hdr, index: 0)
    ce.dispatchThreads(MTLSize(width: W, height: H, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
    ce.setComputePipelineState(glowPSO)
    var gp = SIMD4<Float>(envF("GLOWR", 2.5), envF("GLOW", 0.8), 0, 0)
    ce.setTexture(hdr, index: 0); ce.setTexture(outTex, index: 1); ce.setBytes(&gp, length: 16, index: 0)
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
    render(unfurl: Float(args[2])!, time: 1); render(unfurl: Float(args[2])!, time: 1)
    FileHandle.standardError.write(String(format: "gpu %.1f ms, points %.1fM\n", lastMs, envF("THREADS", 65536) * envF("ITERS", 256) / 1e6).data(using: .utf8)!)
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
    print("usage: fernifs still <unfurl> <out.png> | fernifs film <seconds> <out.mp4>")
}
