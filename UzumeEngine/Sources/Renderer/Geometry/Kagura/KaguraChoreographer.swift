// KaguraChoreographer — the dancer's CPU core: warp, clip changes, handoff, sway, framing (KAG.2).
//
// Pure and GPU-free, so `KaguraDancerTests` can drive it frame by frame. Ported from the KAG.0
// spike (`docs/presets/kagura_spike/kagura.py`, `build_dancer`), which is the behavioural oracle:
//
// - **Warp (KAGURA_DESIGN §5).** Pulse position `u = (p − p0) / m`, clip time
//   `c = clip.clipTime(atPulse: u)`, pose `clip.pose(at: c)`. `p0` is the bar line the clip
//   entered on, so the clip's first pulse lands on that beat and every later pulse on an integer
//   beat after it; the pulse map spreads the phase correction across each beat (never a jump).
// - **Level `m`** is `choose_level`: the allowed level whose playback rate is closest to 1. The
//   twist's allowed set excludes ×½ (Matt: never two turns per beat).
// - **Clip changes** on a bar line, at most every 4 bars, sooner if the clip's pulse map would run
//   out before the crossfade beat after the cut. The two twist clips alternate. With no bar
//   information the bar lines are every 4 beats (D-210).
// - **Handoff.** One-beat smoothstep crossfade; the incoming clip is offset so the midpoint of its
//   ankles matches the outgoing clip's at the cut. The camera never moves.
// - **Sway.** Clip `sway`, unwarped, ping-pong (a modulo wrap teleports the figure — the spike's
//   frame-339 pop). It plays with no grid and, on the streaming path, until the drift tracker
//   reports lock; it joins and leaves the dance at a bar line with the same crossfade, and its
//   clock never stops, so it never freezes.
// - **Framing — the causal leash.** The spike's leash subtracts a ZERO-PHASE Gaussian (σ 2 s) of
//   the pelvis floor path, which needs the future. Here the clips are already centred on their
//   mean pelvis (KAG.1 bake), so the only thing that walks the figure out of frame is the
//   handoff offsets accumulating clip after clip. Each offset decays to zero with τ = 2 s (the
//   spike's σ): the figure is pulled back to centre by the same slow drift the spike's leash
//   applied, and nothing moves when no handoff offset is outstanding. Its foot-slide cost is
//   measured against the spike's in the KAG.2 closeout.

import Foundation
import simd

// MARK: - KaguraChoreographer

/// Kagura's dancer, frame by frame: world joint positions (metres, y up) for a beat position.
public struct KaguraChoreographer: Sendable {

    // MARK: Constants

    /// Handoff offsets decay with this time constant (the spike's leash σ, 2 s).
    public static let leashSeconds: Double = 2.0
    /// A clip plays at most this many bars before the next change (spike `bars_per_clip`).
    public static let maxBarsPerClip = 4
    /// The spike's ping-pong turns 20 ms short of the sway clip's end.
    static let swayTurnInset: Double = 0.02

    // MARK: Types

    private enum Segment: Sendable {
        /// A warped dance clip entered on bar line `entry` at level `level` grid beats per pulse.
        case dance(clip: Int, entry: Double, level: Double, offset: SIMD2<Float>)
        /// The unwarped sway, sampled on `swayClock`.
        case sway(offset: SIMD2<Float>)

        var isDance: Bool { if case .dance = self { return true } else { return false } }

        var offset: SIMD2<Float> {
            switch self {
            case .dance(_, _, _, let offset), .sway(let offset): return offset
            }
        }

        func withOffset(_ offset: SIMD2<Float>) -> Segment {
            switch self {
            case let .dance(clip, entry, level, _):
                return .dance(clip: clip, entry: entry, level: level, offset: offset)
            case .sway: return .sway(offset: offset)
            }
        }
    }

    private enum Fade: Sendable {
        /// A bar-line handoff: progress is beats since `start`.
        case beats(start: Double)
        /// The grid vanished or was replaced mid-dance: progress in seconds. The outgoing dance
        /// keeps its OWN beat, advanced at its old tempo — the new grid numbers beats differently.
        case seconds(elapsed: Double, duration: Double, outgoingBeat: Double?, rate: Double)
    }

    private struct Cut: Sendable {
        let beat: Int
        let toDance: Bool
    }

    // MARK: State

    private let dances: [KaguraClip]
    private let sway: KaguraClip
    private let pelvis: Int, leftAnkle: Int, rightAnkle: Int

    private var current: Segment = .sway(offset: .zero)
    private var previous: Segment?
    private var fade: Fade?
    private var nextCut: Cut?
    private var nextClip = 0
    private var knownGeneration: Int?
    /// Seconds of sway playback. Always advances, whatever the dancer is doing.
    private var swayClock: Double = 0
    /// Last beat position seen, and beats per second, for a dance fading out after its grid went.
    private var lastBeat: Double?
    private var beatsPerSecond: Double = 2

    // MARK: Test surface

    /// Beat indices at which a handoff started, in order (bar lines, by construction).
    public private(set) var cutBeats: [Int] = []
    /// Level chosen for each dance segment, in order.
    public private(set) var chosenLevels: [Double] = []
    /// Whether the dancer is (or is fading into) a dance rather than the sway.
    public var isDancing: Bool { current.isDance }

    // MARK: Init

    /// A choreographer dancing `dance`'s clips from `library`, with its sway as the fallback.
    public init?(library: KaguraClipLibrary, dance: KaguraDance = .twist) {
        let clips = library.clips(for: dance)
        let names = library.jointNames
        guard !clips.isEmpty, let sway = library.sway,
              let pelvis = names.firstIndex(of: "pelvis"),
              let leftAnkle = names.firstIndex(of: "lankle"),
              let rightAnkle = names.firstIndex(of: "rankle") else { return nil }
        dances = clips
        self.sway = sway
        self.pelvis = pelvis
        self.leftAnkle = leftAnkle
        self.rightAnkle = rightAnkle
    }

    // MARK: Level

    /// `choose_level`: the level (grid beats per pulse) whose playback rate is closest to 1.
    public static func chooseLevel(pulsePeriod: Double, beatPeriod: Double, levels: [Double]) -> Double {
        levels.min { abs(log(pulsePeriod / ($0 * beatPeriod))) < abs(log(pulsePeriod / ($1 * beatPeriod))) } ?? 1
    }

    // MARK: Advance

    /// Advance one render frame and return the joints (library order, metres).
    ///
    /// - Parameters:
    ///   - deltaTime: render seconds since the last frame (clamped as Witchlight clamps).
    ///   - beat: `p(t)` from `KaguraBeatClock`, or `nil` with no grid or no clock yet.
    ///   - grid: the installed grid.
    ///   - gridGeneration: `KaguraBeatClock.gridGeneration`; a change means a new or cleared grid.
    ///   - dancePermitted: `KaguraBeatClock.dancePermitted`.
    public mutating func advance(
        deltaTime: Double, beat: Double?, grid: KaguraGrid?, gridGeneration: Int, dancePermitted: Bool
    ) -> [SIMD3<Float>] {
        let dt = min(max(deltaTime > 0 ? deltaTime : 1.0 / 60.0, 1.0 / 240.0), 1.0 / 30.0)
        swayClock += dt
        let pull = Float(exp(-dt / Self.leashSeconds))
        current = current.withOffset(current.offset * pull)
        previous = previous.map { $0.withOffset($0.offset * pull) }

        handleGridChange(generation: gridGeneration, grid: grid)   // fades out at the OLD tempo
        if let grid { beatsPerSecond = 1 / grid.beatPeriod }
        // A clock gap under a live dance (the per-track clock reset lands a frame before the new
        // grid does) dead-reckons at the grid tempo instead of snapping the clip to its start.
        let beat = beat ?? (current.isDance && grid != nil ? lastBeat.map { $0 + beatsPerSecond * dt } : nil)
        if let beat { lastBeat = beat }

        if let grid, let beat {
            schedule(beat: beat, grid: grid, dancePermitted: dancePermitted)
            if let cut = nextCut, beat >= Double(cut.beat) { perform(cut, grid: grid, beat: beat) }
        }
        return pose(at: beat, dt: dt)
    }

    // MARK: Scheduling

    private mutating func handleGridChange(generation: Int, grid: KaguraGrid?) {
        defer { knownGeneration = generation }
        guard let known = knownGeneration, known != generation else { return }
        nextCut = nil
        guard current.isDance else { return }
        // A replaced or cleared grid renumbers the beats, so the dance cannot continue on it.
        // Fade to the sway over one nominal beat; the new grid rejoins at its next bar line.
        // ponytail: a grid change inside a one-beat bar-line fade drops that fade's outgoing pose
        // (a small pop); it needs a grid replaced within that exact beat. Blend three poses if seen.
        let outgoing = displayed(current, beat: lastBeat)
        let target = Segment.sway(offset: feet(rawSway()) - feet(outgoing))
        previous = current
        current = target
        fade = .seconds(elapsed: 0, duration: 1 / beatsPerSecond, outgoingBeat: lastBeat, rate: beatsPerSecond)
    }

    private mutating func schedule(beat: Double, grid: KaguraGrid, dancePermitted: Bool) {
        switch (current, nextCut) {
        case (.sway, nil) where dancePermitted:
            nextCut = Cut(beat: grid.nextBarLine(after: beat), toDance: true)
        case (.sway, .some) where !dancePermitted:
            nextCut = nil
        case (.dance, let cut) where !dancePermitted && cut?.toDance != false:
            nextCut = Cut(beat: min(grid.nextBarLine(after: beat), cut?.beat ?? .max), toDance: false)
        case let (.dance(clip, entry, level, _), cut) where dancePermitted && cut?.toDance != true:
            nextCut = plannedDanceCut(clip: clip, entry: entry, level: level, grid: grid)
        default:
            break
        }
    }

    /// The last bar line within `maxBarsPerClip` bars of `entry` at which the clip still covers
    /// the crossfade beat after the cut; a beat before its pulse map runs out if no bar line fits.
    private func plannedDanceCut(clip: Int, entry: Double, level: Double, grid: KaguraGrid) -> Cut {
        let span = dances[clip].pulseSpan
        let fits = { (cut: Int) in (Double(cut) + 1 - entry) / level <= span }
        var best: Int?
        var line = Double(entry)
        for _ in 0..<Self.maxBarsPerClip {
            let next = grid.nextBarLine(after: line)
            if fits(next) { best = next }
            line = Double(next)
        }
        let fallback = Int(entry) + max(1, Int(floor(span * level)) - 1)
        return Cut(beat: best ?? fallback, toDance: true)
    }

    private mutating func perform(_ cut: Cut, grid: KaguraGrid, beat: Double) {
        guard fade == nil else {
            // Never blend three poses: a cut that lands inside a fade waits for the next bar line.
            nextCut = Cut(beat: grid.nextBarLine(after: beat), toDance: cut.toDance)
            return
        }
        let entry = Double(cut.beat)
        let outgoing = displayed(current, beat: entry)
        let incoming: Segment
        if cut.toDance {
            let index = nextClip % dances.count
            nextClip += 1
            let clip = dances[index]
            let level = Self.chooseLevel(
                pulsePeriod: clip.pulsePeriod ?? grid.beatPeriod,
                beatPeriod: grid.beatPeriod,
                levels: clip.allowedLevels)
            chosenLevels.append(level)
            let raw = clip.pose(at: clip.clipTime(atPulse: 0))
            incoming = .dance(clip: index, entry: entry, level: level, offset: feet(raw) - feet(outgoing))
            nextCut = plannedDanceCut(clip: index, entry: entry, level: level, grid: grid)
        } else {
            incoming = .sway(offset: feet(rawSway()) - feet(outgoing))
            nextCut = nil
        }
        cutBeats.append(cut.beat)
        previous = current
        current = incoming
        fade = .beats(start: entry)
    }

    // MARK: Pose

    private mutating func pose(at beat: Double?, dt: Double) -> [SIMD3<Float>] {
        var weight: Double = 1
        var outgoingBeat = beat
        switch fade {
        case .beats(let start):
            weight = min(max((beat ?? start) - start, 0), 1)
        case let .seconds(elapsed, duration, oldBeat, rate):
            outgoingBeat = oldBeat.map { $0 + rate * dt }
            fade = .seconds(elapsed: elapsed + dt, duration: duration, outgoingBeat: outgoingBeat, rate: rate)
            weight = min((elapsed + dt) / max(duration, 1e-3), 1)
        case nil:
            break
        }
        if weight >= 1 { fade = nil; previous = nil }
        let incoming = displayed(current, beat: beat)
        guard let previous else { return incoming }
        let outgoing = displayed(previous, beat: outgoingBeat)
        let blend = Float(weight * weight * (3 - 2 * weight))
        return zip(outgoing, incoming).map { simd_mix($0, $1, SIMD3(repeating: blend)) }
    }

    /// A segment's joints at `beat`, minus its handoff offset (floor plane only).
    private func displayed(_ segment: Segment, beat: Double?) -> [SIMD3<Float>] {
        let raw: [SIMD3<Float>]
        switch segment {
        case let .dance(clip, entry, level, _):
            let pulse = ((beat ?? entry) - entry) / level
            raw = dances[clip].pose(at: dances[clip].clipTime(atPulse: pulse))
        case .sway:
            raw = rawSway()
        }
        let offset = segment.offset
        return raw.map { SIMD3($0.x - offset.x, $0.y, $0.z - offset.y) }
    }

    /// The sway at `swayClock`, ping-ponged (forward then backward) so it never wraps.
    private func rawSway() -> [SIMD3<Float>] {
        let turn = max(sway.duration - Self.swayTurnInset, 1e-3)
        let folded = turn - abs(swayClock.truncatingRemainder(dividingBy: 2 * turn) - turn)
        return sway.pose(at: folded)
    }

    /// Midpoint of the ankles on the floor plane (x, z).
    private func feet(_ joints: [SIMD3<Float>]) -> SIMD2<Float> {
        let mid = (joints[leftAnkle] + joints[rightAnkle]) * 0.5
        return SIMD2(mid.x, mid.z)
    }

    /// Pelvis floor position of a pose — the framing measure.
    public func pelvisFloor(_ joints: [SIMD3<Float>]) -> SIMD2<Float> {
        SIMD2(joints[pelvis].x, joints[pelvis].z)
    }
}
