// RenderTargetBudgetTests — VQ.0's budgeted allocator and drain → release → allocate resize (D-264).
//
// Drives the REAL RenderPipeline subsystems: the feedback pair, Dragon Bloom's mv_warp set (its own
// sidecar pipelines), a RayMarchPipeline's G-buffer (allocated the way the frame's lazy path does)
// and Staged Sandbox's stages. GPU idle is reached by committing an empty command buffer and waiting.

import Testing
import Metal
import MetalKit
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Fixture

@MainActor
private struct Rig {
    let ctx: MetalContext
    let pipeline: RenderPipeline
    let loader: PresetLoader
    let view: MTKView
    var budget: RenderTargetBudget { ctx.renderTargetBudget }

    init() throws {
        ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let fft = try #require(ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride))
        let wav = try #require(ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride))
        pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        view = MTKView(frame: .zero, device: ctx.device)
    }

    func preset(_ name: String) throws -> PresetLoader.LoadedPreset {
        try #require(loader.presets.first { $0.descriptor.name == name })
    }

    /// Wait until everything committed so far has completed.
    func idle() {
        let cb = ctx.commandQueue.makeCommandBuffer()
        cb?.commit()
        cb?.waitUntilCompleted()
    }

    /// Commit `size` the way a stable callback does.
    func resize(_ size: CGSize) {
        pipeline.mtkView(view, drawableSizeWillChange: size)
        pipeline.flushPendingResize(view: view)
    }

    /// Dragon Bloom's mv_warp set, as `applyPreset` builds it.
    func attachMVWarp(size: CGSize) throws {
        let warp = try #require(try preset("Dragon Bloom").mvWarpPipelines)
        pipeline.setupMVWarp(bundle: MVWarpPipelineBundle(
            warpState: warp.warpState, composeState: warp.composeState, blitState: warp.blitState,
            pixelFormat: ctx.pixelFormat, feedbackFormat: ctx.pixelFormat, blurState: warp.blurState,
            isNacre: false, isFloret: false, canvasClearColor: SIMD4(0, 0, 0, 1)), size: size)
    }

    func attachStaged(size: CGSize) throws {
        let specs = try preset("Staged Sandbox").stages.map {
            StagedStageSpec(name: $0.name, pipelineState: $0.pipelineState, samples: $0.samples,
                            writesToDrawable: $0.writesToDrawable, persistent: $0.persistent,
                            iterations: $0.iterations, pixelFormat: $0.pixelFormat)
        }
        pipeline.setStagedRuntime(specs, drawableSize: size)
    }

    var chargedEqualsLive: Bool {
        budget.totalBytes == budget.liveAllocations.reduce(0) { $0 + $1.bytes } + budget.reservedBytes.values.reduce(0, +)
    }
}

private let hd = CGSize(width: 1920, height: 1080)
private let uhd = CGSize(width: 3840, height: 2160)

// MARK: - Budget

@Suite("RenderTargetBudget")
@MainActor
struct RenderTargetBudgetTests {

    @Test("charges Metal's allocatedSize; the total follows live targets")
    func chargesLiveTargets() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let budget = RenderTargetBudget(device: device, ceiling: 1 << 40)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1920, height: 1080,
                                                            mipmapped: false)
        desc.storageMode = .private
        desc.usage = [.renderTarget, .shaderRead]
        var pair = try #require(budget.makeTextures(owner: "t", [.init(desc, label: "a"), .init(desc, label: "b")]))
        #expect(budget.totalBytes == pair.reduce(0) { $0 + $1.allocatedSize })
        #expect(budget.totalBytes >= 2 * 1920 * 1080 * 8)
        #expect(Set(budget.liveAllocations.map(\.label)) == ["a", "b"])
        pair.removeLast()
        #expect(budget.totalBytes == pair[0].allocatedSize, "a released target stops being charged")
        pair = []
        #expect(budget.totalBytes == 0)
    }

    @Test("a set that would cross the ceiling is refused whole: nothing made, nothing charged")
    func refusesWholeSet() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1920, height: 1080,
                                                            mipmapped: false)
        desc.storageMode = .private
        let one = RenderTargetBudget(device: device).estimatedBytes(desc)
        let budget = RenderTargetBudget(device: device, ceiling: one * 3 / 2)
        #expect(budget.makeTextures(owner: "pair", [.init(desc, label: "a"), .init(desc, label: "b")]) == nil)
        #expect(budget.totalBytes == 0)
        #expect(budget.liveAllocations.isEmpty)
        #expect(budget.refusals.count == 1 && budget.refusals[0].owner == "pair")
        #expect(budget.makeTexture(owner: "one", label: "a", descriptor: desc) != nil, "one still fits")
    }

    @Test("reservations: refused past the ceiling unless forced; replaced by name")
    func reservations() throws {
        let budget = RenderTargetBudget(device: try #require(MTLCreateSystemDefaultDevice()), ceiling: 100)
        #expect(budget.reserve("pool", bytes: 80))
        #expect(!budget.reserve("scaler", bytes: 30))
        #expect(budget.reserve("pool", bytes: 60), "replacing a reservation frees the old charge first")
        #expect(budget.reserve("scaler", bytes: 30))
        #expect(budget.reserve("pool", bytes: 500, force: true))
        #expect(budget.totalBytes == 530)
        budget.releaseReservation("pool")
        #expect(budget.totalBytes == 30)
    }

    @Test("ceiling: min(largest 4K set × 1.5, 15 % of RAM, 25 % of the working set) for 8 / 16 / 36 GB")
    func ceilingFormula() {
        let gib: UInt64 = 1 << 30
        // Memory caps alone (no measured set): 15 % of RAM binds on Apple Silicon (working set ≈ 0.66–0.8 × RAM).
        #expect(RenderTargetBudget.ceiling(largestSetBytes: 0, physicalMemory: 8 * gib,
                                           recommendedWorkingSet: 5_726_623_744) == Int(Double(8 * gib) * 0.15))
        #expect(RenderTargetBudget.ceiling(largestSetBytes: 0, physicalMemory: 16 * gib,
                                           recommendedWorkingSet: 12_713_115_648) == Int(Double(16 * gib) * 0.15))
        // A measured set below the caps sets the ceiling at 1.5×.
        #expect(RenderTargetBudget.ceiling(largestSetBytes: 400 << 20, physicalMemory: 36 * gib,
                                           recommendedWorkingSet: 28 * gib) == 600 << 20)
        // A working set unusually small next to RAM binds instead.
        #expect(RenderTargetBudget.ceiling(largestSetBytes: 0, physicalMemory: 16 * gib,
                                           recommendedWorkingSet: 4 * gib) == Int(gib))
    }

    // MARK: Pipeline

    @Test("forced tiny ceiling: the scene's set is refused, nothing partial is left, no crash")
    func tinyCeilingRefusesScene() throws {
        let rig = try Rig()
        rig.budget.ceiling = 1 << 20   // 1 MB: below any 1080p target
        rig.pipeline.setFeedbackParams(FeedbackParams())
        rig.resize(hd)
        try rig.attachMVWarp(size: hd)
        rig.idle()
        #expect(rig.pipeline.feedbackTextures.isEmpty)
        #expect(rig.pipeline.mvWarpState == nil)
        #expect(rig.budget.liveAllocations.isEmpty, "no partial allocation left behind")
        #expect(Set(rig.budget.refusals.map(\.owner)).isSuperset(of: ["feedback", "mvWarp"]))
        #expect(rig.budget.totalBytes == rig.budget.reservedBytes["drawable pool"], "only the (forced) drawable pool")
    }

    @Test("after a scene switch the budget's total equals the live labelled targets + reservations")
    func totalMatchesLiveAfterSwitch() throws {
        let rig = try Rig()
        rig.pipeline.setFeedbackParams(FeedbackParams())
        rig.resize(hd)
        #expect(rig.pipeline.feedbackTextures.count == 2)
        // Switch: feedback scene → staged scene (what applyPreset does).
        rig.pipeline.setFeedbackParams(nil)
        try rig.attachStaged(size: hd)
        rig.idle()
        #expect(rig.chargedEqualsLive)
        #expect(!rig.budget.liveAllocations.contains { $0.owner == "feedback" }, "the old scene's set is released")
        #expect(rig.budget.liveAllocations.contains { $0.owner == "staged" })
    }
}

// MARK: - Resize

@Suite("DrainReleaseAllocate", .serialized)
@MainActor
struct DrainReleaseAllocateTests {

    @Test("a burst of 20 size callbacks inside 100 ms commits one reallocation, at the last size")
    func burstCoalesces() throws {
        let rig = try Rig()
        rig.pipeline.setFeedbackParams(FeedbackParams())
        rig.resize(hd)   // the first size commits at once
        let before = rig.pipeline.resizeReallocationCount
        for i in 0..<20 {
            rig.pipeline.mtkView(rig.view, drawableSizeWillChange: i.isMultiple(of: 2) ? uhd : CGSize(width: 2560, height: 1440))
        }
        let now = CACurrentMediaTime()
        #expect(!rig.pipeline.commitPendingResizeIfStable(now: now + 0.05, view: nil), "not stable yet")
        #expect(rig.pipeline.commitPendingResizeIfStable(now: now + 0.2, view: nil))
        #expect(!rig.pipeline.commitPendingResizeIfStable(now: now + 0.4, view: nil))
        #expect(rig.pipeline.resizeReallocationCount - before == 1)
        #expect(rig.pipeline.feedbackTextures.first?.width == 2560, "the last size wins")
    }

    @Test("50 × 1080p ↔ 4K across feedback, mv_warp, ray-march and staged: back to baseline, peak ≤ 2× the 4K set")
    func toggleFiftyTimes() throws {
        let rig = try Rig()
        let lib = try ShaderLibrary(context: rig.ctx)
        let rayMarch = try RayMarchPipeline(context: rig.ctx, shaderLibrary: lib)
        rig.pipeline.setRayMarchPipeline(rayMarch)
        rig.pipeline.setFeedbackParams(FeedbackParams())
        rig.resize(hd)
        try rig.attachMVWarp(size: hd)
        try rig.attachStaged(size: hd)
        // The ray-march frame path allocates lazily at the size it renders; do what a frame does.
        func frame(_ size: CGSize) {
            rayMarch.ensureAllocated(width: Int(size.width), height: Int(size.height))
            rig.idle()
        }
        frame(hd)
        let baselineMetal = rig.ctx.device.currentAllocatedSize
        let baselineCharged = rig.budget.totalBytes
        rig.resize(uhd)
        frame(uhd)
        let steady4K = rig.budget.totalBytes
        rig.budget.resetPeak()
        var metalPeak = rig.ctx.device.currentAllocatedSize
        for _ in 0..<50 {
            rig.resize(hd)
            frame(hd)
            rig.resize(uhd)
            frame(uhd)
            metalPeak = max(metalPeak, rig.ctx.device.currentAllocatedSize)
        }
        rig.resize(hd)
        frame(hd)
        let drift = abs(rig.ctx.device.currentAllocatedSize - baselineMetal)
        #expect(drift <= 16 << 20, "Metal allocation back at baseline within 16 MB (drift \(drift >> 20) MB)")
        #expect(rig.budget.totalBytes == baselineCharged)
        #expect(rig.budget.peakTotalBytes <= 2 * steady4K,
                "charged peak \(rig.budget.peakTotalBytes >> 20) MB vs 4K set \(steady4K >> 20) MB")
        #expect(metalPeak - baselineMetal <= 2 * (steady4K - baselineCharged) + (16 << 20))
        #expect(rig.chargedEqualsLive)
        #expect(Set(rig.budget.liveAllocations.map(\.owner)) == ["feedback", "mvWarp", "rayMarch", "staged"])
        print("VQ0 toggle: baseline \(baselineMetal >> 20) MB, 4K set \(steady4K >> 20) MB charged, "
              + "charged peak \(rig.budget.peakTotalBytes >> 20) MB, Metal peak \(metalPeak >> 20) MB, drift \(drift >> 20) MB")
    }
}
