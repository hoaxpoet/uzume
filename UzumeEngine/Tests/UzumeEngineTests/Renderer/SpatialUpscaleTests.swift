// SpatialUpscaleTests — VQ.3 task 2: MetalFX spatial upscaling as an option at every stretch.
//
//   • sidecar `upscale` + the roster default (absent = today's bilinear stretch; no shipped scene opts in);
//   • the present step: bilinear hands the frame target through untouched (no scaler is built);
//     spatial writes a drawable-sized budgeted output; switching away releases the scaler's reservation;
//   • proof (UPSCALE_PROOF=1): the flat proof scene at 3840×2160 from 2560×1440 and 1920×1080 —
//     bilinear stretch vs MetalFX spatial vs native (1 sample a pixel), against a 16-sample
//     reference — gradient energy, ringing beside a hard edge, stair-stepping, and shimmer on a
//     slow pan.

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Sidecar + roster default

@Suite("SpatialUpscale sidecar (VQ.3)")
struct SpatialUpscaleSidecarTests {

    private static func decode(_ value: String?) throws -> PresetDescriptor {
        let field = value.map { ",\"upscale\":\($0)" } ?? ""
        let json = "{\"name\":\"T\",\"family\":\"geometric\",\"passes\":[\"direct\"]\(field)}"
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    @Test func absent_isTheRosterDefault_whichIsTheStretch() throws {
        let desc = try Self.decode(nil)
        #expect(desc.upscale == nil)
        #expect(UpscaleMode.rosterDefault == .bilinear, "VQ.3 flips nothing: a consumer increment moves the roster")
        #expect(UpscaleMode.resolve(desc.upscale) == .bilinear)
    }

    @Test func declared_decodes() throws {
        #expect(try Self.decode("\"spatial\"").upscale == .spatial)
        #expect(try Self.decode("\"bilinear\"").upscale == .bilinear)
        #expect(UpscaleMode.resolve(.spatial) == .spatial)
        #expect(throws: (any Error).self) { try Self.decode("\"fsr\"") }
    }

    @Test @MainActor func noShippedSceneDeclaresIt() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let declared = loader.presets.filter { $0.descriptor.upscale != nil }.map(\.descriptor.name)
        #expect(declared.isEmpty, "upscale declared by \(declared) — VQ.3 opts no shipped scene in")
    }
}

// MARK: - Present step

@Suite("SpatialUpscale present step (VQ.3)")
@MainActor
struct SpatialUpscalePresentTests {

    @Test("Bilinear: the frame target is stretched exactly as before and no scaler is built")
    func bilinear_isTheOldCopy() throws {
        let rig = try OraclePresentRig.shared()
        let blit = try VQ3Blit(context: rig.context)
        let canvas = try blit.texture(rig.context.pixelFormat, 256, 144)
        let output = try blit.texture(rig.context.pixelFormat, 384, 216)
        rig.pipeline.setUpscale(.bilinear)
        let cb = try #require(rig.context.commandQueue.makeCommandBuffer())
        let image = rig.pipeline.encodeLegacyPresent(canvas, into: output, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        #expect(image === canvas, "bilinear copies the frame target itself")
        #expect(rig.pipeline.spatialUpscaler == nil)
    }

    @Test("Spatial: a drawable-sized budgeted output; switching to bilinear releases it")
    func spatial_outputAndRelease() throws {
        let rig = try OraclePresentRig.shared()
        guard SpatialUpscaler.isSupported(device: rig.context.device) else { return }
        let blit = try VQ3Blit(context: rig.context)
        let proof = try FlatProof(blit: blit)
        let canvas = try blit.texture(rig.context.pixelFormat, 1280, 720)
        let output = try blit.texture(rig.context.pixelFormat, 1920, 1080)
        let budget = rig.context.renderTargetBudget
        rig.pipeline.setUpscale(.spatial)
        let cb = try #require(rig.context.commandQueue.makeCommandBuffer())
        proof.render(into: canvas, samples: 1, offset: 0, commandBuffer: cb)
        let image = rig.pipeline.encodeLegacyPresent(canvas, into: output, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        #expect(image !== canvas)
        #expect(image.width == 1920 && image.height == 1080)
        #expect(image.pixelFormat == canvas.pixelFormat, "MetalFX keeps the sRGB encoding")
        let luma = try blit.luma(output)
        let range = (luma.max() ?? 0) - (luma.min() ?? 0)
        #expect(range > 0.5, "non-degenerate (luma range \(range))")
        let reserved = budget.reservedBytes.filter { $0.key.hasPrefix("mfx spatial") }
        #expect(!reserved.isEmpty, "the scaler is charged to the budget")
        #expect(budget.liveAllocations.contains { $0.owner == "spatialUpscale" })
        print("[vq3-spatial] scaler reservation \(reserved.values.reduce(0, +) / 1_048_576) MiB at 1920×1080")

        rig.pipeline.setUpscale(.bilinear)   // the next scene stretches
        #expect(rig.pipeline.spatialUpscaler == nil)
        #expect(budget.reservedBytes.keys.allSatisfy { !$0.hasPrefix("mfx spatial") },
                "no MetalFX reservation outlives its scene")
    }
}

// MARK: - Proof (UPSCALE_PROOF=1)

@Suite("SpatialUpscale proof (VQ.3)", .serialized)
@MainActor
struct SpatialUpscaleProofTests {

    static var enabled: Bool { ProcessInfo.processInfo.environment["UPSCALE_PROOF"] == "1" }
    static let outW = 3840, outH = 2160
    /// The pan: ⅓ output pixel a frame (20 px/s at 60 fps) — sub-pixel motion is where shimmer shows.
    static let panPixelsPerFrame: Float = 1.0 / 3.0
    static let panFrames = 24

    @Test("Flat proof at 4K: stretch vs spatial vs native against a 16-sample reference (UPSCALE_PROOF=1)")
    func flatProof() throws {
        guard Self.enabled else { return }
        let rig = try OraclePresentRig.shared()
        let ctx = rig.context
        let blit = try VQ3Blit(context: ctx)
        let proof = try FlatProof(blit: blit)
        let format = ctx.pixelFormat
        let reference = try blit.texture(format, Self.outW, Self.outH)
        let native = try blit.texture(format, Self.outW, Self.outH)
        let output = try blit.texture(format, Self.outW, Self.outH)

        var canvases: [Int: MTLTexture] = [:]
        /// One frame of `method` at pan `offset` (scene units), as display luma.
        func frame(_ method: String, input: (Int, Int), offset: Float) throws -> [Float] {
            let cb = try #require(ctx.commandQueue.makeCommandBuffer())
            switch method {
            case "reference": proof.render(into: reference, samples: 4, offset: offset, commandBuffer: cb)
            case "native": proof.render(into: native, samples: 1, offset: offset, commandBuffer: cb)
            default:
                if canvases[input.0] == nil { canvases[input.0] = try blit.texture(format, input.0, input.1) }
                let canvas = try #require(canvases[input.0])
                proof.render(into: canvas, samples: 1, offset: offset, commandBuffer: cb)
                rig.pipeline.setUpscale(method == "spatial" ? .spatial : .bilinear)
                _ = rig.pipeline.encodeLegacyPresent(canvas, into: output, commandBuffer: cb)
            }
            cb.commit()
            cb.waitUntilCompleted()
            return try blit.luma(method == "reference" ? reference : (method == "native" ? native : output))
        }

        let step = Self.panPixelsPerFrame / Float(Self.outH)
        let refStill = try frame("reference", input: (0, 0), offset: 0)
        let refPan = try (0..<Self.panFrames).map { try frame("reference", input: (0, 0), offset: Float($0) * step) }
        let edges = FlatProof.edgeColumns(width: Self.outW, height: Self.outH, offset: 0)
        let gRef = UpscaleMetrics.gradientEnergy(refStill, width: Self.outW)
        print("[vq3-flat] reference: 16 samples/px; ringing \(String(format: "%.4f", UpscaleMetrics.overshoot(refStill, width: Self.outW, edges: edges)))")

        let runs = [("native", (0, 0))] + [(2560, 1440), (1920, 1080)].flatMap { [("stretch", $0), ("spatial", $0)] }
        for (method, input) in runs {
            do {
                let still = try frame(method, input: input, offset: 0)
                let pan = try (0..<Self.panFrames).map { try frame(method, input: input, offset: Float($0) * step) }
                let label = method == "native" ? "native 3840×2160" : "\(method) from \(input.0)×\(input.1)"
                print(String(
                    format: "[vq3-flat] %@: grad %.3f (ref 1.0) | ringing %.4f | stair RMS %.3f px | |Δ| vs ref %.4f"
                        + " | pan shimmer %.4f, raw |Δ| %.4f (ref %.4f)",
                    label,
                    UpscaleMetrics.gradientEnergy(still, width: Self.outW) / gRef,
                    UpscaleMetrics.overshoot(still, width: Self.outW, edges: edges),
                    UpscaleMetrics.edgeStepRMS(still, refStill, width: Self.outW, edges: edges),
                    UpscaleMetrics.meanAbs(still, refStill),
                    UpscaleMetrics.shimmer(pan, reference: refPan),
                    UpscaleMetrics.frameDelta(pan), UpscaleMetrics.frameDelta(refPan)))
            }
        }
        rig.pipeline.setUpscale(.bilinear)
    }
}
