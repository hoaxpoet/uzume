// UpscaleMode — how a scene's smaller render reaches a larger screen (VQ.3, Phase VQ; sidecar `upscale`).
//
// Wherever the engine puts a smaller image on a larger output — the tier-1 canvas (BR.6b, A4), the
// NB.8 half-resolution direct path, a ray-march scene's march size — it either stretches it
// bilinearly (`bilinear`, today's look) or runs MetalFX's spatial scaler (`spatial`): edge-adaptive,
// single-frame, no motion vectors needed, so any scene can take it. Either way the image is upscaled
// ONCE, to the output (drawable) size, before the finish (render → upscale → finish → present,
// WWDC25 session 211). Temporal reconstruction (`temporal_reconstruction`) is a separate opt-in and
// wins over this when a scene declares both.
//
// A scene without the sidecar key gets `rosterDefault` — the one place that moves the whole roster.

import Foundation

// MARK: - UpscaleMode

/// The upscale a scene takes at every stretch (sidecar `upscale`: `"bilinear"`, `"spatial"` or, ray-march only,
/// `"native"`).
public enum UpscaleMode: String, Codable, Sendable {
    /// Today's bilinear stretch.
    case bilinear
    /// MetalFX spatial upscaling, to the output size, before the finish.
    case spatial
    /// LM.10, ray-march scenes only: march at the drawable's FULL size — no stretch, no tier-1 cap. For a scene
    /// whose per-pixel cost is small enough to afford it (Lumen Mosaic, its glass baked once). Every other path
    /// treats it as `bilinear`.
    case native

    /// What a scene without a sidecar `upscale` gets. **The roster switch**: a consumer increment
    /// (VQ.3s) flips it after Matt's review; a scene that must keep the stretch then declares
    /// `"upscale": "bilinear"`.
    public static let rosterDefault: UpscaleMode = .bilinear

    /// The mode a scene runs with: its declared mode, else the roster default. Resolved once, at load.
    public static func resolve(_ declared: UpscaleMode?) -> UpscaleMode {
        declared ?? rosterDefault
    }
}
