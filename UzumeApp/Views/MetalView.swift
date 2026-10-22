// MetalView — NSViewRepresentable wrapping MTKView with RenderPipeline as delegate.

import MetalKit
import Renderer
import SwiftUI

// MARK: - MetalView

/// SwiftUI wrapper around `MTKView` for Metal rendering.
///
/// Bridges the Metal render pipeline into the SwiftUI view hierarchy.
/// The view draws continuously at the display refresh rate (60 or 120 Hz).
struct MetalView: NSViewRepresentable {

    /// Metal context providing device and pixel format.
    let context: MetalContext

    /// Render pipeline used as the MTKView delegate.
    let pipeline: RenderPipeline

    /// Creates and configures the underlying `MTKView`.
    func makeNSView(context nsViewContext: Context) -> MTKView {
        let view = PixelModeMTKView(frame: .zero, device: context.device)
        // BR.6b (audit D4, decision 4): tier-1 Macs render scenes at most ~1440p-equivalent.
        // MFX.2 / VQ amendment A4: the cap lives in the engine now (a render canvas stretched into
        // the drawable), so the drawable itself never changes size on a scene switch.
        if VisualizerEngine.detectDeviceTier(device: context.device) == .tier1 {
            pipeline.setRenderPixelCap(PixelModeMTKView.tier1MaxPixels)
        }
        view.colorPixelFormat = context.pixelFormat
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = pipeline

        // Draw at display refresh rate (60 or 120 Hz on ProMotion).
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        // Allow reading the drawable texture post-render. Required for the
        // SessionRecorder's blit-to-capture-texture path; without this, the
        // blit traps with "source texture is framebufferOnly" on first frame.
        // Minor cost: Metal cannot use tile memory optimizations for the
        // drawable. Acceptable at 60 fps on Apple Silicon.
        view.framebufferOnly = false

        // The render surface carries no semantic meaning for VoiceOver.
        view.setAccessibilityElement(false)

        return view
    }

    /// Updates the MTKView when SwiftUI state changes.
    func updateNSView(_ nsView: MTKView, context: Context) {
        // No dynamic SwiftUI state to push into the view yet.
    }
}

// MARK: - PixelModeMTKView

/// An `MTKView` whose drawable matches the display's PIXEL mode (`CGDisplayMode` pixel width ×
/// height), not the backing of a scaled "looks like" mode: on a 4K panel set to look like
/// 2560×1440 the backing is 5120×2880, 1.78× the panel's pixels, all of it thrown away by the
/// compositor. Sized from the view and the screen only, so it changes on a resize or a move to
/// another display and never on a scene switch (MFX.2, VQ amendment A4).
final class PixelModeMTKView: MTKView {

    /// About 2560×1440 — the tier-1 scene render budget (BR.6b), applied by the engine's canvas.
    static let tier1MaxPixels: Double = 2560 * 1440

    /// VQ.0 render soak / inventory only: force the drawable to this size whatever the window and
    /// display (the compositor scales it into the window). Main thread; nil in normal use.
    static var drawableOverride: CGSize? {
        didSet { NotificationCenter.default.post(name: drawableOverrideChanged, object: nil) }
    }
    static let drawableOverrideChanged = Notification.Name("io.uzume.drawableOverrideChanged")

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        autoResizeDrawable = false
        let center = NotificationCenter.default
        center.addObserver(forName: Self.drawableOverrideChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPixelMode() }
        }
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        autoResizeDrawable = false
    }

    override func layout() {
        super.layout()
        applyPixelMode()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyPixelMode()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPixelMode()
    }

    /// The drawable for a view whose backing is `viewBacking` on a display whose full backing is
    /// `displayBacking` and whose mode drives `displayPixels` panel pixels: the view's backing
    /// scaled by pixels ÷ backing, never above 1 (a native mode, or no display info, keeps the
    /// backing size).
    static func drawableSize(viewBacking: CGSize, displayPixels: CGSize, displayBacking: CGSize) -> CGSize {
        guard displayPixels.width > 0, displayBacking.width > 0 else { return viewBacking }
        let scale = min(displayPixels.width / displayBacking.width, 1)
        return CGSize(width: (viewBacking.width * scale).rounded(),
                      height: (viewBacking.height * scale).rounded())
    }

    private func applyPixelMode() {
        let backing = convertToBacking(bounds).size
        var target = backing
        if let screen = window?.screen,
           let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)) {
            let scale = screen.backingScaleFactor
            target = Self.drawableSize(
                viewBacking: backing,
                displayPixels: CGSize(width: mode.pixelWidth, height: mode.pixelHeight),
                displayBacking: CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale))
        }
        if let override = Self.drawableOverride { target = override }
        if target.width >= 1, target.height >= 1, target != drawableSize {
            drawableSize = target   // MTKView forwards this to drawableSizeWillChange
        }
    }
}
