// EnergyScale — the library-calibrated 1–10 energy level and a song's readout (NRG.2, D-259).
//
// A second's score is the mean of its library rank in loudness and in activity. Loudness alone
// carries mastering bias (a 1959 record sits ~10 dB under a modern one), so it is averaged with
// activity rather than used alone. Level = the library decile of that score, so each level holds a
// tenth of the library's seconds — a relative scale for Matt's collection, the DJ convention.
//
// The tables come from `tools/energy_calibration.py` over the 1,000-track stratified pilot
// (`EnergyScale+Table.swift`, generated; mirrored in `tools/data/energy_scale.json`). The Python
// script and this file implement the same rank → score → level → readout steps.

import Foundation

// MARK: - EnergyScale

/// Maps a second's loudness and activity to a 1–10 level against the library (D-259).
public struct EnergyScale: Sendable {

    /// 101 library quantiles of per-second loudness (dB), ascending.
    let loudnessQuantiles: [Float]
    /// 101 library quantiles of per-second activity, ascending.
    let activityQuantiles: [Float]
    /// 11 library deciles of the per-second score: the edges of levels 1…10.
    let scoreDeciles: [Float]

    /// The level of one second, 1 (quietest tenth of the library) … 10 (most energetic tenth).
    public func level(loudnessDB: Float, activity: Float) -> Int {
        let score = 0.5 * Self.rank(loudnessDB, in: loudnessQuantiles)
            + 0.5 * Self.rank(activity, in: activityQuantiles)
        let edges = scoreDeciles.dropFirst().dropLast()          // the nine inner edges
        return min(10, max(1, edges.filter { $0 <= score }.count + 1))
    }

    /// Library rank of `x` in 0…1, interpolated linearly in an ascending quantile table.
    static func rank(_ x: Float, in table: [Float]) -> Float {
        guard let upper = table.firstIndex(where: { $0 >= x }) else { return 1 }
        guard upper > 0 else { return 0 }
        let lo = table[upper - 1], hi = table[upper]
        let fraction = hi > lo ? (x - lo) / (hi - lo) : 0
        return (Float(upper - 1) + fraction) / Float(table.count - 1)
    }
}

// MARK: - Readout

/// A song's energy as the preparation view shows it: one level, or a low → high range (D-259).
public struct EnergyReadout: Sendable, Equatable {
    /// The 10th-percentile section level.
    public let low: Int
    /// The 90th-percentile section level.
    public let high: Int
    /// The median section level — what a steady song reads as.
    public let typical: Int

    /// True when the song's sections span at most one level: show `typical` alone.
    public var isSteady: Bool { high - low <= 1 }
}

extension EnergyCurve {

    /// Seconds quieter than this are digital silence (a track's lead-in or tail), not music.
    static let silenceFloorDB: Float = -90

    /// Each second's level at section scale: loudness and activity are first smoothed with a
    /// ±5 s running median, so the readout describes sections rather than second-to-second jitter.
    public func sectionLevels(on scale: EnergyScale = .library) -> [Int] {
        timedSectionLevels(on: scale).compactMap { $0 }
    }

    /// `sectionLevels`, aligned with the curve's seconds: nil where the second is digital silence.
    public func timedSectionLevels(on scale: EnergyScale = .library) -> [Int?] {
        let kept = loudnessDB.indices.filter { loudnessDB[$0] > Self.silenceFloorDB }
        let loud = Self.runningMedian(kept.map { loudnessDB[$0] })
        let act = Self.runningMedian(kept.map { activity[$0] })
        var timed = [Int?](repeating: nil, count: loudnessDB.count)
        for (position, index) in kept.enumerated() {
            timed[index] = scale.level(loudnessDB: loud[position], activity: act[position])
        }
        return timed
    }

    /// The median section level over seconds `start ..< end` of the curve (NRG.3), or nil when
    /// that stretch holds no audible second.
    public func level(from start: TimeInterval, to end: TimeInterval, on scale: EnergyScale = .library) -> Int? {
        let timed = timedSectionLevels(on: scale)
        let first = max(0, Int(start / Double(hopSeconds)))
        let last = min(timed.count, Int((end / Double(hopSeconds)).rounded(.up)))
        guard first < last else { return nil }
        let levels = timed[first..<last].compactMap { $0 }.sorted()
        return levels.isEmpty ? nil : levels[(levels.count - 1) / 2]
    }

    /// The song's readout, or nil when it has no audible second.
    public func readout(on scale: EnergyScale = .library) -> EnergyReadout? {
        let levels = sectionLevels(on: scale).sorted()
        guard !levels.isEmpty else { return nil }
        let at = { (fraction: Double) in levels[Int(fraction * Double(levels.count - 1))] }
        return EnergyReadout(low: at(0.1), high: at(0.9), typical: at(0.5))
    }

    private static func runningMedian(_ values: [Float], half: Int = 5) -> [Float] {
        values.indices.map { i in
            let window = values[max(0, i - half)...min(values.count - 1, i + half)].sorted()
            return window[window.count / 2]
        }
    }
}

// MARK: - Profile energy (NRG.3)

extension TrackProfile {

    /// A curve covering less than this fraction of the track is a preview (streaming's 30 s): where
    /// it sits in the song is unknown, so the song's typical level stands in for every stretch.
    static let wholeTrackCoverage = 0.9

    /// The measured energy level (1–10) of the stretch `offset ..< offset + window` seconds into the
    /// track — what scene choice reads (D-259). nil when the profile has no curve.
    public func energyLevel(at offset: TimeInterval, window: TimeInterval, trackDuration: TimeInterval) -> Int? {
        guard let curve = energyCurve else { return nil }
        let covered = Double(curve.loudnessDB.count) * Double(curve.hopSeconds)
        guard trackDuration > 0, covered >= Self.wholeTrackCoverage * trackDuration else {
            return curve.readout()?.typical
        }
        // Near the song's end "the next `window` seconds" runs past the curve: read its last
        // `window` seconds instead of falling back to the whole song.
        let start = min(offset, max(0, covered - window))
        return curve.level(from: start, to: start + window) ?? curve.readout()?.typical
    }
}
