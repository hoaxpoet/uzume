// TrackProfile — Pre-computed MIR features for a single track.
// Populated by SessionPreparer from the 30-second preview clip and stored
// in StemCache for instant access at playback start.

import Foundation
import Shared

// MARK: - TrackProfile

/// Pre-analyzed MIR summary for a track derived from its 30-second preview.
///
/// All fields are optional where the analysis may not converge in 30 seconds
/// (e.g., BPM estimation needs multiple beat onsets). The Orchestrator treats
/// nil fields as "unknown" and falls back to live MIR as playback progresses.
public struct TrackProfile: Sendable, Codable {

    // MARK: - Fields

    /// The song's tempo in BPM: the Beat This! grid's octave-folded tempo (BUG-144). nil when
    /// the grid has too few beats, or the D-154 gate judges the beat irregular (Matt: no BPM for
    /// songs without a steady beat) — the scorer then treats tempo as neutral.
    public var bpm: Float?

    /// Estimated musical key (e.g. "C major", "F# minor"), or nil if atonal/percussive.
    public var key: String?

    /// Emotional state (valence × arousal) from the mood classifier: the song's typical mood,
    /// i.e. the per-frame median after the first sixth (BUG-143). Covers the whole file on the
    /// local-file path and the 30 s preview on streaming.
    public var mood: EmotionalState

    /// Average normalized spectral centroid across the preview (0–1).
    public var spectralCentroidAvg: Float

    /// Genre tags from external APIs. Empty when no pre-fetch data is available.
    public var genreTags: [String]

    /// Per-stem energy balance from the preview separation (GPU buffer(3) layout).
    public var stemEnergyBalance: StemFeatures

    /// Coarse section count estimated from 30 seconds of structural analysis.
    /// Typically 1–3 for a 30-second preview window.
    public var estimatedSectionCount: Int

    /// Does the track lack a steady, trustworthy beat? (FBS / D-154.)
    /// Computed at consumption time from the cached grids via
    /// `assessBeatIrregularity` (octave-folded full-mix-vs-drums BPM
    /// disagreement + bar confidence). `true` ⇒ the scorer hard-excludes
    /// presets declaring `requires_regular_beat` — Membrane (PR.26, grid-locked
    /// strikes). FerrofluidOcean's flag was retired by the D-154 amendment
    /// (2026-06-11) after Matt watched it on Pyramid Song. `nil` = unknown —
    /// permissive, no exclusion.
    /// Optional so old persisted profiles decode unchanged.
    public var beatIrregular: Bool?

    // MARK: - Init

    public init(
        bpm: Float? = nil,
        key: String? = nil,
        mood: EmotionalState = .neutral,
        spectralCentroidAvg: Float = 0,
        genreTags: [String] = [],
        stemEnergyBalance: StemFeatures = .zero,
        estimatedSectionCount: Int = 0,
        beatIrregular: Bool? = nil
    ) {
        self.bpm = bpm
        self.key = key
        self.mood = mood
        self.spectralCentroidAvg = spectralCentroidAvg
        self.genreTags = genreTags
        self.stemEnergyBalance = stemEnergyBalance
        self.estimatedSectionCount = estimatedSectionCount
        self.beatIrregular = beatIrregular
    }

    // MARK: - Defaults

    /// Empty profile — all fields at zero or nil.
    public static let empty = TrackProfile()
}
