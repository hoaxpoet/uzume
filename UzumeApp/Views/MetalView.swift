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
        let view = CappedMTKView(frame: .zero, device: context.device)
        // BR.6b (audit D4, decision 4): tier-1 Macs draw at most ~1440p-equivalent and the
        // compositor upscales. Unmeasurable on an M1 here, so the conservative default.
        if VisualizerEngine.detectDeviceTier(device: context.device) == .tier1 {
            view.maxDrawablePixels = CappedMTKView.tier1MaxPixels
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

// MARK: - CappedMTKView

/// An `MTKView` whose drawable never exceeds `maxDrawablePixels` (aspect kept); the window
/// compositor scales it up to the view. `nil` = native backing resolution (the MTKView default).
final class CappedMTKView: MTKView {

    /// About 2560×1440 — the tier-1 render budget (BR.6b).
    static let tier1MaxPixels: Double = 2560 * 1440

    /// Pixel ceiling for the drawable, or nil for native resolution.
    var maxDrawablePixels: Double? {
        didSet {
            autoResizeDrawable = maxDrawablePixels == nil
            applyCap()
        }
    }

    override func layout() {
        super.layout()
        applyCap()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyCap()
    }

    /// `backing` scaled down (never up) so width × height ≤ `maxPixels`, aspect preserved.
    static func cappedSize(_ backing: CGSize, maxPixels: Double) -> CGSize {
        let pixels = Double(backing.width * backing.height)
        guard pixels > maxPixels, pixels > 0 else { return backing }
        let scale = (maxPixels / pixels).squareRoot()
        return CGSize(width: (backing.width * scale).rounded(.down),
                      height: (backing.height * scale).rounded(.down))
    }

    private func applyCap() {
        guard let cap = maxDrawablePixels else { return }
        let target = Self.cappedSize(convertToBacking(bounds).size, maxPixels: cap)
        if target.width >= 1, target.height >= 1, target != drawableSize {
            drawableSize = target   // MTKView forwards this to drawableSizeWillChange
        }
    }
}
