// VisualizerEngine+RenderSoak — VQ.0's 4K render soak, render-memory inventory and scene cycler.
//
// Developer env vars only; a normal launch sets none and this file does nothing. They run INSIDE the
// app because the production scene path is the app's `applyPreset` (the engine has no copy of it):
// the soak and the inventory measure exactly what a viewer's Mac allocates.
//
//   UZUME_SCENE_CYCLE_SECONDS=20      cycle every certified scene, this many seconds each (holds the plan)
//   UZUME_DRAWABLE_OVERRIDE=3840x2160 force the drawable to this size (the compositor scales it to the window)
//   UZUME_RESIZE_TOGGLE_SECONDS=300   toggle the override ↔ 1920×1080 at this period
//   UZUME_RENDER_SOAK_REPORT=<dir>    write render_soak_minutes.csv + render_soak_summary.txt there
//   UZUME_RENDER_SOAK_MINUTES=60      stop (write the summary, quit) after this long
//   UZUME_FOOTPRINT_KILL_MB=4096      exit(3) when phys_footprint crosses this (default 4096 with a report)
//   UZUME_RENDER_INVENTORY=<file.md>  run the render-memory inventory, write it, quit
//
// Recipes: `docs/RUNBOOK.md` §VQ.0 render soak; `Scripts/render_soak.sh`, `Scripts/tv_soak.sh`.

import AppKit
import Foundation
import Metal
import os.log
import Presets
import Renderer
import Shared

private let logger = Logger(subsystem: "io.uzume.mac", category: "RenderSoak")

extension VisualizerEngine {

    /// Start the driver if any of its env vars is set. Called once the first session begins playing.
    @MainActor
    func startRenderSoakIfRequested() {
        guard renderSoak == nil, let config = RenderSoakDriver.Config(environment: ProcessInfo.processInfo.environment)
        else { return }
        diagnosticPresetLocked = true   // the driver owns scene choice (the REC.2 hold)
        let driver = RenderSoakDriver(config: config, engine: self)
        renderSoak = driver
        driver.start()
    }
}

// MARK: - RenderSoakDriver

/// Drives scene cycling, drawable-size toggles, per-minute measurement and the inventory. Main thread.
@MainActor
final class RenderSoakDriver {

    struct Config {
        var cycleSeconds: Double?
        var drawableOverride: CGSize?
        var toggleSeconds: Double?
        var reportDirectory: URL?
        var minutes: Double?
        var killMB: Int?
        var inventoryPath: URL?

        init?(environment env: [String: String]) {
            cycleSeconds = env["UZUME_SCENE_CYCLE_SECONDS"].flatMap(Double.init)
            drawableOverride = env["UZUME_DRAWABLE_OVERRIDE"].flatMap(Self.size)
            toggleSeconds = env["UZUME_RESIZE_TOGGLE_SECONDS"].flatMap(Double.init)
            reportDirectory = env["UZUME_RENDER_SOAK_REPORT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            minutes = env["UZUME_RENDER_SOAK_MINUTES"].flatMap(Double.init)
            killMB = env["UZUME_FOOTPRINT_KILL_MB"].flatMap(Int.init) ?? (reportDirectory == nil ? nil : 4096)
            inventoryPath = env["UZUME_RENDER_INVENTORY"].map { URL(fileURLWithPath: $0) }
            if cycleSeconds == nil, drawableOverride == nil, reportDirectory == nil, inventoryPath == nil { return nil }
        }

        /// "3840x2160" → 3840×2160.
        static func size(_ text: String) -> CGSize? {
            let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
    }

    private let config: Config
    private weak var engine: VisualizerEngine?
    private var timers: [Timer] = []
    private let started = CACurrentMediaTime()
    private var sceneIndex = 0
    private var toggledDown = false

    // Measurement
    private var switchUntil: CFTimeInterval = 0
    private var minute = MinuteSample()
    private var minuteIndex = 0
    private var rows: [String] = []
    private var frameCount = 0

    init(config: Config, engine: VisualizerEngine) {
        self.config = config
        self.engine = engine
    }

    // MARK: Start

    func start() {
        guard let engine else { return }
        if let size = config.drawableOverride { PixelModeMTKView.drawableOverride = size }
        hookFrames(engine.pipeline)
        if let path = config.inventoryPath {
            Task { await runInventory(to: path) }
            return
        }
        if let seconds = config.cycleSeconds {
            nextScene()
            schedule(every: seconds) { $0.nextScene() }
        }
        if let seconds = config.toggleSeconds, config.drawableOverride != nil {
            schedule(every: seconds) { $0.toggleSize() }
        }
        if config.reportDirectory != nil {
            schedule(every: 60) { $0.closeMinute() }
        }
        if let limit = config.killMB {
            schedule(every: 2) { $0.checkFootprint(limitMB: limit) }
        }
        if let minutes = config.minutes {
            schedule(every: minutes * 60, repeats: false) { $0.finish(reason: "\(Int(minutes)) minutes") }
        }
        logger.info("VQ.0 render soak started")
    }

    private func schedule(every seconds: Double, repeats: Bool = true,
                          _ body: @escaping @MainActor (RenderSoakDriver) -> Void) {
        timers.append(Timer.scheduledTimer(withTimeInterval: seconds, repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated { if let self { body(self) } }
        })
    }

    // MARK: Scenes and sizes

    /// Certified scenes this Mac can plan, in name order.
    private var certifiedScenes: [PresetLoader.LoadedPreset] {
        guard let engine else { return [] }
        let plannable = Set(engine.plannableCatalog.filter(\.certified).map(\.id))
        return engine.presetLoader.presets.filter { plannable.contains($0.descriptor.id) }
            .sorted { $0.descriptor.name < $1.descriptor.name }
    }

    private func nextScene() {
        let scenes = certifiedScenes
        guard let engine, !scenes.isEmpty else { return }
        let scene = scenes[sceneIndex % scenes.count]
        sceneIndex += 1
        markSwitch()
        engine.applyPreset(scene)
        engine.sessionRecorder?.log("RENDER_SOAK scene=\(scene.descriptor.name)")
    }

    private func toggleSize() {
        guard let full = config.drawableOverride else { return }
        toggledDown.toggle()
        markSwitch()
        PixelModeMTKView.drawableOverride = toggledDown ? CGSize(width: 1920, height: 1080) : full
        engine?.sessionRecorder?.log("RENDER_SOAK drawable=\(Int(PixelModeMTKView.drawableOverride?.width ?? 0))")
    }

    /// Frames for the next 1.5 s are switch frames, reported apart.
    private func markSwitch() { switchUntil = CACurrentMediaTime() + 1.5 }

    // MARK: Frames

    private func hookFrames(_ pipe: RenderPipeline) {
        let previous = pipe.onFrameTimingObserved
        pipe.onFrameTimingObserved = { [weak self] cpuMs, gpuMs in
            previous?(cpuMs, gpuMs)
            MainActor.assumeIsolated { self?.observe(cpuMs: cpuMs, gpuMs: gpuMs) }
        }
        let committed = pipe.onDrawableSizeCommitted
        pipe.onDrawableSizeCommitted = { [weak self] size, callbacks, ms in
            committed?(size, callbacks, ms)
            MainActor.assumeIsolated { self?.markSwitch() }
        }
    }

    private func observe(cpuMs: Float, gpuMs: Float?) {
        frameCount += 1
        if CACurrentMediaTime() < switchUntil {
            minute.switchCPU.append(cpuMs)
            if let gpuMs { minute.switchGPU.append(gpuMs) }
        } else {
            minute.cpu.append(cpuMs)
            if let gpuMs { minute.gpu.append(gpuMs) }
        }
    }

    // MARK: Per-minute report

    private struct MinuteSample {
        var cpu: [Float] = [], gpu: [Float] = [], switchCPU: [Float] = [], switchGPU: [Float] = []
    }

    static let csvHeader = "minute,footprint_mb,metal_alloc_mb,budget_mb,budget_peak_mb,ceiling_mb,frames,"
        + "gpu_p50_ms,gpu_p95_ms,cpu_max_ms,frames_over_250ms,switch_frames,switch_gpu_p95_ms,switch_cpu_p95_ms,"
        + "cb_errors,forced_steps,refusals,drawable"

    private func closeMinute() {
        guard let engine else { return }
        minuteIndex += 1
        let budget = engine.context.renderTargetBudget
        let drawable = PixelModeMTKView.drawableOverride.map { "\(Int($0.width))x\(Int($0.height))" } ?? "native"
        let row = [
            "\(minuteIndex)", "\(Self.footprintMB())",
            "\(engine.context.device.currentAllocatedSize / 1_048_576)",
            "\(budget.totalBytes / 1_048_576)", "\(budget.peakTotalBytes / 1_048_576)", "\(budget.ceiling / 1_048_576)",
            "\(minute.cpu.count + minute.switchCPU.count)",
            Self.format(Self.percentile(minute.gpu, 0.5)), Self.format(Self.percentile(minute.gpu, 0.95)),
            Self.format(minute.cpu.max()), "\(minute.cpu.filter { $0 > 250 }.count)",
            "\(minute.switchCPU.count)", Self.format(Self.percentile(minute.switchGPU, 0.95)),
            Self.format(Self.percentile(minute.switchCPU, 0.95)),
            "\(engine.pipeline.commandBufferErrorCount)",
            "\(engine.pipeline.frameBudgetManager?.forcedSteps.count ?? 0)",
            "\(budget.refusals.count)", drawable,
        ].joined(separator: ",")
        rows.append(row)
        minute = MinuteSample()
        writeReport(summary: nil)
        engine.sessionRecorder?.log("RENDER_SOAK_MINUTE \(row)")
    }

    private func checkFootprint(limitMB: Int) {
        let footprint = Self.footprintMB()
        guard footprint > limitMB else { return }
        engine?.sessionRecorder?.log("RENDER_SOAK_KILLED footprint_mb=\(footprint) limit_mb=\(limitMB)")
        closeMinute()
        writeReport(summary: "KILLED: phys_footprint \(footprint) MB > \(limitMB) MB at \(elapsedMinutes()) min")
        exit(3)
    }

    private func finish(reason: String) {
        closeMinute()
        writeReport(summary: "completed: \(reason), \(frameCount) frames")
        engine?.sessionRecorder?.log("RENDER_SOAK_DONE \(reason)")
        NSApp.terminate(nil)
    }

    private func elapsedMinutes() -> String { String(format: "%.1f", (CACurrentMediaTime() - started) / 60) }

    private func writeReport(summary: String?) {
        guard let dir = config.reportDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let csv = ([Self.csvHeader] + rows).joined(separator: "\n") + "\n"
        try? csv.write(to: dir.appendingPathComponent("render_soak_minutes.csv"), atomically: true, encoding: .utf8)
        if let summary {
            let url = dir.appendingPathComponent("render_soak_summary.txt")
            try? (summary + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: Inventory

    private struct InventoryConfig {
        let label: String
        let size: CGSize
        let capped: Bool
    }

    /// Every certified scene × {1080p, 1440p, 2160p with this Mac's BR.6b cap, 2160p uncapped}: apply,
    /// render 120 frames, let the GPU idle, then read the budget's live targets and Metal's own total.
    private func runInventory(to path: URL) async {
        guard let engine else { return }
        let pipe = engine.pipeline
        let originalCap = pipe.currentRenderPixelCap
        let uhd = CGSize(width: 3840, height: 2160)
        let configs = [
            InventoryConfig(label: "1920×1080", size: CGSize(width: 1920, height: 1080), capped: true),
            InventoryConfig(label: "2560×1440", size: CGSize(width: 2560, height: 1440), capped: true),
            InventoryConfig(label: "3840×2160 (this Mac, BR.6b cap)", size: uhd, capped: true),
            InventoryConfig(label: "3840×2160 (uncapped, M3/M4)", size: uhd, capped: false),
        ]
        var results: [RenderInventoryReport.Row] = []
        for config in configs {
            pipe.setRenderPixelCap(config.capped ? originalCap : nil)
            PixelModeMTKView.drawableOverride = config.size
            try? await Task.sleep(for: .milliseconds(700))
            for scene in certifiedScenes {
                engine.applyPreset(scene)
                minute = MinuteSample()
                let target = frameCount + 120
                while frameCount < target { try? await Task.sleep(for: .milliseconds(20)) }
                try? await Task.sleep(for: .milliseconds(300))   // the last frames complete; GPU idle
                let budget = engine.context.renderTargetBudget
                let live = budget.liveAllocations
                results.append(RenderInventoryReport.Row(
                    scene: scene.descriptor.name,
                    config: config.label,
                    labelledBytes: live.reduce(0) { $0 + $1.bytes },
                    reservedBytes: budget.reservedBytes.values.reduce(0, +),
                    metalBytes: engine.context.device.currentAllocatedSize,
                    gpuP50: Self.percentile(minute.gpu, 0.5),
                    targets: live
                ))
                logger.info("inventory \(scene.descriptor.name, privacy: .public) @ \(config.label, privacy: .public)")
            }
        }
        pipe.setRenderPixelCap(originalCap)
        let machine = GPUCapability.current(
            device: engine.context.device,
            budgetCeilingBytes: engine.context.renderTargetBudget.ceiling,
            drawableNative: nil
        ).logLine
        let text = RenderInventoryReport.markdown(rows: results, configs: configs.map(\.label), machine: machine)
        try? text.write(to: path, atomically: true, encoding: .utf8)
        engine.sessionRecorder?.log("RENDER_INVENTORY written \(path.path)")
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    static func percentile(_ values: [Float], _ fraction: Double) -> Float? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[min(Int(Double(sorted.count - 1) * fraction + 0.5), sorted.count - 1)]
    }

    static func format(_ value: Float?) -> String { value.map { String(format: "%.2f", $0) } ?? "" }

    /// This process's `phys_footprint` in MB.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint / 1_048_576) : -1
    }
}
