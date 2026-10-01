// UnderstoryField — CPU state for the Understory staged scene (UND.1 → UND.2).
//
// Flexi's "fractal seafood" bends its fern with a two-spring system driven by bass
// against treble, evaluated once per Milkdrop frame. This class runs those springs
// VERBATIM (coefficients, update order) at a fixed 60 Hz substep for every frond in the
// field, and publishes each frond's bend, atlas tile and screen placement to
// `Understory.metal` at fragment buffer(6). The feedback IFS itself lives in the shader;
// see `docs/presets/UNDERSTORY_DESIGN.md §3`. The layout lives in `UnderstoryLayout`.
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
// UND.2 — the wind travels (design §4.2): one drive history, each frond reading it delayed by
// its root's x over `windSpeed`, with its own ±15 % spring stiffness, so a swell crosses the
// field left to right and neighbours drift out of phase. A small idle breeze rides the drive
// so silence reads as still air, not a frozen frame (design §6.2).
//
// UND.3 — colour and trails (design §4.5). The palette rotates with HARMONY, never a clock:
// `tonalPhaseFifths` circular-EMA'd as a unit vector (~0.8 s, wrap-safe — the Nacre TONAL.3
// recipe), gated by `tonalConsonance` so silence / percussion / noise HOLD the last harmonic
// position instead of steering. Afterglow length follows `arousal` (EMA ~2 s): calm → a short,
// clean trail, intense → a long Milkdrop smear.
//
// The backdrop (Matt, 2026-10-01: "a beautiful background — they are just floating in space",
// then his reference: a dim green redwood floor, a mossy fallen log, a carpet of ferns "not all
// of which are moving") is a cached `backdrop` stage — one forest for every track. The header
// paces its build and tells the `fronds` stage when to clear for a new track.
//
// GPU layout (buffer(6)): `Header` (32 B) followed by `maxFronds` × `Frond` (80 B).

import Foundation
import Metal
import simd
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.presets", category: "Understory")

// MARK: - UnderstoryField

/// Spring state + slot-6 buffer for Understory's feedback-IFS fronds.
public final class UnderstoryField: @unchecked Sendable {

    // MARK: Constants

    /// Upper bound on simulated fronds. Must equal `kUnderstoryMaxFronds` in `Understory.metal`.
    public static let maxFronds = UnderstoryLayout.frondCount

    /// Spring substep rate. Flexi's equations are per-frame; 60 Hz is the frame rate its
    /// `70/fps` bend correction is evaluated at (`bendTwitchGain`).
    public static let substepHz: Float = 60

    /// Flexi's `(1 + 2·(70/fps − 1))`, frozen at 60 fps.
    public static let bendTwitchGain: Float = 1 + 2 * (70.0 / 60.0 - 1)

    /// Drive gain — Flexi's `0.2`, kept verbatim: the UND.1 re-fit (bend `ww` RMS / sd against
    /// the butterchurn oracle on the three tempo fixtures) landed at 0.188 / 0.189.
    public static let driveGain: Float = 0.2

    /// Gust speed across the screen, screen widths per second (design §4.2).
    public static let windSpeed: Float = 0.6

    /// Idle breeze added to the drive (design §6.2): ~1 % of a typical musical swing, a slow
    /// two-sine sway so silence is still air rather than a frozen frame.
    static func idleBreeze(at seconds: Float) -> Float {
        0.004 * sin(seconds * 2 * .pi / 9.0) + 0.002 * sin(seconds * 2 * .pi / 4.3 + 1.1)
    }

    /// Drive history length in substeps — covers the widest delay (one screen width).
    static let historyLength = Int((1 / windSpeed) * substepHz) + 2

    // MARK: GPU layout

    /// Buffer header. `frondCount` fronds follow.
    struct Header {
        var frondCount: UInt32
        /// Palette rotation in turns, from harmony.
        var paletteRotation: Float = 0
        /// Afterglow decay per 1/60 s, from arousal.
        var trailDecay: Float = 0
        /// Frames published so far: paces the backdrop's progressive build.
        var frameIndex: Float = 0
        /// 1 for the frame(s) after `reseed`: the `fronds` stage clears its atlas so a new
        /// track's field regrows from its seeds, while the cached forest is kept.
        var clearFronds: Float = 0
        // Scalars only: the header must stay 8 × 4 B = 32 B so the shader's float4-aligned
        // frond array starts where Swift's does.
        var pad0: Float = 0
        var pad1: Float = 0
        var pad2: Float = 0
    }

    /// Afterglow decay per 1/60 s at calm and at intense arousal (design §4.5): a ghost falls
    /// to 10 % in ~3 frames (50 ms) calm, ~12 frames (200 ms) intense. The first UND.3 range
    /// (0.80–0.94) smeared every leaflet into motion blur on a moderate track (so_what).
    public static let trailDecayCalm: Float = 0.50
    public static let trailDecayIntense: Float = 0.82

    /// Arousal mapped onto the trail range. The fixtures span about −0.4 … 0.65.
    static func trailDecay(arousal: Float) -> Float {
        let unit = min(max((arousal + 0.2) / 0.8, 0), 1)
        return trailDecayCalm + (trailDecayIntense - trailDecayCalm) * unit
    }

    /// One frond as the shader reads it.
    struct Frond {
        /// Atlas tile in drawable uv: origin.xy, size.xy.
        var tile: SIMD4<Float>
        /// The region of Flexi's 4:3 frame the tile holds: x0, y0, x1, y1 (frame uv).
        var crop: SIMD4<Float>
        /// Screen placement: seed position (drawable uv), frame height in screen heights,
        /// rotation (radians).
        var place: SIMD4<Float>
        /// Flexi's `ww` (bend + resting curl), Flexi's `w` (heading − 5·ww), depth layer
        /// (0 far … 2 near), brightness.
        var look: SIMD4<Float>
        /// Hue offset (turns), saturation, and two slots UND.4's shimmer will use.
        var colour: SIMD4<Float>
    }

    /// Two-spring state for one frond (Flexi's `y1 v1 y2 v2`).
    struct Springs {
        var y1: Float = 0, v1: Float = 0, y2: Float = 0, v2: Float = 0

        /// Flexi's `ww`.
        var bend: Float { -(y1 - y2) * UnderstoryField.bendTwitchGain - 0.8 * y1 }

        /// One Flexi frame: positions from old velocities, then velocities from new positions.
        /// `stiffness` scales both spring constants (the ±15 % jitter); 1 is Flexi's.
        mutating func step(target q16: Float, stiffness: Float = 1) {
            y1 += 0.1 * v1
            y2 += 0.2 * v2
            v1 = 0.95 * v1 - 0.1 * stiffness * (y1 - q16)
            v2 = 0.99 * v2 - 0.2 * stiffness * (y2 - y1)
        }
    }

    // MARK: State

    /// UMA buffer bound at fragment index 6.
    public let buffer: MTLBuffer

    private let lock = NSLock()
    private var layout: UnderstoryLayout
    private var springs: [Springs]
    private var history: [Float]
    private var historyHead = 0
    private var clock: Float = 0
    private var bb: Float = 0
    private var tt: Float = 0
    private var levels = MilkdropLevels()
    private var pending: Float = 0
    private var fifths = SIMD2<Float>(1, 0)
    private var paletteRotation: Float = 0
    private var arousal: Float = 0
    private var frameIndex: Float = 0
    private var clearPending = false
    private var shimmer: UnderstoryShimmer
    private var onsets: [Float]
    private var events: [UnderstoryShimmer.Event] = []

    // MARK: Init

    public init?(device: MTLDevice, seed: UInt32 = 0) {
        let size = MemoryLayout<Header>.stride + Self.maxFronds * MemoryLayout<Frond>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            logger.error("UnderstoryField: failed to allocate buffer (\(size) bytes)")
            return nil
        }
        buffer = buf
        layout = UnderstoryLayout(seed: seed, aspect: 16.0 / 9.0)
        springs = Array(repeating: Springs(), count: Self.maxFronds)
        history = Array(repeating: 0, count: Self.historyLength)
        shimmer = UnderstoryShimmer(seed: seed)
        onsets = Array(repeating: -100, count: Self.maxFronds)
        writeToGPU()
    }

    /// New track: a new field (design §4.1 "re-seeded at track change"). The springs keep
    /// moving — the wind does not stop because the song changed.
    public func reseed(_ seed: UInt32) {
        lock.withLock {
            layout = UnderstoryLayout(seed: seed, aspect: layout.aspect)
            clearPending = true
            shimmer.reset(seed: seed, at: clock)
            onsets = Array(repeating: -100, count: Self.maxFronds)
        }
        writeToGPU()
    }

    // MARK: Tick

    /// Advance the springs by `deltaTime` in fixed 1/60 s substeps, run the beat sequencer, and
    /// publish the field. `stems` feeds only the no-grid drum fallback.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures = .zero) {
        lock.withLock {
            frameIndex = frameIndex >= 1_000_000 ? 0 : frameIndex + 1
            if features.aspectRatio > 0, abs(features.aspectRatio - layout.aspect) > 1e-3 {
                layout = UnderstoryLayout(seed: layout.seed, aspect: features.aspectRatio)
            }
            pending = min(pending + max(deltaTime, 0), 0.25)
            let step = 1 / Self.substepHz
            while pending + 1e-5 >= step {   // tolerance: 2 × (1/120) must make one step
                pending -= step
                clock += step
                let level = levels.step(bass: features.bass, treble: features.treble)
                bb = 0.97 * bb + 0.04 * level.bass
                tt = 0.97 * tt + 0.04 * level.treble
                historyHead = (historyHead + 1) % history.count
                history[historyHead] = Self.driveGain * (bb - tt) + Self.idleBreeze(at: clock)
                stepColour(features)
                for i in springs.indices {
                    let frond = layout.fronds[i]
                    let back = (historyHead - frond.delaySubsteps + history.count) % history.count
                    springs[i].step(target: history[back], stiffness: frond.stiffness)
                }
            }
            let frame = min(max(deltaTime, 0), 0.25)
            let input = UnderstoryShimmer.Frame(
                clock: clock,
                dt: frame,
                beatPhase: features.beatPhase01,
                barPhase: features.barPhase01,
                beatsPerBar: features.beatsPerBar,
                drumsDev: stems.drumsEnergyDev
            )
            if let event = shimmer.step(input, layout: layout) {
                onsets[event.frond] = event.time
                if events.count < 8192 { events.append(event) }
            }
        }
        writeToGPU()
        lock.withLock { clearPending = false }   // published once by this tick: consumed
    }

    /// One 60 Hz step of the palette and trail state (design §4.5).
    private func stepColour(_ features: FeatureVector) {
        // Consonance gate (the Nacre analyzer floor): atonal or silent → hold, don't steer.
        let gate = min(max((features.tonalConsonance - 0.05) / 0.03, 0), 1)
        let target = SIMD2<Float>(cos(features.tonalPhaseFifths), sin(features.tonalPhaseFifths))
        if features.tonalPhaseFifths.isFinite { fifths += (target - fifths) * (0.025 * gate) }
        if simd_length(fifths) > 1e-3 { paletteRotation = atan2(fifths.y, fifths.x) / (2 * .pi) }
        if features.arousal.isFinite { arousal += (features.arousal - arousal) * (1 / (2 * Self.substepHz)) }
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
            let header = Header(frondCount: UInt32(springs.count),
                                paletteRotation: paletteRotation,
                                trailDecay: Self.trailDecay(arousal: arousal),
                                frameIndex: frameIndex,
                                clearFronds: clearPending ? 1 : 0)
            base.storeBytes(of: header, as: Header.self)
            let fronds = (base + MemoryLayout<Header>.stride).assumingMemoryBound(to: Frond.self)
            for (i, spring) in springs.enumerated() {
                let frond = layout.fronds[i]
                let bend = (spring.bend.isFinite ? spring.bend : 0) + frond.curl
                fronds[i] = Frond(
                    tile: frond.tile,
                    crop: frond.crop,
                    place: SIMD4(frond.root.x, frond.root.y, frond.scale, frond.rotation),
                    look: SIMD4(bend, -5 * bend, Float(frond.layer.rawValue), frond.brightness),
                    colour: SIMD4(frond.hueOffset, frond.saturation, min(clock - onsets[i], 100), 0)
                )
            }
        }
    }

    // MARK: Test seams

    /// Per-frond `(bend, direction)` as published (resting curl included).
    public func frondsForTesting() -> [(bend: Float, direction: Float)] {
        lock.withLock {
            zip(springs, layout.fronds).map { spring, frond in
                let bend = spring.bend + frond.curl
                return (bend, -5 * bend)
            }
        }
    }

    /// The spring bend alone (no resting curl), per frond.
    public func swayForTesting() -> [Float] { lock.withLock { springs.map(\.bend) } }

    /// `(palette rotation in turns, trail decay per 1/60 s)` as published.
    public func colourForTesting() -> (rotation: Float, trailDecay: Float) {
        lock.withLock { (paletteRotation, Self.trailDecay(arousal: arousal)) }
    }

    /// Every shimmer fired so far (capped), for the replay evidence.
    func shimmerEventsForTesting() -> [UnderstoryShimmer.Event] { lock.withLock { events } }

    /// The field's clock (seconds of substeps run).
    public var clockForTesting: Float { lock.withLock { clock } }

    /// The current layout.
    public var layoutForTesting: UnderstoryLayout { lock.withLock { layout } }
}
