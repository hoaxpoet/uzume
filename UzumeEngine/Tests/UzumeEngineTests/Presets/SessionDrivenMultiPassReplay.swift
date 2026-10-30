// SessionDrivenMultiPassReplay — PR.10: replay a RECORDED session through
// `MultiPassRenderHarness`, which already reaches every paradigm.
//
// WHY THIS IS SMALL. PR.1 reported that 23 of the 26 presets Matt flagged "cannot be
// replayed from a real session", because `SessionReplayHarness` drives
// `RayMarchPipeline.render` and its coverage gate was scoped to `.rayMarch`. That was
// true of THAT harness and wrong about the codebase: `MultiPassRenderHarness.render`
// already dispatches Dragon Bloom, Skein, Witchlight, Ricercar, Filigree, Meniscus,
// Stave, Mitosis, Cytokinesis, Nacre, Glaze, Floret, Fata Morgana, Fractal Tree, Lumen
// Mosaic, Volumetric Lithograph, Cymatic Resonance and the four `direct` presets down
// their real render paths. The only thing missing was real INPUT.
//
// So this file is the join: `SessionReplayHarness`'s CSV loaders (which PR.10 widened
// from 27 to 46 carried primitives) feeding `MultiPassRenderHarness`'s dispatch. Both
// halves already existed and neither knew about the other.
//
// Usage:
//   REPLAY_SESSION=~/Documents/uzume_sessions/<dir> \
//   REPLAY_PRESET="Dragon Bloom" \
//   REPLAY_MULTIPASS=1 \
//   [REPLAY_FROM=0 REPLAY_COUNT=90 REPLAY_OUT=/tmp/replay REPLAY_FINISH=cinematic] \
//   [REPLAY_HDR=4  — VQ.2a: also finish every frame for an HDR display at this headroom; prints
//    SDR-vs-HDR light and the flash reports, and REPLAY_OUT gets SDR|HDR side-by-side .heic] \
//   swift test --package-path UzumeEngine --filter SessionDrivenMultiPassReplay
import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CoreImage
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("SessionDrivenMultiPassReplay")
@MainActor
struct SessionDrivenMultiPassReplay {

    /// Fraction of pixels with any channel at 254+, mean saturation of bright pixels,
    /// and mean luma. The three numbers a "washed out / too bright / too dark" report
    /// is actually about (PR.5).
    struct FrameStats {
        var clipped: Double
        var saturation: Double
        var meanLuma: Double
        /// Fraction of the frame that is near-WHITE. Under Dragon Bloom's `bInvert` that is
        /// the fraction of the accumulator that is EMPTY — the quantity the live butterchurn
        /// oracle holds at 0.000 and ours does not.
        var nearWhite: Double
    }

    private static func stats(_ bgra: [UInt8]) -> FrameStats {
        var clipped = 0, bright = 0, white = 0
        var sat = 0.0, lum = 0.0
        let count = bgra.count / 4
        guard count > 0 else {
            return FrameStats(clipped: 0, saturation: 0, meanLuma: 0, nearWhite: 0)
        }
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let b = Int(bgra[i]), g = Int(bgra[i + 1]), r = Int(bgra[i + 2])
            let mx = max(r, max(g, b)), mn = min(r, min(g, b))
            lum += (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
            if mx >= 254 { clipped += 1 }
            if mn >= 235 { white += 1 }
            if mx >= 200 { bright += 1; sat += Double(mx - mn) / Double(mx) }
        }
        return FrameStats(
            clipped: Double(clipped) / Double(count),
            saturation: bright > 0 ? sat / Double(bright) : 0,
            meanLuma: lum / Double(count),
            nearWhite: Double(white) / Double(count))
    }

    @Test("replay a recorded session through MultiPassRenderHarness (REPLAY_MULTIPASS=1)")
    func test_replayMultiPass() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["REPLAY_MULTIPASS"] == "1",
              let sessionPath = env["REPLAY_SESSION"],
              let presetName = env["REPLAY_PRESET"] else {
            print("[multipass-replay] set REPLAY_MULTIPASS=1 + REPLAY_SESSION + REPLAY_PRESET")
            return
        }
        let dir = URL(fileURLWithPath: (sessionPath as NSString).expandingTildeInPath)
        let rows = try SessionReplayHarness.loadRowsForReplay(
            dir.appendingPathComponent("features.csv"))
        let stems = SessionReplayHarness.loadStemsForReplay(
            dir.appendingPathComponent("stems.csv"))
        guard !rows.isEmpty else {
            Issue.record("no rows parsed from \(sessionPath)/features.csv"); return
        }

        // Start where audio actually begins; everything before is frozen pre-roll.
        let firstAudio = rows.firstIndex { $0.accumulatedAudioTime > 0 } ?? 0
        let from = Int(env["REPLAY_FROM"] ?? "") ?? firstAudio
        let count = Int(env["REPLAY_COUNT"] ?? "") ?? 120
        let lo = min(from, rows.count - 1)
        let hi = min(lo + count, rows.count)
        let features = Array(rows[lo..<hi]).map {
            SessionReplayHarness.featureForReplay(from: $0, aspect: 1067.0 / 750.0)
        }
        // stems.csv is row-aligned with features.csv; pad with the last row if short.
        let stemSlice: [StemFeatures] = (lo..<hi).map { i in
            stems.isEmpty ? .zero : stems[min(i, stems.count - 1)]
        }
        if stems.isEmpty {
            print("[multipass-replay] WARNING: no stems.csv — stem routes replay against SILENCE")
        }

        print("[multipass-replay] \(presetName): \(features.count) frames "
              + "from row \(lo) (audio starts \(firstAudio)) of \(rows.count)")

        // PR.5: bigger than the 320x180 default when we are going to LOOK at frames
        // rather than only reduce them to three numbers. The stats are the same either
        // way; a contact sheet at 320x180 is not something a trait verdict can be
        // written from.
        let width = Int(env["REPLAY_W"] ?? "") ?? 320
        let height = Int(env["REPLAY_H"] ?? "") ?? 180
        // VQ.1c: REPLAY_FINISH=legacy|cinematic forces the finish (default legacy).
        let finish = env["REPLAY_FINISH"].flatMap(FinishSpec.Mode.init(rawValue:)) ?? .legacy
        var harness = try MultiPassRenderHarness(width: width, height: height, finishMode: finish)
        let hdr = env["REPLAY_HDR"].flatMap(Float.init).map { HDRReplay(headroom: $0) }
        if let hdr { harness.hdrFrames = HDRFrameLog(headroom: hdr.headroom) { hdr.receive($0, width, height) } }
        // REPLAY_OUT was documented in this file's usage block from PR.10 and never
        // implemented. Writing every Nth frame is what makes the replay a perception
        // check (D-181) instead of a metric-only run.
        let outDir = (env["REPLAY_OUT"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) })
        if let outDir { try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }
        let every = Int(env["REPLAY_EVERY"] ?? "") ?? 20
        var frameIndex = 0
        let measured = try harness.render(
            preset: presetName, features: features, stems: stemSlice, settle: 8
        ) { bgra -> FrameStats in
            defer { frameIndex += 1 }
            if let outDir, frameIndex % every == 0 {
                let url = outDir.appendingPathComponent(String(format: "f_%04d.png", frameIndex))
                try? Self.writePNG(bgra: bgra, width: width, height: height, to: url)
                if let hdr {
                    let url = outDir.appendingPathComponent(String(format: "sbs_%04d.heic", frameIndex))
                    try? hdr.writeSideBySide(sdr: bgra, width: width, height: height, to: url)
                }
            }
            hdr?.receiveSDR(bgra)
            return Self.stats(bgra)
        }
        if let outDir { print("[multipass-replay] frames → \(outDir.path)") }

        guard !measured.isEmpty else { Issue.record("no frames measured"); return }
        let clip = measured.map(\.clipped)
        let sat = measured.map(\.saturation)
        let lum = measured.map(\.meanLuma)
        func mean(_ a: [Double]) -> Double { a.reduce(0, +) / Double(a.count) }
        print("""
        [multipass-replay] \(presetName) over \(measured.count) REAL frames:
          clipped    mean \(String(format: "%.3f", mean(clip)))  max \(String(format: "%.3f", clip.max() ?? 0))
          saturation mean \(String(format: "%.3f", mean(sat)))  min \(String(format: "%.3f", sat.min() ?? 0))
          meanLuma   mean \(String(format: "%.3f", mean(lum)))  max \(String(format: "%.3f", lum.max() ?? 0))
          nearWhite  mean \(String(format: "%.3f", mean(measured.map(\.nearWhite))))  (= EMPTY accumulator; oracle holds 0.000)
        """)
        hdr?.report()
        // PR.5: the TRAJECTORY, not just the mean. Dragon Bloom's fill is documented as a
        // feedback attractor that develops over ~20 s (DRAGON_BLOOM_PLAN.md L4 item 3), so
        // a single mean cannot tell "converged and wrong" apart from "still filling".
        let bucket = max(1, measured.count / 10)
        var trajectory: [String] = []
        for start in stride(from: 0, to: measured.count, by: bucket) {
            let slice = Array(measured[start..<min(start + bucket, measured.count)])
            trajectory.append(String(format: "%3d:%.2f/%.2f",
                                     start, mean(slice.map(\.clipped)), mean(slice.map(\.saturation))))
        }
        print("  trajectory (frame:clipped/saturation)  " + trajectory.joined(separator: "  "))
        var lumaTrack: [String] = []
        for start in stride(from: 0, to: measured.count, by: bucket) {
            let slice = Array(measured[start..<min(start + bucket, measured.count)])
            lumaTrack.append(String(format: "%3d:%.2f", start, mean(slice.map(\.meanLuma))))
        }
        print("  luma trajectory                        " + lumaTrack.joined(separator: "  "))
        // The harness must not be rendering a dead image — that is the FLY.6 failure.
        #expect(lum.max()! > 0.0, "every frame is pure black — the replay drove nothing")
        #expect(Set(lum.map { Int($0 * 1000) }).count > 1,
                "meanLuma is constant across \(measured.count) frames — the preset is not moving")
    }

    /// BGRA8 bytes → an sRGB PNG. Same recipe as the sketch render tests.
    nonisolated static func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        struct PNGError: Error {}
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw PNGError() }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let made = copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let context = CGContext(data: base, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: info.rawValue)
            else { return nil }
            return context.makeImage()
        }
        guard let image = made,
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw PNGError() }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw PNGError() }
    }
}

// MARK: - HDRReplay

/// VQ.2a — the HDR half of a replay: per-frame light above SDR white and dark troughs for SDR and
/// HDR, the largest ninth-of-the-screen mean (the regional cap holds it ≤ 1), and the photosensitive
/// flash reports anchored at SDR white and at the display's peak (VQ.2's two anchors).
final class HDRReplay {
    let headroom: Float
    private var latest: [Float] = []
    private var sdrWhole: [Double] = [], peakWhole: [Double] = []
    private var sdrRegions: [[FlashRegionSample]] = [], peakRegions: [[FlashRegionSample]] = []
    private var maxRegionMean = 0.0
    private var hdrAbove: [Double] = [], hdrP999: [Double] = [], hdrDark: [Double] = [], hdrLuma: [Double] = []
    private var sdrDark: [Double] = [], sdrLuma: [Double] = []

    init(headroom: Float) { self.headroom = headroom }

    func receive(_ px: [Float], _ width: Int, _ height: Int) {
        latest = px
        let sdr = FlashAnalyzer.regions(linearRGBA: px, width: width, height: height)
        let peak = FlashAnalyzer.regions(linearRGBA: px, width: width, height: height, anchor: Double(headroom))
        sdrRegions.append(sdr)
        peakRegions.append(peak)
        maxRegionMean = max(maxRegionMean, sdr.map { Double(max($0.red, $0.green, $0.blue)) }.max() ?? 0)
        let whole = sdr.prefix(9).map(\.luminance).reduce(0, +) / 9
        sdrWhole.append(whole)
        peakWhole.append(whole / Double(headroom))
        var maxes = [Float](), dark = 0, luma = 0.0
        maxes.reserveCapacity(px.count / 4)
        for i in stride(from: 0, to: px.count, by: 4) {
            maxes.append(max(px[i], px[i + 1], px[i + 2]))
            let y = 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
            luma += y
            if y < 0.01 { dark += 1 }
        }
        let n = Double(maxes.count)
        hdrAbove.append(Double(maxes.filter { $0 > 1 }.count) / n)
        hdrP999.append(Double(maxes.sorted()[Int(n * 0.999)]))
        hdrDark.append(Double(dark) / n)
        hdrLuma.append(luma / n)
    }

    func receiveSDR(_ bgra: [UInt8]) {
        var dark = 0, luma = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let y = 0.2126 * Self.decode(bgra[i + 2]) + 0.7152 * Self.decode(bgra[i + 1])
                + 0.0722 * Self.decode(bgra[i])
            luma += y
            if y < 0.01 { dark += 1 }
        }
        let n = Double(bgra.count / 4)
        sdrDark.append(Double(dark) / n)
        sdrLuma.append(luma / n)
    }

    func report() {
        func mean(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        func flashes(_ whole: [Double], _ regions: [[FlashRegionSample]]) -> String {
            let r = [FlashAnalyzer.analyze(relativeLuminance: whole, fps: 60),
                     FlashAnalyzer.analyzeRegional(regions, fps: 60),
                     FlashAnalyzer.analyzeRed(regions, fps: 60)]
            return zip(["whole", "regional", "red"], r).map { "\($0) \($1.isSafe ? "safe" : "FLASH")" }
                .joined(separator: ", ")
        }
        print("""
        [multipass-replay] HDR at headroom \(headroom) over \(hdrAbove.count) frames:
          share of pixels above SDR white  mean \(f(mean(hdrAbove)))  max \(f(hdrAbove.max() ?? 0))
          p99.9 brightest channel          mean \(f(mean(hdrP999)))  max \(f(hdrP999.max() ?? 0))  (× SDR white)
          largest ninth-of-screen mean      \(f(maxRegionMean))  (cap holds ≤ 1)
          dark troughs (luma < 0.01)        SDR \(f(mean(sdrDark)))  HDR \(f(mean(hdrDark)))
          mean luma (linear)                SDR \(f(mean(sdrLuma)))  HDR \(f(mean(hdrLuma)))
          flash, SDR-white anchor:  \(flashes(sdrWhole, sdrRegions))
          flash, peak anchor:       \(flashes(peakWhole, peakRegions))
        """)
    }

    /// SDR (left) | HDR (right) as a 10-bit PQ HEIC: an HDR display shows the right half's light above
    /// SDR white; the left is today's picture. Both halves linear in sRGB primaries (the LG's own).
    func writeSideBySide(sdr bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        struct SBSError: Error {}
        var px = [Float](repeating: 1, count: width * 2 * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let s = (y * width + x) * 4
                let l = (y * width * 2 + x) * 4
                let r = l + width * 4
                px[l] = Float(Self.decode(bgra[s + 2]))
                px[l + 1] = Float(Self.decode(bgra[s + 1]))
                px[l + 2] = Float(Self.decode(bgra[s]))
                px[r] = latest[s]; px[r + 1] = latest[s + 1]; px[r + 2] = latest[s + 2]
            }
        }
        guard let linear = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let pq = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else { throw SBSError() }
        let data = px.withUnsafeBufferPointer { Data(buffer: $0) }
        let image = CIImage(bitmapData: data, bytesPerRow: width * 2 * 16,
                            size: CGSize(width: width * 2, height: height), format: .RGBAf, colorSpace: linear)
            .transformed(by: CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -CGFloat(height)))
        try CIContext().writeHEIF10Representation(of: image, to: url, colorSpace: pq)
        // Where the HDR frame goes above SDR white, marked magenta on today's picture (for reading).
        var mask = bgra
        for i in stride(from: 0, to: mask.count, by: 4) where max(latest[i], latest[i + 1], latest[i + 2]) > 1 {
            mask[i] = 255; mask[i + 1] = 0; mask[i + 2] = 255
        }
        try SessionDrivenMultiPassReplay.writePNG(bgra: mask, width: width, height: height,
                                                  to: url.deletingPathExtension().appendingPathExtension("mask.png"))
    }

    private static func decode(_ code: UInt8) -> Double {
        let e = Double(code) / 255
        return e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4)
    }
}
