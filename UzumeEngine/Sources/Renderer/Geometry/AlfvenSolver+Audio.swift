// AlfvenSolver+Audio — ALFVEN.3 routing (design §7).
//
// One primitive per visual layer, each on its own timescale (FA #67):
//
//   stirring vigour -> seam density   bassRel           ~100 ms
//   palette hue centre                spectralCentroid   seconds
//
// The seam bloom was a third route (trebRel, ~30 ms). REMOVED at ALFVEN.3f on Matt's M7 —
// see `displayBloomAmount` for why the glow is now a constant again.
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

        // ALFVEN.3h — SILENCE GATE. `bassRel` is a DEVIATION primitive: it reads zero at
        // silence AND during steady music, so it cannot tell them apart, and the two-sided
        // map sends zero to its MIDPOINT (drive 9.0 of 18). ALFVEN.3 replaced the constant
        // `cfg.drive` (0.020 — the relaxed state) with `audioDrive` and thereby silently
        // broke the documented silence look: `05_atmosphere_relaxed_state.png` is labelled
        // in the reference README as *"Silence / low-drive state (D-037) … this is what
        // silence must look like"*, and it has been unreachable in production ever since.
        //
        // Detecting literal silence needs an ABSOLUTE level; FA #31 forbids absolute
        // thresholds for REACTIVITY, not for deciding whether there is any sound at all.
        // Test and constant are Witchlight's (WL.5, `mixEnergy <= 1e-6`), including its
        // hard-won detail: the live MIX bands collapse immediately at silence while the
        // stems HOLD their last values, so stems get no vote.
        let mixEnergy = features.bass + features.mid + features.treble
        let silent = mixEnergy <= 1e-6
        // Ramped, not switched: a step in drive is a step in the whole field's motion.
        // Falls to the relaxed state in ~`silenceTau`, recovers at the same rate.
        let gateTarget: Float = silent ? 0 : 1
        silenceGate = ema(silenceGate, gateTarget, configuration.silenceTau)

        bassEnvelope = ema(bassEnvelope, features.bassRel, configuration.bassTau)
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
        // Two-sided: `bassRel` sits negative when the bass is below its running average
        // and positive above, so the field keeps stirring through steady passages instead
        // of dropping to its silence look. See `bassRelShift` for the M7 this fixes.
        let scale = max(configuration.bassRelScale, 1e-4)
        let x = 0.5 * (1.0 + tanh((bassEnvelope + configuration.bassRelShift) / scale))
        let driven = configuration.driveFloor
            + (configuration.driveCeil - configuration.driveFloor) * min(max(x, 0), 1)
        // The gate interpolates toward the FLOOR, which is the relaxed state reference 05
        // depicts. At `silenceGate == 1` this is exactly the driven value, so nothing about
        // the music-playing behaviour measured in ALFVEN.3e changes.
        return configuration.driveFloor
            + (driven - configuration.driveFloor) * min(max(silenceGate, 0), 1)
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
