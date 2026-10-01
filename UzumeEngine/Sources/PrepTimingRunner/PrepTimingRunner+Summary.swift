// PrepTimingRunner+Summary — the summary table, plus PREP.3's sweep sub-stages and the
// per-separation split. Split from `PrepTimingRunner.swift` at PREP.3 (400-line cap).
//
// The sub-stages sit inside `stem_series_sweep`'s wall clock, so they print beneath the stage
// table rather than being summed into it.

import Foundation
import Shared

// MARK: - Summary

/// Everything the report's tables need, derived from the rows rather than
/// recomputed by hand: per-stage share of wall clock, cores held, and cost per
/// second of decoded audio.
struct Summary {
    let rows: [PrepStageRow]
    let wallSeconds: Double
    let trackCount: Int

    func write(to url: URL, alsoPrinting: Bool) {
        let text = render()
        try? text.write(to: url, atomically: true, encoding: .utf8)
        if alsoPrinting { print(text) }
    }

    private func render() -> String {
        let totals = rows.filter { $0.stage == PrepStage.trackTotal }
        let audioSeconds = totals.reduce(0) { $0 + $1.audioSeconds }
        let trackWall = totals.reduce(0) { $0 + $1.wallMs } / 1000
        let perTrack = wallSeconds / Double(max(trackCount, 1))
        let perAudioSecond = audioSeconds > 0 ? wallSeconds / audioSeconds : 0
        let totalShare = wallSeconds > 0 ? trackWall / wallSeconds * 100 : 0

        var out = "tracks                 \(trackCount)\n"
        out += String(format: "audio decoded          %.1f s (%.1f min)\n", audioSeconds, audioSeconds / 60)
        out += String(format: "wall clock             %.1f s\n", wallSeconds)
        out += String(format: "per track              %.1f s\n", perTrack)
        out += String(format: "per second of audio    %.3f s\n", perAudioSecond)
        out += String(format: "sum of TRACK_TOTAL     %.1f s (%.0f%% of wall)\n", trackWall, totalShare)
        out += "\nstage                     wall_s   share   cores   ms/audio_s\n"

        let stages = stageTotals(audioSeconds: audioSeconds)
        let stageWall = stages.reduce(0) { $0 + $1.wallSeconds }
        for stage in stages.sorted(by: { $0.wallSeconds > $1.wallSeconds }) {
            let share = stageWall > 0 ? stage.wallSeconds / stageWall * 100 : 0
            let numbers = String(
                format: " %7.1f  %5.1f%%  %6.2f  %10.1f\n",
                stage.wallSeconds,
                share,
                stage.cores,
                stage.msPerAudioSecond)
            out += pad(stage.name) + numbers
        }
        out += pad("SUM OF STAGES") + String(format: " %7.1f\n", stageWall)
        out += subStageLines(audioSeconds: audioSeconds)
        if trackWall > 0 {
            let remainder = trackWall - stageWall
            out += String(
                format: "unattributed remainder   %7.1f s (%.1f%% of per-track wall)\n",
                remainder,
                remainder / trackWall * 100)
        }
        return out
    }

    /// One row of the stage table. A named type rather than a tuple so the four
    /// numbers cannot be swapped at a call site.
    private struct StageTotal {
        let name: String
        let wallSeconds: Double
        let cores: Double
        let msPerAudioSecond: Double
    }

    private func stageTotals(audioSeconds: Double) -> [StageTotal] {
        stageOrder.compactMap { stage in
            let matching = rows.filter { $0.stage == stage }
            guard !matching.isEmpty else { return nil }
            let wall = matching.reduce(0) { $0 + $1.wallMs } / 1000
            let cpu = matching.reduce(0) { $0 + $1.cpuMs } / 1000
            return StageTotal(
                name: stage,
                wallSeconds: wall,
                cores: wall > 0 ? cpu / wall : 0,
                msPerAudioSecond: audioSeconds > 0 ? wall * 1000 / audioSeconds : 0)
        }
    }

    func pad(_ text: String, to width: Int = 24) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    private var stageOrder: [String] {
        [
            PrepStage.contentHash, PrepStage.cacheProbe, PrepStage.metadata, PrepStage.decode,
            PrepStage.loudness, PrepStage.stemSeparation, PrepStage.stemWarmup, PrepStage.mir,
            PrepStage.beatGrid, PrepStage.gridOnsetCalibration, PrepStage.instrumentFamily,
            PrepStage.stemSeries, PrepStage.cacheWrite,
        ]
    }
}

extension Summary {

    /// The sweep's two halves, and one separation split into its parts.
    func subStageLines(audioSeconds: Double) -> String {
        var out = ""
        for stage in [PrepStage.sweepSeparate, PrepStage.sweepAnalyze] {
            let matching = rows.filter { $0.stage == stage }
            guard !matching.isEmpty else { continue }
            let wall = matching.reduce(0) { $0 + $1.wallMs } / 1000
            let cpu = matching.reduce(0) { $0 + $1.cpuMs } / 1000
            let cores = wall > 0 ? cpu / wall : 0
            let perAudio = audioSeconds > 0 ? wall * 1000 / audioSeconds : 0
            out += pad("  ↳ " + stage) + String(format: " %7.1f          %6.2f  %10.1f\n", wall, cores, perAudio)
        }
        let split = SeparationSplit.snapshot
        guard !split.isEmpty else { return out }
        out += "\nseparation part           total_s   calls   ms/call\n"
        for part in split {
            let perCall = part.ms / Double(max(part.count, 1))
            out += pad(part.part) + String(format: " %7.1f  %6d  %8.2f\n", part.ms / 1000, part.count, perCall)
        }
        return out
    }
}
