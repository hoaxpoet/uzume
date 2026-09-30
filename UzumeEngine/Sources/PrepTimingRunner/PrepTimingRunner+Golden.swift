// PrepTimingRunner+Golden — PREP.3 stem-series goldens: capture, and compare against.
//
// PREP.3 changes how the LFSTEM.1 sweep runs — pre-allocated model outputs, fewer inverse
// transforms, several windows per GPU run — and promises that what a scene reads does not
// change. The promise is checkable only against values captured BEFORE the change, so this
// captures, per track, the whole `StemFeatureSeries` and the stems of one sweep window from
// the production separator, and later re-runs the same sweep and compares.
//
// Goldens are gitignored fixtures (a 6-minute track's series is ~4 MB, a window's stems 7 MB),
// written to `UzumeEngine/Tests/Fixtures/prep3_goldens/` by default. They are not in
// `Scripts/fixtures.manifest`: nothing in a default `swift test` reads them.
//
// **The tolerance rule (pre-registered, PREP.3 task 4).** A field passes when, on every frame,
// |new − golden| ≤ 1 % of the golden's median NONZERO frame-to-frame change in that field.
// A field that never changes frame to frame (median step 0) must match exactly. The rule is
// written here and in the report before the first comparison was run.

import Audio
import DSP
import Foundation
import Metal
import ML
import Session
import Shared

// MARK: - Window tap

/// Wraps the production separator and keeps the stems of the `keep`-th sweep window.
final class WindowTap: StemSeparating, @unchecked Sendable {
    let inner: any StemSeparating
    let keep: Int
    private(set) var windows = 0
    private(set) var kept: [[Float]]?

    init(_ inner: any StemSeparating, keep: Int) {
        self.inner = inner
        self.keep = keep
    }

    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let result = try inner.separate(audio: audio, channelCount: channelCount, sampleRate: sampleRate)
        if windows == keep { kept = result.stemWaveforms }
        windows += 1
        return result
    }

    var stemLabels: [String] { inner.stemLabels }
    var stemBuffers: [UMABuffer<Float>] { inner.stemBuffers }
    var outputSampleRate: Float? { inner.outputSampleRate }
}

// MARK: - Golden

/// One sweep's output as the goldens record it.
struct SweepCapture {
    let series: StemFeatureSeries
    let window: [[Float]]
    let sampleRate: Int
}

struct StemGolden: Codable {
    let source: String
    let sampleRate: Int
    let hopSeconds: Double
    let frameCount: Int
    let fields: [String]
    let windowIndex: Int
    let windowLength: Int

    /// The sweep window whose stems are kept: far enough in that it is a full, tail-placed
    /// window, not the start-of-file special case.
    static let windowIndex = 10

    /// Run the production sweep over `url` the way `LocalFilePreparationPipeline` does. One
    /// autorelease pool per track, so a multi-track harness run does not carry one track's
    /// MPSGraph autoreleased outputs into the next (PREP.3 task 2).
    static func sweep(url: URL, separator: StemSeparator) throws -> SweepCapture {
        try autoreleasepool { try sweepBody(url: url, separator: separator) }
    }

    private static func sweepBody(url: URL, separator: StemSeparator) throws -> SweepCapture {
        let preview = try PreviewAudio.fromLocalFile(at: url)
        let tap = WindowTap(separator, keep: windowIndex)
        let series = try SessionPreparer.analyzeStemSeries(
            samples: preview.pcmSamples,
            sampleRate: preview.sampleRate,
            separator: tap,
            analyzer: StemAnalyzer(sampleRate: separator.outputSampleRate ?? Float(preview.sampleRate))
        )
        return SweepCapture(series: series, window: tap.kept ?? [], sampleRate: preview.sampleRate)
    }

    /// `StemFeatures` as named floats, in declaration order.
    static func fields(of features: StemFeatures) -> [(String, Float)] {
        Mirror(reflecting: features).children.compactMap { child in
            guard let label = child.label, let value = child.value as? Float else { return nil }
            return (label, value)
        }
    }

    static func stem(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
    }
}

// MARK: - Capture / compare

enum GoldenMode {

    static func capture(urls: [URL], into dir: URL, device: MTLDevice) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let separator = try StemSeparator(device: device)
        for url in urls {
            let capture = try StemGolden.sweep(url: url, separator: separator)
            let series = capture.series
            let window = capture.window
            let names = series.frames.first.map { StemGolden.fields(of: $0).map(\.0) } ?? []
            let flat = series.frames.flatMap { StemGolden.fields(of: $0).map(\.1) }
            let base = dir.appendingPathComponent(StemGolden.stem(url))
            try floats(flat).write(to: base.appendingPathExtension("series.f32"))
            try floats(window.flatMap { $0 }).write(to: base.appendingPathExtension("window.f32"))
            let meta = StemGolden(
                source: url.path,
                sampleRate: capture.sampleRate,
                hopSeconds: series.hopSeconds,
                frameCount: series.frames.count,
                fields: names,
                windowIndex: StemGolden.windowIndex,
                windowLength: window.first?.count ?? 0)
            try JSONEncoder().encode(meta).write(to: base.appendingPathExtension("json"))
            let line = "golden: \(url.lastPathComponent) frames=\(series.frames.count) fields=\(names.count)\n"
            FileHandle.standardError.write(Data(line.utf8))
        }
    }

    /// Re-run each golden's sweep on today's code; write `parity.csv` and a verdict per track.
    /// Returns whether every track passed.
    @discardableResult
    static func compare(goldens dir: URL, out: URL, device: MTLDevice) throws -> Bool {
        let separator = try StemSeparator(device: device)
        let metas = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
        var csv = "track,field,max_abs_diff,tolerance,median_step,frames_over,pass\n"
        var report = ""
        var allPass = true
        for metaURL in metas {
            let meta = try JSONDecoder().decode(StemGolden.self, from: Data(contentsOf: metaURL))
            let base = metaURL.deletingPathExtension()
            let golden = try readFloats(base.appendingPathExtension("series.f32"))
            let goldenWindow = try readFloats(base.appendingPathExtension("window.f32"))
            let capture = try StemGolden.sweep(url: URL(fileURLWithPath: meta.source), separator: separator)
            let series = capture.series
            let window = capture.window
            let fieldCount = meta.fields.count
            let fresh = series.frames.flatMap { StemGolden.fields(of: $0).map(\.1) }
            let name = base.lastPathComponent
            guard series.frames.count == meta.frameCount else {
                report += "\(name): FRAME COUNT \(series.frames.count) != golden \(meta.frameCount) — FAIL\n"
                allPass = false
                continue
            }
            var trackPass = true
            var worst: [String] = []
            for (field, label) in meta.fields.enumerated() {
                let old = stride(from: field, to: golden.count, by: fieldCount).map { golden[$0] }
                let new = stride(from: field, to: fresh.count, by: fieldCount).map { fresh[$0] }
                let steps = zip(old.dropFirst(), old).map { abs($0 - $1) }.filter { $0 > 0 }.sorted()
                let medianStep = steps.isEmpty ? 0 : steps[steps.count / 2]
                let tolerance = 0.01 * medianStep
                let diffs = zip(old, new).map { abs($0 - $1) }
                let maxDiff = diffs.max() ?? 0
                let over = diffs.filter { $0 > tolerance }.count
                let pass = over == 0
                trackPass = trackPass && pass
                if !pass { worst.append("\(label) (\(over) frames)") }
                csv += "\"\(name)\",\(label),\(maxDiff),\(tolerance),\(medianStep),\(over),\(pass)\n"
            }
            let freshWindow = window.flatMap { $0 }
            let bitIdentical = freshWindow == goldenWindow
            let windowMax = zip(freshWindow, goldenWindow).map { abs($0 - $1) }.max() ?? .infinity
            let windowPeak = goldenWindow.map(abs).max() ?? 0
            let seriesIdentical = fresh == golden
            let fieldVerdict = trackPass
                ? "all fields within tolerance"
                : "OVER TOLERANCE: " + worst.joined(separator: ", ")
            report += "\(name): series \(seriesIdentical ? "BIT-IDENTICAL" : "differs") · \(fieldVerdict) · "
                + "window stems \(bitIdentical ? "BIT-IDENTICAL" : "differ") "
                + String(format: "(max |Δ| %.3g of peak %.3g)\n", windowMax, windowPeak)
            allPass = allPass && trackPass
        }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try csv.write(to: out.appendingPathComponent("parity.csv"), atomically: true, encoding: .utf8)
        try report.write(to: out.appendingPathComponent("parity.txt"), atomically: true, encoding: .utf8)
        print(report)
        return allPass
    }

    // MARK: Float I/O

    private static func floats(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func readFloats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
