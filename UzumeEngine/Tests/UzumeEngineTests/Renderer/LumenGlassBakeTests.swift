// LumenGlassBakeTests — LM.10: Lumen Mosaic's glass is baked once (`preset_bake_fragment`) and only coloured per
// frame. The bake must be the same glass as the inline evaluation (up to its 8-bit encoding), and only Lumen
// Mosaic may declare a bake / `upscale: native`.

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Lumen Mosaic baked glass (LM.10)", .serialized)
@MainActor
struct LumenGlassBakeTests {

    @Test("Lumen Mosaic ships a bake and renders native; no other ray-march scene does")
    func onlyLumenMosaicBakes() throws {
        let presets = _acceptanceFixture.presets.filter { $0.rayMarchPipelineState != nil }
        let lumen = try #require(presets.first { $0.descriptor.name == "Lumen Mosaic" })
        #expect(lumen.bakePipelineState != nil)
        #expect(lumen.descriptor.upscale == .native)
        let others = presets.filter { $0.descriptor.name != "Lumen Mosaic" }
        #expect(!others.isEmpty)
        #expect(others.allSatisfy { $0.bakePipelineState == nil && $0.descriptor.upscale != .native })
    }

    /// The same frames with the bake bound and without it (inline): a wrong lookup (a flipped axis, a texel
    /// offset) moves every dimple and fails by an order of magnitude.
    @Test("The baked glass is the inline glass (8-bit encoding only)")
    func bakeMatchesInline() throws {
        let ctx = try MetalContext()
        let beat = FlashHarnessSupport.worstCaseBeatTrain(accentHz: 2, seconds: 0.5)
        for name in ["Holi", "Tenebrism"] {
            let palette = try #require(LumenMosaicPaletteLibrary.all.first { $0.name == name })
            var images: [[UInt8]] = []
            for useBake in [false, true] {
                let rig = try RayMarchUpscaleRig(scene: .lumenMosaic, mode: .reference(factor: 1), outW: 1920,
                                                 outH: 1080, marchW: 1920, marchH: 1080, context: ctx,
                                                 lumenPalette: palette, useBake: useBake)
                var last: MTLTexture?
                for i in 0..<12 { last = try rig.frame(time: Float(i) / 60, features: beat[i]).texture }
                #expect(useBake == (rig.bakeTexture != nil))
                images.append(try rig.blit.bgra(try #require(last)))
            }
            let diffs = zip(images[0], images[1]).map { abs(Int($0) - Int($1)) }
            let mean = Double(diffs.reduce(0, +)) / Double(diffs.count)
            let over = diffs.filter { $0 > 4 }.count
            print(String(format: "[lm-bake] %@: mean |Δ| %.3f /255, max %d, > 4: %d of %d", name, mean,
                         diffs.max() ?? 0, over, diffs.count))
            #expect(mean < 0.5, "\(name): mean |Δ| \(mean)")
            #expect(Double(over) < 0.001 * Double(diffs.count), "\(name): \(over) channels off by > 4/255")
        }
    }
}
