// RayMarchTemporalEntryTests — VQ.3a: a reconstructing ray-march scene's first frames, timed one at a time.
//
// UPSCALE_ENTRY=<case> (one case per process — MetalFX state is process-wide; quote Release only):
//   stretch — Lumen Mosaic at its tier-1 march, no upscale (control);
//   lazy    — temporal, nothing built ahead;
//   warm    — temporal after `RayMarchTemporal.warmUp` (production's `prepareRayMarchUpscale`);
//   mfx     — MetalFX alone on a fresh scaler, inputs from a rendered frame;
//   probe   — the root cause: first GPU touch of freshly allocated memory, and a fresh scaler by size.
// Measured (Release, M2 Pro, frame 1 GPU ms): lazy 155 / 28 / 184 / 36 / 87 / 29 over six processes;
// unwarmed-but-unwaited warm-up 36; waited 12–30 over eight (steady 11–13 one at a time). 253 MiB of
// fresh targets cleared 143 ms the first time, 0.2 ms the next.

import Foundation
import Metal
import QuartzCore
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("RayMarch temporal scene entry (VQ.3a)", .serialized)
@MainActor
struct RayMarchTemporalEntryTests {

    static var entryCase: String? { ProcessInfo.processInfo.environment["UPSCALE_ENTRY"] }

    @Test("First frames' GPU ms at Lumen Mosaic's entry, 2560×1440 → 4K (UPSCALE_ENTRY=<case>)")
    func entryFrames() throws {
        guard let entry = Self.entryCase else { return }
        let ctx = try MetalContext()
        func row(_ label: String, _ ms: [Double]) {
            print("[vq3a-entry] \(entry) \(label): " + ms.map { String(format: "%.1f", $0) }.joined(separator: " "))
        }
        let mode: RayMarchUpscaleRig.Mode = entry == "stretch" ? .stretch(canvasW: 2560, canvasH: 1440) : .temporal
        let rig = try RayMarchUpscaleRig(scene: .lumenMosaic, mode: mode, outW: 3840, outH: 2160,
                                         marchW: 2560, marchH: 1440, context: ctx)
        switch entry {
        case "warm":
            let temporal = try #require(rig.temporal)
            let lit = try #require(rig.pipeline.litTexture)
            #expect(temporal.prepare(inputWidth: 2560, inputHeight: 1440, outputWidth: 3840, outputHeight: 2160))
            row("warm-up wall ms", [temporal.warmUp(lit: lit, queue: ctx.commandQueue)])
        case "mfx":
            for frame in 0..<3 { try rig.frame(time: Float(frame) / 60) }
            let lit = try #require(rig.pipeline.litTexture)
            let inputs = try #require(rig.temporal?.lastInputs(color: lit))
            let fresh = DirectTemporalReconstructor(device: ctx.device, spec: .init(motionVectors: .reprojected),
                                                    budget: nil, externalInputs: true)
            #expect(fresh.prepare(inputWidth: 2560, inputHeight: 1440, outputWidth: 3840, outputHeight: 2160))
            var ms: [Double] = []
            for _ in 0..<8 {
                let cb = try #require(ctx.commandQueue.makeCommandBuffer())
                _ = fresh.encodeUpscale(commandBuffer: cb, inputs: inputs)
                fresh.advance()
                cb.commit()
                cb.waitUntilCompleted()
                ms.append((cb.gpuEndTime - cb.gpuStartTime) * 1000)
            }
            row("upscale alone", ms)
            return
        case "apply":
            // Wall ms of each piece of `prepareRayMarchUpscale`, on a fresh RayMarchTemporal, three times.
            let lit = try #require(rig.pipeline.litTexture)
            let lib = try ShaderLibrary(context: ctx)
            for _ in 0..<3 {
                var t = CACurrentMediaTime()
                func lap() -> Double { let now = CACurrentMediaTime(); defer { t = now }; return (now - t) * 1000 }
                let temporal = try RayMarchTemporal(device: ctx.device, library: lib.library,
                                                    spec: .init(motionVectors: .reprojected, reactiveMask: true),
                                                    budget: nil)
                let made = lap()
                #expect(temporal.prepare(inputWidth: 2560, inputHeight: 1440, outputWidth: 3840, outputHeight: 2160))
                let prepared = lap()
                let warm = temporal.warmUp(lit: lit, queue: ctx.commandQueue)
                row("init / prepare (scaler + targets) / warm-up ms", [made, prepared, warm])
            }
            return
        case "probe":
            for frame in 0..<3 { try rig.frame(time: Float(frame) / 60) }
            let lit = try #require(rig.pipeline.litTexture)
            let inputs = try #require(rig.temporal?.lastInputs(color: lit))
            func timedCB(_ body: (MTLCommandBuffer) -> Void) throws -> Double {
                let cb = try #require(ctx.commandQueue.makeCommandBuffer())
                body(cb)
                cb.commit()
                cb.waitUntilCompleted()
                return (cb.gpuEndTime - cb.gpuStartTime) * 1000
            }
            // (1) First touch of plain private memory: 8 fresh 4K rgba16Float targets cleared, twice.
            let descs = (0..<8).map { _ -> MTLTextureDescriptor in
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 3840, height: 2160,
                                                                 mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]
                d.storageMode = .private
                return d
            }
            let fresh = descs.compactMap { ctx.device.makeTexture(descriptor: $0) }
            func clearAll(_ cb: MTLCommandBuffer) {
                for tex in fresh {
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = tex
                    pass.colorAttachments[0].loadAction = .clear
                    pass.colorAttachments[0].storeAction = .store
                    cb.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
                }
            }
            row("clear 8×4K fresh (253 MiB), 1st / 2nd", [try timedCB(clearAll), try timedCB(clearAll)])
            // (2) A fresh scaler's first encodes, by size, with the allocation seen before / after.
            for (inSize, outSize) in [((640, 360), (1280, 720)), ((1280, 720), (2560, 1440)),
                                      ((2560, 1440), (3840, 2160))] {
                let recon = DirectTemporalReconstructor(device: ctx.device, spec: .init(motionVectors: .reprojected),
                                                        budget: nil, externalInputs: true)
                let before = ctx.device.currentAllocatedSize
                #expect(recon.prepare(inputWidth: inSize.0, inputHeight: inSize.1,
                                      outputWidth: outSize.0, outputHeight: outSize.1))
                let made = ctx.device.currentAllocatedSize
                var ms: [Double] = []
                for _ in 0..<3 {
                    ms.append(try timedCB { _ = recon.encodeUpscale(commandBuffer: $0, inputs: inputs); recon.advance() })
                }
                let after = ctx.device.currentAllocatedSize
                row("fresh scaler \(inSize.0)×\(inSize.1)→\(outSize.0)×\(outSize.1) "
                    + "alloc +\((made - before) >> 20) MiB at make, +\((after - made) >> 20) MiB at encode", ms)
            }
            return
        default: break
        }
        let frames = try (0..<10).map { try rig.frame(time: Float($0) / 60).gpuMs }
        row("frames", frames)
        // The governor's hard step-down is two frames over 50 ms GPU. No negative-control assert: in a test
        // process `lazy` spikes only when no freed pages are left to reuse (3 of 6 runs) — the live soak is
        // the deterministic proof (RUNBOOK §VQ.3a).
        let ceiling = Double(FrameBudgetManager.hardGPUCeilingMs)
        #expect(entry == "lazy" || frames.prefix(2).allSatisfy { $0 < ceiling }, "entry frames \(frames.prefix(2))")
    }
}
