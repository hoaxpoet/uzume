// NearTieSamplingTests — BUG-133, the second and binding cause.
//
// BUG133.1 made fatigue per-preset, which was right and did not fix Matt's complaint. Measured with
// the production scorer over his own cached profiles, the whole eligible catalog spans 0.612 → 0.459
// on one track with the TOP TWELVE inside 0.05 of each other, so `max(by:)` was deciding on gaps of
// 0.003 and the same five or six presets opened everything. Fourteen certified presets were
// unreachable at any cooldown setting.
//
// The planner now samples uniformly among presets within `nearTieBandWidth` of the best, seeded so
// the result stays deterministic. These tests pin the three things that make that safe rather than
// merely different: the pool widens, a preset outside the band still never wins, and the same inputs
// still produce the same plan (PREP.2 extends live plans and requires it).

import Foundation
import Testing
@testable import Orchestrator
import Presets
import Session
import Shared

@Suite("Near-tie sampling (BUG-133)")
struct NearTieSamplingTests {

    private let planner = DefaultSessionPlanner()

    /// Presets that score within a whisker of each other, plus one that is clearly worse.
    /// `motionIntensity` is the only lever moved, so the ranking is shallow by construction —
    /// the same shape the real catalog turned out to have.
    private func catalog() -> [PresetDescriptor] {
        let specs: [(String, PresetCategory, Float)] = [
            ("Near0", .reaction, 0.50),
            ("Near1", .geometric, 0.52),
            ("Near2", .fractal, 0.48),
            ("Near3", .hypnotic, 0.54),
            // ~0.04 below the best: outside the scorer's own ±0.02 noise, inside the 0.05 band.
            // This is the preset the change exists for — measured, not guessed (see the scores in
            // the suite header).
            ("MidBand", .particles, 0.71),
            ("FarBelow", .sparkle, 1.0)
        ]
        return specs.map { name, family, motion in
            let json = """
            {
                "name": "\(name)",
                "family": "\(family.rawValue)",
                "motion_intensity": \(motion),
                "color_temperature_range": [0.3, 0.7],
                "fatigue_risk": "medium",
                "section_suitability": ["ambient","buildup","peak","bridge","comedown"],
                "stem_affinity": {},
                "complexity_cost": {"tier1": 2.0, "tier2": 1.5},
                "transition_affordances": ["crossfade"],
                "certified": true
            }
            """
            // swiftlint:disable:next force_try
            return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        }
    }

    private func track(_ n: Int) -> (TrackIdentity, TrackProfile) {
        (TrackIdentity(title: "T\(n)", artist: "A", duration: 180),
         TrackProfile(bpm: 120, mood: EmotionalState(valence: 0.2, arousal: 0.2)))
    }

    private func openersAcrossSeeds(_ seeds: [UInt64]) throws -> [String] {
        try seeds.map { seed in
            let session = try planner.plan(tracks: [track(0)], catalog: catalog(),
                                           deviceTier: .tier1, seed: seed,
                                           includeUncertifiedPresets: true)
            return try #require(session.tracks.first?.preset.id)
        }
    }



    @Test("A preset the ±0.02 noise cannot reach IS reached by the band")
    func bandReachesPastTheNoise() throws {
        let openers = try openersAcrossSeeds((1...24).map { UInt64($0) &* 0x9E37_79B9 })
        // Fixture scores: Near3 0.794, Near1 0.789, Near0 0.784, Near2 0.778, MidBand ~0.755,
        // FarBelow 0.686. The four Near* presets sit inside ±0.02, so the pre-existing seeded noise
        // already shuffled THOSE — asserting on them would pass with sampling removed, which is how
        // the first version of this test fooled itself. MidBand is the discriminator.
        #expect(openers.contains("MidBand"),
                """
                MidBand (~0.04 below the best) must be reachable — that gap is inside the 0.05 \
                near-tie band and outside the scorer's ±0.02 noise, so only sampling can reach it. \
                Got \(Set(openers).sorted()).
                """)
        #expect(Set(openers).count >= 3, "the pool must widen, not just shift; got \(Set(openers).sorted())")
    }

    @Test("A preset outside the band still never wins — this is a band, not a lottery")
    func farBelowNeverWins() throws {
        let openers = try openersAcrossSeeds((1...60).map { UInt64($0) &* 0x85EB_CA6B })
        #expect(!openers.contains("FarBelow"),
                """
                a preset far below the best must stay unpicked — that gap IS a preference, and a band \
                wide enough to admit it would replace the planner with a shuffle. Got \(Set(openers).sorted()).
                """)
    }

    @Test("Same seed, same plan — PREP.2 extends live plans and depends on it")
    func deterministic() throws {
        let seed: UInt64 = 0xC0FF_EE00_1234_5678
        let a = try planner.plan(tracks: [track(0), track(1), track(2)], catalog: catalog(),
                                 deviceTier: .tier1, seed: seed, includeUncertifiedPresets: true)
        let b = try planner.plan(tracks: [track(0), track(1), track(2)], catalog: catalog(),
                                 deviceTier: .tier1, seed: seed, includeUncertifiedPresets: true)
        #expect(a.tracks.map { $0.preset.id } == b.tracks.map { $0.preset.id })
    }

    @Test("Seed 0 stays a pure argmax, so the unseeded goldens still pin the scorer")
    func unseededIsArgmax() throws {
        let ids = try (0..<5).map { _ -> String in
            let session = try planner.plan(tracks: [track(0)], catalog: catalog(),
                                           deviceTier: .tier1, seed: 0,
                                           includeUncertifiedPresets: true)
            return try #require(session.tracks.first?.preset.id)
        }
        #expect(Set(ids).count == 1, "unseeded planning must be single-valued; got \(Set(ids))")
    }
}
