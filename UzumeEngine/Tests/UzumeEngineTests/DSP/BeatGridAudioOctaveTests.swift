// BUG134.2 — audio-referenced octave correction.
//
// Synthetic audio, deterministic, no fixtures. The real-session numbers these mirror
// are in BUG-134: Ready to Start's intro measures fast 0.02-0.18 / slow 0.61-0.68 and
// its body fast 0.56-0.61 / slow 0.42-0.51.

import Testing
import Foundation
@testable import DSP

@Suite("BeatGrid audio-referenced octave (BUG134.2)")
struct BeatGridAudioOctaveTests {

    private let rate = 44_100.0

    /// Clicks at `period`, optionally with a weaker click halfway between (which is
    /// what a fast pulse under a slow one sounds like to an energy envelope).
    private func clickTrack(period: Double, seconds: Double, subdivide: Bool) -> [Float] {
        var out = [Float](repeating: 0, count: Int(seconds * rate))
        var t = 0.05
        while t < seconds {
            for (offset, amp) in [(0.0, Float(1.0))] + (subdivide ? [(period / 2, Float(0.85))] : []) {
                let start = Int((t + offset) * rate)
                for k in 0..<Int(0.010 * rate) where start + k < out.count {
                    let decay = Float(1.0 - Double(k) / (0.010 * rate))
                    out[start + k] += amp * decay * sinf(Float(k) * 0.35)
                }
            }
            t += period
        }
        return out
    }

    private func grid(_ beats: [Double]) -> BeatGrid {
        BeatGrid(beats: beats, downbeats: [], bpm: BeatGridResolver.computeBPM(beats: beats),
                 beatsPerBar: 4, barConfidence: 1, frameRate: 50, frameCount: 0)
    }

    /// The load-bearing case. Audio carries a fast pulse; the grid is running half-time
    /// against it. Those gaps get subdivided.
    @Test("A half-time grid over fast audio is subdivided")
    func halfTimeGridOverFastAudioIsFixed() {
        let audio = clickTrack(period: 0.640, seconds: 12, subdivide: true)   // 187 + 94 BPM
        let env = OnsetEnvelope.compute(samples: audio, sampleRate: rate)
        // Grid at 320 ms for the first half, then dropping to 640 ms — the model error.
        var beats: [Double] = []
        var t = 0.05
        while t < 6 { beats.append(t); t += 0.320 }
        while t < 12 { beats.append(t); t += 0.640 }
        let fixed = grid(beats).audioOctaveCorrected(envelope: env, envelopeRate: OnsetEnvelope.rate)
        #expect(fixed.beats.count > beats.count, "half-time gaps over fast audio must be filled")
        let iv = zip(fixed.beats, fixed.beats.dropFirst()).map { $1 - $0 }
        let long = iv.filter { $0 > 0.48 }.count
        #expect(long == 0, "\(long) half-time gaps survived over audio that carries the fast pulse")
    }

    /// The case BUG134.1 refused to guess at, and the reason this needs audio at all.
    /// The track really is in half-time; the grid is RIGHT and must come back untouched.
    @Test("A genuinely half-time section is left alone")
    func genuineHalfTimeSurvives() {
        let audio = clickTrack(period: 0.640, seconds: 12, subdivide: false)  // only 94 BPM
        let env = OnsetEnvelope.compute(samples: audio, sampleRate: rate)
        var beats: [Double] = []
        var t = 0.05
        while t < 12 { beats.append(t); t += 0.640 }
        let g = grid(beats)
        let fixed = g.audioOctaveCorrected(envelope: env, envelopeRate: OnsetEnvelope.rate)
        #expect(fixed.beats == g.beats, "a real half-time section must not be subdivided")
    }

    /// Silence carries no pulse at all; every window is ambiguous and nothing moves.
    @Test("Silent audio changes nothing")
    func silenceChangesNothing() {
        let env = OnsetEnvelope.compute(samples: [Float](repeating: 0, count: Int(8 * rate)),
                                        sampleRate: rate)
        var beats: [Double] = []
        var t = 0.05
        while t < 8 { beats.append(t); t += 0.640 }
        let g = grid(beats)
        #expect(g.audioOctaveCorrected(envelope: env, envelopeRate: OnsetEnvelope.rate).beats == g.beats)
    }

    /// The verdict itself, on the two populations the real session measured.
    @Test("The verdict separates fast-carrying from slow-only audio")
    func verdictSeparatesThePopulations() {
        let fastAudio = clickTrack(period: 0.640, seconds: 9, subdivide: true)
        let slowAudio = clickTrack(period: 0.640, seconds: 9, subdivide: false)
        let fastV = BeatGrid.audioOctaveVerdicts(
            envelope: OnsetEnvelope.compute(samples: fastAudio, sampleRate: rate),
            envelopeRate: OnsetEnvelope.rate, fastPeriod: 0.320, durationS: 9)
        let slowV = BeatGrid.audioOctaveVerdicts(
            envelope: OnsetEnvelope.compute(samples: slowAudio, sampleRate: rate),
            envelopeRate: OnsetEnvelope.rate, fastPeriod: 0.320, durationS: 9)
        #expect(fastV.contains(.fast), "audio with a fast pulse should yield at least one .fast window")
        #expect(!slowV.contains(.fast), "slow-only audio must NEVER be called .fast — got \(slowV)")
    }

    /// An empty envelope must not crash or rewrite anything.
    @Test("No envelope is a no-op")
    func noEnvelopeIsNoOp() {
        var beats: [Double] = []
        var t = 0.05
        while t < 8 { beats.append(t); t += 0.320 }
        let g = grid(beats)
        #expect(g.audioOctaveCorrected(envelope: [], envelopeRate: OnsetEnvelope.rate).beats == g.beats)
    }
}
