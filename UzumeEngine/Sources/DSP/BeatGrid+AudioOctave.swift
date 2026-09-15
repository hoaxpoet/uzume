// BeatGrid+AudioOctave.swift — BUG134.2.
//
// BUG134.1 fixed the unambiguous half of BUG-134 (isolated dropped beats) and
// explicitly left the other half open, because a contiguous run of 2x intervals is
// IDENTICAL in the beat list whether the model lost the fast pulse or the track
// genuinely went half-time. That distinction needs the audio, and this file makes it.
//
// THE EVIDENCE THAT REOPENED IT (Matt, M7 2026-09-15, "appeared synced in the
// beginning but quickly drifted out of sync. still too loose", on Ready to Start —
// session 2026-09-15T13-03-13Z, chain verdict clean):
//
//   Measured against real onsets from the session's own tap, the strike error grows
//   17 -> 31 -> 43 -> 49 ms over the first 20 s and the share of beats inside a
//   60 ms window falls 100 % -> 100 % -> 93 % -> 62 %. It is not clock drift: the
//   audio's OWN autocorrelation peaks at 314 ms (190.9 BPM, strength 1.00) and
//   629 ms (95.5 BPM, 0.94) — exactly the grid's two clusters. Every beat is on a
//   real pulse. The grid switches OCTAVE under a song that does not.
//
//   And the intro really is slow, which is why a global unification would have been
//   wrong (per-3 s autocorrelation of the onset envelope):
//
//       0-9 s    fast 0.02-0.18   slow 0.61-0.68     <- genuinely half-time
//       9-30 s   fast 0.56-0.61   slow 0.42-0.51     <- band in, fast pulse rules
//
//   The discriminator separates those by 3-30x. That is not a tuned threshold; it is
//   a signal that is either there or it is not.
//
// WHAT THIS DOES. Per window, ask the AUDIO which octave it supports, and only
// subdivide where the audio says the fast pulse is present and the grid is running
// slow anyway. A window whose audio is slow-dominant or ambiguous is left exactly as
// the model produced it — the intro above must survive untouched.
//
// Pure functions over (beats, onset envelope); no model, no GPU, deterministic.

import Foundation

extension BeatGrid {

    /// Per-window verdict on which metrical level the audio actually supports.
    public enum AudioOctave: Sendable, Equatable {
        /// Audio clearly carries the fast pulse — a slow grid here is the model's error.
        case fast
        /// Audio carries only the slow pulse — a slow grid here is CORRECT.
        case slow
        /// Neither dominates. Left alone; guessing is what this file exists to avoid.
        case ambiguous
    }

    /// Window length for the octave verdict. ~3 s spans several beats at any tempo we
    /// care about while still following a real section change (the Ready to Start
    /// transition lands within one window).
    public static let audioOctaveWindowS: Double = 3.0
    /// Presence threshold for the fast pulse. THE RULE IS A FLOOR, NOT A RATIO.
    ///
    /// A ratio cannot work here and the first version of this file got it wrong: if the
    /// fast pulse is present then the SLOW lag correlates too, because every other fast
    /// beat lands on it. Autocorrelation at 2x a real pulse is always high. So "fast
    /// beats slow by N x" is never true, and the test rejected windows that plainly
    /// carry the fast pulse.
    ///
    /// What actually separates the two cases is whether the fast lag correlates AT ALL.
    /// Measured on Ready to Start (session 2026-09-15T13-03-13Z):
    ///
    ///     intro, genuinely half-time   fast 0.02-0.18
    ///     body,  band playing          fast 0.56-0.61
    ///
    /// 0.30 sits 1.7x above the intro's ceiling and 1.9x below the body's floor — in the
    /// empty space between two populations, not fitted to either edge.
    public static let audioOctaveFloor: Double = 0.30

    /// Normalised autocorrelation of `envelope` at `period`, over one window.
    static func envelopeAutocorrelation(
        _ envelope: ArraySlice<Float>, period: Double, envelopeRate: Double
    ) -> Double {
        let lag = Int((period * envelopeRate).rounded())
        let values = Array(envelope)
        guard lag > 0, values.count > lag + 4 else { return 0 }
        let mean = values.reduce(0, +) / Float(values.count)
        let centred = values.map { max(0, $0 - mean) }
        var num = 0.0, den = 0.0
        for i in 0..<(centred.count - lag) { num += Double(centred[i]) * Double(centred[i + lag]) }
        for value in centred { den += Double(value) * Double(value) }
        return den > 0 ? num / den : 0
    }

    /// Which octave the audio supports in each window, given the grid's fast period.
    public static func audioOctaveVerdicts(
        envelope: [Float], envelopeRate: Double, fastPeriod: Double, durationS: Double
    ) -> [AudioOctave] {
        guard envelopeRate > 0, fastPeriod > 0, durationS > 0 else { return [] }
        let windows = max(1, Int(durationS / audioOctaveWindowS))
        return (0..<windows).map { index in
            let lo = Int(Double(index) * audioOctaveWindowS * envelopeRate)
            let hi = min(envelope.count, Int(Double(index + 1) * audioOctaveWindowS * envelopeRate))
            guard lo < hi else { return .ambiguous }
            let slice = envelope[lo..<hi]
            let fast = envelopeAutocorrelation(slice, period: fastPeriod, envelopeRate: envelopeRate)
            let slow = envelopeAutocorrelation(slice, period: fastPeriod * 2, envelopeRate: envelopeRate)
            if fast >= audioOctaveFloor { return .fast }
            if slow >= audioOctaveFloor { return .slow }
            return .ambiguous
        }
    }

    /// Subdivide half-time intervals ONLY inside windows where the audio says the fast
    /// pulse is present. Returns `self` unchanged when the audio never disagrees with
    /// the grid — this must be a no-op on a track that really is in half-time.
    public func audioOctaveCorrected(envelope: [Float], envelopeRate: Double) -> BeatGrid {
        guard beats.count >= 8, envelopeRate > 0, !envelope.isEmpty else { return self }
        let profile = octaveProfile()
        let fastPeriod = profile.dominantPeriod
        guard fastPeriod > 0 else { return self }
        let duration = Double(envelope.count) / envelopeRate
        let verdicts = Self.audioOctaveVerdicts(
            envelope: envelope,
            envelopeRate: envelopeRate,
            fastPeriod: fastPeriod,
            durationS: duration
        )
        guard !verdicts.isEmpty else { return self }

        func verdict(at time: Double) -> AudioOctave {
            let index = Int(time / Self.audioOctaveWindowS)
            guard index >= 0, index < verdicts.count else { return .ambiguous }
            return verdicts[index]
        }

        var out: [Double] = []
        out.reserveCapacity(beats.count * 2)
        for (index, beat) in beats.enumerated() {
            out.append(beat)
            guard index + 1 < beats.count else { continue }
            let gap = beats[index + 1] - beat
            // Only a ~2x gap is a candidate; anything else is a tempo change or a
            // section edge, neither of which this is allowed to touch.
            guard abs(gap / fastPeriod - 2.0) <= Self.octaveToleranceValue else { continue }
            guard verdict(at: beat) == .fast else { continue }
            out.append(beat + gap * 0.5)
        }
        guard out.count != beats.count else { return self }
        return BeatGrid(
            beats: out,
            downbeats: downbeats,
            bpm: BeatGridResolver.computeBPM(beats: out),
            beatsPerBar: beatsPerBar,
            barConfidence: barConfidence,
            frameRate: frameRate,
            frameCount: frameCount
        )
    }

    /// Exposed so the audio pass and the grid-only pass agree on what "a 2x gap" means.
    static var octaveToleranceValue: Double { 0.35 }
}
