// RayMarchUpscaleProofTests — VQ.3 tasks 3, 4 and 7, measured (env-gated; minutes of 4K rendering).
//
// UPSCALE_PROOF=1 (run optimized: `swift test -c release --enable-testable-imports`):
//   • the ray-march proof scene, still camera and slow dolly, 4K out from 2560×1440 and 1920×1080;
//   • Lumen Mosaic (still camera) from its tier-1 march 2560×1440; Volumetric Lithograph (forward dolly)
//     from its tier-1 march 1280×720 (3×) and its uncapped-4K march 1536×864 (2.5×);
//   each: today's stretch, MetalFX spatial, MetalFX temporal, native, against the scene's own 2×2
//   supersampled reference — gradient energy, ringing, stair-stepping, |Δ| vs reference, shimmer and
//   ghosting (D-263's flat-pixel method) — plus 4K PNGs and the proof scene's still sheet;
//   • AA-only (task 4): native vs temporal at scale 1.0 vs the reference, stair-steps on the box.
// UPSCALE_TIMING=1 (task 7; quote Release + `UZUME_PRIVATE_TARGETS=1` only): GPU ms of the upscale
// alone — spatial / temporal from 1440p and 1080p, AA-only — p50 / p95.

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("RayMarch upscale proof (VQ.3)", .serialized)
@MainActor
struct RayMarchUpscaleProofTests {

    static var proofEnabled: Bool { ProcessInfo.processInfo.environment["UPSCALE_PROOF"] == "1" }
    static var timingEnabled: Bool { ProcessInfo.processInfo.environment["UPSCALE_TIMING"] == "1" }
    static let outW = 3840, outH = 2160
    static let settle = 24, measured = 8

    static func outputDir() throws -> URL {
        let env = ProcessInfo.processInfo.environment["UPSCALE_OUT"]
        let ssd = "/Volumes/Extreme SSD"
        let root = env ?? (FileManager.default.fileExists(atPath: ssd) ? "\(ssd)/uzume_vq3" : "/tmp/uzume_visual/vq3")
        let url = URL(fileURLWithPath: root)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The four methods in lockstep over `settle + measured` frames; metrics on the measured frames.
    struct Comparison {
        var luma: [String: [[Float]]] = [:]
        var last: [String: MTLTexture] = [:]
        var blit: VQ3Blit?
    }

    // swiftlint:disable:next function_parameter_count
    static func compare(_ scene: RayMarchUpscaleRig.Scene, label: String, march: (Int, Int), canvas: (Int, Int),
                        dolly: Float, pan: Float = 0, methods: [String] = ["reference", "native", "stretch", "spatial",
                                                                          "temporal"]) throws -> Comparison {
        var rigs: [(String, RayMarchUpscaleRig)] = []
        for method in methods {
            let mode: RayMarchUpscaleRig.Mode
            switch method {
            case "reference": mode = .reference(factor: 2)
            case "native": mode = .reference(factor: 1)
            case "stretch": mode = .stretch(canvasW: canvas.0, canvasH: canvas.1)
            case "spatial": mode = .spatial
            default: mode = .temporal
            }
            let rig = try RayMarchUpscaleRig(scene: scene, mode: mode, outW: outW, outH: outH,
                                             marchW: march.0, marchH: march.1)
            rig.dollySpeed = dolly
            rig.panSpeed = pan
            rigs.append((method, rig))
        }
        var result = Comparison()
        result.blit = rigs.first?.1.blit
        for frame in 0..<(settle + measured) {
            let time = 2 + Float(frame) / 60
            for (method, rig) in rigs {
                let out = try rig.frame(time: time).texture
                if frame >= settle {
                    result.luma[method, default: []].append(try rig.blit.luma(out))
                    result.last[method] = out
                }
            }
        }
        let ref = result.luma["reference"] ?? []
        let gRef = ref.map { UpscaleMetrics.gradientEnergy($0, width: outW) }.reduce(0, +) / Double(max(ref.count, 1))
        // Edges: the strongest rising steps in the middle third of the reference (the box / panel silhouettes).
        let edges = UpscaleMetrics.risingEdges(ref.last ?? [], width: outW, rows: (outH / 3)..<(2 * outH / 3),
                                               x0: outW / 4, x1: 3 * outW / 4)
        for method in methods where method != "reference" {
            let frames = result.luma[method] ?? []
            guard let still = frames.last, let refLast = ref.last else { continue }
            let grad = frames.map { UpscaleMetrics.gradientEnergy($0, width: outW) }.reduce(0, +)
                / Double(max(frames.count, 1)) / gRef
            let ghost = method == "temporal" ? ghostShare(native: result.luma["native"]?.last ?? still, still) : 0
            print(String(
                format: "[vq3-%@] %@ from %d×%d: grad %.3f | ringing %.4f | stair RMS %.3f px | |Δ| vs ref %.4f"
                    + " | shimmer %.4f, raw |Δ| %.4f (ref %.4f) | ghost %.3f%%",
                label, method, method == "native" ? outW : march.0, method == "native" ? outH : march.1, grad,
                UpscaleMetrics.overshoot(still, width: outW, edges: edges),
                UpscaleMetrics.edgeStepRMS(still, refLast, width: outW, edges: edges),
                frames.map { UpscaleMetrics.meanAbs($0, refLast) }.last ?? 0,
                UpscaleMetrics.shimmer(frames, reference: ref),
                UpscaleMetrics.frameDelta(frames), UpscaleMetrics.frameDelta(ref), ghost * 100))
        }
        return result
    }

    /// D-263's ghost measure on a whole frame: of the pixels where native is locally flat (7×7 luma
    /// range < 0.04), the share the reconstruction gets badly wrong (|Δ| > 0.12) — softening cannot
    /// explain those, a trail can.
    static func ghostShare(native: [Float], _ recon: [Float]) -> Double {
        let w = outW, h = outH, r = 3
        var rowMin = native, rowMax = native
        for y in 0..<h {
            for x in r..<(w - r) {
                var lo: Float = 1, hi: Float = 0
                for d in -r...r { let v = native[y * w + x + d]; lo = min(lo, v); hi = max(hi, v) }
                rowMin[y * w + x] = lo
                rowMax[y * w + x] = hi
            }
        }
        var flat = 0, wrong = 0
        for y in stride(from: r, to: h - r, by: 2) {
            for x in stride(from: r, to: w - r, by: 2) {
                var lo: Float = 1, hi: Float = 0
                for d in -r...r { lo = min(lo, rowMin[(y + d) * w + x]); hi = max(hi, rowMax[(y + d) * w + x]) }
                guard hi - lo < 0.04 else { continue }
                flat += 1
                if abs(recon[y * w + x] - native[y * w + x]) > 0.12 { wrong += 1 }
            }
        }
        return flat == 0 ? 0 : Double(wrong) / Double(flat)
    }

    // MARK: Proof scene (task 3)

    @Test("Ray-march proof scene at 4K: still and dolly, from 1440p and 1080p (UPSCALE_PROOF=1)")
    func proofScene() throws {
        guard Self.proofEnabled else { return }
        for (motion, dolly) in [("still", Float(0)), ("dolly", 0.5)] {
            for march in [(2560, 1440), (1920, 1080)] {
                let result = try Self.compare(.proof, label: "rm-proof \(motion)", march: march, canvas: march, dolly: dolly)
                if motion == "still", march.0 == 2560 { try Self.writeSheet(result) }
            }
        }
    }

    // MARK: Lumen Mosaic / Volumetric Lithograph, forced on in tests only (task 3)

    @Test("Lumen Mosaic (still camera) at 4K from its tier-1 march (UPSCALE_PROOF=1)")
    func lumenMosaic() throws {
        guard Self.proofEnabled else { return }
        let result = try Self.compare(.lumenMosaic, label: "lumen", march: (2560, 1440), canvas: (2560, 1440), dolly: 0)
        try Self.writeStills(result, prefix: "lumen_mosaic")
    }

    @Test("Volumetric Lithograph (forward dolly) at 4K from 1280×720 and 1536×864 (UPSCALE_PROOF=1)")
    func volumetricLithograph() throws {
        guard Self.proofEnabled else { return }
        // Tier 1 (Matt's M2 Pro): render 2560×1440, march ½ = 1280×720, stretched 3× to 4K today.
        let tier1 = try Self.compare(.volumetricLithograph, label: "vl", march: (1280, 720), canvas: (2560, 1440),
                                     dolly: 1.8)
        try Self.writeStills(tier1, prefix: "volumetric_lithograph_1280x720")
        // Uncapped 4K (M3/M4): the marched-pixel budget's 1536×864, 2.5×; the stretch is direct to 4K.
        let uncapped = try Self.compare(.volumetricLithograph, label: "vl", march: (1536, 864), canvas: (1536, 864),
                                        dolly: 1.8, methods: ["reference", "stretch", "spatial", "temporal"])
        try Self.writeStills(uncapped, prefix: "volumetric_lithograph_1536x864")
    }

    /// VQ.3a: Matt's side-by-side — the same 1920×2160 centre of the 4K frame, today's stretch left, temporal
    /// right, 1:1 pixels on a 4K screen; every frame of a 120 BPM beat + stem train (cells step, lights move)
    /// into `lumen_sbs/` for the clip, frame 180 also as the still. `UPSCALE_SBS=1`.
    @Test("Lumen Mosaic stretch | temporal side-by-side frames at 4K (UPSCALE_SBS=1)")
    func lumenSideBySide() throws {
        guard ProcessInfo.processInfo.environment["UPSCALE_SBS"] == "1" else { return }
        let ctx = try MetalContext()
        let rigs = try [RayMarchUpscaleRig.Mode.stretch(canvasW: 2560, canvasH: 1440), .temporal].map {
            try RayMarchUpscaleRig(scene: .lumenMosaic, mode: $0, outW: Self.outW, outH: Self.outH,
                                   marchW: 2560, marchH: 1440, context: ctx)
        }
        let settle = 24, frames = 300, still = 180
        let beat = FlashHarnessSupport.worstCaseBeatTrain(accentHz: 2, seconds: Double(settle + frames) / 60)
        let stems = FlashHarnessSupport.worstCaseStemTrain(accentHz: 2, seconds: Double(settle + frames) / 60)
        let dir = try Self.outputDir().appendingPathComponent("lumen_sbs")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let half = Self.outW / 2, x0 = Self.outW / 4
        for i in 0..<(settle + frames) {
            let images = try rigs.map { try $0.blit.bgra($0.frame(time: Float(i) / 60, features: beat[i], stems: stems[i]).texture) }
            guard i >= settle else { continue }
            var sbs = [UInt8](repeating: 0, count: Self.outW * Self.outH * 4)
            for y in 0..<Self.outH {
                for (side, image) in images.enumerated() {
                    let src = (y * Self.outW + x0) * 4, dst = (y * Self.outW + side * half) * 4
                    sbs.replaceSubrange(dst..<(dst + half * 4), with: image[src..<(src + half * 4)])
                }
                for x in (half - 2)..<(half + 2) { (0..<3).forEach { sbs[(y * Self.outW + x) * 4 + $0] = 40 } }
            }
            let frame = i - settle
            try EnergeticFlybyRenderTests.writePNG(sbs, Self.outW, Self.outH,
                                                  dir.appendingPathComponent(String(format: "frame_%04d.png", frame)))
            if frame == still {
                try EnergeticFlybyRenderTests.writePNG(sbs, Self.outW, Self.outH,
                                                      dir.appendingPathComponent("lumen_mosaic_stretch_vs_temporal.png"))
            }
        }
        print("[vq3a-sbs] \(frames) frames → \(dir.path)")
    }

    // MARK: AA-only (task 4)

    @Test("AA-only (temporal at scale 1.0): stair-steps native vs AA-only vs reference (UPSCALE_PROOF=1)")
    func antiAliasingOnly() throws {
        guard Self.proofEnabled else { return }
        for (motion, dolly) in [("still", Float(0)), ("dolly", 0.5)] {
            _ = try Self.compare(.proof, label: "aa-only \(motion)", march: (Self.outW, Self.outH),
                                 canvas: (Self.outW, Self.outH), dolly: dolly,
                                 methods: ["reference", "native", "temporal"])
        }
    }

    // MARK: Cost (task 7)

    @Test("GPU cost of the upscale alone at 4K out (UPSCALE_TIMING=1; quote Release only)")
    func timing() throws {
        guard Self.timingEnabled else { return }
        #if DEBUG
        print("[vq3-timing] WARNING: Debug build — numbers are not quotable (CLAUDE.md)")
        #endif
        let ctx = try MetalContext()
        let blit = try VQ3Blit(context: ctx)
        print("[vq3-timing] device \(ctx.device.name), private targets \(!RenderTargetBudget.cpuReadableTargets)")
        func stats(_ label: String, _ values: [Double]) {
            let s = values.sorted()
            guard !s.isEmpty else { return }
            print(String(format: "[vq3-timing] %@: p50 %.2f ms, p95 %.2f ms (n=%d)", label,
                         s[s.count / 2], s[min(Int(Double(s.count) * 0.95), s.count - 1)], s.count))
        }
        /// `count` command buffers submitted back to back (the queue stays saturated, so the GPU clocks
        /// stay up — VQ.1's method), timed by COMPLETION SPACING: with ~10 buffers in flight each one's
        /// own gpuStart…gpuEnd span includes queueing (measured: spatial 14.7 ms span vs 1.47 ms spacing,
        /// and 1.48 ms one-at-a-time). The first `skip` dropped.
        func timed(_ count: Int = 140, skip: Int = 20, _ body: (MTLCommandBuffer) -> Void) -> [Double] {
            var buffers: [MTLCommandBuffer] = []
            for _ in 0..<count {
                guard let cb = ctx.commandQueue.makeCommandBuffer() else { return [] }
                body(cb)
                cb.commit()
                buffers.append(cb)
            }
            buffers.last?.waitUntilCompleted()
            let ends = buffers.dropFirst(skip).map(\.gpuEndTime)
            return zip(ends.dropFirst(), ends).map { ($0 - $1) * 1000 }
        }
        for input in [(2560, 1440), (1920, 1080)] {
            // Spatial: the tier-1 canvas (perceptual, sRGB) and a linear HDR frame (cinematic / ray-march lit).
            for format in [ctx.pixelFormat, MTLPixelFormat.rgba16Float] {
                let source = try blit.texture(format, input.0, input.1)
                let scaler = SpatialUpscaler(device: ctx.device, budget: nil)
                stats("spatial \(format == .rgba16Float ? "hdr" : "perceptual") \(input.0)×\(input.1) → 4K", timed {
                    _ = scaler.encode(source, outputWidth: Self.outW, outputHeight: Self.outH, commandBuffer: $0)
                })
            }
            // Today's bilinear stretch of the same canvas (the present-step copy), for scale.
            let canvas = try blit.texture(ctx.pixelFormat, input.0, input.1)
            let drawable = try blit.texture(ctx.pixelFormat, Self.outW, Self.outH)
            stats("bilinear stretch \(input.0)×\(input.1) → 4K", timed { blit.encode(canvas, into: drawable, commandBuffer: $0) })
        }
        // Temporal + AA-only: the ray-march proof scene's real inputs; the upscale timed alone.
        let cases = [(2560, 1440), (1920, 1080), (1536, 864), (1280, 720)].map { ($0, (Self.outW, Self.outH)) }
            + [(3840, 2160), (2560, 1440), (1920, 1080)].map { ($0, $0) }   // AA-only at each size
        for (march, out) in cases {
            let rig = try RayMarchUpscaleRig(scene: .proof, mode: .temporal, outW: out.0, outH: out.1,
                                             marchW: march.0, marchH: march.1, context: ctx)
            for frame in 0..<4 { try rig.frame(time: Float(frame) / 60) }
            let recon = try #require(rig.temporal?.reconstructor)
            let lit = try #require(rig.pipeline.litTexture)
            let inputs = try #require(rig.temporal?.lastInputs(color: lit))
            let label = march == out ? "AA-only \(out.0)×\(out.1) (1:1)" : "temporal \(march.0)×\(march.1) → 4K"
            stats(label + " (upscale alone)", timed {
                _ = recon.encodeUpscale(commandBuffer: $0, inputs: inputs)
                recon.advance()
            })
        }
    }

    // MARK: Output

    /// 4K PNG of every method's last frame.
    static func writeStills(_ result: Comparison, prefix: String) throws {
        guard let blit = result.blit else { return }
        let dir = try outputDir()
        for (method, texture) in result.last {
            try EnergeticFlybyRenderTests.writePNG(try blit.bgra(texture), outW, outH,
                                                  dir.appendingPathComponent("\(prefix)_\(method).png"))
        }
        print("[vq3] stills → \(dir.path)/\(prefix)_*.png")
    }

    /// The sheet: two 480×270 crops (the box's left silhouette with the rods; the far ground) at 2×
    /// nearest-neighbour, columns native / stretch / spatial / temporal.
    static func writeSheet(_ result: Comparison) throws {
        guard let blit = result.blit else { return }
        let order = ["native", "stretch", "spatial", "temporal"]
        let sources = try order.compactMap { result.last[$0] }.map { try blit.bgra($0) }
        guard sources.count == order.count else { return }
        try writeStills(result, prefix: "rm_proof_still_1440p")
        let cw = 480, ch = 270, zoom = 2, gap = 8, w = outW
        let crops = [(1560, 1000), (1700, 1180)]
        let sheetW = cw * zoom * sources.count + gap * (sources.count - 1), sheetH = ch * zoom * crops.count + gap
        var sheet = [UInt8](repeating: 255, count: sheetW * sheetH * 4)
        for (row, (cx, cy)) in crops.enumerated() {
            for (col, src) in sources.enumerated() {
                let ox = col * (cw * zoom + gap), oy = row * (ch * zoom + gap)
                for y in 0..<(ch * zoom) {
                    for x in 0..<(cw * zoom) {
                        let s = ((cy + y / zoom) * w + cx + x / zoom) * 4
                        let d = ((oy + y) * sheetW + ox + x) * 4
                        sheet[d] = src[s]; sheet[d + 1] = src[s + 1]; sheet[d + 2] = src[s + 2]; sheet[d + 3] = 255
                    }
                }
            }
        }
        let url = try outputDir().appendingPathComponent("vq3_sheet_native_stretch_spatial_temporal.png")
        try EnergeticFlybyRenderTests.writePNG(sheet, sheetW, sheetH, url)
        print("[vq3] sheet → \(url.path)")
    }
}
