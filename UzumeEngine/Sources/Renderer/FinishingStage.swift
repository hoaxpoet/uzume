// FinishingStage — the cinematic finish (VQ.1, Phase VQ). Shaders: FinishingStage.metal.
//
// On screen the order is fixed by Apple's MetalFX guidance (WWDC25 session 211): render →
// temporal upscale (MFX.2) → FINISH → frame interpolation (VQ.4a, not yet) → present. A
// `cinematic` scene draws linear HDR into `frameTarget` (`.rgba16Float`, render size); `encode`
// blooms it, applies the grade and the Lottes display transform, dithers in the encoded domain and
// writes the output — the drawable today, a budgeted finished image once an interpolator follows.
// The composite samples the frame target bilinearly at the OUTPUT's size, so on a capped (BR.6b)
// Mac the stretch to the drawable happens inside the finish and the dither lands on output pixels.
//
// `legacy` scenes never construct one: their finish is the identity hand-off in
// `RenderPipeline.instrumentedPresent`.
//
// Not thread-safe: built, sized and encoded on the render (main) thread, like the canvas.

import Foundation
import Metal
import os.log
import Shared

private let logger = Logger(subsystem: "io.uzume.renderer", category: "FinishingStage")

// MARK: - FinishUniforms

/// Mirrors `FinishUniforms` in FinishingStage.metal (64 bytes). Keep the two in step.
struct FinishUniforms {
    var bloomStrength: Float
    var bloomThreshold: Float
    var bloomKnee: Float
    var exposure: Float
    var contrast: Float
    var saturation: Float
    var headroom: Float
    var lottesA: Float
    var lottesD: Float
    var lottesB: Float
    var lottesC: Float
    var ditherLSB: Float
    var bloomLevels: Float
    var frame: UInt32
    var useLUT: UInt32
    var hdrOutput: UInt32
}

// MARK: - FinishingStage

/// The cinematic finish for one scene: owns its HDR frame target and bloom chain.
public final class FinishingStage: @unchecked Sendable {

    // MARK: Constants

    /// Height of the bloom chain's base level, in its own texels. Fixed whatever the frame size,
    /// so every bloom distance is a fraction of frame height (one base texel = 1/540 of it).
    public static let bloomBaseHeight = 540
    /// Chain levels: 540 → 270 → 135 → 68 → 34 → 17 px tall. The coarsest texel is ~6 % of the
    /// frame height at every resolution.
    public static let bloomLevelCount = 6
    /// Region cap grid (VQ.2): 6×6 cells, a ninth of the screen = 2×2 cells.
    static let regionCellsPerSide = 6
    static let regionCellCount = regionCellsPerSide * regionCellsPerSide

    /// Lottes 2016 curve parameters (the talk's defaults): contrast, shoulder, the scene value
    /// that maps to display peak, and the mid-grey anchor.
    public static let lottesContrast: Float = 1.6
    public static let lottesShoulder: Float = 0.977
    public static let lottesHDRMax: Float = 8.0
    public static let lottesMidIn: Float = 0.18
    public static let lottesMidOut: Float = 0.267

    // MARK: State

    /// The scene's finish settings.
    public let spec: FinishSpec
    /// Display peak over SDR white: 1.0 for SDR. On an HDR output (VQ.2) the pipeline sets it each
    /// frame from the display (`HDROutput.headroom`) for a scene whose `finish.hdr` is on.
    public var headroom: Float = 1
    /// The output is the linear float HDR drawable (VQ.2): light above SDR white is kept, capped
    /// per ninth of the screen at an average of SDR white (`finish_region_kernel`).
    public let hdrOutput: Bool
    /// Tests only: false drops the regional cap (the flash gate's negative control must fail).
    var regionCapEnabled = true
    /// One output code value in encoded units; 0 disables dither (tests measure the undithered
    /// image). 1/255 for the 8-bit drawable.
    public var ditherLSB: Float = 1.0 / 255.0
    /// The frame target a cinematic scene draws into (`.rgba16Float`, render size). Nil until sized.
    public private(set) var frameTarget: MTLTexture?
    /// The bloom chain, base first. Allocated on first use; follows the frame's aspect.
    public private(set) var bloomChain: [MTLTexture] = []

    private let device: MTLDevice
    private let budget: RenderTargetBudget?
    private let prefilterPipeline: MTLComputePipelineState
    private let downsamplePipeline: MTLComputePipelineState
    private let upsamplePipeline: MTLComputePipelineState
    private let compositePipeline: MTLRenderPipelineState
    private let regionPipeline: MTLComputePipelineState
    /// 6×6 region cells (FinishingStage.metal `kRegionCells`), written by the region kernel.
    private let regionCells: MTLBuffer
    private let sampler: MTLSamplerState
    private let lut: MTLTexture
    private let hasLUT: Bool
    private var frameIndex: UInt32 = 0

    // MARK: Init

    /// - Parameters:
    ///   - library: the renderer library (FinishingStage.metal + Common.metal).
    ///   - outputFormat: the format the finish writes — the drawable's (`HDROutput.drawableFormat`
    ///     on HDR, VQ.2).
    ///   - lut: the scene's 3D LUT (`FinishSpec.loadCubeLUT`), or nil.
    ///   - budget: VQ.0 render-target budget; nil allocates directly (tests).
    public init(device: MTLDevice, library: MTLLibrary, outputFormat: MTLPixelFormat,
                spec: FinishSpec, lut: MTLTexture? = nil, budget: RenderTargetBudget?) throws {
        self.device = device
        self.spec = spec
        self.budget = budget
        func kernel(_ name: String) throws -> MTLComputePipelineState {
            guard let function = library.makeFunction(name: name) else {
                throw ShaderLibraryError.functionNotFound(name)
            }
            return try device.makeComputePipelineState(function: function)
        }
        prefilterPipeline = try kernel("finish_prefilter_kernel")
        downsamplePipeline = try kernel("finish_downsample_kernel")
        upsamplePipeline = try kernel("finish_upsample_kernel")
        regionPipeline = try kernel("finish_region_kernel")
        hdrOutput = outputFormat == HDROutput.drawableFormat
        guard let cells = device.makeBuffer(length: Self.regionCellCount * MemoryLayout<SIMD2<Float>>.stride,
                                            options: .storageModeShared) else {
            throw MetalContextError.noDevice
        }
        regionCells = cells
        let desc = MTLRenderPipelineDescriptor()
        desc.label = "finish_composite"
        desc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        desc.fragmentFunction = library.makeFunction(name: "finish_composite_fragment")
        desc.colorAttachments[0].pixelFormat = outputFormat
        compositePipeline = try device.makeRenderPipelineState(descriptor: desc)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerDesc.rAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDesc) else {
            throw MetalContextError.noDevice
        }
        self.sampler = sampler

        if let lut {
            self.lut = lut
            hasLUT = true
        } else {
            // The composite always binds slot 2; a 1³ placeholder keeps validation quiet.
            let desc = MTLTextureDescriptor()
            desc.textureType = .type3D
            desc.pixelFormat = .rgba16Float
            desc.width = 1; desc.height = 1; desc.depth = 1
            guard let empty = device.makeTexture(descriptor: desc) else { throw MetalContextError.noDevice }
            self.lut = empty
            hasLUT = false
        }
    }

    // MARK: Sizing

    /// The HDR frame target at `width`×`height`, allocated (through the budget) or reused.
    /// Nil when the budget refuses it.
    @discardableResult
    public func ensureFrameTarget(width: Int, height: Int) -> MTLTexture? {
        if let target = frameTarget, target.width == width, target.height == height { return target }
        frameTarget = nil   // VQ.0: release before allocate
        let desc = Self.descriptor(width: width, height: height)
        frameTarget = allocate(desc, label: "finish frame target \(width)×\(height)")
        return frameTarget
    }

    /// Size the chain for a `width`×`height` source: base 540 px tall at the source's aspect.
    private func ensureBloomChain(width: Int, height: Int) -> Bool {
        let baseW = max(Int((Double(width) / Double(max(height, 1)) * Double(Self.bloomBaseHeight)).rounded()), 1)
        if bloomChain.first?.width == baseW { return true }
        bloomChain = []
        var levelW = baseW, levelH = Self.bloomBaseHeight
        for level in 0..<Self.bloomLevelCount {
            let label = "finish bloom L\(level) \(levelW)×\(levelH)"
            let desc = Self.descriptor(width: levelW, height: levelH)
            desc.usage = [.shaderRead, .shaderWrite]
            guard let tex = allocate(desc, label: label) else {
                bloomChain = []
                return false
            }
            bloomChain.append(tex)
            levelW = max((levelW + 1) / 2, 1)
            levelH = max((levelH + 1) / 2, 1)
        }
        return true
    }

    private static func descriptor(width: Int, height: Int) -> MTLTextureDescriptor {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: FinishSpec.cinematicFrameTargetFormat,
            width: max(width, 1),
            height: max(height, 1),
            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = RenderTargetBudget.storageMode()
        return desc
    }

    private func allocate(_ desc: MTLTextureDescriptor, label: String) -> MTLTexture? {
        let texture = budget.map { $0.makeTexture(owner: "finish", label: label, descriptor: desc) }
            ?? device.makeTexture(descriptor: desc)
        texture?.label = label
        if texture == nil { logger.error("Finishing stage: \(label) not allocated") }
        return texture
    }

    // MARK: Encode

    /// Finish `source` (linear HDR) into `output`. Bloom is skipped (not failed) if its chain
    /// cannot be allocated.
    public func encode(source: MTLTexture, output: MTLTexture, commandBuffer: MTLCommandBuffer) {
        var uniforms = makeUniforms()
        let bloomOn = spec.bloom.strength > 0 && ensureBloomChain(width: source.width, height: source.height)
        if bloomOn, let encoder = commandBuffer.makeComputeCommandEncoder() {
            // One serial encoder: each dispatch sees the previous one's writes.
            encoder.label = "finish bloom"
            encoder.setSamplerState(sampler, index: 0)
            encoder.setBytes(&uniforms, length: MemoryLayout<FinishUniforms>.stride, index: 0)
            dispatch(encoder, prefilterPipeline, source, into: bloomChain[0])
            for level in 1..<bloomChain.count {
                var karis: UInt32 = level == 1 ? 1 : 0   // Jimenez: Karis average on the first downsample
                encoder.setBytes(&karis, length: MemoryLayout<UInt32>.stride, index: 1)
                dispatch(encoder, downsamplePipeline, bloomChain[level - 1], into: bloomChain[level])
            }
            for level in stride(from: bloomChain.count - 2, through: 0, by: -1) {
                dispatch(encoder, upsamplePipeline, bloomChain[level + 1], into: bloomChain[level])
            }
            encoder.endEncoding()
        } else {
            uniforms.bloomStrength = 0
        }
        let bloom = bloomOn ? bloomChain[0] : source
        if uniforms.hdrOutput == 1, let encoder = commandBuffer.makeComputeCommandEncoder() {
            // VQ.2: the region cells the composite caps against, after the bloom it includes.
            encoder.label = "finish region cap"
            encoder.setComputePipelineState(regionPipeline)
            encoder.setBytes(&uniforms, length: MemoryLayout<FinishUniforms>.stride, index: 0)
            encoder.setBuffer(regionCells, offset: 0, index: 1)
            encoder.setTexture(source, index: 0)
            encoder.setTexture(bloom, index: 1)
            encoder.setSamplerState(sampler, index: 0)
            let side = Self.regionCellsPerSide
            encoder.dispatchThreadgroups(MTLSize(width: side, height: side, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            encoder.endEncoding()
        }
        run(commandBuffer, into: output, compositePipeline, [source, bloom, lut], &uniforms)
        frameIndex &+= 1
    }

    private func dispatch(_ encoder: MTLComputeCommandEncoder, _ pipeline: MTLComputePipelineState,
                          _ source: MTLTexture, into target: MTLTexture) {
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(target, index: 1)
        let group = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(MTLSize(width: target.width, height: target.height, depth: 1),
                                threadsPerThreadgroup: group)
    }

    private func run(_ commandBuffer: MTLCommandBuffer, into target: MTLTexture,
                     _ pipeline: MTLRenderPipelineState, _ textures: [MTLTexture],
                     _ uniforms: UnsafeMutablePointer<FinishUniforms>) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.label = pipeline.label
        encoder.setRenderPipelineState(pipeline)
        for (index, texture) in textures.enumerated() {
            encoder.setFragmentTexture(texture, index: index)
        }
        encoder.setFragmentBytes(uniforms, length: MemoryLayout<FinishUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(regionCells, offset: 0, index: 1)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    func makeUniforms() -> FinishUniforms {
        let curve = Self.lottesCoefficients(headroom: headroom)
        return FinishUniforms(
            bloomStrength: spec.bloom.strength,
            bloomThreshold: spec.bloom.threshold,
            bloomKnee: spec.bloom.knee,
            exposure: exp2(spec.grade.exposure),
            contrast: spec.grade.contrast,
            saturation: spec.grade.saturation,
            headroom: headroom,
            lottesA: Self.lottesContrast,
            lottesD: Self.lottesShoulder,
            lottesB: curve.b,
            lottesC: curve.c,
            ditherLSB: ditherLSB,
            bloomLevels: Float(Self.bloomLevelCount),
            frame: frameIndex,
            useLUT: hasLUT ? 1 : 0,
            hdrOutput: hdrOutput && headroom > 1 ? (regionCapEnabled ? 1 : 2) : 0)
    }

    // MARK: Display transform

    // swiftlint:disable identifier_name
    // a, b, c, d are the paper's names for the curve's coefficients.

    /// Lottes 2016 `b`, `c` for `y = xᵃ / (xᵃᵈ·b + c)`, solved so `y(midIn) = midOut / headroom`
    /// and `y(hdrMax) = 1`; the shader scales by `headroom`, so mid-grey holds still while the
    /// peak follows the display.
    public static func lottesCoefficients(headroom: Float) -> (b: Float, c: Float) {
        let a = lottesContrast, d = lottesShoulder, hdrMax = lottesHDRMax, midIn = lottesMidIn
        let midOut = lottesMidOut / max(headroom, 1)
        let ad = a * d
        let denom = (pow(hdrMax, ad) - pow(midIn, ad)) * midOut
        let b = (-pow(midIn, a) + pow(hdrMax, a) * midOut) / denom
        let c = (pow(hdrMax, ad) * pow(midIn, a) - pow(hdrMax, a) * pow(midIn, ad) * midOut) / denom
        return (b, c)
    }
    // swiftlint:enable identifier_name

    /// The display transform on the CPU, for tests: scene value → display value.
    public static func displayTransform(_ x: Float, headroom: Float = 1) -> Float {
        let curve = lottesCoefficients(headroom: headroom)
        let z = pow(max(x, 0), lottesContrast)
        return headroom * z / (pow(z, lottesShoulder) * curve.b + curve.c)
    }
}
