// PlayheadAnalysisClock — drive the MIR chain from the decoded file at the playhead (BUG087.4).
//
// **The defect this exists for is CADENCE, not staleness.** `FFTProcessor` fills its window from
// `max(0, count - fftLength)` — the NEWEST frames of whatever it is handed — so audio is not old
// when it arrives. What is wrong on the local-file path is that nothing happens BETWEEN arrivals:
// AVAudioEngine delivers a tap buffer every 0.1 s whatever `installTap(bufferSize:)` asked for
// (BUG087.1 measured 4410 frames at 44.1 kHz and 4800 at 48 kHz — the same fixed *duration*), and
// `processAnalysisFrame` runs once per delivery. Every `FeatureVector` field therefore freezes for
// ~100 ms, which adds ~50 ms of lag on average and shows as a visible staircase.
//
// Slicing the delivered buffer was measured and does not fix it (BUG087.2/.3): all five slices land
// in the same instant, so a preset still observed ~16 Hz. **The binding constraint is how often
// audio ARRIVES.** So stop waiting for it to arrive — the whole file is already decoded on this
// path, and a read at the playhead is an array lookup that is not bounded by the tap at all. That
// is the advantage LFSTEM.1 created for stems and had not yet spent for MIR.
//
// Position comes from `AVAudioPlayerNode.playerTime` through `PlaybackClockSmoother` (LFSTEM.1d),
// which exists precisely to dead-reckon between coarse ticks without rewinding.
//
// Local-file playback ONLY, and since BUG087.5 it is the ONLY analysis source there — the player
// node carries no tap at all. Streaming already runs at ~59 Hz
// through a different capture path and is untouched.

@preconcurrency import AVFoundation
import Foundation
import os.log
import Shared

private let logger = Logger(subsystem: "io.uzume.audio", category: "PlayheadAnalysisClock")

// MARK: - LoopingFileReader

/// Bounded read-ahead over a decoded `AVAudioFile`, addressed by an absolute frame position that
/// wraps at end-of-file.
///
/// The clock ticks ~80 times a second and each tick needs a few hundred frames. Doing an
/// `AVAudioFile.read` per tick would put codec work on the clock's critical path, so a block of
/// `blockSeconds` is decoded at a time and every tick inside it is a memcpy. Not thread-safe:
/// `AVAudioFile` is not, and the clock touches this from one serial queue only.
final class LoopingFileReader {

    /// Total frames in the file. Positions are taken modulo this, so a caller can hold a
    /// monotonically-increasing cursor across loop boundaries and never think about the wrap.
    let frameCount: AVAudioFramePosition

    /// Channels the reader EMITS — 2 when the file has 2 or more, else 1. Matches
    /// `LocalFilePlaybackProvider.handleTapBuffer`'s layout exactly, so the downstream contract
    /// is unchanged.
    let channelCount: Int

    let sampleRate: Double

    private let file: AVAudioFile
    private let scratch: AVAudioPCMBuffer
    private let blockCapacity: Int

    /// Interleaved read-ahead block: frames `[blockStart, blockStart + blockFrames)` of the file.
    private var block: [Float]
    private var blockStart: AVAudioFramePosition = -1
    private var blockFrames = 0

    /// `nil` when the file's processing format is not the deinterleaved float32 layout
    /// `AVAudioFile` documents, or when it is empty — both leave nothing safe to read.
    init?(file: AVAudioFile, blockSeconds: Double = 1.0) {
        let format = file.processingFormat
        guard !format.isInterleaved,
              format.commonFormat == .pcmFormatFloat32,
              format.channelCount >= 1,
              format.sampleRate > 0,
              file.length > 0 else { return nil }

        let capacity = max(1, Int(format.sampleRate * blockSeconds))
        guard let scratch = AVAudioPCMBuffer(pcmFormat: format,
                                             frameCapacity: AVAudioFrameCount(capacity)) else {
            return nil
        }

        self.file = file
        self.scratch = scratch
        self.blockCapacity = capacity
        self.frameCount = file.length
        self.sampleRate = format.sampleRate
        self.channelCount = format.channelCount >= 2 ? 2 : 1
        self.block = [Float](repeating: 0, count: capacity * self.channelCount)
    }

    /// Copy `frames` interleaved frames starting at absolute position `start` into `dst`.
    ///
    /// `start` is taken modulo the file length, and a request that runs off the end continues from
    /// frame 0 — so the samples are contiguous with what the looping player is emitting, not
    /// truncated at the boundary. Returns the interleaved float count written.
    func read(from start: AVAudioFramePosition, frames: Int, into dst: inout [Float]) -> Int {
        guard frames > 0, frameCount > 0 else { return 0 }
        let wanted = min(frames, dst.count / channelCount)
        var written = 0
        var position = start
        while written < wanted {
            let wrapped = ((position % frameCount) + frameCount) % frameCount
            let untilEnd = Int(frameCount - wrapped)
            let take = min(wanted - written, untilEnd)
            let got = copy(fromFileFrame: wrapped, frames: take, into: &dst, atFrame: written)
            guard got > 0 else { break }
            written += got
            position += AVAudioFramePosition(got)
        }
        return written * channelCount
    }

    // MARK: - Private

    /// Copy from the read-ahead block, refilling it first when it does not cover `fileFrame`.
    /// Never crosses the end of the file — `read(from:frames:into:)` splits the request.
    private func copy(fromFileFrame fileFrame: AVAudioFramePosition,
                      frames: Int,
                      into dst: inout [Float],
                      atFrame dstFrame: Int) -> Int {
        if fileFrame < blockStart || fileFrame >= blockStart + AVAudioFramePosition(blockFrames) {
            refill(at: fileFrame)
        }
        let offset = Int(fileFrame - blockStart)
        guard blockFrames > 0, offset >= 0, offset < blockFrames else { return 0 }
        let take = min(frames, blockFrames - offset)
        guard take > 0 else { return 0 }
        let src = offset * channelCount
        let dstBase = dstFrame * channelCount
        for i in 0..<(take * channelCount) {
            dst[dstBase + i] = block[src + i]
        }
        return take
    }

    private func refill(at fileFrame: AVAudioFramePosition) {
        blockFrames = 0
        blockStart = fileFrame
        file.framePosition = fileFrame
        scratch.frameLength = 0
        do {
            try file.read(into: scratch, frameCount: AVAudioFrameCount(blockCapacity))
        } catch {
            logger.error("read failed at frame \(fileFrame): \(error.localizedDescription, privacy: .public)")
            return
        }
        let got = Int(scratch.frameLength)
        guard got > 0, let planes = scratch.floatChannelData else { return }
        if channelCount == 2 {
            let left = planes[0], right = planes[1]
            for i in 0..<got {
                block[i * 2] = left[i]
                block[i * 2 + 1] = right[i]
            }
        } else {
            let mono = planes[0]
            for i in 0..<got { block[i] = mono[i] }
        }
        blockFrames = got
    }
}

// MARK: - PlayheadAnalysisClock

/// Ticks at render rate and hands the analysis funnel the audio the playhead has just passed.
///
/// Threading: one serial queue, `.userInteractive`. Nothing here runs on the audio thread or the
/// render thread — the file read, the interleave and the callback all happen on the clock's own
/// queue, which is what makes a bounded read-ahead sufficient rather than mandatory-lock-free.
public final class PlayheadAnalysisClock: @unchecked Sendable {

    /// Ticks per second.
    ///
    /// **80, not 60, and the reason is the gate.** What BUG-087 measures is how many DISTINCT
    /// values a ~59.8 fps render loop observes, not how often the analyser runs — that distinction
    /// is the whole of why BUG087.3's slice-count test passed against a live 16.4 Hz. A 60 Hz clock
    /// against a 59.8 fps sampler is two near-equal rates beating against each other: a share of
    /// render frames would contain no tick at all and the observed rate would land below the 50 Hz
    /// floor. At 80 Hz the period is 12.5 ms against a 16.7 ms render frame, so every render frame
    /// contains at least one tick with 4.2 ms of jitter margin, and the observed rate becomes the
    /// render rate. The cost is ~80 MIR frames/s against the ~47/s this path already ran at after
    /// BUG087.3, and against the ~59/s the streaming path has always run at.
    public static let tickHz: Double = 80

    /// Longest audio span one tick may deliver. A tick that finds the playhead further ahead than
    /// this (the queue stalled, the process was suspended) delivers the newest `maxHopSeconds` and
    /// skips the rest rather than dumping a backlog into the FFT as one oversized frame.
    static let maxHopSeconds: Double = 0.25

    private let reader: LoopingFileReader
    private let position: () -> Double?
    private let deliver: (UnsafePointer<Float>, Int, Float, UInt32) -> Void
    private let queue = DispatchQueue(label: "io.uzume.localfile.analysisclock", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    // Clock-queue state. Touched only from `queue`.
    private var smoother = PlaybackClockSmoother()
    private var cursor: AVAudioFramePosition = -1
    private var scratch: [Float]

    /// Diagnostic sink — the session log records which clock actually drove the analysis, so a
    /// capture is never ambiguous about which arm produced it.
    public var onDiagnosticEvent: ((String) -> Void)?

    /// - Parameters:
    ///   - reader: read-ahead over the same decoded file the player is playing.
    ///   - position: UNWRAPPED playback position in seconds — monotone across loop boundaries.
    ///     `nil` while the player is not rendering (before `play()`, while paused); the clock
    ///     holds its position and delivers nothing for those ticks.
    ///   - deliver: the analysis funnel, same signature as the tap callback.
    init(reader: LoopingFileReader,
         position: @escaping () -> Double?,
         deliver: @escaping (UnsafePointer<Float>, Int, Float, UInt32) -> Void) {
        self.reader = reader
        self.position = position
        self.deliver = deliver
        let maxFrames = max(1, Int(reader.sampleRate * Self.maxHopSeconds))
        self.scratch = [Float](repeating: 0, count: maxFrames * reader.channelCount)
    }

    /// ⚠ Cancel WITHOUT the barrier `stop()` uses. `deinit` can be reached on any thread — including
    /// the clock queue, if a tick outlives its last external reference — and `queue.sync` from the
    /// queue itself would deadlock. The barrier belongs to `stop()`, which the provider's teardown
    /// always calls; this is the backstop for an instance dropped without one.
    deinit { timer?.cancel() }

    /// Begin ticking. Idempotent.
    public func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        let period = 1.0 / Self.tickHz
        source.schedule(deadline: .now() + period, repeating: period, leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
        let hz = Int(Self.tickHz)
        let rate = Int(reader.sampleRate)
        logger.info("[BUG087.4] analysis clock started: \(hz) Hz over \(rate) Hz file")
        onDiagnosticEvent?("ANALYSIS_CLOCK: playhead-driven, \(hz) Hz, file rate \(rate)")
    }

    /// Stop ticking, and **do not return until any tick already in flight has finished**.
    ///
    /// ⚠ **The barrier is the whole point, and its absence was a process-killing crash (BUG-130).**
    /// `DispatchSourceTimer.cancel()` prevents FUTURE handlers; it does not wait for one that is
    /// already running. The tick reads `AVAudioPlayerNode.lastRenderTime`, and AVFAudio asserts
    /// `_engine != nil` inside it — so a tick racing `teardownAVFoundation` reached a player whose
    /// engine had just been released and threw `com.apple.coreaudio.avfaudio`, an Objective-C
    /// exception no Swift `catch` can intercept. The process dies. Every track change and every
    /// session stop is a teardown, so this was live on the local-file path.
    ///
    /// `queue.sync {}` after `cancel()` is the barrier: the clock queue is serial, so by the time
    /// an empty block runs on it the in-flight handler has returned.
    ///
    /// This does NOT reintroduce BUG-021's ABBA. The clock queue never takes the provider's lock
    /// and never calls into AVFoundation teardown — it only reads the player and the file — so
    /// nothing it does can block on the thread calling `stop()`. The wait is bounded by one tick's
    /// work: a memcpy from the read-ahead block, or at worst one 1-second block decode.
    ///
    /// ⚠ Never call this FROM the clock queue — `queue.sync` onto a serial queue from itself
    /// deadlocks. Nothing does today: `stop()` is called from `teardownAVFoundation`, which runs on
    /// the caller's thread, never on the clock queue.
    public func stop() {
        guard let timer else { return }
        timer.cancel()
        self.timer = nil
        queue.sync { }
    }

    // MARK: - Private

    private func tick() {
        guard let raw = position() else { return }
        let smoothed = smoother.position(rawSeconds: raw, now: CACurrentMediaTime())
        let target = AVAudioFramePosition(smoothed * reader.sampleRate)

        // First tick establishes the cursor; there is no span to deliver yet.
        guard cursor >= 0 else { cursor = target; return }

        var advance = Int(target - cursor)
        guard advance > 0 else { return }
        let maxFrames = scratch.count / reader.channelCount
        advance = min(advance, maxFrames)
        // Read the span ENDING at the playhead, so a clamped hop drops the stale head rather than
        // the fresh tail — the same "newest frames win" rule `FFTProcessor` already applies.
        let start = target - AVAudioFramePosition(advance)
        cursor = target

        let count = reader.read(from: start, frames: advance, into: &scratch)
        guard count > 0 else { return }
        scratch.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            deliver(base, count, Float(reader.sampleRate), UInt32(reader.channelCount))
        }
    }
}

// MARK: - Wiring

@available(macOS 14.2, *)
extension PlayheadAnalysisClock {

    /// Build the playhead-driven analysis clock, or nil when BUG087.4's flag is off, the caller
    /// set no callback, or the file's layout is not one `LoopingFileReader` can address. Every nil
    /// leaves the tap driving the funnel exactly as it does today.
    ///
    /// The position closure returns the player's UNWRAPPED position: `sampleTime` counts frames
    /// rendered since `play()` and keeps counting across a `scheduleFile` loop re-arm, so it is
    /// monotone across the loop boundary and `PlaybackClockSmoother` never sees the wrap as a seek.
    /// `LoopingFileReader` takes the wrap instead, where it is a modulo.
    /// ⚠ Takes the URL, not the provider's `AVAudioFile`, and opens its OWN handle. `AVAudioFile`
    /// is not thread-safe, and the player is reading the provider's instance on the render thread
    /// for the whole of playback while this reader seeks it on the clock queue — sharing one handle
    /// is a data race on an Apple object, which is not something a passing test would reliably show.
    ///
    /// **Throws rather than returning nil since BUG087.5.** While the tap still forwarded, a clock
    /// that could not be built fell back to it; now there is nothing to fall back to, and analysing
    /// nothing would render a dead visualizer against audible music. Refusing to start surfaces
    /// through the app's existing local-file error path instead.
    ///
    /// `deliver` is nil only when a caller starts the provider without setting `onAudioSamples` —
    /// a source with no analysis consumer, which is legitimate (playback only), so that case
    /// produces a silent clock rather than an error.
    static func make(
        url: URL,
        player: AVAudioPlayerNode,
        deliver: ((UnsafePointer<Float>, Int, Float, UInt32) -> Void)?
    ) throws -> PlayheadAnalysisClock {
        let own = try AVAudioFile(forReading: url)
        guard let reader = LoopingFileReader(file: own) else {
            throw PlayheadAnalysisClockError.unsupportedFileLayout(
                format: String(describing: own.processingFormat), frames: own.length)
        }
        return PlayheadAnalysisClock(
            reader: reader,
            position: { [weak player] in
                guard let player,
                      let nodeTime = player.lastRenderTime,
                      let playerTime = player.playerTime(forNodeTime: nodeTime),
                      playerTime.isSampleTimeValid,
                      playerTime.sampleRate > 0 else { return nil }
                return Double(playerTime.sampleTime) / playerTime.sampleRate
            },
            deliver: deliver ?? { _, _, _, _ in }
        )
    }
}

// MARK: - PlayheadAnalysisClockError

/// The clock is the only analysis source on the local-file path (BUG087.5), so a file it cannot
/// address is a start failure rather than a downgrade.
public enum PlayheadAnalysisClockError: Error, CustomStringConvertible {
    case unsupportedFileLayout(format: String, frames: AVAudioFramePosition)

    public var description: String {
        switch self {
        case let .unsupportedFileLayout(format, frames):
            return "analysis clock cannot address this file (\(frames) frames, format \(format)) — "
                + "expected non-interleaved float32 from AVAudioFile.processingFormat"
        }
    }
}
