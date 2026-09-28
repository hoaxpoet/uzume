// ReactiveOrchestratorTests — unit tests for DefaultReactiveOrchestrator (Increment 4.6).
//
// Scoring with nothing measured (NRG.3: no mood, no energy curve, no BPM, no stems, no section):
//   raw = (0.30*energy + 0.20*tempoMotion + 0.25*stemAffinity) / 0.75   (section weight gated off)
//   energy      = 1 - |visualDensity - 0.5|     (unmeasured energy → neutral target 0.5)
//   tempoMotion = 1 - |motionIntensity - 0.5|   (nil BPM → neutral target 0.5)
//   stemAffinity is equal for every preset here, so a gap = 0.4*Δenergy + 0.267*ΔtempoMotion.

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared
import simd

// MARK: - Test Suite

@Suite("DefaultReactiveOrchestrator")
struct ReactiveOrchestratorTests {

    private let orchestrator = DefaultReactiveOrchestrator()

    // MARK: 1 — Listening state always holds

    @Test("Returns hold with nil suggestion during 0–15 s listening window")
    func listening_state_always_holds() {
        let decision = orchestrator.evaluate(
            liveBoundary: strongBoundary(),
            elapsedSessionTime: 10.0,
            currentPreset: nil,
            catalog: smallGapCatalog(),
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil, "Must hold during listening window")
        #expect(decision.accumulationState == .listening)
        #expect(decision.scheduleTransitionAt == nil)
    }

    // MARK: 2 — Confidence ramps correctly

    @Test("Confidence ramps from 0 at 0 s to 1.0 at 30 s")
    func confidence_ramps_correctly() {
        let eps: Float = 0.001

        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 0) - 0.0) < eps,
                "0 s → 0.0")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 7.5) - 0.15) < eps,
                "7.5 s → 0.15")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 15.0) - 0.30) < eps,
                "15 s → 0.30")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 22.5) - 0.65) < eps,
                "22.5 s → 0.65")
        #expect(abs(DefaultReactiveOrchestrator.computeConfidence(elapsed: 30.0) - 1.0) < eps,
                "30 s → 1.0")
    }

    // MARK: 3 — Ramping state suggests the better-scoring preset

    @Test("Suggests better-matching preset during ramping state when score gap > 0.20")
    func ramping_suggests_better_scoring_preset() throws {
        // largeGapCatalog: gap 0.33 > 0.20 (see the catalog builders).
        let catalog = largeGapCatalog()
        let currentDesc = catalog[0]  // CurrentPreset

        let decision = orchestrator.evaluate(
            liveBoundary: noBoundarySignal(),
            elapsedSessionTime: 20.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        let suggested = try #require(decision.suggestedPreset, "Gap > 0.20 must trigger switch")
        #expect(suggested.name == "AltPreset", "Better preset must be selected")
        #expect(decision.accumulationState == .ramping)
    }

    // MARK: 4 — No switch when score gap is too small

    @Test("Holds current preset when gap is 0.02 (< 0.20) and no boundary signal")
    func no_switch_when_score_gap_too_small() {
        // smallGapCatalog: gap 0.02 < 0.20, boundary confidence 0.0 < 0.5 → hold.
        let catalog = smallGapCatalog()
        let currentDesc = catalog[0]  // CurrentPreset

        let decision = orchestrator.evaluate(
            liveBoundary: noBoundarySignal(),
            elapsedSessionTime: 60.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil, "Gap < 0.20 and no boundary — must hold")
        #expect(decision.accumulationState == .full)
    }

    // MARK: 5 — Boundary alone does not fire when gap < minBoundaryScoreGap (QR.2/D-080)

    @Test("Holds when boundary fires but gap is only 0.02 (< minBoundaryScoreGap 0.05)")
    func boundary_requires_minimum_score_gap() {
        // QR.2/D-080: boundary-only switches require scoreGap > minBoundaryScoreGap (0.05).
        // smallGapCatalog gap = 0.02 < 0.05 → boundary gate fails → hold.
        let catalog = smallGapCatalog()
        let currentDesc = catalog[0]  // CurrentPreset

        let decision = orchestrator.evaluate(
            liveBoundary: strongBoundary(predictedNextBoundary: 10.0),
            elapsedSessionTime: 60.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil,
                "Gap 0.02 < minBoundaryScoreGap 0.05: boundary must not trigger switch")
    }

    // MARK: 6 — Boundary schedules transition at correct session time

    @Test("scheduleTransitionAt equals elapsedSessionTime + predictedNextBoundary")
    func boundary_schedules_transition_at_correct_time() {
        // mediumGapCatalog: gap 0.08 > minBoundaryScoreGap (0.05) but < 0.20 (score gate).
        // elapsedSessionTime = 45.0, predictedNextBoundary = 3.5, confidence = 0.8 ≥ 0.5
        // → boundary gate fires; scheduleTransitionAt = 3.5 + 45.0 = 48.5
        let catalog = mediumGapCatalog()
        let currentDesc = catalog[0]

        let decision = orchestrator.evaluate(
            liveBoundary: strongBoundary(predictedNextBoundary: 3.5),
            elapsedSessionTime: 45.0,
            currentPreset: currentDesc,
            catalog: catalog,
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset != nil, "Boundary must trigger a switch")
        #expect(decision.scheduleTransitionAt != nil)
        let scheduledAt = Float(decision.scheduleTransitionAt!)
        #expect(abs(scheduledAt - 48.5) < 0.1,
                "scheduleTransitionAt must equal elapsedSessionTime + predictedNextBoundary")
    }

    // MARK: 7 — nil current preset always suggests past listening

    @Test("Suggests top preset when currentPreset is nil and past listening window")
    func nil_current_preset_always_suggests_past_listening() {
        // No current preset → skip score comparison entirely; always suggest top-ranked.
        // Score gap gate does not apply — there is nothing to compare against.
        let decision = orchestrator.evaluate(
            liveBoundary: noBoundarySignal(),
            elapsedSessionTime: 20.0,
            currentPreset: nil,
            catalog: smallGapCatalog(),
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset != nil,
                "Must suggest a preset when no current preset is set")
        #expect(decision.accumulationState == .ramping)
    }

    // MARK: 8 — Empty catalog returns hold

    @Test("Returns hold with nil suggestion when catalog is empty")
    func empty_catalog_returns_hold() {
        let decision = orchestrator.evaluate(
            liveBoundary: strongBoundary(),
            elapsedSessionTime: 60.0,
            currentPreset: nil,
            catalog: [],
            deviceTier: .tier1
        )

        #expect(decision.suggestedPreset == nil, "Empty catalog must return hold")
        #expect(decision.scheduleTransitionAt == nil)
    }
}

// MARK: - Signal Helpers

/// Structural prediction with zero confidence — boundary gate never fires.
private func noBoundarySignal() -> StructuralPrediction {
    StructuralPrediction(
        sectionIndex: 0, sectionStartTime: 0,
        predictedNextBoundary: 0, confidence: 0.0
    )
}

/// Structural prediction with confidence 0.8 (≥ 0.5 threshold).
private func strongBoundary(predictedNextBoundary: Float = 10.0) -> StructuralPrediction {
    StructuralPrediction(
        sectionIndex: 0, sectionStartTime: 0,
        predictedNextBoundary: predictedNextBoundary, confidence: 0.8
    )
}

// MARK: - Catalog Builders
//
// AltPreset sits on both neutral targets (density 0.5, motion 0.5) and scores 1.0 on each; the
// gap to CurrentPreset comes from how far CurrentPreset sits off them.

/// Large-gap catalog (test 3): Current density 0.0 + motion 0.0 → gap = 0.4*0.5 + 0.267*0.5 = 0.33 > 0.20.
private func largeGapCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "CurrentPreset", family: .reaction, motionIntensity: 0.0, visualDensity: 0.0),
        makePreset(name: "AltPreset", family: .geometric, motionIntensity: 0.5, visualDensity: 0.5),
    ]
}

/// Medium-gap catalog (test 6): Current density 0.30 → gap = 0.4*0.2 = 0.08 — above
/// minBoundaryScoreGap (0.05), below minScoreGapForSwitch (0.20): only the boundary gate fires.
private func mediumGapCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "CurrentPreset", family: .reaction, visualDensity: 0.30),
        makePreset(name: "AltPreset", family: .geometric, visualDensity: 0.5),
    ]
}

/// Small-gap catalog (tests 4, 5, 7): Current density 0.45 → gap = 0.4*0.05 = 0.02 — below both gates.
private func smallGapCatalog() -> [PresetDescriptor] {
    [
        makePreset(name: "CurrentPreset", family: .reaction, visualDensity: 0.45),
        makePreset(name: "AltPreset", family: .geometric, visualDensity: 0.5),
    ]
}

// MARK: - Fixture Builder

private func makePreset(
    name: String = "TestPreset",
    family: PresetCategory = .geometric,
    motionIntensity: Float = 0.5,
    colorTempRange: SIMD2<Float> = SIMD2(0.3, 0.7),
    visualDensity: Float = 0.5
) -> PresetDescriptor {
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": \(motionIntensity),
        "color_temperature_range": [\(colorTempRange.x), \(colorTempRange.y)],
        "visual_density": \(visualDensity),
        "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
        "transition_affordances": ["crossfade"],
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}
