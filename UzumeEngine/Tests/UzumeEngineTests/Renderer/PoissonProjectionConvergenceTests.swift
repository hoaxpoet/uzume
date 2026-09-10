// PoissonProjectionConvergenceTests — ALFVEN.1 task 6 (D-244). THE gate.
//
// Everything else in ALFVEN.1 proves that stages persist and iterate. This proves
// the thing they were built to carry actually SOLVES: the ported Jacobi pressure
// fragment, driven through the production staged encoder, converges to the known
// solution of ∇²p = f.
//
// Analytic problem (doubly periodic, one full period across the grid):
//     f = -2 sin(x) sin(y)   ⇒   p = sin(x) sin(y)   exactly.
//
// Discretisation. The ported reference stencil (WebGL-Fluid-Simulation, MIT) is
// `p = (L + R + B + T - divergence) * 0.25`, i.e. it solves
// `L + R + T + B - 4C = divergence` — the 5-point Laplacian in units where the
// grid spacing is ONE TEXEL. So the sampled RHS is h²·f with h = 2π/N, which is
// what the `analytic_rhs_fragment` below writes. Nothing about the solver was
// tuned to make this pass; the RHS was scaled to the convention the reference
// already had.
//
// Dispatch path: `RenderPipeline.encodeOffscreenStages` — the production stage
// walk `drawWithStaged` uses — driving the REAL `poisson_sandbox_pressure_fragment`
// pipeline compiled by `PresetLoader` from the shipping `PoissonSandbox` sidecar.
// The only synthetic part is the RHS stage feeding it.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

private enum PoissonTestError: Error {
    case noMetalDevice
    case presetNotFound
    case pressureStageNotFound
    case shaderCompileFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case textureMissing
}

@Suite("Poisson projection convergence (ALFVEN.1)")
struct PoissonProjectionConvergenceTests {

    /// Grid edge. One full period of sin(x)sin(y) spans the texture.
    private static let n = 64

    // MARK: Measured convergence — FROZEN, not chosen
    //
    // Max relative error |p_numeric − p_analytic|∞ / |p_analytic|∞, cold start
    // (pressure zeroed), single frame, measured 2026-09-08 on Apple Silicon at
    // N = 64, Debug build:
    //
    //      4 sweeps   0.98086      (closed-form Jacobi theory: 0.98086)
    //      8 sweeps   0.96209
    //     16 sweeps   0.92562
    //     24 sweeps   0.89052      (closed-form Jacobi theory: 0.89052)
    //
    // These are NOT small, and that is the honest result rather than a defect:
    // Jacobi's error is damped by cos(h) per sweep for the domain-scale mode, so
    // at h = 2π/64 it removes only ~0.5 % of that mode per sweep. 24 sweeps is a
    // partial solve BY CONSTRUCTION — which is exactly why the pressure stage is
    // `persistent`. See `warmStartConverges` below for the number that governs
    // what actually reaches the screen. The measured values agree with the
    // closed-form Jacobi prediction for this stencil to five decimal places
    // (`matchesJacobiTheory`), so these are not "whatever came out" — they are the
    // right answer for 24 sweeps of Jacobi at this resolution. They are frozen at
    // the measured values with a small float-noise margin; the solver was not
    // touched to meet them.
    private static let frozenErrors: [Int: Double] = [
        4: 0.98086, 8: 0.96209, 16: 0.92562, 24: 0.89052,
    ]
    private static let frozenTolerance = 0.002

    // MARK: Fixtures

    /// Analytic RHS h²·f. Uses the same vertex body as the shared
    /// `fullscreen_vertex` so its uv→row mapping matches the ported stage's.
    private static func rhsShaderSource(n: Int) -> String {
        """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 position [[position]]; float2 uv; };
        vertex VOut rhs_vertex(uint vid [[vertex_id]]) {
            VOut o;
            o.uv = float2((vid << 1) & 2, vid & 2);
            o.position = float4(o.uv * 2.0 - 1.0, 0.0, 1.0);
            o.uv.y = 1.0 - o.uv.y;
            return o;
        }
        fragment float4 rhs_fragment(VOut in [[stage_in]]) {
            constexpr float kTau = 6.28318530718;
            float h = kTau / float(\(n));
            float x = kTau * in.uv.x;
            float y = kTau * in.uv.y;
            return float4(h * h * (-2.0 * sin(x) * sin(y)), 0.0, 0.0, 1.0);
        }
        """
    }

    private func makePipeline(_ context: MetalContext) throws -> RenderPipeline {
        let library = try ShaderLibrary(context: context)
        let stride = MemoryLayout<Float>.stride
        guard let fft = context.makeSharedBuffer(length: 512 * stride),
              let wave = context.makeSharedBuffer(length: 2048 * stride) else {
            throw PoissonTestError.bufferAllocationFailed
        }
        return try RenderPipeline(context: context, shaderLibrary: library,
                                  fftBuffer: fft, waveformBuffer: wave)
    }

    private func makeRHSStage(_ context: MetalContext) throws -> StagedStageSpec {
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        guard let library = try? context.device.makeLibrary(
                source: Self.rhsShaderSource(n: Self.n), options: options),
              let vfn = library.makeFunction(name: "rhs_vertex"),
              let ffn = library.makeFunction(name: "rhs_fragment") else {
            throw PoissonTestError.shaderCompileFailed
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn
        descriptor.colorAttachments[0].pixelFormat = .rgba32Float
        return StagedStageSpec(
            name: "divergence",
            pipelineState: try context.device.makeRenderPipelineState(descriptor: descriptor),
            samples: [],
            writesToDrawable: false,
            pixelFormat: .rgba32Float)
    }

    /// The REAL shipping pressure stage, with `iterations` overridden per sweep.
    private func makePressureStage(_ context: MetalContext, iterations: Int) throws -> StagedStageSpec {
        let loader = PresetLoader(device: context.device, pixelFormat: context.pixelFormat)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Poisson Sandbox" }) else {
            throw PoissonTestError.presetNotFound
        }
        guard let stage = preset.stages.first(where: { $0.name == "pressure" }) else {
            throw PoissonTestError.pressureStageNotFound
        }
        #expect(stage.persistent, "the shipping pressure stage must be persistent")
        #expect(stage.pixelFormat == .rgba32Float, "the pressure solve must run at 32-bit float")
        #expect(stage.iterations == 24, "the shipping sidecar must declare 24 sweeps")
        return StagedStageSpec(
            name: stage.name, pipelineState: stage.pipelineState, samples: stage.samples,
            writesToDrawable: false, persistent: true, iterations: iterations,
            pixelFormat: stage.pixelFormat)
    }

    /// Analytic p = sin(x)sin(y) sampled at texel centres, row-major (row 0 = top,
    /// matching `fullscreen_vertex`'s uv.y = (row + 0.5) / N).
    private static func analyticField() -> [Double] {
        let tau: Double = 2.0 * Double.pi
        let edge: Double = Double(n)
        var field: [Double] = []
        field.reserveCapacity(n * n)
        for row in 0..<n {
            let y: Double = tau * (Double(row) + 0.5) / edge
            for col in 0..<n {
                let x: Double = tau * (Double(col) + 0.5) / edge
                field.append(sin(x) * sin(y))
            }
        }
        return field
    }

    private func readPressure(_ pipeline: RenderPipeline) throws -> [Double] {
        guard let texture = pipeline.stagedTexture(named: "pressure") else {
            throw PoissonTestError.textureMissing
        }
        var raw = [Float](repeating: 0, count: Self.n * Self.n * 4)
        raw.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.getBytes(base, bytesPerRow: Self.n * 16,
                             from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                             size: MTLSize(width: Self.n, height: Self.n, depth: 1)),
                             mipmapLevel: 0)
        }
        return (0..<(Self.n * Self.n)).map { Double(raw[$0 * 4]) }
    }

    /// Max relative error against the analytic field.
    private static func maxRelativeError(_ numeric: [Double], _ analytic: [Double]) -> Double {
        let scale = analytic.map(abs).max() ?? 1.0
        return zip(numeric, analytic).map { abs($0 - $1) }.max().map { $0 / scale } ?? .infinity
    }

    private func renderFrames(_ context: MetalContext, _ pipeline: RenderPipeline, count: Int) throws {
        for _ in 0..<count {
            guard let commandBuffer = context.commandQueue.makeCommandBuffer() else {
                throw PoissonTestError.commandBufferFailed
            }
            var features = FeatureVector()
            pipeline.encodeOffscreenStages(commandBuffer: commandBuffer, features: &features,
                                           stemFeatures: .zero)
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
        }
    }

    /// Cold-start error after `iterations` Jacobi sweeps in a single frame.
    private func coldStartError(_ context: MetalContext, iterations: Int) throws -> Double {
        let pipeline = try makePipeline(context)
        let stages = [try makeRHSStage(context), try makePressureStage(context, iterations: iterations)]
        // Re-installing the runtime zeroes the persistent pair — a true cold start.
        pipeline.setStagedRuntime(stages, drawableSize: CGSize(width: Self.n, height: Self.n))
        try renderFrames(context, pipeline, count: 1)
        return Self.maxRelativeError(try readPressure(pipeline), Self.analyticField())
    }

    // MARK: Tests

    @Test("cold-start error strictly decreases with sweep count and holds the frozen bound")
    func convergesAgainstAnalyticSolution() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw PoissonTestError.noMetalDevice }
        let ctx = try MetalContext()
        let counts = [4, 8, 16, 24]

        var measured: [Int: Double] = [:]
        for count in counts {
            measured[count] = try coldStartError(ctx, iterations: count)
        }
        print("[alfven.1] Poisson cold-start max relative error, N=\(Self.n), one frame:")
        for count in counts {
            print(String(format: "[alfven.1]   %2d sweeps  %.5f  (frozen %.5f)",
                         count, measured[count] ?? .nan, Self.frozenErrors[count] ?? .nan))
        }

        for count in counts {
            guard let value = measured[count], let frozen = Self.frozenErrors[count] else {
                Issue.record("no measurement for \(count) sweeps"); continue
            }
            #expect(value.isFinite, "\(count) sweeps produced a non-finite field")
            #expect(value <= frozen + Self.frozenTolerance, """
                \(count) sweeps: max relative error \(value) exceeds the frozen \
                \(frozen). Do NOT raise the threshold — a residual that has stopped \
                falling is a finding about the solver (ALFVEN.1 task 6).
                """)
        }

        // Strict monotone decrease — a wrong stencil, a dropped iteration or a
        // mis-bound previous-state slot all break this before they break a bound.
        for (lower, higher) in zip(counts, counts.dropFirst()) {
            guard let a = measured[lower], let b = measured[higher] else { continue }
            #expect(b < a, "error did not decrease from \(lower) to \(higher) sweeps: \(a) → \(b)")
        }
    }

    @Test("cold-start error matches the closed-form Jacobi prediction for this stencil")
    func matchesJacobiTheory() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw PoissonTestError.noMetalDevice }
        let ctx = try MetalContext()

        // For the single mode (kx, ky) = (1, 1) the 5-point Jacobi iteration matrix
        // has eigenvalue cos(h), and the discrete solution is the continuum one
        // scaled by h² / (2(1 − cos h)). Starting from p = 0 the error after n
        // sweeps is therefore exactly predictable — the sharpest available check
        // that the PORTED stencil is the stencil we think it is.
        let h = 2.0 * Double.pi / Double(Self.n)
        let lambda = cos(h)
        let discreteScale = h * h / (2.0 * (1.0 - cos(h)))
        let analytic = Self.analyticField()

        for sweeps in [4, 24] {
            let attenuation = discreteScale * (1.0 - pow(lambda, Double(sweeps)))
            let predicted = analytic.map { $0 * attenuation }
            let predictedError = Self.maxRelativeError(predicted, analytic)
            let measuredError = try coldStartError(ctx, iterations: sweeps)
            print(String(format: "[alfven.1] %2d sweeps: measured %.5f  theory %.5f",
                         sweeps, measuredError, predictedError))
            #expect(abs(measuredError - predictedError) < 1e-3, """
                \(sweeps) sweeps: measured \(measuredError) vs Jacobi theory \
                \(predictedError) — the ported stencil is not solving the equation \
                it is documented to solve
                """)
        }
    }

    @Test("the persistent stage warm-starts, so the field converges over frames")
    func warmStartConverges() throws {
        guard MTLCreateSystemDefaultDevice() != nil else { throw PoissonTestError.noMetalDevice }
        let ctx = try MetalContext()
        let pipeline = try makePipeline(ctx)
        let stages = [try makeRHSStage(ctx), try makePressureStage(ctx, iterations: 24)]
        pipeline.setStagedRuntime(stages, drawableSize: CGSize(width: Self.n, height: Self.n))

        let analytic = Self.analyticField()
        var errors: [(Int, Double)] = []
        for frames in [1, 10, 30, 60] {
            try renderFrames(ctx, pipeline, count: frames - (errors.last?.0 ?? 0))
            errors.append((frames, Self.maxRelativeError(try readPressure(pipeline), analytic)))
        }
        print("[alfven.1] Poisson warm-start (24 sweeps/frame, persistent), N=\(Self.n):")
        for (frames, error) in errors {
            print(String(format: "[alfven.1]   after %2d frame(s)  %.6f", frames, error))
        }

        for (a, b) in zip(errors, errors.dropFirst()) {
            #expect(b.1 < a.1, "warm-start error did not fall from frame \(a.0) to \(b.0)")
        }
        // 60 frames is one second of playback. Measured 2026-09-08 at N = 64:
        //   1 frame 0.890525 | 10 frames 0.313419 | 30 frames 0.030171
        //   60 frames 0.000155  ← frozen below with a margin
        #expect(errors.last?.1 ?? .infinity < 0.0005, """
            after 60 warm-started frames the max relative error is \(errors.last?.1 ?? .infinity); \
            the persistent pressure field is not converging across frames
            """)
    }
}
