// SpotifyScanServices — the system edges of the Spotify playlist scan (SCAN.3/SCAN.4, D-260).
//
// Everything the scan view model touches outside itself sits behind a protocol
// here so its tests run on fakes: the live frame source (ScreenCaptureKit,
// Spotify's window ONLY), the screenshot reader, and Spotify's app lifecycle.
//
// Privacy contract (SECURITY_POSTURE §8): the stream's content filter is one
// Spotify window — never a display. Frames live in memory only for the time it
// takes to read them and are never written anywhere. Capture runs only while the
// scan panel is open. No request goes to any Spotify server; no Accessibility
// API, no synthetic input — the user scrolls.

import AppKit
import Combine
import CoreImage
import CoreMedia
import Foundation
import os
import ScreenCaptureKit
import Session

private let logger = Logger(subsystem: "io.uzume.mac", category: "SpotifyScan")

// MARK: - Errors

/// Why a live scan stopped on its own.
enum SpotifyScanError: Error, Equatable {
    /// Spotify quit while the scan was running.
    case spotifyClosed
    /// No visible Spotify window to read (minimized, on another Space, or gone).
    case windowUnavailable
}

// MARK: - PlaylistFrameSource

/// A live sequence of already-read frames of the playlist.
protocol PlaylistFrameSource: AnyObject, Sendable {
    /// Start reading. The stream ends when `stop()` is called, or throws a
    /// `SpotifyScanError` when the window goes away.
    func frames() -> AsyncThrowingStream<PlaylistScanFrame, Error>
    /// Stop immediately. Safe to call more than once.
    func stop()
}

// MARK: - SpotifyAppControlling

/// Spotify's app lifecycle, as the scan needs it.
@MainActor
protocol SpotifyAppControlling: AnyObject {
    /// Spotify is running.
    var isRunning: Bool { get }
    /// Emits whenever Spotify launches or quits.
    var runningChanges: AnyPublisher<Bool, Never> { get }
    /// Open Spotify (the user asked to).
    func open()
    /// Bring Spotify's window to the front.
    func bringToFront()
}

/// `NSWorkspace`-backed Spotify control.
@MainActor
final class SystemSpotifyApp: SpotifyAppControlling {
    nonisolated static let bundleID = "com.spotify.client"

    var isRunning: Bool { Self.runningApp != nil }

    var runningChanges: AnyPublisher<Bool, Never> {
        let center = NSWorkspace.shared.notificationCenter
        let isSpotify: (Notification) -> Bool = {
            let app = $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            return app?.bundleIdentifier == Self.bundleID
        }
        let launched = center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .filter(isSpotify)
            .map { _ in true }
        let quit = center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .filter(isSpotify)
            .map { _ in false }
        return launched
            .merge(with: quit)
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func open() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func bringToFront() {
        Self.runningApp?.activate()
    }

    private static var runningApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
    }

    /// Spotify's main window in screen coordinates (top-left origin), from the
    /// window list — bounds only, no pixels. nil when not on screen.
    static func mainWindowFrame() -> CGRect? {
        guard let pid = runningApp?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        return list
            .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
            .compactMap { $0[kCGWindowBounds as String] as? NSDictionary }
            .compactMap { CGRect(dictionaryRepresentation: $0) }
            .max { $0.width * $0.height < $1.width * $1.height }
    }
}

// MARK: - SpotifyWindowFrameSource

/// ScreenCaptureKit stream of Spotify's main window only, read frame by frame.
///
/// Reading (~0.3–0.4 s a frame, Release) runs on the stream's own handler queue,
/// so a frame arriving mid-read waits in the stream's small queue or is dropped —
/// the natural throttle. The stream asks for 4 frames a second; the reader sets
/// the real pace.
final class SpotifyWindowFrameSource: NSObject, PlaylistFrameSource, SCStreamOutput, SCStreamDelegate,
                                      @unchecked Sendable {

    private let lock = NSLock()
    private var stream: SCStream?
    private var continuation: AsyncThrowingStream<PlaylistScanFrame, Error>.Continuation?
    private let reader = PlaylistScreenReader()
    // SCStream requires a dispatch queue for sample delivery (no async alternative).
    private let queue = DispatchQueue(label: "io.uzume.scan.frames")

    func frames() -> AsyncThrowingStream<PlaylistScanFrame, Error> {
        AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
            continuation.onTermination = { [weak self] _ in self?.stop() }
            Task { [weak self] in
                do {
                    try await self?.startCapture()
                } catch {
                    logger.info("Spotify scan could not start: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: SpotifyScanError.windowUnavailable)
                }
            }
        }
    }

    func stop() {
        let (stream, continuation) = lock.withLock {
            defer { self.stream = nil; self.continuation = nil }
            return (self.stream, self.continuation)
        }
        continuation?.finish()
        stream?.stopCapture { _ in }
    }

    private func startCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == SystemSpotifyApp.bundleID && $0.windowLayer == 0
                && $0.frame.width > 300 && $0.frame.height > 300
        }
        let largest = windows.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let window = largest else {
            throw SpotifyScanError.windowUnavailable
        }
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 4)
        config.showsCursor = false
        config.capturesAudio = false
        config.queueDepth = 3
        let filter = SCContentFilter(desktopIndependentWindow: window)   // this window only — never a display
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        guard lock.withLock({ continuation != nil }) else { return }   // stopped before we started
        lock.withLock { self.stream = stream }
        try await stream.startCapture()
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, Self.isComplete(sampleBuffer),
              let pixels = sampleBuffer.imageBuffer,
              let image = Self.cgImage(pixels),
              let continuation = lock.withLock({ self.continuation }) else { return }
        // In memory only; `image` is released when this call returns.
        let start = DispatchTime.now().uptimeNanoseconds
        guard let frame = try? reader.read(image) else { return }
        let millis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
        let first = frame.rows.first?.number ?? 0
        let last = frame.rows.last?.number ?? 0
        logger.info("SCAN frame: \(Int(millis)) ms, \(frame.rows.count) rows (#\(first)–#\(last))")
        continuation.yield(frame)
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: SystemSpotifyApp.bundleID)
        let reason: SpotifyScanError = running.isEmpty ? .spotifyClosed : .windowUnavailable
        lock.withLock { continuation }?.finish(throwing: reason)
        lock.withLock { self.stream = nil; self.continuation = nil }
    }

    // MARK: Helpers

    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    private static func cgImage(_ pixels: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixels)
        return imageContext.createCGImage(image, from: image.extent)
    }
}

// MARK: - Screenshot reading

/// Reads dropped screenshots. Order doesn't change the result (rows merge by
/// their playlist number), but they are read in name order — capture order for
/// macOS's default screenshot names.
enum PlaylistScreenshotReader {

    /// Read every image among `urls`; non-images are skipped.
    static func read(_ urls: [URL]) async -> [PlaylistScanFrame] {
        await Task.detached(priority: .userInitiated) {
            urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap { url -> PlaylistScanFrame? in
                    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    else { return nil }
                    // A fresh reader per image: screenshots can be of differently placed windows.
                    return try? PlaylistScreenReader().read(image)
                }
        }.value
    }
}
