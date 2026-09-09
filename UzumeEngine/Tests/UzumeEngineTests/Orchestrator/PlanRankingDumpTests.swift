// PlanRankingDumpTests — PR.8 diagnostic. Env-gated; prints the PRODUCTION scorer's
// ranking for a cached track profile so "why did preset X open?" is answered by the
// code that chose it, not by a hand model of it.
//
//   PLAN_DUMP_META=<StemCache …/metadata.json> swift test --filter PlanRankingDump
import Foundation
import Orchestrator
import Presets
import Session
import Testing

@Suite("PR.8 plan ranking dump (env-gated)")
struct PlanRankingDumpTests {
    private struct CacheEntry: Decodable { let metadata: TrackIdentity; let trackProfile: TrackProfile }

    @Test("dump the production ranking + planner picks for a cached track (PLAN_DUMP_META)")
    func dump() throws {
        guard let path = ProcessInfo.processInfo.environment["PLAN_DUMP_META"] else { return }
        let entry = try JSONDecoder().decode(CacheEntry.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let dir = try #require(PresetLoader.bundledShadersURL)
        let catalog: [PresetDescriptor] = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(PresetDescriptor.self, from: Data(contentsOf: $0)) }
        let scorer = DefaultPresetScorer()
        let p = entry.trackProfile
        print("[plan-dump] \(entry.metadata.title) — bpm \(p.bpm.map { String(format: "%.1f", $0) } ?? "nil"), valence \(p.mood.valence), arousal \(p.mood.arousal), catalog \(catalog.count)")
        for tier in [DeviceTier.tier1, .tier2] {
            let ctx = PresetScoringContext(deviceTier: tier, includeUncertifiedPresets: true)
            let rows = catalog.map { ($0, scorer.breakdown(preset: $0, track: p, context: ctx)) }
                .sorted { $0.1.total > $1.1.total }
            print("[plan-dump] tier \(tier) — empty history (the opener context):")
            for (d, b) in rows.prefix(12) {
                let ex = b.excluded ? "  EXCLUDED: \(b.exclusionReason ?? "?")" : ""
                print(String(format: "[plan-dump]   %-22@ total %.3f  mood %.2f tempo %.2f aff %.2f sect %.2f fam×%.2f fat×%.2f boost %.2f%@",
                             d.name as NSString, b.total, b.mood, b.tempoMotion, b.stemAffinity, b.sectionSuitability,
                             b.familyRepeatMultiplier, b.fatigueMultiplier, b.familyBoost, ex as NSString))
            }
            if let w = rows.firstIndex(where: { $0.0.name == "Witchlight" }) {
                let b = rows[w].1
                print(String(format: "[plan-dump]   Witchlight rank %d/%d total %.3f%@", w + 1, rows.count, b.total,
                             (b.excluded ? "  EXCLUDED: \(b.exclusionReason ?? "?")" : "") as NSString))
            }
            let planner = DefaultSessionPlanner()
            var picks: [String: Int] = [:]
            for seed in [UInt64(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11] {
                let s = try planner.plan(tracks: [(entry.metadata, p)], catalog: catalog, deviceTier: tier,
                                         seed: seed, includeUncertifiedPresets: true)
                let name = s.tracks.first?.segments.first?.preset.name ?? "?"
                picks[name, default: 0] += 1
            }
            print("[plan-dump]   planner first pick over 12 seeds: \(picks.sorted { $0.value > $1.value })")
        }
    }
}
