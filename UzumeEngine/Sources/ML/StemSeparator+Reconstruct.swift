// StemSeparator+Reconstruct — iSTFT reconstruction and mono averaging.
//
// After MPSGraph prediction produces 4 stem × 2 channel magnitude
// spectrograms, this extension applies iSTFT with the original phase
// and averages stereo to mono.
//
// Optimized with vDSP:
// - Mono averaging: vDSP_vadd + vDSP_vsmul

import Accelerate

// MARK: - Spectra

/// The model's four stems as L/R magnitude spectrograms, and the mixture's L/R phase.
struct StemSpectra {
    let magL: [[Float]]
    let magR: [[Float]]
    let phaseL: [Float]
    let phaseR: [Float]
}

// MARK: - Reconstruct

extension StemSeparator {

    /// iSTFT each stem with the original phase and return it as mono.
    ///
    /// PREP.3: every inverse transform of a separation runs in ONE batched graph run
    /// (`StemFFTEngine.inverseBatch`), with sin/cos of each phase grid computed once.
    ///
    /// **Mono input takes four transforms, not eight.** Mono deinterleaves to identical L/R, so
    /// the two channels share one phase (CLEAN.4.2), and the inverse STFT is linear in the
    /// spectrum: `(istft(magL, φ) + istft(magR, φ)) / 2 == istft((magL + magR) / 2, φ)`.
    /// Averaging the magnitudes first gives the same waveform to float rounding
    /// (`StemSeparatorTests` pins it against the per-channel path). Stereo — the live path —
    /// still transforms each channel with its own phase and averages the waveforms.
    ///
    /// Frame counts other than the model's (tiny test clips) keep the per-channel path.
    func reconstructStemWaveforms(_ spectra: StemSpectra, nbFrames: Int, mono: Bool) -> [[Float]] {
        guard nbFrames == Self.modelFrameCount else {
            return reconstructStemWaveformsPerChannel(spectra, nbFrames: nbFrames)
        }
        if mono {
            let averaged = zip(spectra.magL, spectra.magR).map { averageToMono(left: $0, right: $1) }
            return fftEngine.inverseBatch(
                magnitudes: averaged,
                phases: [spectra.phaseL],
                phaseIndex: Array(repeating: 0, count: averaged.count),
                originalLength: Self.requiredMonoSamples)
        }
        let channels = zip(spectra.magL, spectra.magR).flatMap { [$0, $1] }
        let waves = fftEngine.inverseBatch(
            magnitudes: channels,
            phases: [spectra.phaseL, spectra.phaseR],
            phaseIndex: channels.indices.map { $0 % 2 },
            originalLength: Self.requiredMonoSamples)
        return stride(from: 0, to: waves.count, by: 2).map { averageToMono(left: waves[$0], right: waves[$0 + 1]) }
    }

    /// The pre-PREP.3 reconstruction: one inverse STFT per stem per channel, waveforms averaged
    /// to mono. The reference the batched path is tested against, and the path for frame counts
    /// the fixed-size GPU graphs do not cover.
    func reconstructStemWaveformsPerChannel(_ spectra: StemSpectra, nbFrames: Int) -> [[Float]] {
        var stemWaveforms = [[Float]]()
        stemWaveforms.reserveCapacity(Self.stemCount)

        for stem in 0..<Self.stemCount {
            let waveL = istft(
                magnitude: spectra.magL[stem],
                phase: spectra.phaseL,
                nbFrames: nbFrames,
                originalLength: Self.requiredMonoSamples
            )
            let waveR = istft(
                magnitude: spectra.magR[stem],
                phase: spectra.phaseR,
                nbFrames: nbFrames,
                originalLength: Self.requiredMonoSamples
            )

            stemWaveforms.append(averageToMono(left: waveL, right: waveR))
        }

        return stemWaveforms
    }

    /// Average stereo to mono via vDSP.
    func averageToMono(left: [Float], right: [Float]) -> [Float] {
        let count = min(left.count, right.count)
        var mono = [Float](repeating: 0, count: count)
        let vLen = vDSP_Length(count)

        left.withUnsafeBufferPointer { leftBuf in
            right.withUnsafeBufferPointer { rightBuf in
                mono.withUnsafeMutableBufferPointer { dst in
                    guard let lPtr = leftBuf.baseAddress,
                          let rPtr = rightBuf.baseAddress,
                          let dPtr = dst.baseAddress else { return }
                    vDSP_vadd(lPtr, 1, rPtr, 1, dPtr, 1, vLen)
                    var half: Float = 0.5
                    vDSP_vsmul(dPtr, 1, &half, dPtr, 1, vLen)
                }
            }
        }

        return mono
    }
}

// MARK: - Padding

extension StemSeparator {

    /// Pad with zeros or truncate an array to exactly `targetCount` elements.
    func padOrTruncate(_ input: [Float], to targetCount: Int) -> [Float] {
        if input.count == targetCount {
            return input
        } else if input.count > targetCount {
            return Array(input.prefix(targetCount))
        } else {
            var result = input
            result.append(contentsOf: [Float](repeating: 0, count: targetCount - input.count))
            return result
        }
    }
}
