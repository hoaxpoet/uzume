// KaguraBetaPlaylistReportTests — the safety net and the dance pick on the 30 beta-playlist captures (KAG.3).
//
// A REPORT, opt-in: `KAGURA_BETA_SESSIONS=<dir of fixturegen-bNN_pXX captures>` (the spike's production-chain
// windows at 20 / 50 / 80 % of each `tools/data/beta_test_playlist.m3u` song; not in git). Each capture's
// grid is built from its own `beatPhase01` / `barPhase01_permille` wraps, exactly as the spike's
// `load_session` does, and the choreographer runs on the capture's playback clock and `bass_att`, with the
// song's `TrackProfile.songArousal`. Printed per capture: how much of it the safety net swayed (README §11
// is the spike's per-window verdict) and the dance picked at each clip change, with its time, for the
// agreement check against the spike's `--family auto` (KAGURA_DESIGN §6; a report, not a gate).

import DSP
import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Session

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

    // MARK: - KAG.5 energy table

    /// A v17 cache entry's fields the table reads (SongMoodBetaPlaylistTests' decode).
    private struct Entry: Decodable {
        let trackProfile: TrackProfile
        let decodedDuration: Double?
        let beatGrid: BeatGrid?
    }

    /// `tools/data/beta_test_playlist.m3u` order: (title, EXTINF seconds). FLAC entries carry no title, so
    /// cache entries are matched by duration.
    static let playlist: [(title: String, seconds: Double)] = [
        ("Dance Yrself Clean", 538), ("B.O.B.", 304), ("Superstition", 266), ("Smells Like Teen Spirit", 301),
        ("Penny Lane", 181), ("Take Five", 327), ("Pyramid Song", 289), ("Teardrop", 331),
        ("Moonlight I", 426), ("Warszawa", 384),
    ]

    /// The Charleston per Matt's call (2026-09-28, B): a song in its tempo band keeps it as one of its
    /// three whatever the energy; energy picks the other two. (Probe-local until task 5 ships it.)
    static func pickB(bpm: Double, level: Int, library: KaguraClipLibrary) -> [KaguraDance] {
        let energy = Double(level - 1) / 9
        let others = KaguraRepertoire.dances.filter { !KaguraRepertoire.fastSongDances.contains($0) }
        let eligible = KaguraRepertoire.pick(bpm: bpm, energy: energy, library: library, count: 5).contains(.charleston)
        return eligible
            ? KaguraRepertoire.pick(bpm: bpm, energy: energy, library: library, count: 2, from: others) + [.charleston]
            : KaguraRepertoire.pick(bpm: bpm, energy: energy, library: library, from: others)
    }

    /// Task 1 (KAG.5): each beta song's energy sections, the repertoire and rest per section under the
    /// section rule and the per-song-typical rule, and each dance's share of bars over the playlist under
    /// the current (arousal) rule and both new rules. Report-only. `KAGURA_ENERGY_TABLE=1`; the cache is
    /// `KAGURA_ENERGY_CACHE` or the app's `~/Library/Application Support/Uzume/StemCache`.
    ///
    /// Bar shares assume the bar pick splits each repertoire's bars in thirds — it ranks each bar among
    /// the song's bars, so each tercile holds a third (KAG.3 M7: calm 65 / middle 60 / vigorous 65 of 190).
    /// Safety-net and silence sways are not modelled.
    @Test("KAG.5 energy table (opt-in)")
    func energyTable() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["KAGURA_ENERGY_TABLE"] == "1" else { return }
        let dir = env["KAGURA_ENERGY_CACHE"]
            ?? NSHomeDirectory() + "/Library/Application Support/Uzume/StemCache"
        let files = FileManager.default.enumerator(atPath: dir)?.compactMap { $0 as? String }
            .filter { $0.hasSuffix("metadata.json") } ?? []
        let entries = try files.map {
            try JSONDecoder().decode(Entry.self, from: Data(contentsOf: URL(fileURLWithPath: dir + "/" + $0)))
        }.filter { $0.trackProfile.energyCurve != nil }
        let library = try KaguraClipLibrary.shared()
        var bars: [String: [KaguraDance: Double]] = [:]
        func credit(_ rule: String, _ repertoire: [KaguraDance], _ count: Double) {
            for dance in repertoire { bars[rule, default: [:]][dance, default: 0] += count / Double(repertoire.count) }
        }
        let names = { (rep: [KaguraDance]) in rep.map(\.rawValue).joined(separator: "/") }
        for song in Self.playlist {
            let entry = try #require(entries.first { abs(($0.decodedDuration ?? 0) - song.seconds) < 2 },
                                     "no cached curve for \(song.title)")
            let duration = try #require(entry.decodedDuration)
            let beatGrid = try #require(entry.beatGrid)
            let grid = try #require(KaguraGrid(beats: beatGrid.beats, downbeats: beatGrid.downbeats,
                                               beatsPerBar: beatGrid.beatsPerBar,
                                               hasBarInformation: beatGrid.hasBarInformation))
            let bpm = 60 / grid.beatPeriod
            let barSeconds = KaguraChoreographer.barSeconds(grid)
            let profile = entry.trackProfile
            let curve = try #require(profile.wholeTrackCurve(trackDuration: duration))
            let readout = try #require(curve.readout())
            // Current rule: the mood classifier's arousal against energyReference.
            let arousal = Double(profile.mood.arousal)
            let arousalEnergy = KaguraRepertoire.songEnergy(arousal: arousal)
            let current = KaguraRepertoire.pick(bpm: bpm, energy: arousalEnergy, library: library)
            let currentRest = arousalEnergy < 1.0 / 3 ? "ballet" : "sway"
            credit("current", current, duration / barSeconds)
            // Per-song typical.
            let typicalA = KaguraRepertoire.pick(bpm: bpm, energy: Double(readout.typical - 1) / 9, library: library)
            let typicalB = Self.pickB(bpm: bpm, level: readout.typical, library: library)
            let typicalRest = readout.typical <= 3 ? "ballet" : "sway"
            credit("typical", typicalB, duration / barSeconds)
            print(String(format: "[kagura-energy] %@ | grid %.1f BPM (stored %.1f) | energy %d → %d, typical %d | arousal %.3f → %.2f",
                         song.title, bpm, beatGrid.bpm, readout.low, readout.high, readout.typical, arousal, arousalEnergy))
            print("[kagura-energy]   current (arousal): \(names(current)), \(currentRest)")
            print("[kagura-energy]   typical: A \(names(typicalA)) | B \(names(typicalB)), \(typicalRest)")
            // Which level earns which repertoire at this tempo: where the twist comes in.
            let sweep = (1...10).map { "\($0):" + names(Self.pickB(bpm: bpm, level: $0, library: library)) }
            print("[kagura-energy]   by level: \(sweep.joined(separator: " "))")
            // Sections: cut at the NRG.4 energy changes.
            let edges = [0] + profile.energyChanges(trackDuration: duration) + [duration]
            for (start, end) in zip(edges, edges.dropFirst()) {
                let level = curve.level(from: start, to: end)
                let rep = level.map { Self.pickB(bpm: bpm, level: $0, library: library) }
                    ?? KaguraRepertoire.pick(bpm: bpm, energy: KaguraRepertoire.unknownEnergy, library: library)
                let rest = (level ?? 10) <= 3 ? "ballet" : "sway"
                credit("section", rep, (end - start) / barSeconds)
                // Alternative read: the section's loud end (its 90th-percentile level, the readout's "high").
                let timed = curve.timedSectionLevels()
                let inSection = timed[min(Int(start), timed.count)..<min(Int(end.rounded(.up)), timed.count)]
                    .compactMap { $0 }.sorted()
                let high = inSection.isEmpty ? nil : inSection[Int(0.9 * Double(inSection.count - 1))]
                let highRep = high.map { Self.pickB(bpm: bpm, level: $0, library: library) } ?? rep
                credit("section-high", highRep, (end - start) / barSeconds)
                print(String(format: "[kagura-energy]   section %d:%02d–%d:%02d level %@: %@, %@ | high %@: %@, %@",
                             Int(start) / 60, Int(start) % 60, Int(end) / 60, Int(end) % 60,
                             level.map(String.init) ?? "nil", names(rep), rest,
                             high.map(String.init) ?? "nil", names(highRep), (high ?? 10) <= 3 ? "ballet" : "sway"))
            }
        }
        for rule in ["current", "typical", "section", "section-high"] {
            let shares = bars[rule] ?? [:]
            let total = shares.values.reduce(0, +)
            let line = KaguraRepertoire.dances.map { dance in
                String(format: "%@ %.0f%%", dance.rawValue, 100 * (shares[dance] ?? 0) / max(total, 1))
            }.joined(separator: ", ")
            print(String(format: "[kagura-energy] bar share, %@ rule (%.0f bars): %@", rule, total, line))
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
