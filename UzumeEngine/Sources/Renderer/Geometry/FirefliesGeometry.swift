// FirefliesGeometry — the Fireflies preset's `ParticleGeometry` conformer: the Metal seam.
//
// A sibling, not a subclass (D-097). The model lives in `FirefliesSwarm`, the place in
// `FirefliesWorld`; this file owns the GPU side of both. Per frame it:
//   1. advances the swarm (FF.1, unchanged) and the world's camera drift;
//   2. writes the camera into `worldBuffer`, which the app binds at the world fragment's
//      buffer(6) (`bindFirefliesRuntime`, the Nebula slot-6 precedent);
//   3. draws the branch skeletons through that camera, then the fireflies additively.
//
// Tempo: the swarm's natural periods are built on the installed grid's BPM, which
// `FeatureVector` does not carry. The engine already publishes it every MIR analysis frame in
// `SpectralHistoryBuffer` slot 2418 (`grid.bpm`, 0 with no grid); the geometry is handed that
// buffer at construction and reads the one float — the Stave / Meniscus precedent of handing a
// geometry an existing engine buffer (no protocol change, no new surface).
//
// FIREFLIES IN DEPTH (FF.2). The swarm's coupling domain stays FF.1's screen-space layout —
// the neighbour relation, the relay radius and every constant are untouched, so the parity
// gate still holds. Each firefly's 3D position is DERIVED from it: its (posU, posV) is a ray
// through the fixed rest camera and its FF.1 depth (1 near … 9 far) is a distance along that
// ray, `metresPerDepth` metres per unit. The moving camera then projects that point, so near
// fireflies slide against far ones and against the trees. Size and brightness keep FF.1's
// formulas with FF.1's depth replaced by the TRUE view depth from the moving camera (close to
// FF.1's values at the rest camera; the 10 % overscan below is the one deliberate difference).
//
// No compute pass: 600 clocks and a once-per-frame grid neighbour search (0.28 ms/frame at
// `-O`) are cheaper in Swift than a dispatch (the Witchlight WL.2 precedent, 1024 beads on the
// CPU). Sprites are instanced quads sized in FRAME HEIGHTS, not `[[point_size]]` pixels, so a
// flash covers the same frame fraction at every drawable size — the flash-safety budget
// (D-157) is a frame-AREA rule (Witchlight WL.2-g).
//
// The firefly LIGHT is still FF.1's two Gaussian stamps; the bloom, the light on the grass and
// mist, occlusion and out-of-focus discs are FF.3.

import Metal
import Shared

// MARK: - GPU mirror

/// 32 bytes, scalar floats only — mirrors `FFSprite` in `Renderer/Shaders/Fireflies.metal`.
struct FFSpriteGPU {
    var x: Float = 0, y: Float = 0          // centre, NDC
    var coreSigma: Float = 0                // frame heights
    var haloSigma: Float = 0                // frame heights
    var coreAmp: Float = 0
    var haloAmp: Float = 0
    var pad0: Float = 0, pad1: Float = 0
}

// MARK: - FirefliesGeometry

public final class FirefliesGeometry: ParticleGeometry, @unchecked Sendable {

    /// D-057 governor gate, unused: the swarm is COUPLED — dropping fireflies would change
    /// the neighbour relay and so the behaviour, not just the cost (the coupled-flock rule).
    public var activeParticleFraction: Float = 1.0

    /// The model. Exposed so harnesses and tests can drive and inspect it.
    public let swarm: FirefliesSwarm
    /// The camera for the world fragment — bind at fragment buffer(6).
    public let worldBuffer: MTLBuffer
    /// Harness-only: shifts the camera drift's clock so a still can show the same moment from a
    /// drifted camera. 0 in production.
    public var cameraTimeOffset: Float {
        get { world.cameraTimeOffset }
        set { world.cameraTimeOffset = newValue }
    }
    /// Harness-only: hold the camera at its rest pose so the wind can be measured alone.
    public var freezeCamera: Bool {
        get { world.freezeCamera }
        set { world.freezeCamera = newValue }
    }

    /// Metres of distance per unit of FF.1's 2.5-D depth (1 near … 9 far → 3 … 27 m).
    static let metresPerDepth: Float = 3
    /// The swarm's screen layout is spread 10 % wider than the frame through the rest camera, so
    /// the drift never uncovers an empty strip at the side.
    static let overscan: Float = 1.1

    let world: FirefliesWorld
    private let beatGrid: SpectralHistoryBuffer?
    private let sprites: MTLBuffer
    private let branchBuffer: MTLBuffer
    private let pipeline: MTLRenderPipelineState?
    private let branchPipeline: MTLRenderPipelineState?
    private var visibleCount = 0
    private var aspect: Float = 16.0 / 9.0
    private var viewport = SIMD2<Float>(1920, 1080)

    /// - Parameter beatGrid: the engine's `SpectralHistoryBuffer`, read for the installed
    ///   grid's BPM. `nil` = no grid ever (the swarm stays free).
    public init(device: MTLDevice, library: MTLLibrary, beatGrid: SpectralHistoryBuffer?,
                pixelFormat: MTLPixelFormat? = nil, seed: UInt64 = 7) throws {
        swarm = FirefliesSwarm(seed: seed)
        self.beatGrid = beatGrid
        let place = FirefliesWorld()
        world = place
        let branchBytes = place.branches.count * MemoryLayout<FFBranchGPU>.stride
        guard let buffer = device.makeBuffer(length: FirefliesSwarm.count * MemoryLayout<FFSpriteGPU>.stride,
                                             options: .storageModeShared),
              let worldBuf = device.makeBuffer(length: MemoryLayout<FFWorldGPU>.stride, options: .storageModeShared),
              let branches = device.makeBuffer(length: max(branchBytes, 16), options: .storageModeShared) else {
            throw FirefliesError.bufferAllocationFailed
        }
        place.branches.withUnsafeBytes { raw in
            if let base = raw.baseAddress { branches.contents().copyMemory(from: base, byteCount: raw.count) }
        }
        sprites = buffer
        worldBuffer = worldBuf
        branchBuffer = branches
        guard let pixelFormat else { pipeline = nil; branchPipeline = nil; writeWorld(); return }
        let target = PipelineTarget(device: device, library: library, pixelFormat: pixelFormat)
        pipeline = try target.make(stage: "fireflies_sprite", additive: true)
        branchPipeline = try target.make(stage: "fireflies_branch", additive: false)
        writeWorld()
    }

    /// Builds the geometry's two pipelines onto one colour target.
    private struct PipelineTarget {
        let device: MTLDevice
        let library: MTLLibrary
        let pixelFormat: MTLPixelFormat

        /// `<stage>_vertex` + `<stage>_fragment`. Sprites are emissive (light adds to the dusk
        /// behind); branches are ink laid over the world (premultiplied source-over).
        func make(stage: String, additive: Bool) throws -> MTLRenderPipelineState {
            guard let vertexFn = library.makeFunction(name: "\(stage)_vertex"),
                  let fragmentFn = library.makeFunction(name: "\(stage)_fragment") else {
                throw FirefliesError.functionNotFound(stage)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFn
            descriptor.fragmentFunction = fragmentFn
            guard let attachment = descriptor.colorAttachments[0] else {
                throw FirefliesError.functionNotFound("\(stage): colorAttachments[0]")
            }
            attachment.pixelFormat = pixelFormat
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = additive ? .one : .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .zero
            attachment.destinationAlphaBlendFactor = .one
            return try device.makeRenderPipelineState(descriptor: descriptor)
        }
    }

    // MARK: - ParticleGeometry

    public func ensureAllocated(width: Int, height: Int) {
        if width > 0, height > 0 { viewport = SIMD2(Float(width), Float(height)) }
    }

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        let bpm = beatGrid?.readOverlayState().bpm ?? 0
        swarm.advance(features: features, clarity: stemFeatures.beatClarity01, gridBPM: bpm)
        if features.aspectRatio > 0 { aspect = features.aspectRatio }
        world.advance(dt: min(max(features.deltaTime, 0), 0.1), aspect: aspect, bassAttRel: features.bassAttRel)
        writeWorld()
        upload()
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        var cam = world.gpu
        if let branchPipeline {
            var size = viewport
            encoder.setRenderPipelineState(branchPipeline)
            encoder.setVertexBuffer(branchBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&cam, length: MemoryLayout<FFWorldGPU>.stride, index: 1)
            encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            let count = world.branches.count
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        }
        guard let pipeline, visibleCount > 0 else { return }
        var aspectLocal = aspect
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(sprites, offset: 0, index: 0)
        encoder.setVertexBytes(&aspectLocal, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: visibleCount)
    }

    // MARK: - Upload

    private func writeWorld() {
        worldBuffer.contents().storeBytes(of: world.gpu, as: FFWorldGPU.self)
    }

    /// World position of firefly `i`: its FF.1 screen position as a ray through the rest camera,
    /// its FF.1 depth as the distance along it. Kept a little above the ground.
    func position(_ i: Int) -> SIMD3<Float> {
        let rest = world.restCamera
        let ray = rest.ray(ndcX: (swarm.posU[i] * 2 - 1) * Self.overscan, ndcY: 1 - 2 * swarm.posV[i])
        var point = rest.position + ray * (swarm.depth(i) * Self.metresPerDepth)
        point.y = max(point.y, 0.15)
        return point
    }

    /// The spike's `render` with FF.1's depth replaced by true depth from the moving camera:
    /// amp = envelope × visibility × depth fog; a core stamp always, a halo only while the
    /// flash is lit (env > 0.05). Dark fireflies are skipped.
    private func upload() {
        let out = sprites.contents().bindMemory(to: FFSpriteGPU.self, capacity: FirefliesSwarm.count)
        let cam = world.camera
        var visible = 0
        for i in 0..<FirefliesSwarm.count {
            let env = swarm.envelope(i)
            guard env * swarm.vis[i] > 0.004 else { continue }
            let ndc = cam.project(position(i))
            guard ndc.z > 0.5 else { continue }
            let depth = max(ndc.z / Self.metresPerDepth, 1)
            let amp = env * swarm.vis[i] * exp(-0.10 * depth)
            guard amp > 0.004 else { continue }
            let near = 1 / depth
            out[visible] = FFSpriteGPU(
                x: ndc.x,
                y: ndc.y,
                coreSigma: (0.8 + 1.6 * near) / 720,
                haloSigma: (2.5 + 7 * near) / 720,
                coreAmp: amp * 1.2,
                haloAmp: env > 0.05 ? amp * 0.06 : 0)
            visible += 1
        }
        visibleCount = visible
    }
}

// MARK: - Errors

public enum FirefliesError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}
