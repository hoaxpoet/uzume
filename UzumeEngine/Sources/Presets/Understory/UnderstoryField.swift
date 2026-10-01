// UnderstoryField — CPU state for the Understory staged scene (UND.1).
//
// Flexi's "fractal seafood" bends its fern with a two-spring system driven by bass
// against treble, evaluated once per Milkdrop frame. This class runs those springs
// VERBATIM (coefficients, update order) at a fixed 60 Hz substep, so the sway's
// character does not depend on the render rate, and publishes each frond's bend to
// `Understory.metal` at fragment buffer(6). The feedback IFS itself lives in the
// shader; see `docs/presets/UNDERSTORY_DESIGN.md §3`.
//
// The DRIVE input (design §3 "Adapt") is Milkdrop's own band level, ported verbatim from
// butterchurn's `AudioLevels`: each band over its own long average (rate 0.992 per 30 fps
// frame, ~4 s; 0.9 for the first 50 frames), applied to Uzume's `bass` / `treble`. The AGC
// scale cancels in the ratio, so this is a deviation form, not an absolute threshold (FA #31).
// Two alternatives were measured on the three fixtures at UND.1 and rejected:
//   • `bassDev − trebDev` (the design's literal wording): `trebDev` runs ~100× below `bassDev`
//     (treble sits near 0.005 post-AGC), so the drive collapses to bass-only, one-sided.
//   • `band / (band − rel/2)` (the ratio recovered from `BandDeviationTracker`): its ~21 s
//     average makes the ratio lopsided — on so_what the frond leaned one way (bend p02 −0.08
//     vs the source's −0.25). Milkdrop's ~4 s average swings both ways like the source.
//
// GPU layout (buffer(6)): `Header` (16 B) followed by `maxFronds` × `Frond` (32 B).

import Foundation
import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.presets", category: "Understory")

// MARK: - UnderstoryField

/// Spring state + slot-6 buffer for Understory's feedback-IFS fronds.
public final class UnderstoryField: @unchecked Sendable {

    // MARK: Constants

    /// Upper bound on simulated fronds. Must equal `kUnderstoryMaxFronds` in `Understory.metal`.
    public static let maxFronds = 12

    /// Spring substep rate. Flexi's equations are per-frame; 60 Hz is the frame rate its
    /// `70/fps` bend correction is evaluated at (`bendTwitchGain`).
    public static let substepHz: Float = 60

    /// Flexi's `(1 + 2·(70/fps − 1))`, frozen at 60 fps.
    public static let bendTwitchGain: Float = 1 + 2 * (70.0 / 60.0 - 1)

    /// Drive gain — Flexi's `0.2`, kept verbatim: the UND.1 re-fit (bend `ww` RMS / sd against
    /// the butterchurn oracle on the three tempo fixtures) landed at 0.188 / 0.189.
    public static let driveGain: Float = 0.2

    // MARK: GPU layout

    /// Buffer header. `frondCount` fronds follow.
    struct Header {
        var frondCount: UInt32
        var pad0: UInt32 = 0
        var pad1: UInt32 = 0
        var pad2: UInt32 = 0
    }

    /// One frond as the shader reads it.
    struct Frond {
        /// Atlas tile in drawable uv: origin.xy, size.xy.
        var tile: SIMD4<Float>
        /// Flexi's `ww`: per-generation rotation of the main arm.
        var bend: Float
        /// Flexi's `w`: heading of the arm offsets (`heading − 5·ww`).
        var direction: Float
        var pad0: Float = 0
        var pad1: Float = 0
    }

    /// Two-spring state for one frond (Flexi's `y1 v1 y2 v2`).
    struct Springs {
        var y1: Float = 0, v1: Float = 0, y2: Float = 0, v2: Float = 0
        var heading: Float = 0

        /// Flexi's `ww`.
        var bend: Float { -(y1 - y2) * UnderstoryField.bendTwitchGain - 0.8 * y1 }

        /// One Flexi frame: positions from old velocities, then velocities from new positions.
        mutating func step(target q16: Float) {
            y1 += 0.1 * v1
            y2 += 0.2 * v2
            v1 = 0.95 * v1 - 0.1 * (y1 - q16)
            v2 = 0.99 * v2 - 0.2 * (y2 - y1)
        }
    }

    // MARK: State

    /// UMA buffer bound at fragment index 6.
    public let buffer: MTLBuffer

    private let lock = NSLock()
    private var springs: [Springs]
    private var tiles: [SIMD4<Float>]
    private var bb: Float = 0
    private var tt: Float = 0
    private var levels = MilkdropLevels()
    private var pending: Float = 0

    // MARK: Init

    /// UND.1 — one frond in a centred 4:3 tile (the source's frame), heading 0 (upright).
    public init?(device: MTLDevice) {
        let size = MemoryLayout<Header>.stride + Self.maxFronds * MemoryLayout<Frond>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            logger.error("UnderstoryField: failed to allocate buffer (\(size) bytes)")
            return nil
        }
        buffer = buf
        springs = [Springs()]
        tiles = [Self.centredTile(aspect: 16.0 / 9.0)]
        writeToGPU()
    }

    // MARK: Tick

    /// Advance the springs by `deltaTime` in fixed 1/60 s substeps and publish the bends.
    public func tick(deltaTime: Float, features: FeatureVector) {
        lock.withLock {
            // ponytail: one centred 4:3 tile until UND.2's atlas layout.
            tiles[0] = Self.centredTile(aspect: features.aspectRatio)
            pending = min(pending + max(deltaTime, 0), 0.25)
            let step = 1 / Self.substepHz
            while pending + 1e-5 >= step {   // tolerance: 2 × (1/120) must make one step
                pending -= step
                let level = levels.step(bass: features.bass, treble: features.treble)
                bb = 0.97 * bb + 0.04 * level.bass
                tt = 0.97 * tt + 0.04 * level.treble
                let q16 = Self.driveGain * (bb - tt)
                for i in springs.indices { springs[i].step(target: q16) }
            }
        }
        writeToGPU()
    }

    /// The source's 4:3 frame, full height, centred in a drawable of `aspect` (width/height).
    static func centredTile(aspect: Float) -> SIMD4<Float> {
        let width = aspect > 0 ? min(1, (4.0 / 3.0) / aspect) : 1
        return SIMD4((1 - width) / 2, 0, width, 1)
    }

    /// butterchurn `AudioLevels.updateAudioLevels`, the `val` half, for bass and treble at the
    /// 60 Hz substep: `val = imm / longAvg`, `longAvg` at rate `0.992^(30/60)` (`0.9` for the
    /// first 50 frames), `val = 1` below a silence floor.
    ///
    /// Two UNIT constants are adapted (the rates are verbatim). butterchurn's `imm` is a sum of
    /// FFT bins (tens), so it starts `longAvg` at 1 and floors at 0.001; Uzume's AGC'd treble
    /// sits near 0.002, where a start of 1 takes ~25 s to come down (the frond leaned bass-ward
    /// for the whole UND.1 window) and 0.001 is the signal itself. So the average seeds from
    /// the first non-zero sample (SAR.1, as BandDeviationTracker does) and the floor is 1e-5.
    struct MilkdropLevels {
        static let silenceFloor: Float = 1e-5
        var longAvg: SIMD2<Float> = .zero
        var frame = 0

        mutating func step(bass: Float, treble: Float) -> (bass: Float, treble: Float) {
            let imm = SIMD2(bass.isFinite ? max(bass, 0) : 0, treble.isFinite ? max(treble, 0) : 0)
            longAvg = SIMD2(longAvg.x == 0 ? imm.x : longAvg.x, longAvg.y == 0 ? imm.y : longAvg.y)
            frame += 1
            let rate = pow(frame < 50 ? Float(0.9) : 0.992, 30 / UnderstoryField.substepHz)
            longAvg = longAvg * rate + imm * (1 - rate)
            let floor = Self.silenceFloor
            return (longAvg.x < floor ? 1 : imm.x / longAvg.x, longAvg.y < floor ? 1 : imm.y / longAvg.y)
        }
    }

    // MARK: GPU

    private func writeToGPU() {
        lock.withLock {
            let base = buffer.contents()
            base.storeBytes(of: Header(frondCount: UInt32(springs.count)), as: Header.self)
            let fronds = (base + MemoryLayout<Header>.stride).assumingMemoryBound(to: Frond.self)
            for (i, spring) in springs.enumerated() {
                let bend = spring.bend.isFinite ? spring.bend : 0
                fronds[i] = Frond(tile: tiles[i], bend: bend, direction: spring.heading - 5 * bend)
            }
        }
    }

    /// Test seam: per-frond `(bend, direction)`.
    public func frondsForTesting() -> [(bend: Float, direction: Float)] {
        lock.withLock { springs.map { ($0.bend, $0.heading - 5 * $0.bend) } }
    }
}
