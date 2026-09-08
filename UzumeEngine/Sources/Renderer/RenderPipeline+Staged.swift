// RenderPipeline+Staged — Per-preset staged composition with named offscreen
// textures and pass-separated harness capture (V.ENGINE.1), extended at
// ALFVEN.1 (D-244) into a stateful, iterated GPU-solver surface.
//
// A staged preset declares an ordered `stages: [...]` array on its JSON sidecar.
// Each stage names a fragment function and an optional list of earlier stages
// whose outputs it samples at fragment textures starting at `[[texture(13)]]`.
// Non-final stages render to per-stage offscreen textures in their declared
// `pixel_format` (default `.rgba16Float`); the final stage renders to the drawable.
//
// ALFVEN.1 adds two generic composition capabilities on top of that:
//
//   • `persistent: true` — the stage owns a ping-pong texture PAIR whose content
//     survives across frames. Each frame it samples the previous frame's output
//     at `[[texture(20)]]` (`kStagedPersistentTextureSlot`) and renders into the
//     other half, then the halves swap. The pair is zeroed at allocation, on
//     preset switch, and by `resetStagedPersistentState()`.
//
//   • `iterations: N` — the stage encodes N render passes per frame, ping-ponging
//     its own pair, with its `samples` inputs held CONSTANT across all N. This is
//     what turns a stage into a relaxation solver (Jacobi). It composes with
//     `persistent`: iteration 1 of an iterated persistent stage starts from the
//     previous frame's state, so a Poisson solve warm-starts instead of restarting
//     from zero every frame.
//
// A non-finite watchdog (ALFVEN_DESIGN.md §8.3) probes persistent state sparsely
// each frame and silently re-zeroes the pair if it has blown up — see
// `probeStagedPersistentState()`.
//
// See `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` for the engine capability
// matrix that motivates this scaffold.

import Metal
@preconcurrency import MetalKit
import Shared

// MARK: - Staged Stage Spec

/// One stage in the renderer's active staged-composition spec.
///
/// `RenderPipeline.setStagedRuntime(_:)` accepts an ordered array of these,
/// allocates the offscreen texture (or ping-pong pair) each non-final stage
/// needs, and dispatches the stages each frame in `drawWithStaged(...)`.
public struct StagedStageSpec: Sendable {
    /// Stage identifier — must be unique within the runtime; matches the
    /// stage's `name` in `PresetDescriptor.stages`.
    public let name: String
    /// Compiled fragment pipeline. Non-final stages target `pixelFormat`; the
    /// final stage targets the drawable pixel format.
    public let pipelineState: MTLRenderPipelineState
    /// Names of earlier stages whose outputs this stage samples at
    /// `[[texture(13)]]`, `[[texture(14)]]`, ... in the listed order.
    public let samples: [String]
    /// True if this stage targets the drawable; false if it targets `pixelFormat`.
    public let writesToDrawable: Bool
    /// True when this stage's state survives across frames (ALFVEN.1).
    public let persistent: Bool
    /// Render passes encoded per frame, ping-ponging this stage's own pair.
    public let iterations: Int
    /// Offscreen colour format. Ignored when `writesToDrawable`.
    public let pixelFormat: MTLPixelFormat

    /// True when this stage needs a ping-pong pair rather than a single texture.
    public var needsPingPongPair: Bool { persistent || iterations > 1 }

    public init(
        name: String,
        pipelineState: MTLRenderPipelineState,
        samples: [String],
        writesToDrawable: Bool,
        persistent: Bool = false,
        iterations: Int = 1,
        pixelFormat: MTLPixelFormat = .rgba16Float
    ) {
        self.name = name
        self.pipelineState = pipelineState
        self.samples = samples
        self.writesToDrawable = writesToDrawable
        self.persistent = persistent
        self.iterations = iterations
        self.pixelFormat = pixelFormat
    }
}

/// A staged preset's per-stage offscreen textures.
///
/// `front` is each stage's most recent output — what later stages sample and what
/// `stagedTexture(named:)` returns. `back` holds the other half of the pair for
/// stages that own one (`persistent` or `iterations > 1`); the two swap after each
/// iteration.
struct StagedTextureSet {
    var front: [String: MTLTexture]
    var back: [String: MTLTexture]
}

/// One frame's lock-free view of the staged runtime.
struct StagedFrameSnapshot {
    let stages: [StagedStageSpec]
    let textures: StagedTextureSet
}

/// First fragment-texture binding slot used by staged sampled inputs.
/// Slots 0–12 are reserved (noise textures 4–8, IBL 9–11, text overlay 12).
/// Sampled outputs occupy 13…19 — `PresetStage.maxSamples` caps a stage at 7.
public let kStagedSampledTextureFirstSlot: Int = 13

/// Fragment-texture slot carrying a persistent/iterated stage's PREVIOUS state
/// (previous frame for `persistent`, previous iteration within `iterations`).
/// Deliberately above the 13…19 `samples` window so the two never collide and a
/// shader's `[[texture(20)]]` binding does not move when a sample is added —
/// see `docs/ARCHITECTURE.md §GPU Contract Details`.
public let kStagedPersistentTextureSlot: Int = 20

// MARK: - RenderPipeline + Staged

extension RenderPipeline {

    // MARK: Configuration

    /// Configure the renderer for a staged-composition preset.
    ///
    /// Pass an ordered array of stage specs (last entry must have
    /// `writesToDrawable == true`). Allocates one offscreen texture per non-final
    /// stage in that stage's declared pixel format, or a zeroed ping-pong pair for
    /// stages that are `persistent` or run more than one iteration.
    /// Pass `nil` to clear the staged path (call on every preset switch).
    public func setStagedRuntime(_ stages: [StagedStageSpec]?, drawableSize: CGSize) {
        stagedLock.withLock {
            stagedStages = stages ?? []
            stagedTextures.removeAll(keepingCapacity: true)
            stagedBackTextures.removeAll(keepingCapacity: true)
        }
        if let stages, !stages.isEmpty {
            allocateStagedTextures(size: drawableSize)
        }
    }

    /// Snapshot of the active staged stages (for tests / diagnostics).
    public var currentStagedStageNames: [String] {
        stagedLock.withLock { stagedStages.map(\.name) }
    }

    /// Number of times the non-finite watchdog has re-zeroed persistent state
    /// since the last `setStagedRuntime`. Diagnostics only (ALFVEN_DESIGN.md §8.3).
    public var stagedWatchdogTripCount: Int {
        stagedLock.withLock { stagedWatchdogTrips }
    }

    /// Zero every persistent stage's ping-pong pair. Called on preset switch and
    /// available to callers that need a clean field (track change, watchdog trip).
    public func resetStagedPersistentState() {
        let pairs: [MTLTexture] = stagedLock.withLock {
            stagedStages
                .filter(\.persistent)
                .flatMap { [stagedTextures[$0.name], stagedBackTextures[$0.name]] }
                .compactMap { $0 }
        }
        zeroTextures(pairs)
    }

    /// Reallocate per-stage offscreen textures at the new size. Called from
    /// `mtkView(_:drawableSizeWillChange:)` so resizes pick up immediately.
    func reallocateStagedTextures(size: CGSize) {
        let hasStages = stagedLock.withLock { !stagedStages.isEmpty }
        guard hasStages else { return }
        allocateStagedTextures(size: size)
    }

    private func allocateStagedTextures(size: CGSize) {
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)
        var toZero: [MTLTexture] = []
        stagedLock.withLock {
            stagedTextures.removeAll(keepingCapacity: true)
            stagedBackTextures.removeAll(keepingCapacity: true)
            stagedWatchdogTrips = 0
            for stage in stagedStages where !stage.writesToDrawable {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: stage.pixelFormat,
                    width: width,
                    height: height,
                    mipmapped: false
                )
                desc.usage = [.renderTarget, .shaderRead]
                // Persistent state is CPU-probed by the non-finite watchdog, so it
                // lives in shared (UMA) memory — on Apple Silicon that is the same
                // physical memory a `.private` render target uses.
                desc.storageMode = stage.persistent ? .shared : .private
                guard let front = context.device.makeTexture(descriptor: desc) else { continue }
                stagedTextures[stage.name] = front
                guard stage.needsPingPongPair,
                      let back = context.device.makeTexture(descriptor: desc) else { continue }
                stagedBackTextures[stage.name] = back
                toZero.append(front)
                toZero.append(back)
            }
        }
        zeroTextures(toZero)
    }

    /// Clear a set of textures to (0,0,0,0) on the GPU. Synchronous — allocation,
    /// reset and a watchdog trip are all off the hot path.
    func zeroTextures(_ textures: [MTLTexture]) {
        guard !textures.isEmpty,
              let commandBuffer = context.commandQueue.makeCommandBuffer() else { return }
        for texture in textures {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].storeAction = .store
            commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)?.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: Texture Lookup

    /// Lookup an offscreen stage texture by name. Returns nil for the final
    /// stage (which writes to the drawable) or any unknown name.
    ///
    /// For a ping-pong stage this is the FRONT texture — the stage's most recent
    /// output, and what later stages sample.
    public func stagedTexture(named name: String) -> MTLTexture? {
        stagedLock.withLock { stagedTextures[name] }
    }

    // MARK: Draw

    /// Walk the staged-composition stages for the active preset and render
    /// each into its target. The final stage renders to the drawable; all
    /// earlier stages render into named offscreen textures (or ping-pong pairs).
    @MainActor
    func drawWithStaged(
        commandBuffer: MTLCommandBuffer,
        view: MTKView,
        features: inout FeatureVector,
        stemFeatures: StemFeatures
    ) {
        let front = encodeOffscreenStages(commandBuffer: commandBuffer,
                                          features: &features,
                                          stemFeatures: stemFeatures)
        let stages = stagedLock.withLock { stagedStages }
        guard !stages.isEmpty else { return }

        // Final stage: render to drawable.
        guard let finalStage = stages.last,
              finalStage.writesToDrawable,
              let descriptor = instrumentedRenderPassDescriptor(
                  from: view, commandBuffer: commandBuffer, site: "staged.descriptor"),
              let drawable = instrumentedDrawable(
                  from: view, commandBuffer: commandBuffer, site: "staged.drawable") else {
            return
        }
        descriptor.colorAttachments[0].clearColor =
            MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        encodeStage(stage: finalStage,
                    encoder: encoder,
                    features: &features,
                    stemFeatures: stemFeatures,
                    textures: front)
        encoder.endEncoding()
        instrumentedPresent(drawable, on: commandBuffer)
    }
}
