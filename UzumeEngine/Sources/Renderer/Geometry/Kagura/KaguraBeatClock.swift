// KaguraBeatClock — the dancer's musical position, continuous at render rate (KAG.2).
//
// KAGURA_DESIGN §5: the warp reads a beat position `p(t)` = beat index + fraction. It must be
// continuous. `FeatureVector.beatPhase01` updates ~14.6 times a second in steps of ~0.11 beat
// (BUG-096, `DancePhase.swift`), so a dancer driven from it steps like a robot. `p` is computed
// here from the grid's own beat times and a render-rate playback position instead.
//
// Renderer cannot see DSP's `BeatGrid`, so the app copies the grid in as plain data
// (`KaguraGrid`) on every install or clear, and pushes the playback position once per frame from
// its stateful tick:
//   - local-file path: the playback clock (BUG-087: the only clock there);
//   - streaming path: playback time + the drift tracker's drift, as its relative beat times use it.
// The push is smoothed with `PlaybackClockSmoother` (coarse clock → continuous position), then
// phase-locked at render rate: the position advances one playback second per render second and is
// corrected gently toward the smoothed reading (DancePhase's shape, FTR.28). The smoother alone
// first sees each coarse tick up to a frame late, which measured as per-frame steps of 0.38–1.5×
// nominal on the 43 Hz captures — a ~10 ms wobble in the dance; the lock makes them even. It is
// STAMPED with the render clock. The tick runs after `particles.update` (RenderPipeline+Draw), so
// the dancer reads a position pushed one frame earlier; `playbackSeconds(atRenderTime:)`
// extrapolates it by the render time elapsed since the stamp, so the dancer is never a frame late.

import Foundation
import Shared

// MARK: - KaguraGrid

/// The cached beat grid as plain data (a copy of DSP's `BeatGrid` fields Kagura reads).
public struct KaguraGrid: Sendable, Equatable {

    /// Beat times, seconds, ascending.
    public let beats: [Double]
    /// Downbeat times, seconds, ascending (a subset of `beats`).
    public let downbeats: [Double]
    /// Beats per bar as the grid estimated it.
    public let beatsPerBar: Int
    /// `BeatGrid.hasBarInformation` — false when the grid declined the bar (D-210, BUG-117).
    public let hasBarInformation: Bool

    /// Median inter-beat interval, seconds.
    public let beatPeriod: Double
    /// Beat index of each downbeat (nearest beat), ascending and unique.
    let downbeatIndices: [Int]

    /// `nil` when there are fewer than two beats: no position can be derived from one.
    public init?(beats: [Double], downbeats: [Double], beatsPerBar: Int, hasBarInformation: Bool) {
        guard beats.count >= 2 else { return nil }
        self.beats = beats
        self.downbeats = downbeats
        self.beatsPerBar = beatsPerBar
        self.hasBarInformation = hasBarInformation
        let intervals = zip(beats.dropFirst(), beats).map { $0 - $1 }.sorted()
        beatPeriod = max(intervals[intervals.count / 2], 1e-3)
        var indices: [Int] = []
        for time in downbeats {
            let index = Self.nearestIndex(of: time, in: beats)
            if index != indices.last { indices.append(index) }
        }
        downbeatIndices = indices
    }

    /// Whether clip changes can fall on real bar lines. With no bar information
    /// (`beatsPerBar == 1`, or no downbeats) they fall every 4 beats instead (D-210).
    public var knowsBars: Bool { hasBarInformation && beatsPerBar > 1 && !downbeatIndices.isEmpty }

    /// The continuous beat position at `seconds`: beat index + fraction, piecewise linear
    /// between beats, extended past either end with the edge interval (continuous at the ends).
    public func beatPosition(atTime seconds: Double) -> Double {
        let last = beats.count - 1
        if seconds <= beats[0] {
            return (seconds - beats[0]) / max(beats[1] - beats[0], 1e-6)
        }
        if seconds >= beats[last] {
            return Double(last) + (seconds - beats[last]) / max(beats[last] - beats[last - 1], 1e-6)
        }
        var lo = 0, hi = last
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if beats[mid] <= seconds { lo = mid } else { hi = mid }
        }
        return Double(lo) + (seconds - beats[lo]) / max(beats[hi] - beats[lo], 1e-6)
    }

    /// The first bar line strictly after beat position `beat`, as a beat index.
    ///
    /// Known downbeats are used where the grid has them; before the first and after the last the
    /// bar is extended every `beatsPerBar` beats. With no bar information, every 4th beat (from
    /// beat 0) is a bar line (D-210: "decline the bar, keep the beat").
    public func nextBarLine(after beat: Double) -> Int {
        guard knowsBars else { return (Int(floor(beat / 4)) + 1) * 4 }
        let bar = beatsPerBar
        let first = downbeatIndices[0], last = downbeatIndices[downbeatIndices.count - 1]
        if beat >= Double(last) {
            return last + (Int(floor((beat - Double(last)) / Double(bar))) + 1) * bar
        }
        if beat < Double(first) {
            let barsBack = Int(ceil((Double(first) - beat) / Double(bar))) - 1
            return first - barsBack * bar
        }
        // `first <= beat < last`: the first known downbeat after `beat` exists.
        return downbeatIndices.first { Double($0) > beat } ?? last
    }

    private static func nearestIndex(of time: Double, in beats: [Double]) -> Int {
        var best = 0
        for (index, beat) in beats.enumerated() where abs(beat - time) < abs(beats[best] - time) {
            best = index
        }
        return best
    }
}

// MARK: - KaguraBeatClock

/// Grid + playback position → the continuous beat position `p(t)` at any render time.
public struct KaguraBeatClock: Sendable {

    /// The installed grid; `nil` = no grid (the dancer sways).
    public private(set) var grid: KaguraGrid?
    /// Bumped on every `setGrid`, so a consumer can tell a replaced grid from the same one.
    public private(set) var gridGeneration = 0
    /// Streaming path: the position adds the drift tracker's drift, and the dancer waits for its
    /// lock before dancing (§3a). Local-file path: the playback clock alone (BUG-087).
    public private(set) var streaming = false
    /// Drift-tracker lock state as the app publishes it (0 unlocked, 1 locking, 2 locked).
    public private(set) var lockState = 0

    /// Correction toward the smoothed clock per push (≈ 0.17 s time constant at 60 fps).
    static let lockGain = 0.1

    private var smoother = PlaybackClockSmoother()
    private var stampedSeconds: Double?
    private var stampRenderTime: Double = 0

    public init() {}

    /// Install (or clear, with `nil`) the grid, and say which path it came from.
    public mutating func setGrid(_ grid: KaguraGrid?, streaming: Bool) {
        self.grid = grid
        self.streaming = streaming
        gridGeneration &+= 1
    }

    /// Push this frame's playback clock, the drift tracker's drift (seconds; added on the streaming
    /// path only, as its relative beat times add it) and lock state, stamped with the render clock
    /// (`FeatureVector.time`).
    public mutating func ingest(playbackSeconds: Double, driftSeconds: Double = 0, renderTime: Double, lockState: Int) {
        let raw = streaming ? playbackSeconds + driftSeconds : playbackSeconds
        let target = smoother.position(rawSeconds: raw, now: renderTime)
        if let predicted = self.playbackSeconds(atRenderTime: renderTime),
           abs(target - predicted) < PlaybackClockSmoother.maxDeadReckonSeconds {
            // Locked: never backwards, corrected a tenth of the way per frame.
            stampedSeconds = max(predicted + Self.lockGain * (target - predicted), stampedSeconds ?? predicted)
        } else {
            stampedSeconds = target   // first push, a seek, a track change: resync exactly
        }
        stampRenderTime = renderTime
        self.lockState = lockState
    }

    /// Forget the clock's history (track change). The grid is left alone: on the local-file path
    /// the new track's grid is installed BEFORE the per-track reset runs.
    public mutating func resetClock() {
        smoother.reset()
        stampedSeconds = nil
    }

    /// The pushed position extrapolated to `renderTime` — capped like the smoother's own dead
    /// reckoning, so a stopped clock reads as held rather than running on into the track.
    public func playbackSeconds(atRenderTime renderTime: Double) -> Double? {
        guard let stampedSeconds else { return nil }
        let since = min(max(renderTime - stampRenderTime, 0), PlaybackClockSmoother.maxDeadReckonSeconds)
        return stampedSeconds + since
    }

    /// `p(t)`: the beat position at `renderTime`, or `nil` without a grid or a clock.
    public func beatPosition(atRenderTime renderTime: Double) -> Double? {
        guard let grid, let seconds = playbackSeconds(atRenderTime: renderTime) else { return nil }
        return grid.beatPosition(atTime: seconds)
    }

    /// Whether the dancer may dance: a grid, and on the streaming path a lock (`lockState ≥ 1`).
    public var dancePermitted: Bool { grid != nil && (!streaming || lockState >= 1) }
}
