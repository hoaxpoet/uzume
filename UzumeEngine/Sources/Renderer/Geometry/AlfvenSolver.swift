// AlfvenSolver — Alfvén's 2D MHD solver as a compute pipeline (ALFVEN.4).
//
// WHY THIS EXISTS. ALFVEN.2 built the same physics on the `staged` fragment path and
// measured three limits that are architectural rather than tuning:
//
//   1. SUBSTEPS were impossible. Derivative spectra are computed once per frame upstream
//      in a staged DAG, so substeps 2..N evaluate the Poisson brackets against STALE
//      derivatives — measured as psi 0.90 -> 0.049 while superficially improving omega.
//   2. ADAPTIVE dt was inexpressible. The blow-up is a CFL violation that DEVELOPS as the
//      enstrophy cascade energises the field (u*k_max*dt: 0.10 at omega 1.2, 2.56 at
//      omega 30), and the fix needs dt recomputed from a field-wide reduction over the
//      current state — which a linear DAG cannot feed back into the same frame.
//   3. COST. A 2D FFT as fragment passes is 16 render passes; in threadgroup memory it is
//      2 dispatches.
//
// A Swift-side substep loop with barriers solves all three at once. The pattern follows
// `MitosisGeometry` (D-182 — adapt the template matching the paradigm): Gray-Scott is the
// same shape, an iterative PDE ping-ponged across substeps per frame.
//
// The PHYSICS is ALFVEN.2's and unchanged: spectral Poisson with the corrected sign
// (phi_h = -omega_h/k^2), spectral Poisson brackets, Hou-Li filter, 2/3 dealiasing, and
// the spike's integrating factor with omega alone carrying the drag. That version reached
// psi conserved to 0.06%, J in the right order and total energy conserved; what it could
// not do is keep the timestep inside the CFL limit as the field energised.

import Foundation
import Metal
import simd
import Shared

// MARK: - Configuration

/// Tunables for the solver. Values are the spike's where the spike has one.
public struct AlfvenSolverConfiguration: Sendable {
    /// Grid edge. Must be a power of two (the FFT requires it) and <= 1024 (threadgroup
    /// memory). Fixed rather than drawable-sized: D-244's N^2 finding and the FFT's
    /// power-of-two requirement both point the same way, and it caps cost independently
    /// of display resolution.
    public var edge: Int
    /// Upper bound on the timestep. The CFL reduction lowers it as the field energises;
    /// it never raises it above this.
    public var maxDt: Float
    /// Substeps per frame. Free here — each runs its own full RHS evaluation, so none of
    /// them sees stale derivatives.
    public var substeps: Int
    public var alpha: Float
    /// k^4 hyperdiffusion. DERIVED from the grid rather than copied: the spike's
    /// nu4 = 2.5e-7 is tuned for N = 256, and k^4 damping is violently
    /// resolution-dependent — the same constant at N = 128 gives 17x less dissipation at
    /// the dealias cutoff (13.3/s vs 0.83/s), which is exactly the enstrophy pile-up seen
    /// as omega climbing. What should be held fixed is the dissipation RATE at the cutoff,
    /// so nu4 = C / k_cut^4 with C taken from the spike's own operating point.
    public var nu4: Float
    public var drive: Float
    public var spectralCutoff: Float
    public var clampOmega: Float
    public var clampPsi: Float
    public var seedKOmega: Int
    public var seedKPsi: Int
    public var seedAmpOmega: Float
    public var seedAmpPsi: Float
    /// Seconds per re-seed. §5: a sustained driven MHD state condenses into a static
    /// quilt, so the look is a sequence of transients.
    public var cycleSeconds: Float
    /// Crossfade duration for a re-seed, seconds (the spike's advance_blend tau).
    public var blendTau: Float

    public init(
        edge: Int = 256,
        maxDt: Float = 0.005,          // the spike's own ceiling
        substeps: Int = 4,
        alpha: Float = 0.16,
        nu4: Float? = nil,     // nil => derived from `edge`, see the property comment
        drive: Float = 0.020,
        spectralCutoff: Float = 100.0,
        clampOmega: Float = 200.0,     // a genuine backstop: ~25x the measured equilibrium
        clampPsi: Float = 100.0,
        seedKOmega: Int = 3,
        seedKPsi: Int = 2,
        seedAmpOmega: Float = 1.2,
        seedAmpPsi: Float = 0.9,
        cycleSeconds: Float = 22.0,
        blendTau: Float = 1.1
    ) {
        self.edge = edge
        self.maxDt = maxDt
        self.substeps = substeps
        self.alpha = alpha
        // C = 2.5e-7 * ((2/3)*128)^4 — the spike's dissipation rate at its own cutoff.
        let kCut = (2.0 / 3.0) * (Float(edge) / 2.0)
        self.nu4 = nu4 ?? (13.256 / (kCut * kCut * kCut * kCut))
        self.drive = drive
        self.spectralCutoff = spectralCutoff
        self.clampOmega = clampOmega
        self.clampPsi = clampPsi
        self.seedKOmega = seedKOmega
        self.seedKPsi = seedKPsi
        self.seedAmpOmega = seedAmpOmega
        self.seedAmpPsi = seedAmpPsi
        self.cycleSeconds = cycleSeconds
        self.blendTau = blendTau
    }
}

/// Mirrors `AlfvenDisplayParams` in AlfvenSolver.metal. Layout is the GPU contract.
struct AlfvenDisplayParams {
    var exposure: Float
    var hueCentre: Float
    var pad0: Float
    var pad1: Float
}

/// Mirrors `AlfvenParams` in AlfvenSolver.metal. Layout is the GPU contract.
struct AlfvenParams {
    var dt: Float = 0
    var alpha: Float = 0
    var nu4: Float = 0
    var drive: Float = 0
    var time: Float = 0
    var cutoff: Float = 0
    var clampW: Float = 0
    var clampP: Float = 0
    var gridEdge: UInt32 = 0
    var seedKOmega: UInt32 = 0
    var seedKPsi: UInt32 = 0
    var seedAmpOmega: Float = 0
    var seedAmpPsi: Float = 0
    var seedPhase: Float = 0
    var blendRate: Float = 0
    var pad: Float = 0
}

public enum AlfvenSolverError: Error {
    case functionNotFound(String)
    case allocationFailed
    case edgeNotPowerOfTwo(Int)
}

// MARK: - Solver

/// Owns the MHD state, advances it, and draws it.
///
/// Conforms to `ParticleGeometry` for the same reason `MitosisGeometry` does: the protocol
/// is exactly "compute per frame, then draw into the caller's encoder", which is what a
/// PDE-on-textures preset needs. `activeParticleFraction` is accepted and ignored — the
/// governor's lever here is `substeps`, not a particle count.
public final class AlfvenSolver: ParticleGeometry, @unchecked Sendable {

    /// Accepted for protocol conformance; this solver has no particles. The frame-budget
    /// lever for an MHD field is the substep count, not a dispatch fraction.
    public var activeParticleFraction: Float = 1.0

    /// Fixed exposure standing in for film.py's percentile auto-exposure, which needs a
    /// reduction surface that does not exist yet.
    public var displayExposure: Float = 0.55
    /// Late magenta<->teal end of film.py's palette drift (Matt, 2026-09-09).
    public var displayHueCentre: Float = 0.72

    public private(set) var configuration: AlfvenSolverConfiguration

    /// Current state: `.r = omega`, `.g = psi`, `.b = J`. Sampled by the fragment.
    public var stateTexture: MTLTexture { state[stateIndex] }

    private let device: MTLDevice
    private let logger = Logging.renderer

    var state: [MTLTexture] = []      // ping-pong pair
    var stateIndex = 0
    /// Working textures. Grouped so they are non-optional and allocated together —
    /// implicitly-unwrapped optionals are a lint error and, here, would also hide an
    /// allocation failure until first use.
    struct Fields {
        let scratchA: MTLTexture      // spectra / intermediate complex fields
        let scratchB: MTLTexture
        let scratchC: MTLTexture      // inverse staging, keeps fields.scratchB intact
        let gradPhi: MTLTexture
        let gradOmega: MTLTexture
        let gradPsi: MTLTexture
        let gradJ: MTLTexture
        let nonlinear: MTLTexture
        /// The spectrally filtered state — what each step advances FROM.
        let filtered: MTLTexture
    }
    var fields: Fields

    let fftRows: MTLComputePipelineState
    let fftCols: MTLComputePipelineState
    private let seedPSO: MTLComputePipelineState
    let filterPSO: MTLComputePipelineState
    let gradPSO: MTLComputePipelineState
    let bracketPSO: MTLComputePipelineState
    let dealiasPSO: MTLComputePipelineState
    let integratePSO: MTLComputePipelineState
    let cflReducePSO: MTLComputePipelineState
    let cflFinishPSO: MTLComputePipelineState

    let dtBuffer: MTLBuffer
    let cflScratch: MTLBuffer
    private let displayPipeline: MTLRenderPipelineState?

    /// Cycle index at the last step, so a re-seed is detected rather than recomputed.
    private var lastCycle: Int = -1

    public init(device: MTLDevice, library: MTLLibrary,
                pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: AlfvenSolverConfiguration = .init()) throws {
        guard configuration.edge > 0, configuration.edge & (configuration.edge - 1) == 0,
              configuration.edge <= 1024 else {
            throw AlfvenSolverError.edgeNotPowerOfTwo(configuration.edge)
        }
        self.device = device
        self.configuration = configuration

        func pso(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else {
                throw AlfvenSolverError.functionNotFound(name)
            }
            return try device.makeComputePipelineState(function: fn)
        }
        fftRows      = try pso("alfven_fft_rows")
        fftCols      = try pso("alfven_fft_cols")
        seedPSO      = try pso("alfven_seed_state")
        filterPSO    = try pso("alfven_spectral_filter")
        gradPSO      = try pso("alfven_grad_spectrum")
        bracketPSO   = try pso("alfven_brackets")
        dealiasPSO   = try pso("alfven_dealias")
        integratePSO = try pso("alfven_integrate")
        cflReducePSO = try pso("alfven_cfl_reduce")
        cflFinishPSO = try pso("alfven_cfl_finish")

        guard let dtBuf = device.makeBuffer(length: MemoryLayout<Float>.size,
                                            options: .storageModeShared),
              let cfl = device.makeBuffer(length: MemoryLayout<UInt32>.size,
                                          options: .storageModeShared) else {
            throw AlfvenSolverError.allocationFailed
        }
        dtBuffer = dtBuf
        cflScratch = cfl

        (state, fields) = try Self.allocateTextures(device: device, edge: configuration.edge)

        // Display pipeline. Optional so a solver can be constructed headlessly for tests
        // on a library without the display functions.
        if let vfn = library.makeFunction(name: "alfven_display_vertex"),
           let ffn = library.makeFunction(name: "alfven_display_fragment") {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            displayPipeline = try? device.makeRenderPipelineState(descriptor: desc)
        } else {
            displayPipeline = nil
        }
        logger.info("""
            AlfvenSolver: \(configuration.edge)² compute solver, \
            \(configuration.substeps) substeps/frame, adaptive dt <= \(configuration.maxDt)
            """)
    }

    private static func allocateTextures(device: MTLDevice, edge: Int) throws
        -> ([MTLTexture], Fields) {
        func make() throws -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: edge, height: edge, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared   // read back by tests; UMA, so no copy cost
            guard let tex = device.makeTexture(descriptor: desc) else {
                throw AlfvenSolverError.allocationFailed
            }
            return tex
        }
        let pair = [try make(), try make()]
        let fields = Fields(
            scratchA: try make(),
            scratchB: try make(),
            scratchC: try make(),
            gradPhi: try make(),
            gradOmega: try make(),
            gradPsi: try make(),
            gradJ: try make(),
            nonlinear: try make(),
            filtered: try make())
        return (pair, fields)
    }

    // MARK: Stepping

    /// `ParticleGeometry` entry point. Audio is NOT read here — routing is ALFVEN.3 — so
    /// the field advances on wall-clock time only, which is also what keeps the re-seed
    /// cycle on the listener's clock rather than the simulation's.
    public func update(features: FeatureVector, stemFeatures: StemFeatures,
                       commandBuffer: MTLCommandBuffer) {
        update(time: features.time, commandBuffer: commandBuffer)
    }

    /// Draw the current field. `J` is what the fragment colours (§4); omega and psi are
    /// state and supply nothing visual on their own.
    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let displayPipeline else { return }
        var params = AlfvenDisplayParams(exposure: displayExposure,
                                         hueCentre: displayHueCentre,
                                         pad0: 0,
                                         pad1: 0)
        encoder.setRenderPipelineState(displayPipeline)
        encoder.setFragmentBytes(&params,
                                 length: MemoryLayout<AlfvenDisplayParams>.stride,
                                 index: 0)
        encoder.setFragmentTexture(stateTexture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Advance the field by one frame: `substeps` explicit steps, each with its own full
    /// RHS evaluation and its own CFL-adapted timestep.
    ///
    /// Encodes into `commandBuffer`; the caller commits. Nothing here reads back, so the
    /// adaptive timestep costs no stall — the reduction writes `dtBuffer` on the GPU and
    /// the integrate kernel reads it there.
    public func update(time: Float, commandBuffer: MTLCommandBuffer) {
        var params = makeParams(time: time)

        // Re-seed on a cycle boundary (§5): the look is a sequence of transients, because
        // a sustained driven 2D MHD state condenses to a static quilt.
        let cycle = Int(floor(time / configuration.cycleSeconds))
        if cycle != lastCycle {
            lastCycle = cycle
            params.seedPhase = 7.31 * Float(cycle) + 1.7
            if cycle == 0 { encodeSeed(&params, into: commandBuffer) }
        }

        for _ in 0..<configuration.substeps {
            encodeSubstep(&params, into: commandBuffer)
        }
    }

    /// Force a fresh seed — first frame, or recovery after a non-finite blow-up.
    public func reseed(time: Float, commandBuffer: MTLCommandBuffer) {
        var params = makeParams(time: time)
        params.seedPhase = 7.31 * floor(time / configuration.cycleSeconds) + 1.7
        encodeSeed(&params, into: commandBuffer)
    }

    private func makeParams(time: Float) -> AlfvenParams {
        let cfg = configuration
        // Per-substep share of the re-seed crossfade, raised cosine (the spike's
        // advance_blend). Zero outside the blend window.
        let cycleStart = floor(time / cfg.cycleSeconds) * cfg.cycleSeconds
        let blendPhase = min(max((time - cycleStart) / cfg.blendTau, 0), 1)
        let blendRate: Float = blendPhase < 1
            ? (0.5 - 0.5 * cos(.pi * blendPhase)) * (cfg.maxDt / cfg.blendTau) * .pi
            : 0
        return AlfvenParams(
            dt: cfg.maxDt,
            alpha: cfg.alpha,
            nu4: cfg.nu4,
            drive: cfg.drive,
            time: time,
            cutoff: cfg.spectralCutoff,
            clampW: cfg.clampOmega,
            clampP: cfg.clampPsi,
            gridEdge: UInt32(cfg.edge),
            seedKOmega: UInt32(cfg.seedKOmega),
            seedKPsi: UInt32(cfg.seedKPsi),
            seedAmpOmega: cfg.seedAmpOmega,
            seedAmpPsi: cfg.seedAmpPsi,
            seedPhase: 7.31 * floor(time / cfg.cycleSeconds) + 1.7,
            blendRate: blendRate)
    }

    func grid() -> (MTLSize, MTLSize) {
        let edge = configuration.edge
        return (MTLSize(width: edge, height: edge, depth: 1),
                MTLSize(width: 16, height: 16, depth: 1))
    }

    func encodeSeed(_ params: inout AlfvenParams, into cmd: MTLCommandBuffer) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        let (gridSize, tgSize) = grid()
        enc.setComputePipelineState(seedPSO)
        enc.setTexture(state[stateIndex], index: 0)
        enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
        enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        enc.endEncoding()
    }

    /// The timestep the CFL reduction chose on the last substep. Diagnostics only.
    public var lastAdaptiveDt: Float {
        dtBuffer.contents().assumingMemoryBound(to: Float.self).pointee
    }
}
