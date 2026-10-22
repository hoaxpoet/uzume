// RenderPipeline+TemporalReconstruction — the MFX.2 branch of the direct path.
//
// A direct scene that declares `temporal_reconstruction` takes this branch instead of the
// full-res or NB.8 bilinear paths: its MRT fragment renders colour + depth + motion at
// `internal_scale × drawable` with a sub-pixel jitter (buffer(9)), `DirectTemporalReconstructor`
// rebuilds a drawable-sized image with MetalFX into its own output texture, and that is copied to
// the drawable. It writes the drawable itself, never the tier-1 render canvas (A4), and the
// drawable does not change size when this scene comes or goes. Every other scene never reaches
// this file.
//
// Order (VQ amendment A2): render (jittered) → temporal upscale → [finishing: VQ.1's bloom /
// tone map slots in on the scaler's output, before the copy] → present. Frame interpolation
// (task 5) is not here: it needs a present clock the main-thread MTKView loop does not have
// (A5) and lands with VQ.4a.

import Foundation
import Metal
import MetalKit
import Shared

extension RenderPipeline {

    // MARK: - Opt-in (applyPreset)

    /// Opt the active direct scene into temporal reconstruction, or pass nil to opt out. Called
    /// from `applyPreset` on every preset change (nil for every scene without the sidecar block).
    /// Allocates for the current drawable now, so the first frame does not. Main thread.
    public func setTemporalReconstruction(_ spec: TemporalReconstructionSpec?,
                                          pipeline: MTLRenderPipelineState?) {
        guard let spec, let pipeline else {
            temporalPipelineState = nil
            temporalReconstructor = nil
            temporalSummaryLock.withLock { temporalSummary = nil }
            return
        }
        temporalReconstructor = nil   // VQ.0: release the previous set before allocating
        let budget = context.renderTargetBudget
        let recon = DirectTemporalReconstructor(device: context.device, spec: spec, budget: budget)
        let size = presentationDrawableSize
        recon.prepare(outputWidth: Int(size.width), outputHeight: Int(size.height))
        temporalPipelineState = pipeline
        temporalReconstructor = recon
        temporalSummaryLock.withLock { temporalSummary = spec.internalScale }
    }

    /// True while the active scene reconstructs.
    public var isTemporallyReconstructing: Bool { temporalReconstructor != nil }

    /// Discard the reconstruction history — a cut the motion vectors cannot explain. Main thread.
    public func resetTemporalHistory() {
        temporalReconstructor?.reset()
    }

    // MARK: - Encode (view-free; tests drive this)

    /// Scene → internal MRT targets → MetalFX. Returns the drawable-sized image (or, without
    /// MetalFX, the internal colour for the caller to stretch); presenting is the caller's job,
    /// so the offline tests exercise exactly the production encode.
    func encodeTemporalReconstruction( // swiftlint:disable:this function_parameter_count
        commandBuffer: MTLCommandBuffer,
        outputWidth: Int,
        outputHeight: Int,
        features: inout FeatureVector,
        stems: StemFeatures,
        textOverlay: DynamicTextOverlay?
    ) -> MTLTexture? {
        guard let recon = temporalReconstructor, let mrt = temporalPipelineState,
              recon.prepare(outputWidth: outputWidth, outputHeight: outputHeight),
              let targets = recon.targets else { return nil }

        let pass = MTLRenderPassDescriptor()
        let clears: [(MTLTexture?, MTLClearColor)] = [
            (targets.color, MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)),
            (targets.depth, MTLClearColor(red: 1, green: 0, blue: 0, alpha: 0)),
            (targets.motion, MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)),
            (targets.reactive, MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)),
        ]
        for (index, (texture, clear)) in clears.enumerated() {
            guard let texture else { continue }
            pass.colorAttachments[index].texture = texture
            pass.colorAttachments[index].loadAction = .clear
            pass.colorAttachments[index].clearColor = clear
            pass.colorAttachments[index].storeAction = .store
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        // Particles are not drawn here: their single-target pipelines cannot join an MRT pass.
        encodePresetVisualization(
            into: encoder,
            activePipeline: mrt,
            features: &features,
            stems: stems,
            particles: nil,
            textOverlay: textOverlay,
            temporalFrame: recon.frameUniforms)
        encoder.endEncoding()

        let image = recon.encodeUpscale(commandBuffer: commandBuffer)
        recon.advance()
        return image ?? targets.color
    }

    // MARK: - Present (drawDirect's third branch)

    /// Encode, copy to the drawable and present. Returns false when the reconstructor could not
    /// run, so `drawDirect` falls back to its normal paths.
    @MainActor
    func drawDirectReconstructed(
        commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable,
        features: inout FeatureVector,
        stems: StemFeatures,
        textOverlay: DynamicTextOverlay?
    ) -> Bool {
        guard let image = encodeTemporalReconstruction(
            commandBuffer: commandBuffer,
            outputWidth: drawable.texture.width,
            outputHeight: drawable.texture.height,
            features: &features,
            stems: stems,
            textOverlay: textOverlay) else { return false }
        // VQ.1 seam: finishing (bloom, tone map) runs on `image` here, before the copy.
        copy(image, to: drawable.texture, commandBuffer: commandBuffer)
        instrumentedPresent(FrameTarget(texture: drawable.texture, drawable: drawable), on: commandBuffer)
        // The recorder locks its video to one frame size and skips any other (ARCHITECTURE
        // §Session recording). On a capped Mac every other scene records the canvas, so record this
        // one there too: the idle canvas gets a downscaled copy, only while something is recording.
        if onFrameRendered != nil, let canvas = canvasTexture {
            copy(image, to: canvas, commandBuffer: commandBuffer)
            presentedFrameTexture = canvas
        }
        return true
    }
}
