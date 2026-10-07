// FiddleheadFern+Layout — the GPU contract structs and the fern's SHAPE (spines + child placements per curl
// state), built once on the CPU. Pure: no Metal, so the shape is unit-testable.
//
// Ported from the FH.15 spike (`docs/presets/fiddlehead_spike/fern_descent.swift`). The constants are the spike's
// approved values; changing one changes the picture Matt signed off on.

import Foundation
import simd

// MARK: - GPU layout

/// Mirrors `FernParams` in FiddleheadFern.metal. Layout is the GPU contract.
struct FernParams {
    var box: SIMD4<Float> = .zero       // bmin.xy, bmax.xy
    var shape: SIMD4<Float> = .zero     // W0, CS, SINF, prune slack (texels)
    var grid: SIMD4<Float> = .zero      // children per state, states, field resolution, spine samples
    var curl: SIMD4<Float> = .zero      // LOPEN, LCURL, max levels, colour-unit size
    var lift: SIMD4<Float> = .zero      // level-0 → lifted ancestor: offset x, y, rotation, scale
    var zc: SIMD4<Float> = .zero        // dive centre x, y, view half-height, view rotation
    var tm: SIMD4<Float> = .zero        // time, phi of the lifted root, colour flow, pulse count
    var au: SIMD4<Float> = .zero        // bass, treble, hue base, hue spread
    var look: SIMD4<Float> = .zero      // palette luminance, candidate window, LOD pixels, lane normals on
}

/// Mirrors `FernChild` in FiddleheadFern.metal (32 bytes).
struct FernChild {
    var root: SIMD2<Float>
    var ang: Float
    var scale: Float
    var mirror: Float
    var arc: Float        // where it sits on its parent's stem (arc fraction): the impulse path's step
    var shift: Float      // how many curl states MORE rolled it renders than its parent
    var pad: Float = 0
}

/// Everything `FernShape.build()` produces for the GPU.
struct FernBuild {
    var spines: [SIMD2<Float>]      // every state's spine, flattened
    var children: [FernChild]       // per state (state-major), left/right pairs
    var boxMin: SIMD2<Float>
    var boxMax: SIMD2<Float>
}

// MARK: - Shape

/// The one frond, in units of its own length: a gently bowed stem that rolls into a log-spiral crozier, lined on
/// both sides with children that are the same frond scaled to the local coil radius.
struct FernShape {
    var spineSamples = 768
    var states = 20                 // curl states, 0 = open … states-1 = tightly rolled
    var bow: Float = 0.35           // K0
    var curlTightness: Float = 3.0  // ACURL (log-spiral 1/b)
    var eye: Float = 1.02           // SINF: where the spiral's eye sits in arc length (> 1)
    var rollStartRolled: Float = 0.3
    var rollStartOpen: Float = 0.9
    var rachisWidth: Float = 0.006  // W0
    var childScale: Float = 0.34    // CS
    var childSpacing: Float = 0.32  // SP (× child length)
    var lean: Float = 0.55          // rad off the normal, toward the tip
    var logOpen: Float = log(0.9)   // log(on-screen length / view height) at which a frond is fully open
    var logRolled: Float = log(0.05)

    func sigma(_ arc: Float) -> Float { childScale * (eye - arc) / eye }
    func width(_ arc: Float) -> Float { rachisWidth * (1 - 0.85 * arc) }

    /// Curl state → curl amount 0…1 (smoothstep).
    func curl(ofState state: Int) -> Float {
        let x = Float(state) / Float(states - 1)
        return x * x * (3 - 2 * x)
    }

    func kappa(_ arc: Float, curl amount: Float) -> Float {
        let rollStart = rollStartOpen + (rollStartRolled - rollStartOpen) * amount
        let ramp = min(max((arc - (rollStart - 0.15)) / 0.3, 0), 1), blend = ramp * ramp * (3 - 2 * ramp)
        return bow + blend * curlTightness / (eye - arc)
    }

    /// Spine positions and tangent angles for one curl amount.
    func spine(curl amount: Float) -> (points: [SIMD2<Float>], angles: [Float]) {
        var points = [SIMD2<Float>](repeating: .zero, count: spineSamples)
        var angles = [Float](repeating: 0, count: spineSamples)
        let step = 1 / Float(spineSamples - 1)
        for i in 1..<spineSamples {
            angles[i] = angles[i - 1] + kappa(Float(i - 1) * step + step * 0.5, curl: amount) * step
            let mid = (angles[i - 1] + angles[i]) * 0.5
            points[i] = points[i - 1] + SIMD2(cos(mid), sin(mid)) * step
        }
        return (points, angles)
    }

    /// Arc positions of the child sites (the same in every state; only where they land moves as the stem unrolls).
    var sites: [Float] {
        var out: [Float] = [], arc: Float = 0.05
        while arc < 0.985 && out.count < 127 { out.append(arc); arc += childSpacing * sigma(arc) }
        return out
    }

    /// Spines for every state, children per state, and the field's bounding box (covers every state's subtree reach).
    func build() -> FernBuild {
        var out = FernBuild(spines: [],
                            children: [],
                            boxMin: SIMD2(repeating: 1e9),
                            boxMax: SIMD2(repeating: -1e9))
        let span = logOpen - logRolled, siteList = sites
        for state in 0..<states {
            let (points, angles) = spine(curl: curl(ofState: state))
            out.spines += points
            for j in 0..<spineSamples {
                let reach = sigma(Float(j) / Float(spineSamples - 1)) * 1.6 + 0.03
                out.boxMin = simd_min(out.boxMin, points[j] - SIMD2(reach, reach))
                out.boxMax = simd_max(out.boxMax, points[j] + SIMD2(reach, reach))
            }
            for arc in siteList {
                let pos = arc * Float(spineSamples - 1), k = min(Int(pos), spineSamples - 2), frac = pos - Float(k)
                let root = points[k] * (1 - frac) + points[k + 1] * frac
                let ang = angles[k] * (1 - frac) + angles[k + 1] * frac
                let normal = SIMD2<Float>(-sin(ang), cos(ang)), size = sigma(arc)
                let shift = -log(size) / span * Float(states - 1)
                for side: Float in [1, -1] {
                    out.children.append(FernChild(root: root + normal * side * width(arc) * 0.8,
                                                  ang: ang + side * (Float.pi / 2 - lean),
                                                  scale: size,
                                                  mirror: side > 0 ? 1 : 0,
                                                  arc: arc,
                                                  shift: shift))
                }
            }
        }
        return out
    }

    /// On-screen size → curl state (mirrors `fh_state`).
    func state(length: Float, viewHeight: Float) -> Int {
        let logSize = log(max(length / viewHeight, 1e-6))
        return min(max(Int((logOpen - logSize) / (logOpen - logRolled) * Float(states - 1) + 0.5), 0), states - 1)
    }
}

// MARK: - Palettes

/// sRGB anchors, walked as a ping-pong gradient in the shader. Each anchored to a named look (FH.15 colour pass).
public enum FernPalette: Int, CaseIterable, Sendable {
    case psychedelic, bioluminescent, klimtGold, aurora, stainedGlass

    var anchors: [SIMD4<Float>] {
        switch self {
        case .psychedelic:
            return [[0.42, 0.12, 0.95, 0], [0.98, 0.12, 0.62, 0], [1.0, 0.58, 0.06, 0],
                    [0.15, 0.92, 0.38, 0], [0.05, 0.82, 0.98, 0], [0.18, 0.30, 1.0, 0]]
        case .bioluminescent:
            return [[0.05, 0.10, 0.45, 0], [0.0, 0.45, 0.95, 0], [0.0, 0.95, 0.90, 0],
                    [0.35, 0.95, 0.75, 0], [0.55, 0.25, 1.0, 0], [0.95, 0.20, 0.80, 0]]
        case .klimtGold:
            return [[0.02, 0.30, 0.35, 0], [0.05, 0.55, 0.40, 0], [0.55, 0.62, 0.15, 0],
                    [1.0, 0.80, 0.25, 0], [1.0, 0.52, 0.08, 0], [0.80, 0.15, 0.08, 0]]
        case .aurora:
            return [[0.25, 0.10, 0.55, 0], [0.85, 0.25, 0.55, 0], [0.60, 0.20, 0.85, 0],
                    [0.05, 0.70, 0.75, 0], [0.10, 0.95, 0.45, 0], [0.75, 1.0, 0.55, 0]]
        case .stainedGlass:
            return [[0.05, 0.15, 0.75, 0], [0.20, 0.25, 1.0, 0], [0.85, 0.05, 0.25, 0],
                    [1.0, 0.25, 0.10, 0], [1.0, 0.75, 0.10, 0], [0.05, 0.65, 0.35, 0]]
        }
    }
}
