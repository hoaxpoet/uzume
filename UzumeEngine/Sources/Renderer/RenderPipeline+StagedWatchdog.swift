// RenderPipeline+StagedWatchdog — non-finite guard for persistent staged state
// (ALFVEN.1 / D-244; `docs/presets/ALFVEN_DESIGN.md` §8.3).
//
// A stage that carries state across frames can diverge, and on stage that is a P0
// black (or worse, strobing) frame. The guard runs at the top of every staged
// frame, detects a persistent texture that has gone non-finite, and silently
// re-zeroes the pair — silently on purpose: a visible reset is worse than the
// artefact it replaces.
//
// Split from `RenderPipeline+Staged.swift` to keep both files under the 400-line
// lint ceiling.

import Metal
import Shared

/// One persistent stage's ping-pong pair, as the watchdog sees it.
private struct PersistentStagePair {
    let name: String
    let front: MTLTexture
    let back: MTLTexture?
}

extension RenderPipeline {

    /// Sparsely probe every persistent stage's front texture for non-finite
    /// values and re-zero the whole pair if any are found. Returns the names of
    /// the stages that tripped.
    ///
    /// Cost control: ONE 16×16 texel block per persistent stage per frame, with
    /// the anchor walking a block lattice over the whole texture, so the field is
    /// fully covered every `(w/16)·(h/16)` frames (~1.4 s at 1080p / 60 fps) and a
    /// blow-up that has spread — which is what a Laplacian-coupled field always
    /// does within a frame or two — is caught immediately. A per-frame full-texture
    /// readback would move megabytes; this moves 4 KB. Persistent textures are
    /// `.shared`, so it is a UMA read with no blit and no GPU work.
    @discardableResult
    func probeStagedPersistentState() -> [String] {
        let candidates: [PersistentStagePair] = stagedLock.withLock {
            stagedStages.filter(\.persistent).compactMap { stage in
                guard let front = stagedTextures[stage.name] else { return nil }
                return PersistentStagePair(
                    name: stage.name,
                    front: front,
                    back: stagedBackTextures[stage.name])
            }
        }
        guard !candidates.isEmpty else { return [] }

        var tripped: [String] = []
        var blownPair: [MTLTexture] = []
        for pair in candidates {
            guard textureBlockIsNonFinite(pair.front, blockIndex: stagedProbeCursor) else { continue }
            tripped.append(pair.name)
            blownPair.append(pair.front)
            if let back = pair.back { blownPair.append(back) }
        }
        stagedProbeCursor &+= 1

        guard !tripped.isEmpty else { return [] }
        zeroTextures(blownPair)
        stagedLock.withLock { stagedWatchdogTrips += tripped.count }
        Logging.renderer.warning(
            "staged watchdog: persistent state went non-finite in \(tripped.joined(separator: ", ")) — re-zeroed")
        return tripped
    }

    /// Edge of the square texel block the watchdog reads per stage per frame.
    static let stagedProbeBlockEdge: Int = 16

    /// True if any component in the `blockIndex`-th 16×16 block of `texture` is
    /// NaN or infinite. Blocks are numbered row-major over the texture and the
    /// index wraps, so successive frames walk the whole field.
    ///
    /// Reuses `stagedProbeScratch` rather than allocating per call — the
    /// allocation, not the read, is what made an earlier full-row version cost
    /// hundreds of microseconds in a Debug build.
    func textureBlockIsNonFinite(_ texture: MTLTexture, blockIndex: Int) -> Bool {
        let edge = Self.stagedProbeBlockEdge
        let width = min(edge, texture.width)
        let height = min(edge, texture.height)
        guard width > 0, height > 0 else { return false }

        let columns = max(texture.width / width, 1)
        let rows = max(texture.height / height, 1)
        let index = abs(blockIndex) % (columns * rows)
        let region = MTLRegion(
            origin: MTLOrigin(x: (index % columns) * width, y: (index / columns) * height, z: 0),
            size: MTLSize(width: width, height: height, depth: 1))

        let components: Int
        let bytesPerComponent: Int
        switch texture.pixelFormat {
        case .rgba32Float: (components, bytesPerComponent) = (4, 4)
        case .rg32Float:   (components, bytesPerComponent) = (2, 4)
        case .rgba16Float: (components, bytesPerComponent) = (4, 2)
        default:           return false // Unprobeable format — abstain, do not guess.
        }
        let bytesPerRow = width * components * bytesPerComponent
        let byteCount = bytesPerRow * height
        if stagedProbeScratch.count < byteCount {
            stagedProbeScratch = [UInt8](repeating: 0, count: byteCount)
        }

        return stagedProbeScratch.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            texture.getBytes(base, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
            let count = byteCount / bytesPerComponent
            if bytesPerComponent == 4 {
                let floats = base.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count where !floats[i].isFinite { return true }
            } else {
                // IEEE half: exponent all-ones ⇒ Inf (mantissa 0) or NaN (mantissa ≠ 0).
                let halves = base.bindMemory(to: UInt16.self, capacity: count)
                for i in 0..<count where (halves[i] & 0x7C00) == 0x7C00 { return true }
            }
            return false
        }
    }
}
