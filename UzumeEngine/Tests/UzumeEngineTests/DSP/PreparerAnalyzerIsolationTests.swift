// PreparerAnalyzerIsolationTests — BR.9 / audit C3, G3: why background preparation must have its
// own StemAnalyzer. The analyzer is stateful (AGC, deviation EMAs). Pushing another song's
// ~430 preparation frames through the LIVE instance moves the live drivers; a separate
// instance leaves them bit-identical.

import Foundation
import Testing
@testable import DSP
@testable import Shared

@Suite("Background preparation leaves the live stem drivers untouched (BR.9)")
struct PreparerAnalyzerIsolationTests {

    /// Four 1024-sample stem windows for frame `i` of a song whose loudness is `gain`.
    private func windows(_ i: Int, gain: Float, pitch: Float) -> [[Float]] {
        (0..<4).map { stem in
            (0..<1024).map { n in
                let t = Float(i * 1024 + n) / 44_100
                let beat: Float = (i % 30) < 3 ? 1 : 0.3
                return gain * beat * sinf(2 * .pi * (pitch + Float(stem) * 110) * t)
            }
        }
    }

    /// The live song's drums deviation over 400 frames, with two preparation-sized bursts of a
    /// different, much louder song landing on `prepAnalyzer` (frames 100 and 300).
    private func liveTrace(live: StemAnalyzer, prepAnalyzer: StemAnalyzer?) -> [Float] {
        var trace: [Float] = []
        for i in 0..<400 {
            if let prep = prepAnalyzer, i == 100 || i == 300 {
                for j in 0..<430 { _ = prep.analyze(stemWaveforms: windows(j, gain: 0.9, pitch: 330), fps: 60) }
            }
            trace.append(live.analyze(stemWaveforms: windows(i, gain: 0.15, pitch: 110), fps: 60).drumsEnergyDev)
        }
        return trace
    }

    @Test func aSeparatePreparerAnalyzer_leavesTheLiveTraceIdentical() {
        let baseline = liveTrace(live: StemAnalyzer(sampleRate: 44_100), prepAnalyzer: nil)
        let separate = liveTrace(live: StemAnalyzer(sampleRate: 44_100), prepAnalyzer: StemAnalyzer(sampleRate: 44_100))
        #expect(separate == baseline)
    }

    /// Negative control — the pre-BR.9 wiring: preparation runs on the live instance.
    @Test func theSharedAnalyzer_movesTheLiveTrace() {
        let baseline = liveTrace(live: StemAnalyzer(sampleRate: 44_100), prepAnalyzer: nil)
        let shared = StemAnalyzer(sampleRate: 44_100)
        let corrupted = liveTrace(live: shared, prepAnalyzer: shared)
        let maxDiff = zip(baseline, corrupted).map { abs($0 - $1) }.max() ?? 0
        #expect(maxDiff > 0.05, "sharing moves the live drums deviation (max Δ \(maxDiff))")
    }
}
