// EnergySections — a track's stretches between its energy changes, each judged by its loud end (KAG.5).
//
// Kagura's dances follow the measured energy of the part of the song playing (D-259 §1, §4 amendment).
// A stretch is judged by its loudest tenth — the 90th-percentile section level, the same rule as the
// readout's `high` (Matt, 2026-09-28, KAG.5: the median put Dance Yrself Clean's drop at 8, where its
// tempo does not earn the twist). The cuts are NRG.4's `energyChanges`, unchanged: the planner's too.

import Foundation

// MARK: - EnergySection

/// One stretch of a track and its loud-end energy level.
public struct EnergySection: Sendable, Equatable {
    /// Seconds into the track the stretch starts.
    public let start: TimeInterval
    /// The stretch's 90th-percentile section level (1–10), or nil when it holds no audible second.
    public let loudEnd: Int?
}

/// What a track's energy curve covers.
public enum EnergyCoverage: String, Sendable {
    /// The whole track (local files): sections at the energy changes.
    case whole
    /// A preview (streaming's 30 s): its place in the song is unknown, so one section stands for all.
    case preview
    /// No curve (a cache miss): no energy.
    case none
}

// MARK: - Curve + profile

extension EnergyCurve {

    /// The 90th-percentile section level over seconds `start ..< end` (the readout's `high` index rule),
    /// or nil when that stretch holds no audible second.
    public func loudEnd(from start: TimeInterval, to end: TimeInterval, on scale: EnergyScale = .library) -> Int? {
        let timed = timedSectionLevels(on: scale)
        let first = max(0, Int(start / Double(hopSeconds)))
        let last = min(timed.count, Int((end / Double(hopSeconds)).rounded(.up)))
        guard first < last else { return nil }
        let levels = timed[first..<last].compactMap { $0 }.sorted()
        return levels.isEmpty ? nil : levels[Int(0.9 * Double(levels.count - 1))]
    }
}

extension TrackProfile {

    /// The track's energy sections: on a whole-track curve, the stretches between `energyChanges`; on a
    /// preview, one section over the preview; with no curve, none.
    public func energySections(trackDuration: TimeInterval) -> (coverage: EnergyCoverage, sections: [EnergySection]) {
        guard let curve = energyCurve else { return (.none, []) }
        let covered = Double(curve.loudnessDB.count) * Double(curve.hopSeconds)
        guard let whole = wholeTrackCurve(trackDuration: trackDuration) else {
            return (.preview, [EnergySection(start: 0, loudEnd: curve.loudEnd(from: 0, to: covered))])
        }
        let starts = [0] + energyChanges(trackDuration: trackDuration)
        let ends = starts.dropFirst() + [max(covered, trackDuration)]
        return (.whole, zip(starts, ends).map { EnergySection(start: $0, loudEnd: whole.loudEnd(from: $0, to: $1)) })
    }
}
