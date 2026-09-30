// WaveformState — held bar heights for the Waveform `direct` preset (BR.20 / I8).
//
// WHY THIS EXISTS. The flash check v2 (a ninth of the frame, WCAG's small-area rule) measured
// Waveform at 5 flashes/s under a spectrum pulsing with the 270 BPM worst-case train: its 64 bars
// read the raw FFT every frame, so a kick's bars jump to full and drop straight back — a patch of
// screen flashing with every beat. Waveform is the launch default and the fallback, the first
// thing every tester sees. Matt, 2026-09-30: bars RISE instantly and FALL slowly, so they still jump
// on every kick but cannot flash fully on and off within a beat. The fall had to be 0.6 s, not the
// first-proposed 0.15 s — measured (regional flashes/s): 0.15 / 0.25 / 0.35 / 0.5 → 5.0,
// 0.6 / 0.75 → 0.0 (option A′, approved). A peak-meter look.
//
// That needs the previous frame's bars, which a `direct` preset has no memory of — so per-preset
// state at fragment slot 6, the NebulaState pattern (PR.21).
//
// GPU layout (bound at buffer(6)): 64 Float32 bar heights in [0, 1] (the shader's own
// `saturate(max-of-8-bins × 10)`), then one flag at [64] = 1. A zeroed slot 6 (the test
// harnesses' placeholder) reads the flag as 0 and the shader falls back to the raw spectrum,
// exactly as before — so every harness that never ticks this state renders unchanged.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.presets", category: "Waveform")

/// Per-frame held bar heights for Waveform's spectrum.
public final class WaveformState: @unchecked Sendable {

    /// Bars across the spectrum (the shader's `NUM_BARS`).
    public static let barCount = 64
    /// FFT bins per bar (512 / 64).
    public static let binsPerBar = 8
    /// Release time constant: a bar falls ~63 % of the way in this long (BR.20; 0.5 s still flashes).
    public static let releaseTau: Float = 0.6

    /// Buffer bound at fragment index 6: `barCount` heights, then the bound flag.
    public let barBuffer: MTLBuffer

    private let lock = NSLock()
    private var held: [Float]

    public init?(device: MTLDevice) {
        let size = (Self.barCount + 1) * MemoryLayout<Float>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            logger.error("WaveformState: failed to allocate barBuffer (\(size) bytes)")
            return nil
        }
        barBuffer = buf
        held = [Float](repeating: 0, count: Self.barCount)
        writeToGPU()
    }

    /// Recompute the bars from this frame's FFT magnitudes: instant rise, `releaseTau` fall.
    public func tick(deltaTime: Float, magnitudes: UnsafePointer<Float>, binCount: Int) {
        lock.withLock {
            // Frame-rate independent: the fall reads the same at 60 and 120 Hz (the BUG-096 class).
            let fall = 1 - exp(-max(deltaTime, 1.0 / 240.0) / Self.releaseTau)
            for bar in 0..<Self.barCount {
                var raw: Float = 0
                for bin in (bar * Self.binsPerBar)..<min(binCount, (bar + 1) * Self.binsPerBar) {
                    raw = max(raw, mags(magnitudes, bin))
                }
                let target = min(max(raw * 10, 0), 1)
                let next = target >= held[bar] ? target : held[bar] + (target - held[bar]) * fall
                held[bar] = next.isFinite ? next : 0
            }
        }
        writeToGPU()
    }

    private func mags(_ ptr: UnsafePointer<Float>, _ bin: Int) -> Float {
        let value = ptr[bin]
        return value.isFinite ? value : 0
    }

    private func writeToGPU() {
        let ptr = barBuffer.contents().assumingMemoryBound(to: Float.self)
        lock.withLock {
            for bar in 0..<Self.barCount { ptr[bar] = held[bar] }
            ptr[Self.barCount] = 1   // bound flag
        }
    }

    /// Test seam: the held bar heights.
    public func barsForTesting() -> [Float] { lock.withLock { held } }
}
