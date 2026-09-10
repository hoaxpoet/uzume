// NebulaState — per-preset band state for the Nebula `direct` preset (PR.21).
//
// WHY THIS EXISTS. Matt, on the PR.20 build: *"looks good, but I'm not getting a clear
// understanding of how the visuals are tied to the audio."* Measured on his session, one
// half of that is temporal: the ring's value at any angular position moves 0.40x its own
// mean between consecutive frames, so a loud moment appears and vanishes inside a frame or
// two. The eye reads that as shimmer, not as response — there is nothing to follow.
//
// The fix is peak-hold: fast attack, slow release, so a spike shoots out and DECAYS. That
// needs memory of the previous frame, and a `direct` preset has none — `SpectralHistoryBuffer`
// carries MIR scalars, not spectra. Hence per-preset state, bound at fragment slot 6 exactly
// as `GossamerState` is.
//
// ★ AND IT MAKES THE PRESET CHEAPER, not more expensive. The log-band aggregation used to run
//   PER PIXEL inside the shader — every fragment re-derived the same 256 bands. Doing it once
//   per frame on the CPU and handing the shader a table is strictly less work: ~2 M fragments
//   at 1080p were each looping over bins.
//
// GPU layout (bound at buffer(6)): 256 Float32 band values in [0, 1], angular position 0 at
// `kFreqLo` rising logarithmically to `kFreqHi`. No header — the count is a shader constant,
// and a header that can disagree with the shader is a bug waiting to happen.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.presets", category: "Nebula")

/// Per-frame smoothed spectrum bands for Nebula's ring.
public final class NebulaState: @unchecked Sendable {

    /// Angular positions around the ring. Must equal `kBandCount` in `Nebula.metal`.
    public static let bandCount = 256

    /// Frequency range mapped around the circle. Must match `kFreqLo`/`kFreqHi` in the shader
    /// — they are documented there with the sweep that chose them (PR.19).
    public static let freqLo: Float = 40
    public static let freqHi: Float = 8000
    /// Amplitude ∝ sqrt(f): the +3 dB/octave pink slope. Natural spectra fall ~1/f, so without
    /// it the top of the circle is permanently dark however the gain is set.
    public static let tilt: Float = 0.5
    /// Response knee, chosen from the measured magnitude distribution (PR.19).
    public static let logGain: Float = 90
    /// Window width in angular positions. Overlapping neighbours is what makes the ring read
    /// as a ring rather than a starburst — see `Nebula.metal`.
    public static let overlap: Float = 5

    /// ★ THE TWO CONSTANTS THIS CLASS EXISTS FOR. Attack is fast enough that a transient is
    /// not visibly late; release is slow enough that the eye can follow the decay. Symmetric
    /// smoothing would just be a low-pass — it would calm the shimmer AND flatten the peaks,
    /// which is the opposite of legible.
    public static let attackTau: Float = 0.025
    public static let releaseTau: Float = 0.40

    /// UMA buffer bound at fragment index 6.
    public let bandBuffer: MTLBuffer

    private var smoothed: [Float]
    private let lock = NSLock()

    /// Highest smoothed band this frame — diagnostics only.
    public private(set) var peak: Float = 0

    public init?(device: MTLDevice) {
        let size = Self.bandCount * MemoryLayout<Float>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            logger.error("NebulaState: failed to allocate bandBuffer (\(size) bytes)")
            return nil
        }
        bandBuffer = buf
        smoothed = [Float](repeating: 0, count: Self.bandCount)
        writeToGPU()
    }

    /// Recompute the bands from this frame's FFT magnitudes and advance the peak-hold.
    ///
    /// `magnitudes` is the production `FFTProcessor` output — 512 raw bins, no AGC.
    public func tick(deltaTime: Float, magnitudes: UnsafePointer<Float>, binCount: Int) {
        lock.withLock { advance(deltaTime: deltaTime, mags: magnitudes, binCount: binCount) }
        writeToGPU()
    }

    private func advance(deltaTime: Float, mags: UnsafePointer<Float>, binCount: Int) {
        let dt = max(deltaTime, 1.0 / 240.0)
        // k = 1 - exp(-dt/tau): frame-rate independent, so the feel does not change when the
        // frame time does. A fixed per-frame coefficient would make the release twice as fast
        // at 120 Hz as at 60 — the BUG-096 class of defect.
        let attackK = 1 - exp(-dt / Self.attackTau)
        let releaseK = 1 - exp(-dt / Self.releaseTau)
        let binHz = 48000.0 / 1024.0 as Float
        let ratio = Self.freqHi / Self.freqLo
        var maxSeen: Float = 0

        for k in 0..<Self.bandCount {
            let centre = (Float(k) + 0.5) / Float(Self.bandCount)
            let halfSpan = Self.overlap * 0.5 / Float(Self.bandCount)
            let h0 = Self.freqLo * pow(ratio, max(0, centre - halfSpan))
            let h1 = Self.freqLo * pow(ratio, min(1, centre + halfSpan))
            let b0 = max(0, min(binCount - 1, Int(h0 / binHz)))
            let b1 = max(b0 + 1, min(binCount, Int(h1 / binHz) + 1))
            var acc: Float = 0
            for bin in b0..<b1 { acc += mags[bin] }
            let tilted = (acc / Float(b1 - b0)) * pow(h0 / Self.freqLo, Self.tilt)
            // Logarithmic response — a heavy-tailed signal needs a compressive curve, which
            // is why spectrum displays are drawn in dB (PR.19 measured the alternatives).
            let target = min(max(log(1 + max(tilted, 0) * Self.logGain) / log(1 + Self.logGain), 0), 1)

            let cur = smoothed[k]
            let k1 = target > cur ? attackK : releaseK
            let next = cur + (target - cur) * k1
            smoothed[k] = next.isFinite ? next : 0
            maxSeen = max(maxSeen, smoothed[k])
        }
        peak = maxSeen
    }

    private func writeToGPU() {
        let ptr = bandBuffer.contents().assumingMemoryBound(to: Float.self)
        lock.withLock {
            for k in 0..<Self.bandCount { ptr[k] = smoothed[k] }
        }
    }

    /// Test seam: the smoothed band values.
    public func bandsForTesting() -> [Float] { lock.withLock { smoothed } }
}
