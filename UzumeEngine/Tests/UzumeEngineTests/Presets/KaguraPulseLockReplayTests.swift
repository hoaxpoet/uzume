// KaguraPulseLockReplayTests — do the twist's hip turns land on the beat? (KAG.2; KAGURA_DESIGN §11)
//
// Drives `KaguraDancer` frame by frame at 60 fps through its production `update` path, on each
// committed route-coverage capture:
//   - clock: the capture's own 43 Hz `playback_time_s`, pushed after each update (the app's tick);
//   - grid: the matching Beat This! reference (`beats_seconds`, `downbeats_seconds`).
// Then the KAG.0 spike's hip-yaw detector (`KaguraSpikeDetector`, ported verbatim — FA #73) runs on
// the dancer's OUTPUT joints, per clip segment, skipping each crossfade beat, at 30 fps — exactly
// `cmd_film`'s pulse-lock block. Checking the pulse map instead would only confirm the design.
//
// Each event's phase is measured against the TRUE grid in music time (the capture clock at that
// render instant). Chance for "within ±⅛ beat of a grid beat" is 25 %.
//
// Negative control (the decoy): the dancer is driven by the grid shifted +½ beat and measured
// against the true grid. The events must move wholesale onto the half-beat.
//
// Spike figures on the same three captures (`kagura.py film … --family twist --metrics-only`,
// 2026-09-25): on-beat 100 % (n 40 / 43 / 43), decoy 0 % on the beat, 100 % on the half-beat.

import Foundation
import Metal
import simd
import Testing
@testable import Renderer
@testable import Shared

@Suite("Kagura pulse-lock replay (KAG.2)", .serialized)
struct KaguraPulseLockReplayTests {

    /// Set from KAG.2's first measurement (100 % on all three captures, n 44 / 51 / 48; decoy 0 %) minus a
    /// margin of 5 points, never below the spike's 90 % bar (KAGURA_DESIGN §11).
    static let onBeatFloor = 0.95
    /// Decoy: at most this fraction may stay on the beat, and at least `onBeatFloor` must reach the "and".
    static let decoyOnBeatCeiling = 0.05

    struct Lock: CustomStringConvertible {
        let onBeat: Double
        let halfBeat: Double
        let count: Int
        let histogram: [Int]
        var description: String {
            String(format: "on-beat %.0f %% (chance 25 %%), half-beat %.0f %%, n=%d, hist %@",
                   onBeat * 100, halfBeat * 100, count, histogram.description)
        }
    }

    // MARK: - Replay

    static func measure(_ fixture: KaguraFixture, shiftBeats: Double, dance: KaguraDance = .twist) throws -> Lock {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let clips = try KaguraClipLibrary.shared()
        let dancer = try KaguraDancer(device: ctx.device, library: lib.library, dance: dance)
        dancer.ensureAllocated(width: 64, height: 36)
        let driven = try fixture.grid(shiftBeats: shiftBeats)
        dancer.setGrid(driven, streaming: false)

        var joints: [[SIMD3<Float>]] = []
        var cuts: [Int] = []
        var times: [Double] = []
        let fps = 60.0
        var cmd = ctx.commandQueue.makeCommandBuffer()
        for frame in 0..<Int(fixture.duration * fps) {
            let time = Double(frame) / fps
            var features = FeatureVector()
            features.time = Float(time)
            features.deltaTime = Float(1 / fps)
            features.bassAtt = Float(fixture.bass(at: time))   // KAG.3: arm reach + the silence rest read it
            if let buffer = cmd { dancer.update(features: features, stemFeatures: StemFeatures(), commandBuffer: buffer) }
            joints.append(dancer.lastJoints)
            cuts.append(dancer.choreography.cutBeats.count)
            times.append(time)
            if let row = fixture.row(at: time) {
                dancer.ingestClock(playbackSeconds: fixture.playback[row], renderTime: time, lockState: 0)
            }
            if frame % 120 == 119 { cmd?.commit(); cmd = ctx.commandQueue.makeCommandBuffer() }
        }
        cmd?.commit()
        cmd?.waitUntilCompleted()

        // KAGURA_DUMP=<dir>: write the output at 30 fps for the spike's own `foot_slide`
        // (the causal leash's cost against the spike's zero-phase one; KAG.2 closeout).
        if let dir = ProcessInfo.processInfo.environment["KAGURA_DUMP"] {
            var csv = "t,cut," + clips.jointNames.flatMap { ["\($0)_x", "\($0)_y", "\($0)_z"] }.joined(separator: ",") + "\n"
            for index in stride(from: 0, to: joints.count, by: 2) {
                let cut = index > 0 && cuts[index] != cuts[max(index - 2, 0)] ? 1 : 0
                let values = joints[index].flatMap { [$0.x, $0.y, $0.z] }.map { String(format: "%.5f", $0) }
                csv += String(format: "%.5f,%d,", times[index], cut) + values.joined(separator: ",") + "\n"
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(fixture.name)_\(dance)_shift\(shiftBeats).csv")
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }

        let joint = { (name: String) in try #require(clips.jointNames.firstIndex(of: name)) }
        let leftHip = try joint("lhip"), rightHip = try joint("rhip")
        let leftWrist = try joint("lwrist"), rightWrist = try joint("rwrist"), pelvis = try joint("pelvis")
        let arms = try ["lwrist", "rwrist", "lelbow", "relbow"].map(joint)
        let pulse = try #require(clips.clips(for: dance).first?.pulseKind)
        let truth = fixture.beats
        let crossfade = driven.beatPeriod
        let cutFrames = cuts.indices.filter { $0 > 0 && cuts[$0] != cuts[$0 - 1] }

        // `cmd_film`: per segment, skip the crossfade beat, detect at 30 fps, need 30 samples.
        var phases: [Double] = []
        for (index, start) in cutFrames.enumerated() {
            let end = index + 1 < cutFrames.count ? cutFrames[index + 1] : joints.count
            let window = stride(from: start, to: end, by: 2).filter { times[$0] >= times[start] + crossfade }
            guard window.count >= 30 else { continue }
            let frames = window.map { joints[$0] }
            let events: [Double]
            switch pulse {
            case "hipyaw":
                events = KaguraSpikeDetector.hipYawEvents(frames, leftHip: leftHip, rightHip: rightHip, fps: 30)
            case "wrists":
                events = KaguraSpikeDetector.wristBottoms(frames, leftWrist: leftWrist, rightWrist: rightWrist, fps: 30)
            default:
                events = KaguraSpikeDetector.gestureLandings(
                    frames, pelvis: pelvis, arms: arms, fps: 30, beatPeriod: driven.beatPeriod)
            }
            for event in events {
                guard let music = fixture.truePlayback(at: times[window[0]] + event),
                      music >= truth[0], music < truth[truth.count - 1] else { continue }
                let beat = (truth.lastIndex { $0 <= music }) ?? 0
                phases.append((music - truth[beat]) / (truth[beat + 1] - truth[beat]))
            }
        }
        let count = max(phases.count, 1)
        var histogram = [Int](repeating: 0, count: 8)
        for phase in phases { histogram[min(Int(phase * 8), 7)] += 1 }
        return Lock(
            onBeat: Double(phases.filter { min($0, 1 - $0) < 0.125 }.count) / Double(count),
            halfBeat: Double(phases.filter { abs($0 - 0.5) < 0.125 }.count) / Double(count),
            count: phases.count,
            histogram: histogram)
    }

    // MARK: - Tests

    @Test("Twist hip turns land on the grid beat; the +½-beat decoy moves them to the \"and\"",
          arguments: KaguraFixture.tracks)
    func pulseLock(track: String) throws {
        let fixture = try KaguraFixture.load(track)
        let lock = try Self.measure(fixture, shiftBeats: 0)
        let decoy = try Self.measure(fixture, shiftBeats: 0.5)
        print("[kagura-pulse] \(track) TRUE grid : \(lock)")
        print("[kagura-pulse] \(track) DECOY +½  : \(decoy)")
        #expect(lock.count >= 30, "\(track): only \(lock.count) hip-yaw events detected")
        #expect(lock.onBeat >= Self.onBeatFloor, "\(track): \(lock)")
        #expect(decoy.onBeat <= Self.decoyOnBeatCeiling, "\(track) decoy stayed on the beat: \(decoy)")
        #expect(decoy.halfBeat >= Self.onBeatFloor, "\(track) decoy did not move to the half-beat: \(decoy)")
    }

    @Test("The ported detector reproduces the spike's _extrema on a known signal")
    func detectorMatchesSpike() {
        // A 1.4 Hz sine yaw of ±20° over a slow 0.1 Hz drift at 30 fps. scipy on the same signal
        // (kagura.py `_extrema`, run 2026-09-25) returns these 14 events, in frames of 1/30 s.
        let fps = 30.0
        let sig = (0..<150).map { i -> Double in
            let t = Double(i) / fps
            return 20 * sin(2 * .pi * 1.4 * t) + 30 * sin(2 * .pi * 0.1 * t)
        }
        let scipyFrames = [6, 16, 27, 37, 48, 59, 70, 80, 91, 102, 112, 123, 134, 145]
        let events = KaguraSpikeDetector.extrema(sig, fps: fps)
        #expect(events.map { Int(($0 * fps).rounded()) } == scipyFrames, "\(events)")
    }
}

// MARK: - Per dance (KAG.3)

extension KaguraPulseLockReplayTests {

    /// The spike on the same captures (`kagura.py film <capture> none /dev/null --family <dance>
    /// --metrics-only --shift-beats k`, 2026-09-25), on-beat % / half-beat %, for k = 0 … 4. A WHOLE-beat
    /// shift keeps the true phase and only moves where clips start, so the five cuts are the spike's own
    /// spread on that capture (e.g. there_there chicken 51 → 31 % on the beat). The gate is against the
    /// spike's LOWEST cut: a single cut read one sample of that spread — so_what macarena reads 85 %
    /// on-beat + "and" at k = 0 and 75–80 % at k = 1 … 4, and the build's 73 % sits between them.
    static let spike: [String: [KaguraDance: [(on: Double, half: Double)]]] = [
        "love_rehab": [
            .cabbage: [(100, 0), (100, 0), (94, 0), (94, 0), (93, 0)],
            .chicken: [(49, 32), (42, 34), (41, 26), (41, 29), (44, 29)],
            .macarena: [(51, 0), (50, 5), (42, 2), (45, 3), (41, 3)],
            .egyptian: [(39, 61), (40, 60), (45, 55), (44, 56), (36, 64)],
        ],
        "so_what": [
            .cabbage: [(94, 0), (100, 0), (100, 0), (100, 0), (94, 0)],
            .chicken: [(49, 24), (49, 24), (48, 26), (45, 30), (45, 23)],
            .macarena: [(38, 47), (41, 37), (39, 41), (39, 39), (36, 39)],
            .egyptian: [(42, 56), (41, 59), (40, 55), (48, 52), (46, 52)],
        ],
        "there_there": [
            .cabbage: [(100, 0), (100, 0), (100, 0), (94, 0), (100, 0)],
            .chicken: [(51, 31), (51, 30), (51, 32), (47, 25), (31, 28)],
            .macarena: [(38, 45), (41, 37), (40, 40), (33, 44), (33, 43)],
            .egyptian: [(29, 71), (40, 57), (39, 59), (37, 61), (36, 64)],
        ],
    ]

    /// Points below the spike's lowest cut the build may sit (KAG.3 prompt: 10).
    static let margin = 10.0
    /// The +½-beat decoy must move (on − half) at least this far toward the other side. The build's
    /// smallest measured move is 8 points (there_there macarena, whose landings sit between beats).
    static let decoySwing = 5.0

    static let cases: [(String, KaguraDance)] = KaguraFixture.tracks.flatMap { track in
        [KaguraDance.cabbage, .chicken, .macarena, .egyptian].map { (track, $0) }
    }

    @Test("Each dance locks to the grid no worse than the spike on the same capture", arguments: cases)
    func perDance(track: String, dance: KaguraDance) throws {
        let fixture = try KaguraFixture.load(track)
        let lock = try Self.measure(fixture, shiftBeats: 0, dance: dance)
        let decoy = try Self.measure(fixture, shiftBeats: 0.5, dance: dance)
        let cuts = try #require(Self.spike[track]?[dance])
        let floorOn = (cuts.map(\.on).min() ?? 0) - Self.margin
        let floorBoth = (cuts.map { $0.on + $0.half }.min() ?? 0) - Self.margin
        print(String(format: "[kagura-pulse-dance] %@ %@ TRUE %@ | DECOY %@ | spike k=0 %.0f/%.0f, floors %.0f / %.0f",
                     track, "\(dance)", lock.description, decoy.description, cuts[0].on, cuts[0].half, floorOn, floorBoth))
        #expect(lock.count >= 10)
        #expect(lock.onBeat * 100 >= floorOn, "\(track) \(dance): \(lock)")
        #expect((lock.onBeat + lock.halfBeat) * 100 >= floorBoth, "\(track) \(dance): \(lock)")
        let lean = (lock.onBeat - lock.halfBeat) * 100
        let decoyLean = (decoy.onBeat - decoy.halfBeat) * 100
        #expect((decoyLean - lean) * (lean >= 0 ? -1 : 1) >= Self.decoySwing,
                "\(track) \(dance): the decoy did not swap the beat and the \"and\" (\(lock) → \(decoy))")
    }

    @Test("The ported wrists and gesture detectors reproduce scipy on known signals")
    func detectorsMatchSpike() {
        // scipy on the same signals (kagura.py's `wrists` branch and `cmd_film`'s gesture block, run
        // 2026-09-25), in frames of 1/30 s.
        let fps = 30.0
        let t = (0..<150).map { Double($0) / fps }
        let wrists = t.map { 1.6 + 0.25 * sin(2 * .pi * 0.9 * $0) + 0.05 * sin(2 * .pi * 2.7 * $0) + 0.1 * sin(2 * .pi * 0.2 * $0) }
        let bottoms = KaguraSpikeDetector.wristBottoms(summedHeight: wrists, fps: fps)
        #expect(bottoms.map { Int(($0 * fps).rounded()) } == [22, 62, 95, 122], "\(bottoms)")
        let speed = t.map {
            1.0 + 0.8 * pow(cos(2 * .pi * 1.6 * $0), 2) + 0.3 * sin(2 * .pi * 3.1 * $0) + 0.2 * sin(2 * .pi * 0.3 * $0)
        }
        let landings = KaguraSpikeDetector.gestureLandings(speed: speed, fps: fps, beatPeriod: 0.52)
        #expect(landings.map { Int(($0 * fps).rounded()) } == [6, 15, 25, 34, 44, 53, 62, 71, 88, 97, 106, 116, 125, 135, 144],
                "\(landings)")
        #expect(KaguraSpikeDetector.gradient([0, 1, 4, 9, 7, 7.5]) == [1, 2, 4, 1.5, -0.75, 0.5])
    }
}
