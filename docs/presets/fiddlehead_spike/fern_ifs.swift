// fern_ifs.swift — FH.6 look-spike (throwaway; not engine code).
//
// Matt's definition of the intricacy (2026-10-06): COMPLETE self-similarity — zoom into any part and it is
// another whole fern (leaflets are miniature fronds with their own leaflets; rim croziers are whole croziers),
// down to sparkle — and it must clearly read as a FERN.
//
// Architecture: a STRAIGHT self-similar fern (Barnsley-style iterated function system, two nodes: the frond W
// and its pinna P) whose every level is ROLLED by a crozier warp — a frond rolls up from its tip along a log
// spiral (the coil law, ~2.7× per turn). An affine copy can't be "straight base + rolled tip" (one constant
// curl per map: rings in the coil, no tip curls when open), so the roll is a non-linear map applied
//   • to each pinna as it is copied into the frond   (pinnae are croziers),
//   • to each pinnule as it is copied into the pinna (leaflets are croziers),
//   • to the whole frond at display                   (the fiddlehead).
// Unfurl moves where each roll starts: near the base = tight coil, near the tip = open frond with tip croziers.
//
// Rendering: chaos game on the GPU (two walkers — the frond's pinna maps draw points from a pinna walker),
// log-density tone with flame colouring (Draves & Reckase, "The Fractal Flame Algorithm"), glow.
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

struct Map { float2x2 m; float2 t; float p; int from; int to; float col; int roll; };   // x' = m·roll?(x) + t
struct Roll { float a; float b; float len; float dir; };      // roll start (fraction of length), spiral b, length, side
struct P { int nMaps; int iters; float scale; float pad; float2 centre; float time; uint seed; Roll rw; Roll rp; Roll rpp; };

static uint hash(uint x) { x ^= x >> 16; x *= 0x7feb352d; x ^= x >> 15; x *= 0x846ca68b; x ^= x >> 16; return x; }
static float rnd(thread uint& s) { s = hash(s); return float(s) * (1.0 / 4294967296.0); }

// A straight frond (axis +y from 0 to len, lateral x) rolled from a·len to its tip along a log spiral.
static float2 roll(float2 q, Roll R) {
    float y0 = R.a * R.len;
    if (q.y <= y0 || R.a >= 0.999) { return q; }
    float k = R.b / sqrt(1.0 + R.b * R.b);
    float R0 = max((R.len - y0) * k, 1e-4);
    float r = max(R0 - (q.y - y0) * k, R0 * 0.004);
    float phi = log(R0 / r) / R.b;
    float2 c = float2(R.dir * R0, y0), u = float2(-R.dir * cos(phi), sin(phi));
    return c + u * (r - q.x * R.dir * (r / R0));                // lateral tissue winds with the local radius
}

kernel void chaos(device const Map* maps [[buffer(0)]], constant P& p [[buffer(1)]],
                  device atomic_uint* hist [[buffer(2)]], uint gid [[thread_position_in_grid]]) {
    uint s = hash(gid * 9781u + p.seed);
    float2 xP = float2(rnd(s) - 0.5, rnd(s) * 3.0), xW = xP;
    float cP = 0.5, cW = 0.5, totP = 0.0, totW = 0.0;
    for (int j = 0; j < p.nMaps; j++) { if (maps[j].to == 1) { totP += maps[j].p; } else { totW += maps[j].p; } }
    for (int i = 0; i < p.iters; i++) {
        float r = rnd(s) * totP, acc = 0.0; int k = 0;            // pinna walker (A_P)
        for (int j = 0; j < p.nMaps; j++) { if (maps[j].to != 1) { continue; } acc += maps[j].p; k = j; if (r <= acc) { break; } }
        Map a = maps[k];
        xP = a.m * (a.roll == 2 ? roll(xP, p.rpp) : xP) + a.t; cP = 0.5 * (cP + a.col);
        r = rnd(s) * totW; acc = 0.0;                              // frond walker (A_W)
        for (int j = 0; j < p.nMaps; j++) { if (maps[j].to != 0) { continue; } acc += maps[j].p; k = j; if (r <= acc) { break; } }
        Map b = maps[k];
        if (b.from == 1) { xW = b.m * (b.roll == 1 ? roll(xP, p.rp) : xP) + b.t; cW = 0.5 * (cP + b.col); }
        else { xW = b.m * xW + b.t; cW = 0.5 * (cW + b.col); }
        if (i < 30) { continue; }
        float2 q = (roll(xW, p.rw) - p.centre) * p.scale + float2(\(W / 2).0, \(H / 2).0);
        if (q.x < 0.0 || q.y < 0.0 || q.x >= \(W).0 || q.y >= \(H).0) { continue; }
        uint idx = (uint(\(H).0 - 1.0 - q.y) * \(W)u + uint(q.x)) * 2u;
        atomic_fetch_add_explicit(&hist[idx], 1u, memory_order_relaxed);
        atomic_fetch_add_explicit(&hist[idx + 1u], uint(cW * 255.0), memory_order_relaxed);
    }
}

static float3 palette(float c) {
    // gold stalk → green/emerald tissue → teal → violet tips
    const float3 k[5] = { float3(0.95, 0.65, 0.20), float3(0.35, 0.75, 0.15), float3(0.10, 0.70, 0.35),
                          float3(0.10, 0.65, 0.75), float3(0.65, 0.35, 0.95) };
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
    out.write(float4(col * pow(a, t.y) * t.z, 1.0), gid);
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
    c += b / wsum * g.y + float3(0.004, 0.005, 0.008);
    c = c / (1.0 + c);
    out.write(float4(pow(c, float3(1.0 / 1.8)), 1.0), gid);
}
"""

// MARK: - The fern

struct Map { var m: simd_float2x2; var t: SIMD2<Float>; var p: Float; var from: Int32; var to: Int32; var col: Float; var roll: Int32 }
struct Roll { var a: Float; var b: Float; var len: Float; var dir: Float }
struct Params { var nMaps: Int32; var iters: Int32; var scale: Float; var pad: Float = 0; var centre: SIMD2<Float>; var time: Float; var seed: UInt32
                var rw: Roll; var rp: Roll; var rpp: Roll }

func rs(_ s: Float, _ a: Float, flip: Bool = false) -> simd_float2x2 {   // scale·rotation (optionally mirrored)
    let c = cos(a) * s, n = sin(a) * s
    let m = simd_float2x2(columns: (SIMD2(c, n), SIMD2(-n, c)))
    return flip ? m * simd_float2x2(columns: (SIMD2(-1, 0), SIMD2(0, 1))) : m
}
func roll(_ q: SIMD2<Float>, _ R: Roll) -> SIMD2<Float> {             // = the shader's roll()
    let y0 = R.a * R.len
    if q.y <= y0 || R.a >= 0.999 { return q }
    let k = R.b / (1 + R.b * R.b).squareRoot(), R0 = max((R.len - y0) * k, 1e-4)
    let r = max(R0 - (q.y - y0) * k, R0 * 0.004), phi = log(R0 / r) / R.b
    let c = SIMD2<Float>(R.dir * R0, y0), u = SIMD2<Float>(-R.dir * cos(phi), sin(phi))
    return c + u * (r - q.x * R.dir * (r / R0))
}

struct Fern { var maps: [Map]; var rw: Roll; var rp: Roll; var rpp: Roll }

/// u: unfurl 0 (tight crozier) … 1 (open frond with rolled tips). Node 0 = frond W, node 1 = pinna P.
func fern(_ u: Float, _ t: Float) -> Fern {
    func L(_ k: String, _ c: Float, _ o: Float) -> Float { let a = envF(k, c), b = envF(k + "_O", o); return a + (b - a) * u }
    let sway = envF("SWAY", 0.01) * (sin(t * 0.9) + 0.5 * sin(t * 1.7 + 1.3))
    // straight fern proportions (Barnsley-like; a slight natural bend)
    let sW = envF("SW", 0.86), hW = envF("HW", 1.6), bW = envF("BEND", 0.03) + sway
    let sPin = L("SPIN", 0.24, 0.34), aPin = envF("APIN", 0.95), hPin = envF("HPIN", 1.6)   // arms puff out as it opens
    let sP = envF("SP", 0.86), hP = envF("HP", 1.6)
    let sPP = L("SPP", 0.28, 0.32), aPP = envF("APP", 0.95), hPP = envF("HPP", 1.6)
    let stem = simd_float2x2(columns: (SIMD2(0, 0), SIMD2(0, envF("STEMW", 0.16))))
    var m: [Map] = []
    m.append(Map(m: stem, t: [0, 0], p: 0, from: 0, to: 0, col: 0.02, roll: 0))
    m.append(Map(m: rs(sW, -bW), t: [0, hW], p: 0, from: 0, to: 0, col: 0.25, roll: 0))
    m.append(Map(m: rs(sPin, aPin), t: [0, hPin], p: 0, from: 1, to: 0, col: 0.6, roll: 1))
    m.append(Map(m: rs(sPin, -aPin, flip: true), t: [0, hPin * 0.95], p: 0, from: 1, to: 0, col: 0.6, roll: 1))
    m.append(Map(m: stem, t: [0, 0], p: 0, from: 1, to: 1, col: 0.1, roll: 0))
    m.append(Map(m: rs(sP, -envF("BENDP", 0.03)), t: [0, hP], p: 0, from: 1, to: 1, col: 0.45, roll: 0))
    m.append(Map(m: rs(sPP, aPP), t: [0, hPP], p: 0, from: 1, to: 1, col: 0.95, roll: 2))
    m.append(Map(m: rs(sPP, -aPP, flip: true), t: [0, hPP * 0.95], p: 0, from: 1, to: 1, col: 0.95, roll: 2))
    for i in m.indices { m[i].p = max(abs(m[i].m.determinant), envF("PFLOOR", 0.03)) }   // area-proportional picks
    // rolls: where each level's rolling starts (fraction of its length), spiral b (growth e^{2πb} per turn)
    let lenW = hW / (1 - sW), lenP = hP / (1 - sP)
    let rw = Roll(a: L("RW", 0.10, 0.82), b: envF("BW", 0.16), len: lenW, dir: 1)
    let rp = Roll(a: L("RP", 0.05, 0.62), b: envF("BP", 0.18), len: lenP, dir: 1)
    let rpp = Roll(a: L("RPP", 0.05, 0.55), b: envF("BPP", 0.2), len: lenP, dir: 1)
    return Fern(maps: m, rw: rw, rp: rp, rpp: rpp)
}

func extent(_ f: Fern) -> (SIMD2<Float>, SIMD2<Float>) {
    var xP = SIMD2<Float>(0, 0), xW = SIMD2<Float>(0, 0), xs: [Float] = [], ys: [Float] = []
    let mp = f.maps.filter { $0.to == 1 }, mw = f.maps.filter { $0.to == 0 }
    func pick(_ a: [Map]) -> Map { var r = Float.random(in: 0..<a.reduce(0) { $0 + $1.p }); for c in a { r -= c.p; if r <= 0 { return c } }; return a[0] }
    for i in 0..<40000 {
        let a = pick(mp); xP = a.m * (a.roll == 2 ? roll(xP, f.rpp) : xP) + a.t
        let b = pick(mw); xW = b.from == 1 ? b.m * (b.roll == 1 ? roll(xP, f.rp) : xP) + b.t : b.m * xW + b.t
        if i > 50 { let q = roll(xW, f.rw); xs.append(q.x); ys.append(q.y) }
    }
    xs.sort(); ys.sort()
    func q(_ a: [Float], _ v: Float) -> Float { a[min(a.count - 1, Int(Float(a.count) * v))] }
    return ([q(xs, 0.005), q(ys, 0.005)], [q(xs, 0.995), q(ys, 0.995)])
}

// MARK: - Metal

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
    let f = fern(u, t)
    let mp = mapsBuf.contents().bindMemory(to: Map.self, capacity: 64)
    for (i, m) in f.maps.enumerated() { mp[i] = m }
    let (lo, hi) = extent(f), fill = envF("FILL", 0.88)
    let scale = min(Float(H) * fill / (hi.y - lo.y), Float(W) * fill / (hi.x - lo.x))
    var p = Params(nMaps: Int32(f.maps.count), iters: Int32(envF("ITERS", 256)), scale: scale, centre: (lo + hi) * 0.5,
                   time: t, seed: UInt32(t * 1000) &+ 17, rw: f.rw, rp: f.rp, rpp: f.rpp)
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
