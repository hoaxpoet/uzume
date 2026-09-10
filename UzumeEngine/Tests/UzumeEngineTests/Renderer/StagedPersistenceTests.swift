// StagedPersistenceTests — ALFVEN.1 tasks 2, 3 and 8 (D-244).
//
// Dispatch path exercised: `RenderPipeline.encodeOffscreenStages` — the SAME
// method `drawWithStaged` calls for the offscreen half of every staged frame.
// Nothing here re-implements the stage walk, the ping-pong swap or the binding,
// so a green run is evidence about the production encoder rather than about a
// test-local copy of it.
//
// The subject is a synthetic accumulator stage: `out = previous + 1`, reading its
// own previous state at [[texture(20)]]. That single fragment makes all three
// behaviours countable rather than merely plausible:
//
//   • persistence  — frame 2 reads frame 1's output (1 → 2, exactly)
//   • iterations   — `iterations: 8` yields exactly +8 in one frame
//   • composition  — persistent + iterations: 8 yields +16 after two frames
//   • reset        — the pair is zero again after a preset switch
//   • watchdog     — a NaN injected into persistent state is cleared, and the
//                    next frame renders finite

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Shared

private enum PersistenceTestError: Error {
    case shaderCompileFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case stagedTextureMissing
}

/// `out = previous + 1`. Reads the persistent/iteration slot the engine binds
/// (`kStagedPersistentTextureSlot` = 20); if that binding were missing the
/// fragment would read zero every pass and every count below would come out 1.
/// Writes the bound pass index, so a readback proves each iteration of an iterated stage
/// sees a DIFFERENT value. Before ALFVEN.1c every iteration was byte-identical and this
/// would read back 0 on the final pass regardless of the iteration count.
private let kPassIndexShader = """
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

struct StagedPassInfo { int index; int count; };

vertex VOut pass_vertex(uint vid [[vertex_id]]) {
    float2 pts[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VOut o;
    o.position = float4(pts[vid], 0.0, 1.0);
    o.uv = (pts[vid] + 1.0) * 0.5;
    return o;
}

fragment float4 pass_fragment(
    VOut in [[stage_in]],
    constant StagedPassInfo& p [[buffer(9)]]
) {
    return float4(float(p.index), float(p.count), 0.0, 1.0);
}
"""

private let kAccumulatorShader = """
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut accum_vertex(uint vid [[vertex_id]]) {
    float2 pts[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VOut o;
    o.position = float4(pts[vid], 0.0, 1.0);
    o.uv = (pts[vid] + 1.0) * 0.5;
    return o;
}

fragment float4 accum_fragment(
    VOut in [[stage_in]],
    texture2d<float, access::sample> prev [[texture(20)]]
) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float previous = prev.sample(s, in.uv).x;
    return float4(previous + 1.0, 0.0, 0.0, 1.0);
}
"""

@Suite("Staged persistence + iteration (ALFVEN.1)")
struct StagedPersistenceTests {

    private static let size = CGSize(width: 16, height: 16)

    /// `swift test` is a Debug build unless `-c release` is passed; performance
    /// numbers are meaningless without saying which (CLAUDE.md §Build & Test).
    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: Helpers

    private func makePipeline(_ context: MetalContext) throws -> RenderPipeline {
        let library = try ShaderLibrary(context: context)
        let stride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * stride),
              let wave = context.makeSharedBuffer(length: 2048 * stride) else {
            throw PersistenceTestError.bufferAllocationFailed
        }
        return try RenderPipeline(context: context, shaderLibrary: library,
                                  fftBuffer: fft, waveformBuffer: wave)
    }

    private func makeAccumulatorStage(
        _ context: MetalContext, persistent: Bool, iterations: Int
    ) throws -> StagedStageSpec {
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        guard let library = try? context.device.makeLibrary(source: kAccumulatorShader, options: options),
              let vfn = library.makeFunction(name: "accum_vertex"),
              let ffn = library.makeFunction(name: "accum_fragment") else {
            throw PersistenceTestError.shaderCompileFailed
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        return StagedStageSpec(
            name: "accum",
            pipelineState: try context.device.makeRenderPipelineState(descriptor: descriptor),
            samples: [],
            writesToDrawable: false,
            persistent: persistent,
            iterations: iterations,
            pixelFormat: .rgba32Float
        )
    }

    /// Drive one frame through the production offscreen stage walk.
    private func renderFrame(_ context: MetalContext, _ pipeline: RenderPipeline) throws {
        guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
            throw PersistenceTestError.commandBufferFailed
        }
        var features = FeatureVector()
        pipeline.encodeOffscreenStages(commandBuffer: commandBuffer,
                                       features: &features,
                                       stemFeatures: .zero)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    /// Red channel of texel (0,0) of the stage's current front texture.
    private func readRed(_ pipeline: RenderPipeline, stage: String) throws -> Float {
        guard let texture = pipeline.stagedTexture(named: stage) else {
            throw PersistenceTestError.stagedTextureMissing
        }
        var pixel = [Float](repeating: .nan, count: 4)
        pixel.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: 4 * 4,
                             from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                             size: MTLSize(width: 1, height: 1, depth: 1)),
                             mipmapLevel: 0)
        }
        return pixel[0]
    }

    // MARK: Task 2 — persistence across frames

    @Test("frame 2 of a persistent stage reads frame 1's output")
    func persistentStageCarriesStateAcrossFrames() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stage = try makeAccumulatorStage(ctx, persistent: true, iterations: 1)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)

        #expect(try readRed(pipeline, stage: "accum") == 0.0,
                "a freshly allocated persistent pair must be zeroed")

        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "accum") == 1.0, "frame 1 must write 0 + 1")

        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "accum") == 2.0,
                "frame 2 must read frame 1's output (1) and write 2 — state did not survive")
    }

    @Test("a non-persistent stage restarts from zero every frame")
    func nonPersistentStageDoesNotAccumulate() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stage = try makeAccumulatorStage(ctx, persistent: false, iterations: 1)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)

        try renderFrame(ctx, pipeline)
        try renderFrame(ctx, pipeline)
        // No pair, no slot-20 binding: the fragment reads Metal's zero and writes 1.
        #expect(try readRed(pipeline, stage: "accum") == 1.0,
                "a plain stage must not acquire persistence")
    }

    @Test("a preset switch zeroes the persistent pair")
    func presetSwitchZeroesPersistentState() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stage = try makeAccumulatorStage(ctx, persistent: true, iterations: 1)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)
        for _ in 0..<5 { try renderFrame(ctx, pipeline) }
        #expect(try readRed(pipeline, stage: "accum") == 5.0)

        // Preset switch: clear, then install the same runtime again.
        pipeline.setStagedRuntime(nil, drawableSize: Self.size)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)
        #expect(try readRed(pipeline, stage: "accum") == 0.0,
                "persistent state leaked across a preset switch")

        // …and the explicit reset seam does the same without a switch.
        try renderFrame(ctx, pipeline)
        pipeline.resetStagedPersistentState()
        #expect(try readRed(pipeline, stage: "accum") == 0.0,
                "resetStagedPersistentState() did not zero the pair")
    }

    // MARK: Task 3 — iterations

    @Test("iterations: 8 runs exactly 8 passes in one frame")
    func iteratedStageRunsNTimesPerFrame() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stage = try makeAccumulatorStage(ctx, persistent: false, iterations: 8)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)

        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "accum") == 8.0,
                "one frame at iterations: 8 must accumulate exactly +8")
    }

    @Test("persistent + iterations: 8 reaches +16 after two frames")
    func iteratedPersistentStageComposes() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stage = try makeAccumulatorStage(ctx, persistent: true, iterations: 8)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)

        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "accum") == 8.0)
        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "accum") == 16.0,
                "iteration 1 of frame 2 must warm-start from frame 1's state")
    }

    // MARK: ALFVEN.1c — per-pass index

    @Test("each iteration of an iterated stage sees its own pass index")
    func iteratedStageSeesPassIndex() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)

        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        guard let library = try? ctx.device.makeLibrary(source: kPassIndexShader, options: options),
              let vfn = library.makeFunction(name: "pass_vertex"),
              let ffn = library.makeFunction(name: "pass_fragment") else {
            throw PersistenceTestError.shaderCompileFailed
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let stage = StagedStageSpec(
            name: "passidx",
            pipelineState: try ctx.device.makeRenderPipelineState(descriptor: descriptor),
            samples: [], writesToDrawable: false,
            persistent: false, iterations: 6, pixelFormat: .rgba32Float)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)
        try renderFrame(ctx, pipeline)

        // The front texture holds the LAST pass, so index must be iterations - 1.
        #expect(try readRed(pipeline, stage: "passidx") == 5.0, """
            the final pass of a 6-iteration stage did not see index 5 — every iteration is \
            still byte-identical, and no per-pass algorithm (FFT butterfly, multigrid \
            level, jump flood step) is authorable
            """)
    }

    @Test("a non-iterated stage sees pass (0, 1)")
    func singleShotStageSeesZeroIndex() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        guard let library = try? ctx.device.makeLibrary(source: kPassIndexShader, options: options),
              let vfn = library.makeFunction(name: "pass_vertex"),
              let ffn = library.makeFunction(name: "pass_fragment") else {
            throw PersistenceTestError.shaderCompileFailed
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        let stage = StagedStageSpec(
            name: "single",
            pipelineState: try ctx.device.makeRenderPipelineState(descriptor: descriptor),
            samples: [], writesToDrawable: false, pixelFormat: .rgba32Float)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)
        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "single") == 0.0)
    }

    // MARK: Task 8 — non-finite watchdog

    @Test("a NaN injected into persistent state is cleared and the next frame is finite")
    func watchdogRecoversFromNonFiniteState() throws {
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stage = try makeAccumulatorStage(ctx, persistent: true, iterations: 1)
        pipeline.setStagedRuntime([stage], drawableSize: Self.size)
        try renderFrame(ctx, pipeline)
        #expect(try readRed(pipeline, stage: "accum") == 1.0)

        // Inject a NaN across the whole field, the way a real blow-up arrives —
        // the Laplacian smears a single bad texel over the field within a frame,
        // so the sparse row probe is a sound detector for the real failure shape.
        guard let texture = pipeline.stagedTexture(named: "accum") else {
            throw PersistenceTestError.stagedTextureMissing
        }
        let width = texture.width, height = texture.height
        let poison = [Float](repeating: .nan, count: width * height * 4)
        poison.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                              size: MTLSize(width: width, height: height, depth: 1)),
                            mipmapLevel: 0, withBytes: base, bytesPerRow: width * 16)
        }
        #expect(try readRed(pipeline, stage: "accum").isNaN, "injection did not take")

        // The production frame walk probes before it encodes, so one frame is
        // enough: the pair is re-zeroed and the accumulator restarts from 0 + 1.
        try renderFrame(ctx, pipeline)
        let after = try readRed(pipeline, stage: "accum")
        #expect(after.isFinite, "watchdog did not recover — state is still non-finite")
        #expect(after == 1.0, "watchdog must re-zero the pair, not merely mask the NaN")
        #expect(pipeline.stagedWatchdogTripCount == 1, "the trip was not recorded")
    }

    @Test("the watchdog probe's cost is set by the block, not by the texture")
    func watchdogProbeCostIsMeasured() throws {
        let ctx = try MetalContext()

        // WHAT THIS ASSERTS, AND WHY IT IS A RATIO. The probe must stay O(block), never
        // O(texture) — the defect it guards is the probe growing back into a full-texture
        // readback. An earlier version asserted an absolute wall-clock ceiling (400 µs
        // Debug / 5 µs Release). That measures the MACHINE as much as the code: it passed
        // 3/3 in isolation and failed at 402 µs and then 508 µs inside the full suite,
        // where swift-testing runs suites in parallel and the box is loaded. Widening the
        // budget would only have moved the tripwire (deterministic tests over
        // budget-widening). Scaling the drawable 4x in AREA and comparing the two costs
        // measured in the SAME run divides the machine out: a block probe stays flat, a
        // full-texture readback grows with the area.
        func probeCost(width: Int, height: Int) throws -> Double {
            let pipeline = try makePipeline(ctx)
            let stage = try makeAccumulatorStage(ctx, persistent: true, iterations: 1)
            pipeline.setStagedRuntime([stage],
                                      drawableSize: CGSize(width: width, height: height))
            try renderFrame(ctx, pipeline)
            for _ in 0..<200 { pipeline.probeStagedPersistentState() }   // warm

            let iterations = 2000
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<iterations { pipeline.probeStagedPersistentState() }
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            #expect(pipeline.stagedWatchdogTripCount == 0,
                    "clean state must not trip the watchdog")
            return Double(elapsed) / Double(iterations) / 1000.0
        }

        let hd = try probeCost(width: 1920, height: 1080)
        let uhd = try probeCost(width: 3840, height: 2160)   // 4x the texels
        let growth = uhd / max(hd, 1e-9)

        let edge = RenderPipeline.stagedProbeBlockEdge
        print(String(format: "[alfven.1] watchdog probe: %.2f µs at 1920×1080, %.2f µs at "
                             + "3840×2160 (4x area) — growth %.2fx, one %d×%d block, %d bytes "
                             + "— BUILD: %@",
                     hd, uhd, growth, edge, edge, edge * edge * 16,
                     Self.isDebugBuild ? "Debug/-Onone" : "Release"))

        // A full-texture readback would grow ~4x with the area. A block probe is flat.
        // 2.0 sits clear of both, so this fails on the regression and not on load.
        #expect(growth < 2.0,
                """
                watchdog probe cost grew \(growth)x when the drawable area grew 4x \
                (\(hd) µs -> \(uhd) µs): the probe is scaling with the TEXTURE, not with \
                its fixed \(edge)×\(edge) block
                """)
    }
}
