// AnalysisRateGateTests — BUG087.4's rate gate.
//
// ⚠ **THE METRIC IS THE POINT, AND THE PREVIOUS ONE WAS WRONG.** BUG087.3 shipped a regression
// test asserting `hz >= 40` computed from SLICE COUNT. It passed. The live capture measured
// 16.4 Hz. It was counting how often the analyser RAN, and a preset cannot observe more distinct
// values per second than the render loop finds distinct — every slice of a buffer lands in the
// same instant, so five of them are worth one update. A green tick against a refuted claim is
// worse than no test.
//
// So both gates here measure the OBSERVED quantity:
//
//  · `sessionRateGate` counts how often a `FeatureVector` column actually CHANGES between
//    rendered rows of a real `features.csv`. That is the number BUG-087 was diagnosed with
//    (10.1 Hz local against 58.8 Hz streaming) and the number it has to be closed with.
//
//  · `deliveryRateGate` runs the real provider and records WHEN each analysis frame is delivered,
//    then asks how many 1/60 s render windows would contain at least one. Not "how many were
//    produced" — how many a renderer could tell apart. Bunched deliveries fail it by construction,
//    which is exactly what slicing did.
//
// Usage:
//   RATE_SESSION=~/Documents/uzume_sessions/<dir> \
//     swift test --package-path UzumeEngine --filter AnalysisRateGate
//   swift test --package-path UzumeEngine --filter AnalysisRateGate
import Testing
import Foundation
import AVFoundation
@testable import Audio

@Suite("AnalysisRateGate (BUG087.4)")
struct AnalysisRateGateTests {

    /// The floor BUG087.4 committed to. Local-file sessions measured 10.1 Hz; streaming, which
    /// this increment does not touch, measures 58.8 Hz against a 59.9 fps render.
    static let floorHz = 50.0

    /// Columns that are continuous primitives — they change on every analysis frame when the
    /// music is not silent, so their change rate IS the analysis rate. Beat and mood fields are
    /// deliberately excluded: they are quantised or slow by design, so a low rate there says
    /// nothing about the clock.
    static let columns = ["bass", "mid", "treble", "spectralCentroid", "spectralFlux"]

    // MARK: - The product gate: a real recorded session

    @Test("A recorded local-file session's columns change at >= 50 Hz (RATE_SESSION=<dir>)")
    func sessionRateGate() throws {
        guard let dir = ProcessInfo.processInfo.environment["RATE_SESSION"] else {
            print("[rate] set RATE_SESSION=<session dir> to gate a real capture")
            return
        }
        let csv = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            .appendingPathComponent("features.csv")
        let (times, columns) = try Self.loadColumns(csv, names: Self.columns)
        try #require(times.count > 500, "features.csv too short to measure a rate")
        let span = times[times.count - 1] - times[0]
        try #require(span > 5, "capture spans only \(span) s")

        print(String(format: "[rate] %@\n[rate]   %d rows over %.2f s — render %.2f fps",
                     csv.path, times.count, span, Double(times.count) / span))
        var worst = Double.infinity
        for name in Self.columns {
            guard let values = columns[name] else {
                print("[rate]   \(name): COLUMN ABSENT")
                continue
            }
            // Distinct-value transitions between consecutive RENDERED rows — not analyser calls.
            var changes = 0
            for i in 1..<values.count where values[i] != values[i - 1] { changes += 1 }
            let hz = Double(changes) / span
            let label = name.padding(toLength: 18, withPad: " ", startingAt: 0)
            print(String(format: "[rate]   %@ %5d changes  %6.2f Hz", label, changes, hz))
            worst = min(worst, hz)
        }
        try #require(worst.isFinite, "no measurable column present")
        let slowest = String(format: "%.2f", worst)
        #expect(worst >= Self.floorHz,
                "slowest continuous column changes at \(slowest) Hz, floor is \(Self.floorHz) Hz")
    }

    // MARK: - The mechanism gate: delivery spacing, under the flag

    @available(macOS 14.2, *)
    @Test("Deliveries land in distinct render windows", .timeLimit(.minutes(1)))
    func deliveryRateGate() throws {
        let url = try PlayheadAnalysisClockTests.writeRamp(frames: 44_100 * 2)
        defer { try? FileManager.default.removeItem(at: url) }

        let arrivals = Arrivals()
        let provider = LocalFilePlaybackProvider(url: url)
        provider.onAudioSamples = { _, _, _, _ in arrivals.record() }
        try provider.start()
        Thread.sleep(forTimeInterval: 3.0)
        provider.stop()

        let times = arrivals.snapshot()
        // BUG087.5: the clock is the ONLY analysis source on this path, so too few deliveries is
        // silence reaching every preset, not a slower fallback.
        let seen = times.count
        try #require(seen > 100, "only \(seen) deliveries — this is silence, not a slower fallback")
        let span = times[times.count - 1] - times[0]

        // ★ The observed rate, simulated honestly: bucket deliveries into 1/60 s render windows
        // and count the windows that got at least one. Five deliveries in one window are worth
        // one update to a preset, which is precisely what BUG087.3's slice count could not see.
        let renderPeriod = 1.0 / 59.8
        var occupied = Set<Int>()
        for t in times { occupied.insert(Int((t - times[0]) / renderPeriod)) }
        let observedHz = Double(occupied.count) / span
        let producedHz = Double(times.count) / span

        var gaps = times.indices.dropFirst().map { (times[$0] - times[$0 - 1]) * 1000 }
        gaps.sort()
        let bunched = gaps.filter { $0 < 2.0 }.count

        print(String(
            format: "[rate] clock delivery over %.2f s: produced %.1f Hz, OBSERVED %.1f Hz | "
                + "gap median %.1f ms p95 %.1f ms | bunched (<2 ms) %d of %d",
            span, producedHz, observedHz,
            gaps[gaps.count / 2], gaps[Int(Double(gaps.count) * 0.95)], bunched, gaps.count))

        #expect(observedHz >= Self.floorHz,
                "a 59.8 fps render would see \(String(format: "%.1f", observedHz)) Hz")
        // The slicing signature: deliveries stacked in one instant. It must be absent, or the
        // produced rate is again lying about what a preset sees.
        #expect(Double(bunched) / Double(gaps.count) < 0.05,
                "\(bunched)/\(gaps.count) deliveries arrived bunched — the BUG087.3 failure shape")
    }

    // MARK: - Helpers

    private final class Arrivals: @unchecked Sendable {
        private let lock = NSLock()
        private var times: [Double] = []
        func record() {
            let now = CACurrentMediaTime()
            lock.withLock { times.append(now) }
        }
        func snapshot() -> [Double] { lock.withLock { times } }
    }

    /// Read `wallclock_s` plus the named columns as raw STRINGS — the comparison that matters is
    /// "did the recorded text change", and parsing to Float would merge values that differ below
    /// print precision, understating the rate.
    static func loadColumns(_ url: URL, names: [String]) throws -> ([Double], [String: [String]]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return ([], [:]) }
        let header = lines.removeFirst()
            .split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let ti = header.firstIndex(of: "wallclock_s") else { return ([], [:]) }
        let indices = names.compactMap { name in header.firstIndex(of: name).map { (name, $0) } }
        var times: [Double] = []
        var out: [String: [String]] = [:]
        for line in lines {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count > ti, let t = Double(f[ti]) else { continue }
            times.append(t)
            for (name, i) in indices where f.count > i {
                out[name, default: []].append(String(f[i]))
            }
        }
        return (times, out)
    }
}
