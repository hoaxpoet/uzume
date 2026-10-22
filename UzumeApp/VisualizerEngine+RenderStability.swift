// VisualizerEngine+RenderStability — the app side of VQ.0's stability floor (D-264).
//
// The engine's render-target budget refuses a scene that would cross this Mac's ceiling, and the
// frame-budget governor asks for a light fallback scene under critical heat, critical memory
// pressure or repeated command-buffer errors. This file turns those into what the viewer sees:
//   - a refused scene is skipped for the rest of the session on this Mac (Matt's DECISION-NEEDED
//     option A: nothing looks different, that scene just never appears) and the next one plays;
//   - a fallback request plays the designated light scene;
//   - every forced governor step, refusal and committed resize is named in the session log, and the
//     GPU capability line is logged once the drawable's native size is known.

import Foundation
import Metal
import os.log
import Renderer
import Shared

private let logger = Logger(subsystem: "io.uzume.mac", category: "RenderStability")

extension VisualizerEngine {

    /// The light scene the governor falls back to: the certified scene with the lowest measured 4K GPU
    /// time in the VQ.0 inventory (`docs/diagnostics/VQ0_RENDER_MEMORY_INVENTORY.md`).
    static let lightFallbackSceneID = "Meniscus"   // 0.53 ms GPU at 4K, no size-scaled targets; ids are names

    // MARK: - Wiring

    /// Wire the budget, governor and resize callbacks; start the memory-pressure source; apply the
    /// floor-simulation ceiling if asked. Called once from init.
    func setupRenderStability(pipe: RenderPipeline, ctx: MetalContext) {
        if let gigabytes = ProcessInfo.processInfo.environment["UZUME_SIMULATE_MAC_GB"].flatMap(Double.init) {
            ctx.renderTargetBudget.ceiling = Self.simulatedCeiling(gigabytes: gigabytes, device: ctx.device)
            logger.info("VQ.0 floor simulation: \(gigabytes) GB Mac → ceiling \(ctx.renderTargetBudget.ceiling / 1_048_576) MB")
        }

        let recorder = sessionRecorder
        var loggedCapability = false
        pipe.onDrawableSizeCommitted = { [weak ctx] drawable, callbacks, ms in
            guard let ctx else { return }
            let budget = ctx.renderTargetBudget
            if !loggedCapability {
                loggedCapability = true
                let capability = GPUCapability.current(
                    device: ctx.device,
                    budgetCeilingBytes: budget.ceiling,
                    drawableNative: drawable
                )
                let line = capability.logLine
                GPUCapability.lastLogged = line
                recorder?.log(line)
                logger.info("\(line, privacy: .public)")
            }
            let line = "RENDER_RESIZE drawable=\(Int(drawable.width))x\(Int(drawable.height)) callbacks=\(callbacks) "
                + String(format: "drain_release_alloc_ms=%.1f ", ms)
                + "budget_mb=\(budget.totalBytes / 1_048_576) peak_mb=\(budget.peakTotalBytes / 1_048_576)"
            recorder?.log(line)
            logger.info("\(line, privacy: .public)")
        }
        pipe.onRenderBudgetRefusal = { [weak self] refusal in self?.handleRenderBudgetRefusal(refusal) }
        pipe.onFallbackSceneRequested = { [weak self] cause in self?.applyLightFallbackScene(cause: cause) }
        pipe.frameBudgetManager?.onForcedStep = { step in
            let cap = step.frameRateCap.map { " cap=\($0)fps" } ?? ""
            let line = "GOVERNOR_FORCED cause=\"\(step.cause)\" level=\(step.level.displayName)\(cap)"
                + (step.fallbackScene ? " fallback-scene" : "")
            recorder?.log(line)
        }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let event = source?.data else { return }
            let pressure: FrameBudgetManager.MemoryPressure =
                event.contains(.critical) ? .critical : (event.contains(.warning) ? .warning : .normal)
            self.sessionRecorder?.log("MEMORY_PRESSURE \(pressure)")
            MainActor.assumeIsolated { self.pipeline.handleMemoryPressure(pressure) }
        }
        source.resume()
        memoryPressureSource = source
    }

    /// The ceiling an `gigabytes` GB Mac would get: the D-264 formula with this Mac's
    /// working-set-to-memory ratio (there is no 8 GB Mac here to read its own from).
    static func simulatedCeiling(gigabytes: Double, device: MTLDevice) -> Int {
        let physical = UInt64(gigabytes * 1_073_741_824)
        let ratio = Double(device.recommendedMaxWorkingSetSize) / Double(ProcessInfo.processInfo.physicalMemory)
        let workingSet = UInt64(Double(physical) * ratio)
        return RenderTargetBudget.ceiling(physicalMemory: physical, recommendedWorkingSet: workingSet)
    }

    // MARK: - Refusal → skip

    /// The budget refused the active scene: skip it for the session and play the next one.
    @MainActor
    func handleRenderBudgetRefusal(_ refusal: RenderTargetBudget.Refusal) {
        // The scene on screen, as `applyPreset` recorded it (`presetLoader.currentPreset` lags planned applies).
        let current = stemsStateLock.withLock { onScreenScene.name }
        guard !current.isEmpty, !renderBudgetRefusedPresetIDs.contains(current) else { return }
        // Under memory pressure the cap is the current scene's set, and it lifts when pressure does:
        // a refusal then says nothing about this Mac, so play the light scene and ban nothing.
        if pipeline.isMemoryPressureCapped {
            sessionRecorder?.log("RENDER_BUDGET_REFUSED scene=\(current) owner=\(refusal.owner) under memory pressure")
            guard current != Self.lightFallbackSceneID else { return }
            applyLightFallbackScene(cause: "budget refusal under memory pressure")
            return
        }
        renderBudgetRefusedPresetIDs.insert(current)
        let line = "RENDER_BUDGET_REFUSED scene=\(current) owner=\(refusal.owner) "
            + "requested_mb=\(refusal.requestedBytes / 1_048_576) total_mb=\(refusal.totalBytes / 1_048_576) "
            + "ceiling_mb=\(refusal.ceilingBytes / 1_048_576)"
        sessionRecorder?.log(line)
        logger.error("\(line, privacy: .public)")
        let planOrder = orchestratorLock.withLock { livePlan }?.tracks.flatMap { $0.segments.map(\.preset.id) } ?? []
        guard let next = Self.sceneAfterRefusal(
                current: current,
                planOrder: planOrder,
                catalog: plannableCatalog.map(\.id),
                excluded: renderBudgetRefusedPresetIDs
              ),
              let loaded = presetLoader.presets.first(where: { $0.descriptor.id == next }) else { return }
        applyPreset(loaded)
        showPresetName(loaded.descriptor.name)
    }

    /// The scene to play instead of `current`: the next plan entry after it that is not excluded,
    /// else the first catalog scene that is neither excluded nor `current`. Pure (tested).
    static func sceneAfterRefusal(current: String, planOrder: [String], catalog: [String],
                                  excluded: Set<String>) -> String? {
        let start = planOrder.firstIndex(of: current).map { $0 + 1 } ?? planOrder.count
        let ahead = planOrder[start...] + planOrder[..<min(start, planOrder.count)]
        return ahead.first { !excluded.contains($0) && $0 != current }
            ?? catalog.first { !excluded.contains($0) && $0 != current }
    }

    // MARK: - Fallback scene

    /// The governor wants the light fallback scene (critical heat or memory pressure, repeated
    /// command-buffer errors).
    @MainActor
    func applyLightFallbackScene(cause: String) {
        sessionRecorder?.log("GOVERNOR_FALLBACK_SCENE cause=\"\(cause)\" scene=\(Self.lightFallbackSceneID)")
        guard stemsStateLock.withLock({ onScreenScene.name }) != Self.lightFallbackSceneID,
              let loaded = presetLoader.presets.first(where: { $0.descriptor.id == Self.lightFallbackSceneID })
        else { return }
        applyPreset(loaded)
        showPresetName(loaded.descriptor.name)
    }

    // MARK: - Floor simulation

    /// "warning:24,critical:42,normal:51" → [(.warning, 24), …]; unknown entries are skipped.
    static func pressureSchedule(env name: String) -> [(FrameBudgetManager.MemoryPressure, Double)] {
        let levels: [String: FrameBudgetManager.MemoryPressure] = ["warning": .warning, "critical": .critical,
                                                                   "normal": .normal]
        return (ProcessInfo.processInfo.environment[name] ?? "").split(separator: ",").compactMap { entry in
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let level = levels[String(parts[0])], let minute = Double(parts[1])
            else { return nil }
            return (level, minute)
        }
    }
}
