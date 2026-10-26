// DirectTemporalReconstructionTests — MFX.2 evidence for MetalFX temporal reconstruction on the
// `direct` path. Every render goes through the production encode
// (`RenderPipeline.encodeTemporalReconstruction`) or the production binding
// (`encodePresetVisualization` with the MRT pipeline `PresetLoader` built).
//
//   • syntheticMovingPattern (always) — task 1: a scrolling checker, reactive mask on, reconstructs
//     to a drawable-sized, non-degenerate image.
//   • jitterSequence (always) — Halton(2,3) in range, cycles, resets.
//   • proofSequence (MFX_PROOF=1) — task 4: the proof scene, internal 2560×1440 → 3840×2160 vs
//     native 3840×2160 vs bilinear stretch, 120 frames: mean |Δ|, gradient-energy ratio, ghost
//     trail behind the turning ring; writes the comparison sheet.
//   • jitterConvention (MFX_PROOF=1) — the static-scene test (A3): a frozen frame converges on
//     native, and only with the shipped jitter sign.
//   • motionClasses (MFX_PROOF=1) — still / pan / forward flight against a 2×2-supersampled reference.
//   • canvas tests (always) — VQ amendment A4: the drawable never changes on a scene switch.
//   • timing (MFX_TIMING=1) — task 6. Release only:
//     `swift test -c release --enable-testable-imports --filter DirectTemporalReconstruction`.

import Accelerate
import Foundation
import Metal
import MetalKit
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("DirectTemporalReconstruction (MFX.2)")
@MainActor
struct DirectTemporalReconstructionTests {

    private static var proofEnabled: Bool { ProcessInfo.processInfo.environment["MFX_PROOF"] == "1" }

    // MARK: - Task 1

    @Test("A scrolling pattern reconstructs to a drawable-sized, non-degenerate image")
    func syntheticMovingPattern() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let rig = try MFXProofRig(shader: MFXProofScene.scrollShader, sidecar: MFXProofScene.scrollSidecar,
                                  file: "MFXScroll", outW: 480, outH: 270)
        let recon = try #require(rig.reconstructor)
        #expect(recon.renderWidth == 320 && recon.renderHeight == 180, "2/3 internal scale")
        var image: MTLTexture?
        for frame in 0..<24 {
            image = try rig.reconstruct(time: Float(frame) / 60, dt: frame == 0 ? 0 : 1 / 60)
        }
        let output = try #require(image)
        if DirectTemporalReconstructor.isSupported(device: rig.context.device) {
            #expect(output.width == 480 && output.height == 270, "output is drawable-sized")
            #expect(recon.resetCount == 1, "history reset once (first frame), not per frame")
        }
        let luma = try rig.luma(try rig.display(output, slot: "out"))
        let mean = luma.reduce(0, +) / Float(luma.count)
        let variance = luma.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(luma.count)
        print(String(format: "[mfx2] scroll 320×180 → 480×270: mean %.3f, sd %.3f", mean, variance.squareRoot()))
        #expect(mean > 0.2 && mean < 0.8, "a checker averages mid-grey, not black or white")
        #expect(variance.squareRoot() > 0.2, "the checker survived: not a flat or smeared field")
    }

    @Test("Jitter is Halton(2,3) in ±0.5 px, cycles, and restarts on reset")
    func jitterSequence() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let recon = DirectTemporalReconstructor(device: device, spec: TemporalReconstructionSpec())
        var seen: [SIMD2<Float>] = []
        for _ in 0..<Int(DirectTemporalReconstructor.jitterPhases) {
            let j = recon.jitter
            #expect(abs(j.x) <= 0.5 && abs(j.y) <= 0.5)
            seen.append(j)
            recon.advance()
        }
        #expect(Set(seen.map { "\($0)" }).count == seen.count, "every phase distinct")
        #expect(recon.jitter == seen[0], "the sequence cycles")
        recon.advance()
        recon.reset()
        #expect(recon.jitter == seen[0], "reset restarts the sequence")
        #expect(recon.frameUniforms.reset == 1)
    }

    // MARK: - Task 4

    /// Five versions of one frame, as display luma.
    private struct Frame {
        let native: [Float], reference: [Float], recon: [Float], stretch: [Float], spatial: [Float]
    }

    private static func capture(_ rig: MFXProofRig, recon image: MTLTexture, time: Float, dt: Float,
                                keep: inout [String: MTLTexture]) throws -> Frame {
        let recon = try #require(rig.reconstructor)
        var unused: Double?
        let native = try rig.display(try rig.renderPlain(time: time, dt: dt, width: rig.outW, height: rig.outH,
                                                         gpuMs: &unused), slot: "native")
        let small = try rig.renderPlain(time: time, dt: dt, width: recon.renderWidth, height: recon.renderHeight,
                                        gpuMs: &unused)
        let stretch = try rig.display(small, slot: "stretch")
        let spatial = try rig.display(try rig.spatial(small), slot: "spatial")
        let reconstructed = try rig.display(image, slot: "recon")
        let reference = try rig.supersampled(time: time, dt: dt)
        keep = ["native": native, "reconstructed": reconstructed, "stretch": stretch, "spatial": spatial]
        return Frame(native: try rig.luma(native), reference: try rig.luma(reference),
                     recon: try rig.luma(reconstructed), stretch: try rig.luma(stretch), spatial: try rig.luma(spatial))
    }

    @Test("Proof scene: reconstructed vs native vs stretch at 4K (MFX_PROOF=1)")
    func proofSequence() throws {
        guard Self.proofEnabled else { return }
        let rig = try MFXProofRig(outW: 3840, outH: 2160)
        let recon = try #require(rig.reconstructor)
        try #require(DirectTemporalReconstructor.isSupported(device: rig.context.device))
        let dir = try Self.outputDir()
        let warmUp = 16, frames = 120, sheetFrame = 100
        var rows: [ProofMetrics] = []
        for frame in 0..<frames {
            let time = Float(frame) / 60, dt: Float = frame == 0 ? 0 : 1 / 60
            let reconImage = try rig.reconstruct(time: time, dt: dt)
            guard frame >= warmUp else { continue }
            var keep: [String: MTLTexture] = [:]
            let f = try Self.capture(rig, recon: reconImage, time: time, dt: dt, keep: &keep)
            let m = ProofMetrics.measure(f.native, f.reference, f.recon, f.stretch, f.spatial, width: 3840, height: 2160)
            rows.append(m)
            print("[mfx2-proof] frame \(frame)  " + m.line)
            if frame == sheetFrame {
                let order = ["native", "reconstructed", "stretch", "spatial"]
                try Self.writeSheet(rig: rig, columns: order.compactMap { keep[$0] },
                                    url: dir.appendingPathComponent("mfx2_sheet_native_recon_stretch_spatial.png"))
                for name in order {
                    guard let tex = keep[name] else { continue }
                    try EnergeticFlybyRenderTests.writePNG(rig.bgra(tex), 3840, 2160,
                                                          dir.appendingPathComponent("mfx2_f\(frame)_\(name).png"))
                }
            }
        }
        let mean = ProofMetrics.mean(rows)
        let ghostMax = rows.map(\.ghostRecon).max() ?? 1
        print("[mfx2-proof] MEAN over \(rows.count) frames  " + mean.line)
        print(String(format: "[mfx2-proof] ghost max %.4f%% (threshold %.2f%%); flat pixels in the ring disc ≈ %d",
                     ghostMax * 100, ProofMetrics.ghostThreshold * 100, rows.last?.flatPixels ?? 0))
        print("[mfx2-proof] encodes \(recon.encodeCount), resets \(recon.resetCount); output → \(dir.path)")
        #expect(recon.resetCount == 1)
        #expect((rows.last?.flatPixels ?? 0) > 1000, "the ghost check has pixels to look at")
        #expect(ghostMax < ProofMetrics.ghostThreshold, "no ghost trail behind the turning ring")
    }

    /// The finding that shapes EFB.4: how much MetalFX keeps depends on how the WHOLE frame moves.
    /// Gate: with the camera still (only the ring turns) reconstruction must beat the stretch —
    /// if it does not, the wiring is wrong. The two moving-camera classes are measured and reported.
    @Test("Motion classes: still / pan / forward flight vs a supersampled reference (MFX_PROOF=1)")
    func motionClasses() throws {
        guard Self.proofEnabled else { return }
        var still: ProofMetrics?
        for (label, mode) in [("camera still, ring turns", Float(2)), ("sideways pan", 1), ("forward flight", 0)] {
            let rig = try MFXProofRig(outW: 1920, outH: 1080)
            rig.cameraMode = mode
            var image: MTLTexture?
            var time: Float = 2
            for frame in 0..<60 {
                time = 2 + Float(frame) / 60
                image = try rig.reconstruct(time: time, dt: frame == 0 ? 0 : 1 / 60)
            }
            var keep: [String: MTLTexture] = [:]
            let f = try Self.capture(rig, recon: try #require(image), time: time, dt: 1 / 60, keep: &keep)
            let m = ProofMetrics.measure(f.native, f.reference, f.recon, f.stretch, f.spatial, width: 1920, height: 1080)
            print("[mfx2-motion] \(label): " + m.line)
            if mode == 2 { still = m }
        }
        let m = try #require(still)
        #expect(m.refDiffRecon < m.refDiffStretch, "camera still: reconstruction is closer to the reference")
        #expect(m.refGradRecon > m.refGradStretch, "camera still: reconstruction keeps more edge detail")
    }

    @Test("Jitter sign: MetalFX converges on native only with the right sign (MFX_PROOF=1)")
    func jitterConvention() throws {
        guard Self.proofEnabled else { return }
        var result: [Float: Double] = [:]
        for sign: Float in [1, -1] {
            let rig = try MFXProofRig(outW: 1920, outH: 1080)
            let recon = try #require(rig.reconstructor)
            recon.jitterSign = sign
            var image: MTLTexture?
            for _ in 0..<48 { image = try rig.reconstruct(time: 2, dt: 0) }   // a still frame
            var unused: Double?
            let native = try rig.luma(try rig.display(try rig.renderPlain(time: 2, dt: 0, width: 1920, height: 1080,
                                                                          gpuMs: &unused), slot: "n"))
            let out = try rig.luma(try rig.display(try #require(image), slot: "r"))
            result[sign] = ProofMetrics.meanAbs(native, out)
            print(String(format: "[mfx2-jitter] sign %+.0f: still-frame |Δ| vs native %.5f", sign, result[sign] ?? 0))
        }
        let chosen = DirectTemporalReconstructor(device: MTLCreateSystemDefaultDevice()!,   // swiftlint:disable:this force_unwrapping
                                                 spec: TemporalReconstructionSpec()).jitterSign
        #expect((result[chosen] ?? 1) < (result[-chosen] ?? 0), "the shipped sign is the better one")
    }

    // MARK: - Task 3 (VQ amendment A4)

    @Test("Render size: tier-1 cap shrinks, never grows; no cap = drawable")
    func renderSizePolicy() {
        let uhd = CGSize(width: 3840, height: 2160), hd = CGSize(width: 1920, height: 1080)
        let cap = 2560.0 * 1440.0
        #expect(RenderPipeline.renderSize(drawable: uhd, pixelCap: cap) == CGSize(width: 2560, height: 1440))
        #expect(RenderPipeline.renderSize(drawable: hd, pixelCap: cap) == hd)
        #expect(RenderPipeline.renderSize(drawable: uhd, pixelCap: nil) == uhd)
    }

    @Test("A reconstructing ↔ non-reconstructing switch reallocates neither the drawable nor the canvas")
    func sceneSwitchKeepsDrawable() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let rig = try MFXProofRig(outW: 480, outH: 270)
        let pipe = rig.pipeline
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 960, height: 540), device: rig.context.device)
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 3840, height: 2160)
        pipe.setRenderPixelCap(2560 * 1440)
        pipe.mtkView(view, drawableSizeWillChange: view.drawableSize)
        let canvas = try #require(pipe.canvasTexture)
        #expect(canvas.width == 2560 && canvas.height == 1440, "non-reconstructing scenes render at the cap")
        for round in 0..<3 {
            pipe.setTemporalReconstruction(rig.preset.descriptor.temporalReconstruction,
                                           pipeline: rig.preset.temporalPipelineState)
            #expect(pipe.temporalReconstructor?.outputWidth == 3840, "reconstruction targets the drawable (\(round))")
            pipe.setTemporalReconstruction(nil, pipeline: nil)
            #expect(pipe.canvasTexture === canvas, "canvas untouched by the switch (\(round))")
            #expect(view.drawableSize == CGSize(width: 3840, height: 2160), "drawable untouched (\(round))")
            #expect(pipe.mvWarpDrawableSize == CGSize(width: 2560, height: 1440))
        }
    }

    // MARK: - Task 6

    @Test("GPU time: native 4K vs 1440p + reconstruction (MFX_TIMING=1)")
    func timing() throws {
        guard ProcessInfo.processInfo.environment["MFX_TIMING"] == "1" else { return }
        #if DEBUG
        print("[mfx2-timing] WARNING: Debug build — numbers are not quotable (CLAUDE.md)")
        #endif
        let rig = try MFXProofRig(outW: 3840, outH: 2160)
        let recon = try #require(rig.reconstructor)
        let frames = 130, skip = 10
        var native: [Double] = [], internalRender: [Double] = [], upscale: [Double] = [], total: [Double] = []
        for frame in 0..<frames {
            let time = Float(frame) / 30, dt: Float = frame == 0 ? 0 : 1 / 30
            var ms: Double?
            _ = try rig.renderPlain(time: time, dt: dt, width: 3840, height: 2160, gpuMs: &ms)
            if frame >= skip, let ms { native.append(ms) }

            // The production encode, split one stage per command buffer so each is timed alone.
            let stages = try Self.timedReconstruct(rig: rig, recon: recon, time: time, dt: dt)
            if frame >= skip {
                internalRender.append(stages.render)
                upscale.append(stages.upscale)
                total.append(stages.render + stages.upscale)
            }
        }
        func line(_ label: String, _ v: [Double]) {
            let s = v.sorted()
            guard !s.isEmpty else { print("[mfx2-timing] \(label): n/a"); return }
            print(String(format: "[mfx2-timing] %@: p50 %.2f ms, p95 %.2f ms (n=%d)", label,
                         s[s.count / 2], s[min(Int(Double(s.count) * 0.95), s.count - 1)], s.count))
        }
        print("[mfx2-timing] device \(rig.context.device.name)")
        line("native 3840×2160 scene", native)
        line("internal \(recon.renderWidth)×\(recon.renderHeight) scene (jittered)", internalRender)
        line("MetalFX temporal upscale alone", upscale)
        line("reconstructed total (scene + upscale)", total)
    }

    // MARK: - Helpers

    private static func timedReconstruct(rig: MFXProofRig, recon: DirectTemporalReconstructor,
                                         time: Float, dt: Float) throws
        -> (render: Double, upscale: Double) {
        guard recon.prepare(outputWidth: rig.outW, outputHeight: rig.outH), let targets = recon.targets,
              let mrt = rig.preset.temporalPipelineState else { throw MFXProofError.noPipeline }
        func run(_ body: (MTLCommandBuffer) throws -> Bool) throws -> Double? {
            guard let cb = rig.context.commandQueue.makeCommandBuffer() else { throw MFXProofError.gpu("cb") }
            guard try body(cb) else { return nil }
            cb.commit()
            cb.waitUntilCompleted()
            return cb.gpuEndTime > cb.gpuStartTime ? (cb.gpuEndTime - cb.gpuStartTime) * 1000 : nil
        }
        let render = try run { cb in
            let pass = MTLRenderPassDescriptor()
            for (i, tex) in [targets.color, targets.depth, targets.motion].enumerated() {
                pass.colorAttachments[i].texture = tex
                pass.colorAttachments[i].loadAction = .clear
                pass.colorAttachments[i].storeAction = .store
            }
            guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return false }
            var fv = MFXProofRig.features(time: time, dt: dt)
            rig.pipeline.encodePresetVisualization(into: enc, activePipeline: mrt, features: &fv, stems: .zero,
                                                   particles: nil, textOverlay: nil,
                                                   temporalFrame: recon.frameUniforms)
            enc.endEncoding()
            return true
        } ?? 0
        let upscale = try run { recon.encodeUpscale(commandBuffer: $0) != nil } ?? 0
        recon.advance()
        return (render, upscale)
    }

    private static func outputDir() throws -> URL {
        let root = ProcessInfo.processInfo.environment["MFX_OUT"] ?? "/tmp/uzume_visual/mfx2"
        let url = URL(fileURLWithPath: root)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A presented frame at 1920×1080 (bilinear from 4K) for the motion gate.
    private static func writeFrame(rig: MFXProofRig, _ tex: MTLTexture, _ dir: URL, _ index: inout Int) throws {
        let small = try rig.display(tex, slot: "seq", width: 1920, height: 1080)
        try EnergeticFlybyRenderTests.writePNG(rig.bgra(small), 1920, 1080,
                                              dir.appendingPathComponent(String(format: "mfx_proof_seq_%04d.png", index)))
        index += 1
    }

    /// Two 480×270 crops (ring hub + far lattice at the centre; the ring's right edge), 1:1 pixels
    /// shown at 2× nearest-neighbour, one column per texture in `columns` order.
    private static func writeSheet(rig: MFXProofRig, columns: [MTLTexture], url: URL) throws {
        let w = 3840, cw = 480, ch = 270, zoom = 2, gap = 8
        let crops = [(1920 - cw / 2, 1080 - ch / 2), (1920 + 300, 1080 - ch / 2)]
        let sources = columns.map { rig.bgra($0) }
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
        try EnergeticFlybyRenderTests.writePNG(sheet, sheetW, sheetH, url)
    }
}

// MARK: - ProofMetrics

/// One frame of the comparison. "vs native" is the prompt's measure; native is one sample per
/// pixel, so its edges carry aliasing and its gradient energy is inflated (~1.5× the reference).
/// "vs reference" uses the 2×2-supersampled frame — what an anti-aliased native would look like.
struct ProofMetrics {
    var diffRecon = 0.0, diffStretch = 0.0, diffSpatial = 0.0
    var gradRecon = 0.0, gradStretch = 0.0, gradSpatial = 0.0
    var refDiffRecon = 0.0, refDiffStretch = 0.0, refDiffSpatial = 0.0
    var refGradRecon = 0.0, refGradStretch = 0.0, refGradSpatial = 0.0, refGradNative = 0.0
    /// Fraction of locally flat native pixels in the ring's disc that the reconstruction gets badly
    /// wrong: edge softening cannot explain those, a trail can.
    var ghostRecon = 0.0
    var flatPixels = 0

    /// Stated before measuring: a trail is visible long before it covers 0.5 % of the flat disc.
    static let ghostThreshold = 0.005

    var line: String {
        String(format: "vs native |Δ| recon %.4f stretch %.4f spatial %.4f, grad recon %.3f stretch %.3f spatial %.3f"
                   + " | vs reference |Δ| recon %.4f stretch %.4f spatial %.4f, grad recon %.3f stretch %.3f"
                   + " spatial %.3f native %.3f | ghost %.4f%%",
               diffRecon, diffStretch, diffSpatial, gradRecon, gradStretch, gradSpatial,
               refDiffRecon, refDiffStretch, refDiffSpatial, refGradRecon, refGradStretch, refGradSpatial,
               refGradNative, ghostRecon * 100)
    }

    // swiftlint:disable:next function_parameter_count
    static func measure(_ native: [Float], _ reference: [Float], _ recon: [Float], _ stretch: [Float],
                        _ spatial: [Float], width: Int, height: Int) -> ProofMetrics {
        var m = ProofMetrics()
        let gN = gradientEnergy(native, width: width), gR = gradientEnergy(reference, width: width)
        let gRecon = gradientEnergy(recon, width: width), gStretch = gradientEnergy(stretch, width: width)
        let gSpatial = gradientEnergy(spatial, width: width)
        m.diffRecon = meanAbs(native, recon)
        m.diffStretch = meanAbs(native, stretch)
        m.diffSpatial = meanAbs(native, spatial)
        m.gradRecon = gRecon / gN
        m.gradStretch = gStretch / gN
        m.gradSpatial = gSpatial / gN
        m.refDiffRecon = meanAbs(reference, recon)
        m.refDiffStretch = meanAbs(reference, stretch)
        m.refDiffSpatial = meanAbs(reference, spatial)
        m.refGradRecon = gRecon / gR
        m.refGradStretch = gStretch / gR
        m.refGradSpatial = gSpatial / gR
        m.refGradNative = gN / gR
        let flat = flatMask(native, width: width, height: height)
        m.flatPixels = flat.count
        m.ghostRecon = flat.isEmpty ? 0 : Double(flat.filter { abs(recon[$0] - native[$0]) > 0.12 }.count) / Double(flat.count)
        return m
    }

    static func mean(_ rows: [ProofMetrics]) -> ProofMetrics {
        let n = Double(max(rows.count, 1))
        func avg(_ key: KeyPath<ProofMetrics, Double>) -> Double { rows.map { $0[keyPath: key] }.reduce(0, +) / n }
        var m = ProofMetrics()
        m.diffRecon = avg(\.diffRecon); m.diffStretch = avg(\.diffStretch); m.diffSpatial = avg(\.diffSpatial)
        m.gradRecon = avg(\.gradRecon); m.gradStretch = avg(\.gradStretch); m.gradSpatial = avg(\.gradSpatial)
        m.refDiffRecon = avg(\.refDiffRecon); m.refDiffStretch = avg(\.refDiffStretch)
        m.refDiffSpatial = avg(\.refDiffSpatial)
        m.refGradRecon = avg(\.refGradRecon); m.refGradStretch = avg(\.refGradStretch)
        m.refGradSpatial = avg(\.refGradSpatial); m.refGradNative = avg(\.refGradNative)
        m.ghostRecon = avg(\.ghostRecon)
        return m
    }

    static func meanAbs(_ a: [Float], _ b: [Float]) -> Double {
        var diff = [Float](repeating: 0, count: a.count)
        vDSP_vsub(b, 1, a, 1, &diff, 1, vDSP_Length(a.count))
        var result: Float = 0
        vDSP_meamgv(diff, 1, &result, vDSP_Length(a.count))
        return Double(result)
    }

    /// Σ (horizontal + vertical neighbour differences)². Row wrap at the image edge is noise.
    static func gradientEnergy(_ a: [Float], width: Int) -> Double {
        var total = 0.0
        a.withUnsafeBufferPointer { p in
            guard let base = p.baseAddress else { return }
            for offset in [1, width] {
                let n = a.count - offset
                var diff = [Float](repeating: 0, count: n)
                vDSP_vsub(base, 1, base + offset, 1, &diff, 1, vDSP_Length(n))
                var energy: Float = 0
                vDSP_svesq(diff, 1, &energy, vDSP_Length(n))
                total += Double(energy)
            }
        }
        return total
    }

    /// Pixels inside the ring's disc (frame centre; radius from the ring's 0.82 extent at 3.5 units,
    /// 60° field of view) where native is flat: the 7×7 luma range is under 0.04.
    static func flatMask(_ native: [Float], width: Int, height: Int) -> [Int] {
        let radius = Int(0.82 / 3.5 / 0.57735 * Double(height) / 2)
        let pad = 3, side = 2 * (radius + pad) + 1
        let x0 = width / 2 - radius - pad, y0 = height / 2 - radius - pad
        var lo = [Float](repeating: 0, count: side * side), hi = lo
        for y in 0..<side {
            for x in 0..<side {
                var a: Float = 1, b: Float = 0
                for d in max(0, x - pad)...min(side - 1, x + pad) {
                    let v = native[(y0 + y) * width + x0 + d]
                    a = min(a, v)
                    b = max(b, v)
                }
                lo[y * side + x] = a
                hi[y * side + x] = b
            }
        }
        var mask: [Int] = []
        for y in pad..<(side - pad) {
            for x in pad..<(side - pad) {
                let dx = x - radius - pad, dy = y - radius - pad
                guard dx * dx + dy * dy <= radius * radius else { continue }
                var a: Float = 1, b: Float = 0
                for d in (y - pad)...(y + pad) {
                    a = min(a, lo[d * side + x])
                    b = max(b, hi[d * side + x])
                }
                if b - a < 0.04 { mask.append((y0 + y) * width + x0 + x) }
            }
        }
        return mask
    }
}

// MARK: - Sidecar + loader (task 2)

@Suite("DirectTemporalReconstructionSidecar (MFX.2)")
struct DirectTemporalReconstructionSidecarTests {

    private static func decode(_ block: String, passes: String = "\"direct\"") throws -> PresetDescriptor {
        let json = """
        {"name":"T","family":"geometric","passes":[\(passes)]\(block.isEmpty ? "" : ",\"temporal_reconstruction\":\(block)")}
        """
        return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    @Test func absentBlock_isNil() throws {
        #expect(try Self.decode("").temporalReconstruction == nil)
    }

    @Test func fullBlock_decodes() throws {
        let spec = try #require(try Self.decode("""
        {"internal_scale":0.75,"motion_vectors":"analytic","reactive_mask":true,
         "fov":50,"near":0.1,"far":40}
        """).temporalReconstruction)
        #expect(spec == TemporalReconstructionSpec(internalScale: 0.75, motionVectors: .analytic, reactiveMask: true,
                                                   fieldOfViewDegrees: 50, nearPlane: 0.1, farPlane: 40))
    }

    @Test func defaults_andClamp() throws {
        let spec = try #require(try Self.decode("{\"motion_vectors\":\"analytic\"}").temporalReconstruction)
        #expect(spec.internalScale == TemporalReconstructionSpec.defaultInternalScale)
        #expect(!spec.reactiveMask)
        let low = try #require(try Self.decode("{\"motion_vectors\":\"analytic\",\"internal_scale\":0.2}")
            .temporalReconstruction)
        #expect(low.internalScale == 0.5, "clamped: MetalFX upscales at most 2× here")
    }

    @Test func motionVectors_requiredAndAnalyticOnly() {
        #expect(throws: (any Error).self) { try Self.decode("{\"internal_scale\":0.75}") }
        #expect(throws: (any Error).self) { try Self.decode("{\"motion_vectors\":\"estimated\"}") }
    }

    @Test func block_onlyOnDirectOnlyScenes() {
        #expect(throws: (any Error).self) {
            try Self.decode("{\"motion_vectors\":\"analytic\"}", passes: "\"ray_march\"")
        }
        #expect(throws: (any Error).self) {
            try Self.decode("{\"motion_vectors\":\"analytic\"}", passes: "\"direct\",\"feedback\"")
        }
    }

    @Test @MainActor func loader_buildsMRTOnlyForOptedInScene() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let context = try MetalContext()
        let proof = try MFXProofScene.load(shader: MFXProofScene.shader, sidecar: MFXProofScene.sidecar,
                                           file: "MFXProof", context: context)
        #expect(proof.temporalPipelineState != nil, "opted-in scene gets the MRT pipeline")
        let builtIn = PresetLoader(device: context.device, pixelFormat: context.pixelFormat)
        #expect(!builtIn.presets.isEmpty)
        // EFB.4 (option B, Matt): Energetic Flyby kept the stretch, so no shipped scene declares the block.
        let optedIn = builtIn.presets.filter { $0.temporalPipelineState != nil }.map(\.descriptor.name)
        #expect(optedIn.isEmpty, "MRT pipelines built for \(optedIn)")
    }
}
