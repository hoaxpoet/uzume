// EnergyCurveTests — NRG.1 (D-259). Preparation stores a song's energy as a curve over time, so a
// quiet opening and a loud drop read as different parts of one song, not one averaged number.

import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import Session
@testable import Shared

@Suite("NRG.1 energy curve")
struct EnergyCurveTests {

    @Test("a quiet half then a loud half reads as a ~29.5 dB step with rising activity, one point a second")
    func quietThenLoudIsAStep() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let rate = 44_100
        var seed: UInt32 = 7
        let samples = (0..<(rate * 10)).map { n -> Float in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Float(seed >> 8) / Float(1 << 24) - 0.5
            return noise * (n < rate * 5 ? 0.01 : 0.3)   // 30× amplitude = 29.54 dB
        }
        let curve = try #require(try SessionPreparer.analyzePreview(
            PreviewAudio(trackIdentity: TrackIdentity(title: "song", artist: "test"),
                         pcmSamples: samples, sampleRate: rate, duration: 10),
            separator: try FakeStemSeparator(device: device, bufferCapacity: samples.count),
            analyzer: StemAnalyzer(),
            classifier: MockMoodClassifier()
        ).trackProfile.energyCurve)

        #expect(curve.hopSeconds == 1)
        #expect(curve.loudnessDB.count == 10, "one point per second of a 10 s clip, got \(curve.loudnessDB.count)")
        // Seconds 1–3 are the quiet half and 6–8 the loud half, clear of the boundary and the edges.
        let quiet = curve.loudnessDB[1...3].reduce(0, +) / 3, loud = curve.loudnessDB[6...8].reduce(0, +) / 3
        #expect(abs((loud - quiet) - 29.54) < 1.0, "loudness step \(loud - quiet) dB, expected 29.5")
        let quietActivity = curve.activity[1...3].max() ?? 0, loudActivity = curve.activity[6...8].min() ?? 0
        #expect(loudActivity > 5 * quietActivity, "activity \(quietActivity) → \(loudActivity) should rise")
    }
}
