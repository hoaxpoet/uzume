// EnergyScaleTests — NRG.2 (D-259). The 1–10 level is a library decile of each second's loudness +
// activity rank, and a song reads as one level or a low → high range of its sections.

import Foundation
import Testing
@testable import Session

@Suite("NRG.2 energy scale and readout")
struct EnergyScaleTests {

    private let scale = EnergyScale.library

    /// A curve that holds the given library quantile (0…100) of both loudness and activity.
    private func curve(at percentiles: [Int]) -> EnergyCurve {
        EnergyCurve(hopSeconds: 1,
                    loudnessDB: percentiles.map { scale.loudnessQuantiles[$0] },
                    activity: percentiles.map { scale.activityQuantiles[$0] })
    }

    @Test("the generated Swift table matches tools/data/energy_scale.json")
    func tableMatchesJSON() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let url = root.appendingPathComponent("tools/data/energy_scale.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }   // outside a checkout
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for (key, table) in [("loud_q", scale.loudnessQuantiles), ("act_q", scale.activityQuantiles),
                             ("score_q", scale.scoreDeciles)] {
            let expected = try #require(json[key] as? [Double]).map(Float.init)
            #expect(expected.count == table.count, "\(key) length")
            #expect(zip(expected, table).allSatisfy { abs($0 - $1) <= 1e-4 * max(1, abs($0)) },
                    "\(key) drifted from the JSON — regenerate with tools/energy_calibration.py --swift")
        }
    }

    @Test("a quiet minute then a loud minute reads as a low → high range")
    func quietThenLoudIsARange() throws {
        let readout = try #require(curve(at: Array(repeating: 5, count: 60) + Array(repeating: 97, count: 60)).readout())
        #expect(!readout.isSteady)
        #expect(readout.low <= 2 && readout.high >= 9, "read \(readout.low) → \(readout.high)")
    }

    @Test("a steady song reads one level, near the middle at the library median")
    func steadyIsOneLevel() throws {
        let readout = try #require(curve(at: Array(repeating: 50, count: 120)).readout())
        #expect(readout.isSteady)
        #expect((5...6).contains(readout.typical), "median library second read level \(readout.typical)")
    }

    @Test("digital silence at the edges does not count")
    func silenceIsIgnored() throws {
        var loud = Array(repeating: scale.loudnessQuantiles[97], count: 60)
        var act = Array(repeating: scale.activityQuantiles[97], count: 60)
        loud.insert(contentsOf: Array(repeating: -120, count: 30), at: 0)
        act.insert(contentsOf: Array(repeating: 0, count: 30), at: 0)
        let readout = try #require(EnergyCurve(hopSeconds: 1, loudnessDB: loud, activity: act).readout())
        #expect(readout.isSteady && readout.typical >= 9, "silence pulled the readout to \(readout.low) → \(readout.high)")
    }
}
