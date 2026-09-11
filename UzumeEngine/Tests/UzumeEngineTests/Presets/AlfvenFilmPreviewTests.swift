// AlfvenFilmPreviewTests — the §11 look gate, run on the CPU.
//
// `docs/presets/alfven_spike/film.py` is the authoritative look ("the Metal fragment
// shader should reproduce THIS, not invent its own look"), but three of its operations are
// global or multi-scale — `autoexp` (2nd/99.6th percentile of |J|), `std(J)`, and two
// Gaussian blurs — and a fragment shader cannot do any of them. Porting it to Metal needs
// a reduction/mip surface Uzume does not have.
//
// So this ports film.py to the CPU instead, exactly, and applies it to the REAL GPU field
// pulled off the live persistent state texture. That does two jobs:
//   1. It answers §11 — does a GPU Jacobi projection reproduce the spike's look? — without
//      waiting on the missing engine surface. The physics is on trial here, not the tonemap.
//   2. It IS the reference implementation to port to Metal later, already validated against
//      the same field the shader will see.
//
// Why this exists at all: the placeholder fixed exposure in Alfven.metal made the field
// look dead, and I read that as a physics failure. It was not — autoexp normalises |J| by
// its own percentiles, so J's absolute scale is irrelevant to the look. Absolute RMS was
// the wrong measurement; this is the right one.
//
// Env-gated `RENDER_VISUAL=1` (writes PNGs). Reader is the eyes (D-064).

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Alfvén film preview (env-gated, ALFVEN.2)")
@MainActor
struct AlfvenFilmPreviewTests {

    private static let edge = 256
    private var edge: Int { Self.edge }
    /// Palette centre. 0.72 = the late (magenta <-> teal) end Matt selected; overridable
    /// so the drift range can be inspected without an edit.
    private static var hueCentre: Double {
        ProcessInfo.processInfo.environment["ALFVEN_HUE"].flatMap(Double.init) ?? 0.72
    }
    /// Frames to capture: early in the arc, mid-arc, and late — the fold-to-filament
    /// progression §3 calls the cycle.
    private static var captureAt: Set<Int> {
        if let list = ProcessInfo.processInfo.environment["ALFVEN_CAPTURE"] {
            return Set(list.split(separator: ",").compactMap { Int($0) })
        }
        return [30, 120, 300, 600]
    }

    @Test("render the live MHD field through film.py's mapping")
    func filmPreview() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("AlfvenFilmPreview: RENDER_VISUAL not set, skipping")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        var cfg = AlfvenSolverConfiguration()
        cfg.edge = edge
        // Same override set as AlfvenSolverTests, so the film harness can be pointed at a
        // decay run (ALFVEN_DRIVEFLOOR=0 ALFVEN_DRIVECEIL=0) — the cleanest comparison
        // against the spike, because
        // an unforced field just relaxes from a statistically identical seed instead of
        // diverging chaotically.
        let env = ProcessInfo.processInfo.environment
        if let a = env["ALFVEN_ALPHA"].flatMap(Float.init) { cfg.alpha = a }
        if let n4 = env["ALFVEN_NU4"].flatMap(Float.init) { cfg.nu4 = n4 }
        if let sc = env["ALFVEN_CUTOFF"].flatMap(Float.init) { cfg.spectralCutoff = sc }
        if let cy = env["ALFVEN_CYCLE"].flatMap(Float.init) { cfg.cycleSeconds = cy }
        if let jc = env["ALFVEN_JCUT"].flatMap(Float.init) { cfg.jCutoff = jc }
        if let df = env["ALFVEN_DRIVEFLOOR"].flatMap(Float.init) { cfg.driveFloor = df }
        if let dc = env["ALFVEN_DRIVECEIL"].flatMap(Float.init) { cfg.driveCeil = dc }
        if let bh = env["ALFVEN_BASSSHIFT"].flatMap(Float.init) { cfg.bassRelShift = bh }
        if let bl = env["ALFVEN_BASSSCALE"].flatMap(Float.init) { cfg.bassRelScale = bl }
        let solver = try AlfvenSolver(device: ctx.device, library: lib.library,
                                      pixelFormat: ctx.pixelFormat, configuration: cfg)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("uzume-alfven4-film")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let seedCmd = ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        solver.reseed(time: 0, commandBuffer: seedCmd)
        seedCmd.commit(); seedCmd.waitUntilCompleted()

        // ALFVEN_LIVE: render through the PRODUCTION display fragment
        // (`alfven_display_fragment` via `AlfvenSolver.render`) and measure ITS luma.
        // Everything else in this file measures the CPU port of film.py, which uses
        // PERCENTILE auto-exposure the shader cannot do — so the numbers here are the
        // only ones that describe what the app actually draws, and they are what
        // `displayExposure` has to be calibrated against.
        if env["ALFVEN_LIVE"] == "1" {
            if let ex = env["ALFVEN_EXPOSURE"].flatMap(Float.init) { solver.displayExposure = ex }
            if let hu = env["ALFVEN_HUE"].flatMap(Float.init) { solver.displayHueCentre = hu }
            if let bl = env["ALFVEN_BLOOM"].flatMap(Float.init) { solver.displayBloomAmount = bl }
            if let be = env["ALFVEN_BLOOMEXP"].flatMap(Float.init) { solver.displayBloomExposure = be }
            let frames = Int(env["ALFVEN_FRAMES"] ?? "300") ?? 300
            let target = try Self.makeTarget(ctx, edge: Self.edge)
            var lums: [Double] = []
            for frame in 1...frames {
                guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                    throw HarnessError.commandBufferFailed
                }
                // ALFVEN.3: when audio values are supplied, go through the PRODUCTION
                // `update(features:stemFeatures:)` entry point so the envelopes, the
                // soft-saturating drive map and the hue blend are all exercised — not a
                // back door that sets the solver's constants directly.
                if let bd = env["ALFVEN_BASSDEV"].flatMap(Float.init) {
                    var f = FeatureVector()
                    f.time = Float(frame) / 60.0
                    f.deltaTime = 1.0 / 60.0
                    f.bassRel = bd
                    f.bassDev = max(bd, 0)
                    f.trebRel = env["ALFVEN_TREBREL"].flatMap(Float.init) ?? 0
                    f.spectralCentroid = env["ALFVEN_CENTROID"].flatMap(Float.init) ?? 0.12
                    solver.update(features: f, stemFeatures: StemFeatures(), commandBuffer: cmd)
                } else {
                    solver.update(time: Float(frame) / 60.0, commandBuffer: cmd)
                }
                if frame % 60 == 0 {
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = target
                    pass.colorAttachments[0].loadAction = .clear
                    pass.colorAttachments[0].storeAction = .store
                    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                    guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
                        throw HarnessError.commandBufferFailed
                    }
                    // ALFVEN_TIME_SCALE compresses the listener clock so a whole palette
                    // cycle can be sampled in a few hundred frames. The FIELD still
                    // advances at its own rate; only the drift's clock is scaled.
                    let scale = Float(env["ALFVEN_TIME_SCALE"] ?? "1") ?? 1
                    var features = FeatureVector()
                    features.time = Float(frame) / 60.0 * scale
                    solver.render(encoder: enc, features: features)
                    enc.endEncoding()
                }
                cmd.commit(); cmd.waitUntilCompleted()
                guard frame % 60 == 0 else { continue }
                lums.append(Self.meanLuma(target))
                // Dump the bloom chain so film.py's own gaussian_filter can be run on the
                // same field and compared field-to-field — percentages of frame brightness
                // are not comparable across the sRGB/linear split.
                for (tex, tag) in [(solver.bloomCoreTexture, "core"),
                                   (solver.bloomNearTexture, "b0"),
                                   (solver.bloomFarTexture, "b1")] {
                    let n = tex.width
                    var raw = [Float](repeating: 0, count: n * n * 4)
                    raw.withUnsafeMutableBytes { buf in
                        guard let base = buf.baseAddress else { return }
                        tex.getBytes(base, bytesPerRow: n * 16,
                                     from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                                     size: MTLSize(width: n, height: n, depth: 1)),
                                     mipmapLevel: 0)
                    }
                    var out = Data(capacity: n * n * 8)
                    for i in 0..<(n * n) {
                        withUnsafeBytes(of: Double(raw[i * 4]).bitPattern.littleEndian) {
                            out.append(contentsOf: $0)
                        }
                    }
                    try out.write(to: dir.appendingPathComponent("bloom_\(tag).f64"))
                }
                let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("uzume-alfven4-film")
                try FileManager.default.createDirectory(at: dir,
                                                        withIntermediateDirectories: true)
                var bgra = [UInt8](repeating: 0, count: Self.edge * Self.edge * 4)
                bgra.withUnsafeMutableBytes { buf in
                    guard let base = buf.baseAddress else { return }
                    target.getBytes(base, bytesPerRow: Self.edge * 4,
                                    from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                                    size: MTLSize(width: Self.edge,
                                                                  height: Self.edge, depth: 1)),
                                    mipmapLevel: 0)
                }
                try Self.writePNG(bgra, width: Self.edge, height: Self.edge,
                                  to: dir.appendingPathComponent(
                                      String(format: "live_f%04d.png", frame)))
            }
            print(String(format: "[alfven-live] exposure %.3f hue %.2f  meanLum avg %.3f "
                                 + "min %.3f max %.3f   DISPLAYED-LINEAR (film.py port 0.159, "
                                 + "REF 01 0.114, REF 05 0.229)",
                         solver.displayExposure, solver.displayHueCentre,
                         lums.reduce(0, +) / Double(lums.count),
                         lums.min() ?? 0, lums.max() ?? 0))
            return
        }

        // ALFVEN_VIGOUR: does more drive actually LOOK more vigorous? The drive map is a
        // curve onto the forcing amplitude, but nothing guarantees the display responds
        // to the top
        // of it: substeps are fixed at 4 and dt is CFL-reduced, so a harder-forced field
        // advances LESS sim time per frame. Whether net stirring still rises with drive is
        // an empirical question about the whole pipeline, not a property of the map.
        //
        // Metric: mean per-frame absolute pixel delta on the PRODUCTION display path —
        // "how much of the frame changed", which is what stirring vigour looks like. Held
        // at a CONSTANT bassRel per run so the only variable is the drive level; sweep by
        // re-running across the measured envelope percentiles.
        if env["ALFVEN_VIGOUR"] == "1" {
            let frames = Int(env["ALFVEN_FRAMES"] ?? "240") ?? 240
            let settle = Int(env["ALFVEN_SETTLE"] ?? "60") ?? 60
            let target = try Self.makeTarget(ctx, edge: Self.edge)
            var previous: [UInt8] = []
            var deltas: [Double] = []
            var drives: [Float] = []
            var clipFractions: [Double] = []
            var ajP50: [Double] = []
            var ajP95: [Double] = []
            var meanAbsJ: [Double] = []
            var meanJEma = 0.0
            var exposures: [Double] = []
            var lumas: [Double] = []
            var relDeltas: [Double] = []
            var filmSpan: [Double] = []
            for frame in 1...frames {
                guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                    throw HarnessError.commandBufferFailed
                }
                var f = FeatureVector()
                f.time = Float(frame) / 60.0
                f.deltaTime = 1.0 / 60.0
                f.bassRel = env["ALFVEN_BASSDEV"].flatMap(Float.init) ?? 0.0
                f.bassDev = max(f.bassRel, 0)
                f.trebRel = env["ALFVEN_TREBREL"].flatMap(Float.init) ?? 0
                f.spectralCentroid = env["ALFVEN_CENTROID"].flatMap(Float.init) ?? 0.125
                solver.update(features: f, stemFeatures: StemFeatures(), commandBuffer: cmd)
                // ALFVEN_AUTOEXP: CPU-side PROTOTYPE of film.py's auto-exposure, to measure
                // the visual outcome before committing to a GPU reduction. `autoexp` divides
                // by (p99.6 - p2); measured over drive 5…24 that span tracks mean|J| at a
                // ratio of 0.163 +/- 6% while the field energy moves 4.8x, so mean|J| — which
                // the solver's existing CFL-style atomic reduction can produce — substitutes.
                // The readback here is far too slow to ship; it is an instrument, not a design.
                if env["ALFVEN_AUTOEXP"] == "1" {
                    cmd.commit(); cmd.waitUntilCompleted()
                    let jNow = Self.readJ(solver)
                    let m = jNow.reduce(0.0) { $0 + abs($1) } / Double(jNow.count)
                    let tau = Double(env["ALFVEN_AUTOEXP_TAU"] ?? "0.30") ?? 0.30
                    let alpha = 1.0 - exp(-(1.0 / 60.0) / max(tau, 1e-4))
                    meanJEma = meanJEma <= 0 ? m : meanJEma + alpha * (m - meanJEma)
                    // PARTIAL adaptation. beta = 0 is the fixed constant; beta = 1 is
                    // film.py exactly (0.085 * 1.917 = 0.163, the measured ratio). film.py
                    // renders STILLS, each normalised independently, so it never had to
                    // carry loudness across time — for a visualiser the brightness
                    // variation it removes is signal. beta trades clipping against that.
                    let beta = Double(env["ALFVEN_AUTOEXP_BETA"] ?? "1.0") ?? 1.0
                    let meanRef = 1.917
                    let expo0 = 0.085
                    let e = expo0 * pow(meanRef / max(meanJEma, 1e-6), beta)
                    solver.displayExposure = Float(min(max(e, 0.01), 0.40))
                }
                guard let cmd2 = env["ALFVEN_AUTOEXP"] == "1"
                        ? ctx.commandQueue.makeCommandBuffer() : cmd else {
                    throw HarnessError.commandBufferFailed
                }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                guard let enc = cmd2.makeRenderCommandEncoder(descriptor: pass) else {
                    throw HarnessError.commandBufferFailed
                }
                solver.render(encoder: enc, features: f)
                enc.endEncoding()
                cmd2.commit(); cmd2.waitUntilCompleted()
                let now = Self.pixels(target)
                // Skip the settle window: the seeded field's initial transient is not the
                // steady-state stirring the metric is meant to describe.
                if frame > settle, !previous.isEmpty {
                    var sum = 0.0
                    for i in stride(from: 0, to: now.count, by: 4) {
                        sum += abs(Double(now[i]) - Double(previous[i]))
                            + abs(Double(now[i + 1]) - Double(previous[i + 1]))
                            + abs(Double(now[i + 2]) - Double(previous[i + 2]))
                    }
                    let d = sum / Double(now.count / 4 * 3)
                    deltas.append(d)
                    // ⚠ `meanPixelDelta` scales with EXPOSURE: the same structural change
                    // under a 2.5x darker tone map yields 2.5x smaller pixel differences.
                    // Comparing two exposure schemes on it measures brightness, not motion
                    // (it made film.py's own auto-exposure look like a 27 % motion loss).
                    // `relDelta` divides by the frame's own brightness, so it compares how
                    // much of what is VISIBLE changed — the thing the eye actually reads.
                    var lumaSum = 0.0
                    for i in stride(from: 0, to: now.count, by: 4) {
                        lumaSum += 0.0722 * Double(now[i]) + 0.7152 * Double(now[i + 1])
                            + 0.2126 * Double(now[i + 2])
                    }
                    let meanLuma = lumaSum / Double(now.count / 4)
                    lumas.append(meanLuma)
                    relDeltas.append(d / max(meanLuma, 1e-6))
                    drives.append(solver.audioDrive)
                    // Per-frame, not a final snapshot: one frame of a chaotic field is far
                    // too noisy to size a display lever from (a single-frame read made the
                    // clip fraction non-monotonic in drive, which the field is not).
                    let jf = Self.readJ(solver)
                    // ⚠ Must include the GPU-computed factor. ALFVEN.3g moved part of the
                    // exposure onto the GPU (`exposureBuffer[0]`); reading only
                    // `displayExposure` here measured a quantity the shader no longer uses
                    // and reported the pre-fix clip fraction against a fixed build.
                    let factor = Double(
                        solver.exposureBuffer.contents().assumingMemoryBound(to: Float.self).pointee)
                    let expo = Double(solver.displayExposure) * factor
                    clipFractions.append(
                        Double(jf.filter { abs($0) * expo >= 1.0 }.count) / Double(jf.count))
                    let aj = jf.map { abs($0) * expo }.sorted()
                    ajP50.append(aj[aj.count / 2])
                    ajP95.append(aj[min(aj.count - 1, aj.count * 95 / 100)])
                    // ALFVEN.3g: can a cheap GPU-reducible statistic stand in for film.py's
                    // percentile normaliser? `autoexp` divides by (p99.6 - p2) of |J|; a
                    // fragment cannot do percentiles, but the solver already runs an atomic
                    // reduction for the CFL timestep, so mean|J| IS reachable. Record both
                    // per frame and compare — if their ratio is stable, mean substitutes.
                    let absJ = jf.map { abs($0) }.sorted()
                    meanAbsJ.append(absJ.reduce(0, +) / Double(absJ.count))
                    exposures.append(Double(solver.displayExposure))
                    let hi = absJ[min(absJ.count - 1, Int(0.996 * Double(absJ.count - 1)))]
                    let lo = absJ[max(0, Int(0.02 * Double(absJ.count - 1)))]
                    filmSpan.append(hi - lo)
                }
                previous = now
            }
            let mean = deltas.reduce(0, +) / Double(max(deltas.count, 1))
            if let tag = env["ALFVEN_VIGOUR_PNG"] {
                let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("uzume-alfven-beta")
                try FileManager.default.createDirectory(at: dir,
                                                        withIntermediateDirectories: true)
                try Self.writePNG(previous, width: Self.edge, height: Self.edge,
                                  to: dir.appendingPathComponent("\(tag).png"))
            }
            func avg(_ xs: [Double]) -> Double { xs.reduce(0, +) / Double(max(xs.count, 1)) }
            print(String(format: "[alfven-vigour] bassRel %+.4f -> drive %.2f   "
                                 + "meanPixelDelta %.4f  relDelta %.5f  luma %.1f  aJ p50 %.3f p95 %.3f   "
                                 + "CLIPPED %.2f%% (max %.2f%%)   n %d",
                         env["ALFVEN_BASSDEV"].flatMap(Float.init) ?? 0.0,
                         drives.last ?? 0, mean, avg(relDeltas), avg(lumas),
                         avg(ajP50), avg(ajP95),
                         avg(clipFractions) * 100.0, (clipFractions.max() ?? 0) * 100.0,
                         deltas.count))
            print(String(format: "               mean|J| %.4f   filmSpan(p99.6-p2) %.4f   "
                                 + "ratio %.4f   film-exposure-equiv %.4f (fixed is %.4f)",
                         avg(meanAbsJ), avg(filmSpan),
                         avg(meanAbsJ) / max(avg(filmSpan), 1e-9),
                         1.0 / max(avg(filmSpan), 1e-9), avg(exposures)))
            return
        }

        // ALFVEN_FLASH: the D-157 flash-safety metric on the PRODUCTION path — max
        // frame-to-frame delta of mean luminance while the audio drivers move. Renders
        // EVERY frame (not every 60th), because a strobe is by definition a single-frame
        // event and a sampled harness cannot see one.
        if env["ALFVEN_FLASH"] == "1" {
            let frames = Int(env["ALFVEN_FRAMES"] ?? "600") ?? 600
            let target = try Self.makeTarget(ctx, edge: Self.edge)
            var lums: [Double] = []
            var blooms: [Float] = []
            for frame in 1...frames {
                guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                    throw HarnessError.commandBufferFailed
                }
                var f = FeatureVector()
                f.time = Float(frame) / 60.0
                f.deltaTime = 1.0 / 60.0
                f.bassRel = env["ALFVEN_BASSDEV"].flatMap(Float.init) ?? -0.014
                f.spectralCentroid = env["ALFVEN_CENTROID"].flatMap(Float.init) ?? 0.125
                // A percussive treble train: bursts to the p99 the fixtures actually show,
                // silent between. This is the shape that produced Matt's strobe.
                let burst = (frame % 24) < 3
                f.trebRel = burst ? (env["ALFVEN_TREBREL"].flatMap(Float.init) ?? 0.017) : 0.0
                solver.update(features: f, stemFeatures: StemFeatures(), commandBuffer: cmd)
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear
                pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
                guard let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else {
                    throw HarnessError.commandBufferFailed
                }
                solver.render(encoder: enc, features: f)
                enc.endEncoding()
                cmd.commit(); cmd.waitUntilCompleted()
                lums.append(Self.meanLuma(target))
                blooms.append(solver.displayBloomAmount)
            }
            var maxDelta = 0.0
            var over = 0
            for i in 1..<lums.count {
                let d = abs(lums[i] - lums[i - 1])
                maxDelta = max(maxDelta, d)
                if d > 0.05 { over += 1 }
            }
            print(String(format: "[alfven-flash] bloom %.2f...%.2f  maxDelta %.4f  over-gate %d/%d "
                                 + "(D-157 gate 0.05)",
                         blooms.min() ?? 0, blooms.max() ?? 0, maxDelta, over, lums.count - 1))
            return
        }

        // ALFVEN_SWEEP: report brightness across a LONG run instead of four stills. The
        // re-seed cadence can only be judged over several cycles, and mean(aJ) is the
        // right per-frame proxy — it tracks film.py's delivered luma closely (0.061 ->
        // meanLum 0.130, 0.116 -> 0.188, 0.290 -> 0.324) and needs no blur.
        if env["ALFVEN_SWEEP"] == "1" {
            let frames = Int(env["ALFVEN_FRAMES"] ?? "900") ?? 900
            var samples: [Double] = []
            for frame in 1...frames {
                guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                    throw HarnessError.commandBufferFailed
                }
                solver.update(time: Float(frame) / 60.0, commandBuffer: cmd)
                cmd.commit(); cmd.waitUntilCompleted()
                guard frame % 10 == 0 else { continue }
                let aJ = Self.autoexp(Self.readJ(solver).map(abs))
                samples.append(aJ.reduce(0, +) / Double(aJ.count))
            }
            let mean = samples.reduce(0, +) / Double(samples.count)
            // 0.20 is the mean(aJ) that lands near REF 01's meanLum 0.283.
            let good = Double(samples.filter { $0 > 0.20 }.count) / Double(samples.count)
            print(String(format: "[alfven-sweep] cycle=%.1f simClock=%.2f  mean(aJ) avg %.3f "
                                 + "min %.3f max %.3f  frac(>0.20) %.3f",
                         cfg.cycleSeconds, solver.simClock, mean,
                         samples.min() ?? 0, samples.max() ?? 0, good))
            return
        }

        let last = Self.captureAt.max() ?? 0
        for frame in 1...last {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            solver.update(time: Float(frame) / 60.0, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
            guard Self.captureAt.contains(frame) else { continue }

            let j = Self.readJ(solver)
            let stats = Self.fieldStats(j)
            // Raw autoexp(|J|) as grey — no colour mapping, no blur. Keep this: when
            // the frames showed fine diagonal hatching on the steepest ridges, this dump
            // is what separated "the FIELD has grid-scale energy" from "the film mapping
            // is amplifying it" in one look. film.py's hue term is a periodic function of
            // J, so it turns a ripple far too small to see in grey into a vivid colour
            // band — the colour frame alone cannot tell you which half is at fault.
            let g = Self.autoexp(j.map(abs))
            var grey = [UInt8](repeating: 255, count: Self.edge * Self.edge * 4)
            for i in 0..<(Self.edge * Self.edge) {
                let v = UInt8(min(max(g[i], 0), 1) * 255)
                grey[i * 4 + 0] = v; grey[i * 4 + 1] = v; grey[i * 4 + 2] = v
            }
            try Self.writePNG(grey, width: Self.edge, height: Self.edge,
                              to: dir.appendingPathComponent(
                                  String(format: "raw_J_f%04d.png", frame)))

            // Raw J as float64 little-endian, so film.py itself can be run on the very
            // same field. That is the only way to tell "our field's |J| distribution is
            // wrong" apart from "the Swift port of film.py is wrong".
            var raw = Data(capacity: j.count * 8)
            for value in j { withUnsafeBytes(of: value.bitPattern.littleEndian) { raw.append(contentsOf: $0) } }
            try raw.write(to: dir.appendingPathComponent(String(format: "J_f%04d.f64", frame)))
            for (channel, tag) in [(0, "W"), (1, "P")] {
                var out = Data(capacity: j.count * 8)
                for value in Self.readChannel(solver, channel) {
                    withUnsafeBytes(of: value.bitPattern.littleEndian) { out.append(contentsOf: $0) }
                }
                try out.write(to: dir.appendingPathComponent(
                    String(format: "%@_f%04d.f64", tag, frame)))
            }

            let rgb = Self.film(j, width: Self.edge, height: Self.edge)
            let url = dir.appendingPathComponent(String(format: "alfven_film_f%04d.png", frame))
            try Self.writePNG(rgb, width: Self.edge, height: Self.edge, to: url)
            // Delivered brightness, the only number that can be compared against the
            // reference PNGs: film.py's own value curve, then Rec.709 luma of the final
            // RGB. REF 05 (the silence target) is meanLum 0.422; REF 01 is 0.283.
            let aJ = Self.autoexp(j.map(abs))
            let meanAJ = aJ.reduce(0, +) / Double(aJ.count)
            var lumSum = 0.0
            var bright = 0
            for i in 0..<(Self.edge * Self.edge) {
                let lum = 0.2126 * Double(rgb[i * 4 + 2]) / 255.0
                        + 0.7152 * Double(rgb[i * 4 + 1]) / 255.0
                        + 0.0722 * Double(rgb[i * 4 + 0]) / 255.0
                lumSum += lum
                if lum > 0.25 { bright += 1 }
            }
            let meanLum = lumSum / Double(Self.edge * Self.edge)
            print(String(format: "[alfven-film] f%4d  mean(aJ) %.3f  meanLum %.3f  "
                                 + "frac>0.25 %.3f", frame, meanAJ, meanLum,
                         Double(bright) / Double(Self.edge * Self.edge)))
            print(String(format: "[alfven-film] f%4d  J p2 %+.5f p99.6 %+.5f std %.5f "
                                 + "| dynamic range %.1fx | %@",
                         frame, stats.p2, stats.p996, stats.std,
                         stats.p996 / max(abs(stats.p2), 1e-9), url.lastPathComponent))
        }
        print("[alfven-film] wrote to \(dir.path)")
    }

    /// `.b` of the solver's state texture is J = lap(psi) — what the fragment colours (§4).
    private static func readJ(_ solver: AlfvenSolver) -> [Double] {
        readChannel(solver, 2)
    }

    /// Offscreen colour target for the production display pass.
    private static func makeTarget(_ ctx: MetalContext, edge: Int) throws -> MTLTexture {
        let d = MTLTextureDescriptor()
        d.pixelFormat = ctx.pixelFormat
        d.width = edge; d.height = edge
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: d) else {
            throw HarnessError.setupFailed("no render target")
        }
        return tex
    }

    /// Rec.709 mean luma in DISPLAYED-LINEAR space — what the panel actually emits.
    ///
    /// This has to sRGB-DECODE the bytes, and getting that wrong invalidates the whole
    /// comparison. `MetalContext.pixelFormat` is `.bgra8Unorm_srgb`, so the render target
    /// stores gamma-ENCODED bytes and the display decodes them back to the shader's linear
    /// output. film.py and the reference PNGs do the opposite: they write LINEAR values
    /// straight to bytes (`(rgb*255).astype(uint8)`), which a viewer then decodes as sRGB
    /// — so the references appear much darker than their byte values suggest, and that
    /// darker appearance is what Matt approved. Comparing raw byte means across the two
    /// conventions is apples-to-oranges: it made the live path look 2x too DARK and sent
    /// me to an exposure of 0.05 that killed the hue opponency. Decode both, then compare.
    ///
    /// Targets in this space: our film.py port 0.159, REF 01 0.114, REF 05 0.229.
    private static func srgbToLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// Raw BGRA bytes of a rendered frame — the input to the vigour delta.
    private static func pixels(_ tex: MTLTexture) -> [UInt8] {
        var bgra = [UInt8](repeating: 0, count: tex.width * tex.height * 4)
        bgra.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: tex.width * 4,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: tex.width,
                                                       height: tex.height, depth: 1)),
                         mipmapLevel: 0)
        }
        return bgra
    }

    private static func meanLuma(_ tex: MTLTexture) -> Double {
        let n = tex.width
        var raw = [UInt8](repeating: 0, count: n * n * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: n * 4,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: n, height: n, depth: 1)),
                         mipmapLevel: 0)
        }
        // BGRA8 on this path.
        var sum = 0.0
        for i in 0..<(n * n) {
            sum += 0.2126 * srgbToLinear(Double(raw[i * 4 + 2]) / 255.0)
                 + 0.7152 * srgbToLinear(Double(raw[i * 4 + 1]) / 255.0)
                 + 0.0722 * srgbToLinear(Double(raw[i * 4 + 0]) / 255.0)
        }
        return sum / Double(n * n)
    }

    /// `.x` = omega, `.y` = psi, `.z` = J.
    private static func readChannel(_ solver: AlfvenSolver, _ channel: Int) -> [Double] {
        let tex = solver.stateTexture
        let n = tex.width
        var raw = [Float](repeating: 0, count: n * n * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: n * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: n, height: n, depth: 1)),
                         mipmapLevel: 0)
        }
        return (0..<(n * n)).map { Double(raw[$0 * 4 + channel]) }
    }

    // MARK: film.py, ported

    private struct Stats { var p2 = 0.0, p996 = 0.0, std = 0.0 }

    private static func fieldStats(_ j: [Double]) -> Stats {
        let absSorted = j.map(abs).sorted()
        let mean = j.reduce(0, +) / Double(j.count)
        let varr = j.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(j.count)
        func pct(_ p: Double) -> Double {
            let idx = min(max(Int(p / 100.0 * Double(absSorted.count - 1)), 0), absSorted.count - 1)
            return absSorted[idx]
        }
        return Stats(p2: pct(2.0), p996: pct(99.6), std: varr.squareRoot())
    }

    /// `autoexp(a, lo=2.0, hi=99.6)` — percentile normalisation, the reason J's absolute
    /// scale does not matter to the look (and the same FA #31 reasoning as deviation
    /// primitives: track the field's own distribution, never an absolute threshold).
    private static func autoexp(_ a: [Double]) -> [Double] {
        let s = a.sorted()
        func pct(_ p: Double) -> Double {
            let idx = min(max(Int(p / 100.0 * Double(s.count - 1)), 0), s.count - 1)
            return s[idx]
        }
        let p1 = pct(2.0), p2 = pct(99.6)
        let d = max(p2 - p1, 1e-9)
        return a.map { min(max(($0 - p1) / d, 0), 1) }
    }

    private static func filmic(_ x: Double) -> Double {
        let a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14
        return min(max((x * (a * x + b)) / (x * (c * x + d) + e), 0), 1)
    }

    private static func hsv2rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let hh = (h - h.rounded(.down)) * 6.0
        let i = Int(hh), f = hh - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    /// Separable Gaussian, matching `scipy.ndimage.gaussian_filter(core, sigma)`.
    private static func blur(_ src: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        let radius = max(Int(sigma * 3.0), 1)
        var kernel = [Double](repeating: 0, count: radius * 2 + 1)
        var sum = 0.0
        for i in 0...(radius * 2) {
            let x = Double(i - radius)
            let w = exp(-(x * x) / (2 * sigma * sigma))
            kernel[i] = w; sum += w
        }
        for i in kernel.indices { kernel[i] /= sum }

        var tmp = [Double](repeating: 0, count: src.count)
        var out = [Double](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in 0...(radius * 2) {
                    let sx = min(max(x + k - radius, 0), width - 1)
                    acc += src[y * width + sx] * kernel[k]
                }
                tmp[y * width + x] = acc
            }
        }
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in 0...(radius * 2) {
                    let sy = min(max(y + k - radius, 0), height - 1)
                    acc += tmp[sy * width + x] * kernel[k]
                }
                out[y * width + x] = acc
            }
        }
        return out
    }

    /// `film.py:render()`, at silence (sizzle clips to 0 ⇒ amt = 0.30; hue centre 0.52).
    private static func film(_ j: [Double], width: Int, height: Int) -> [UInt8] {
        let aJ = autoexp(j.map(abs))
        let mean = j.reduce(0, +) / Double(j.count)
        let sd = (j.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(j.count)).squareRoot()
        let sJ = j.map { tanh($0 / (sd * 1.2 + 1e-9)) }

        let core = aJ.map { pow(min(max(($0 - 0.72) / 0.28, 0), 1), 1.5) }
        let b0 = blur(core, width: width, height: height, sigma: 2.0)
        let b1 = blur(core, width: width, height: height, sigma: 7.0)
        let amt = 0.30   // silence: sizzle = trebRel - 0.6 clips to 0

        let tintA = (1.00, 0.72, 0.42), tintB = (0.45, 0.72, 1.00)
        let ground = (0.035, 0.045, 0.075)

        var out = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            // Matt's pick (2026-09-09): the FOURTH COLUMN of the concept sheet, i.e. the
            // LATE end of film.py's palette drift — magenta <-> teal, not the early
            // acid-green <-> violet. film.py maps hue = 0.46 + 0.26*centroid01, so the
            // late end is 0.72. `04_palette_opponent_drift.png` annotates exactly this:
            // "Left = early (acid green <-> violet), right = late (magenta <-> teal)".
            let hue = Self.hueCentre + 0.30 * sJ[i]
            let sat = 0.32 + 0.58 * (1.0 - aJ[i] * aJ[i])
            let val = filmic(1.9 * pow(aJ[i], 0.85))
            var (r, g, b) = hsv2rgb(hue, min(max(sat, 0), 1), min(max(val, 0), 1))

            let glow = 0.75 * b0[i] + 0.55 * b1[i]
            let split = 0.5 + 0.5 * sJ[i]
            r += amt * glow * (tintA.0 * split + tintB.0 * (1 - split))
            g += amt * glow * (tintA.1 * split + tintB.1 * (1 - split))
            b += amt * glow * (tintA.2 * split + tintB.2 * (1 - split))

            r += ground.0 * (1 - val); g += ground.1 * (1 - val); b += ground.2 * (1 - val)

            // BGRA, premultiplied-first byte order to match the PNG writer.
            out[i * 4 + 0] = UInt8(min(max(b, 0), 1) * 255)
            out[i * 4 + 1] = UInt8(min(max(g, 0), 1) * 255)
            out[i * 4 + 2] = UInt8(min(max(r, 0), 1) * 255)
            out[i * 4 + 3] = 255
        }
        return out
    }

    // MARK: plumbing

    private static func readJ(_ pipeline: RenderPipeline) throws -> [Double] {
        guard let tex = pipeline.stagedTexture(named: "state") else {
            throw HarnessError.setupFailed("no state texture")
        }
        let w = tex.width, h = tex.height
        var raw = [Float](repeating: 0, count: w * h * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: w * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: w, height: h, depth: 1)),
                         mipmapLevel: 0)
        }
        return (0..<(w * h)).map { Double(raw[$0 * 4 + 2]) }   // .b = J
    }

    private static func writePNG(_ bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw HarnessError.setupFailed("sRGB")
        }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let cg = CGContext(data: base, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: space, bitmapInfo: info.rawValue) else { return nil }
            return cg.makeImage()
        }
        guard let image, let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw HarnessError.setupFailed("png dest")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw HarnessError.setupFailed("png write") }
    }
}
