// KaguraSelection — which dance, how far the arms reach, and when to rest (KAG.3).
//
// Ported from the KAG.0 spike (`docs/presets/kagura_spike/kagura.py`), the behavioural oracle (FA #73):
//
// - **Repertoire (KAGURA_DESIGN §6 items 1–2)** — `dance_profile`, `pick_repertoire` verbatim. The inputs
//   are the measured energy level of the stretch playing (D-259; KAG.5 retired the spike's
//   `song_energy` mood rank) and the grid BPM; the dance profiles come from the KAG.1 manifest
//   (vigor, pulse period, allowed levels), which the bake reproduced from the spike.
// - **Energy (§6 item 3, §8)** — the spike's envelope: `bass_att` through a 1.5 s EMA (per elapsed
//   time, never per frame — BUG-097). The spike ranked and normalised it against a whole 30 s window
//   with lookahead; no whole-track `bass_att` exists on either path (§6 correction), so both read a
//   TRAILING ~60 s window, sampled at a fixed 20 Hz so its weighting does not depend on the frame rate.
//   The dance pick ranks the bar JUST PLAYED (Matt, 2026-09-25, option A); arm reach normalises by the
//   window's p10–p90.
// - **Safety net (§7)** — the coefficient of variation of the last 16 grid inter-beat intervals, with
//   hysteresis, evaluated as the dance advances.
// - **Silence (§3a)** — the same envelope under a floor for a full bar.

import Foundation

// MARK: - KaguraRepertoire

/// One stretch of the song, between two of its energy changes (NRG.4), and its measured energy (D-259).
public struct KaguraSection: Sendable, Equatable {
    /// Seconds into the track the stretch starts.
    public let start: Double
    /// The stretch's 1–10 level on the library scale — its loud end, the 90th-percentile level (Matt,
    /// 2026-09-28, KAG.5: a stretch is judged by its loudest tenth). `nil` = unknown.
    public let level: Int?

    public init(start: Double, level: Int?) {
        self.start = start
        self.level = level
    }
}

/// The song's three dances, from the measured energy of the stretch playing and the tempo (spike
/// `pick_repertoire`).
public enum KaguraRepertoire {

    /// The dances the repertoire picks from. The chicken dance is out (Matt, 2026-09-28, after three M7
    /// sessions: "a poor fit", "should be used sparingly, if at all"); its clips stay in the KAG.1 resource.
    public static let dances: [KaguraDance] = [.twist, .cabbage, .macarena, .egyptian, .charleston]
    /// Fast-song dances (Matt, 2026-09-28: the Charleston "for fast energetic songs"): eligible only at one
    /// pulse per beat within `fastSongRate` of natural speed, and their vigor is capped at the top of the
    /// other dances' scale. The Charleston's kicks (1.25 m/s against the twist's 0.71) would otherwise
    /// stretch the scale and push every other dance toward calm; uncapped and ungated, the spike's rule gave
    /// Dance Yrself Clean a 0.56× slow-motion Charleston in place of the twist and kept it off Take Five.
    public static let fastSongDances: Set<KaguraDance> = [.charleston]
    /// Playback rates a fast-song dance may play at: ±25 % around natural speed, the warp's own foot-slide
    /// tolerance for in-place material (spike README §4: under the line up to ×1.25). About 137–214 BPM
    /// for the Charleston's 171–176 steps a minute.
    public static let fastSongRate: ClosedRange<Double> = 0.8...1.25
    /// The spike's `DANCES` (README §9, §10 are reproduced against these).
    public static let spikeDances: [KaguraDance] = [.twist, .cabbage, .chicken, .macarena, .egyptian]

    /// Song energy with no measured level (no cache entry, or a stretch with no audible second): the
    /// middle of the scale (§6; KAG.3 task 2).
    public static let unknownEnergy = 0.5

    /// Levels at or under this are calm: the rest is ballet (Matt, 2026-09-28). The calm third of the
    /// 1–10 scale, the dance pick's own tercile: `energy(level: 3)` = 0.22, `energy(level: 4)` = 0.33.
    public static let calmLevel = 3

    /// Song energy, 0…1, from a stretch's measured 1–10 level on the library scale (D-259; KAG.5). The
    /// library scale is already a rank (deciles of 1,000 songs), so no playlist reference is needed.
    public static func energy(level: Int?) -> Double {
        level.map { Double(min(max($0, 1), 10) - 1) / 9 } ?? unknownEnergy
    }

    /// The stretch of the song playing at `seconds` into the track: the last section starting at or before
    /// it (the first section before the clock is known). `nil` with no sections.
    public static func section(at seconds: Double?, in sections: [KaguraSection]) -> KaguraSection? {
        sections.last { $0.start <= (seconds ?? 0) } ?? sections.first
    }

    /// A dance's `dance_profile`.
    public struct Profile: Sendable {
        /// Mean speed of wrists, ankles and head relative to the pelvis, m/s (mean over the clips).
        public let vigor: Double
        /// Pulse period, seconds (mean over the clips).
        public let period: Double
        /// The first clip's allowed levels.
        public let levels: [Double]
    }

    /// `dance_profile`: the dance's vigor, pulse period and allowed levels, from the KAG.1 manifest.
    public static func profile(_ dance: KaguraDance, library: KaguraClipLibrary) -> Profile? {
        let clips = library.clips(for: dance)
        let periods = clips.compactMap(\.pulsePeriod)
        guard let first = clips.first, periods.count == clips.count else { return nil }
        let vigor = clips.map(\.vigor).reduce(0, +) / Double(clips.count)
        return Profile(vigor: vigor, period: periods.reduce(0, +) / Double(periods.count), levels: first.allowedLevels)
    }

    private struct Scored {
        let index: Int
        let dance: KaguraDance
        let score: Double
        let vigor: Double
    }

    /// `pick_repertoire(bpm, energy, k=3)`: the `k` lowest-scoring dances, calmest first.
    /// Score = |log₂ playback rate at the best level| + |library-normalised vigor − song energy|.
    public static func pick(
        bpm: Double, energy: Double, library: KaguraClipLibrary, count: Int = 3, from dances: [KaguraDance] = dances
    ) -> [KaguraDance] {
        let profiles = dances.compactMap { dance in profile(dance, library: library).map { (dance, $0) } }
        let vigors = profiles.filter { !fastSongDances.contains($0.0) }.map(\.1.vigor)
        guard let low = vigors.min(), let high = vigors.max(), high > low, bpm > 0 else { return [] }
        let normalised = { (vigor: Double) in min((vigor - low) / (high - low), 1) }
        let gridPeriod = 60 / bpm
        let scored = profiles.enumerated().compactMap { index, entry -> Scored? in
            let level = KaguraChoreographer.chooseLevel(
                pulsePeriod: entry.1.period, beatPeriod: gridPeriod, levels: entry.1.levels)
            let rate = entry.1.period / (level * gridPeriod)
            if fastSongDances.contains(entry.0), level != 1 || !fastSongRate.contains(rate) { return nil }
            let vigor = normalised(entry.1.vigor)
            return Scored(index: index, dance: entry.0, score: abs(log2(rate)) + abs(vigor - energy), vigor: vigor)
        }
        // numpy's `sorted` is stable: ties keep `DANCES` order.
        let best = scored.sorted { ($0.score, $0.index) < ($1.score, $1.index) }.prefix(count)
        return best.sorted { ($0.vigor, $0.index) < ($1.vigor, $1.index) }.map(\.dance)
    }

    /// The three dances for a stretch at `level` (KAG.5), calmest first. A fast-song dance in its tempo band
    /// always takes one of the three, whatever the energy (Matt, 2026-09-28, B: "tempo earns the
    /// Charleston"); energy picks the rest by `pick`. Its capped vigor sorts it last, so the bar pick
    /// gives it the vigorous third: a quiet fast song kicks on its loud bars only.
    public static func repertoire(
        bpm: Double, level: Int?, library: KaguraClipLibrary, count: Int = 3
    ) -> [KaguraDance] {
        let energy = energy(level: level)
        let fast = pick(bpm: bpm, energy: energy, library: library, count: dances.count).filter(fastSongDances.contains)
        let others = dances.filter { !fastSongDances.contains($0) }
        return pick(bpm: bpm, energy: energy, library: library, count: max(count - fast.count, 0), from: others) + fast
    }

    /// The dance for a bar whose energy ranks `rank` (0…1) in the song: calm, middle or vigorous by
    /// tercile (spike `rep[min(int(le * len(rep)), len(rep) - 1)]`).
    public static func dance(forRank rank: Double, in repertoire: [KaguraDance]) -> KaguraDance? {
        guard !repertoire.isEmpty else { return nil }
        return repertoire[min(max(Int(rank * Double(repertoire.count)), 0), repertoire.count - 1)]
    }
}

// MARK: - KaguraEnergy

/// The smoothed bass envelope and its trailing distribution — the dance pick and arm reach (§6, §8).
public struct KaguraEnergy: Sendable {

    /// The spike's envelope time constant.
    public static let smoothingSeconds: Double = 1.5
    /// Trailing window the song-relative rank and p10–p90 read (§6: "~60 s").
    public static let windowSeconds: Double = 60
    /// The window is sampled at this fixed rate, so its weighting is frame-rate independent.
    public static let sampleRate: Double = 20
    /// Arm reach swings at most this fraction about the neutral pose (§8).
    public static let reachAmplitude: Double = 0.25
    /// Reach fades in over the first seconds of a window, so the first few samples — whose p10–p90 is
    /// near zero and saturates `tanh` — cannot throw the arms to an extreme at track start.
    public static let reachRampSeconds: Double = 4
    /// The p10–p90 width reach normalises by never goes under this. The narrowest window measured on 80
    /// production-chain captures (the beta playlist, the spike sessions, the route-coverage fixtures) is
    /// 0.0117 (Smells Like Teen Spirit 50 %; median 0.065), so real music is normalised exactly as the
    /// spike did; only a flat stretch (a held tone, the zeros of silence) is kept from dividing by ~0.
    public static let minimumBand: Double = 0.01
    /// Reach changes by at most this much per second. The spike's formula peaks at 0.84 / s on the same
    /// 80 captures (YYZ; median of maxima 0.36), so real music never meets the limit. Without it, a band
    /// collapsed by a steady stretch saturates `tanh` on the first change — a drop into silence moved a
    /// wrist 0.108 m in one frame (KaguraSelectionTests, first run).
    public static let maxReachRate: Double = 1.0
    /// Silence floor on the envelope (§3a). Measured at KAG.3: the quietest beat-bearing bar on the 30
    /// beta-playlist captures peaks at 0.065 (B.O.B. 80 %; Penny Lane's quietest 0.166), and a real track
    /// end (Warszawa's tail, production chain) reads 0.0047 at its first silent row, then 0.001. The
    /// floor sits 3× under the quietest music and 4× over the fade. A GATE on a value that is exactly 0
    /// when the input is silent (BUG-130 feeds zeros), not a driver (FA #31).
    public static let silenceFloor: Double = 0.02

    /// The 1.5 s EMA of `bass_att`; `nil` before the first frame.
    public private(set) var envelope: Double?
    private var samples: [Double] = []
    private var sampleClock: Double = 0
    /// p10 / p90 of the window, refreshed on every sample.
    private var band: (low: Double, high: Double)?
    /// Arm-reach scale, 0.75…1.25: `1 + 0.25·tanh((e − mid) / (p90 − p10) · 2)` (spike `scale_of`),
    /// rate-limited by `maxReachRate`.
    public private(set) var reach: Double = 1

    public init() {}

    /// Seconds of envelope the window holds.
    public var windowFill: Double { Double(samples.count) / Self.sampleRate }

    /// Advance by `deltaTime` render seconds with this frame's `bass_att`.
    public mutating func advance(bass: Double, deltaTime: Double) {
        let current = envelope.map { $0 + (1 - exp(-deltaTime / Self.smoothingSeconds)) * (bass - $0) } ?? bass
        envelope = current
        sampleClock += deltaTime
        let step = 1 / Self.sampleRate
        if sampleClock >= step {
            while sampleClock >= step {
                sampleClock -= step
                samples.append(current)
            }
            let capacity = Int(Self.windowSeconds * Self.sampleRate)
            if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
            let sorted = samples.sorted()
            band = (Self.percentile(sorted, 10), Self.percentile(sorted, 90))
        }
        let limit = Self.maxReachRate * deltaTime
        reach += min(max(reachTarget - reach, -limit), limit)
    }

    /// The song-relative energy of the last `seconds` (one bar), 0…1: the bar's mean envelope ranked among
    /// the means of every bar-long stretch in the window (Matt, 2026-09-28, step 2). The spike averaged
    /// the per-sample ranks of the bar's moments (`erank[w].mean()`); an average of ranks crowds toward
    /// ½, and live it put 62 % of picks in the middle third (49 of 79, session 2026-09-28T13-56-00Z) —
    /// on energetic songs the cabbage patch, with the twist 1 change in 21. Ranking a bar against bars
    /// gives each third its share while a loud stretch still ranks loud (no rotation term).
    /// `unknownEnergy` until the window holds two bars' worth of stretches.
    public func rank(ofLast seconds: Double) -> Double {
        let length = max(1, Int((seconds * Self.sampleRate).rounded()))
        guard samples.count > length else { return KaguraRepertoire.unknownEnergy }
        var prefix = [0.0]
        prefix.reserveCapacity(samples.count + 1)
        for value in samples { prefix.append(prefix[prefix.count - 1] + value) }
        let means = (length...samples.count).map { (prefix[$0] - prefix[$0 - length]) / Double(length) }
        guard let latest = means.last else { return KaguraRepertoire.unknownEnergy }
        let sorted = means.sorted()
        // The bar's position among the bars (ties take the middle of their run).
        let below = Double(Self.lowerBound(sorted, latest))
        let atOrBelow = Double(Self.upperBound(sorted, latest))
        return min((below + atOrBelow - 1) / 2 / Double(sorted.count - 1), 1)
    }

    /// The unlimited reach this frame's envelope asks for.
    private var reachTarget: Double {
        guard let envelope, let band else { return 1 }
        let mid = (band.low + band.high) / 2
        let swing = tanh((envelope - mid) / max(band.high - band.low, Self.minimumBand) * 2)
        return 1 + Self.reachAmplitude * swing * min(windowFill / Self.reachRampSeconds, 1)
    }

    /// Whether the envelope stayed under the silence floor for the whole last `seconds` (§3a) — or, in
    /// a window younger than that, for all of it: a track that OPENS silent has no music to leave, and
    /// waiting a bar would let the dancer start a dance on the first bar line of the silence.
    public func isSilent(forLast seconds: Double) -> Bool {
        guard let envelope, envelope < Self.silenceFloor else { return false }
        let needed = max(1, Int((seconds * Self.sampleRate).rounded(.up)))
        return samples.suffix(needed).allSatisfy { $0 < Self.silenceFloor }
    }

    /// Forget the song: a new track ranks against its own bars.
    public mutating func reset() { self = KaguraEnergy() }

    // MARK: Helpers

    /// numpy's default (linear) percentile.
    static func percentile(_ sorted: [Double], _ percent: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let position = percent / 100 * Double(sorted.count - 1)
        let lower = Int(position)
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (position - Double(lower)) * (sorted[upper] - sorted[lower])
    }

    private static func lowerBound(_ sorted: [Double], _ value: Double) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi { let mid = (lo + hi) / 2; if sorted[mid] < value { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    private static func upperBound(_ sorted: [Double], _ value: Double) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi { let mid = (lo + hi) / 2; if sorted[mid] <= value { lo = mid + 1 } else { hi = mid } }
        return lo
    }
}

// MARK: - KaguraSafetyNet

/// The per-section grid-CV safety net (§7): sway while the grid's own recent beat spacing is uneven.
///
/// Thresholds, from the rolling 16-interval CV on the 30 beta-playlist captures (KAG.3; README §11 has
/// the per-window figures): every steady window stays at or under 0.062 (Take Five 50 %; median of the
/// steady windows' maxima 0.029), every irregular one at or over 0.102 (Moonlight 80 %).
/// - **Enter** above 0.08 (the spike's `GRID_CV_SWAY`, in that gap).
/// - **Rejoin** once the CV has stayed under 0.06 for 8 beats: under 0.06 is at or below every steady
///   window's p90 (max 0.059), so a steady stretch rejoins; 8 beats is two bars of 4/4, half the
///   16-interval window, so one steady-looking run inside an irregular section does not flip it back.
public struct KaguraSafetyNet: Sendable {

    /// Intervals the CV reads (§7).
    public static let window = 16
    /// Sway above this CV.
    public static let enterCV = 0.08
    /// Rejoin once under this CV …
    public static let exitCV = 0.06
    /// … for this many consecutive beats.
    public static let exitBeats = 8

    /// Whether the grid is currently judged too uneven to dance to.
    public private(set) var irregular = false
    private var lastBeat: Int?
    private var steadyBeats = 0

    public init() {}

    /// The CV of the `window` intervals ending at beat `index` (clamped to the grid's start); `nil` with
    /// fewer than 3 intervals (the spike's `len(ibi) > 2`).
    public static func cv(of grid: KaguraGrid, endingAt index: Int) -> Double? {
        let beats = grid.beats
        let end = min(max(index, min(window, beats.count - 1)), beats.count - 1)
        let start = max(end - window, 0)
        guard end - start >= 3 else { return nil }
        let intervals = (start..<end).map { beats[$0 + 1] - beats[$0] }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(intervals.count)
        return mean > 0 ? variance.squareRoot() / mean : nil
    }

    /// Step to beat position `beat` of `grid`; evaluates once per beat crossed.
    public mutating func advance(beat: Double, grid: KaguraGrid) {
        let index = Int(floor(beat))
        guard index != lastBeat else { return }
        lastBeat = index
        guard let cv = Self.cv(of: grid, endingAt: index) else { return }
        if cv > Self.enterCV {
            irregular = true
            steadyBeats = 0
        } else if irregular {
            steadyBeats = cv < Self.exitCV ? steadyBeats + 1 : 0
            if steadyBeats >= Self.exitBeats { irregular = false; steadyBeats = 0 }
        }
    }

    /// A new or cleared grid starts steady and is judged afresh.
    public mutating func reset() { self = KaguraSafetyNet() }
}
