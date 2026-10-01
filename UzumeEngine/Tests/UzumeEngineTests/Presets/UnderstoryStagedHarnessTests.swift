// UnderstoryStagedHarnessTests — the multi-frame harness for Understory (UND.0 / UND.1),
// copy-adapted from `PersistentStagedPathHarnessTemplate` (PRESET_SESSION_CHECKLIST Part 2:
// the harness precedes the shader work it guards).
//
// Dispatch path exercised: the production staged frame — `RenderPipeline.encodeOffscreenStages`
// (persistent `fronds` ping-pong, watchdog probe, swap commit) then `encodeStage` for the final
// `present` stage into a capture texture (no MTKView headless). Slot 6 carries a real
// `UnderstoryField.buffer`, ticked every frame exactly as the app's `setMeshPresetTick` does.
//
// Two tests, both GPU and env-gated (not in the default parallel run):
//   • HARNESS_TEMPLATES=1 — 60 silence frames: the persistent frond neither blows up, decays to
//     nothing, nor renders black.
//   • UNDERSTORY_SEQUENCE=<fixture> — replays `route_coverage/<fixture>/features.csv` at 60 fps
//     from t = 0 and writes frames (UNDERSTORY_SIZE=WxH, default 640×480) for t ∈ [8, 20) s to
//     /tmp/uzume_visual/understory_<fixture>/understory_seq_*.png, plus `bend.csv` — the
//     side-by-side input for the UND.1 GO/NO-GO against the butterchurn oracle (same window,
//     same frame size, same 4:3 frame the source draws in).

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - UnderstoryStagedHarnessTests

@Suite("Understory staged harness (env-gated, UND.1)")
@MainActor
struct UnderstoryStagedHarnessTests {

    private struct Rig {
        let ctx: MetalContext
        let pipeline: RenderPipeline
        let finalSpec: StagedStageSpec
        let capture: MTLTexture
        let field: UnderstoryField
        let width: Int
        let height: Int

        /// One production staged frame: tick the springs, encode every stage, capture.
        func frame(_ features: FeatureVector) throws {
            var features = features
            field.tick(deltaTime: features.deltaTime, features: features)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
            let front = pipeline.encodeOffscreenStages(commandBuffer: cmd, features: &features, stemFeatures: .zero)
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = capture
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw HarnessError.encoderCreationFailed }
            pipeline.encodeStage(stage: finalSpec, encoder: enc, features: &features, stemFeatures: .zero, textures: front)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
        }

        var pixels: [UInt8] { HarnessTemplateCore.readBGRA(capture, width: width, height: height) }

        /// `frame`, returning the command buffer's GPU time in seconds.
        func timedFrame(_ features: FeatureVector) throws -> Double {
            var features = features
            field.tick(deltaTime: features.deltaTime, features: features)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
            let front = pipeline.encodeOffscreenStages(commandBuffer: cmd, features: &features, stemFeatures: .zero)
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = capture
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw HarnessError.encoderCreationFailed }
            pipeline.encodeStage(stage: finalSpec, encoder: enc, features: &features, stemFeatures: .zero, textures: front)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            return cmd.gpuEndTime - cmd.gpuStartTime
        }
    }

    private static func rig(width: Int, height: Int) throws -> Rig {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Understory" }) else {
            throw HarnessError.presetNotFound("Understory")
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)
        let specs = preset.stages.map {
            StagedStageSpec(name: $0.name, pipelineState: $0.pipelineState, samples: $0.samples,
                            writesToDrawable: $0.writesToDrawable, persistent: $0.persistent,
                            iterations: $0.iterations, pixelFormat: $0.pixelFormat)
        }
        guard let finalSpec = specs.last, finalSpec.writesToDrawable else {
            throw HarnessError.setupFailed("staged final stage must write to drawable")
        }
        pipeline.setStagedRuntime(specs, drawableSize: CGSize(width: width, height: height))
        guard let field = UnderstoryField(device: ctx.device) else { throw HarnessError.setupFailed("UnderstoryField") }
        pipeline.setDirectPresetFragmentBuffer(field.buffer)
        let capture = try HarnessTemplateCore.makeCaptureTexture(ctx, width: width, height: height,
                                                                 pixelFormat: ctx.pixelFormat)
        return Rig(ctx: ctx, pipeline: pipeline, finalSpec: finalSpec, capture: capture, field: field,
                   width: width, height: height)
    }

    // MARK: Silence

    @Test("at silence the persistent frond grows, holds, and never renders black")
    func silenceIsStable() throws {
        guard HarnessTemplateCore.isEnabled else { return }
        let rig = try Self.rig(width: 320, height: 180)
        var mass: [Double] = []
        for i in 0..<60 {
            var f = HarnessTemplateCore.silenceFeature(frame: i)
            f.aspectRatio = 320.0 / 180.0
            try rig.frame(f)
            mass.append(try Self.frondMass(rig.pipeline))
        }
        let first = mass[0], last = mass[59]
        print(String(format: "[understory-harness] frond mass frame 1 %.2f | frame 30 %.2f | frame 60 %.2f | watchdog %d",
                     first, mass[29], last, rig.pipeline.stagedWatchdogTripCount))
        #expect(mass.allSatisfy { $0.isFinite })
        #expect(rig.pipeline.stagedWatchdogTripCount == 0)
        #expect(first > 0, "the seed must land on frame 1")
        #expect(last > first * 2, "the frond must grow out of the seed at silence")
        #expect(mass[59] - mass[49] < mass[10] - mass[0], "growth must decelerate toward the attractor")
        let px = rig.pixels
        #expect(HarnessTemplateCore.isNonConstant(px))
        #expect(HarnessTemplateCore.meanLuma(px) > 0.015, "silence must not render black (D-037)")
    }

    /// Sum of the `fronds` stage's density channel.
    private static func frondMass(_ pipeline: RenderPipeline) throws -> Double {
        guard let tex = pipeline.stagedTexture(named: "fronds") else { throw HarnessError.setupFailed("fronds") }
        let bytes = HarnessTemplateCore.readHalf(tex, width: tex.width, height: tex.height)
        var sum = 0.0
        bytes.withUnsafeBytes { raw in
            let halves = raw.bindMemory(to: UInt16.self)
            for i in stride(from: 0, to: halves.count, by: 4) {
                sum += Double(HarnessTemplateCore.halfToFloat(halves[i]))
            }
        }
        return sum
    }

    // MARK: Fixture sequence

    @Test("fixture replay writes the GO/NO-GO sequence")
    func fixtureSequence() throws {
        guard let fixture = ProcessInfo.processInfo.environment["UNDERSTORY_SEQUENCE"] else { return }
        let root = try #require(Bundle.module.url(forResource: "route_coverage", withExtension: nil))
        let rows = try SessionReplayHarness.loadRowsForReplay(
            root.appendingPathComponent(fixture).appendingPathComponent("features.csv"))
        try #require(!rows.isEmpty)
        let out = URL(fileURLWithPath: "/tmp/uzume_visual/understory_\(fixture)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        // UNDERSTORY_SIZE=WxH (default 640x480, the oracle's frame for the UND.1 side-by-side).
        let dims = (ProcessInfo.processInfo.environment["UNDERSTORY_SIZE"] ?? "640x480")
            .split(separator: "x").compactMap { Int($0) }
        let (width, height) = dims.count == 2 ? (dims[0], dims[1]) : (640, 480)
        let rig = try Self.rig(width: width, height: height)
        var bendLog = ["frame,t,bend,direction"]
        var row = 0
        for i in 0..<(20 * 60) {
            let t = Float(i) / 60
            while row + 1 < rows.count && rows[row + 1].time <= t { row += 1 }
            var f = SessionReplayHarness.featureForReplay(from: rows[row], aspect: Float(width) / Float(height))
            f.time = t
            f.deltaTime = 1.0 / 60.0
            try rig.frame(f)
            guard t >= 8 else { continue }
            let n = i - 8 * 60
            let frond = rig.field.frondsForTesting()[0]
            bendLog.append(String(format: "%d,%.4f,%.5f,%.5f", n, t, frond.bend, frond.direction))
            if n % 90 == 0, ProcessInfo.processInfo.environment["UNDERSTORY_ATLAS"] == "1",
               let atlas = rig.pipeline.stagedTexture(named: "fronds") {
                try Self.writePNG(Self.atlasGray(atlas), width: atlas.width, height: atlas.height,
                                  to: out.appendingPathComponent(String(format: "atlas_%05d.png", n)))
            }
            try Self.writePNG(rig.pixels, width: width, height: height,
                              to: out.appendingPathComponent(String(format: "understory_seq_%05d.png", n)))
        }
        try (bendLog.joined(separator: "\n") + "\n").write(to: out.appendingPathComponent("bend.csv"),
                                                          atomically: true, encoding: .utf8)
        print("[understory-harness] wrote 720 frames + bend.csv to \(out.path); watchdog \(rig.pipeline.stagedWatchdogTripCount)")
        #expect(rig.pipeline.stagedWatchdogTripCount == 0)
    }

    // MARK: GPU cost

    /// UNDERSTORY_PERF=1 — median GPU time of the full staged frame at 1080p and 4K, the number
    /// behind the sidecar's `complexity_cost`. Quote it only from a Release run:
    /// `swift test -c release --enable-testable-imports` (CLAUDE.md: Debug numbers mean nothing).
    @Test("GPU cost of the staged frame at 1080p and 4K")
    func gpuCost() throws {
        guard ProcessInfo.processInfo.environment["UNDERSTORY_PERF"] == "1" else { return }
        #if DEBUG
        print("[understory-perf] DEBUG build — numbers below are NOT a cost (use -c release)")
        #endif
        for (width, height) in [(1920, 1080), (3840, 2160)] {
            let rig = try Self.rig(width: width, height: height)
            var millis: [Double] = []
            for i in 0..<240 {
                var f = HarnessTemplateCore.silenceFeature(frame: i)
                f.aspectRatio = Float(width) / Float(height)
                f.bass = 0.3 + 0.2 * sin(Float(i) * 0.3)
                f.treble = 0.01
                let gpu = try rig.timedFrame(f)
                if i >= 60 { millis.append(gpu * 1000) }
            }
            millis.sort()
            print(String(format: "[understory-perf] %dx%d GPU ms: median %.3f  p90 %.3f  max %.3f",
                         width, height, millis[millis.count / 2], millis[millis.count * 9 / 10],
                         millis.last ?? 0))
        }
    }

    /// The `fronds` atlas density as an opaque grey BGRA image (diagnostics).
    private static func atlasGray(_ tex: MTLTexture) -> [UInt8] {
        let bytes = HarnessTemplateCore.readHalf(tex, width: tex.width, height: tex.height)
        var out = [UInt8](repeating: 255, count: tex.width * tex.height * 4)
        bytes.withUnsafeBytes { raw in
            let halves = raw.bindMemory(to: UInt16.self)
            for i in 0..<(tex.width * tex.height) {
                let v = UInt8(max(0, min(255, HarnessTemplateCore.halfToFloat(halves[i * 4]) * 255)))
                out[i * 4] = v; out[i * 4 + 1] = v; out[i * 4 + 2] = v
            }
        }
        return out
    }

    private static func writePNG(_ bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw HarnessError.setupFailed("sRGB") }
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
            return context.makeImage()
        }
        guard let image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw HarnessError.setupFailed("PNG")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw HarnessError.setupFailed("PNG write") }
    }
}
