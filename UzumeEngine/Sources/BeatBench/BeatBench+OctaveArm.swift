// BeatBench+OctaveArm.swift — BUG-134 A/B arm.
//
// Lives in its own file because BeatBench.swift sits at SwiftLint's 400-line cap;
// adding the arm inline pushed it over, and shaving explanatory comments to fit a
// line count is the wrong trade.
//
// `UZUME_GRID_OCTAVE_FIX=1` scores the grid the APP installs — isolated dropped
// beats filled — instead of the analyzer's raw output, so the mandatory five-suite
// before/after (beat-sync program house rule) is one flag on one binary rather than
// two builds that might differ in other ways.
//
// Default OFF: the benchmark's baseline must stay the analyzer's own result.

import Foundation
import DSP

extension BeatBenchCommand {
    static let gridOctaveFixOn =
        ProcessInfo.processInfo.environment["UZUME_GRID_OCTAVE_FIX"] == "1"

    /// The grid to score for this arm.
    static func scoredGrid(_ raw: BeatGrid) -> BeatGrid {
        gridOctaveFixOn ? raw.octaveUnified() : raw
    }
}
