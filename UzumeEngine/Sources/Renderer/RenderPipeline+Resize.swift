// RenderPipeline+Resize — display changes drain, release, then allocate (VQ.0, D-264).
//
// Metal frees a texture only after every in-flight command buffer that references it completes, so
// "release before allocate" means nothing without a drain. A committed resize therefore:
//   1. waits for the last committed frame (the queue is serial: every earlier frame is done too);
//   2. drops every subsystem's old size-scaled set (the budget stops charging each target the moment
//      nothing references it);
//   3. charges the drawable pool, then allocates the new set. Ray-march and post-process targets are
//      left to their per-frame lazy allocators, which size them at the march scale (BUG-101) — the
//      eager full-size reallocation that used to run here silently dropped that scale after a resize.
//
// Resizes are COALESCED: the fullscreen animation alone sends many size callbacks and a TV handshake
// sends more. `mtkView(_:drawableSizeWillChange:)` only records the size; the render loop keeps
// rendering at the committed size (the present step stretches it into the new drawable) until the
// size has been stable for `resizeCoalescingWindow`, then commits once. The very first size commits
// at once — there is no old size to render at. D-061(a) holds: every frame's targets are one size.

import Metal
import MetalKit
import QuartzCore
import os.log

private let logger = Logger(subsystem: "io.uzume.renderer", category: "RenderResize")

extension RenderPipeline {

    /// Drawables the layer may hold. Explicit (VQ.0) so the pool charged is the pool that exists.
    static let drawablePoolCount = 3

    // MARK: - Callback

    /// Record a drawable size from the view's delegate callback. Commits at once only for the first
    /// size; later sizes commit from the render loop once stable.
    @MainActor
    func recordDrawableSize(_ drawableSize: CGSize, view: MTKView?) {
        let commitNow: Bool = resizeLock.withLock {
            resizeCallbackCount += 1
            guard committedDrawableSize != nil else { return true }
            pendingResize = drawableSize == committedDrawableSize
                ? nil : PendingResize(size: drawableSize, since: CACurrentMediaTime())
            return false
        }
        if commitNow { commitResize(to: drawableSize, view: view) }
    }

    // MARK: - Render-loop side

    /// The size every size-scaled subsystem allocates at this frame: the committed size, or the
    /// drawable's own before anything has committed.
    var allocationDrawableSize: CGSize? { resizeLock.withLock { committedDrawableSize } }

    /// Called at the top of every frame: commit a pending size once it has been stable for
    /// `resizeCoalescingWindow`, and treat a drawable that changed without a callback as pending.
    /// Returns true when it committed.
    @MainActor
    @discardableResult
    func commitPendingResizeIfStable(now: CFTimeInterval, view: MTKView?) -> Bool {
        let viewSize = view?.drawableSize
        let due: CGSize? = resizeLock.withLock {
            if let viewSize, viewSize.width >= 1, viewSize.height >= 1, pendingResize == nil,
               viewSize != committedDrawableSize {
                if committedDrawableSize == nil { return viewSize }
                pendingResize = PendingResize(size: viewSize, since: now)
            }
            guard let pending = pendingResize, now - pending.since >= resizeCoalescingWindow else { return nil }
            pendingResize = nil
            return pending.size
        }
        guard let due else { return false }
        commitResize(to: due, view: view)
        return true
    }

    /// Commit any pending size now, stable or not (tests; a caller that knows the size is final).
    @MainActor
    public func flushPendingResize(view: MTKView? = nil) {
        let due: CGSize? = resizeLock.withLock {
            defer { pendingResize = nil }
            return pendingResize?.size
        }
        if let due { commitResize(to: due, view: view) }
    }

    // MARK: - Commit

    /// Drain → release → allocate at `drawableSize`.
    @MainActor
    func commitResize(to drawableSize: CGSize, view: MTKView?) {
        let started = CACurrentMediaTime()
        drainFramesInFlight()

        // Release: every subsystem's old set, before any new allocation.
        let mvWarpBundle = mvWarpLock.withLock { () -> MVWarpPipelineBundle? in
            defer { mvWarpState = nil }
            return mvWarpState.map(MVWarpPipelineBundle.init(rebuilding:))
        }
        feedbackLock.withLock { feedbackTextures = [] }
        postProcessLock.withLock { postProcessChain?.releaseTextures() }
        rayMarchLock.withLock { rayMarchPipeline?.releaseTextures() }
        stagedLock.withLock {
            stagedTextures.removeAll(keepingCapacity: true)
            stagedBackTextures.removeAll(keepingCapacity: true)
        }
        canvasTexture = nil
        edrLegacyOutput = nil
        halfResTexture = nil
        temporalReconstructor?.releaseTargets()
        spatialUpscaler?.release()   // VQ.3: rebuilt at the new size by the next frame that needs it
        let released = context.renderTargetBudget.totalBytes

        // Allocate: the drawable pool first (the OS holds it whatever we decide), then the new set.
        reserveDrawablePool(size: drawableSize, view: view)
        resizeLock.withLock { committedDrawableSize = drawableSize }
        // A4: every subsystem below allocates at the size scenes render at (the canvas on tier 1).
        let size = updateCanvas(drawableSize: drawableSize)
        let width = max(Int(size.width), 1)
        let height = max(Int(size.height), 1)

        // CLEAN.4.4: only allocate the ping-pong for a preset that samples it. CLEAN.4.3: a failed
        // allocation leaves the pair empty (feedback rendering guards on empty) and falls through so
        // the other subsystems still resize.
        if activePresetSamplesFeedback {
            let textures = makeFeedbackPair(width: width, height: height)
            if textures == nil { logger.error("Failed to allocate feedback textures") }
            feedbackLock.withLock {
                feedbackTextures = textures ?? []
                feedbackIndex = 0
            }
        }

        // Track size so mid-session preset switches allocate mv_warp textures correctly.
        mvWarpLock.withLock { currentDrawableSize = size }
        if let mvWarpBundle { setupMVWarp(bundle: mvWarpBundle, size: size) }
        reallocateStagedTextures(size: size)

        let callbacks: Int = resizeLock.withLock {
            resizeReallocationCount += 1
            return resizeCallbackCount
        }
        let ms = (CACurrentMediaTime() - started) * 1000
        onDrawableSizeCommitted?(drawableSize, callbacks, ms)
        logger.info("""
            Drawable resized to \(width)×\(height) (drawable \(Int(drawableSize.width))×\(Int(drawableSize.height))): \
            drain+release+allocate \(String(format: "%.1f", ms)) ms, budget \(released / 1_048_576) → \
            \(self.context.renderTargetBudget.totalBytes / 1_048_576) MB
            """)
    }

    /// A scene switch starts (top of `applyPreset`, main thread): the new scene's first refusal is reported.
    /// It does not wait for the frames in flight — the outgoing scene's targets stay charged until those
    /// frames complete, and only an allocation that would then cross the ceiling waits for them
    /// (`RenderTargetBudget.reclaim` → `reclaimInFlightTargets`), so an ordinary switch costs nothing.
    @MainActor
    public func beginSceneSwitch() {
        resizeLock.withLock { sceneEpoch += 1 }
        budgetRefusalReported = false
    }

    /// The budget is about to refuse: wait for the frames in flight so targets nothing references any more
    /// actually free, then it checks again. Logged with how long it waited.
    func reclaimInFlightTargets() {
        let started = CACurrentMediaTime()
        drainFramesInFlight()
        let ms = (CACurrentMediaTime() - started) * 1000
        let count: Int = resizeLock.withLock {
            reclaimWaitCount += 1
            return reclaimWaitCount
        }
        logger.info("budget reclaim: waited \(String(format: "%.1f", ms)) ms for the frames in flight (#\(count))")
    }

    /// Wait until every frame committed so far has completed on the GPU.
    func drainFramesInFlight() {
        let last = resizeLock.withLock { lastCommittedCommandBuffer }
        guard let last, last.status.rawValue < MTLCommandBufferStatus.completed.rawValue else { return }
        last.waitUntilCompleted()
    }

    /// Set the layer's drawable count explicitly and charge count × one drawable (forced: the OS
    /// allocates the pool whatever the budget says).
    @MainActor
    private func reserveDrawablePool(size: CGSize, view: MTKView?) {
        let layer = view?.layer as? CAMetalLayer
        layer?.maximumDrawableCount = Self.drawablePoolCount
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: view?.colorPixelFormat ?? context.pixelFormat,
            width: max(Int(size.width), 1),
            height: max(Int(size.height), 1),
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let bytes = Self.drawablePoolCount * context.renderTargetBudget.estimatedBytes(descriptor)
        context.renderTargetBudget.reserve("drawable pool", bytes: bytes, force: true)
    }
}

// MARK: - PendingResize

/// A drawable size waiting to be committed, and when it was first seen.
struct PendingResize {
    let size: CGSize
    let since: CFTimeInterval
}

// MARK: - MVWarpPipelineBundle (rebuild)

extension MVWarpPipelineBundle {
    /// The bundle that rebuilds `state` at a new size (resize re-clears to the same ground, D-143).
    init(rebuilding state: MVWarpState) {
        self.init(
            warpState: state.warpPipeline,
            composeState: state.composePipeline,
            blitState: state.blitPipeline,
            pixelFormat: state.pixelFormat,
            feedbackFormat: state.feedbackFormat,
            blurState: state.blurPipeline,
            isNacre: state.isNacre,
            isFloret: state.isFloret,
            isGlaze: state.isGlaze,
            canvasClearColor: state.canvasClearColor
        )
    }
}
