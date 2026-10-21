// DrawablePixelModeTests — MFX.2 / VQ amendment A4: the drawable follows the display's PIXEL mode
// (not a scaled mode's backing), from the view and the screen only — never from the scene.

import CoreGraphics
import Testing
@testable import UzumeApp

struct DrawablePixelModeTests {

    private let uhd = CGSize(width: 3840, height: 2160)

    @Test func scaledMode_onA4KPanel_drawsThePanelsPixels() {
        // "Looks like 2560×1440" on a 4K panel: backing 5120×2880, panel 3840×2160.
        let backing = CGSize(width: 5120, height: 2880)
        #expect(PixelModeMTKView.drawableSize(viewBacking: backing, displayPixels: uhd, displayBacking: backing) == uhd)
    }

    @Test func windowedView_scalesByTheSameRatio() {
        let view = CGSize(width: 2560, height: 1440), display = CGSize(width: 5120, height: 2880)
        #expect(PixelModeMTKView.drawableSize(viewBacking: view, displayPixels: uhd, displayBacking: display)
                == CGSize(width: 1920, height: 1080))
    }

    @Test func nativeMode_keepsTheBacking() {
        #expect(PixelModeMTKView.drawableSize(viewBacking: uhd, displayPixels: uhd, displayBacking: uhd) == uhd)
    }

    @Test func missingDisplayInfo_keepsTheBacking() {
        #expect(PixelModeMTKView.drawableSize(viewBacking: uhd, displayPixels: .zero, displayBacking: .zero) == uhd)
    }
}
