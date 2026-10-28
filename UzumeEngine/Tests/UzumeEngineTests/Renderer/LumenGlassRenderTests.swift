// LumenGlassRenderTests — LMG: Lumen Mosaic at Matt's real geometry (tier-1 4K: march 2560×1440, stretched to
// 3840×2160 — the production path), one 4K PNG per palette, for the stained-hammered-glass review.
//
// LM_GLASS_OUT=<dir> (optional LM_GLASS_LABEL=<prefix>): Tenebrism (darkest), Obsidian, Holi (bright), Autumnal,
// after 90 frames of a 120 BPM beat + stem train so cells have stepped. Debug is fine — this is an image, not timing.

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Lumen Mosaic glass render (LMG)", .serialized)
@MainActor
struct LumenGlassRenderTests {

    @Test("Lumen Mosaic at 4K per palette (LM_GLASS_OUT=<dir>)")
    func renderPalettes() throws {
        guard let out = ProcessInfo.processInfo.environment["LM_GLASS_OUT"] else { return }
        let label = ProcessInfo.processInfo.environment["LM_GLASS_LABEL"] ?? "lm"
        let dir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = try MetalContext()
        let frames = 90
        let beat = FlashHarnessSupport.worstCaseBeatTrain(accentHz: 2, seconds: Double(frames) / 60)
        let stems = FlashHarnessSupport.worstCaseStemTrain(accentHz: 2, seconds: Double(frames) / 60)
        for name in ["Tenebrism", "Obsidian", "Holi", "Autumnal"] {
            let palette = try #require(LumenMosaicPaletteLibrary.all.first { $0.name == name })
            let rig = try RayMarchUpscaleRig(scene: .lumenMosaic, mode: .stretch(canvasW: 2560, canvasH: 1440),
                                             outW: 3840, outH: 2160, marchW: 2560, marchH: 1440, context: ctx,
                                             lumenPalette: palette)
            // LM_GLASS_SEQ=1: every frame of the darkest palette too, for `motion_gate.sh`.
            let sequence = ProcessInfo.processInfo.environment["LM_GLASS_SEQ"] == "1" && name == "Tenebrism"
            var last: MTLTexture?
            for i in 0..<frames {
                last = try rig.frame(time: Float(i) / 60, features: beat[i], stems: stems[i]).texture
                if sequence, let last {
                    try EnergeticFlybyRenderTests.writePNG(try rig.blit.bgra(last), 3840, 2160,
                                                          dir.appendingPathComponent(String(format: "seq_%04d.png", i)))
                }
            }
            let url = dir.appendingPathComponent("\(label)_\(name).png")
            try EnergeticFlybyRenderTests.writePNG(try rig.blit.bgra(try #require(last)), 3840, 2160, url)
            print("[lm-glass] \(url.path)")
        }
    }

    /// How sharp at 4K, at what cost: the stretch (march 2560×1440), native 4K computed per frame, and native 4K
    /// with the glass baked once (LM.10, production). Same frames; 4K PNGs, frame 0's GPU ms (the bake runs there)
    /// and the median of frames 30–89, one frame at a time (relative — quote Release only). LM_GLASS_MODES=<dir>.
    /// (ab90c478 measured MetalFX temporal here at 16.7 ms: ruled out.)
    @Test("Lumen Mosaic glass: stretch vs native 4K, computed vs baked (LM_GLASS_MODES=<dir>)")
    func renderModes() throws {
        guard let out = ProcessInfo.processInfo.environment["LM_GLASS_MODES"] else { return }
        let dir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = try MetalContext()
        let frames = 90
        let beat = FlashHarnessSupport.worstCaseBeatTrain(accentHz: 2, seconds: Double(frames) / 60)
        let stems = FlashHarnessSupport.worstCaseStemTrain(accentHz: 2, seconds: Double(frames) / 60)
        let modes: [(String, RayMarchUpscaleRig.Mode, Bool)] = [
            ("stretch", .stretch(canvasW: 2560, canvasH: 1440), false),
            ("native", .reference(factor: 1), false), ("native-baked", .reference(factor: 1), true)]
        for name in ["Tenebrism", "Holi"] {
            let palette = try #require(LumenMosaicPaletteLibrary.all.first { $0.name == name })
            for (label, mode, baked) in modes {
                let rig = try RayMarchUpscaleRig(scene: .lumenMosaic, mode: mode, outW: 3840, outH: 2160,
                                                 marchW: 2560, marchH: 1440, context: ctx, lumenPalette: palette,
                                                 useBake: baked)
                var gpu: [Double] = []
                var first = 0.0
                var last: MTLTexture?
                for i in 0..<frames {
                    let frame = try rig.frame(time: Float(i) / 60, features: beat[i], stems: stems[i])
                    last = frame.texture
                    if i == 0 { first = frame.gpuMs }
                    if i >= 30 { gpu.append(frame.gpuMs) }
                }
                try EnergeticFlybyRenderTests.writePNG(try rig.blit.bgra(try #require(last)), 3840, 2160,
                                                      dir.appendingPathComponent("\(label)_\(name).png"))
                print(String(format: "[lm-glass-modes] %@ %@: GPU median %.2f ms, frame 0 %.2f ms", name, label,
                             gpu.sorted()[gpu.count / 2], first))
            }
        }
    }
}
