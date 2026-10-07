// FiddleheadFern+Palette — the palette LOOKS and the logic that chooses between them. Pure: no Metal, unit-testable.
//
// Matt (2026-10-07): keep several palettes, choose with decision logic, cycle through them. The nine looks are the
// set he preferred ("quite nice" — several colours woven through every frame), each anchored to a named work, in
// three families. The family follows the music's ENERGY (light most intense when the music is loud and driving —
// Matt); within a family the looks rotate every 32 bars on a downbeat, in a per-track order; every change crossfades.

import Foundation
import simd

// MARK: - Looks

/// One palette look: 6 sRGB anchors (walked as a ping-pong gradient in the shader) plus how they are worn.
struct FernLook: Equatable {
    var anchors: [SIMD4<Float>]
    var spread: Float           // palette colours per stem of the impulse path (higher = more colours per frame)
    var luminance: Float        // the palette's evened brightness (linear luminance target)
    var veinWhite: Float = 0.2  // white mixed into the vein light
    var glow: Float = 1
    var edge: Float = 1

    func mixed(with other: FernLook, _ amount: Float) -> FernLook {
        func lerp(_ from: Float, _ to: Float) -> Float { from + (to - from) * amount }
        return FernLook(anchors: zip(anchors, other.anchors).map { $0 + ($1 - $0) * amount },
                        spread: lerp(spread, other.spread),
                        luminance: lerp(luminance, other.luminance),
                        veinWhite: lerp(veinWhite, other.veinWhite),
                        glow: lerp(glow, other.glow),
                        edge: lerp(edge, other.edge))
    }
}

enum FernFamily: Int, CaseIterable { case subtle, jewel, bold }

/// The catalogue (FH.16 palette round, the set Matt preferred). sRGB anchors.
public enum FernPalette: Int, CaseIterable, Sendable {
    case flavin, moscoso, matisse, stainedGlass, afKlint, klimt, turrell, monet, rothko

    var family: FernFamily {
        switch self {
        case .flavin, .moscoso, .matisse: return .bold
        case .stainedGlass, .afKlint, .klimt: return .jewel
        case .turrell, .monet, .rothko: return .subtle
        }
    }

    private static func make(_ rgb: [[Float]], spread: Float, luminance: Float) -> FernLook {
        FernLook(anchors: rgb.map { SIMD4($0[0], $0[1], $0[2], 0) }, spread: spread, luminance: luminance)
    }

    var look: FernLook {
        switch self {
        case .moscoso:      // Victor Moscoso, 1967 Fillmore posters
            return Self.make([[1.0, 0.10, 0.15], [0.10, 0.90, 0.40], [1.0, 0.10, 0.90],
                              [1.0, 0.55, 0.0], [0.15, 0.25, 1.0], [1.0, 0.95, 0.10]],
                             spread: 0.6,
                             luminance: 0.10)
        case .flavin:       // Dan Flavin, fluorescent light works
            return Self.make([[1.0, 0.10, 0.55], [1.0, 0.15, 0.10], [1.0, 0.90, 0.10],
                              [0.20, 1.0, 0.25], [0.10, 0.50, 1.0], [0.50, 0.10, 1.0]],
                             spread: 0.45,
                             luminance: 0.11)
        case .matisse:      // Matisse, The Snail (1953)
            return Self.make([[0.10, 0.20, 0.75], [1.0, 0.50, 0.05], [0.85, 0.10, 0.45],
                              [0.10, 0.60, 0.25], [1.0, 0.85, 0.15], [0.95, 0.25, 0.10]],
                             spread: 0.6,
                             luminance: 0.09)
        case .stainedGlass: // Sainte-Chapelle
            return Self.make([[0.05, 0.15, 0.75], [0.20, 0.25, 1.0], [0.85, 0.05, 0.25],
                              [1.0, 0.25, 0.10], [1.0, 0.75, 0.10], [0.05, 0.65, 0.35]],
                             spread: 1.4,
                             luminance: 0.08)
        case .afKlint:      // Hilma af Klint, The Ten Largest (1907)
            return Self.make([[0.95, 0.55, 0.45], [0.70, 0.55, 0.90], [1.0, 0.60, 0.20],
                              [0.45, 0.65, 0.95], [1.0, 0.60, 0.75], [0.85, 0.70, 0.30]],
                             spread: 0.8,
                             luminance: 0.08)
        case .klimt:        // Klimt, gold period
            return Self.make([[0.02, 0.30, 0.35], [0.05, 0.55, 0.40], [0.55, 0.62, 0.15],
                              [1.0, 0.80, 0.25], [1.0, 0.52, 0.08], [0.80, 0.15, 0.08]],
                             spread: 1.0,
                             luminance: 0.07)
        case .turrell:      // James Turrell, Skyspace at dusk
            return Self.make([[0.12, 0.10, 0.35], [0.40, 0.25, 0.60], [0.80, 0.45, 0.55],
                              [0.95, 0.65, 0.50], [0.60, 0.70, 0.85], [0.25, 0.35, 0.60]],
                             spread: 0.5,
                             luminance: 0.045)
        case .monet:        // Monet, Water Lilies (Orangerie)
            return Self.make([[0.65, 0.60, 0.85], [0.50, 0.65, 0.50], [0.30, 0.55, 0.60],
                              [0.85, 0.60, 0.70], [0.55, 0.70, 0.85], [0.60, 0.70, 0.40]],
                             spread: 0.7,
                             luminance: 0.05)
        case .rothko:       // Rothko Chapel
            return Self.make([[0.30, 0.10, 0.25], [0.45, 0.10, 0.12], [0.25, 0.12, 0.35],
                              [0.10, 0.12, 0.30], [0.55, 0.15, 0.30], [0.35, 0.15, 0.50]],
                             spread: 0.4,
                             luminance: 0.022)
        }
    }

    static func members(of family: FernFamily) -> [FernPalette] { allCases.filter { $0.family == family } }
}

// MARK: - Choosing

/// Chooses the look each frame. Family ← energy (the measured 1–10 section energy; live loudness when unknown), with
/// hysteresis and a dwell so it never flaps; look within the family ← rotation every 32 bars on a downbeat (every
/// 60 s without a grid), in a per-track order; every change crossfades over 3 s.
struct FernPalettePlan {
    private(set) var current: FernPalette = .stainedGlass
    private var previous: FernPalette = .stainedGlass
    private var fadeStart: Float = -100
    private var family: FernFamily = .jewel
    private var candidate: FernFamily = .jewel
    private var candidateSince: Float = 0
    private var barsInLook = 0
    private var rotation = 0
    private var sawDownbeat = false
    private var lookStart: Float = 0
    private var trackSeed = 0
    private var seeded = false

    static let fadeSeconds: Float = 3
    static let dwellSeconds: Float = 6
    static let barsPerLook = 32

    /// Energy on a 1–10 scale: the measured section energy, or live loudness (spectralSurge 0…1) when that is unknown.
    static func energy(level: Float, surge: Float) -> Float { level > 0 ? level : 1 + 9 * min(max(surge, 0), 1) }

    /// Family for an energy, with ±0.5 hysteresis around the current family's edges.
    static func family(for energy: Float, current: FernFamily) -> FernFamily {
        let boldAt: Float = current == .bold ? 6.5 : 7.0
        let subtleAt: Float = current == .subtle ? 4.0 : 3.5
        if energy >= boldAt { return .bold }
        if energy <= subtleAt { return .subtle }
        return .jewel
    }

    /// - Parameters: `trackKey` 0…1 identifies the track (seeds the rotation order); `downbeat` is true on the frame
    ///   the cached grid's bar wraps.
    mutating func update(time: Float, energy: Float, trackKey: Float, downbeat: Bool) {
        if !seeded {
            trackSeed = Int(trackKey * 997)
            family = Self.family(for: energy, current: .jewel)
            candidate = family
            current = Self.pick(family, rotation: 0, seed: trackSeed)
            previous = current
            lookStart = time
            seeded = true
            return
        }
        let wanted = Self.family(for: energy, current: family)
        if wanted != candidate { candidate = wanted; candidateSince = time }
        if downbeat { barsInLook += 1; sawDownbeat = true }
        let familyDue = candidate != family && time - candidateSince >= Self.dwellSeconds
        let rotationDue = sawDownbeat ? barsInLook >= Self.barsPerLook : time - lookStart >= 60
        // with a grid, changes land on a downbeat; without one they land when due
        guard (familyDue || rotationDue) && (downbeat || !sawDownbeat) else { return }
        if familyDue { family = candidate; rotation = 0 } else { rotation += 1 }
        let next = Self.pick(family, rotation: rotation, seed: trackSeed)
        if next != current {
            previous = current
            current = next
            fadeStart = time
        }
        barsInLook = 0
        lookStart = time
    }

    /// The look to render now (mid-crossfade when a change is under way).
    func look(at time: Float) -> FernLook {
        let raw = min(max((time - fadeStart) / Self.fadeSeconds, 0), 1)
        let eased = raw * raw * (3 - 2 * raw)
        return eased >= 1 ? current.look : previous.look.mixed(with: current.look, eased)
    }

    private static func pick(_ family: FernFamily, rotation: Int, seed: Int) -> FernPalette {
        let members = FernPalette.members(of: family)
        return members[(seed + rotation) % members.count]
    }

    mutating func reset() { self = FernPalettePlan() }
}
