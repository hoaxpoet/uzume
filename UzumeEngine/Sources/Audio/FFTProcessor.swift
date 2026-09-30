// FFTProcessor — vDSP-based real-time FFT analysis.
// Performs 1024-point FFT on audio samples, producing 512 magnitude bins.
// Results are written into a UMABuffer<Float> for direct GPU consumption
// as a frequency spectrum texture.
//
// Uses Accelerate.framework for SIMD-optimized FFT on Apple Silicon.
// All allocations happen at init time — per-frame processing is zero-alloc.

import Foundation
import Metal
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.audio", category: "FFTProcessor")

// MARK: - FFTProcessor

/// Real-time FFT analysis using vDSP.
///
/// Produces 512 magnitude bins from 1024-point FFT of audio input.
/// Output is written to a UMA buffer for direct GPU binding.
///
/// Usage:
/// ```swift
/// let fft = try FFTProcessor(device: device)
/// let result = fft.process(samples: audioBuffer.latestSamples(count: 1024))
/// encoder.setBuffer(fft.magnitudeBuffer, offset: 0, index: 1)
/// ```
public final class FFTProcessor: FFTProcessing, @unchecked Sendable {

    // MARK: - Configuration

    /// FFT size (must be power of 2).
    public static let fftSize = 1024

    /// Number of output magnitude bins (fftSize / 2).
    public static let binCount = fftSize / 2

    // MARK: - vDSP Resources

    /// Shared window→magnitude kernel (BUG-066 / MOOD-FLUX.3 — the single formula
    /// the offline `analyzeMIR` path also uses). Owns the FFT setup and all per-frame
    /// scratch, so the real-time path stays allocation-free (BUG-036).
    private let kernel: FFTMagnitudeKernel

    // MARK: - Output Buffers

    /// UMA buffer holding 512 magnitude bins for GPU binding.
    public let magnitudeBuffer: UMABuffer<Float>

    /// Most recent FFT result metadata.
    public private(set) var latestResult = FFTResult()

    /// Lock for thread safety.
    private let lock = NSLock()

    // MARK: - Init

    /// Create an FFT processor with GPU-shared output buffers.
    ///
    /// - Parameter device: Metal device for UMA buffer allocation.
    public init(device: MTLDevice) throws {
        self.kernel = try FFTMagnitudeKernel(fftSize: Self.fftSize)

        // Allocate GPU-shared magnitude buffer.
        self.magnitudeBuffer = try UMABuffer<Float>(device: device, capacity: Self.binCount)

        logger.info("FFTProcessor created: \(Self.fftSize)-point FFT → \(Self.binCount) bins")
    }

    // MARK: - Processing

    /// Perform FFT on the given samples and write magnitudes to the UMA buffer.
    ///
    /// Input samples should be mono (or pre-mixed to mono). If fewer than
    /// `fftSize` samples are provided, the remainder is zero-padded.
    /// If more are provided, only the last `fftSize` samples are used.
    ///
    /// - Parameter samples: Mono float32 PCM samples.
    /// - Returns: FFT result metadata including dominant frequency.
    @discardableResult
    public func process(samples: [Float], sampleRate: Float = 48000) -> FFTResult {
        let fftLength = Self.fftSize

        // Fill windowed samples: use the latest `fftSize` samples, zero-pad if short.
        kernel.windowed.withUnsafeMutableBufferPointer { dst in
            // Zero the buffer first.
            dst.update(repeating: 0)

            let sampleCount = min(samples.count, fftLength)
            let sourceOffset = max(0, samples.count - fftLength)

            samples.withUnsafeBufferPointer { src in
                for i in 0..<sampleCount {
                    // CLEAN.4.5: sanitize the tap trust boundary — a NaN/Inf input sample
                    // otherwise propagates through the FFT into every GPU-bound feature.
                    let sample = src[sourceOffset + i]
                    dst[i] = sample.isFinite ? sample : 0
                }
            }
        }

        return runFFTCore(sampleRate: sampleRate)
    }

    /// Shared FFT core. Assumes `kernel.windowed` already holds the latest
    /// `fftSize` time-domain samples (zero-padded). Runs the shared window→magnitude
    /// kernel, writes magnitudes to the GPU buffer, and returns metadata.
    /// Allocation-free — the kernel reuses its own scratch (BUG-036).
    private func runFFTCore(sampleRate: Float) -> FFTResult {
        let fftLength = Self.fftSize

        // Window → forward FFT → |FFT| × 2/fftSize, via the single shared kernel
        // (BUG-066 / MOOD-FLUX.3 — same formula the offline path uses).
        kernel.computeMagnitudes()

        lock.lock()
        // Write to UMA buffer for GPU.
        magnitudeBuffer.write(kernel.magnitudes)

        // Find dominant frequency (FFTProcessor-specific metadata).
        var maxMag: Float = 0
        var maxIdx: vDSP_Length = 0
        vDSP_maxvi(kernel.magnitudes, 1, &maxMag, &maxIdx, vDSP_Length(Self.binCount))

        let binResolution = sampleRate / Float(fftLength)
        latestResult = FFTResult(
            binCount: UInt32(Self.binCount),
            binResolution: binResolution,
            dominantFrequency: Float(maxIdx) * binResolution,
            dominantMagnitude: maxMag
        )
        lock.unlock()

        return latestResult
    }

    // MARK: - Convenience: Process Stereo to Mono

    /// Mix interleaved stereo samples down to mono, then run FFT.
    ///
    /// - Parameters:
    ///   - interleavedSamples: Interleaved stereo float32 PCM (L, R, L, R, ...).
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: FFT result metadata.
    @discardableResult
    public func processStereo(interleavedSamples: [Float], sampleRate: Float = 48000) -> FFTResult {
        interleavedSamples.withUnsafeBufferPointer {
            processStereo(interleaved: $0, sampleRate: sampleRate)
        }
    }

    /// Zero-allocation stereo path for the real-time audio thread (BUG-036).
    /// Averages interleaved L/R straight into the reused windowed-sample scratch
    /// — no intermediate `mono` array — then runs the shared FFT core. Pass the
    /// most recent `fftSize * 2` interleaved samples; a shorter buffer zero-pads.
    @discardableResult
    public func processStereo(interleaved samples: UnsafeBufferPointer<Float>, sampleRate: Float = 48000) -> FFTResult {
        let fftLength = Self.fftSize
        let frameCount = samples.count / 2

        kernel.windowed.withUnsafeMutableBufferPointer { dst in
            dst.update(repeating: 0)

            // Use the latest `fftLength` frames; zero-pad (front) if short.
            let validFrames = min(frameCount, fftLength)
            let frameOffset = max(0, frameCount - fftLength)
            for i in 0..<validFrames {
                let left = samples[(frameOffset + i) * 2]
                let right = samples[(frameOffset + i) * 2 + 1]
                // CLEAN.4.5: sanitize the tap trust boundary (see process(samples:)).
                let mono = (left + right) * 0.5
                dst[i] = mono.isFinite ? mono : 0
            }
        }

        return runFFTCore(sampleRate: sampleRate)
    }
}

// MARK: - High-rate input (BR.17 / B9)

extension FFTProcessor {

    /// Zero-allocation mono path for input already reduced to the analysis rate (the
    /// `HighRateDecimator` output). Uses the latest `fftSize` samples; zero-pads (front) if short.
    @discardableResult
    public func processMono(_ samples: UnsafeBufferPointer<Float>, sampleRate: Float) -> FFTResult {
        let fftLength = Self.fftSize
        kernel.windowed.withUnsafeMutableBufferPointer { dst in
            dst.update(repeating: 0)
            let valid = min(samples.count, fftLength)
            let offset = samples.count - valid
            for i in 0..<valid {
                let sample = samples[offset + i]
                dst[i] = sample.isFinite ? sample : 0
            }
        }
        return runFFTCore(sampleRate: sampleRate)
    }
}

// MARK: - HighRateDecimator

/// Brings 88.2 kHz and faster live input down to 44.1 / 48 kHz before the FFT (BR.17 / B9), so
/// a 1024-point frame keeps its ~46 Hz bins and ~21 ms span — the same bass resolution, band
/// edges and chroma the 44.1 / 48 kHz paths get. At 96 kHz the undecimated frame had 93.75 Hz bins
/// (bass three bins wide) and at 192 kHz 187.5 Hz; BUG-146 fixed only preparation.
///
/// Averages each run of `factor` stereo frames to one mono sample (L+R and time together) into a
/// ring of `FFTProcessor.fftSize`. Allocation-free after init; owned by one real-time thread.
///
/// ponytail: a box-car average is a weak anti-alias filter (−3.9 dB at the new Nyquist); music
/// carries little above 20 kHz. A proper low-pass (vDSP_desamp) if aliasing ever shows up.
public struct HighRateDecimator {

    /// 1 below 80 kHz (44.1 / 48 unchanged), 2 for 88.2 / 96, 4 for 176.4 / 192.
    public static func factor(forRate rate: Float) -> Int {
        rate >= 160_000 ? 4 : (rate >= 80_000 ? 2 : 1)
    }

    /// The rate the analysis sees for a given tap rate.
    public static func analysisRate(forTapRate rate: Float) -> Float {
        rate / Float(factor(forRate: rate))
    }

    public private(set) var factor = 1
    private var ring: [Float]
    private var head = 0
    private var filled = 0
    private var sum: Float = 0
    private var summed = 0

    public init(capacity: Int = FFTProcessor.fftSize) {
        ring = [Float](repeating: 0, count: capacity)
    }

    /// Append interleaved stereo input; a changed `factor` (a device swap) starts a fresh history.
    public mutating func append(interleavedStereo samples: UnsafePointer<Float>, count: Int, factor newFactor: Int) {
        if newFactor != factor {
            factor = newFactor
            head = 0
            filled = 0
            sum = 0
            summed = 0
        }
        let frames = count / 2
        let norm = 1 / Float(2 * factor)
        for frame in 0..<frames {
            let left = samples[frame * 2], right = samples[frame * 2 + 1]
            sum += (left.isFinite ? left : 0) + (right.isFinite ? right : 0)
            summed += 1
            guard summed == factor else { continue }
            ring[head] = sum * norm
            head = (head + 1) % ring.count
            filled = min(filled + 1, ring.count)
            sum = 0
            summed = 0
        }
    }

    /// Copy the held samples, oldest first, into `dst`; returns how many.
    public func copyLatest(into dst: UnsafeMutableBufferPointer<Float>) -> Int {
        let count = min(filled, dst.count)
        let start = (head - count + ring.count) % ring.count
        for i in 0..<count { dst[i] = ring[(start + i) % ring.count] }
        return count
    }
}

// MARK: - FFTError

public enum FFTError: Error, Sendable {
    case setupFailed
}
