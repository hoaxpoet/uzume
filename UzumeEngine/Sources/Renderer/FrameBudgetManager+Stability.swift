// FrameBudgetManager+Stability — VQ.0's governor inputs (D-264): the hard GPU-time ceiling's constants,
// command-buffer errors, thermal state + Low Power Mode (amends D-167) and memory pressure. Backstops:
// GPU timing includes pre-emption by other processes and arrives 3–5 frames late with three in flight;
// bounded shader loops (`Scripts/check_shader_loop_bounds.sh`) are the prevention.

import Foundation
import os.log

private let logger = Logger(subsystem: "io.uzume.renderer", category: "FrameBudgetManager")

extension FrameBudgetManager {

    // MARK: - Constants and types

    /// GPU time per frame above which a frame counts toward the hard ceiling.
    public static let hardGPUCeilingMs: Float = 50
    /// Consecutive frames over the hard ceiling that force the lowest rung.
    public static let hardOverrunFrames = 2
    /// A forced drop holds the lowest rung at least this long before recovery may climb.
    public static let forcedHoldSeconds: TimeInterval = 5
    /// Command-buffer errors inside this window …
    public static let errorWindowSeconds: TimeInterval = 10
    /// … this many of them request the light fallback scene.
    public static let errorsForFallback = 3

    /// One forced step, named by its cause (the session log records each).
    public struct ForcedStep: Sendable, Equatable {
        public let cause: String
        public let level: QualityLevel
        public let frameRateCap: Int?
        public let fallbackScene: Bool
    }

    /// Memory pressure as `DispatchSource.makeMemoryPressureSource` reports it.
    public enum MemoryPressure: Sendable { case normal, warning, critical }

    // MARK: - Thermal / Low Power (VQ.0)

    /// What the governor does for a thermal state + Low Power Mode (VQ.0, D-264; amends D-167):
    /// fair → one rung down; serious → one more and 30 fps; critical → the light fallback scene (and
    /// the lowest rung). Low Power Mode keeps Matt's D-167 `.noBloom` floor and adds the 30 fps cap.
    public struct ThermalResponse: Sendable, Equatable {
        public let floor: QualityLevel
        public let frameRateCap: Int?
        public let fallbackScene: Bool
    }

    /// Pure mapping — the listener reads `ProcessInfo` and feeds the values here.
    public static func thermalResponse(
        thermalState: ProcessInfo.ThermalState,
        lowPowerMode: Bool
    ) -> ThermalResponse {
        var floor: QualityLevel
        var cap: Int?
        var fallback = false
        switch thermalState {
        case .nominal:    floor = .full
        case .fair:       floor = .noBloom
        case .serious:    floor = .reducedRayMarch; cap = 30
        case .critical:   floor = .reducedMesh; cap = 30; fallback = true
        @unknown default: floor = .noBloom
        }
        // D-167 amended (Matt, 2026-08-26): Low Power Mode floors at `.noBloom` (bloom off, ACES
        // kept). VQ.0 adds the 30 fps cap.
        if lowPowerMode {
            floor = max(floor, .noBloom)
            cap = 30
        }
        return ThermalResponse(floor: floor, frameRateCap: cap, fallbackScene: fallback)
    }

    /// The floor half of `thermalResponse` (kept for the existing callers).
    public static func qualityFloor(
        thermalState: ProcessInfo.ThermalState,
        lowPowerMode: Bool
    ) -> QualityLevel {
        thermalResponse(thermalState: thermalState, lowPowerMode: lowPowerMode).floor
    }

    /// Apply the thermal / Low Power Mode response: floor, frame-rate cap and, on entering critical,
    /// one fallback-scene request.
    public func setThermalState(_ thermalState: ProcessInfo.ThermalState, lowPowerMode: Bool) {
        let response = Self.thermalResponse(thermalState: thermalState, lowPowerMode: lowPowerMode)
        setThermalFloor(response.floor)
        let cause = "thermal \(Self.name(thermalState))\(lowPowerMode ? " + low-power" : "")"
        if response.frameRateCap != frameRateCap {
            frameRateCap = response.frameRateCap
            record(cause: cause)
        }
        if response.fallbackScene, !thermalCritical { requestFallback(cause: cause) }
        thermalCritical = response.fallbackScene
    }

    // MARK: - Command-buffer errors / memory pressure (VQ.0)

    /// A command buffer completed with `.error`: the lowest rung (held ≥ 5 s); three inside 10 s
    /// request the light fallback scene. `description` names the code and the failing encoder.
    public func observeCommandBufferError(_ description: String, at now: TimeInterval) {
        clock = max(clock, now)
        guard configuration.enabled else { return }
        errorTimes = errorTimes.filter { now - $0 < Self.errorWindowSeconds } + [now]
        forceLowest(cause: "command-buffer error: \(description)", now: now)
        if errorTimes.count >= Self.errorsForFallback {
            errorTimes.removeAll()
            let window = Int(Self.errorWindowSeconds)
            requestFallback(cause: "\(Self.errorsForFallback) command-buffer errors in \(window) s")
        }
    }

    /// Memory pressure: warning → the lowest rung (the pipeline also stops any new scene allocation
    /// larger than the current one); critical → the light fallback scene; normal clears both.
    public func setMemoryPressure(_ pressure: MemoryPressure) {
        let floor: QualityLevel = pressure == .normal ? .full : .reducedMesh
        if floor != pressureFloor {
            pressureFloor = floor
            record(cause: "memory pressure \(pressure)")
        }
        let critical = pressure == .critical
        if critical, !pressureCritical { requestFallback(cause: "memory pressure critical") }
        pressureCritical = critical
    }

    /// The pipeline has acted on the fallback request.
    public func acknowledgeFallback() {
        fallbackSceneRequested = false
    }

    func forceLowest(cause: String, now: TimeInterval) {
        let lowest = QualityLevel.allCases.last ?? .reducedMesh
        let alreadyHeld = currentLevel == lowest && now < holdUntil
        currentLevel = lowest
        consecutiveOverruns = 0
        consecutiveRecovered = 0
        holdUntil = now + Self.forcedHoldSeconds
        // A sustained overrun re-arms the hold every two frames; name the step once, not 30×/s.
        if !alreadyHeld { record(cause: cause) }
    }

    func requestFallback(cause: String) {
        fallbackSceneRequested = true
        fallbackCause = cause
        record(cause: cause, fallback: true)
    }

    func record(cause: String, fallback: Bool = false) {
        let step = ForcedStep(cause: cause, level: appliedLevel, frameRateCap: frameRateCap, fallbackScene: fallback)
        forcedSteps.append(step)
        if forcedSteps.count > 256 { forcedSteps.removeFirst(forcedSteps.count - 256) }
        let fps = frameRateCap.map { " cap=\($0)fps" } ?? ""
        logger.info("""
            forced: \(cause, privacy: .public) → \(step.level.displayName, privacy: .public)\(fps, privacy: .public)\
            \(fallback ? " fallback-scene" : "", privacy: .public)
            """)
        onForcedStep?(step)
    }

    private static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
