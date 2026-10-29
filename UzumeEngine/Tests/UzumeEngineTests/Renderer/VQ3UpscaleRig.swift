// VQ3UpscaleRig — the VQ.3 proof scenes, the rigs that render them, and the image metrics (test-only).
//
// Two proof scenes, never shipped:
//   • `FlatProof` — a 2D field for the spatial scaler: thin high-contrast lines at four angles, a
//     fine noise field, a soft gradient, and a hard-edged rotated square for ringing. Rendered at
//     any size with an N×N in-shader supersample (N = 4 is the reference: 16 samples a pixel).
//   • `RayMarchProof` — a ray-march scene through the shared preamble G-buffer: a ground plane with
//     fine noise, a turned box with striped faces, a row of thin rods, the engine's sky gradient.
//
// `RayMarchUpscaleRig` renders a ray-march scene (the proof, Lumen Mosaic, Volumetric Lithograph)
// through the PRODUCTION `RayMarchPipeline.render` — march → lighting → [VQ.3 upscale] → composite
// (ACES / PostProcessChain) into an 8-bit sRGB output — in one of four ways: today's path (march →
// composite into a canvas → bilinear stretch), MetalFX spatial, MetalFX temporal, or a supersampled
// reference (march and composite at N× the output, box-filtered down).

import Accelerate
import Foundation
import Metal
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Errors

enum VQ3RigError: Error {
    case setup(String)
}

// MARK: - Blit

/// Bilinear / box copies between 8-bit sRGB textures, and luma readback (display-encoded Rec.709).
final class VQ3Blit {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private let copyState: MTLRenderPipelineState
    private let boxState: MTLRenderPipelineState
    private let lumaState: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    init(context: MetalContext) throws {
        let device = context.device
        self.device = device
        queue = context.commandQueue
        let lib = try device.makeLibrary(source: Self.source, options: nil)
        func state(_ fragment: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "vq3_vertex")
            desc.fragmentFunction = lib.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: desc)
        }
        copyState = try state("vq3_copy", context.pixelFormat)
        boxState = try state("vq3_box", context.pixelFormat)
        lumaState = try state("vq3_luma", .r32Float)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let made = device.makeSamplerState(descriptor: sd) else { throw VQ3RigError.setup("sampler") }
        sampler = made
    }

    func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int,
                 usage: MTLTextureUsage = [.renderTarget, .shaderRead],
                 storage: MTLStorageMode = .private) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
        desc.usage = usage
        desc.storageMode = storage
        guard let tex = device.makeTexture(descriptor: desc) else { throw VQ3RigError.setup("texture \(w)×\(h)") }
        return tex
    }

    /// Bilinear copy (the engine's stretch), or an N×N box average when `box` (the reference downsample).
    func encode(_ source: MTLTexture, into target: MTLTexture, box: Int = 0, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(box > 0 ? boxState : copyState)
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        var factor = Int32(box)
        enc.setFragmentBytes(&factor, length: 4, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Display luma of an 8-bit sRGB texture, one Float per pixel.
    func luma(_ display: MTLTexture) throws -> [Float] {
        let w = display.width, h = display.height
        let out = try texture(.r32Float, w, h, storage: .shared)
        guard let cb = queue.makeCommandBuffer() else { throw VQ3RigError.setup("cb") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = out
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { throw VQ3RigError.setup("enc") }
        enc.setRenderPipelineState(lumaState)
        enc.setFragmentTexture(display, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var values = [Float](repeating: 0, count: w * h)
        values.withUnsafeMutableBytes { ptr in
            out.getBytes(ptr.baseAddress!, bytesPerRow: w * 4,   // swiftlint:disable:this force_unwrapping
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return values
    }

    /// BGRA bytes of a texture (copied through a shared texture of the same format).
    func bgra(_ display: MTLTexture) throws -> [UInt8] {
        let w = display.width, h = display.height
        let shared = try texture(display.pixelFormat, w, h, storage: .shared)
        guard let cb = queue.makeCommandBuffer(), let blit = cb.makeBlitCommandEncoder() else {
            throw VQ3RigError.setup("blit")
        }
        blit.copy(from: display, to: shared)
        blit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        shared.getBytes(&bytes, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return bytes
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 p [[position]]; float2 uv; };
    vertex V vq3_vertex(uint i [[vertex_id]]) {
        V o; float2 uv = float2((i << 1) & 2, i & 2);
        o.p = float4(uv * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(uv.x, 1.0 - uv.y); return o;
    }
    fragment float4 vq3_copy(V in [[stage_in]], texture2d<float> t [[texture(0)]], sampler s [[sampler(0)]]) {
        return t.sample(s, in.uv);
    }
    fragment float4 vq3_box(V in [[stage_in]], texture2d<float> t [[texture(0)]], constant int& n [[buffer(0)]]) {
        uint2 base = uint2(in.p.xy) * uint(n);
        float4 acc = 0.0;
        for (int y = 0; y < n; y++) for (int x = 0; x < n; x++) acc += t.read(base + uint2(x, y));
        return acc / float(n * n);
    }
    fragment float vq3_luma(V in [[stage_in]], texture2d<float> t [[texture(0)]]) {
        float3 c = saturate(t.read(uint2(in.p.xy)).rgb);
        float3 e = select(1.055 * pow(c, 1.0 / 2.4) - 0.055, 12.92 * c, c <= 0.0031308);
        return dot(e, float3(0.2126, 0.7152, 0.0722));
    }
    """
}

// MARK: - FlatProof

/// The 2D proof scene for the spatial scaler. Scene coordinates: screen height = 1, width = 16/9,
/// panned by `offset` (scene units).
final class FlatProof {
    private let state: MTLRenderPipelineState
    let blit: VQ3Blit

    /// The rotated square: centre, half side, angle — the ringing edge (its left side).
    static let squareCentre = SIMD2<Float>(1.45, 0.72)
    static let squareHalf: Float = 0.16
    static let squareAngle: Float = 0.087   // 5°

    init(blit: VQ3Blit, format: MTLPixelFormat = .bgra8Unorm_srgb) throws {
        self.blit = blit
        let lib = try blit.device.makeLibrary(source: VQ3Blit.source + Self.shader, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "vq3_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "vq3_flat_proof")
        desc.colorAttachments[0].pixelFormat = format
        state = try blit.device.makeRenderPipelineState(descriptor: desc)
    }

    /// The scene at `w × h` with `samples × samples` sub-samples a pixel, panned by `offset`.
    func render(into target: MTLTexture, samples: Int, offset: Float, commandBuffer: MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(state)
        var params = SIMD4<Float>(Float(target.width), Float(target.height), offset, Float(samples))
        enc.setFragmentBytes(&params, length: 16, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    static let shader = """
    static float vq3_hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    static float vq3_noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float a = vq3_hash(i), b = vq3_hash(i + float2(1, 0));
        float c = vq3_hash(i + float2(0, 1)), d = vq3_hash(i + float2(1, 1));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }
    // One sample of the scene at scene point q (linear colour).
    static float3 vq3_flat(float2 q) {
        float3 dark = float3(0.03), bright = float3(0.85);
        if (q.x < 0.6) {
            // Thin lines at 0°, 3°, 30° and 45°, 1 and 2 output pixels wide (1 px = 1/2160).
            float band = floor(q.y * 4.0);
            float ang = band == 0.0 ? 0.0 : (band == 1.0 ? 0.0524 : (band == 2.0 ? 0.5236 : 0.7854));
            float2 n = float2(-sin(ang), cos(ang));
            float spacing = 0.012;
            float d = abs(fract(dot(q, n) / spacing) - 0.5) * spacing;
            float halfWidth = (q.x < 0.3 ? 0.5 : 1.0) / 2160.0;
            return d < halfWidth ? bright : dark;
        }
        if (q.x < 1.2) {
            // Fine high-contrast value noise, features ~3 output pixels.
            float v = vq3_noise(q * 720.0);
            return mix(dark, bright, smoothstep(0.35, 0.65, v));
        }
        if (q.y < 0.45) {
            // Soft gradient.
            float g = saturate(length(q - float2(1.5, 0.2)) * 2.2);
            return mix(float3(0.06, 0.08, 0.14), float3(0.55, 0.42, 0.30), g);
        }
        // Hard-edged rotated bright square on dark (the ringing edge).
        float2 c = float2(\(squareCentre.x), \(squareCentre.y));
        float a = \(squareAngle);
        float2 r = q - c;
        r = float2(cos(a) * r.x + sin(a) * r.y, -sin(a) * r.x + cos(a) * r.y);
        return (abs(r.x) < \(squareHalf) && abs(r.y) < \(squareHalf)) ? bright : dark;
    }
    fragment float4 vq3_flat_proof(V in [[stage_in]], constant float4& pp [[buffer(0)]]) {
        float2 size = pp.xy;
        int n = int(pp.w);
        float3 acc = 0.0;
        for (int sy = 0; sy < n; sy++) {
            for (int sx = 0; sx < n; sx++) {
                float2 px = floor(in.p.xy) + (float2(sx, sy) + 0.5) / float(n);
                float2 q = px / size.y + float2(pp.z, 0.0);
                acc += vq3_flat(q);
            }
        }
        return float4(acc / float(n * n), 1.0);
    }
    """

    /// The rows and the column where the square's LEFT edge crosses them, in an `w × h` image panned
    /// by `offset` — the windows the overshoot and stair-step metrics read.
    static func edgeColumns(width: Int, height: Int, offset: Float) -> [(row: Int, column: Float)] {
        let c = squareCentre, a = squareAngle, h = squareHalf
        var out: [(Int, Float)] = []
        let scale = Float(height)
        for row in 0..<height {
            let y = (Float(row) + 0.5) / scale
            // Left side: points c + R(a)·(−h, t), t ∈ (−h, h) (inverse of the shader's rotation).
            let t = (y - c.y + h * sin(a)) / cos(a)
            guard abs(t) < h * 0.7 else { continue }
            let x = c.x - h * cos(a) - t * sin(a) - offset
            out.append((row, x * scale - 0.5))
        }
        return out
    }
}

// MARK: - Ray-march proof scene

enum RayMarchProof {
    static let sidecar = """
    {"name":"VQ3 Ray-March Proof","family":"geometric","passes":["ray_march"],
     "is_diagnostic":true,"exclude_from_cycling":true,
     "scene_camera":{"position":[0.0,1.1,-3.0],"target":[0.0,0.7,2.0],"fov":50},
     "scene_lights":[{"position":[3.0,6.0,-4.0],"color":[1.0,0.97,0.92],"intensity":3.0}],
     "scene_fog":0.0,"scene_far_plane":40.0}
    """

    static let shader = """
    // VQ.3 ray-march proof scene — see VQ3UpscaleRig.swift.
    static float vq3rm_box(float3 p, float3 b) {
        float3 q = abs(p) - b;
        return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
    }
    static float3 vq3rm_boxLocal(float3 p) {
        float3 b = p - float3(0.0, 0.7, 2.0);
        float c = cos(0.35), s = sin(0.35);
        return float3(c * b.x - s * b.z, b.y, s * b.x + c * b.z);
    }
    static float vq3rm_rods(float3 p) {
        float3 r = p - float3(-2.0, 0.0, 1.0);
        r.x -= 0.3 * clamp(round(r.x / 0.3), -3.0, 3.0);
        return max(length(r.xz) - 0.012, p.y - 1.8);
    }
    static float vq3rm_hash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

    float sceneSDF(float3 p, constant FeatureVector& f, constant SceneUniforms& s,
                   constant StemFeatures& stems, texture2d<float> ferrofluidHeight) {
        (void)f; (void)s; (void)stems; (void)ferrofluidHeight;
        float ground = p.y;
        float box = vq3rm_box(vq3rm_boxLocal(p), float3(0.55, 0.7, 0.55));
        return min(ground, min(box, vq3rm_rods(p)));
    }

    void sceneMaterial(float3 p, int matID, constant FeatureVector& f, constant SceneUniforms& s,
                       constant StemFeatures& stems, thread float3& albedo, thread float& roughness,
                       thread float& metallic, thread int& outMatID, constant LumenPatternState& lumen,
                       texture2d<float> presetTexture) {
        (void)matID; (void)f; (void)s; (void)stems; (void)lumen; (void)presetTexture;
        outMatID = 0;
        metallic = 0.0;
        roughness = 0.6;
        if (p.y < 0.002) {
            // Ground: a fine high-contrast cell noise (sub-pixel in the distance — aliasing).
            float v = vq3rm_hash(floor(p.xz * 24.0));
            albedo = float3(v > 0.5 ? 0.85 : 0.04);
        } else if (vq3rm_rods(p) < 0.003) {
            albedo = float3(0.95);
        } else {
            // Box: bright faces with thin dark stripes.
            float3 q = vq3rm_boxLocal(p);
            float stripe = step(0.85, fract(q.y * 6.0));
            albedo = mix(float3(0.9, 0.88, 0.84), float3(0.03), stripe);
        }
    }
    """

    static func load(context: MetalContext) throws -> PresetLoader.LoadedPreset {
        try MFXProofScene.load(shader: shader, sidecar: sidecar, file: "VQ3RMProof", context: context)
    }
}

// MARK: - RayMarchUpscaleRig

/// One ray-march scene rendered one way. Production encode: `RayMarchPipeline.render`.
final class RayMarchUpscaleRig {

    enum Scene: String {
        case proof = "VQ3 Ray-March Proof"
        case lumenMosaic = "Lumen Mosaic"
        case volumetricLithograph = "Volumetric Lithograph"
    }

    enum Mode: Equatable {
        /// Today: march → composite into a `canvas`-sized frame → bilinear stretch to the output.
        case stretch(canvasW: Int, canvasH: Int)
        /// MetalFX spatial from the march size to the output (VQ.3).
        case spatial
        /// MetalFX temporal from the march size to the output (VQ.3).
        case temporal
        /// March and composite at `factor`× the output, box-filtered down (`factor` 1 = native).
        case reference(factor: Int)
    }

    let scene: Scene
    let mode: Mode
    let outW: Int, outH: Int
    let marchW: Int, marchH: Int
    let context: MetalContext
    let blit: VQ3Blit
    let pipeline: RayMarchPipeline
    private let gbufferState: MTLRenderPipelineState
    private let bakeState: MTLRenderPipelineState?
    private let chain: PostProcessChain?
    private let ibl: IBLManager
    private let noise: TextureManager?
    private let fft: MTLBuffer, wave: MTLBuffer
    private let lumen: LumenPatternEngine?
    private let composite: MTLTexture
    /// LM.10: the scene's baked slot-10 texture at the march size (`useBake`), as production makes it.
    private(set) var bakeTexture: MTLTexture?
    let output: MTLTexture
    private let baseCamera: SIMD4<Float>
    private var audioTime: Float = 0
    /// Forward dolly, world units per second (Volumetric Lithograph's own 1.8 by default).
    var dollySpeed: Float = 0
    /// Sideways pan, world units per second.
    var panSpeed: Float = 0

    // swiftlint:disable:next function_body_length
    init(scene: Scene, mode: Mode, outW: Int, outH: Int, marchW: Int, marchH: Int,
         context: MetalContext? = nil, temporalSpec: TemporalReconstructionSpec? = nil,
         lumenPalette: LumenPalette? = nil, useBake: Bool = false) throws {
        self.scene = scene
        self.mode = mode
        self.outW = outW
        self.outH = outH
        let ctx = try context ?? MetalContext()
        self.context = ctx
        blit = try VQ3Blit(context: ctx)
        let lib = try ShaderLibrary(context: ctx)
        let preset: PresetLoader.LoadedPreset
        if scene == .proof {
            preset = try RayMarchProof.load(context: ctx)
        } else {
            guard let found = _acceptanceFixture.presets.first(where: { $0.descriptor.name == scene.rawValue }) else {
                throw VQ3RigError.setup("\(scene.rawValue) not loaded")
            }
            preset = found
        }
        guard let state = preset.rayMarchPipelineState else { throw VQ3RigError.setup("no G-buffer state") }
        gbufferState = state
        bakeState = useBake ? preset.bakePipelineState : nil

        var march = (marchW, marchH)
        var compositeSize = (outW, outH)
        switch mode {
        case let .stretch(canvasW, canvasH): compositeSize = (canvasW, canvasH)
        case let .reference(factor):
            march = (outW * factor, outH * factor)
            compositeSize = march
            ctx.renderTargetBudget.ceiling = 1 << 40   // a 2× 4K reference is far over any Mac's render budget
        case .spatial, .temporal: break
        }
        self.marchW = march.0
        self.marchH = march.1

        pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.renderScale = Float(march.0) / Float(compositeSize.0)
        pipeline.allocateTextures(width: march.0, height: march.1)
        var uniforms = preset.descriptor.makeSceneUniforms()
        uniforms.sceneParamsA.y = Float(outW) / Float(outH)
        pipeline.sceneUniforms = uniforms
        baseCamera = uniforms.cameraOriginAndFov
        ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        if preset.descriptor.passes.contains(.postProcess) {
            let made = try PostProcessChain(context: ctx, shaderLibrary: lib)
            made.allocateTextures(width: march.0, height: march.1)   // production: the chain at march size
            chain = made
        } else {
            chain = nil
        }
        if scene == .lumenMosaic {
            guard let engine = LumenPatternEngine(device: ctx.device) else { throw VQ3RigError.setup("lumen") }
            engine.setPalette(lumenPalette ?? LumenMosaicPaletteLibrary.all[0])
            lumen = engine
        } else {
            lumen = nil
        }
        guard let f = ctx.makeSharedBuffer(length: 512 * 4), let w = ctx.makeSharedBuffer(length: 2048 * 4) else {
            throw VQ3RigError.setup("audio buffers")
        }
        fft = f
        wave = w

        composite = try blit.texture(ctx.pixelFormat, compositeSize.0, compositeSize.1)
        output = try blit.texture(ctx.pixelFormat, outW, outH)
        switch mode {
        case .spatial:
            pipeline.spatialUpscaler = SpatialUpscaler(device: ctx.device, budget: ctx.renderTargetBudget)
            pipeline.upscaleOutputSize = (outW, outH)
        case .temporal:
            let spec = temporalSpec ?? TemporalReconstructionSpec(motionVectors: .reprojected, reactiveMask: true)
            pipeline.temporal = try RayMarchTemporal(device: ctx.device, library: lib.library, spec: spec,
                                                     budget: ctx.renderTargetBudget)
            pipeline.upscaleOutputSize = (outW, outH)
        default: break
        }
    }

    var temporal: RayMarchTemporal? { pipeline.temporal }

    /// One frame at `time` (seconds; 60 fps steps). Returns the 8-bit sRGB output and the GPU ms.
    @discardableResult
    func frame(time: Float, features base: FeatureVector? = nil, stems: StemFeatures = .zero) throws
        -> (texture: MTLTexture, gpuMs: Double) {
        var fv = base ?? FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: time, deltaTime: 1.0 / 60)
        fv.time = time
        audioTime += max(0, fv.bass) * (1.0 / 60.0)
        fv.accumulatedAudioTime = audioTime
        pipeline.sceneUniforms.sceneParamsA.x = audioTime
        pipeline.sceneUniforms.cameraOriginAndFov = SIMD4(baseCamera.x + panSpeed * time, baseCamera.y,
                                                          baseCamera.z + dollySpeed * time, baseCamera.w)
        lumen?.tick(features: fv, stems: stems)
        guard let cb = context.commandQueue.makeCommandBuffer() else { throw VQ3RigError.setup("cb") }
        if let bakeState, bakeTexture == nil {
            bakeTexture = try blit.texture(.rgba8Unorm, marchW, marchH)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = bakeTexture
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store
            let encoder = cb.makeRenderCommandEncoder(descriptor: pass)
            encoder?.setRenderPipelineState(bakeState)
            var uniforms = pipeline.sceneUniforms
            encoder?.setFragmentBytes(&uniforms, length: MemoryLayout<SceneUniforms>.stride, index: 4)
            encoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder?.endEncoding()
        }
        pipeline.render(gbufferPipelineState: gbufferState, features: &fv, fftBuffer: fft, waveformBuffer: wave,
                        stemFeatures: stems, outputTexture: mode == .spatial || mode == .temporal ? output : composite,
                        commandBuffer: cb, noiseTextures: noise, iblManager: ibl, postProcessChain: chain,
                        presetFragmentBuffer3: lumen?.patternBuffer, presetHeightTexture: bakeTexture)
        switch mode {
        case .stretch: blit.encode(composite, into: output, commandBuffer: cb)
        case let .reference(factor): blit.encode(composite, into: output, box: factor, commandBuffer: cb)
        default: break
        }
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw VQ3RigError.setup("GPU: \(error)") }
        return (output, (cb.gpuEndTime - cb.gpuStartTime) * 1000)
    }
}

// MARK: - Metrics

/// The VQ.3 image metrics, on display-encoded luma (0…1).
enum UpscaleMetrics {

    /// Σ squared neighbour differences (horizontal + vertical) — ProofMetrics' measure.
    static func gradientEnergy(_ a: [Float], width: Int) -> Double {
        ProofMetrics.gradientEnergy(a, width: width)
    }

    static func meanAbs(_ a: [Float], _ b: [Float]) -> Double { ProofMetrics.meanAbs(a, b) }

    /// Ringing beside a hard edge: per row, the overshoot above the bright plateau and the undershoot
    /// below the dark one, within ±`reach` px of the edge, as a fraction of the edge's contrast
    /// (plateaus = means 6…`reach` px out on each side). Returns the mean over rows of
    /// max(overshoot, undershoot).
    static func overshoot(_ luma: [Float], width: Int, edges: [(row: Int, column: Float)], reach: Int = 12) -> Double {
        var total = 0.0
        var counted = 0
        for (row, column) in edges {
            let centre = Int(column.rounded())
            guard centre - reach >= 0, centre + reach < width else { continue }
            let base = row * width
            let dark = (6...reach).map { Double(luma[base + centre - $0]) }.reduce(0, +) / Double(reach - 5)
            let bright = (6...reach).map { Double(luma[base + centre + $0]) }.reduce(0, +) / Double(reach - 5)
            let contrast = bright - dark
            guard contrast > 0.2 else { continue }
            var hi = -Double.infinity, lo = Double.infinity
            for x in (centre - reach)...(centre + reach) {
                hi = max(hi, Double(luma[base + x]))
                lo = min(lo, Double(luma[base + x]))
            }
            total += max(max(hi - bright, 0), max(dark - lo, 0)) / contrast
            counted += 1
        }
        return counted == 0 ? 0 : total / Double(counted)
    }

    /// Stair-stepping: the RMS (px) between each row's sub-pixel edge position in `luma` and in the
    /// reference. Position = the window's left end + its coverage sum (dark→bright, normalised).
    static func edgeStepRMS(_ luma: [Float], _ reference: [Float], width: Int,
                            edges: [(row: Int, column: Float)], reach: Int = 8) -> Double {
        func position(_ image: [Float], _ row: Int, _ centre: Int) -> Double? {
            let base = row * width
            let dark = Double(image[base + centre - reach]), bright = Double(image[base + centre + reach])
            guard bright - dark > 0.2 else { return nil }
            var coverage = 0.0
            for x in (centre - reach)...(centre + reach) {
                coverage += min(max((Double(image[base + x]) - dark) / (bright - dark), 0), 1)
            }
            return Double(centre + reach) - coverage
        }
        var sum = 0.0
        var counted = 0
        for (row, column) in edges {
            let centre = Int(column.rounded())
            guard centre - reach >= 0, centre + reach < width,
                  let p = position(luma, row, centre), let r = position(reference, row, centre) else { continue }
            sum += (p - r) * (p - r)
            counted += 1
        }
        return counted == 0 ? 0 : (sum / Double(counted)).squareRoot()
    }

    /// Shimmer on a pan: the mean |(fₜ − fₜ₋₁) − (rₜ − rₜ₋₁)| — how much the frame-to-frame change
    /// departs from the reference's own change (0 = moves exactly like the reference).
    static func shimmer(_ frames: [[Float]], reference: [[Float]]) -> Double {
        guard frames.count > 1, frames.count == reference.count else { return 0 }
        var total = 0.0
        for t in 1..<frames.count {
            var df = [Float](repeating: 0, count: frames[t].count), dr = df, err = df
            vDSP_vsub(frames[t - 1], 1, frames[t], 1, &df, 1, vDSP_Length(df.count))
            vDSP_vsub(reference[t - 1], 1, reference[t], 1, &dr, 1, vDSP_Length(dr.count))
            vDSP_vsub(dr, 1, df, 1, &err, 1, vDSP_Length(err.count))
            var mean: Float = 0
            vDSP_meamgv(err, 1, &mean, vDSP_Length(err.count))
            total += Double(mean)
        }
        return total / Double(frames.count - 1)
    }

    /// Mean raw frame-to-frame |Δ| (MFX.2's measure).
    static func frameDelta(_ frames: [[Float]]) -> Double {
        guard frames.count > 1 else { return 0 }
        return (1..<frames.count).map { meanAbs(frames[$0], frames[$0 - 1]) }.reduce(0, +) / Double(frames.count - 1)
    }

    /// Edges found in a reference: for each row in `rows`, the column of the largest rising step
    /// (left dark → right bright) inside `[x0, x1)` — the windows `edgeStepRMS` / `overshoot` read.
    static func risingEdges(_ reference: [Float], width: Int, rows: Range<Int>, x0: Int, x1: Int,
                            minStep: Float = 0.25) -> [(row: Int, column: Float)] {
        var out: [(Int, Float)] = []
        for row in rows {
            var best: Float = 0, at = -1
            for x in max(x0, 2)..<min(x1, width - 2) {
                let step = reference[row * width + x + 2] - reference[row * width + x - 2]
                if step > best { best = step; at = x }
            }
            if best > minStep { out.append((row, Float(at))) }
        }
        return out
    }
}
