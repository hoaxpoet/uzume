// UnderstoryMotion — the band in the fronds (UND.6, Matt 2026-10-01).
//
// Matt, on the first full films: the beat sync "looks a little floppy"; then, of what he wants:
// "fronds move on musical signals, e.g., drum hits, bass notes/rhythm, vocal melody", and his pick
// of how to divide them: EACH INSTRUMENT GETS FRONDS, so you can see who is playing —
//   far row   flicks on DRUM HITS        `spectralLevelRise` rising past 0.3 (≥ 0.1 s apart)
//   mid row   pushes on BASS NOTES       `bassDev` through a fast-attack / 0.18 s-release follower
//   near row  sways with the VOCAL LINE  the vocal stem's centroid against its own 3 s average,
//                                        gated by `UnderstoryVoice` presence (a trumpet in the
//                                        vocal stem does not move the singer's fronds)
// all of it added to each frond's bend on top of the bass/treble wind.
//
// Signals chosen by measurement (design §12): the drum STEM is more drum-specific (56–75 % of
// level-rise hits coincide with drum-stem hits on the fixtures), but every stem runs ~2.5 s late
// on the streaming path, and lateness is the "floppy" Matt named. Level-rise and bassDev are live
// on both paths. The vocal line has no live equivalent: tight on local files, late on streaming.
//
// Each motion is a shaped PULSE added to the bend — never a kick into Flexi's springs, whose fast
// spring is lightly damped (0.99) and would ring for seconds after every hit. A bend change
// rotates the whole frond about its seed in the same frame; the tip whips through after it.

import Foundation
import Shared

// MARK: - UnderstoryMotion

struct UnderstoryMotion {

    // Drum flicks.
    static let hitThreshold: Float = 0.3
    static let hitRefractory: Float = 0.10
    static let flickAmplitude: Float = 0.06
    static let flickRise: Float = 0.03

    // Bass pushes.
    static let pushAmplitude: Float = 0.08
    static let pushAttack: Float = 0.015
    static let pushRelease: Float = 0.18

    // The vocal line.
    static let swayAmplitude: Float = 0.09
    static let swayScale: Float = 0.06

    private var prevRise: Float = 0
    private(set) var lastHit: Float = -100
    private(set) var hits = 0
    private var hitStrength: Float = 0
    private(set) var bassPush: Float = 0
    private var centroidMean: Float?
    private var line: Float = 0
    private(set) var sway: Float = 0

    /// One render frame of `dt` seconds ending at `clock`. `presence` is the voice gate (0…1).
    mutating func step(_ features: FeatureVector, _ stems: StemFeatures, presence: Float, clock: Float, dt: Float) {
        guard dt > 0 else { return }
        // Drums: a rising edge of the level-rise transient is a hit.
        let rise = features.spectralLevelRise.isFinite ? features.spectralLevelRise : 0
        if prevRise < Self.hitThreshold, rise >= Self.hitThreshold, clock - lastHit >= Self.hitRefractory {
            lastHit = clock
            hits += 1
            hitStrength = min(rise, 1)
        }
        prevRise = rise
        // Bass: each note's deviation spike becomes a push (x/(x+k): scaled to the track's own range).
        let dev = max(features.bassDev.isFinite ? features.bassDev : 0, 0)
        let target = dev / (dev + 0.15)
        let tau = target > bassPush ? Self.pushAttack : Self.pushRelease
        bassPush += (target - bassPush) * (1 - exp(-dt / tau))
        // The vocal line: centroid against its own slow average, gated by voice presence.
        let centroid = stems.vocalsCentroid.isFinite ? stems.vocalsCentroid : 0
        let mean = centroidMean ?? centroid
        centroidMean = mean + (centroid - mean) * (1 - exp(-dt / 3.0))
        line += (tanh((centroid - mean) / Self.swayScale) - line) * (1 - exp(-dt / 0.10))
        sway = line * presence
    }

    /// The bend this motion adds to frond `index` (in `layout`) at `clock`.
    func bend(index: Int, layout: UnderstoryLayout, clock: Float) -> Float {
        let frond = layout.fronds[index]
        switch frond.layer {
        case .far:
            // Flick: an alpha pulse peaking `flickRise` after the hit; neighbours flick opposite ways.
            let since = clock - lastHit
            guard since >= 0, since < 0.5 else { return 0 }
            let x = since / Self.flickRise
            let sign: Float = (index + hits).isMultiple(of: 2) ? 1 : -1
            return sign * Self.flickAmplitude * hitStrength * x * exp(1 - x)
        case .mid:
            // Push: the mid row leans outward from the centre on each bass note.
            return (frond.root.x < 0.5 ? -1 : 1) * Self.pushAmplitude * bassPush
        case .near:
            return Self.swayAmplitude * sway
        }
    }
}
