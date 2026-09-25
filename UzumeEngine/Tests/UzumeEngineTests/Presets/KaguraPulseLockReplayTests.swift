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

    static func measure(_ fixture: KaguraFixture, shiftBeats: Double) throws -> Lock {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let clips = try KaguraClipLibrary.shared()
        let dancer = try KaguraDancer(device: ctx.device, library: lib.library)
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
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(fixture.name)_shift\(shiftBeats).csv")
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try csv.write(to: url, atomically: true, encoding: .utf8)
        }

        let leftHip = try #require(clips.jointNames.firstIndex(of: "lhip"))
        let rightHip = try #require(clips.jointNames.firstIndex(of: "rhip"))
        let truth = fixture.beats
        let crossfade = driven.beatPeriod
        let cutFrames = cuts.indices.filter { $0 > 0 && cuts[$0] != cuts[$0 - 1] }

        // `cmd_film`: per segment, skip the crossfade beat, detect at 30 fps, need 30 samples.
        var phases: [Double] = []
        for (index, start) in cutFrames.enumerated() {
            let end = index + 1 < cutFrames.count ? cutFrames[index + 1] : joints.count
            let window = stride(from: start, to: end, by: 2).filter { times[$0] >= times[start] + crossfade }
            guard window.count >= 30 else { continue }
            let events = KaguraSpikeDetector.hipYawEvents(
                window.map { joints[$0] }, leftHip: leftHip, rightHip: rightHip, fps: 30)
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
