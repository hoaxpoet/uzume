// SessionPlanner — Greedy forward-walk playlist planner (Increment 4.3, D-032).
//
// Composes DefaultPresetScorer (4.1) and DefaultTransitionPolicy (4.2) to
// produce a fully pre-planned PlannedSession before playback begins.
//
// Algorithm: walk the playlist in order; for each track build a scoring context
// reflecting accumulated history and pick the best eligible preset. Never
// backtracks (O(N × catalog), deterministic). Global optimization over mood arcs
// is a future enhancement (D-032).
//
// Determinism rule: no Date.now(), no random, no environment reads inside plan().

import Foundation
import Shared
import Presets
import Session
import os.log

private let logger = Logging.session

// MARK: - SessionPlanningError

/// Errors thrown by session planning.
public enum SessionPlanningError: Error, Sendable, Equatable {
    /// The track list was empty.
    case emptyPlaylist
    /// The preset catalog was empty.
    case emptyCatalog
    /// Precompilation of a specific preset failed after planning completed.
    case precompileFailed(presetID: String, underlying: String)
}

// MARK: - DefaultSessionPlanner

/// The session planner (PUB.4: its single-conformer ceremony protocol
/// `SessionPlanning` was deleted — wire this concrete type directly).
/// Deterministic: the same `(tracks, catalog, deviceTier,
/// includeUncertifiedPresets)` always produces byte-identical output.
///
/// Selects presets via `DefaultPresetScorer`, schedules transitions via
/// `DefaultTransitionPolicy`. See D-032 for the full design rationale.
///
/// **Fallback ladder (D-018, D-032):**
/// 1. Highest-scoring non-excluded preset in the catalog.
/// 2. All excluded: cheapest non-current preset — `.noEligiblePresets` warning.
/// 3. No alternative: cheapest preset regardless of identity — `.budgetExceeded` too.
///
/// Plans are always producible given a non-empty catalog.
public struct DefaultSessionPlanner: Sendable {

    // MARK: - Dependencies

    let scorer: DefaultPresetScorer
    let transitionPolicy: any TransitionDeciding
    private let precompile: (@Sendable (PresetDescriptor) async throws -> Void)?

    /// Fallback track duration when `TrackIdentity.duration` is nil (seconds).
    private static let defaultTrackDuration: TimeInterval = 180

    // MARK: - Init

    public init(
        scorer: DefaultPresetScorer = DefaultPresetScorer(),
        transitionPolicy: any TransitionDeciding = DefaultTransitionPolicy(),
        precompile: (@Sendable (PresetDescriptor) async throws -> Void)? = nil
    ) {
        self.scorer = scorer
        self.transitionPolicy = transitionPolicy
        self.precompile = precompile
    }

    // MARK: - SessionPlanning

    public func plan(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        includeUncertifiedPresets: Bool = false
    ) throws -> PlannedSession {
        try plan(
            tracks: tracks,
            catalog: catalog,
            deviceTier: deviceTier,
            seed: 0,
            includeUncertifiedPresets: includeUncertifiedPresets
        )
    }

    /// Seeded variant for "Regenerate Plan" (D-047).
    ///
    /// When `seed` is zero, output is byte-identical to the zero-seed run (D-034 preserved).
    /// When nonzero, a deterministic ±0.02 perturbation is added to each preset score before
    /// selection — enough to break ties without changing the ranking meaningfully on non-equal
    /// scores. Two calls with the same nonzero seed produce identical output.
    public func plan(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier,
        seed: UInt64,
        includeUncertifiedPresets: Bool = false
    ) throws -> PlannedSession {
        guard !tracks.isEmpty else { throw SessionPlanningError.emptyPlaylist }
        guard !catalog.isEmpty else { throw SessionPlanningError.emptyCatalog }

        var sessionClock: TimeInterval = 0
        var history: [PresetHistoryEntry] = []
        var currentPreset: PresetDescriptor?
        var planned: [PlannedTrack] = []
        var warnings: [PlanningWarning] = []

        for (index, (identity, profile)) in tracks.enumerated() {
            let trackStart = sessionClock
            let trackEnd = sessionClock + (identity.duration ?? Self.defaultTrackDuration)
            let priorTrackLastPreset = currentPreset

            let (segments, lastPreset) = planSegments(
                trackStart: trackStart,
                trackEnd: trackEnd,
                identity: identity,
                profile: profile,
                catalog: catalog,
                deviceTier: deviceTier,
                includeUncertifiedPresets: includeUncertifiedPresets,
                seed: seed,
                trackIndex: index,
                history: &history,
                currentPreset: &currentPreset,
                warnings: &warnings
            )

            // Family-repeat warning relative to the *previous track's last preset*.
            // Diagnostic presets (family == nil) never trigger the warning.
            if let firstSeg = segments.first,
               let prior = priorTrackLastPreset,
               let priorFamily = prior.family,
               let segFamily = firstSeg.preset.family,
               priorFamily == segFamily {
                warnings.append(
                    familyRepeatWarning(index: index, title: identity.title, chosen: firstSeg.preset)
                )
            }

            planned.append(PlannedTrack(
                track: identity,
                trackProfile: profile,
                segments: segments,
                plannedStartTime: trackStart,
                plannedEndTime: trackEnd
            ))
            currentPreset = lastPreset
            sessionClock = trackEnd
        }

        return PlannedSession(
            deviceTier: deviceTier,
            tracks: planned,
            totalDuration: sessionClock,
            warnings: warnings
        )
    }

    // MARK: - planAsync

    /// Builds the plan then awaits precompilation of every distinct preset in the result.
    ///
    /// Precompilation failures are surfaced as `.precompileFailed` after planning
    /// completes — the plan itself is NOT unwound (D-018, D-032).
    public func planAsync(
        tracks: [(TrackIdentity, TrackProfile)],
        catalog: [PresetDescriptor],
        deviceTier: DeviceTier
    ) async throws -> PlannedSession {
        let session = try plan(tracks: tracks, catalog: catalog, deviceTier: deviceTier)
        guard let precompile = self.precompile else { return session }

        var seen = Set<String>()
        let distinctPresets = session.tracks.compactMap { entry -> PresetDescriptor? in
            guard seen.insert(entry.preset.id).inserted else { return nil }
            return entry.preset
        }
        for preset in distinctPresets {
            do {
                try await precompile(preset)
            } catch {
                throw SessionPlanningError.precompileFailed(
                    presetID: preset.id,
                    underlying: error.localizedDescription
                )
            }
        }
        return session
    }

    // MARK: - Transition Construction

    /// Builds a `PlannedTransition` using a synthetic `StructuralPrediction` placing the
    /// boundary at the current session clock (confidence 1.0), so `DefaultTransitionPolicy`
    /// fires `.structuralBoundary` at every track change (D-032).
    func buildTransition(
        from fromPreset: PresetDescriptor,
        to toPreset: PresetDescriptor,
        profile: TrackProfile,
        at sessionClock: TimeInterval,
        lastEntry: PresetHistoryEntry?
    ) -> PlannedTransition {
        let energy = max(0, min(1, 0.5 + 0.4 * profile.mood.arousal))
        let clock = Float(sessionClock)
        let elapsed = lastEntry.map { $0.endTime - $0.startTime } ?? 0
        let ctx = TransitionContext(
            currentPreset: fromPreset,
            elapsedPresetTime: elapsed,
            prediction: StructuralPrediction(
                sectionIndex: 0,
                sectionStartTime: clock,
                predictedNextBoundary: clock,
                confidence: 1.0
            ),
            energy: energy,
            captureTime: clock
        )
        if let decision = transitionPolicy.evaluate(context: ctx) {
            return PlannedTransition(
                fromPreset: fromPreset,
                toPreset: toPreset,
                style: decision.style,
                duration: decision.duration,
                scheduledAt: TimeInterval(decision.scheduledAt),
                reason: decision.rationale
            )
        }
        return PlannedTransition(
            fromPreset: fromPreset,
            toPreset: toPreset,
            style: .crossfade,
            duration: 1.0,
            scheduledAt: sessionClock,
            reason: "Policy returned nil at track change; using default 1 s crossfade."
        )
    }

    // MARK: - Warning Helpers

    private func familyRepeatWarning(
        index: Int,
        title: String,
        chosen: PresetDescriptor
    ) -> PlanningWarning {
        PlanningWarning(
            kind: .forcedFamilyRepeat,
            trackIndex: index,
            message: "\(title): '\(chosen.name)' shares family '\(chosen.family?.rawValue ?? "(none)")' with previous."
        )
    }
}

// MARK: - Sendable conformance check (compile-time)

private func _assertSendable(_: some Sendable) {}
private func _checkDefaultSessionPlannerSendable() { _assertSendable(DefaultSessionPlanner()) }
