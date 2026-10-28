// SpatialUpscaler — MetalFX spatial upscaling into a budgeted output texture (VQ.3).
//
// The `spatial` option at every stretch (`UpscaleMode`): one frame in, one larger frame out, edge-
// adaptive, no history and no motion vectors — so it works for any scene. The output is a texture
// this class owns, never the drawable (the present step or the finish reads it).
//
// Colour processing follows the input's encoding: `perceptual` for the 8-bit sRGB frame target
// (the canvas a legacy scene draws), `hdr` for a linear `.rgba16Float` input (a cinematic frame
// target, a ray-march lit image). MetalFX does not mix sRGB and non-sRGB, so the output keeps the
// input's format.
//
// VQ.0: the scaler is opaque — what creating it allocated (`currentAllocatedSize` delta) is charged
// to the budget as a reservation, and the output texture is a budgeted target. `release()` (scene
// switch, resize) drops both.
//
// Not thread-safe: built and encoded on the render (main) thread, like the canvas.

import Foundation
import Metal
import MetalFX
import os.log
import Shared

private let logger = Logger(subsystem: "io.uzume.renderer", category: "SpatialUpscaler")

// MARK: - SpatialUpscaler

/// MetalFX spatial upscaling from one input size and format to one output size, rebuilt when either
/// changes.
public final class SpatialUpscaler {

    private struct Shape: Equatable {
        let inW: Int, inH: Int, outW: Int, outH: Int
        let format: MTLPixelFormat
    }

    private let device: MTLDevice
    private let budget: RenderTargetBudget?
    private var scaler: MTLFXSpatialScaler?
    private var output: MTLTexture?
    private var shape: Shape?
    /// The shape the budget (or Metal) last declined — not retried every frame.
    private var failedShape: Shape?
    /// Unique per instance, so a successor's charge is never dropped by this deinit.
    private lazy var reservationName = "mfx spatial \(ObjectIdentifier(self).hashValue)"

    /// Diagnostics: frames upscaled.
    public private(set) var encodeCount = 0

    /// - Parameter budget: nil (offline tests) allocates directly.
    public init(device: MTLDevice, budget: RenderTargetBudget?) {
        self.device = device
        self.budget = budget
    }

    deinit {
        budget?.releaseReservation(reservationName)
    }

    /// True when this device has the MetalFX spatial scaler.
    public static func isSupported(device: MTLDevice) -> Bool {
        MTLFXSpatialScalerDescriptor.supportsDevice(device)
    }

    /// Perceptual for an encoded (sRGB) input, HDR for a linear float one.
    public static func colorProcessingMode(for format: MTLPixelFormat) -> MTLFXSpatialScalerColorProcessingMode {
        format == .rgba16Float ? .hdr : .perceptual
    }

    /// Upscale `source` to `outputWidth × outputHeight`. Nil when the device has no MetalFX or the
    /// budget refused the scaler — the caller stretches instead.
    public func encode(_ source: MTLTexture, outputWidth: Int, outputHeight: Int,
                       commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        let wanted = Shape(inW: source.width,
                           inH: source.height,
                           outW: outputWidth,
                           outH: outputHeight,
                           format: source.pixelFormat)
        guard prepare(wanted), let scaler, let output else { return nil }
        scaler.colorTexture = source
        scaler.inputContentWidth = source.width
        scaler.inputContentHeight = source.height
        scaler.outputTexture = output
        scaler.encode(commandBuffer: commandBuffer)
        encodeCount += 1
        return output
    }

    /// Drop the scaler, its reservation and its output (VQ.0: switch away / resize release step —
    /// call only once the frames in flight have drained).
    public func release() {
        scaler = nil
        output = nil
        shape = nil
        failedShape = nil
        budget?.releaseReservation(reservationName)
    }

    // MARK: Allocation

    private func prepare(_ wanted: Shape) -> Bool {
        if wanted == shape, scaler != nil, output != nil { return true }
        if wanted == failedShape { return false }
        release()   // VQ.0: release before allocate
        guard Self.isSupported(device: device) else { return fail(wanted, "no MetalFX spatial scaler") }
        let desc = MTLFXSpatialScalerDescriptor()
        desc.inputWidth = wanted.inW
        desc.inputHeight = wanted.inH
        desc.outputWidth = wanted.outW
        desc.outputHeight = wanted.outH
        desc.colorTextureFormat = wanted.format
        desc.outputTextureFormat = wanted.format
        desc.colorProcessingMode = Self.colorProcessingMode(for: wanted.format)
        let before = device.currentAllocatedSize
        guard let made = desc.makeSpatialScaler(device: device) else { return fail(wanted, "creation failed") }
        let delta = max(device.currentAllocatedSize - before, 0)
        if let budget, !budget.reserve(reservationName, bytes: delta) { return fail(wanted, "budget refused") }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: wanted.format, width: wanted.outW, height: wanted.outH, mipmapped: false)
        outDesc.usage = made.outputTextureUsage.union(.shaderRead)
        outDesc.storageMode = .private
        let label = "MetalFX spatial output \(wanted.outW)×\(wanted.outH)"
        let texture = budget.map { $0.makeTexture(owner: "spatialUpscale", label: label, descriptor: outDesc) }
            ?? device.makeTexture(descriptor: outDesc)
        guard let texture else { return fail(wanted, "output refused") }
        texture.label = label
        scaler = made
        output = texture
        shape = wanted
        logger.info("""
            MetalFX spatial \(wanted.inW)×\(wanted.inH) → \(wanted.outW)×\(wanted.outH) \
            (\(wanted.format == .rgba16Float ? "hdr" : "perceptual")): scaler +\(delta) B
            """)
        return true
    }

    private func fail(_ wanted: Shape, _ reason: String) -> Bool {
        release()
        failedShape = wanted
        logger.error("MetalFX spatial \(wanted.inW)×\(wanted.inH) → \(wanted.outW)×\(wanted.outH): \(reason)")
        return false
    }
}
