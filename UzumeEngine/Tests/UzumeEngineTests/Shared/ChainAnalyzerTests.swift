// ChainAnalyzerTests — ASH.2 post-session chain-health grader.
//
// Verdict paths are driven off hand-written session.log dirs (log-parser tests,
// FA-#27-clean — no audio is synthesized) plus the checked-in REAL Love Rehab
// capture for the clean + onset-report case.

import Foundation
import Testing
@testable import Shared

struct ChainAnalyzerTests {

    // MARK: - Helpers

    /// A throwaway session dir under the system temp area. Caller writes artifacts.
    private func makeDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ash2-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to dir: URL, _ file: String) throws {
        try text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    /// The checked-in real Love Rehab features.csv (route-coverage fixture) copied
    /// into a fresh Love-Rehab-named dir so the analyzer applies its calibration.
    private func realLoveRehabDir() throws -> URL? {
        guard let url = Bundle.module.url(
            forResource: "features", withExtension: "csv",
            subdirectory: "route_coverage/love_rehab") else { return nil }
        let dir = try makeDir("love_rehab_clean")
        try FileManager.default.copyItem(at: url, to: dir.appendingPathComponent("features.csv"))
        try write("[t] track → Love Rehab — Chaim\n", to: dir, "session.log")
        return dir
    }

    // MARK: - Verdict paths

    @Test("A clean real Love Rehab capture grades clean and reports ~11 onsets/5s")
    func cleanLoveRehab() throws {
        guard let dir = try realLoveRehabDir() else {
            Issue.record("route_coverage/love_rehab fixture missing from test bundle")
            return
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(health.verdict == .clean)
        #expect(health.reasons.isEmpty)
        // Reported, not gated. The real capture sits on the validated 11 reference.
        #expect(health.loveRehabMedianOnsetsPer5s == ChainAnalyzer.loveRehabReferenceOnsets)
    }

    @Test("band=low AFTER a healthy window + DRM-silence grade degraded with those reasons")
    func degradedFromLog() throws {
        let dir = try makeDir("degraded")
        defer { try? FileManager.default.removeItem(at: dir) }
        // D-197: the chain was loud (healthy) first, THEN dropped — a real degradation.
        // BUG-121: the drop must be SUSTAINED. One window is a fade between tracks; a
        // misrouted chain is quiet in every window, so the fixture holds a run.
        try write("""
            [t] SIGNAL_HEALTH: peak=-4.0dBFS band=healthy deadTap=false rate=48000
            [t] SIGNAL_HEALTH: peak=-13.5dBFS band=low deadTap=false rate=48000
            [t] SIGNAL_HEALTH: peak=-13.8dBFS band=low deadTap=false rate=48000
            [t] SIGNAL_HEALTH: peak=-14.2dBFS band=low deadTap=false rate=48000
            [t] DRM silence detected on the tap
            """, to: dir, "session.log")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(health.verdict == .degraded)
        #expect(health.reasons.contains("signal_health_band_low"))
        #expect(health.reasons.contains { $0.hasPrefix("drm_silence") })
        #expect(health.outputSampleRateHz == 48_000)
    }

    @Test("A quiet intro (band=critical/low BEFORE any healthy) does NOT flag band_low (D-197)")
    func quietIntroDoesNotFlagBandLow() throws {
        let dir = try makeDir("quiet_intro")
        defer { try? FileManager.default.removeItem(at: dir) }
        // The Cymatic Resonance M7 shape: a quiet song intro reads critical/low, then
        // the song kicks in (healthy) and stays. Degraded-only-after-loud → clean.
        try write("""
            [t] SIGNAL_HEALTH: peak=-24.0dBFS band=critical deadTap=false rate=44100
            [t] SIGNAL_HEALTH: peak=-13.0dBFS band=low deadTap=false rate=44100
            [t] SIGNAL_HEALTH: peak=-2.0dBFS band=healthy deadTap=false rate=44100
            """, to: dir, "session.log")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(!health.reasons.contains("signal_health_band_low"),
                "a low/critical window before the chain was ever loud must not flag degraded")
        #expect(health.verdict == .clean)
    }

    @Test("A confirmed dead tap grades broken")
    func brokenFromDeadTap() throws {
        let dir = try makeDir("broken")
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("[t] SIGNAL_HEALTH: peak=-40.0dBFS band=critical deadTap=true rate=96000\n",
                  to: dir, "session.log")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(health.verdict == .broken)
        #expect(health.reasons.contains("dead_tap"))
    }

    @Test("A pre-ASH historical dir (no raw_tap, no SIGNAL_HEALTH) grades without error")
    func historicalDirNoError() throws {
        let dir = try makeDir("historical")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Minimal features.csv, no session.log, no raw_tap — the retroactive case.
        try write(SessionRecorder.featuresCSVHeader, to: dir, "features.csv")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(health.verdict == .clean)
        #expect(health.notes.contains("no_raw_tap"))
    }

    @Test("A low onset count does NOT change the verdict — the count is report-only (D-184)")
    func onsetCountNotGated() throws {
        let dir = try makeDir("love_rehab_few_onsets")
        defer { try? FileManager.default.removeItem(at: dir) }
        // A features.csv with almost no beatBass onsets. This tests the GATING
        // LOGIC (onset count must not downgrade), not an audio-fidelity claim —
        // so hand-writing the column is FA-#27-clean here.
        var csv = SessionRecorder.featuresCSVHeader
        let header = SessionRecorder.featuresCSVHeader.split(separator: ",").map(String.init)
        let cols = header.count
        let iBeat = header.firstIndex(of: "beatBass")!
        let iWall = header.firstIndex(of: "wallclock_s")!
        for frame in 0..<600 {
            var fields = [String](repeating: "0", count: cols)
            fields[iWall] = String(Double(frame) / 60.0)   // 10 s of frames
            fields[iBeat] = "0"                             // no onsets at all
            csv += fields.joined(separator: ",") + "\n"
        }
        try write(csv, to: dir, "features.csv")
        try write("[t] track → Love Rehab — Chaim\n", to: dir, "session.log")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(health.verdict == .clean)               // NOT degraded despite 0 onsets
        #expect(health.loveRehabMedianOnsetsPer5s == 0) // but the count is reported
    }

    // MARK: - Units

    @Test("Peak dBFS classification matches the RUNBOOK bands")
    func dbfsClassification() {
        #expect(ChainAnalyzer.dbfs(peak: 1.0) == 0)
        #expect(ChainAnalyzer.dbfs(peak: 0) == -120)          // silence floor
        #expect(abs(ChainAnalyzer.dbfs(peak: 0.1) - -20) < 0.01)
    }

    @Test("analyzeAndWrite emits chain_health.json and the CHAIN_HEALTH log line")
    func writesArtifacts() throws {
        let dir = try makeDir("write")
        defer { try? FileManager.default.removeItem(at: dir) }
        try write("[t] SIGNAL_HEALTH: peak=-9.0dBFS band=healthy deadTap=false rate=48000\n",
                  to: dir, "session.log")
        let health = ChainAnalyzer.analyzeAndWrite(sessionDir: dir)

        let jsonURL = dir.appendingPathComponent("chain_health.json")
        #expect(FileManager.default.fileExists(atPath: jsonURL.path))
        let decoded = try JSONDecoder().decode(
            ChainHealth.self, from: Data(contentsOf: jsonURL))
        #expect(decoded == health)

        let log = try String(contentsOf: dir.appendingPathComponent("session.log"), encoding: .utf8)
        #expect(log.contains("CHAIN_HEALTH: verdict=clean"))
    }

    // MARK: - BUG-121 — one quiet window is a passage, not a degraded chain

    /// Every "degraded" verdict in Matt's entire session history was ONE window: 1 of 68,
    /// 1 of 20, 1 of 34, always a lone `critical` at −18 to −24 dBFS in the MIDDLE of a
    /// track, and `band=low` never once occurred. D-197 had already patched the version of
    /// this that fired on a quiet opening; the false positive simply moved into the song.
    @Test("A single quiet window mid-session does NOT grade degraded (BUG-121)")
    func oneQuietWindowIsNotDegraded() throws {
        let dir = try makeDir("one_quiet_window")
        defer { try? FileManager.default.removeItem(at: dir) }
        var lines = (0..<8).map { _ in
            "[t] SIGNAL_HEALTH: peak=-10.4dBFS band=healthy deadTap=false rate=48000"
        }
        // The fade between two tracks, verbatim in shape from session 2026-09-08T14-09-48Z.
        lines.insert("[t] SIGNAL_HEALTH: peak=-18.6dBFS band=critical deadTap=false rate=48000",
                     at: 5)
        try write(lines.joined(separator: "\n"), to: dir, "session.log")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(!health.reasons.contains("signal_health_band_low"),
                "a lone quiet window graded the whole session degraded")
    }

    /// The other direction, which is what the check is FOR: a chain that is actually quiet —
    /// wrong output device, wrong routing — is quiet in every window, and must still flag.
    @Test("A sustained quiet run DOES grade degraded (BUG-121 negative control)")
    func sustainedQuietIsDegraded() throws {
        let dir = try makeDir("sustained_quiet")
        defer { try? FileManager.default.removeItem(at: dir) }
        var lines = ["[t] SIGNAL_HEALTH: peak=-4.0dBFS band=healthy deadTap=false rate=48000"]
        lines += (0..<6).map { _ in
            "[t] SIGNAL_HEALTH: peak=-19.0dBFS band=critical deadTap=false rate=48000"
        }
        try write(lines.joined(separator: "\n"), to: dir, "session.log")
        let health = ChainAnalyzer.analyze(sessionDir: dir)
        #expect(health.reasons.contains("signal_health_band_low"),
                "a chain quiet in every window must still be caught")
        #expect(health.verdict == .degraded)
    }

    /// Two quiet windows is still a passage — the boundary, asserted so the threshold is not
    /// quietly loosened or tightened without this failing.
    @Test("The threshold is a RUN of three, not two (BUG-121)")
    func thresholdIsThree() throws {
        for (count, shouldFlag) in [(2, false), (3, true)] {
            let dir = try makeDir("run_\(count)")
            defer { try? FileManager.default.removeItem(at: dir) }
            var lines = ["[t] SIGNAL_HEALTH: peak=-4.0dBFS band=healthy deadTap=false rate=48000"]
            lines += (0..<count).map { _ in
                "[t] SIGNAL_HEALTH: peak=-16.0dBFS band=critical deadTap=false rate=48000"
            }
            try write(lines.joined(separator: "\n"), to: dir, "session.log")
            let health = ChainAnalyzer.analyze(sessionDir: dir)
            #expect(health.reasons.contains("signal_health_band_low") == shouldFlag,
                    "a run of \(count) should\(shouldFlag ? "" : " not") flag")
        }
    }
}
