// ScanBench — SCAN.0 accuracy harness for playlist screen reading (D-260).
//
//   swift build -c release --package-path UzumeEngine --product ScanBench
//   UzumeEngine/.build/release/ScanBench [fixtures-root] [--mode reader|whole|both] [--report out.md]
//   SCANBENCH_OBS=frames.json UzumeEngine/.build/release/ScanBench   # replay recorded observations
//
// Default root: ~/Documents/uzume_scan_fixtures (outside the repo — the captures show a
// real account; never commit them). The evaluation lives in ScanBenchCore, shared with
// PlaylistScanFixtureTests. Numbers of record: docs/diagnostics/SCAN_FEASIBILITY_2026-09-28.md.

import Foundation
import ScanBenchCore
import Session

// MARK: - Observation replay (parser debugging)

if let obsPath = ProcessInfo.processInfo.environment["SCANBENCH_OBS"] {
    let data = try Data(contentsOf: URL(fileURLWithPath: obsPath))
    let frames = try JSONDecoder().decode([[ScanTextObservation]].self, from: data)
    for (index, observations) in frames.enumerated() {
        let frame = PlaylistFrameParser.parse(observations)
        print("-- frame \(index): count=\(frame.songCount.map(String.init) ?? "nil") "
              + "name=\(frame.playlistName ?? "nil") end=\(frame.reachedEnd)")
        for row in frame.rows {
            print("   \(row.number) \(row.title) | \(row.artist) | \(row.duration ?? 0) | \(row.confidence)")
        }
    }
    exit(0)
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
var options: [String: String] = [:]
for flag in ["--report", "--mode"] {
    if let index = arguments.firstIndex(of: flag), index + 1 < arguments.count {
        options[flag] = arguments[index + 1]
        arguments.removeSubrange(index...(index + 1))
    }
}
let reportPath = options["--report"]
let mode = options["--mode"].flatMap(ScanReadingMode.init(rawValue:)) ?? .reader
let rootPath = arguments.first ?? "~/Documents/uzume_scan_fixtures"
let root = URL(fileURLWithPath: (rootPath as NSString).expandingTildeInPath)

// MARK: - Run

let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
let cache = ScanBenchResponseCache()
var results: [ScanBenchResult] = []
for folder in folders {
    FileHandle.standardError.write(Data("scanning \(folder.lastPathComponent)…\n".utf8))
    results.append(try await evaluateScanFixture(folder: folder, cache: cache, mode: mode))
}
let text = "Mode: \(mode.rawValue)\n\n" + scanBenchReport(results)
    + "\n\n_iTunes network requests this run: \(cache.networkRequests) (rest from cache)._\n"
print(text)
if let reportPath { try text.write(toFile: reportPath, atomically: true, encoding: .utf8) }
