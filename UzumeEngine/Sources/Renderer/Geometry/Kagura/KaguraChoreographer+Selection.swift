// KaguraChoreographer+Selection — the KAG.3 half of the choreographer: which dance, arm reach, the song.
//
// KAGURA_DESIGN §6 (the pick), §8 (arm reach). Split from `KaguraChoreographer.swift` for length; the
// mechanisms themselves are `KaguraSelection.swift`.

import Foundation
import simd

// MARK: - Types

extension KaguraChoreographer {

    /// The joints of one arm.
    struct Arm: Sendable {
        let shoulder: Int
        let elbow: Int
        let wrist: Int
    }

    /// What an auto pick read and chose — also the `KAGURA_PICK` session-log line.
    public struct Pick: Sendable, Equatable {
        /// The bar line (beat index) the dance starts on.
        public let beat: Int
        /// The song's arousal as pushed (`nil` = unknown → the middle energy).
        public let songArousal: Double?
        /// Song energy, 0…1 (§6 item 1).
        public let songEnergy: Double
        /// The song's three dances, calmest first.
        public let repertoire: [KaguraDance]
        /// The bar just played, ranked in the song's trailing energy, 0…1.
        public let rank: Double
        /// The dance the rank picked.
        public let dance: KaguraDance

        /// One session-log line.
        public var logLine: String {
            let arousal = songArousal.map { String(format: "%.3f", $0) } ?? "nil (middle energy)"
            let dances = repertoire.map(\.rawValue).joined(separator: ", ")
            let numbers = String(format: "songEnergy=%.2f, barRank=%.2f", songEnergy, rank)
            return "KAGURA_PICK: beat=\(beat), songArousal=\(arousal), \(numbers), "
                + "repertoire=[\(dances)] → \(dance.rawValue)"
        }
    }
}

// MARK: - Song + pick + reach

extension KaguraChoreographer {

    /// `choose_level`: the level (grid beats per pulse) whose playback rate is closest to 1.
    public static func chooseLevel(pulsePeriod: Double, beatPeriod: Double, levels: [Double]) -> Double {
        levels.min { abs(log(pulsePeriod / ($0 * beatPeriod))) < abs(log(pulsePeriod / ($1 * beatPeriod))) } ?? 1
    }

    /// The song's arousal (`TrackProfile.songArousal`), or `nil` while unknown — the repertoire then
    /// uses the middle energy, and re-picks at the next clip change once it arrives (§6).
    public mutating func setSongArousal(_ arousal: Double?) { songArousal = arousal }

    /// A new track: forget the song's energy distribution (the grid push handles the dance itself).
    public mutating func resetSong() {
        energy.reset()
        songArousal = nil
    }

    /// Seconds in one bar (4 beats when the grid declined the bar, D-210) — the window the dance
    /// pick and the silence rest read.
    static func barSeconds(_ grid: KaguraGrid) -> Double {
        Double(grid.knowsBars ? grid.beatsPerBar : 4) * grid.beatPeriod
    }

    /// §6: the song's repertoire, then the bar just played ranked in the song's trailing energy.
    mutating func pickDance(grid: KaguraGrid, beat: Int) -> KaguraDance {
        let songEnergy = songArousal.map { KaguraRepertoire.songEnergy(arousal: $0) } ?? KaguraRepertoire.unknownEnergy
        let repertoire = KaguraRepertoire.pick(bpm: 60 / grid.beatPeriod, energy: songEnergy, library: library)
        let rank = energy.rank(ofLast: Self.barSeconds(grid))
        let dance = KaguraRepertoire.dance(forRank: rank, in: repertoire) ?? .twist
        picks.append(Pick(
            beat: beat,
            songArousal: songArousal,
            songEnergy: songEnergy,
            repertoire: repertoire,
            rank: rank,
            dance: dance
        ))
        return dance
    }

    /// Elbows and wrists scaled about their shoulder by the arm reach (§8); legs untouched.
    mutating func reached(_ joints: [SIMD3<Float>]) -> [SIMD3<Float>] {
        lastReach = energy.reach
        let scale = Float(lastReach)
        guard scale != 1 else { return joints }
        var out = joints
        for arm in arms {
            let shoulder = joints[arm.shoulder]
            out[arm.elbow] = shoulder + scale * (joints[arm.elbow] - shoulder)
            out[arm.wrist] = shoulder + scale * (joints[arm.wrist] - shoulder)
        }
        return out
    }
}

// MARK: - Test surface

extension KaguraChoreographer {

    /// The dance the current segment plays (`nil` for the sway), and the one it is fading from.
    public var currentDance: KaguraDance? { dance(of: current) }
    public var fadingFromDance: KaguraDance? { previous.flatMap { dance(of: $0) } }
    /// Whether a crossfade is in progress, and whether it is the sway joining or leaving.
    public var isFading: Bool { previous != nil }
    public var fadeTouchesSway: Bool { previous.map { !$0.isDance || !current.isDance } ?? false }
    /// Whether the safety net currently holds the dancer in the sway (§7).
    public var gridIrregular: Bool { safetyNet.irregular }
    /// The trailing bass envelope (test surface).
    public var energyState: KaguraEnergy { energy }

    func dance(of segment: Segment) -> KaguraDance? {
        if case let .dance(clip, _, _, _) = segment { return dances[clip].dance }
        return nil
    }
}
