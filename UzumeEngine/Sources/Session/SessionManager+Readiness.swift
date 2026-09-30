// SessionManager+Readiness — Progressive readiness computation.
// Extracted from SessionManager.swift to keep that file under the 400-line
// SwiftLint gate (BUG-006.1 added wiring instrumentation that pushed it over).

import Foundation

extension SessionManager {

    // MARK: - Progressive Readiness Computation

    // swiftlint:disable cyclomatic_complexity
    /// Compute the progressive readiness level from the current track statuses.
    ///
    /// Rules (D-056):
    /// - `.partial` tracks NEVER count toward the consecutive prefix (PUB.6,
    ///   ultra-review). D-056 intended them to qualify when their cached
    ///   `TrackProfile` carried BPM + genre, but no code path has ever stored a
    ///   cache entry for a `.partial` track (stems fail → nothing is stored),
    ///   so the qualification was unreachable dead code. Making the D-056 rule
    ///   real would mean storing a metadata-only entry on the analysisError
    ///   path — a readiness-semantics change to take up deliberately, not a
    ///   side effect of a doc fix.
    /// - The prefix counts `.ready` tracks from position 1 and SKIPS terminal non-ready ones
    ///   (`.failed`, `.partial`); only a track still in flight ends it (BR.7 / audit C2). Before,
    ///   one failed track among the first three (≈1 Spotify-scan session in 5) hid Start now
    ///   until every track was terminal — minutes, with only Cancel.
    /// - `fullyPrepared` requires every track to be in a terminal state
    ///   (`.ready`, `.partial`, or `.failed`) with at least one usable track.
    /// - `reactiveFallback` when all terminal tracks are `.failed` (nothing to plan).
    public static func computeReadiness(
        statuses: [TrackIdentity: TrackPreparationStatus],
        trackList: [TrackIdentity],
        cache: StemCache
    ) -> ProgressiveReadinessLevel {
        guard !trackList.isEmpty else { return .reactiveFallback }

        let threshold = defaultProgressiveReadinessThreshold
        let total = trackList.count

        var prefixCount = 0
        var prefixBroken = false
        var readyCount = 0       // .ready or .partial
        var allTerminal = true

        for track in trackList {
            let status = statuses[track] ?? .queued

            let isTerminal: Bool
            switch status {
            case .ready, .partial, .failed: isTerminal = true
            default:                        isTerminal = false
            }
            if !isTerminal { allTerminal = false }

            let isReady: Bool
            switch status {
            case .ready, .partial: isReady = true
            default:               isReady = false
            }
            if isReady { readyCount += 1 }

            // Prefix: `.ready` tracks from position 1, skipping terminal non-ready ones
            // (BR.7 / C2). Only `.ready` counts (PUB.6); an in-flight track ends the run.
            if !prefixBroken {
                switch status {
                case .ready:            prefixCount += 1
                case .failed, .partial: break
                default:                prefixBroken = true
                }
            }
        }

        if allTerminal && readyCount == 0 { return .reactiveFallback }
        if allTerminal { return .fullyPrepared }
        if prefixCount < threshold { return .preparing }

        let readyPercent = Double(readyCount) / Double(total)
        return readyPercent >= 0.5 ? .partiallyPlanned : .readyForFirstTracks
    }
    // swiftlint:enable cyclomatic_complexity
}
