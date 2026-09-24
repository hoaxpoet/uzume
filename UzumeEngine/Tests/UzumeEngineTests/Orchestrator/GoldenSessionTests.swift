// GoldenSessionTests — three curated playlists as regression fixtures (Increment 4.4, D-034).
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
import Session
import Shared
import simd

// MARK: - Suite

@Suite("GoldenSessionFixtures")
struct GoldenSessionTests {

    private let planner = DefaultSessionPlanner()

    // MARK: — Session A: High-Energy Electronic (5 × 180 s, BPM=130, val=0.7, arous=0.8)

    // Scoring trace — GOLDEN.1 (2026-09-24), real 30-scene roster (25 eligible: 4
    // diagnostic + uncertified Waveform are hard-excluded). targetTemp=0.78,
    // targetDensity=0.82, targetMotion=0.633. makeStemBalance sets energy fields only
    // (dev=0), so stemAffinity is 0.000 for every scene and sect is 1.000 for every
    // scene — mood + tempo decide. Track-0 ranking:
    //   Cymatic Resonance 0.588 (mood 0.825, tempo 0.967)
    //   Mitosis           0.586 (mood 0.875, tempo 0.883)
    //   Cytokinesis       0.574 · Dragon Bloom 0.569 · Glaze 0.564 · Fractal Tree 0.549
    // Segments per track: CR (0–52 s) → Mitosis (52–125 s) → Dragon Bloom (125–180 s).
    // Cytokinesis loses the third slot to the 0.2× family-repeat against Mitosis
    // (both `particles`); CR is still inside its 120 s window. By each 180 s track
    // boundary CR has recovered, so argmax restarts the same cycle every track.

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
        // GOLDEN.1 (2026-09-24): regenerated against the real roster. The BETA.0 expectation
        // `[VL, Membrane ×4]` was a property of the stale 10-scene fixture (one `reaction`
        // scene, no competition) — Membrane does not appear at all on the real roster.
        //
        // ⚠ Five identical track-firsts is NOT the BUG-133 monopoly back: each track runs
        // three distinct scenes (see trace above), and it is the seed-0 argmax restarting the
        // same cycle once CR's window expires — the track-granularity repeat BUG133.1 already
        // recorded as a window-tuning question for Matt. Production never plans at seed 0;
        // measured over seeds 1…24 this session draws 7–11 distinct scenes across its
        // 15–16 segments (2–5 distinct track-firsts).
        #expect(ids == [
            "Cymatic Resonance", "Cymatic Resonance", "Cymatic Resonance", "Cymatic Resonance",
            "Cymatic Resonance",
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

    // MARK: — Session B: Mellow Jazz (5 × 180 s, BPM=85, val=0.3, arous=−0.3)

    // Scoring trace — GOLDEN.1 (2026-09-24), real roster. targetTemp=0.62,
    // targetDensity=0.38, targetMotion=0.3125; stemAffinity 0.000 / sect 1.000 for all.
    // Track-0 ranking: Gossamer 0.635 (mood 0.930, tempo 0.988) · Skein 0.615 ·
    // Nacre 0.602 · Alfvén 0.599 · Aurora Veil 0.599 · Nimbus 0.595.
    // Segments per track: Gossamer (0–101.5 s, its maxDuration) → Skein. Gossamer's
    // 60 s window (fatigue_risk low) has expired by the next track boundary, so it
    // takes every track-first. Same seed-0 argmax property as Session A; seeds 1…24
    // give 5–8 distinct scenes over the 10–12 segments.

    @Test("Session B: preset IDs match V.7.6.2 multi-segment golden sequence")
    func sessionB_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // GOLDEN.1: unchanged by the re-mirror — Gossamer was already the winner.
        #expect(session.tracks.map { $0.preset.id } == [
            "Gossamer", "Gossamer", "Gossamer", "Gossamer", "Gossamer",
        ])
        #expect(session.tracks.map { $0.preset.family?.rawValue } == [
            "sparkle", "sparkle", "sparkle", "sparkle", "sparkle",
        ])
    }

    @Test("Session B: all transitions are crossfade (energy=0.38 < 0.85 cut threshold QR.2)")
    func sessionB_allTransitionsAreCrossfade() throws {
        let session = try planner.plan(
            tracks: makeSessionB(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // energy = 0.5 + 0.4*(−0.3) = 0.38; duration = 2.0*0.62 + 0.5*0.38 ≈ 1.43 s
        for entry in session.tracks.dropFirst() {
            let t = try #require(entry.incomingTransition)
            #expect(t.style == .crossfade)
            #expect(abs(t.duration - 1.43) < 0.05)
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

    // Scoring trace — GOLDEN.1 (2026-09-24), real roster, track-firsts:
    //   Track 0 (BPM=130, val=0.70, arous=0.80):  Cymatic Resonance 0.588 (= Session A).
    //   Track 1 (BPM=80,  val=0.20, arous=-0.40): Gossamer 0.632 (mood 0.930, tempo 0.975).
    //   Track 2 (BPM=115, val=0.50, arous=0.40):  Glaze 0.630 (mood 0.920, tempo 0.983).
    //   Track 3 (BPM=125, val=0.60, arous=0.75):  Mitosis 0.589 (CR, used 551–603 s, is
    //                                              still inside its 120 s window).
    //   Track 4 (BPM=70,  val=0.30, arous=-0.50): Gossamer 0.596 (recovered, 60 s window).
    //   Track 5 (BPM=135, val=0.75, arous=0.85):  Mitosis 0.586.
    // Four families (geometric / sparkle / hypnotic / particles); 9 distinct scenes over
    // 20 segments at seed 0.

    @Test("Session C: preset IDs match V.7.6.2 multi-segment genre-driven sequence")
    func sessionC_presetSequence() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        // GOLDEN.1: regenerated against the real roster (trace above).
        #expect(session.tracks.map { $0.preset.id } == [
            "Cymatic Resonance", "Gossamer", "Glaze", "Mitosis", "Gossamer", "Mitosis",
        ])
    }

    @Test("Session C: genre diversity produces ≥3 distinct preset families")
    func sessionC_moodShiftProducesFamilyVariety() throws {
        let session = try planner.plan(
            tracks: makeSessionC(), catalog: makeRealCatalog(), deviceTier: .tier2)
        let families = Set(session.tracks.map { $0.preset.family })
        #expect(families.count >= 3)
    }

    // MARK: — Session D: Lumen Mosaic eligibility (BUG-004 closure verification)

    // Scoring trace — GOLDEN.1 (2026-09-24), real roster. Session D locks that a scene
    // wins when the mood matches its identity (BUG-004 closure, 2026-05-12): Lumen Mosaic
    // is low-motion, medium-density, neutral-temperature.
    //
    // Track profile: BPM=75, val=0.0, arous=+0.30, single 180 s track.
    //   targetTemp    = 0.5 + 0.4 * 0.0   = 0.50
    //   targetDensity = 0.5 + 0.4 * 0.30  = 0.62
    //   targetMotion  = 0.2 + 0.3 * (75-70)/40 = 0.2375
    //
    // Ranking: Lumen Mosaic 0.824 (mood 0.985, tempo 0.988) · Alfvén 0.789 ·
    // Gossamer 0.773 · Nimbus 0.753 · Ricercar 0.749 · Skein 0.746.
    // Segments: Lumen Mosaic (0–100.3 s) → Alfvén → Gossamer.

    @Test("Session D: Lumen Mosaic wins track 0 segment 0 under LM-favourable mood")
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

private func makeProfile(
    bpm: Float? = nil,
    valence: Float = 0,
    arousal: Float = 0,
    stemBalance: StemFeatures = .zero
) -> TrackProfile {
    TrackProfile(
        bpm: bpm,
        mood: EmotionalState(valence: valence, arousal: arousal),
        stemEnergyBalance: stemBalance
    )
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
         makeProfile(bpm: 130, valence: 0.7, arousal: 0.8, stemBalance: stems))
    }
}

private func makeSessionB() -> [(TrackIdentity, TrackProfile)] {
    let stems = makeStemBalance(vocals: 0.30, drums: 0.05, bass: 0.40, other: 0.35)
    return (0..<5).map { i in
        (makeIdentity(title: "Jazz-\(i)", duration: 180),
         makeProfile(bpm: 85, valence: 0.3, arousal: -0.3, stemBalance: stems))
    }
}

private typealias TrackSpec = (
    title: String, dur: TimeInterval,
    bpm: Float, val: Float, arous: Float,
    vocals: Float, drums: Float, bass: Float, other: Float
)

private func makeSessionC() -> [(TrackIdentity, TrackProfile)] {
    let specs: [TrackSpec] = [
        ("Elec-0",  240, 130,  0.70,  0.80, 0.30, 0.40, 0.40, 0.20),
        ("Jazz-1",  200,  80,  0.20, -0.40, 0.35, 0.05, 0.40, 0.30),
        ("Rock-2",  210, 115,  0.50,  0.40, 0.25, 0.35, 0.30, 0.25),
        ("Elec-3",  230, 125,  0.60,  0.75, 0.25, 0.45, 0.45, 0.15),
        ("Jazz-4",  180,  70,  0.30, -0.50, 0.45, 0.05, 0.35, 0.30),
        ("Elec-5",  220, 135,  0.75,  0.85, 0.20, 0.45, 0.45, 0.20),
    ]
    return specs.map { p in
        let stems = makeStemBalance(vocals: p.vocals, drums: p.drums, bass: p.bass, other: p.other)
        let profile = makeProfile(bpm: p.bpm, valence: p.val, arousal: p.arous, stemBalance: stems)
        return (makeIdentity(title: p.title, duration: p.dur), profile)
    }
}

// MARK: — Session D Fixture (BUG-004 closure — LM-favourable mood profile)

/// Single 180 s ambient-ish track. BPM=75, val=0.0, arous=+0.30 → moderate
/// density target (0.62), low motion target (0.2375), neutral colour temp (0.50)
/// — aligned to Lumen Mosaic's identity (motion 0.25, density 0.65, tempCenter 0.5).
private func makeSessionD() -> [(TrackIdentity, TrackProfile)] {
    [(makeIdentity(title: "AmbientLM-0", duration: 180),
      makeProfile(bpm: 75, valence: 0.0, arousal: 0.30))]
}
