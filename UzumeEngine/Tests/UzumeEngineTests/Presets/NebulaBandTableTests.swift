// NebulaBandTableTests — PR.21: the CPU band table and the shader that reads it.
//
// Two defect classes, both silent:
//
//   1. The table's length is a Swift constant and the shader's index bound is an MSL
//      constant. If they drift, the shader reads past the buffer or ignores part of it, and
//      nothing fails — the ring just goes wrong in a way that looks like a tuning problem.
//
//   2. Peak-hold is the whole reason this state exists. Attack and release are two numbers,
//      and a build where they are equal is a plain low-pass: it calms the shimmer AND
//      flattens the peaks, which is the opposite of what Matt asked for. That build passes
//      any test that only checks "the bands move".
import Testing
import Foundation
import Metal
@testable import Presets

@Suite("NebulaBandTable (PR.21)")
struct NebulaBandTableTests {

    private func makeState() throws -> NebulaState {
        let device = try #require(MTLCreateSystemDefaultDevice(), "no Metal device")
        return try #require(NebulaState(device: device), "NebulaState allocation failed")
    }

    /// Parses the shader source, because the two constants live in different languages and
    /// nothing else can compare them.
    @Test("kBandCount in Nebula.metal matches NebulaState.bandCount")
    func bandCountsAgree() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Presets/Shaders/Nebula.metal")
        let src = try String(contentsOf: url, encoding: .utf8)
        let re = try NSRegularExpression(pattern: #"constant\s+int\s+kBandCount\s*=\s*(\d+)"#)
        let ns = src as NSString
        let m = try #require(re.firstMatch(in: src, range: NSRange(location: 0, length: ns.length)),
                             "kBandCount not found in Nebula.metal")
        let shaderCount = Int(ns.substring(with: m.range(at: 1))) ?? -1
        #expect(shaderCount == NebulaState.bandCount,
                "shader kBandCount \(shaderCount) != NebulaState.bandCount \(NebulaState.bandCount)")
    }

    /// ★ THE ASYMMETRY IS THE FEATURE. A transient must arrive fast and leave slowly; that is
    /// what turns a one-frame spike into something the eye can follow. Measured as the number
    /// of frames to cover most of the distance in each direction.
    @Test("Attack is fast and release is slow — a spike arrives at once and decays")
    func peakHoldIsAsymmetric() throws {
        let state = try makeState()
        let dt: Float = 1.0 / 60.0
        var loud = [Float](repeating: 0.35, count: 512)
        let quiet = [Float](repeating: 0.0, count: 512)

        // Rise: how many frames until the table is mostly up?
        var framesToRise = 0
        for _ in 0..<240 {
            loud.withUnsafeBufferPointer { state.tick(deltaTime: dt, magnitudes: $0.baseAddress!, binCount: 512) }
            framesToRise += 1
            if state.peak > 0.6 { break }
        }
        let risen = state.peak
        #expect(risen > 0.6, "bands never rose on a loud spectrum (peak \(risen))")
        #expect(framesToRise <= 12,
                "attack took \(framesToRise) frames — a transient arriving that late reads as lag")

        // Fall: how many frames until it has mostly decayed?
        var framesToFall = 0
        for _ in 0..<600 {
            quiet.withUnsafeBufferPointer { state.tick(deltaTime: dt, magnitudes: $0.baseAddress!, binCount: 512) }
            framesToFall += 1
            if state.peak < risen * 0.2 { break }
        }
        #expect(framesToFall > framesToRise * 3,
                "release \(framesToFall) frames vs attack \(framesToRise) — not meaningfully slower, so this is a low-pass rather than peak-hold and it flattens exactly the peaks the ring should show")
    }

    /// Frame-rate independence. A fixed per-frame coefficient would make the release twice as
    /// fast at 120 Hz as at 60 — the BUG-096 class, where a per-frame delta stood in for a
    /// duration. Two runs covering the same WALL time must land in the same place.
    @Test("Decay is frame-rate independent")
    func decayIsFrameRateIndependent() throws {
        func decayedPeak(dt: Float, frames: Int) throws -> Float {
            let state = try makeState()
            let loud = [Float](repeating: 0.35, count: 512)
            let quiet = [Float](repeating: 0.0, count: 512)
            for _ in 0..<120 {
                loud.withUnsafeBufferPointer { state.tick(deltaTime: dt, magnitudes: $0.baseAddress!, binCount: 512) }
            }
            for _ in 0..<frames {
                quiet.withUnsafeBufferPointer { state.tick(deltaTime: dt, magnitudes: $0.baseAddress!, binCount: 512) }
            }
            return state.peak
        }
        // 0.5 s of decay, reached two ways.
        let at60 = try decayedPeak(dt: 1.0 / 60.0, frames: 30)
        let at120 = try decayedPeak(dt: 1.0 / 120.0, frames: 60)
        #expect(abs(at60 - at120) < 0.02,
                "same wall time, different frame rates: \(at60) vs \(at120) — the smoothing coefficient is per-frame, not per-second")
    }

    @Test("Silence decays toward zero and never goes negative or non-finite")
    func silenceIsClean() throws {
        let state = try makeState()
        let quiet = [Float](repeating: 0, count: 512)
        for _ in 0..<600 {
            quiet.withUnsafeBufferPointer { state.tick(deltaTime: 1.0 / 60.0, magnitudes: $0.baseAddress!, binCount: 512) }
        }
        let bands = state.bandsForTesting()
        #expect(bands.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(state.peak < 0.02, "bands did not settle at silence (peak \(state.peak))")
    }
}
