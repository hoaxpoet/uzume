// RenderPipeline+HDRProof — VQ.2's developer proof. Launched with `UZUME_HDR_PROOF=1`, every frame
// shows a test pattern (Shaders/HDRProof.metal) through a cinematic finish that opts into HDR,
// bloom on, in place of the scene — so the 4× highlight cap can be judged on an HDR display and
// compared with the HDR setting off. Never in the shipped roster: nothing but the environment
// variable reaches it, and it draws through the same seam (frame target → finish → present).

import Metal
@preconcurrency import MetalKit
import QuartzCore
import Shared

// MARK: - HDRProof

/// The proof's pipeline and its own finish (rebuilt when the drawable's format changes).
final class HDRProof {
    let pipeline: MTLRenderPipelineState
    var stage: FinishingStage
    let start = CACurrentMediaTime()

    init(pipeline: MTLRenderPipelineState, stage: FinishingStage) {
        self.pipeline = pipeline
        self.stage = stage
    }
}

extension RenderPipeline {

    /// `UZUME_HDR_PROOF=1` in the launch environment.
    static let hdrProofRequested = ProcessInfo.processInfo.environment["UZUME_HDR_PROOF"] == "1"

    /// Draw the proof instead of the scene when it was requested; false otherwise. Main thread.
    @MainActor
    func drawHDRProof(commandBuffer: MTLCommandBuffer, view: MTKView) -> Bool {
        guard Self.hdrProofRequested else { return false }
        guard let proof = hdrProofForCurrentOutput() else { return true }
        let saved = finishingStage
        finishingStage = proof.stage
        defer { finishingStage = saved }
        let render = renderSize(of: view)
        proof.stage.ensureFrameTarget(width: max(Int(render.width), 1), height: max(Int(render.height), 1))
        let current = view.window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1
        proof.stage.headroom = outputIsEDR ? HDROutput.headroom(current: current, reduceMotion: frameReduceMotion) : 1
        guard let target = instrumentedDrawable(from: view, commandBuffer: commandBuffer, site: "hdrProof") else {
            return true
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return true }
        var params = SIMD2<Float>(Float(CACurrentMediaTime() - proof.start),
                                  Float(target.texture.width) / Float(max(target.texture.height, 1)))
        encoder.setRenderPipelineState(proof.pipeline)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        instrumentedPresent(target, on: commandBuffer)
        return true
    }

    /// The proof, built on first use and its finish rebuilt for the drawable's current format.
    private func hdrProofForCurrentOutput() -> HDRProof? {
        func stage() -> FinishingStage? {
            try? FinishingStage(device: context.device,
                                library: rendererLibrary,
                                outputFormat: drawableFormat,
                                spec: FinishSpec(mode: .cinematic, hdr: true),
                                budget: context.renderTargetBudget)
        }
        if let proof = hdrProof {
            if proof.stage.hdrOutput != outputIsEDR, let rebuilt = stage() { proof.stage = rebuilt }
            return proof
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.label = "hdr_proof"
        desc.vertexFunction = rendererLibrary.makeFunction(name: "fullscreen_vertex")
        desc.fragmentFunction = rendererLibrary.makeFunction(name: "hdr_proof_fragment")
        desc.colorAttachments[0].pixelFormat = FinishSpec.cinematicFrameTargetFormat
        guard let finish = stage(),
              let pipeline = try? context.device.makeRenderPipelineState(descriptor: desc) else { return nil }
        hdrProof = HDRProof(pipeline: pipeline, stage: finish)
        return hdrProof
    }
}
