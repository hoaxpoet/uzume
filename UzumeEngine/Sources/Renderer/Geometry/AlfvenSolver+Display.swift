// AlfvenSolver+Display — how the field is COLOURED, split from the solver for the
// 400-line lint ceiling.
//
// A coherent seam rather than an arbitrary cut: nothing here touches the physics, and
// everything here is a stand-in for a reduction film.py can do on the CPU and a fragment
// cannot (percentile auto-exposure, std(J), and the seam bloom that is still absent).
// Every constant is calibrated against a measurement, in DISPLAYED-LINEAR space — see
// `displayExposure` for the sRGB trap that invalidates raw byte comparisons.

import Foundation
import Metal
import simd
import Shared

/// Mirrors `AlfvenDisplayParams` in AlfvenSolver.metal. Layout is the GPU contract.
struct AlfvenDisplayParams {
    var exposure: Float
    var polarityScale: Float
    var hueCentre: Float
    var pad0: Float
}

extension AlfvenSolver {

    /// The drifting opponent centre at a given moment on the listener's clock.
    ///
    /// A raised cosine away from `displayHueCentre` and back: at t = 0 it is exactly the
    /// anchor, at the half period it reaches `anchor - displayHueSpan` (0.46, film.py's
    /// other end), with no discontinuity and no wrap. Both endpoints are the two ends
    /// annotated in `04_palette_opponent_drift.png`, so the traverse cannot wander outside
    /// the approved family.
    ///
    /// The fragment still opposes +/-0.30 about this centre, so what moves is WHICH
    /// complementary pair is on screen, not how complementary it is.
    func hueCentre(at time: Float) -> Float {
        let period = max(configuration.displayHuePeriodSeconds, 0.001)
        let phase = 2.0 * Float.pi * time / period
        let traverse = 0.5 * (1.0 - cos(phase))          // 0 at the anchor, 1 at the far end
        let shaped = pow(traverse, max(configuration.displayHueDwell, 0.01))
        return displayHueCentre - configuration.displayHueSpan * shaped
    }

    /// Draw the current field. `J` is what the fragment colours (§4); omega and psi are
    /// state and supply nothing visual on their own.
    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let displayPipeline else { return }
        var params = AlfvenDisplayParams(exposure: displayExposure,
                                         polarityScale: displayPolarityScale,
                                         hueCentre: hueCentre(at: features.time),
                                         pad0: 0)
        encoder.setRenderPipelineState(displayPipeline)
        encoder.setFragmentBytes(&params,
                                 length: MemoryLayout<AlfvenDisplayParams>.stride,
                                 index: 0)
        encoder.setFragmentTexture(stateTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
