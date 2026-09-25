// KaguraDancer — Kagura's `ParticleGeometry`: fifteen points of light dancing the twist (KAG.2).
//
// KAGURA_DESIGN §1, §5, §8. The dance itself is `KaguraChoreographer` (pure CPU); the beat position
// is `KaguraBeatClock` (fed by the app's stateful tick, `VisualizerEngine+Presets`). This file is
// the GPU half — look B, ported from the spike's `render()`:
//
// - a geometry-owned ping-pong `rgba16Float` TRAIL (Ricercar's pattern, `RicercarEchoGeometry`):
//   decay per elapsed time (`0.05^(dt / 0.4 s)`, BUG-097), then one amber line segment per joint
//   from its previous to its current projected position;
// - a COMPOSITE target: ground + trail, then each joint as an instanced quad (Witchlight's bead
//   pattern, `WitchlightStroke`) carrying a soft warm-white core and a wide dim halo;
// - `render()` draws the composite through the soft filmic shoulder `1 − exp(−1.6·x)`.
//
// The camera is orthographic, 35° yaw, fixed. The spike framed a 720 px-tall frame at 255 px per
// metre with the floor at 0.88·H, core σ 2.6 px, halo σ 9 px, trail σ 2.4 px; every one of those
// scales with drawable HEIGHT, and the figure is centred on the width.
//
// Nothing brightens on the beat (D-157). Not built here (KAG.3): dance selection, arm reach, the
// grid-CV safety net, the silence rest.

import Foundation
import Metal
import simd
import Shared

// MARK: - GPU mirrors (Kagura.metal)

/// Mirror of MSL `KaguraConfig` — six float4, no padding.
struct KaguraConfig {
    var frame: SIMD4<Float>      // width px, height px, trail multiplier, deposit
    var sigmas: SIMD4<Float>     // trail σ, core σ, halo σ, shoulder gain
    var amps: SIMD4<Float>       // core amplitude, halo amplitude, –, –
    var ground: SIMD4<Float>
    var trailColor: SIMD4<Float>
    var dotColor: SIMD4<Float>
}

/// Mirror of MSL `KaguraJoint` — previous and current projected position, px, y down.
struct KaguraJoint {
    var ends: SIMD4<Float>
}

// MARK: - KaguraLook

/// Look B's constants, at the spike's 720 px reference height (KAGURA_DESIGN §8).
public enum KaguraLook {
    public static let referenceHeight: Float = 720
    public static let pixelsPerMetre: Float = 255
    public static let floorFraction: Float = 0.88
    public static let yawDegrees: Float = 35
    public static let coreSigma: Float = 2.6
    public static let haloSigma: Float = 9.0
    public static let trailSigma: Float = 2.4
    public static let coreAmplitude: Float = 1.0
    public static let haloAmplitude: Float = 0.22
    /// The spike deposited 6 splats of amplitude 0.22 per 30 fps frame.
    public static let spikeDepositPerFrame: Float = 0.22 * 6
    public static let spikeFrameSeconds: Double = 1.0 / 30
    /// A trail point fades to this fraction …
    public static let trailFloor: Double = 0.05
    /// … over this many seconds.
    public static let trailSeconds: Double = 0.4
    public static let shoulder: Float = 1.6
    public static let ground = SIMD3<Float>(4, 5, 9) / 255
    public static let trailColor = SIMD3<Float>(255, 170, 110) / 255
    public static let dotColor = SIMD3<Float>(255, 236, 214) / 255

    /// The trail multiplier for `seconds` of elapsed time — per time, never per frame (BUG-097).
    public static func trailDecay(seconds: Double) -> Float {
        Float(pow(trailFloor, max(seconds, 0) / trailSeconds))
    }

    /// Splat amplitude deposited along a segment covering `seconds` of motion.
    ///
    /// A frame's segment is drawn AFTER that frame's decay, so its light is under-decayed by about
    /// half a frame — +6.6 % trail energy at 30 fps against 60, −3.6 % at 120 (KaguraTrailDecayTests,
    /// first run). Scaling by the frame's own `1 − decay` is the exact mean decay over the interval,
    /// which makes the trail's energy frame-rate independent; normalising to the spike's 30 fps
    /// frame keeps the spike's brightness, whose render carried the same bias at 30 fps.
    public static func trailDeposit(seconds: Double) -> Float {
        spikeDepositPerFrame * (1 - trailDecay(seconds: seconds)) / (1 - trailDecay(seconds: spikeFrameSeconds))
    }

    /// Orthographic three-quarter projection to pixels (y down) for a target of the given size.
    public static func project(_ joint: SIMD3<Float>, width: Int, height: Int) -> SIMD2<Float> {
        let yaw = yawDegrees * .pi / 180
        let scale = pixelsPerMetre * Float(height) / referenceHeight
        let x = joint.x * cos(yaw) + joint.z * sin(yaw)
        return SIMD2(Float(width) / 2 + scale * x, Float(height) * floorFraction - scale * joint.y)
    }
}

// MARK: - KaguraDancer

/// Kagura's particle geometry: the dancer's CPU core plus look B's trail, points and composite.
public final class KaguraDancer: ParticleGeometry, @unchecked Sendable {

    public enum KaguraError: Error { case clipsUnavailable, functionNotFound(String) }

    public var activeParticleFraction: Float = 1.0

    private let device: MTLDevice
    private let clips: KaguraClipLibrary
    private var choreographer: KaguraChoreographer
    private let clockLock = NSLock()
    private var clock = KaguraBeatClock()

    private let jointCount: Int
    private var trail: [MTLTexture] = []
    private var composite: MTLTexture?
    private var cur = 0
    private var width = 0, height = 0
    private var lastPixels: [SIMD2<Float>]?
    private var lastDeltaTime: Float = 1.0 / 60.0

    private let decayPSO: MTLRenderPipelineState
    private let segmentPSO: MTLRenderPipelineState
    private let compositePSO: MTLRenderPipelineState
    private let dotPSO: MTLRenderPipelineState
    private let displayPSO: MTLRenderPipelineState?

    /// The last frame's world joints (metres) — the pulse-lock replay reads the dancer's OUTPUT.
    public private(set) var lastJoints: [SIMD3<Float>] = []
    /// The beat position the last frame danced to (`nil` without grid or clock).
    public private(set) var lastBeat: Double?

    // MARK: Init

    /// - Parameters:
    ///   - pixelFormat: the drawable's format for `render`; `nil` builds the offscreen passes only.
    public init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat? = nil,
                clips: KaguraClipLibrary? = nil) throws {
        let lib = try clips ?? KaguraClipLibrary.shared()
        guard let choreographer = KaguraChoreographer(library: lib) else { throw KaguraError.clipsUnavailable }
        self.device = device
        self.clips = lib
        self.choreographer = choreographer
        jointCount = lib.jointNames.count

        func fn(_ name: String) throws -> MTLFunction {
            guard let function = library.makeFunction(name: name) else { throw KaguraError.functionNotFound(name) }
            return function
        }
        func pso(_ vertex: String, _ fragment: String, format: MTLPixelFormat, additive: Bool) throws
            -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = try fn(vertex)
            desc.fragmentFunction = try fn(fragment)
            desc.colorAttachments[0].pixelFormat = format
            if additive, let att = desc.colorAttachments[0] {
                att.isBlendingEnabled = true
                att.rgbBlendOperation = .add
                att.alphaBlendOperation = .add
                att.sourceRGBBlendFactor = .one
                att.destinationRGBBlendFactor = .one
                att.sourceAlphaBlendFactor = .zero
                att.destinationAlphaBlendFactor = .one
            }
            return try device.makeRenderPipelineState(descriptor: desc)
        }
        decayPSO = try pso("fullscreen_vertex", "kagura_trail_decay_fragment", format: .rgba16Float, additive: false)
        segmentPSO = try pso("kagura_segment_vertex", "kagura_segment_fragment", format: .rgba16Float, additive: true)
        compositePSO = try pso("fullscreen_vertex", "kagura_composite_fragment", format: .rgba16Float, additive: false)
        dotPSO = try pso("kagura_dot_vertex", "kagura_dot_fragment", format: .rgba16Float, additive: true)
        displayPSO = try pixelFormat.map {
            try pso("fullscreen_vertex", "kagura_display_fragment", format: $0, additive: false)
        }
    }

    // MARK: Clock + grid input (the app's push; thread-safe)

    /// Install (or clear) the grid; `streaming` selects the clock source and the lock gate (§3a).
    public func setGrid(_ grid: KaguraGrid?, streaming: Bool) {
        clockLock.withLock { clock.setGrid(grid, streaming: streaming) }
    }

    /// Push this frame's playback clock, drift and lock state, stamped with the render clock.
    public func ingestClock(playbackSeconds: Double, driftSeconds: Double = 0, renderTime: Double, lockState: Int) {
        clockLock.withLock {
            clock.ingest(
                playbackSeconds: playbackSeconds,
                driftSeconds: driftSeconds,
                renderTime: renderTime,
                lockState: lockState
            )
        }
    }

    /// Per-track reset: forget the playback clock's history. The grid push handles the rest (a new
    /// grid fades the dancer to the sway; it rejoins at the new grid's next bar line).
    public func reset() {
        clockLock.withLock { clock.resetClock() }
    }

    /// Preset activation: start from the sway with an empty trail and no clock history, so a
    /// dance and a clock left over from an earlier activation are never resumed minutes stale.
    /// The installed grid is kept (it belongs to the track, not the activation).
    public func restart() {
        clockLock.withLock { clock.resetClock() }
        if let fresh = KaguraChoreographer(library: clips) { choreographer = fresh }
        lastPixels = nil
        clearTrail()
    }

    // MARK: ParticleGeometry

    public func ensureAllocated(width: Int, height: Int) {
        let newW = max(1, width), newH = max(1, height)
        guard newW != self.width || newH != self.height else { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: newW, height: newH, mipmapped: false)
        desc.usage = [.shaderRead, .renderTarget]
        desc.storageMode = .private
        guard let first = device.makeTexture(descriptor: desc), let second = device.makeTexture(descriptor: desc),
              let comp = device.makeTexture(descriptor: desc) else { return }
        trail = [first, second]
        composite = comp
        cur = 0
        self.width = newW
        self.height = newH
        lastPixels = nil   // a resize drops the trail; never streak from the old frame's positions
        clearTrail()
    }

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        if trail.isEmpty { ensureAllocated(width: 1280, height: 720) }
        let deltaTime = features.deltaTime > 0 ? features.deltaTime : 1.0 / 60.0
        lastDeltaTime = deltaTime
        let (beat, grid, generation, permitted) = clockLock.withLock {
            (
                clock.beatPosition(atRenderTime: Double(features.time)),
                clock.grid,
                clock.gridGeneration,
                clock.dancePermitted
            )
        }
        let joints = choreographer.advance(
            deltaTime: Double(deltaTime),
            beat: beat,
            grid: grid,
            gridGeneration: generation,
            dancePermitted: permitted
        )
        lastJoints = joints
        lastBeat = beat
        encodeFrame(joints: joints, deltaTime: deltaTime, commandBuffer: commandBuffer)
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let displayPSO, let composite else { return }
        var cfg = config(deltaTime: lastDeltaTime)
        encoder.setRenderPipelineState(displayPSO)
        encoder.setFragmentBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 0)
        encoder.setFragmentTexture(composite, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: Test surface

    /// The composite target (ground + trail + points, before the shoulder).
    public var compositeTexture: MTLTexture? { composite }
    /// The current trail target.
    public var trailTexture: MTLTexture? { trail.isEmpty ? nil : trail[cur] }
    /// Read-only view of the choreographer (cut beats, chosen levels).
    public var choreography: KaguraChoreographer { choreographer }

    /// Encode the GPU passes for a frame whose joints are already known. `update` is this plus the
    /// choreographer; tests that need an exact, synthetic motion call it directly.
    public func encodeFrame(joints: [SIMD3<Float>], deltaTime: Float, commandBuffer: MTLCommandBuffer) {
        guard trail.count == 2, let composite else { return }
        let pixels = joints.map { KaguraLook.project($0, width: width, height: height) }
        let previous = lastPixels ?? pixels
        lastPixels = pixels
        // `setVertexBytes`, not a shared MTLBuffer: frames stay in flight after `update` returns
        // (up to three in production), and a buffer rewritten per frame would hand every queued
        // frame the NEWEST segment — the trail collapsed to one dash per joint in the first run.
        var segments = (0..<min(jointCount, pixels.count)).map {
            KaguraJoint(ends: SIMD4(lowHalf: previous[$0], highHalf: pixels[$0]))
        }
        let segmentBytes = segments.count * MemoryLayout<KaguraJoint>.stride
        var cfg = config(deltaTime: deltaTime)
        let src = trail[cur], dst = trail[1 - cur]

        // Pass 1 — trail: decay the previous trail into `dst`, then deposit this frame's segments.
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: Self.target(dst, load: .dontCare)) {
            enc.setRenderPipelineState(decayPSO)
            enc.setFragmentBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 0)
            enc.setFragmentTexture(src, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.setRenderPipelineState(segmentPSO)
            enc.setVertexBytes(&segments, length: segmentBytes, index: 0)
            enc.setVertexBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 1)
            enc.setFragmentBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segments.count)
            enc.endEncoding()
        }
        // Pass 2 — composite: ground + trail, then the points (core + halo) added on top.
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: Self.target(composite, load: .dontCare)) {
            enc.setRenderPipelineState(compositePSO)
            enc.setFragmentBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 0)
            enc.setFragmentTexture(dst, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.setRenderPipelineState(dotPSO)
            enc.setVertexBytes(&segments, length: segmentBytes, index: 0)
            enc.setVertexBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 1)
            enc.setFragmentBytes(&cfg, length: MemoryLayout<KaguraConfig>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: segments.count)
            enc.endEncoding()
        }
        cur = 1 - cur
    }

    // MARK: Helpers

    private func config(deltaTime: Float) -> KaguraConfig {
        let scale = Float(height) / KaguraLook.referenceHeight
        let decay = KaguraLook.trailDecay(seconds: Double(deltaTime))
        let deposit = KaguraLook.trailDeposit(seconds: Double(deltaTime))
        return KaguraConfig(
            frame: SIMD4(Float(width), Float(height), decay, deposit),
            sigmas: SIMD4(
                KaguraLook.trailSigma * scale,
                KaguraLook.coreSigma * scale,
                KaguraLook.haloSigma * scale,
                KaguraLook.shoulder
            ),
            amps: SIMD4(KaguraLook.coreAmplitude, KaguraLook.haloAmplitude, 0, 0),
            ground: SIMD4(KaguraLook.ground, 0),
            trailColor: SIMD4(KaguraLook.trailColor, 0),
            dotColor: SIMD4(KaguraLook.dotColor, 0))
    }

    private static func target(_ texture: MTLTexture, load: MTLLoadAction) -> MTLRenderPassDescriptor {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = load
        rpd.colorAttachments[0].storeAction = .store
        return rpd
    }

    private func clearTrail() {
        guard let queue = device.makeCommandQueue(), let cmd = queue.makeCommandBuffer() else { return }
        for tex in trail {
            let rpd = Self.target(tex, load: .clear)
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            cmd.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        }
        cmd.commit()
        cmd.waitUntilCompleted()
    }
}
