// KaguraMotionSequenceTests — the pre-M7 look + motion dump (KAG.2; Witchlight template).
//
// Renders a contiguous 60 fps sequence through Kagura's production path (`KaguraDancer.update` →
// `.render`, the calls the app makes), driven by the committed route-coverage captures: the
// capture's own playback clock pushed after each update (the app's tick) and the matching Beat
// This! reference grid (FA #27). Writes:
//   <root>/<track>/kagura_seq_NNNN.png     every frame, for Scripts/motion_gate.sh
//   <root>/kagura_<track>_24s.png          a 720×720 centre crop at 24 s — reference 01's moment
//   <root>/kagura_sway_8s.png              the no-grid sway at 8 s — reference 02's moment
// The 720×720 crops are exact: the framing scales with drawable HEIGHT and centres on the width,
// so a 1280×720 frame's centre square is the spike's 720×720 frame.
//
//   RENDER_VISUAL=1 swift test --package-path UzumeEngine --filter KaguraMotionSequence
//   Scripts/compare_render.sh kagura
//   Scripts/motion_gate.sh kagura /tmp/uzume_visual/<stamp>/<track>
//
// The verdicts (compare table, motion) are the reader's (D-064); the guards below only stop a
// frozen or blank sequence from reading "smooth" for the wrong reason.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
@testable import Renderer
@testable import Shared

@Suite("Kagura motion sequence (pre-M7 gate)", .serialized)
struct KaguraMotionSequenceTests {

    private static let width = 1280, height = 720, fps = 60.0

    @Test("Render Kagura motion sequences from the committed fixtures (RENDER_VISUAL=1)")
    func renderKaguraMotionSequences() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[kagura] RENDER_VISUAL not set — skipping motion-sequence dump")
            return
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let root = URL(fileURLWithPath: "/tmp/uzume_visual").appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for track in KaguraFixture.tracks {
            let fixture = try KaguraFixture.load(track)
            let dir = root.appendingPathComponent(track)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var lastFrame: [UInt8] = []
            var changed = 0
            try Self.render(seconds: fixture.duration, grid: try fixture.grid(),
                            clock: { time in fixture.row(at: time).map { fixture.playback[$0] } }) { index, bgra in
                if bgra != lastFrame { changed += 1 }
                lastFrame = bgra
                try Self.writePNG(bgra, to: dir.appendingPathComponent(String(format: "kagura_seq_%04d.png", index)))
                if index == Int(24 * Self.fps) {
                    try Self.writePNG(bgra, to: root.appendingPathComponent("kagura_\(track)_24s.png"), square: true)
                }
            }
            print("[kagura] \(track): frames → \(dir.path); \(changed) changed frames")
            #expect(changed > Int(fixture.duration * Self.fps) - 5, "\(track): the sequence froze")
            #expect(lastFrame.contains { $0 > 40 }, "\(track): the final frame is blank")
        }

        // The sway: no grid at all (reference 02's case — irregular grid / cold start).
        try Self.render(seconds: 8.5, grid: nil, clock: { $0 }) { index, bgra in
            if index == Int(8 * Self.fps) {
                try Self.writePNG(bgra, to: root.appendingPathComponent("kagura_sway_8s.png"), square: true)
            }
        }
        print("""
            [kagura] motion-sequence root: \(root.path)
                     next: Scripts/compare_render.sh kagura, then Scripts/motion_gate.sh kagura <root>/<track>
            """)
    }

    // MARK: - Production-path render

    /// 60 fps: update (choreography + trail + composite), render (shoulder) into an sRGB target,
    /// read back, then push the clock (the app's tick runs after update).
    private static func render(seconds: Double, grid: KaguraGrid?, clock: (Double) -> Double?,
                               frame: (Int, [UInt8]) throws -> Void) throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let dancer = try KaguraDancer(device: ctx.device, library: lib.library, pixelFormat: ctx.pixelFormat)
        dancer.ensureAllocated(width: width, height: height)
        dancer.setGrid(grid, streaming: false)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        let target = try #require(ctx.device.makeTexture(descriptor: desc))
        var bgra = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<Int(seconds * fps) {
            let time = Double(index) / fps
            var features = FeatureVector()
            features.time = Float(time)
            features.deltaTime = Float(1 / fps)
            let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
            dancer.update(features: features, stemFeatures: StemFeatures(), commandBuffer: cmd)
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = target
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].storeAction = .store
            let enc = try #require(cmd.makeRenderCommandEncoder(descriptor: rpd))
            dancer.render(encoder: enc, features: features)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            bgra.withUnsafeMutableBytes {
                target.getBytes($0.baseAddress!, bytesPerRow: width * 4,   // swiftlint:disable:this force_unwrapping
                                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
            try frame(index, bgra)
            if let seconds = clock(time) { dancer.ingestClock(playbackSeconds: seconds, renderTime: time, lockState: 0) }
        }
    }

    // MARK: - PNG

    private static func writePNG(_ bgra: [UInt8], to url: URL, square: Bool = false) throws {
        // BGRA straight through (little-endian, alpha skipped) — no per-pixel swizzle; the
        // square crop is a row-strided slice starting at the centre column.
        let x0 = square ? (width - height) / 2 : 0
        let outW = square ? height : width
        var bytes = bgra
        if square {
            bytes = []
            bytes.reserveCapacity(outW * height * 4)
            for row in 0..<height {
                let start = (row * width + x0) * 4
                bytes.append(contentsOf: bgra[start..<(start + outW * 4)])
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: outW, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: outW * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                     | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}
