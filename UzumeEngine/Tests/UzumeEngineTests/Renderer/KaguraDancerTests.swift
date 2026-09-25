// KaguraDancerTests — the dancer's CPU core (KAG.2 task 2; KAGURA_DESIGN §3a, §5, §6 item 4).
//
// Drives `KaguraChoreographer` through `KaguraBeatClock` frame by frame at 60 fps, the order
// production uses (read p, advance, then push the clock). Synthetic grids are fine HERE: these are
// structural properties of the choreography (where cuts land, whether a pose jumps), not claims
// about real music. The real-music claim — pulse lock — is `KaguraPulseLockReplayTests`.

import Foundation
import simd
import Testing
@testable import Renderer

@Suite("Kagura dancer — warp, clip changes, sway, framing (KAG.2)")
struct KaguraDancerTests {

    // MARK: - Harness

    private static let fps = 60.0

    /// No joint may move further than this between consecutive 60 fps frames (3.6 m/s). The
    /// twist's fastest joint at its fastest warp measures well under it; a handoff that re-poses the
    /// body, or a sway that wraps, moves joints tens of centimetres in one frame. Native clip maxima
    /// (60 fps): twist 0.030/0.040, sway 0.055 (its own wrist, frame 650). KAG.3: the macarena is
    /// 0.071 natively, so this bound becomes per-dance there.
    private static let maxJointStep: Float = 0.06

    struct Run {
        var joints: [[SIMD3<Float>]] = []
        var dancing: [Bool] = []
        var beats: [Double?] = []
        var choreographer: KaguraChoreographer
    }

    private static func grid(bpm: Double, seconds: Double, downbeatOffset: Int = 0,
                             beatsPerBar: Int = 4, bars: Bool = true) throws -> KaguraGrid {
        let period = 60 / bpm
        let beats = (0..<Int(seconds / period) + 8).map { Double($0) * period }
        let downbeats = bars ? stride(from: downbeatOffset, to: beats.count, by: beatsPerBar).map { beats[$0] } : []
        return try #require(KaguraGrid(beats: beats, downbeats: downbeats,
                                       beatsPerBar: bars ? beatsPerBar : 1, hasBarInformation: bars))
    }

    /// Run `seconds` at 60 fps. `schedule(t)` may change the grid or lock at render time `t`.
    private static func run(seconds: Double, grid: KaguraGrid?, streaming: Bool = false,
                            lockState: (Double) -> Int = { _ in 0 },
                            regrid: ((Double) -> KaguraGrid??)? = nil) throws -> Run {
        let lib = try KaguraClipLibrary.shared()
        var run = Run(choreographer: try #require(KaguraChoreographer(library: lib)))
        var clock = KaguraBeatClock()
        clock.setGrid(grid, streaming: streaming)
        let frames = Int(seconds * fps)
        for frame in 0..<frames {
            let time = Double(frame) / fps
            if let change = regrid?(time) { clock.setGrid(change, streaming: streaming) }
            let beat = clock.beatPosition(atRenderTime: time)
            let pose = run.choreographer.advance(
                deltaTime: 1 / fps, beat: beat, grid: clock.grid, gridGeneration: clock.gridGeneration,
                dancePermitted: clock.dancePermitted)
            run.joints.append(pose)
            run.dancing.append(run.choreographer.isDancing)
            run.beats.append(beat)
            clock.ingest(playbackSeconds: time, renderTime: time, lockState: lockState(time))
        }
        return run
    }

    /// Largest single-frame joint displacement in `frames[range]`.
    private static func maxStep(_ frames: [[SIMD3<Float>]], in range: Range<Int>? = nil) -> Float {
        let range = range ?? 1..<frames.count
        var worst: Float = 0
        for index in range where index > 0 && index < frames.count {
            for (a, b) in zip(frames[index], frames[index - 1]) { worst = max(worst, simd_distance(a, b)) }
        }
        return worst
    }

    /// Frames within one beat of each index where `dancing` flips or a cut starts.
    private static func frames(near beatsOfInterest: [Double], in run: Run) -> [Range<Int>] {
        beatsOfInterest.compactMap { target in
            guard let start = run.beats.firstIndex(where: { ($0 ?? -.infinity) >= target - 0.25 }) else { return nil }
            return start..<min(start + Int(fps), run.joints.count)
        }
    }

    // MARK: - Level

    @Test("Level choice at 80, 117 and 166 BPM — the twist never goes to ×½", arguments: [80.0, 117.0, 166.0])
    func levelChoice(bpm: Double) throws {
        let lib = try KaguraClipLibrary.shared()
        for clip in lib.clips(for: .twist) {
            #expect(!clip.allowedLevels.contains(0.5), "\(clip.id): ×½ must not be allowed for the twist")
            let level = KaguraChoreographer.chooseLevel(
                pulsePeriod: try #require(clip.pulsePeriod), beatPeriod: 60 / bpm, levels: clip.allowedLevels)
            #expect(level == 1, "\(clip.id) at \(bpm) BPM: level \(level), expected one twist per beat")
        }
        let run = try Self.run(seconds: 40, grid: Self.grid(bpm: bpm, seconds: 40))
        #expect(!run.choreographer.chosenLevels.isEmpty)
        #expect(run.choreographer.chosenLevels.allSatisfy { $0 == 1 }, "\(run.choreographer.chosenLevels)")
    }

    @Test("choose_level picks the rate closest to 1 within the allowed set")
    func chooseLevelRule() {
        // Pulse 0.6 s against a 0.5 s beat: ×1 plays at 1.2, ×2 at 0.6 → ×1.
        #expect(KaguraChoreographer.chooseLevel(pulsePeriod: 0.6, beatPeriod: 0.5, levels: [1, 2, 4]) == 1)
        // Pulse 1.2 s against a 0.3 s beat: ×4 plays at 1.0 → ×4.
        #expect(KaguraChoreographer.chooseLevel(pulsePeriod: 1.2, beatPeriod: 0.3, levels: [0.5, 1, 2, 4]) == 4)
        // Pulse 0.3 s against 0.75 s beat: ×½ would be 0.8 but is excluded → ×1 (0.4).
        #expect(KaguraChoreographer.chooseLevel(pulsePeriod: 0.3, beatPeriod: 0.75, levels: [1, 2, 4]) == 1)
    }

    // MARK: - Clip changes

    @Test("Clip changes land only on bar lines, at most every 4 bars, and alternate the two clips")
    func clipChangesOnBarLines() throws {
        // Downbeats at beat 1, 5, 9 … so a "every 4th beat from 0" bug cannot pass by accident.
        let run = try Self.run(seconds: 90, grid: Self.grid(bpm: 120, seconds: 90, downbeatOffset: 1))
        let cuts = run.choreographer.cutBeats
        print("[kagura-dancer] 4/4 cuts at beats \(cuts)")
        #expect(cuts.count >= 10)
        #expect(cuts.allSatisfy { ($0 - 1) % 4 == 0 }, "a cut fell off a bar line: \(cuts)")
        let gaps = zip(cuts.dropFirst(), cuts).map { $0 - $1 }
        #expect(gaps.allSatisfy { $0 >= 4 && $0 <= 16 }, "cut spacing outside 1…4 bars: \(gaps)")
    }

    @Test("With the bar declined (beatsPerBar 1, no downbeats) changes fall every 4 beats")
    func declinedBarChangesEveryFourBeats() throws {
        let run = try Self.run(seconds: 90, grid: Self.grid(bpm: 120, seconds: 90, bars: false))
        let cuts = run.choreographer.cutBeats
        print("[kagura-dancer] declined-bar cuts at beats \(cuts)")
        #expect(cuts.count >= 10)
        #expect(cuts.allSatisfy { $0 % 4 == 0 }, "a cut fell off the 4-beat lattice: \(cuts)")
        #expect(run.dancing.suffix(60).allSatisfy { $0 }, "a declined bar must not make the dancer sway (D-210)")
    }

    // MARK: - Continuity

    @Test("Crossfades are continuous: handoffs, sway↔dance, and a grid replaced mid-dance")
    func crossfadeContinuity() throws {
        let grid = try Self.grid(bpm: 128, seconds: 80)
        let other = try Self.grid(bpm: 104, seconds: 80)
        // Streaming: unlocked 0–6 s (sway), locked 6–40 s (dance), lock lost 40–50 s (sway),
        // locked again, and the grid replaced at 62 s.
        let run = try Self.run(
            seconds: 80, grid: grid, streaming: true,
            lockState: { ($0 < 6 || ($0 >= 40 && $0 < 50)) ? 0 : 2 },
            regrid: { abs($0 - 62) < 0.5 / Self.fps ? .some(other) : nil })
        let flips = zip(run.dancing.dropFirst(), run.dancing).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(flips.count >= 4, "expected sway→dance, dance→sway, sway→dance and the regrid fade")
        let handoffRanges = Self.frames(near: run.choreographer.cutBeats.map(Double.init), in: run)
            + flips.map { $0.offset..<min($0.offset + Int(Self.fps), run.joints.count) }
        let worstAtHandoff = handoffRanges.map { Self.maxStep(run.joints, in: $0) }.max() ?? 0
        let worstOverall = Self.maxStep(run.joints)
        print("[kagura-dancer] max joint step: at handoffs \(worstAtHandoff) m, overall \(worstOverall) m "
              + "(bound \(Self.maxJointStep)), \(handoffRanges.count) handoff windows")
        #expect(worstOverall < Self.maxJointStep, "a joint jumped \(worstOverall) m in one 60 fps frame")
    }

    // MARK: - Sway

    @Test("No grid: the dancer sways, and never freezes")
    func swayWithoutGrid() throws {
        let run = try Self.run(seconds: 30, grid: nil)
        #expect(run.dancing.allSatisfy { !$0 })
        let frozen = (1..<run.joints.count).filter { index in
            zip(run.joints[index], run.joints[index - 1]).allSatisfy { simd_distance($0, $1) < 1e-6 }
        }
        #expect(frozen.isEmpty, "\(frozen.count) frozen frames (a frozen human reads as a dropped frame)")
    }

    @Test("Streaming, unlocked: the dancer sways until lock, then joins at the next bar line")
    func swayWhileUnlocked() throws {
        let grid = try Self.grid(bpm: 120, seconds: 30)
        let run = try Self.run(seconds: 30, grid: grid, streaming: true, lockState: { $0 < 10 ? 0 : 1 })
        let firstDance = try #require(run.dancing.firstIndex(of: true))
        #expect(Double(firstDance) / Self.fps >= 10, "danced before the drift tracker reported lock")
        #expect(Double(firstDance) / Self.fps < 10 + 2.1, "did not join within a bar of lock")
        let joinBeat = try #require(run.choreographer.cutBeats.first)
        #expect(joinBeat % 4 == 0, "joined off a bar line (beat \(joinBeat))")
    }

    @Test("The sway's ping-pong never teleports (a modulo wrap would)")
    func swayPingPongNeverTeleports() throws {
        let lib = try KaguraClipLibrary.shared()
        let sway = try #require(lib.sway)
        let run = try Self.run(seconds: sway.duration * 3.2, grid: nil)
        let worst = Self.maxStep(run.joints)
        // Negative control: the jump a plain modulo wrap makes at the clip's end.
        let wrap = zip(sway.pose(at: sway.duration), sway.pose(at: 0)).map { simd_distance($0, $1) }.max() ?? 0
        print("[kagura-dancer] sway max joint step \(worst) m; modulo-wrap jump \(wrap) m")
        #expect(worst < Self.maxJointStep)
        #expect(wrap > Self.maxJointStep, "the wrap control does not jump — the bound has no teeth")
    }

    // MARK: - Framing

    @Test("The pelvis stays inside a fixed frame box over 5 minutes at 120 BPM")
    func framingOverFiveMinutes() throws {
        let run = try Self.run(seconds: 300, grid: Self.grid(bpm: 120, seconds: 300))
        let lib = try KaguraClipLibrary.shared()
        let pelvis = try #require(lib.jointNames.firstIndex(of: "pelvis"))
        let xs = run.joints.map { $0[pelvis].x }, zs = run.joints.map { $0[pelvis].z }
        let reach = max(xs.map(abs).max() ?? 0, zs.map(abs).max() ?? 0)
        print("[kagura-dancer] 5 min pelvis x [\(xs.min() ?? 0), \(xs.max() ?? 0)] z [\(zs.min() ?? 0), \(zs.max() ?? 0)] m, "
              + "\(run.choreographer.cutBeats.count) clip changes")
        #expect(run.choreographer.cutBeats.count > 50)
        #expect(reach < 0.35, "the figure wandered \(reach) m from centre")
    }
}
