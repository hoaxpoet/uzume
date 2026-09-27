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
        let kept = loudnessDB.indices.filter { loudnessDB[$0] > Self.silenceFloorDB }
        let loud = Self.runningMedian(kept.map { loudnessDB[$0] })
        let act = Self.runningMedian(kept.map { activity[$0] })
        return zip(loud, act).map { scale.level(loudnessDB: $0, activity: $1) }
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
