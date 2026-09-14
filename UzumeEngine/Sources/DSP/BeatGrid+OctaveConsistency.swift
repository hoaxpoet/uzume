// BeatGrid+OctaveConsistency.swift — BUG-134.
//
// A cached BeatGrid can carry TWO tempo octaves inside one track. Measured over
// the 50 grids in the local stem cache, 15 of them do. On Arcade Fire's "Ready to
// Start" the inter-beat intervals form two clean clusters —
//
//     402 intervals @ 314 ms (191 BPM)      198 intervals @ 637 ms (94 BPM)
//     ratio 2.03x — the grid alternates between half and double time
//
// — and a preset locked to that grid fires every third strike twice as late as the
// others. That is what Matt reported as "it's actually out of phase" (M7,
// 2026-09-14) on that track and no other; the three grids he did NOT complain about
// are all unimodal and their `bpm` matches their own beats to within 0.2 %.
//
// TWO THINGS WERE WRONG, and they hid each other.
//
// 1. `BeatGridResolver.computeBPM` averages ACROSS octaves. Its inlier window is
//    `[median * 0.5, median * 2.0]` — a full octave wide — so both clusters are
//    admitted and the mean of a bimodal set is returned. For Ready to Start that
//    is a `bpm` matching NEITHER cluster. Matt already ruled on this class at
//    PR.12 ("you should not be averaging BPM / tempo"); the meter computation was
//    fixed then and this one was not.
//
// 2. `halvingOctaveCorrected()` gates on `bpm > 175`. Ready to Start's summary
//    `bpm` is 154.31, so the gate never opens — while two thirds of its actual
//    beats run at 191 BPM, which is exactly what that gate exists to catch. The
//    bad summary suppressed the correction for the bad grid.
//
// WHAT THIS FILE DOES NOT DO. It does not touch clustered octave changes. A long
// contiguous run of slow intervals is the model tracking a genuinely slower pulse
// through a section (Ready to Start's tail carries a 119-interval run), and
// rewriting that would be inventing structure. Only the two cases below are
// corrected, both of which are unambiguous:
//
//   * an ISOLATED 2x gap — one long interval with normal intervals either side, i.e.
//     the model dropped exactly one beat. 202 of these across the 50 cached grids.
//   * a grid that is still bimodal at 2x afterwards, where the FAST cluster exceeds
//     the D-079 halving threshold. Then the fast cluster is the double-time error
//     that threshold already names, and the grid is expressed at the slow octave.
//
// Pure functions over the beat list; no engine state, no GPU, deterministic.

import Foundation

extension BeatGrid {

    // MARK: - Diagnostic

    /// What the interval distribution of this grid actually looks like.
    public struct OctaveProfile: Sendable, Equatable {
        /// Modal inter-beat interval, seconds (the dominant cluster, not a mean).
        public let dominantPeriod: Double
        /// Tempo of the dominant cluster — what `bpm` SHOULD describe.
        public let dominantBPM: Double
        /// Slow-cluster tempo when the grid is bimodal at ~2x, else nil.
        public let slowBPM: Double?
        /// Long intervals that are ~2x their local median with normal neighbours —
        /// dropped beats, safe to fill.
        public let isolatedGapCount: Int
        /// Long intervals inside a run — a real octave section, left alone.
        public let clusteredLongCount: Int
        public var isBimodal: Bool { slowBPM != nil }
        /// How far the grid's own `bpm` is from its dominant cluster, as a ratio.
        public let summaryErrorRatio: Double
    }

    /// Window used for the LOCAL median, in intervals either side. Wide enough to be
    /// robust to a single dropout, narrow enough to follow a real tempo change.
    private static let localWindow = 9
    /// How close to exactly 2x an interval must be to count as an octave gap.
    private static let octaveTolerance = 0.35

    private static func localMedian(_ iois: [Double], _ i: Int) -> Double {
        let lo = max(0, i - localWindow), hi = min(iois.count, i + localWindow + 1)
        let window = iois[lo..<hi].sorted()
        return window.isEmpty ? 0 : window[window.count / 2]
    }

    /// Measure the grid's octave structure. Cheap; safe to log on every install.
    public func octaveProfile() -> OctaveProfile {
        let iois = zip(beats, beats.dropFirst()).map { $1 - $0 }
        guard iois.count >= 8 else {
            return OctaveProfile(
                dominantPeriod: 0,
                dominantBPM: 0,
                slowBPM: nil,
                isolatedGapCount: 0,
                clusteredLongCount: 0,
                summaryErrorRatio: 1
            )
        }
        let sorted = iois.sorted()
        let median = sorted[sorted.count / 2]

        // Dominant cluster = intervals within a quarter-octave of the median. This is
        // deliberately NARROW: the whole defect is that a full-octave window averages
        // two clusters together.
        let near = iois.filter { $0 >= median * 0.75 && $0 <= median * 1.33 }
        let dominantPeriod = near.isEmpty ? median : near.reduce(0, +) / Double(near.count)

        var isolated = 0, clustered = 0
        var slowSamples: [Double] = []
        for (i, x) in iois.enumerated() {
            let loc = Self.localMedian(iois, i)
            guard loc > 0, x >= loc * 1.5, abs(x / loc - 2.0) <= Self.octaveTolerance else { continue }
            slowSamples.append(x)
            let prevOK = i > 0 && iois[i - 1] < loc * 1.5
            let nextOK = i + 1 < iois.count && iois[i + 1] < loc * 1.5
            if prevOK && nextOK { isolated += 1 } else { clustered += 1 }
        }
        // Bimodality is measured GLOBALLY, against the whole-grid median, not against a
        // local window. A long contiguous half-time block is locally NORMAL — its own
        // neighbourhood is slow — so a local test reports 0 bimodal grids across the
        // whole cache while the histogram plainly shows two clusters. Measured: the
        // local test found 0; this one finds the real ones.
        let globalSlow = iois.filter { abs($0 / median - 2.0) <= Self.octaveTolerance }
        let slowBPM: Double? = globalSlow.count >= max(8, iois.count / 10)
            ? 60.0 / (globalSlow.reduce(0, +) / Double(globalSlow.count))
            : nil
        _ = slowSamples
        let domBPM = dominantPeriod > 0 ? 60.0 / dominantPeriod : 0
        let errRatio = (bpm > 0 && domBPM > 0) ? bpm / domBPM : 1
        return OctaveProfile(
            dominantPeriod: dominantPeriod,
            dominantBPM: domBPM,
            slowBPM: slowBPM,
            isolatedGapCount: isolated,
            clusteredLongCount: clustered,
            summaryErrorRatio: errRatio
        )
    }

    // MARK: - Correction

    /// Return a grid whose beats are octave-consistent, per the two rules in the file
    /// header. Returns `self` unchanged when there is nothing unambiguous to fix —
    /// this must be a no-op on a healthy grid.
    public func octaveUnified() -> BeatGrid {
        guard beats.count >= 8 else { return self }
        let profile = octaveProfile()

        // Pass 1 — fill isolated dropped beats at the midpoint. Cannot invent
        // structure: it restores the beat the model skipped between two beats it kept.
        var out = beats
        if profile.isolatedGapCount > 0 {
            let iois = zip(beats, beats.dropFirst()).map { $1 - $0 }
            var inserted: [Double] = []
            for (i, x) in iois.enumerated() {
                let loc = Self.localMedian(iois, i)
                guard loc > 0, x >= loc * 1.5, abs(x / loc - 2.0) <= Self.octaveTolerance,
                      i > 0, iois[i - 1] < loc * 1.5,
                      i + 1 < iois.count, iois[i + 1] < loc * 1.5 else { continue }
                inserted.append(beats[i] + x * 0.5)
            }
            if !inserted.isEmpty { out = (out + inserted).sorted() }
        }

        // NO OCTAVE-UNIFICATION PASS, deliberately. An earlier version of this file
        // expressed a still-bimodal grid at its slow octave when the fast cluster
        // exceeded the D-079 halving threshold. Measured over the 50 cached grids it
        // fired ZERO times, and making it fire would require deciding, from the beat
        // list alone, whether a long contiguous slow run is
        //
        //   (a) the model losing the fast pulse and tracking half-time — an error, or
        //   (b) the track genuinely playing a half-time section — correct.
        //
        // Those are indistinguishable in the grid: both are a run of intervals at 2x
        // the surrounding period. Telling them apart needs the AUDIO, not the grid.
        // Guessing would rewrite real tempo changes on every track with a half-time
        // bridge, so the grid is left alone and the profile reports the bimodality for
        // a human to act on. Ready to Start's residual irregularity (29.8 % after gap
        // filling) is this case, and it is recorded in BUG-134 rather than guessed at.
        let unified = out

        guard unified != beats else { return self }

        // Downbeats survive only where a beat still sits under them (±40 ms), the same
        // rule `halvingOctaveCorrected` uses after thinning.
        let snapped = downbeats.compactMap { db -> Double? in
            unified.min(by: { abs($0 - db) < abs($1 - db) }).flatMap { abs($0 - db) <= 0.040 ? $0 : nil }
        }
        return BeatGrid(
            beats: unified,
            downbeats: snapped,
            bpm: BeatGridResolver.computeBPM(beats: unified),
            beatsPerBar: beatsPerBar,
            barConfidence: barConfidence,
            frameRate: frameRate,
            frameCount: frameCount
        )
    }
}
