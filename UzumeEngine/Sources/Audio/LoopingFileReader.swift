// LoopingFileReader — bounded read-ahead over a decoded AVAudioFile, addressed by absolute frame.
//
// Split out of `PlayheadAnalysisClock.swift` at BUG130.1, which is the increment that pushed that
// file past the 400-line lint budget. Nothing moved but the type: it was always a separate type
// sharing a file with its only caller, and the clock's own history comment stays with the clock.

@preconcurrency import AVFoundation
import Foundation
import os.log

private let logger = Logger(subsystem: "io.uzume.audio", category: "LoopingFileReader")

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
