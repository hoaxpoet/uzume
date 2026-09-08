// PresetStage — One stage in a `.staged` preset's composition graph (V.ENGINE.1,
// extended for stateful iterated solvers at ALFVEN.1 / D-244).
//
// A staged preset declares an ordered `stages: [...]` array on its JSON sidecar.
// Each stage names a fragment function and an optional list of earlier stages
// whose outputs it samples as fragment textures starting at `[[texture(13)]]`.
// Non-final stages render to per-stage offscreen textures; the final stage
// writes to the drawable.
//
// ALFVEN.1 adds three optional, generic keys — none of them Alfvén-specific:
//
//   "persistent": true        the stage owns a ping-pong texture pair whose
//                             content survives across frames; frame N samples
//                             frame N-1's output at `[[texture(20)]]`.
//   "iterations": N           the stage encodes N passes per frame, ping-ponging
//                             its own pair, with its `samples` inputs held
//                             constant. Composes with `persistent`: iteration 1
//                             of an iterated persistent stage starts from the
//                             previous frame's state.
//   "pixel_format": "..."     per-stage offscreen format, default `rgba16Float`.
//                             A Jacobi/Poisson solve needs `rgba32Float`.
//
// See `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`, `docs/SHADER_CRAFT.md §17`,
// the `StagedSandbox` diagnostic (plain staged authoring) and the
// `PoissonSandbox` diagnostic (all three new keys) for the canonical patterns.

import Foundation
import Metal
import Shared

// MARK: - PresetStage

/// One stage in a staged-composition preset.
public struct PresetStage: Sendable, Codable, Equatable {

    /// Stage identifier — must be unique within the preset.
    /// Used as the texture key when later stages sample this stage's output.
    public let name: String

    /// Metal fragment function name. Defined in the preset's `.metal` source and
    /// compiled by `PresetLoader` against the standard preamble.
    public let fragmentFunction: String

    /// Names of earlier stages whose outputs this stage samples.
    ///
    /// Bound at fragment textures `[[texture(13)]]`, `[[texture(14)]]`, ... in the
    /// order listed. Empty / omitted = no earlier-stage inputs (typical for the
    /// first stage). At most `maxSamples` — slot 20 is the persistent-state slot.
    public let samples: [String]

    /// When true this stage owns a ping-pong texture pair that survives across
    /// frames. Frame N samples frame N-1's output at `[[texture(20)]]`; the pair
    /// is zeroed on preset switch and on `resetStagedPersistentState()`.
    ///
    /// A persistent stage may not be the final (drawable-writing) stage — the
    /// drawable is owned by the view, not by the preset, so there is nothing to
    /// persist. That combination is a decode error, not a warning.
    public let persistent: Bool

    /// Number of render passes this stage encodes per frame, ping-ponging its own
    /// pair. `1` (the default) is the classic single-pass stage. Range `1...64`.
    public let iterations: Int

    /// Offscreen colour format for this stage. `nil` = `rgba16Float` (the
    /// historical hardcoded format, so every existing sidecar is unchanged).
    /// Ignored for the final stage, which always targets the drawable format.
    public let pixelFormat: StagePixelFormat?

    /// Highest sample count a stage may declare. Sampled stage outputs occupy
    /// `[[texture(13)]]` … `[[texture(19)]]`; `[[texture(20)]]` is the persistent
    /// previous-state slot. See `docs/ARCHITECTURE.md §GPU Contract Details`.
    public static let maxSamples: Int = 7

    /// Widest supported `iterations` value. A stage encodes one render pass per
    /// iteration, so this is a frame-budget guardrail, not a numerical limit.
    public static let maxIterations: Int = 64

    /// The offscreen formats a stage may declare. Raw values are the sidecar
    /// strings, spelled like the `MTLPixelFormat` cases they map to.
    public enum StagePixelFormat: String, Sendable, Codable, Equatable, CaseIterable {
        case rgba16Float
        case rgba32Float
        case rg32Float

        /// The Metal format this sidecar value selects.
        public var metal: MTLPixelFormat {
            switch self {
            case .rgba16Float: return .rgba16Float
            case .rgba32Float: return .rgba32Float
            case .rg32Float:   return .rg32Float
            }
        }
    }

    /// Metal offscreen format for this stage, resolving the `nil` default.
    public var resolvedPixelFormat: MTLPixelFormat {
        (pixelFormat ?? .rgba16Float).metal
    }

    /// True when this stage needs a ping-pong pair: either its state survives
    /// across frames, or it runs more than once per frame against its own output.
    public var needsPingPongPair: Bool { persistent || iterations > 1 }

    public init(
        name: String,
        fragmentFunction: String,
        samples: [String] = [],
        persistent: Bool = false,
        iterations: Int = 1,
        pixelFormat: StagePixelFormat? = nil
    ) {
        self.name = name
        self.fragmentFunction = fragmentFunction
        self.samples = samples
        self.persistent = persistent
        self.iterations = iterations
        self.pixelFormat = pixelFormat
    }

    enum CodingKeys: String, CodingKey {
        case name
        case fragmentFunction = "fragment_function"
        case samples
        case persistent
        case iterations
        case pixelFormat = "pixel_format"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.fragmentFunction = try container.decode(String.self, forKey: .fragmentFunction)
        let decodedSamples = try container.decodeIfPresent([String].self, forKey: .samples) ?? []
        guard decodedSamples.count <= Self.maxSamples else {
            throw DecodingError.dataCorruptedError(
                forKey: .samples,
                in: container,
                debugDescription: """
                    stage '\(name)' declares \(decodedSamples.count) samples; \
                    at most \(Self.maxSamples) fit the texture(13…19) window \
                    (texture(20) is the persistent-state slot)
                    """)
        }
        self.samples = decodedSamples

        self.persistent = try container.decodeIfPresent(Bool.self, forKey: .persistent) ?? false

        let decodedIterations = try container.decodeIfPresent(Int.self, forKey: .iterations) ?? 1
        guard (1...Self.maxIterations).contains(decodedIterations) else {
            throw DecodingError.dataCorruptedError(
                forKey: .iterations,
                in: container,
                debugDescription: """
                    stage '\(name)' declares iterations=\(decodedIterations); \
                    must be 1…\(Self.maxIterations)
                    """)
        }
        self.iterations = decodedIterations

        // Unknown format strings warn and fall back to the historical default —
        // the `feedback_pixel_format` precedent (PUB.4). A typo must not take the
        // whole preset out of the roster.
        if let raw = try container.decodeIfPresent(String.self, forKey: .pixelFormat) {
            if let parsed = StagePixelFormat(rawValue: raw) {
                self.pixelFormat = parsed
            } else {
                let stageName = name
                Logging.renderer.warning(
                    "PresetStage '\(stageName)': unknown pixel_format '\(raw)' — using rgba16Float")
                self.pixelFormat = nil
            }
        } else {
            self.pixelFormat = nil
        }
    }
}
