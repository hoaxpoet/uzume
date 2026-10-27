// MultiPassFlashUpscaleTests — VQ.3 task 6: sharpening can enlarge a flash, so every VQ.3 upscale is
// run through the photosensitivity gate (Harding / WCAG 2.3.1, the multi-pass suite's analyzer and
// worst-case beat + stem train) against today's stretch of the same frames.
//
// Cases at 640×360 out — the tier-1 4K geometry at ⅙ size: the stretch renders into a ⅔ canvas, Lumen
// Mosaic marches the canvas (1.5×), Volumetric Lithograph marches ½ of it (3×):
//   • Lumen Mosaic and Volumetric Lithograph (forced on in tests only) — stretch / spatial / temporal,
//     each asserted safe (whole frame, per ninth, saturated red) and stated against the stretch;
//   • the ray-march proof scene (dolly) and the flat proof scene (pan) — they do not respond to audio,
//     so they are not "measured" in the gate's sense: their rates are stated and must stay at the
//     stretch's and under the limit (a sharpening-made flash would show here).
// Keep the `MultiPassFlash` type-name prefix — the RUNBOOK certification battery filters on it.

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Photosensitivity Multi-Pass Flash: VQ.3 upscales vs the stretch", .serialized)
struct MultiPassFlashUpscaleTests {

    static let outW = 640, outH = 360
    static let canvas = (426, 240)

    struct Rates {
        let samples: [FlashHarnessSupport.FlashSample]
        var whole: Double { FlashAnalyzer.analyze(relativeLuminance: samples.map(\.luma), fps: FlashHarnessSupport.fps).peakFlashesPerSecond }
        var regional: Double { FlashAnalyzer.analyzeRegional(samples.map(\.regions), fps: FlashHarnessSupport.fps).peakFlashesPerSecond }
        var red: Double { FlashAnalyzer.analyzeRed(samples.map(\.regions), fps: FlashHarnessSupport.fps).peakFlashesPerSecond }
    }

    static func rayMarchSamples(_ scene: RayMarchUpscaleRig.Scene, _ mode: RayMarchUpscaleRig.Mode,
                                march: (Int, Int), dolly: Float) throws -> [FlashHarnessSupport.FlashSample] {
        let rig = try RayMarchUpscaleRig(scene: scene, mode: mode, outW: outW, outH: outH,
                                         marchW: march.0, marchH: march.1)
        rig.dollySpeed = dolly
        let beat = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try beat.indices.map { i in
            let out = try rig.frame(time: Float(i) / 60, features: beat[i], stems: stems[i]).texture
            return FlashHarnessSupport.sample(try rig.blit.bgra(out), width: outW, height: outH)
        }
    }

    static func report(_ name: String, _ rates: Rates, stretch: Rates) {
        print(String(format: "[vq3-flash] %@: whole %.2f/s (stretch %.2f), regional %.2f/s (stretch %.2f), red %.2f/s (stretch %.2f)",
                     name, rates.whole, stretch.whole, rates.regional, stretch.regional, rates.red, stretch.red))
    }

    static func modes(march: (Int, Int)) -> [(String, RayMarchUpscaleRig.Mode)] {
        [("stretch", .stretch(canvasW: canvas.0, canvasH: canvas.1)), ("spatial", .spatial), ("temporal", .temporal)]
    }

    @Test("Lumen Mosaic and Volumetric Lithograph stay flash-safe with spatial and temporal upscaling")
    func scenesStaySafe() throws {
        guard DirectTemporalReconstructor.isSupported(device: try #require(MTLCreateSystemDefaultDevice())) else { return }
        for (scene, march, dolly) in [(RayMarchUpscaleRig.Scene.lumenMosaic, (426, 240), Float(0)),
                                      (.volumetricLithograph, (213, 120), 1.8)] {
            var stretch: Rates?
            for (label, mode) in Self.modes(march: march) {
                let samples = try Self.rayMarchSamples(scene, mode, march: march, dolly: dolly)
                let name = "\(scene.rawValue) [\(label), march \(march.0)×\(march.1)]"
                FlashHarnessSupport.assertFlashSafe(name: name, samples: samples)
                let rates = Rates(samples: samples)
                if stretch == nil { stretch = rates }
                Self.report(name, rates, stretch: stretch ?? rates)
            }
        }
    }

    @Test("Proof scenes: spatial and temporal add no flash over the stretch")
    func proofScenesAddNoFlash() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        guard DirectTemporalReconstructor.isSupported(device: device) else { return }
        // The ray-march proof scene, dollying.
        var stretch: Rates?
        for (label, mode) in Self.modes(march: Self.canvas) {
            let rates = Rates(samples: try Self.rayMarchSamples(.proof, mode, march: Self.canvas, dolly: 0.5))
            if stretch == nil { stretch = rates }
            let base = stretch ?? rates
            Self.report("ray-march proof [\(label)]", rates, stretch: base)
            #expect(rates.whole <= max(base.whole, 0) + 0.5 && rates.whole <= 3, "ray-march proof \(label): whole-frame")
            #expect(rates.regional <= base.regional + 0.5 && rates.regional <= 3, "ray-march proof \(label): regional")
            #expect(rates.red <= base.red + 0.5 && rates.red <= 3, "ray-march proof \(label): red")
        }
        // The flat proof scene, panning ⅓ px a frame: stretch vs spatial.
        let ctx = try MetalContext()
        let blit = try VQ3Blit(context: ctx)
        let proof = try FlatProof(blit: blit)
        let canvas = try blit.texture(ctx.pixelFormat, Self.canvas.0, Self.canvas.1)
        let output = try blit.texture(ctx.pixelFormat, Self.outW, Self.outH)
        let spatial = SpatialUpscaler(device: ctx.device, budget: nil)
        var flat: [String: Rates] = [:]
        for label in ["stretch", "spatial"] {
            var samples: [FlashHarnessSupport.FlashSample] = []
            for frame in 0..<180 {
                let cb = try #require(ctx.commandQueue.makeCommandBuffer())
                proof.render(into: canvas, samples: 1, offset: Float(frame) / 3 / Float(Self.outH), commandBuffer: cb)
                let source = label == "spatial"
                    ? spatial.encode(canvas, outputWidth: Self.outW, outputHeight: Self.outH, commandBuffer: cb) ?? canvas
                    : canvas
                blit.encode(source, into: output, commandBuffer: cb)
                cb.commit()
                cb.waitUntilCompleted()
                samples.append(FlashHarnessSupport.sample(try blit.bgra(output), width: Self.outW, height: Self.outH))
            }
            flat[label] = Rates(samples: samples)
        }
        let base = try #require(flat["stretch"]), sharp = try #require(flat["spatial"])
        Self.report("flat proof [stretch]", base, stretch: base)
        Self.report("flat proof [spatial]", sharp, stretch: base)
        #expect(sharp.whole <= base.whole + 0.5 && sharp.regional <= base.regional + 0.5 && sharp.red <= base.red + 0.5)
    }
}
