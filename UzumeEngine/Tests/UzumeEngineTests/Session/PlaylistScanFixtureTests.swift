// PlaylistScanFixtureTests — SCAN.1 (D-260): the real-screenshot half of the scan tests.
//
// FIXTURE-GATED and NOT on the CI allow-list. Reads Matt's captures at
// ~/Documents/uzume_scan_fixtures (outside the repo — they show a real account; never
// committed) and FAILS LOUDLY when they are absent (the BeatThisFixturePresenceGate
// precedent — never a silent skip). Runs the same evaluation as the ScanBench CLI
// (ScanBenchCore), OFFLINE against ScanBench's recorded iTunes responses
// (~/.uzume/scanbench/itunes_cache.json), and pins the numbers of record in
// docs/diagnostics/SCAN_FEASIBILITY_2026-09-28.md. A Vision or parser change that moves
// them fails here: re-run ScanBench (Release), then update the doc and these pins together.

import Foundation
import ScanBenchCore
import Testing

@Suite("PlaylistScan — real screenshots (fixture-gated, SCAN.1)")
struct PlaylistScanFixtureTests {

    static let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/uzume_scan_fixtures")

    static var folders: [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return found.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @Test("fixture presence gate: four playlists with captures and a CSV each")
    func fixturesPresent() throws {
        let folders = Self.folders
        guard folders.count == 4 else {
            Issue.record("""
                PlaylistScanFixtureTests: expected 4 playlist folders at \(Self.root.path), found \(folders.count). \
                The scan fixtures live outside the repo (docs/diagnostics/SCAN_FEASIBILITY_2026-09-28.md §Setup).
                """)
            return
        }
        for folder in folders {
            let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(files.contains { $0.lowercased().hasSuffix(".png") }, "\(folder.lastPathComponent): no captures")
            #expect(files.contains { $0.lowercased().hasSuffix(".csv") }, "\(folder.lastPathComponent): no Exportify CSV")
        }
    }

    @Test("reproduces the SCAN gate: 144/144 rows, 98.4 % identified (127/129, BR.19), 0 wrong songs")
    func reproducesGate() async throws {
        guard Self.folders.count == 4 else {
            Issue.record("scan fixtures absent at \(Self.root.path) — see fixturesPresent")
            return
        }
        let cache = ScanBenchResponseCache(offline: true)
        guard cache.count > 0 else {
            Issue.record("no recorded iTunes responses at \(ScanBenchResponseCache.defaultURL.path) — run ScanBench once (Release)")
            return
        }
        var results: [ScanBenchResult] = []
        for folder in Self.folders {
            results.append(try await evaluateScanFixture(folder: folder, cache: cache, mode: .reader))
        }
        for result in results {
            #expect(result.songCountRead == result.truthCount, "\(result.name): header count not read")
            #expect(result.playlistNameRead != nil, "\(result.name): playlist name not read")
            #expect(result.silentMiss == 0, "\(result.name): \(result.silentMiss) silent misses")
        }
        let found = results.reduce(0) { $0 + $1.found }
        let identified = results.reduce(0) { $0 + $1.identified }
        let judged = results.reduce(0) { $0 + $1.judged }
        let wrong = results.reduce(0) { $0 + $1.wrong }
        let report = scanBenchReport(results)
        #expect(found == 144, "coverage moved — \(report)")
        // BR.19 (BUG-152): the ground truth is now verified too, so its 11 wrong-song rows became
        // "no preview" and judged moved 125 → 129 (the title-only retry found four more).
        #expect(identified == 127 && judged == 129, "identification moved from 127/129 — \(report)")
        #expect(wrong == 0, "a wrong song appeared — \(report)")
        #expect(Double(identified) / Double(judged) >= 0.95 && Double(wrong) / Double(judged) <= 0.02, "below the SCAN.0 bar")
    }
}
