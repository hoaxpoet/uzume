// RenderPipeline+FrameSeam — the one seam between every render path and the screen (VQ.1).
//
// Three roles, each owned here and nowhere else:
//   - the FRAME TARGET (`FrameTarget.texture`): what a scene draws into. Legacy: the drawable
//     itself when it is the render size and nothing follows the finish (zero copies — identical by
//     construction), else the BR.6b canvas (A4). Cinematic: the finishing stage's `.rgba16Float`
//     target at the render size. Every path obtains it through `instrumentedRenderPassDescriptor` /
//     `instrumentedDrawable`; none touches the drawable (gated: FinishFormatMatchTests).
//   - the FINISHED IMAGE: what the finish writes. Nothing follows the finish yet, so it writes the
//     drawable; when VQ.4a's frame interpolator lands, the finish writes a budgeted texture and the
//     interpolator (which also needs the previous finished image) writes the drawable instead.
//   - the PRESENT STEP (`instrumentedPresent`): the only writer of the drawable — the legacy
//     hand-off (or the canvas stretch) or the cinematic finish — and where the recorder and the
//     flash analyzer read (`presentedFrameTexture`), so they see every frame that reaches the glass.
//
// Order on screen (Apple, WWDC25 session 211): render → temporal upscale (MFX.2) → finish →
// frame interpolation (VQ.4a) → present.
//
// HANG.1's lifecycle probe brackets every drawable request and present made here.

import Metal
@preconcurrency import MetalKit
import os.log
import Shared

private let frameSeamLogger = Logger(subsystem: "io.uzume.renderer", category: "FrameSeam")

// MARK: - FrameTarget

/// What a render path draws into this frame (the frame target) and the drawable the present step
/// will write. `instrumentedPresent` finishes `texture` into `drawable` and presents it.
struct FrameTarget {
    let texture: MTLTexture
    let drawable: CAMetalDrawable
}

// MARK: - Finish

extension RenderPipeline {

    /// Install the active scene's finish (VQ.1), from its sidecar `finish` block. `.legacy` — every
    /// shipped scene — removes the finishing stage: the scene's pixels reach the drawable unchanged.
    /// `lutURL` is the sidecar's `.cube` (a LUT that fails to load is logged and skipped). Main
    /// thread (`applyPreset`).
    public func setFinish(_ spec: FinishSpec, lutURL: URL? = nil) {
        finishingStage = nil   // VQ.0: release before allocate
        guard spec.mode == .cinematic else { return }
        var lut: MTLTexture?
        if let lutURL {
            do {
                lut = try FinishSpec.loadCubeLUT(url: lutURL, device: context.device)
            } catch {
                let reason = String(describing: error)
                let name = lutURL.lastPathComponent
                frameSeamLogger.error("Finish LUT \(name, privacy: .public): \(reason, privacy: .public)")
            }
        }
        do {
            let stage = try FinishingStage(
                device: context.device,
                library: rendererLibrary,
                outputFormat: context.pixelFormat,
                spec: spec,
                lut: lut,
                budget: context.renderTargetBudget)
            let render = Self.renderSize(drawable: presentationDrawableSize, pixelCap: renderPixelCap)
            stage.ensureFrameTarget(width: max(Int(render.width), 1), height: max(Int(render.height), 1))
            finishingStage = stage
        } catch {
            frameSeamLogger.error("Finishing stage failed to build: \(String(describing: error))")
        }
    }

    /// The active scene's finish mode.
    public var finishMode: FinishSpec.Mode { finishingStage == nil ? .legacy : .cinematic }

    /// The blit that draws a texture into a frame target of `format` (its pipeline must match it).
    func frameBlitPipeline(for format: MTLPixelFormat) -> MTLRenderPipelineState {
        format == FinishSpec.cinematicFrameTargetFormat ? hdrBlitPipelineState : feedbackBlitPipelineState
    }
}

// MARK: - Seam

extension RenderPipeline {

    /// This frame's target for `drawable`, or nil when a cinematic scene has no frame target (the
    /// budget refused it): the frame is skipped rather than drawn with mismatched formats.
    func frameTarget(for drawable: CAMetalDrawable) -> FrameTarget? {
        if let finish = finishingStage {
            return finish.frameTarget.map { FrameTarget(texture: $0, drawable: drawable) }
        }
        return FrameTarget(texture: canvasTexture ?? drawable.texture, drawable: drawable)
    }

    /// A render pass on an offscreen frame target (the finish's, or the canvas), set up like
    /// MTKView's own descriptor (clear to the view's clear colour, store). Nil when the frame
    /// target is the drawable.
    private func offscreenFrameTargetDescriptor(clearColor: MTLClearColor) -> MTLRenderPassDescriptor? {
        guard let texture = finishingStage?.frameTarget ?? canvasTexture else { return nil }
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = clearColor
        desc.colorAttachments[0].storeAction = .store
        return desc
    }

    /// Current HANG.1 lifecycle counters. Safe to read from the watchdog task.
    public func drawableLifecycleSnapshot() -> DrawableLifecycleSnapshot {
        drawableLifecycleProbe.snapshot(now: ProcessInfo.processInfo.systemUptime)
    }

    @MainActor
    func captureRenderedFrame(
        from view: MTKView,
        features: FeatureVector,
        commandBuffer: MTLCommandBuffer
    ) {
        // The frame the present step put on screen (or its canvas-sized copy while recording), so
        // the recorder and the flash analyzer see it.
        guard let hook = onFrameRendered,
              let texture = presentedFrameTexture ?? instrumentedDrawable(
                  from: view, commandBuffer: commandBuffer, site: "draw.captureHook")?.texture else { return }
        let stems = stemFeaturesLock.withLock { latestStemFeatures }
        hook(texture, features, stems, commandBuffer)
    }

    func recordDrawableLifecycleCompletion(
        commandBufferID: ObjectIdentifier,
        commandBuffer: MTLCommandBuffer
    ) {
        drawableLifecycleProbe.recordCompletion(
            commandBufferID: commandBufferID,
            succeeded: commandBuffer.status == .completed
        )
    }

    @MainActor
    func instrumentedRenderPassDescriptor(
        from view: MTKView,
        commandBuffer: MTLCommandBuffer,
        site: String
    ) -> MTLRenderPassDescriptor? {
        let commandBufferID = ObjectIdentifier(commandBuffer as AnyObject)
        drawableLifecycleProbe.beginRequest(
            commandBufferID: commandBufferID,
            kind: .renderPassDescriptor,
            site: site,
            now: ProcessInfo.processInfo.systemUptime
        )
        // An offscreen frame target when there is one; the drawable is acquired separately.
        // A cinematic scene without its frame target gets none (the frame is skipped).
        let descriptor = offscreenFrameTargetDescriptor(clearColor: view.clearColor)
            ?? (finishingStage == nil ? view.currentRenderPassDescriptor : nil)
        drawableLifecycleProbe.endRequest(
            commandBufferID: commandBufferID,
            kind: .renderPassDescriptor,
            resolved: descriptor != nil
        )
        return descriptor
    }

    @MainActor
    func instrumentedDrawable(
        from view: MTKView,
        commandBuffer: MTLCommandBuffer,
        site: String
    ) -> FrameTarget? {
        let commandBufferID = ObjectIdentifier(commandBuffer as AnyObject)
        drawableLifecycleProbe.beginRequest(
            commandBufferID: commandBufferID,
            kind: .drawable,
            site: site,
            now: ProcessInfo.processInfo.systemUptime
        )
        let drawable = view.currentDrawable
        drawableLifecycleProbe.endRequest(
            commandBufferID: commandBufferID,
            kind: .drawable,
            resolved: drawable != nil,
            drawableID: drawable.map { ObjectIdentifier($0 as AnyObject) }
        )
        return drawable.flatMap(frameTarget(for:))
    }

    /// The present step: finish `target.texture` into the drawable, record what reached the
    /// glass, present. Legacy: a hand-off (no pass) or the canvas stretch, exactly as before VQ.1.
    @MainActor
    func instrumentedPresent(_ target: FrameTarget, on commandBuffer: MTLCommandBuffer) {
        let drawable = target.drawable
        if let finish = finishingStage {
            finish.encode(source: target.texture, output: drawable.texture, commandBuffer: commandBuffer)
            presentedFrameTexture = drawable.texture
            // The recorder locks its video to one frame size (the canvas on a capped Mac); give it
            // the finished frame at that size, only while something is recording.
            if onFrameRendered != nil, let canvas = canvasTexture {
                copy(drawable.texture, to: canvas, commandBuffer: commandBuffer)
                presentedFrameTexture = canvas
            }
        } else {
            if target.texture !== drawable.texture {
                copy(target.texture, to: drawable.texture, commandBuffer: commandBuffer)
            }
            presentedFrameTexture = target.texture === canvasTexture ? target.texture : drawable.texture
        }
        drawableLifecycleProbe.recordPresent(
            commandBufferID: ObjectIdentifier(commandBuffer as AnyObject),
            drawableID: ObjectIdentifier(drawable as AnyObject)
        )
        commandBuffer.present(drawable)
    }

    /// The texture the present step writes (the drawable's): its size is the MFX.2 reconstruct
    /// path's output size.
    func outputTexture(of target: FrameTarget) -> MTLTexture { target.drawable.texture }
}
