// InariState — the drawings and per-light levels for the Inari `direct` preset.
//
// THE SCENE. One night shrine drawn twice by the artist — lit only by the moon, and with every
// lantern, window and fox eye burning (`Shaders/Inari/inari_unlit.webp`, `inari_lit.webp`).
// Nothing in the scene moves; only its light changes (Matt, 2026-10-05). `tools/inari/prep.swift`
// derives `inari_lights.png` from the pair: for each pixel, which light source lights it (g) and
// how far down that light's drawn falloff it sits (r), plus `inari_lights.json` (one row per
// source). The shader brightens the moonlit drawing smoothly toward the lit one, per source.
//
// THE MUSIC (Matt's routing, 2026-10-05; tuning still to come — `docs/presets/INARI_DESIGN.md`):
//   • fox eyes  ← vocals — dark stone when no one sings; they kindle with the voice and linger.
//   • lanterns  ← bass   — swell and fall with the bass; a higher lantern follows a little later,
//                          so a swell climbs the stairs toward the hall.
//   • the shrine (the hall's lamps, the pagoda) ← drums — kick on each hit and fall back.
//
// GPU layout (bound at buffer(6)): `maxLights` Float32 levels indexed by source id − 1
// (0 dark … 1 as drawn … > 1 brighter than drawn). Textures at 9 / 10 / 11: unlit, lit, lights.

import Foundation
import Metal
import MetalKit
import Shared
import os.log

private let logger = Logger(subsystem: "io.uzume.presets", category: "Inari")

/// Inari's drawings, light map and per-frame light levels.
public final class InariState: @unchecked Sendable {

    // MARK: - Constants

    /// Level slots in the buffer. Source ids in `inari_lights.json` must stay below this.
    public static let maxLights = 64

    /// One light source found in the drawings by `tools/inari/prep.swift`.
    struct Light: Decodable {
        let id: Int
        let x: Float
        let y: Float
        let pixels: Int
        let peak: Float
        enum CodingKeys: String, CodingKey { case id, x, y, pixels = "n", peak }
    }

    /// What a source is, by where it sits in the drawing (image px, 1536 × 1024). Classified by
    /// position because ids change whenever the drawings are regenerated.
    enum Role: Equatable { case eye, shrine, lantern(climb: Float) }

    /// Envelope time constants (seconds). Attack / release per group.
    static let lanternAttack: Float = 0.06, lanternRelease: Float = 0.45
    static let shrineAttack: Float = 0.015, shrineRelease: Float = 0.22
    static let eyeAttack: Float = 0.12, eyeRelease: Float = 0.9
    /// How long a bass swell takes to climb from the nearest lantern to the hall.
    static let climbSeconds: Float = 0.35

    // MARK: - GPU resources

    /// UMA buffer bound at fragment index 6.
    public let levelBuffer: MTLBuffer
    /// Fragment textures 9, 10, 11.
    public let textures: [MTLTexture]

    // MARK: - State

    private let roles: [Int: Role]
    private let lock = NSLock()
    private var bassHistory: [Float] = []       // smoothed bass target, newest last, one per tick
    private var historyTimes: [Float] = []
    private var clock: Float = 0
    private var lantern: [Int: Float] = [:]
    private var shrine: Float = 0
    private var eye: Float = 0

    // MARK: - Init

    public init?(device: MTLDevice) {
        guard let dir = Bundle.module.url(forResource: "Shaders", withExtension: nil)?
                .appendingPathComponent("Inari"),
              let buf = device.makeBuffer(length: Self.maxLights * MemoryLayout<Float>.stride,
                                          options: .storageModeShared) else {
            logger.error("InariState: resources or level buffer unavailable")
            return nil
        }
        let loader = MTKTextureLoader(device: device)
        let opts: [MTKTextureLoader.Option: Any] = [
            .SRGB: true,                  // sampled — and mip-averaged — in linear light
            .generateMipmaps: true,       // the shader reads a blurred light ratio off mip ~2.8
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]
        do {
            textures = try ["inari_unlit.webp", "inari_lit.webp", "inari_lights.png"].map { name in
                try loader.newTexture(URL: dir.appendingPathComponent(name),
                                      options: name.hasSuffix(".png") ? [.SRGB: false] : opts)
            }
            let json = try Data(contentsOf: dir.appendingPathComponent("inari_lights.json"))
            let lights = try JSONDecoder().decode([Light].self, from: json)
            roles = Self.classify(lights)
        } catch {
            logger.error("InariState: failed to load drawings: \(error.localizedDescription)")
            return nil
        }
        levelBuffer = buf
        writeToGPU()
    }

    /// Eyes: the two foxes' heads. Shrine: the pagoda's windows (top right) and the hall's big
    /// lamp clusters. Everything else is a lantern; its climb delay grows with height in the frame.
    static func classify(_ lights: [Light]) -> [Int: Role] {
        func near(_ light: Light, _ x: Float, _ y: Float, _ radius: Float) -> Bool {
            hypot(light.x - x, light.y - y) < radius
        }
        let lanternYs = lights.map(\.y)
        let lo = lanternYs.min() ?? 0, hi = lanternYs.max() ?? 1
        var out: [Int: Role] = [:]
        for light in lights where light.id < maxLights {
            let pagoda = light.y < 300 && light.x > 1200
            let hall = light.pixels > 1500 && !near(light, 361, 520, 40)
            if near(light, 330, 210, 60) || near(light, 1340, 370, 60) {
                out[light.id] = .eye
            } else if pagoda || hall {
                out[light.id] = .shrine
            } else {
                out[light.id] = .lantern(climb: (hi - light.y) / max(hi - lo, 1))   // nearest/lowest first
            }
        }
        return out
    }

    // MARK: - Tick

    /// Advance the envelopes from this frame's stems and write the levels.
    public func tick(deltaTime: Float, stems: StemFeatures) {
        lock.withLock { advance(dt: max(deltaTime, 1.0 / 240.0), stems: stems) }
        writeToGPU()
    }

    private func advance(dt: Float, stems: StemFeatures) {
        clock += dt
        // Provisional mappings — tuned against real sessions before certification.
        let bassTarget = min(max(0.35 + 1.4 * stems.bassEnergyRel, 0), 1.3)
        let drumTarget = min(max(1.6 * stems.drumsEnergyDev, 0), 1.3)
        let voxTarget = min(max((stems.vocalsEnergy - 0.15) / 0.45, 0), 1.2) + 0.8 * stems.vocalsEnergyDev

        bassHistory.append(bassTarget); historyTimes.append(clock)
        while let first = historyTimes.first, clock - first > Self.climbSeconds + 0.1 {
            historyTimes.removeFirst(); bassHistory.removeFirst()
        }
        shrine = follow(shrine, drumTarget, Self.shrineAttack, Self.shrineRelease, dt)
        eye = follow(eye, voxTarget, Self.eyeAttack, Self.eyeRelease, dt)
        for (id, role) in roles {
            guard case .lantern(let climb) = role else { continue }
            let target = bassAt(clock - climb * Self.climbSeconds)
            lantern[id] = follow(lantern[id] ?? 0, target, Self.lanternAttack, Self.lanternRelease, dt)
        }
    }

    /// The bass target as it was at time `t` (the newest sample at or before it).
    private func bassAt(_ time: Float) -> Float {
        guard let i = historyTimes.lastIndex(where: { $0 <= time }) else { return bassHistory.first ?? 0 }
        return bassHistory[i]
    }

    /// One-pole follower with separate attack/release, frame-rate independent.
    private func follow(_ cur: Float, _ target: Float, _ atk: Float, _ rel: Float, _ dt: Float) -> Float {
        let next = cur + (target - cur) * (1 - exp(-dt / (target > cur ? atk : rel)))
        return next.isFinite ? next : 0
    }

    /// The level each source shows this frame.
    func levels() -> [Float] {
        var out = [Float](repeating: 0, count: Self.maxLights)
        let eyeLevel = pow(max(eye - 0.15, 0) / 0.85, 1.3) * 1.25
        for (id, role) in roles {
            switch role {
            case .eye: out[id - 1] = eyeLevel
            case .shrine: out[id - 1] = 0.2 + shrine
            case .lantern: out[id - 1] = 0.12 + 1.05 * (lantern[id] ?? 0)
            }
        }
        return out
    }

    private func writeToGPU() {
        let ptr = levelBuffer.contents().assumingMemoryBound(to: Float.self)
        let lv = lock.withLock { levels() }
        for k in 0..<Self.maxLights { ptr[k] = lv[k] }
    }

    /// Test seam: the current per-source levels and roles.
    public func levelsForTesting() -> [Float] { lock.withLock { levels() } }
    func rolesForTesting() -> [Int: Role] { roles }
}
