// UnderstoryLayout — the seeded field of fronds for Understory (UND.2, design §4.1).
//
// Matt, 2026-10-01 (§10-3): "a field of ferns swaying in the wind and … a combination of
// open and closed fiddleheads" — not a blanket. Fourteen fronds in three depths with dark
// ground between them: 2 near (the lead frond + a fiddlehead), 6 mid (4 open, 2 fiddleheads),
// 6 far (5 open, 1 fiddlehead). Positions, sizes, leans, spring stiffness and which slots are
// fiddleheads all come from the track seed, so a track always grows its own field and the
// next track grows a different one (FA #44: jittered, never mirrored or uniform).
//
// The atlas (the `fronds` stage target) is packed in rows by depth so every frond is drawn
// at a similar upscale: near row 2 tiles, two mid rows of 3, a far row of 6. Each tile holds
// the part of Flexi's 4:3 frame the frond can reach — the full width, from a little below the
// seed (frame y 0.60; the seed sits at 0.5) upward — so almost no tile pixels are spent below
// the seed (design §5.4 lever (a): the frame is cropped, the maps are untouched). The crop height
// is chosen so the tile's pixels stay square at any drawable aspect.

import Foundation

// MARK: - UnderstoryLayout

/// One track's field: per-frond atlas tile, frame crop, screen placement and character.
public struct UnderstoryLayout: Sendable, Equatable {

    /// Depth layer, drawn far → near (painter's order, design §4.1).
    public enum Layer: Int, Sendable { case far = 0, mid = 1, near = 2 }

    /// One frond's placement and character.
    public struct Frond: Sendable, Equatable {
        /// Atlas tile in drawable uv: origin.xy, size.xy.
        public var tile: SIMD4<Float>
        /// Region of Flexi's 4:3 frame the tile holds: x0, y0, x1, y1.
        public var crop: SIMD4<Float>
        /// Seed position on screen (drawable uv; y > 1 is below the bottom edge).
        public var root: SIMD2<Float>
        /// Flexi's frame height in screen heights (the frond is ~0.47 of it).
        public var scale: Float
        /// Lean on screen, radians.
        public var rotation: Float
        public var layer: Layer
        public var brightness: Float
        /// Resting curl added to `ww` every generation; 0 = an open frond (design §4.4).
        public var curl: Float
        /// Spring stiffness multiplier, 1 ± 15 % (design §4.2).
        public var stiffness: Float
        /// Gust delay in 60 Hz substeps: root x over the wind speed (design §4.2).
        public var delaySubsteps: Int
        /// This frond's place on the palette wheel, in turns (design §4.5).
        public var hueOffset: Float
        /// Colour saturation; the far layer is paler so depth survives the saturation.
        public var saturation: Float
        public var isFiddlehead: Bool { curl != 0 }
    }

    public static let frondCount = 14

    /// Flexi's frame y below the seed (centre 0.5, radius 0.029), with room for a coil beside
    /// it: at 0.56 a fiddlehead's coil touched the crop edge (UND.2).
    static let cropBottom: Float = 0.60

    /// One atlas row: its depth, its tile count, and its height as a drawable fraction.
    struct Row {
        let layer: Layer
        let count: Int
        let height: Float
    }

    /// Atlas rows, top → bottom.
    static let rows: [Row] = [
        Row(layer: .near, count: 2, height: 0.375),
        Row(layer: .mid, count: 3, height: 0.25),
        Row(layer: .mid, count: 3, height: 0.25),
        Row(layer: .far, count: 6, height: 0.125)
    ]

    /// Per-depth ranges for a frond's frame scale and root height, and its brightness.
    struct Style {
        let scale: ClosedRange<Float>
        let rootY: ClosedRange<Float>
        let brightness: Float
        let saturation: Float
    }

    static func style(_ layer: Layer) -> Style {
        switch layer {
        case .far: Style(scale: 0.55...0.70, rootY: 0.72...0.82, brightness: 0.45, saturation: 0.60)
        case .mid: Style(scale: 0.95...1.15, rootY: 0.94...1.00, brightness: 0.70, saturation: 0.85)
        case .near: Style(scale: 1.45...1.75, rootY: 1.04...1.10, brightness: 1.00, saturation: 0.95)
        }
    }

    /// Fiddleheads per layer (the rest are open fronds).
    static let fiddleheads: [Layer: Int] = [.near: 1, .mid: 2, .far: 1]

    public let seed: UInt32
    public let aspect: Float
    /// Fronds in draw order: far first, near last.
    public let fronds: [Frond]
    /// The lead frond (the downbeat's, design §4.3): the open near frond.
    public let leadIndex: Int

    public init(seed: UInt32, aspect: Float) {
        self.seed = seed
        self.aspect = aspect
        var rng = SplitMix64(seed: UInt64(seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x5EED)
        var byLayer: [Layer: [Frond]] = [:]
        var rowTop: Float = 0
        for row in Self.rows {
            for column in 0..<row.count {
                let width = 1 / Float(row.count)
                let tile = SIMD4(Float(column) * width, rowTop, width, row.height)
                // Square tile pixels: tile aspect = aspect / (count · height); the crop spans the
                // frame's full width (4/3 frame heights) so its height is (4/3) / tile aspect.
                let tileAspect = aspect / (Float(row.count) * row.height)
                let cropHeight = (4.0 / 3.0) / tileAspect
                let crop = SIMD4(0, Self.cropBottom - cropHeight, 1, Self.cropBottom)
                let frond = Self.place(tile: tile, crop: crop, layer: row.layer, rng: &rng)
                byLayer[row.layer, default: []].append(frond)
            }
            rowTop += row.height
        }
        var ordered: [Frond] = []
        for layer in [Layer.far, .mid, .near] {
            var fronds = byLayer[layer] ?? []
            Self.spread(&fronds, layer: layer, rng: &rng)
            ordered += fronds
        }
        fronds = ordered
        leadIndex = ordered.lastIndex { $0.layer == .near && !$0.isFiddlehead } ?? ordered.count - 1
    }

    // MARK: Placement

    /// Character of one frond in a layer (position comes from `spread`).
    private static func place(tile: SIMD4<Float>, crop: SIMD4<Float>, layer: Layer,
                              rng: inout SplitMix64) -> Frond {
        let style = Self.style(layer)
        let rootY = rng.next(in: style.rootY)
        let scale = rng.next(in: style.scale)
        let stiffness = rng.next(in: 0.85...1.15)
        let hueOffset = rng.next(in: 0...1)
        return Frond(
            tile: tile,
            crop: crop,
            root: SIMD2(0, rootY),
            scale: scale,
            rotation: 0,
            layer: layer,
            brightness: style.brightness,
            curl: 0,
            stiffness: stiffness,
            delaySubsteps: 0,
            hueOffset: hueOffset,
            saturation: style.saturation
        )
    }

    /// Spread a layer across the screen: jittered slots, shuffled, a seeded subset made into
    /// fiddleheads, a lean that fans away from the centre, and the gust delay from root x.
    private static func spread(_ fronds: inout [Frond], layer: Layer, rng: inout SplitMix64) {
        let count = fronds.count
        var slots = (0..<count).map { (Float($0) + 0.5) / Float(count) + rng.next(in: -0.32...0.32) / Float(count) }
        rng.shuffle(&slots)
        var curled = Array(repeating: false, count: count)
        for index in rng.sample(count: Self.fiddleheads[layer] ?? 0, of: count) { curled[index] = true }
        for i in fronds.indices {
            let x = min(max(slots[i], 0.03), 0.97)
            fronds[i].root.x = x
            fronds[i].rotation = (x - 0.5) * 0.6 + rng.next(in: -0.15...0.15)
            fronds[i].delaySubsteps = Int((x / UnderstoryField.windSpeed * UnderstoryField.substepHz).rounded())
            if curled[i] {
                // Provisional resting coil (UND.5 fits κ against ref 02 and uncoils it with the voice).
                fronds[i].curl = (rng.next(in: 0...1) < 0.5 ? -1 : 1) * rng.next(in: 0.22...0.30)
                fronds[i].scale *= 0.8
            }
        }
        fronds.sort { $0.root.y < $1.root.y }   // within a layer, higher roots (further) first
    }
}

// MARK: - SplitMix64

/// Small deterministic PRNG — the layout must be byte-identical for a seed.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Float>) -> Float {
        let unit = Float(next() >> 40) / Float(1 << 24)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func shuffle<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for i in stride(from: array.count - 1, to: 0, by: -1) {
            array.swapAt(i, Int(next() % UInt64(i + 1)))
        }
    }

    /// `count` distinct indices from `0..<total`.
    mutating func sample(count: Int, of total: Int) -> [Int] {
        var indices = Array(0..<total)
        shuffle(&indices)
        return Array(indices.prefix(count))
    }
}
