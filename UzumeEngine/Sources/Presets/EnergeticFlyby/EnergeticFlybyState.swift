// EnergeticFlybyState — the music drivers for Energetic Flyby (Kali, Shadertoy csjGDD).
//
// The shader is a stateless single-pass ray march; everything temporal lives here, CPU-side, and
// is flushed each frame to fragment buffer(6) (the Nimbus pattern). Design of record:
// docs/presets/ENERGETIC_FLYBY_DESIGN.md §3 (routing), §4 (camera), §6 (reset). The maths
// reproduce the spike's `prep_flyby3.py`, with its offline percentile normalisation replaced by
// self-normalisation (FA #31: no fixed p5–p95 is available live).
//
// One primitive per layer (FA #67):
//   • downbeat (cached grid, `barPhase01` wrap) → the glow's colour turns (pink → orange → pink → blue);
//     every second downbeat a quarter-turn bank, eased over 1 s, alternating direction. No brightness
//     flare: at Kali's full glow any flare took the worst-case flash train over the regional limit
//     (Matt, 2026-10-19: Kali's colour, the downbeat by the colour turn only)
//   • energy (`spectralFlux`, self-normalised, 0.6 s) → flight speed + glow floor
//   • bass (positive `bassDev`, self-normalised, 30 ms / 300 ms) → sphere spin
//
// EFB_FAITHFUL=1 replaces the music with Kali's own behaviour (travel = spin = time, the
// pseudo-random `so` flicker, Kali's 5 s camera park, hue/roll 0, no white-out fix) so a still can be
// compared against the reference frames 01–04. Never the shipped path.

import Foundation
import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.presets", category: "EnergeticFlyby")

// MARK: - GPU struct

/// 48 bytes; must match `EnergeticFlybyStateGPU` in EnergeticFlyby.metal byte-for-byte.
struct EnergeticFlybyStateGPU: Equatable {
    var time: Float = 0
    var travel: Float = 0
    var camT: Float = 0
    var spin: Float = 0
    var flicker: Float = 0   // faithful mode only: Kali's `so`
    var glowBase: Float = 0
    var hue: Float = 0
    var roll: Float = 0
    var faithful: Float = 0
    var pad0: Float = 0, pad1: Float = 0, pad2: Float = 0
}

// MARK: - EnergeticFlybyState

/// Owns the flight, spin, colour-turn and bank state for Energetic Flyby and its GPU buffer.
///
/// Thread-safe: `tick()`, `reset()` and `stateBuffer` can be used from any queue.
public final class EnergeticFlybyState: @unchecked Sendable {

    // MARK: - Constants (spike values; starting points for EFB.2's M7)

    static let speedFloor: Float = 0.65
    static let speedGain: Float = 0.8
    /// Glow level = glowFloor + glowGain·energy. Kali's glow flickered between 0.5× and 2.0× every frame
    /// (`.5 + so·1.5`, `so` uniform), averaging 1.25×; the flicker is a strobe and is gone, so the steady level
    /// is set to that average: a typical passage (energy ≈ 0.5 on the route-coverage captures) is 1.25×,
    /// silence 0.9×, the loudest 1.6×. Matt, 2026-10-19: "you still have the color wrong" — the spike's
    /// 0.45 + 0.5·energy sat at about half of Kali's glow, darker and less saturated than his frames.
    static let glowFloor: Float = 0.9
    static let glowGain: Float = 0.7
    static let energyTau: Float = 0.6
    static let bassAttack: Float = 0.03
    static let bassRelease: Float = 0.30
    static let spinGain: Float = 3
    static let hueStep: Float = 0.7
    /// The colour turn swings pink → orange → pink → blue (0, +0.7, 0, −0.7 rad on Kali's glow rotation), one
    /// step per downbeat. Matt, 2026-10-19: stay in Kali's range — accumulating the turn took the glow
    /// through teal and green (±1.4 rad and beyond), which no reference frame has.
    static let hueCycle: [Float] = [hueStep, 0, -hueStep, 0]
    static let hueEase: Float = 0.25
    static let rollStep = Float.pi / 2
    static let rollEase: Float = 1.0
    /// Normaliser warm-up: a plain running mean until this much has been heard, then a follower
    /// with this time constant (the FH.17 rule — a follower started at zero reads every early hit
    /// as huge, then sags once as the mean catches up: a whole-frame flash transition).
    static let warmUp: Float = 8

    // MARK: - Public state (diagnostics, tests)

    public let stateBuffer: MTLBuffer
    public private(set) var energy: Float = 0
    public private(set) var bass: Float = 0
    /// True on the frame the cached grid's bar wrapped.
    public private(set) var downbeatThisFrame = false

    // MARK: - Private state

    private let faithful: Bool
    private var gpu = EnergeticFlybyStateGPU()
    // ponytail: Double accumulators; the march itself is Float, so precision near det = .001 runs
    // out after a few hours of continuous flight (travel ≈ 10⁴). The state lives only while the
    // scene is active; wrap travel if a session ever holds the scene that long.
    private var clock: Double = 0
    private var travel: Double = 0
    private var spin: Double = 0
    private var heard: Float = 0
    private var fluxMean: Float = 0
    private var bassMean: Float = 0
    private var lastBarPhase: Float = 0
    private var hueBase: Float = 0
    private var hueTarget: Float = 0
    /// Position in `hueCycle`; never reset, so a track change continues the swing rather than repeating a colour.
    private var hueIndex = 0
    private var hueSince: Float = .infinity
    private var rollBase: Float = 0
    private var rollTarget: Float = 0
    private var rollSince: Float = .infinity
    private var downbeatCount = 0
    private let lock = NSLock()

    // MARK: - Init

    /// `faithful` defaults to the `EFB_FAITHFUL=1` environment switch (reference comparison only).
    public init?(device: MTLDevice,
                 faithful: Bool = ProcessInfo.processInfo.environment["EFB_FAITHFUL"] == "1") {
        let size = MemoryLayout<EnergeticFlybyStateGPU>.stride
        guard let buf = device.makeBuffer(length: size, options: .storageModeShared) else {
            logger.error("EnergeticFlybyState: failed to allocate stateBuffer (\(size) bytes)")
            return nil
        }
        stateBuffer = buf
        self.faithful = faithful
        if faithful { logger.info("EnergeticFlybyState: EFB_FAITHFUL=1 — Kali's own behaviour, no music") }
        lock.withLock { publish() }
    }

    // MARK: - Public API

    /// Advance one rendered frame and flush to the GPU buffer. Call once per frame before the draw.
    public func tick(deltaTime: Float, features: FeatureVector, stems: StemFeatures) {
        lock.withLock {
            let dt = min(max(deltaTime, 0.001), 0.1)   // stale first frame / stall (Witchlight precedent)
            clock += Double(dt)
            if faithful { tickFaithful() } else { tickMusic(dt, features) }
            publish()
        }
    }

    /// Per-track reset: normalisers, envelopes and the bank sequence start over. Travel, the clock,
    /// spin and hue are kept — a track change must not snap the camera or the palette (design §6).
    /// The bank settles where it is (its target becomes its current angle), so nothing jumps.
    public func reset() {
        lock.withLock {
            heard = 0; fluxMean = 0; bassMean = 0
            energy = 0; bass = 0
            lastBarPhase = 0
            rollBase = currentRoll(); rollTarget = rollBase; rollSince = .infinity
            hueBase = currentHue(); hueTarget = hueBase; hueSince = .infinity
            downbeatCount = 0
            downbeatThisFrame = false
            publish()
        }
    }

    /// The values the shader reads this frame.
    var gpuState: EnergeticFlybyStateGPU { lock.withLock { gpu } }

    // MARK: - Music

    private func tickMusic(_ dt: Float, _ features: FeatureVector) {
        heard += dt

        // Energy → speed + glow floor. Squashed so its own mean sits at 0.5 (the spike's
        // percentile-normalised mid-range), then smoothed 0.6 s.
        let flux = Self.squash(max(features.spectralFlux, 0), mean: &fluxMean, heard: heard, dt: dt, gain: 1)
        energy += (flux - energy) * (1 - exp(-dt / Self.energyTau))
        travel += Double((Self.speedFloor + Self.speedGain * energy) * dt)

        // Bass → spin. Fiddlehead's squash (mean → 0.25), fast attack / slow release.
        let bassIn = Self.squash(max(features.bassDev, 0), mean: &bassMean, heard: heard, dt: dt, gain: 3)
        bass += (bassIn - bass) * (1 - exp(-dt / (bassIn > bass ? Self.bassAttack : Self.bassRelease)))
        spin += Double((1 + Self.spinGain * bass) * dt)

        // Downbeat = the cached grid's bar wrapping (never raw onsets).
        let downbeat = features.barPhase01 + 0.5 < lastBarPhase
        lastBarPhase = features.barPhase01
        downbeatThisFrame = downbeat

        hueSince += dt
        rollSince += dt
        if downbeat {
            hueBase = currentHue()
            hueTarget = Self.hueCycle[hueIndex % Self.hueCycle.count]
            hueIndex += 1
            hueSince = 0
            if downbeatCount % 2 == 0 {
                rollBase = currentRoll()
                rollTarget = rollBase + ((downbeatCount / 2) % 2 == 0 ? Self.rollStep : -Self.rollStep)
                rollSince = 0
            }
            downbeatCount += 1
        }

        gpu.time = Float(clock)
        gpu.travel = Float(travel)
        gpu.camT = gpu.travel
        gpu.spin = Float(spin)
        gpu.flicker = 0
        gpu.glowBase = Self.glowFloor + Self.glowGain * energy
        gpu.hue = currentHue()
        gpu.roll = currentRoll()
        gpu.faithful = 0
    }

    /// The eased colour turn from the last step's start toward its target.
    private func currentHue() -> Float {
        hueSince.isFinite ? hueBase + (hueTarget - hueBase) * Self.ease(hueSince / Self.hueEase) : hueTarget
    }

    private func currentRoll() -> Float {
        rollSince.isFinite ? rollBase + (rollTarget - rollBase) * Self.ease(rollSince / Self.rollEase) : rollTarget
    }

    // MARK: - Faithful mode

    /// Kali's own drivers: `t = time`, spin = time, `so = fract(sin(time)*123.456)`, the camera
    /// parked every other 5 s at the nearest multiple of 4.
    private func tickFaithful() {
        let time = Float(clock)
        let sine = sin(time) * 123.456
        gpu.time = time
        gpu.travel = time
        gpu.camT = time.truncatingRemainder(dividingBy: 10) > 5 ? (time / 4 + 0.5).rounded(.down) * 4 : time
        gpu.spin = time
        gpu.flicker = sine - sine.rounded(.down)
        gpu.glowBase = 0.5
        gpu.hue = 0
        gpu.roll = 0
        gpu.faithful = 1
    }

    // MARK: - Helpers

    /// A non-negative level self-normalised against its own mean: mean → 1/(1+gain).
    /// The mean is a plain running average over everything heard until `warmUp` s, then a
    /// `warmUp`-second follower (Fiddlehead's `squash`, FH.17).
    static func squash(_ value: Float, mean: inout Float, heard: Float, dt: Float, gain: Float) -> Float {
        mean += (value - mean) * min(dt / max(min(heard, warmUp), dt), 1)
        return value / (value + gain * max(mean, 1e-5))
    }

    static func ease(_ progress: Float) -> Float {
        let clamped = min(max(progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func publish() {
        var packed = gpu
        stateBuffer.contents().copyMemory(from: &packed, byteCount: MemoryLayout<EnergeticFlybyStateGPU>.stride)
    }
}
