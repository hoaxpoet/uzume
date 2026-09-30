// FlashAnalyzer.swift — Harding / WCAG 2.3.1 photosensitivity flash analysis.
//
// CLEAN.7.6 / GAP-9. Measures the temporal luminance-transition rate of a
// rendered frame sequence and reports peak flashes-per-second against the
// Harding general-flash threshold. This is the measurement primitive behind
// the photosensitivity certification gate (Work B) and the planned runtime
// backstop (A-next).
//
// Standard (WCAG 2.3.1, general flash):
//   - A *flash* is a pair of opposing changes in relative luminance of ≥ 10 %
//     of max (≥ 0.10 on a 0…1 scale) where the *darker* state is < 0.80.
//   - Content is unsafe if it produces *more than 3 flashes within any
//     1-second window* over a sufficiently large area (~25 % of a 10° field).
//
// v2 (BR.20 / I8): `analyzeRegional` runs the same rule per screen region (a 3×3 grid plus a
// half-shifted 2×2, each a ninth of the frame — WCAG's small-safe area, 0.006 sr ≈ 341×256 px at
// 1024×768, is exactly a ninth), and `analyzeRed` adds the saturated-red channel. The v1 text below
// is the whole-frame analysis, unchanged.
//
// SCOPE (v1, full-frame). This analyzer consumes the per-frame *full-frame
// mean* relative luminance. That is the correct, conservative metric for
// GLOBAL luminance pumping — the FBS "beat-punch" failure class (the whole
// field brightening on every kick), which is the documented real-world defect
// this gate exists to prevent. It deliberately does NOT yet implement:
//   - regional / area-gating: a flash confined to < the full frame can move
//     the full-frame mean by < 10 % and be missed. Follow-up refinement.
//   - the separate saturated-RED flash channel. Follow-up.
//   - feedback-chain accumulation: callers that render frame-independently
//     (no previous-frame texture) measure the shader response, not feedback
//     build-up. Follow-up (drive the real RenderPipeline for a faithful chain).
// These limits are restated at the certification-gate call site.

import Foundation

// MARK: - FlashReport

/// Result of analyzing one luminance sequence against the Harding threshold.
public struct FlashReport: Sendable, Equatable {
    /// Number of frames analyzed.
    public let frameCount: Int
    /// Frames-per-second used to map frame indices to time.
    public let fps: Double
    /// Total qualifying opposing luminance transitions (each ≥ 10 % swing,
    /// darker state < 0.80). A flash is a pair of these.
    public let transitionCount: Int
    /// Peak flashes/second over any 1-second sliding window.
    public let peakFlashesPerSecond: Double
    /// Start time (s) of the worst 1-second window.
    public let peakWindowStartSeconds: Double
    /// True iff `peakFlashesPerSecond` is within the Harding limit (≤ 3).
    public let isSafe: Bool
}

// MARK: - FlashAnalyzer

public enum FlashAnalyzer {

    /// WCAG general-flash limit: *more than* this many flashes within any 1 s
    /// is unsafe. The limit itself (exactly 3/s) is safe.
    public static let flashesPerSecondLimit = 3.0
    /// Minimum relative-luminance swing (of max) for a change to count.
    public static let swingThreshold = 0.10
    /// The darker state of a qualifying flash must be below this.
    public static let darkStateCeiling = 0.80

    /// Analyze a chronological sequence of full-frame mean relative luminances
    /// (each in 0…1) at a uniform frame rate.
    ///
    /// - Parameters:
    ///   - luma: per-frame full-frame mean relative luminance, chronological.
    ///   - fps: frames per second (must be > 0).
    public static func analyze(relativeLuminance luma: [Double], fps: Double) -> FlashReport {
        precondition(fps > 0, "fps must be positive")

        // 1–2. Significant turning points (hysteresis), then each adjacent pair is one qualifying
        //      transition iff it swings ≥ threshold AND its darker endpoint is < the dark ceiling.
        let transitionTimes = qualifyingTransitionTimes(luma, threshold: swingThreshold, fps: fps) { prev, curr in
            min(luma[prev], luma[curr]) < darkStateCeiling
        }
        return report(transitionTimes: transitionTimes, frameCount: luma.count, fps: fps)
    }

    /// Steps 3+: slide a 1-second window over the transition events. A flash is a pair of opposing
    /// transitions, so the peak flashes/second is the worst window's transition count ÷ 2.
    private static func report(transitionTimes: [Double], frameCount: Int, fps: Double) -> FlashReport {
        // 3. Slide a 1-second window over the transition events. A flash is a
        //    pair of opposing transitions, so the peak flashes/second is the
        //    worst window's transition count ÷ 2.
        var peakTransitionsInWindow = 0
        var peakWindowStart = 0.0
        for j in 0..<transitionTimes.count {
            let windowStart = transitionTimes[j]
            var count = 0
            for k in j..<transitionTimes.count where transitionTimes[k] < windowStart + 1.0 {
                count += 1
            }
            if count > peakTransitionsInWindow {
                peakTransitionsInWindow = count
                peakWindowStart = windowStart
            }
        }
        let peakFlashes = Double(peakTransitionsInWindow) / 2.0

        return FlashReport(
            frameCount: frameCount,
            fps: fps,
            transitionCount: transitionTimes.count,
            peakFlashesPerSecond: peakFlashes,
            peakWindowStartSeconds: peakWindowStart,
            isSafe: peakFlashes <= flashesPerSecondLimit
        )
    }

    // MARK: - Internal

    private struct Extremum { let index: Int; let value: Double }

    /// Times (s) of the qualifying transitions in `signal`: adjacent significant extrema that differ
    /// by ≥ `threshold` and pass `qualifies(prevIndex, currIndex)`.
    private static func qualifyingTransitionTimes(
        _ signal: [Double], threshold: Double, fps: Double, qualifies: (Int, Int) -> Bool
    ) -> [Double] {
        let extrema = significantExtrema(signal, threshold: threshold)
        guard extrema.count >= 2 else { return [] }
        return (1..<extrema.count).compactMap { k in
            let prev = extrema[k - 1], curr = extrema[k]
            return abs(curr.value - prev.value) >= threshold && qualifies(prev.index, curr.index)
                ? Double(curr.index) / fps : nil
        }
    }

    /// Turning points with a minimum reversal amplitude (hysteresis). The first
    /// sample seeds the sequence; thereafter a peak/valley is emitted only when
    /// luminance reverses from the running extreme by ≥ `threshold`. Consecutive
    /// emitted extrema therefore alternate direction and differ by ≥ `threshold`.
    private static func significantExtrema(_ x: [Double], threshold: Double) -> [Extremum] {
        guard let first = x.first else { return [] }
        var out: [Extremum] = [Extremum(index: 0, value: first)]
        var anchor = out[0]            // last confirmed turning point
        var cand = anchor              // running extreme since the anchor
        var dir = 0.0                  // +1 rising, -1 falling, 0 undetermined

        // The rising and falling cases are mirror images, so direction is a sign
        // multiplier: `delta * dir > 0` means "still moving the current way"
        // (extend the running extreme); a reversal of ≥ threshold confirms a
        // turning point and flips the direction.
        for i in 1..<x.count {
            let lum = x[i]
            if dir == 0 {
                if abs(lum - anchor.value) >= threshold {
                    dir = lum > anchor.value ? 1 : -1
                    cand = Extremum(index: i, value: lum)
                }
            } else if (lum - cand.value) * dir > 0 {
                cand = Extremum(index: i, value: lum)
            } else if (cand.value - lum) * dir >= threshold {
                out.append(cand); anchor = cand
                dir = -dir
                cand = Extremum(index: i, value: lum)
            }
        }
        return out
    }
}

// MARK: - v2: regions and saturated red (BR.20 / I8)

/// One screen region, as fractions of the frame: its top-left corner and its (square-fraction) size.
public struct FlashRegionRect: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let size: Double
}

/// Mean linear-light R, G, B of one screen region in one frame (each 0…1).
public struct FlashRegionSample: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    /// WCAG relative luminance (Rec. 709).
    public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    /// WCAG "saturated red": R / (R + G + B) ≥ 0.8.
    public var isSaturatedRed: Bool {
        let sum = red + green + blue
        return sum > 0 && red / sum >= FlashAnalyzer.saturatedRedRatio
    }

    /// WCAG's red-flash quantity, (R − G − B) × 320, negative values set to zero.
    public var redValue: Double { max(0, red - green - blue) * 320 }
}

extension FlashAnalyzer {

    /// WCAG red flash: the state is saturated red when R / (R + G + B) ≥ this.
    public static let saturatedRedRatio = 0.8
    /// …and a transition counts when (R − G − B) × 320 changes by more than this.
    public static let redSwingThreshold = 20.0

    /// Regions as fractions of the frame (x, y, width, height): a 3×3 grid and the 2×2 grid of the
    /// same tile size shifted half a tile, so a flash straddling tile edges is still one tile's worth.
    public static let regionRects: [FlashRegionRect] = {
        let tile: Double = 1.0 / 3
        var rects: [FlashRegionRect] = []
        for row in 0..<3 {
            for col in 0..<3 { rects.append(FlashRegionRect(x: Double(col) * tile, y: Double(row) * tile, size: tile)) }
        }
        for row in 0..<2 {
            for col in 0..<2 {
                let x = tile / 2 + Double(col) * tile, y = tile / 2 + Double(row) * tile
                rects.append(FlashRegionRect(x: x, y: y, size: tile))
            }
        }
        return rects
    }()

    /// Per-region linear R, G, B means of a BGRA8 frame (`regionRects`, in order).
    public static func regions(bgra: [UInt8], width: Int, height: Int) -> [FlashRegionSample] {
        regionRects.map { rect in
            let x0 = Int(rect.x * Double(width)), x1 = min(width, Int((rect.x + rect.size) * Double(width)))
            let y0 = Int(rect.y * Double(height)), y1 = min(height, Int((rect.y + rect.size) * Double(height)))
            var red = 0.0, green = 0.0, blue = 0.0
            var count = 0
            for row in y0..<max(y0, y1) {
                var index = (row * width + x0) * 4
                for _ in x0..<max(x0, x1) {
                    blue += srgbToLinear[Int(bgra[index])]
                    green += srgbToLinear[Int(bgra[index + 1])]
                    red += srgbToLinear[Int(bgra[index + 2])]
                    count += 1
                    index += 4
                }
            }
            let pixels = Double(max(count, 1))
            return FlashRegionSample(red: red / pixels, green: green / pixels, blue: blue / pixels)
        }
    }

    /// The general-flash rule per region; the worst region's report.
    /// - Parameter frames: per frame, one sample per region (same count every frame).
    public static func analyzeRegional(_ frames: [[FlashRegionSample]], fps: Double) -> FlashReport {
        worst(over: frames) { analyze(relativeLuminance: $0.map(\.luminance), fps: fps) }
    }

    /// The saturated-red rule per region: transitions of more than 20 in (R − G − B) × 320 where
    /// either end is saturated red, > 3 flashes in any second unsafe. The worst region's report.
    public static func analyzeRed(_ frames: [[FlashRegionSample]], fps: Double) -> FlashReport {
        worst(over: frames) { series in
            let value = series.map(\.redValue)
            let times = qualifyingTransitionTimes(value, threshold: redSwingThreshold, fps: fps) { prev, curr in
                series[prev].isSaturatedRed || series[curr].isSaturatedRed
            }
            return report(transitionTimes: times, frameCount: series.count, fps: fps)
        }
    }

    private static func worst(
        over frames: [[FlashRegionSample]], _ perRegion: ([FlashRegionSample]) -> FlashReport
    ) -> FlashReport {
        let regionCount = frames.first?.count ?? 0
        let reports = (0..<regionCount).map { k in perRegion(frames.map { $0[k] }) }
        return reports.max { $0.peakFlashesPerSecond < $1.peakFlashesPerSecond }
            ?? analyze(relativeLuminance: [], fps: 60)
    }

    /// sRGB byte (0…255) → linear component (0…1).
    static let srgbToLinear: [Double] = (0..<256).map { byte in
        let value = Double(byte) / 255.0
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
