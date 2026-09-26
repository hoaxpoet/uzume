// FirefliesWorld — the Fireflies meadow as a 3D place: one camera, and the branch skeletons (FF.2).
//
// ONE CAMERA FOR EVERYTHING (FIREFLIES_DESIGN §4.2). The camera is computed here, once per
// frame, and read by all three consumers so the parallax cannot contradict itself:
//   • the world fragment (`Presets/Shaders/Fireflies.metal`) reads `FFWorldGPU` at buffer(6)
//     and casts one ray per pixel — sky, receding ground, far tree-line cards, mist;
//   • the branch skeletons below are drawn as 3D segments projected by the same numbers
//     (`fireflies_branch_vertex`, `Renderer/Shaders/Fireflies.metal`);
//   • the fireflies are projected on the CPU by `project(_:)`.
// The projection is written once in Swift (`project`) and once in MSL (`ff_project`); they are
// the same pinhole: x = (d·right)/(z·tanY·aspect), y = (d·up)/(z·tanY), z = d·forward.
//
// THE TREES are a stochastic recursive branching after Honda (1971) — each branch forks into
// two or three children at a spread angle with a length ratio — with lateral shoots along the
// parent (Weber & Penn 1995), radii by da Vinci's rule (r_parent^Δ = Σ r_child^Δ, Δ ≈ 2.5;
// Eloy 2011) and a mild tropism. Built ONCE at init from a fixed seed: the world is the same
// place every time, only the camera and the wind move it. `03` (the fine branching against a
// pale sky) and `07` (a big near tree to one side, smaller trees at depth) set the layout.
//
// Units: metres. Camera at the origin looking +z, +y up, ground plane y = 0.

import Foundation
import simd

// MARK: - GPU mirrors

/// 80 bytes — mirrors `FFWorld` in `Presets/Shaders/Fireflies.metal` and `FFCam` in
/// `Renderer/Shaders/Fireflies.metal`. `w` lanes carry scalars so the layout is five float4s.
public struct FFWorldGPU {
    /// xyz camera position, w = tan(half vertical FOV).
    public var camPos = SIMD4<Float>(0, 0, 0, 0)
    /// xyz right, w = aspect (width / height).
    public var right = SIMD4<Float>(0, 0, 0, 0)
    /// xyz up, w = world time in seconds (never resets on a track change).
    public var up = SIMD4<Float>(0, 0, 0, 0)
    /// xyz forward, w = world breath 0…1.
    public var forward = SIMD4<Float>(0, 0, 0, 0)
    /// x = wind phase (s), y = mist drift (m), zw unused. Both are INTEGRATED on the CPU so a
    /// change of breath changes their speed, never their position — no lurch.
    public var motion = SIMD4<Float>(0, 0, 0, 0)
}

/// 48 bytes — one branch segment; mirrors `FFBranch` in `Renderer/Shaders/Fireflies.metal`.
struct FFBranchGPU {
    var p0r0: SIMD4<Float>     // start xyz, start radius
    var p1r1: SIMD4<Float>     // end xyz, end radius
    var sway: SIMD4<Float>     // x = sway weight at start, y = at end, z = ink (0 = by depth), w unused
}

// MARK: - Camera

/// A pinhole camera. The fireflies, the branches and the world fragment all use this.
public struct FFCamera: Sendable {
    public var position: SIMD3<Float>
    public var right: SIMD3<Float>
    public var up: SIMD3<Float>
    public var forward: SIMD3<Float>
    public var tanHalfFovY: Float
    public var aspect: Float

    static let height: Float = 1.5
    /// Pitched up so the horizon sits ~66 % down the frame (`07`: sky dominant, ground below).
    static let pitch: Float = 6.6 * .pi / 180
    static let tanHalfFov: Float = tan(20 * Float.pi / 180)

    /// The camera at `offset` from the rest position, yawed by `yaw` radians.
    init(offset: SIMD3<Float>, yaw: Float, aspect: Float) {
        position = SIMD3(0, Self.height, 0) + offset
        let (cosP, sinP) = (cos(Self.pitch), sin(Self.pitch))
        let (cosY, sinY) = (cos(yaw), sin(yaw))
        forward = SIMD3(sinY * cosP, sinP, cosY * cosP)
        right = SIMD3(cosY, 0, -sinY)
        up = simd_cross(forward, right)
        tanHalfFovY = Self.tanHalfFov
        self.aspect = aspect
    }

    /// NDC x, y and view depth z (metres) of a world point. z ≤ 0 is behind the camera.
    func project(_ point: SIMD3<Float>) -> SIMD3<Float> {
        let rel = point - position
        let depth = simd_dot(rel, forward)
        return SIMD3(simd_dot(rel, right) / (depth * tanHalfFovY * aspect),
                     simd_dot(rel, up) / (depth * tanHalfFovY),
                     depth)
    }

    /// World ray direction through NDC (x, y).
    func ray(ndcX: Float, ndcY: Float) -> SIMD3<Float> {
        simd_normalize(forward + ndcX * tanHalfFovY * aspect * right + ndcY * tanHalfFovY * up)
    }

    var gpu: FFWorldGPU {
        FFWorldGPU(camPos: SIMD4(position, tanHalfFovY),
                   right: SIMD4(right, aspect),
                   up: SIMD4(up, 0),
                   forward: SIMD4(forward, 0),
                   motion: .zero)
    }
}

// MARK: - FirefliesWorld

/// The camera drift, the breath, and the static branch skeletons (trees and foreground grass). Not thread-safe: advanced and read on the
/// render thread only, via `FirefliesGeometry`.
final class FirefliesWorld {

    /// Seconds of world time; accumulates `deltaTime` and never resets (a track change restarts
    /// the swarm, not the place).
    private(set) var time: Float = 0
    /// Added to `time` for the camera only — harness stills show the same moment from a drifted
    /// camera (FF.2 Task 3 frame 2). 0 in production.
    var cameraTimeOffset: Float = 0
    /// Harness-only: hold the camera still so the wind's own motion can be measured. false in
    /// production.
    var freezeCamera = false
    private(set) var camera = FFCamera(offset: .zero, yaw: 0, aspect: 16.0 / 9.0)
    /// The world's breath, 0…1 (0.5 = the track's usual level): the one audio route the world
    /// has (FIREFLIES_DESIGN §4.3, Matt's "B"). See `advance`.
    private(set) var breath: Float = 0.5
    private var breathEMA: Float = 0
    private var windPhase: Float = 0
    private var mistDrift: Float = 0
    /// The fixed camera the swarm's screen-space coupling domain is unprojected through.
    private(set) var restCamera = FFCamera(offset: .zero, yaw: 0, aspect: 16.0 / 9.0)
    let branches: [FFBranchGPU]

    init(seed: UInt64 = 11) {
        branches = Self.plantTrees(seed: seed)
    }

    // MARK: Advance

    /// The slow drift — a few incommensurate sines, periods 31–59 s, so the path never visibly
    /// repeats. Amplitudes: ±1.1 m sideways, ±0.6 m in depth, ±0.12 m in height, ±1° of yaw;
    /// enough that the near tree slides across the far tree line, never enough to break the
    /// composition of §4.1.
    ///
    /// THE BREATH (Matt, 2026-09-25: "B"): `bassAttRel` — the smoothed bass deviation (D-026) —
    /// averaged again over τ = 4 s, so it swells over several seconds and can never pulse on
    /// the beat (the beat is the fireflies' alone, FA #67). It is soft-saturated,
    /// 0.5 + 0.5·tanh(4·x), because its span differs ~10× between tracks (4 s EMA p5–p95 on the
    /// parity captures: DYC 0.31, Pyramid Song 0.14, Warszawa 0.09, Teardrop 0.03) and a p99 is
    /// not a constant. At silence it sinks toward 0 and the world COASTS: the wind and mist slow
    /// but never stop (D-037, the per-preset silence doctrine). `bassAttRel` was chosen over
    /// `midAttRel` / `trebAttRel` because it is the only one that moves on all four captures.
    func advance(dt: Float, aspect: Float, bassAttRel: Float) {
        time += dt
        breathEMA += (bassAttRel - breathEMA) * (1 - exp(-dt / 4))
        breath = 0.5 + 0.5 * tanh(4 * breathEMA)
        // The breath sets how FAST the wind and the mist move (here) and how FAR the wind leans
        // the grass and sways the trees (the shaders, ∝ breath²). Ranges chosen so a quiet →
        // full passage roughly triples the sway (FF.2 measured the first, linear mapping as
        // invisible under the camera drift).
        windPhase += dt * (0.4 + 1.2 * breath)
        mistDrift += dt * (0.2 + 1.6 * breath)
        if freezeCamera { return }
        let clock = time + cameraTimeOffset
        let tau = 2 * Float.pi
        let offset = SIMD3<Float>(1.1 * sin(tau * clock / 47),
                                  0.12 * sin(tau * clock / 31 + 1),
                                  0.6 * sin(tau * clock / 59 + 2))
        let yaw = (1.0 * Float.pi / 180) * sin(tau * clock / 53 + 0.5)
        camera = FFCamera(offset: offset, yaw: yaw, aspect: aspect)
        restCamera = FFCamera(offset: .zero, yaw: 0, aspect: aspect)
    }

    var gpu: FFWorldGPU {
        var out = camera.gpu
        out.up.w = time
        out.forward.w = breath
        out.motion = SIMD4(windPhase, mistDrift, 0, 0)
        return out
    }

    // MARK: Planting

    /// `07`'s layout: one big tree near and to the left, a few smaller ones to the right at mid
    /// distance, and a ragged row of fine-branched trees along the far edge of the meadow in
    /// front of the tree-line cards (`03`'s branching against the pale sky). Far to near, so the
    /// segment array is already in painter's order.
    static func plantTrees(seed: UInt64) -> [FFBranchGPU] {
        var rng = SplitMix64(seed: seed)
        var out: [FFBranchGPU] = []
        // Each tree grows from its own generator, so replanting one never reshapes another.
        var treeIndex: UInt64 = 0
        func tree(_ base: SIMD3<Float>, height: Float, trunkRadius: Float, levels: Int) {
            treeIndex += 1
            var grower = Grower(rng: SplitMix64(seed: seed &* 0x9E37_79B9 &+ treeIndex), levels: levels)
            let lean = SIMD3<Float>(0.15 * grower.rng.gaussian(), 1, 0.1 * grower.rng.gaussian())
            let trunk = Shoot(start: base,
                              dir: simd_normalize(lean),
                              length: height * 0.55,
                              radius: trunkRadius,
                              level: 0,
                              sway: 0)
            grower.branch(trunk)
            out += grower.segments
        }
        // Far row: ~32 trees at 66–106 m across the whole drift range.
        var xPos: Float = -70
        while xPos < 70 {
            // Irregular spacing, depth and size: a hedgerow grown by nobody, not an orchard.
            let zPos = 66 + 40 * rng.unit() * rng.unit()
            let height = 4.5 + 7 * rng.unit()
            tree(SIMD3(xPos, 0, zPos), height: height, trunkRadius: 0.18 + 0.12 * rng.unit(), levels: 7)
            xPos += rng.unit() < 0.35 ? 1.2 + 1.5 * rng.unit() : 3.5 + 5 * rng.unit()
        }
        // Mid trees, right of centre (`07`).
        for (px, pz, height) in [(10.5, 36.0, 11.0), (16.0, 44.0, 12.0), (22.0, 33.0, 10.0), (-17.0, 48.0, 10.0)] {
            tree(SIMD3(Float(px), 0, Float(pz)), height: Float(height), trunkRadius: 0.32, levels: 7)
        }
        // The near tree, left, reaching out of the top of the frame.
        tree(SIMD3(-6.5, 0, 12), height: 6, trunkRadius: 0.42, levels: 8)
        out += plantForeground(seed: seed)
        return out
    }

    /// The bottom edge (§4.1): tall grass stalks and seed heads 3.5–7 m away. They stand on the
    /// darkest ground in the frame, so a near-black silhouette vanishes there (FF.2 still, round
    /// 6); `07` draws its foreground grass as LIGHT cut lines on that dark ground, and so do we —
    /// stalks in ink 2, seed heads in ink 3, catching the sky. The ground around them stays the
    /// darkest value, so value still runs near → far, dark → pale.
    /// Stalks curve as they rise; about one in four carries a seed head of fine splayed awns.
    /// The whole stalk sways with the wind, weighted by height; the root never moves.
    static func plantForeground(seed: UInt64) -> [FFBranchGPU] {
        var rng = SplitMix64(seed: seed ^ 0xF0F0_F0F0)
        var out: [FFBranchGPU] = []
        for _ in 0..<1100 {
            let zPos = 3.5 + 3.5 * rng.unit()
            let reach = 0.75 * zPos + 1.6                        // frame half-width + drift
            let xPos = (2 * rng.unit() - 1) * reach
            let height = (0.4 + 0.5 * rng.unit()) * (rng.unit() < 0.15 ? 1.4 : 1)
            var point = SIMD3<Float>(xPos, 0, zPos)
            var dir = simd_normalize(SIMD3<Float>(0.25 * rng.gaussian(), 1, 0.15 * rng.gaussian()))
            let curve = SIMD3<Float>(0.12 * rng.gaussian(), 0, 0.05 * rng.gaussian())
            let pieces = 4
            for piece in 0..<pieces {
                let (from, to) = (Float(piece) / Float(pieces), Float(piece + 1) / Float(pieces))
                dir = simd_normalize(dir + curve)
                let next = point + dir * (height / Float(pieces))
                out.append(FFBranchGPU(p0r0: SIMD4(point, 0.006 - 0.0045 * from),
                                       p1r1: SIMD4(next, 0.006 - 0.0045 * to),
                                       sway: SIMD4(0.5 * from * from, 0.5 * to * to, 2, 0)))
                point = next
            }
            guard rng.unit() < 0.25 else { continue }
            // Seed head: 5–8 awns splayed up and out from the tip.
            let awns = 5 + Int(rng.unit() * 4)
            for _ in 0..<awns {
                let awn = simd_normalize(dir + 0.9 * randomUnit(&rng) + SIMD3(0, 0.4, 0))
                let length = 0.03 + 0.05 * rng.unit()
                out.append(FFBranchGPU(p0r0: SIMD4(point, 0.0025),
                                       p1r1: SIMD4(point + awn * length, 0.0012),
                                       sway: SIMD4(0.5, 0.55, 3, 0)))
            }
        }
        return out
    }

    /// One branch to grow: where it starts, where it points, how long and thick, how deep in the
    /// recursion, and how much the wind moves its base.
    struct Shoot {
        var start: SIMD3<Float>
        var dir: SIMD3<Float>
        var length: Float
        var radius: Float
        var level: Int
        var sway: Float
    }

    /// Grows one tree into `segments` with its own generator.
    struct Grower {
        var rng: SplitMix64
        let levels: Int
        var segments: [FFBranchGPU] = []

        init(rng: SplitMix64, levels: Int) {
            self.rng = rng
            self.levels = levels
        }

        /// Honda's recursion: the branch is drawn as 3 slightly bent sub-segments, may put out one
        /// lateral shoot, then forks into 2–3 children at 22–48° with length ratio 0.62–0.82.
        mutating func branch(_ shoot: Shoot) {
            let depthFrac = Float(shoot.level) / Float(levels)
            let endRadius = shoot.radius * 0.8
            // Sway accrues with the SQUARE of depth: twigs move, limbs barely (a linear ramp bent
            // the near tree's big limbs ~20 px at full breath — a gale, not a night breeze).
            let tipSway = min(1, shoot.sway + 0.02 + 0.25 * depthFrac * depthFrac)
            var point = shoot.start, dir = shoot.dir
            let pieces = 3
            for piece in 0..<pieces {
                // Tortuosity grows toward the twigs; a slight droop on the long outer branches.
                let bend = (0.10 + 0.25 * depthFrac) * FirefliesWorld.randomUnit(&rng)
                dir = simd_normalize(dir + bend - SIMD3(0, 0.04 * depthFrac, 0))
                let next = point + dir * (shoot.length / Float(pieces))
                let (from, to) = (Float(piece) / Float(pieces), Float(piece + 1) / Float(pieces))
                let radius0 = shoot.radius + (endRadius - shoot.radius) * from
                let radius1 = shoot.radius + (endRadius - shoot.radius) * to
                let sway0 = shoot.sway + (tipSway - shoot.sway) * from
                let sway1 = shoot.sway + (tipSway - shoot.sway) * to
                segments.append(FFBranchGPU(p0r0: SIMD4(point, radius0),
                                            p1r1: SIMD4(next, radius1),
                                            sway: SIMD4(sway0, sway1, 0, 0)))
                point = next
            }
            guard shoot.level < levels, endRadius > 0.004 else { return }

            // One lateral shoot from the middle of the branch, below the fork (Weber & Penn).
            if shoot.level >= 1, rng.unit() < 0.55 {
                let mid = shoot.start + (point - shoot.start) * (0.35 + 0.3 * rng.unit())
                let side = FirefliesWorld.spread(dir, angle: 0.8 + 0.4 * rng.unit(), &rng)
                let lateral = Shoot(start: mid,
                                    dir: side,
                                    length: shoot.length * 0.5,
                                    radius: endRadius * 0.55,
                                    level: shoot.level + 2,
                                    sway: tipSway)
                branch(lateral)
            }
            // The fork. da Vinci: r^2.5 conserved across the split.
            let count = rng.unit() < 0.3 ? 3 : 2
            let childRadius = endRadius * pow(1 / Float(count), 1 / 2.5)
            for _ in 0..<count {
                let angle = 0.38 + 0.46 * rng.unit()
                var childDir = FirefliesWorld.spread(dir, angle: angle, &rng)
                // Tropism: the crown spreads up and out, like `07`'s bare oaks.
                childDir = simd_normalize(childDir + SIMD3(0, 0.18 * (1 - depthFrac), 0))
                let length = shoot.length * (0.62 + 0.2 * rng.unit())
                let child = Shoot(start: point,
                                  dir: childDir,
                                  length: length,
                                  radius: childRadius,
                                  level: shoot.level + 1,
                                  sway: tipSway)
                branch(child)
            }
        }
    }

    /// `dir` rotated by `angle` about a random axis perpendicular to it.
    static func spread(_ dir: SIMD3<Float>, angle: Float, _ rng: inout SplitMix64) -> SIMD3<Float> {
        var axis = simd_cross(dir, randomUnit(&rng))
        if simd_length(axis) < 1e-3 { axis = simd_cross(dir, SIMD3(1, 0, 0)) }
        axis = simd_normalize(axis)
        return simd_normalize(simd_quatf(angle: angle, axis: axis).act(dir))
    }

    static func randomUnit(_ rng: inout SplitMix64) -> SIMD3<Float> {
        simd_normalize(SIMD3(rng.gaussian(), rng.gaussian(), rng.gaussian()) + SIMD3(0, 0, 1e-4))
    }
}
