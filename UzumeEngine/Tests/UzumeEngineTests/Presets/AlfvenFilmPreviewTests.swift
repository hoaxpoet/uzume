// AlfvenFilmPreviewTests — the §11 look gate, run on the CPU.
//
// `docs/presets/alfven_spike/film.py` is the authoritative look ("the Metal fragment
// shader should reproduce THIS, not invent its own look"), but three of its operations are
// global or multi-scale — `autoexp` (2nd/99.6th percentile of |J|), `std(J)`, and two
// Gaussian blurs — and a fragment shader cannot do any of them. Porting it to Metal needs
// a reduction/mip surface Uzume does not have.
//
// So this ports film.py to the CPU instead, exactly, and applies it to the REAL GPU field
// pulled off the live persistent state texture. That does two jobs:
//   1. It answers §11 — does a GPU Jacobi projection reproduce the spike's look? — without
//      waiting on the missing engine surface. The physics is on trial here, not the tonemap.
//   2. It IS the reference implementation to port to Metal later, already validated against
//      the same field the shader will see.
//
// Why this exists at all: the placeholder fixed exposure in Alfven.metal made the field
// look dead, and I read that as a physics failure. It was not — autoexp normalises |J| by
// its own percentiles, so J's absolute scale is irrelevant to the look. Absolute RMS was
// the wrong measurement; this is the right one.
//
// Env-gated `RENDER_VISUAL=1` (writes PNGs). Reader is the eyes (D-064).

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Alfvén film preview (env-gated, ALFVEN.2)")
@MainActor
struct AlfvenFilmPreviewTests {

    private static let edge = 256
    /// Palette centre. 0.72 = the late (magenta <-> teal) end Matt selected; overridable
    /// so the drift range can be inspected without an edit.
    private static var hueCentre: Double {
        ProcessInfo.processInfo.environment["ALFVEN_HUE"].flatMap(Double.init) ?? 0.72
    }
    /// Frames to capture: early in the arc, mid-arc, and late — the fold-to-filament
    /// progression §3 calls the cycle.
    private static let captureAt: Set<Int> = [60, 240, 600, 1080]

    @Test("render the live MHD field through film.py's mapping")
    func filmPreview() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("AlfvenFilmPreview: RENDER_VISUAL not set, skipping")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Alfvén" }) else {
            Issue.record("Alfvén not found"); return
        }
        let specs = preset.stages.map {
            StagedStageSpec(name: $0.name, pipelineState: $0.pipelineState, samples: $0.samples,
                            writesToDrawable: $0.writesToDrawable, persistent: $0.persistent,
                            iterations: $0.iterations, pixelFormat: $0.pixelFormat)
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)
        pipeline.setStagedRuntime(specs, drawableSize: CGSize(width: Self.edge, height: Self.edge))

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uzume-alfven2-film")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let last = (Self.captureAt.max() ?? 0)
        for i in 0...last {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            pipeline.encodeOffscreenStages(commandBuffer: cmd, features: &features,
                                           stemFeatures: .zero)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard Self.captureAt.contains(i) else { continue }

            let j = try Self.readJ(pipeline)
            let stats = Self.fieldStats(j)
            let rgb = Self.film(j, width: Self.edge, height: Self.edge)
            let url = dir.appendingPathComponent(String(format: "alfven_film_f%04d.png", i))
            try Self.writePNG(rgb, width: Self.edge, height: Self.edge, to: url)
            print(String(format: "[alfven-film] f%4d  J p2 %+.5f p99.6 %+.5f std %.5f "
                                 + "| dynamic range %.1fx | %@",
                         i, stats.p2, stats.p996, stats.std,
                         stats.p996 / max(abs(stats.p2), 1e-9), url.lastPathComponent))
        }
        print("[alfven-film] wrote to \(dir.path)")
    }

    // MARK: film.py, ported

    private struct Stats { var p2 = 0.0, p996 = 0.0, std = 0.0 }

    private static func fieldStats(_ j: [Double]) -> Stats {
        let absSorted = j.map(abs).sorted()
        let mean = j.reduce(0, +) / Double(j.count)
        let varr = j.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(j.count)
        func pct(_ p: Double) -> Double {
            let idx = min(max(Int(p / 100.0 * Double(absSorted.count - 1)), 0), absSorted.count - 1)
            return absSorted[idx]
        }
        return Stats(p2: pct(2.0), p996: pct(99.6), std: varr.squareRoot())
    }

    /// `autoexp(a, lo=2.0, hi=99.6)` — percentile normalisation, the reason J's absolute
    /// scale does not matter to the look (and the same FA #31 reasoning as deviation
    /// primitives: track the field's own distribution, never an absolute threshold).
    private static func autoexp(_ a: [Double]) -> [Double] {
        let s = a.sorted()
        func pct(_ p: Double) -> Double {
            let idx = min(max(Int(p / 100.0 * Double(s.count - 1)), 0), s.count - 1)
            return s[idx]
        }
        let p1 = pct(2.0), p2 = pct(99.6)
        let d = max(p2 - p1, 1e-9)
        return a.map { min(max(($0 - p1) / d, 0), 1) }
    }

    private static func filmic(_ x: Double) -> Double {
        let a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14
        return min(max((x * (a * x + b)) / (x * (c * x + d) + e), 0), 1)
    }

    private static func hsv2rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let hh = (h - h.rounded(.down)) * 6.0
        let i = Int(hh), f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// Separable Gaussian, matching `scipy.ndimage.gaussian_filter(core, sigma)`.
    private static func blur(_ src: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        let radius = max(Int(sigma * 3.0), 1)
        var kernel = [Double](repeating: 0, count: radius * 2 + 1)
        var sum = 0.0
        for i in 0...(radius * 2) {
            let x = Double(i - radius)
            let w = exp(-(x * x) / (2 * sigma * sigma))
            kernel[i] = w; sum += w
        }
        for i in kernel.indices { kernel[i] /= sum }

        var tmp = [Double](repeating: 0, count: src.count)
        var out = [Double](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in 0...(radius * 2) {
                    let sx = min(max(x + k - radius, 0), width - 1)
                    acc += src[y * width + sx] * kernel[k]
                }
                tmp[y * width + x] = acc
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in 0...(radius * 2) {
                    let sy = min(max(y + k - radius, 0), height - 1)
                    acc += tmp[sy * width + x] * kernel[k]
                }
                out[y * width + x] = acc
            }
        }
        return out
    }

    /// `film.py:render()`, at silence (sizzle clips to 0 ⇒ amt = 0.30; hue centre 0.52).
    private static func film(_ j: [Double], width: Int, height: Int) -> [UInt8] {
        let aJ = autoexp(j.map(abs))
        let mean = j.reduce(0, +) / Double(j.count)
        let sd = (j.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(j.count)).squareRoot()
        let sJ = j.map { tanh($0 / (sd * 1.2 + 1e-9)) }

        let core = aJ.map { pow(min(max(($0 - 0.72) / 0.28, 0), 1), 1.5) }
        let b0 = blur(core, width: width, height: height, sigma: 2.0)
        let b1 = blur(core, width: width, height: height, sigma: 7.0)
        let amt = 0.30   // silence: sizzle = trebRel - 0.6 clips to 0

        let tintA = (1.00, 0.72, 0.42), tintB = (0.45, 0.72, 1.00)
        let ground = (0.035, 0.045, 0.075)

        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            // Matt's pick (2026-09-09): the FOURTH COLUMN of the concept sheet, i.e. the
            // LATE end of film.py's palette drift — magenta <-> teal, not the early
            // acid-green <-> violet. film.py maps hue = 0.46 + 0.26*centroid01, so the
            // late end is 0.72. `04_palette_opponent_drift.png` annotates exactly this:
            // "Left = early (acid green <-> violet), right = late (magenta <-> teal)".
            let hue = Self.hueCentre + 0.30 * sJ[i]
            let sat = 0.32 + 0.58 * (1.0 - aJ[i] * aJ[i])
            let val = filmic(1.9 * pow(aJ[i], 0.85))
            var (r, g, b) = hsv2rgb(hue, min(max(sat, 0), 1), min(max(val, 0), 1))

            let glow = 0.75 * b0[i] + 0.55 * b1[i]
            let split = 0.5 + 0.5 * sJ[i]
            r += amt * glow * (tintA.0 * split + tintB.0 * (1 - split))
            g += amt * glow * (tintA.1 * split + tintB.1 * (1 - split))
            b += amt * glow * (tintA.2 * split + tintB.2 * (1 - split))

            r += ground.0 * (1 - val); g += ground.1 * (1 - val); b += ground.2 * (1 - val)

            // BGRA, premultiplied-first byte order to match the PNG writer.
            out[i * 4 + 0] = UInt8(min(max(b, 0), 1) * 255)
            out[i * 4 + 1] = UInt8(min(max(g, 0), 1) * 255)
            out[i * 4 + 2] = UInt8(min(max(r, 0), 1) * 255)
            out[i * 4 + 3] = 255
        }
        return out
    }

    // MARK: plumbing

    private static func readJ(_ pipeline: RenderPipeline) throws -> [Double] {
        guard let tex = pipeline.stagedTexture(named: "state") else {
            throw HarnessError.setupFailed("no state texture")
        }
        let w = tex.width, h = tex.height
        var raw = [Float](repeating: 0, count: w * h * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: w * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: w, height: h, depth: 1)),
                         mipmapLevel: 0)
        }
        return (0..<(w * h)).map { Double(raw[$0 * 4 + 2]) }   // .b = J
    }

    private static func writePNG(_ bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw HarnessError.setupFailed("sRGB")
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let cg = CGContext(data: base, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: space, bitmapInfo: info.rawValue) else { return nil }
            return cg.makeImage()
        }
        guard let image, let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw HarnessError.setupFailed("png dest")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw HarnessError.setupFailed("png write") }
    }
}
