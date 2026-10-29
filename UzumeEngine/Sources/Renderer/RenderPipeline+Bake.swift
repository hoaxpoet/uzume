// RenderPipeline+Bake — LM.10 (D-266): a ray-march scene's static surface, baked once.
//
// A scene that defines `preset_bake_fragment` (compiled by PresetLoader into `LoadedPreset.bakePipelineState`) gets
// it run into the slot-10 texture at the march size by the first frame that needs it — on the GPU, in that frame's
// command buffer, never on the main thread — and again whenever the march size changes. `sceneSDF` and
// `sceneMaterial` (`presetTexture`) read it; each frame then only colours what was baked.

import Metal
import Shared

extension RenderPipeline {

    // MARK: - Bake

    /// The active ray-march scene's bake (`LoadedPreset.bakePipelineState`), or nil. Call on every scene apply.
    public func setRayMarchBake(_ state: MTLRenderPipelineState?) {
        rayMarchPresetHeightTextureLock.withLock {
            rayMarchBakePipeline = state
            if state != nil { rayMarchPresetHeightTexture = nil }
        }
    }

    /// Run the active scene's bake into a `width × height` slot-10 texture if it has none at that size yet.
    func bakeRayMarchPresetTextureIfNeeded(
        width: Int,
        height: Int,
        sceneUniforms: SceneUniforms,
        commandBuffer: MTLCommandBuffer
    ) {
        let (state, current) = rayMarchPresetHeightTextureLock.withLock {
            (rayMarchBakePipeline, rayMarchPresetHeightTexture)
        }
        guard let state else { return }
        if let current, current.width == width, current.height == height { return }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        let label = "ray-march preset bake \(width)×\(height)"
        guard let texture = context.renderTargetBudget.makeTexture(
            owner: "rayMarchBake", label: label, descriptor: desc) else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = "ray-march preset bake"
        encoder.setRenderPipelineState(state)
        var uniforms = sceneUniforms
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 4)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        rayMarchPresetHeightTextureLock.withLock {
            if rayMarchBakePipeline === state { rayMarchPresetHeightTexture = texture }
        }
    }
}
