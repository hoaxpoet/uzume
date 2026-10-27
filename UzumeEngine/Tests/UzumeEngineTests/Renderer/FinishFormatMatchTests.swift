// FinishFormatMatchTests — VQ.1 task 3 (the BUG-061 class) and task 1's seam gate.
//
// A scene's finish mode decides its frame-target format (legacy `.bgra8Unorm_srgb`, cinematic
// `.rgba16Float`), and every pipeline that draws the frame target compiles against it, resolved in
// one place (`FinishSpec.frameTargetFormat`). This suite loads every certified scene in BOTH modes
// and renders it through its real path into a frame target of that mode's format. A pipeline
// compiled for the other format is an attachment-format mismatch: Metal API validation aborts on
// it, and without validation the command buffer fails. Run it under validation for the full proof:
//
//   MTL_DEBUG_LAYER=1 swift test --package-path UzumeEngine --filter FinishFormatMatch

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

/// Every built-in preset loaded with its finish forced to `cinematic` (test only).
let _cinematicFixture: PresetFixtureContext = {
    guard let ctx = try? MetalContext() else { return PresetFixtureContext(presets: []) }
    let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true,
                              finishOverride: .cinematic)
    return PresetFixtureContext(presets: loader.presets)
}()

/// Every built-in preset loaded with its finish forced to `legacy` (test only) — the roster as
/// shipped (`_acceptanceFixture`) has adopters on cinematic since VQ.1c.
let _legacyFixture: PresetFixtureContext = {
    guard let ctx = try? MetalContext() else { return PresetFixtureContext(presets: []) }
    let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true,
                              finishOverride: .legacy)
    return PresetFixtureContext(presets: loader.presets)
}()

@Suite("Finish format match (VQ.1)")
struct FinishFormatMatchTests {

    static let certifiedNames = _acceptanceFixture.presets.filter(\.descriptor.certified).map(\.descriptor.name)

    @Test("Every certified scene loads in both finish modes with the mode's frame-target format")
    func everySceneLoadsInBothModes() {
        #expect(Self.certifiedNames.count >= 25, "the roster is present (\(Self.certifiedNames.count))")
        for (mode, fixture) in [(FinishSpec.Mode.legacy, _legacyFixture), (.cinematic, _cinematicFixture)] {
            for name in Self.certifiedNames {
                let preset = fixture.presets.first { $0.descriptor.name == name }
                #expect(preset != nil, "\(name) failed to load in \(mode) mode")
                #expect(preset?.descriptor.finish.mode == mode)
                #expect(preset?.descriptor.finish.frameTargetFormat == FinishSpec(mode: mode).frameTargetFormat)
            }
        }
    }

    @Test("Every certified scene renders its real path into its mode's frame target (no format mismatch)",
          arguments: [FinishSpec.Mode.legacy, .cinematic])
    func everySceneRendersInMode(_ mode: FinishSpec.Mode) async throws {
        let fixture = mode == .cinematic ? _cinematicFixture : _legacyFixture
        let harness = MultiPassRenderHarness(width: 160, height: 90, finishMode: mode)
        let drive = FlashHarnessSupport.worstCaseBeatTrain().prefix(3).map { $0 }
        let stems = [StemFeatures](repeating: .zero, count: drive.count)
        for name in Self.certifiedNames {
            let path: String
            if MultiPassRenderHarness.renders(name) {
                let frames = try await harness.renderOffMain(preset: name, features: drive, stems: stems) { $0.count }
                #expect(frames.count == drive.count, "\(name) [\(mode)]")
                path = "harness"
            } else {
                let preset = try #require(fixture.presets.first { $0.descriptor.name == name })
                try Self.renderSinglePass(preset, format: preset.descriptor.finish.frameTargetFormat)
                path = "single-pass"
            }
            print("[finish-format] \(name) [\(mode)] via \(path): OK")
        }
    }

    /// The fragment pipeline into a target of `format` — for the scenes the harness does not carry.
    private static func renderSinglePass(_ preset: PresetLoader.LoadedPreset, format: MTLPixelFormat) throws {
        let ctx = try MetalContext()
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 160, height: 90,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        guard let target = ctx.device.makeTexture(descriptor: desc),
              let slot = ctx.makeSharedBuffer(length: 64 * 1024),
              let cmd = ctx.commandQueue.makeCommandBuffer() else { throw FormatError.setup }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { throw FormatError.setup }
        var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 1, deltaTime: 1.0 / 60)
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
        for index in 1...8 { enc.setFragmentBuffer(slot, offset: 0, index: index) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        #expect(cmd.status == .completed, "\(preset.descriptor.name): \(String(describing: cmd.error))")
    }

    // MARK: - Seam gate (task 1)

    /// Every render path obtains its target from the seam (`RenderPipeline+FrameSeam.swift`):
    /// no other Renderer file touches the drawable, its texture, MTKView's descriptor, or presents.
    @Test("Only the frame seam touches the drawable or presents")
    func onlyTheSeamTouchesTheDrawable() throws {
        let renderer = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Renderer")
        let files = try #require(FileManager.default.enumerator(at: renderer, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(files.count > 20)
        let banned = ["drawable.texture", ".currentDrawable", ".currentRenderPassDescriptor", ".present("]
        for file in files where file.lastPathComponent != "RenderPipeline+FrameSeam.swift" {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            for token in banned {
                #expect(!code.contains(token), "\(file.lastPathComponent) uses `\(token)` outside the frame seam")
            }
        }
    }

    enum FormatError: Error { case setup }
}
