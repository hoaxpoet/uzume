// PR.15 — give BarLineEstimator the input its own documentation specifies.
//
// `BarLineEstimator.estimate`'s doc comment: "beats: … Typically `BeatGrid.beats` from a
// full-track decode (`BeatThisTiledInference`), NOT a 30 s window."
//
// In production it has never had that. `applyBarLineEstimate` receives `grid.beats` from
// the clamped predict, so FT.3's calibration, FT.4's A/B, FT.4.1's split and PR.3d's
// adoption attempt ALL fed it ~40–60 beats when it was designed for ~300–700. The four
// "failed attempts" on the bar problem share that confound, and PR.12 removed it.
//
// The estimator scores four meter hypotheses against a permutation null. Null-corrected
// margin grows with the number of observations, so more beats should mean higher margins
// and fewer declines — the decline rate was never a property of the music alone.
//
//   UZUME_BARLINE_WHOLETRACK=1 swift test --package-path UzumeEngine --filter BarLineWholeTrackProbe
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import Session

@Suite("BarLineWholeTrackProbe")
struct BarLineWholeTrackProbe {

    private struct GroundTruth: Decodable {
        let meterFromTaps: Int?
        let status: String?
        enum CodingKeys: String, CodingKey {
            case meterFromTaps = "meter_from_taps"
            case status
        }
    }

    /// Production-faithful decode: native rate, manual channel average.
    private static func decodeMono(url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return ([], 0) }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return ([], 0) }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        if channelCount == 1 {
            return (Array(UnsafeBufferPointer(start: channels[0], count: count)), format.sampleRate)
        }
        var mono = [Float](repeating: 0, count: count)
        let scale = 1.0 / Float(channelCount)
        for channel in 0..<channelCount {
            let ptr = UnsafeBufferPointer(start: channels[channel], count: count)
            for i in 0..<count { mono[i] += ptr[i] * scale }
        }
        return (mono, format.sampleRate)
    }



    /// PR.16 task 1 — the per-window margin distribution, LABELLED correct/incorrect
    /// against the tapped meter, so `declineThreshold` can be re-derived for windowed
    /// scoring the way FT.3 derived it for global scoring: the objective
    /// (correct kept − incorrect admitted) plateaus over an interval containing no
    /// observation, and the threshold is that interval's midpoint.
    ///
    /// The shipping 1.54 was fitted to ONE-ANSWER-PER-TRACK margins and is the wrong
    /// operating point here — PR.15 measured bleed 1.179, bohemian_rhapsody 1.419 and
    /// solsbury_hill 1.412 sitting just under it with no answer at all.
    @Test("per-window margin distribution, labelled",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_THRESHOLD"] == "1"))
    func thresholdDerivation() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)
        let beatsPerWindow = 80

        // (margin, isCorrect?) — nil isCorrect = track has no tapped meter, so the window
        // is neither correct nor incorrect and only informs the "never answer here" side.
        var samples: [(margin: Double, correct: Bool?)] = []

        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard grid.beats.count > beatsPerWindow else { continue }
            var start = 0
            while start + beatsPerWindow <= grid.beats.count {
                let slice = Array(grid.beats[start..<(start + beatsPerWindow)])
                let est = BarLineEstimator.estimate(
                    beats: slice, audio: audio, sampleRate: rate, options: opts)
                let correct: Bool? = gt?.meterFromTaps.map { est.beatsPerBar == $0 }
                samples.append((est.margin, correct))
                start += beatsPerWindow
            }
        }

        // Sweep every observed margin as a candidate threshold.
        let candidates = samples.map(\.margin).sorted()
        print("\n  Per-window threshold sweep — \(samples.count) windows\n")
        print("  threshold   kept  correct  INCORRECT  objective")
        var best: (thr: Double, objective: Int) = (0, Int.min)
        for cand in candidates {
            let kept = samples.filter { $0.margin >= cand }
            let correct = kept.filter { $0.correct == true }.count
            let incorrect = kept.filter { $0.correct == false }.count
            let objective = correct - incorrect
            if objective > best.objective { best = (cand, objective) }
        }
        // Print the interesting band around the optimum.
        for cand in candidates where abs(cand - best.thr) < 1.0 {
            let kept = samples.filter { $0.margin >= cand }
            let correct = kept.filter { $0.correct == true }.count
            let incorrect = kept.filter { $0.correct == false }.count
            print(String(format: "  %9.3f  %5d  %7d  %9d  %+9d",
                         cand, kept.count, correct, incorrect, correct - incorrect))
        }
        print("""

          best objective \(best.objective) first reached at margin \(String(format: "%.3f", best.thr))
          shipping threshold 1.54 keeps: \
        \(samples.filter { $0.margin >= 1.54 }.filter { $0.correct == true }.count) correct, \
        \(samples.filter { $0.margin >= 1.54 }.filter { $0.correct == false }.count) incorrect
        """)
    }

    /// Is bar structure LOCAL? Score the estimator over successive ~40 s windows of the
    /// whole-track beat sequence. If per-window margins are strong where the single global
    /// margin is weak, the bar is a local property and one answer per track is the wrong
    /// output shape — the same lesson tempo taught (record it over the duration, do not
    /// average it into one number).
    @Test("bar line per window vs one global answer",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_WINDOWED"] == "1"))
    func windowed() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)
        let thr = BarLineEstimator.declineThreshold
        let beatsPerWindow = 80          // ~40 s at 120 BPM

        print("\n  Per-window bar line (\(beatsPerWindow) beats/window). threshold = \(thr)\n")
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard grid.beats.count > beatsPerWindow else { continue }

            let global = BarLineEstimator.estimate(
                beats: grid.beats, audio: audio, sampleRate: rate, options: opts)
            var answers: [Int] = []
            var margins: [Double] = []
            var start = 0
            while start + beatsPerWindow <= grid.beats.count {
                let slice = Array(grid.beats[start..<(start + beatsPerWindow)])
                let est = BarLineEstimator.estimate(
                    beats: slice, audio: audio, sampleRate: rate, options: opts)
                margins.append(est.margin)
                if est.margin >= thr, let bpb = est.beatsPerBar { answers.append(bpb) }
                start += beatsPerWindow
            }
            var hist: [Int: Int] = [:]
            for a in answers { hist[a, default: 0] += 1 }
            let windows = max(margins.count, 1)
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            print("  \(name)\(pad) tapped \(gt?.meterFromTaps.map(String.init) ?? "-")"
                  + "  global \(String(format: "%6.3f", global.margin))"
                  + " -> \(global.margin >= thr ? String(global.beatsPerBar ?? 0) : "decline")"
                  + "  |  windows \(windows), answered \(answers.count)"
                  + ", max margin \(String(format: "%6.3f", margins.max() ?? 0))"
                  + ", answers \(hist.sorted { $0.key < $1.key })")
        }
    }

    @Test("bar line: 30 s beats vs whole-track beats",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_WHOLETRACK"] == "1"))
    func probe() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)
        let thr = BarLineEstimator.declineThreshold

        print("""

          BarLineEstimator with the input it was designed for. threshold = \(thr)

          track                tapped   30s: beats  margin  answer |  whole: beats  margin  answer
        """)
        var answered30 = 0, answeredWhole = 0, correct30 = 0, correctWhole = 0, total = 0
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }

            let clampCount = min(audio.count, Int(30 * rate))
            let g30 = analyzer.analyzeBeatGrid(
                samples: Array(audio[0..<clampCount]), sampleRate: rate, wholeTrack: false)
            let gWhole = analyzer.analyzeBeatGrid(
                samples: audio, sampleRate: rate, wholeTrack: true)
            let e30 = BarLineEstimator.estimate(
                beats: g30.beats, audio: audio, sampleRate: rate, options: opts)
            let eWhole = BarLineEstimator.estimate(
                beats: gWhole.beats, audio: audio, sampleRate: rate, options: opts)

            func verdict(_ e: BarLineEstimate) -> String {
                e.margin >= thr ? "\(e.beatsPerBar.map(String.init) ?? "?")" : "decline"
            }
            total += 1
            if e30.margin >= thr { answered30 += 1 }
            if eWhole.margin >= thr { answeredWhole += 1 }
            if let tapped = gt?.meterFromTaps {
                if e30.margin >= thr, e30.beatsPerBar == tapped { correct30 += 1 }
                if eWhole.margin >= thr, eWhole.beatsPerBar == tapped { correctWhole += 1 }
            }
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            let tapped = gt?.meterFromTaps.map(String.init) ?? "-"
            print("  \(name)\(pad) tapped \(tapped)"
                  + "  |  30s: \(g30.beats.count) beats "
                  + "margin \(String(format: "%7.3f", e30.margin)) -> \(verdict(e30))"
                  + "  |  whole: \(gWhole.beats.count) beats "
                  + "margin \(String(format: "%7.3f", eWhole.margin)) -> \(verdict(eWhole))")
        }
        print("""

          answered:  30 s \(answered30)/\(total)   whole-track \(answeredWhole)/\(total)
          correct (vs tapped meter, where one exists):  30 s \(correct30)   whole-track \(correctWhole)
        """)
    }

    /// PR.17 — the SHIPPED `estimateWindowed`, not a probe reimplementation, scored
    /// against the tapped meter on every ground-truthed fixture.
    ///
    /// PR.15's `windowed()` above measured the idea with its own loop, which drops the
    /// track's tail and re-resamples per window. Production does neither. This runs the
    /// real function so the number that gets quoted is the number that ships.
    ///
    /// Run with the production default OFF so `global` and the grid's own meter are the
    /// incumbent behaviour, not this change reflected back:
    ///
    ///     UZUME_BARLINE_PROD=1 UZUME_BARLINE_LOCAL=0 \
    ///       swift test --package-path UzumeEngine --filter BarLineWholeTrackProbe
    @Test("PR.17 — shipped estimateWindowed vs tapped meter",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_BARLINE_PROD"] == "1"))
    func shippedWindowed() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let gtDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/beatbench/groundtruth")
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let opts = BarLineEstimator.Options(resampleToReferenceRate: true)

        print("\n  track                tapped  global   windowed ans/tot  cover  answers")
        var correct = 0, incorrect = 0, silentWindows = 0, unscoreable = 0
        for gtURL in (try FileManager.default.contentsOfDirectory(
                        at: gtDir, includingPropertiesForKeys: nil)).sorted(by: {
                            $0.lastPathComponent < $1.lastPathComponent }) {
            guard gtURL.lastPathComponent.hasSuffix(".groundtruth.json") else { continue }
            let name = gtURL.lastPathComponent.replacingOccurrences(of: ".groundtruth.json", with: "")
            let gt = try? JSONDecoder().decode(GroundTruth.self, from: Data(contentsOf: gtURL))
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard !grid.beats.isEmpty else { continue }
            let global = BarLineEstimator.estimate(
                beats: grid.beats, audio: audio, sampleRate: rate, options: opts)
            let windowed = BarLineEstimator.estimateWindowed(
                beats: grid.beats, audio: audio, sampleRate: rate, options: opts)
            for estimate in windowed.estimates {
                guard let meter = estimate.beatsPerBar else { silentWindows += 1; continue }
                // No tapped meter (clair_de_lune, pyramid_song, yyz) means the window
                // cannot be scored EITHER way. Counting those as incorrect would be a
                // false failure — yyz's four 4s are very likely right, its ground truth
                // just records "no clean meter; unresolved".
                guard let tapped = gt?.meterFromTaps else { unscoreable += 1; continue }
                if meter == tapped { correct += 1 } else { incorrect += 1 }
            }
            let answers = windowed.estimates.compactMap(\.beatsPerBar).map(String.init)
                .joined(separator: ",")
            let pad = String(repeating: " ", count: max(0, 20 - name.count))
            print("  \(name)\(pad) "
                  + String(format: "%5@   %5@   %8@  %5.0f%%  ",
                           (gt?.meterFromTaps.map(String.init) ?? "-") as NSString,
                           (global.beatsPerBar.map(String.init) ?? "-") as NSString,
                           "\(windowed.windowsAnswered)/\(windowed.windowCount)" as NSString,
                           windowed.coverage * 100)
                  + (answers.isEmpty ? "-" : answers))
        }
        print("\n  windows: \(correct) correct, \(incorrect) incorrect, "
              + "\(unscoreable) unscoreable (no tapped meter), \(silentWindows) declined")
    }

    /// BUG-118 — what does tiling do to the DOWNBEAT activation, as opposed to the beats?
    ///
    /// The five-suite table's one span-fair regression is billie_jean, whose reference is
    /// full-track (`extended_by: librosa`): beat F IMPROVES 0.97 -> 0.99 while downbeat F
    /// collapses 0.90 -> 0.37. Beats survive tiling; downbeats do not. This measures the
    /// grid either side to say how.
    ///
    /// UZUME_DB_TILE_PROBE=1 swift test --package-path UzumeEngine --filter BarLineWholeTrackProbe
    @Test("tiling: beats vs downbeats",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_DB_TILE_PROBE"] == "1"))
    func tilingDownbeats() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        let names = ["billie_jean", "bleed", "take_five", "solsbury_hill", "money"]
        print("\n  track            arm      beats  downbeats  db/beat  medianBarSec  meter")
        for name in names {
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            for whole in [false, true] {
                let grid = analyzer.analyzeBeatGrid(
                    samples: audio, sampleRate: rate, wholeTrack: whole)
                // Restrict to the first 30 s so BOTH arms describe the same music.
                let beats = grid.beats.filter { $0 <= 30.0 }
                let downs = grid.downbeats.filter { $0 <= 30.0 }
                let gaps = (0..<max(downs.count - 1, 0)).map { downs[$0 + 1] - downs[$0] }
                let medianBar = gaps.isEmpty ? 0 : gaps.sorted()[gaps.count / 2]
                let ratio = beats.isEmpty ? 0 : Double(downs.count) / Double(beats.count)
                let pad = String(repeating: " ", count: max(0, 16 - name.count))
                print(String(format: "  %@%@%@  %5d  %9d  %7.3f  %12.3f  %5d",
                             name, pad, whole ? "whole " : "clamp ",
                             beats.count, downs.count, ratio, medianBar, grid.beatsPerBar))
            }
        }
    }

    /// BUG-118 — WHERE does the whole-track grid degrade?
    ///
    /// Span-matched over the first 30 s it equals the clamp. Over the full track it does
    /// not: bleed's beat F is 0.76 and billie_jean's downbeat F falls 0.90 -> 0.37 against
    /// the same full-track reference. If quality falls with time-into-track, the defect is
    /// in what the resolver assumes globally, not in the tiling of activations.
    ///
    /// Beat spacing regularity is the proxy: |IOI - local median| in each tenth of the
    /// track, plus the downbeat interval's coefficient of variation per tenth.
    ///
    /// UZUME_DECAY_PROBE=1 swift test --package-path UzumeEngine --filter BarLineWholeTrackProbe
    @Test("does the whole-track grid degrade with time into the track",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_DECAY_PROBE"] == "1"))
    func degradesWithTime() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)
        for name in ["billie_jean", "bleed", "take_five", "solsbury_hill"] {
            var audioURL: URL?
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { audioURL = u; break }
            }
            guard let audioURL, let (audio, rate) = try? Self.decodeMono(url: audioURL),
                  !audio.isEmpty else { continue }
            let grid = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            guard grid.beats.count > 100 else { continue }
            let span = (grid.beats.last ?? 0) - (grid.beats.first ?? 0)
            let iois = (0..<(grid.beats.count - 1)).map { grid.beats[$0 + 1] - grid.beats[$0] }
            let median = iois.sorted()[iois.count / 2]
            var buckets = [[Double]](repeating: [], count: 10)
            for (i, ioi) in iois.enumerated() {
                let t = (grid.beats[i] - (grid.beats.first ?? 0)) / max(span, 1e-9)
                buckets[min(9, max(0, Int(t * 10)))].append(abs(ioi - median) * 1000)
            }
            let line = buckets.map { b -> String in
                b.isEmpty ? "  -  " : String(format: "%5.0f", b.reduce(0, +) / Double(b.count))
            }.joined(separator: " ")
            let pad = String(repeating: " ", count: max(0, 15 - name.count))
            print("  \(name)\(pad)|IOI-med| ms by tenth:  \(line)")
        }
    }

    /// Plain 4/4, strong pulse — Matt, 2026-09-08: *"Can you test on tracks that are not
    /// strange time signatures or that have tempo changes within the track?"*
    ///
    /// The benchmark is deliberately stacked with hard cases (odd meters, rubato, mid-track
    /// tempo changes), so it says little about the material most listening actually is. This
    /// runs the suite-1 fixtures plus whatever album directory is pointed at, and reports the
    /// two things that decide whether a preset can sync: does the grid find a METER, and how
    /// much of the track does it COVER.
    ///
    /// UZUME_44_PROBE=1 [UZUME_44_DIR="<album>"] swift test --filter BarLineWholeTrackProbe
    @Test("plain 4/4: meter and coverage, clamped vs whole-track",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_44_PROBE"] == "1"))
    func plainFourFour() throws {
        let fixtures = URL(fileURLWithPath: (NSHomeDirectory() as NSString)
            .appendingPathComponent("uzume_beatbench_fixtures"))
        let device = try #require(MTLCreateSystemDefaultDevice())
        let analyzer = try DefaultBeatGridAnalyzer(device: device)

        var urls: [URL] = []
        for name in ["billie_jean", "stayin_alive", "superstition", "around_the_world",
                     "love_rehab", "there_there", "giorgio_by_moroder"] {
            for ext in ["mp3", "wav", "m4a", "flac"] {
                let u = fixtures.appendingPathComponent("\(name).\(ext)")
                if FileManager.default.fileExists(atPath: u.path) { urls.append(u); break }
            }
        }
        if let dir = ProcessInfo.processInfo.environment["UZUME_44_DIR"], !dir.isEmpty {
            let extra = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)) ?? []
            urls += extra.filter { ["flac", "mp3", "m4a", "wav"].contains($0.pathExtension.lowercased())
                                   && !$0.lastPathComponent.hasPrefix("._") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }

        print("\n  track                              len    CLAMPED           WHOLE-TRACK")
        print("                                            meter  cover     meter  cover")
        var clampMeter4 = 0, wholeMeter4 = 0, total = 0
        var clampCover = 0.0, wholeCover = 0.0
        for url in urls {
            guard let (audio, rate) = try? Self.decodeMono(url: url), !audio.isEmpty else { continue }
            let len = Double(audio.count) / rate
            let clamped = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: false)
            let whole = analyzer.analyzeBeatGrid(samples: audio, sampleRate: rate, wholeTrack: true)
            func cover(_ g: BeatGrid) -> Double {
                guard let a = g.beats.first, let b = g.beats.last, len > 0 else { return 0 }
                return (b - a) / len * 100
            }
            total += 1
            if clamped.beatsPerBar == 4 { clampMeter4 += 1 }
            if whole.beatsPerBar == 4 { wholeMeter4 += 1 }
            clampCover += cover(clamped); wholeCover += cover(whole)
            let name = String(url.deletingPathExtension().lastPathComponent.prefix(32))
            let pad = String(repeating: " ", count: max(0, 34 - name.count))
            print(String(format: "  %@%@%5.0fs   %2d   %5.1f%%     %2d   %5.1f%%",
                         name, pad, len, clamped.beatsPerBar, cover(clamped),
                         whole.beatsPerBar, cover(whole)))
        }
        guard total > 0 else { return }
        print(String(format: "\n  meter == 4:  clamped %d/%d,  whole-track %d/%d",
                     clampMeter4, total, wholeMeter4, total))
        print(String(format: "  mean coverage: clamped %.1f %%,  whole-track %.1f %%",
                     clampCover / Double(total), wholeCover / Double(total)))
    }
}
