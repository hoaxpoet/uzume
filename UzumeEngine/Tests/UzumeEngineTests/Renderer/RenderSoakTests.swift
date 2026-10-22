// RenderSoakTests — VQ.0's engine-side render-memory soak (D-264). Isolated: SOAK_TESTS=1.
//
//   SOAK_TESTS=1 swift test --package-path UzumeEngine --filter RenderSoak          (10 minutes)
//   SOAK_TESTS=1 RENDER_SOAK_MINUTES=60 swift test --package-path UzumeEngine --filter RenderSoak
//
// The full-scene soak runs in the app (`Scripts/render_soak.sh`): only the app owns `applyPreset`. This one churns
// the engine's allocation paths for the whole duration — scene switches across feedback, mv_warp (Dragon Bloom),
// ray-march and staged (Staged Sandbox), each at 4K, with a 1080p ↔ 4K commit every 30 s — and gates on drift:
// after the first full cycle, Metal's allocation and phys_footprint must not climb.

import Testing
import Foundation
import Metal
@testable import Diagnostics
@testable import Renderer
@testable import Shared

@Suite("RenderSoak", .serialized)
@MainActor
struct RenderSoakTests {

    @Test("10-minute allocation soak: no Metal or footprint drift after the first cycle")
    func soak() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SOAK_TESTS"] == "1" else { return }   // isolated only
        let minutes = env["RENDER_SOAK_MINUTES"].flatMap(Double.init) ?? 10
        let rig = try RenderBudgetRig()
        let lib = try ShaderLibrary(context: rig.ctx)
        let rayMarch = try RayMarchPipeline(context: rig.ctx, shaderLibrary: lib)
        var size = vq0UHD
        rig.resize(size)

        /// One scene switch the way `applyPreset` tears down and builds up.
        func apply(_ scene: Int) throws {
            rig.pipeline.setFeedbackParams(nil)
            rig.pipeline.clearMVWarpState()
            rig.pipeline.setRayMarchPipeline(nil)
            rig.pipeline.setStagedRuntime(nil, drawableSize: size)
            switch scene % 4 {
            case 0: rig.pipeline.setFeedbackParams(FeedbackParams()); rig.resize(size)
            case 1: try rig.attachMVWarp(size: size)
            case 2: rig.pipeline.setRayMarchPipeline(rayMarch)
                    rayMarch.releaseTextures()
                    rayMarch.ensureAllocated(width: Int(size.width), height: Int(size.height))
            default: try rig.attachStaged(size: size)
            }
            rig.idle()
        }

        let start = Date()
        var lastToggle = start
        var scene = 0
        var samples: [(t: Double, metal: Int, footprint: Int)] = []
        var baselineIndex: Int?
        while Date().timeIntervalSince(start) < minutes * 60 {
            try apply(scene)
            scene += 1
            if Date().timeIntervalSince(lastToggle) >= 30 {
                size = size == vq0UHD ? vq0HD : vq0UHD
                rig.resize(size)
                if scene % 4 == 3 { rayMarch.ensureAllocated(width: Int(size.width), height: Int(size.height)) }
                rig.idle()
                lastToggle = Date()
            }
            if scene % 4 == 0, size == vq0UHD {      // sample at the same point of the cycle, at 4K
                rig.idle()
                let footprint = Int(MemoryReporter.snapshot()?.residentBytes ?? 0)
                samples.append((Date().timeIntervalSince(start), rig.ctx.device.currentAllocatedSize, footprint))
                if baselineIndex == nil { baselineIndex = samples.count - 1 }
            }
            #expect(rig.chargedEqualsLive)
            #expect(rig.budget.totalBytes <= rig.budget.ceiling)
        }
        let base = try #require(baselineIndex.map { samples[$0] })
        let last = try #require(samples.last)
        let metalDrift = last.metal - base.metal
        let footprintDrift = last.footprint - base.footprint
        print("VQ0 render soak \(Int(minutes)) min: \(scene) switches, \(samples.count) samples; "
              + "Metal \(base.metal >> 20) → \(last.metal >> 20) MB, footprint \(base.footprint >> 20) → \(last.footprint >> 20) MB")
        #expect(abs(metalDrift) <= 16 << 20, "Metal allocation drift \(metalDrift >> 20) MB")
        #expect(footprintDrift <= 50 << 20, "phys_footprint drift \(footprintDrift >> 20) MB")
        #expect(rig.budget.refusals.isEmpty)
    }
}
