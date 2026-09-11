// MVWarpFeedbackFormatRegressionTests — BUG-125 live/replay format parity.
//
// ROOTCHOIR.3.1 declared linear bgra8Unorm feedback. PresetLoader and the replay
// harness honored it, but the live app used a display-name allowlist and fell back
// to the sRGB drawable format for Root Choir, producing a black live frame.

import Metal
import Presets
import Testing

@testable import UzumeApp

@Suite("mv_warp live feedback-format parity (BUG-125)")
struct MVWarpFeedbackFormatRegressionTests {

    @Test("linear sidecar override wins over the sRGB drawable format")
    func linearOverride() {
        #expect(mvWarpFeedbackFormat(.bgra8Unorm, drawableFormat: .bgra8Unorm_srgb) == .bgra8Unorm)
    }

    @Test("HDR sidecar override wins over the sRGB drawable format")
    func hdrOverride() {
        #expect(mvWarpFeedbackFormat(.rgba16Float, drawableFormat: .bgra8Unorm_srgb) == .rgba16Float)
    }

    @Test("an absent override preserves the drawable format")
    func defaultFormat() {
        #expect(mvWarpFeedbackFormat(nil, drawableFormat: .bgra8Unorm_srgb) == .bgra8Unorm_srgb)
    }
}
