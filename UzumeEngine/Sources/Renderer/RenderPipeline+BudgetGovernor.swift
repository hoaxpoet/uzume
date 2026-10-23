// RenderPipeline+BudgetGovernor — Quality-level gate application (D-057).
//
// Translates FrameBudgetManager.QualityLevel into scalar attenuation across
// five subsystems. The governor never modifies activePasses — it only
// attenuates work within existing passes.

import Metal
import Shared

extension RenderPipeline {

    // MARK: - Quality Level Application

    /// Apply a governor quality level to all five subsystem gates.
    ///
    /// Each level is a strict superset of reductions from the level above it.
    /// Called from the @MainActor completed-handler hop — one frame behind the
    /// measured frame.
    @MainActor
    func applyQualityLevel(_ level: FrameBudgetManager.QualityLevel) {
        let bloomOff = level >= .noBloom
        postProcessLock.withLock { postProcessChain }?.bloomEnabled = !bloomOff

        let stepMult: Float = level >= .reducedRayMarch ? 0.75 : 1.0
        rayMarchLock.withLock { rayMarchPipeline }?.stepCountMultiplier = stepMult

        let particleFraction: Float = level >= .reducedParticles ? 0.5 : 1.0
        particleLock.withLock { particleGeometry }?.activeParticleFraction = particleFraction

        // No-op on M1/M2 vertex fallback — D-057(e).
        let meshDensity: Float = level >= .reducedMesh ? 0.5 : 1.0
        meshLock.withLock { meshGenerator }?.densityMultiplier = meshDensity
    }

    // MARK: - Completed frames (VQ.0)

    /// Feed one completed frame to the governor and apply what it decides: the quality level, a
    /// command-buffer error, the frame-rate cap and a fallback-scene request.
    @MainActor
    func observeCompletedFrame(cpuMs: Float, gpuMs: Float?, fault: String?, at time: CFTimeInterval) {
        if let fault {
            commandBufferErrorCount += 1
            frameBudgetManager?.observeCommandBufferError(fault, at: time)
        }
        guard let mgr = frameBudgetManager else { return }
        let level = mgr.observe(.init(cpuFrameMs: cpuMs, gpuFrameMs: gpuMs, timestamp: time))
        applyQualityLevel(level)
        applyGovernorRequests()
    }

    /// Act on the governor's latched fallback request (once).
    @MainActor
    public func applyGovernorRequests() {
        guard let mgr = frameBudgetManager, mgr.fallbackSceneRequested else { return }
        mgr.acknowledgeFallback()
        onFallbackSceneRequested?(mgr.fallbackCause ?? "governor")
    }

    /// Memory pressure (from the app's `DispatchSource.makeMemoryPressureSource`): warning → the lowest
    /// rung, scenes keep playing; critical → the light fallback scene, and no new scene allocation larger
    /// than the current one (the budget's ceiling is capped at today's total); normal restores both.
    @MainActor
    public func handleMemoryPressure(_ pressure: FrameBudgetManager.MemoryPressure) {
        let budget = context.renderTargetBudget
        switch pressure {
        case .normal, .warning:
            // Matt (2026-10-22, option A): a warning lowers quality but keeps the planned scenes — warnings
            // are routine on 8–16 GB Macs (3 in 90 min of ordinary work on the 16 GB dev Mac), and capping
            // the budget there collapsed playback to the light scene each time.
            if let restore = ceilingBeforeMemoryPressure { budget.ceiling = restore }
            ceilingBeforeMemoryPressure = nil
        case .critical:
            // No new scene larger than the current one. That needs a current scene: with nothing but the
            // drawable pool live (launch, a switch in flight) there is nothing to compare against, so no cap.
            let pool = budget.reservedBytes.values.reduce(0, +)
            guard budget.totalBytes > pool else { break }
            if ceilingBeforeMemoryPressure == nil { ceilingBeforeMemoryPressure = budget.ceiling }
            budget.ceiling = min(budget.ceiling, budget.totalBytes)
        }
        frameBudgetManager?.setMemoryPressure(pressure)
        applyQualityLevel(frameBudgetManager?.appliedLevel ?? .full)
        applyGovernorRequests()
    }

    /// True while memory pressure caps the budget at the current scene's set (a refusal now is
    /// transient: the app falls back to the light scene instead of skipping the refused one for good).
    @MainActor
    public var isMemoryPressureCapped: Bool { ceilingBeforeMemoryPressure != nil }

    /// The failing frame's error code and encoder, or nil when it completed cleanly.
    static func faultDescription(_ commandBuffer: MTLCommandBuffer) -> String? {
        guard commandBuffer.status == .error else { return nil }
        let error = commandBuffer.error as NSError?
        let infos = error?.userInfo[MTLCommandBufferEncoderInfoErrorKey] as? [MTLCommandBufferEncoderInfo] ?? []
        let encoder = infos.first { $0.errorState == .faulted }?.label ?? "unknown encoder"
        return "code \(error?.code ?? -1) in '\(encoder)'"
    }
}
