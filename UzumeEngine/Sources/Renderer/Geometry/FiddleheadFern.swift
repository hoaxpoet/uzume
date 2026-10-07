// FiddleheadFern — the Fiddlehead preset's renderer (FH.16): an endless dive into a self-similar fern that unfurls as
// the camera reaches it, glowing in a colour bath with beat-grid nerve impulses running trunk → leaflet tips.
//
// WHY A ParticleGeometry. The fern is drawn by a per-pixel bounded depth-first descent over precomputed curl-state
// fields (texture arrays), a one-time precompute, and its own bloom — compute kernels and custom textures, which only
// this seam gives a preset (the Alfvén shape). `activeParticleFraction` is the governor's lever on the INTERNAL
// render resolution.
//
// Reference implementation and test bed: `docs/presets/fiddlehead_spike/fern_descent.swift` (FH.15). Its
// exhaustive-search ground truth found 0.00 % missing pixels across a full zoom cycle with these settings.
//
// Lifecycle: the shape (CPU) is built at init; the fields (~57 MB) are allocated and baked on the FIRST update, on a
// separate command queue so no frame waits on it — until the bake completes the preset shows its ground fragment.

import Foundation
import Metal
import Shared

public enum FiddleheadFernError: Error {
    case functionNotFound(String)
    case allocationFailed
}

public final class FiddleheadFern: ParticleGeometry, @unchecked Sendable {

    /// Governor lever: scales the internal render AREA (1 = up to 1080p).
    public var activeParticleFraction: Float = 1.0

    let device: MTLDevice
    let shape = FernShape()
    /// Chooses the palette look each frame (FiddleheadFern+Palette).
    var palettePlan = FernPalettePlan()
    /// Harness override: render this look instead of the plan's (palette curation).
    var lookOverride: FernLook?
    let dive: FernDive
    var music = FernMusic()
    private let logger = Logging.renderer

    // Shape on the GPU
    let childBuffer: MTLBuffer
    let spineBuffer: MTLBuffer
    let pulseBuffer: MTLBuffer
    var params = FernParams()
    let fieldResolution = 640

    // Pipelines
    let spinePSO, seedPSO, stepPSO, childPSO, renderPSO, resolvePSO, brightPSO, blurPSO: MTLComputePipelineState
    let displayPipeline: MTLRenderPipelineState?
    let laneNormals: Bool

    // Fields (lazy) and frame targets (drawable-sized)
    var fieldF: MTLTexture?, fieldT: MTLTexture?, fieldC: MTLTexture?
    var hdr: MTLTexture?, bloomA: MTLTexture?, bloomB: MTLTexture?
    /// TAA history ping-pong (the resolved picture the bloom and display read), and the previous frame's camera.
    var history: [MTLTexture] = []
    var historyIndex = 0
    var historyValid = false
    var lastCamera: (centre: SIMD4<Float>, cycle: Float)?
    var frameIndex = 0
    private let bakeLock = NSLock()
    private var bakeState = 0                       // 0 not started, 1 baking, 2 ready
    var drawableSize = SIMD2<Int>(1920, 1080)
    var clock: Float = 0

    public init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb) throws {
        self.device = device
        func pso(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw FiddleheadFernError.functionNotFound(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        spinePSO = try pso("fh_spine_field"); seedPSO = try pso("fh_tree_seed"); stepPSO = try pso("fh_tree_step")
        childPSO = try pso("fh_child_field"); renderPSO = try pso("fh_render"); resolvePSO = try pso("fh_resolve")
        brightPSO = try pso("fh_bright"); blurPSO = try pso("fh_blur")
        laneNormals = renderPSO.threadExecutionWidth == 32                  // the normals' lane layout assumes 32
        if let vfn = library.makeFunction(name: "fh_display_vertex"),
           let ffn = library.makeFunction(name: "fh_display_fragment") {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn; desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            displayPipeline = try? device.makeRenderPipelineState(descriptor: desc)
        } else {
            displayPipeline = nil
        }

        let built = shape.build()
        dive = FernDive(shape: shape, children: built.children)
        var children = built.children, spines = built.spines
        guard let cb = device.makeBuffer(bytes: &children, length: MemoryLayout<FernChild>.stride * children.count),
              let sb = device.makeBuffer(bytes: &spines, length: MemoryLayout<SIMD2<Float>>.stride * spines.count),
              let qb = device.makeBuffer(length: MemoryLayout<SIMD2<Float>>.stride * FernMusic.maxPulses,
                                         options: .storageModeShared) else {
            throw FiddleheadFernError.allocationFailed
        }
        childBuffer = cb; spineBuffer = sb; pulseBuffer = qb

        params.box = SIMD4(built.boxMin.x, built.boxMin.y, built.boxMax.x, built.boxMax.y)
        params.shape = SIMD4(shape.rachisWidth, shape.childScale, shape.eye, 2)
        params.grid = SIMD4(Float(dive.perState),
                            Float(shape.states),
                            Float(fieldResolution),
                            Float(shape.spineSamples))
        params.curl = SIMD4(shape.logOpen, shape.logRolled, 14, 0.15)
        params.look = SIMD4(0.08, 4, 2.5, laneNormals ? 1 : 0)
        logger.info("""
            FiddleheadFern: \(self.dive.perState) children × \(self.shape.states) curl states, \
            fields \(self.fieldResolution)²
            """)
    }

    /// True once the fields are baked and the fern can draw.
    public var isReady: Bool { bakeLock.withLock { bakeState == 2 } }

    // MARK: ParticleGeometry

    public func ensureAllocated(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        drawableSize = SIMD2(width, height)
        let (width, height) = internalSize()
        if let hdr, hdr.width == width, hdr.height == height { return }
        hdr = makeTexture(.rgba16Float, width, height)
        bloomA = makeTexture(.rgba16Float, max(width / 4, 1), max(height / 4, 1))
        bloomB = makeTexture(.rgba16Float, max(width / 4, 1), max(height / 4, 1))
        history = [makeTexture(.rgba16Float, width, height), makeTexture(.rgba16Float, width, height)].compactMap { $0 }
        historyValid = false
    }

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        startBakeIfNeeded()
        let dt = min(max(features.deltaTime, 0), 0.1)
        clock += dt
        music.update(features: features, time: clock, dt: dt, dive: dive)
        let energy = FernPalettePlan.energy(level: stemFeatures.energyLevel, surge: features.spectralSurge)
        palettePlan.update(time: clock,
                           energy: energy,
                           trackKey: features.trackHueAnchor01,
                           downbeat: music.downbeatThisFrame)
        guard isReady else { return }
        if hdr == nil { ensureAllocated(width: drawableSize.x, height: drawableSize.y) }
        encodeFrame(into: commandBuffer)
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard isReady, let displayPipeline, history.count == 2, let bloomA else { return }
        // bloom, white point, exposure (← the passage's section level)
        var display = SIMD4<Float>(1.0, 2.5, 2.8 * (0.55 + 0.55 * music.level), 0)
        encoder.setRenderPipelineState(displayPipeline)
        encoder.setFragmentTexture(history[historyIndex], index: 0)   // the resolved picture
        encoder.setFragmentTexture(bloomA, index: 1)
        encoder.setFragmentBytes(&display, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// New track: the music state and the palette plan start over (the dive keeps falling).
    public func resetForTrack() { music.reset(); palettePlan.reset() }

    // MARK: Internals

    /// Internal render size: the drawable, capped at 80 % of 1080p's area × the governor's fraction (a 4K drawable at
    /// full resolution is 4× the cost; the display pass upscales). Measured (FH.16, M2 Pro, release, back-to-back):
    /// full 1080p p50 16.7 / p95 17.7 ms — on the 60 fps line, so the default keeps ~20 % headroom.
    func internalSize() -> (Int, Int) {
        let width = Float(drawableSize.x), height = Float(drawableSize.y)
        let cap = 1920 * 1080 * 0.8 * max(min(activeParticleFraction, 1), 0.25)
        let factor = min(1, (cap / (width * height)).squareRoot())
        return (max(Int(width * factor), 16), max(Int(height * factor), 16))
    }

    func makeTexture(_ format: MTLPixelFormat, _ width: Int, _ height: Int, slices: Int = 0) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format,
                                                            width: width,
                                                            height: height,
                                                            mipmapped: false)
        if slices > 0 { desc.textureType = .type2DArray; desc.arrayLength = slices }
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        return device.makeTexture(descriptor: desc)
    }

    private func startBakeIfNeeded() {
        let start = bakeLock.withLock { () -> Bool in
            guard bakeState == 0 else { return false }
            bakeState = 1
            return true
        }
        guard start else { return }
        guard let queue = device.makeCommandQueue(), let cb = queue.makeCommandBuffer() else {
            logger.error("FiddleheadFern: no command queue for the bake")
            return
        }
        let t0 = Date()
        guard encodeBake(into: cb) else { logger.error("FiddleheadFern: field allocation failed"); return }
        cb.addCompletedHandler { [weak self] buffer in
            guard let self else { return }
            let ok = buffer.status == .completed
            self.bakeLock.withLock { self.bakeState = ok ? 2 : 0 }
            self.logger.info("FiddleheadFern: fields baked in \(Int(Date().timeIntervalSince(t0) * 1000)) ms (ok \(ok))")
        }
        cb.commit()
    }
}
