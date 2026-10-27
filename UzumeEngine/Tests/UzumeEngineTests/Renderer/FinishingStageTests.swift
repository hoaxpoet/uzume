// FinishingStageTests — VQ.1's cinematic finish: the sidecar block, the display transform, and a
// test-only proof scene (a dark radial gradient, thin bright lines, a small hot spot) rendered at
// 1920×1080 and 3840×2160 to prove bloom is height-relative, dither removes banding and the glow
// survives 4K. Flash safety on the proof scene is FinishFlashTests; the format matrix over the
// roster is FinishFormatMatchTests.
//
//   FINISH_OUT=<dir>   write the legacy / cinematic still sheet (PNG) at 1080p and 4K.
//   FINISH_TIMING=1    GPU ms of the finish alone at 4K (quote only from a Release build).

import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Proof scene

/// The proof scene, drawn straight into an HDR frame target. Spatial sizes are in frame heights
/// and edges are analytically anti-aliased, so 1080p and 4K draw the same picture.
struct FinishProofScene {

    struct Params {
        var aspect: Float
        var hotSpot: Float        // hot-spot radiance (linear)
        var lines: Float          // line radiance (linear)
        var gradientOnly: UInt32  // 1 = just the dark gradient (banding measure)
    }

    /// Hot-spot centre and radius, frame-height units from the frame centre (+x right, +y down).
    static let hotSpotCentre = SIMD2<Float>(0.35, -0.15)
    static let hotSpotRadius: Float = 0.012

    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct ProofOut { float4 position [[position]]; float2 uv; };
    struct ProofParams { float aspect; float hotSpot; float lines; uint gradientOnly; };
    vertex ProofOut proof_vertex(uint vid [[vertex_id]]) {
        ProofOut o;
        o.uv = float2((vid << 1) & 2, vid & 2);
        o.position = float4(o.uv * 2.0 - 1.0, 0.0, 1.0);
        o.uv.y = 1.0 - o.uv.y;
        return o;
    }
    static float cover(float signedDistance, float pixel) {   // > 0 inside
        return saturate(signedDistance / pixel + 0.5);
    }
    fragment float4 proof_fragment(ProofOut in [[stage_in]], constant ProofParams& p [[buffer(0)]]) {
        float2 q = (in.uv - 0.5) * float2(p.aspect, 1.0);         // frame heights, centred
        float pixel = abs(dfdy(q.y));
        float r = length(q);
        float3 c = float3(0.004 + 0.05 * saturate(1.0 - r / 0.95));   // dark radial gradient
        if (p.gradientOnly == 0) {
            for (int i = 0; i < 3; i++) {                              // thin bright lines
                float y = 0.15 + 0.05 * float(i);
                float d = 0.0015 - abs(q.y - y);
                float span = cover(0.6 - abs(q.x + 0.2), pixel);
                c += p.lines * cover(d, pixel) * span;
            }
            float d = 0.012 - length(q - float2(0.35, -0.15));        // hot spot
            c += p.hotSpot * cover(d, pixel);
        }
        return float4(c, 1.0);
    }
    """

    let pipeline: MTLRenderPipelineState

    init(device: MTLDevice) throws {
        let library = try device.makeLibrary(source: Self.source, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "proof_vertex")
        desc.fragmentFunction = library.makeFunction(name: "proof_fragment")
        desc.colorAttachments[0].pixelFormat = FinishSpec.cinematicFrameTargetFormat
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    func encode(into target: MTLTexture, params: Params, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var params = params
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<Params>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}

// MARK: - Rig

/// Proof scene → finishing stage → readback, at one output size.
final class FinishProofRig {
    let context: MetalContext
    let library: MTLLibrary
    let scene: FinishProofScene
    let width: Int
    let height: Int

    init(width: Int, height: Int) throws {
        context = try MetalContext()
        library = try ShaderLibrary(context: context).library
        scene = try FinishProofScene(device: context.device)
        self.width = width
        self.height = height
    }

    func stage(output: MTLPixelFormat, spec: FinishSpec = FinishSpec(mode: .cinematic), dither: Bool,
               lut: MTLTexture? = nil) throws -> FinishingStage {
        let stage = try FinishingStage(device: context.device, library: library, outputFormat: output,
                                       spec: spec, lut: lut, budget: nil)
        stage.ditherLSB = dither ? 1.0 / 255.0 : 0
        return stage
    }

    func params(hotSpot: Float = 40, lines: Float = 3, gradientOnly: Bool = false) -> FinishProofScene.Params {
        FinishProofScene.Params(aspect: Float(width) / Float(height), hotSpot: hotSpot, lines: lines,
                                gradientOnly: gradientOnly ? 1 : 0)
    }

    /// One finished frame read back as Float RGBA (rgba32Float output) — linear display values.
    func linear(stage: FinishingStage, params: FinishProofScene.Params) throws -> [Float] {
        let out = try texture(.rgba32Float)
        try run(stage: stage, params: params, output: out)
        var px = [Float](repeating: 0, count: width * height * 4)
        out.getBytes(&px, bytesPerRow: width * 16, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return px
    }

    /// One finished frame read back as 8-bit BGRA (the drawable format) — encoded values.
    func encoded(stage: FinishingStage, params: FinishProofScene.Params) throws -> [UInt8] {
        let out = try texture(.bgra8Unorm_srgb)
        try run(stage: stage, params: params, output: out)
        var px = [UInt8](repeating: 0, count: width * height * 4)
        out.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return px
    }

    /// The proof scene drawn straight into an 8-bit target — what `legacy` shows (no finish).
    func legacy(params: FinishProofScene.Params) throws -> [UInt8] {
        let hdr = try texture(.rgba16Float)
        let out = try texture(.bgra8Unorm_srgb)
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw RigError.gpu }
        scene.encode(into: hdr, params: params, commandBuffer: cmd)
        let blitDesc = MTLRenderPipelineDescriptor()
        blitDesc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        blitDesc.fragmentFunction = library.makeFunction(name: "feedback_blit_fragment")
        blitDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        let blit = try context.device.makeRenderPipelineState(descriptor: blitDesc)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = out
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { throw RigError.gpu }
        enc.setRenderPipelineState(blit)
        enc.setFragmentTexture(hdr, index: 0)
        enc.setFragmentSamplerState(try sampler(), index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: width * height * 4)
        out.getBytes(&px, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return px
    }

    /// Render + finish in one command buffer; returns its GPU ms.
    @discardableResult
    func run(stage: FinishingStage, params: FinishProofScene.Params, output: MTLTexture,
             finishOnly: Bool = false) throws -> Double {
        guard let target = stage.ensureFrameTarget(width: width, height: height) else { throw RigError.gpu }
        if finishOnly {
            guard let cmd = context.commandQueue.makeCommandBuffer() else { throw RigError.gpu }
            scene.encode(into: target, params: params, commandBuffer: cmd)
            cmd.commit()
            cmd.waitUntilCompleted()
        }
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw RigError.gpu }
        if !finishOnly { scene.encode(into: target, params: params, commandBuffer: cmd) }
        stage.encode(source: target, output: output, commandBuffer: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw RigError.gpu }
        return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000
    }

    func texture(_ format: MTLPixelFormat) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = context.device.makeTexture(descriptor: desc) else { throw RigError.gpu }
        return tex
    }

    private func sampler() throws -> MTLSamplerState {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        guard let s = context.device.makeSamplerState(descriptor: desc) else { throw RigError.gpu }
        return s
    }

    enum RigError: Error { case gpu }
}

// MARK: - Flash measure

/// The proof scene under the worst-case beat train (FlashHarnessSupport), hot spot and lines driven
/// by the beat and bass deviation, rendered legacy (no finish) and cinematic at the flash
/// harness's 320×180. Both flash suites assert on the cinematic run (VQ.1 task 5).
enum FinishProofFlash {

    struct Result {
        let legacy: [FlashHarnessSupport.FlashSample]
        let cinematic: [FlashHarnessSupport.FlashSample]

        /// Largest frame-to-frame change of mean relative luminance.
        static func maxDelta(_ samples: [FlashHarnessSupport.FlashSample]) -> Double {
            zip(samples.dropFirst(), samples).map { abs($0.luma - $1.luma) }.max() ?? 0
        }
    }

    static func measure() throws -> Result {
        let rig = try FinishProofRig(width: 320, height: 180)
        let stage = try rig.stage(output: .bgra8Unorm_srgb, dither: true)
        var legacy: [FlashHarnessSupport.FlashSample] = [], cinematic: [FlashHarnessSupport.FlashSample] = []
        for features in FlashHarnessSupport.worstCaseBeatTrain() {
            let params = rig.params(hotSpot: 40 * (0.1 + features.beatBass),
                                    lines: 3 * (0.2 + max(0, features.bassDev)))
            legacy.append(FlashHarnessSupport.sample(try rig.legacy(params: params), width: 320, height: 180))
            cinematic.append(FlashHarnessSupport.sample(try rig.encoded(stage: stage, params: params),
                                                        width: 320, height: 180))
        }
        let result = Result(legacy: legacy, cinematic: cinematic)
        print(String(format: "[finish-flash] proof scene max Δ frame-mean luma: legacy %.4f, cinematic %.4f",
                     Result.maxDelta(legacy), Result.maxDelta(cinematic)))
        return result
    }
}

// MARK: - Suite

@Suite("Finishing stage (VQ.1)")
struct FinishingStageTests {

    // MARK: Sidecar block

    @Test("Sidecar `finish`: absent = legacy; full and partial blocks decode; unknown mode rejected")
    func sidecarBlock() throws {
        func decode(_ json: String) throws -> FinishSpec {
            try JSONDecoder().decode(FinishSpec.self, from: Data(json.utf8))
        }
        let base = #"{"name":"T","family":"geometric","passes":["direct"]}"#
        let absent = try JSONDecoder().decode(PresetDescriptor.self, from: Data(base.utf8))
        #expect(absent.finish == .legacy)
        #expect(absent.finish.frameTargetFormat == .bgra8Unorm_srgb)

        let full = try decode("""
            {"mode":"cinematic","bloom":{"strength":0.7,"threshold":1.5,"knee":0.25},
             "grade":{"exposure":-0.5,"contrast":1.1,"saturation":0.9},"lut":"warm.cube"}
            """)
        #expect(full.mode == .cinematic)
        #expect(full.bloom == FinishSpec.Bloom(strength: 0.7, threshold: 1.5, knee: 0.25))
        #expect(full.grade == FinishSpec.Grade(exposure: -0.5, contrast: 1.1, saturation: 0.9))
        #expect(full.lut == "warm.cube")
        #expect(full.frameTargetFormat == .rgba16Float)

        let partial = try decode(#"{"mode":"cinematic","bloom":{"strength":0.2}}"#)
        #expect(partial.bloom.strength == 0.2)
        #expect(partial.bloom.threshold == FinishSpec.Bloom().threshold)
        #expect(partial.grade == FinishSpec.Grade())

        #expect(throws: DecodingError.self) { try decode(#"{"mode":"filmic"}"#) }

        let inSidecar = try JSONDecoder().decode(PresetDescriptor.self, from: Data("""
            {"name":"T","family":"geometric","passes":["direct"],"finish":{"mode":"cinematic"}}
            """.utf8))
        #expect(inSidecar.finish.mode == .cinematic)
    }

    @Test("No shipped scene opts into the cinematic finish (VQ.1c does Ferrofluid Ocean)")
    func noShippedSceneIsCinematic() {
        let cinematic = _acceptanceFixture.presets.filter { $0.descriptor.finish.mode != .legacy }
        #expect(cinematic.isEmpty, "\(cinematic.map(\.descriptor.name))")
    }

    // MARK: Display transform

    @Test("Lottes display transform: mid-grey anchored, peak = headroom, monotonic")
    func displayTransform() {
        for headroom: Float in [1, 2, 4] {
            #expect(abs(FinishingStage.displayTransform(0.18, headroom: headroom) - 0.267) < 1e-3)
            #expect(abs(FinishingStage.displayTransform(8, headroom: headroom) - headroom) < 1e-3 * headroom)
            var previous: Float = -1
            for step in 0...200 {
                let y = FinishingStage.displayTransform(Float(step) * 0.05, headroom: headroom)
                #expect(y >= previous)
                previous = y
            }
        }
    }

    // MARK: Proof scene

    @Test("Bloom radius is the same fraction of frame height at 1080p and 4K (±5 %); glow present at 4K")
    func bloomIsHeightRelative() throws {
        var radii: [Int: Float] = [:]
        for (width, height) in [(1920, 1080), (3840, 2160)] {
            let rig = try FinishProofRig(width: width, height: height)
            let bloom = try rig.linear(stage: try rig.stage(output: .rgba32Float, dither: false), params: rig.params())
            var off = FinishSpec(mode: .cinematic)
            off.bloom.strength = 0
            let plain = try rig.linear(stage: try rig.stage(output: .rgba32Float, spec: off, dither: false),
                                       params: rig.params())
            let profile = Self.glowProfile(bloom: bloom, plain: plain, width: width, height: height)
            let r = Self.radius(profile, falloff: 0.25)
            radii[height] = r
            print(String(format: "[finish-proof] %d×%d: glow at edge+0.005H %.4f, edge+0.05H %.4f, r25 %.4f H",
                         width, height, profile.first { $0.distance >= 0.005 }?.glow ?? 0,
                         profile.first { $0.distance >= 0.05 }?.glow ?? 0, r))
            if height == 2160 {
                let far = profile.first { $0.distance >= 0.02 }?.glow ?? 0
                #expect(far > 0.005, "4K: the hot spot's glow is present 0.02 H past its edge (\(far))")
            }
        }
        let hd = try #require(radii[1080]), uhd = try #require(radii[2160])
        print(String(format: "[finish-proof] bloom radius (25 %% falloff): 1080p %.4f H, 4K %.4f H, ratio %.3f",
                     hd, uhd, uhd / hd))
        #expect(hd > 0.01, "bloom is visible at all")
        #expect(abs(uhd / hd - 1) <= 0.05)
    }

    @Test("Dither: 16×16-block means within 0.25 LSB of the ideal gradient; undithered is not")
    func ditherRemovesBanding() throws {
        for (width, height) in [(1920, 1080), (3840, 2160)] {
            let rig = try FinishProofRig(width: width, height: height)
            let params = rig.params(gradientOnly: true)
            var spec = FinishSpec(mode: .cinematic)
            spec.bloom.strength = 0
            let ideal = try rig.linear(stage: try rig.stage(output: .rgba32Float, spec: spec, dither: false),
                                       params: params)
            let idealCodes = stride(from: 1, to: ideal.count, by: 4).map { Self.encode(Double(ideal[$0])) * 255 }
            let dithered = try rig.encoded(stage: try rig.stage(output: .bgra8Unorm_srgb, spec: spec, dither: true),
                                           params: params)
            let plain = try rig.encoded(stage: try rig.stage(output: .bgra8Unorm_srgb, spec: spec, dither: false),
                                        params: params)
            let withDither = Self.worstBlockError(dithered, ideal: idealCodes, width: width, height: height)
            let without = Self.worstBlockError(plain, ideal: idealCodes, width: width, height: height)
            let range = (idealCodes.min() ?? 0, idealCodes.max() ?? 0)
            print(String(format: "[finish-proof] %d×%d gradient %.1f–%.1f LSB: worst 16×16 block |Δ| "
                         + "dithered %.3f LSB, undithered %.3f LSB", width, height, range.0, range.1,
                         withDither, without))
            #expect(withDither <= 0.25)
            #expect(without > 0.25, "the undithered render bands (the measure can see banding)")
        }
    }

    @Test("Identity 3D LUT leaves the image unchanged (≤ 1 LSB)")
    func identityLUT() throws {
        let rig = try FinishProofRig(width: 320, height: 180)
        let n = 17
        var lines = ["LUT_3D_SIZE \(n)"]
        for b in 0..<n { for g in 0..<n { for r in 0..<n {
            lines.append("\(Float(r) / Float(n - 1)) \(Float(g) / Float(n - 1)) \(Float(b) / Float(n - 1))")
        } } }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vq1-identity-\(UUID()).cube")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let lut = try FinishSpec.loadCubeLUT(url: url, device: rig.context.device)
        let with = try rig.encoded(stage: try rig.stage(output: .bgra8Unorm_srgb, dither: false, lut: lut),
                                   params: rig.params())
        let without = try rig.encoded(stage: try rig.stage(output: .bgra8Unorm_srgb, dither: false),
                                      params: rig.params())
        let worst = zip(with, without).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1)
    }

    // MARK: Still sheet

    @Test("Still sheet: legacy / cinematic at 1080p and 4K (FINISH_OUT)")
    func stillSheet() throws {
        guard let out = ProcessInfo.processInfo.environment["FINISH_OUT"] else { return }
        let dir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (width, height) in [(1920, 1080), (3840, 2160)] {
            let rig = try FinishProofRig(width: width, height: height)
            try Self.writePNG(try rig.legacy(params: rig.params()), width: width, height: height,
                              to: dir.appendingPathComponent("proof_legacy_\(height)p.png"))
            let finished = try rig.encoded(stage: try rig.stage(output: .bgra8Unorm_srgb, dither: true),
                                           params: rig.params())
            try Self.writePNG(finished, width: width, height: height,
                              to: dir.appendingPathComponent("proof_cinematic_\(height)p.png"))
        }
        print("[finish-proof] still sheet → \(dir.path)")
    }

    // MARK: Cost

    @Test("GPU ms of the finish alone at 3840×2160, and its budget bytes (FINISH_TIMING=1)")
    func timing() throws {
        guard ProcessInfo.processInfo.environment["FINISH_TIMING"] == "1" else { return }
        #if DEBUG
        print("[finish-timing] WARNING: Debug build — numbers are not quotable (CLAUDE.md)")
        #endif
        print("[finish-timing] storage: \(RenderTargetBudget.storageMode() == .private ? "private (production)" : "shared")")
        var noBloom = FinishSpec(mode: .cinematic)
        noBloom.bloom.strength = 0
        for (width, height, label, spec) in [(3840, 2160, "4K native", FinishSpec(mode: .cinematic)),
                                             (3840, 2160, "4K native, composite only", noBloom),
                                             (2560, 1440, "1440p canvas → 4K drawable", FinishSpec(mode: .cinematic))] {
            let rig = try FinishProofRig(width: width, height: height)
            let stage = try rig.stage(output: .bgra8Unorm_srgb, spec: spec, dither: true)
            // Production storage: the drawable and the budget's targets are `.private` (compressed);
            // run with UZUME_PRIVATE_TARGETS=1 so the frame target and chain are too.
            let outDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: 3840,
                                                                   height: 2160, mipmapped: false)
            outDesc.usage = [.renderTarget, .shaderRead]
            outDesc.storageMode = .private
            let out = try #require(rig.context.device.makeTexture(descriptor: outDesc))
            // Back to back, no wait between frames: a GPU that idles between frames clocks down and
            // the per-frame time swings with it (0.81 vs 1.40 ms for the same pass, measured). With
            // many buffers queued, gpuEnd − gpuStart includes the queue, so read the completion spacing.
            guard let target = stage.ensureFrameTarget(width: width, height: height),
                  let cmd = rig.context.commandQueue.makeCommandBuffer() else { throw FinishProofRig.RigError.gpu }
            rig.scene.encode(into: target, params: rig.params(), commandBuffer: cmd)
            cmd.commit()
            let log = GPUTimeLog()
            var last: MTLCommandBuffer?
            for _ in 0..<400 {
                guard let frame = rig.context.commandQueue.makeCommandBuffer() else { continue }
                stage.encode(source: target, output: out, commandBuffer: frame)
                frame.addCompletedHandler { log.append($0.gpuEndTime * 1000) }
                frame.commit()
                last = frame
            }
            last?.waitUntilCompleted()
            // Saturated GPU: the spacing of consecutive completions is the per-frame cost.
            let ends = log.ms.sorted()
            var ms = zip(ends.dropFirst(), ends).map { $0 - $1 }.dropFirst(50).map { $0 }
            ms.sort()
            print(String(format: "[finish-timing] %@ (%d×%d → 3840×2160), device %@: p50 %.3f ms, p95 %.3f ms",
                         label, width, height, rig.context.device.name, ms[ms.count / 2],
                         ms[Int(Double(ms.count) * 0.95)]))
            let budget = RenderTargetBudget(device: rig.context.device)
            let bytes = ([stage.frameTarget].compactMap { $0 } + stage.bloomChain)
                .map { budget.estimatedBytes(Self.descriptor(of: $0)) }.reduce(0, +)
            print(String(format: "[finish-timing] %@ budget: frame target + bloom chain = %.1f MiB "
                         + "(chain alone %.1f MiB)", label, Double(bytes) / 1_048_576,
                         Double(stage.bloomChain.map { budget.estimatedBytes(Self.descriptor(of: $0)) }
                            .reduce(0, +)) / 1_048_576))
        }
    }

    @Test("4K frame GPU ms: a heavy certified scene legacy vs forced cinematic (FINISH_TIMING=1)")
    func heavySceneTiming() async throws {
        guard ProcessInfo.processInfo.environment["FINISH_TIMING"] == "1" else { return }
        let drive = (0..<130).map { FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: Float($0) / 60,
                                                  deltaTime: 1.0 / 60) }
        let stems = [StemFeatures](repeating: .zero, count: drive.count)
        for name in ["Ferrofluid Ocean", "Nebula"] {
            for mode in [FinishSpec.Mode.legacy, .cinematic] {
                var harness = MultiPassRenderHarness(width: 3840, height: 2160, readback: false, finishMode: mode)
                let log = GPUTimeLog()
                harness.gpuTimes = log
                _ = try await harness.renderOffMain(preset: name, features: drive, stems: stems) { _ in 0 }
                let ms = log.ms.dropFirst(10).sorted()
                guard !ms.isEmpty else { continue }
                print(String(format: "[finish-timing] %@ 3840×2160 %@: frame p50 %.2f ms, p95 %.2f ms (n=%d)",
                             name, "\(mode)", ms[ms.count / 2], ms[Int(Double(ms.count) * 0.95)], ms.count))
            }
        }
    }

    // MARK: - Helpers

    struct GlowSample { let distance: Float; let glow: Float }

    /// Bloom-minus-plain luminance along the row through the hot spot, rightwards from its edge,
    /// distance in frame heights.
    static func glowProfile(bloom: [Float], plain: [Float], width: Int, height: Int) -> [GlowSample] {
        let h = Float(height)
        let cx = Float(width) / 2 + FinishProofScene.hotSpotCentre.x * h
        let cy = Float(height) / 2 + FinishProofScene.hotSpotCentre.y * h
        let row = Int(cy)
        var samples: [GlowSample] = []
        for x in Int(cx)..<width {
            let distance = (Float(x) + 0.5 - cx) / h - FinishProofScene.hotSpotRadius
            guard distance > 0.002 else { continue }
            let i = (row * width + x) * 4
            func luma(_ p: [Float]) -> Float { 0.2126 * p[i] + 0.7152 * p[i + 1] + 0.0722 * p[i + 2] }
            samples.append(GlowSample(distance: distance, glow: luma(bloom) - luma(plain)))
        }
        return samples
    }

    /// Distance where the glow first falls to `falloff` × its value just outside the spot.
    static func radius(_ profile: [GlowSample], falloff: Float) -> Float {
        guard let start = profile.first(where: { $0.distance >= 0.005 }) else { return 0 }
        return profile.first { $0.distance > start.distance && $0.glow < start.glow * falloff }?.distance ?? 1
    }

    static func encode(_ linear: Double) -> Double {
        let c = max(0, min(1, linear))
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// Worst |mean(test) − mean(ideal)| over 16×16 blocks, green channel, in code values.
    static func worstBlockError(_ bgra: [UInt8], ideal: [Double], width: Int, height: Int) -> Double {
        var worst = 0.0
        for by in stride(from: 0, to: height - 15, by: 16) {
            for bx in stride(from: 0, to: width - 15, by: 16) {
                var test = 0.0, want = 0.0
                for y in by..<(by + 16) {
                    for x in bx..<(bx + 16) {
                        test += Double(bgra[(y * width + x) * 4 + 1])
                        want += ideal[y * width + x]
                    }
                }
                worst = max(worst, abs(test - want) / 256)
            }
        }
        return worst
    }

    static func descriptor(of texture: MTLTexture) -> MTLTextureDescriptor {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: texture.width,
                                                            height: texture.height, mipmapped: false)
        desc.usage = texture.usage
        desc.storageMode = .private
        return desc
    }

    static func writePNG(_ bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        var bytes = bgra
        let image = try bytes.withUnsafeMutableBytes { raw -> CGImage in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,  // swiftlint:disable:this force_unwrapping
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue),
                  let image = ctx.makeImage() else { throw FinishProofRig.RigError.gpu }
            return image
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw FinishProofRig.RigError.gpu }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
