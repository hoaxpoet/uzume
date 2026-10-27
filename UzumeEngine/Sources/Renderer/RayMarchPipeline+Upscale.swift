// RayMarchPipeline+Upscale — the ray-march path's VQ.3 upscale step, called from `render`.
//
// With `upscaleOutputSize` set, the lit (linear, pre-tone-map) image is upscaled ONCE, to the output
// size, before bloom and tone mapping: by `temporal` (MetalFX temporal on a jittered march — see
// RayMarchTemporal) or else `spatialUpscaler` (MetalFX spatial). Without it, nothing here runs and
// the composite stretches the lit image by UV, exactly as before VQ.3.

import Metal
import Shared

extension RayMarchPipeline {

    /// This frame's upscale state: the unjittered camera (restored after the frame) and whether the
    /// temporal step runs.
    struct UpscaleFrame {
        let camera: RayMarchTemporal.Camera
        let unjitteredForward: SIMD4<Float>
        let reconstructing: Bool
    }

    /// Prepare the temporal step for this march size and jitter the camera basis when it runs.
    func beginUpscaleFrame(march gbuffer0: MTLTexture) -> UpscaleFrame {
        let camera = RayMarchTemporal.Camera(sceneUniforms)
        let forward = sceneUniforms.cameraForward
        guard let temporal, let out = upscaleOutputSize,
              temporal.prepare(inputWidth: gbuffer0.width,
                               inputHeight: gbuffer0.height,
                               outputWidth: out.width,
                               outputHeight: out.height) else {
            return UpscaleFrame(camera: camera, unjitteredForward: forward, reconstructing: false)
        }
        temporal.applyJitter(to: &sceneUniforms, width: gbuffer0.width, height: gbuffer0.height)
        return UpscaleFrame(camera: camera, unjitteredForward: forward, reconstructing: true)
    }

    /// `lit` reconstructed or spatially upscaled to `upscaleOutputSize`, or `lit` itself when nothing
    /// upscales (or MetalFX declined).
    func upscaleLit(_ lit: MTLTexture, gbuffer0: MTLTexture, frame: UpscaleFrame,
                    commandBuffer: MTLCommandBuffer) -> MTLTexture {
        if frame.reconstructing, let temporal {
            return temporal.resolve(commandBuffer: commandBuffer,
                                    lit: lit,
                                    gbuffer0: gbuffer0,
                                    jittered: sceneUniforms,
                                    camera: frame.camera) ?? lit
        }
        guard let spatialUpscaler, let out = upscaleOutputSize,
              out.width > lit.width || out.height > lit.height else { return lit }
        return spatialUpscaler.encode(lit,
                                      outputWidth: out.width,
                                      outputHeight: out.height,
                                      commandBuffer: commandBuffer) ?? lit
    }
}
