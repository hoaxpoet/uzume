// EnergeticFlybyReconstructionTests — EFB.4: Energetic Flyby on MFX.2's temporal reconstruction.
//
// The scene is loaded through `PresetLoader` (its own shader + sidecar), `EnergeticFlybyState` is ticked
// per frame and bound at slot 6, and reconstructed frames go through `RenderPipeline.encodeTemporalReconstruction`
// — the production encode. "Today" is the plain pipeline at the tier-1 cap stretched bilinearly (the A4 canvas),
// "native" the plain pipeline at the output size.
//
//   • motionFieldPredictsNextFrame (always runs) — warping frame N by frame N+1's motion field predicts N+1 on
//     thin edges, materially better than camera-only motion (task 2's done-when).
//   • evidence (EFB_RECON_EVIDENCE=1, Release) — GPU time per mode at 4K, the three route-coverage replays in
//     reconstructed mode (motion-gate sequence, continuity, flash, downbeat colour lag vs native, with and
//     without the reactive mask), the worst-case flash train, and stills native / reconstructed / stretch /
//     MetalFX spatial at three moments. `swift test -c release --enable-testable-imports --filter
//     EnergeticFlybyReconstruction`; EFB_RECON_OUT picks the output directory.

import Testing
import Metal
import MetalFX
import Foundation
import simd
@testable import Renderer
@testable import Presets
@testable import Shared
@testable import Diagnostics

// MARK: - Rig

@MainActor
final class EFBReconRig {
    let context: MetalContext
    let pipeline: RenderPipeline
    let preset: PresetLoader.LoadedPreset
    let state: EnergeticFlybyState
    let outW: Int
    let outH: Int
    private var textures: [String: MTLTexture] = [:]

    /// `reactiveMask: false` loads the same shader with the mask switched off (the colour-lag control arm).
    init(outW: Int, outH: Int, reactiveMask: Bool = true, internalScale: Float? = nil) throws {
        let ctx = try MetalContext()
        context = ctx
        var src = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { src.deleteLastPathComponent() }   // → UzumeEngine/
        src.appendPathComponent("Sources/Presets/Shaders")
        let shader = try String(contentsOf: src.appendingPathComponent("EnergeticFlyby.metal"), encoding: .utf8)
        var sidecar = try String(contentsOf: src.appendingPathComponent("EnergeticFlyby.json"), encoding: .utf8)
        if !reactiveMask { sidecar = sidecar.replacingOccurrences(of: "\"reactive_mask\": true", with: "\"reactive_mask\": false") }
        if let internalScale {
            sidecar = sidecar.replacingOccurrences(of: "\"internal_scale\": 0.6666667", with: "\"internal_scale\": \(internalScale)")
        }
        preset = try MFXProofScene.load(shader: shader, sidecar: sidecar, file: "EnergeticFlyby", context: ctx)
        guard let spec = preset.descriptor.temporalReconstruction, preset.temporalPipelineState != nil else {
            throw MFXProofError.noPipeline
        }
        #expect(spec.reactiveMask == reactiveMask)
        let library = try ShaderLibrary(context: ctx)
        let stride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * stride),
              let wave = ctx.makeSharedBuffer(length: 2048 * stride),
              let flyby = EnergeticFlybyState(device: ctx.device, faithful: false) else { throw MFXProofError.gpu("setup") }
        let pipe = try RenderPipeline(context: ctx, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wave)
        pipe.mvWarpLock.withLock { pipe.presentationSize = CGSize(width: outW, height: outH) }
        pipe.setTemporalReconstruction(spec, pipeline: preset.temporalPipelineState)
        pipe.setDirectPresetFragmentBuffer(flyby.stateBuffer)
        pipeline = pipe
        state = flyby
        self.outW = outW
        self.outH = outH
    }

    /// Overwrite the state the shader reads (after `tick`, or instead of it).
    func force(_ gpu: EnergeticFlybyStateGPU) {
        var copy = gpu
        state.stateBuffer.contents().copyMemory(from: &copy, byteCount: MemoryLayout<EnergeticFlybyStateGPU>.stride)
    }

    // MARK: Modes

    /// The plain (shipped) pipeline at `width × height` into an 8-bit sRGB texture, then copied (bilinear) to
    /// `outW × outH` when the sizes differ — native when they match, today's tier-1 stretch at the cap.
    func plain(_ fv: FeatureVector, width: Int, height: Int, slot: String, toOutput: Bool = true,
               gpuMs: inout Double?) throws -> MTLTexture {
        let src = try texture(context.pixelFormat, width, height, "plain_\(slot)")
        guard let cb = context.commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: Self.pass([src])) else { throw MFXProofError.gpu("plain") }
        var features = fv
        pipeline.encodePresetVisualization(into: enc, activePipeline: preset.pipelineState, features: &features,
                                           stems: .zero, particles: nil, textOverlay: nil)
        enc.endEncoding()
        var out = src
        if toOutput, width != outW || height != outH {
            out = try texture(context.pixelFormat, outW, outH, "plain_out_\(slot)")
            pipeline.copy(src, to: out, commandBuffer: cb)
        }
        try finish(cb, &gpuMs)
        return out
    }

    /// One production reconstruct encode, copied to an 8-bit sRGB `outW × outH` texture (what the drawable gets).
    func reconstruct(_ fv: FeatureVector, gpuMs: inout Double?) throws -> MTLTexture {
        let out = try texture(context.pixelFormat, outW, outH, "recon_out")
        guard let cb = context.commandQueue.makeCommandBuffer() else { throw MFXProofError.gpu("cb") }
        var features = fv
        guard let image = pipeline.encodeTemporalReconstruction(
            commandBuffer: cb, outputWidth: outW, outputHeight: outH,
            features: &features, stems: .zero, textOverlay: nil) else { throw MFXProofError.noPipeline }
        pipeline.copy(image, to: out, commandBuffer: cb)
        try finish(cb, &gpuMs)
        return out
    }

    /// Comparison column only (nothing ships it; D-263): MetalFX SPATIAL from the plain render at the cap.
    func spatial(_ fv: FeatureVector, width: Int, height: Int) throws -> MTLTexture {
        let src = try texture(.rgba16Float, width, height, "spatial_src", storage: .private)
        let mrt = try mrtTargets(width, height, storage: .private)
        guard let cb = context.commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: Self.pass([src] + mrt.dropFirst())),
              let temporal = preset.temporalPipelineState else { throw MFXProofError.gpu("spatial") }
        var features = fv
        var frame = DirectTemporalFrame()
        frame.renderSize = SIMD2(Float(width), Float(height))
        pipeline.encodePresetVisualization(into: enc, activePipeline: temporal, features: &features,
                                           stems: .zero, particles: nil, textOverlay: nil, temporalFrame: frame)
        enc.endEncoding()
        if spatialScaler == nil {
            let desc = MTLFXSpatialScalerDescriptor()
            desc.inputWidth = width
            desc.inputHeight = height
            desc.outputWidth = outW
            desc.outputHeight = outH
            desc.colorTextureFormat = .rgba16Float
            desc.outputTextureFormat = .rgba16Float
            desc.colorProcessingMode = .linear
            spatialScaler = desc.makeSpatialScaler(device: context.device)
        }
        guard let scaler = spatialScaler else { throw MFXProofError.gpu("spatial scaler") }
        let up = try texture(.rgba16Float, outW, outH, "spatial_up", storage: .private,
                             usage: scaler.outputTextureUsage.union(.shaderRead))
        scaler.colorTexture = src
        scaler.inputContentWidth = width
        scaler.inputContentHeight = height
        scaler.outputTexture = up
        scaler.encode(commandBuffer: cb)
        let out = try texture(context.pixelFormat, outW, outH, "spatial_out")
        pipeline.copy(up, to: out, commandBuffer: cb)
        var unused: Double?
        try finish(cb, &unused)
        return out
    }
    private var spatialScaler: MTLFXSpatialScaler?

    /// The MRT fragment at `width × height` with zero jitter: linear colour, depth, motion, reactive.
    func mrt(_ fv: FeatureVector, width: Int, height: Int) throws -> (color: [Float16], motion: [Float16], reactive: [UInt8]) {
        let targets = try mrtTargets(width, height, storage: .shared)
        guard let cb = context.commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: Self.pass(targets)),
              let temporal = preset.temporalPipelineState else { throw MFXProofError.gpu("mrt") }
        var features = fv
        var frame = DirectTemporalFrame()
        frame.renderSize = SIMD2(Float(width), Float(height))
        frame.outputSize = frame.renderSize
        pipeline.encodePresetVisualization(into: enc, activePipeline: temporal, features: &features,
                                           stems: .zero, particles: nil, textOverlay: nil, temporalFrame: frame)
        enc.endEncoding()
        var unused: Double?
        try finish(cb, &unused)
        return (Self.read(targets[0], Float16.self, 4), Self.read(targets[2], Float16.self, 2), Self.read(targets[3], UInt8.self, 1))
    }

    // MARK: Plumbing

    private func mrtTargets(_ width: Int, _ height: Int, storage: MTLStorageMode) throws -> [MTLTexture] {
        let formats: [MTLPixelFormat] = [TemporalReconstructionSpec.colorFormat, TemporalReconstructionSpec.depthFormat,
                                         TemporalReconstructionSpec.motionFormat, TemporalReconstructionSpec.reactiveFormat]
        return try formats.enumerated().map { try texture($1, width, height, "mrt\($0)_\(storage.rawValue)", storage: storage) }
    }

    private static func pass(_ targets: [MTLTexture]) -> MTLRenderPassDescriptor {
        let pass = MTLRenderPassDescriptor()
        for (index, tex) in targets.enumerated() {
            pass.colorAttachments[index].texture = tex
            pass.colorAttachments[index].loadAction = .clear
            pass.colorAttachments[index].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            pass.colorAttachments[index].storeAction = .store
        }
        return pass
    }

    private func finish(_ cb: MTLCommandBuffer, _ gpuMs: inout Double?) throws {
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw MFXProofError.gpu("\(error)") }
        if cb.gpuEndTime > cb.gpuStartTime { gpuMs = (cb.gpuEndTime - cb.gpuStartTime) * 1000 }
    }

    func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int, _ key: String,
                 storage: MTLStorageMode = .shared, usage: MTLTextureUsage = [.renderTarget, .shaderRead]) throws -> MTLTexture {
        let name = "\(key)_\(width)x\(height)"
        if let tex = textures[name] { return tex }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = usage
        desc.storageMode = storage
        guard let tex = context.device.makeTexture(descriptor: desc) else { throw MFXProofError.gpu("texture") }
        textures[name] = tex
        return tex
    }

    static func read<T: Numeric>(_ tex: MTLTexture, _: T.Type, _ channels: Int) -> [T] {
        var out = [T](repeating: 0, count: tex.width * tex.height * channels)
        out.withUnsafeMutableBytes { ptr in
            tex.getBytes(ptr.baseAddress!, bytesPerRow: tex.width * channels * MemoryLayout<T>.stride,   // swiftlint:disable:this force_unwrapping
                         from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        }
        return out
    }

    func bgra(_ tex: MTLTexture) -> [UInt8] { Self.read(tex, UInt8.self, 4) }
}

// MARK: - Tests

@Suite("EnergeticFlybyReconstruction (EFB.4)")
@MainActor
struct EnergeticFlybyReconstructionTests {

    static let fps: Float = 30   // the scene's render cap

    /// `seconds` of a route-coverage capture at `fps`, each row held until the next (replayEvidence's axis).
    static func drive(_ capture: String, seconds: Float, aspect: Float = 16 / 9) throws -> [FeatureVector] {
        let rows = try SessionReplayHarness.loadRowsForReplay(
            EnergeticFlybyRenderTests.fixturesDir().appendingPathComponent("route_coverage/\(capture)/features.csv"))
        let start = rows[0].playbackTime
        var row = 0
        return (0..<Int(seconds * fps)).map { i in
            let t = start + Float(i) / fps
            while row + 1 < rows.count && rows[row + 1].playbackTime <= t { row += 1 }
            var fv = SessionReplayHarness.featureForReplay(from: rows[row], aspect: aspect)
            fv.deltaTime = 1 / fps
            return fv
        }
    }

    // MARK: - Motion field (task 2)

    @Test("Warping frame N by N+1's motion predicts N+1 on thin edges, better than camera-only motion")
    func motionFieldPredictsNextFrame() throws {
        let width = 960, height = 540
        let rig = try EFBReconRig(outW: width, outH: height)
        let drive = try Self.drive("there_there", seconds: 16)
        var trace: [EnergeticFlybyStateGPU] = []
        for fv in drive {
            rig.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            trace.append(rig.state.gpuState)
        }
        // Self-consistency: previous == current must give zero motion everywhere (projection inverts the ray).
        var still = trace[200]
        (still.prevTime, still.prevTravel, still.prevCamT) = (still.time, still.travel, still.camT)
        (still.prevSpin, still.prevRoll, still.prevHue) = (still.spin, still.roll, still.hue)
        rig.force(still)
        let stillMotion = try rig.mrt(drive[200], width: width, height: height).motion.map { abs(Float($0)) }
        let maxStill = stillMotion.max() ?? 0
        print(String(format: "[efb4-motion] previous == current: max |motion| %.4f px, mean %.5f px", maxStill,
                     stillMotion.reduce(0, +) / Float(stillMotion.count)))
        #expect(maxStill < 0.05, "a frame against itself moves \(maxStill) px")
        var errors: [(full: Double, camera: Double, zero: Double)] = []
        for n in [90, 180, 270, 360, 450] {
            rig.force(trace[n])
            let previous = try rig.mrt(drive[n], width: width, height: height).color
            rig.force(trace[n + 1])
            let next = try rig.mrt(drive[n + 1], width: width, height: height)
            var cameraOnly = trace[n + 1]
            cameraOnly.cameraOnlyMotion = 1
            rig.force(cameraOnly)
            let cameraMotion = try rig.mrt(drive[n + 1], width: width, height: height).motion
            let edges = Self.edgePixels(next.color, width, height, topFraction: 0.1)
            func error(_ motion: [Float16]?) -> Double {
                var sum = 0.0, count = 0
                for i in edges {
                    let x = Float(i % width) + 0.5 + Float(motion?[2 * i] ?? 0)
                    let y = Float(i / width) + 0.5 + Float(motion?[2 * i + 1] ?? 0)
                    guard x >= 0.5, y >= 0.5, x <= Float(width) - 0.5, y <= Float(height) - 0.5 else { continue }
                    sum += abs(Self.bilinearLuma(previous, width, height, x, y) - Self.luma(next.color, i))
                    count += 1
                }
                return sum / Double(max(count, 1))
            }
            errors.append((error(next.motion), error(cameraMotion), error(nil)))
        }
        for (k, e) in errors.enumerated() {
            print(String(format: "[efb4-motion] pair %d: thin-edge mean |Δ| (linear luma) analytic %.4f | camera-only %.4f | "
                         + "zero motion %.4f", k, e.full, e.camera, e.zero))
        }
        let full = errors.map(\.full).reduce(0, +) / Double(errors.count)
        let camera = errors.map(\.camera).reduce(0, +) / Double(errors.count)
        let zero = errors.map(\.zero).reduce(0, +) / Double(errors.count)
        print(String(format: "[efb4-motion] mean: analytic %.4f, camera-only %.4f (×%.2f), zero %.4f (×%.2f)",
                     full, camera, camera / full, zero, zero / full))
        // Negative control: camera-only must itself beat zero motion, or the camera reprojection is wrong.
        #expect(camera < zero, "camera-only \(camera) vs zero \(zero)")
        #expect(full < 0.8 * camera, "analytic \(full) vs camera-only \(camera): not materially better")
    }

    /// Indices of the `topFraction` highest-gradient pixels (central differences on linear luma).
    static func edgePixels(_ color: [Float16], _ w: Int, _ h: Int, topFraction: Double) -> [Int] {
        var grad: [(Int, Double)] = []
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * w + x
                let gx = luma(color, i + 1) - luma(color, i - 1)
                let gy = luma(color, i + w) - luma(color, i - w)
                grad.append((i, gx * gx + gy * gy))
            }
        }
        grad.sort { $0.1 > $1.1 }
        return grad.prefix(Int(Double(grad.count) * topFraction)).map(\.0)
    }

    static func luma(_ c: [Float16], _ i: Int) -> Double {
        0.2126 * Double(c[4 * i]) + 0.7152 * Double(c[4 * i + 1]) + 0.0722 * Double(c[4 * i + 2])
    }

    static func bilinearLuma(_ c: [Float16], _ w: Int, _ h: Int, _ x: Float, _ y: Float) -> Double {
        let fx = x - 0.5, fy = y - 0.5
        let x0 = min(max(Int(fx), 0), w - 2), y0 = min(max(Int(fy), 0), h - 2)
        let ax = Double(fx - Float(x0)), ay = Double(fy - Float(y0))
        let i = y0 * w + x0
        return (luma(c, i) * (1 - ax) + luma(c, i + 1) * ax) * (1 - ay)
            + (luma(c, i + w) * (1 - ax) + luma(c, i + w + 1) * ax) * ay
    }

    // MARK: - Evidence (task 5, EFB_RECON_EVIDENCE=1)

    @Test("Evidence: GPU per mode, replays, flash train, colour lag, stills (EFB_RECON_EVIDENCE=1)",
          .enabled(if: ProcessInfo.processInfo.environment["EFB_RECON_EVIDENCE"] == "1"))
    func evidence() throws {
        #if DEBUG
        print("[efb4] WARNING: Debug build — GPU numbers are not quotable (CLAUDE.md)")
        #endif
        let env = ProcessInfo.processInfo.environment
        let out = URL(fileURLWithPath: env["EFB_RECON_OUT"] ?? "/tmp/uzume_visual/efb4")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let parts = Set((env["EFB_RECON_PARTS"] ?? "timing,replay,flash,lag,stills").split(separator: ",").map(String.init))
        if parts.contains("timing") { try timing() }
        if parts.contains("stills") { try stills(out) }
        if parts.contains("flash") { try flashTrain() }
        if parts.contains("lag") { try colourLagControl() }
        if parts.contains("replay") {
            for capture in ["there_there", "love_rehab", "so_what"] {
                try replay(capture, out: out.appendingPathComponent(capture))
            }
        }
    }

    /// Release GPU ms at a 4K drawable: today (cap + stretch), reconstructed, native, spatial (comparison).
    private func timing() throws {
        let rig = try EFBReconRig(outW: 3840, outH: 2160)
        let half = try EFBReconRig(outW: 3840, outH: 2160, internalScale: 0.5)
        let drive = try Self.drive("there_there", seconds: 10)
        var ms: [String: [Double]] = [:]
        for (i, fv) in drive.enumerated() {
            rig.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            half.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            var today: Double?, recon: Double?, native: Double?, halfRecon: Double?
            _ = try rig.plain(fv, width: 2560, height: 1440, slot: "today", gpuMs: &today)
            _ = try rig.reconstruct(fv, gpuMs: &recon)
            _ = try rig.plain(fv, width: 3840, height: 2160, slot: "native", gpuMs: &native)
            _ = try half.reconstruct(fv, gpuMs: &halfRecon)
            guard i >= 10 else { continue }
            for (key, value) in [("today 2560×1440 stretched", today), ("reconstructed 2560×1440 → 3840×2160", recon),
                                 ("native 3840×2160", native), ("reconstructed 1920×1080 → 3840×2160 (scale 0.5)", halfRecon)] {
                if let value { ms[key, default: []].append(value) }
            }
        }
        for (key, values) in ms.sorted(by: { $0.key < $1.key }) {
            let s = values.sorted()
            print(String(format: "[efb4-timing] %@: p50 %.2f ms, p95 %.2f ms, max %.2f ms, %.1f%% > 33.3 ms (n=%d)",
                         key, s[s.count / 2], s[Int(Double(s.count) * 0.95)], s.last ?? 0,
                         Double(s.filter { $0 > 1000 / 30 }.count) / Double(s.count) * 100, s.count))
        }
    }

    /// The four modes at three moments of There There, full 4K frames.
    private func stills(_ out: URL) throws {
        let rig = try EFBReconRig(outW: 3840, outH: 2160)
        let half = try EFBReconRig(outW: 3840, outH: 2160, internalScale: 0.5)
        let drive = try Self.drive("there_there", seconds: 15)
        let moments = [149: "t05", 299: "t10", 449: "t15"]
        for (i, fv) in drive.enumerated() {
            rig.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            half.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            var unused: Double?
            let recon = try rig.reconstruct(fv, gpuMs: &unused)   // every frame: the history is the point
            let recon50 = try half.reconstruct(fv, gpuMs: &unused)
            guard let label = moments[i] else { continue }
            try EnergeticFlybyRenderTests.writePNG(half.bgra(recon50), 3840, 2160,
                                                   out.appendingPathComponent("efb4_\(label)_recon50.png"))
            let native = try rig.plain(fv, width: 3840, height: 2160, slot: "native", gpuMs: &unused)
            let today = try rig.plain(fv, width: 2560, height: 1440, slot: "today", gpuMs: &unused)
            let spatial = try rig.spatial(fv, width: 2560, height: 1440)
            for (mode, tex) in [("native", native), ("recon", recon), ("stretch", today), ("spatial", spatial)] {
                try EnergeticFlybyRenderTests.writePNG(rig.bgra(tex), 3840, 2160,
                                                       out.appendingPathComponent("efb4_\(label)_\(mode).png"))
            }
        }
        print("[efb4-stills] \(out.path)/efb4_t{05,10,15}_{native,recon,recon50,stretch,spatial}.png")
    }

    /// The certified flash measure (the worst-case train, 60 settle + 900 frames at 60 fps, 320×180 internal) on the
    /// plain path and through reconstruction (internal 320×180 → 480×270).
    private func flashTrain() throws {
        let train = FlashHarnessSupport.worstCaseBeatTrain()
        let drive = (0..<960).map { train[$0 % train.count] }
        func run(_ reconstructed: Bool) throws -> [FlashHarnessSupport.FlashSample] {
            let rig = try EFBReconRig(outW: reconstructed ? 480 : 320, outH: reconstructed ? 270 : 180)
            var samples: [FlashHarnessSupport.FlashSample] = []
            for (i, fv) in drive.enumerated() {
                rig.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
                var unused: Double?
                let tex = reconstructed ? try rig.reconstruct(fv, gpuMs: &unused)
                    : try rig.plain(fv, width: 320, height: 180, slot: "flash", gpuMs: &unused)
                if i >= 60 { samples.append(FlashHarnessSupport.sample(rig.bgra(tex), width: rig.outW, height: rig.outH)) }
            }
            return samples
        }
        for (name, samples) in [("plain (certified path)", try run(false)), ("reconstructed", try run(true))] {
            let luma = samples.map(\.luma)
            let full = FlashAnalyzer.analyze(relativeLuminance: luma, fps: FlashHarnessSupport.fps)
            let regional = FlashAnalyzer.analyzeRegional(samples.map(\.regions), fps: FlashHarnessSupport.fps)
            let red = FlashAnalyzer.analyzeRed(samples.map(\.regions), fps: FlashHarnessSupport.fps)
            let deltas = zip(luma, luma.dropFirst()).map { abs($1 - $0) }
            print(String(format: "[efb4-flash] %@: full %.2f/s (%d transitions) | regional %.2f/s | red %.2f/s | "
                         + "max Δ frame-mean luminance %.4f", name, full.peakFlashesPerSecond, full.transitionCount,
                         regional.peakFlashesPerSecond, red.peakFlashesPerSecond, deltas.max() ?? 0))
        }
    }

    /// Downbeat colour lag with and without the reactive mask, There There, 1920×1080 output.
    private func colourLagControl() throws {
        let drive = try Self.drive("there_there", seconds: 20)
        for mask in [true, false] {
            let rig = try EFBReconRig(outW: 1920, outH: 1080, reactiveMask: mask)
            var recon: [Double] = [], native: [Double] = [], hues: [Float] = []
            for fv in drive {
                rig.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
                var unused: Double?
                recon.append(Self.colourIndex(rig.bgra(try rig.reconstruct(fv, gpuMs: &unused))))
                native.append(Self.colourIndex(rig.bgra(try rig.plain(fv, width: 1920, height: 1080, slot: "n", gpuMs: &unused))))
                hues.append(rig.state.gpuState.hue)
            }
            let lags = Self.downbeatLags(recon: recon, native: native, hues: hues)
            print("[efb4-lag] reactive mask \(mask ? "on" : "off"): downbeat colour lag (frames, recon behind native) "
                  + "\(lags) | max \(lags.map(abs).max() ?? 0) | "
                  + String(format: "colour error over the 8 frames after a step %.5f, elsewhere %.5f",
                           Self.stepError(recon: recon, native: native, hues: hues, after: true),
                           Self.stepError(recon: recon, native: native, hues: hues, after: false)))
        }
    }

    /// One capture in reconstructed mode at a 4K drawable, 20 s at 30 fps.
    private func replay(_ capture: String, out: URL) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let rig = try EFBReconRig(outW: 3840, outH: 2160)
        let drive = try Self.drive(capture, seconds: 20)
        var luma: [Double] = [], grey: [[Double]] = [], flash: [FlashHarnessSupport.FlashSample] = []
        var recon: [Double] = [], native: [Double] = [], hues: [Float] = []
        for (i, fv) in drive.enumerated() {
            rig.state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            hues.append(rig.state.gpuState.hue)
            var unused: Double?
            let bgra = rig.bgra(try rig.reconstruct(fv, gpuMs: &unused))
            let small = EnergeticFlybyRenderTests.downsample(bgra, 3840, 2160, 8)   // 480×270
            try EnergeticFlybyRenderTests.writePNG(small, 480, 270, out.appendingPathComponent(String(format: "seq_%04d.png", i)))
            luma.append(EnergeticFlybyRenderTests.meanLuma(small))
            grey.append(EnergeticFlybyRenderTests.grey(small, 480, 270, 160, 90))
            flash.append(FlashHarnessSupport.sample(small, width: 480, height: 270))
            recon.append(Self.colourIndex(small))
            let nat = try rig.plain(fv, width: 960, height: 540, slot: "lag", toOutput: false, gpuMs: &unused)
            native.append(Self.colourIndex(rig.bgra(nat)))
        }
        let diffs: [Double] = zip(grey, grey.dropFirst()).map { (a: [Double], b: [Double]) -> Double in
            let total: Double = zip(a, b).map { abs($0 - $1) }.reduce(0, +)
            return total / Double(a.count)
        }
        let median = diffs.sorted()[diffs.count / 2]
        let full = FlashAnalyzer.analyze(relativeLuminance: flash.map(\.luma), fps: Double(Self.fps))
        let regional = FlashAnalyzer.analyzeRegional(flash.map(\.regions), fps: Double(Self.fps))
        let red = FlashAnalyzer.analyzeRed(flash.map(\.regions), fps: Double(Self.fps))
        let deltas = zip(luma, luma.dropFirst()).map { abs($1 - $0) }
        let lags = Self.downbeatLags(recon: recon, native: native, hues: hues)
        print(String(format: "[efb4-replay] %@ reconstructed 2560×1440 → 3840×2160 @30: continuity median %.4f max %.4f, "
                     + "%d frames > 3× median | flash full %.2f/s, regional %.2f/s, red %.2f/s | max Δ luma %.4f | "
                     + "downbeat colour lag %@ (max %d) | seq %@",
                     capture, median, diffs.max() ?? 0, diffs.filter { $0 > 3 * median }.count,
                     full.peakFlashesPerSecond, regional.peakFlashesPerSecond, red.peakFlashesPerSecond,
                     deltas.max() ?? 0, "\(lags)", lags.map(abs).max() ?? 0, out.path))
    }

    /// The glow's colour as one number: Σ(R − B) / Σ(R + G + B) over every 4th pixel.
    static func colourIndex(_ bgra: [UInt8]) -> Double {
        var diff = 0.0, sum = 0.0
        for i in stride(from: 0, to: bgra.count, by: 16) {
            let b = Double(bgra[i]), g = Double(bgra[i + 1]), r = Double(bgra[i + 2])
            diff += r - b
            sum += r + g + b
        }
        return diff / max(sum, 1)
    }

    /// Mean |recon − native| colour index over the 8 frames after each colour step (`after`), or over every other
    /// frame: a sub-frame measure of how much the reconstruction trails the turn.
    static func stepError(recon: [Double], native: [Double], hues: [Float], after: Bool) -> Double {
        var near = Set<Int>()
        for f in hues.indices.dropFirst() where hues[f] != hues[f - 1] { for j in 0..<8 { near.insert(f + j) } }
        let frames = recon.indices.filter { near.contains($0) == after }
        return frames.map { abs(recon[$0] - native[$0]) }.reduce(0, +) / Double(max(frames.count, 1))
    }

    /// For each downbeat colour step (the frame the hue starts moving), the shift k in −3…3 frames that best aligns
    /// the reconstructed colour index with native's over the next 12 frames, each relative to the frame before the
    /// step (so a steady offset between the two does not count). Positive = reconstruction behind native.
    static func downbeatLags(recon: [Double], native: [Double], hues: [Float]) -> [Int] {
        let starts = hues.indices.filter { $0 > 4 && $0 + 16 < hues.count && hues[$0] != hues[$0 - 1] && hues[$0 - 1] == hues[$0 - 2] }
        return starts.map { f in
            let r0 = recon[f - 1]
            return (-3...3).min { a, b in
                func err(_ k: Int) -> Double {
                    (0..<12).map { j in abs((recon[f + j] - r0) - (native[f + j - k] - native[f - 1 - k])) }.reduce(0, +)
                }
                return err(a) < err(b)
            } ?? 0
        }
    }
}
