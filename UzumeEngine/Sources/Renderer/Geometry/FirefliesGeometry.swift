// FirefliesGeometry — the Fireflies preset's `ParticleGeometry` conformer: the Metal seam.
//
// A sibling, not a subclass (D-097). The model lives in `FirefliesSwarm`; this file uploads
// one sprite per visible firefly and issues one instanced draw, additively over the preset's
// world fragment (`Presets/Shaders/Fireflies.metal`).
//
// Tempo: the swarm's natural periods are built on the installed grid's BPM, which
// `FeatureVector` does not carry. The engine already publishes it every MIR analysis frame in
// `SpectralHistoryBuffer` slot 2418 (`grid.bpm`, 0 with no grid); the geometry is handed that
// buffer at construction and reads the one float — the Stave / Meniscus precedent of handing a
// geometry an existing engine buffer (no protocol change, no new surface).
//
// No compute pass: 600 clocks and a once-per-frame grid neighbour search (0.28 ms/frame at
// `-O`) are cheaper in Swift than a dispatch (the Witchlight WL.2 precedent, 1024 beads on the CPU). Sprites are instanced
// quads sized in FRAME HEIGHTS, not `[[point_size]]` pixels, so a flash covers the same
// frame fraction at every drawable size — the flash-safety budget (D-157) is a frame-AREA
// rule (Witchlight WL.2-g).
//
// FF.1 is SPIKE fidelity on purpose: the core + halo below is the spike's two Gaussian
// stamps (`fireflies_spike.py` `render`). The out-of-focus discs, mist scatter, grass
// occlusion and per-fly variation are FF.3 (FF.0 README §7.3).

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

    private let beatGrid: SpectralHistoryBuffer?
    private let sprites: MTLBuffer
    private let pipeline: MTLRenderPipelineState?
    private var visibleCount = 0
    private var aspect: Float = 16.0 / 9.0

    /// - Parameter beatGrid: the engine's `SpectralHistoryBuffer`, read for the installed
    ///   grid's BPM. `nil` = no grid ever (the swarm stays free).
    public init(device: MTLDevice, library: MTLLibrary, beatGrid: SpectralHistoryBuffer?,
                pixelFormat: MTLPixelFormat? = nil, seed: UInt64 = 7) throws {
        swarm = FirefliesSwarm(seed: seed)
        self.beatGrid = beatGrid
        guard let buffer = device.makeBuffer(length: FirefliesSwarm.count * MemoryLayout<FFSpriteGPU>.stride,
                                             options: .storageModeShared) else {
            throw FirefliesError.bufferAllocationFailed
        }
        sprites = buffer
        guard let pixelFormat else { pipeline = nil; return }
        guard let vertex = library.makeFunction(name: "fireflies_sprite_vertex"),
              let fragment = library.makeFunction(name: "fireflies_sprite_fragment") else {
            throw FirefliesError.functionNotFound("fireflies_sprite")
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        guard let attachment = descriptor.colorAttachments[0] else {
            throw FirefliesError.functionNotFound("fireflies_sprite: colorAttachments[0]")
        }
        attachment.pixelFormat = pixelFormat
        // Emissive: light adds to the dusk behind it.
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .zero
        attachment.destinationAlphaBlendFactor = .one
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        let bpm = beatGrid?.readOverlayState().bpm ?? 0
        swarm.advance(features: features, clarity: stemFeatures.beatClarity01, gridBPM: bpm)
        if features.aspectRatio > 0 { aspect = features.aspectRatio }
        upload()
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let pipeline, visibleCount > 0 else { return }
        var aspectLocal = aspect
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(sprites, offset: 0, index: 0)
        encoder.setVertexBytes(&aspectLocal, length: MemoryLayout<Float>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: visibleCount)
    }

    // MARK: - Upload

    /// The spike's `render`: amp = envelope × visibility × depth fog; a core stamp always,
    /// a halo only while the flash is lit (env > 0.05). Dark fireflies are skipped.
    private func upload() {
        let out = sprites.contents().bindMemory(to: FFSpriteGPU.self, capacity: FirefliesSwarm.count)
        var visible = 0
        for i in 0..<FirefliesSwarm.count {
            let env = swarm.envelope(i)
            let depth = swarm.depth(i)
            let amp = env * swarm.vis[i] * exp(-0.10 * depth)
            guard amp > 0.004 else { continue }
            let near = 1 / depth
            out[visible] = FFSpriteGPU(
                x: swarm.posU[i] * 2 - 1,
                y: 1 - 2 * swarm.posV[i],
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
