// NebulaSpectrumDiagnosticTests — PR.19 step 2: measure Nebula's INPUT before
// diagnosing its output.
//
// Matt's roster note is *"Needs better sync with music. Spikes are too sporadic.
// Should look more activated."* Nebula's sidecar declares NO `audio_routes`, so
// QG.1 gates nothing here and no existing artifact says what the preset actually
// consumes. Reading the shader says it consumes RAW `fftMagnitudes` — no
// deviation primitive anywhere — through two fixed gains:
//
//     smoothMag   = saturate(mag * 8.0)                  // radial band extent
//     totalEnergy = saturate(sum(bins 0..<64) / 64 * 6.0) // core glow + haze
//
// ★ THIS MEASURES THE CONSUMER'S ARITHMETIC, NOT THE PRIMITIVE. Measuring a bin
//   magnitude correctly says nothing if what matters is where `saturate(mag*8)`
//   lands — a primitive can be perfectly healthy and still arrive at a shader
//   that crushes it to a constant. That mistake has been made repeatedly in this
//   repo; the numbers below are the shader's own expressions.
//
// FA #27: real audio through the production FFT path, never synthetic envelopes.
//
// Usage (needs a session with raw_tap.wav):
//   NEBULA_SPECTRUM=~/Documents/uzume_sessions/<dir>/raw_tap.wav \
//   swift test --package-path UzumeEngine --filter NebulaSpectrumDiagnostic
import Testing
import Foundation
import AVFoundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Audio
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("NebulaSpectrumDiagnostic")
@MainActor
struct NebulaSpectrumDiagnosticTests {

    /// Nebula reads bins 0..<256 (angle → bin) and sums bins 0..<64 for energy.
    static let ringBins = 256
    static let energyBins = 64

    @Test("Measure what Nebula's own expressions evaluate to on real music")
    func measureSpectrum() throws {
        guard let path = ProcessInfo.processInfo.environment["NEBULA_SPECTRUM"] else {
            print("[nebula-spectrum] set NEBULA_SPECTRUM=<session>/raw_tap.wav")
            return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let (samples, sampleRate) = try Self.decodeMono(url)
        guard samples.count > 4096 else { Issue.record("too few samples"); return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[nebula-spectrum] no Metal device"); return
        }
        let fft = try FFTProcessor(device: device)

        // Hop at the analysis cadence, not per render frame: this is about what the
        // spectrum DOES, and the render simply re-reads whatever the last hop wrote.
        let hop = Int(sampleRate / 60.0)
        let window = 1024
        var mags: [[Float]] = []
        var i = window
        while i < samples.count {
            fft.process(samples: Array(samples[(i - window)..<i]), sampleRate: Float(sampleRate))
            mags.append(Array(fft.magnitudeBuffer.pointer.prefix(512)))
            i += hop
        }
        guard mags.count > 30 else { Issue.record("too few frames"); return }

        func pct(_ a: [Float], _ p: Double) -> Float {
            let s = a.sorted(); return s[min(s.count - 1, max(0, Int(Double(s.count - 1) * p)))]
        }

        // 1. Raw magnitudes over the bins the ring actually reads.
        var ring: [Float] = []
        for f in mags { ring.append(contentsOf: f[0..<Self.ringBins]) }

        // 2. The shader's own band expression.
        let smoothMag = ring.map { min(max($0 * 8.0, 0), 1) }
        let bandRadius = smoothMag.map { 0.08 + $0 * 0.35 }

        // 3. The shader's own energy expression.
        let totalEnergy: [Float] = mags.map { f in
            let s = f[0..<Self.energyBins].reduce(0, +)
            return min(max(s / Float(Self.energyBins) * 6.0, 0), 1)
        }

        // 4. "Spikes are too sporadic" — two volatilities, and they are different
        //    complaints. TEMPORAL is one bin moving frame to frame. SPATIAL is
        //    neighbour-to-neighbour around the ring, which matters here *because*
        //    the shader wraps the spectrum around a circle: bin-to-bin noise IS
        //    visible roughness in the ring, at one instant, with no motion at all.
        var temporalDelta: [Float] = []
        for k in 1..<mags.count {
            for b in 0..<Self.ringBins {
                temporalDelta.append(abs(mags[k][b] - mags[k - 1][b]))
            }
        }
        var spatialDelta: [Float] = []
        for f in mags {
            for b in 1..<Self.ringBins { spatialDelta.append(abs(f[b] - f[b - 1])) }
        }

        let meanRing = ring.reduce(0, +) / Float(ring.count)
        let meanTemporal = temporalDelta.reduce(0, +) / Float(temporalDelta.count)
        let meanSpatial = spatialDelta.reduce(0, +) / Float(spatialDelta.count)

        func f3(_ v: Float) -> String { String(format: "%.4f", v) }
        func pctOf(_ a: [Float], _ test: (Float) -> Bool) -> String {
            String(format: "%.1f%%", 100.0 * Double(a.filter(test).count) / Double(a.count))
        }

        print("""
        [nebula-spectrum] \(mags.count) frames, \(Self.ringBins) ring bins, \(url.lastPathComponent)

          RAW fftMagnitudes[0..<256]
            p50 \(f3(pct(ring, 0.50)))  p90 \(f3(pct(ring, 0.90)))  p99 \(f3(pct(ring, 0.99)))  max \(f3(ring.max() ?? 0))
            mean \(f3(meanRing))

          smoothMag = saturate(mag * 8.0)        <- drives the radial band
            p50 \(f3(pct(smoothMag, 0.50)))  p90 \(f3(pct(smoothMag, 0.90)))  p99 \(f3(pct(smoothMag, 0.99)))
            at floor (<0.02):  \(pctOf(smoothMag) { $0 < 0.02 })
            appreciable (>0.5): \(pctOf(smoothMag) { $0 > 0.5 })
            saturated (=1.0):   \(pctOf(smoothMag) { $0 >= 0.999 })

          bandRadius = 0.08 + smoothMag * 0.35   <- 0.08 is the floor, 0.43 the ceiling
            p50 \(f3(pct(bandRadius, 0.50)))  p90 \(f3(pct(bandRadius, 0.90)))  p99 \(f3(pct(bandRadius, 0.99)))

          totalEnergy = saturate(sum(0..<64)/64 * 6.0)  <- core glow + haze
            p50 \(f3(pct(totalEnergy, 0.50)))  p90 \(f3(pct(totalEnergy, 0.90)))  p99 \(f3(pct(totalEnergy, 0.99)))
            saturated (=1.0): \(pctOf(totalEnergy) { $0 >= 0.999 })

          VOLATILITY (the "sporadic" complaint), as a ratio to the mean magnitude
            temporal |d(bin)/frame| \(f3(meanTemporal))  = \(String(format: "%.2f", meanTemporal / max(meanRing, 1e-9)))x mean
            spatial  |d(bin)/bin|   \(f3(meanSpatial))  = \(String(format: "%.2f", meanSpatial / max(meanRing, 1e-9)))x mean
        """)

        // 5. WHERE THE ENERGY SITS AROUND THE CIRCLE. The shader maps bin index to
        //    angle LINEARLY (`bin = normalizedAngle * 256`), but musical energy is
        //    distributed logarithmically in frequency and concentrated at the bottom.
        //    If that mismatch is real, most of the circle shows bins carrying almost
        //    nothing -- a different complaint from "the gain is wrong", and one that
        //    no amount of scaling fixes.
        let binHz = Float(sampleRate) / 1024.0
        var sectorEnergy = [Float](repeating: 0, count: 8)
        for f in mags {
            for b in 0..<Self.ringBins { sectorEnergy[b * 8 / Self.ringBins] += f[b] }
        }
        let totalSector = max(sectorEnergy.reduce(0, +), 1e-9)
        var sectorLines: [String] = []
        for (k, e) in sectorEnergy.enumerated() {
            let lo = Float(k * Self.ringBins / 8) * binHz
            let hi = Float((k + 1) * Self.ringBins / 8) * binHz
            sectorLines.append(String(format: "    sector %d/8  %5.0f-%5.0f Hz  %5.1f%%",
                                      k + 1, lo, hi, 100.0 * e / totalSector))
        }
        let bassBins = max(1, Int(250.0 / binHz))
        var bassEnergy: Float = 0, allEnergy: Float = 0
        for f in mags {
            for b in 0..<Self.ringBins {
                allEnergy += f[b]
                if b < bassBins { bassEnergy += f[b] }
            }
        }
        let circleShare = 100.0 * Double(bassBins) / Double(Self.ringBins)
        let energyShare = 100.0 * Double(bassEnergy / max(allEnergy, 1e-9))
        print("  ANGULAR ENERGY (bin -> angle is LINEAR; "
              + String(format: "%.1f", binHz) + " Hz per bin), share of ring energy:")
        print(sectorLines.joined(separator: "\n"))
        print(String(format: "    below 250 Hz = bins 0..<%d = %.1f%% of the circle, "
                     + "carrying %.1f%% of ring energy", bassBins, circleShare, energyShare))

        // 6. DOES LOG-BAND AGGREGATION FIX THE VOLATILITY WITHOUT NEW STATE?
        //
        //    A direct preset has no per-bin history — `SpectralHistoryBuffer` carries MIR
        //    scalars, not spectra — so temporal smoothing would mean adding a per-preset
        //    state buffer and its wiring. Before building that, measure whether it is
        //    needed: a correct log-frequency mapping AGGREGATES many bins into one
        //    angular position at the top of the range, and averaging N independent noisy
        //    bins cuts variance by sqrt(N). If that alone brings the volatility down, the
        //    state buffer is work that buys nothing.
        //
        //    Same 256 angular positions, but each reads the MEAN of the bins its
        //    log-spaced band actually covers.
        let fLo: Float = 30.0, fHi: Float = 11000.0
        func logBand(_ f: [Float], _ k: Int) -> Float {
            let a0 = Float(k) / Float(Self.ringBins), a1 = Float(k + 1) / Float(Self.ringBins)
            let h0 = fLo * pow(fHi / fLo, a0), h1 = fLo * pow(fHi / fLo, a1)
            let b0 = max(0, min(511, Int(h0 / binHz)))
            let b1 = max(b0 + 1, min(512, Int(h1 / binHz) + 1))
            var acc: Float = 0
            for b in b0..<b1 { acc += f[b] }
            return acc / Float(b1 - b0)
        }
        var logged: [[Float]] = []
        for f in mags { logged.append((0..<Self.ringBins).map { logBand(f, $0) }) }

        var logRing: [Float] = []
        for f in logged { logRing.append(contentsOf: f) }
        let meanLog = logRing.reduce(0, +) / Float(logRing.count)

        var logTemporal: [Float] = []
        for k in 1..<logged.count {
            for b in 0..<Self.ringBins { logTemporal.append(abs(logged[k][b] - logged[k - 1][b])) }
        }
        var logSpatial: [Float] = []
        for f in logged {
            for b in 1..<Self.ringBins { logSpatial.append(abs(f[b] - f[b - 1])) }
        }
        let mLogT = logTemporal.reduce(0, +) / Float(logTemporal.count)
        let mLogS = logSpatial.reduce(0, +) / Float(logSpatial.count)

        var logSector = [Float](repeating: 0, count: 8)
        for f in logged {
            for b in 0..<Self.ringBins { logSector[b * 8 / Self.ringBins] += f[b] }
        }
        let logTotal = max(logSector.reduce(0, +), 1e-9)
        let logShares = logSector.map { String(format: "%.1f%%", 100.0 * $0 / logTotal) }

        print("  PROPOSED log-band aggregation (30 Hz - 11 kHz over the same 256 positions):")
        print(String(format: "    temporal volatility  %.2fx mean  (linear was %.2fx)",
                     mLogT / max(meanLog, 1e-9), meanTemporal / max(meanRing, 1e-9)))
        print(String(format: "    spatial  volatility  %.2fx mean  (linear was %.2fx)",
                     mLogS / max(meanLog, 1e-9), meanSpatial / max(meanRing, 1e-9)))
        print("    energy per eighth: " + logShares.joined(separator: "  "))

        // 7. PICK THE CURVE FROM MEASUREMENT, NOT FROM TASTE. Log spacing alone still
        //    leaves the top of the circle quiet, because natural spectra fall off with
        //    frequency (~1/f). Spectrum displays compensate with a slope. Sweep a few
        //    (range, tilt) pairs and read the energy spread — the target is a circle
        //    where no eighth is dead and none dominates.
        func evaluate(_ lo: Float, _ hi: Float, _ tilt: Float) -> (String, Float) {
            var sect = [Float](repeating: 0, count: 8)
            for f in mags {
                for k in 0..<Self.ringBins {
                    let a0 = Float(k) / Float(Self.ringBins), a1 = Float(k + 1) / Float(Self.ringBins)
                    let h0 = lo * pow(hi / lo, a0), h1 = lo * pow(hi / lo, a1)
                    let b0 = max(0, min(511, Int(h0 / binHz)))
                    let b1 = max(b0 + 1, min(512, Int(h1 / binHz) + 1))
                    var acc: Float = 0
                    for b in b0..<b1 { acc += f[b] }
                    sect[k * 8 / Self.ringBins] += (acc / Float(b1 - b0)) * pow(h0 / lo, tilt)
                }
            }
            let tot = max(sect.reduce(0, +), 1e-9)
            let shares = sect.map { 100.0 * $0 / tot }
            // Spread score: max share / min share. 1.0 would be perfectly even.
            let ratio = (shares.max() ?? 1) / max(shares.min() ?? 1, 1e-6)
            return (shares.map { String(format: "%4.1f", $0) }.joined(separator: " "), ratio)
        }
        print("  CURVE SWEEP (energy share per eighth, and max/min spread — lower is flatter):")
        for (lo, hi, tilt) in [(Float(30), Float(11000), Float(0.0)),
                               (Float(40), Float(8000), Float(0.0)),
                               (Float(40), Float(8000), Float(0.25)),
                               (Float(40), Float(8000), Float(0.5)),
                               (Float(50), Float(6000), Float(0.4)),
                               (Float(40), Float(8000), Float(0.75))] {
            let (shares, ratio) = evaluate(lo, hi, tilt)
            print(String(format: "    %5.0f-%5.0f Hz tilt %.2f  [%@]  spread %.1fx",
                         lo, hi, tilt, shares as NSString, ratio))
        }

        // 8. PICK THE GAIN FROM THE DISTRIBUTION. The v1 shader used `saturate(mag * 8)`
        //    and that single linear gain is why the band sits at its floor: FFT
        //    magnitudes are heavy-tailed (p50 to p99 spans ~100x here), so no linear
        //    gain can lift the median without crushing the peaks. A COMPRESSIVE curve
        //    can. Measure where each candidate puts the band across its 0.10-0.42 range.
        let selLo: Float = 40, selHi: Float = 8000, selTilt: Float = 0.5
        var agg: [Float] = []
        for f in mags {
            for k in 0..<Self.ringBins {
                let a0 = Float(k) / Float(Self.ringBins), a1 = Float(k + 1) / Float(Self.ringBins)
                let h0 = selLo * pow(selHi / selLo, a0), h1 = selLo * pow(selHi / selLo, a1)
                let b0 = max(0, min(511, Int(h0 / binHz)))
                let b1 = max(b0 + 1, min(512, Int(h1 / binHz) + 1))
                var acc: Float = 0
                for b in b0..<b1 { acc += f[b] }
                agg.append((acc / Float(b1 - b0)) * pow(h0 / selLo, selTilt))
            }
        }
        print(String(format: "  AGGREGATED value (log+tilt): p10 %.4f p50 %.4f p90 %.4f p99 %.4f max %.4f",
                     pct(agg, 0.10), pct(agg, 0.50), pct(agg, 0.90), pct(agg, 0.99), agg.max() ?? 0))
        print("  RESPONSE CURVE candidates -> where the radial band lands (floor 0.10, ceiling 0.42):")
        for (name, curve) in [("linear x8 (v1)", { (x: Float) in min(max(x * 8.0, 0), 1) }),
                              ("sqrt(x*14)", { (x: Float) in min(max(sqrt(x * 14.0), 0), 1) }),
                              ("pow(x*30,0.4)", { (x: Float) in min(max(pow(x * 30.0, 0.4), 0), 1) }),
                              ("log1p(x*90)/log1p(90)", { (x: Float) in
                                  min(max(log(1 + x * 90.0) / log(91.0), 0), 1) })] {
            let mapped = agg.map(curve)
            let radius = mapped.map { 0.10 + $0 * 0.32 }
            print(String(format: "    %-22@ p10 %.3f  p50 %.3f  p90 %.3f  p99 %.3f   at-floor %.0f%%  saturated %.0f%%",
                         name as NSString, pct(radius, 0.10), pct(radius, 0.50),
                         pct(radius, 0.90), pct(radius, 0.99),
                         100.0 * Double(mapped.filter { $0 < 0.02 }.count) / Double(mapped.count),
                         100.0 * Double(mapped.filter { $0 >= 0.999 }.count) / Double(mapped.count)))
        }

        // 9. MEASURE THE RADIUS THE SHADER ACTUALLY DRAWS, NOT THE MAGNITUDE.
        //    Aggregation smooths the MAGNITUDE (0.60x -> 0.09x), but the shader then
        //    applies a log response, whose slope is steepest near zero — so small
        //    magnitude differences at the quiet end become large RADIUS differences.
        //    Whether the ring reads as a ring or as a starburst depends on
        //    |d(radius)/d(angle)| compared with the band's own WIDTH: if the radius
        //    moves further between neighbouring positions than the band is thick, the
        //    band cannot connect and the eye sees spokes.
        func response(_ x: Float) -> Float {
            return min(max(log(1 + max(x, 0) * 90.0) / log(91.0), 0), 1)
        }
        var radiusStep: [Float] = []
        var widths: [Float] = []
        for f in mags {
            var prev: Float = -1
            for k in 0..<Self.ringBins {
                let a0 = Float(k) / Float(Self.ringBins), a1 = Float(k + 1) / Float(Self.ringBins)
                let h0 = selLo * pow(selHi / selLo, a0), h1 = selLo * pow(selHi / selLo, a1)
                let b0 = max(0, min(511, Int(h0 / binHz)))
                let b1 = max(b0 + 1, min(512, Int(h1 / binHz) + 1))
                var acc: Float = 0
                for b in b0..<b1 { acc += f[b] }
                let v = response((acc / Float(b1 - b0)) * pow(h0 / selLo, selTilt))
                let r = 0.10 + v * 0.32
                widths.append(0.012 + v * 0.024)
                if prev >= 0 { radiusStep.append(abs(r - prev)) }
                prev = r
            }
        }
        let meanStep = radiusStep.reduce(0, +) / Float(radiusStep.count)
        let meanWidth = widths.reduce(0, +) / Float(widths.count)
        print(String(format: "  RING CONTINUITY: mean |d(radius)/position| %.4f vs mean bandWidth %.4f  -> %.2fx",
                     meanStep, meanWidth, meanStep / max(meanWidth, 1e-9)))
        print(String(format: "    p90 step %.4f  p99 step %.4f  (a step larger than the width breaks the ring)",
                     pct(radiusStep, 0.90), pct(radiusStep, 0.99)))
        print(String(format: "    positions whose step exceeds the band width: %.1f%%",
                     100.0 * Double(radiusStep.filter { $0 > meanWidth }.count) / Double(radiusStep.count)))

        // 10. OVERLAP SWEEP. Adjacent positions currently aggregate DISJOINT bin ranges,
        //     so nothing couples them and the radius is free to jump. Widening each
        //     position's window to span several positions' worth of frequency makes
        //     neighbours share most of their bins, which smooths the radius directly
        //     rather than by blurring the drawn band. Cost is a few more bin reads at
        //     the top of the range, where the bands are widest.
        func continuity(_ overlap: Float, _ widthScale: Float) -> (Float, Double) {
            var steps: [Float] = []
            var ws: [Float] = []
            for f in mags {
                var prev: Float = -1
                for k in 0..<Self.ringBins {
                    let c = (Float(k) + 0.5) / Float(Self.ringBins)
                    let half = overlap * 0.5 / Float(Self.ringBins)
                    let h0 = selLo * pow(selHi / selLo, max(0, c - half))
                    let h1 = selLo * pow(selHi / selLo, min(1, c + half))
                    let b0 = max(0, min(511, Int(h0 / binHz)))
                    let b1 = max(b0 + 1, min(512, Int(h1 / binHz) + 1))
                    var acc: Float = 0
                    for b in b0..<b1 { acc += f[b] }
                    let v = response((acc / Float(b1 - b0)) * pow(h0 / selLo, selTilt))
                    let r = 0.10 + v * 0.32
                    let w = (0.012 + v * 0.024) * widthScale
                    ws.append(w)
                    if prev >= 0 { steps.append(abs(r - prev)) }
                    prev = r
                }
            }
            let mw = ws.reduce(0, +) / Float(ws.count)
            let broken = 100.0 * Double(steps.filter { $0 > mw }.count) / Double(steps.count)
            return (steps.reduce(0, +) / Float(steps.count) / max(mw, 1e-9), broken)
        }
        print("  OVERLAP SWEEP (window in units of angular positions; broken = % of steps wider than the band):")
        for (ov, wsn) in [(Float(1), Float(1.0)), (Float(3), Float(1.0)), (Float(5), Float(1.0)),
                          (Float(8), Float(1.0)), (Float(5), Float(1.4)), (Float(8), Float(1.4))] {
            let (ratio, broken) = continuity(ov, wsn)
            print(String(format: "    overlap %.0f  width x%.1f  ->  step/width %.2fx   broken %.1f%%",
                         ov, wsn, ratio, broken))
        }

        // ── Render it on the REAL spectrum ────────────────────────────────────
        // Every automated still of Nebula until now was rendered against the direct
        // path's LCG noise fill, so nobody has looked at this preset on music.
        if let outDir = ProcessInfo.processInfo.environment["NEBULA_RENDER_OUT"] {
            // Pair the real spectrum with the session's REAL FeatureVectors. Driving
            // synthetic ones leaves every deviation primitive at zero, which pins the
            // preset's `activity` term at its floor — the render would then show the
            // preset's quietest possible state and be read as its normal one.
            var real: [FeatureVector] = []
            let sessionDir = url.deletingLastPathComponent()
            let csv = sessionDir.appendingPathComponent("features.csv")
            if FileManager.default.fileExists(atPath: csv.path),
               let rows = try? SessionReplayHarness.loadRowsForReplay(csv), !rows.isEmpty {
                let audioStart = rows.firstIndex { $0.accumulatedAudioTime > 0 } ?? 0
                real = rows[audioStart...].map {
                    SessionReplayHarness.featureForReplay(from: $0, aspect: 16.0 / 9.0)
                }
                print("[nebula-render] paired with \(real.count) REAL feature rows")
            } else {
                print("[nebula-render] WARNING: no features.csv — deviations replay as ZERO")
            }
            try Self.render(mags: mags, features: real, to: outDir)
        }

        #expect(!ring.isEmpty)
    }

    @MainActor
    static func render(mags: [[Float]], features realFeatures: [FeatureVector],
                       to outPath: String) throws {
        let dir = URL(fileURLWithPath: (outPath as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Sample across the capture rather than the first N frames — the opening of a
        // track is not representative of it.
        let stride = max(1, mags.count / 6)
        let picked = Swift.stride(from: 0, to: mags.count, by: stride).prefix(6).map { mags[$0] }
        MultiPassRenderHarness.realSpectrum = picked
        defer { MultiPassRenderHarness.realSpectrum = nil }

        let harness = MultiPassRenderHarness(width: 960, height: 540)
        var frame = 0
        // Sample the feature rows at the same fractional positions as the spectra, so a
        // frame's picture and its audio state come from the same moment of the track.
        let features: [FeatureVector] = (0..<picked.count).map { i -> FeatureVector in
            guard !realFeatures.isEmpty else {
                return FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                     time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
            }
            let frac = Double(i) / Double(max(picked.count - 1, 1))
            var fv = realFeatures[min(realFeatures.count - 1,
                                      Int(frac * Double(realFeatures.count - 1)))]
            fv.aspectRatio = 16.0 / 9.0
            return fv
        }
        let stems = [StemFeatures](repeating: .zero, count: picked.count)
        _ = try harness.render(preset: "Nebula", features: features, stems: stems,
                               settle: 0) { bgra -> Int in
            let url = dir.appendingPathComponent(String(format: "nebula_%02d.png", frame))
            try? SessionDrivenMultiPassReplay.writePNG(bgra: bgra, width: 960, height: 540, to: url)
            frame += 1
            return 0
        }
        print("[nebula-render] \(frame) frames on REAL spectrum → \(dir.path)")
    }

    static func decodeMono(_ url: URL) throws -> ([Float], Double) {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                         frameCapacity: AVAudioFrameCount(file.length)) else {
            return ([], fmt.sampleRate)
        }
        try file.read(into: buf)
        guard let ch = buf.floatChannelData else { return ([], fmt.sampleRate) }
        let n = Int(buf.frameLength), channels = Int(fmt.channelCount)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var acc: Float = 0
            for c in 0..<channels { acc += ch[c][i] }
            out[i] = acc / Float(channels)
        }
        return (out, fmt.sampleRate)
    }
}
