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
        /// The measured level of the stretch playing (`nil` = unknown → the middle energy).
        public let level: Int?
        /// The song's three dances, calmest first.
        public let repertoire: [KaguraDance]
        /// The bar just played, ranked in the song's trailing energy, 0…1 (0 while warming up).
        public let rank: Double
        /// The song's first `warmUpBars`: too little history to rank a bar, so the calm dance.
        public let warmingUp: Bool
        /// The dance the rank picked.
        public let dance: KaguraDance

        /// One session-log line.
        public var logLine: String {
            let shown = level.map(String.init) ?? "nil (middle energy)"
            let dances = repertoire.map(\.rawValue).joined(separator: ", ")
            let ranked = warmingUp ? "barRank=warm-up, " : String(format: "barRank=%.2f, ", rank)
            return "KAGURA_PICK: beat=\(beat), level=\(shown), " + ranked
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

    /// The song's energy sections (KAG.5; empty while unknown — the repertoire then uses the middle
    /// energy). Each clip change reads the section playing, so a new section's repertoire takes effect at
    /// the next clip change (a bar line), never mid-clip (§6).
    public mutating func setSongSections(_ sections: [KaguraSection]) { songSections = sections }

    /// A new track: forget the song's energy distribution (the grid push handles the dance itself).
    public mutating func resetSong() {
        energy.reset()
        songSections = []
        songPosition = nil
    }

    /// The measured level of the stretch playing now (`nil` = unknown).
    public var songLevel: Int? { KaguraRepertoire.section(at: songPosition, in: songSections)?.level }

    /// Seconds in one bar (4 beats when the grid declined the bar, D-210) — the window the dance
    /// pick and the silence rest read.
    static func barSeconds(_ grid: KaguraGrid) -> Double {
        Double(grid.knowsBars ? grid.beatsPerBar : 4) * grid.beatPeriod
    }

    /// A song's first bars: the pick has too little history to rank a bar (Matt, 2026-09-28, KAG.5 M7,
    /// option A). Before, the rank read the middle, and the middle of every calm set is the macarena, so
    /// the macarena opened most songs (session 2026-09-28T21-31-31Z).
    public static let warmUpBars: Double = 4

    /// §6: the song's repertoire, then the bar just played ranked in the song's trailing energy — during
    /// the warm-up, the calm dance.
    mutating func pickDance(grid: KaguraGrid, beat: Int) -> KaguraDance {
        let level = songLevel
        let repertoire = KaguraRepertoire.repertoire(bpm: 60 / grid.beatPeriod, level: level, library: library)
        let warmingUp = energy.windowFill < Self.warmUpBars * Self.barSeconds(grid)
        let rank = warmingUp ? 0 : energy.rank(ofLast: Self.barSeconds(grid))
        let dance = KaguraRepertoire.dance(forRank: rank, in: repertoire) ?? .twist
        picks.append(Pick(
            beat: beat,
            level: level,
            repertoire: repertoire,
            rank: rank,
            warmingUp: warmingUp,
            dance: dance
        ))
        return dance
    }

    /// Pulses into a clip at the bar line it enters on: a gesture dance as the spike (beat `p0 − 2` on
    /// pulse 1), a single repeated move on its first pulse.
    static func entryPulse(_ clip: KaguraClip, level: Double) -> Double {
        clip.pulseKind == "gesture" ? 1 + 2 / level : 0
    }

    // MARK: Rest (KAG.3 — Matt, 2026-09-28: ballet for calm songs' rests)

    /// Rest `clip` since `start`, ping-ponged (forward then backward) so it never wraps.
    func rawRest(_ clip: Int, start: Double) -> [SIMD3<Float>] {
        let turn = Self.restTurn(rests[clip])
        let folded = turn - abs((swayClock - start).truncatingRemainder(dividingBy: 2 * turn) - turn)
        return rests[clip].pose(at: folded)
    }

    /// A rest crossfades to another rest over this long (a song's calm arriving, the next ballet clip).
    static let restFadeSeconds: Double = 1.5

    /// Where a rest clip ping-pongs: the spike's 20 ms short of its end.
    static func restTurn(_ clip: KaguraClip) -> Double { max(clip.duration - swayTurnInset, 1e-3) }

    /// Whether the stretch playing is calm: a known level at or under `calmLevel` (KAG.5). A silence has
    /// no level of its own, so it reads the section it interrupts. Unknown is not calm — the sway.
    var songIsCalm: Bool {
        guard let level = songLevel else { return false }
        return level <= KaguraRepertoire.calmLevel
    }

    /// The rest to enter now: the next ballet clip in a calm stretch (rotating), else the sway.
    mutating func nextRest() -> Int {
        guard songIsCalm, rests.count > 1 else { return 0 }
        balletTurns += 1
        return 1 + (balletTurns - 1) % (rests.count - 1)
    }

    /// Whether the current rest should change: the stretch's calm and the rest disagree (energy arrived, a
    /// new section, or a new track), or a ballet clip has played once forward and back (the next one takes over).
    func restNeedsChange() -> Bool {
        guard case let .rest(clip, start, _) = current else { return false }
        if (clip > 0) != (songIsCalm && rests.count > 1) { return true }
        return clip > 0 && swayClock - start >= 2 * Self.restTurn(rests[clip])
    }

    /// The rest clip the dancer is in (or fading into) — the sway or a ballet clip — or `nil` while dancing.
    public var currentRest: KaguraClip? {
        if case let .rest(clip, _, _) = current { return rests[clip] }
        return nil
    }

    /// Midpoint of the ankles on the floor plane (x, z).
    func feet(_ joints: [SIMD3<Float>]) -> SIMD2<Float> {
        let mid = (joints[leftAnkle] + joints[rightAnkle]) * 0.5
        return SIMD2(mid.x, mid.z)
    }

    /// Pelvis floor position of a pose — the framing measure.
    public func pelvisFloor(_ joints: [SIMD3<Float>]) -> SIMD2<Float> {
        SIMD2(joints[pelvis].x, joints[pelvis].z)
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
