// BUG-134 corpus probe — env-gated, never in the default run.
//
//   OCTAVE_CORPUS=1 swift test --package-path UzumeEngine --filter OctaveCorpusProbe
//
// Reads the real cached BeatGrids from the local stem cache and reports what
// `octaveUnified()` would change. This is the evidence substrate for the fix; the
// deterministic behaviour is pinned by BeatGridOctaveConsistencyTests.

import Testing
import Foundation
@testable import DSP

@Suite("OctaveCorpusProbe", .serialized)
struct BeatGridOctaveCorpusProbe {

    @Test("Report octave consistency across the cached corpus")
    func corpusReport() throws {
        guard ProcessInfo.processInfo.environment["OCTAVE_CORPUS"] == "1" else { return }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Uzume/StemCache/sha256")
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }

        var total = 0, bimodal = 0, changed = 0, gapsFilled = 0, unifiedSlow = 0, untouched = 0
        for case let url as URL in en where url.lastPathComponent == "metadata.json" {
            guard let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let gd = obj["beatGrid"] as? [String: Any],
                  let beats = gd["beats"] as? [Double], beats.count >= 40 else { continue }
            let bpm = (gd["bpm"] as? Double) ?? 0
            let g = BeatGrid(beats: beats, downbeats: (gd["downbeats"] as? [Double]) ?? [],
                             bpm: bpm, beatsPerBar: (gd["beatsPerBar"] as? Int) ?? 4,
                             barConfidence: 1, frameRate: 50, frameCount: 0)
            total += 1
            let p = g.octaveProfile()
            if p.isBimodal { bimodal += 1 }
            let fixed = g.octaveUnified()
            if fixed.beats == g.beats { untouched += 1; continue }
            changed += 1
            if fixed.beats.count > g.beats.count { gapsFilled += fixed.beats.count - g.beats.count }
            if fixed.beats.count < g.beats.count { unifiedSlow += 1 }

            // Irregularity: fraction of intervals more than 1.5x their own local median.
            func irregularity(_ b: [Double]) -> Double {
                let iv = zip(b, b.dropFirst()).map { $1 - $0 }
                guard iv.count > 20 else { return 0 }
                let s = iv.sorted(); let m = s[s.count / 2]
                return Double(iv.filter { $0 > m * 1.5 }.count) / Double(iv.count)
            }
            let before = irregularity(g.beats), after = irregularity(fixed.beats)
            let title = ((obj["metadata"] as? [String: Any])?["title"] as? String) ?? "?"
            print(String(format: "  %-30@ bpm %6.1f→%6.1f  beats %4d→%4d  irregular %4.1f%%→%4.1f%%",
                         title as NSString, g.bpm, fixed.bpm,
                         g.beats.count, fixed.beats.count, before * 100, after * 100))
        }
        print("""

          [octave-corpus] \(total) cached grids
            bimodal (two populated octaves): \(bimodal)
            changed: \(changed)   untouched: \(untouched)
            dropped beats filled: \(gapsFilled)   grids unified to slow octave: \(unifiedSlow)
          """)
        #expect(total > 0, "no cached grids found")
        #expect(untouched > 0, "a correction that rewrites EVERY grid is too aggressive")
    }
}
