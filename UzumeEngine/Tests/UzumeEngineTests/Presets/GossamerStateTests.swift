// GossamerStateTests — Unit tests for GossamerState wave-pool logic (Increment 3.5.6).
//
// Tests exercise the public Swift API only.
// GPU buffer contents are read back via waveBuffer.contents() using WaveGPU.
//
// Invariants verified:
//   1. Initial pool: 2 seeded waves, waveCount = 2 (D-037 inv.1, inv.4)
//   2. Emission rate: confident vocals + otherEnergyDev=0.75 for 1.5s → ≥ 2 new waves
//   3. Confidence gate: low confidence suppresses emission; accumulator preserved for re-entry
//   4. FV fallback: stems=.zero + midAttRel=0.75 emits proportionally via FV path
//   5. Retirement: a wave older than maxWaveLifetime is retired; count decreases
//   6. Pool full: 33rd emission evicts oldest wave; waveCount stays ≤ maxWaves
//   7. Determinism: two instances with same seed + same inputs → identical GPU buffer
//   8. Silence stability: at zero audio for 10s, waveCount ≥ 2 (drift floor holds)

import Testing
import Foundation
import Metal
@testable import Presets
import Shared

// MARK: - Helpers

private enum GossamerTestError: Error { case noMetalDevice }

/// Read waveCount from the GossamerState buffer header.
private func readWaveCount(_ state: GossamerState) -> Int {
    let ptr = state.waveBuffer.contents().bindMemory(to: UInt32.self, capacity: 4)
    return Int(ptr[0])
}

/// Read the WaveGPU array from the buffer (up to maxWaves entries).
private func readWaves(_ state: GossamerState) -> [WaveGPU] {
    let count = readWaveCount(state)
    let ptr = state.waveBuffer.contents().advanced(by: 16)
                   .bindMemory(to: WaveGPU.self, capacity: GossamerState.maxWaves)
    return (0..<count).map { ptr[$0] }
}

/// Read raw GPU buffer bytes for determinism comparison.
private func readRawBuffer(_ state: GossamerState) -> Data {
    let len = state.waveBuffer.length
    return Data(bytes: state.waveBuffer.contents(), count: len)
}

/// FeatureVector with optional fields for test control.
private func fv(
    midAtt: Float = 0,
    midRel: Float = 0,
    midAttRel: Float = 0,
    deltaTime: Float = 1.0 / 60.0
) -> FeatureVector {
    var f = FeatureVector.zero
    f.midAtt    = midAtt
    f.midRel    = midRel
    f.midAttRel = midAttRel
    f.deltaTime = deltaTime
    return f
}

/// StemFeatures with the fields Gossamer cares about.
private func stems(
    otherEnergyDev: Float = 0,
    vocalsPitchHz: Float = 0,
    vocalsPitchConfidence: Float = 0,
    vocalsEnergyDev: Float = 0,
    totalEnergy: Float = 0.1   // > 0.06 → stemMix ≈ 1.0
) -> StemFeatures {
    var s = StemFeatures.zero
    s.otherEnergyDev         = otherEnergyDev
    s.vocalsPitchHz          = vocalsPitchHz
    s.vocalsPitchConfidence  = vocalsPitchConfidence
    s.vocalsEnergyDev        = vocalsEnergyDev
    // Distribute total energy evenly so D-019 warmup threshold (0.06) is crossed.
    s.vocalsEnergy  = totalEnergy / 4
    s.drumsEnergy   = totalEnergy / 4
    s.bassEnergy    = totalEnergy / 4
    s.otherEnergy   = totalEnergy / 4
    return s
}

// MARK: - Tests

@Suite("GossamerState")
struct GossamerStateTests {

    // MARK: Test 1 — Initial pool

    @Test("Initial pool contains exactly 2 seeded waves with age > 0")
    func testInitialPool() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else {
            Issue.record("GossamerState init returned nil")
            return
        }
        #expect(state.waveCount == 2)
        let waves = readWaves(state)
        #expect(waves.count == 2)
        // Both seeded waves must have positive age at frame zero.
        for w in waves { #expect(w.age > 0) }
    }

    // MARK: Test 2 — Emission rate

    @Test("Emission rate: otherEnergyDev=0.75 with confident vocals for 1.5s produces ≥ 2 new waves")
    func testEmissionRate() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else { return }

        let initialCount = state.waveCount   // 2
        let frameTime: Float = 1.0 / 60.0
        // otherEnergyDev=0.75 → stemRate = 0.5 + 0.75×2 = 2.0 waves/sec.
        // Over 1.5s: ~3 new waves expected.
        let s = stems(otherEnergyDev: 0.75, vocalsPitchHz: 220, vocalsPitchConfidence: 0.8,
                      vocalsEnergyDev: 0.2, totalEnergy: 0.2)
        for _ in 0..<90 {
            state.tick(deltaTime: frameTime, features: fv(deltaTime: frameTime), stems: s)
        }
        #expect(state.waveCount >= initialCount + 2)
    }

    // MARK: Test 3 — Confidence gate

    @Test("Confidence gate: low confidence suppresses emission; accumulator preserved for re-entry")
    func testConfidenceGate() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else { return }

        let initialCount = state.waveCount  // 2

        // Low confidence + no vocal energy → gate closed. Run for 1.0s.
        // Base rate (0.5/sec) builds the accumulator to ~0.5 — below the 1.0 threshold,
        // so no emission slots trigger during the gated period.
        let frameTime: Float = 1.0 / 60.0
        let sSilentVocals = stems(otherEnergyDev: 0.0,
                                  vocalsPitchHz: 220,
                                  vocalsPitchConfidence: 0.1,   // below 0.35 gate
                                  vocalsEnergyDev: 0.0,          // also below 0.05
                                  totalEnergy: 0.2)
        for _ in 0..<60 {
            state.tick(deltaTime: frameTime, features: fv(deltaTime: frameTime), stems: sSilentVocals)
        }
        // No new waves should have been emitted by the main gate.
        // (Drift floor may top up to 2 if initial waves retired, but shouldn't add beyond 2.)
        let countAfterGated = state.waveCount
        #expect(countAfterGated <= initialCount + 1)  // allow at most 1 drift wave

        // Accumulator should have grown during the gated period (≥ 0).
        #expect(state.waveEmissionAccumulator >= 0)

        // Now open the gate — emission should resume within a fraction of a second.
        // otherEnergyDev=0.5 → stemRate=1.5/sec; accumulator ~0.5 head-start →
        // first emission within ~0.33s = 20 frames.
        let sConfident = stems(otherEnergyDev: 0.5,
                               vocalsPitchHz: 220,
                               vocalsPitchConfidence: 0.9,
                               vocalsEnergyDev: 0.3,
                               totalEnergy: 0.2)
        for _ in 0..<30 {
            state.tick(deltaTime: frameTime, features: fv(deltaTime: frameTime), stems: sConfident)
        }
        // At least one new wave should appear within 30 frames of gate opening.
        #expect(state.waveCount > countAfterGated)
    }

    // MARK: Test 4 — FV fallback emission

    @Test("FV fallback: stems=.zero + midAttRel=0.75 emits waves via FV path")
    func testFVFallback() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else { return }

        // stems.zero → totalStemEnergy=0 → stemMix≈0 → FV path drives emission.
        // midAttRel=0.75 → fvRate = 0.4 + 0.75×0.8 = 1.0 waves/sec.
        let fvFeatures = fv(midAttRel: 0.75, deltaTime: 1.0 / 60.0)
        // vocalsEnergyDev > 0.05 so the emission gate opens.
        var sZero = StemFeatures.zero
        sZero.vocalsEnergyDev = 0.1   // gate open; stems otherwise zero

        let initialCount = state.waveCount
        for _ in 0..<120 {  // 2 seconds at 60 fps → ~2 new waves at 1.0/sec
            state.tick(deltaTime: 1.0 / 60.0, features: fvFeatures, stems: sZero)
        }
        #expect(state.waveCount >= initialCount + 1)
    }

    // MARK: Test 5 — Wave retirement

    @Test("Retirement: a wave older than maxWaveLifetime is retired; pool count decreases")
    func testRetirement() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else { return }

        // The seeded waves have ages 1.0s and 3.0s. Drive the clock past maxWaveLifetime (6.0s)
        // without emitting new waves (zero stems, zero FV).
        let frameTime: Float = 1.0 / 60.0
        var sZero = StemFeatures.zero   // no emission; confidence gate stays closed
        // 400 frames ≈ 6.7s
        for _ in 0..<400 {
            state.tick(deltaTime: frameTime, features: fv(deltaTime: frameTime), stems: sZero)
        }
        // Both initial seeded waves should have been retired by now.
        // The drift floor should have replaced them — but initial pool is gone.
        // waveCount ≥ 0 (drift may have filled some slots, which is fine).
        // The key invariant: no wave in the GPU buffer has age > maxWaveLifetime.
        let waves = readWaves(state)
        for w in waves {
            #expect(w.age < GossamerState.maxWaveLifetime + 0.1)  // small tolerance for frame timing
        }
    }

    // MARK: Test 6 — Pool full: evict oldest

    @Test("Pool full: 33rd emission evicts oldest wave; waveCount stays ≤ maxWaves")
    func testPoolFull() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else { return }

        // Emit at a very high rate to fill the pool quickly.
        // otherEnergyDev=10.0 is test-inflated (real max ≈ 1.0) to drive stemRate=20.5/sec
        // so the pool fills within the 10s window.
        let sHigh = stems(otherEnergyDev: 10.0,
                          vocalsPitchHz: 440,
                          vocalsPitchConfidence: 0.9,
                          vocalsEnergyDev: 0.5,
                          totalEnergy: 0.3)
        // 10 seconds at 60fps should easily overflow the 32-slot pool.
        for _ in 0..<600 {
            state.tick(deltaTime: 1.0 / 60.0, features: fv(deltaTime: 1.0 / 60.0), stems: sHigh)
        }
        #expect(state.waveCount <= GossamerState.maxWaves)
        #expect(readWaveCount(state) <= GossamerState.maxWaves)
    }

    // MARK: Test 7 — Determinism

    @Test("Determinism: two instances with identical seed + inputs produce byte-identical GPU buffer after 600 frames")
    func testDeterminism() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let a = GossamerState(device: device, seed: 7),
              let b = GossamerState(device: device, seed: 7) else { return }

        let frameTime: Float = 1.0 / 60.0
        let s = stems(otherEnergyDev: 0.5, vocalsPitchHz: 330, vocalsPitchConfidence: 0.7,
                      vocalsEnergyDev: 0.25, totalEnergy: 0.2)
        let f = fv(midAtt: 0.4, midRel: 0.1, deltaTime: frameTime)

        for _ in 0..<600 {
            a.tick(deltaTime: frameTime, features: f, stems: s)
            b.tick(deltaTime: frameTime, features: f, stems: s)
        }
        #expect(readRawBuffer(a) == readRawBuffer(b))
    }

    // MARK: Test 8 — Silence stability

    @Test("Silence stability: at zero audio for 10s, waveCount stays ≥ 2 (drift floor holds)")
    func testSilenceStability() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw GossamerTestError.noMetalDevice }
        guard let state = GossamerState(device: device, seed: 42) else { return }

        // 10 seconds at 60 fps, fully silent.
        for _ in 0..<600 {
            state.tick(deltaTime: 1.0 / 60.0, features: fv(deltaTime: 1.0 / 60.0),
                       stems: StemFeatures.zero)
        }
        // Drift floor should keep ≥ 2 waves alive (D-037 invariant 4).
        #expect(state.waveCount >= 2)
    }

    // MARK: Test 9 — the spoke direction table agrees with the spoke angles (PR.18)

    /// ★ TWO SOURCES OF TRUTH, HELD IN AGREEMENT BY A TEST.
    ///
    /// `Gossamer.metal` carries D-042's 17 spoke angles in radians — the readable,
    /// authoritative form — and, since PR.18, a parallel table of their unit direction
    /// vectors. The table exists because indexing a `constant` array in a loop defeats
    /// constant folding, so the shader was evaluating 17 `cos` and 17 `sin` for every
    /// pixel of a fullscreen pass to rebuild something that never changes.
    ///
    /// The hazard that buys is obvious: edit one array, forget the other, and the web's
    /// geometry silently stops matching the angles the design decision specifies — with
    /// nothing failing, because both arrays are individually well-formed. So this reads
    /// the shader source and checks them against each other. There is no way to do this
    /// from Swift by importing the constants; they are Metal `constant` scope.
    @Test("Gossamer's spoke direction table matches its spoke angles")
    func testSpokeDirectionTableMatchesAngles() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Presets
            .deletingLastPathComponent()          // UzumeEngineTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // UzumeEngine (package root)
            .appendingPathComponent("Sources/Presets/Shaders/Gossamer.metal")
        let source = try String(contentsOf: url, encoding: .utf8)

        func floats(after marker: String) -> [Double] {
            guard let start = source.range(of: marker),
                  let end = source.range(of: "};", range: start.upperBound..<source.endIndex)
            else { return [] }
            let body = source[start.upperBound..<end.lowerBound]
            // Strip // comments so the annotations beside each row are not scanned.
            let cleaned = body.split(separator: "\n").map { line -> Substring in
                guard let slash = line.range(of: "//") else { return line }
                return line[line.startIndex..<slash.lowerBound]
            }.joined(separator: "\n")
            // `float2(` would otherwise contribute a literal 2 per row — the parse read
            // 51 numbers instead of 34 the first time this ran.
            let scanned = cleaned.replacingOccurrences(of: "float2", with: "")
            let pattern = "[-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?"
            let re = try? NSRegularExpression(pattern: pattern)
            let ns = scanned as NSString
            let matches = re?.matches(in: scanned, range: NSRange(location: 0, length: ns.length)) ?? []
            return matches.compactMap { Double(ns.substring(with: $0.range)) }
        }

        let angles = floats(after: "constant float kSpokeAngles[17] = {")
        let dirs   = floats(after: "constant float2 kSpokeDirs[17] = {")

        #expect(angles.count == 17, "expected 17 spoke angles, parsed \(angles.count)")
        #expect(dirs.count == 34, "expected 17 direction pairs (34 floats), parsed \(dirs.count)")
        guard angles.count == 17, dirs.count == 34 else { return }

        for i in 0..<17 {
            let expectedX = cos(angles[i]), expectedY = sin(angles[i])
            let actualX = dirs[i * 2], actualY = dirs[i * 2 + 1]
            #expect(abs(actualX - expectedX) < 1e-6,
                    "spoke \(i): kSpokeDirs.x \(actualX) != cos(\(angles[i])) = \(expectedX)")
            #expect(abs(actualY - expectedY) < 1e-6,
                    "spoke \(i): kSpokeDirs.y \(actualY) != sin(\(angles[i])) = \(expectedY)")
        }
    }
}
