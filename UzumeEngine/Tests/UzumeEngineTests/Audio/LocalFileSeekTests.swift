// LocalFileSeekTests — LFSEEK.1. A jump within a local file restarts the player at that frame,
// the analysis playhead reads the new position (not 0), the jump never fires the queue advance,
// and a paused player stays paused. Drives the real AVAudioEngine on the real tempo fixture, like
// SessionLifecycleChurnTests (the output is muted under XCTest, BUG-052).

import AVFoundation
import Foundation
import Testing
@testable import Audio
@testable import DSP

@Suite("LFSEEK.1 local-file seek", .serialized)
struct LocalFileSeekTests {

    private static func fixture() -> URL? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("fixture absent at \(url.path) — run Scripts/fetch_tempo_fixtures.sh")
            return nil
        }
        return url
    }

    @Test("a seek plays from the new point: the playhead reads it, and the end comes that much sooner")
    func seekMovesThePlayhead() throws {
        guard #available(macOS 14.2, *), let url = Self.fixture() else { return }
        let duration = try { let f = try AVAudioFile(forReading: url); return Double(f.length) / f.processingFormat.sampleRate }()
        let ended = DispatchSemaphore(value: 0)
        let provider = LocalFilePlaybackProvider(url: url)
        provider.onFileEnded = { ended.signal() }
        try provider.start()
        defer { provider.stop() }

        try provider.seek(to: 12)
        Thread.sleep(forTimeInterval: 0.3)
        let at = try #require(provider.playheadSeconds)
        #expect((12...13).contains(at), "playhead read \(at) s after a seek to 12 s")

        // A second seek to 3 s before the end: the old node's stop must not read as end-of-file
        // (that would skip the track), and the real end arrives a few seconds later. The player
        // reports the end once it has READ the last audio (`.dataConsumed`, the pre-existing EOF
        // semantics), a little before it has played it — so the remainder must outlast that read.
        try provider.seek(to: duration - 3)
        #expect(ended.wait(timeout: .now() + 0.3) == .timedOut, "the seek itself fired the queue advance")
        #expect(ended.wait(timeout: .now() + 5) == .success, "no end-of-file within 5 s of a seek to 3 s before it")
    }

    @Test("seeking while paused stays paused")
    func pausedStaysPaused() throws {
        guard #available(macOS 14.2, *), let url = Self.fixture() else { return }
        let provider = LocalFilePlaybackProvider(url: url)
        try provider.start()
        defer { provider.stop() }
        provider.pause()
        try provider.seek(to: 5)
        #expect(provider.isPaused)
    }

    @Test("the track clock moves to the seek point and keeps the beat grid")
    func mirClockFollowsTheSeek() {
        let mir = MIRPipeline()
        mir.setBeatGrid(BeatGrid(beats: stride(from: 0.0, to: 60, by: 0.5).map { $0 }, downbeats: [], bpm: 120,
                                 beatsPerBar: 4, barConfidence: 1, frameRate: 50, frameCount: 0))
        _ = mir.process(magnitudes: [Float](repeating: 0, count: 512), fps: 60, time: 0, deltaTime: 2)
        mir.seek(to: 190)
        #expect(mir.elapsedSeconds == 190)
        #expect(mir.liveDriftTracker.hasGrid, "a seek is the same song: the grid stays installed")
    }
}
