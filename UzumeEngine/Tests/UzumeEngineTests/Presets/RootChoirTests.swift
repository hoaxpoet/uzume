import Testing
import Foundation
import Metal
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Root Choir — Liquid Script")
struct RootChoirTests {
    @Test("shader and sidecar declare the production mv_warp contract")
    func loads() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Root Choir" })
        #expect(preset.descriptor.passes == [.direct, .mvWarp])
        #expect(preset.descriptor.family == .drawing)
        #expect(preset.descriptor.certified == false)
        #expect(preset.descriptor.audioRoutes.count == 2)
        #expect(preset.mvWarpPipelines != nil)

        let source = try String(contentsOf: shaderURL("RootChoir.metal"), encoding: .utf8)
        for symbol in ["root_choir_fragment(", "root_choir_warp_fragment(",
                       "root_choir_comp_fragment(", "MVWarpPerFrame mvWarpPerFrame(",
                       "float2 mvWarpPerVertex("] {
            #expect(source.contains(symbol), "RootChoir.metal missing \(symbol)")
        }
    }

    @MainActor
    @Test("production feedback loop stays alive, bounded, and moving over 96 frames")
    func accumulation() throws {
        let width = 192, height = 108, count = 96
        let harness = MultiPassRenderHarness(width: width, height: height)
        var features: [FeatureVector] = []
        for frame in 0..<count {
            let time = Float(frame) / 60.0
            var f = FeatureVector(time: time, deltaTime: 1.0 / 60.0)
            f.aspectRatio = Float(width) / Float(height)
            f.bassDev = 0.18 + 0.28 * max(0, sin(time * 2.7))
            f.beatComposite = frame % 30 < 5 ? 1.0 - Float(frame % 30) / 5.0 : 0
            features.append(f)
        }
        let stats = try harness.render(
            preset: "Root Choir", features: features,
            stems: Array(repeating: .zero, count: count)
        ) { pixels in
            var sum: UInt64 = 0, bright = 0, hash: UInt64 = 14_695_981_039_346_656_037
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let luma = (UInt64(pixels[i]) + UInt64(pixels[i + 1]) + UInt64(pixels[i + 2])) / 3
                sum += luma
                if luma > 245 { bright += 1 }
                hash = (hash ^ luma) &* 1_099_511_628_211
            }
            return (mean: Double(sum) / Double(width * height * 255),
                    bright: Double(bright) / Double(width * height), hash: hash)
        }
        let tail = stats.suffix(32)
        #expect(tail.allSatisfy { $0.mean > 0.012 }, "feedback starved to black")
        #expect(tail.allSatisfy { $0.mean < 0.58 }, "feedback washed out")
        #expect(tail.allSatisfy { $0.bright < 0.12 }, "white content dominates")
        #expect(Set(tail.map(\.hash)).count > 24, "feedback motion froze")
    }

    @MainActor
    @Test("Tier-2 mv_warp work stays under 7 ms at 1080p (ROOT_CHOIR_PERF=1)")
    func tier2Performance() throws {
        guard ProcessInfo.processInfo.environment["ROOT_CHOIR_PERF"] == "1" else { return }
        let count = 24
        let harness = MultiPassRenderHarness(width: 1920, height: 1080, readback: false)
        let features = (0..<count).map { frame -> FeatureVector in
            var f = FeatureVector(time: Float(frame) / 60.0, deltaTime: 1.0 / 60.0)
            f.aspectRatio = 16.0 / 9.0; f.bassDev = 0.45
            f.beatComposite = frame % 12 == 0 ? 1 : 0
            return f
        }
        let stems = Array(repeating: StemFeatures.zero, count: count)
        _ = try harness.render(preset: "Root Choir", features: features, stems: stems) { _ in 0 }
        let start = ProcessInfo.processInfo.systemUptime
        _ = try harness.render(preset: "Root Choir", features: features, stems: stems) { _ in 0 }
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1_000 / Double(count)
        #expect(ms < 7.0, "Root Choir exceeds the Tier-2 ceiling: \(ms) ms")
    }

    private func shaderURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Presets/Shaders/\(name)")
    }
}
