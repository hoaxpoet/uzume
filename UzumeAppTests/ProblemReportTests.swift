// ProblemReportTests — BR.5 / audit H3, F16: the report builder on fakes, the abnormal-exit
// marker, and the pre-filled issue link.

import Foundation
import Testing
@testable import UzumeApp

@Suite("Problem report (BR.5)")
struct ProblemReportTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("br5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func build_zipsLogSystemUzumeCrashReportsAndStallSamples_only() throws {
        let root = try tempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let reports = root.appendingPathComponent("DiagnosticReports")
        let samples = root.appendingPathComponent("Samples")
        let out = root.appendingPathComponent("Out")
        for dir in [reports, samples] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for (dir, name) in [(reports, "Uzume-2026-09-29-120709.ips"), (reports, "Uzume_2026-09-29-1300.hang"),
                            (reports, "Spotify-2026-09-29.ips"), (reports, "Uzume-notes.txt"),
                            (samples, "stall-2026-09-29T12-00-00Z.txt"), (samples, "other.txt")] {
            try "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let zip = try ProblemReportBuilder.build(
            into: out,
            logText: "LOG LINE io.uzume",
            systemSummary: "Uzume 0.9.0 (5) sha=abc123",
            diagnosticReports: reports,
            watchdogSamples: samples,
            now: Date(timeIntervalSince1970: 1_790_000_000)
        )
        #expect(zip.pathExtension == "zip")
        #expect(FileManager.default.fileExists(atPath: zip.path))

        let unpacked = root.appendingPathComponent("Unpacked")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        try ditto.run()
        ditto.waitUntilExit()
        let top = try #require(try FileManager.default.contentsOfDirectory(atPath: unpacked.path).first)
        let base = unpacked.appendingPathComponent(top)
        let files = Set(try FileManager.default.subpathsOfDirectory(atPath: base.path))
        #expect(files.isSuperset(of: ["system.txt", "unified_log.txt", "stall-2026-09-29T12-00-00Z.txt",
                                      "DiagnosticReports/Uzume-2026-09-29-120709.ips",
                                      "DiagnosticReports/Uzume_2026-09-29-1300.hang"]))
        #expect(!files.contains("DiagnosticReports/Spotify-2026-09-29.ips"), "only Uzume's own reports")
        #expect(!files.contains("DiagnosticReports/Uzume-notes.txt"))
        #expect(!files.contains("other.txt"))
        #expect(!files.contains { $0.hasPrefix("._") || $0.contains("/._") }, "no AppleDouble files")
        let system = try String(contentsOf: base.appendingPathComponent("system.txt"), encoding: .utf8)
        #expect(system.contains("sha=abc123"))
    }

    @Test func liveSystemSummary_namesBuildShaAndHardware() {
        let summary = ProblemReportBuilder.systemSummary()
        #expect(summary.hasPrefix("Uzume "))
        #expect(summary.contains("sha="))
        #expect(summary.contains("Mac: "))
        #expect(summary.contains("macOS: "))
        #expect(summary.contains("GPU: "))
    }

    @Test func abnormalExitMarker_setAtLaunch_clearedOnCleanQuit() throws {
        let suite = "test.br5.marker"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let marker = AbnormalExitMarker(defaults: defaults)

        #expect(!marker.markLaunch(), "first launch ever: nothing to report")
        marker.markCleanQuit()
        #expect(!marker.markLaunch(), "clean quit → no offer")
        // …this run crashes, hangs and is force-quit, or is killed: no markCleanQuit.
        #expect(marker.markLaunch(), "the next launch offers the report")
    }

    @MainActor
    @Test func issueURL_isPrefilledAndPointsAtTheRepo() throws {
        let url = try #require(ProblemReporter.issueURL(zipName: "Uzume-Report-X.zip",
                                                        summaryFirstLine: "Uzume 0.9.0 (5) sha=abc"))
        #expect(url.absoluteString.hasPrefix("https://github.com/hoaxpoet/uzume/issues/new?"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body = try #require(items.first { $0.name == "body" }?.value)
        #expect(body.contains("Uzume-Report-X.zip"))
        #expect(body.contains("sha=abc"))
        #expect(items.contains { $0.name == "title" })
    }
}
