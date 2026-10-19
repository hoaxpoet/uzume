import Foundation
import Metal
import Testing
@testable import Renderer

@Suite("Ray-march GPU pass timing")
struct RayMarchPassProfilerTests {
    private final class TimingBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: RayMarchPassTimings?

        var value: RayMarchPassTimings? { lock.withLock { stored } }
        func set(_ value: RayMarchPassTimings) { lock.withLock { stored = value } }
    }

    @Test("decodes timestamp-counter pairs as milliseconds")
    func decodesTimestampPairs() {
        let timestamps: [UInt64] = [
            1_000_000, 3_500_000,
            4_000_000, 5_250_000,
            8_000_000, 8_750_000
        ]
        let data = timestamps.withUnsafeBytes { Data($0) }

        let timings = RayMarchPassProfiler.timings(from: data)

        #expect(timings == RayMarchPassTimings(
            gbufferMs: 2.5,
            lightingMs: 1.25,
            postProcessMs: 0.75
        ))
    }

    @Test("rejects incomplete or invalid counter samples")
    func rejectsInvalidSamples() {
        let incomplete = [UInt64](repeating: 0, count: 5).withUnsafeBytes { Data($0) }
        #expect(RayMarchPassProfiler.timings(from: incomplete) == nil)

        let invalid: [UInt64] = [
            1, MTLCounterErrorValue,
            4, 3,
            5, 6
        ]
        let invalidData = invalid.withUnsafeBytes { Data($0) }
        #expect(RayMarchPassProfiler.timings(from: invalidData) == nil)
    }

    @Test("resolves real Apple-GPU draw-boundary counters when available")
    func resolvesHardwareCounters() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let profiler = RayMarchPassProfiler(device: device),
              let queue = device.makeCommandQueue(),
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: 4,
            height: 4,
            mipmapped: false
        )
        textureDescriptor.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else { return }

        let frame = profiler.beginFrame()
        for window in [frame.gbuffer, frame.lighting, frame.postProcess] {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            window.begin(on: encoder)
            window.end(on: encoder)
            encoder.endEncoding()
        }

        let box = TimingBox()
        let completed = DispatchSemaphore(value: 0)
        profiler.resolve(frame, after: commandBuffer) { timings in
            box.set(timings)
            completed.signal()
        }
        commandBuffer.commit()

        #expect(completed.wait(timeout: .now() + 5) == .success)
        #expect(box.value != nil)
        #expect((box.value?.gbufferMs ?? -1) >= 0)
        #expect((box.value?.lightingMs ?? -1) >= 0)
        #expect((box.value?.postProcessMs ?? -1) >= 0)
    }
}
