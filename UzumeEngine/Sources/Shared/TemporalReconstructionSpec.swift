// TemporalReconstructionSpec — a direct scene's opt-in to MetalFX temporal reconstruction (MFX.2).
//
// Declared in the sidecar as a `temporal_reconstruction` block. A scene that declares it renders
// at `internal_scale × drawable` into three targets (colour, depth, motion; plus a reactive mask
// when asked) and MetalFX's temporal scaler rebuilds a drawable-sized image from the jittered
// history. Only for scenes whose frames share structure (D-201): reprojection needs the same
// surfaces to persist from frame to frame. The camera fields (fov, near, far) are part of the
// contract now because MetalFX frame interpolation needs them (VQ amendment A3); interpolation
// itself lands with VQ.4a (A5), so nothing reads them yet.
//
// VQ.3: a ray-march scene declares the same block with `motion_vectors: reprojected` — the engine
// reprojects the G-buffer depth with the previous and current camera (RayMarchTemporal). There,
// `internal_scale` is optional: absent = the scene's own march size (render_scale and the marched-
// pixel budget, unchanged); declared = march at that fraction of the OUTPUT (1.0 = anti-aliasing only).
//
// Lives in Shared because both the sidecar decoder (Presets) and the draw path (Renderer) read it.

import Foundation
import Metal

// MARK: - TemporalReconstructionSpec

/// A direct scene's temporal-reconstruction contract (sidecar `temporal_reconstruction`).
public struct TemporalReconstructionSpec: Codable, Sendable, Equatable {

    /// How the scene produces its motion vectors. Estimated (optical-flow) motion is not supported.
    public enum MotionVectors: String, Codable, Sendable {
        /// Direct scenes: the scene computes each pixel's previous-frame position in closed form.
        case analytic
        /// Ray-march scenes (VQ.3): the engine reprojects depth with the previous and current camera.
        case reprojected
    }

    /// Internal render size as a fraction of the drawable, clamped to 0.5…1.0 (MetalFX upscales at
    /// most 2× per axis here; 1.0 = temporal anti-aliasing at native size).
    public let internalScale: Float
    /// `internal_scale` as written, unclamped; nil when absent (VQ.3: a ray-march scene then keeps its
    /// own march size).
    public let declaredInternalScale: Float?
    /// Motion-vector source.
    public let motionVectors: MotionVectors
    /// The scene writes a reactive mask at `[[color(3)]]` (1 = ignore history for this pixel).
    public let reactiveMask: Bool
    /// Camera vertical field of view, degrees — for the frame interpolator (VQ.4a) with the planes.
    public let fieldOfViewDegrees: Float
    /// Near / far planes of the depth the scene writes (Metal NDC, 0 = near).
    public let nearPlane: Float
    public let farPlane: Float

    /// Target formats of the MRT pipeline `PresetLoader` builds and the textures the reconstructor
    /// allocates — one source, so the two cannot drift. Colour is linear; MetalFX reads these.
    public static let colorFormat: MTLPixelFormat = .rgba16Float
    public static let depthFormat: MTLPixelFormat = .r32Float
    public static let motionFormat: MTLPixelFormat = .rg16Float
    public static let reactiveFormat: MTLPixelFormat = .r8Unorm

    /// The default internal scale: 2560×1440 from a 3840×2160 drawable.
    public static let defaultInternalScale: Float = 2.0 / 3.0

    /// A ray-march scene's internal scale (VQ.3): nil = its own march size; else clamped to MetalFX's
    /// 3× ceiling (⅓) … 1.0 (anti-aliasing only).
    public var rayMarchInternalScale: Float? {
        declaredInternalScale.map { min(max($0, 1.0 / 3.0), 1.0) }
    }

    public init(
        internalScale: Float? = nil,
        motionVectors: MotionVectors = .analytic,
        reactiveMask: Bool = false,
        fieldOfViewDegrees: Float = 60,
        nearPlane: Float = 0.05,
        farPlane: Float = 100
    ) {
        self.internalScale = min(max(internalScale ?? Self.defaultInternalScale, 0.5), 1.0)
        self.declaredInternalScale = internalScale
        self.motionVectors = motionVectors
        self.reactiveMask = reactiveMask
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.nearPlane = nearPlane
        self.farPlane = farPlane
    }

    private enum CodingKeys: String, CodingKey {
        case internalScale = "internal_scale"
        case motionVectors = "motion_vectors"
        case reactiveMask = "reactive_mask"
        case fieldOfViewDegrees = "fov"
        case nearPlane = "near"
        case farPlane = "far"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `motion_vectors` is required: a scene must state where its motion comes from.
        self.init(
            internalScale: try container.decodeIfPresent(Float.self, forKey: .internalScale),
            motionVectors: try container.decode(MotionVectors.self, forKey: .motionVectors),
            reactiveMask: try container.decodeIfPresent(Bool.self, forKey: .reactiveMask) ?? false,
            fieldOfViewDegrees: try container.decodeIfPresent(Float.self, forKey: .fieldOfViewDegrees) ?? 60,
            nearPlane: try container.decodeIfPresent(Float.self, forKey: .nearPlane) ?? 0.05,
            farPlane: try container.decodeIfPresent(Float.self, forKey: .farPlane) ?? 100
        )
    }
}
