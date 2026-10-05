// InariTests — INARI.1: the relit shrine drawing.
//
// What can silently go wrong:
//   1. The light map's sources stop classifying (regenerated drawings, new ids) — the eyes
//      become lanterns and answer the bass, and nothing errors.
//   2. The routing drifts: eyes must answer the voice only, lanterns the bass, the shrine the
//      drums (Matt, 2026-10-05).
//   3. The contract with the drawings breaks: level 0 must BE the moonlit drawing, level 1 must
//      come out near the lit drawing. Measured through the real shader, not asserted.
import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
@testable import Presets
@testable import Shared

@Suite("Inari (INARI.1)")
struct InariTests {

    private func makeState() throws -> (MTLDevice, InariState) {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        return (device, try #require(InariState(device: device), "InariState failed to load its drawings"))
    }

    // MARK: - Sources

    @Test("The light map's sources classify: 3 eye sources, a shrine, and the lanterns")
    func sourcesClassify() throws {
        let (_, state) = try makeState()
        let roles = state.rolesForTesting()
        let eyes = roles.values.filter { $0 == .eye }.count
        let shrine = roles.values.filter { $0 == .shrine }.count
        let lanterns = roles.values.filter { if case .lantern = $0 { return true }; return false }.count
        #expect(eyes == 3, "eye sources: \(eyes) (left fox's pair + right fox's two)")
        #expect(shrine >= 3, "shrine sources: \(shrine) (pagoda windows + hall lamps)")
        #expect(lanterns >= 15, "lantern sources: \(lanterns)")
        #expect(roles.keys.allSatisfy { $0 >= 1 && $0 < InariState.maxLights })
    }

    // MARK: - Routing

    private func run(_ state: InariState, seconds: Float, stems: StemFeatures) {
        for _ in 0..<Int(seconds * 60) { state.tick(deltaTime: 1.0 / 60.0, stems: stems) }
    }

    private func mean(_ state: InariState, _ pick: (InariState.Role) -> Bool) -> Float {
        let lv = state.levelsForTesting(), roles = state.rolesForTesting().filter { pick($0.value) }
        return roles.keys.map { lv[$0 - 1] }.reduce(0, +) / Float(max(roles.count, 1))
    }
    private func isLantern(_ r: InariState.Role) -> Bool { if case .lantern = r { return true }; return false }

    @Test("Each group answers its own stem and no other")
    func routing() throws {
        var quiet = StemFeatures.zero
        quiet.bassEnergyRel = -0.25          // below its running mean: a quiet bass
        var vox = quiet; vox.vocalsEnergy = 0.7; vox.vocalsEnergyDev = 0.2
        var bass = quiet; bass.bassEnergyRel = 0.6
        var drums = quiet; drums.drumsEnergyDev = 0.6

        let (_, base) = try makeState(); run(base, seconds: 3, stems: quiet)
        let (_, v) = try makeState(); run(v, seconds: 3, stems: vox)
        let (_, b) = try makeState(); run(b, seconds: 3, stems: bass)
        let (_, d) = try makeState(); run(d, seconds: 3, stems: drums)

        #expect(mean(base, { $0 == .eye }) < 0.01, "eyes must be dark stone with no voice")
        #expect(mean(v, { $0 == .eye }) > 0.5, "eyes must kindle with the voice")
        #expect(mean(b, isLantern) > mean(base, isLantern) + 0.4, "lanterns must swell with the bass")
        #expect(mean(d, { $0 == .shrine }) > mean(base, { $0 == .shrine }) + 0.4, "the shrine must answer the drums")
        // and only their own stem
        #expect(abs(mean(v, isLantern) - mean(base, isLantern)) < 0.01)
        #expect(abs(mean(b, { $0 == .eye }) - mean(base, { $0 == .eye })) < 0.01)
        #expect(abs(mean(d, isLantern) - mean(base, isLantern)) < 0.01)
    }

    @Test("A bass swell climbs the stairs: the highest lantern rises after the nearest")
    func bassClimbs() throws {
        let (_, state) = try makeState()
        var stems = StemFeatures.zero
        stems.bassEnergyRel = -0.25
        run(state, seconds: 2, stems: stems)
        let roles = state.rolesForTesting().compactMap { id, r -> (Int, Float)? in
            if case .lantern(let c) = r { return (id, c) }; return nil
        }
        let lowest = try #require(roles.min { $0.1 < $1.1 }), highest = try #require(roles.max { $0.1 < $1.1 })
        stems.bassEnergyRel = 0.6
        run(state, seconds: 0.15, stems: stems)
        let lv = state.levelsForTesting()
        #expect(lv[lowest.0 - 1] > lv[highest.0 - 1] + 0.2,
                "after 0.15 s the nearest lantern (\(lv[lowest.0 - 1])) must lead the highest (\(lv[highest.0 - 1]))")
    }

    // MARK: - The drawings, through the real shader

    /// Renders Inari at 1536 × 1024 (the drawings' own aspect, so no crop) with every level `L`.
    private func render(level: Float, bindTextures: Bool = true) throws -> [UInt8] {
        let (device, state) = try makeState()
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Inari" }, "Inari not loaded")
        let w = 1536, h = 1024
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget]; td.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: td))
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = target; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
        let queue = try #require(device.makeCommandQueue())
        let cb = try #require(queue.makeCommandBuffer()), enc = try #require(cb.makeRenderCommandEncoder(descriptor: rp))
        var features = FeatureVector(time: 0, deltaTime: 0.016)
        features.aspectRatio = 1.5
        var levels = [Float](repeating: level, count: InariState.maxLights)
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentBytes(&levels, length: levels.count * 4, index: 6)
        if bindTextures { for (k, t) in state.textures.enumerated() { enc.setFragmentTexture(t, index: 9 + k) } }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: w * h * 4)
        target.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return px   // BGRA
    }

    private func drawing(_ name: String) throws -> [UInt8] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Presets/Shaders/Inari/\(name)")
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        var px = [UInt8](repeating: 0, count: 1536 * 1024 * 4)
        let ctx = try #require(CGContext(data: &px, width: 1536, height: 1024, bitsPerComponent: 8, bytesPerRow: 1536 * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1536, height: 1024))
        return px   // RGBA
    }

    /// Mean absolute difference (8-bit) between a BGRA render and an RGBA drawing.
    private func mad(_ bgra: [UInt8], _ rgba: [UInt8]) -> Double {
        var s = 0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let r = abs(Int(bgra[i + 2]) - Int(rgba[i]))
            let g = abs(Int(bgra[i + 1]) - Int(rgba[i + 1]))
            let b = abs(Int(bgra[i]) - Int(rgba[i + 2]))
            s += r + g + b
        }
        return Double(s) / Double(bgra.count / 4 * 3)
    }

    @Test("Level 0 is the moonlit drawing; level 1 brings the lit areas up to the lit drawing")
    func drawingsContract() throws {
        let unlit = try drawing("inari_unlit.webp"), lit = try drawing("inari_lit.webp")
        let dark = try render(level: 0), full = try render(level: 1)
        let darkToUnlit = mad(dark, unlit)
        // Mean linear brightness over every pixel a light owns. Never per pixel, and never over
        // pixels selected for being brighter in the lit drawing: the two drawings' fine marks
        // differ everywhere, so either would measure texture, not light.
        let owners = try drawing("inari_lights.png")
        func lin(_ v: UInt8) -> Double { let s = Double(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        func luma(_ p: [UInt8], _ i: Int, bgra: Bool) -> Double {
            0.2126 * lin(p[bgra ? i + 2 : i]) + 0.7152 * lin(p[i + 1]) + 0.0722 * lin(p[bgra ? i : i + 2])
        }
        var mLit = 0.0, mDark = 0.0, mFull = 0.0, n = 0.0
        for i in stride(from: 0, to: lit.count, by: 4) where owners[i + 1] > 0 {
            mLit += luma(lit, i, bgra: false); mDark += luma(dark, i, bgra: true); mFull += luma(full, i, bgra: true); n += 1
        }
        let gap0 = (mLit - mDark) / max(n, 1), gap1 = (mLit - mFull) / max(n, 1)
        print("Inari: |L0 − unlit| \(darkToUnlit); lit-area mean linear brightness gap to the lit drawing: L0 \(gap0), L1 \(gap1) over \(Int(n)) px")
        #expect(darkToUnlit < 1.0, "level 0 must reproduce the moonlit drawing (MAD \(darkToUnlit))")
        #expect(n > 200_000, "the light map must own the lit areas")
        #expect(abs(gap1) < gap0 * 0.35, "level 1 must close most of the brightness gap to the lit drawing")
    }

    @Test("Unbound (generic harness): a still, non-black field — D-037")
    func unboundFallback() throws {
        let px = try render(level: 0, bindTextures: false)
        var sum = 0
        for i in stride(from: 0, to: px.count, by: 4) { sum += Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) }
        let meanLuma = sum / (px.count / 4)
        #expect(meanLuma > 10, "fallback must not render black (sum-of-channels mean \(meanLuma))")
    }
}
