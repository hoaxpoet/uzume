// MFXProofScene — the MFX.2 proof scene and the rig that renders it (test-only, never shipped).
//
// A ray-marched lattice of thin, striped, high-contrast rods the camera flies through (camera
// motion), plus a spoked ring that rides ahead of the camera and turns (object motion) — the two
// kinds of motion Energetic Flyby has. Every pixel writes its EXACT previous-frame position
// (static lattice: the hit point itself; ring: the hit point carried back through the ring's own
// rotation), so the reconstruction is judged on MetalFX, not on estimated motion.
//
// The scene is loaded through `PresetLoader` from a temp directory (sidecar included), so the MRT
// pipeline under test is the one production builds; frames go through
// `RenderPipeline.encodeTemporalReconstruction`, the production encode.

import Foundation
import Metal
import MetalFX
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Sources

enum MFXProofScene {

    static let name = "MFX Proof"

    static let sidecar = """
    {"name":"MFX Proof","family":"geometric","passes":["direct"],
     "fragment_function":"mfx_proof_fragment","is_diagnostic":true,"exclude_from_cycling":true,
     "temporal_reconstruction":{"internal_scale":0.6666667,"motion_vectors":"analytic",
                                "fov":60,"near":0.05,"far":100}}
    """

    static let shader = """
    // MFX.2 proof scene — see MFXProofScene.swift.
    constant float kProofTanY = 0.57735027;      // tan(30°): 60° vertical field of view
    constant float kProofNear = 0.05;
    constant float kProofFar = 100.0;
    constant float kProofSpinRate = 0.8;         // ring turn, rad/s
    constant float kProofSpinDist = 3.5;         // ring centre, ahead of the camera

    struct ProofCam { float3 pos; float3 rt; float3 up; float3 fw; };

    static ProofCam proof_cam(float t, float mode) {
        ProofCam c;
        c.pos = float3(0.35 * sin(0.5 * t), 0.25 * cos(0.37 * t), 1.6 * t);
        // Camera modes (FeatureVector.treble): 1 = sideways pan, 2 = still. Both look straight ahead.
        if (mode == 1.0) c.pos = float3(0.4 * sin(0.8 * t), 0.0, 3.2);
        if (mode == 2.0) c.pos = float3(0.0, 0.0, 3.2);
        if (mode >= 1.0) t = 0.0;
        float yaw = 0.18 * sin(0.31 * t);
        float pitch = 0.10 * sin(0.23 * t);
        c.fw = normalize(float3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)));
        c.rt = normalize(cross(float3(0, 1, 0), c.fw));
        c.up = cross(c.fw, c.rt);
        return c;
    }

    // World → ring-local at time t (ring in local xy, axis = camera forward), and back.
    static float3 proof_to_ring(float3 p, ProofCam c, float t) {
        float3 v = p - (c.pos + c.fw * kProofSpinDist);
        float3 q = float3(dot(v, c.rt), dot(v, c.up), dot(v, c.fw));
        float a = -kProofSpinRate * t;
        return float3(cos(a) * q.x - sin(a) * q.y, sin(a) * q.x + cos(a) * q.y, q.z);
    }
    static float3 proof_from_ring(float3 q, ProofCam c, float t) {
        float a = kProofSpinRate * t;
        float3 r = float3(cos(a) * q.x - sin(a) * q.y, sin(a) * q.x + cos(a) * q.y, q.z);
        return c.pos + c.fw * kProofSpinDist + c.rt * r.x + c.up * r.y + c.fw * r.z;
    }

    // Rods along every cell edge of a 2-unit lattice; the camera path stays inside one tunnel.
    static float proof_lattice(float3 p) {
        float3 q = p - 2.0 * floor((p + 1.0) * 0.5);
        float3 a = 1.0 - abs(q);
        return min(length(a.xy), min(length(a.yz), length(a.xz))) - 0.02;
    }

    // A thin ring with seven thin blades.
    static float proof_ring(float3 q) {
        float r = length(q.xy);
        float ring = length(float2(r - 0.75, q.z)) - 0.012;
        float sector = 6.2831853 / 7.0;
        float ang = atan2(q.y, q.x);
        float a2 = ang - sector * floor(ang / sector + 0.5);
        float2 p2 = float2(r * cos(a2), r * sin(a2));
        float3 b = float3(abs(p2.x - 0.435) - 0.315, abs(p2.y) - 0.008, abs(q.z) - 0.03);
        float blade = length(max(b, 0.0)) + min(max(b.x, max(b.y, b.z)), 0.0);
        return min(ring, blade);
    }

    static float2 proof_map(float3 p, ProofCam c, float t) {
        float dl = proof_lattice(p);
        float dr = proof_ring(proof_to_ring(p, c, t));
        return dr < dl ? float2(dr, 1.0) : float2(dl, 0.0);
    }

    static float2 proof_project(float3 p, ProofCam c, float2 size) {
        float3 v = p - c.pos;
        float z = max(dot(v, c.fw), 1e-4);
        float tanX = kProofTanY * size.x / size.y;
        float2 ndc = float2(dot(v, c.rt) / (z * tanX), dot(v, c.up) / (z * kProofTanY));
        return float2((ndc.x * 0.5 + 0.5) * size.x, (0.5 - ndc.y * 0.5) * size.y);
    }

    fragment TemporalFragmentOut mfx_proof_fragment(
        VertexOut in [[stage_in]],
        constant FeatureVector& f [[buffer(0)]],
        constant TemporalFrame& tf [[buffer(9)]]
    ) {
        float2 size = tf.render_size;
        float t = f.time;
        float tp = f.time - f.delta_time;
        ProofCam c = proof_cam(t, f.treble);
        ProofCam cp = proof_cam(tp, f.treble);
        float2 s = in.position.xy + tf.jitter;          // the sample point, render pixels
        float tanX = kProofTanY * size.x / size.y;
        float2 ndc = float2(s.x / size.x * 2.0 - 1.0, 1.0 - s.y / size.y * 2.0);
        float3 rd = normalize(c.fw + ndc.x * tanX * c.rt + ndc.y * kProofTanY * c.up);

        float dist = 0.0;
        float id = -1.0;
        for (int i = 0; i < 192 && dist < 40.0; i++) {
            float2 h = proof_map(c.pos + rd * dist, c, t);
            if (h.x < 0.0004 * dist + 0.0002) { id = h.y; break; }
            dist += h.x * 0.9;
        }

        TemporalFragmentOut o;
        float3 bg = mix(float3(0.015, 0.02, 0.05), float3(0.05, 0.06, 0.12), saturate(rd.y * 0.5 + 0.5));
        if (id < 0.0) {
            o.color = float4(bg, 1.0);
            o.depth = 1.0;
            o.motion = proof_project(cp.pos + rd, cp, size) - s;   // a direction: camera turn only
            return o;
        }
        float3 p = c.pos + rd * dist;
        float2 e = float2(0.0005, 0.0);
        float3 n = normalize(float3(
            proof_map(p + e.xyy, c, t).x - proof_map(p - e.xyy, c, t).x,
            proof_map(p + e.yxy, c, t).x - proof_map(p - e.yxy, c, t).x,
            proof_map(p + e.yyx, c, t).x - proof_map(p - e.yyx, c, t).x));
        float3 col;
        float3 pPrev;
        if (id < 0.5) {
            float3 q = p - 2.0 * floor((p + 1.0) * 0.5);
            float3 a = 1.0 - abs(q);
            float along = (a.x > a.y && a.x > a.z) ? p.x : ((a.y > a.z) ? p.y : p.z);
            float stripe = step(0.5, fract(along * 3.0));
            float3 base = mix(float3(0.06, 0.07, 0.09), float3(0.95, 0.97, 1.0), stripe);
            col = base * (0.35 + 0.65 * saturate(dot(n, normalize(float3(0.4, 0.7, -0.5)))));
            pPrev = p;                                             // the lattice is static
        } else {
            float3 q = proof_to_ring(p, c, t);
            float band = step(0.5, fract(length(q.xy) * 12.0));
            col = mix(float3(0.55, 0.22, 0.05), float3(1.0, 0.92, 0.75), band)
                * (0.6 + 0.4 * saturate(dot(n, -rd)));
            pPrev = proof_from_ring(q, cp, tp);                   // the same ring point, last frame
        }
        col = mix(bg, col, exp(-dist * 0.05));
        float z = dot(p - c.pos, c.fw);
        o.color = float4(col, 1.0);
        o.depth = saturate(kProofFar * (z - kProofNear) / (z * (kProofFar - kProofNear)));
        o.motion = proof_project(pPrev, cp, size) - s;
        return o;
    }
    """

    /// A checkerboard scrolling right at `kScrollSpeed` px/s, with a reactive mask (task-1 unit test).
    static let scrollSidecar = """
    {"name":"MFX Scroll","family":"geometric","passes":["direct"],
     "fragment_function":"mfx_scroll_fragment","is_diagnostic":true,"exclude_from_cycling":true,
     "temporal_reconstruction":{"internal_scale":0.6666667,"motion_vectors":"analytic",
                                "reactive_mask":true}}
    """

    static let scrollShader = """
    fragment TemporalFragmentOutReactive mfx_scroll_fragment(
        VertexOut in [[stage_in]],
        constant FeatureVector& f [[buffer(0)]],
        constant TemporalFrame& tf [[buffer(9)]]
    ) {
        float speed = 90.0;                                       // render px / s
        float2 s = in.position.xy + tf.jitter;
        float2 cell = floor((s - float2(speed * f.time, 0.0)) / 12.0);
        float checker = fmod(abs(cell.x + cell.y), 2.0);
        TemporalFragmentOutReactive o;
        o.color = float4(float3(0.08 + 0.84 * checker), 1.0);
        o.depth = 0.5;
        o.motion = float2(-speed * f.delta_time, 0.0);            // previous − current
        o.reactive = 0.0;
        return o;
    }
    """

    /// Load a scene through `PresetLoader` (bundled presets off), as production would.
    static func load(shader: String, sidecar: String, file: String,
                     context: MetalContext) throws -> PresetLoader.LoadedPreset {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mfx2_\(file)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try shader.write(to: dir.appendingPathComponent("\(file).metal"), atomically: true, encoding: .utf8)
        try sidecar.write(to: dir.appendingPathComponent("\(file).json"), atomically: true, encoding: .utf8)
        let loader = PresetLoader(device: context.device, pixelFormat: context.pixelFormat,
                                  watchDirectory: dir, loadBuiltIn: false)
        guard let preset = loader.presets.first else { throw MFXProofError.loadFailed(file) }
        return preset
    }
}

enum MFXProofError: Error {
    case loadFailed(String)
    case noPipeline
    case gpu(String)
}

// MARK: - Rig

/// Renders the proof scene three ways at one output size: native (no jitter, full size),
/// reconstructed (production encode), and stretched (internal size, no jitter, bilinear copy).
/// Every result is copied into an sRGB 8-bit texture exactly as `drawDirect` copies to the drawable.
@MainActor
final class MFXProofRig {
    let context: MetalContext
    let pipeline: RenderPipeline
    let preset: PresetLoader.LoadedPreset
    let outW: Int
    let outH: Int
    var nativeTargets: [String: [MTLTexture]] = [:]
    private var displayTextures: [String: MTLTexture] = [:]
    private let lumaState: MTLRenderPipelineState
    private var lumaTexture: MTLTexture?

    init(shader: String = MFXProofScene.shader, sidecar: String = MFXProofScene.sidecar,
         file: String = "MFXProof", outW: Int, outH: Int) throws {
        let ctx = try MetalContext()
        context = ctx
        preset = try MFXProofScene.load(shader: shader, sidecar: sidecar, file: file, context: ctx)
        let library = try ShaderLibrary(context: ctx)
        let stride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * stride),
              let wave = ctx.makeSharedBuffer(length: 2048 * stride) else { throw MFXProofError.gpu("buffers") }
        let pipe = try RenderPipeline(context: ctx, shaderLibrary: library, fftBuffer: fft, waveformBuffer: wave)
        pipe.mvWarpLock.withLock { pipe.presentationSize = CGSize(width: outW, height: outH) }
        pipe.setTemporalReconstruction(preset.descriptor.temporalReconstruction,
                                       pipeline: preset.temporalPipelineState)
        pipeline = pipe
        self.outW = outW
        self.outH = outH

        let lib = try ctx.device.makeLibrary(source: Self.lumaSource, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = lib.makeFunction(name: "mfx_luma_vertex")
        desc.fragmentFunction = lib.makeFunction(name: "mfx_luma_fragment")
        desc.colorAttachments[0].pixelFormat = .r32Float
        lumaState = try ctx.device.makeRenderPipelineState(descriptor: desc)
    }

    var reconstructor: DirectTemporalReconstructor? { pipeline.temporalReconstructor }
    /// Proof camera: 0 = forward flight (the default, Energetic Flyby's motion), 1 = sideways pan,
    /// 2 = camera still (only the ring turns). Rides `FeatureVector.treble` — a test-only scene.
    var cameraMode: Float = 0

    static func features(time: Float, dt: Float) -> FeatureVector {
        var fv = FeatureVector()
        fv.time = time
        fv.deltaTime = dt
        fv.aspectRatio = 16.0 / 9.0
        return fv
    }

    /// One production reconstruct encode. Returns the reconstructed frame.
    func reconstruct(time: Float, dt: Float) throws -> MTLTexture {
        guard let cb = context.commandQueue.makeCommandBuffer() else { throw MFXProofError.gpu("cb") }
        var fv = Self.features(time: time, dt: dt)
        fv.treble = cameraMode
        guard let image = pipeline.encodeTemporalReconstruction(
            commandBuffer: cb, outputWidth: outW, outputHeight: outH,
            features: &fv, stems: .zero, textOverlay: nil) else { throw MFXProofError.noPipeline }
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw MFXProofError.gpu("\(error)") }
        return image
    }

    /// The scene's MRT fragment at `width × height`, no jitter: the reference ("native") and the
    /// stretch source. Returns the colour target.
    func renderPlain(time: Float, dt: Float, width: Int, height: Int,
                     gpuMs: inout Double?) throws -> MTLTexture {
        let key = "\(width)x\(height)"
        if nativeTargets[key] == nil {
            nativeTargets[key] = try [DirectTemporalReconstructor.colorFormat,
                                      DirectTemporalReconstructor.depthFormat,
                                      DirectTemporalReconstructor.motionFormat].map {
                try texture($0, width, height, [.renderTarget, .shaderRead], .private)
            }
        }
        let targets = nativeTargets[key] ?? []
        guard let mrt = preset.temporalPipelineState,
              let cb = context.commandQueue.makeCommandBuffer() else { throw MFXProofError.noPipeline }
        let pass = MTLRenderPassDescriptor()
        for (index, tex) in targets.enumerated() {
            pass.colorAttachments[index].texture = tex
            pass.colorAttachments[index].loadAction = .clear
            pass.colorAttachments[index].storeAction = .store
        }
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { throw MFXProofError.gpu("enc") }
        var fv = Self.features(time: time, dt: dt)
        fv.treble = cameraMode
        var frame = DirectTemporalFrame()
        frame.renderSize = SIMD2(Float(width), Float(height))
        frame.outputSize = frame.renderSize
        pipeline.encodePresetVisualization(into: enc, activePipeline: mrt, features: &fv, stems: .zero,
                                           particles: nil, textOverlay: nil, temporalFrame: frame)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if cb.gpuEndTime > cb.gpuStartTime { gpuMs = (cb.gpuEndTime - cb.gpuStartTime) * 1000 }
        return targets[0]
    }

    /// Copy (bilinear when sizes differ) into an 8-bit sRGB texture of `width × height` — what
    /// `drawDirect` does to the drawable. `slot` keeps results that must coexist apart.
    func display(_ source: MTLTexture, slot: String, width: Int? = nil, height: Int? = nil) throws -> MTLTexture {
        let w = width ?? outW, h = height ?? outH
        let key = "\(slot)_\(w)x\(h)"
        if displayTextures[key] == nil {
            displayTextures[key] = try texture(context.pixelFormat, w, h, [.renderTarget, .shaderRead], .shared)
        }
        guard let target = displayTextures[key], let cb = context.commandQueue.makeCommandBuffer() else {
            throw MFXProofError.gpu("display")
        }
        pipeline.copy(source, to: target, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        return target
    }

    /// Display luma (sRGB-encoded, Rec.709) of an 8-bit sRGB texture, one Float per pixel.
    func luma(_ display: MTLTexture) throws -> [Float] {
        let w = display.width, h = display.height
        if lumaTexture?.width != w || lumaTexture?.height != h {
            lumaTexture = try texture(.r32Float, w, h, [.renderTarget, .shaderRead], .shared)
        }
        guard let out = lumaTexture, let cb = context.commandQueue.makeCommandBuffer() else {
            throw MFXProofError.gpu("luma")
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = out
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { throw MFXProofError.gpu("enc") }
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

    /// The anti-aliased reference: the scene at 2× per axis, box-filtered to `outW × outH` (the
    /// bilinear copy at exactly 2× samples each 2×2 block's centre — an equal-weight average).
    func supersampled(time: Float, dt: Float) throws -> MTLTexture {
        var unused: Double?
        let big = try renderPlain(time: time, dt: dt, width: 2 * outW, height: 2 * outH, gpuMs: &unused)
        return try display(big, slot: "supersampled")
    }

    /// Comparison column only (nothing ships it): MetalFX's SPATIAL scaler — single-frame,
    /// edge-adaptive — from `source` at its size to `outW × outH`.
    func spatial(_ source: MTLTexture) throws -> MTLTexture {
        if spatialScaler == nil {
            let desc = MTLFXSpatialScalerDescriptor()
            desc.inputWidth = source.width
            desc.inputHeight = source.height
            desc.outputWidth = outW
            desc.outputHeight = outH
            desc.colorTextureFormat = DirectTemporalReconstructor.colorFormat
            desc.outputTextureFormat = DirectTemporalReconstructor.outputFormat
            desc.colorProcessingMode = .linear
            guard let made = desc.makeSpatialScaler(device: context.device) else { throw MFXProofError.gpu("spatial") }
            spatialScaler = made
            spatialOutput = try texture(DirectTemporalReconstructor.outputFormat, outW, outH,
                                        made.outputTextureUsage.union(.shaderRead), .private)
        }
        guard let scaler = spatialScaler, let out = spatialOutput,
              let cb = context.commandQueue.makeCommandBuffer() else { throw MFXProofError.gpu("spatial") }
        scaler.colorTexture = source
        scaler.inputContentWidth = source.width
        scaler.inputContentHeight = source.height
        scaler.outputTexture = out
        scaler.encode(commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        return out
    }
    private var spatialScaler: MTLFXSpatialScaler?
    private var spatialOutput: MTLTexture?

    /// BGRA bytes of an 8-bit display texture (for PNGs).
    func bgra(_ display: MTLTexture) -> [UInt8] {
        let w = display.width, h = display.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        bytes.withUnsafeMutableBytes { ptr in
            display.getBytes(ptr.baseAddress!, bytesPerRow: w * 4,   // swiftlint:disable:this force_unwrapping
                             from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }
        return bytes
    }

    func texture(_ format: MTLPixelFormat, _ width: Int, _ height: Int, _ usage: MTLTextureUsage,
                 _ storage: MTLStorageMode) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height,
                                                            mipmapped: false)
        desc.usage = usage
        desc.storageMode = storage
        guard let tex = context.device.makeTexture(descriptor: desc) else { throw MFXProofError.gpu("texture") }
        return tex
    }

    static let lumaSource = """
    #include <metal_stdlib>
    using namespace metal;
    struct LV { float4 p [[position]]; };
    vertex LV mfx_luma_vertex(uint i [[vertex_id]]) {
        LV o; float2 uv = float2((i << 1) & 2, i & 2); o.p = float4(uv * 2.0 - 1.0, 0.0, 1.0); return o;
    }
    fragment float mfx_luma_fragment(LV in [[stage_in]], texture2d<float> t [[texture(0)]]) {
        float3 c = saturate(t.read(uint2(in.p.xy)).rgb);              // sRGB texture: reads linear
        float3 e = select(1.055 * pow(c, 1.0 / 2.4) - 0.055, 12.92 * c, c <= 0.0031308);
        return dot(e, float3(0.2126, 0.7152, 0.0722));
    }
    """
}
