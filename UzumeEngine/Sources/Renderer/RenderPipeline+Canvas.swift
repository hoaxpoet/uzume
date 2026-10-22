// RenderPipeline+Canvas — the render canvas behind a fixed-size drawable (MFX.2, Phase VQ amendment A4).
//
// The app sizes the drawable once, to the display's pixel mode, and a scene switch never changes it.
// What varies per scene is the size scenes RENDER at. On a tier-1 Mac every scene that does not
// reconstruct still renders at the BR.6b capped size (≈2560×1440): render paths draw into this
// canvas instead of the drawable, and the present step stretches it bilinearly into the drawable —
// the stretch the window compositor used to do, so nothing looks different. A scene that
// reconstructs (MFX.2) bypasses the canvas and MetalFX writes the drawable at full size.
// Without a cap (tier 2), or when the drawable already fits, there is no canvas: paths draw the
// drawable directly, exactly as before.

import Metal
import MetalKit
import os.log
import Shared

private let logger = Logger(subsystem: "io.uzume.renderer", category: "RenderCanvas")

// MARK: - FrameTarget

/// What a render path draws into this frame: the canvas when one is active, else the drawable
/// itself. `instrumentedPresent` resolves the canvas into `drawable` before presenting it.
struct FrameTarget {
    let texture: MTLTexture
    let drawable: CAMetalDrawable
}

extension RenderPipeline {

    // MARK: - Policy

    /// Cap the pixel count scenes render at (BR.6b, tier 1), or nil to render at drawable size.
    /// Set once by the app, before the first frame. Main thread.
    public func setRenderPixelCap(_ cap: Double?) {
        guard cap != renderPixelCap else { return }
        renderPixelCap = cap
        // VQ.0: the render size changed, so the size-scaled set must follow — commit it like a resize.
        resizeLock.withLock {
            guard let committed = committedDrawableSize else { return }
            pendingResize = PendingResize(size: committed, since: -.infinity)
        }
    }

    /// `drawable` scaled down (never up) to at most `pixelCap` pixels, aspect kept, or `drawable`
    /// itself when there is no cap or it already fits.
    public static func renderSize(drawable: CGSize, pixelCap: Double?) -> CGSize {
        let pixels = Double(drawable.width * drawable.height)
        guard let cap = pixelCap, pixels > cap, pixels > 0 else { return drawable }
        let scale = (cap / pixels).squareRoot()
        return CGSize(width: (drawable.width * scale).rounded(.down),
                      height: (drawable.height * scale).rounded(.down))
    }

    /// The size scenes render at for this view's drawable.
    func renderSize(of view: MTKView) -> CGSize {
        // VQ.0: the committed size, which lags the drawable through a coalesced resize.
        let drawable = allocationDrawableSize ?? MainActor.assumeIsolated { view.drawableSize }
        return Self.renderSize(drawable: drawable, pixelCap: renderPixelCap)
    }

    /// The drawable's own size (what the reconstruct path writes), as last reported.
    var presentationDrawableSize: CGSize {
        mvWarpLock.withLock { presentationSize }
    }

    // MARK: - Canvas

    /// Match the canvas to `drawableSize`: allocate, resize or drop it; record the drawable size.
    /// Returns the render size. Main thread; cheap when nothing changed (called every frame too,
    /// because `drawableSizeWillChange` is not guaranteed to fire before the first draw).
    @discardableResult
    func updateCanvas(drawableSize: CGSize) -> CGSize {
        let render = Self.renderSize(drawable: drawableSize, pixelCap: renderPixelCap)
        mvWarpLock.withLock { presentationSize = drawableSize }
        guard render != drawableSize else {
            canvasTexture = nil
            return render
        }
        let width = max(Int(render.width), 1), height = max(Int(render.height), 1)
        if canvasTexture?.width == width, canvasTexture?.height == height { return render }
        canvasTexture = nil   // VQ.0: release before allocate
        let descriptor = context.sizeScaledDescriptor(width: width, height: height, storage: .private)
        let label = "render canvas (BR.6b cap, A4) \(width)×\(height)"
        canvasTexture = context.renderTargetBudget.makeTexture(owner: "canvas", label: label, descriptor: descriptor)
        logger.info("Render canvas \(width)×\(height) → drawable \(Int(drawableSize.width))×\(Int(drawableSize.height))")
        return render
    }

    /// This frame's target for `drawable`.
    func frameTarget(for drawable: CAMetalDrawable) -> FrameTarget {
        FrameTarget(texture: canvasTexture ?? drawable.texture, drawable: drawable)
    }

    /// A render pass on the canvas, set up like MTKView's own descriptor (clear to the view's clear
    /// colour, store). Nil when there is no canvas.
    func canvasRenderPassDescriptor(clearColor: MTLClearColor) -> MTLRenderPassDescriptor? {
        guard let canvas = canvasTexture else { return nil }
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = canvas
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = clearColor
        desc.colorAttachments[0].storeAction = .store
        return desc
    }

    /// Stretch the canvas into the drawable (bilinear). No-op when the target is the drawable.
    func resolveCanvas(_ target: FrameTarget, on commandBuffer: MTLCommandBuffer) {
        guard target.texture !== target.drawable.texture else { return }
        copy(target.texture, to: target.drawable.texture, commandBuffer: commandBuffer)
    }

    /// Full-screen copy, bilinear when the sizes differ.
    func copy(_ source: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(feedbackBlitPipelineState)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(feedbackSamplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }
}
