// BUG-140 — the D-154 beat-irregularity gate compared tempos that were wrong.
//
// (1) `BeatGrid.bpm` is `computeBPM`'s mean of IOIs across a full octave, so a drums grid
//     that reads eighths then quarters averaged to a tempo describing neither
//     (Superstition: 138.25 against a 98.53 full-mix grid → flagged "no steady beat").
//     The gate now compares `octaveFoldedMedianBPM` of the beats.
// (2) On the local-file path the drums grid was analysed at the FILE's sample rate
//     although the separator returns stems at 44.1 kHz — 48 kHz files read ×1.088.
//
// Beat lists below are real CorpusCensusRunner dumps (CENSUS_DUMP_BEATS), 2026-09-24.
import Foundation
import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

@Suite("BUG-140 — beat-irregularity tempos")
struct BeatIrregularityTempoTests {

    // MARK: - Fixtures

    private static func grid(_ beats: [Double], barConfidence: Float = 1) -> BeatGrid {
        BeatGrid(beats: beats, downbeats: [], bpm: BeatGridResolver.computeBPM(beats: beats),
                 beatsPerBar: 4, barConfidence: barConfidence, frameRate: 50, frameCount: 0)
    }

    private static func steady(bpm: Double, count: Int = 40) -> [Double] {
        (0..<count).map { Double($0) * 60 / bpm }
    }

    /// Superstition (Talking Book FLAC), drums stem: six eighths, then four quarters.
    static let superstitionDrums = [0.1, 0.4, 0.72, 1.04, 1.34, 1.62, 1.96, 2.58, 3.2, 3.8, 4.44]
    /// Penny Lane (stereo FLAC), drums stem: eighths for ~5 s, then quarters.
    static let pennyLaneDrums = [0.3, 0.54, 0.86, 1.14, 1.42, 1.78, 1.96, 2.23, 2.5, 2.74, 3.06,
                                 3.6, 3.94, 4.14, 4.68, 4.98, 5.22, 5.78, 6.32, 6.86, 7.38, 7.92,
                                 8.44, 8.98, 9.3, 9.52]

    // MARK: - The defect, and the fix

    @Test("computeBPM averages Superstition's mixed drums grid to a non-octave tempo")
    func meanReproducesTheDefect() {
        let drums = Self.grid(Self.superstitionDrums)
        #expect(abs(drums.bpm - 138.25) < 0.5, "the census value this bug was filed on")
        let full = Self.grid(Self.steady(bpm: 98.53))
        #expect(assessBeatIrregularity(gridBPM: full.bpm, drumsBPM: drums.bpm,
                                       barConfidence: 1) == true)
    }

    @Test("the octave-folded median reads Superstition's drums at one pulse level")
    func foldedMedianIsOnTheGrid() throws {
        let bpm = try #require(octaveFoldedMedianBPM(beats: Self.superstitionDrums))
        let disagreement = try #require(foldedBPMDisagreement(bpm, 98.53))
        #expect(disagreement < 0.10, "folded disagreement \(disagreement) at \(bpm) BPM")
    }

    @Test("Superstition and Penny Lane are regular through the grid-level gate",
          arguments: [(superstitionDrums, 98.53), (pennyLaneDrums, 112.09)])
    func motivatingTracksPass(drums: [Double], gridBPM: Double) {
        let verdict = assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: gridBPM)),
                                             drums: Self.grid(drums))
        #expect(verdict == false)
    }

    // MARK: - Negative controls: real disagreement still flags

    @Test("two steady grids at a non-octave ratio are still irregular")
    func nonOctaveDisagreementStillFlags() {
        // 120 vs 88 — ratio 1.36, not an octave.
        #expect(assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: 120)),
                                       drums: Self.grid(Self.steady(bpm: 88))) == true)
        // D-154's pinned Pyramid Song pair (70 vs 164.3 → 17.4 % folded).
        #expect(assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: 70)),
                                       drums: Self.grid(Self.steady(bpm: 164.3))) == true)
    }

    @Test("an exact octave between steady grids stays regular")
    func octaveStaysRegular() {
        #expect(assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: 119.8)),
                                       drums: Self.grid(Self.steady(bpm: 60.7))) == false)
    }

    @Test("low bar confidence still flags on its own")
    func barConfidenceStillFlags() {
        #expect(assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: 120), barConfidence: 0.1),
                                       drums: Self.grid(Self.steady(bpm: 120))) == true)
    }

    @Test("too few beats or no drums grid is unknown, not irregular")
    func missingEvidenceIsUnknown() {
        #expect(octaveFoldedMedianBPM(beats: [0, 0.5, 1.0]) == nil)
        #expect(assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: 120)), drums: nil) == nil)
        #expect(assessBeatIrregularity(grid: Self.grid(Self.steady(bpm: 120)),
                                       drums: Self.grid([0, 0.5])) == nil)
    }

    // MARK: - Sample rate (local-file path)

    /// Records the sample rate of every analyzer call, in order: full mix, then drums.
    private final class RateRecordingAnalyzer: BeatGridAnalyzing, @unchecked Sendable {
        private(set) var rates: [Double] = []
        func analyzeBeatGrid(samples: [Float], sampleRate: Double, wholeTrack: Bool) -> BeatGrid {
            rates.append(sampleRate)
            return .empty
        }
    }

    @Test("the drums grid is analysed at the separator's model rate, not the file's")
    func drumsGridUsesModelRate() throws {
        guard #available(macOS 14.2, *) else { return }
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let fileRate = 48_000
        let pcm = [Float](repeating: 0, count: fileRate * 2)
        let preview = PreviewAudio(
            trackIdentity: TrackIdentity(title: "t", artist: "a", spotifyID: "test:bug140"),
            pcmSamples: pcm, sampleRate: fileRate, duration: 2.0)
        let analyzer = RateRecordingAnalyzer()

        _ = try SessionPreparer.analyzePreview(
            preview,
            separator: try FakeStemSeparator(device: device, bufferCapacity: pcm.count),
            analyzer: StemAnalyzer(sampleRate: Float(fileRate)),
            classifier: MockMoodClassifier(),
            beatGridAnalyzer: analyzer)

        #expect(analyzer.rates == [Double(fileRate), Double(StemSeparator.modelSampleRate)],
                "full mix at the file rate, drums stem at 44.1 kHz — got \(analyzer.rates)")
    }
}
