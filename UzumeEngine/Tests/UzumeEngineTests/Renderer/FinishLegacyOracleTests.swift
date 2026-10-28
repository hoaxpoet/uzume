// FinishLegacyOracleTests — VQ.1's legacy-mode oracle: a 1080p frame-exact capture of every
// certified scene, taken before the finishing stage landed and compared after.
//
// Env-gated (it renders the whole roster at 1920×1080 for 61 frames — minutes, and the point is
// the comparison across builds, not a per-run assertion):
//
//   FINISH_ORACLE=capture FINISH_ORACLE_DIR=<dir>  swift test … --filter FinishLegacyOracle
//       writes <dir>/<scene>.bgra (frame 60) + <dir>/manifest.txt (scene, path, SHA-256).
//   FINISH_ORACLE=compare FINISH_ORACLE_A=<dir> FINISH_ORACLE_B=<dir> FINISH_ORACLE_DIR=<dir>
//       captures into DIR, then asserts per scene: deterministic (A == B) → DIR == A byte for
//       byte; otherwise max |DIR − A| ≤ max |A − B| (within the run-to-run difference).
//
// VQ.3: `FINISH_ORACLE_SIZE=capped4k` captures the tier-1 case instead — the scene at the BR.6b
// render size (2560×1440) through the same paths, then the present step's stretch to a
// 3840×2160 drawable (`RenderPipeline.encodeLegacyPresent`, the production code) — so the default
// upscale is proved unchanged where it actually runs.
//
// Each scene renders through MultiPassRenderHarness (its real path) when the harness carries it;
// the rest (Murmuration, Nimbus, Aurora Veil) render their single fragment pipeline, as
// PresetRegressionTests does. The manifest names which path each capture exercised.

import CryptoKit
import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Finish legacy oracle (VQ.1)")
struct FinishLegacyOracleTests {

    static let frames = 61
    /// 1920×1080, or the BR.6b render size under `FINISH_ORACLE_SIZE=capped4k` (VQ.3).
    static let capped4K = ProcessInfo.processInfo.environment["FINISH_ORACLE_SIZE"] == "capped4k"
    static let width = capped4K ? 2560 : 1920, height = capped4K ? 1440 : 1080
    static let drawableWidth = 3840, drawableHeight = 2160

    @Test("Capture / compare the 1080p frame-60 oracle (FINISH_ORACLE)")
    func oracle() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let mode = env["FINISH_ORACLE"], let dirPath = env["FINISH_ORACLE_DIR"] else { return }
        let dir = URL(fileURLWithPath: dirPath)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // `FINISH_ORACLE_ONLY=<scene>` captures one scene (VQ.3: measuring a noisy scene's spread).
        let only = env["FINISH_ORACLE_ONLY"]
        var manifest: [String] = []
        for preset in _acceptanceFixture.presets where preset.descriptor.certified
            && (only == nil || preset.descriptor.name == only) {
            let name = preset.descriptor.name
            var (bytes, path) = try await Self.capture(preset)
            if Self.capped4K { bytes = try await Self.presentStretch(bytes) }
            try Data(bytes).write(to: dir.appendingPathComponent("\(Self.fileName(name)).bgra"))
            let digest = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
            manifest.append("\(name)\t\(path)\t\(digest)")
            print("[finish-oracle] \(name) via \(path): \(digest.prefix(16))")
        }
        try manifest.joined(separator: "\n").write(to: dir.appendingPathComponent("manifest.txt"),
                                                   atomically: true, encoding: .utf8)
        guard mode == "compare", let pathA = env["FINISH_ORACLE_A"], let pathB = env["FINISH_ORACLE_B"] else {
            return
        }
        var identical = 0, withinNoise = 0
        for preset in _acceptanceFixture.presets where preset.descriptor.certified {
            let file = "\(Self.fileName(preset.descriptor.name)).bgra"
            let a = try [UInt8](Data(contentsOf: URL(fileURLWithPath: pathA).appendingPathComponent(file)))
            let b = try [UInt8](Data(contentsOf: URL(fileURLWithPath: pathB).appendingPathComponent(file)))
            let now = try [UInt8](Data(contentsOf: dir.appendingPathComponent(file)))
            let runToRun = Self.maxAbsDiff(a, b), drift = Self.maxAbsDiff(now, a)
            if runToRun == 0 {
                #expect(drift == 0, "\(preset.descriptor.name): deterministic scene moved (max |Δ| \(drift))")
                if drift == 0 { identical += 1 }
            } else {
                #expect(drift <= runToRun,
                        "\(preset.descriptor.name): max |Δ| \(drift) exceeds run-to-run \(runToRun)")
                if drift <= runToRun { withinNoise += 1 }
            }
            print("[finish-oracle] \(preset.descriptor.name): run-to-run \(runToRun), after-change \(drift)")
        }
        print("[finish-oracle] byte-identical \(identical), within run-to-run noise \(withinNoise)")
    }

    // MARK: - Capture

    /// Frame 60 of `preset` at 1920×1080 under a fixed steady drive, and the path that drew it.
    static func capture(_ preset: PresetLoader.LoadedPreset) async throws -> ([UInt8], String) {
        let drive = (0..<frames).map { frame -> FeatureVector in
            FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: Float(frame) / 60, deltaTime: 1.0 / 60)
        }
        let stems = [StemFeatures](repeating: .zero, count: frames)
        let name = preset.descriptor.name
        let harness = MultiPassRenderHarness(width: width, height: height)
        if let frames = try? await harness.renderOffMain(preset: name, features: drive, stems: stems,
                                                         reduce: { $0 }), let last = frames.last {
            return (last, "MultiPassRenderHarness")
        }
        return (try singlePass(preset, features: drive.last ?? FeatureVector()), "single-pass fragment")
    }

    /// The present step on a tier-1 Mac: the render-size frame stretched into a 3840×2160 drawable
    /// by the production code, under the active scene's default upscale.
    @MainActor
    private static func presentStretch(_ bytes: [UInt8]) throws -> [UInt8] {
        let rig = try OraclePresentRig.shared()
        return try rig.stretch(bytes, width: width, height: height,
                               toWidth: drawableWidth, toHeight: drawableHeight)
    }

    /// The preset's own fragment pipeline, full screen, zeroed audio buffers (PresetRegressionTests).
    private static func singlePass(_ preset: PresetLoader.LoadedPreset, features: FeatureVector) throws -> [UInt8] {
        let ctx = try MetalContext()
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let target = ctx.device.makeTexture(descriptor: desc),
              let fft = ctx.makeSharedBuffer(length: 512 * 4),
              let wav = ctx.makeSharedBuffer(length: 2048 * 4),
              let slot = ctx.makeSharedBuffer(length: 64 * 1024),
              let cmd = ctx.commandQueue.makeCommandBuffer() else { throw OracleError.setup }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { throw OracleError.setup }
        var fv = features
        var stems = StemFeatures.zero
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        for index in 4...8 { enc.setFragmentBuffer(slot, offset: 0, index: index) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return bytes
    }

    // MARK: - Helpers

    private static func fileName(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "_")
    }

    private static func maxAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Int {
        guard a.count == b.count else { return 255 }
        var worst = 0
        for i in a.indices { worst = max(worst, abs(Int(a[i]) - Int(b[i]))) }
        return worst
    }

    enum OracleError: Error { case setup }
}

// MARK: - OraclePresentRig

/// A `RenderPipeline` used only for its present-step stretch (VQ.3 oracle).
@MainActor
final class OraclePresentRig {
    private static var instance: OraclePresentRig?
    static func shared() throws -> OraclePresentRig {
        if let instance { return instance }
        let made = try OraclePresentRig()
        instance = made
        return made
    }

    let context: MetalContext
    let pipeline: RenderPipeline

    private init() throws {
        let ctx = try MetalContext()
        context = ctx
        let library = try ShaderLibrary(context: ctx)
        guard let fft = ctx.makeSharedBuffer(length: 512 * 4),
              let wave = ctx.makeSharedBuffer(length: 2048 * 4) else { throw FinishLegacyOracleTests.OracleError.setup }
        pipeline = try RenderPipeline(context: ctx, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wave)
    }

    func stretch(_ bytes: [UInt8], width: Int, height: Int, toWidth: Int, toHeight: Int) throws -> [UInt8] {
        func make(_ w: Int, _ h: Int) throws -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: context.pixelFormat, width: w, height: h, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .shared
            guard let tex = context.device.makeTexture(descriptor: desc) else {
                throw FinishLegacyOracleTests.OracleError.setup
            }
            return tex
        }
        let source = try make(width, height), output = try make(toWidth, toHeight)
        source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: bytes,
                       bytesPerRow: width * 4)
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw FinishLegacyOracleTests.OracleError.setup }
        _ = pipeline.encodeLegacyPresent(source, into: output, commandBuffer: cmd)   // the default upscale
        cmd.commit()
        cmd.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: toWidth * toHeight * 4)
        output.getBytes(&out, bytesPerRow: toWidth * 4, from: MTLRegionMake2D(0, 0, toWidth, toHeight), mipmapLevel: 0)
        return out
    }
}
