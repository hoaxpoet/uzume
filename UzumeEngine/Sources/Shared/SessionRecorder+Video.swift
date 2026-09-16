import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Metal
import os.log

private let videoLogger = Logger(subsystem: "io.uzume", category: "SessionRecorder")

// MARK: - VideoRecordingMode

/// What the session recorder writes as video (BUG-050: off unless asked for).
public enum VideoRecordingMode: Sendable, Equatable {
    /// No video. The default.
    case off
    /// `UZUME_RECORD_VIDEO=1` — H.264 `.mp4` at ≈ 30 fps, 4 Mbps: small files for diagnosis.
    case diagnostic
    /// `UZUME_RECORD_VIDEO=capture` — ProRes 422 `.mov`, every rendered frame up to 60 fps:
    /// masters for footage (REC.1).
    case capture

    /// Parses the `UZUME_RECORD_VIDEO` value; anything unrecognised is `.off`.
    public init(environmentValue: String?) {
        switch environmentValue {
        case "1": self = .diagnostic
        case "capture": self = .capture
        default: self = .off
        }
    }

    /// Target written-frame rate for `shouldKeepVideoFrame`.
    var targetFPS: Double { self == .capture ? 60 : 30 }
    var fileExtension: String { self == .capture ? "mov" : "mp4" }
    var fileType: AVFileType { self == .capture ? .mov : .mp4 }
    var logDescription: String {
        switch self {
        case .off: return "off"
        case .diagnostic: return "mode=diagnostic codec=H.264 container=mp4 target_fps=30"
        case .capture: return "mode=capture codec=ProRes422 container=mov target_fps=60 (every rendered frame)"
        }
    }
}

// MARK: - VideoFrame

/// One rendered frame's video buffer: an IOSurface-backed `CVPixelBuffer` and a Metal texture
/// aliasing the same memory. The render loop blits the drawable into `texture`; the recorder
/// appends `pixelBuffer` once the command buffer completes. Each frame owns its buffer, so a
/// later frame can never overwrite the pixels under an earlier frame's timestamp (REC.1).
public struct VideoFrame: @unchecked Sendable {
    /// Blit destination — same pixel format and size as the drawable it was made for.
    public let texture: MTLTexture
    let pixelBuffer: CVPixelBuffer
    /// Holds the texture↔buffer binding alive until the append.
    let metalTexture: CVMetalTexture
}

extension SessionRecorder {

    // MARK: - Render-thread frame allocation

    /// A buffer for this render frame to blit the drawable into, or nil when video is off,
    /// the frame is not due (`shouldKeepVideoFrame`), or the format is unsupported. Call once
    /// per rendered frame from the render loop, and pass the result to `recordFrame` from the
    /// same command buffer's completion handler.
    public func makeVideoFrame(
        device: MTLDevice,
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat
    ) -> VideoFrame? {
        guard videoMode != .off, width > 0, height > 0 else { return nil }
        return videoRenderLock.withLock {
            // The encoder takes 32BGRA; the blit needs the drawable's exact format.
            guard pixelFormat == .bgra8Unorm || pixelFormat == .bgra8Unorm_srgb else {
                if !videoFormatUnsupportedLogged {
                    videoFormatUnsupportedLogged = true
                    log("video disabled: drawable pixel format \(pixelFormat.rawValue) is not BGRA8")
                }
                return nil
            }
            let now = CFAbsoluteTimeGetCurrent()
            let targetFPS = videoMode.targetFPS
            guard Self.shouldKeepVideoFrame(at: now, lastKept: lastVideoFrameTime, targetFPS: targetFPS) else {
                return nil
            }
            guard let pool = videoPixelBufferPool(device: device, width: width, height: height),
                  let cache = videoTextureCache else { return nil }
            var maybeBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
            var maybeCVTex: CVMetalTexture?
            if let buffer = maybeBuffer {
                CVMetalTextureCacheCreateTextureFromImage(
                    nil, cache, buffer, nil, pixelFormat, width, height, 0, &maybeCVTex)
            }
            guard status == kCVReturnSuccess, let buffer = maybeBuffer,
                  let cvTex = maybeCVTex, let texture = CVMetalTextureGetTexture(cvTex) else {
                videoPoolFailCount += 1
                if videoPoolFailCount % 120 == 1 {
                    log("video pixel-buffer create failed (CVReturn \(status), "
                        + "count \(videoPoolFailCount); BUG-039 instrumentation)")
                }
                return nil
            }
            lastVideoFrameTime = now
            return VideoFrame(texture: texture, pixelBuffer: buffer, metalTexture: cvTex)
        }
    }

    /// The pool for `width`×`height`, rebuilt on a size change. `videoRenderLock` held.
    private func videoPixelBufferPool(device: MTLDevice, width: Int, height: Int) -> CVPixelBufferPool? {
        if let pool = videoPool, videoPoolDims?.width == width, videoPoolDims?.height == height { return pool }
        if videoTextureCache == nil {
            CVMetalTextureCacheCreate(nil, nil, device, nil, &videoTextureCache)
        }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        videoPool = pool
        videoPoolDims = pool == nil ? nil : (width, height)
        if pool == nil {
            videoPoolFailCount += 1
            if videoPoolFailCount % 120 == 1 {
                log("video pixel-buffer pool unavailable "
                    + "(count \(videoPoolFailCount); BUG-039 instrumentation)")
            }
        }
        return pool
    }

    // MARK: - Video encoding

    func appendVideoFrame(_ pixelBuffer: CVPixelBuffer, wallclock: CFAbsoluteTime) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard initializeVideoWriterIfNeeded(width: width, height: height) else { return }

        let lockedW = writerLockedDims?.width ?? 0
        let lockedH = writerLockedDims?.height ?? 0
        if lockedW != width || lockedH != height {
            guard handleDimensionMismatch(
                width: width,
                height: height,
                lockedW: lockedW,
                lockedH: lockedH
            ) else { return }
        }

        // BUG-039 instrumentation: video output has stalled silently a few seconds into some
        // sessions (2026-06-09T22-35-09Z froze at 120 frames / 5.0 s; 17-14-25Z at 15 s) with NO
        // log lines — every early-out below was silent and the `append` result was ignored. Each
        // path now logs (throttled), and a writer that left `.writing` is detected once, logged
        // loudly with its error, and left alone WITHOUT deleting the partial file (the BUG-022
        // fragmented MP4 keeps everything up to the last 5 s fragment playable).
        guard let adaptor = healthyVideoAdaptor() else { return }

        if videoStartTime == nil {
            let startTime = CMTime(value: CMTimeValue(wallclock * 1_000_000), timescale: 1_000_000)
            videoStartTime = startTime
            videoWriter?.startSession(atSourceTime: startTime)
        }
        let pts = CMTime(value: CMTimeValue(wallclock * 1_000_000), timescale: 1_000_000)
        if adaptor.append(pixelBuffer, withPresentationTime: pts) {
            // BUG-039 invariant (CLEAN.3.6): the "actually-writing" signal, asserted at finish().
            videoFramesAppended += 1
            lastVideoAppendFrameIndex = frameIndex
        } else {
            videoAppendFailCount += 1
            let err = videoWriter?.error.map { String(describing: $0) } ?? "nil"
            let statusRaw = videoWriter?.status.rawValue ?? -1
            if videoAppendFailCount % 30 == 1 {
                writeLogLine("video append FAILED at pts \(String(format: "%.3f", wallclock)) "
                    + "(status=\(statusRaw), error=\(err), "
                    + "count \(videoAppendFailCount); BUG-039 instrumentation)")
            }
        }
    }

    /// The adaptor to append to, or nil with a (throttled / one-shot) log naming WHY the frame
    /// was dropped — the BUG-039 silent stall paths made loud. A writer that left `.writing` is
    /// reported once and the partial file retained (never deleted).
    private func healthyVideoAdaptor() -> AVAssetWriterInputPixelBufferAdaptor? {
        if let writer = videoWriter, writer.status != .writing {
            let err = writer.error.map { String(describing: $0) } ?? "nil"
            // BUG-039 recovery: the writer died (intermittent encoder-session
            // failure; death certificate from 2026-06-10T17-50-56Z was
            // AVFoundation -11800 / undocumented OSStatus -16341). The dead
            // file is playable up to its last 5 s fragment (BUG-022) — retain
            // it, roll to the next segment file, and let the lazy init build
            // a fresh writer on the next frame. Bounded so a failure loop
            // can't churn forever.
            if videoWriterRestartCount < Self.maxVideoWriterRestarts {
                videoWriterRestartCount += 1
                videoSegmentIndex += 1
                writeLogLine("video writer DIED (status=\(writer.status.rawValue), error=\(err)) "
                    + "— partial retained; restarting into \(currentVideoURL.lastPathComponent) "
                    + "(restart \(videoWriterRestartCount)/\(Self.maxVideoWriterRestarts); BUG-039 recovery)")
                tearDownVideoWriter()
                videoStartTime = nil
                videoFailureLogged = false
                return nil   // next appendVideoFrame lazily re-initializes
            }
            if !videoFailureLogged {
                videoFailureLogged = true
                writeLogLine("video writer stopped consuming (status=\(writer.status.rawValue), "
                    + "error=\(err)) — restart budget exhausted, video output disabled, "
                    + "partials retained (BUG-039)")
            }
            return nil
        }
        guard let adaptor = pixelAdaptor, let videoInput = videoInput else { return nil }
        guard videoInput.isReadyForMoreMediaData else {
            videoNotReadyCount += 1
            if videoNotReadyCount % 120 == 1 {
                writeLogLine("video input not ready — frame dropped "
                    + "(count \(videoNotReadyCount); BUG-039 instrumentation)")
            }
            return nil
        }
        return adaptor
    }

    private func initializeVideoWriterIfNeeded(width: Int, height: Int) -> Bool {
        guard videoWriter == nil else { return true }
        if let last = lastObservedDims, last.width == width, last.height == height {
            sameDimsStreak += 1
        } else {
            lastObservedDims = (width, height)
            sameDimsStreak = 1
        }
        guard sameDimsStreak >= videoSizeStableThreshold else { return false }
        guard setupVideoWriter(width: width, height: height) else { return false }
        writerLockedDims = (width, height)
        writeLogLine("video writer locked to \(width)x\(height) after \(sameDimsStreak) stable frames")
        return true
    }

    private func handleDimensionMismatch(
        width: Int, height: Int, lockedW: Int, lockedH: Int
    ) -> Bool {
        skippedFrameCount += 1
        if let meta = mismatchedDims, meta.width == width, meta.height == height {
            mismatchedDimsStreak += 1
        } else {
            mismatchedDims = (width, height)
            mismatchedDimsStreak = 1
        }
        if mismatchedDimsStreak >= writerRelockThreshold {
            writeLogLine("video writer relocking: drawable stabilised at \(width)x\(height),"
                + " was locked at \(lockedW)x\(lockedH) (skipped \(skippedFrameCount) frames)")
            tearDownVideoWriter()
            if setupVideoWriter(width: width, height: height) {
                writerLockedDims = (width, height)
                writeLogLine("video writer relocked to \(width)x\(height)")
                skippedFrameCount = 0
                mismatchedDims = nil
                mismatchedDimsStreak = 0
                return true
            }
            writeLogLine("video writer relock FAILED — video output disabled")
            return false
        }
        if skippedFrameCount % 30 == 1 {
            writeLogLine("video frame skipped: drawable \(width)x\(height)"
                + " != writer \(lockedW)x\(lockedH) (skip count: \(skippedFrameCount))")
        }
        return false
    }

    func tearDownVideoWriter() {
        videoInput?.markAsFinished()
        if let writer = videoWriter, writer.status == .writing { writer.cancelWriting() }
        videoWriter = nil
        videoInput = nil
        pixelAdaptor = nil
        videoStartTime = nil
        try? FileManager.default.removeItem(at: currentVideoURL)
    }

    private func setupVideoWriter(width: Int, height: Int) -> Bool {
        do {
            guard materializeIfNeeded() else { return false }
            let writer = try AVAssetWriter(outputURL: currentVideoURL, fileType: videoMode.fileType)
            // BUG-022 — write a fragmented MP4 so the file remains playable
            // even if the process exits without calling `finishWriting`
            // (force-quit, crash, signal kill). Default AVAssetWriter only
            // writes the `moov` index when `finishWriting` runs, so any
            // abnormal termination produces an `mdat`-only file that
            // ffprobe / ffmpeg / QuickTime cannot open. With a 5 s fragment
            // interval the writer flushes a `moof` (movie fragment) every
            // 5 s; up to the last fragment boundary is always recoverable.
            // Clean Cmd+Q still hits `finishWriting` via the willTerminate
            // observer and produces a full final moov as before.
            writer.movieFragmentInterval = CMTime(seconds: 5, preferredTimescale: 1)
            var settings: [String: Any] = [
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
            if videoMode == .capture {
                // REC.1: ProRes 422, not HQ — visually lossless for masters at ~2/3 the size.
                settings[AVVideoCodecKey] = AVVideoCodecType.proRes422
            } else {
                settings[AVVideoCodecKey] = AVVideoCodecType.h264
                settings[AVVideoCompressionPropertiesKey] = [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
                ]
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input,
                sourcePixelBufferAttributes: nil
            )
            guard writer.canAdd(input) else { return false }
            writer.add(input)
            guard writer.startWriting() else {
                videoLogger.error("AVAssetWriter.startWriting failed: \(writer.error?.localizedDescription ?? "nil")")
                return false
            }
            self.videoWriter = writer
            self.videoInput = input
            self.pixelAdaptor = adaptor
            return true
        } catch {
            videoLogger.error("AVAssetWriter init failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Frame-keep decision (BUG-136)

    // Half a 60 Hz render frame: how early a frame may arrive and still count as due.
    // ponytail: assumes a 60 Hz render loop (MTKView default); a 120 Hz loop would need half of
    // ITS frame, passed in, or capture at target 60 would keep ~half the 120 Hz frames.
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

    // MARK: - BUG-039 invariant (CLEAN.3.6)

    /// At `finish()` (on the queue): flag a silent video stop loudly and return the
    /// video-outcome fragment for the session-end summary line. The recorder keeps
    /// "running" (CSV/log advance) even when the writer stops, so this is the single
    /// place the running-vs-actually-writing invariant is asserted on the artifacts.
    func finalizeVideoInvariant() -> String {
        if Self.isSilentVideoStop(
            videoLocked: writerLockedDims != nil,
            framesAppended: videoFramesAppended,
            restarts: videoWriterRestartCount,
            disabled: videoFailureLogged,
            framesSinceLastAppend: frameIndex - lastVideoAppendFrameIndex
        ) {
            writeLogLine("BUG-039 invariant VIOLATED: video locked but appends stopped "
                + "\(frameIndex - lastVideoAppendFrameIndex) frames before session end "
                + "(\(videoFramesAppended) appended) with no writer death/restart and "
                + "video not disabled — silent stop")
        }
        return "video \(videoFramesAppended) appended / \(videoSegmentIndex) segment(s) / "
            + "\(videoWriterRestartCount) restart(s) / disabled=\(videoFailureLogged)"
    }

    /// BUG-039 invariant predicate: true when the writer locked and appended frames, then
    /// stopped appending well before session end (`framesSinceLastAppend` over
    /// `videoSilentStopFrameThreshold`) with NO logged cause — no writer death/restart and
    /// video not disabled. Every *explained* stop is excluded. Pure → unit-testable without
    /// a Metal device / AVAssetWriter.
    static func isSilentVideoStop(
        videoLocked: Bool,
        framesAppended: Int,
        restarts: Int,
        disabled: Bool,
        framesSinceLastAppend: Int
    ) -> Bool {
        videoLocked
            && framesAppended > 0
            && restarts == 0
            && !disabled
            && framesSinceLastAppend > videoSilentStopFrameThreshold
    }
}
