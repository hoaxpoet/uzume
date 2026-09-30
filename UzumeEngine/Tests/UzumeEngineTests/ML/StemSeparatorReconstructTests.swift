// StemSeparatorReconstructTests — PREP.3: the batched inverse STFT against the per-channel path.
//
// PREP.3 runs a separation's inverse transforms in one batched graph and, for mono input,
// averages the L/R magnitudes before a single transform per stem — four inverse STFTs where
// there were eight. Both rest on the inverse STFT being linear, which holds to float rounding,
// not bit for bit. These pin both paths against the pre-PREP.3 per-channel reconstruction.
//
// Tolerance: max |Δ| ≤ 1e-6 × the waveform's peak — float32 rounding across one extra add
// and a reordered sum. Measured on the goldens: 2.4e-7 absolute on a 0.96 peak.

import Foundation
import Metal
import Testing
@testable import ML

@Suite("StemSeparator reconstruction (PREP.3)", .serialized)
struct StemSeparatorReconstructTests {

    /// Four stems' L/R magnitudes that differ per stem AND per channel (as the model's do even
    /// for mono input), over the phase of a real multi-tone signal.
    private static func spectra(_ separator: StemSeparator) -> StemSpectra {
        let signal = (0..<StemSeparator.requiredMonoSamples).map { index -> Float in
            let time = Float(index) / StemSeparator.modelSampleRate
            return 0.3 * sin(2 * .pi * 110 * time) + 0.2 * sin(2 * .pi * 1_760 * time)
                + 0.05 * sin(Float(index) * 0.37) * sin(2 * .pi * 3 * time)
        }
        let (magnitude, phase) = separator.stft(mono: signal)
        func masked(_ gain: Float, _ tilt: Float) -> [Float] {
            magnitude.enumerated().map { index, value in
                value * gain * (1 + tilt * Float(index % StemSeparator.nBins) / Float(StemSeparator.nBins))
            }
        }
        return StemSpectra(
            magL: (0..<4).map { masked(0.2 + 0.2 * Float($0), 0.5) },
            magR: (0..<4).map { masked(0.25 + 0.15 * Float($0), -0.3) },
            phaseL: phase,
            phaseR: phase)
    }

    private static func worstRelativeError(_ new: [[Float]], _ reference: [[Float]]) -> Float {
        zip(new, reference).map { lhs, rhs in
            let peak = rhs.map(abs).max() ?? 0
            let diff = zip(lhs, rhs).map { abs($0 - $1) }.max() ?? .infinity
            return peak > 0 ? diff / peak : diff
        }.max() ?? .infinity
    }

    /// Mono: average the magnitudes, then four transforms == eight transforms, then average.
    @Test func mono_fourTransforms_matchEightTransforms() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let separator = try StemSeparator(device: device)
        let spectra = Self.spectra(separator)
        let frames = StemSeparator.modelFrameCount

        let batched = separator.reconstructStemWaveforms(spectra, nbFrames: frames, mono: true)
        let reference = separator.reconstructStemWaveformsPerChannel(spectra, nbFrames: frames)

        #expect(batched.count == 4)
        #expect(batched.map(\.count) == reference.map(\.count))
        let worst = Self.worstRelativeError(batched, reference)
        #expect(worst <= 1e-6, "mono batched reconstruction off by \(worst) of peak")
    }

    /// Stereo (the live path): eight transforms in one batched run == eight separate runs.
    @Test func stereo_batchedRun_matchesSeparateRuns() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let separator = try StemSeparator(device: device)
        let spectra = Self.spectra(separator)
        let frames = StemSeparator.modelFrameCount

        let batched = separator.reconstructStemWaveforms(spectra, nbFrames: frames, mono: false)
        let reference = separator.reconstructStemWaveformsPerChannel(spectra, nbFrames: frames)

        #expect(batched.map(\.count) == reference.map(\.count))
        let worst = Self.worstRelativeError(batched, reference)
        #expect(worst <= 1e-6, "stereo batched reconstruction off by \(worst) of peak")
    }
}
