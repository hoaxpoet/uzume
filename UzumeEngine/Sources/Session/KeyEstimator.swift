// KeyEstimator — BUG-149: the key a prepared song stores and the preparation row shows.
//
// The live `ChromaExtractor` folds a 1024-point FFT (47 Hz bins) above 500 Hz — too coarse to
// separate neighbouring semitones, so a song's spectral TILT, not its notes, set the answer:
// pink noise read F# minor, and 35 % of a 993-track census did too. Synthetic chord
// progressions in all 24 keys scored 3 / 24, mostly a fifth off (only harmonics were heard).
//
// This estimator runs once per song at preparation, so it can afford resolution: an 8192-point
// FFT (5.4 Hz bins at 44.1 kHz) over the range where notes live, with spectral peaks rather
// than raw bins (a Hann main lobe smears a low note across several semitones), each frame
// weighted equally. The live chroma — read by the tonal visuals and the mood features — is
// untouched.

import Accelerate
import Audio
import Foundation

// MARK: - KeyEstimator

/// Whole-song key estimation from decoded audio (Krumhansl–Schmuckler on a peak chroma).
public enum KeyEstimator {

    // MARK: Constants

    static let fftSize = 8192
    static let hop = 4096
    /// A1 to A6: fundamentals and the low harmonics that confirm them.
    static let minHz: Float = 55
    static let maxHz: Float = 1760
    /// Below this the correlation is no better than a guess; no key is stored.
    static let minCorrelation: Float = 0.3
    /// Below this no notes stand out of the pitch profile, and no key is stored. Measured
    /// (2026-10-01): pink noise 0.08; synthetic progressions ≥ 1.13; on the 997-track census
    /// pilot the median is 0.63 and the 14 tracks under 0.2 are speech, comedy, free jazz,
    /// Ives, Nancarrow and Autechre.
    static let minContrast: Float = 0.2

    static let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    static let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    // MARK: Estimate

    /// The song's key ("A minor"), or nil for audio too short, silent or tonally ambiguous.
    public static func estimate(samples: [Float], sampleRate: Int) -> String? {
        guard let chroma = chroma(samples: samples, sampleRate: sampleRate),
              contrast(chroma) >= minContrast else { return nil }
        let (index, correlation) = bestKey(chroma)
        guard correlation >= minCorrelation else { return nil }
        return "\(pitchNames[index % 12]) \(index < 12 ? "major" : "minor")"
    }

    /// 12-bin pitch-class profile of the whole song, or nil when no frame carried energy.
    static func chroma(samples: [Float], sampleRate: Int) -> [Float]? {
        guard sampleRate > 0, samples.count >= fftSize,
              let fft = try? FFTMagnitudeKernel(fftSize: fftSize) else { return nil }
        let binHz = Float(sampleRate) / Float(fftSize)
        let lo = max(1, Int(minHz / binHz)), hi = min(fft.binCount - 2, Int(maxHz / binHz) + 1)
        var chroma = [Float](repeating: 0, count: 12)
        var semitones = [Float](repeating: 0, count: noteCount)
        var offset = 0
        while offset + fftSize <= samples.count {
            fft.windowed.withUnsafeMutableBufferPointer { dst in
                samples.withUnsafeBufferPointer { src in
                    guard let base = src.baseAddress, let out = dst.baseAddress else { return }
                    out.update(from: base + offset, count: fftSize)
                }
            }
            fft.computeMagnitudes()
            accumulatePeaks(fft.magnitudes, from: lo, to: hi, binHz: binHz, into: &semitones)
            let frame = foldWhitened(semitones)
            let total = frame.reduce(0, +)
            if total > 1e-9 { for pc in 0..<12 { chroma[pc] += frame[pc] / total } }
            offset += hop
        }
        return chroma.contains { $0 > 0 } ? chroma : nil
    }

    /// MIDI notes `minHz`...`maxHz` (A1 = 33 … A6 = 93).
    private static let lowestNote = 33
    private static let noteCount = 61

    /// Add each spectral peak's magnitude to its nearest semitone; `semitones` is overwritten.
    private static func accumulatePeaks(
        _ mags: [Float], from lo: Int, to hi: Int, binHz: Float, into semitones: inout [Float]
    ) {
        for index in semitones.indices { semitones[index] = 0 }
        guard hi > lo else { return }
        for bin in lo...hi where mags[bin] > mags[bin - 1] && mags[bin] >= mags[bin + 1] {
            // Parabolic interpolation of the peak's true frequency.
            let (left, mid, right) = (mags[bin - 1], mags[bin], mags[bin + 1])
            let denom = left - 2 * mid + right
            let shift = denom != 0 ? 0.5 * (left - right) / denom : 0
            let note = Int((69 + 12 * log2f((Float(bin) + shift) * binHz / 440)).rounded()) - lowestNote
            if semitones.indices.contains(note) { semitones[note] += mid }
        }
    }

    /// Fold semitones into 12 pitch classes, keeping only what stands above the surrounding
    /// octave. Without this whitening the spectrum's smooth tilt — more peaks per semitone as
    /// frequency rises, less energy per peak — leaves a fixed shape in the chroma that one key
    /// fits (pink noise read F# minor), whatever the notes are.
    private static func foldWhitened(_ semitones: [Float]) -> [Float] {
        var frame = [Float](repeating: 0, count: 12)
        for note in semitones.indices {
            let window = max(0, note - 6)...min(semitones.count - 1, note + 6)
            let local = semitones[window].reduce(0, +) / Float(window.count)
            frame[(note + lowestNote) % 12] += max(0, semitones[note] - local)
        }
        return frame
    }

    /// How far the pitch profile stands from flat (standard deviation over mean). A correlation
    /// is scale-free, so a near-flat noise profile still "fits" some key strongly; this is the
    /// measure of whether any notes stand out at all.
    static func contrast(_ chroma: [Float]) -> Float {
        let mean = chroma.reduce(0, +) / 12
        guard mean > 0 else { return 0 }
        return sqrtf(chroma.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / 12) / mean
    }

    /// Index of the best-correlating key (0–11 major, 12–23 minor, by root) and its correlation.
    static func bestKey(_ chroma: [Float]) -> (index: Int, correlation: Float) {
        var best = (index: 0, correlation: -Float.infinity)
        for index in 0..<24 {
            let profile = index < 12 ? majorProfile : minorProfile
            let rotated = (0..<12).map { profile[($0 - index % 12 + 12) % 12] }
            let corr = pearson(chroma, rotated)
            if corr > best.correlation { best = (index, corr) }
        }
        return best
    }

    private static func pearson(_ x: [Float], _ y: [Float]) -> Float {
        let mx = x.reduce(0, +) / 12, my = y.reduce(0, +) / 12
        var cov: Float = 0, vx: Float = 0, vy: Float = 0
        for i in 0..<12 {
            cov += (x[i] - mx) * (y[i] - my); vx += (x[i] - mx) * (x[i] - mx); vy += (y[i] - my) * (y[i] - my)
        }
        let denom = sqrtf(vx * vy)
        return denom > 1e-10 ? cov / denom : 0
    }
}
