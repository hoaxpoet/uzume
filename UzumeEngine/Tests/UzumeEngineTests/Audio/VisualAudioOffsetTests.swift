// VisualAudioOffsetTests — BUG-087 follow-on: turn "sync is a little loose" into a NUMBER.
//
// Matt on the streaming build: *"audio sync is still a little loose, not perfectly synced."*
// The rate ceiling is gone on that path — the driver bus measures ~59 Hz against a 59.9 fps
// render — so what remains is not quantisation but OFFSET: the visual arrives late.
//
// ★ WHAT MAKES THIS MEASURABLE RATHER THAN GUESSWORK IS A SHARED CLOCK. `session.log` records
//   `raw tap capture started ... wallclock=<t0>`, and every `features.csv` row carries the same
//   `wallclock_s`. So a sample index in `raw_tap.wav` and a feature row can be placed on ONE
//   timeline exactly, with no estimated offset — which is the thing that makes CS.1-style
//   onset pairing necessary elsewhere and unnecessary here.
//
// ⚠ WHAT THIS MEASURES, precisely: the delay from audio being CAPTURED AT THE TAP to the
//   derived feature appearing in a rendered row. It does NOT include output-device buffering
//   between the tap point and the speaker, nor display presentation latency. It is a lower
//   bound on what the eye-vs-ear gap is, and the part this codebase can act on.
//
// Usage:
//   OFFSET_SESSION=~/Documents/uzume_sessions/<dir> \
//   swift test --package-path UzumeEngine --filter VisualAudioOffset
import Testing
import Foundation
import AVFoundation

@Suite("VisualAudioOffset (BUG-087)")
struct VisualAudioOffsetTests {

    static let hop = 0.005          // 5 ms analysis grid — 1/10th of the finest lag we care about
    static let window = 1024
    static let maxLagMs = 400.0

    @Test("Measure tap-to-feature delay on a real session (OFFSET_SESSION=<dir>)")
    func measureOffset() throws {
        guard let dir = ProcessInfo.processInfo.environment["OFFSET_SESSION"] else {
            print("[offset] set OFFSET_SESSION=<session dir>")
            return
        }
        let base = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)

        // 1. The shared clock origin, straight from the log.
        let log = try String(contentsOf: base.appendingPathComponent("session.log"), encoding: .utf8)
        guard let tapT0 = Self.tapStartWallclock(log) else {
            Issue.record("no 'raw tap capture started ... wallclock=' line — cannot align clocks")
            return
        }

        // 2. Offline onset strength from the captured audio.
        let (samples, sr) = try Self.decodeMono(base.appendingPathComponent("raw_tap.wav"))
        guard samples.count > Self.window else { Issue.record("raw_tap too short"); return }
        let onset = Self.onsetStrength(samples, sampleRate: sr)
        let onsetT0 = tapT0

        // 3. The recorded features. ★ SEVERAL COLUMNS, NOT ONE — because a lag measured
        //    against a single feature cannot tell TRANSPORT delay from that feature's own
        //    SHAPE. `spectral_level_rise` compares level against a 0.15 s trailing floor, so
        //    it peaks after a transient BY DESIGN; `bass` is a band energy that tracks the
        //    envelope directly. If both lag equally the delay is in the pipeline; if only the
        //    level-rise column lags, most of it is the feature definition and there is far
        //    less to fix than the first number suggested.
        let columns = ["bass", "treble", "beatComposite", "spectral_level_rise"]
        var report: [String] = []
        var overlapS = 0.0
        for column in columns {
        let (featT, featV) = try Self.loadFeature(base.appendingPathComponent("features.csv"),
                                                  column: column)
        guard featT.count > 100 else {
            report.append(String(format: "  %-20@ COLUMN ABSENT or empty — skipped",
                                 column as NSString))
            continue
        }

        // 4. Overlap window only — the tap is capped at 30 s, the session runs longer.
        let lo = max(onsetT0, featT.first!)
        let hi = min(onsetT0 + Double(onset.count) * Self.hop, featT.last!)
        guard hi - lo > 5 else {
            Issue.record("overlap only \(hi - lo) s — too short to correlate")
            return
        }
        overlapS = hi - lo
        let steps = Int((hi - lo) / Self.hop)

        // Resample both onto the shared 5 ms grid.
        var a = [Double](repeating: 0, count: steps)   // audio onset strength
        var b = [Double](repeating: 0, count: steps)   // recorded feature
        var cursor = 0
        for k in 0..<steps {
            let t = lo + Double(k) * Self.hop
            let oi = Int((t - onsetT0) / Self.hop)
            a[k] = (oi >= 0 && oi < onset.count) ? Double(onset[oi]) : 0
            while cursor + 1 < featT.count && featT[cursor + 1] <= t { cursor += 1 }
            b[k] = Double(featV[cursor])
        }

        // 5. Cross-correlate. Positive lag = the FEATURE happens after the AUDIO, i.e. late.
        let maxLag = Int(Self.maxLagMs / 1000.0 / Self.hop)
        let (bestLag, bestR) = Self.bestLag(a, b, maxLag: maxLag)
        let ms = Double(bestLag) * Self.hop * 1000

        // A neighbourhood, so a sharp peak can be told from a flat one.
        var neighbourhood: [String] = []
        for off in stride(from: -60, through: 60, by: 20) {
            let l = bestLag + Int(Double(off) / 1000.0 / Self.hop)
            if abs(l) <= maxLag {
                neighbourhood.append(String(format: "%+d ms r=%.3f",
                                            Int(Double(l) * Self.hop * 1000),
                                            Self.correlate(a, b, lag: l)))
            }
        }

        report.append(String(format: "  %-20@ lag %+5.0f ms   r %.3f   (r@0 %.3f)   %@",
                             column as NSString, ms, bestR,
                             Self.correlate(a, b, lag: 0),
                             neighbourhood.joined(separator: " ") as NSString))
        }

        print("[offset] \(base.lastPathComponent) — overlap \(String(format: "%.1f", overlapS)) s"
              + " on a shared wallclock (tap t0 \(tapT0))")
        print("  positive lag = the feature lands AFTER the audio, i.e. the visual is late")
        print(report.joined(separator: "\n"))
        #expect(!report.isEmpty)
    }

    // MARK: - Helpers

    static func tapStartWallclock(_ log: String) -> Double? {
        for line in log.split(separator: "\n") where line.contains("raw tap capture started") {
            guard let r = line.range(of: "wallclock=") else { continue }
            return Double(line[r.upperBound...].prefix { $0.isNumber || $0 == "." })
        }
        return nil
    }

    /// Positive first difference of log broadband energy — the standard onset-strength shape,
    /// and deliberately NOT a reimplementation of `spectral_level_rise`: correlating the
    /// recorded feature against an offline copy of its own algorithm would measure the
    /// algorithm, not the delay.
    static func onsetStrength(_ x: [Float], sampleRate: Double) -> [Float] {
        let hopN = Int(Self.hop * sampleRate)
        guard hopN > 0 else { return [] }
        var out: [Float] = []
        var prev: Float = -12
        var i = 0
        while i + Self.window <= x.count {
            var e: Float = 0
            for n in i..<(i + Self.window) { e += x[n] * x[n] }
            let logE = log(max(e / Float(Self.window), 1e-12))
            out.append(max(0, logE - prev))
            prev = logE
            i += hopN
        }
        return out
    }

    static func loadFeature(_ url: URL, column: String) throws -> ([Double], [Float]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return ([], []) }
        let header = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        guard let ci = header.firstIndex(of: column),
              let ti = header.firstIndex(of: "wallclock_s") else { return ([], []) }
        var times: [Double] = [], values: [Float] = []
        for line in lines {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count > max(ci, ti), let t = Double(f[ti]) else { continue }
            times.append(t)
            values.append(Float(f[ci]) ?? 0)
        }
        return (times, values)
    }

    static func correlate(_ a: [Double], _ b: [Double], lag: Int) -> Double {
        let n = min(a.count, b.count)
        var sa = 0.0, sb = 0.0, sab = 0.0, saa = 0.0, sbb = 0.0
        var count = 0
        for i in 0..<n {
            let j = i + lag
            guard j >= 0 && j < n else { continue }
            sa += a[i]; sb += b[j]; sab += a[i] * b[j]
            saa += a[i] * a[i]; sbb += b[j] * b[j]
            count += 1
        }
        guard count > 10 else { return 0 }
        let m = Double(count)
        let num = sab - sa * sb / m
        let den = ((saa - sa * sa / m) * (sbb - sb * sb / m)).squareRoot()
        return den > 0 ? num / den : 0
    }

    static func bestLag(_ a: [Double], _ b: [Double], maxLag: Int) -> (Int, Double) {
        var bl = 0, br = -2.0
        for l in -maxLag...maxLag {
            let r = correlate(a, b, lag: l)
            if r > br { br = r; bl = l }
        }
        return (bl, br)
    }

    static func decodeMono(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                         frameCapacity: AVAudioFrameCount(file.length)) else {
            return ([], fmt.sampleRate)
        }
        try file.read(into: buf)
        guard let ch = buf.floatChannelData else { return ([], fmt.sampleRate) }
        let n = Int(buf.frameLength), c = Int(fmt.channelCount)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var acc: Float = 0
            for k in 0..<c { acc += ch[k][i] }
            out[i] = acc / Float(c)
        }
        return (out, fmt.sampleRate)
    }
}
