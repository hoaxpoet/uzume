// FinishSpec — a scene's finishing stage (VQ.1, Phase VQ; sidecar `finish`).
//
// Every scene's frame passes through one finish before it is presented. `legacy` (the default,
// and every shipped scene's mode) is the scene's own pixels: the frame target is the 8-bit sRGB
// format scenes have always drawn, and the finish is an identity hand-off. `cinematic` renders the
// scene into a linear `.rgba16Float` frame target and the finish adds height-relative bloom, a
// filmic display transform with a headroom input, a grade and dither (FinishingStage.metal).
//
// The mode decides the frame-target format, and every pipeline that draws a scene's frame target
// takes its format from `frameTargetFormat` — one source, so a pipeline compiled for one format is
// never drawn into the other (the BUG-061 class).

import Foundation
import Metal

// MARK: - FinishSpec

/// A scene's finish, decoded from the sidecar `finish` block. Absent means `legacy`.
public struct FinishSpec: Codable, Sendable, Equatable {

    /// How the scene's frame is finished.
    public enum Mode: String, Codable, Sendable {
        /// The scene's own pixels, unchanged.
        case legacy
        /// Bloom, filmic display transform, grade and dither on a linear HDR frame target.
        case cinematic
    }

    /// Bloom in the cinematic finish. Sizes are relative to frame height by construction (the
    /// chain starts at a fixed 540-px base), so the glow covers the same share of every screen.
    public struct Bloom: Codable, Sendable, Equatable {
        /// Bloom added to the scene. 0 turns bloom off.
        public var strength: Float
        /// Linear brightness where bloom starts.
        public var threshold: Float
        /// Soft-knee half-width as a fraction of `threshold` (0 = hard cut).
        public var knee: Float

        /// Creates a bloom block.
        public init(strength: Float = 0.5, threshold: Float = 1.0, knee: Float = 0.5) {
            self.strength = strength
            self.threshold = threshold
            self.knee = knee
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Bloom()
            strength = try container.decodeIfPresent(Float.self, forKey: .strength) ?? defaults.strength
            threshold = try container.decodeIfPresent(Float.self, forKey: .threshold) ?? defaults.threshold
            knee = try container.decodeIfPresent(Float.self, forKey: .knee) ?? defaults.knee
        }
    }

    /// Per-scene grade, applied to the scene-referred colour before the display transform.
    public struct Grade: Codable, Sendable, Equatable {
        /// Exposure in stops.
        public var exposure: Float
        /// Contrast as a power about mid-grey (1 = none).
        public var contrast: Float
        /// Saturation (0 = grey, 1 = none).
        public var saturation: Float

        /// Creates a grade block.
        public init(exposure: Float = 0, contrast: Float = 1, saturation: Float = 1) {
            self.exposure = exposure
            self.contrast = contrast
            self.saturation = saturation
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            exposure = try container.decodeIfPresent(Float.self, forKey: .exposure) ?? 0
            contrast = try container.decodeIfPresent(Float.self, forKey: .contrast) ?? 1
            saturation = try container.decodeIfPresent(Float.self, forKey: .saturation) ?? 1
        }
    }

    /// Finish mode.
    public var mode: Mode
    /// Bloom (cinematic only).
    public var bloom: Bloom
    /// Grade (cinematic only).
    public var grade: Grade
    /// Optional 3D LUT: a `.cube` file name next to the scene's shader (cinematic only).
    public var lut: String?

    /// Creates a finish.
    public init(mode: Mode = .legacy, bloom: Bloom = Bloom(), grade: Grade = Grade(), lut: String? = nil) {
        self.mode = mode
        self.bloom = bloom
        self.grade = grade
        self.lut = lut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decodeIfPresent(Mode.self, forKey: .mode) ?? .legacy
        bloom = try container.decodeIfPresent(Bloom.self, forKey: .bloom) ?? Bloom()
        grade = try container.decodeIfPresent(Grade.self, forKey: .grade) ?? Grade()
        lut = try container.decodeIfPresent(String.self, forKey: .lut)
    }

    /// The default finish: the scene's own pixels.
    public static let legacy = FinishSpec()

    // MARK: - Frame-target format

    /// The legacy frame target: a fixed constant (the 8-bit sRGB format every scene has always
    /// drawn), NOT "the drawable's format", so VQ.2 can change the drawable without recompiling
    /// any legacy pipeline.
    public static let legacyFrameTargetFormat: MTLPixelFormat = .bgra8Unorm_srgb
    /// The cinematic frame target: linear HDR.
    public static let cinematicFrameTargetFormat: MTLPixelFormat = .rgba16Float

    /// The format of every pipeline that draws this scene's frame target.
    public var frameTargetFormat: MTLPixelFormat {
        mode == .cinematic ? Self.cinematicFrameTargetFormat : Self.legacyFrameTargetFormat
    }
}

// MARK: - LUT

extension FinishSpec {

    /// Load a `.cube` 3D LUT (Adobe/Resolve text format: `LUT_3D_SIZE n`, then n³ `r g b` rows,
    /// red fastest) into a 3D texture.
    public static func loadCubeLUT(url: URL, device: MTLDevice) throws -> MTLTexture {
        let text = try String(contentsOf: url, encoding: .utf8)
        var size = 0
        var values: [Float] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ").filter { !$0.isEmpty }
            guard let first = fields.first, !first.hasPrefix("#") else { continue }
            if first == "LUT_3D_SIZE", fields.count == 2, let declared = Int(fields[1]) {
                size = declared
            } else if fields.count == 3 {
                let rgb = fields.compactMap { Float($0) }
                if rgb.count == 3 { values += rgb + [1] }
            }
        }
        guard (2...256).contains(size), values.count == size * size * size * 4 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        let desc = MTLTextureDescriptor()
        desc.textureType = .type3D
        desc.pixelFormat = .rgba32Float
        desc.width = size; desc.height = size; desc.depth = size
        desc.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: desc) else { throw CocoaError(.featureUnsupported) }
        values.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: MTLRegionMake3D(0, 0, 0, size, size, size),
                            mipmapLevel: 0,
                            slice: 0,
                            withBytes: base,
                            bytesPerRow: size * 16,
                            bytesPerImage: size * size * 16)
        }
        return texture
    }
}
