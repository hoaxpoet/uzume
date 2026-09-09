// PresetWalkOrderTests — PR.8.2. The manual walk must reach every preset and must not
// re-order itself as it moves.
//
// The defect this pins: PR.8 walked `rank(...)` under the LIVE context. `familyRepeatMultiplier`
// penalises the current preset too, so each press sank it to the bottom of a freshly-computed
// ranking and `(currentIdx + 1) % count` wrapped to index 0. Matt's session walked
// Aurora Veil → Dragon Bloom → Aurora Veil → … and could reach two presets of thirty.
import Foundation
import Orchestrator
import Presets
import Session
import Testing

@Suite("PR.8.2 manual walk order")
struct PresetWalkOrderTests {
    private let scorer = DefaultPresetScorer()

    private func preset(_ name: String, family: PresetCategory?, certified: Bool = true,
                        diagnostic: Bool = false, cost: Float = 1) -> PresetDescriptor {
        let fam = family.map { "\"family\": \"\($0.rawValue)\"," } ?? ""
        let json = """
        {
            "name": "\(name)",
            \(fam)
            "complexity_cost": {"tier1": \(cost), "tier2": \(cost)},
            "is_diagnostic": \(diagnostic),
            "certified": \(certified)
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    private var catalog: [PresetDescriptor] {
        [preset("Aurora Veil", family: .hypnotic), preset("Dragon Bloom", family: .hypnotic),
         preset("Ricercar", family: .painterly), preset("Fata Morgana", family: .hypnotic),
         preset("Arachne", family: .drawing, certified: false),
         preset("Cartograph", family: nil, diagnostic: true),
         preset("Heavy", family: .geometric, cost: 99)]
    }

    private func context(current: PresetDescriptor?) -> PresetScoringContext {
        PresetScoringContext(deviceTier: .tier1, currentPreset: current,
                             includeUncertifiedPresets: true)
    }

    private var track: TrackProfile {
        TrackProfile(bpm: 122, mood: EmotionalState(valence: -0.7, arousal: 0.6))
    }

    @Test("the walk reaches EVERY preset — diagnostics and over-budget included")
    func walkVisitsEverything() {
        let all = catalog
        var current = all[0]
        var seen: Set<String> = [current.id]
        for _ in 0..<(all.count * 2) {
            let order = scorer.walkOrder(presets: all, track: track, context: context(current: current))
            let idx = order.firstIndex(where: { $0.id == current.id }) ?? -1
            current = order[(idx + 1) % order.count]
            seen.insert(current.id)
        }
        #expect(seen.count == all.count,
                "walk reached \(seen.count) of \(all.count): \(seen.sorted()) — a manual override must reach anything loaded")
    }

    @Test("the order does not change as the walk moves through it")
    func orderIsStableUnderTheWalk() {
        let all = catalog
        let baseline = scorer.walkOrder(presets: all, track: track, context: context(current: nil)).map(\.id)
        for candidate in all {
            let order = scorer.walkOrder(presets: all, track: track,
                                         context: context(current: candidate)).map(\.id)
            #expect(order == baseline,
                    "order shifted when current == \(candidate.id): \(order) vs \(baseline)")
        }
    }

    @Test("a full cycle returns to the start having passed through all of them")
    func cycleIsAPermutation() {
        let all = catalog
        var current = all[0]
        var visited: [String] = []
        for _ in 0..<all.count {
            let order = scorer.walkOrder(presets: all, track: track, context: context(current: current))
            let idx = order.firstIndex(where: { $0.id == current.id }) ?? -1
            current = order[(idx + 1) % order.count]
            visited.append(current.id)
        }
        #expect(Set(visited).count == all.count, "a full cycle repeated entries: \(visited)")
        #expect(current.id == all[0].id, "a full cycle did not return to the start: ended at \(current.id)")
    }
}
