// LocalFileTrackClockTests — BR.11 / audit B2: on the local-file path the track clock
// (`MIRPipeline.elapsedSeconds`) is the player's playhead wrapped at the file length, not a
// sum of analysis frames. Streaming (no source) still accumulates.

import Foundation
import Testing
@testable import Audio
@testable import DSP

@Suite("The local-file track clock follows the playhead (BR.11)")
struct LocalFileTrackClockTests {

    private final class Playhead: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Double?
        func set(_ seconds: Double?) { lock.withLock { value = seconds } }
        var current: Double? { lock.withLock { value } }
    }

    private let magnitudes = [Float](repeating: 0.1, count: 512)

    @Test func withAPlayhead_elapsedIsThePlayhead_pausesHold_loopsWrap() {
        let mir = MIRPipeline()
        let playhead = Playhead()
        mir.elapsedSecondsSource = { playhead.current }

        playhead.set(12.0)
        _ = mir.process(magnitudes: magnitudes, fps: 60, time: 0, deltaTime: 1.0 / 60)
        #expect(mir.elapsedSeconds == 12.0)

        // Paused: frames keep arriving (the 1.5 s silence flush), the playhead does not move.
        for _ in 0..<90 { _ = mir.process(magnitudes: magnitudes, fps: 60, time: 0, deltaTime: 1.0 / 60) }
        #expect(mir.elapsedSeconds == 12.0, "a pause adds no lead")

        // The file loops: the wrapped playhead restarts near 0.
        playhead.set(0.4)
        _ = mir.process(magnitudes: magnitudes, fps: 60, time: 0, deltaTime: 1.0 / 60)
        #expect(mir.elapsedSeconds == 0.4, "the clock wraps with the loop")
    }

    @Test func withoutASource_orBeforeThePlayerReports_itAccumulates() {
        let mir = MIRPipeline()
        for _ in 0..<60 { _ = mir.process(magnitudes: magnitudes, fps: 60, time: 0, deltaTime: 1.0 / 60) }
        #expect(abs(mir.elapsedSeconds - 1.0) < 1e-6, "streaming: sum of frames")

        let early = MIRPipeline()
        early.elapsedSecondsSource = { nil }   // the player has no render time yet
        _ = early.process(magnitudes: magnitudes, fps: 60, time: 0, deltaTime: 0.5)
        #expect(early.elapsedSeconds == 0.5)
    }

    @Test func thePlayheadWrapsAtTheFileLength() {
        #expect(LocalFilePlaybackProvider.wrapped(65.0, fileSeconds: 30.0) == 5.0)
        #expect(LocalFilePlaybackProvider.wrapped(12.0, fileSeconds: 30.0) == 12.0)
        #expect(LocalFilePlaybackProvider.wrapped(12.0, fileSeconds: 0) == 12.0)
    }
}
