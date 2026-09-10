// AlfvenSolver+Audio — ALFVEN.3 routing (design §7).
//
// One primitive per visual layer, each on its own timescale (FA #67):
//
//   stirring vigour -> seam density   bassDev           ~100 ms
//   seam bloom / sizzle               trebRel            ~30 ms
//   palette hue centre                spectralCentroid   seconds
//
// Every driver is a DEVIATION primitive (D-026); no absolute threshold is taken on an
// AGC-normalised value (FA #31). The envelopes live here on the CPU rather than in the
// shader because the solver already runs a Swift per-frame tick, and because a smoothed
// envelope is what §7's timescales describe — the raw primitives are far spikier than the
// visual behaviour they are meant to drive.

import Foundation
import Shared

extension AlfvenSolver {

    /// Advance the three audio envelopes and map them onto the solver's constants.
    ///
    /// Called once per frame from `update(features:…)`. `dt` is real seconds — the
    /// listener's clock, not `simClock`: these are perceptual couplings, and a coupling
    /// that sped up when the field energised would read as the music losing time.
    func advanceAudio(_ features: FeatureVector, dt: Float) {
        let step = max(dt, 1e-4)
        func ema(_ current: Float, _ target: Float, _ tau: Float) -> Float {
            let alpha = 1.0 - exp(-step / max(tau, 1e-4))
            return current + alpha * (target - current)
        }

        bassEnvelope = ema(bassEnvelope, max(0, features.bassDev), configuration.bassTau)
        trebleEnvelope = ema(trebleEnvelope,
                             max(0, features.trebRel),
                             configuration.trebleTau)
        centroidEnvelope = ema(centroidEnvelope,
                               features.spectralCentroid,
                               configuration.centroidTau)
    }

    /// Forcing amplitude for this frame — the stirring vigour §7 routes to `bassDev`.
    ///
    /// Soft-saturating rather than linear: the measured tau-100ms envelope sits at p50
    /// 0.033 against a p95 of 0.296, so a linear map from zero would hold the field at its
    /// silence look through most of a track. `tanh(env/knee)` puts the common range across
    /// the usable span and lets the rare p99 spikes approach the ceiling without clipping
    /// the everyday response into it.
    var audioDrive: Float {
        let x = tanh(bassEnvelope / max(configuration.bassKnee, 1e-4))
        return configuration.driveFloor
            + (configuration.driveCeil - configuration.driveFloor) * x
    }

    /// Seam-bloom strength — film.py's `amt = 0.30 + 0.85 * clip(sizzle, 0, 1.6)` with its
    /// own `sizzle = trebRel - 0.6`, restored now that there is audio to feed it. At
    /// silence this is the 0.30 floor ALFVEN.4f shipped; at full treble it reaches 1.66.
    var audioBloomAmount: Float {
        let sizzle = min(max(trebleEnvelope - 0.6, 0), 1.6)
        return 0.30 + 0.85 * sizzle
    }

    /// Palette centre: spectral centroid PLACES it, the ALFVEN.4e time drift keeps it
    /// moving. Both, deliberately — and this is the one routing decision here that is not
    /// simply §7.
    ///
    /// §7 routes the hue centre to spectral centroid, and film.py agrees. But two things
    /// measured against real music say centroid alone is not enough:
    ///
    ///  1. Ours is NOT the 0…1 primitive film.py's `0.46 + 0.26*centroid01` assumes —
    ///     p05 0.047 / p95 0.186 across 8 sessions. Used raw it moves the centre by 0.028:
    ///     no visible drift, centred near 0.49 rather than the magenta<->teal Matt signed
    ///     off. So the observed range is renormalised onto film.py's own span.
    ///  2. Even renormalised, its WITHIN-TRACK span is track-dependent: median 0.35 of the
    ///     range over the 7 canonical fixtures, but `there_there` 0.16 and
    ///     `10_-_Weeping_Wall` 0.27. On that material a centroid-only palette reads as
    ///     frozen — which is precisely the thing Matt asked for and approved at 4e
    ///     ("a cycling of colors over time... i LOVE the color palette right now").
    ///     Replacing the time drift with centroid would have quietly deleted his feature
    ///     on the tracks that need it most.
    ///
    /// A convex combination keeps the centre inside the referenced family whatever both
    /// terms do, so the traverse can never leave the palette of
    /// `04_palette_opponent_drift`. Centroid leads; the time term is the floor on motion.
    /// FA #67 is satisfied — only ONE audio primitive drives this layer; wall-clock is not
    /// a primitive.
    func audioHueCentre(at time: Float) -> Float {
        let span = max(configuration.centroidHi - configuration.centroidLo, 1e-4)
        let x = min(max((centroidEnvelope - configuration.centroidLo) / span, 0), 1)

        let period = max(configuration.displayHuePeriodSeconds, 0.001)
        let traverse = 0.5 * (1.0 - cos(2.0 * Float.pi * time / period))
        let drift = pow(traverse, max(configuration.displayHueDwell, 0.01))

        let lead = configuration.centroidWeight
        let blended = lead * (1.0 - x) + (1.0 - lead) * drift
        // Skew typical excursions back toward the anchor; the extremes still reach the far
        // end. See `hueAnchorBias` for the measured distribution behind the exponent.
        let excursion = pow(blended, max(configuration.hueAnchorBias, 0.01))
        return displayHueCentre - configuration.displayHueSpan * excursion
    }
}
