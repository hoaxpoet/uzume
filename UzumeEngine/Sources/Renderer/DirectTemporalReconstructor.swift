// DirectTemporalReconstructor — MetalFX temporal reconstruction for the `direct` path (MFX.2).
//
// A direct scene that declares `temporal_reconstruction` renders at `internal_scale × drawable`
// into colour + depth + motion (MRT, see the preamble's `TemporalFrame` / `TemporalFragmentOut`),
// with a Halton(2,3) sub-pixel jitter per frame. The temporal scaler accumulates those jittered
// frames into a drawable-sized image: real sub-pixel detail rebuilt from history, unlike the NB.8
// bilinear stretch which only interpolates the pixels it has. (Frame interpolation, MFX.2 task 5,
// was skipped under VQ amendment A5: it needs a present clock; it lands with VQ.4a.)
//
// Prior art: MFX.1's `MetalFXTemporalUpscaler` (ray-march G-buffer path, deleted at D-213 with no
// consumer). This is its direct-path sibling; Energetic Flyby (EFB.4) is the named consumer.
// VQ.3: the ray-march path reuses it in external-input mode (`RayMarchTemporal` owns the lit colour,
// depth, motion and reactive targets; this owns only the scaler and its output).
//
// Conventions (all checked by `DirectTemporalReconstructionTests`, not assumed):
//   • jitter is in render pixels, +x right, +y down; the scene samples at `position.xy + jitter`;
//   • motion is in render pixels: previous position − current position (MetalFX's convention);
//   • depth is Metal NDC, 0 = near, 1 = background (not reversed).

import Foundation
import Metal
import MetalFX
import os
import simd
import Shared

private let logger = Logger(subsystem: "io.uzume.renderer", category: "DirectTemporalReconstructor")

// MARK: - DirectTemporalFrame

/// Per-frame values the reconstruct path binds at fragment `buffer(9)`. Mirrors MSL `TemporalFrame`
/// in the preamble (32 bytes). Every other direct draw binds it zeroed.
public struct DirectTemporalFrame: Sendable, Equatable {
    /// Sub-pixel offset in render pixels (+x right, +y down), each component in −0.5…0.5.
    public var jitter: SIMD2<Float> = .zero
    /// Internal render size, pixels.
    public var renderSize: SIMD2<Float> = .zero
    /// Reconstructed (drawable) size, pixels.
    public var outputSize: SIMD2<Float> = .zero
    /// Frames since the last history reset.
    public var frameIndex: UInt32 = 0
    /// 1 on a frame whose history was discarded.
    public var reset: UInt32 = 0

    public init() {}
}

// MARK: - DirectTemporalReconstructor

/// Owns the MetalFX temporal scaler for one opted-in direct scene, plus the internal render
/// targets, the scaler's output texture and the jitter sequence.
public final class DirectTemporalReconstructor {

    public static let colorFormat = TemporalReconstructionSpec.colorFormat
    public static let depthFormat = TemporalReconstructionSpec.depthFormat
    public static let motionFormat = TemporalReconstructionSpec.motionFormat
    public static let reactiveFormat = TemporalReconstructionSpec.reactiveFormat
    public static let outputFormat: MTLPixelFormat = .rgba16Float

    /// Jitter cycle length. Apple's guidance is ≥ 8 × (output/input)² phases; 32 covers a 2× upscale.
    static let jitterPhases: UInt32 = 32

    /// The internal (render-size) targets the scene's MRT fragment writes.
    public struct Targets {
        public let color: MTLTexture
        public let depth: MTLTexture
        public let motion: MTLTexture
        public let reactive: MTLTexture?
    }

    public let spec: TemporalReconstructionSpec
    private let device: MTLDevice

    public private(set) var targets: Targets?
    /// The scaler's output: drawable-sized, never the drawable itself (A2).
    private var output: MTLTexture?
    private var scaler: MTLFXTemporalScaler?

    /// The budget declined the last scaler's reservation (a refusal, unlike a Metal failure, fails `prepare`).
    private var scalerRefused = false
    private var frameIndex: UInt32 = 0
    private var needsReset = true

    public private(set) var outputWidth = 0
    public private(set) var outputHeight = 0
    public private(set) var renderWidth = 0
    public private(set) var renderHeight = 0

    /// Diagnostics: a healthy run resets once per preset switch or cut, not per frame.
    public private(set) var encodeCount = 0
    public private(set) var resetCount = 0

    /// VQ.0: the targets are budgeted and the scaler is charged as an opaque reservation. Nil (offline
    /// tests that build a reconstructor alone) allocates directly.
    private let budget: RenderTargetBudget?
    /// This instance's scaler reservation (unique, so a successor's charge is never dropped by this deinit).
    private lazy var reservationName = "mfx2 scaler \(ObjectIdentifier(self).hashValue)"

    /// VQ.3: true when the caller owns the input targets and passes them to `encodeUpscale(…inputs:)`.
    public let externalInputs: Bool

    /// VQ.3 test hook: false hands MetalFX (and the scene) zero jitter every frame.
    public var jitterEnabled = true

    public init(device: MTLDevice, spec: TemporalReconstructionSpec, budget: RenderTargetBudget? = nil,
                externalInputs: Bool = false) {
        self.device = device
        self.spec = spec
        self.budget = budget
        self.externalInputs = externalInputs
    }

    deinit {
        budget?.releaseReservation(reservationName)
    }

    /// True when this device has the MetalFX temporal scaler.
    public static func isSupported(device: MTLDevice) -> Bool {
        MTLFXTemporalScalerDescriptor.supportsDevice(device)
    }

    /// The output ÷ input ratios this device's temporal scaler accepts (M2 Pro, macOS 26: 1…3).
    public static func supportedScaleRange(device: MTLDevice) -> ClosedRange<Float> {
        MTLFXTemporalScalerDescriptor.supportedInputContentMinScale(device: device)
            ... MTLFXTemporalScalerDescriptor.supportedInputContentMaxScale(device: device)
    }

    /// True while MetalFX itself reconstructs (false: no MetalFX, or the last `prepare` failed).
    public var isTemporal: Bool { scaler != nil && output != nil }

    /// Discard the history: preset switch, a cut, any jump reprojection cannot explain.
    public func reset() {
        needsReset = true
        frameIndex = 0
    }

    // MARK: Jitter

    /// Radical-inverse base-`base` Halton term.
    static func halton(_ index: UInt32, _ base: UInt32) -> Float {
        var result: Float = 0
        var fraction: Float = 1
        var i = index
        while i > 0 {
            fraction /= Float(base)
            result += fraction * Float(i % base)
            i /= base
        }
        return result
    }

    /// This frame's jitter in render pixels, −0.5…0.5. Indexed from 1 so frame 0 is not (−0.5, −0.5).
    public var jitter: SIMD2<Float> {
        guard jitterEnabled else { return .zero }
        let i = frameIndex % Self.jitterPhases + 1
        return SIMD2(Self.halton(i, 2) - 0.5, Self.halton(i, 3) - 0.5)
    }

    /// The `buffer(9)` values for this frame.
    public var frameUniforms: DirectTemporalFrame {
        var frame = DirectTemporalFrame()
        frame.jitter = jitter
        frame.renderSize = SIMD2(Float(renderWidth), Float(renderHeight))
        frame.outputSize = SIMD2(Float(outputWidth), Float(outputHeight))
        frame.frameIndex = frameIndex
        frame.reset = needsReset ? 1 : 0
        return frame
    }

    // MARK: Allocation

    /// (Re)allocate for a drawable size. Cheap when nothing changed; a change rebuilds the scaler
    /// and resets the history. Call on preset apply (so the first frame does not allocate) and
    /// per frame (covers resizes).
    @discardableResult
    public func prepare(outputWidth: Int, outputHeight: Int) -> Bool {
        let outW = max(outputWidth, 1), outH = max(outputHeight, 1)
        return prepare(inputWidth: max(Int((Float(outW) * spec.internalScale).rounded()), 1),
                       inputHeight: max(Int((Float(outH) * spec.internalScale).rounded()), 1),
                       outputWidth: outW,
                       outputHeight: outH)
    }

    /// (Re)allocate for an explicit input (render) size — the ray-march path's march size (VQ.3).
    /// False when the ratio is outside what this device's scaler accepts, or the budget refused.
    @discardableResult
    public func prepare(inputWidth: Int, inputHeight: Int, outputWidth: Int, outputHeight: Int) -> Bool {
        let outW = max(outputWidth, 1), outH = max(outputHeight, 1)
        let inW = max(inputWidth, 1), inH = max(inputHeight, 1)
        let prepared = externalInputs ? output != nil : targets != nil
        if prepared, outW == self.outputWidth, outH == self.outputHeight,
           inW == renderWidth, inH == renderHeight { return true }
        let ratio = max(Float(outW) / Float(inW), Float(outH) / Float(inH))
        if Self.isSupported(device: device), !Self.supportedScaleRange(device: device).contains(ratio) {
            logger.error("MetalFX temporal cannot upscale \(inW)×\(inH) → \(outW)×\(outH) (\(ratio)×)")
            return fail(outW, outH)
        }

        // VQ.0: release the old set (targets, output, scaler and its reservation) before allocating.
        targets = nil
        output = nil
        scaler = nil
        budget?.releaseReservation(reservationName)
        scalerRefused = false
        scaler = makeScaler(inW: inW, inH: inH, outW: outW, outH: outH)
        if scalerRefused { return fail(outW, outH) }

        let renderUsage: MTLTextureUsage = [.renderTarget, .shaderRead]
        typealias Request = RenderTargetBudget.Request
        func internalTarget(_ format: MTLPixelFormat, _ usage: MTLTextureUsage?, _ name: String) -> Request {
            let desc = descriptor(format, inW, inH, renderUsage.union(usage ?? []))
            return .init(desc, label: "MFX.2 \(name) \(inW)×\(inH)")
        }
        var requests: [Request] = []
        if !externalInputs {
            requests = [internalTarget(Self.colorFormat, scaler?.colorTextureUsage, "colour"),
                        internalTarget(Self.depthFormat, scaler?.depthTextureUsage, "depth"),
                        internalTarget(Self.motionFormat, scaler?.motionTextureUsage, "motion")]
        }
        if spec.reactiveMask, !externalInputs {
            requests.append(internalTarget(Self.reactiveFormat, scaler?.reactiveTextureUsage, "reactive"))
        }
        if let scaler {
            let usage = scaler.outputTextureUsage.union(.shaderRead)
            let desc = descriptor(Self.outputFormat, outW, outH, usage)
            requests.append(.init(desc, label: "MFX.2 output \(outW)×\(outH)"))
        }
        guard let made = makeTextures(requests) else { return fail(outW, outH) }
        output = scaler == nil ? nil : made.last
        if !externalInputs {
            let reactive = spec.reactiveMask ? made[3] : nil
            targets = Targets(color: made[0], depth: made[1], motion: made[2], reactive: reactive)
        } else if scaler == nil {
            return fail(outW, outH)   // nothing to reconstruct with: the caller takes its normal path
        }
        self.outputWidth = outW
        self.outputHeight = outH
        renderWidth = inW
        renderHeight = inH
        reset()
        let mode = scaler == nil ? "bilinear fallback (no MetalFX)" : "temporal"
        logger.info("MFX.2 reconstruct \(inW)×\(inH) → \(outW)×\(outH), \(mode)")
        return true
    }

    /// Drop every target, the scaler and its reservation; the next `prepare` reallocates (VQ.0 resize
    /// release step — call only once the frames in flight have drained).
    public func releaseTargets() {
        targets = nil
        output = nil
        scaler = nil
        budget?.releaseReservation(reservationName)
    }

    private func fail(_ outW: Int, _ outH: Int) -> Bool {
        logger.error("MFX.2 target allocation failed at \(outW)×\(outH)")
        targets = nil
        scaler = nil
        output = nil
        budget?.releaseReservation(reservationName)
        return false
    }

    private func descriptor(_ format: MTLPixelFormat, _ width: Int, _ height: Int,
                            _ usage: MTLTextureUsage) -> MTLTextureDescriptor {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = usage
        desc.storageMode = .private
        return desc
    }

    /// Through the budget when there is one (all or nothing), else directly.
    private func makeTextures(_ requests: [RenderTargetBudget.Request]) -> [MTLTexture]? {
        if let budget { return budget.makeTextures(owner: "mfx2", requests) }
        var made: [MTLTexture] = []
        for request in requests {
            guard let texture = device.makeTexture(descriptor: request.descriptor) else { return nil }
            texture.label = request.label
            made.append(texture)
        }
        return made
    }

    private func makeScaler(inW: Int, inH: Int, outW: Int, outH: Int) -> MTLFXTemporalScaler? {
        guard Self.isSupported(device: device) else { return nil }
        let desc = MTLFXTemporalScalerDescriptor()
        desc.inputWidth = inW
        desc.inputHeight = inH
        desc.outputWidth = outW
        desc.outputHeight = outH
        desc.colorTextureFormat = Self.colorFormat
        desc.depthTextureFormat = Self.depthFormat
        desc.motionTextureFormat = Self.motionFormat
        desc.outputTextureFormat = Self.outputFormat
        if spec.reactiveMask {
            desc.isReactiveMaskTextureEnabled = true
            desc.reactiveMaskTextureFormat = Self.reactiveFormat
        }
        // VQ.0: the scaler is opaque — charge what creating it allocated, as a reservation.
        let before = device.currentAllocatedSize
        guard let made = desc.makeTemporalScaler(device: device) else {
            logger.error("MTLFXTemporalScaler creation failed at \(inW)×\(inH) → \(outW)×\(outH)")
            return nil
        }
        let delta = max(device.currentAllocatedSize - before, 0)
        logger.info("MFX.2 MTLFXTemporalScaler \(inW)×\(inH) → \(outW)×\(outH): currentAllocatedSize +\(delta) B")
        if let budget, !budget.reserve(reservationName, bytes: delta) {
            scalerRefused = true
            return nil
        }
        made.isDepthReversed = false
        return made
    }

    // MARK: Encode

    /// Reconstruct this frame from `targets` into a drawable-sized texture. Returns nil when the
    /// device has no MetalFX (the caller stretches `targets.color` instead).
    public func encodeUpscale(commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let targets else { return nil }
        return encodeUpscale(commandBuffer: commandBuffer, inputs: targets)
    }

    /// Reconstruct from caller-owned inputs (VQ.3, external-input mode), each `renderWidth × renderHeight`.
    public func encodeUpscale(commandBuffer: MTLCommandBuffer, inputs targets: Targets) -> MTLTexture? {
        guard let scaler, let output else { return nil }
        scaler.colorTexture = targets.color
        scaler.depthTexture = targets.depth
        scaler.motionTexture = targets.motion
        scaler.reactiveMaskTexture = targets.reactive
        scaler.outputTexture = output
        scaler.inputContentWidth = renderWidth
        scaler.inputContentHeight = renderHeight
        scaler.motionVectorScaleX = 1   // render pixels; measured best of 0.67 / 1 / 1.5 / axis flips
        scaler.motionVectorScaleY = 1
        let jit = jitter
        scaler.jitterOffsetX = jitterSign * jit.x
        scaler.jitterOffsetY = jitterSign * jit.y
        scaler.reset = needsReset
        if needsReset { resetCount += 1 }
        encodeCount += 1
        scaler.encode(commandBuffer: commandBuffer)
        return output
    }

    /// Sign applied to the scene's jitter when handing it to MetalFX. Measured, not assumed: see
    /// `DirectTemporalReconstructionTests.jitterConvention` (the only writer besides this default).
    var jitterSign: Float = -1

    /// Advance to the next frame (next jitter phase). Once per rendered frame.
    public func advance() {
        frameIndex &+= 1
        needsReset = false
    }
}
