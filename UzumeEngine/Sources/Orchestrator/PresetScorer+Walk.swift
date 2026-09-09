// PresetScorer+Walk — the manual preset walk's ordering (PR.8.2).
//
// Split from PresetScorer.swift for file-length compliance; the walk is the manual override path,
// distinct from `rank`/`score`, which serve the planner.

import Foundation
import Presets
import Session

extension DefaultPresetScorer {

    /// Deterministic order for a MANUAL preset walk (the immediate nudge).
    ///
    /// Ranked by track fit, with the history-dependent multipliers held neutral —
    /// `currentPreset` and `recentHistory` are cleared before scoring — so the order does **not**
    /// change as the walk moves through it.
    ///
    /// PR.8 walked `rank(...)` under the live context and Matt could not reach eight of his
    /// presets. `familyRepeatMultiplier` penalises the *current* preset too (its family always
    /// equals the current family), so every press sank the current preset to the bottom of a
    /// freshly-computed ranking and `(currentIdx + 1) % count` wrapped back to index 0. The walk
    /// oscillated between the top two entries — his log reads
    /// `Aurora Veil → Dragon Bloom → Aurora Veil → …`, then `Ricercar ↔ Fata Morgana`.
    ///
    /// **Every preset is returned, including ones the planner excludes.** A manual override has to
    /// be able to reach anything the user has loaded — diagnostics and over-budget presets included
    /// — which the alphabetical walk this replaced did by accident and PR.8's `filter { $0.1 > 0 }`
    /// removed. Excluded presets sort last (score 0); ties break by name so the order is total.
    public func walkOrder(
        presets: [PresetDescriptor],
        track: TrackProfile,
        context: PresetScoringContext
    ) -> [PresetDescriptor] {
        let neutral = PresetScoringContext(
            deviceTier: context.deviceTier,
            frameBudgetMs: context.frameBudgetMs,
            recentHistory: [],
            currentPreset: nil,
            elapsedSessionTime: context.elapsedSessionTime,
            currentSection: context.currentSection,
            excludedFamilies: context.excludedFamilies,
            qualityCeiling: context.qualityCeiling,
            familyBoosts: context.familyBoosts,
            temporarilyExcludedFamilies: context.temporarilyExcludedFamilies,
            sessionExcludedPresets: context.sessionExcludedPresets,
            includeUncertifiedPresets: context.includeUncertifiedPresets
        )
        return presets
            .map { ($0, score(preset: $0, track: track, context: neutral)) }
            .sorted { ($0.1, $1.0.name) > ($1.1, $0.0.name) }
            .map { $0.0 }
    }
}
