// KaguraClipLibrary — Kagura's dance clips, decoded from the bundled Renderer resource (KAG.1).
//
// `Resources/Kagura/` holds `kagura_clips.bin` + `kagura_clips.json` + `SHA256SUMS`, baked by
// `tools/kagura/bake_clips.py` from the CMU Graphics Lab Motion Capture Database (docs/CREDITS.md).
// Each clip is a 15-joint point-light track at 60 fps, already turned to the common three-quarter
// facing and centred on its mean pelvis, plus a pulse-index map: clip time as a monotone PCHIP through
// the clip's pulse events, 64 samples per pulse (KAGURA_DESIGN §4, §5). The consumer is KAG.2's dancer.

import Foundation
import simd

// MARK: - KaguraDance

/// A dance in Kagura's library (KAGURA_DESIGN §4). `sway` is the unwarped fallback.
public enum KaguraDance: String, Sendable, Codable, CaseIterable {
    case twist, cabbage, chicken, macarena, egyptian, sway
}

// MARK: - KaguraClipError

/// Why the clip resource could not be decoded.
public enum KaguraClipError: Error, Equatable {
    /// The `Kagura` resource directory or one of its files is missing from the bundle.
    case resourceMissing(String)
    /// A clip's byte range, frame count or joint count disagrees with the manifest.
    case malformed(String)
}

// MARK: - KaguraClip

/// One dance clip: joint positions at `fps` and the pulse-index map the beat warp reads.
public struct KaguraClip: Sendable {
    /// CMU trial and window, e.g. `"15_04@109.5-114"` (seconds into the trial).
    public let id: String
    /// The dance this clip belongs to.
    public let dance: KaguraDance
    /// Frame rate of `pose(at:)`'s samples (60).
    public let fps: Double
    /// Number of frames.
    public let frameCount: Int
    /// The detector that found the pulse (`hipyaw`, `wrists`, `gesture`); `nil` for the unwarped sway.
    public let pulseKind: String?
    /// Pulse events in clip seconds, detected on the native 120 fps capture.
    public let pulseEvents: [Double]
    /// Median pulse period in seconds; `nil` for the sway.
    public let pulsePeriod: Double?
    /// Grid beats per pulse the warp may choose from (twist excludes 0.5).
    public let allowedLevels: [Double]
    /// Mean speed of wrists, ankles and head relative to the pelvis at native speed, m/s.
    public let vigor: Double
    /// Yaw the bake applied to reach the common three-quarter facing, degrees.
    public let facingYawDegrees: Double

    /// `frameCount × jointCount` positions, frame-major, metres, y up.
    let positions: [SIMD3<Float>]
    let jointCount: Int
    /// Clip seconds at pulse index `i / samplesPerPulse`.
    let pulseMap: [Float]
    let samplesPerPulse: Int

    /// Clip length in seconds (time of the last frame).
    public var duration: Double { Double(max(frameCount - 1, 0)) / fps }

    /// Number of pulses the map spans (`pulseEvents.count - 1` intervals); 0 for the sway.
    public var pulseSpan: Double { Double(max(pulseMap.count - 1, 0)) / Double(samplesPerPulse) }

    /// The pose at `clipTime` seconds, linearly interpolated between frames and clamped to the clip.
    /// Joint order is `KaguraClipLibrary.jointNames`.
    public func pose(at clipTime: Double) -> [SIMD3<Float>] {
        let x = min(max(clipTime * fps, 0), Double(frameCount - 1))
        let i0 = Int(x)
        let i1 = min(i0 + 1, frameCount - 1)
        let frac = SIMD3<Float>(repeating: Float(x - Double(i0)))
        return (0..<jointCount).map { j in
            simd_mix(positions[i0 * jointCount + j], positions[i1 * jointCount + j], frac)
        }
    }

    /// Clip seconds at pulse position `pulse` (0 = the first pulse event), by linear lookup in the
    /// pulse-index map, clamped to the map. Returns 0 for a clip without a pulse (the sway).
    public func clipTime(atPulse pulse: Double) -> Double {
        guard let last = pulseMap.indices.last else { return 0 }
        let x = min(max(pulse * Double(samplesPerPulse), 0), Double(last))
        let i0 = Int(x)
        let i1 = min(i0 + 1, last)
        let frac = x - Double(i0)
        return Double(pulseMap[i0]) * (1 - frac) + Double(pulseMap[i1]) * frac
    }
}

// MARK: - KaguraClipLibrary

/// Kagura's clip library, decoded once from the manifest and binary.
public struct KaguraClipLibrary: Sendable {
    /// Joint names in storage order (the 15-point Johansson / BML set).
    public let jointNames: [String]
    /// Every clip, in manifest order.
    public let clips: [KaguraClip]
    /// The hip-line yaw every clip was turned to, degrees (`atan2(z, x)` of right → left hip).
    public let facingTargetDegrees: Double
    /// The acknowledgement CMU asks for.
    public let credit: String

    /// The clips of one dance, in manifest order.
    public func clips(for dance: KaguraDance) -> [KaguraClip] {
        clips.filter { $0.dance == dance }
    }

    /// The unwarped fallback clip.
    public var sway: KaguraClip? { clips(for: .sway).first }

    /// The bundled `Kagura` resource directory (the manifest, binary and `SHA256SUMS`).
    public static var resourceDirectory: URL? {
        Bundle.module.url(forResource: "Kagura", withExtension: nil)
    }

    /// The bundled library, decoded on first access and shared thereafter.
    public static func shared() throws -> KaguraClipLibrary { try bundled.get() }

    private static let bundled = Result { try loadBundled() }

    /// Decodes the bundled resource (a fresh decode on every call; prefer `shared()`).
    public static func loadBundled() throws -> KaguraClipLibrary {
        guard let dir = resourceDirectory else { throw KaguraClipError.resourceMissing("Kagura") }
        return try KaguraClipLibrary(
            manifest: Data(contentsOf: dir.appendingPathComponent("kagura_clips.json")),
            binary: Data(contentsOf: dir.appendingPathComponent("kagura_clips.bin"))
        )
    }

    /// Decodes a manifest and its binary.
    public init(manifest: Data, binary: Data) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(Manifest.self, from: manifest)
        jointNames = decoded.joints
        facingTargetDegrees = decoded.facingTargetDeg
        credit = decoded.credit
        clips = try decoded.clips.map {
            try Self.decode(
                $0,
                binary: binary,
                joints: decoded.joints.count,
                samplesPerPulse: decoded.pulseMapSamplesPerPulse
            )
        }
    }

    // MARK: - Decoding

    private struct Manifest: Decodable {
        let joints: [String]
        let facingTargetDeg: Double
        let pulseMapSamplesPerPulse: Int
        let credit: String
        let clips: [ClipEntry]
    }

    private struct ClipEntry: Decodable {
        let id: String
        let dance: KaguraDance
        let fps: Double
        let frameCount: Int
        let pulseKind: String?
        let pulseEventsS: [Double]
        let pulsePeriodS: Double?
        let allowedLevels: [Double]
        let vigorMps: Double
        let facingYawDeg: Double
        let jointsOffset: Int
        let jointsLength: Int
        let pulseMapOffset: Int
        let pulseMapLength: Int
    }

    private static func decode(
        _ entry: ClipEntry, binary: Data, joints: Int, samplesPerPulse: Int
    ) throws -> KaguraClip {
        let values = entry.frameCount * joints * 3
        guard entry.frameCount > 0, entry.jointsLength == values * MemoryLayout<Float16>.size,
              entry.pulseMapLength % MemoryLayout<Float>.size == 0,
              entry.jointsOffset >= 0, entry.jointsOffset + entry.jointsLength <= binary.count,
              entry.pulseMapOffset >= 0, entry.pulseMapOffset + entry.pulseMapLength <= binary.count else {
            throw KaguraClipError.malformed(entry.id)
        }
        let (positions, map) = binary.withUnsafeBytes { raw -> ([SIMD3<Float>], [Float]) in
            // Float16 / Float32 little-endian; Apple Silicon is little-endian, so a plain load is the decode.
            let half = { (k: Int) -> Float in
                Float(raw.loadUnaligned(fromByteOffset: entry.jointsOffset + 2 * k, as: Float16.self))
            }
            let pos = (0..<(values / 3)).map { SIMD3(half(3 * $0), half(3 * $0 + 1), half(3 * $0 + 2)) }
            let map = (0..<(entry.pulseMapLength / 4)).map {
                raw.loadUnaligned(fromByteOffset: entry.pulseMapOffset + 4 * $0, as: Float.self)
            }
            return (pos, map)
        }
        return KaguraClip(
            id: entry.id,
            dance: entry.dance,
            fps: entry.fps,
            frameCount: entry.frameCount,
            pulseKind: entry.pulseKind,
            pulseEvents: entry.pulseEventsS,
            pulsePeriod: entry.pulsePeriodS,
            allowedLevels: entry.allowedLevels,
            vigor: entry.vigorMps,
            facingYawDegrees: entry.facingYawDeg,
            positions: positions,
            jointCount: joints,
            pulseMap: map,
            samplesPerPulse: samplesPerPulse
        )
    }
}
