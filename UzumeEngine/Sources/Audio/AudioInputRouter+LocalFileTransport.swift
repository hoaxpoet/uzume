// AudioInputRouter+LocalFileTransport — the local-file transport the playback chrome drives:
// pause / resume (LF.5.fix D-LF5-3) and seek (LFSEEK.1). No-ops outside `.localFilePlayback`.

import Foundation

// MARK: - Local-file transport

@available(macOS 14.2, *)
extension AudioInputRouter {

    /// Pause LF playback in place (engine + tap stay alive; player retains
    /// position). No-op for non-LF modes. LF.5.fix D-LF5-3.
    public func pauseLocalFilePlayback() {
        localFilePlaybackProvider?.pause()
    }

    /// Resume LF playback from the paused position. No-op for non-LF modes
    /// or when the player isn't paused.
    public func resumeLocalFilePlayback() {
        localFilePlaybackProvider?.resume()
    }

    /// LFSEEK.1 — jump LF playback to `seconds` into the current file. No-op for non-LF modes.
    public func seekLocalFilePlayback(to seconds: TimeInterval) throws {
        try localFilePlaybackProvider?.seek(to: seconds)
    }

    /// `true` when LF playback is paused (engine alive, player not playing).
    /// `false` in every other state (stopped / actively playing / non-LF mode).
    public var isLocalFilePlaybackPaused: Bool {
        localFilePlaybackProvider?.isPaused ?? false
    }
}
