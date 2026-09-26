// SessionPreparer+WiringLogs — Extracted to keep SessionPreparer.swift under
// the SwiftLint 400-line gate (BUG-008.2). Holds the per-track summary line
// emitted at the end of every prepare(), the BUG-006.1 WIRING: instrumentation
// (cleanup tracked under QR.5), and the BPM-mismatch warnings (2-way BUG-008.2
// and 3-way DSP.4).

import Foundation
import os.log

extension SessionPreparer {

    /// Emit per-track BeatGrid summaries plus the DONE line. Extracted from
    /// `_runPreparation` to keep that function within the 60-line SwiftLint gate.
    func logWiringDoneSummary(
        cachedTracks: [TrackIdentity],
        failedTracks: [TrackIdentity]
    ) {
        var withGrid = 0
        var emptyGrid = 0
        for track in cachedTracks {
            if let grid = cache.beatGrid(for: track), !grid.beats.isEmpty {
                withGrid += 1
                let bpmStr = String(format: "%.1f", grid.bpm)
                let beatCount = grid.beats.count
                sessionRecorder?.log(
                    "WIRING: SessionPreparer.beatGrid track='\(track.title)' " +
                    "bpm=\(bpmStr) beats=\(beatCount) isEmpty=false"
                )
            } else {
                emptyGrid += 1
                sessionRecorder?.log(
                    "WIRING: SessionPreparer.beatGrid track='\(track.title)' " +
                    "bpm=0 beats=0 isEmpty=true"
                )
            }
            logDrumsBeatGridLine(track: track)
        }
        let doneMsg = "WIRING: SessionPreparer.prepare DONE prepared=\(cachedTracks.count) " +
            "withGrid=\(withGrid) empty=\(emptyGrid) failed=\(failedTracks.count)"
        sessionRecorder?.log(doneMsg)
        wiringLogsLogger.info("\(doneMsg, privacy: .public)")
    }

    // MARK: - DSP.4 Drums BeatGrid

    /// Emit a `WIRING: SessionPreparer.drumsBeatGrid` line for every prepared track.
    /// Diagnostic-only — the live drift tracker does not consume this grid.
    fileprivate func logDrumsBeatGridLine(track: TrackIdentity) {
        if let grid = cache.drumsBeatGrid(for: track), !grid.beats.isEmpty {
            let bpmStr = String(format: "%.1f", grid.bpm)
            let beatCount = grid.beats.count
            sessionRecorder?.log(
                "WIRING: SessionPreparer.drumsBeatGrid track='\(track.title)' " +
                "bpm=\(bpmStr) beats=\(beatCount) isEmpty=false"
            )
        } else {
            sessionRecorder?.log(
                "WIRING: SessionPreparer.drumsBeatGrid track='\(track.title)' " +
                "bpm=0 beats=0 isEmpty=true"
            )
        }
    }
}

private let wiringLogsLogger = Logger(subsystem: "io.uzume", category: "SessionPreparer.WiringLogs")
