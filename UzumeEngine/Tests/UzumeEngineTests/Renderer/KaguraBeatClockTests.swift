// KaguraBeatClockTests — `p(t)` is continuous at render rate (KAG.2 task 1; KAGURA_DESIGN §5).
//
// Drives `KaguraBeatClock` exactly as production does: 60 Hz render frames; at each frame the
// dancer reads `p` FIRST (`particles.update`), then the app's tick pushes the playback clock
// stamped with this frame's render time (the tick runs after update, RenderPipeline+Draw). The
// clock is the capture's own 43 Hz `playback_time_s`, so the renderer sees it hold and jump.
//
// The negative control is the same check on a `p` built from the stepped `beatPhase01`
// (beat count + phase, the BUG-096 staircase): it must FAIL, or the check has no teeth.

import Foundation
import Testing
@testable import Renderer

private extension Array where Element == Double {
    var mean: Double { isEmpty ? 0 : reduce(0, +) / Double(count) }
}

@Suite("Kagura beat clock — continuous p(t) (KAG.2)")
struct KaguraBeatClockTests {

    private static let frame = 1.0 / 60.0

    /// Steps of `p` across consecutive 60 Hz frames, and the nominal per-frame advance.
    private static func steps(_ positions: [Double], grid: KaguraGrid) -> (steps: [Double], nominal: Double) {
        (zip(positions.dropFirst(), positions).map { $0 - $1 }, frame / grid.beatPeriod)
    }

    private static func violations(_ steps: [Double], nominal: Double) -> Int {
        steps.filter { !($0 > 0) || $0 > 2 * nominal }.count
    }

    @Test("p(t) from the pushed clock is strictly increasing with no step over 2× nominal",
          arguments: KaguraFixture.tracks)
    func continuousFromPushedClock(track: String) throws {
        let fixture = try KaguraFixture.load(track)
        let grid = try fixture.grid()
        var clock = KaguraBeatClock()
        clock.setGrid(grid, streaming: false)

        var positions: [Double] = []
        var lagMs: [Double] = []
        var time = 0.0
        while time < fixture.duration {
            if let seconds = clock.playbackSeconds(atRenderTime: time), let beat = clock.beatPosition(atRenderTime: time),
               let row = fixture.row(at: time), row + 1 < fixture.rowTime.count {                      // update
                positions.append(beat)
                // Truth: the capture's playback clock interpolated to this render instant.
                let frac = (time - fixture.rowTime[row]) / (fixture.rowTime[row + 1] - fixture.rowTime[row])
                let truth = fixture.playback[row] + frac * (fixture.playback[row + 1] - fixture.playback[row])
                if time > 1 { lagMs.append((truth - seconds) * 1000) }
            }
            if let row = fixture.row(at: time) {                                              // tick
                clock.ingest(playbackSeconds: fixture.playback[row], renderTime: time, lockState: 0)
            }
            time += Self.frame
        }
        let (steps, nominal) = Self.steps(positions, grid: grid)
        let bad = Self.violations(steps, nominal: nominal)
        print("[kagura-clock] \(track): \(steps.count) steps, nominal \(String(format: "%.4f", nominal)) beat, "
              + "min \(String(format: "%.4f", steps.min() ?? 0)) max \(String(format: "%.4f", steps.max() ?? 0)), "
              + "violations \(bad); lag vs true playback mean \(String(format: "%.1f", lagMs.mean)) ms, "
              + "max |lag| \(String(format: "%.1f", lagMs.map(abs).max() ?? 0)) ms")
        #expect(positions.count > 1500, "\(track): too few frames with a beat position")
        #expect(bad == 0, "\(track): \(bad) frames where p(t) held, went back, or jumped > 2× nominal")
        // Stamp + extrapolate: the dancer reads a position pushed a frame earlier, and must not
        // be a frame (16.7 ms) behind for it.
        #expect(abs(lagMs.mean) < 16.7 / 2, "\(track): p(t) lags the playback clock by a frame or more")
    }

    @Test("Negative control: p(t) from the stepped beatPhase01 FAILS the same check",
          arguments: KaguraFixture.tracks)
    func staircaseFromBeatPhaseFails(track: String) throws {
        let fixture = try KaguraFixture.load(track)
        let grid = try fixture.grid()
        var positions: [Double] = []
        var time = 0.0
        while time < fixture.duration {
            if let row = fixture.row(at: time) {
                // Beat count so far (phase wraps) + the current stepped phase.
                let wraps = (1...max(row, 1)).filter { fixture.beatPhase[$0 - 1] - fixture.beatPhase[$0] > 0.5 }
                positions.append(Double(wraps.count) + fixture.beatPhase[row])
            }
            time += Self.frame
        }
        let (steps, nominal) = Self.steps(positions, grid: grid)
        let bad = Self.violations(steps, nominal: nominal)
        print("[kagura-clock] \(track) beatPhase01 staircase: violations \(bad) of \(steps.count)")
        #expect(bad > 100, "\(track): the beatPhase01 staircase passed — the continuity check has no teeth")
    }

    @Test("A stalled clock holds after 0.25 s instead of running on")
    func stalledClockHolds() throws {
        let grid = try #require(KaguraGrid(beats: (0..<40).map { Double($0) * 0.5 }, downbeats: [],
                                           beatsPerBar: 4, hasBarInformation: true))
        var clock = KaguraBeatClock()
        clock.setGrid(grid, streaming: false)
        clock.ingest(playbackSeconds: 5, renderTime: 100, lockState: 0)
        let atStamp = try #require(clock.beatPosition(atRenderTime: 100))
        let later = try #require(clock.beatPosition(atRenderTime: 103))
        #expect(abs(atStamp - 10) < 1e-9)
        #expect(abs(later - 10.5) < 1e-9, "extrapolation must cap at 0.25 s (half a beat at 120 BPM)")
    }

    @Test("Streaming: dancing waits for lockState ≥ 1; local-file does not")
    func lockGate() throws {
        let grid = try #require(KaguraGrid(beats: [0, 0.5, 1], downbeats: [], beatsPerBar: 4,
                                           hasBarInformation: true))
        var clock = KaguraBeatClock()
        #expect(!clock.dancePermitted)
        clock.setGrid(grid, streaming: true)
        clock.ingest(playbackSeconds: 0, renderTime: 0, lockState: 0)
        #expect(!clock.dancePermitted)
        clock.ingest(playbackSeconds: 0, renderTime: 0, lockState: 1)
        #expect(clock.dancePermitted)
        clock.setGrid(grid, streaming: false)
        clock.ingest(playbackSeconds: 0, renderTime: 0, lockState: 0)
        #expect(clock.dancePermitted)
    }
}
