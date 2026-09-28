// KaguraChoreographer — the dancer's CPU core: warp, clip changes, handoff, sway, framing (KAG.2),
// and the choice of dance, arm reach and the safety nets (KAG.3, `KaguraSelection`).
//
// Pure and GPU-free, so `KaguraDancerTests` can drive it frame by frame. Ported from the KAG.0
// spike (`docs/presets/kagura_spike/kagura.py`, `build_dancer`), which is the behavioural oracle:
//
// - **Warp (KAGURA_DESIGN §5).** Pulse position `u = 1 + (p − (p0 − 2)) / m`, clip time
//   `c = clip.clipTime(atPulse: u)`, pose `clip.pose(at: c)`. `p0` is the bar line the clip
//   entered on. A GESTURE dance enters as the spike's did: beat p0 − 2 pins its second pulse
//   (`warp_map(..., start_event=1)` on beats from t0 − 2), 1 + 2/m pulses in — entering on the first
//   pulse moved its landings up to 13 points off the spike's lock. The twist and cabbage patch (one
//   repeated move; 100 % locked either way) enter on the first pulse, as KAG.2 did: the spike's
//   entry made the twist's planted feet slide ~⅓ more (Matt, 2026-09-25: split by dance).
// - **Level `m`** is `choose_level`: the allowed level whose playback rate is closest to 1. The
//   twist's allowed set excludes ×½ (Matt: never two turns per beat).
// - **Clip changes** on a bar line: the last one within 4 bars (+ ½ beat) that is at least ½ beat
//   before the clip's pulses run out; if none fits, the next bar line, the clip playing on to its
//   own end meanwhile (spike `build_dancer`: `limit`, `ok`, `nxt`). Each dance alternates its
//   clips. With no bar information the bar lines are every 4 beats (D-210).
// - **Handoff.** One-beat smoothstep crossfade; the incoming clip is offset so the midpoint of its
//   ankles matches the outgoing clip's at the cut. The camera never moves.
// - **Sway.** Clip `sway`, unwarped, ping-pong (a modulo wrap teleports the figure). It plays with
//   no grid and, streaming, until the drift tracker locks; it joins and leaves at a bar line with
//   the same crossfade, and its clock never stops, so it never freezes.
// - **Framing — the causal leash.** The spike's leash subtracts a ZERO-PHASE Gaussian (σ 2 s) of
//   the pelvis floor path, which needs the future. Here the clips are already centred on their
//   mean pelvis (KAG.1 bake), so the only thing that walks the figure out of frame is the
//   handoff offsets accumulating clip after clip. Each offset decays to zero with τ = 2 s (the
//   spike's σ): the figure is pulled back to centre by the same slow drift the spike's leash
//   applied, and nothing moves when no handoff offset is outstanding. Its foot-slide cost is
//   measured against the spike's in the KAG.2 closeout.
//
// KAG.3 (KAGURA_DESIGN §6–§8, §3a):
// - **The dance** at each clip change: the repertoire (the playing stretch's energy + grid BPM), then the
//   bar just played ranked in the song's trailing energy picks calm / middle / vigorous. Each dance
//   alternates its own clips. No anti-repeat term (Matt: "follow the song's energy").
// - **Arm reach**: elbows and wrists scale about their shoulder by `KaguraEnergy.reach`. The legs are
//   never scaled (a scaled planted foot drags; spike §3).
// - **Rest**: the dancer sways while the grid's recent beat spacing is uneven (`KaguraSafetyNet`) or
//   the bass envelope has sat under the silence floor for a full bar, leaving and rejoining the dance
//   at bar lines. A declined bar is NOT a reason to rest (D-210). If the beat itself stops advancing
//   (a paused or ended local file holds its playback clock — BUG-130's 1.5 s bound), no bar line will
//   ever come, so the dance fades to the sway over one beat of render time instead.

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
    /// A beat position that has not advanced for this long (render seconds) is a stopped clock.
    public static let stallSeconds: Double = 0.5
    /// … where "not advanced" is moving at under this fraction of the grid tempo.
    static let stallFraction: Double = 0.25

    // MARK: Types

    enum Segment: Sendable {
        /// A warped dance clip entered on bar line `entry` at level `level` grid beats per pulse.
        case dance(clip: Int, entry: Double, level: Double, offset: SIMD2<Float>)
        /// An unwarped rest (`rests[clip]`: the sway, or a ballet clip on calm songs), ping-ponged from
        /// `start` on `swayClock`.
        case rest(clip: Int, start: Double, offset: SIMD2<Float>)
        /// A pose held still: what was on screen when a fade had to start inside another fade.
        case held(joints: [SIMD3<Float>])

        var isDance: Bool { if case .dance = self { return true } else { return false } }

        var offset: SIMD2<Float> {
            switch self {
            case .dance(_, _, _, let offset), .rest(_, _, let offset): return offset
            case .held: return .zero
            }
        }

        func withOffset(_ offset: SIMD2<Float>) -> Segment {
            switch self {
            case let .dance(clip, entry, level, _):
                return .dance(clip: clip, entry: entry, level: level, offset: offset)
            case let .rest(clip, start, _): return .rest(clip: clip, start: start, offset: offset)
            case .held: return self
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

    // Internal, not private: `KaguraChoreographer+Selection` reads them (file length).
    let library: KaguraClipLibrary
    /// Every dance clip; segments index into it.
    let dances: [KaguraClip]
    /// `dances` indices per dance, in manifest order.
    private let clipIndices: [KaguraDance: [Int]]
    /// Fixed dances, cycled (tests, and the per-dance pulse-lock replay); empty picks by the song (§6).
    private let forcedDances: [KaguraDance]
    /// The unwarped rests: the sway first, then the ballet clips (KAG.3).
    let rests: [KaguraClip]
    private let pelvis: Int, leftAnkle: Int, rightAnkle: Int
    /// The joints of each arm.
    let arms: [Arm]

    var current: Segment = .rest(clip: 0, start: 0, offset: .zero)
    var previous: Segment?
    private var fade: Fade?
    private var nextCut: Cut?
    /// Clip changes per dance so far, so each dance alternates its clips.
    private var used: [KaguraDance: Int] = [:]
    private var knownGeneration: Int?
    var energy = KaguraEnergy()
    var safetyNet = KaguraSafetyNet()
    var songSections: [KaguraSection] = []   // KAG.5; `songPosition`: the track second last played
    var songPosition: Double?
    /// Render seconds the beat position has not advanced.
    private var stalled: Double = 0
    /// The last pose `pose(at:)` returned (before arm reach).
    private var lastPose: [SIMD3<Float>] = []
    /// Seconds of rest playback. Always advances, whatever the dancer is doing.
    var swayClock: Double = 0
    /// Ballet rests entered so far, so a calm song rotates its ballet clips.
    var balletTurns = 0
    /// Last beat position seen, and beats per second, for a dance fading out after its grid went.
    private var lastBeat: Double?
    private var beatsPerSecond: Double = 2

    // MARK: Test surface

    /// Beat indices at which a handoff started, in order (bar lines, by construction).
    public private(set) var cutBeats: [Int] = []
    /// Level chosen for each dance segment, in order.
    public private(set) var chosenLevels: [Double] = []
    /// Dance chosen at each change to a dance, in order.
    public private(set) var chosenDances: [KaguraDance] = []
    /// The repertoire and bar rank each auto pick read, in order (empty entries for a forced dance).
    public internal(set) var picks: [Pick] = []
    /// Arm-reach scale applied to the last frame.
    public internal(set) var lastReach: Double = 1
    /// Whether the dancer is (or is fading into) a dance rather than the sway.
    public var isDancing: Bool { current.isDance }

    // MARK: Init

    /// A choreographer choosing among the library's dances by the song (§6), or dancing only `dance`,
    /// with the sway as the fallback.
    public init?(library: KaguraClipLibrary, dance: KaguraDance? = nil) {
        self.init(library: library, sequence: dance.map { [$0] } ?? [])
    }

    /// A choreographer dancing `sequence` in turn, one dance per clip change (empty: by the song).
    init?(library: KaguraClipLibrary, sequence: [KaguraDance]) {
        let clips = KaguraDance.allCases.filter { !$0.isRest }.flatMap { library.clips(for: $0) }   // incl. unpicked
        let names = library.jointNames
        let index = { (name: String) in names.firstIndex(of: name) }
        guard !clips.isEmpty, let sway = library.sway, sequence.allSatisfy({ !library.clips(for: $0).isEmpty }),
              let pelvis = index("pelvis"), let leftAnkle = index("lankle"), let rightAnkle = index("rankle"),
              let lShoulder = index("lshoulder"), let lElbow = index("lelbow"), let lWrist = index("lwrist"),
              let rShoulder = index("rshoulder"), let rElbow = index("relbow"), let rWrist = index("rwrist")
        else { return nil }
        self.library = library
        dances = clips
        clipIndices = Dictionary(grouping: clips.indices) { clips[$0].dance }
        forcedDances = sequence
        rests = [sway] + library.clips(for: .ballet)
        self.pelvis = pelvis
        self.leftAnkle = leftAnkle
        self.rightAnkle = rightAnkle
        arms = [
            Arm(shoulder: lShoulder, elbow: lElbow, wrist: lWrist),
            Arm(shoulder: rShoulder, elbow: rElbow, wrist: rWrist),
        ]
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
    ///   - bass, playbackSeconds: `FeatureVector.bassAtt`; the track second, for the energy section (KAG.5).
    public mutating func advance( // swiftlint:disable:this function_parameter_count
        deltaTime: Double, beat: Double?, grid: KaguraGrid?, gridGeneration: Int, dancePermitted: Bool,
        bass: Double, playbackSeconds: Double? = nil
    ) -> [SIMD3<Float>] {
        let dt = min(max(deltaTime > 0 ? deltaTime : 1.0 / 60.0, 1.0 / 240.0), 1.0 / 30.0)
        if let playbackSeconds { songPosition = playbackSeconds }
        swayClock += dt
        energy.advance(bass: bass, deltaTime: dt)
        let pull = Float(exp(-dt / Self.leashSeconds))
        current = current.withOffset(current.offset * pull)
        previous = previous.map { $0.withOffset($0.offset * pull) }

        handleGridChange(generation: gridGeneration, grid: grid)   // fades out at the OLD tempo
        if let grid { beatsPerSecond = 1 / grid.beatPeriod }
        // A clock gap under a live dance (the per-track clock reset lands a frame before the new
        // grid does) dead-reckons at the grid tempo instead of snapping the clip to its start.
        let beat = beat ?? (current.isDance && grid != nil ? lastBeat.map { $0 + beatsPerSecond * dt } : nil)
        if let beat {
            // "Stopped" is advancing at under a quarter of the grid tempo: a held playhead does not
            // hold `p` exactly — the clock's phase lock creeps toward it geometrically.
            let advance = beat - (lastBeat ?? -.infinity)
            stalled = advance >= Self.stallFraction * beatsPerSecond * dt ? 0 : stalled + dt
            lastBeat = beat
        }

        if let grid, let beat {
            safetyNet.advance(beat: beat, grid: grid)
            let resting = safetyNet.irregular || energy.isSilent(forLast: Self.barSeconds(grid))
            if stalled >= Self.stallSeconds, case let .beats(start) = fade {
                // A bar-line crossfade counts beats, which have stopped: finish it in render time.
                let rate = beatsPerSecond
                fade = .seconds(elapsed: (beat - start) / rate, duration: 1 / rate, outgoingBeat: beat, rate: rate)
            }
            if stalled >= Self.stallSeconds && current.isDance && fade == nil {
                fadeToRest()   // a stopped clock never reaches a bar line
            }
            let permitted = dancePermitted && !resting && stalled < Self.stallSeconds
            schedule(beat: beat, grid: grid, dancePermitted: permitted)
            if let cut = nextCut, beat >= Double(cut.beat) { perform(cut, grid: grid, beat: beat) }
        }
        if fade == nil, restNeedsChange() { fadeToRest(seconds: Self.restFadeSeconds) }
        return reached(pose(at: beat, dt: dt))
    }

    // MARK: Scheduling

    private mutating func handleGridChange(generation: Int, grid: KaguraGrid?) {
        defer { knownGeneration = generation }
        guard let known = knownGeneration, known != generation else { return }
        nextCut = nil
        safetyNet.reset()
        stalled = 0
        guard current.isDance else { return }
        // A replaced or cleared grid renumbers the beats, so the dance cannot continue on it.
        // Fade to the rest over one nominal beat; the new grid rejoins at its next bar line.
        fadeToRest()
    }

    /// Fade to the song's rest (`nextRest`) over `seconds`, or one nominal beat, of render time. Inside
    /// another fade the outgoing side is the pose on screen, held still — dropping that fade's outgoing
    /// clip popped 0.14 m when a grid was replaced within a bar-line crossfade (KAG.3, first seen).
    private mutating func fadeToRest(seconds: Double? = nil) {
        nextCut = nil
        let leaving = previous == nil ? current : .held(joints: lastPose)
        let outgoing = displayed(leaving, beat: lastBeat)
        previous = leaving
        current = enterRest(from: outgoing)
        let duration = seconds ?? 1 / beatsPerSecond
        fade = .seconds(elapsed: 0, duration: duration, outgoingBeat: lastBeat, rate: beatsPerSecond)
    }

    /// The song's next rest, placed so its ankle midpoint matches `outgoing`'s.
    private mutating func enterRest(from outgoing: [SIMD3<Float>]) -> Segment {
        let clip = nextRest()
        return .rest(clip: clip, start: swayClock, offset: feet(rawRest(clip, start: swayClock)) - feet(outgoing))
    }

    private mutating func schedule(beat: Double, grid: KaguraGrid, dancePermitted: Bool) {
        switch (current, nextCut) {
        case (.rest, nil) where dancePermitted:
            nextCut = Cut(beat: grid.nextBarLine(after: beat), toDance: true)
        case (.rest, .some) where !dancePermitted:
            nextCut = nil
        case (.dance, let cut) where !dancePermitted && cut?.toDance != false:
            nextCut = Cut(beat: min(grid.nextBarLine(after: beat), cut?.beat ?? .max), toDance: false)
        case let (.dance(clip, entry, level, _), cut) where dancePermitted && cut?.toDance != true:
            nextCut = plannedDanceCut(clip: clip, entry: entry, level: level, grid: grid)
        default:
            break
        }
    }

    /// The spike's cut: the last bar line after `entry + ½` and within `maxBarsPerClip` bars (+ ½ beat)
    /// that is no later than ½ beat before the clip's last pulse; the next bar line if none is.
    /// the crossfade beat after the cut; a beat before its pulse map runs out if no bar line fits.
    private func plannedDanceCut(clip: Int, entry: Double, level: Double, grid: KaguraGrid) -> Cut {
        // The beat at which the warp reaches the clip's last pulse (spike `tt[-1]`).
        let covered = entry + (dances[clip].pulseSpan - Self.entryPulse(dances[clip], level: level)) * level
        let first = grid.nextBarLine(after: entry + 0.5)
        var best: Int?
        var line = first
        for _ in 0..<Self.maxBarsPerClip where Double(line) <= covered - 0.5 {
            best = line
            line = grid.nextBarLine(after: Double(line))
        }
        return Cut(beat: best ?? first, toDance: true)
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
            let dance = forcedDances.isEmpty
                ? pickDance(grid: grid, beat: cut.beat)
                : forcedDances[chosenDances.count % forcedDances.count]
            let choices = clipIndices[dance] ?? [0]
            let index = choices[(used[dance] ?? 0) % choices.count]
            used[dance, default: 0] += 1
            chosenDances.append(dance)
            let clip = dances[index]
            let level = Self.chooseLevel(
                pulsePeriod: clip.pulsePeriod ?? grid.beatPeriod,
                beatPeriod: grid.beatPeriod,
                levels: clip.allowedLevels)
            chosenLevels.append(level)
            let raw = clip.pose(at: clip.clipTime(atPulse: Self.entryPulse(clip, level: level)))
            incoming = .dance(clip: index, entry: entry, level: level, offset: feet(raw) - feet(outgoing))
            nextCut = plannedDanceCut(clip: index, entry: entry, level: level, grid: grid)
        } else {
            incoming = enterRest(from: outgoing)
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
        guard let previous else { lastPose = incoming; return incoming }
        let outgoing = displayed(previous, beat: outgoingBeat)
        let blend = Float(weight * weight * (3 - 2 * weight))
        lastPose = zip(outgoing, incoming).map { simd_mix($0, $1, SIMD3(repeating: blend)) }
        return lastPose
    }

    /// A segment's joints at `beat`, minus its handoff offset (floor plane only).
    private func displayed(_ segment: Segment, beat: Double?) -> [SIMD3<Float>] {
        let raw: [SIMD3<Float>]
        switch segment {
        case let .dance(clip, entry, level, _):
            let pulse = ((beat ?? entry) - entry) / level + Self.entryPulse(dances[clip], level: level)
            raw = dances[clip].pose(at: dances[clip].clipTime(atPulse: pulse))
        case let .rest(clip, start, _):
            raw = rawRest(clip, start: start)
        case .held(let joints):
            raw = joints
        }
        let offset = segment.offset
        return raw.map { SIMD3($0.x - offset.x, $0.y, $0.z - offset.y) }
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
