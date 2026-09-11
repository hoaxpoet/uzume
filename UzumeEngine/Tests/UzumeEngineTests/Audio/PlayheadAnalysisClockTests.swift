// PlayheadAnalysisClockTests — BUG087.4 tasks 1 and 2.
//
// Two properties, in the order the increment gates them:
//
//  1. **The position source, before anything is built on it.** BUG087.4's own risk section says
//     playhead accuracy is the whole thing: a read position that drifts from what is audible
//     DESYNCHRONISES the analysis, which is worse than being uniformly late, because a constant
//     offset is at least consistent. So `AVAudioPlayerNode.playerTime` is driven through
//     `PlaybackClockSmoother` on a real file, across a real loop boundary, and the band the
//     smoother promises is checked ON THIS CONSUMER — never behind the player, never more than
//     `maxDeadReckonSeconds` ahead, never backwards.
//
//  2. **The read-ahead addresses frames, not files.** A ramp fixture (sample value == frame index
//     ÷ length) makes "correctly positioned" an exact equality rather than a plausibility check,
//     so a read that spans the end of the file and continues into the next lap is verified frame
//     by frame — including from an absolute cursor several laps past the end, which is what the
//     clock actually holds.
import Testing
import Foundation
import AVFoundation
import Shared
@testable import Audio

@Suite("PlayheadAnalysisClock (BUG087.4)")
struct PlayheadAnalysisClockTests {

    // MARK: - Fixtures

    /// Write a float32 stereo file whose left channel ramps 0 → 1 over its length and whose right
    /// channel is the complement. Frame `i` is identifiable from its sample value alone.
    static func writeRamp(frames: Int, sampleRate: Double = 44_100) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug087_4_ramp_\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                      frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let planes = buffer.floatChannelData!
        for i in 0..<frames {
            let v = Float(i) / Float(frames)
            planes[0][i] = v
            planes[1][i] = 1 - v
        }
        try file.write(from: buffer)
        return url
    }

    /// Expected left-channel value at file frame `i`.
    static func ramp(_ i: Int, of frames: Int) -> Float { Float(i) / Float(frames) }

    // MARK: - Task 2 — the read-ahead

    @Test("Reader is contiguous across the file end and into the next lap")
    func readerWrapsContiguously() throws {
        let n = 5_000
        let url = try Self.writeRamp(frames: n)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        // A block far smaller than the request, so the read walks several refills and the wrap
        // and the block boundary are not the same event.
        let reader = try #require(LoopingFileReader(file: file, blockSeconds: 0.01))
        #expect(reader.frameCount == AVAudioFramePosition(n))
        #expect(reader.channelCount == 2)

        var dst = [Float](repeating: .nan, count: 900 * 2)
        let written = reader.read(from: 4_700, frames: 900, into: &dst)
        #expect(written == 900 * 2)

        for k in 0..<900 {
            let expectedFrame = (4_700 + k) % n
            let got = dst[k * 2]
            let want = Self.ramp(expectedFrame, of: n)
            #expect(abs(got - want) < 1e-6,
                    "frame \(k): expected file frame \(expectedFrame) (\(want)), got \(got)")
            #expect(abs(dst[k * 2 + 1] - (1 - want)) < 1e-6, "right channel at \(k)")
        }
    }

    @Test("Reader addresses an absolute cursor several laps past the end")
    func readerAcceptsUnwrappedCursor() throws {
        let n = 4_096
        let url = try Self.writeRamp(frames: n)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let reader = try #require(LoopingFileReader(file: file, blockSeconds: 0.02))

        // What the clock actually holds after a few minutes of looping.
        let cursor = AVAudioFramePosition(n) * 37 + 4_000
        var dst = [Float](repeating: .nan, count: 200 * 2)
        let written = reader.read(from: cursor, frames: 200, into: &dst)
        #expect(written == 200 * 2)
        for k in 0..<200 {
            let want = Self.ramp((4_000 + k) % n, of: n)
            #expect(abs(dst[k * 2] - want) < 1e-6, "lap-37 frame \(k)")
        }
    }

    @Test("Reader refuses a file layout it cannot address rather than reading garbage")
    func readerRejectsEmptyFile() throws {
        let url = try Self.writeRamp(frames: 0)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        #expect(LoopingFileReader(file: file) == nil)
    }

    // MARK: - BUG-130 — a stopped playhead is silence

    @Test("A stalled or paused playhead delivers silence, not the last frame forever")
    func stalledPlayheadDeliversSilence() throws {
        let sampleRate = 44_100.0
        let n = 20_000
        let url = try Self.writeRamp(frames: n, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }
        let reader = try #require(LoopingFileReader(file: try AVAudioFile(forReading: url)))

        // A hand-driven playhead: `nil` models a paused node (no render time), a repeated value
        // models one whose clock has stopped advancing.
        final class Playhead: @unchecked Sendable { var seconds: Double? = 0 }
        let playhead = Playhead()
        var delivered: [[Float]] = []
        let clock = PlayheadAnalysisClock(
            reader: reader,
            position: { playhead.seconds },
            deliver: { samples, count, _, _ in
                delivered.append(Array(UnsafeBufferPointer(start: samples, count: count)))
            })

        // Playing: first tick seeds the cursor, the next carries real audio.
        clock.tick()
        playhead.seconds = 0.1
        clock.tick()
        try #require(delivered.count == 2)
        #expect(delivered[1].contains { $0 != 0 }, "a moving playhead must deliver real audio")

        // Stopped — the playhead no longer advances. Before BUG-130 every tick here returned and
        // the last FeatureVector re-published forever. `PlaybackClockSmoother` is entitled to dead
        // reckon `maxDeadReckonSeconds` past the last distinct clock value, so drain that bounded
        // tail first; after it every tick must be silence however long the stop lasts.
        Thread.sleep(forTimeInterval: PlaybackClockSmoother.maxDeadReckonSeconds + 0.05)
        clock.tick()
        delivered.removeAll()
        for _ in 0..<10 { clock.tick() }
        #expect(delivered.count == 10, "a stalled playhead must keep feeding the chain")
        #expect(delivered.allSatisfy { $0.allSatisfy { $0 == 0 } }, "stopped playback must read as silence")

        // Paused — no render time at all.
        delivered.removeAll()
        playhead.seconds = nil
        for _ in 0..<10 { clock.tick() }
        #expect(delivered.count == 10, "a paused playhead must keep feeding the chain")
        #expect(delivered.allSatisfy { $0.allSatisfy { $0 == 0 } }, "paused playback must read as silence")

        // The silence is BOUNDED: once the chain has settled at silence, further stalled ticks
        // deliver nothing, so a long pause costs `MIRPipeline.elapsedSeconds` at most the flush
        // window rather than its whole duration.
        delivered.removeAll()
        for _ in 0..<(PlayheadAnalysisClock.stallFlushTicks * 3) { clock.tick() }
        #expect(delivered.count == PlayheadAnalysisClock.stallFlushTicks - 20,
                "a stall must stop feeding once the flush budget is spent")
        #expect(delivered.allSatisfy { $0.allSatisfy { $0 == 0 } })

        // Resuming picks real audio back up — one tick re-seeds the cursor from the playhead (and
        // delivers nothing, the flush budget being spent), the next carries audio. No catching up
        // to a position the smoother ran ahead to while stalled.
        delivered.removeAll()
        playhead.seconds = 0.2
        clock.tick()
        playhead.seconds = 0.21
        clock.tick()
        try #require(delivered.count == 1)
        #expect(delivered[0].contains { $0 != 0 }, "resume must deliver real audio again")
    }

    // MARK: - Task 1 — the position source, on a real player, across a real loop

    @Test("Smoothed playhead stays inside the band across a loop boundary", .timeLimit(.minutes(1)))
    func smoothedPositionIsBoundedAcrossLoop() throws {
        // 1.2 s of audio, sampled for 4 s → at least two loop boundaries.
        let sampleRate = 44_100.0
        let n = Int(sampleRate * 1.2)
        let url = try Self.writeRamp(frames: n, sampleRate: sampleRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let file = try AVAudioFile(forReading: url)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
        engine.mainMixerNode.outputVolume = 0     // never play fixture audio out loud (BUG-052)

        // Loop the same way the provider does, so `sampleTime` keeps counting across the boundary
        // instead of restarting — which is what makes the position monotone for the smoother.
        let rearm = Rearm(player: player, file: file)
        rearm.schedule()
        try engine.start()
        player.play()

        var smoother = PlaybackClockSmoother()
        var samples: [(wall: Double, raw: Double, smoothed: Double)] = []
        let tick = 1.0 / PlayheadAnalysisClock.tickHz
        let deadline = Date().addingTimeInterval(4.0)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: tick)
            guard let nodeTime = player.lastRenderTime,
                  let t = player.playerTime(forNodeTime: nodeTime),
                  t.isSampleTimeValid, t.sampleRate > 0 else { continue }
            let raw = Double(t.sampleTime) / t.sampleRate
            let now = CACurrentMediaTime()
            samples.append((now, raw, smoother.position(rawSeconds: raw, now: now)))
        }
        player.stop()
        engine.stop()

        try #require(samples.count > 100, "player produced no usable time base")
        let duration = Double(n) / sampleRate
        let laps = samples.last!.raw / duration
        #expect(laps > 2.0, "expected >2 loop boundaries, saw \(String(format: "%.2f", laps))")

        var backwards = 0
        var behind = 0
        var maxLeadMs = 0.0
        var overshoot = 0
        let eps = 1e-6
        for i in samples.indices {
            if i > 0 && samples[i].smoothed < samples[i - 1].smoothed - eps { backwards += 1 }
            if samples[i].smoothed < samples[i].raw - eps { behind += 1 }
            let lead = samples[i].smoothed - samples[i].raw
            maxLeadMs = max(maxLeadMs, lead * 1000)
            if lead > PlaybackClockSmoother.maxDeadReckonSeconds + eps { overshoot += 1 }
        }

        print(String(
            format: "[BUG087.4 task1] %d samples over %.2f s, %.2f laps of a %.2f s file | "
                + "backwards=%d behind-player=%d beyond-band=%d | max lead %.1f ms",
            samples.count, samples.last!.wall - samples.first!.wall, laps, duration,
            backwards, behind, overshoot, maxLeadMs))

        #expect(backwards == 0, "smoothed position stepped backwards \(backwards)x")
        #expect(behind == 0, "smoothed position fell behind the player \(behind)x")
        #expect(overshoot == 0, "smoothed position ran beyond the dead-reckon band \(overshoot)x")
    }

    /// Re-arms `scheduleFile` at EOF so the player loops without stopping, mirroring
    /// `LocalFilePlaybackProvider._scheduleFileLoopLocked`.
    private final class Rearm: @unchecked Sendable {
        private let player: AVAudioPlayerNode
        private let file: AVAudioFile
        init(player: AVAudioPlayerNode, file: AVAudioFile) {
            self.player = player
            self.file = file
        }
        func schedule() {
            player.scheduleFile(file, at: nil) { [weak self] in
                guard let self else { return }
                DispatchQueue.global().async { self.schedule() }
            }
        }
    }
}
