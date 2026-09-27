// LiveAdapter — Real-time plan adaptation during playback (Increment 4.5, D-035).
//
// Receives the pre-planned PlannedSession and a live structural prediction, and decides
// whether to reschedule the upcoming track transition.
//
// NRG.3 (D-259): the mid-track preset override that fired on live-vs-prepared MOOD divergence
// is removed with its cooldown state. The mood model is at chance on unseen songs (BUG-148),
// so it re-planned scenes on noise; scene choice reads the prepared energy curve instead.

import Foundation
import Presets
import Session
import Shared
import os.log

private let logger = Logging.orchestrator

// MARK: - AdaptationEvent

/// A logged event produced when `DefaultLiveAdapter.adapt` makes (or declines) an adaptation.
public struct AdaptationEvent: Sendable, Hashable, Codable {

    // MARK: Kind

    /// The outcome category of one `adapt` call.
    public enum Kind: String, Sendable, Hashable, Codable {
        /// A planned transition was rescheduled to align with a live structural boundary.
        case boundaryRescheduled
        /// No adaptation was warranted; plan unchanged.
        case noAdaptation
    }

    // MARK: Fields

    /// What outcome occurred.
    public let kind: Kind
    /// 0-based playlist position of the affected track.
    public let trackIndex: Int
    /// Human-readable explanation for logging and testing.
    public let message: String

    public init(kind: Kind, trackIndex: Int, message: String) {
        self.kind = kind
        self.trackIndex = trackIndex
        self.message = message
    }
}

// MARK: - LiveAdaptation

/// The result of a single `DefaultLiveAdapter.adapt` call.
///
public struct LiveAdaptation: Sendable {

    /// Revised outgoing transition for the current track (`scheduledAt` updated).
    /// Non-nil only when `events` contains `.boundaryRescheduled`.
    public let updatedTransition: PlannedTransition?

    /// Diagnostic events for logging and testing.
    public let events: [AdaptationEvent]

    public init(
        updatedTransition: PlannedTransition? = nil,
        events: [AdaptationEvent]
    ) {
        self.updatedTransition = updatedTransition
        self.events = events
    }
}

// MARK: - DefaultLiveAdapter

/// The live adapter (PUB.4: its single-conformer ceremony protocol
/// `LiveAdapting` was deleted — wire this concrete type directly). `adapt`
/// must not access mutable external state — all state arrives via arguments.
///
/// **Boundary rescheduling** fires when `liveBoundary.confidence ≥ 0.5` and the
/// live prediction differs from the planned transition time by more than 5 s.
///
/// The mood-driven preset override (D-035 / D-080) was removed at NRG.3 (D-259).
///
/// See D-035 for design rationale.
public final class DefaultLiveAdapter: @unchecked Sendable {
    // MARK: - Tuning constants

    /// Minimum `StructuralPrediction.confidence` required to consider rescheduling.
    public static let boundaryConfidenceThreshold: Float = 0.5

    /// Minimum deviation (seconds) between live and planned transition times before
    /// a reschedule is triggered.
    public static let boundaryRescheduleThreshold: TimeInterval = 5.0

    // MARK: - Init

    public init() {}

    // MARK: - LiveAdapting

    /// Reschedule the upcoming track transition when a confident live boundary disagrees with
    /// the plan by more than `boundaryRescheduleThreshold`; otherwise report no adaptation.
    public func adapt(
        plan: PlannedSession,
        currentTrackIndex: Int,
        liveBoundary: StructuralPrediction
    ) -> LiveAdaptation {
        guard currentTrackIndex < plan.tracks.count else {
            return LiveAdaptation(events: [AdaptationEvent(
                kind: .noAdaptation,
                trackIndex: currentTrackIndex,
                message: "Track index \(currentTrackIndex) out of range (plan has \(plan.tracks.count) tracks)."
            )])
        }

        if let reschedule = evaluateBoundaryReschedule(
            plan: plan,
            currentTrackIndex: currentTrackIndex,
            liveBoundary: liveBoundary
        ) {
            return reschedule
        }
        return LiveAdaptation(events: [AdaptationEvent(
            kind: .noAdaptation,
            trackIndex: currentTrackIndex,
            message: "No boundary reschedule warranted."
        )])
    }

    // MARK: - Boundary Rescheduling

    private func evaluateBoundaryReschedule(
        plan: PlannedSession,
        currentTrackIndex: Int,
        liveBoundary: StructuralPrediction
    ) -> LiveAdaptation? {
        guard liveBoundary.confidence >= Self.boundaryConfidenceThreshold else { return nil }

        // Outgoing transition is stored as the incomingTransition of the next track.
        let nextIndex = currentTrackIndex + 1
        guard nextIndex < plan.tracks.count,
              let plannedTransition = plan.tracks[nextIndex].incomingTransition else {
            return nil
        }

        // Convert capture-relative boundary time to session-relative.
        let trackStart = plan.tracks[currentTrackIndex].plannedStartTime
        let liveSessionBoundary = TimeInterval(liveBoundary.predictedNextBoundary) + trackStart

        let deviation = abs(liveSessionBoundary - plannedTransition.scheduledAt)
        guard deviation > Self.boundaryRescheduleThreshold else { return nil }

        let rescheduled = PlannedTransition(
            fromPreset: plannedTransition.fromPreset,
            toPreset: plannedTransition.toPreset,
            style: plannedTransition.style,
            duration: plannedTransition.duration,
            scheduledAt: liveSessionBoundary,
            reason: "Live boundary rescheduled: "
                + "\(String(format: "%.1f", plannedTransition.scheduledAt))s → "
                + "\(String(format: "%.1f", liveSessionBoundary))s "
                + "(Δ\(String(format: "%.1f", deviation))s, "
                + "confidence \(String(format: "%.2f", liveBoundary.confidence)))."
        )

        logger.info("""
            LiveAdapter: boundary rescheduled track \(currentTrackIndex): \
            \(String(format: "%.1f", plannedTransition.scheduledAt))s → \
            \(String(format: "%.1f", liveSessionBoundary))s
            """)

        return LiveAdaptation(
            updatedTransition: rescheduled,
            events: [AdaptationEvent(
                kind: .boundaryRescheduled,
                trackIndex: currentTrackIndex,
                message: rescheduled.reason
            )]
        )
    }
}
