// SessionPreparer+StemSeries — the full-file stem sweep (LFSTEM.1).
//
// Split from `SessionPreparer+Analysis.swift`, which was at its 400-line cap. The sweep is a
// self-contained pass over one decoded file and shares nothing with `analyzePreview` beyond
// the separator and analyzer it is handed.

import Foundation
import Audio
import DSP
import Shared

extension SessionPreparer {

    // MARK: - Full-file stem series (LFSTEM.1)

    /// Analysis hop the live path uses, and therefore the series grid.
    /// `VisualizerEngine+Audio.runPerFrameStemAnalysis` slides a 1024-sample window; a series
    /// on any coarser grid would not be a drop-in for what presets already consume.
    nonisolated static let seriesAnalysisHop = 1024

    /// Build a dense `StemFeatureSeries` covering the whole of `samples`.
    ///
    /// **The point of this function.** Live separation is late by construction: it can only
    /// analyse audio that has already played, so stem features reach presets ~2.5 s behind the
    /// music. Given the whole file up front — which local-file preparation already decodes —
    /// there is no reason to be late. Each frame is computed offline and handed to the renderer
    /// at the playback second it describes.
    ///
    /// **Window placement, which is the part that matters.** The separator works on a fixed
    /// window (~10 s). Rather than analysing each window whole and discarding most of it, this
    /// sweeps *kept spans* of `hopSeconds` in playback order and places each span at the END of
    /// its separation window wherever the audio allows:
    ///
    /// ```
    ///   window k:  [------------- ~10 s -------------]
    ///   kept:                                [ hop  ]
    /// ```
    ///
    /// That is deliberately the same relative position the live path reads from — live analyses
    /// the newest slice of the most recent separation — so the series carries the same character
    /// as the values presets were tuned against, only arriving on time instead of late. Near the
    /// start of the file the window cannot be pushed earlier, so the span sits wherever it falls
    /// inside the first window; those frames see less preceding context, exactly as they do live
    /// at track start.
    ///
    /// **AGC continuity.** One analyzer instance sweeps every span in playback order, so its
    /// band-energy AGC carries across span boundaries the way it does across live separations.
    /// Analysing spans independently would restart the AGC 120 times and put a discontinuity at
    /// every hop.
    ///
    /// - Parameters:
    ///   - samples: Fully decoded mono PCM for the whole track.
    ///   - sampleRate: Sample rate of `samples`.
    ///   - separator: Production separator. Its window length is read from the first result
    ///     rather than assumed, so a test double with a different window still works.
    ///   - analyzer: A FRESH analyzer — this function relies on owning its AGC state.
    ///   - hopSeconds: Playback seconds each separation contributes. 2.0 matches the live
    ///     separation period, so the offline sweep does the same amount of model work per second
    ///     of audio that live playback would.
    ///   - probe: PREP.3 — records `sweep_separate` / `sweep_analyze` sub-stages when enabled.
    /// - Returns: The series, or `.empty` when there is too little audio to analyse.
    nonisolated public static func analyzeStemSeries(
        samples: [Float],
        sampleRate: Int,
        separator: any StemSeparating,
        analyzer: any StemAnalyzing,
        hopSeconds: Double = 2.0,
        probe: PrepStageProbe = .disabled
    ) throws -> StemFeatureSeries {
        let hop = Self.seriesAnalysisHop
        guard sampleRate > 0, hopSeconds > 0 else { return .empty }

        let (samples, sampleRate) = workingAudio(samples, sampleRate: sampleRate, separator: separator)
        let sampleCount = samples.count
        guard sampleCount >= hop else { return .empty }

        let fps = Float(sampleRate) / Float(hop)
        let hopSamples = max(hop, Int(hopSeconds * Double(sampleRate)))
        let frameCount = sampleCount / hop
        var frames: [StemFeatures] = []
        frames.reserveCapacity(frameCount)

        let grid = SweepGrid(sampleCount: sampleCount, hop: hop, hopSamples: hopSamples)
        var separateTime = SweepSubStages.Total()
        var analyzeTime = SweepSubStages.Total()
        defer { SweepSubStages.record(probe: probe, separate: separateTime, analyze: analyzeTime) }
        let rate = Float(sampleRate)

        // The first window is separated alone: its result's length IS the separator's window
        // (it pads or truncates to its own), which places every window after it. Reading it
        // keeps a test double with a different window working.
        let first = SweepWindow(spanStart: 0, windowStart: 0, windowEnd: sampleCount)
        let firstResult = try SweepSubStages.time(&separateTime, probe) {
            try separator.separate(audio: grid.audio(first, samples), channelCount: 1, sampleRate: rate)
        }
        guard let windowSamples = firstResult.stemWaveforms.first?.count, windowSamples >= hop else {
            return .empty
        }
        SweepSubStages.time(&analyzeTime, probe) {
            grid.analyzeSpan(first, stems: firstResult.stemWaveforms, into: &frames, analyzer: analyzer, fps: fps)
        }

        // PREP.3 — every later window, in groups of `sweepBatchSize` per model run, with the
        // GPU separating group k+1 while this thread analyses group k's kept spans IN PLAYBACK
        // ORDER on the one analyzer (its AGC must sweep in order; separation is stateless).
        let groups = grid.windows(after: first, windowSamples: windowSamples).chunked(Self.sweepBatchSize)
        let separateGroup: @Sendable ([SweepWindow]) throws -> TimedSeparation = { group in
            var total = SweepSubStages.Total()
            let results = try SweepSubStages.time(&total, probe) {
                try separator.separateBatch(monoWindows: group.map { grid.audio($0, samples) }, sampleRate: rate)
            }
            return TimedSeparation(results: results, time: total)
        }
        var pending = groups.first.map { group in BackgroundJob { try separateGroup(group) } }
        for (index, group) in groups.enumerated() {
            guard let job = pending else { break }
            let separated = try job.join()
            separateTime.add(separated.time)
            pending = index + 1 < groups.count
                ? BackgroundJob { [upcoming = groups[index + 1]] in try separateGroup(upcoming) }
                : nil
            var valid = true
            SweepSubStages.time(&analyzeTime, probe) {
                for (window, result) in zip(group, separated.results) {
                    guard let length = result.stemWaveforms.first?.count, length >= hop else { valid = false; return }
                    grid.analyzeSpan(window, stems: result.stemWaveforms, into: &frames, analyzer: analyzer, fps: fps)
                }
            }
            guard valid else {
                _ = try? pending?.join()
                return .empty
            }
        }

        guard !frames.isEmpty else { return .empty }
        return StemFeatureSeries(frames: frames, hopSeconds: Double(hop) / Double(sampleRate))
    }

    /// The audio the sweep works on, in the separator's time base (BUG-116).
    nonisolated static func workingAudio(
        _ samples: [Float], sampleRate: Int, separator: any StemSeparating
    ) -> (samples: [Float], rate: Int) {
        // BUG-116 — work in the SEPARATOR's time base, not the caller's.
        //
        // `separate` resamples any input to its own model rate and pads to a fixed sample
        // count, so its output is in that rate whatever it was handed. Every offset in the
        // sweep is an index into that output, so feeding it audio at some other rate makes the two
        // disagree: at 48 kHz a 440,320-sample window holds 9.17 s of audio, which resamples
        // to 404,544 samples, and the remaining 35,776 are ZERO PADDING. The kept span sits
        // at the window's tail by design, so it landed squarely in that padding — all four
        // stems reading 0.000 for ~0.4 s out of every 2 s, on every non-44.1 kHz local file
        // since LFSTEM.1 (2026-08-26). Matt saw it as Ferrofluid Ocean going dark on a beat.
        //
        // Resampling once here makes the separator's internal resample a no-op and every
        // offset exact. `hopSeconds` then reports the frame grid in the working rate, which
        // is what `sample(atPlaybackSeconds:)` divides by, so playback alignment is unchanged.
        let workingSamples: [Float]
        let workingRate: Int
        if let outputRate = separator.outputSampleRate,
           abs(Double(outputRate) - Double(sampleRate)) > 1 {
            workingSamples = BeatThisPreprocessor.resample(
                samples, from: Double(sampleRate), to: Double(outputRate))
            workingRate = Int(outputRate.rounded())
        } else {
            workingSamples = samples
            workingRate = sampleRate
        }
        return (workingSamples, workingRate)
    }
}

// MARK: - Sweep batching (PREP.3)

extension SessionPreparer {
    // ponytail: process-wide knob, written once at startup by the measurement CLI only.
    /// Windows per batched model run in the sweep. Chosen by measurement (PREP.3 N sweep,
    /// `docs/diagnostics/PREP3_PREPARATION_THROUGHPUT_2026-09-30.md`); settable only so
    /// `PrepTimingRunner` can measure other values.
    nonisolated(unsafe) public static var sweepBatchSize = 8
}

/// One separation window of the sweep and the kept span it contributes.
struct SweepWindow {
    let spanStart: Int
    let windowStart: Int
    let windowEnd: Int
}

/// The sweep's placement arithmetic and per-span analysis, unchanged from LFSTEM.1 — only
/// pulled out of the loop so windows can be separated in groups.
struct SweepGrid {
    let sampleCount: Int
    let hop: Int
    let hopSamples: Int

    /// Every window after `first`, placed as LFSTEM.1 places them. Place the kept span at the
    /// window's end where the audio allows it — but leave ONE analysis frame of room past the
    /// span, or the frame starting on the span's last sample has no 1024 samples left inside
    /// the window and is silently dropped. That cost 10 of 1292 frames over 30 s before
    /// `stemSeries_spanBoundariesDoNotDrift` caught it: a per-span shortfall, invisible in any
    /// single span, compounding.
    func windows(after first: SweepWindow, windowSamples: Int) -> [SweepWindow] {
        stride(from: first.spanStart + hopSamples, to: sampleCount, by: hopSamples).map { spanStart in
            let windowStart = max(0, spanStart + hopSamples + hop - windowSamples)
            return SweepWindow(
                spanStart: spanStart,
                windowStart: windowStart,
                windowEnd: min(sampleCount, windowStart + windowSamples))
        }
    }

    func audio(_ window: SweepWindow, _ samples: [Float]) -> [Float] {
        Array(samples[window.windowStart..<max(window.windowStart, window.windowEnd)])
    }

    /// Emit every frame of the global 1024-sample grid whose start falls in this span.
    /// Indexing globally (rather than counting within the span) keeps the grid uniform even
    /// though hopSamples is not a whole number of analysis frames.
    func analyzeSpan(
        _ window: SweepWindow,
        stems: [[Float]],
        into frames: inout [StemFeatures],
        analyzer: any StemAnalyzing,
        fps: Float
    ) {
        let stemLength = stems.first?.count ?? 0
        let firstFrame = Int(ceil(Double(window.spanStart) / Double(hop)))
        let spanEnd = min(window.spanStart + hopSamples, sampleCount)
        var frameIndex = max(firstFrame, frames.count)
        while frameIndex * hop < spanEnd {
            let absolute = frameIndex * hop
            guard absolute + hop <= sampleCount else { break }
            let offset = absolute - window.windowStart
            guard offset >= 0, offset + hop <= stemLength else { break }
            let slice = stems.map { Array($0[offset..<(offset + hop)]) }
            frames.append(analyzer.analyze(stemWaveforms: slice, fps: fps))
            frameIndex += 1
        }
    }
}

extension Array {
    /// Consecutive slices of at most `size` elements.
    func chunked(_ size: Int) -> [[Element]] {
        let step = Swift.max(1, size)
        return stride(from: 0, to: count, by: step).map { Array(self[$0..<Swift.min($0 + step, count)]) }
    }
}

/// A group's separations and the time they took on the background thread.
struct TimedSeparation: Sendable {
    let results: [StemSeparationResult]
    let time: SweepSubStages.Total
}

/// Runs `work` on its own thread while the caller carries on; `join()` waits for it. The
/// sweep's one use: separate the next window group while this thread analyses the current one.
/// A thread rather than a task because the sweep is synchronous code on a detached task and
/// the work is a blocking GPU wait — it should not sit on a cooperative-pool thread.
final class BackgroundJob<T: Sendable>: @unchecked Sendable {
    private var result: Result<T, Error>?
    private let done = DispatchSemaphore(value: 0)

    init(_ work: @escaping @Sendable () throws -> T) {
        let thread = Thread { [self] in
            result = Result { try work() }
            done.signal()
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    /// Wait for the work; rethrows its error. Call once.
    func join() throws -> T {
        done.wait()
        guard let result else { throw CancellationError() }
        return try result.get()
    }
}

// MARK: - Sweep sub-stage timing (PREP.3)

/// Wall + CPU totals for the sweep's two halves, recorded once per track. Per-call rows would
/// be ~100 per track; the report needs only the split. The halves overlap in time since PREP.3
/// (the GPU separates the next group while the analyzer runs), so their sum exceeds the sweep.
enum SweepSubStages {
    struct Total: Sendable {
        var wallMs = 0.0
        var cpuMs = 0.0

        mutating func add(_ other: Total) {
            wallMs += other.wallMs
            cpuMs += other.cpuMs
        }
    }

    static func time<T>(_ total: inout Total, _ probe: PrepStageProbe, _ body: () throws -> T) rethrows -> T {
        guard probe.isEnabled else { return try body() }
        let wall0 = Date()
        let cpu0 = PrepStageSink.cpuSeconds()
        defer {
            total.wallMs += Date().timeIntervalSince(wall0) * 1000
            total.cpuMs += (PrepStageSink.cpuSeconds() - cpu0) * 1000
        }
        return try body()
    }

    static func record(probe: PrepStageProbe, separate: Total, analyze: Total) {
        guard probe.isEnabled else { return }
        probe.record(PrepStage.sweepSeparate, wallMs: separate.wallMs, cpuMs: separate.cpuMs)
        probe.record(PrepStage.sweepAnalyze, wallMs: analyze.wallMs, cpuMs: analyze.cpuMs)
    }
}
