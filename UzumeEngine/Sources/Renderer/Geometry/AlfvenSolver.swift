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
    /// Band limit for the DISPLAY quantity J; see `alfven_j_spectrum`.
    var jCutoff: Float = 0
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

    public private(set) var configuration: AlfvenSolverConfiguration

    /// Current state: `.r = omega`, `.g = psi`, `.b = J`. Sampled by the fragment.
    public var stateTexture: MTLTexture { state[stateIndex] }

    private let device: MTLDevice
    private let logger = Logging.renderer

    var state: [MTLTexture] = []      // ping-pong pair
    var stateIndex = 0
    var fields: Fields

    let fftRows: MTLComputePipelineState
    let fftCols: MTLComputePipelineState
    private let seedPSO: MTLComputePipelineState
    let efactorPSO: MTLComputePipelineState
    let houliPSO: MTLComputePipelineState
    let gradPSO: MTLComputePipelineState
    let bracketPSO: MTLComputePipelineState
    let dealiasPSO: MTLComputePipelineState
    let accumulatePSO: MTLComputePipelineState
    let finalizePSO: MTLComputePipelineState
    let cflReducePSO: MTLComputePipelineState
    let cflFinishPSO: MTLComputePipelineState
    let jSpectrumPSO: MTLComputePipelineState
    let bloomCorePSO: MTLComputePipelineState
    let blurPSO: MTLComputePipelineState

    let dtBuffer: MTLBuffer
    let cflScratch: MTLBuffer
    let displayPipeline: MTLRenderPipelineState?

    /// Cycle index at the last step, so a re-seed is detected rather than recomputed.
    private var lastCycle: Int = -1

    /// Accumulated SIMULATION time — the clock the field actually evolves on.
    ///
    /// The re-seed cycle, its crossfade and the forcing phase were all driven off the
    /// caller's REAL time (`frame / 60`), while everything they control evolves in sim
    /// time, which advances by `substeps * dt` with `dt` set by the CFL — i.e. by the
    /// field's own energy. The two ran ~4.4x apart here (f300 = 5.0 real s but t = 2.75
    /// sim s) and the ratio is not even constant. Same class as BUG-097: a render-clock
    /// duration used for something that lives on another clock. Reading the PREVIOUS
    /// frame's dt keeps this stall-free — the reduction writes `dtBuffer` on the GPU.
    public private(set) var simClock: Float = 0

    /// ALFVEN.3 audio envelopes (see AlfvenSolver+Audio). Real-time smoothed, per §7's
    /// timescales; zero at silence, which is the state the preset relaxes to (D-037).
    var bassEnvelope: Float = 0
    var trebleEnvelope: Float = 0
    var centroidEnvelope: Float = 0
    private var lastFeatureTime: Float = 0

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
        efactorPSO   = try pso("alfven_efactor")
        houliPSO     = try pso("alfven_houli")
        gradPSO      = try pso("alfven_grad_spectrum")
        bracketPSO   = try pso("alfven_brackets")
        dealiasPSO   = try pso("alfven_dealias")
        accumulatePSO = try pso("alfven_accumulate")
        finalizePSO  = try pso("alfven_finalize")
        cflReducePSO = try pso("alfven_cfl_reduce")
        cflFinishPSO = try pso("alfven_cfl_finish")
        jSpectrumPSO = try pso("alfven_j_spectrum")
        bloomCorePSO = try pso("alfven_bloom_core")
        blurPSO      = try pso("alfven_blur")

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
            filtered: try make(),
            jField: try make(),
            k1: try make(),
            rk: try make(),
            bloomCore: try make(),
            bloomTmp: try make(),
            bloomNear: try make(),
            bloomFar: try make())
        return (pair, fields)
    }

    // MARK: Stepping

    /// `ParticleGeometry` entry point. Audio is NOT read here — routing is ALFVEN.3.
    ///
    /// `features.time` is accepted and ignored: since ALFVEN.4c the field, the re-seed
    /// cycle, its crossfade and the forcing phase all run off `simClock` (accumulated
    /// substeps*dt), NOT off the caller's clock. An earlier version of this comment
    /// claimed the opposite — that the cycle stayed "on the listener's clock rather than
    /// the simulation's" — which is exactly the bug 4c fixed.
    public func update(features: FeatureVector, stemFeatures: StemFeatures,
                       commandBuffer: MTLCommandBuffer) {
        let dt = features.deltaTime > 0
            ? features.deltaTime
            : max(features.time - lastFeatureTime, 1.0 / 60.0)
        lastFeatureTime = features.time
        advanceAudio(features, dt: dt)
        update(time: features.time, commandBuffer: commandBuffer)
    }

    /// Advance the field by one frame: `substeps` explicit steps, each with its own full
    /// RHS evaluation and its own CFL-adapted timestep.
    ///
    /// Encodes into `commandBuffer`; the caller commits. Nothing here reads back, so the
    /// adaptive timestep costs no stall — the reduction writes `dtBuffer` on the GPU and
    /// the integrate kernel reads it there.
    public func update(time: Float, commandBuffer: MTLCommandBuffer) {
        // `time` is deliberately unused for anything the FIELD sees; see `simClock`.
        _ = time
        if lastCycle >= 0 { simClock += Float(configuration.substeps) * lastAdaptiveDt }
        var params = makeParams(time: simClock)

        // Re-seed on a cycle boundary (§5): the look is a sequence of transients, because
        // a sustained driven 2D MHD state condenses to a static quilt. Measured brightness
        // across one transient (drive 0, N=256, film.py's own mapping): meanLum 0.33 at
        // t = 0.35-1.31, collapsing to 0.13 by t = 2.75 and recovering only to 0.19 by
        // t = 5.5. The reference look — REF 01 meanLum 0.283, REF 05 (silence) 0.422 — is
        // the FIRST ~1.5 sim seconds after a re-seed, so the cycle length is what decides
        // whether the preset lives in that window or in the trough.
        let cycle = Int(floor(simClock / configuration.cycleSeconds))
        if cycle != lastCycle {
            lastCycle = cycle
            params.seedPhase = 7.31 * Float(cycle) + 1.7
            if cycle == 0 { encodeSeed(&params, into: commandBuffer) }
        }

        for _ in 0..<configuration.substeps {
            encodeSubstep(&params, into: commandBuffer)
        }
        encodeBloom(&params, into: commandBuffer)
    }

    /// Force a fresh seed — first frame, or recovery after a non-finite blow-up.
    public func reseed(time: Float, commandBuffer: MTLCommandBuffer) {
        _ = time
        simClock = 0
        lastCycle = 0
        var params = makeParams(time: 0)
        params.seedPhase = 1.7
        encodeSeed(&params, into: commandBuffer)
    }

    private func makeParams(time: Float) -> AlfvenParams {
        let cfg = configuration
        // Per-substep share of the re-seed crossfade, raised cosine (the spike's
        // advance_blend). Zero outside the blend window.
        let cycleStart = floor(time / cfg.cycleSeconds) * cfg.cycleSeconds
        let blendPhase = min(max((time - cycleStart) / cfg.blendTau, 0), 1)
        // Per-substep share of the crossfade, raised cosine (the spike's advance_blend,
        // alfven.py:115-127). The spike divides by its ACTUAL dt; this used `cfg.maxDt`,
        // the 0.005 ceiling, so the crossfade ran ~2.5x fast whenever the CFL was biting.
        let stepDt = lastAdaptiveDt > 0 ? lastAdaptiveDt : cfg.maxDt
        let blendRate: Float = blendPhase < 1
            ? (0.5 - 0.5 * cos(.pi * blendPhase)) * (stepDt / cfg.blendTau) * .pi
            : 0
        return AlfvenParams(
            dt: cfg.maxDt,
            alpha: cfg.alpha,
            nu4: cfg.nu4,
            drive: audioDrive,   // ALFVEN.3: bassDev envelope -> stirring vigour (§7)
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
            blendRate: blendRate,
            jCutoff: cfg.jCutoff)
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

    /// Fixed stand-in for film.py's percentile auto-exposure (`1/(p99.6 - p2)`), which
    /// needs a reduction surface that does not exist yet. Calibrated against the measured
    /// field at ALFVEN.4d, in DISPLAYED-LINEAR space against `05_atmosphere_relaxed_state`
    /// (the silence target Matt named): 0.085 puts the production path at 0.229, which is
    /// REF 05's own value. Note this is BRIGHTER than our film.py port's stills (0.159),
    /// deliberately — the port still undershoots REF 05, and matching the port would just
    /// reproduce that shortfall.
    ///
    /// ⚠ Calibrating this needs sRGB care, and getting it wrong cost a round: the render
    /// target is `.bgra8Unorm_srgb` so its bytes are gamma-ENCODED, while film.py and the
    /// reference PNGs write LINEAR values straight to bytes. Comparing raw byte means
    /// across the two conventions made the live path look 2x too dark.
    ///
    /// ⚠ The previous 0.55 was never calibrated against anything and blew the value
    /// channel out at BOTH field scales — `|J| * 0.55` reached 2.99 at ALFVEN.4's J (rms
    /// 5.43) and still saturates at 4c's (rms 1.55). Measured on the production path it
    /// gave meanLum 0.701 against film.py's 0.309...0.332.
    public var displayExposure: Float = 0.085
    /// Fixed stand-in for film.py's `1/(std(J) * 1.2)` — the current-sheet POLARITY scale
    /// that drives hue opponency. Separate from `displayExposure` on purpose: they
    /// normalise by different statistics, and collapsing them onto one constant is what
    /// made the live frame flat lavender. J's std runs 1.54...1.64, so 1/(1.6*1.2) ~ 0.52.
    public var displayPolarityScale: Float = 0.52
    /// Seam-bloom strength — film.py's `amt` at silence.
    ///
    /// film.py uses `0.30 + 0.85 * clip(sizzle, 0, 1.6)` where `sizzle` is `trebRel - 0.6`;
    /// at silence that clips to 0 and the constant term is all that remains. The treble
    /// term needs audio, so it arrives with ALFVEN.3 and this is the floor it builds on.
    public var displayBloomAmount: Float = 0.30
    /// The normalisation the BLOOM THRESHOLD is measured against — `1/(p99.6 - p2)`, the
    /// autoexp scale. J's p99.6 runs 3.99…4.66 across frames, so the true scale is
    /// 0.216…0.253 and no fixed constant tracks it; 0.216 is the value at the BRIGHTEST
    /// end, chosen deliberately because the threshold is nonlinear — being 6% high on
    /// this constant made the core 1.56x too dense, while being low only makes the bloom
    /// slightly shy. Under-blooming is the safe direction. Validated field-to-field
    /// against film.py's own `gaussian_filter` on the same J: core mean ratio 1.071,
    /// coverage 3.28% vs 3.09%, correlation 0.958 (at 0.229 it was 1.560 / 4.34%).
    ///
    /// Deliberately NOT `displayExposure`, and the distinction is the same trap that made
    /// the frame flat lavender at 4d: the two constants answer different questions.
    /// `displayExposure` (0.085) is calibrated so the frame's BRIGHTNESS matches REF 05;
    /// this one reproduces film.py's percentile scale so that its threshold still means
    /// "the brightest decile". Feed the brightness constant in instead and `aJ` tops out
    /// near 0.38, never crosses film.py's 0.72, and the bloom silently contributes
    /// nothing — which is exactly what the first build of this did.
    ///
    /// Keeping it separate is what lets `alfven_bloom_core` use film.py's 0.72 / 0.28 /
    /// ^1.5 verbatim rather than three constants re-derived into our own space.
    public var displayBloomExposure: Float = 0.216

    /// ANCHOR of the palette drift: the late magenta<->teal end of film.py's drift, and
    /// the state Matt signed off on live (2026-09-09). The drift is arranged so this exact
    /// value is what you see at t = 0 and again every period — his ask was to keep this
    /// state and add colours around it, not to replace it.
    public var displayHueCentre: Float = 0.72

    /// The seam-bloom chain, for field-to-field comparison against film.py. Diagnostics only.
    public var bloomCoreTexture: MTLTexture { fields.bloomCore }
    public var bloomNearTexture: MTLTexture { fields.bloomNear }
    public var bloomFarTexture: MTLTexture { fields.bloomFar }

    /// The timestep the CFL reduction chose on the last substep. Diagnostics only.
    public var lastAdaptiveDt: Float {
        dtBuffer.contents().assumingMemoryBound(to: Float.self).pointee
    }
}
