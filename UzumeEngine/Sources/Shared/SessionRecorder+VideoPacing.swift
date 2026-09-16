// SessionRecorder+VideoPacing.swift — which rendered frames reach the video writer, and when.
//
// Diagnostic mode (BUG-136): `shouldKeepVideoFrame` keeps every second frame of a 60 Hz loop with
// half a frame of tolerance, so jitter cannot turn a two-frame gap into three.
//
// Capture mode (BUG-137): every frame, and none lost silently. Under CPU load the ProRes writer
// input reports not-ready in bursts; capture used to drop there — 14 of 20 test runs under full
// load lost 13-38 of 70 frames. Now it waits for the writer (`captureAdaptorWhenReady`), bounds how
// much may wait (`admitVideoFrame` / `releaseVideoBacklog`), and logs every frame it still loses.
//
// Split from `SessionRecorder+Video.swift` to keep that file under `file_length`.

import AVFoundation
import CoreVideo
import Foundation

extension SessionRecorder {

    /// Capture: the adaptor once the writer can take a frame, waiting out a busy encoder instead of
    /// dropping — under CPU load the ProRes input reports not-ready for bursts of a few hundred
    /// milliseconds. Nil (counted and logged) only if it stays not-ready past the timeout. Queue.
    func captureAdaptorWhenReady(
        _ adaptor: AVAssetWriterInputPixelBufferAdaptor,
        _ input: AVAssetWriterInput
    ) -> AVAssetWriterInputPixelBufferAdaptor? {
        let ready = Self.waitUntil(timeout: Self.captureReadyTimeout, poll: Self.captureReadyPoll) {
            input.isReadyForMoreMediaData || self.videoWriter?.status != .writing
        }
        guard ready, input.isReadyForMoreMediaData else {
            videoNotReadyCount += 1
            recordCaptureDrop("writer not ready after \(Self.captureReadyTimeout) s")
            return nil
        }
        return adaptor
    }

    /// Ceiling on capture frames waiting for the encoder: about one second of 1080p60 BGRA
    /// (8.3 MB a frame), a quarter of that at 4K.
    static let defaultCaptureBacklogByteBudget = 512 * 1024 * 1024
    /// How long one capture frame waits for a not-ready writer before it is dropped (and logged).
    static let captureReadyTimeout: TimeInterval = 1.0
    static let captureReadyPoll: TimeInterval = 0.002

    /// Capture mode: the frame if the backlog has room, else nil — counted and logged, because a
    /// master must never lose a frame silently. Other modes pass the frame through. Render thread.
    func admitVideoFrame(_ frame: VideoFrame?) -> VideoFrame? {
        guard let frame, videoMode == .capture else { return frame }
        let bytes = Self.videoFrameBytes(frame)
        var pending = 0
        var dropped = 0
        let admitted = videoRenderLock.withLock { () -> Bool in
            let fits = Self.captureBacklogAdmits(
                pendingBytes: captureBacklogBytes, frameBytes: bytes, budget: captureBacklogByteBudget)
            if fits { captureBacklogBytes += bytes } else { captureDropCount += 1 }
            pending = captureBacklogBytes
            dropped = captureDropCount
            return fits
        }
        guard admitted else {
            log("capture frame dropped: encoder backlog full (\(pending / 1_048_576) MB waiting, "
                + "budget \(captureBacklogByteBudget / 1_048_576) MB; dropped \(dropped); BUG-137)")
            return nil
        }
        return frame
    }

    /// Returns an admitted frame's bytes to the backlog once the queue is done with it.
    func releaseVideoBacklog(_ frame: VideoFrame) {
        guard videoMode == .capture else { return }
        let bytes = Self.videoFrameBytes(frame)
        videoRenderLock.withLock { captureBacklogBytes -= bytes }
    }

    /// Counts and logs a capture frame lost after admission. Recorder queue; takes `videoRenderLock`.
    func recordCaptureDrop(_ reason: String) {
        let dropped = videoRenderLock.withLock { () -> Int in
            captureDropCount += 1
            return captureDropCount
        }
        writeLogLine("capture frame dropped: \(reason) (dropped \(dropped); BUG-137)")
    }

    static func videoFrameBytes(_ frame: VideoFrame) -> Int {
        CVPixelBufferGetBytesPerRow(frame.pixelBuffer) * CVPixelBufferGetHeight(frame.pixelBuffer)
    }

    /// Admit while nothing is waiting — so any single frame records, however large — or while the
    /// backlog stays within budget. Pure.
    static func captureBacklogAdmits(pendingBytes: Int, frameBytes: Int, budget: Int) -> Bool {
        pendingBytes == 0 || pendingBytes + frameBytes <= budget
    }

    /// Polls `isReady` until it returns true or `timeout` has been waited. Pure given `sleep`; the
    /// default sleeps the calling thread (the recorder's serial queue).
    static func waitUntil(
        timeout: TimeInterval,
        poll: TimeInterval,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        _ isReady: () -> Bool
    ) -> Bool {
        if isReady() { return true }
        var waited: TimeInterval = 0
        while waited < timeout {
            sleep(poll)
            waited += poll
            if isReady() { return true }
        }
        return false
    }

    // MARK: - Frame-keep decision (BUG-136)

    // Half a 60 Hz render frame: how early a frame may arrive and still count as due.
    // ponytail: assumes a 60 Hz render loop (MTKView default); on a 120 Hz loop the diagnostic
    // 30 fps target would need half of ITS frame passed in. Capture mode never consults it.
    static let videoKeepTolerance: CFAbsoluteTime = 0.5 / 60.0

    /// Whether a rendered frame at `time` is written, given the last written frame's time and
    /// the target video rate. The frame is due at `lastKept + 1/targetFPS` and is kept when it
    /// arrives no more than half a render frame before that. The old strict comparison had no
    /// tolerance, so at 60 Hz a two-frame gap (≈ 33.4 ms) jittered under 1/30 about half the
    /// time and became three frames — 23.4 fps from a "30 fps" recorder (BUG-136).
    static func shouldKeepVideoFrame(
        at time: CFAbsoluteTime,
        lastKept: CFAbsoluteTime?,
        targetFPS: Double
    ) -> Bool {
        guard let lastKept else { return true }
        return time >= lastKept + 1.0 / targetFPS - videoKeepTolerance
    }
}
