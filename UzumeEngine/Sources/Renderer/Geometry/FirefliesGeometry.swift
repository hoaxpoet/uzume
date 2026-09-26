// FirefliesGeometry — the Fireflies preset's `ParticleGeometry` conformer: the Metal seam.
//
// A sibling, not a subclass (D-097). The model lives in `FirefliesSwarm`, the place in
// `FirefliesWorld`; this file owns the GPU side of both. Per frame it:
//   1. advances the swarm (FF.1, unchanged) and the world's camera drift;
//   2. writes the camera into `worldBuffer`, which the app binds at the world fragment's
//      buffer(6) (`bindFirefliesRuntime`, the Nebula slot-6 precedent);
//   3. draws the branch skeletons and the fireflies' light through that camera, interleaved in
//      depth bands (FF.3, below).
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
// THE LIGHT (FF.3, FIREFLIES_DESIGN §4.4). Each lit firefly is a printed near-white dot with a
// stippled yellow-green halo and starburst, a LIGHT POOL that multiplies the print around it
// (the grass strokes, mist and branches brighten; the dark between them stays dark), and — near
// the camera — a soft out-of-focus disc sized by the thin-lens circle of confusion. The shading
// is in `Renderer/Shaders/Fireflies.metal`; this file sizes it and orders it.
//
// OCCLUSION WITHOUT A DEPTH BUFFER (FF.3). The direct path has no depth attachment, so occlusion
// is painter's order (Newell, Newell & Sancha 1972) in DEPTH BANDS: the static segments are
// sorted far → near once (`FirefliesWorld`), cut into `bandWidth` slices of world z, and each
// frame the lit fireflies are counting-sorted into the same slices. Band by band, far → near:
// that band's branches, then its light pools, then its fireflies. A nearer trunk, branch or
// grass stalk is drawn later and covers a farther firefly AND its light; a branch in front of a
// firefly stays a silhouette against its glow (`07`), which is also what a back-lit branch is.
// ⚠ Ceiling: bands are world z, not view depth — right while the camera looks along +z (yaw ±1°,
// pitch 6.6°); a camera that turns needs view-depth bands re-sorted per frame.
//
// No compute pass: 600 clocks and a once-per-frame grid neighbour search (0.28 ms/frame at
// `-O`) are cheaper in Swift than a dispatch (the Witchlight WL.2 precedent, 1024 beads on the
// CPU). Sprites are instanced quads sized in FRAME HEIGHTS, not `[[point_size]]` pixels, so a
// flash covers the same frame fraction at every drawable size — the flash-safety budget
// (D-157) is a frame-AREA rule (Witchlight WL.2-g).

import Metal
import Shared

// MARK: - GPU mirror

/// 48 bytes, scalar floats only — mirrors `FFSprite` in `Renderer/Shaders/Fireflies.metal`.
struct FFSpriteGPU {
    var x: Float = 0, y: Float = 0          // centre, NDC
    var coreR: Float = 0                    // frame heights: the in-focus dot
    var haloR: Float = 0                    // frame heights
    var coc: Float = 0                      // frame heights: circle of confusion radius
    var coreAmp: Float = 0
    var haloAmp: Float = 0                  // halo coverage, 0…1
    var poolR: Float = 0                    // frame heights: the light's reach on the surroundings
    var poolAmp: Float = 0
    var spin: Float = 0                     // starburst rotation, radians
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

    // Depth bands (painter's order). Band 0 holds everything at z ≥ `bandFar` — behind every
    // firefly (the deepest sits at 27 m); bands 1… are `bandWidth` slices toward the camera.
    static let bandFar: Float = 30
    static let bandWidth: Float = 0.5
    static let bandCount = 1 + Int(bandFar / bandWidth) + 1

    static func band(z: Float) -> Int {
        z >= bandFar ? 0 : min(bandCount - 1, 1 + Int((bandFar - max(z, 0)) / bandWidth))
    }

    // The light (FF.3). Thin-lens depth of field: focused mid-meadow, so only the nearest
    // fireflies (≲ 6 m) open into discs; CoC = `cocScale`·|1/z − 1/z_f| frame heights
    // (Potmesil & Chakravarty 1981) — ~11 px at 3 m on a 1080-line frame.
    static let focusMetres: Float = 14
    static let cocScale: Float = 0.045
    /// How far a firefly's light reaches on what is around it, metres — capped on screen so the
    /// nearest fireflies' pools cannot tile the foreground (the pools MULTIPLY where they overlap;
    /// uncapped, a DYC unison lifted the frame-mean luma 0.09 → 0.35, FF.3 round 1).
    static let poolMetres: Float = 0.45
    static let poolMaxFrameHeights: Float = 0.05
    /// Peak lift of a pool at full flash, before the shader's tint.
    static let poolLift: Float = 1.0

    let world: FirefliesWorld
    private let beatGrid: SpectralHistoryBuffer?
    private let sprites: MTLBuffer
    private let branchBuffer: MTLBuffer
    private let pipeline: MTLRenderPipelineState?
    private let poolPipeline: MTLRenderPipelineState?
    private let branchPipeline: MTLRenderPipelineState?
    /// First segment of each band (+ the end), from the far → near sorted skeleton.
    private let branchBandStart: [Int]
    /// First sprite of each band (+ the end), rebuilt every upload.
    private var spriteBandStart: [Int]
    private var staging: [(band: Int, sprite: FFSpriteGPU)] = []
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
        branchBandStart = Self.bandStarts(place.branches.map { Self.band(z: 0.5 * ($0.p0r0.z + $0.p1r1.z)) })
        spriteBandStart = [Int](repeating: 0, count: Self.bandCount + 1)
        staging.reserveCapacity(FirefliesSwarm.count)
        guard let pixelFormat else { pipeline = nil; poolPipeline = nil; branchPipeline = nil; writeWorld(); return }
        let target = PipelineTarget(device: device, library: library, pixelFormat: pixelFormat)
        pipeline = try target.make(stage: "fireflies_sprite", blend: .additive)
        poolPipeline = try target.make(stage: "fireflies_pool", blend: .modulateAdd)
        branchPipeline = try target.make(stage: "fireflies_branch", blend: .over)
        writeWorld()
    }

    /// `starts[b]` = index of the first element in band ≥ b, for a band list sorted ascending.
    static func bandStarts(_ bands: [Int]) -> [Int] {
        var starts = [Int](repeating: bands.count, count: bandCount + 1)
        for (index, band) in bands.enumerated().reversed() { starts[band] = index }
        for band in stride(from: bandCount - 1, through: 0, by: -1) {
            starts[band] = min(starts[band], starts[band + 1])
        }
        return starts
    }

    /// Builds the geometry's pipelines onto one colour target.
    private struct PipelineTarget {
        enum Blend { case additive, modulateAdd, over }
        let device: MTLDevice
        let library: MTLLibrary
        let pixelFormat: MTLPixelFormat

        /// `<stage>_vertex` + `<stage>_fragment`. Sprites are emissive (light adds to the dusk
        /// behind); pools multiply the print by (1 + lift) — src·dst + dst; branches are ink laid
        /// over the world (premultiplied source-over).
        func make(stage: String, blend: Blend) throws -> MTLRenderPipelineState {
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
            switch blend {
            case .additive:
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .one
            case .modulateAdd:
                attachment.sourceRGBBlendFactor = .destinationColor
                attachment.destinationRGBBlendFactor = .one
            case .over:
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            }
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

    /// Far → near, band by band: branches, light pools, fireflies (see OCCLUSION above).
    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let branchPipeline, let poolPipeline, let pipeline else { return }
        var cam = world.gpu
        var size = viewport
        encoder.setVertexBuffer(branchBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&cam, length: MemoryLayout<FFWorldGPU>.stride, index: 1)
        encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
        encoder.setVertexBuffer(sprites, offset: 0, index: 3)
        for band in 0..<Self.bandCount {
            draw(encoder, branchPipeline, branchBandStart[band]..<branchBandStart[band + 1])
            let lights = spriteBandStart[band]..<spriteBandStart[band + 1]
            draw(encoder, poolPipeline, lights)
            draw(encoder, pipeline, lights)
        }
    }

    private func draw(_ encoder: MTLRenderCommandEncoder, _ state: MTLRenderPipelineState, _ range: Range<Int>) {
        guard !range.isEmpty else { return }
        encoder.setRenderPipelineState(state)
        encoder.drawPrimitives(type: .triangleStrip,
                               vertexStart: 0,
                               vertexCount: 4,
                               instanceCount: range.count,
                               baseInstance: range.lowerBound)
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
    /// amp = envelope × visibility × depth fog. Every visible firefly gets its dot; a lit one
    /// (env > 0.05) also its halo and its light pool, all scaled by the same envelope, so the
    /// light rises and falls with the flash (40 ms, 0.11 s) and never lingers. Dark fireflies are
    /// skipped. The survivors are counting-sorted into their depth bands.
    private func upload() {
        let cam = world.camera
        let frameHeightsPerMetre = 1 / (2 * cam.tanHalfFovY)       // at 1 m
        staging.removeAll(keepingCapacity: true)
        for i in 0..<FirefliesSwarm.count {
            let env = swarm.envelope(i)
            guard env * swarm.vis[i] > 0.004 else { continue }
            let point = position(i)
            let ndc = cam.project(point)
            guard ndc.z > 0.5 else { continue }
            let depth = max(ndc.z / Self.metresPerDepth, 1)
            let amp = env * swarm.vis[i] * exp(-0.10 * depth)
            guard amp > 0.004 else { continue }
            let near = 1 / depth
            let lit = env > 0.05
            let sprite = FFSpriteGPU(
                x: ndc.x,
                y: ndc.y,
                coreR: 1.3 * (0.8 + 1.6 * near) / 720,
                haloR: (2.5 + 7 * near) / 720,
                coc: Self.cocScale * abs(1 / ndc.z - 1 / Self.focusMetres),
                coreAmp: amp * 2.4,
                haloAmp: lit ? amp * 0.9 : 0,
                poolR: min(Self.poolMetres * frameHeightsPerMetre / ndc.z, Self.poolMaxFrameHeights),
                poolAmp: lit ? amp * Self.poolLift : 0,
                spin: Float(i) * 2.399963)
            staging.append((Self.band(z: point.z), sprite))
        }
        // Counting sort by band, far → near.
        var starts = [Int](repeating: 0, count: Self.bandCount + 1)
        for entry in staging { starts[entry.band + 1] += 1 }
        for band in 0..<Self.bandCount { starts[band + 1] += starts[band] }
        spriteBandStart = starts
        let out = sprites.contents().bindMemory(to: FFSpriteGPU.self, capacity: FirefliesSwarm.count)
        for entry in staging {
            out[starts[entry.band]] = entry.sprite
            starts[entry.band] += 1
        }
    }
}

// MARK: - Errors

public enum FirefliesError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}
