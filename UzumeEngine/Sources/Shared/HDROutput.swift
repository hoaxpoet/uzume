// HDROutput — when Uzume outputs HDR, and how bright it may go (VQ.2, Phase VQ).
//
// HDR is on when the user's setting is on (default on, D-264) AND the window's display can EVER
// show more than SDR white: its POTENTIAL headroom > 1. Current headroom alone is the wrong test —
// a built-in SDR panel reports current headroom > 1 while dimmed.
//
// On HDR the drawable is linear `.rgba16Float` in the display's OWN colour space, extended. Today's
// SDR layer does no colour matching (`CAMetalLayer.colorspace` nil): the display shows the bytes in
// its own primaries. The extended-linearized display space keeps exactly that, so a legacy scene
// (sRGB-decoded to linear by the present step's copy) looks the same as on SDR, and SDR white is
// 1.0. Only a cinematic scene that opts in (`FinishSpec.hdr`) puts light above 1.0.
//
// How bright: Matt 2026-10-29 — highlights up to 4× SDR white (or the display's current headroom if
// lower); no ninth of the screen may average above SDR white (the finish's regional cap), so a
// full-screen flash is never brighter than on SDR. Reduce Motion / Dim Flashing Lights: no highlights.

import CoreGraphics
import Metal

// MARK: - HDROutput

/// The HDR output rule (VQ.2).
public enum HDROutput {

    /// Highest highlight, in SDR-white units (Matt, 2026-10-29: "highlights pop, the picture stays").
    public static let peakCap: Float = 4

    /// The drawable's format on HDR.
    public static let drawableFormat: MTLPixelFormat = .rgba16Float

    /// Whether to output HDR: the setting is on and the display can ever exceed SDR white.
    public static func isActive(settingOn: Bool, potentialHeadroom: CGFloat) -> Bool {
        settingOn && potentialHeadroom > 1
    }

    /// The finish's headroom: the display's current headroom, never below 1, capped at `peakCap`;
    /// 1 (no highlights) under Reduce Motion / Dim Flashing Lights.
    public static func headroom(current: CGFloat, reduceMotion: Bool) -> Float {
        reduceMotion ? 1 : min(max(Float(current), 1), peakCap)
    }

    /// The EDR layer's colour space: `display`'s own, extended and linear — so the colours are the
    /// ones the unmatched SDR layer shows today. Extended linear sRGB when the display has none.
    public static func colorSpace(display: CGColorSpace?) -> CGColorSpace? {
        display.flatMap(CGColorSpaceCreateExtendedLinearized)
            ?? CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
    }
}
