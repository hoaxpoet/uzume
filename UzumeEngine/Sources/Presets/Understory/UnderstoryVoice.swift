// UnderstoryVoice — the voice that uncoils Understory's fiddleheads (UND.5, design §4.4).
//
// Matt's locked choice: vocal phrases unfurl the fiddleheads; on instrumentals they stay coiled
// (§10-4 default). Presence is the vocal stem's energy against its own average
// (`vocalsEnergyRel`), D-019-gated on total stem energy, and VETOED by the instrument-family
// model's brass + woodwind + string activity: measured on the fixtures, the separated "vocals"
// stem carries a trumpet as strongly as a singer (so_what vocalsEnergy median 0.30 vs 0.30 / 0.32
// on the sung tracks), while brass separates them ~100× (median 0.167 vs 0.001–0.002). The
// envelope opens over ~1.5 s and closes over ~5 s; the four fiddleheads open in a stagger across
// it, left to right, so a sung line reads as a wave.

import Foundation
import Shared

// MARK: - UnderstoryVoice

/// Voice-presence envelope: 0 coiled … 1 open.
struct UnderstoryVoice {

    /// Envelope time constants (design §4.4).
    static let attack: Float = 1.5
    static let release: Float = 5.0

    private(set) var unfurl: Float = 0
    /// This frame's voice presence (0…1), before the envelope: the vocal-line sway's gate.
    private(set) var presence: Float = 0
    private var familyVeto: Float = 0
    private var vetoSeeded = false

    /// One render frame of `dt` seconds.
    mutating func step(_ stems: StemFeatures, dt: Float) {
        guard dt > 0 else { return }
        let family = stems.brassActivity + stems.woodwindsActivity + stems.stringsActivity
        // Seeded from the first sample (SAR.1): smoothing up from 0 let a horn track open the
        // fiddleheads for its first half second.
        if family.isFinite {
            familyVeto = vetoSeeded ? familyVeto + (family - familyVeto) * (1 - exp(-dt / 0.5)) : family
            vetoSeeded = true
        }
        let total = stems.drumsEnergy + stems.bassEnergy + stems.vocalsEnergy + stems.otherEnergy
        let sung = stems.vocalsEnergyRel.isFinite ? stems.vocalsEnergyRel : 0
        presence = Self.ramp(0.05, 0.35, sung) * (1 - Self.ramp(0.03, 0.10, familyVeto))
            * Self.ramp(0.02, 0.10, total)
        let tau = presence > unfurl ? Self.attack : Self.release
        unfurl += (presence - unfurl) * (1 - exp(-dt / tau))
    }

    /// How open fiddlehead number `order` (0…3, left to right) is at envelope `unfurl`: each
    /// opens over its own stretch of the envelope, so they uncoil in a wave.
    static func opening(order: Int, unfurl: Float) -> Float {
        let start = Float(order) * 0.12
        return ramp(start, start + 0.55, unfurl)
    }

    private static func ramp(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
        let unit = min(max((value - lower) / (upper - lower), 0), 1)
        return unit * unit * (3 - 2 * unit)
    }
}
