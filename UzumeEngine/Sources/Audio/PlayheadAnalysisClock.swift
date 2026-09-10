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
// Local-file playback ONLY, behind `UZUME_LF_ANALYSIS_CLOCK=1`. Streaming already runs at ~59 Hz
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

    /// BUG087.4 ships behind a flag with a one-increment A/B path: off, this type is never
    /// constructed and the tap drives the funnel exactly as it does today.
    public static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["UZUME_LF_ANALYSIS_CLOCK"] == "1"
    }

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

    /// Stop ticking. Idempotent, non-blocking, and safe to call from any thread — `cancel()` only
    /// enqueues, so this never waits on the clock queue the way a teardown that blocked would.
    public func stop() {
        timer?.cancel()
        timer = nil
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
    static func make(
        file: AVAudioFile,
        player: AVAudioPlayerNode,
        deliver: ((UnsafePointer<Float>, Int, Float, UInt32) -> Void)?
    ) -> PlayheadAnalysisClock? {
        guard PlayheadAnalysisClock.isEnabled, let deliver else { return nil }
        guard let reader = LoopingFileReader(file: file) else {
            logger.error("[BUG087.4] analysis clock unavailable for this file layout — tap drives")
            return nil
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
            deliver: deliver
        )
    }
}
