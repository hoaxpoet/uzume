// FrameBudgetManagerStabilityTests — VQ.0's governor inputs, driven synthetically (D-264).
//
// GPU-time ceiling (two frames > 50 ms → lowest rung, held ≥ 5 s, then the 180-frame recovery one rung
// at a time), command-buffer errors (lowest rung; three in 10 s → the fallback scene), thermal state and
// Low Power Mode (floors + 30 fps cap + fallback on critical), memory pressure, and the completed-frame
// wiring on RenderPipeline.

import Testing
import Metal
@testable import Renderer
@testable import Shared

@Suite("FrameBudgetManagerStability")
@MainActor
struct FrameBudgetManagerStabilityTests {

    private typealias FBM = FrameBudgetManager

    private func manager() -> FBM { FBM(configuration: .tier2Default) }

    /// Feed `count` frames of `gpuMs` at 60 Hz from `start`; returns the time after the last.
    @discardableResult
    private func feed(_ mgr: FBM, gpuMs: Float, count: Int, from start: Double) -> Double {
        var t = start
        for _ in 0..<count {
            t += 1.0 / 60.0
            mgr.observe(.init(cpuFrameMs: 8, gpuFrameMs: gpuMs, timestamp: t))
        }
        return t
    }

    @Test("two frames over 50 ms of GPU time force the lowest rung; one does not")
    func hardCeiling() {
        let mgr = manager()
        mgr.observe(.init(cpuFrameMs: 8, gpuFrameMs: 60, timestamp: 0))
        mgr.observe(.init(cpuFrameMs: 8, gpuFrameMs: 5, timestamp: 0.02))
        mgr.observe(.init(cpuFrameMs: 8, gpuFrameMs: 60, timestamp: 0.04))
        #expect(mgr.appliedLevel == .noBloom || mgr.appliedLevel == .full, "isolated spikes are the D-057 path")
        mgr.observe(.init(cpuFrameMs: 8, gpuFrameMs: 60, timestamp: 0.06))
        #expect(mgr.appliedLevel == .reducedMesh)
        #expect(mgr.forcedSteps.last?.cause.hasPrefix("gpu-time") == true)
    }

    @Test("the forced drop holds ≥ 5 s, then climbs one rung per 180 recovered frames")
    func holdThenClimb() {
        let mgr = manager()
        let dropAt = feed(mgr, gpuMs: 60, count: 2, from: 0)
        #expect(mgr.appliedLevel == .reducedMesh)
        var t = dropAt
        var climbs: [Double] = []
        while climbs.count < 2, t < 30 {
            let before = mgr.appliedLevel
            t = feed(mgr, gpuMs: 4, count: 1, from: t)
            if mgr.appliedLevel != before {
                #expect(mgr.appliedLevel.rawValue == before.rawValue - 1, "one rung at a time")
                climbs.append(t)
            }
        }
        let frame = 1.0 / 60.0
        let firstClimb = climbs.first ?? .infinity
        #expect(firstClimb >= dropAt + FBM.forcedHoldSeconds + 179 * frame, "held 5 s, then 180 frames of recovery")
        #expect(firstClimb <= dropAt + FBM.forcedHoldSeconds + 181 * frame)
        #expect(climbs.count == 2 && abs(climbs[1] - climbs[0] - 180 * frame) < frame / 2)
    }

    @Test("a sustained overrun names its forced step once")
    func sustainedOverrunLogsOnce() {
        let mgr = manager()
        feed(mgr, gpuMs: 80, count: 120, from: 0)
        #expect(mgr.forcedSteps.count == 1)
    }

    @Test("square-wave overrun: no oscillation")
    func squareWave() {
        let mgr = manager()
        var t = 0.0
        var levels: [FBM.QualityLevel] = []
        for _ in 0..<30 {                                  // 30 periods of 1 s over / 1 s fine
            t = feed(mgr, gpuMs: 70, count: 60, from: t)
            levels.append(mgr.appliedLevel)
            t = feed(mgr, gpuMs: 4, count: 60, from: t)
            levels.append(mgr.appliedLevel)
        }
        let changes = zip(levels, levels.dropFirst()).filter { $0 != $1 }.count
        #expect(changes == 0, "level changes across 60 half-periods: \(changes)")
        #expect(levels.allSatisfy { $0 == .reducedMesh })
    }

    @Test("command-buffer error → lowest rung; three inside 10 s → the fallback scene, once")
    func commandBufferErrors() {
        let mgr = manager()
        mgr.observeCommandBufferError("code 1 in 'mv_warp compose'", at: 1)
        #expect(mgr.appliedLevel == .reducedMesh)
        #expect(mgr.forcedSteps.last?.cause.contains("mv_warp compose") == true)
        mgr.observeCommandBufferError("code 1 in 'x'", at: 12)    // the first has aged out
        #expect(!mgr.fallbackSceneRequested)
        mgr.observeCommandBufferError("code 1 in 'x'", at: 13)
        mgr.observeCommandBufferError("code 1 in 'x'", at: 14)
        #expect(mgr.fallbackSceneRequested)
        mgr.acknowledgeFallback()
        #expect(!mgr.fallbackSceneRequested)
    }

    @Test("thermal: fair → one rung, serious → one more + 30 fps, critical → fallback; Low Power → 30 fps")
    func thermal() {
        typealias Response = FBM.ThermalResponse
        #expect(FBM.thermalResponse(thermalState: .nominal, lowPowerMode: false)
                == Response(floor: .full, frameRateCap: nil, fallbackScene: false))
        #expect(FBM.thermalResponse(thermalState: .fair, lowPowerMode: false)
                == Response(floor: .noBloom, frameRateCap: nil, fallbackScene: false))
        #expect(FBM.thermalResponse(thermalState: .serious, lowPowerMode: false)
                == Response(floor: .reducedRayMarch, frameRateCap: 30, fallbackScene: false))
        #expect(FBM.thermalResponse(thermalState: .critical, lowPowerMode: false).fallbackScene)
        // D-167 (Matt): Low Power Mode keeps its no-bloom floor; VQ.0 adds the cap.
        #expect(FBM.thermalResponse(thermalState: .nominal, lowPowerMode: true)
                == Response(floor: .noBloom, frameRateCap: 30, fallbackScene: false))

        let mgr = manager()
        mgr.setThermalState(.critical, lowPowerMode: false)
        #expect(mgr.fallbackSceneRequested && mgr.frameRateCap == 30)
        mgr.acknowledgeFallback()
        mgr.setThermalState(.critical, lowPowerMode: false)
        #expect(!mgr.fallbackSceneRequested, "one request per critical episode")
        mgr.setThermalState(.nominal, lowPowerMode: false)
        #expect(mgr.frameRateCap == nil && mgr.appliedLevel == .full)
    }

    @Test("memory pressure: warning → lowest rung, critical → fallback, normal clears")
    func memoryPressure() {
        let mgr = manager()
        mgr.setMemoryPressure(.warning)
        #expect(mgr.appliedLevel == .reducedMesh && !mgr.fallbackSceneRequested)
        mgr.setMemoryPressure(.critical)
        #expect(mgr.fallbackSceneRequested)
        mgr.setMemoryPressure(.normal)
        #expect(mgr.appliedLevel == .full)
        #expect(mgr.forcedSteps.map(\.cause).contains("memory pressure warning"))
    }

    // MARK: Wiring

    @Test("RenderPipeline: a completed frame's GPU time and fault reach the governor; fallback fires once")
    func completedFrameWiring() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let fft = try #require(ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride))
        let wav = try #require(ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride))
        let pipe = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        let mgr = manager()
        pipe.frameBudgetManager = mgr
        var fallbacks: [String] = []
        pipe.onFallbackSceneRequested = { fallbacks.append($0) }

        pipe.observeCompletedFrame(cpuMs: 8, gpuMs: 70, fault: nil, at: 0)
        pipe.observeCompletedFrame(cpuMs: 8, gpuMs: 70, fault: nil, at: 0.02)
        #expect(mgr.appliedLevel == .reducedMesh, "GPU time reaches the governor")
        for i in 0..<3 {
            pipe.observeCompletedFrame(cpuMs: 8, gpuMs: 5, fault: "code 3 in 'staged world'", at: 1 + Double(i))
        }
        #expect(pipe.commandBufferErrorCount == 3)
        #expect(fallbacks.count == 1 && fallbacks[0].contains("command-buffer errors"))

        // A clean command buffer reports no fault.
        let cb = try #require(ctx.commandQueue.makeCommandBuffer())
        cb.commit()
        cb.waitUntilCompleted()
        #expect(RenderPipeline.faultDescription(cb) == nil)
    }

    @Test("GPU capability line names every measured field")
    func capabilityLine() {
        let line = GPUCapability(chip: "Apple M2 Pro", gpuCores: 16, physicalMemoryBytes: 16 << 30,
                                 recommendedWorkingSetBytes: 12_713_115_648, budgetCeilingBytes: 600 << 20,
                                 drawableNative: CGSize(width: 3840, height: 2160)).logLine
        #expect(line == "GPU_CAPABILITY chip=\"Apple M2 Pro\" gpu_cores=16 memory_gb=16.0 working_set_mb=12124 "
                + "budget_ceiling_mb=600 drawable_native=3840x2160")
        #expect(GPUCapability(chip: "x", gpuCores: nil, physicalMemoryBytes: 0, recommendedWorkingSetBytes: 0,
                              budgetCeilingBytes: 0, drawableNative: nil).logLine.contains("gpu_cores=? "))
    }
}
