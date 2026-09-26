// MIRSampleRateTests — BUG-145. Preparation MIR ran its 1024-point FFT at the FILE's rate, so the
// same music prepared from a 96 kHz file read a halved centroid and skewed key correlations —
// Superstition's arousal 0.21 against 0.52 at 44.1 kHz. It now runs at the stems' 44.1 kHz.

import Foundation
import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

@Suite("BUG-145 preparation MIR is sample-rate independent")
struct MIRSampleRateTests {

    /// The same 20 s of music at any rate: a pulsing chord with a bass line.
    private static func music(rate: Int) -> [Float] {
        (0..<(rate * 20)).map { n in
            let t = Double(n) / Double(rate)
            let pulse = 0.6 + 0.4 * sin(2 * .pi * 2 * t)
            let tones = [(110.0, 0.5), (220.0, 0.3), (277.2, 0.25), (329.6, 0.25), (1318.5, 0.1), (3000.0, 0.05)]
            return Float(pulse * tones.reduce(0) { $0 + $1.1 * sin(2 * .pi * $1.0 * t) } * 0.3)
        }
    }

    @available(macOS 14.2, *)
    private static func profile(rate: Int) throws -> TrackProfile {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let samples = music(rate: rate)
        return try SessionPreparer.analyzePreview(
            PreviewAudio(trackIdentity: TrackIdentity(title: "song", artist: "test"),
                         pcmSamples: samples, sampleRate: rate, duration: 20),
            separator: try FakeStemSeparator(device: device, bufferCapacity: samples.count),
            analyzer: StemAnalyzer(),
            classifier: MoodClassifier()
        ).trackProfile
    }

    @Test("the same music prepared from a 96 kHz file reads as it does at 44.1 kHz")
    func ninetySixKilohertzMatchesFortyFour() throws {
        guard #available(macOS 14.2, *) else { return }   // FakeStemSeparator's floor
        let reference = try Self.profile(rate: Int(StemSeparator.modelSampleRate))
        let high = try Self.profile(rate: 96_000)
        #expect(abs(high.spectralCentroidAvg / reference.spectralCentroidAvg - 1) < 0.05,
                "centroid \(high.spectralCentroidAvg) at 96 kHz vs \(reference.spectralCentroidAvg) (BUG-145)")
        #expect(abs(high.mood.arousal - reference.mood.arousal) < 0.05
                && abs(high.mood.valence - reference.mood.valence) < 0.05,
                "mood \(high.mood) at 96 kHz vs \(reference.mood) (BUG-145)")
    }
}
