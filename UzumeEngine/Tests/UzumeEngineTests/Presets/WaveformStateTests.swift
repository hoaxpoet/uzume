// WaveformStateTests — BR.20 / I8: Waveform's bars rise instantly and fall over 0.6 s.

import Metal
import Testing
@testable import Presets

@Suite("WaveformState (BR.20)")
struct WaveformStateTests {

    private func state() throws -> WaveformState {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try #require(WaveformState(device: device))
    }

    @Test func barsRiseInstantly_andFallOverTheReleaseTime() throws {
        let bars = try state()
        var loud = [Float](repeating: 0, count: 512)
        for bin in 0..<8 { loud[bin] = 0.1 }   // bar 0 at full scale (× 10)
        let silent = [Float](repeating: 0, count: 512)
        loud.withUnsafeBufferPointer { bars.tick(deltaTime: 1.0 / 60, magnitudes: $0.baseAddress!, binCount: 512) }
        #expect(bars.barsForTesting()[0] == 1, "instant rise")
        // One release time constant (0.6 s = 36 frames) of silence: ~1/e of the way down.
        for _ in 0..<36 {
            silent.withUnsafeBufferPointer { bars.tick(deltaTime: 1.0 / 60, magnitudes: $0.baseAddress!, binCount: 512) }
        }
        let afterTau = bars.barsForTesting()[0]
        #expect(abs(afterTau - exp(-1)) < 0.03, "after 0.6 s the bar reads \(afterTau), expected ~0.37")
        #expect(bars.barBuffer.contents().assumingMemoryBound(to: Float.self)[WaveformState.barCount] == 1,
                "the bound flag the shader checks")
    }
}
