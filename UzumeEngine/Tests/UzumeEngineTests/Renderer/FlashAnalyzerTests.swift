// FlashAnalyzerTests — synthetic self-check for the Harding / WCAG flash analyzer (CLEAN.7.6).
//
// Pins the detector semantics with hand-built luminance sequences at known
// flash rates: dangerous strobes trip, safe motion passes, and the two
// qualifying conditions (≥ 10 % swing, darker state < 0.80) gate correctly.
//
// This is the analyzer's correctness proof. The prompt's intended A/B against
// the FBS "373 events" video material is not runnable — that pre/post video
// was never committed (only 3-band feature CSVs survive). Synthetic sequences
// at known rates prove the detector more precisely than a single real-world
// A/B would, and need no fixtures (worktree-safe).

import Testing
@testable import Renderer

// MARK: - FlashAnalyzerTests

@Suite("Flash Analyzer (Harding / WCAG 2.3.1)")
struct FlashAnalyzerTests {

    /// A square wave alternating `low`/`high` at `hz` for `seconds` at `fps`.
    private func square(low: Double, high: Double, hz: Double, seconds: Double, fps: Double) -> [Double] {
        let count = Int(seconds * fps)
        let halfPeriod = fps / (2 * hz)   // frames per half-cycle
        return (0..<count).map { i in
            (Int(Double(i) / halfPeriod) % 2) == 0 ? low : high
        }
    }

    @Test("Steady luminance produces zero flashes")
    func steadyIsSafe() {
        let r = FlashAnalyzer.analyze(relativeLuminance: Array(repeating: 0.5, count: 120), fps: 60)
        #expect(r.transitionCount == 0)
        #expect(r.peakFlashesPerSecond == 0)
        #expect(r.isSafe)
    }

    @Test("Monotonic ramp produces zero flashes")
    func rampIsSafe() {
        let ramp = (0..<120).map { Double($0) / 119.0 }
        let r = FlashAnalyzer.analyze(relativeLuminance: ramp, fps: 60)
        #expect(r.peakFlashesPerSecond == 0)
        #expect(r.isSafe)
    }

    @Test("6 Hz full-swing strobe is unsafe")
    func fastStrobeIsUnsafe() {
        let s = square(low: 0.1, high: 0.9, hz: 6, seconds: 2, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(!r.isSafe)
        #expect(r.peakFlashesPerSecond > 3.0)
    }

    @Test("2 Hz full-swing flash is safe")
    func slowFlashIsSafe() {
        let s = square(low: 0.1, high: 0.9, hz: 2, seconds: 3, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.isSafe)
        #expect(r.peakFlashesPerSecond <= 3.0)
        #expect(r.peakFlashesPerSecond >= 1.5)   // ~2/s, demonstrably not zero
    }

    // Bracket the 3/s limit without sitting on the float knife-edge of exactly 3.

    @Test("Just below the limit (2.5 Hz) is safe")
    func justBelowLimitIsSafe() {
        let s = square(low: 0.1, high: 0.9, hz: 2.5, seconds: 4, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.isSafe)
        #expect(r.peakFlashesPerSecond >= 2.0 && r.peakFlashesPerSecond <= 3.0)
    }

    @Test("Just above the limit (3.5 Hz) is unsafe")
    func justAboveLimitIsUnsafe() {
        let s = square(low: 0.1, high: 0.9, hz: 3.5, seconds: 4, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(!r.isSafe)
        #expect(r.peakFlashesPerSecond > 3.0)
    }

    @Test("Bright-only flashes (darker state ≥ 0.80) do not count")
    func brightOnlyIsSafe() {
        // 6 Hz, but both states are bright: darker = 0.82 ≥ 0.80 ceiling.
        let s = square(low: 0.82, high: 0.99, hz: 6, seconds: 2, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.transitionCount == 0)
        #expect(r.isSafe)
    }

    @Test("Sub-threshold swing (< 10 %) does not count")
    func subThresholdIsSafe() {
        // 6 Hz, but swing 0.07 < 0.10 → no qualifying transition.
        let s = square(low: 0.45, high: 0.52, hz: 6, seconds: 2, fps: 60)
        let r = FlashAnalyzer.analyze(relativeLuminance: s, fps: 60)
        #expect(r.transitionCount == 0)
        #expect(r.isSafe)
    }
}

// MARK: - BR.20 (I8): regional and saturated-red flashes

/// A 320×180 BGRA frame: mid-grey, with `tile` (a ninth, 3×3 grid index) painted `patch`.
private func frame(grey: UInt8 = 118, tile: Int? = nil, patch: (b: UInt8, g: UInt8, r: UInt8)? = nil) -> [UInt8] {
    let width = 320, height = 180
    var px = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let inTile = tile.map { x * 3 / width == $0 % 3 && y * 3 / height == $0 / 3 } ?? false
            let c = inTile ? (patch ?? (grey, grey, grey)) : (grey, grey, grey)
            px[i] = c.0; px[i + 1] = c.1; px[i + 2] = c.2
        }
    }
    return px
}

@Suite("FlashAnalyzer v2 — regions and red (BR.20)")
struct FlashAnalyzerV2Tests {

    /// 60 fps, the patch toggling every `period` frames for 3 s.
    private func sequence(period: Int, on: [UInt8], off: [UInt8]) -> [[UInt8]] {
        (0..<180).map { ($0 / period) % 2 == 0 ? on : off }
    }

    private func whole(_ frames: [[UInt8]]) -> [Double] {
        frames.map { f in FlashAnalyzer.regions(bgra: f, width: 320, height: 180).prefix(9)
            .map(\.luminance).reduce(0, +) / 9 }
    }

    /// Negative control: a ninth of the frame flashing near-black ↔ near-white at 6 Hz. The whole-frame
    /// mean moves < 10 % and v1 calls it safe; the regional check does not.
    @Test func aFlashingNinth_isCaughtByRegion_missedByTheWholeFrame() {
        let on = frame(tile: 4, patch: (230, 230, 230)), off = frame(tile: 4, patch: (30, 30, 30))
        let frames = sequence(period: 5, on: on, off: off)
        #expect(FlashAnalyzer.analyze(relativeLuminance: whole(frames), fps: 60).isSafe, "v1 cannot see it")
        let regional = FlashAnalyzer.analyzeRegional(
            frames.map { FlashAnalyzer.regions(bgra: $0, width: 320, height: 180) }, fps: 60)
        #expect(!regional.isSafe, "regional peak \(regional.peakFlashesPerSecond)/s")
    }

    /// Negative control: the whole frame pulsing dark saturated red ↔ black at 5 Hz — a luminance
    /// swing under 10 % (v1 and regional both pass), a red swing far over 20.
    @Test func aDimRedFlash_isCaughtByTheRedChannel() {
        let red = frame(grey: 0, tile: nil, patch: nil).enumerated().map { i, v in i % 4 == 2 ? 140 : (i % 4 == 3 ? 255 : 0) } as [UInt8]
        let black = frame(grey: 0)
        let frames = sequence(period: 6, on: red, off: black)
        let samples = frames.map { FlashAnalyzer.regions(bgra: $0, width: 320, height: 180) }
        #expect(FlashAnalyzer.analyzeRegional(samples, fps: 60).isSafe, "luminance swing < 10 %")
        #expect(samples[0][0].isSaturatedRed && samples[0][0].redValue > 20)
        #expect(!FlashAnalyzer.analyzeRed(samples, fps: 60).isSafe)
    }

    /// Bright but steady colour, and red that doesn't flash, stay safe.
    @Test func steadyRed_andSlowChanges_areSafe() {
        let red = frame(tile: 0, patch: (0, 0, 255))
        let samples = Array(repeating: FlashAnalyzer.regions(bgra: red, width: 320, height: 180), count: 180)
        #expect(FlashAnalyzer.analyzeRed(samples, fps: 60).isSafe)
        #expect(FlashAnalyzer.analyzeRegional(samples, fps: 60).isSafe)
        #expect(FlashAnalyzer.regionRects.count == 13)
    }
}
