// RayMarchTemporal — MetalFX temporal reconstruction on the ray-march G-buffer path (VQ.3).
//
// A ray-march scene that declares `temporal_reconstruction` (motion_vectors `reprojected`) marches
// at its march size with a Halton(2,3) sub-pixel jitter, and MetalFX rebuilds an output-sized image
// from the jittered history. `RayMarchPipeline.render` drives it:
//   1. `applyJitter` nudges `cameraForward` by the jitter before the G-buffer pass. Every ray in the
//      shared ray generation (the preamble's `raymarch_gbuffer_fragment`, `rm_rayDir` in the lighting
//      pass) is `fwd + ndc.x·xFov·rt − ndc.y·yFov·up`, so a constant image-plane offset IS a nudge of
//      `fwd`: no shader reads a new uniform, every pass stays consistent, and zero jitter leaves the
//      uniforms — and so the frame — byte-identical (MFX.1's method, `git show ffadb100`).
//   2. After lighting, the motion pass (RayMarchTemporal.metal) reprojects the depth with the current
//      and previous unjittered cameras into depth / motion / reactive targets.
//   3. `DirectTemporalReconstructor` (MFX.2's scaler wrapper, external-input mode) upscales the LIT,
//      LINEAR image — before any tone mapping — into its output, which feeds the scene's finish (the
//      legacy ACES composite / PostProcessChain, or the cinematic stage).
//
// Prior art: MFX.1 (`MetalFXTemporalUpscaler`, deleted at D-213); D-263's conventions hold — jitter
// handed to MetalFX negated, motion scale 1. Not thread-safe: render (main) thread, like the canvas.

import Foundation
import Metal
import os.log
import simd
import Shared

private let logger = Logger(subsystem: "io.uzume.renderer", category: "RayMarchTemporal")

// MARK: - Uniforms

/// Mirrors `RayMarchTemporalUniforms` in RayMarchTemporal.metal (160 bytes).
struct RayMarchTemporalUniforms {
    var currentInverse = simd_float3x3()
    var previousInverse = simd_float3x3()
    var currentPosition = SIMD4<Float>.zero
    var previousPosition = SIMD4<Float>.zero
    var fov = SIMD4<Float>.zero
    var params = SIMD4<Float>.zero
}

// MARK: - RayMarchTemporal

/// The ray-march path's temporal reconstruction: jitter, motion pass, MetalFX.
public final class RayMarchTemporal {

    /// One camera as the shared ray generation sees it.
    struct Camera {
        var position: SIMD3<Float>
        var basis: simd_float3x3          // columns fwd, rt, up
        var tanHalf: SIMD2<Float>         // x includes the aspect ratio

        init(_ scene: SceneUniforms) {
            let fov = scene.cameraOriginAndFov
            position = SIMD3(fov.x, fov.y, fov.z)
            basis = simd_float3x3(columns: (SIMD3(scene.cameraForward.x, scene.cameraForward.y, scene.cameraForward.z),
                                            SIMD3(scene.cameraRight.x, scene.cameraRight.y, scene.cameraRight.z),
                                            SIMD3(scene.cameraUp.x, scene.cameraUp.y, scene.cameraUp.z)))
            let tanY = tan(fov.w * 0.5)
            tanHalf = SIMD2(tanY * scene.sceneParamsA.y, tanY)
        }
    }

    public let reconstructor: DirectTemporalReconstructor
    private let device: MTLDevice
    private let budget: RenderTargetBudget?
    private let pipeline: MTLRenderPipelineState
    private var depth: [MTLTexture] = []
    private var motion: MTLTexture?
    private var reactive: MTLTexture?
    private var parity = 0
    private var previous: Camera?

    /// Relative depth mismatch where the reactive mask starts (full at 2×). Measured: see
    /// `RayMarchTemporalReconstructionTests`.
    public var reactiveTolerance: Float = 0.02

    /// - Parameters:
    ///   - library: the Renderer library (holds `raymarch_temporal_fragment`).
    ///   - budget: nil (offline tests) allocates directly.
    public init(device: MTLDevice, library: MTLLibrary, spec: TemporalReconstructionSpec,
                budget: RenderTargetBudget?) throws {
        self.device = device
        self.budget = budget
        reconstructor = DirectTemporalReconstructor(device: device, spec: spec, budget: budget, externalInputs: true)
        guard let vertex = library.makeFunction(name: "fullscreen_vertex"),
              let fragment = library.makeFunction(name: "raymarch_temporal_fragment") else {
            throw RayMarchPipelineError.functionNotFound("raymarch_temporal_fragment")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = TemporalReconstructionSpec.depthFormat
        desc.colorAttachments[1].pixelFormat = TemporalReconstructionSpec.motionFormat
        desc.colorAttachments[2].pixelFormat = TemporalReconstructionSpec.reactiveFormat
        desc.label = "ray-march temporal motion"
        pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    /// Discard the history: scene switch, a cut, a resize.
    public func reset() {
        reconstructor.reset()
        previous = nil
    }

    /// The march (input) size and the output size this frame. Cheap when nothing changed; a change
    /// reallocates and resets the history. False when MetalFX cannot reconstruct at this ratio, or the
    /// budget refused — the caller takes the scene's normal path.
    public func prepare(inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int) -> Bool {
        guard reconstructor.prepare(inputWidth: inputWidth,
                                    inputHeight: inputHeight,
                                    outputWidth: outputWidth,
                                    outputHeight: outputHeight),
              reconstructor.isTemporal else {
            releaseInputs()
            return false
        }
        if depth.count == 2, depth[0].width == inputWidth, depth[0].height == inputHeight { return true }
        releaseInputs()   // VQ.0: release before allocate
        func request(_ format: MTLPixelFormat, _ name: String) -> RenderTargetBudget.Request {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: inputWidth, height: inputHeight, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            return .init(desc, label: "ray-march temporal \(name) \(inputWidth)×\(inputHeight)")
        }
        let requests = [request(TemporalReconstructionSpec.depthFormat, "depth A"),
                        request(TemporalReconstructionSpec.depthFormat, "depth B"),
                        request(TemporalReconstructionSpec.motionFormat, "motion"),
                        request(TemporalReconstructionSpec.reactiveFormat, "reactive")]
        guard let made = makeTextures(requests) else {
            logger.error("Ray-march temporal targets refused at \(inputWidth)×\(inputHeight)")
            reconstructor.releaseTargets()
            return false
        }
        depth = [made[0], made[1]]
        motion = made[2]
        reactive = made[3]
        reset()
        return true
    }

    /// Drop every target, the scaler and its reservation (VQ.0 — call once the frames in flight drained).
    public func release() {
        releaseInputs()
        reconstructor.releaseTargets()
    }

    private func releaseInputs() {
        depth = []
        motion = nil
        reactive = nil
        previous = nil
    }

    private func makeTextures(_ requests: [RenderTargetBudget.Request]) -> [MTLTexture]? {
        if let budget { return budget.makeTextures(owner: "rayMarchTemporal", requests) }
        var made: [MTLTexture] = []
        for request in requests {
            guard let texture = device.makeTexture(descriptor: request.descriptor) else { return nil }
            texture.label = request.label
            made.append(texture)
        }
        return made
    }

    // MARK: Frame

    /// Nudge `scene.cameraForward` by this frame's jitter (render pixels at `width × height`, the
    /// march size). The caller restores the unjittered forward after the frame.
    func applyJitter(to scene: inout SceneUniforms, width: Int, height: Int) {
        let jitter = reconstructor.jitter
        guard jitter != .zero, width > 0, height > 0 else { return }
        let tanY = tan(scene.cameraOriginAndFov.w * 0.5)
        let ndcX = jitter.x * 2 / Float(width) * tanY * scene.sceneParamsA.y
        let ndcY = jitter.y * 2 / Float(height) * tanY
        let fwd = scene.cameraForward, rt = scene.cameraRight, up = scene.cameraUp
        scene.cameraForward = SIMD4(fwd.x + ndcX * rt.x - ndcY * up.x,
                                    fwd.y + ndcX * rt.y - ndcY * up.y,
                                    fwd.z + ndcX * rt.z - ndcY * up.z,
                                    fwd.w)
    }

    /// Motion pass + MetalFX for this frame. `jittered` is the uniforms the G-buffer marched with,
    /// `camera` the same frame's unjittered camera. Returns the output-sized, linear image, or nil
    /// (the caller uses `lit` unchanged).
    func resolve(commandBuffer: MTLCommandBuffer, lit: MTLTexture, gbuffer0: MTLTexture,
                 jittered: SceneUniforms, camera: Camera) -> MTLTexture? {
        guard depth.count == 2, let motion, let reactive else { return nil }
        let current = depth[parity], prior = depth[1 - parity]
        let last = previous ?? camera
        var uniforms = RayMarchTemporalUniforms()
        uniforms.currentInverse = camera.basis.inverse
        uniforms.previousInverse = last.basis.inverse
        uniforms.currentPosition = SIMD4(camera.position, jittered.sceneParamsA.w)
        uniforms.previousPosition = SIMD4(last.position, 0)
        uniforms.fov = SIMD4(camera.tanHalf.x, camera.tanHalf.y, last.tanHalf.x, last.tanHalf.y)
        uniforms.params = SIMD4(Float(lit.width), Float(lit.height), previous == nil ? 0 : 1, reactiveTolerance)

        let pass = MTLRenderPassDescriptor()
        for (index, texture) in [current, motion, reactive].enumerated() {
            pass.colorAttachments[index].texture = texture
            pass.colorAttachments[index].loadAction = .dontCare
            pass.colorAttachments[index].storeAction = .store
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "ray-march temporal motion"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<RayMarchTemporalUniforms>.stride, index: 0)
        var scene = jittered
        encoder.setFragmentBytes(&scene, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        encoder.setFragmentTexture(gbuffer0, index: 0)
        encoder.setFragmentTexture(prior, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let inputs = DirectTemporalReconstructor.Targets(
            color: lit,
            depth: current,
            motion: motion,
            reactive: reconstructor.spec.reactiveMask ? reactive : nil)
        let image = reconstructor.encodeUpscale(commandBuffer: commandBuffer, inputs: inputs)
        reconstructor.advance()
        previous = camera
        parity = 1 - parity
        return image
    }

    /// Run MetalFX once off screen and discard the history (scene apply): its first encode is slow.
    public func warmUp(lit: MTLTexture, queue: MTLCommandQueue) {
        guard let inputs = lastInputs(color: lit), let cb = queue.makeCommandBuffer() else { return }
        cb.label = "ray-march temporal warm-up"
        _ = reconstructor.encodeUpscale(commandBuffer: cb, inputs: inputs)
        cb.commit()
        reset()
    }

    // MARK: Diagnostics (tests)

    /// MetalFX's inputs as the last `resolve` left them, with `color` (tests: readback, timing).
    func lastInputs(color: MTLTexture) -> DirectTemporalReconstructor.Targets? {
        guard let motion, depth.count == 2 else { return nil }
        return .init(color: color, depth: depth[1 - parity], motion: motion, reactive: reactive)
    }
}
