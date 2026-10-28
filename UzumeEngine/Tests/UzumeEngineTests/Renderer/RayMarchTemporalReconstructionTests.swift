// RayMarchTemporalReconstructionTests — VQ.3 tasks 3–5 and 7: MetalFX temporal reconstruction on the
// ray-march G-buffer path, the scale-1.0 anti-aliasing-only mode, memory, and cost.
//
// Always on (CI): the sidecar rules; zero jitter leaves the march byte-identical; the motion pass
// (still camera → no motion, dolly → the right sign, static geometry is not reactive); the jitter
// sign MetalFX needs; the budget at 4K and the scene-switch release; the floor refusal.
// UPSCALE_PROOF=1: the ray-march proof scene, Lumen Mosaic (still camera) and Volumetric Lithograph
// (forward dolly) at 4K against their own 2×2-supersampled reference, plus the AA-only stair-step
// measure and the still sheet (native / stretch / spatial / temporal). UPSCALE_TIMING=1: GPU cost
// (quote Release only — CLAUDE.md).

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Sidecar

@Suite("RayMarchTemporal sidecar (VQ.3)")
struct RayMarchTemporalSidecarTests {

    private static func decode(_ block: String, passes: String) throws -> PresetDescriptor {
        let json = """
        {"name":"T","family":"geometric","passes":[\(passes)],"temporal_reconstruction":\(block)}
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    @Test func rayMarch_takesReprojected() throws {
        let spec = try #require(try Self.decode("{\"motion_vectors\":\"reprojected\",\"reactive_mask\":true}",
                                                passes: "\"ray_march\",\"post_process\"").temporalReconstruction)
        #expect(spec.motionVectors == .reprojected)
        #expect(spec.declaredInternalScale == nil, "absent: the scene's own march size")
        #expect(spec.reactiveMask)
        let aa = try #require(try Self.decode("{\"motion_vectors\":\"reprojected\",\"internal_scale\":1.0}",
                                              passes: "\"ray_march\"").temporalReconstruction)
        #expect(aa.rayMarchInternalScale == 1.0, "1.0 = anti-aliasing only")
        let low = try #require(try Self.decode("{\"motion_vectors\":\"reprojected\",\"internal_scale\":0.1}",
                                               passes: "\"ray_march\"").temporalReconstruction)
        #expect(low.rayMarchInternalScale == Float(1.0 / 3.0), "clamped to MetalFX's 3× ceiling")
    }

    @Test func motionSource_mustMatchThePath() {
        #expect(throws: (any Error).self) {
            try Self.decode("{\"motion_vectors\":\"analytic\"}", passes: "\"ray_march\"")
        }
        #expect(throws: (any Error).self) {
            try Self.decode("{\"motion_vectors\":\"reprojected\"}", passes: "\"direct\"")
        }
        #expect(throws: (any Error).self) {
            try Self.decode("{\"motion_vectors\":\"reprojected\"}", passes: "\"ray_march\",\"mv_warp\"")
        }
    }

    @Test @MainActor func noShippedRayMarchSceneDeclaresIt() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let declared = loader.presets.filter { $0.descriptor.temporalReconstruction != nil }.map(\.descriptor.name)
        #expect(declared.isEmpty, "temporal_reconstruction declared by \(declared) — no shipped scene adopts it (VQ.3a: Lumen Mosaic kept the stretch, D-265)")
    }
}

// MARK: - Mechanics

@Suite("RayMarchTemporal mechanics (VQ.3)", .serialized)
struct RayMarchTemporalMechanicsTests {

    /// Raw bytes of any texture (blit to a shared twin).
    static func bytes(_ tex: MTLTexture, _ blit: VQ3Blit, bytesPerPixel: Int) throws -> [UInt8] {
        let shared = try blit.texture(tex.pixelFormat, tex.width, tex.height, usage: [.shaderRead], storage: .shared)
        let cb = try #require(blit.queue.makeCommandBuffer())
        let enc = try #require(cb.makeBlitCommandEncoder())
        enc.copy(from: tex, to: shared)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var out = [UInt8](repeating: 0, count: tex.width * tex.height * bytesPerPixel)
        shared.getBytes(&out, bytesPerRow: tex.width * bytesPerPixel,
                        from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        return out
    }

    static func floats(_ tex: MTLTexture, _ blit: VQ3Blit, channels: Int) throws -> [Float] {
        let raw = try bytes(tex, blit, bytesPerPixel: channels * (tex.pixelFormat == .r32Float ? 4 : 2))
        if tex.pixelFormat == .r32Float {
            return raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        return raw.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)).map(Float.init) }
    }

    @Test("Zero jitter: the march (G-buffer + lit) is byte-identical to today's path")
    func zeroJitter_isByteIdentical() throws {
        guard DirectTemporalReconstructor.isSupported(device: try #require(MTLCreateSystemDefaultDevice())) else { return }
        let plain = try RayMarchUpscaleRig(scene: .proof, mode: .stretch(canvasW: 640, canvasH: 360),
                                           outW: 960, outH: 540, marchW: 640, marchH: 360)
        let recon = try RayMarchUpscaleRig(scene: .proof, mode: .temporal, outW: 960, outH: 540,
                                           marchW: 640, marchH: 360, context: plain.context)
        recon.temporal?.reconstructor.jitterEnabled = false
        plain.dollySpeed = 0.6
        recon.dollySpeed = 0.6
        let times: [Float] = [0.5, 0.5 + 1.0 / 60, 0.5 + 2.0 / 60]
        for time in times {
            try plain.frame(time: time)
            try recon.frame(time: time)
            let pairs: [(MTLTexture?, MTLTexture?, Int, String)] = [
                (plain.pipeline.gbuffer0, recon.pipeline.gbuffer0, 4, "gbuffer0"),
                (plain.pipeline.gbuffer1, recon.pipeline.gbuffer1, 4, "gbuffer1"),
                (plain.pipeline.gbuffer2, recon.pipeline.gbuffer2, 4, "gbuffer2"),
                (plain.pipeline.litTexture, recon.pipeline.litTexture, 8, "lit"),
            ]
            for (a, b, bpp, name) in pairs {
                let lhs = try Self.bytes(try #require(a), plain.blit, bytesPerPixel: bpp)
                let rhs = try Self.bytes(try #require(b), plain.blit, bytesPerPixel: bpp)
                #expect(lhs == rhs, "\(name) differs at t=\(time) with zero jitter")
            }
        }
        #expect(recon.temporal?.reconstructor.encodeCount == 3, "the reconstruct path ran")
    }

    @Test("Motion pass: still camera → no motion, no reactive; dolly → outward motion, static geometry not reactive")
    func motionPass() throws {
        guard DirectTemporalReconstructor.isSupported(device: try #require(MTLCreateSystemDefaultDevice())) else { return }
        let rig = try RayMarchUpscaleRig(scene: .proof, mode: .temporal, outW: 960, outH: 540, marchW: 640, marchH: 360)
        let temporal = try #require(rig.temporal)
        for frame in 0..<3 { try rig.frame(time: Float(frame) / 60) }
        let lit = try #require(rig.pipeline.litTexture)
        var targets = try #require(temporal.lastInputs(color: lit))
        let still = try Self.floats(targets.motion, rig.blit, channels: 2)
        let maxStill = still.map(abs).max() ?? 0
        #expect(maxStill < 0.02, "still camera: max |motion| \(maxStill) px")
        let stillReactive = try Self.bytes(try #require(targets.reactive), rig.blit, bytesPerPixel: 1)
        #expect(stillReactive.filter { $0 > 128 }.count < stillReactive.count / 100, "still: nothing reactive")

        rig.dollySpeed = 1.5
        for frame in 3..<6 { try rig.frame(time: Float(frame) / 60) }
        targets = try #require(temporal.lastInputs(color: lit))
        let moving = try Self.floats(targets.motion, rig.blit, channels: 2)
        let w = 640, h = 360
        // Ground right of centre, low on screen: moving forward, a point there was nearer the centre last
        // frame → previous − current x < 0.
        let px = (h * 7 / 8) * w + w * 3 / 4
        #expect(moving[px * 2] < -0.05, "dolly: lower-right ground moves outward (motion.x \(moving[px * 2]))")
        let reactiveBytes = try Self.bytes(try #require(targets.reactive), rig.blit, bytesPerPixel: 1)
        let reactiveShare = Double(reactiveBytes.filter { $0 > 128 }.count) / Double(reactiveBytes.count)
        print("[vq3-rm] dolly 1.5 u/s: reactive share \(String(format: "%.4f", reactiveShare)), still max |m| \(maxStill)")
        #expect(reactiveShare < 0.02, "static geometry under a camera move is not reactive (\(reactiveShare))")
    }

    @Test("Jitter sign: a still scene converges on native only with MetalFX's sign")
    func jitterSign() throws {
        guard DirectTemporalReconstructor.isSupported(device: try #require(MTLCreateSystemDefaultDevice())) else { return }
        let native = try RayMarchUpscaleRig(scene: .proof, mode: .reference(factor: 1), outW: 960, outH: 540,
                                            marchW: 960, marchH: 540)
        let reference = try native.blit.luma(try native.frame(time: 1).texture)
        var errors: [Float: Double] = [:]
        let signs: [Float] = [-1, 1]
        for sign in signs {
            let rig = try RayMarchUpscaleRig(scene: .proof, mode: .temporal, outW: 960, outH: 540,
                                             marchW: 640, marchH: 360, context: native.context)
            rig.temporal?.reconstructor.jitterSign = sign
            var out: MTLTexture?
            for _ in 0..<40 { out = try rig.frame(time: 1).texture }
            errors[sign] = UpscaleMetrics.meanAbs(try rig.blit.luma(try #require(out)), reference)
        }
        let negated = errors[-1] ?? 1, plain = errors[1] ?? 0
        print("[vq3-rm] jitter sign: |Δ| vs native −1 \(negated), +1 \(plain)")
        #expect(negated < plain, "MetalFX takes the jitter negated (D-263)")
    }
}

// MARK: - Memory (task 5)

@Suite("RayMarchTemporal memory (VQ.3)", .serialized)
struct RayMarchTemporalMemoryTests {

    /// What production charges for the drawable pool (three 8-bit frames, VQ.0).
    static func drawablePool(_ w: Int, _ h: Int) -> Int { 3 * w * h * 4 }

    /// UPSCALE_MEMORY=1, and run ALONE (`--filter reconstructing4K_fits`): a MetalFX scaler is charged
    /// as the device's `currentAllocatedSize` delta around its creation, so a parallel suite's
    /// allocations inflate the number — and ~800 MiB of 4K sets here would inflate theirs (MFX.2's
    /// switch test was refused when this ran alongside it).
    @Test("Lumen Mosaic and Volumetric Lithograph reconstructing at 4K fit under the ceiling (UPSCALE_MEMORY=1)")
    func reconstructing4K_fits() throws {
        guard ProcessInfo.processInfo.environment["UPSCALE_MEMORY"] == "1" else { return }
        let device = try #require(MTLCreateSystemDefaultDevice())
        guard DirectTemporalReconstructor.isSupported(device: device) else { return }
        let ceiling = RenderTargetBudget.ceiling(device: device)
        for (scene, march) in [(RayMarchUpscaleRig.Scene.lumenMosaic, (2560, 1440)),
                               (.volumetricLithograph, (1536, 864)), (.volumetricLithograph, (1280, 720))] {
            let ctx = try MetalContext()
            let budget = ctx.renderTargetBudget
            #expect(budget.reserve("drawable pool", bytes: Self.drawablePool(3840, 2160)))
            let rig = try RayMarchUpscaleRig(scene: scene, mode: .temporal, outW: 3840, outH: 2160,
                                             marchW: march.0, marchH: march.1, context: ctx)
            try rig.frame(time: 0)
            try rig.frame(time: 1 / 60)
            #expect(rig.temporal?.reconstructor.isTemporal == true, "\(scene) reconstructed")
            let total = budget.totalBytes
            let scaler = budget.reservedBytes.filter { $0.key.hasPrefix("mfx2 scaler") }.values.reduce(0, +)
            print(String(format: "[vq3-memory] %@ %d×%d → 3840×2160: render set %.1f MiB (scaler %.1f MiB) of %.1f MiB",
                         scene.rawValue, march.0, march.1, Double(total) / 1_048_576, Double(scaler) / 1_048_576,
                         Double(ceiling) / 1_048_576))
            #expect(total <= ceiling, "\(scene) at 4K: \(total) B over the \(ceiling) B ceiling")
        }
    }

    @Test("Switching away releases every MetalFX reservation and target")
    func sceneSwitch_releases() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        guard DirectTemporalReconstructor.isSupported(device: device) else { return }
        let ctx = try MetalContext()
        let budget = ctx.renderTargetBudget
        let baseline = budget.totalBytes
        for mode in [RayMarchUpscaleRig.Mode.temporal, .spatial] {
            try autoreleasepool {
                var rig: RayMarchUpscaleRig? = try RayMarchUpscaleRig(
                    scene: .proof, mode: mode, outW: 1920, outH: 1080, marchW: 1280, marchH: 720, context: ctx)
                try rig?.frame(time: 0)
                #expect(budget.reservedBytes.keys.contains { $0.hasPrefix("mfx") }, "\(mode) charged a reservation")
                // Production's switch: the app drops the scene's RayMarchPipeline (setRayMarchPipeline(nil)).
                rig?.pipeline.temporal = nil
                rig?.pipeline.spatialUpscaler = nil
                rig = nil
            }
            #expect(budget.reservedBytes.keys.allSatisfy { !$0.hasPrefix("mfx") }, "\(mode): a reservation outlived its scene")
        }
        ctx.commandQueue.makeCommandBuffer().map { $0.commit(); $0.waitUntilCompleted() }
        #expect(budget.totalBytes <= baseline + 1, "every target released (\(budget.totalBytes) B left)")
    }

    @Test("Floor: an 8 GB-Mac budget under pressure refuses the scaler and the scene renders stretched, no crash")
    func floor_refusesAndFallsBack() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        guard DirectTemporalReconstructor.isSupported(device: device) else { return }
        let ctx = try MetalContext()
        // The 8 GB Mac's ceiling, with injected pressure: everything but 20 MiB already held.
        let budget = ctx.renderTargetBudget
        let floorCeiling = RenderTargetBudget.ceiling(largestSetBytes: RenderTargetBudget.largestScene4KSetBytes,
                                                      physicalMemory: 8 << 30,
                                                      recommendedWorkingSet: device.recommendedMaxWorkingSetSize)
        budget.ceiling = floorCeiling
        #expect(budget.reserve("injected pressure", bytes: floorCeiling - budget.totalBytes - (20 << 20), force: true))
        let rig = try RayMarchUpscaleRig(scene: .proof, mode: .temporal, outW: 1280, outH: 720,
                                         marchW: 640, marchH: 360, context: ctx)
        let out = try rig.frame(time: 0)
        #expect(rig.temporal?.reconstructor.isTemporal == false, "the scaler was refused")
        #expect(!budget.refusals.isEmpty)
        let luma = try rig.blit.luma(out.texture)
        #expect((luma.max() ?? 0) - (luma.min() ?? 0) > 0.3, "the frame still renders (the scene's normal path)")
        print("[vq3-memory] floor ceiling \(floorCeiling / 1_048_576) MiB: \(budget.refusals.count) refusal(s), rendered")
        budget.releaseReservation("injected pressure")
    }
}
