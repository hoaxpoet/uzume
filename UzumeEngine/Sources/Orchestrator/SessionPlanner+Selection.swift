// SessionPlanner+Selection — how one segment's preset is chosen (split out at BUG133.2).
//
// Split from `SessionPlanner.swift` when near-tie sampling pushed that file past the 400-line lint
// budget. Nothing moved but the selection block: the seeded noise (D-047), the near-tie band
// (BUG-133) and `selectPreset` with its eligibility fallbacks. The planning walk, transitions and
// warnings stay with the planner.

import Foundation
import Presets
import Session
import Shared

extension DefaultSessionPlanner {

    // MARK: - Seed Noise (D-047)

    /// Deterministic ±0.02 perturbation for seeded Regenerate Plan.
    ///
    /// Uses a simple LCG chain to produce a float in [-0.02, 0.02] for a given
    /// (seed, trackIndex, presetID) triple. When seed == 0 this is never called.
    private func seededNoise(seed: UInt64, trackIndex: Int, presetID: String) -> Float {
        var hash = seed &+ UInt64(bitPattern: Int64(trackIndex)) &* 2654435761
        hash ^= UInt64(bitPattern: Int64(presetID.hashValue))
        hash = hash &* 6364136223846793005 &+ 1442695040888963407
        let normalized = Float(hash >> 11) / Float(1 << 53)
        return (normalized - 0.5) * 0.04  // [-0.02, 0.02]
    }

    // MARK: - Near-tie sampling (BUG-133)

    /// How close to the best score counts as "the scorer cannot tell these apart".
    ///
    /// ★ **Why this exists.** Measured with the production scorer over Matt's own cached profiles,
    /// the whole eligible catalog spans **0.612 → 0.459** on one track, with the **top twelve inside
    /// 0.05 of each other**. A 0.003 gap between Cytokinesis (0.612) and Dragon Bloom (0.611) is
    /// arithmetic, not a musical preference — but `max(by:)` treats it as decisive, so the same five
    /// or six presets opened every segment of every track and fourteen certified presets were
    /// unreachable at any cooldown setting (BUG-133; BUG133.1's per-preset fatigue was necessary and
    /// did not fix this).
    ///
    /// 0.05 is chosen against that measurement, and against the scorer's own admission: it already
    /// adds ±0.02 of seeded noise to every total, so ±0.02 is *already* declared meaningless. This
    /// band is modestly wider and reaches the twelve presets the spread shows are indistinguishable.
    ///
    /// ⚠ It is a **band, not a lottery over the catalog** — a preset 0.15 below the best still never
    /// plays, because that gap IS a preference. Widening this until everything qualifies would
    /// replace the planner with a shuffle.
    static let nearTieBandWidth: Float = 0.05

    /// Pick uniformly among the presets the scorer cannot distinguish from the best.
    ///
    /// **Deterministic, and that is load-bearing.** The choice is a pure function of
    /// `(seed, trackIndex, clock, candidate ids)`, so a plan grown 3 → 6 → 12 is byte-identical to
    /// one planned all at once — the invariant `PartialPlanTests.extendedPlanEqualsFullyPreparedPlan`
    /// pins, and which PREP.2 leans on every time the walk extends a live plan.
    ///
    /// Returns nil when `seed == 0`, which keeps the unseeded path a pure argmax: the golden session
    /// fixtures plan without a seed, so they still pin scorer behaviour rather than a sample. That
    /// also means the goldens do NOT cover this path — `NearTieSamplingTests` does.
    ///
    /// Uniform rather than score-weighted on purpose: inside the band the score differences are the
    /// very thing being called noise, so weighting by them would re-import the precision this is
    /// discarding.
    private func nearTiePick(
        eligible: [(PresetDescriptor, PresetScoreBreakdown)],
        best: (PresetDescriptor, PresetScoreBreakdown),
        seed: UInt64,
        trackIndex: Int,
        clock: TimeInterval
    ) -> (PresetDescriptor, PresetScoreBreakdown)? {
        guard seed != 0 else { return nil }
        let floor = best.1.total - Self.nearTieBandWidth
        // Sorted by id so the candidate order cannot depend on catalog enumeration order.
        let contenders = eligible.filter { $0.1.total >= floor }.sorted { $0.0.id < $1.0.id }
        guard contenders.count > 1 else { return nil }

        var hash = seed &+ UInt64(bitPattern: Int64(trackIndex)) &* 2654435761
        hash ^= UInt64(bitPattern: Int64(clock * 1000))
        hash = hash &* 6364136223846793005 &+ 1442695040888963407
        return contenders[Int((hash >> 33) % UInt64(contenders.count))]
    }

    // MARK: - Preset Selection

    /// Returns the best eligible `(preset, breakdown)`, falling back if all are excluded.
    ///
    /// `trackRef` bundles the playlist index and title used for warning messages.
    func selectPreset( // swiftlint:disable:this function_parameter_count
        catalog: [PresetDescriptor],
        profile: TrackProfile,
        context: PresetScoringContext,
        trackRef: (index: Int, title: String),
        seed: UInt64,
        warnings: inout [PlanningWarning]
    ) -> (PresetDescriptor, PresetScoreBreakdown) {
        let allBDs = catalog.map { preset -> (PresetDescriptor, PresetScoreBreakdown) in
            var bd = scorer.breakdown(preset: preset, track: profile, context: context)
            if seed != 0 {
                let noise = seededNoise(seed: seed, trackIndex: trackRef.index, presetID: preset.id)
                bd = PresetScoreBreakdown(
                    mood: bd.mood,
                    tempoMotion: bd.tempoMotion,
                    stemAffinity: bd.stemAffinity,
                    sectionSuitability: bd.sectionSuitability,
                    familyRepeatMultiplier: bd.familyRepeatMultiplier,
                    fatigueMultiplier: bd.fatigueMultiplier,
                    excluded: bd.excluded,
                    exclusionReason: bd.exclusionReason,
                    familyBoost: bd.familyBoost,
                    excludedReason: bd.excludedReason,
                    total: max(0, min(1, bd.total + noise))
                )
            }
            return (preset, bd)
        }
        let eligible = allBDs.filter { !$0.1.excluded && $0.1.total > 0 }
        if let top = eligible.max(by: { $0.1.total < $1.1.total }) {
            let sampled = nearTiePick(
                eligible: eligible,
                best: top,
                seed: seed,
                trackIndex: trackRef.index,
                clock: context.elapsedSessionTime
            )
            return sampled ?? top
        }
        warnings.append(PlanningWarning(
            kind: .noEligiblePresets,
            trackIndex: trackRef.index,
            message: "No eligible preset for track \(trackRef.index) (\(trackRef.title)); "
                   + "all \(catalog.count) catalog presets excluded. Using cheapest fallback."
        ))
        return cheapestFallback(
            catalog: catalog,
            context: context,
            trackIndex: trackRef.index,
            profile: profile,
            warnings: &warnings
        )
    }

    /// Catalog filtered to presets eligible to auto-install on this track: never a
    /// diagnostic (D-074), never a beat-locked preset on an irregular track (D-154).
    /// Falls back to the full `catalog` only when *nothing* is categorically eligible
    /// (a degenerate catalog) — rendering something beats rendering nothing, and the
    /// caller has already warned. Single source of truth for the planner's two
    /// defensive fallbacks (zero-duration `planSegments`, budget `cheapestFallback`):
    /// both filter identically so a diagnostic can never reach a segment via either
    /// path (CLEAN.3.2).
    func categoricallyEligiblePool(
        _ catalog: [PresetDescriptor],
        onIrregularBeat: Bool
    ) -> [PresetDescriptor] {
        let eligible = catalog.filter {
            !$0.isDiagnostic && !($0.requiresRegularBeat && onIrregularBeat)
        }
        return eligible.isEmpty ? catalog : eligible
    }

    /// Picks the cheapest preset that is not the current preset.
    /// If no alternative exists, returns the globally cheapest with a `.budgetExceeded` warning.
    private func cheapestFallback(
        catalog: [PresetDescriptor],
        context: PresetScoringContext,
        trackIndex: Int,
        profile: TrackProfile,
        warnings: inout [PlanningWarning]
    ) -> (PresetDescriptor, PresetScoreBreakdown) {
        let tier = context.deviceTier
        // The fallback exists to relax SOFT exclusions (budget, fatigue,
        // score) when nothing is eligible — it must never relax CATEGORICAL
        // ones: a diagnostic preset (D-074) or a beat-locked preset on a
        // beat-irregular track (FBS / D-154) cannot land via fallback either.
        // Discovered by `test_plannedSession_neverSchedulesRequiringPreset_
        // onIrregularTrack`: alternate segments fell through to this path
        // (current preset active-excluded + family-mates fatigued to zero)
        // and scheduled the excluded preset. Degenerate catalogs (everything
        // categorical) keep the old behaviour — the warning above already
        // fired and rendering something beats rendering nothing.
        let pool = categoricallyEligiblePool(catalog, onIrregularBeat: profile.beatIrregular == true)
        let sorted = pool.sorted { $0.complexityCost.cost(for: tier) < $1.complexityCost.cost(for: tier) }
        let excludingID = context.currentPreset?.id
        if let fallback = sorted.first(where: { $0.id != excludingID }) {
            return (fallback, scorer.breakdown(preset: fallback, track: profile, context: context))
        }
        // Single-preset catalog and it is the current one — use it anyway.
        // swiftlint:disable:next force_unwrapping
        let fallback = sorted.first!
        warnings.append(PlanningWarning(
            kind: .budgetExceeded,
            trackIndex: trackIndex,
            message: "Track \(trackIndex): no preset fits tier '\(tier)' budget; "
                   + "using '\(fallback.name)' (\(fallback.complexityCost.cost(for: tier)) ms)."
        ))
        return (fallback, scorer.breakdown(preset: fallback, track: profile, context: context))
    }
}
