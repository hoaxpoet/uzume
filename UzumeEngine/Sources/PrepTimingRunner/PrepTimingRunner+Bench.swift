// PrepTimingRunner+Bench — PREP.3 single-separation latency, stereo (live) and mono (sweep).
//
// Live separation hands `separate` a stereo chunk and must not get slower (PREP.3 "Do NOT");
// the sweep hands it mono windows. This times both on the same 10 s of real audio, after a
// warm-up call, and reports the median and p90 of `iterations` calls.

import Foundation
import Metal
import ML
import Session

enum SeparateBench {

    static func run(url: URL, iterations: Int, device: MTLDevice, out: URL) throws {
        let separator = try StemSeparator(device: device)
        let preview = try PreviewAudio.fromLocalFile(at: url)
        let rate = Float(preview.sampleRate)
        let count = min(preview.pcmSamples.count, Int(10 * rate))
        let start = min(preview.pcmSamples.count - count, Int(30 * rate))
        let mono = Array(preview.pcmSamples[start..<(start + count)])
        // A real stereo image is not needed for latency: the separator's work per channel
        // does not depend on the samples. R is a scaled copy so L != R.
        var stereo = [Float](repeating: 0, count: count * 2)
        for index in 0..<count {
            stereo[2 * index] = mono[index]
            stereo[2 * index + 1] = mono[index] * 0.8
        }
        var report = "separate() latency, \(iterations) calls after one warm-up, 10 s input\n"
        for (label, audio, channels) in [("stereo (live)", stereo, 2), ("mono (sweep)", mono, 1)] {
            _ = try separator.separate(audio: audio, channelCount: channels, sampleRate: rate)
            var times: [Double] = []
            for _ in 0..<iterations {
                let t0 = DispatchTime.now().uptimeNanoseconds
                _ = try separator.separate(audio: audio, channelCount: channels, sampleRate: rate)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6)
            }
            times.sort()
            let median = times[times.count / 2]
            let p90 = times[times.count * 9 / 10]
            report += label.padding(toLength: 15, withPad: " ", startingAt: 0)
                + String(format: "median %.1f ms   p90 %.1f ms   min %.1f ms\n", median, p90, times[0])
        }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try report.write(to: out.appendingPathComponent("separate_latency.txt"), atomically: true, encoding: .utf8)
        print(report)
    }
}
