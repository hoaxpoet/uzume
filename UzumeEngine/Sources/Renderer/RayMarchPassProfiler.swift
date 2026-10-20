// RayMarchPassProfiler — GPU timestamp-counter timing for the deferred render path.
//
// Command-buffer gpuStartTime/gpuEndTime includes queue/display effects and cannot
// attribute work to individual encoders. Timestamp counter samples bracket the
// G-buffer, lighting, and post-process encoder groups on the GPU itself.

import Foundation
@preconcurrency import Metal
import os.log

private let profilerLogger = Logger(subsystem: "io.uzume.renderer", category: "RayMarchPassProfiler")

/// GPU execution time for the three logical sections of a ray-march frame.
public struct RayMarchPassTimings: Sendable, Equatable {
    public let gbufferMs: Float
    public let lightingMs: Float
    public let postProcessMs: Float

    public init(gbufferMs: Float, lightingMs: Float, postProcessMs: Float) {
        self.gbufferMs = gbufferMs
        self.lightingMs = lightingMs
        self.postProcessMs = postProcessMs
    }
}

/// One timestamp-sample window within a frame.
struct GPUPassSampleWindow: @unchecked Sendable {
    let sampleBuffer: any MTLCounterSampleBuffer
    let startIndex: Int
    let endIndex: Int

    func begin(on encoder: any MTLRenderCommandEncoder) {
        encoder.sampleCounters(sampleBuffer: sampleBuffer, sampleIndex: startIndex, barrier: true)
    }

    func end(on encoder: any MTLRenderCommandEncoder) {
        encoder.sampleCounters(sampleBuffer: sampleBuffer, sampleIndex: endIndex, barrier: true)
    }
}

/// Triple-buffered timestamp-counter sampler. A frame owns six samples:
/// G-buffer start/end, lighting start/end, and post-process start/end.
final class RayMarchPassProfiler: @unchecked Sendable {
    struct Frame: @unchecked Sendable {
        let sampleBuffer: any MTLCounterSampleBuffer
        let sampleRange: Range<Int>

        var gbuffer: GPUPassSampleWindow { window(offset: 0) }
        var lighting: GPUPassSampleWindow { window(offset: 2) }
        var postProcess: GPUPassSampleWindow { window(offset: 4) }

        private func window(offset: Int) -> GPUPassSampleWindow {
            GPUPassSampleWindow(
                sampleBuffer: sampleBuffer,
                startIndex: sampleRange.lowerBound + offset,
                endIndex: sampleRange.lowerBound + offset + 1
            )
        }
    }

    static let samplesPerFrame = 6
    static let framesInFlight = 3

    private let sampleBuffer: any MTLCounterSampleBuffer
    private var nextSlot = 0

    init?(device: MTLDevice) {
        guard device.supportsCounterSampling(.atDrawBoundary),
              let timestampSet = device.counterSets?.first(where: {
                  $0.name == MTLCommonCounterSet.timestamp.rawValue
              }) else {
            profilerLogger.info("GPU timestamp counters unavailable; ray-march pass timing disabled")
            return nil
        }

        let descriptor = MTLCounterSampleBufferDescriptor()
        descriptor.counterSet = timestampSet
        descriptor.label = "Uzume ray-march pass timestamps"
        descriptor.storageMode = .shared
        descriptor.sampleCount = Self.samplesPerFrame * Self.framesInFlight

        do {
            sampleBuffer = try device.makeCounterSampleBuffer(descriptor: descriptor)
        } catch {
            profilerLogger.error("GPU timestamp buffer creation failed: \(error.localizedDescription)")
            return nil
        }
    }

    func beginFrame() -> Frame {
        let base = nextSlot * Self.samplesPerFrame
        nextSlot = (nextSlot + 1) % Self.framesInFlight
        return Frame(sampleBuffer: sampleBuffer, sampleRange: base..<(base + Self.samplesPerFrame))
    }

    func resolve(
        _ frame: Frame,
        after commandBuffer: MTLCommandBuffer,
        handler: @escaping @Sendable (RayMarchPassTimings) -> Void
    ) {
        commandBuffer.addCompletedHandler { _ in
            do {
                guard let data = try frame.sampleBuffer.resolveCounterRange(frame.sampleRange),
                      let timings = Self.timings(from: data) else { return }
                handler(timings)
            } catch {
                profilerLogger.error("GPU timestamp resolve failed: \(error.localizedDescription)")
            }
        }
    }

    /// Timestamp counter results are nanoseconds on Apple GPUs. Six UInt64 values are
    /// emitted in start/end pairs for the three pass groups.
    static func timings(from data: Data) -> RayMarchPassTimings? {
        let requiredBytes = samplesPerFrame * MemoryLayout<MTLCounterResultTimestamp>.stride
        guard data.count >= requiredBytes else { return nil }

        return data.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: MTLCounterResultTimestamp.self)
            guard values.count >= samplesPerFrame else { return nil }

            func milliseconds(start: Int, end: Int) -> Float? {
                let startValue = values[start].timestamp
                let endValue = values[end].timestamp
                guard startValue != MTLCounterErrorValue,
                      endValue != MTLCounterErrorValue,
                      endValue >= startValue else { return nil }
                return Float(Double(endValue - startValue) / 1_000_000.0)
            }

            guard let gbuffer = milliseconds(start: 0, end: 1),
                  let lighting = milliseconds(start: 2, end: 3),
                  let post = milliseconds(start: 4, end: 5) else { return nil }
            return RayMarchPassTimings(
                gbufferMs: gbuffer,
                lightingMs: lighting,
                postProcessMs: post
            )
        }
    }
}
