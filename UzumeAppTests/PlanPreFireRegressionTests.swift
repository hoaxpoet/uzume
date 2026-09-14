// PlanPreFireRegressionTests — BUG-132.
//
// A plan rebuild pre-fires the plan's FIRST track into the live pipeline: it resets the stem
// pipeline and installs that track's `BeatGrid`. That is right before a session starts — it is how
// Spectral Cartograph shows "PLANNED · UNLOCKED" straight after plan-build (DSP.3.2) — and wrong
// once one is playing, because a rebuild decides what plays NEXT.
//
// It was harmless while the plan was built once per session. PREP.2 rebuilds it once per PREPARED
// track, so a walk running behind an early start fires it repeatedly. Measured on session
// `2026-09-14T13-49-57Z`: five of nine rebuilds installed track 1's 164.4 BPM grid over a different
// playing track, and `grid_bpm` stayed wrong until the next track change — 13,190 frames inside a
// 175.0 BPM track and 13,928 inside a 108.0 BPM track in 3/4.
//
// ⚠ **Two halves, deliberately.** The policy is a pure function of `SessionState`, unit-tested here
// over every case; the WIRE is a source-presence assertion, because `_buildPlan` is `@MainActor` on
// `VisualizerEngine` and needs a Metal device, a session manager and a preset loader to reach. A
// correct policy with no call site is exactly BUG-015, which is why the second half exists at all.
//
// (BUG-132's own verification criteria named `LocalFileEarlyStartTests` as the home for this. That
// was written before checking where the code lives: that suite is in the ENGINE and `_buildPlan` is
// in the APP, so an engine test cannot reach it. Recorded rather than quietly re-scoped.)

import Foundation
import Testing
@testable import UzumeApp
import Session

@Suite("PlanPreFireRegression (BUG-132)")
struct PlanPreFireRegressionTests {

    // MARK: - The policy

    @Test("A plan rebuilt while playing must not pre-fire into the live pipeline")
    func playingSuppressesPreFire() {
        #expect(VisualizerEngine.shouldPreFirePlan(sessionState: .playing) == false)
    }

    @Test("Every non-playing state still pre-fires — the priming this exists for is pre-playback")
    func nonPlayingStatesStillPreFire() {
        for state: SessionState in [.idle, .connecting, .preparing, .ready, .ended] {
            #expect(VisualizerEngine.shouldPreFirePlan(sessionState: state),
                    """
                    state \(state.rawValue) must still pre-fire — suppressing it would cost \
                    the DSP.3.2 priming this call exists for
                    """)
        }
    }

    // MARK: - The wire

    /// Strip `//` and `/* … */` comments so a source-presence assertion cannot be satisfied by a
    /// doc comment that merely names the symbol (the sibling BUG-015 test learned this first).
    private static func strippingComments(_ src: String) -> String {
        var out = ""
        var i = src.startIndex
        var inBlock = false
        while i < src.endIndex {
            let rest = src[i...]
            if inBlock {
                if rest.hasPrefix("*/") {
                    inBlock = false
                    i = src.index(i, offsetBy: 2)
                } else {
                    i = src.index(after: i)
                }
            } else if rest.hasPrefix("/*") {
                inBlock = true; i = src.index(i, offsetBy: 2)
            } else if rest.hasPrefix("//") {
                while i < src.endIndex, src[i] != "\n" { i = src.index(after: i) }
            } else {
                out.append(src[i]); i = src.index(after: i)
            }
        }
        return out
    }

    @Test("_buildPlan actually consults the policy before pre-firing")
    func buildPlanConsultsThePolicy() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("UzumeApp").path) {
            let parent = dir.deletingLastPathComponent()
            try #require(parent != dir, "could not locate repo root from \(#filePath)")
            dir = parent
        }
        let raw = try String(contentsOf: dir.appendingPathComponent(
            "UzumeApp/VisualizerEngine+Orchestrator.swift"), encoding: .utf8)
        let source = Self.strippingComments(raw)

        // The guard must sit on the same call the defect went through: `resetStemPipeline`
        // with `caller: .preFire`.
        try #require(source.contains("resetStemPipeline(for: firstTrack, caller: .preFire)"),
                     "the pre-fire call site moved — re-point this test at it")

        // ⚠ Match the CALL, not the declaration. The first version of this test looked for
        // "shouldPreFirePlan(sessionState:", which the `static func` line satisfies all by
        // itself — so it passed against a deliberately reverted guard. That is BUG-015's shape
        // exactly (a tested policy with no call site), caught only by running the revert.
        #expect(source.contains("Self.shouldPreFirePlan("),
                """
                _buildPlan no longer CALLS shouldPreFirePlan — the policy is dead code and \
                BUG-132 is back (a rebuild behind a playing session clobbers its BeatGrid)
                """)
    }
}
