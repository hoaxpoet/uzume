// FiddleheadFern+Palette — the palette LOOKS and the rotation that chooses between them. Pure: no Metal, unit-testable.
//
// Matt (2026-10-07): keep several palettes and cycle through them; make them "bolder and more playful overall"; then
// "approve all, share the energy range". Fifteen looks, each anchored to a named work, in four families. No family
// is tied to an energy band — they take turns across the whole range: the look changes every 32 bars on a downbeat
// (every 60 s without a grid), stepping through a per-track order that interleaves the families so consecutive looks
// always differ in character; every change crossfades over 3 s. Brightness, not palette, follows the music's level.

import Foundation
import simd

// MARK: - Looks

/// One palette look: 6 sRGB anchors (walked as a ping-pong gradient in the shader) plus how they are worn.
struct FernLook: Equatable {
    var anchors: [SIMD4<Float>]
    var spread: Float           // palette colours per stem of the impulse path (higher = more colours per frame)
    var luminance: Float        // the palette's evened brightness (linear luminance target)
    var veinWhite: Float = 0    // white mixed into the vein light (0: the vein light is the palette's own colour)
    var glow: Float = 1.2
    var edge: Float = 1.2

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

/// Character groups. They share the whole energy range; the rotation interleaves them.
enum FernFamily: Int, CaseIterable { case playful, bold, jewel, subtle }

/// The approved catalogue (Matt, 2026-10-07: "approve all"). sRGB anchors, worn bold: no white in the vein light,
/// glow and edges 1.2. The original nine were saturated ×1.35 around each anchor's grey for the bolder pass.
public enum FernPalette: Int, CaseIterable, Sendable {
    case moscoso, flavin, matisse                                   // bold
    case stainedGlass, afKlint, klimt                               // jewel
    case turrell, monet, rothko                                     // subtle
    case memphis, murakami, lisaFrank, warhol, peterMax, delaunay   // playful

    var family: FernFamily {
        switch self {
        case .moscoso, .flavin, .matisse: return .bold
        case .stainedGlass, .afKlint, .klimt: return .jewel
        case .turrell, .monet, .rothko: return .subtle
        case .memphis, .murakami, .lisaFrank, .warhol, .peterMax, .delaunay: return .playful
        }
    }

    private static func make(_ rgb: [[Float]], spread: Float, luminance: Float) -> FernLook {
        FernLook(anchors: rgb.map { SIMD4($0[0], $0[1], $0[2], 0) }, spread: spread, luminance: luminance)
    }

    var look: FernLook {
        switch self {
        case .moscoso:      // Victor Moscoso, 1967 Fillmore posters
            return Self.make([[1.0, 0.0, 0.057], [0.0, 1.0, 0.377], [1.0, 0.0, 0.982],
                              [1.0, 0.562, 0.0], [0.039, 0.174, 1.0], [1.0, 1.0, 0.0]],
                             spread: 0.6,
                             luminance: 0.12)
        case .flavin:       // Dan Flavin, fluorescent light works
            return Self.make([[1.0, 0.0, 0.55], [1.0, 0.057, 0.0], [1.0, 0.982, 0.0],
                              [0.101, 1.0, 0.168], [0.0, 0.488, 1.0], [0.488, 0.0, 1.0]],
                             spread: 0.45,
                             luminance: 0.13)
        case .matisse:      // Matisse, The Snail (1953)
            return Self.make([[0.013, 0.147, 0.89], [1.0, 0.494, 0.0], [0.984, 0.0, 0.444],
                              [0.024, 0.699, 0.227], [1.0, 0.914, 0.0], [1.0, 0.186, 0.0]],
                             spread: 0.6,
                             luminance: 0.12)
        case .stainedGlass: // Sainte-Chapelle
            return Self.make([[0.0, 0.092, 0.902], [0.101, 0.168, 1.0], [1.0, 0.0, 0.203],
                              [1.0, 0.18, 0.0], [1.0, 0.797, 0.0], [0.0, 0.755, 0.35]],
                             spread: 1.4,
                             luminance: 0.11)
        case .afKlint:      // Hilma af Klint, The Ten Largest (1907)
            return Self.make([[1.0, 0.515, 0.38], [0.694, 0.492, 0.964], [1.0, 0.6, 0.06],
                              [0.368, 0.638, 1.0], [1.0, 0.536, 0.738], [0.932, 0.729, 0.189]],
                             spread: 0.8,
                             luminance: 0.11)
        case .klimt:        // Klimt, gold period
            return Self.make([[0.0, 0.327, 0.394], [0.0, 0.626, 0.423], [0.589, 0.683, 0.048],
                              [1.0, 0.841, 0.098], [1.0, 0.515, 0.0], [0.96, 0.082, 0.0]],
                             spread: 1.0,
                             luminance: 0.10)
        case .turrell:      // James Turrell, Skyspace at dusk
            return Self.make([[0.096, 0.069, 0.406], [0.394, 0.192, 0.664], [0.87, 0.398, 0.533],
                              [1.0, 0.633, 0.43], [0.559, 0.694, 0.897], [0.198, 0.332, 0.67]],
                             spread: 0.5,
                             luminance: 0.08)
        case .monet:        // Monet, Water Lilies (Orangerie)
            return Self.make([[0.633, 0.565, 0.902], [0.483, 0.685, 0.483], [0.236, 0.573, 0.641],
                              [0.897, 0.559, 0.694], [0.498, 0.7, 0.902], [0.612, 0.747, 0.342]],
                             spread: 0.7,
                             luminance: 0.08)
        case .rothko:       // Rothko Chapel
            return Self.make([[0.329, 0.059, 0.262], [0.529, 0.057, 0.084], [0.254, 0.078, 0.388],
                              [0.074, 0.101, 0.344], [0.626, 0.086, 0.288], [0.356, 0.086, 0.558]],
                             spread: 0.4,
                             luminance: 0.05)
        case .memphis:      // Memphis Group (Ettore Sottsass, 1980s)
            return Self.make([[1.0, 0.40, 0.70], [0.20, 0.85, 0.80], [1.0, 0.85, 0.15],
                              [0.15, 0.30, 0.90], [1.0, 0.25, 0.20], [0.60, 0.30, 0.90]],
                             spread: 0.8,
                             luminance: 0.13)
        case .murakami:     // Takashi Murakami, Flowers
            return Self.make([[1.0, 0.30, 0.60], [1.0, 0.85, 0.10], [0.20, 0.80, 1.0],
                              [0.40, 0.90, 0.30], [0.65, 0.35, 1.0], [1.0, 0.55, 0.15]],
                             spread: 1.1,
                             luminance: 0.13)
        case .lisaFrank:    // Lisa Frank
            return Self.make([[1.0, 0.15, 0.75], [0.55, 0.15, 1.0], [0.10, 0.90, 0.95],
                              [0.55, 1.0, 0.20], [1.0, 0.95, 0.20], [1.0, 0.40, 0.10]],
                             spread: 0.9,
                             luminance: 0.13)
        case .warhol:       // Andy Warhol, Marilyn screenprints
            return Self.make([[1.0, 0.35, 0.65], [0.10, 0.85, 0.80], [1.0, 0.90, 0.20],
                              [1.0, 0.55, 0.15], [0.60, 0.95, 0.30], [0.95, 0.25, 0.45]],
                             spread: 0.7,
                             luminance: 0.13)
        case .peterMax:     // Peter Max, 1960s pop
            return Self.make([[1.0, 0.50, 0.0], [0.95, 0.15, 0.60], [0.50, 0.20, 0.85],
                              [1.0, 0.90, 0.15], [0.30, 0.70, 1.0], [0.95, 0.30, 0.20]],
                             spread: 0.8,
                             luminance: 0.13)
        case .delaunay:     // Sonia Delaunay, Rhythm
            return Self.make([[1.0, 0.55, 0.10], [0.10, 0.30, 0.85], [0.90, 0.15, 0.20],
                              [1.0, 0.85, 0.20], [0.15, 0.60, 0.40], [0.25, 0.55, 0.95]],
                             spread: 0.6,
                             luminance: 0.13)
        }
    }

    static func members(of family: FernFamily) -> [FernPalette] { allCases.filter { $0.family == family } }

    /// Every look, interleaving the families round-robin (playful, bold, jewel, subtle, playful, …), so consecutive
    /// entries always differ in family while the families have members left.
    static let rotation: [FernPalette] = {
        let groups = FernFamily.allCases.map(members(of:))
        let longest = groups.map(\.count).max() ?? 0
        return (0..<longest).flatMap { i in groups.compactMap { i < $0.count ? $0[i] : nil } }
    }()
}

// MARK: - Choosing

/// Steps through `FernPalette.rotation` from a per-track start: one step every 32 bars on a downbeat (every 60 s
/// without a grid); every change crossfades over 3 s.
struct FernPalettePlan {
    private(set) var current: FernPalette = .stainedGlass
    private var previous: FernPalette = .stainedGlass
    private var fadeStart: Float = -100
    private var index = 0
    private var barsInLook = 0
    private var lookStart: Float = 0
    private var sawDownbeat = false
    private var seeded = false

    static let fadeSeconds: Float = 3
    static let barsPerLook = 32
    static let secondsPerLookWithoutGrid: Float = 60

    /// - Parameters: `trackKey` 0…1 identifies the track (its starting point in the rotation); `downbeat` is true on
    ///   the frame the cached grid's bar wraps.
    mutating func update(time: Float, trackKey: Float, downbeat: Bool) {
        let looks = FernPalette.rotation
        if !seeded {
            index = Int(min(max(trackKey, 0), 0.999) * Float(looks.count))
            current = looks[index]
            previous = current
            lookStart = time
            seeded = true
            return
        }
        if downbeat { barsInLook += 1; sawDownbeat = true }
        let due = sawDownbeat
            ? barsInLook >= Self.barsPerLook && downbeat
            : time - lookStart >= Self.secondsPerLookWithoutGrid
        guard due else { return }
        index = (index + 1) % looks.count
        previous = current
        current = looks[index]
        fadeStart = time
        barsInLook = 0
        lookStart = time
    }

    /// The look to render now (mid-crossfade when a change is under way).
    func look(at time: Float) -> FernLook {
        let raw = min(max((time - fadeStart) / Self.fadeSeconds, 0), 1)
        let eased = raw * raw * (3 - 2 * raw)
        return eased >= 1 ? current.look : previous.look.mixed(with: current.look, eased)
    }

    mutating func reset() { self = FernPalettePlan() }
}
