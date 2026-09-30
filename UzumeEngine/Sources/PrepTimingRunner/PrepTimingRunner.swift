// PrepTimingRunner — PREP.1 preparation-cost measurement CLI.
//
// D-242 set a 7.5 s/track budget for session preparation and recorded that
// nobody knows which stage spends the 50 s/track the local path actually
// costs. This runs the shipping pipeline — `LocalFilePreparationPipeline`,
// the same code `VisualizerEngine.prepareLocalFile(url:)` calls — over a list
// of audio files with `UZUME_PREP_TIMING=1`, and writes the per-stage
// `preparation.csv` plus a summary to stdout.
//
// It exists because the alternative is driving the GUI, and because a runner
// that re-implements the stage list measures a copy of the pipeline rather
// than the pipeline. Nothing here decides what the pipeline does; it only
// supplies the dependencies the app layer normally supplies.
//
// Usage:
//
//   swift run -c release PrepTimingRunner \
//     --cache /tmp/prep-cold --out /tmp/prep-run-1 \
//     "/path/to/01.flac" "/path/to/02.flac" …
//
//   # streaming control — the shared analyzePreview over a 30 s window
//   swift run -c release PrepTimingRunner --preview-seconds 30 …
//
//   # does running two tracks at once overlap, or merely contend?
//   swift run -c release PrepTimingRunner --concurrency 2 …
//
// `--cache` MUST be a scratch directory. The runner never writes to the real
// `~/Library/Application Support/Uzume/StemCache`; a cold run is the point,
// and Matt's cache is not test scaffolding.

import ArgumentParser
import Audio
import DSP
import Foundation
import ML
import Metal
import Session
import Shared

// MARK: - Command

@main
struct PrepTimingRunner: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "prep-timing-runner",
        abstract: "Time every stage of session preparation over a list of audio files (PREP.1 / D-242)."
    )

    @Argument(help: "Audio files to prepare, in order.")
    var files: [String] = []

    @Option(name: .long, help: "Folder to take audio files from instead of listing them.")
    var folder: String?

    @Option(name: .long, help: "Scratch directory for the cold persistent stem cache. REQUIRED.")
    var cache: String

    @Option(name: .long, help: "Directory to write preparation.csv into.")
    var out: String

    @Option(name: .long, help: "Tracks prepared at once. 1 (default) is the shipping serial loop.")
    var concurrency: Int = 1

    @Option(name: .long, help: "Stop after this many files.")
    var limit: Int?

    @Option(
        name: .long,
        help: "Streaming control: analyse only the first N seconds through the shared analyzePreview."
    )
    var previewSeconds: Double?

    @Option(name: .long, help: "PREP.3: capture stem-series goldens for the input files into this directory.")
    var goldenCapture: String?

    @Option(
        name: .long,
        help: "PREP.3: re-run the sweep for every golden in this directory and compare (parity.* in --out).")
    var goldenCompare: String?

    @Flag(name: .long, help: "Write the summary to disk only; no progress on stderr.")
    var quiet: Bool = false

    @Flag(
        name: .long,
        help: "Run with the timing probe OFF, to measure what the instrumentation itself costs."
    )
    var disableProbe: Bool = false

    // MARK: Run

    mutating func run() async throws {
        guard PrepStageSink.isEnabled || disableProbe else {
            throw ValidationError(
                "UZUME_PREP_TIMING=1 must be set — the timing probe is gated on it. "
                + "Re-run as: UZUME_PREP_TIMING=1 swift run …"
            )
        }

        let urls = try resolveInputs()
        guard !urls.isEmpty || goldenCompare != nil else { throw ValidationError("no input files") }

        let cacheRoot = URL(fileURLWithPath: cache, isDirectory: true)
        try assertScratch(cacheRoot)
        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ValidationError("no Metal device")
        }
        if let goldenCapture {
            try GoldenMode.capture(urls: urls, into: URL(fileURLWithPath: goldenCapture), device: device)
            return
        }
        if let goldenCompare {
            let pass = try GoldenMode.compare(goldens: URL(fileURLWithPath: goldenCompare), out: outDir, device: device)
            if !pass { throw ExitCode(1) }
            return
        }

        // --disable-probe is how the gate gets proved with a number rather than
        // an assertion: same files, same build, probe off.
        let sink = disableProbe
            ? nil
            : PrepStageSink(destination: outDir.appendingPathComponent("preparation.csv"))
        let workers = try (0..<max(1, concurrency)).map { _ in
            try Worker(device: device, cacheRoot: cacheRoot)
        }

        note("prep-timing: \(urls.count) file(s) · concurrency=\(concurrency)"
            + (previewSeconds.map { " · preview-window=\($0)s" } ?? " · full local pipeline")
            + " · cache=\(cacheRoot.path)")

        let started = Date()
        if concurrency <= 1 {
            for (index, url) in urls.enumerated() {
                try await prepare(url, worker: workers[0], sink: sink, index: index, of: urls.count)
            }
        } else {
            try await runConcurrently(urls: urls, workers: workers, sink: sink)
        }
        let wall = Date().timeIntervalSince(started)

        sink?.flush()
        Summary(rows: sink?.snapshot ?? [], wallSeconds: wall, trackCount: urls.count)
            .write(to: outDir.appendingPathComponent("summary.txt"), alsoPrinting: !quiet)
    }

    // MARK: One track

    private func prepare(
        _ url: URL,
        worker: Worker,
        sink: PrepStageSink?,
        index: Int,
        of total: Int
    ) async throws {
        let name = url.lastPathComponent
        let started = Date()
        var profileNote = ""
        if let previewSeconds {
            try worker.runPreviewControl(url: url, seconds: previewSeconds, sink: sink)
        } else if let result = await LocalFilePreparationPipeline.run(inputs: worker.inputs(for: url, sink: sink)) {
            // KAG.5 — the profile values Kagura reads: the song's measured energy (D-259) and grid BPM.
            let readout = result.cached.trackProfile.energyCurve?.readout()
            profileNote = String(
                format: "  energy %@ grid %.1f BPM",
                readout.map { "\($0.low) → \($0.high) (typical \($0.typical))" } ?? "none",
                result.cached.beatGrid.bpm
            )
        }
        let elapsed = Date().timeIntervalSince(started)
        note(String(format: "  [%d/%d] %@  %.1f s", index + 1, total, name, elapsed) + profileNote)
    }

    /// Concurrency is a MEASUREMENT here, never a pipeline change: the shipping
    /// loop in `SessionPreparer._runLocalFilePreparation` stays strictly serial.
    /// This mode exists to answer whether two tracks at once would overlap or
    /// merely contend — task 3's question — with a wall-clock number instead of
    /// an inference from CPU percentages.
    private func runConcurrently(urls: [URL], workers: [Worker], sink: PrepStageSink?) async throws {
        var next = 0
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (slot, worker) in workers.enumerated() where slot < urls.count {
                let url = urls[next]
                let index = next
                next += 1
                group.addTask { [self] in
                    try await prepare(url, worker: worker, sink: sink, index: index, of: urls.count)
                }
            }
            var slot = 0
            while try await group.next() != nil {
                guard next < urls.count else { continue }
                let url = urls[next]
                let index = next
                next += 1
                let worker = workers[slot % workers.count]
                slot += 1
                group.addTask { [self] in
                    try await prepare(url, worker: worker, sink: sink, index: index, of: urls.count)
                }
            }
        }
    }

    // MARK: Inputs

    private func resolveInputs() throws -> [URL] {
        var urls = files.map { URL(fileURLWithPath: $0) }
        if let folder {
            let dir = URL(fileURLWithPath: folder, isDirectory: true)
            let contents = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            let audio: Set<String> = ["flac", "m4a", "mp3", "wav", "aiff", "aif", "aac", "alac"]
            urls += contents
                .filter { audio.contains($0.pathExtension.lowercased()) }
                .filter { !$0.lastPathComponent.hasPrefix("._") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        if let limit { urls = Array(urls.prefix(limit)) }
        return urls
    }

    /// A cold run means an empty cache, and an empty cache means the runner is
    /// allowed to create and fill this directory. Refuse anything that looks
    /// like the real one.
    private func assertScratch(_ root: URL) throws {
        let real = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        if let real, root.standardizedFileURL.path.hasPrefix(real.standardizedFileURL.path) {
            throw ValidationError(
                "--cache points inside Application Support (\(root.path)). "
                + "Use a scratch directory; the user's real stem cache is never a test fixture.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func note(_ line: String) {
        guard !quiet else { return }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

// MARK: - Worker

/// One set of the ML dependencies `VisualizerEngine` normally owns. At
/// `--concurrency N` there are N of these, which is what N parallel prepare
/// tasks would need: `StemSeparator` serialises internally (BUG-031), so
/// sharing one would measure the lock rather than the hardware.
private final class Worker: @unchecked Sendable {
    let separator: StemSeparator
    let beatGrid: DefaultBeatGridAnalyzer
    let family: InstrumentFamilyAnalyzer
    let classifier: MoodClassifier
    let cache: PersistentStemCache

    init(device: MTLDevice, cacheRoot: URL) throws {
        separator = try StemSeparator(device: device)
        beatGrid = try DefaultBeatGridAnalyzer(device: device)
        family = try InstrumentFamilyAnalyzer(device: device)
        classifier = MoodClassifier()
        cache = try PersistentStemCache(rootDirectory: cacheRoot)
    }

    func inputs(for url: URL, sink: PrepStageSink?) -> LocalFilePrepWorkerInputs {
        LocalFilePrepWorkerInputs(
            url: url,
            filename: url.lastPathComponent,
            separator: separator,
            analyzer: StemAnalyzer(),
            classifier: classifier,
            beatGridAnalyzer: beatGrid,
            familyAnalyzer: family,
            persistentCache: cache,
            recorder: nil,
            timingSink: sink
        )
    }

    /// The streaming control (PREP.1 task 6). Streaming downloads a 30 s
    /// preview and runs `SessionPreparer.analyzePreview` on it — the same call
    /// the local path makes, minus the two whole-file extras. Decoding a local
    /// file and truncating to the same window isolates the shared analysis cost
    /// from the whole-file cost, on identical material.
    func runPreviewControl(url: URL, seconds: Double, sink: PrepStageSink?) throws {
        let name = url.lastPathComponent
        var probe = PrepStageProbe(sink: sink, track: name)
        let trackStart = Date()
        let trackCPU0 = PrepStageSink.cpuSeconds()

        let full = try probe.measure(PrepStage.decode) {
            try PreviewAudio.fromLocalFile(at: url)
        }
        let wanted = min(full.pcmSamples.count, Int(seconds * Double(full.sampleRate)))
        let window = PreviewAudio(
            trackIdentity: full.trackIdentity,
            pcmSamples: Array(full.pcmSamples.prefix(wanted)),
            sampleRate: full.sampleRate,
            duration: Double(wanted) / Double(full.sampleRate)
        )
        probe = probe.notingAudioSeconds(window.duration)

        _ = try SessionPreparer.analyzePreview(
            window,
            separator: separator,
            analyzer: StemAnalyzer(),
            classifier: classifier,
            beatGridAnalyzer: beatGrid,
            familyAnalyzer: family,
            prefetchedProfile: nil,
            probe: probe
        )
        probe.record(
            PrepStage.trackTotal,
            wallMs: Date().timeIntervalSince(trackStart) * 1000,
            cpuMs: (PrepStageSink.cpuSeconds() - trackCPU0) * 1000
        )
    }
}
