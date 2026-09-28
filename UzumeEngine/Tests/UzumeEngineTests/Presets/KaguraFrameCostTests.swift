// KaguraFrameCostTests — Kagura's per-frame cost on the production path (KAG.3; opt-in).
//
// `KAGURA_PERF=1`: 1920×1080, `KaguraDancer.update` → `.render` into a private drawable-format target, NO
// readback, the dance chosen by the song on love_rehab's clock, grid and `bass_att`. Reports the GPU time
// of each frame's command buffer (`gpuEndTime − gpuStartTime`) and the CPU time of `update` (the
// choreographer, selection and encoding). A cost means nothing without its build configuration (CLAUDE.md):
//
//   KAGURA_PERF=1 swift test -c release --enable-testable-imports --package-path UzumeEngine --filter KaguraFrameCost

import Foundation
import Metal
import Testing
@testable import Renderer
@testable import Shared

@Suite("Kagura frame cost (KAG.3, opt-in)", .serialized)
struct KaguraFrameCostTests {

    @Test("GPU and CPU cost per frame at 1080p")
    func frameCost() throws {
        guard ProcessInfo.processInfo.environment["KAGURA_PERF"] == "1" else { return }
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        let fixture = try KaguraFixture.load("love_rehab")
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let dancer = try KaguraDancer(device: ctx.device, library: lib.library, pixelFormat: ctx.pixelFormat)
        dancer.ensureAllocated(width: 1920, height: 1080)
        dancer.setGrid(try fixture.grid(), streaming: false)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: 1920, height: 1080, mipmapped: false)
        desc.usage = [.renderTarget]
        desc.storageMode = .private
        let target = try #require(ctx.device.makeTexture(descriptor: desc))
        var gpu: [Double] = [], cpu: [Double] = []
        let fps = 60.0
        for index in 0..<Int(fixture.duration * fps) {
            let time = Double(index) / fps
            var features = FeatureVector()
            features.time = Float(time)
            features.deltaTime = Float(1 / fps)
            features.bassAtt = Float(fixture.bass(at: time))
            let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
            let start = DispatchTime.now().uptimeNanoseconds
            dancer.update(features: features, stemFeatures: StemFeatures(), commandBuffer: cmd)
            cpu.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .dontCare
            rpd.colorAttachments[0].storeAction = .store
            let enc = try #require(cmd.makeRenderCommandEncoder(descriptor: rpd))
            dancer.render(encoder: enc, features: features)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            if index >= 60 { gpu.append((cmd.gpuEndTime - cmd.gpuStartTime) * 1000) } else { cpu.removeLast() }
            if let row = fixture.row(at: time) {
                dancer.ingestClock(playbackSeconds: fixture.playback[row], renderTime: time, lockState: 0)
            }
        }
        func stat(_ values: [Double], _ percent: Double) -> Double {
            let sorted = values.sorted()
            return sorted[min(Int(Double(sorted.count) * percent), sorted.count - 1)]
        }
        print("[kagura-perf] frames over 1 ms GPU: \(gpu.filter { $0 > 1 }.count) of \(gpu.count)")
        print(String(format: "[kagura-perf] %@, 1920×1080, no readback, n=%d: GPU median %.3f ms, p95 %.3f ms; "
                     + "CPU update median %.3f ms, p95 %.3f ms; picks %d",
                     configuration, gpu.count, stat(gpu, 0.5), stat(gpu, 0.95), stat(cpu, 0.5), stat(cpu, 0.95),
                     dancer.choreography.picks.count))
        #expect(stat(gpu, 0.95) < 16.6)
    }
}
