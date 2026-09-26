// SessionPreparer+ProfileRules — the rules that turn analysis into stored profile values:
// the rate MIR runs at (BUG-146), the stored tempo (BUG-145) and the stored mood (BUG-144).
// Split from SessionPreparer+Analysis to keep that file under the lint length limit.

import DSP
import Foundation
import ML
import Shared

extension SessionPreparer {

    // MARK: - Profile rules

    /// The preview at the rate MIR runs at (BUG-146): the stems' 44.1 kHz whatever the file's rate.
    /// A 1024-point FFT at the file's rate moved the mood features with it — at 96 kHz the
    /// Nyquist-normalised centroid halved and 93.75 Hz bins pushed the key correlations
    /// +1.6/+1.9 σ, so the same song read arousal 0.21 instead of 0.52.
    nonisolated static func mirInput(_ preview: PreviewAudio) -> (samples: [Float], sampleRate: Int) {
        let rate = Int(StemSeparator.modelSampleRate)
        guard preview.sampleRate != rate else { return (preview.pcmSamples, rate) }
        return (BeatThisPreprocessor.resample(
            preview.pcmSamples, from: Double(preview.sampleRate), to: Double(rate)), rate)
    }

    /// The BPM a prepared track stores (BUG-145; Matt: no BPM for songs without a steady beat).
    /// The beat tracker's octave-folded tempo — never the MIR BeatDetector's, whose sub-bass
    /// onsets fire at their 400 ms cooldown on every song (130–143 BPM whatever the music).
    /// nil when the D-154 gate calls the beat irregular: the scorer's neutral, no readout.
    nonisolated static func storedTempo(grid: BeatGrid, drums: BeatGrid) -> Float? {
        guard assessBeatIrregularity(grid: grid, drums: drums) != true else { return nil }
        return octaveFoldedTempoBPM(beats: grid.beats).map(Float.init)
    }

    /// The song's typical mood (BUG-144, Matt's option A): the per-frame median of valence and
    /// arousal after the first sixth, which is the classifier's warm-up (the KAG.0 spike's
    /// `load_session` rule). `classifier.currentState` after the loop was a 0.7 s EMA, so it
    /// described only the last second or two. On the beta playlist its rank agreement with the
    /// production chain was 0.59; this statistic scores 0.85. `.neutral` when no frame was classified.
    nonisolated static func songMood(_ trace: [EmotionalState]) -> EmotionalState {
        guard !trace.isEmpty else { return .neutral }
        let settled = trace[(trace.count / 6)...]
        func median(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
        }
        return EmotionalState(
            valence: median(settled.map(\.valence)),
            arousal: median(settled.map(\.arousal))
        )
    }
}
