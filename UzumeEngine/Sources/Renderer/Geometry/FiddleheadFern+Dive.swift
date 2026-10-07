// FiddleheadFern+Dive — the camera's endless dive and the music state. Pure: no Metal, unit-testable.
//
// THE DIVE: the camera falls toward the fixed point of one child (k*), so after one cycle (`period` seconds) the view
// is exactly the same picture one level down and the zoom loops forever. Each level is evaluated in the curl state its
// on-screen size gives it NOW, so fronds unroll as the camera reaches them. The frame is lifted a few ancestors up so
// the surroundings exist at every depth.
//
// THE MUSIC (audio data hierarchy): continuous energy is the primary driver — bass deviation swells the light riding
// the colour bands, treble deviation drives the leaflet-edge shimmer, the section level (`spectralSurge`) sets the
// exposure. Beat-locked pulses ride the cached beat GRID (wraps of `beatPhase01`), never raw onsets; each is a nerve
// impulse running trunk → branches → leaflet tips, downbeats stronger. With no grid, no pulses: the continuous layers
// still carry the music. Cold start fires ungated (the Cold-Start Phase Contract).

import Foundation
import Shared
import simd

// MARK: - Dive

struct FernDive {
    let shape: FernShape
    let children: [FernChild]
    let perState: Int
    let kStar: Int
    let period: Float           // seconds per level dived
    let viewHalf: Float         // view half-height at the start of a cycle (units of the level-0 frond)
    let lifts = 3

    var sigmaStar: Float { children[kStar].scale }
    var arcStar: Float { children[kStar].arc }

    init(shape: FernShape, children: [FernChild], kStar requested: Int = 5, period: Float = 7, viewHalf: Float = 0.55) {
        self.shape = shape
        self.children = children
        perState = children.count / shape.states
        var pick = min(requested, perState - 1)
        if children[pick].mirror > 0.5 { pick ^= 1 }                        // non-mirrored: one cycle maps onto itself
        kStar = pick
        self.period = period
        self.viewHalf = viewHalf
    }

    /// A similarity x ↦ origin + R(angle)·scale·x.
    struct Similarity { var origin: SIMD2<Float>; var angle: Float; var scale: Float }

    private func rotate(_ vec: SIMD2<Float>, _ angle: Float) -> SIMD2<Float> {
        SIMD2(cos(angle) * vec.x - sin(angle) * vec.y, sin(angle) * vec.x + cos(angle) * vec.y)
    }
    private func apply(_ sim: Similarity, _ point: SIMD2<Float>) -> SIMD2<Float> {
        sim.origin + rotate(point * sim.scale, sim.angle)
    }

    /// Child k* of the level-`level` frond, in the state its on-screen size gives it at cycle fraction `frac`.
    func step(level: Int, frac: Float) -> Similarity {
        let length = pow(sigmaStar, Float(level)), viewH = 2 * viewHalf * pow(sigmaStar, frac)
        let child = children[shape.state(length: length, viewHeight: viewH) * perState + kStar]
        return Similarity(origin: child.root, angle: child.ang, scale: child.scale)
    }

    struct Frame { var lift: SIMD4<Float>; var centre: SIMD4<Float>; var phi0: Float; var cycle: Float }

    func frame(time: Float) -> Frame {
        let cycles = time / period, cycle = floor(cycles), frac = cycles - cycle
        var point = SIMD2<Float>(0.3, 0.1)                                  // G0∘G1∘…: the dive point
        for level in stride(from: 9, through: 0, by: -1) { point = apply(step(level: level, frac: frac), point) }
        let rotEnd = step(level: 0, frac: 1).angle                          // the view turns with the dive
        var lift = Similarity(origin: .zero, angle: 0, scale: 1)
        for ancestor in 1...lifts {
            let up = step(level: -ancestor, frac: frac)
            lift = Similarity(origin: apply(up, lift.origin),
                              angle: up.angle + lift.angle,
                              scale: up.scale * lift.scale)
        }
        return Frame(lift: SIMD4(lift.origin.x, lift.origin.y, lift.angle, lift.scale),
                     centre: SIMD4(point.x, point.y, viewHalf * pow(sigmaStar, frac), rotEnd * frac),
                     phi0: (cycle - Float(lifts)) * arcStar,
                     cycle: cycle)
    }
}

// MARK: - Music

struct FernMusic {
    struct Pulse { var phi: Float; var time: Float; var amp: Float }

    private(set) var pulses: [Pulse] = []
    private var lastBeatPhase: Float = 0
    private var lastBarPhase: Float = 0
    private var bassMean: Float = 0
    private var trebMean: Float = 0
    private(set) var bass: Float = 0
    private(set) var treble: Float = 0
    private(set) var level: Float = 0

    /// Pulse front speed in path units per second (≈ one stem per 2 s).
    let speed: Float = 0.5
    static let maxPulses = 32

    /// A deviation primitive, self-normalised against its own slow mean (treble deviation runs ~100× below bass;
    /// tuning either against an absolute is FA #31). Mean level → 0.25, 3× → 0.5, 10× → 0.77.
    private static func squash(_ value: Float, mean: inout Float, dt: Float) -> Float {
        mean += (value - mean) * min(dt / 8, 1)
        return value / (value + 3 * max(mean, 1e-5))
    }

    mutating func update(features: FeatureVector, time: Float, dt: Float, dive: FernDive) {
        bass = Self.squash(max(features.bassDev, 0), mean: &bassMean, dt: dt)
        treble = Self.squash(max(features.trebDev, 0), mean: &trebMean, dt: dt)
        level += (min(max(features.spectralSurge, 0), 1) - level) * min(dt / 0.5, 1)
        // a beat = beatPhase01 wrapping; a downbeat = barPhase01 wrapping on the same frame
        let beat = features.beatPhase01 + 0.5 < lastBeatPhase
        let downbeat = features.barPhase01 + 0.5 < lastBarPhase
        lastBeatPhase = features.beatPhase01
        lastBarPhase = features.barPhase01
        if beat {
            pulses.append(Pulse(phi: (time / dive.period - 1) * dive.arcStar, time: time, amp: downbeat ? 0.7 : 0.3))
        }
        pulses.removeAll { time - $0.time > 8 }
        if pulses.count > Self.maxPulses { pulses.removeFirst(pulses.count - Self.maxPulses) }
    }

    /// (front position along the path, strength) per live pulse, for the shader.
    func fronts(at time: Float) -> [SIMD2<Float>] {
        pulses.map { SIMD2($0.phi + speed * (time - $0.time), $0.amp) }
    }

    mutating func reset() { self = FernMusic() }
}
