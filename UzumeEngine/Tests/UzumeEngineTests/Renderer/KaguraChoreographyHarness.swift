// KaguraChoreographyHarness — drives `KaguraChoreographer` through `KaguraBeatClock` at 60 fps (KAG.2/3).
//
// The order production uses: read p, advance, then push the clock. Synthetic grids are fine HERE: the
// tests that use this check structural properties of the choreography (where cuts land, whether a pose
// jumps, which tercile a pick reads). The real-music claims are `KaguraPulseLockReplayTests`.

import Foundation
import simd
import Testing
@testable import Renderer

enum KaguraChoreographyHarness {

    static let fps = 60.0

    struct Run {
        var joints: [[SIMD3<Float>]] = []
        var dancing: [Bool] = []
        var beats: [Double?] = []
        /// Per frame: the current segment's dance (nil = sway), the dance it fades from, whether fading.
        var dance: [KaguraDance?] = []
        var fadingFrom: [KaguraDance?] = []
        var fading: [Bool] = []
        var swayInFade: [Bool] = []
        /// Per frame: whether the grid-CV safety net held the dancer (§7).
        var irregular: [Bool] = []
        /// Render time of each auto pick, parallel to `choreographer.picks`.
        var pickTimes: [Double] = []
        var choreographer: KaguraChoreographer
    }

    static func grid(bpm: Double, seconds: Double, downbeatOffset: Int = 0,
                     beatsPerBar: Int = 4, bars: Bool = true) throws -> KaguraGrid {
        let period = 60 / bpm
        let beats = (0..<Int(seconds / period) + 8).map { Double($0) * period }
        return try grid(beats: beats, downbeatOffset: downbeatOffset, beatsPerBar: beatsPerBar, bars: bars)
    }

    static func grid(beats: [Double], downbeatOffset: Int = 0, beatsPerBar: Int = 4, bars: Bool = true) throws -> KaguraGrid {
        let downbeats = bars ? stride(from: downbeatOffset, to: beats.count, by: beatsPerBar).map { beats[$0] } : []
        return try #require(KaguraGrid(beats: beats, downbeats: downbeats,
                                       beatsPerBar: bars ? beatsPerBar : 1, hasBarInformation: bars))
    }

    /// Run `seconds` at 60 fps.
    /// - Parameters:
    ///   - sequence: dances forced in turn (default: the twist alone, KAG.2); empty = pick by the song.
    ///   - bass: `bassAtt` at render time `t` (default steady music, never silent, reach 1).
    ///   - playback: the playback clock at `t` (default `t`; hold it to stop the clock).
    ///   - regrid: may replace the grid at render time `t`.
    static func run(seconds: Double, grid: KaguraGrid?, streaming: Bool = false,
                    sequence: [KaguraDance] = [.twist], songArousal: Double? = nil,
                    bass: (Double) -> Double = { _ in 0.2 },
                    playback: (Double) -> Double = { $0 },
                    lockState: (Double) -> Int = { _ in 0 },
                    regrid: ((Double) -> KaguraGrid??)? = nil) throws -> Run {
        let lib = try KaguraClipLibrary.shared()
        var run = Run(choreographer: try #require(KaguraChoreographer(library: lib, sequence: sequence)))
        run.choreographer.setSongArousal(songArousal)
        var clock = KaguraBeatClock()
        clock.setGrid(grid, streaming: streaming)
        for frame in 0..<Int(seconds * fps) {
            let time = Double(frame) / fps
            if let change = regrid?(time) { clock.setGrid(change, streaming: streaming) }
            let beat = clock.beatPosition(atRenderTime: time)
            let picks = run.choreographer.picks.count
            let pose = run.choreographer.advance(
                deltaTime: 1 / fps, beat: beat, grid: clock.grid, gridGeneration: clock.gridGeneration,
                dancePermitted: clock.dancePermitted, bass: bass(time))
            if run.choreographer.picks.count > picks { run.pickTimes.append(time) }
            run.joints.append(pose)
            run.dancing.append(run.choreographer.isDancing)
            run.beats.append(beat)
            run.dance.append(run.choreographer.currentDance)
            run.fadingFrom.append(run.choreographer.fadingFromDance)
            run.fading.append(run.choreographer.isFading)
            run.swayInFade.append(run.choreographer.fadeTouchesSway)
            run.irregular.append(run.choreographer.gridIrregular)
            clock.ingest(playbackSeconds: playback(time), renderTime: time, lockState: lockState(time))
        }
        return run
    }

    /// Largest single-joint displacement between frames `index - 1` and `index`.
    static func step(_ frames: [[SIMD3<Float>]], at index: Int) -> Float {
        zip(frames[index], frames[index - 1]).map { simd_distance($0, $1) }.max() ?? 0
    }

    /// Largest single-frame joint displacement in `frames[range]`.
    static func maxStep(_ frames: [[SIMD3<Float>]], in range: Range<Int>? = nil) -> Float {
        let range = range ?? 1..<frames.count
        return range.filter { $0 > 0 && $0 < frames.count }.map { step(frames, at: $0) }.max() ?? 0
    }

    /// Frames with no joint moving at all (a frozen human reads as a dropped frame).
    static func frozenFrames(_ run: Run, in range: Range<Int>? = nil) -> [Int] {
        (range ?? 1..<run.joints.count).filter { index in
            index > 0 && zip(run.joints[index], run.joints[index - 1]).allSatisfy { simd_distance($0, $1) < 1e-6 }
        }
    }
}
