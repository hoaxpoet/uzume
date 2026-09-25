// FirefliesRenderTests — FF.1 flash safety measured through the real draw path.
//
// `MultiPassRenderHarness.renderFireflies` mirrors production's `drawDirect` →
// `encodePresetVisualization` for a `particles`-only preset: the world fragment through the
// preset's own compiled pipeline, then the swarm sprites additively into the same encoder,
// on the sRGB drawable format. Frame-mean luma is Rec.709 over the ENCODED bytes, the same
// definition the FF.0 spike's luminance table used.
//
// D-157: max |Δ frame-mean luma| between consecutive frames < 0.05 — a unison flash must be
// hundreds of tiny points, never a frame-wide lift.
//
// Always-on: a steady-beat fixture (love_rehab, K = 1 — the worst case, full unison).
// Env-gated (`FIREFLIES_PARITY=1`): the spike's four captures at 1920×1080, with a PNG film of
// each (1280×720) written to `FIREFLIES_PARITY_OUT` for `Scripts/motion_gate.sh`.
//
// ⚠ Run the env-gated probes FILTERED (`swift test --filter Fireflies`). They hold the main actor
// for minutes of 1080p rendering, and inside a full-suite run that starved 11 `SessionManager`
// tests past their 120 s preparation cap (FF.1; all 23 pass in 0.24 s in isolation).

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Renderer
@testable import Shared

@Suite("Fireflies render (FF.1)")
@MainActor
struct FirefliesRenderTests {

    /// Rec.709 luma of the encoded frame, 0–1 (BGRA bytes).
    static func meanLuma(_ bgra: [UInt8]) -> Float {
        var sum: Float = 0
        var i = 0
        while i < bgra.count {
            sum += 0.0722 * Float(bgra[i]) + 0.7152 * Float(bgra[i + 1]) + 0.2126 * Float(bgra[i + 2])
            i += 4
        }
        return sum / Float(bgra.count / 4) / 255
    }

    struct LumaReport {
        let mean: Float, maxPerSecondRange: Float, maxStep: Float

        init(_ luma: [Float], fps: Int) {
            mean = luma.reduce(0, +) / Float(max(luma.count, 1))
            maxPerSecondRange = stride(from: 0, to: max(luma.count - fps + 1, 0), by: fps).map { start in
                let s = luma[start..<start + fps]
                return (s.max() ?? 0) - (s.min() ?? 0)
            }.max() ?? 0
            maxStep = zip(luma.dropFirst(), luma).map { abs($0 - $1) }.max() ?? 0
        }
    }

    /// The clarity is injected into every frame's stems (the captures predate the column).
    static func stems(_ count: Int, clarity: Float) -> [StemFeatures] {
        var s = StemFeatures.zero
        s.beatClarity01 = clarity
        return [StemFeatures](repeating: s, count: count)
    }

    @Test("A locked unison never lifts the frame (D-157), steady-beat fixture")
    func unisonIsFlashSafe() throws {
        let base = try #require(Bundle.module.url(forResource: "route_coverage", withExtension: nil))
        let drive = try FirefliesDrive(directory: base.appendingPathComponent("love_rehab"))
        MultiPassRenderHarness.firefliesGridBPM = drive.gridBPM
        defer { MultiPassRenderHarness.firefliesGridBPM = nil }
        let luma = try MultiPassRenderHarness().render(
            preset: "Fireflies", features: drive.features,
            stems: Self.stems(drive.features.count, clarity: 1), reduce: Self.meanLuma)
        let report = LumaReport(luma, fps: 43)
        print(String(format: "[fireflies-flash] love_rehab 320×180  mean %.4f  per-s range %.4f  maxΔ %.4f",
                     report.mean, report.maxPerSecondRange, report.maxStep))
        #expect(report.maxStep < 0.05)
        #expect(report.mean > 0.05, "the dusk world must stay lit (D-037)")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_PARITY"] == "1"))
    func spikeCapturesAt1080p() throws {
        let out = ProcessInfo.processInfo.environment["FIREFLIES_PARITY_OUT"].map { URL(fileURLWithPath: $0) }
        for (session, stem, clarity, _, _) in FirefliesSpikeParityProbe.tracks {
            let drive = try FirefliesDrive(
                directory: FirefliesSpikeParityProbe.root.appendingPathComponent("sessions/\(session)"))
            let stems = Self.stems(drive.features.count, clarity: clarity)
            MultiPassRenderHarness.firefliesGridBPM = drive.gridBPM
            defer { MultiPassRenderHarness.firefliesGridBPM = nil }
            let luma = try MultiPassRenderHarness(width: 1920, height: 1080).render(
                preset: "Fireflies", features: drive.features, stems: stems, reduce: Self.meanLuma)
            let report = LumaReport(luma, fps: 43)
            print(String(format: "[fireflies-flash] %@ 1920×1080 K-in %.1f  mean %.4f  per-s range %.4f  maxΔ %.4f",
                         stem, clarity, report.mean, report.maxPerSecondRange, report.maxStep))
            #expect(report.maxStep < 0.05, "\(stem): D-157 frame-mean step \(report.maxStep)")

            guard let out else { continue }
            let dir = out.appendingPathComponent("film_\(stem)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var index = 0
            _ = try MultiPassRenderHarness(width: 1280, height: 720).render(
                preset: "Fireflies", features: drive.features, stems: stems) { bgra -> Int in
                    Self.writePNG(bgra, width: 1280, height: 720,
                                  to: dir.appendingPathComponent(String(format: "fireflies_seq_%05d.png", index)))
                    index += 1
                    return index
                }
        }
    }

    static func writePNG(_ bgra: [UInt8], width: Int, height: Int, to url: URL) {
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bgra) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: info, provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
