// TrackChangeResetRouter — sends a song change's resets to the owners of their state (BR.3, audit G1).

import Foundation

// MARK: - TrackChangeResetRouter

/// The streaming Now Playing poller calls the track-change handler on a Swift concurrency
/// pool thread. Resetting renderer or analysis state inline there raced the render loop
/// (main) and the analysis queue with no lock on either side (audit G1). Every reset goes
/// to the queue that owns its state instead.
public enum TrackChangeResetRouter {

    /// Run `analysis` on `analysisQueue` (MIR, mood) and `main` on the main actor (preset,
    /// geometry, identity, renderer clocks). Safe to call from any thread; returns at once.
    public static func route(
        analysisQueue: DispatchQueue,
        analysis: @escaping @Sendable () -> Void,
        main: @escaping @MainActor @Sendable () -> Void
    ) {
        analysisQueue.async(execute: analysis)
        Task { @MainActor in main() }
    }
}
