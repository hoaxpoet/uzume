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
// Order on screen (Apple, WWDC25 session 211): render → upscale (MFX.2 / VQ.3 temporal, or VQ.3
// spatial) → finish → frame interpolation (VQ.4a) → present. The upscale writes a texture, never
// the drawable, and runs once, to the drawable's size: a scene under `upscale: spatial` hands its
// smaller frame target (the tier-1 canvas, an NB.8 half-res target) to the present step, which runs
// MetalFX spatial BEFORE the finish — so bloom and dither happen at output size. `bilinear` (every
// shipped scene) is exactly the old present step: a hand-off or the canvas stretch.
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
        finishLUTURL = lutURL
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
                outputFormat: drawableFormat,
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

    /// Install the active scene's upscale (VQ.3), resolved from its sidecar at load
    /// (`UpscaleMode.resolve`). Always releases the previous scene's scaler (VQ.0: no MetalFX
    /// reservation outlives its scene); under `.spatial` the next one is built by the first frame
    /// that needs it. Main thread (`applyPreset`).
    public func setUpscale(_ mode: UpscaleMode) {
        upscaleMode = mode
        spatialUpscaler?.release()
        spatialUpscaler = nil
    }

    /// The active scene's upscale mode.
    public var activeUpscaleMode: UpscaleMode { upscaleMode }

    /// The spatial scaler while the active scene takes `.spatial` (built on first use), else nil.
    func spatialUpscalerIfActive() -> SpatialUpscaler? {
        guard upscaleMode == .spatial else { return nil }
        if spatialUpscaler == nil {
            spatialUpscaler = SpatialUpscaler(device: context.device, budget: context.renderTargetBudget)
        }
        return spatialUpscaler
    }

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

    /// The present step: [upscale →] finish `target.texture` into the drawable, record what reached
    /// the glass, present. Legacy + bilinear: a hand-off (no pass) or the canvas stretch, exactly as
    /// before VQ.1.
    @MainActor
    func instrumentedPresent(_ target: FrameTarget, on commandBuffer: MTLCommandBuffer) {
        let drawable = target.drawable
        if let finish = finishingStage {
            let image = presentUpscale(target.texture, to: drawable.texture, commandBuffer: commandBuffer)
            finish.encode(source: image, output: drawable.texture, commandBuffer: commandBuffer)
            presentedFrameTexture = drawable.texture
            recordAtCanvasSize(drawable.texture, commandBuffer: commandBuffer)
        } else {
            let image = encodeLegacyPresent(target.texture, into: drawable.texture, commandBuffer: commandBuffer)
            if image === canvasTexture {
                presentedFrameTexture = image   // the tier-1 stretch: the recorder reads the canvas
            } else {
                presentedFrameTexture = drawable.texture
                recordAtCanvasSize(drawable.texture, commandBuffer: commandBuffer)
            }
        }
        drawableLifecycleProbe.recordPresent(
            commandBufferID: ObjectIdentifier(commandBuffer as AnyObject),
            drawableID: ObjectIdentifier(drawable as AnyObject)
        )
        commandBuffer.present(drawable)
    }

    /// The legacy present step into `output` (the drawable): MetalFX spatial first when the scene
    /// takes it and `source` is smaller, then the hand-off — a bilinear copy unless `source` is
    /// `output` itself. Returns the image copied in (`source` itself under `.bilinear`).
    func encodeLegacyPresent(_ source: MTLTexture, into output: MTLTexture,
                             commandBuffer: MTLCommandBuffer) -> MTLTexture {
        let image = presentUpscale(source, to: output, commandBuffer: commandBuffer)
        if image !== output {
            copy(image, to: output, commandBuffer: commandBuffer)
        }
        return image
    }

    /// The upscale step (VQ.3): `source` itself unless the scene takes `.spatial` and `source` is
    /// smaller than `output`, then MetalFX spatial's `output`-sized image (or `source` again if the
    /// device or the budget declined — the caller then stretches as before).
    func presentUpscale(_ source: MTLTexture, to output: MTLTexture, commandBuffer: MTLCommandBuffer) -> MTLTexture {
        guard source.width < output.width || source.height < output.height,
              let spatial = spatialUpscalerIfActive() else { return source }
        return spatial.encode(source,
                              outputWidth: output.width,
                              outputHeight: output.height,
                              commandBuffer: commandBuffer) ?? source
    }

    /// The recorder locks its video to one frame size (the canvas on a capped Mac): a frame that
    /// reached the glass at drawable size is copied down to it, only while something records.
    func recordAtCanvasSize(_ frame: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard onFrameRendered != nil, let canvas = canvasTexture else { return }
        copy(frame, to: canvas, commandBuffer: commandBuffer)
        presentedFrameTexture = canvas
    }

    /// The texture an upscaling path writes at the drawable's size (its size is the MFX.2
    /// reconstruct path's output size): the drawable itself, or on HDR for a legacy scene the 8-bit
    /// `edrLegacyOutput` the present step converts into it (VQ.2).
    func outputTexture(of target: FrameTarget) -> MTLTexture {
        guard outputIsEDR, finishingStage == nil else { return target.drawable.texture }
        return edrLegacyOutputTexture(matching: target.drawable.texture) ?? target.drawable.texture
    }
}
