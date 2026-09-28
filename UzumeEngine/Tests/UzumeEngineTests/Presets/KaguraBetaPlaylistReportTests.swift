// KaguraBetaPlaylistReportTests — the safety net and the dance pick on the 30 beta-playlist captures (KAG.3).
//
// A REPORT, opt-in: `KAGURA_BETA_SESSIONS=<dir of fixturegen-bNN_pXX captures>` (the spike's production-chain
// windows at 20 / 50 / 80 % of each `tools/data/beta_test_playlist.m3u` song; not in git). Each capture's
// grid is built from its own `beatPhase01` / `barPhase01_permille` wraps, exactly as the spike's
// `load_session` does, and the choreographer runs on the capture's playback clock and `bass_att`, with the
// song's `TrackProfile.songArousal`. Printed per capture: how much of it the safety net swayed (README §11
// is the spike's per-window verdict) and the dance picked at each clip change, with its time, for the
// agreement check against the spike's `--family auto` (KAGURA_DESIGN §6; a report, not a gate).

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer

@Suite("Kagura beta-playlist report (KAG.3, opt-in)")
struct KaguraBetaPlaylistReportTests {

    /// `TrackProfile.songArousal` per playlist position (KaguraRepertoireTests.build).
    static let songArousal: [Int: Double] = [
        1: 0.609, 2: 0.569, 3: 0.206, 4: 0.597, 5: -0.426, 6: 0.327, 7: 0.334, 8: 0.479, 9: -0.355, 10: 0.040,
    ]

    @Test("Safety net + dance pick on the beta captures")
    func report() throws {
        guard let root = ProcessInfo.processInfo.environment["KAGURA_BETA_SESSIONS"] else { return }
        let dirs = try FileManager.default.contentsOfDirectory(atPath: root).filter { $0.hasPrefix("fixturegen-") }.sorted()
        for name in dirs {
            let series = try SessionColumnSeries.load(directory: URL(fileURLWithPath: root).appendingPathComponent(name))
            func column(_ key: String) throws -> [Double] {
                try #require(series.floatSeries(key), "\(name): no \(key)").map { Double($0 ?? 0) }
            }
            let time = try column("time"), playback = try column("playback_time_s"), bass = try column("bass_att")
            let beats = Self.wraps(try column("beatPhase01"), time: time)
            let bars = Self.wraps(try column("barPhase01_permille").map { $0 / 1000 }, time: time)
            let beatsPerBar = Int(try column("beatsPerBar")[time.count / 2])
            guard let grid = KaguraGrid(beats: beats, downbeats: bars.count >= 2 ? bars : [],
                                        beatsPerBar: beatsPerBar, hasBarInformation: bars.count >= 2) else {
                print("[kagura-beta] \(name): no grid (\(beats.count) beats) — sways"); continue
            }
            let song = Int(name.dropFirst("fixturegen-b".count).prefix(2)) ?? 0
            let row = { (at: Double) in max(0, (time.lastIndex { $0 <= at }) ?? 0) }
            let run = try KaguraChoreographyHarness.run(
                seconds: time.last ?? 0, grid: grid, sequence: [], songArousal: Self.songArousal[song],
                bass: { bass[row($0)] }, playback: { playback[row($0)] })
            let frames = Double(max(run.dancing.count, 1))
            let danced = Double(run.dancing.filter { $0 }.count) / frames
            let held = Double(run.irregular.filter { $0 }.count) / frames
            let maxCV = (0..<beats.count).compactMap { KaguraSafetyNet.cv(of: grid, endingAt: $0) }.max() ?? 0
            let picks = zip(run.pickTimes, run.choreographer.chosenDances.suffix(run.pickTimes.count))
                .map { String(format: "%.2f:%@", $0.0, $0.1.rawValue) }.joined(separator: " ")
            print(String(format: "[kagura-beta] %@ max rolling CV %.3f | safety net held %.0f %% | danced %.0f %% | picks %@",
                         name, maxCV, held * 100, danced * 100, picks))
        }
    }

    /// `load_session`'s `wraps`: the time each phase column wraps to a new cycle, interpolated.
    static func wraps(_ phase: [Double], time: [Double]) -> [Double] {
        (1..<phase.count).compactMap { index in
            guard phase[index - 1] - phase[index] > 0.5 else { return nil }
            let a = phase[index - 1], b = phase[index] + 1
            return time[index - 1] + (1 - a) / (b - a) * (time[index] - time[index - 1])
        }
    }
}
