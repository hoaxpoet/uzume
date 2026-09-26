// ProfileTempoTests — BUG-144. `TrackProfile.bpm` must be the beat tracker's tempo. It was the
// MIR BeatDetector's sub-bass IOI tempo, whose onsets fire at their 400 ms cooldown on every
// song, so every song read 130–143 BPM. Matt's call: songs without a steady beat store no BPM.

import DSP
import Metal
import Testing
@testable import Audio
@testable import Session
@testable import Shared

// MARK: - Stub grid analyzer

/// Full mix first, drums stem second — the order `computeBeatGrids` calls in.
private final class FixedTempoAnalyzer: BeatGridAnalyzing, @unchecked Sendable {
    private var periods: [Double]
    init(fullMixBPM: Double, drumsBPM: Double) { periods = [60 / fullMixBPM, 60 / drumsBPM] }

    func analyzeBeatGrid(samples: [Float], sampleRate: Double, wholeTrack: Bool) -> BeatGrid {
        let period = periods.isEmpty ? 0.5 : periods.removeFirst()
        let beats = stride(from: 0.0, to: Double(samples.count) / sampleRate, by: period).map { $0 }
        return BeatGrid(beats: beats, downbeats: [], bpm: 60 / period, beatsPerBar: 4,
                        barConfidence: 1, frameRate: 50, frameCount: beats.count)
    }
}

// MARK: - Tests

@Suite("BUG-144 stored tempo is the beat tracker's")
struct ProfileTempoTests {

    @available(macOS 14.2, *)
    private func storedBPM(fullMix: Double, drums: Double) throws -> Float? {
        let device = try #require(MTLCreateSystemDefaultDevice())
        var seed: UInt32 = 1   // broadband noise: fires the sub-bass onset detector freely
        let samples = (0..<(44_100 * 20)).map { _ -> Float in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.6
        }
        let cached = try SessionPreparer.analyzePreview(
            PreviewAudio(trackIdentity: TrackIdentity(title: "song", artist: "test"),
                         pcmSamples: samples, sampleRate: 44_100, duration: 20),
            separator: try FakeStemSeparator(device: device, bufferCapacity: samples.count),
            analyzer: StemAnalyzer(),
            classifier: MockMoodClassifier(),
            beatGridAnalyzer: FixedTempoAnalyzer(fullMixBPM: fullMix, drumsBPM: drums)
        )
        return cached.trackProfile.bpm
    }

    @Test("a steady 90 BPM grid is stored as 90, not the onset detector's ~135")
    func steadyGridTempoIsStored() throws {
        guard #available(macOS 14.2, *) else { return }   // FakeStemSeparator's floor
        let bpm = try #require(try storedBPM(fullMix: 90, drums: 90), "a steady grid must store a BPM")
        #expect(abs(bpm - 90) < 0.5, "stored \(bpm), expected the grid's 90 (BUG-144)")
    }

    @Test("a beat the D-154 gate calls irregular stores no BPM")
    func irregularBeatStoresNoBPM() throws {
        guard #available(macOS 14.2, *) else { return }
        // 90 vs 117: a 30 % non-octave disagreement between the full-mix and drums grids.
        #expect(try storedBPM(fullMix: 90, drums: 117) == nil)
    }

    @Test("a 20 ms-quantised grid reads its average tempo, through a half-time stretch")
    func foldedTempoIsNotQuantised() throws {
        // B.O.B.'s shape: intervals alternate 0.38/0.40 s (mean 0.39 s = 153.8 BPM) on Beat This!'s
        // 20 ms grid, with a stretch tracked at half time. The folded MEDIAN reads 150.0 or 157.9.
        var beats: [Double] = [0]
        for i in 0..<200 { beats.append(beats[beats.count - 1] + (i.isMultiple(of: 2) ? 0.38 : 0.40)) }
        for _ in 0..<30 { beats.append(beats[beats.count - 1] + 0.78) }
        let bpm = try #require(octaveFoldedTempoBPM(beats: beats))
        #expect(abs(bpm - 60 / 0.39) < 0.5, "read \(bpm), expected 153.8")
    }
}
