// LiveAdapterTests — unit tests for DefaultLiveAdapter (Increment 4.5).
//
// All sessions are built via DefaultSessionPlanner.plan() — never hand-constructed.
// Fixture builders at the bottom keep test bodies compact.
//
// Boundary rescheduling only: the mood-driven preset override was removed at NRG.3 (D-259 —
// the mood model is at chance on unseen songs, BUG-148).

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

// MARK: - Test Suite

@Suite("DefaultLiveAdapter")
struct LiveAdapterTests {

    private let adapter = DefaultLiveAdapter()

    // MARK: 1 — No reschedule when live boundary is within tolerance

    @Test("No reschedule when live deviation is 3 s (< 5 s threshold)")
    func noAdaptation_whenBoundaryWithinTolerance() throws {
        // 2-track plan; planned transition lands at session time ≈ 60 s.
        let plan = try twoTrackPlan(duration: 60)

        let liveBoundary = StructuralPrediction(
            sectionIndex: 0,
            sectionStartTime: 0,
            predictedNextBoundary: 57.0, // 3 s before planned → deviation < 5 s
            confidence: 0.8
        )
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0, liveBoundary: liveBoundary
        )

        #expect(result.updatedTransition == nil, "Deviation < 5 s must not trigger reschedule")
        #expect(result.events.contains { $0.kind == .noAdaptation })
    }

    // MARK: 2 — Reschedule when deviation ≥ 5 s

    @Test("Boundary rescheduled when live deviation is 7 s (≥ 5 s threshold)")
    func boundaryRescheduled_whenLiveDiffers5sOrMore() throws {
        let plan = try twoTrackPlan(duration: 60)

        let liveBoundary = StructuralPrediction(
            sectionIndex: 0,
            sectionStartTime: 0,
            predictedNextBoundary: 67.0, // 7 s after planned → deviation > 5 s
            confidence: 0.8
        )
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0, liveBoundary: liveBoundary
        )

        let rescheduled = try #require(result.updatedTransition, "Deviation ≥ 5 s must reschedule")
        // liveSessionBoundary = 67 + plannedStartTime(0) = 67 s
        #expect(abs(Float(rescheduled.scheduledAt) - 67.0) < 0.01,
                "Rescheduled time must equal the live session boundary")
        #expect(result.events.contains { $0.kind == .boundaryRescheduled })
    }

    // MARK: 3 — No reschedule when confidence < 0.5

    @Test("No reschedule when confidence is 0.4 even if deviation would exceed threshold")
    func boundaryRescheduled_onlyWhenConfidenceSufficient() throws {
        let plan = try twoTrackPlan(duration: 60)

        let lowConfidence = StructuralPrediction(
            sectionIndex: 0,
            sectionStartTime: 0,
            predictedNextBoundary: 67.0, // would trigger if confidence were ≥ 0.5
            confidence: 0.4             // below threshold
        )
        let result = adapter.adapt(
            plan: plan, currentTrackIndex: 0, liveBoundary: lowConfidence
        )

        #expect(result.updatedTransition == nil, "Low confidence must suppress reschedule")
    }

    // MARK: 4 — Each outcome emits its event kind

    @Test("No adaptation and boundary reschedule each emit their AdaptationEvent.Kind")
    func adaptationEvents_areLogged_forBothOutcomes() throws {
        let plan = try twoTrackPlan(duration: 60)

        let none = adapter.adapt(plan: plan, currentTrackIndex: 0, liveBoundary: noBoundarySignal())
        #expect(none.events.first?.kind == .noAdaptation)

        let bigBoundary = StructuralPrediction(
            sectionIndex: 0, sectionStartTime: 0,
            predictedNextBoundary: 70.0, confidence: 0.7   // planned at 60 s, live at 70 s
        )
        let rescheduled = adapter.adapt(plan: plan, currentTrackIndex: 0, liveBoundary: bigBoundary)
        #expect(rescheduled.events.first?.kind == .boundaryRescheduled)
    }
}

// MARK: - Session Builders

private func twoTrackPlan(duration: TimeInterval) throws -> PlannedSession {
    let tracks: [(TrackIdentity, TrackProfile)] = [
        (makeIdentity(title: "T0", duration: duration), TrackProfile()),
        (makeIdentity(title: "T1", duration: duration), TrackProfile()),
    ]
    return try DefaultSessionPlanner().plan(tracks: tracks, catalog: simpleCatalog(), deviceTier: .tier1)
}

/// A structural prediction with zero confidence — the boundary path is never triggered.
private func noBoundarySignal() -> StructuralPrediction {
    StructuralPrediction(sectionIndex: 0, sectionStartTime: 0,
                         predictedNextBoundary: 0, confidence: 0.0)
}

// MARK: - Catalog Builders

private func simpleCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "SimpleA", family: .reaction),
        makePreset(name: "SimpleB", family: .geometric),
    ]
}

// MARK: - Fixture Builders

private func makeIdentity(
    title: String = "TestTrack",
    duration: TimeInterval = 180
) -> TrackIdentity {
    TrackIdentity(title: title, artist: "TestArtist", duration: duration)
}

private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .geometric,
    motionIntensity: Float = 0.5,
    colorTempRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    visualDensity: Float = 0.5,
    complexityCost: ComplexityCost = ComplexityCost(tier1: 2.0, tier2: 1.5),
    transitionAffordances: [TransitionAffordance] = [.crossfade]
) -> PresetDescriptor {
    let affordJSON = transitionAffordances.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTempRange.x), \(colorTempRange.y)],
        "visual_density": \(visualDensity),
        "complexity_cost": {"tier1": \(complexityCost.tier1), "tier2": \(complexityCost.tier2)},
        "transition_affordances": [\(affordJSON)],
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}
