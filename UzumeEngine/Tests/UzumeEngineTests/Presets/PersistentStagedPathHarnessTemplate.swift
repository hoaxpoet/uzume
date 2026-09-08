// PersistentStagedPathHarnessTemplate — reference multi-frame harness for a
// PERSISTENT, ITERATED staged preset (ALFVEN.1 task 7; QG.4 / D-182 spine).
// Copy-adapt this for any staged preset that carries state across frames —
// ALFVEN.2's Alfvén is the first consumer.
//
// It exists BEFORE the preset it serves on purpose: `PRESET_SESSION_CHECKLIST.md`
// Part 2 requires the multi-frame harness to precede the preset, because a
// stateful field's failure modes (blow-up, decay to nothing, freeze) are invisible
// in a single frame and were what cost the CPU spike three NaN cycles
// (ALFVEN_DESIGN.md §8).
//
// Dispatch path exercised — the full production staged frame, twice over:
//   • `RenderPipeline.encodeOffscreenStages` walks every non-final stage, runs the
//     pressure stage's 24 Jacobi sweeps against its own ping-pong pair, probes the
//     non-finite watchdog, and commits the frame's swaps. Same call `drawWithStaged`
//     makes.
//   • `RenderPipeline.encodeStage` then renders the final stage into a capture
//     texture instead of the drawable — the only substitution, and only because
//     there is no MTKView in a headless test.
// Nothing here re-implements the stage walk or the ping-pong, so a green run is
// evidence about the production encoder.
//
//   subject: Poisson Sandbox — velocity → divergence → pressure (persistent,
//            iterations 24, rgba32Float) → project → compose (drawable)
//
// Metric: the persistent pressure field's RMS across 60 silence frames. The two
// failure directions a stateful solver actually has are BOTH asserted — it must
// not saturate (RMS bounded, field finite, watchdog never trips) and it must not
// decay to nothing (RMS strictly positive and settled, not drifting to zero). A
// single-frame still cannot see either.
//
// GPU test — env-gated `HARNESS_TEMPLATES=1`, NOT in the default parallel run.

import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - PersistentStagedPathHarnessTemplate

@Suite("Persistent staged path harness template (env-gated, ALFVEN.1)")
@MainActor
struct PersistentStagedPathHarnessTemplate {

    private static let width = 256
    private static let height = 256
    private static let frameCount = 60
    private static let subjectName = "Poisson Sandbox"
    private static let stateStageName = "pressure"

    @Test("a persistent staged preset neither saturates nor decays over 60 frames")
    func persistentStagedPath_isStable() throws {
        guard HarnessTemplateCore.isEnabled else {
            print("PersistentStagedPathHarnessTemplate: HARNESS_TEMPLATES not set, skipping")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }) else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        guard !preset.stages.isEmpty else {
            throw HarnessError.setupFailed("\(Self.subjectName) has no staged stages")
        }

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)

        // Production stage specs, carrying the persistent / iterations / pixel_format
        // declarations straight off the sidecar. `setStagedRuntime` owns every
        // offscreen texture and ping-pong pair from here on — the harness allocates
        // only the drawable-substitute capture texture.
        let specs = preset.stages.map {
            StagedStageSpec(name: $0.name, pipelineState: $0.pipelineState, samples: $0.samples,
                            writesToDrawable: $0.writesToDrawable, persistent: $0.persistent,
                            iterations: $0.iterations, pixelFormat: $0.pixelFormat)
        }
        guard let finalSpec = specs.last, finalSpec.writesToDrawable else {
            throw HarnessError.setupFailed("staged final stage must write to drawable")
        }
        pipeline.setStagedRuntime(specs, drawableSize: CGSize(width: Self.width, height: Self.height))
        let capture = try HarnessTemplateCore.makeCaptureTexture(
            ctx, width: Self.width, height: Self.height, pixelFormat: ctx.pixelFormat)

        var stateRMS: [Double] = []
        stateRMS.reserveCapacity(Self.frameCount)

        for i in 0..<Self.frameCount {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            let front = pipeline.encodeOffscreenStages(commandBuffer: cmd, features: &features,
                                                       stemFeatures: .zero)
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = capture
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            desc.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else {
                throw HarnessError.encoderCreationFailed
            }
            pipeline.encodeStage(stage: finalSpec, encoder: enc, features: &features,
                                 stemFeatures: .zero, textures: front)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }

            stateRMS.append(try Self.rms(of: pipeline, stage: Self.stateStageName))

            // RENDER_VISUAL=1 dumps the composite at a few frames so a human can
            // SEE the field converge, not just read that it did. Task 5's "a
            // solved field must not be black" is an eyes claim; meanLuma below is
            // the floor, this is the evidence.
            if Self.dumpFrames.contains(i + 1), let dir = try Self.visualOutputDirectory() {
                try Self.writePNG(HarnessTemplateCore.readBGRA(capture, width: Self.width,
                                                              height: Self.height),
                                  to: dir.appendingPathComponent(
                                      String(format: "poisson_composite_frame%03d.png", i + 1)))
                print("[persistent-template] wrote \(dir.path)/poisson_composite_frame"
                      + String(format: "%03d.png", i + 1))
            }
        }

        // ── The metric ──
        guard let first = stateRMS.first, let last = stateRMS.last else {
            throw HarnessError.setupFailed("no frames captured")
        }
        let peak = stateRMS.max() ?? 0
        // Per-frame growth early vs late. At 256² a Jacobi solve is still climbing
        // toward its answer at frame 60 (24 sweeps damp the domain-scale mode by
        // only ~0.7 % per frame at this h), so "has settled" is the WRONG health
        // check here — it would fail a perfectly healthy field. What separates
        // healthy from broken is the SHAPE of the approach: a converging field's
        // per-frame increment shrinks, a running-away field's grows.
        let earlyGrowth = stateRMS[min(10, stateRMS.count - 1)] - first
        let lateGrowth = last - stateRMS[max(stateRMS.count - 11, 0)]
        print(String(format: "[persistent-template] %@/%@ RMS: frame 1 %.6f | frame %d %.6f | "
                             + "peak %.6f | growth frames 1–11 %.4f vs %d–%d %.4f | watchdog trips %d",
                     Self.subjectName, Self.stateStageName, first, Self.frameCount, last, peak,
                     earlyGrowth, Self.frameCount - 10, Self.frameCount, lateGrowth,
                     pipeline.stagedWatchdogTripCount))

        #expect(stateRMS.allSatisfy { $0.isFinite }, "persistent state went non-finite")
        #expect(pipeline.stagedWatchdogTripCount == 0,
                "the watchdog tripped — persistent state blew up during a silent run")

        // Does not decay to zero: the field carries signal and keeps it.
        #expect(last > 1e-6, "persistent state decayed to nothing by frame \(Self.frameCount)")
        #expect(last >= first, "persistent state is bleeding away frame over frame")

        // Does not saturate or run away: bounded, and DECELERATING toward a limit.
        #expect(peak < 1e3, "persistent state is running away (peak RMS \(peak))")
        #expect(lateGrowth >= 0, "persistent state reversed — it is not converging")
        #expect(lateGrowth < earlyGrowth, """
            persistent state is not converging: per-frame growth over the last 10 \
            frames (\(lateGrowth)) is not below the first 10 (\(earlyGrowth))
            """)

        // …and the thing a human looks at is neither black nor flat.
        let composite = HarnessTemplateCore.readBGRA(capture, width: Self.width, height: Self.height)
        #expect(HarnessTemplateCore.isNonConstant(composite), "composite is constant at silence")
        #expect(HarnessTemplateCore.meanLuma(composite) > 0.02,
                "a solved pressure field rendered black — a black diagnostic teaches nothing")
    }

    /// Frames whose composite is written to PNG under `RENDER_VISUAL=1`.
    private static let dumpFrames: Set<Int> = [1, 10, 30, 60]

    /// Output directory for the PNG dump, or nil when `RENDER_VISUAL` is unset.
    private static func visualOutputDirectory() throws -> URL? {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return nil }
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uzume-alfven1-poisson")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func writePNG(_ bgra: [UInt8], to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw HarnessError.setupFailed("sRGB colour space")
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: info.rawValue) else { return nil }
            return context.makeImage()
        }
        guard let image,
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw HarnessError.setupFailed("PNG destination")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw HarnessError.setupFailed("PNG write")
        }
    }

    /// Root-mean-square of the red channel of a persistent stage's current state.
    private static func rms(of pipeline: RenderPipeline, stage: String) throws -> Double {
        guard let texture = pipeline.stagedTexture(named: stage) else {
            throw HarnessError.setupFailed("no persistent texture for stage '\(stage)'")
        }
        let count = texture.width * texture.height
        var raw = [Float](repeating: 0, count: count * 4)
        raw.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: texture.width * 16,
                             from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                             size: MTLSize(width: texture.width,
                                                           height: texture.height, depth: 1)),
                             mipmapLevel: 0)
        }
        var sum = 0.0
        for i in 0..<count {
            let value = Double(raw[i * 4])
            sum += value * value
        }
        return (sum / Double(count)).squareRoot()
    }
}
