// GoldenSessionTests — curated playlists as regression fixtures (Increment 4.4, D-034).
//
// NRG.3 (2026-09-27, D-259): fixtures state ENERGY (a steady 1–10 curve), not mood — scene
// choice reads measured energy since BUG-148 showed the mood model is at chance. Each level was
// chosen to ask for the density the old arousal did (0.1 + 0.8·(level−1)/9 ≈ 0.5 + 0.4·arousal).
//
// Every test encodes what DefaultPresetScorer + DefaultTransitionPolicy +
// DefaultSessionPlanner *actually* produce for these inputs. Any future change
// to the scorer formula, transition policy, or a preset JSON sidecar that breaks
// a golden test is a regression — fix the test only by updating the expected
// values AND adding a scoring-trace comment that proves correctness.
//
// Catalog: the shipped sidecars, loaded directly (GOLDEN.1). Every plan here is
// UNSEEDED (`seed == 0` → pure argmax), so these goldens pin the scorer, not the
// near-tie sampling (BUG133.2) that every production plan runs with a random seed.
// Seeded variety is covered by the BUG133.2 tests, not here.
//
// No Sources/ files are modified. Tests only.

import Foundation
import Testing
@testable import Orchestrator
import Presets
@testable import Session
import Shared
import simd

// MARK: - Suite

@Suite("GoldenSessionFixtures")
struct GoldenSessionTests {

    private let planner = DefaultSessionPlanner()

    // MARK: — Session A: High-Energy Electronic (5 × 180 s, BPM=130, energy level 9)

    // Scoring trace — NRG.3 (2026-09-27), real roster. Energy level 9 → target density 0.811,
    // targetMotion 0.633; stemAffinity 0.000 / sect gated off for all. Track-0 ranking:
    //   Filigree          0.633 (energy 0.961, tempo 0.933)
    //   Mitosis           0.631 (energy 0.989, tempo 0.883)
    //   Cymatic Resonance 0.613 · Cytokinesis 0.604 · Ferrofluid Ocean 0.580 · Fractal Tree 0.580
    // Track-firsts rotate (Filigree, Ferrofluid Ocean, Mitosis, Cymatic Resonance, Filigree) as
    // each winner's fatigue window is still open at the next track boundary.

    @Test("Session A: 5 tracks, no errors")
    func sessionA_producesCorrectCount() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        #expect(session.tracks.count == 5)
        #expect(session.warnings.isEmpty)
    }

    @Test("Session A: first track has no incoming transition")
    func sessionA_firstTrack_hasNoIncomingTransition() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        #expect(session.tracks[0].incomingTransition == nil)
    }

    @Test("Session A: preset IDs match golden sequence")
    func sessionA_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let ids = session.tracks.map { $0.preset.id }
        // NRG.3 (2026-09-27): regenerated for energy (trace above). Production plans with a
        // random seed; this seed-0 argmax pins the scorer only.
        #expect(ids == [
            "Filigree", "Ferrofluid Ocean", "Mitosis", "Cymatic Resonance", "Filigree",
        ])
    }

    @Test("Session A: track-boundary transitions all present and well-formed")
    func sessionA_transitionStyles() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // V.7.6.2 multi-segment regeneration: track-level `.incomingTransition`
        // accessor surfaces segments[0].incomingTransition (the track-boundary one).
        // The outgoing preset feeding each new track is now whichever preset closed
        // out the previous track's segment list, so styles depend on intra-track
        // segment cascades rather than the V.7.6.1 single-segment "from VL" rule.
        // We assert presence and basic well-formedness only; per-style and per-
        // duration assertions belong in V.7.6.C calibration.
        let transitions = session.tracks.compactMap { $0.incomingTransition }
        #expect(transitions.count == 4)
        for tx in transitions {
            #expect(tx.duration >= 0)
            #expect(tx.scheduledAt >= 0)
        }
    }

    @Test("Session A: all transition triggers are structuralBoundary")
    func sessionA_allTransitionsAreStructuralBoundary() throws {
        let session = try planner.plan(
            tracks: makeSessionA(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // Planner uses a synthetic StructuralPrediction (confidence=1.0) at every
        // track boundary → policy fires .structuralBoundary → rationale starts with
        // "Structural boundary".
        for entry in session.tracks.dropFirst() {
            let t = try #require(entry.incomingTransition)
            #expect(t.reason.hasPrefix("Structural boundary"))
        }
    }

    // MARK: — Session B: Mellow Jazz (5 × 180 s, BPM=85, energy level 4)

    // Scoring trace — NRG.3 (2026-09-27), real roster. Energy level 4 → target density 0.367,
    // targetMotion 0.3125. Track-0 ranking: Gossamer 0.650 (energy 0.967, tempo 0.988) ·
    // Aurora Veil 0.643 · Witchlight 0.637 · Nimbus 0.630 · Skein 0.630 · Meniscus 0.610.
    // Gossamer's 60 s window has expired by each track boundary, so it takes every track-first
    // (unchanged from the mood-era golden).

    @Test("Session B: preset IDs match V.7.6.2 multi-segment golden sequence")
    func sessionB_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // NRG.3: unchanged — Gossamer also wins on energy (trace above).
        #expect(session.tracks.map { $0.preset.id } == [
            "Gossamer", "Gossamer", "Gossamer", "Gossamer", "Gossamer",
        ])
        #expect(session.tracks.map { $0.preset.family?.rawValue } == [
            "sparkle", "sparkle", "sparkle", "sparkle", "sparkle",
        ])
    }

    @Test("Session B: all transitions are crossfade (energy level 4 → 0.37 < 0.85 cut threshold QR.2)")
    func sessionB_allTransitionsAreCrossfade() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // energy = 0.1 + 0.8*(4−1)/9 = 0.367; duration = 2.0*0.633 + 0.5*0.367 ≈ 1.45 s
        for entry in session.tracks.dropFirst() {
            let t = try #require(entry.incomingTransition)
            #expect(t.style == .crossfade)
            #expect(abs(t.duration - 1.45) < 0.02)
        }
    }

    @Test("Session B: no high-motion preset wins a slow jazz session")
    func sessionB_highMotionPresetsNeverWin() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // Murmuration (motion=0.85) is far from targetMotion 0.3125 and never ranks.
        for entry in session.tracks {
            #expect(
                entry.preset.motionIntensity <= 0.8,
                "\(entry.preset.name) (motion=\(entry.preset.motionIntensity)) should not win jazz"
            )
        }
    }

    // MARK: — Session C: Genre-Diverse Mix (6 tracks, varied durations)

    // Scoring trace — NRG.3 (2026-09-27), real roster, track-first rankings:
    //   Track 0 (BPM=130, level 9): Filigree 0.633 (= Session A).
    //   Track 1 (BPM=80,  level 4): Gossamer 0.647 (energy 0.967, tempo 0.975).
    //   Track 2 (BPM=115, level 7): Ferrofluid Ocean 0.656 = Fractal Tree 0.656 (tie broken by
    //                               catalog order) · Glaze 0.649.
    //   Track 3 (BPM=125, level 9): Filigree (recovered by then).
    //   Track 4 (BPM=70,  level 3): Gossamer 0.591 · Witchlight 0.584.
    //   Track 5 (BPM=135, level 9): Cymatic Resonance (Filigree still inside its window).

    @Test("Session C: preset IDs match V.7.6.2 multi-segment genre-driven sequence")
    func sessionC_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // NRG.3: regenerated for energy (trace above).
        #expect(session.tracks.map { $0.preset.id } == [
            "Filigree", "Gossamer", "Ferrofluid Ocean", "Filigree", "Gossamer", "Cymatic Resonance",
        ])
    }

    @Test("Session C: genre diversity produces ≥3 distinct preset families")
    func sessionC_energyShiftProducesFamilyVariety() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let families = Set(session.tracks.map { $0.preset.family })
        #expect(families.count >= 3)
    }

    // MARK: — Session D: Lumen Mosaic eligibility (BUG-004 closure verification)

    // Scoring trace — NRG.3 (2026-09-27), real roster. Session D locks that a scene wins
    // where its identity fits (BUG-004 closure, 2026-05-12): Lumen Mosaic is low-motion and
    // medium-density (motion 0.25, density 0.65).
    //
    // Track profile: BPM=75, energy level 7, single 180 s track.
    //   target density = 0.1 + 0.8 * 6/9 = 0.633
    //   targetMotion   = 0.2 + 0.3 * (75-70)/40 = 0.2375
    //
    // Ranking: Lumen Mosaic 0.823 (energy 0.983, tempo 0.988) · Alfvén 0.770 · Nebula 0.750 ·
    // Ferrofluid Ocean 0.743 · Fractal Tree 0.743 · Nimbus 0.743.

    @Test("Session D: Lumen Mosaic wins track 0 segment 0 at an LM-favourable energy")
    func sessionD_lumenMosaicWinsFirstSegment() throws {
        let session = try planner.plan(
            tracks: makeSessionD(), catalog: makeRealCatalog(), deviceTier: .tier2)
        #expect(session.tracks.count == 1)
        // The first PlannedTrack's preset reflects the first segment.
        #expect(session.tracks[0].preset.id == "Lumen Mosaic")
        #expect(session.tracks[0].presetScore > 0)
    }

    // MARK: — Cross-session

    @Test("Catalog fixture is the full shipped roster (no silent partial load)")
    func catalog_isTheShippedRoster() {
        #expect(makeRealCatalog().count == PresetLoaderCompileFailureTest.expectedProductionPresetCount)
    }

    @Test("Determinism: identical inputs produce identical PlannedSession")
    func determinism_samePlanOnRepeatedCalls() throws {
        let tracks  = makeSessionA()
        let catalog = makeRealCatalog()
        let s1 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        let s2 = try planner.plan(tracks: tracks, catalog: catalog, deviceTier: .tier2)
        #expect(s1.tracks.map { $0.preset.id } == s2.tracks.map { $0.preset.id })
        #expect(s1.tracks.map { $0.plannedStartTime } == s2.tracks.map { $0.plannedStartTime })
        #expect(s1.tracks.map { $0.plannedEndTime } == s2.tracks.map { $0.plannedEndTime })
    }

    @Test("totalDuration equals sum of individual track durations (Session C varied lengths)")
    func totalDuration_matchesSumOfTrackDurations() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let summed = session.tracks
            .map { $0.plannedEndTime - $0.plannedStartTime }
            .reduce(0, +)
        #expect(abs(session.totalDuration - summed) < 0.001)
    }
}

// MARK: — Stem Balance Helper

private func makeStemBalance(vocals: Float, drums: Float, bass: Float, other: Float) -> StemFeatures {
    var s = StemFeatures()
    s.vocalsEnergy = vocals
    s.drumsEnergy  = drums
    s.bassEnergy   = bass
    s.otherEnergy  = other
    return s
}

// MARK: — Fixture Builders (private; no conflict with SessionPlannerTests helpers)

private func makeIdentity(title: String, duration: TimeInterval = 180) -> TrackIdentity {
    TrackIdentity(title: title, artist: "GoldenArtist", duration: duration)
}

/// A profile whose energy curve holds one 1–10 level for the whole track (NRG.3, D-259) — the
/// planner reads energy from the curve, so a steady curve is how a fixture states "this energy".
private func makeProfile(
    bpm: Float? = nil,
    energyLevel: Int,
    seconds: Int = 180,
    stemBalance: StemFeatures = .zero
) -> TrackProfile {
    TrackProfile(bpm: bpm, stemEnergyBalance: stemBalance, energyCurve: steadyCurve(level: energyLevel, seconds: seconds))
}

/// A curve that reads `level` throughout: the library quantile whose loudness and activity both
/// land in that level, repeated.
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

// MARK: — Catalog Fixture

/// The shipped scene roster, decoded from the sidecars in `Sources/Presets/Shaders/`
/// exactly as `PresetLoader` decodes them, in the loader's filename order (the
/// planner breaks score ties by catalog position). The app passes every loaded
/// scene — diagnostics and uncertified included — and the scorer's exclusion gate
/// drops them, so this fixture does the same.
///
/// GOLDEN.1 (2026-09-24): replaces a hand-mirrored copy of the sidecars that had
/// drifted to a May-2026 subset of ~10 scenes (it still carried Arachne, removed at
/// D-246). A copy cannot go stale if there is no copy; `PresetLoaderCompileFailureTest`
/// owns the roster count.
private func makeRealCatalog() -> [PresetDescriptor] {
    guard let shaders = PresetLoader.bundledShadersURL,
          let files = try? FileManager.default.contentsOfDirectory(
              at: shaders, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
        return []
    }
    return files
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PresetDescriptor.self, from: $0) }
        }
}

// MARK: — Session Fixtures

private func makeSessionA() -> [(TrackIdentity, TrackProfile)] {
    let stems = makeStemBalance(vocals: 0.30, drums: 0.40, bass: 0.40, other: 0.20)
    return (0..<5).map { i in
        (makeIdentity(title: "Elec-\(i)", duration: 180),
         makeProfile(bpm: 130, energyLevel: 9, stemBalance: stems))
    }
}

private func makeSessionB() -> [(TrackIdentity, TrackProfile)] {
    let stems = makeStemBalance(vocals: 0.30, drums: 0.05, bass: 0.40, other: 0.35)
    return (0..<5).map { i in
        (makeIdentity(title: "Jazz-\(i)", duration: 180),
         makeProfile(bpm: 85, energyLevel: 4, stemBalance: stems))
    }
}

private typealias TrackSpec = (
    title: String, dur: TimeInterval,
    bpm: Float, energy: Int,
    vocals: Float, drums: Float, bass: Float, other: Float
)

private func makeSessionC() -> [(TrackIdentity, TrackProfile)] {
    let specs: [TrackSpec] = [
        ("Elec-0",  240, 130, 9, 0.30, 0.40, 0.40, 0.20),
        ("Jazz-1",  200,  80, 4, 0.35, 0.05, 0.40, 0.30),
        ("Rock-2",  210, 115, 7, 0.25, 0.35, 0.30, 0.25),
        ("Elec-3",  230, 125, 9, 0.25, 0.45, 0.45, 0.15),
        ("Jazz-4",  180,  70, 3, 0.45, 0.05, 0.35, 0.30),
        ("Elec-5",  220, 135, 9, 0.20, 0.45, 0.45, 0.20),
    ]
    return specs.map { p in
        let stems = makeStemBalance(vocals: p.vocals, drums: p.drums, bass: p.bass, other: p.other)
        let profile = makeProfile(bpm: p.bpm, energyLevel: p.energy, seconds: Int(p.dur), stemBalance: stems)
        return (makeIdentity(title: p.title, duration: p.dur), profile)
    }
}

// MARK: — Session D Fixture (BUG-004 closure — LM-favourable energy profile)

/// Single 180 s ambient-ish track. BPM=75, energy level 7 → moderate density target (0.633),
/// low motion target (0.2375) — aligned to Lumen Mosaic's identity (motion 0.25, density 0.65).
private func makeSessionD() -> [(TrackIdentity, TrackProfile)] {
    [(makeIdentity(title: "AmbientLM-0", duration: 180),
      makeProfile(bpm: 75, energyLevel: 7))]
}
