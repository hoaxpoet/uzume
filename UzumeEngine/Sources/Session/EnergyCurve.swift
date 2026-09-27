// EnergyCurve — a song's measured energy over time (NRG.1, D-259).
//
// Mood was one number per song from a classifier that does not generalise (BUG-148). Energy is
// measured, not inferred, and it is a CURVE because songs move: Dance Yrself Clean sits near
// −27 dB for its first three minutes and near −11 dB after the drop. Two signals per hop:
//
//   loudnessDB — mean power of the audio in the hop, in dB. Tracks a song's quiet and loud parts;
//                comparable WITHIN a song (mastering is constant), not across songs.
//   activity   — median spectral flux (MIR's smoothed raw flux) in the hop: how fast the sound is
//                changing. Less tied to mastering, so the better cross-song signal.
//
// The 1–10 level and the planner's use of the curve come later; this type only measures.

import Accelerate
import Foundation

// MARK: - EnergyCurve

/// A song's measured energy, one point per `hopSeconds` (NRG.1, D-259).
public struct EnergyCurve: Sendable, Codable, Equatable {

    /// Seconds per point.
    public let hopSeconds: Float
    /// Mean power of each hop, in dB (full scale). Silence floors at −120.
    public let loudnessDB: [Float]
    /// Median spectral flux of each hop — how fast the sound is changing.
    public let activity: [Float]

    /// Create a curve from per-hop values; the two arrays must be the same length.
    public init(hopSeconds: Float, loudnessDB: [Float], activity: [Float]) {
        precondition(loudnessDB.count == activity.count, "EnergyCurve: arrays differ in length")
        self.hopSeconds = hopSeconds
        self.loudnessDB = loudnessDB
        self.activity = activity
    }
}

// MARK: - Builder

/// Accumulates analysis frames into an `EnergyCurve`. Feed every frame in order.
struct EnergyCurveBuilder {

    /// One point per second: finer than any scene segment, coarse enough to read a song's shape.
    static let hopSeconds: Float = 1

    private let framesPerHop: Int
    private var power: [Float] = []
    private var flux: [Float] = []
    private var loudness: [Float] = []
    private var activity: [Float] = []

    /// - Parameter frameSeconds: duration of one analysis frame.
    init(frameSeconds: Float) {
        framesPerHop = max(1, Int((Self.hopSeconds / frameSeconds).rounded()))
    }

    /// Add one frame: its raw (unwindowed) samples and MIR's smoothed raw flux for it.
    mutating func add(frame: UnsafeBufferPointer<Float>, flux frameFlux: Float) {
        guard let base = frame.baseAddress, !frame.isEmpty else { return }
        var sumOfSquares: Float = 0
        vDSP_svesq(base, 1, &sumOfSquares, vDSP_Length(frame.count))
        power.append(sumOfSquares / Float(frame.count))
        flux.append(frameFlux)
        if power.count == framesPerHop { closeHop() }
    }

    /// The curve so far, including a final partial hop of at least half a hop.
    mutating func build() -> EnergyCurve {
        if power.count * 2 >= framesPerHop { closeHop() }
        return EnergyCurve(hopSeconds: Self.hopSeconds, loudnessDB: loudness, activity: activity)
    }

    private mutating func closeHop() {
        let meanPower = power.reduce(0, +) / Float(power.count)
        loudness.append(max(-120, 10 * log10(max(meanPower, 1e-12))))
        let sorted = flux.sorted()
        activity.append(sorted[sorted.count / 2])
        power.removeAll(keepingCapacity: true)
        flux.removeAll(keepingCapacity: true)
    }
}
