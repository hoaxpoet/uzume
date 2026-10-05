// NacreHueStateTests — BUG-179 regression: Nacre's harmony-set palette phase must not pop.
//
// Replays the love_rehab route_coverage fixture (real preview clip, production analysis
// chain) through `NacreHueState`. Near the consonance gate the fifths phase is near-random,
// the circular mean collapses and the pre-fix atan2 stepped up to 0.38 turns in one frame.
// Negative control: the pre-fix formula, replayed on the same frames, must pop.

import Testing
import Foundation
@testable import Renderer
@testable import PresetSessionReplay

// MARK: - NacreHueStateTests

@Suite("Nacre hue state (BUG-179)")
struct NacreHueStateTests {

    private let period: Float = 2 * .pi / 0.437   // nacrePalette's period, palette-seconds

    private func turns(_ delta: Float) -> Float { abs(remainder(delta, period)) / period }

    @Test("love_rehab: the palette never steps faster than the slew limit; the pre-fix formula pops")
    func loveRehabHasNoPop() throws {
        let base = try #require(Bundle.module.url(forResource: "route_coverage", withExtension: nil))
        let cols = try SessionColumnSeries.load(directory: base.appendingPathComponent("love_rehab"))
        func series(_ col: String) throws -> [Float] {
            try #require(cols.floatSeries(col), "missing \(col)").map { $0 ?? 0 }
        }
        let consonance = try series("tonal_consonance")
        let fifths = try series("tonal_phase_fifths")
        let dts = try series("deltaTime")

        var state = NacreHueState()
        var oldVec = SIMD2<Float>.zero, oldDrift: Float = 0   // pre-fix TONAL.3 round 2 math
        var prev: Float?, prevOld: Float?
        var maxExcess: Float = -.infinity, maxStep: Float = 0, maxOldStep: Float = 0
        for i in 0..<cols.frameCount {
            let gate = max(0, min(1, (consonance[i] - 0.05) / 0.03))
            let hue = state.step(tonalGate: gate, phaseFifths: fifths[i], deltaTime: dts[i])

            oldVec += (SIMD2(cos(fifths[i]), sin(fifths[i])) - oldVec) * 0.025
            oldDrift += dts[i] * (1.0 + (0.06 - 1.0) * gate)
            let old = atan2(oldVec.y, oldVec.x) / (2 * .pi) * 14.4 * gate + oldDrift

            if let prev, let prevOld {
                let step = turns(hue - prev)
                maxStep = max(maxStep, step)
                maxExcess = max(maxExcess, step - 0.25 * dts[i])
                maxOldStep = max(maxOldStep, turns(old - prevOld))
            }
            prev = hue; prevOld = old
        }
        print("BUG-179 love_rehab: max step fixed=\(maxStep) turns, pre-fix=\(maxOldStep) turns")
        #expect(maxOldStep > 0.2, "negative control: the fixture must exercise the pop")
        #expect(maxExcess <= 1e-4, "palette stepped faster than 0.25 turns/s")
    }

    @Test("A held clear key lands on the same colour as before the fix")
    func heldKeyKeepsItsColour() {
        var state = NacreHueState()
        let phase: Float = 1.7, dt: Float = 1.0 / 60
        var hue: Float = 0
        for _ in 0..<600 { hue = state.step(tonalGate: 1, phaseFifths: phase, deltaTime: dt) }
        // Pre-fix target for a settled key: anchor + the demoted clock (0.06 × 10 s). The
        // fix's ~0.3 s coherence ramp-in runs the clock at the faithful rate meanwhile, a
        // fixed ~0.014-turn (~5°) offset; anything near a real colour change fails.
        let target = phase / (2 * .pi) * 14.4 + 0.06 * 10
        #expect(turns(hue - target) < 0.02, "settled hue \(hue) vs pre-fix \(target)")
    }
}
