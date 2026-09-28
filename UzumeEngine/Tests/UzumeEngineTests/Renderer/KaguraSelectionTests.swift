// KaguraSelectionTests — the dance pick, arm reach, the safety nets and the song-energy push (KAG.3; KAG.5).
//
// KAGURA_DESIGN §3a, §6–§8. Structural properties of the choreography on synthetic grids (the harness),
// except the silence rest, which is driven by a real capture's `bass_att` rows (FA #27).

import Foundation
import Metal
import simd
import Testing
@testable import Renderer
@testable import Shared

@Suite("Kagura selection — dance pick, reach, safety nets (KAG.3)")
struct KaguraSelectionTests {

    typealias Harness = KaguraChoreographyHarness
    static let fps = Harness.fps

    // MARK: - Dance pick (§6 item 3)

    /// A varied minute that primes the song's energy distribution, then calm / middle / loud steps.
    /// 0.05 sits under the whole primer (rank ≈ 0.1), 0.18 inside it (≈ 0.6), 0.4 over it (≈ 0.87).
    static func staircase(_ time: Double) -> Double {
        switch time {
        case ..<60: return 0.2 + 0.08 * sin(2 * .pi * time / 7)
        case ..<76: return 0.05
        case ..<92: return 0.18
        default: return 0.4
        }
    }

    @Test("The pick follows a real energy staircase tercile by tercile, from the bar just played")
    func pickFollowsStaircase() throws {
        let run = try Harness.run(seconds: 108, grid: Harness.grid(bpm: 120, seconds: 108), sequence: [],
                                  sections: Harness.steady(6), bass: Self.staircase)
        let picks = run.choreographer.picks
        #expect(picks.count == run.pickTimes.count && picks.count >= 20)
        // Steps start at 60 / 76 / 92 s; the last pick at least a bar + the EMA's settling (4 s) inside each.
        for (start, end, tercile) in [(60.0, 76.0, 0), (76.0, 92.0, 1), (92.0, 108.0, 2)] {
            let inside = picks.indices.filter { run.pickTimes[$0] >= start + 4 && run.pickTimes[$0] < end }
            let last = try #require(inside.last, "no pick inside the step at \(start) s")
            let pick = picks[last]
            print("[kagura-pick] step \(start) s: rank \(pick.rank) → \(run.choreographer.chosenDances[last]) of \(pick.repertoire)")
            #expect(min(Int(pick.rank * 3), 2) == tercile, "step at \(start) s ranked \(pick.rank)")
            #expect(run.choreographer.chosenDances[last] == pick.repertoire[tercile])
        }
    }

    @Test("A loud stretch keeps the vigorous dance — no rotation, no anti-repeat")
    func loudStretchKeepsVigorous() throws {
        let run = try Harness.run(seconds: 80, grid: Harness.grid(bpm: 120, seconds: 80), sequence: [],
                                  sections: Harness.steady(10), bass: { $0 < 60 ? 0.2 + 0.08 * sin(2 * .pi * $0 / 7) : 0.45 })
        let loud = run.pickTimes.indices.filter { run.pickTimes[$0] >= 64 }
        let dances = loud.map { run.choreographer.chosenDances[$0] }
        let vigorous = try #require(run.choreographer.picks.last?.repertoire.last)
        print("[kagura-pick] loud stretch: \(dances) (vigorous = \(vigorous))")
        #expect(loud.count >= 3)
        #expect(dances.allSatisfy { $0 == vigorous }, "the loud stretch rotated away from \(vigorous): \(dances)")
    }

    @Test("On real music, calm, middle and vigorous each get a fair share of the bars (Matt, step 2)")
    func tercileBalance() throws {
        // The three route-coverage captures' `bass_att`, back to back (90 s of real music, FA #27), ranked
        // bar by bar (2 s at 120 BPM) the way every pick ranks the bar just played. Every bar, not only
        // the ones that fell on a clip change: ~35 ranks instead of ~22 picks, so a third's share is not
        // sampling noise. From 20 s: before that the window holds too few bars to rank against.
        let captures = try KaguraFixture.tracks.map { try KaguraFixture.load($0) }
        var energy = KaguraEnergy()
        var ranks: [Double] = []
        let fps = 60.0, bar = 2.0
        for frame in 0..<Int(90 * fps) {
            let time = Double(frame) / fps
            let index = min(Int(time / 30), captures.count - 1)
            energy.advance(bass: captures[index].bass(at: time - 30 * Double(index)), deltaTime: 1 / fps)
            if time >= 20, frame % Int(bar * fps) == 0 { ranks.append(energy.rank(ofLast: bar)) }
        }
        let shares = (0..<3).map { tercile in
            Double(ranks.filter { min(Int($0 * 3), 2) == tercile }.count) / Double(max(ranks.count, 1))
        }
        print(String(format: "[kagura-balance] n=%d bars: calm %.0f %% / middle %.0f %% / vigorous %.0f %%",
                     ranks.count, shares[0] * 100, shares[1] * 100, shares[2] * 100))
        #expect(ranks.count >= 30)
        #expect(shares.allSatisfy { $0 >= 0.2 }, "a third is starved: \(shares)")
    }

    // MARK: - Continuity (per dance)

    /// Every ordered pair of the five dances, in 21 clip changes: strides 1–4 through the library.
    static let allPairs: [KaguraDance] = {
        let dances = KaguraRepertoire.spikeDances
        return (1...4).flatMap { stride in (0..<5).map { dances[($0 * stride) % 5] } } + [dances[0]]
    }()

    /// A dance's native maximum per-frame joint step (60 fps) × its fastest local warp rate at `bpm` × 1.25.
    static func bound(_ dance: KaguraDance?, bpm: Double, library: KaguraClipLibrary) -> Float {
        guard let dance else { return nativeStep(library.sway) * 1.25 }
        return library.clips(for: dance).map { clip -> Float in
            let level = KaguraChoreographer.chooseLevel(
                pulsePeriod: clip.pulsePeriod ?? 1, beatPeriod: 60 / bpm, levels: clip.allowedLevels)
            let slope = zip(clip.pulseMap.dropFirst(), clip.pulseMap).map { Double($0 - $1) }.max() ?? 0
            let rate = slope * Double(clip.samplesPerPulse) / (level * 60 / bpm)
            return nativeStep(clip) * Float(rate) * 1.25
        }.max() ?? 0
    }

    static func nativeStep(_ clip: KaguraClip?) -> Float {
        guard let clip else { return 0 }
        let frames = stride(from: 0.0, through: clip.duration, by: 1 / 60).map { clip.pose(at: $0) }
        return Harness.maxStep(frames)
    }

    @Test("Every handoff between the five dances, and to and from the sway, stays under a per-dance bound",
          arguments: [80.0, 166.0])
    func continuity(bpm: Double) throws {
        let lib = try KaguraClipLibrary.shared()
        let natives = KaguraRepertoire.spikeDances.map { dance in
            "\(dance) " + lib.clips(for: dance).map { String(format: "%.3f", Self.nativeStep($0)) }.joined(separator: "/")
        }
        print("[kagura-continuity] native max step (60 fps): \(natives), sway \(Self.nativeStep(lib.sway))")
        // Dance to dance: all 20 ordered pairs. Streaming lock dropped twice, for dance → sway → dance.
        let seconds = 21 * 4 * 4 * 60 / bpm + 30
        let run = try Harness.run(seconds: seconds, grid: Harness.grid(bpm: bpm, seconds: seconds), streaming: true,
                                  sequence: Self.allPairs,
                                  lockState: { ($0 < 3 || ($0 > 40 && $0 < 48) || ($0 > 90 && $0 < 97)) ? 0 : 2 })
        let order = run.choreographer.chosenDances
        let pairs = Set(zip(order, order.dropFirst()).map { "\($0)>\($1)" })
        #expect(pairs.count >= 20, "only \(pairs.count) ordered dance pairs covered: \(order)")
        var bounds: [KaguraDance?: Float] = [:]
        for dance in KaguraRepertoire.spikeDances.map(Optional.some) + [nil] { bounds[dance] = Self.bound(dance, bpm: bpm, library: lib) }
        var worstRatio: Float = 0
        for index in 1..<run.joints.count {
            let limit = max(bounds[run.dance[index]] ?? 0, run.fading[index] ? bounds[run.fadingFrom[index]] ?? 0 : 0)
            let step = Harness.step(run.joints, at: index)
            worstRatio = max(worstRatio, step / limit)
            let what = "\(String(describing: run.dance[index])) from \(String(describing: run.fadingFrom[index]))"
            #expect(step < limit, "frame \(index): step \(step) m over the bound \(limit) (\(what))")
            if step >= limit { break }
        }
        #expect(run.swayInFade.contains(true), "no sway handoff was exercised")
        print("[kagura-continuity] \(bpm) BPM: \(order.count) dances, \(pairs.count) pairs, worst step / bound \(worstRatio)")
        // Negative control: a cut with no crossfade between two dances' poses exceeds every bound.
        let twist = try #require(lib.clips(for: .twist).first), chicken = try #require(lib.clips(for: .chicken).first)
        let teleport = zip(twist.pose(at: twist.duration / 2), chicken.pose(at: 0)).map { simd_distance($0, $1) }.max() ?? 0
        let largest = bounds.values.max() ?? 0
        #expect(teleport > largest, "the teleport control (\(teleport) m) does not exceed the bound \(largest)")
    }

    // MARK: - Arm reach (§8)

    @Test("Arm reach stays within ±25 % and never touches the legs")
    func armReach() throws {
        let grid = try Harness.grid(bpm: 117, seconds: 90)
        // Same forced dance and grid; only the bass differs, so the pre-reach choreography is identical.
        let steady = try Harness.run(seconds: 90, grid: grid, bass: { _ in 0.2 })
        let moving = try Harness.run(seconds: 90, grid: grid, bass: { 0.2 + 0.12 * sin(2 * .pi * $0 / 9) })
        let names = try KaguraClipLibrary.shared().jointNames
        let index = { (name: String) in try #require(names.firstIndex(of: name)) }
        let legs = try ["lhip", "lknee", "lankle", "rhip", "rknee", "rankle", "pelvis"].map(index)
        var low = Float.infinity, high: Float = 0
        for frame in steady.joints.indices {
            for joint in legs { #expect(steady.joints[frame][joint] == moving.joints[frame][joint]) }
            for side in ["l", "r"] {
                let shoulder = try index(side + "shoulder"), wrist = try index(side + "wrist")
                let base = simd_distance(steady.joints[frame][wrist], steady.joints[frame][shoulder])
                guard base > 0.05 else { continue }
                let ratio = simd_distance(moving.joints[frame][wrist], moving.joints[frame][shoulder]) / base
                low = min(low, ratio); high = max(high, ratio)
            }
        }
        print("[kagura-reach] wrist-to-shoulder ratio \(low)…\(high)")
        #expect(low >= 0.75 - 1e-4 && high <= 1.25 + 1e-4)
        #expect(low < 0.85 && high > 1.15, "reach barely moved (\(low)…\(high)) — the route is not live")
    }

    // MARK: - Safety net (§7)

    @Test("Grid-CV safety net: sways through an irregular stretch, rejoins after the hysteresis")
    func safetyNetHysteresis() throws {
        // 120 BPM to 40 s, then IBIs alternating 0.35 / 0.65 s (CV 0.3) to 70 s, then steady again.
        var beats: [Double] = [0]
        while beats.last! < 130 {
            let time = beats.last!
            let irregular = time >= 40 && time < 70
            beats.append(time + (irregular ? (beats.count % 2 == 0 ? 0.35 : 0.65) : 0.5))
        }
        let run = try Harness.run(seconds: 125, grid: Harness.grid(beats: beats))
        let at = { (seconds: Double) in run.dancing[Int(seconds * Self.fps)] }
        let swayStart = try #require((Int(40 * Self.fps)..<run.dancing.count).first { !run.dancing[$0] })
        let rejoin = try #require((Int(70 * Self.fps)..<run.dancing.count).first { run.dancing[$0] })
        print(String(format: "[kagura-safety] sway from %.2f s, rejoin at %.2f s", Double(swayStart) / Self.fps,
                     Double(rejoin) / Self.fps))
        #expect(at(38), "danced to the steady opening")
        #expect(Double(swayStart) / Self.fps < 44, "did not leave the dance within a bar of the irregular stretch")
        #expect(!(Int(44 * Self.fps)..<Int(78 * Self.fps)).contains { run.dancing[$0] }, "danced on the irregular grid")
        // Rejoin: 16 intervals to flush the window + 8 steady beats (12 s at 120 BPM), then the bar line.
        #expect(Double(rejoin) / Self.fps >= 70 + 12 && Double(rejoin) / Self.fps < 70 + 16)
        #expect(at(120))
        #expect(Harness.frozenFrames(run).isEmpty)
    }

    // MARK: - Silence (§3a)

    @Test("Silence → music → silence on real rows: sway, dance, sway, joining and leaving at bar lines")
    func silenceRest() throws {
        let fixture = try KaguraFixture.load("love_rehab")
        // Silence is the zeros the chain feeds (BUG-130; a real track end reads 0.000); music is the
        // capture's own `bass_att` from 10 to 40 s.
        let bass = { (time: Double) in time >= 10 && time < 40 ? fixture.bass(at: time - 10) : 0 }
        let run = try Harness.run(seconds: 56, grid: Harness.grid(bpm: 120, seconds: 56), bass: bass)
        let first = try #require(run.dancing.firstIndex(of: true))
        let rest = try #require((Int(40 * Self.fps)..<run.dancing.count).first { !run.dancing[$0] })
        print(String(format: "[kagura-silence] dance from %.2f s, rest from %.2f s; cuts %@", Double(first) / Self.fps,
                     Double(rest) / Self.fps, run.choreographer.cutBeats.description))
        #expect(Double(first) / Self.fps >= 10 && Double(first) / Self.fps <= 12.1, "joined late or during silence")
        // Every change lands on a 4/4 bar line (beats 0, 4, 8 …).
        #expect(run.choreographer.cutBeats.allSatisfy { $0 % 4 == 0 })
        #expect(!run.dancing[Int(50 * Self.fps)...].contains(true), "still dancing ten seconds into silence")
        #expect(Harness.frozenFrames(run).isEmpty, "the sway froze")
    }

    @Test("A stopped clock (pause, track end) fades the dance to the sway without a bar line, and never freezes")
    func stoppedClock() throws {
        // The playhead holds at 20 s and the chain feeds zeros, as a paused local file does (BUG-130).
        let run = try Harness.run(seconds: 30, grid: Harness.grid(bpm: 120, seconds: 30),
                                  bass: { $0 < 20 ? 0.2 : 0 }, playback: { min($0, 20) })
        #expect(run.dancing[Int(19 * Self.fps)])
        let rest = try #require((Int(20 * Self.fps)..<run.dancing.count).first { !run.dancing[$0] })
        print(String(format: "[kagura-stall] sway from %.2f s", Double(rest) / Self.fps))
        // 0.25 s of dead reckoning, the phase lock's creep, then `stallSeconds` (0.5 s).
        #expect(Double(rest) / Self.fps < 21.5, "the dance held on a stopped clock")
        #expect(Harness.frozenFrames(run).isEmpty, "\(Harness.frozenFrames(run).count) frozen frames")
        #expect(Harness.maxStep(run.joints) < 0.06)
    }

    // MARK: - The song-energy push (KAG.3 task 2; KAG.5 levels), production path

    @Test("The pushed song energy reaches the repertoire; a track change clears it before the next arrives")
    func songEnergyPush() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let clips = try KaguraClipLibrary.shared()
        let dancer = try KaguraDancer(device: ctx.device, library: lib.library)
        dancer.ensureAllocated(width: 64, height: 36)
        let grid = try Harness.grid(bpm: 95.2, seconds: 60)
        var time = 0.0
        func play(_ seconds: Double) {
            let cmd = ctx.commandQueue.makeCommandBuffer()
            for _ in 0..<Int(seconds * Self.fps) {
                var features = FeatureVector()
                features.time = Float(time)
                features.deltaTime = Float(1 / Self.fps)
                features.bassAtt = 0.2
                if let cmd { dancer.update(features: features, stemFeatures: StemFeatures(), commandBuffer: cmd) }
                dancer.ingestClock(playbackSeconds: time, renderTime: time, lockState: 0)
                time += 1 / Self.fps
            }
            cmd?.commit()
            cmd?.waitUntilCompleted()
        }
        let expected = { (level: Int?) in
            KaguraRepertoire.pick(bpm: 60 / grid.beatPeriod, energy: KaguraRepertoire.energy(level: level), library: clips)
        }
        #expect(expected(10) != expected(nil), "the fixture cannot tell them apart")

        // Track 1 (a level-10 song): the push reaches the repertoire.
        dancer.setGrid(grid, streaming: false)
        dancer.setSongSections(Harness.steady(10))
        play(12)
        #expect(dancer.choreography.picks.last?.repertoire == expected(10))
        // The session-log feed: each pick handed over once, with what it read and chose.
        let logged = dancer.takeNewPicks()
        #expect(!logged.isEmpty && dancer.takeNewPicks().isEmpty)
        let line = try #require(logged.last?.logLine)
        print("[kagura-log] \(line)")
        #expect(line.hasPrefix("KAGURA_PICK: beat=") && line.contains("level=10")
                && line.contains("repertoire=[") && line.contains("barRank="))

        // Track change, cache miss: the app writes no sections; the next pick reads the middle energy.
        dancer.setSongSections([])
        dancer.reset()
        dancer.setGrid(grid, streaming: false)
        time = 0
        let before = dancer.choreography.picks.count
        play(12)
        let afterChange = dancer.choreography.picks.dropFirst(before)
        #expect(!afterChange.isEmpty && afterChange.allSatisfy { $0.repertoire == expected(nil) })

        // The next track's sections: the next clip change re-picks.
        dancer.setSongSections(Harness.steady(10))
        let mark = dancer.choreography.picks.count
        play(12)
        #expect(dancer.choreography.picks.count > mark)
        #expect(dancer.choreography.picks.last?.repertoire == expected(10))
    }
}
