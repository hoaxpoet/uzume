// FiddleheadFernTests — the Fiddlehead preset's renderer (FH.16), through the same calls the app makes per frame:
// `ensureAllocated` → `update(features:stemFeatures:commandBuffer:)` → `render(encoder:)` into an sRGB target.
//
// Default-on: shape + dive invariants, and one rendered frame that must be a fern (not black, not clipped, varied).
// `FIDDLEHEAD_FILM=1` additionally renders a sequence at 1080p to `$TMPDIR/fiddlehead_film/` (PNG frames) and prints
// GPU frame-time percentiles — run it with `-c release`; it uses a SYNTHETIC beat clock (a beatPhase01 ramp), so it
// judges look, motion and cost, never music coupling (FA #27).

import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Shared

@Suite("Fiddlehead fern (FH.16)")
struct FiddleheadFernTests {

    // MARK: Pure

    @Test("the shape builds every curl state with children more rolled than their parent")
    func shapeIsSane() {
        let shape = FernShape()
        let built = shape.build()
        #expect(built.spines.count == shape.spineSamples * shape.states)
        #expect(built.children.count == shape.sites.count * 2 * shape.states)
        #expect(built.children.allSatisfy { $0.shift > 0 && $0.scale > 0 && $0.scale < 1 })
        #expect(built.boxMin.x < 0 && built.boxMax.x > 0.5)
    }

    @Test("the dive loops: one period later the camera frame is the same, one level down")
    func diveLoops() {
        let shape = FernShape()
        let dive = FernDive(shape: shape, children: shape.build().children)
        #expect(dive.children[dive.kStar].mirror < 0.5)
        for t: Float in [0.3, 2.9, 6.1] {
            let a = dive.frame(time: t), b = dive.frame(time: t + dive.period)
            #expect(simd_length(a.lift - b.lift) < 1e-4)
            #expect(simd_length(a.centre - b.centre) < 1e-4)
            #expect(abs((b.phi0 - a.phi0) - dive.arcStar) < 1e-4)            // the impulse path advances one stem
        }
    }

    @Test("a beat-phase wrap fires one pulse; a bar wrap makes it a downbeat")
    func pulsesOnGridWraps() {
        let shape = FernShape()
        let dive = FernDive(shape: shape, children: shape.build().children)
        var music = FernMusic(), f = FeatureVector()
        f.beatPhase01 = 0.9; f.barPhase01 = 0.95
        music.update(features: f, time: 0, dt: 1 / 60, dive: dive)
        #expect(music.pulses.isEmpty)
        f.beatPhase01 = 0.02; f.barPhase01 = 0.01
        music.update(features: f, time: 1 / 60, dt: 1 / 60, dive: dive)
        #expect(music.pulses.count == 1 && music.pulses[0].amp > 0.5)
        f.beatPhase01 = 0.95; f.barPhase01 = 0.25
        music.update(features: f, time: 0.3, dt: 1 / 60, dive: dive)
        f.beatPhase01 = 0.01; f.barPhase01 = 0.26
        music.update(features: f, time: 0.5, dt: 1 / 60, dive: dive)
        #expect(music.pulses.count == 2 && music.pulses[1].amp < 0.5)
    }

    // MARK: GPU

    struct Rig {
        let ctx: MetalContext
        let fern: FiddleheadFern
        let target: MTLTexture
        let readback: MTLBuffer

        init(width: Int, height: Int) throws {
            ctx = try MetalContext()
            let lib = try ShaderLibrary(context: ctx)
            fern = try FiddleheadFern(device: ctx.device, library: lib.library, pixelFormat: .bgra8Unorm_srgb)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            guard let t = ctx.device.makeTexture(descriptor: d),
                  let b = ctx.device.makeBuffer(length: width * height * 4, options: .storageModeShared) else {
                throw FiddleheadFernError.allocationFailed
            }
            target = t; readback = b
            fern.ensureAllocated(width: width, height: height)
        }

        /// One app frame. Returns GPU milliseconds.
        @discardableResult
        func frame(_ f: FeatureVector) -> Double {
            guard let cb = ctx.commandQueue.makeCommandBuffer() else { return 0 }
            fern.update(features: f, stemFeatures: StemFeatures(), commandBuffer: cb)
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = target
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.01, green: 0.012, blue: 0.05, alpha: 1)
            rp.colorAttachments[0].storeAction = .store
            if let enc = cb.makeRenderCommandEncoder(descriptor: rp) {
                fern.render(encoder: enc, features: f)
                enc.endEncoding()
            }
            if let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                          sourceSize: MTLSize(width: target.width, height: target.height, depth: 1),
                          to: readback, destinationOffset: 0, destinationBytesPerRow: target.width * 4,
                          destinationBytesPerImage: target.width * target.height * 4)
                blit.endEncoding()
            }
            cb.commit(); cb.waitUntilCompleted()
            return (cb.gpuEndTime - cb.gpuStartTime) * 1000
        }

        /// Frames until the bake lands (it runs on its own queue). Bounded: a bake that never completes is a failure.
        func waitForBake(_ f: FeatureVector) -> Bool {
            for _ in 0..<600 where !fern.isReady {
                frame(f)
                Thread.sleep(forTimeInterval: 0.01)
            }
            return fern.isReady
        }

        /// (mean luma 0…255, fraction of near-white pixels, luma std) of the last frame.
        func stats() -> (mean: Double, white: Double, std: Double) {
            let p = readback.contents().assumingMemoryBound(to: UInt8.self)
            let n = target.width * target.height
            var sum = 0.0, sq = 0.0, white = 0
            for i in 0..<n {
                let y = 0.0722 * Double(p[i * 4]) + 0.7152 * Double(p[i * 4 + 1]) + 0.2126 * Double(p[i * 4 + 2])   // BGRA
                sum += y; sq += y * y
                if y > 250 { white += 1 }
            }
            let mean = sum / Double(n)
            return (mean, Double(white) / Double(n), (sq / Double(n) - mean * mean).squareRoot())
        }

        func writePNG(_ url: URL) {
            guard let ctxCG = CGContext(data: readback.contents(), width: target.width, height: target.height, bitsPerComponent: 8,
                                        bytesPerRow: target.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  let img = ctxCG.makeImage(),
                  let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
        }
    }

    static func features(frame i: Int, fps: Float = 30, bpm: Float = 118) -> FeatureVector {
        var f = FeatureVector()
        let t = Float(i) / fps, beats = t * bpm / 60
        f.time = t; f.deltaTime = 1 / fps
        f.beatPhase01 = beats - floor(beats)
        f.barPhase01 = beats / 4 - floor(beats / 4)
        f.bassDev = 0.3 * exp(-(beats - floor(beats)) * 4); f.trebDev = 0.004; f.spectralSurge = 0.6
        return f
    }

    @Test("bakes, then renders a fern: lit, varied, not clipped")
    func rendersAFern() throws {
        let rig = try Rig(width: 640, height: 360)
        #expect(rig.waitForBake(Self.features(frame: 0)))
        for i in 0..<45 { rig.frame(Self.features(frame: i)) }
        let s = rig.stats()
        #expect(s.mean > 20 && s.mean < 200, "mean luma \(s.mean)")
        #expect(s.white < 0.05, "clipped fraction \(s.white)")
        #expect(s.std > 15, "luma std \(s.std) — a flat frame is not a fern")
    }

    @Test("FIDDLEHEAD_FILM=1: 1080p sequence + GPU frame-time percentiles",
          .enabled(if: ProcessInfo.processInfo.environment["FIDDLEHEAD_FILM"] == "1"))
    func film() throws {
        let env = ProcessInfo.processInfo.environment
        let w = Int(env["FIDDLEHEAD_W"] ?? "") ?? 1920, h = Int(env["FIDDLEHEAD_H"] ?? "") ?? 1080
        let frames = Int(env["FIDDLEHEAD_FRAMES"] ?? "") ?? 300
        let rig = try Rig(width: w, height: h)
        #expect(rig.waitForBake(Self.features(frame: 0)))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fiddlehead_film")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var times: [Double] = []
        for i in 0..<frames {
            times.append(rig.frame(Self.features(frame: i)))
            // PNGs only on request: encoding one takes ~150 ms of CPU, the GPU idles and clocks down, and the
            // timings measure a cold GPU (31 ms here against 19 ms back-to-back)
            if env["FIDDLEHEAD_PNG"] == "1" { rig.writePNG(dir.appendingPathComponent(String(format: "f%05d.png", i))) }
        }
        times.sort()
        print(String(format: "FIDDLEHEAD %dx%d GPU ms p50 %.1f p95 %.1f max %.1f → %@", w, h,
                     times[times.count / 2], times[times.count * 95 / 100], times[times.count - 1], dir.path))
    }
}
