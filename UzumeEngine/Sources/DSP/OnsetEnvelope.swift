// OnsetEnvelope.swift — BUG134.2.
//
// A short-time energy envelope of the mix, used by `BeatGrid.audioOctaveCorrected`
// to ask the AUDIO which metrical level a section actually carries.
//
// Deliberately crude: 5 ms hops of 20 ms RMS. The question it answers is "is there
// periodicity at ~314 ms here", which survives a blunt envelope — the measured
// separation between the two cases is 3-30x. Anything more elaborate would be
// precision the decision does not use.

import Foundation
import Accelerate

public enum OnsetEnvelope {

    /// Hop between envelope samples, seconds.
    public static let hopS: Double = 0.005
    /// RMS window, seconds.
    public static let windowS: Double = 0.020

    public static var rate: Double { 1.0 / hopS }

    /// Short-time RMS envelope of `samples`.
    public static func compute(samples: [Float], sampleRate: Double) -> [Float] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        let hop = max(1, Int(hopS * sampleRate))
        let window = max(hop, Int(windowS * sampleRate))
        guard samples.count > window else { return [] }
        var out = [Float]()
        out.reserveCapacity((samples.count - window) / hop + 1)
        var start = 0
        while start + window <= samples.count {
            var mean: Float = 0
            samples.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                vDSP_measqv(base + start, 1, &mean, vDSP_Length(window))
            }
            out.append(mean.squareRoot())
            start += hop
        }
        return out
    }
}
