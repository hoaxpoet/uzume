// BPMMismatchCheck — tempo agreement between the full-mix and drums-stem Beat This! grids:
// the D-154 beat-irregularity gate and the octave-folded tempo statistics it and
// `TrackProfile.bpm` (BUG-144) share.
//
// BUG-144 removed the MIR-vs-grid mismatch diagnostics that used to live here
// (`detectBPMMismatch`, BUG-008.2; `detectThreeWayBPMDisagreement`, DSP.4). Their MIR
// input — `BeatDetector`'s sub-bass IOI tempo — sits at its 400 ms onset cooldown on every
// song (130–143 BPM), so the "disagreement" they logged measured the cooldown, and the
// profile no longer stores that tempo at all.

import DSP
import Foundation

// MARK: - Beat-Regularity Assessment (FBS / D-154)

/// Does this track have a steady, trustworthy beat — or should beat-locked
/// presets avoid it entirely?
///
/// Matt's product rule (2026-06-10): tracks without a steady beat should
/// **never see** beat-locked presets like Ferrofluid Ocean (Pyramid Song is
/// the canonical case). Consumed by `DefaultPresetScorer`'s hard-exclusion
/// gate via `TrackProfile.beatIrregular` + `PresetDescriptor.requiresRegularBeat`.
///
/// **The discriminating signal** (calibrated on real session
/// `2026-06-10T03-02-32Z`): agreement between the full-mix Beat This! grid and
/// the drums-stem Beat This! grid, after octave folding. On tracks where the
/// beat pulse worked or could work, the two agree to 0.1–0.7 % (Love Rehab,
/// There There, Money, Lotus Flower); on Pyramid Song they disagree by 57 %
/// raw / ~17 % after octave folding. The MIR estimator is deliberately NOT
/// consulted — it disagrees by 8–11 % even on tracks where the beat is solid,
/// so it cannot discriminate. Bar confidence (downbeat-interval consistency)
/// is a second, independent irregularity signal.
///
/// **Octave folding:** a drums grid legitimately reading 2× the full-mix grid
/// (half/double-time feel) is NOT irregularity — the ratio is folded into
/// [1, 2) before comparison, so only non-octave disagreement counts.
///
/// - Returns: `true` = irregular (exclude beat-locked presets), `false` =
///   regular, `nil` = unknown (missing estimators — be permissive; exclusion
///   requires evidence).
public func assessBeatIrregularity(
    gridBPM: Double,
    drumsBPM: Double,
    barConfidence: Float,
    foldedDisagreementThreshold: Double = 0.10,
    barConfidenceFloor: Float = 0.2
) -> Bool? {
    guard let disagreement = foldedBPMDisagreement(gridBPM, drumsBPM) else {
        return nil   // missing estimator — unknown, not irregular
    }
    if disagreement > foldedDisagreementThreshold { return true }
    if barConfidence < barConfidenceFloor { return true }
    return false
}

/// `assessBeatIrregularity` on the grids themselves — the production gate (StemCache)
/// and the CENSUS harness both call this, so they measure the same thing.
///
/// **BUG-140:** the tempos compared are `octaveFoldedMedianBPM` of each grid's beats,
/// NOT `BeatGrid.bpm`. `bpm` is `computeBPM`'s mean of IOIs across a full octave, so a
/// drums grid that reads eighths for part of the window and quarters for the rest
/// averages to a tempo describing neither (Superstition: 138 against a 98.5 grid).
public func assessBeatIrregularity(grid: BeatGrid, drums: BeatGrid?) -> Bool? {
    assessBeatIrregularity(
        gridBPM: octaveFoldedMedianBPM(beats: grid.beats) ?? 0,
        drumsBPM: drums.flatMap { octaveFoldedMedianBPM(beats: $0.beats) } ?? 0,
        barConfidence: grid.barConfidence
    )
}

/// The tempo a beat list is at, robust to the list switching metrical level.
///
/// Every inter-beat interval is folded by factors of 2 onto the octave of the median
/// interval, then the median of the folded set is taken. An eighth-note stretch and a
/// quarter-note stretch then agree instead of averaging to a non-octave tempo (BUG-140).
/// The reported octave is the median interval's, which is arbitrary — callers compare
/// through `foldedBPMDisagreement`, which ignores octaves anyway.
///
/// - Returns: BPM, or `nil` for fewer than 4 beats (the same floor as `computeBPM`).
public func octaveFoldedMedianBPM(beats: [Double]) -> Double? {
    guard let folded = octaveFoldedIOIs(beats: beats), let period = median(folded), period > 0 else {
        return nil
    }
    return 60.0 / period
}

/// The tempo a listener reads (BUG-144): the mean of the octave-folded intervals within ±15 % of
/// their median. The median alone lands on Beat This!'s 20 ms beat grid — B.O.B. read 150.0 for
/// a 153.8 grid — while the trimmed mean matches the grid's own average on steady songs and still
/// folds out eighth/quarter switches. `nil` for fewer than 4 beats.
public func octaveFoldedTempoBPM(beats: [Double]) -> Double? {
    guard let folded = octaveFoldedIOIs(beats: beats), let centre = median(folded), centre > 0 else {
        return nil
    }
    let kept = folded.filter { abs($0 - centre) <= centre * 0.15 }
    guard !kept.isEmpty else { return nil }
    return 60.0 / (kept.reduce(0, +) / Double(kept.count))
}

/// Every inter-beat interval folded by factors of 2 onto the octave of the median interval.
private func octaveFoldedIOIs(beats: [Double]) -> [Double]? {
    guard beats.count >= 4 else { return nil }
    let iois = zip(beats, beats.dropFirst()).map { $1 - $0 }.filter { $0 > 0 }
    guard let reference = median(iois), reference > 0 else { return nil }
    let root2 = 2.0.squareRoot()
    return iois.map { ioi -> Double in
        var value = ioi
        while value > reference * root2 { value /= 2 }
        while value < reference / root2 { value *= 2 }
        return value
    }
}

private func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let mid = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
}

/// Octave-folded disagreement between two BPM values, in `[0, 1)`.
///
/// The continuous evidence behind `assessBeatIrregularity` (D-154), extracted so
/// the production gate and the CENSUS batch harness compute it identically.
/// Folds the ratio into `[1, 2)` (half/double-time octave relations are clean),
/// then returns the distance to the nearer of `{1.0, 2.0}` — 0 for a 1:1 or exact
/// octave relation, larger for genuinely non-octave disagreement (Pyramid Song:
/// 57 % raw → ~0.17 folded).
///
/// - Returns: the folded disagreement, or `nil` if either input is non-finite or
///   non-positive (missing estimator).
public func foldedBPMDisagreement(_ lhs: Double, _ rhs: Double) -> Double? {
    guard lhs.isFinite, rhs.isFinite, lhs > 0, rhs > 0 else { return nil }
    var ratio = max(lhs, rhs) / min(lhs, rhs)
    while ratio >= 2.0 { ratio /= 2.0 }
    // A folded ratio just under 2.0 is also clean (it was an exact octave before a
    // tiny error pushed it below the fold), so measure to the nearer of {1.0, 2.0}.
    return min(ratio - 1.0, 2.0 - ratio)
}
