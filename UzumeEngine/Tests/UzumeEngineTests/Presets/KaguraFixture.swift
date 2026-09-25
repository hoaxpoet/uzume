// KaguraFixture — the real-music clock and grid for every Kagura test (KAG.2).
//
// FA #27: the clock and grid come from the committed route-coverage captures (production chain,
// ~43 Hz rows) and the matching Beat This! reference JSONs, not hand-authored envelopes.
//   - `playback_time_s` steps once per capture row (0.0232 s), so a 60 Hz renderer sees it hold
//     for one or two frames and then jump — the jitter `KaguraBeatClock` has to smooth.
//   - `time` is when that row was produced, the moment the app would have pushed it.
//   - `beatPhase01` is the stepped feature a dancer must NOT be driven from (BUG-096).

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer

// MARK: - KaguraFixture

struct KaguraFixture {

    static let tracks = ["love_rehab", "so_what", "there_there"]

    let name: String
    /// Capture row times (s) — when each playback reading was published.
    let rowTime: [Double]
    /// The capture's playback clock (s), one reading per row.
    let playback: [Double]
    /// The capture's stepped beat phase, one per row.
    let beatPhase: [Double]
    /// Beat This! reference beats and downbeats (s), and its meter estimate.
    let beats: [Double]
    let downbeats: [Double]
    let beatsPerBar: Int

    static func load(_ track: String) throws -> KaguraFixture {
        let routes = try #require(Bundle.module.url(forResource: "route_coverage", withExtension: nil),
                                  "route_coverage fixtures not bundled — run Scripts/link_fixtures.sh")
        let series = try SessionColumnSeries.load(directory: routes.appendingPathComponent(track))
        func column(_ name: String) throws -> [Double] {
            try #require(series.floatSeries(name), "\(track): no \(name) column").map { Double($0 ?? 0) }
        }
        let refURL = try #require(
            Bundle.module.url(forResource: "beat_this_reference", withExtension: nil)?
                .appendingPathComponent("\(track)_reference.json"))
        let ref = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: refURL))
        return KaguraFixture(
            name: track,
            rowTime: try column("time"),
            playback: try column("playback_time_s"),
            beatPhase: try column("beatPhase01"),
            beats: ref.beatsSeconds,
            downbeats: ref.downbeatsSeconds,
            beatsPerBar: ref.beatsPerBarEstimate)
    }

    private struct Reference: Decodable {
        let beatsSeconds: [Double]
        let downbeatsSeconds: [Double]
        let beatsPerBarEstimate: Int
        enum CodingKeys: String, CodingKey {
            case beatsSeconds = "beats_seconds"
            case downbeatsSeconds = "downbeats_seconds"
            case beatsPerBarEstimate = "beats_per_bar_estimate"
        }
    }

    /// The reference grid, optionally shifted by `shiftBeats` of the median beat period (the decoy).
    func grid(shiftBeats: Double = 0) throws -> KaguraGrid {
        let base = try #require(KaguraGrid(beats: beats, downbeats: downbeats,
                                           beatsPerBar: beatsPerBar, hasBarInformation: beatsPerBar > 1))
        let shift = shiftBeats * base.beatPeriod
        return try #require(KaguraGrid(beats: beats.map { $0 + shift }, downbeats: downbeats.map { $0 + shift },
                                       beatsPerBar: beatsPerBar, hasBarInformation: beatsPerBar > 1))
    }

    /// Index of the last capture row published at or before `time` (nil before the first).
    func row(at time: Double) -> Int? {
        var lo = 0, hi = rowTime.count - 1
        guard hi >= 0, rowTime[0] <= time else { return nil }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if rowTime[mid] <= time { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    var duration: Double { rowTime.last ?? 0 }

    /// The capture's playback clock interpolated to a render instant — the music's true position.
    func truePlayback(at time: Double) -> Double? {
        guard let row = row(at: time), row + 1 < rowTime.count else { return nil }
        let frac = (time - rowTime[row]) / (rowTime[row + 1] - rowTime[row])
        return playback[row] + frac * (playback[row + 1] - playback[row])
    }
}
