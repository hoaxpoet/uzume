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
import Metal
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

    /// FF.2 Task 3 — the look still. DYC's locked-unison peak (FF.1's films: near frame 1221) at
    /// 1920×1080 through the real draw path, once from the drift camera ("a") and once at the
    /// same moment with the camera clock shifted half a sideways period ("b") to show the
    /// parallax. Writes `fireflies_{a,b}_f<frame>.png` for frames 1212–1231 to
    /// `FIREFLIES_STILL_OUT` — or, under `RENDER_VISUAL=1`, to a fresh `/tmp/uzume_visual/<stamp>/`
    /// where `Scripts/compare_render.sh fireflies` finds them — plus each frame's mean luma.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_STILL_OUT"] != nil
                   || ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1"))
    func lookStills() throws {
        let env = ProcessInfo.processInfo.environment
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let out = URL(fileURLWithPath: env["FIREFLIES_STILL_OUT"] ?? "/tmp/uzume_visual/\(stamp)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let drive = try FirefliesDrive(directory: FirefliesSpikeParityProbe.root
            .appendingPathComponent("sessions/fixturegen-01_Dance_Yrself_Clean"))
        let window = 1212..<1232
        let features = Array(drive.features.prefix(window.upperBound))
        MultiPassRenderHarness.firefliesGridBPM = drive.gridBPM
        defer {
            MultiPassRenderHarness.firefliesGridBPM = nil
            MultiPassRenderHarness.firefliesCameraTimeOffset = 0
        }
        for (tag, offset) in [("a", Float(0)), ("b", Float(23.5))] {
            MultiPassRenderHarness.firefliesCameraTimeOffset = offset
            var index = 0
            let luma = try MultiPassRenderHarness(width: 1920, height: 1080).render(
                preset: "Fireflies", features: features, stems: Self.stems(features.count, clarity: 1)
            ) { bgra -> Float in
                defer { index += 1 }
                guard window.contains(index) else { return 0 }
                Self.writePNG(bgra, width: 1920, height: 1080,
                              to: out.appendingPathComponent("fireflies_\(tag)_f\(index).png"))
                return Self.meanLuma(bgra)
            }
            for frame in window {
                print(String(format: "[fireflies-still] %@ frame %d mean luma %.4f", tag, frame, luma[frame]))
            }
        }
    }

    /// FF.2 Task 5 — the world at near-silence. Warszawa's tail ends in ~4.8 s of
    /// `near_silent01`; the film (1280×720, every frame) shows whether the world COASTS — wind and
    /// mist slower but moving, never black (D-037) — while the swarm fades to stragglers.
    /// Env-gated (`FIREFLIES_SILENCE_OUT`), for `Scripts/motion_gate.sh`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_SILENCE_OUT"] != nil))
    func silenceFilm() throws {
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FIREFLIES_SILENCE_OUT"] ?? "")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let drive = try FirefliesDrive(directory: FirefliesSpikeParityProbe.root
            .appendingPathComponent("sessions/fixturegen-Warszawa_tail"))
        MultiPassRenderHarness.firefliesGridBPM = drive.gridBPM
        defer { MultiPassRenderHarness.firefliesGridBPM = nil }
        var index = 0
        let luma = try MultiPassRenderHarness(width: 1280, height: 720).render(
            preset: "Fireflies", features: drive.features, stems: Self.stems(drive.features.count, clarity: 0.5)
        ) { bgra -> Float in
            Self.writePNG(bgra, width: 1280, height: 720,
                          to: out.appendingPathComponent(String(format: "fireflies_seq_%05d.png", index)))
            index += 1
            return Self.meanLuma(bgra)
        }
        let silent = drive.features.indices.filter { drive.features[$0].nearSilent01 > 0.5 }
        let quiet = silent.map { luma[$0] }
        print(String(format: "[fireflies-silence] %d near-silent frames, luma min %.4f mean %.4f",
                     quiet.count, quiet.min() ?? 0, quiet.reduce(0, +) / Float(max(quiet.count, 1))))
        #expect((quiet.min() ?? 0) > 0.05, "the world must stay lit at silence (D-037)")
    }

    /// FF.2 Task 7 — frame cost at 1920×1080 on the DYC capture through the real draw path, no
    /// readback: GPU time per frame from command-buffer timestamps, and the CPU model (swarm +
    /// world + upload) timed on its own. Env-gated (`FIREFLIES_TIMING=1`); run it ISOLATED and
    /// state the build configuration — `swift test -c release --enable-testable-imports` for
    /// Release (TESTREL.1), plain `swift test` for Debug.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_TIMING"] == "1"))
    func frameCostAt1080p() throws {
        let drive = try FirefliesDrive(directory: FirefliesSpikeParityProbe.root
            .appendingPathComponent("sessions/fixturegen-01_Dance_Yrself_Clean"))
        MultiPassRenderHarness.firefliesGridBPM = drive.gridBPM
        MultiPassRenderHarness.gpuTimesMs = []
        defer {
            MultiPassRenderHarness.firefliesGridBPM = nil
            MultiPassRenderHarness.gpuTimesMs = nil
        }
        _ = try MultiPassRenderHarness(width: 1920, height: 1080, readback: false).render(
            preset: "Fireflies", features: drive.features, stems: Self.stems(drive.features.count, clarity: 1)
        ) { _ in 0 }
        let gpu = (MultiPassRenderHarness.gpuTimesMs ?? []).dropFirst(60).sorted()

        let ctx = try MetalContext()
        let geo = try FirefliesGeometry(device: ctx.device, library: try ShaderLibrary(context: ctx).library,
                                        beatGrid: nil)
        let stem = Self.stems(1, clarity: 1)[0]
        var cpu: [Double] = []
        for f in drive.features {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            let start = DispatchTime.now().uptimeNanoseconds
            geo.update(features: f, stemFeatures: stem, commandBuffer: cmd)
            cpu.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        cpu = cpu.dropFirst(60).sorted()
        func pct(_ v: [Double], _ p: Double) -> Double { v.isEmpty ? 0 : v[min(v.count - 1, Int(p * Double(v.count)))] }
        print(String(format: "[fireflies-cost] 1920×1080 GPU median %.3f ms p95 %.3f max %.3f | CPU model median %.3f ms p95 %.3f (%d frames)",
                     pct(gpu, 0.5), pct(gpu, 0.95), gpu.last ?? 0, pct(cpu, 0.5), pct(cpu, 0.95), gpu.count))
        #expect(!gpu.isEmpty)
    }

    /// FF.2 Task 5 — does the world's breath SHOW? The route gate proves `bassAttRel` varies; this
    /// proves the consumer answers it (a metric is a model of the pipeline). DYC and Pyramid Song
    /// at 640×360 with the camera HELD STILL, so the only world motion is the wind: the mean
    /// frame-to-frame change in the tree-crown band above the swarm (rows 0–85), 2 s averaged,
    /// in the top vs bottom quartile of the breath. Env-gated (`FIREFLIES_BREATH=1`), report-only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_BREATH"] == "1"))
    func breathIsVisible() throws {
        for (session, stem) in [("fixturegen-01_Dance_Yrself_Clean", "dyc"), ("fixturegen-02_Pyramid_Song", "pyramid")] {
            let drive = try FirefliesDrive(directory: FirefliesSpikeParityProbe.root
                .appendingPathComponent("sessions/\(session)"))
            MultiPassRenderHarness.firefliesGridBPM = drive.gridBPM
            MultiPassRenderHarness.firefliesFreezeCamera = true
            defer {
                MultiPassRenderHarness.firefliesGridBPM = nil
                MultiPassRenderHarness.firefliesFreezeCamera = false
            }
            var prev: [UInt8]?
            let band = 640 * 85 * 4
            let motion = try MultiPassRenderHarness(width: 640, height: 360).render(
                preset: "Fireflies", features: drive.features, stems: Self.stems(drive.features.count, clarity: 1)
            ) { bgra -> Float in
                defer { prev = Array(bgra[0..<band]) }
                guard let prev else { return 0 }
                var sum = 0
                for k in stride(from: 1, to: band, by: 4) { sum += abs(Int(bgra[k]) - Int(prev[k])) }
                return Float(sum) / Float(band / 4)
            }
            // The breath the world saw, recomputed from the same column (FirefliesWorld.advance).
            var ema: Float = 0
            let breath = drive.features.map { f -> Float in
                ema += (f.bassAttRel - ema) * (1 - exp(-min(max(f.deltaTime, 0), 0.1) / 4))
                return 0.5 + 0.5 * tanh(4 * ema)
            }
            let window = 86
            let smooth = (window..<motion.count).map { i in motion[(i - window)..<i].reduce(0, +) / Float(window) }
            let aligned = Array(breath[window...].prefix(smooth.count))
            let sorted = aligned.sorted()
            let (lo, hi) = (sorted[sorted.count / 4], sorted[3 * sorted.count / 4])
            let quiet = zip(smooth, aligned).filter { $0.1 <= lo }.map(\.0)
            let full = zip(smooth, aligned).filter { $0.1 >= hi }.map(\.0)
            let mean = { (v: [Float]) in v.reduce(0, +) / Float(max(v.count, 1)) }
            print(String(format: "[fireflies-breath] %@ breath q25 %.2f q75 %.2f  crown motion quiet %.3f full %.3f  ratio %.2f",
                         stem, lo, hi, mean(quiet), mean(full), mean(full) / max(mean(quiet), 1e-6)))
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
