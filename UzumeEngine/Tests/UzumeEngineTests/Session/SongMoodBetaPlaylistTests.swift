// SongMoodBetaPlaylistTests — BUG-143 + BUG-144 verification on real music. Env-gated: it needs a
// PrepTimingRunner cache of the ten `tools/data/beta_test_playlist.m3u` songs.
//
//   PrepTimingRunner --cache <dir> --out <dir> <each playlist file>   (Release, one song per run)
//   BETA_MOOD_CACHE=<dir> swift test --package-path UzumeEngine --filter SongMoodBetaPlaylist
import DSP
import Foundation
import Testing
@testable import Session
@testable import Shared

@Suite("BUG-143/144 stored profile on the beta playlist (env-gated)")
struct SongMoodBetaPlaylistTests {
    private struct Entry: Decodable {
        let trackProfile: TrackProfile; let decodedDuration: Double?
        let beatGrid: BeatGrid?; let drumsBeatGrid: BeatGrid?
    }

    private static func entries(in dir: String) throws -> [Entry] {
        let files = FileManager.default.enumerator(atPath: dir)?.compactMap { $0 as? String }
            .filter { $0.hasSuffix("metadata.json") } ?? []
        return try files.map {
            try JSONDecoder().decode(Entry.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/" + $0)))
        }
    }

    /// (playlist EXTINF seconds, production-chain song-median arousal — KAG.0g §10, the median
    /// of three 30 s windows at 20/50/80 %). Matched by duration: FLAC entries carry no title.
    private static let reference: [(seconds: Double, arousal: Float)] = [
        (538, 0.69), (304, 0.67), (266, 0.51), (301, 0.54), (181, -0.04),
        (327, 0.48), (289, 0.45), (331, 0.43), (426, -0.28), (384, 0.19),
    ]

    private static func ranks(_ xs: [Float]) -> [Int] {
        let order = xs.indices.sorted { xs[$0] < xs[$1] }
        var r = [Int](repeating: 0, count: xs.count)
        for (rank, idx) in order.enumerated() { r[idx] = rank }
        return r
    }

    @Test("stored arousal ranks the beta playlist like the production chain (ρ ≥ 0.85; was 0.59)")
    func spearmanAgainstProductionChain() throws {
        guard let dir = ProcessInfo.processInfo.environment["BETA_MOOD_CACHE"] else { return }
        let entries = try Self.entries(in: dir)
        var stored: [Float] = [], expected: [Float] = []
        for ref in Self.reference {
            let entry = try #require(entries.first { abs(($0.decodedDuration ?? 0) - ref.seconds) < 2 },
                                     "no cached song of \(ref.seconds) s")
            stored.append(entry.trackProfile.mood.arousal)
            expected.append(ref.arousal)
        }
        let n = Float(stored.count)
        let d2 = zip(Self.ranks(stored), Self.ranks(expected)).map { Float(($0 - $1) * ($0 - $1)) }.reduce(0, +)
        let rho = 1 - 6 * d2 / (n * (n * n - 1))
        print("[song-mood] stored arousal \(stored.map { String(format: "%+.3f", $0) }) ρ = \(rho)")
        #expect(rho >= 0.85, "Spearman ρ \(rho) < 0.85 — the stored mood is not the song's (BUG-143)")
    }

    @Test("stored BPM spreads with the music; irregular beats store none (BUG-144; was 130.6–143.3)")
    func tempoFollowsTheGrid() throws {
        guard let dir = ProcessInfo.processInfo.environment["BETA_MOOD_CACHE"] else { return }
        let entries = try Self.entries(in: dir)
        #expect(entries.count >= 10)
        for entry in entries {
            guard let grid = entry.beatGrid,
                  assessBeatIrregularity(grid: grid, drums: entry.drumsBeatGrid) == true else { continue }
            #expect(entry.trackProfile.bpm == nil, "an irregular beat stored \(entry.trackProfile.bpm ?? 0) BPM")
        }
        let bpms = entries.compactMap(\.trackProfile.bpm)
        let spread = (bpms.max() ?? 0) - (bpms.min() ?? 0)
        print("[song-tempo] stored BPM \(bpms.map { String(format: "%.1f", $0) }) spread \(spread)")
        #expect(spread > 60, "stored BPMs span only \(spread) — the onset-cooldown tempo is back (BUG-144)")
    }
}
