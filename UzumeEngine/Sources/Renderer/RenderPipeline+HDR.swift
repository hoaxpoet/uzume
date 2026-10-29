// RenderPipeline+HDR — the drawable's dynamic range (VQ.2, Phase VQ; rule in Shared/HDROutput).
//
// Two formats, never confused: `context.pixelFormat` is the LEGACY FRAME FORMAT — a constant
// (`FinishSpec.legacyFrameTargetFormat`) that every legacy scene pipeline, the ray-march composite,
// `PostProcessChain` and the 8-bit blits compile for — and `drawableFormat` is what the drawable is
// right now: the same 8-bit sRGB on SDR, linear `.rgba16Float` on HDR. Only the finish's composite
// and the present step's copy write the drawable, and both pick their pipeline from the drawable's
// format, so switching it recompiles no scene (the BUG-061 class).
//
// On HDR a legacy scene keeps drawing 8-bit: into the canvas (allocated at full size on HDR too,
// `updateCanvas`), or — for a path that upscales straight to the drawable — into `edrLegacyOutput`.
// The present step's copy samples that sRGB target (the hardware decodes to linear) and writes the
// linear drawable, SDR white at 1.0: the same colours the SDR drawable shows.
//
// A format change is a display change (D-264): drain, rebuild the finish for the new output, then
// drain → release → allocate at the committed size (which re-charges the drawable pool at the new
// format's bytes).

import Metal
@preconcurrency import MetalKit
import os.log
import QuartzCore
import Shared

private let hdrLogger = Logger(subsystem: "io.uzume.renderer", category: "HDR")

extension RenderPipeline {

    /// The drawable's format now: `HDROutput.drawableFormat` on HDR, else the legacy frame format.
    var drawableFormat: MTLPixelFormat { outputIsEDR ? HDROutput.drawableFormat : context.pixelFormat }

    /// Whether the drawable is HDR (EDR).
    public var isOutputEDR: Bool { outputIsEDR }

    /// Put the drawable on HDR (`edr`) or SDR, in `displayColorSpace` (the window's screen's).
    /// Main thread, between frames. Re-sending the same state only refreshes the colour space (the
    /// window moved between two HDR displays).
    @MainActor
    public func setOutputEDR(_ edr: Bool, view: MTKView, displayColorSpace: CGColorSpace?) {
        view.colorspace = edr ? HDROutput.colorSpace(display: displayColorSpace) : nil
        guard edr != outputIsEDR else { return }
        drainFramesInFlight()
        outputIsEDR = edr
        view.colorPixelFormat = drawableFormat
        (view.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = edr
        if let spec = finishingStage?.spec { setFinish(spec, lutURL: finishLUTURL) }
        let size = allocationDrawableSize ?? view.drawableSize
        if size.width >= 1, size.height >= 1 {
            commitResize(to: size, view: view)
        }
        let format = String(describing: drawableFormat)
        hdrLogger.info("HDR output \(edr ? "on" : "off", privacy: .public): drawable \(format, privacy: .public)")
    }

    /// Each frame: the finish's headroom from the display's current headroom (it changes with
    /// brightness and with other HDR content on screen), for a scene that opts in; 1 otherwise.
    /// A legacy scene on HDR whose 8-bit target the budget refused falls back to SDR (it would
    /// otherwise have nothing it can draw into); the view re-tries HDR on the next display change.
    @MainActor
    func updateDynamicRange(view: MTKView) {
        if outputIsEDR, finishingStage == nil, canvasTexture == nil, allocationDrawableSize != nil {
            hdrLogger.error("HDR off: the 8-bit frame target was refused by the render budget")
            setOutputEDR(false, view: view, displayColorSpace: nil)
        }
        guard let finish = finishingStage else { return }
        guard outputIsEDR, finish.spec.hdr else {
            finish.headroom = 1
            return
        }
        let current = view.window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1
        finish.headroom = HDROutput.headroom(current: current, reduceMotion: frameReduceMotion)
    }

    /// The 8-bit drawable-size target a legacy upscaling path writes on HDR, allocated through the
    /// budget on first use (nil when refused: the caller gets the drawable and must check its format).
    func edrLegacyOutputTexture(matching drawable: MTLTexture) -> MTLTexture? {
        if let tex = edrLegacyOutput, tex.width == drawable.width, tex.height == drawable.height { return tex }
        edrLegacyOutput = nil   // VQ.0: release before allocate
        let descriptor = context.sizeScaledDescriptor(
            width: drawable.width,
            height: drawable.height,
            pixelFormat: FinishSpec.legacyFrameTargetFormat,
            storage: .private)
        let label = "HDR legacy output \(drawable.width)×\(drawable.height)"
        edrLegacyOutput = context.renderTargetBudget.makeTexture(owner: "hdr", label: label, descriptor: descriptor)
        return edrLegacyOutput
    }
}
