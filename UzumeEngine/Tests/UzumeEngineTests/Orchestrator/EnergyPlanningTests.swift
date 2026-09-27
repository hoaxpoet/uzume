// EnergyPlanningTests — NRG.3/NRG.4 (D-259). The planner reads the song's energy curve for the stretch each
// scene will play over, so a quiet opening and a loud second half get different scenes — the point
// of measuring energy over time rather than one number per song (Dance Yrself Clean's hush → drop).

import Foundation
import Testing
@testable import Orchestrator
import Presets
@testable import Session
import Shared

@Suite("NRG.3/4 planner reads the energy curve per segment and changes scene on energy changes")
struct EnergyPlanningTests {

    @Test("a quiet half gets sparse scenes and a loud half gets dense ones, within one song")
    func quietThenLoudSongChangesScenesWithTheMusic() throws {
        let catalog = [
            makePreset(name: "SparseA", family: .reaction, visualDensity: 0.10),
            makePreset(name: "SparseB", family: .fractal, visualDensity: 0.15),
            makePreset(name: "DenseA", family: .geometric, visualDensity: 0.85),
            makePreset(name: "DenseB", family: .particles, visualDensity: 0.90),
            makePreset(name: "DenseC", family: .volumetric, visualDensity: 0.80),
        ]
        let quiet = steadyCurve(level: 2, seconds: 120), loud = steadyCurve(level: 9, seconds: 120)
        let curve = EnergyCurve(hopSeconds: 1,
                                loudnessDB: quiet.loudnessDB + loud.loudnessDB,
                                activity: quiet.activity + loud.activity)
        let track = TrackIdentity(title: "hush-then-drop", artist: "test", duration: 240)
        let plan = try DefaultSessionPlanner().plan(
            tracks: [(track, TrackProfile(bpm: 110, energyCurve: curve))], catalog: catalog, deviceTier: .tier2)

        let segments = try #require(plan.tracks.first?.segments)
        #expect(segments.count >= 2, "a 240 s song should span several scenes")
        // NRG.4: a scene change lands on the energy change itself, and no scene straddles it.
        #expect(segments.contains { abs($0.plannedStartTime - 120) < 0.5 }, "no scene starts at the 120 s drop")
        for segment in segments {
            let sparse = segment.preset.visualDensity < 0.5
            if segment.plannedStartTime < 119.5 {
                #expect(sparse, "\(segment.preset.name) at \(segment.plannedStartTime) s is in the quiet half")
                #expect(segment.plannedEndTime <= 120.5, "\(segment.preset.name) straddles the drop")
            } else {
                #expect(!sparse, "\(segment.preset.name) at \(segment.plannedStartTime) s is in the loud half")
            }
        }
    }

    @Test("energy changes: a step is found where it happens; a short dip is not a change, a breakdown is")
    func energyChangesFindSteps() {
        let quiet = steadyCurve(level: 2, seconds: 90), loud = steadyCurve(level: 9, seconds: 90)
        let step = EnergyCurve(hopSeconds: 1, loudnessDB: quiet.loudnessDB + loud.loudnessDB,
                               activity: quiet.activity + loud.activity)
        #expect(step.energyChanges() == [90])
        let dip = steadyCurve(level: 2, seconds: 15)
        let dipped = EnergyCurve(hopSeconds: 1, loudnessDB: loud.loudnessDB + dip.loudnessDB + loud.loudnessDB,
                                 activity: loud.activity + dip.activity + loud.activity)
        #expect(dipped.energyChanges().isEmpty, "a 15 s dip read as a section change")
        let breakdown = steadyCurve(level: 2, seconds: 40)
        let broken = EnergyCurve(hopSeconds: 1, loudnessDB: loud.loudnessDB + breakdown.loudnessDB + loud.loudnessDB,
                                 activity: loud.activity + breakdown.activity + loud.activity)
        #expect(broken.energyChanges() == [90, 130], "a 40 s breakdown is its own section")
    }

    @Test("with no curve, energy is neutral: the planner still plans, on tempo and stems")
    func noCurveIsNeutral() throws {
        let catalog = [makePreset(name: "Mid", family: .reaction, visualDensity: 0.5)]
        let plan = try DefaultSessionPlanner().plan(
            tracks: [(TrackIdentity(title: "unmeasured", artist: "test", duration: 120), TrackProfile(bpm: 110))],
            catalog: catalog, deviceTier: .tier2)
        #expect(plan.tracks.first?.segments.first?.scoreBreakdown.energy == 1, "density 0.5 meets the neutral 0.5 target")
    }
}

// MARK: - Fixtures

/// A curve reading `level` throughout, built from the library table's own quantiles.
private func steadyCurve(level: Int, seconds: Int) -> EnergyCurve {
    let scale = EnergyScale.library
    let matching = (0...100).filter {
        scale.level(loudnessDB: scale.loudnessQuantiles[$0], activity: scale.activityQuantiles[$0]) == level
    }
    let q = matching[matching.count / 2]
    return EnergyCurve(hopSeconds: 1,
                       loudnessDB: Array(repeating: scale.loudnessQuantiles[q], count: seconds),
                       activity: Array(repeating: scale.activityQuantiles[q], count: seconds))
}

private func makePreset(name: String, family: PresetCategory, visualDensity: Float) -> PresetDescriptor {
    let json = """
    {
        "name": "\(name)",
        "family": "\(family.rawValue)",
        "motion_intensity": 0.5,
        "visual_density": \(visualDensity),
        "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
        "transition_affordances": ["crossfade"],
        "certified": true
    }
    """
    // swiftlint:disable:next force_try
    return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}
