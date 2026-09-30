// StemSeparator+Batch — PREP.3 batched separation for the offline sweep.
//
// Each window goes through the same steps `separate` takes for mono input — pad or truncate,
// STFT, the model, four inverse transforms over the mixture phase — except that the model runs
// once for all the windows (`StemModelEngine.predictBatch`). Live separation keeps calling
// `separate`, whose batch-1 graph and buffers this never touches; both hold `lock` across their
// model section, so a live call and a prep batch serialise rather than interleave (BUG-031).

import Foundation
import Audio
import Shared

extension StemSeparator {

    /// Separate several mono windows with one batched model run. See
    /// `StemSeparating.separateBatch`.
    public func separateBatch(monoWindows: [[Float]], sampleRate: Float) throws -> [StemSeparationResult] {
        // Off the model's rate the per-call resample would run anyway; batching buys nothing
        // there that is worth a second resample path. The sweep always hands model-rate audio.
        guard abs(sampleRate - Self.modelSampleRate) <= 1.0, !monoWindows.isEmpty else {
            return try monoWindows.map { try separate(audio: $0, channelCount: 1, sampleRate: sampleRate) }
        }
        for window in monoWindows where window.count < Self.hopLength {
            throw StemSeparationError.insufficientSamples(window.count)
        }
        return try autoreleasepool { try separateBatchInPool(monoWindows) }
    }

    private func separateBatchInPool(_ monoWindows: [[Float]]) throws -> [StemSeparationResult] {
        let spectra = monoWindows.map { window in
            SeparationSplit.measure("stft") { stft(mono: padOrTruncate(window, to: Self.requiredMonoSamples)) }
        }
        let stems = try lock.withLock {
            let raceID = ConcurrencyAuditProbe.enterSeparate()
            defer { ConcurrencyAuditProbe.exitSeparate(id: raceID, outcome: "exit-batch") }
            do {
                return try stemModel.predictBatch(monoMagnitudes: spectra.map(\.magnitude), batch: monoWindows.count)
            } catch {
                throw StemSeparationError.predictionFailed(error.localizedDescription)
            }
        }
        return zip(spectra, stems).map { spectrum, stem in
            let waveforms = SeparationSplit.measure("istft") {
                reconstructStemWaveforms(
                    StemSpectra(magL: stem.magL, magR: stem.magR, phaseL: spectrum.phase, phaseR: spectrum.phase),
                    nbFrames: Self.modelFrameCount,
                    mono: true)
            }
            return Self.buildResult(sampleCount: waveforms[0].count, stemWaveforms: waveforms)
        }
    }
}
