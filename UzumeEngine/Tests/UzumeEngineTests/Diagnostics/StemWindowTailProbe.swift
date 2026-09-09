// BUG-116 probe — does the separator's output fade at the END of its analysis window?
//
// `SessionPreparer.analyzeStemSeries` places each 2 s KEPT SPAN at the very end of a ~10 s
// separation window, leaving exactly one 1024-sample frame of room past it. If the model's
// output is attenuated near its window edge, then every kept span carries that attenuation
// in its tail — and the series shows a hole every 2.0 s, which is what session
// 2026-09-05T18-17-12Z records (68 spans, all four stems to 0.000, 2.00 s apart, ~0.37 s long).
//
// This measures the window envelope directly, so the diagnosis is not an inference from the
// placement arithmetic.
//
//   UZUME_STEM_TAIL_PROBE=1 UZUME_STEM_TAIL_AUDIO="<path>" \
//     swift test --package-path UzumeEngine --filter StemWindowTailProbe
import Testing
import Foundation
import AVFoundation
import Metal
@testable import DSP
@testable import ML
@testable import Session
@testable import Shared

@Suite("StemWindowTailProbe")
struct StemWindowTailProbe {

    private static func decodeMono(url: URL, rate: Double) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { return [] }
        let count = Int(buffer.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        let scale = 1.0 / Float(channelCount)
        for channel in 0..<channelCount {
            let pointer = UnsafeBufferPointer(start: channels[channel], count: count)
            for index in 0..<count { mono[index] += pointer[index] * scale }
        }
        guard format.sampleRate != rate else { return mono }
        return BeatThisPreprocessor.resample(mono, from: format.sampleRate, to: rate)
    }

    @Test("separator output envelope across its own window",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_STEM_TAIL_PROBE"] == "1"))
    func windowEnvelope() throws {
        let path = ProcessInfo.processInfo.environment["UZUME_STEM_TAIL_AUDIO"] ?? ""
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("set UZUME_STEM_TAIL_AUDIO to an audio file"); return
        }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let separator = try StemSeparator(device: device)
        let rate = Double(StemSeparator.modelSampleRate)
        let audio = try Self.decodeMono(url: url, rate: rate)
        // Take a window from well inside the track so both ends have real music.
        let need = StemSeparator.requiredMonoSamples
        let start = min(max(0, audio.count / 3), max(0, audio.count - need))
        let window = Array(audio[start..<min(audio.count, start + need)])
        #expect(window.count == need, "window is \(window.count) samples, model wants \(need)")

        let result = try separator.separate(
            audio: window, channelCount: 1, sampleRate: Float(rate))
        let stems = result.stemWaveforms
        let names = ["drums", "bass", "vocals", "other"]
        let bucket = Int(rate / 10)   // 100 ms
        print("\n  window \(String(format: "%.2f", Double(window.count) / rate)) s "
              + "at \(String(format: "%.1f", Double(start) / rate)) s — per-100 ms RMS\n")
        // The INPUT envelope is the control: if the input also falls at the tail, the model is
        // innocent and the audio simply got quieter there.
        var series: [(String, [Double])] = [("input ", rms(window, bucket: bucket))]
        for (index, stem) in stems.enumerated() where index < names.count {
            series.append((names[index], rms(stem, bucket: bucket)))
        }
        for (name, values) in series {
            let tail = values.suffix(6).map { String(format: "%.4f", $0) }.joined(separator: " ")
            let mid = values.dropLast(10).suffix(6).map { String(format: "%.4f", $0) }.joined(separator: " ")
            print("  \(name)  mid[…] \(mid)   TAIL[last 600 ms] \(tail)")
        }
        // The claim under test, stated as a number: the last 400 ms of a stem should not be
        // dramatically quieter than the middle of the same window.
        for (name, values) in series.dropFirst() {
            let mid = values.dropLast(12).suffix(20)
            let tail = values.suffix(4)
            let midMean = mid.reduce(0, +) / Double(max(mid.count, 1))
            let tailMean = tail.reduce(0, +) / Double(max(tail.count, 1))
            print(String(format: "  %@ tail/mid = %.3f", name, midMean > 0 ? tailMean / midMean : 0))
        }
    }

    private func rms(_ signal: [Float], bucket: Int) -> [Double] {
        stride(from: 0, to: signal.count, by: bucket).map { start in
            let end = min(start + bucket, signal.count)
            var sum = 0.0
            for i in start..<end { sum += Double(signal[i]) * Double(signal[i]) }
            return (sum / Double(max(end - start, 1))).squareRoot()
        }
    }

    /// Reproduce the series offline and locate the holes, then check the SAME frames'
    /// separator output. If the model's samples are healthy where the series frame is zero,
    /// the defect is in the analysis step, not the separation.
    @Test("series holes: is the audio zero, or is the analysis?",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_STEM_SERIES_PROBE"] == "1"))
    func seriesHoles() throws {
        let path = ProcessInfo.processInfo.environment["UZUME_STEM_TAIL_AUDIO"] ?? ""
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Issue.record("set UZUME_STEM_TAIL_AUDIO"); return
        }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let separator = try StemSeparator(device: device)
        let analyzer = StemAnalyzer()
        // The A/B: the separator ALWAYS returns 44.1 kHz output, but this function computes
        // its slice offsets in the INPUT's rate. Feed it 48 kHz and the two disagree.
        let rate = Int(ProcessInfo.processInfo.environment["UZUME_STEM_SERIES_RATE"] ?? "")
            ?? Int(StemSeparator.modelSampleRate)
        var audio = try Self.decodeMono(url: url, rate: Double(rate))
        audio = Array(audio.prefix(rate * 40))
        let series = try SessionPreparer.analyzeStemSeries(
            samples: audio, sampleRate: rate, separator: separator, analyzer: analyzer)
        let frames = series.frames
        print("\n  series frames \(frames.count), hop \(String(format: "%.4f", series.hopSeconds)) s")
        let hop = series.hopSeconds
        var holes: [Int] = []
        for (i, f) in frames.enumerated() where f.drumsEnergy < 0.01 && f.otherEnergy < 0.01 {
            holes.append(i)
        }
        print("  near-zero frames: \(holes.count) of \(frames.count)")
        // Group into spans and print where each sits inside its 2 s span.
        var runs: [(Int, Int)] = []
        var start = -1
        for i in 0..<frames.count {
            let isHole = holes.contains(i)
            if isHole, start < 0 { start = i }
            if !isHole, start >= 0 { runs.append((start, i)); start = -1 }
        }
        for (a, b) in runs.prefix(8) {
            print(String(format: "    frames %4d-%4d  %.2f-%.2f s  (span offset %.2f-%.2f s)",
                         a, b, Double(a) * hop, Double(b) * hop,
                         Double(a) * hop.truncatingRemainder(dividingBy: 2.0),
                         Double(b) * hop))
        }
        // What does the ENERGY look like around a hole?
        if let (a, b) = runs.dropFirst().first {
            let lo = max(0, a - 6), hi = min(frames.count, b + 6)
            print("  drumsEnergy around the second hole:")
            print("    " + (lo..<hi).map { String(format: "%.3f", frames[$0].drumsEnergy) }.joined(separator: " "))
        }
    }

    /// BUG-065 — does the resample to the model rate preserve DURATION?
    ///
    /// `BeatGridResolver` labels activation frame i as `i / 50.0` seconds, and 22050/441 is
    /// exactly 50, so that is right IF the resampled signal has the duration the original
    /// did. If the converter returns N' samples where N'/22050 differs from the true
    /// duration, every beat time is scaled by that ratio — a LINEAR drift of the whole grid
    /// against the audio, which is exactly the −0.81 ms/s measured in session
    /// 2026-09-08T18-49-10Z.
    ///
    /// UZUME_RESAMPLE_PROBE=1 swift test --package-path UzumeEngine --filter StemWindowTailProbe
    @Test("resample preserves duration",
          .enabled(if: ProcessInfo.processInfo.environment["UZUME_RESAMPLE_PROBE"] == "1"))
    func resampleDuration() throws {
        let target = Double(BeatThisPreprocessor.sampleRate)
        print("\n  target rate \(Int(target)) Hz, hop \(BeatThisPreprocessor.hopLength)"
              + " -> nominal \(target / Double(BeatThisPreprocessor.hopLength)) fps\n")
        print("  input rate   seconds   expected out   actual out      error (ppm)")
        for rate in [44100.0, 48000.0, 96000.0] {
            for seconds in [10.0, 120.0] {
                let n = Int(rate * seconds)
                let input = (0..<n).map { Float(sin(2.0 * Double.pi * 440.0 * Double($0) / rate)) }
                let out = BeatThisPreprocessor.resample(input, from: rate, to: target)
                let expected = seconds * target
                let ppm = (Double(out.count) - expected) / expected * 1e6
                print(String(format: "  %8.0f  %8.0f   %12.0f   %10d   %+12.0f",
                             rate, seconds, expected, out.count, ppm))
            }
        }
    }
}
