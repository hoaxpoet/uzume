// KeyEstimatorTests — BUG-149. The stored key must name the music's key, not its spectral tilt.
// The live 1024-point chroma it replaced scored 3 / 24 on these progressions and read pink
// noise as F# minor, the attractor 35 % of a 993-track census landed on.

import Foundation
import Testing
@testable import Session

@Suite("KeyEstimator (BUG-149)")
struct KeyEstimatorTests {

    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let rate = 22050

    /// I–IV–V–I (major) or i–iv–V–i (minor), 2 s a chord: a triad around middle C over a bass
    /// root, four harmonics per note at 1/h.
    private static func progression(root: Int, minor: Bool) -> [Float] {
        let third = minor ? 3 : 4
        let chords = [[0, third, 7], [5, 5 + third, 12], [7, 11, 14], [0, third, 7]]
        let perChord = rate * 2
        var out = [Float](repeating: 0, count: perChord * chords.count)
        for (index, chord) in chords.enumerated() {
            let freqs = (chord.map { 60 + root + $0 } + [36 + root + chord[0] % 12])
                .map { 440 * pow(2, Double($0 - 69) / 12) }
            for n in 0..<perChord {
                let t = Double(n) / Double(rate)
                var sample = 0.0
                for f in freqs { for h in 1...4 { sample += sin(2 * .pi * f * Double(h) * t) / Double(h) } }
                out[index * perChord + n] = Float(sample * 0.05)
            }
        }
        return out
    }

    @Test("names the key of a chord progression in every one of the 24 keys")
    func allTwentyFourKeys() {
        var misses: [String] = []
        for minor in [false, true] {
            for root in 0..<12 {
                let truth = "\(Self.names[root]) \(minor ? "minor" : "major")"
                let got = KeyEstimator.estimate(samples: Self.progression(root: root, minor: minor), sampleRate: Self.rate)
                if got != truth { misses.append("\(truth) → \(got ?? "nil")") }
            }
        }
        #expect(misses.isEmpty, "misread: \(misses)")
    }

    @Test("pink noise has no key — the spectral tilt alone must not name one")
    func pinkNoiseHasNoKey() {
        var rng = SeededGenerator(seed: 149)
        var b0: Float = 0, b1: Float = 0, b2: Float = 0
        let pink: [Float] = (0..<Self.rate * 8).map { _ in
            let white = Float(rng.next() % 2001) / 1000 - 1
            b0 = 0.99765 * b0 + white * 0.0990460
            b1 = 0.96300 * b1 + white * 0.2965164
            b2 = 0.57000 * b2 + white * 1.0526913
            return (b0 + b1 + b2 + white * 0.1848) * 0.05
        }
        #expect(KeyEstimator.estimate(samples: pink, sampleRate: Self.rate) == nil)
    }

    @Test("too short or silent audio stores no key")
    func shortOrSilent() {
        #expect(KeyEstimator.estimate(samples: [Float](repeating: 0, count: 100), sampleRate: Self.rate) == nil)
        #expect(KeyEstimator.estimate(samples: [Float](repeating: 0, count: Self.rate * 4), sampleRate: Self.rate) == nil)
    }
}

/// SplitMix64 — deterministic noise for the pink-noise case.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
