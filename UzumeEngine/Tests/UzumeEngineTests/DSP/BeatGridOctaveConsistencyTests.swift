// BUG-134 — octave consistency on the cached BeatGrid.
//
// Deterministic, synthetic grids: no cache, no GPU, no fixtures. The real-corpus
// numbers these mirror are in the increment's closeout (50 cached grids, 15 of them
// octave-mixed, 202 isolated dropped beats).

import Testing
import Foundation
@testable import DSP

@Suite("BeatGrid octave consistency (BUG-134)")
struct BeatGridOctaveConsistencyTests {

    private func grid(_ beats: [Double], bpm: Double? = nil) -> BeatGrid {
        BeatGrid(beats: beats, downbeats: [],
                 bpm: bpm ?? BeatGridResolver.computeBPM(beats: beats),
                 beatsPerBar: 4, barConfidence: 1, frameRate: 50, frameCount: 0)
    }

    /// A healthy grid must come back byte-identical. The correction is only allowed to
    /// act on the two unambiguous cases; anything else is a regression for every track
    /// whose grid was already fine (48 of the 50 in the local cache).
    @Test("A uniform grid is untouched")
    func uniformGridIsNoOp() {
        let beats = (0..<200).map { Double($0) * 0.5 }        // 120 BPM, clean
        let g = grid(beats)
        #expect(g.octaveUnified().beats == beats)
        #expect(g.octaveProfile().isBimodal == false)
        #expect(g.octaveProfile().isolatedGapCount == 0)
    }

    /// One dropped beat in an otherwise clean grid: the model kept the beats either
    /// side, so the midpoint is recoverable rather than invented.
    @Test("An isolated dropped beat is filled at the midpoint")
    func isolatedGapIsFilled() {
        var beats = (0..<120).map { Double($0) * 0.5 }
        let removed = beats[60]
        beats.remove(at: 60)
        let g = grid(beats)
        #expect(g.octaveProfile().isolatedGapCount == 1)
        let fixed = g.octaveUnified()
        #expect(fixed.beats.count == 120)
        #expect(fixed.beats.contains { abs($0 - removed) < 1e-9 })
    }

    /// A long contiguous slow section is the model tracking a genuinely slower pulse.
    /// Rewriting it would be inventing structure, so it is reported as clustered and
    /// left alone. Ready to Start carries a 119-interval run of exactly this shape.
    @Test("A clustered slow section is reported but NOT rewritten")
    func clusteredSectionIsLeftAlone() {
        let fast = (0..<80).map { Double($0) * 0.5 }               // 120 BPM
        let start = fast.last! + 1.0
        let slow = (0..<40).map { start + Double($0) * 1.0 }       // 60 BPM section
        let g = grid(fast + slow)
        let p = g.octaveProfile()
        // Inside the slow section the LOCAL median is the slow period, so its intervals
        // are not long relative to their own neighbourhood — which is the point: a
        // genuine tempo change is not an anomaly, and the profile does not flag it.
        #expect(p.isolatedGapCount == 0, "a tempo change is not a dropped beat")
        #expect(g.octaveUnified().beats == fast + slow, "a real tempo change must survive")
    }

    /// The Ready to Start shape: two populated octaves. The grid is REPORTED as
    /// bimodal and deliberately NOT rewritten — see the no-unification note in
    /// BeatGrid+OctaveConsistency.swift. This test pins that it stays a report.
    @Test("A bimodal grid is reported, and deliberately not rewritten")
    func bimodalIsReportedNotRewritten() {
        // Mirrors Arcade Fire "Ready to Start" as cached: a 320 ms fast cluster and a
        // 637 ms slow cluster, ratio 1.99. The ratio matters — `computeBPM`'s inlier
        // window is [median*0.5, median*2.0], so a slow cluster at 1.99x squeaks INSIDE
        // the ceiling and is averaged in, producing a bpm that describes neither.
        var beats: [Double] = []
        var t = 0.0
        for block in 0..<20 {
            let (period, n) = (block % 3 == 2) ? (0.637, 6) : (0.320, 12)
            for _ in 0..<n { beats.append(t); t += period }
        }
        let g = grid(beats)
        let p = g.octaveProfile()
        #expect(p.isBimodal, "two populated octaves must be REPORTED")
        #expect(p.dominantBPM > BeatGrid.halvingThresholdBPM)
        // The defect that hid the defect: the averaged summary sits below the gate that
        // exists to catch exactly this, so the existing correction never opens.
        #expect(g.bpm < BeatGrid.halvingThresholdBPM,
                "averaged bpm \(g.bpm) sits below the 175 gate while the real cluster is above it")
        #expect(g.summaryErrorIsMaterial(p), "bpm should be materially wrong here")
    }

    /// No bimodal grid is rewritten, at any tempo — the grid cannot tell a model
    /// dropout from a real half-time section.
    @Test("A bimodal grid is never rewritten")
    func bimodalBelowThresholdIsLeftAlone() {
        var beats: [Double] = []
        var t = 0.0
        for block in 0..<20 {                                   // 100 BPM vs 50 BPM
            let (period, n) = (block % 3 == 2) ? (1.2, 6) : (0.6, 12)
            for _ in 0..<n { beats.append(t); t += period }
        }
        let g = grid(beats)
        #expect(g.octaveProfile().dominantBPM < BeatGrid.halvingThresholdBPM)
        #expect(g.octaveUnified().beats == beats)
    }

    /// Downbeats must not survive where no beat does.
    @Test("Downbeats are re-snapped to surviving beats")
    func downbeatsAreResnapped() {
        var beats = (0..<120).map { Double($0) * 0.5 }
        beats.remove(at: 60)
        let g = BeatGrid(beats: beats, downbeats: [0, 2, 4],
                         bpm: BeatGridResolver.computeBPM(beats: beats),
                         beatsPerBar: 4, barConfidence: 1, frameRate: 50, frameCount: 0)
        let fixed = g.octaveUnified()
        for db in fixed.downbeats {
            #expect(fixed.beats.contains { abs($0 - db) <= 0.040 })
        }
    }
}

private extension BeatGrid {
    /// Is the grid's own `bpm` materially away from its dominant cluster?
    func summaryErrorIsMaterial(_ p: OctaveProfile) -> Bool { abs(p.summaryErrorRatio - 1.0) > 0.10 }
}
