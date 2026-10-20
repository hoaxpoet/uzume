// EnergeticFlybyRenderTests — EFB.1 rendered evidence for Energetic Flyby, all through
// `MultiPassRenderHarness`'s direct path: the scene fragment with `EnergeticFlybyState` ticked per
// frame and bound at slot 6, exactly as production's `setMeshPresetTick` + `encodePresetVisualization`
// do (not `preset.pipelineState` against a zeroed slot).
//
//   • whiteOutIsBounded (always runs) — a forced rod-through-camera moment, with a negative control.
//   • faithfulStills (RENDER_VISUAL=1) — EFB_FAITHFUL stills at 3.0 / 7.0 / 12.5 / 18.0 s for
//     `Scripts/compare_render.sh energetic_flyby` against references 01–04.
//   • replayEvidence (EFB_REPLAY=1) — 20 s of each route-coverage capture at 1080p, 60 fps: continuity,
//     downbeat timing against Beat This!, D-157 luminance, a motion-gate sequence and two look stills.
//   • releaseTiming (EFB_TIMING=1) — GPU time at 1080p / 4K and the 0.75× / 0.5× scales. Release only:
//     `swift test -c release --enable-testable-imports --filter EnergeticFlybyRender`.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
import simd
@testable import Renderer
@testable import Presets
@testable import Shared
@testable import Diagnostics

@Suite("EnergeticFlybyRender (EFB.1)")
@MainActor
struct EnergeticFlybyRenderTests {

    private static let preset = "Energetic Flyby"
    private static let fps: Float = 60

    // MARK: - White-out (design §5)

    @Test("A rod through the camera does not white out the frame (forced moment + negative control)")
    func whiteOutIsBounded() throws {
        // Find the spin at which a sphere rod passes closest to the camera (CPU copy of Kali's rod
        // distance), then render five consecutive frames with the rods sweeping past at the fastest
        // spin the bass can drive (4 rad/s).
        var best = (travel: Float(0), spin: Float(0), distance: Float.infinity)
        for travelStep in 0..<200 {
            let travel = Float(travelStep) * 0.05
            for spinStep in 0..<6_300 {
                let spin = Float(spinStep) * 0.002
                let distance = Self.rodDistanceAtCamera(travel: travel, spin: spin)
                if distance < best.distance { best = (travel, spin, distance) }
            }
        }
        let time = best.travel
        #expect(best.distance < 0.01, "no rod passes the camera in the sweep (closest \(best.distance))")
        let spinStep: Float = 4 / Self.fps
        func frames(faithful: Float) -> [EnergeticFlybyStateGPU] {
            (-2...2).map { k in
                EnergeticFlybyStateGPU(time: time, travel: time, camT: time, spin: best.spin + Float(k) * spinStep,
                                       flicker: 0, glowBase: 1.25, faithful: faithful)   // typical glow = Kali's average
            }
        }
        func luma(_ states: [EnergeticFlybyStateGPU]) throws -> [Double] {
            var harness = MultiPassRenderHarness(width: 320, height: 180)
            harness.energeticFlybyForced = states
            let drive = states.map { _ in FeatureVector(deltaTime: 1 / Self.fps) }
            return try harness.render(preset: Self.preset, features: drive,
                                      stems: drive.map { _ in .zero }, reduce: Self.meanLuma)
        }
        let without = try luma(frames(faithful: 1))   // Kali's glow, no fix: the white-out
        let with = try luma(frames(faithful: 0))      // the shipped path
        func ratios(_ l: [Double]) -> (Double, Double) { (l[2] / l[1], l[2] / l[3]) }
        print(String(format: "[efb-whiteout] rod %.4f from camera at travel %.2f spin %.4f | no fix: %@ (×%.2f, ×%.2f) | "
                     + "fixed: %@ (×%.2f, ×%.2f)", best.distance, best.travel, best.spin,
                     without.map { String(format: "%.3f", $0) }.joined(separator: " "), ratios(without).0, ratios(without).1,
                     with.map { String(format: "%.3f", $0) }.joined(separator: " "), ratios(with).0, ratios(with).1))
        // Negative control: without the fix the forced moment IS a white-out, or this test forces nothing.
        #expect(max(ratios(without).0, ratios(without).1) > 1.25, "negative control did not white out: \(without)")
        for ratio in [ratios(with).0, ratios(with).1] {
            #expect(ratio <= 1.25 && ratio >= 1 / 1.25, "middle frame vs neighbour ×\(ratio): \(with)")
        }
    }

    /// Kali's rod distance (`br` in `coso`) at the camera, for the one sphere system the scene keeps.
    static func rodDistanceAtCamera(travel: Float, spin: Float) -> Float {
        func path(_ t: Float) -> SIMD3<Float> { SIMD3(sin(t + cos(t) * 0.5) * 0.5, cos(t * 0.5), t) }
        func rot(_ v: SIMD2<Float>, _ a: Float) -> SIMD2<Float> {   // GLSL/MSL `v * mat2(c, s, -s, c)`
            SIMD2(v.x * cos(a) + v.y * sin(a), -v.x * sin(a) + v.y * cos(a))
        }
        func rods(_ q: SIMD3<Float>) -> Float {
            var p = q * 0.7
            let xy = rot(SIMD2(p.x, p.y), p.z * 2); p.x = xy.x; p.y = xy.y
            let xz = rot(SIMD2(p.x, p.z), spin * 2); p.x = xz.x; p.z = xz.y
            let yz = rot(SIMD2(p.y, p.z), spin); p.y = yz.x; p.z = yz.y
            var br = simd_length(p) - 0.03
            br = min(br, simd_length(SIMD2(p.x, p.y)) + 0.005)
            br = min(br, simd_length(SIMD2(p.x, p.z)) + 0.005)
            br = min(br, simd_length(SIMD2(p.y, p.z)) + 0.005)
            return max(br, simd_length(p) - 1)
        }
        let from = path(travel) + SIMD3(0.2, 0, 0)
        return rods(from - path(travel + 0.5))
    }

    // MARK: - Flash ablation (EFB_FLASH_DIAG=1)

    @Test("Which driver flashes: the worst-case train with each driver switched off (EFB_FLASH_DIAG=1)")
    func flashAblation() throws {
        guard ProcessInfo.processInfo.environment["EFB_FLASH_DIAG"] == "1" else { return }
        let train = FlashHarnessSupport.worstCaseBeatTrain()
        let drive = (0..<900).map { train[$0 % train.count] }
        let stems = (0..<900).map { _ in StemFeatures.zero }
        let trace = EnergeticFlybyTraceLog()
        var harness = MultiPassRenderHarness(width: 320, height: 180)
        harness.energeticFlybyTrace = trace
        let shipped = try harness.render(preset: Self.preset, features: drive, stems: stems) {
            FlashHarnessSupport.sample($0, width: 320, height: 180)
        }
        let base = trace.states
        func arm(_ edit: (Int, inout EnergeticFlybyStateGPU) -> Void) throws -> [FlashHarnessSupport.FlashSample] {
            var states = base
            for i in states.indices { edit(i, &states[i]) }
            var forced = MultiPassRenderHarness(width: 320, height: 180)
            forced.energeticFlybyForced = states
            return try forced.render(preset: Self.preset, features: drive, stems: stems) {
                FlashHarnessSupport.sample($0, width: 320, height: 180)
            }
        }
        func report(_ name: String, _ samples: [FlashHarnessSupport.FlashSample]) {
            let luma = samples.map(\.luma)
            let full = FlashAnalyzer.analyze(relativeLuminance: luma, fps: FlashHarnessSupport.fps)
            let regional = FlashAnalyzer.analyzeRegional(samples.map(\.regions), fps: FlashHarnessSupport.fps)
            let red = FlashAnalyzer.analyzeRed(samples.map(\.regions), fps: FlashHarnessSupport.fps)
            let deltas = zip(luma, luma.dropFirst()).map { abs($1 - $0) }
            print(String(format: "[efb-flash-diag] %@: full %.2f/s (%d) | regional %.2f/s | red %.2f/s | "
                         + "luma %.3f…%.3f, max Δ/frame %.4f", name, full.peakFlashesPerSecond, full.transitionCount,
                         regional.peakFlashesPerSecond, red.peakFlashesPerSecond,
                         luma.min() ?? 0, luma.max() ?? 0, deltas.max() ?? 0))
        }
        report("shipped", shipped)
        let fixedGlow = EnergeticFlybyState.glowFloor + EnergeticFlybyState.glowGain * 0.5
        report("no hue, roll", try arm { _, s in s.hue = 0; s.roll = 0 })
        report("+ constant glow", try arm { _, s in s.hue = 0; s.roll = 0; s.glowBase = fixedGlow })
        report("+ constant speed + spin", try arm { i, s in
            let t = Float(i) / 60
            s.hue = 0; s.roll = 0; s.glowBase = fixedGlow
            s.travel = t * 1.05; s.camT = s.travel; s.spin = t * 2
        })
        report("Kali (faithful)", try arm { i, s in
            let t = Float(i) / 60, sine = sin(t) * 123.456
            s = EnergeticFlybyStateGPU(time: t, travel: t,
                                       camT: t.truncatingRemainder(dividingBy: 10) > 5 ? (t / 4 + 0.5).rounded(.down) * 4 : t,
                                       spin: t, flicker: sine - sine.rounded(.down), glowBase: 0.5, faithful: 1)
        })
    }

    // MARK: - Faithful stills (task 1)

    @Test("Faithful-mode stills at the reference times (RENDER_VISUAL=1)")
    func faithfulStills() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        // The state's clock advances by the clamped dt (≤ 0.1 s), so 180 ticks of 0.1 s reach 18.0 s.
        let drive = (0..<180).map { _ in FeatureVector(deltaTime: 0.1) }
        var harness = MultiPassRenderHarness(width: 1280, height: 720)
        harness.energeticFlybyFaithful = true
        let pixels = try harness.render(preset: Self.preset, features: drive,
                                        stems: drive.map { _ in .zero }) { $0 }
        let dir = try Self.visualDir()
        for (frame, label) in [(29, "3.0"), (69, "7.0"), (124, "12.5"), (179, "18.0")] {
            try Self.writePNG(pixels[frame], 1280, 720,
                              dir.appendingPathComponent("Energetic_Flyby_faithful_t\(label).png"))
        }
        print("[efb-faithful] stills in \(dir.path)")
    }

    // MARK: - Replay evidence (task 6 + the task 3 luminance numbers)

    @Test("Replay of the route-coverage captures at 1080p (EFB_REPLAY=1)")
    func replayEvidence() throws {
        guard ProcessInfo.processInfo.environment["EFB_REPLAY"] == "1" else { return }
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["EFB_REPLAY_OUT"] ?? "/tmp/efb_replay")
        let visual = try Self.visualDir()
        for capture in ["there_there", "love_rehab", "so_what"] {
            try replay(capture, out: out.appendingPathComponent(capture), visual: visual)
        }
    }

    private func replay(_ capture: String, out: URL, visual: URL) throws {
        let fixtures = Self.fixturesDir()
        let rows = try SessionReplayHarness.loadRowsForReplay(
            fixtures.appendingPathComponent("route_coverage/\(capture)/features.csv"))
        // The capture is ~43 Hz; production renders at 60 fps from the latest analysis frame, so the
        // drive holds each row until the next one arrives (on the capture's playback-time axis, the
        // axis Beat This! reports in).
        let seconds: Float = 20, start = rows[0].playbackTime
        var drive: [FeatureVector] = [], times: [Float] = []
        var row = 0
        for i in 0..<Int(seconds * Self.fps) {
            let t = start + Float(i) / Self.fps
            while row + 1 < rows.count && rows[row + 1].playbackTime <= t { row += 1 }
            var fv = SessionReplayHarness.featureForReplay(from: rows[row], aspect: 16 / 9)
            fv.deltaTime = 1 / Self.fps
            drive.append(fv); times.append(t)
        }
        var harness = MultiPassRenderHarness(width: 1920, height: 1080)
        let trace = EnergeticFlybyTraceLog()
        harness.energeticFlybyTrace = trace
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // Per frame: the luma, the 160×90 continuity thumbnail, a 480×270 motion-gate PNG, and the
        // full 1080p frame at 10 s only (keeping every full frame would hold ~10 GB).
        var index = 0
        var still: [UInt8] = []
        let frames = try harness.render(preset: Self.preset, features: drive, stems: drive.map { _ in .zero }) { bgra in
            defer { index += 1 }
            try? Self.writePNG(Self.downsample(bgra, 1920, 1080, 4), 480, 270,
                               out.appendingPathComponent(String(format: "seq_%04d.png", index)))
            if index == 600 { still = bgra }
            return (luma: Self.meanLuma(bgra), grey: Self.grey(bgra, 1920, 1080, 160, 90))
        }
        try Self.writePNG(still, 1920, 1080, visual.appendingPathComponent("Energetic_Flyby_replay_\(capture)_t10.png"))

        // Continuity: mean |Δ| of the 160×90 grey frames; spikes = frames above 3× the median.
        let diffs = zip(frames, frames.dropFirst()).map { a, b in
            zip(a.grey, b.grey).map { abs($0 - $1) }.reduce(0, +) / Double(a.grey.count)
        }
        let median = diffs.sorted()[diffs.count / 2]
        let spikes = diffs.filter { $0 > 3 * median }.count

        // D-157: per-frame Δ of frame-mean luma.
        let deltas = zip(frames, frames.dropFirst()).map { abs($1.luma - $0.luma) }

        // Downbeat timing: the frame each colour step starts (the downbeat's visual event) against every
        // Beat This! downbeat.
        let states = trace.states
        let peaks = states.indices.filter {
            $0 > 1 && states[$0].hue != states[$0 - 1].hue && states[$0 - 1].hue == states[$0 - 2].hue
        }.map { times[$0] }
        let reference = try Self.referenceDownbeats(capture).filter { $0 >= start && $0 < start + seconds }
        let lags = reference.map { ref in peaks.map { $0 - ref }.min { abs($0) < abs($1) } ?? .infinity }
        let hits = lags.filter { abs($0) <= 1 / Self.fps + 1e-4 }.count
        let finiteLags = lags.filter(\.isFinite).sorted()
        print(String(format: "[efb-replay] %@ | continuity: median %.4f max %.4f, %d frames > 3× median | "
                     + "luma mean %.3f, max Δ %.4f, %d > 0.05, %d > 0.1 | downbeats %d/%d within ±1 frame "
                     + "(lags ms: %@) | colour steps %d",
                     capture, median, diffs.max() ?? 0, spikes,
                     frames.map(\.luma).reduce(0, +) / Double(frames.count), deltas.max() ?? 0,
                     deltas.filter { $0 > 0.05 }.count, deltas.filter { $0 > 0.1 }.count,
                     hits, reference.count,
                     lags.map { $0.isFinite ? String(format: "%+.0f", $0 * 1000) : "miss" }.joined(separator: " "),
                     peaks.count))
        if let mid = finiteLags.dropFirst(finiteLags.count / 2).first {
            print(String(format: "[efb-replay] %@ median lag %+.1f ms", capture, mid * 1000))
        }
    }

    // MARK: - Session replay (EFB_SESSION=<features.csv>)

    /// Replays a recorded session's frames — its own deltaTime per frame, its own features — through the
    /// scene at the session's drawable size, writing every frame as a PNG. For live defects that only one
    /// session showed (EFB.2: seams and blockiness on the Spotify pass). EFB_FROM / EFB_COUNT pick rows,
    /// EFB_W / EFB_H the drawable (default 2636×1398, the Mac mini's Tier-1 fullscreen cap on a 4K TV).
    @Test("Replay a recorded session's frames through the scene (EFB_SESSION=features.csv)")
    func sessionReplay() throws {
        let env = ProcessInfo.processInfo.environment
        guard let csv = env["EFB_SESSION"] else { return }
        let rows = try SessionReplayHarness.loadRowsForReplay(URL(fileURLWithPath: csv))
        let from = Int(env["EFB_FROM"] ?? "") ?? 0, count = Int(env["EFB_COUNT"] ?? "") ?? 300
        let width = Int(env["EFB_W"] ?? "") ?? 2636, height = Int(env["EFB_H"] ?? "") ?? 1398
        let slice = Array(rows[min(from, rows.count - 1)..<min(from + count, rows.count)])
        let drive = slice.map { SessionReplayHarness.featureForReplay(from: $0, aspect: Float(width) / Float(height)) }
        let out = URL(fileURLWithPath: env["EFB_OUT"] ?? "/tmp/efb_session")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        // EFB_TIMING_ONLY=1: no readback or PNGs, just GPU time per frame — the same frames without the live
        // app's other GPU work (stem separation), to split content cost from contention.
        let timingOnly = env["EFB_TIMING_ONLY"] == "1"
        var harness = MultiPassRenderHarness(width: width, height: height, readback: !timingOnly)
        let trace = EnergeticFlybyTraceLog(), log = GPUTimeLog()
        harness.energeticFlybyTrace = trace
        harness.gpuTimes = log
        var index = 0
        _ = try harness.render(preset: Self.preset, features: drive, stems: drive.map { _ in .zero }) { bgra in
            defer { index += 1 }
            if !timingOnly {
                try? Self.writePNG(bgra, width, height, out.appendingPathComponent(String(format: "f_%05d.png", from + index)))
            }
            return 0
        }
        let ms = log.ms.sorted()
        print(String(format: "[efb-session-timing] rows %d…%d at %d×%d: GPU p50 %.1f p95 %.1f max %.1f ms, %.1f%% > 33.3 ms",
                     from, from + slice.count - 1, width, height, ms[ms.count / 2], ms[Int(Double(ms.count) * 0.95)],
                     ms.last ?? 0, Double(ms.filter { $0 > 33.3 }.count) / Double(ms.count) * 100))
        if timingOnly { return }
        for (i, state) in trace.states.enumerated() {
            print(String(format: "[efb-session] row %d dt %.1f ms travel %.3f spin %.3f hue %.3f roll %.3f glow %.3f",
                         from + i, drive[i].deltaTime * 1000, state.travel, state.spin, state.hue, state.roll, state.glowBase))
        }
    }

    // MARK: - Soak (EFB_SOAK=1, EFB.3 certification)

    /// Ten minutes of scene time at native 2560×1440, 30 fps, on one live state (the shared harness's direct path),
    /// driven by a real-music capture looped. Per minute: the frame is lit and moving, not white; resident memory
    /// grows < 25 MB; GPU p50 stays within 1.5× of minute 1.
    @Test("EFB_SOAK=1: ten minutes — memory flat, lit and moving, cost steady",
          .enabled(if: ProcessInfo.processInfo.environment["EFB_SOAK"] == "1"))
    func soak() throws {
        let rows = try SessionReplayHarness.loadRowsForReplay(
            Self.fixturesDir().appendingPathComponent("route_coverage/there_there/features.csv"))
        let perMinute = 1800, minutes = Int(ProcessInfo.processInfo.environment["EFB_SOAK_MINUTES"] ?? "") ?? 10
        let drive = (0..<(perMinute * minutes)).map { i -> FeatureVector in
            var fv = SessionReplayHarness.featureForReplay(from: rows[i % rows.count], aspect: 16 / 9)
            fv.deltaTime = 1 / 30
            return fv
        }
        var harness = MultiPassRenderHarness(width: 2560, height: 1440)
        let log = GPUTimeLog()
        harness.gpuTimes = log
        var lumas: [Double] = [], whites: [Double] = [], memory: [Double] = []
        _ = try harness.render(preset: Self.preset, features: drive, stems: drive.map { _ in .zero }) { bgra in
            // Every 64th pixel: mean luma and the fraction near white.
            var sum = 0.0, white = 0, n = 0
            for i in stride(from: 0, to: bgra.count, by: 256) {
                let blue = 0.114 * Double(bgra[i]), green = 0.587 * Double(bgra[i + 1])
                let y: Double = blue + green + 0.299 * Double(bgra[i + 2])
                sum += y; n += 1; if y > 245 { white += 1 }
            }
            lumas.append(sum / Double(n)); whites.append(Double(white) / Double(n))
            if lumas.count % perMinute == 1 { memory.append(Double(MemoryReporter.snapshot()?.residentBytes ?? 0)) }
            return 0
        }
        let gpu = log.ms
        for minute in 0..<minutes {
            let range = (minute * perMinute)..<((minute + 1) * perMinute)
            let times = gpu[range].sorted(), p50 = times[times.count / 2]
            let firstP50 = gpu[0..<perMinute].sorted()[perMinute / 2]
            let luma = lumas[range].reduce(0, +) / Double(perMinute)
            let moving = zip(lumas[range], lumas[range].dropFirst()).map { abs($0 - $1) }.max() ?? 0
            let white = whites[range].max() ?? 0
            let growth = (memory[minute] - memory[0]) / (1024 * 1024)
            print(String(format: "[efb-soak] min %d: luma %.1f, max frame Δ %.2f, white %.3f | GPU p50 %.1f ms | +%.1f MB",
                         minute + 1, luma, moving, white, p50, growth))
            #expect(luma > 20 && luma < 200 && white < 0.05, "minute \(minute + 1): luma \(luma) white \(white)")
            #expect(moving > 0.05, "minute \(minute + 1): frames not moving")
            #expect(growth < 25, "minute \(minute + 1): resident +\(growth) MB since minute 1")
            #expect(p50 < firstP50 * 1.5, "minute \(minute + 1): GPU p50 \(p50) ms vs \(firstP50) ms in minute 1")
        }
    }

    // MARK: - Release timing (task 7)

    @Test("Release GPU time at 1080p and 4K, and the 0.75× / 0.5× scales (EFB_TIMING=1)")
    func releaseTiming() throws {
        guard ProcessInfo.processInfo.environment["EFB_TIMING"] == "1" else { return }
        #if DEBUG
        print("[efb-timing] WARNING: Debug build — numbers are not quotable (CLAUDE.md)")
        #endif
        let rows = try SessionReplayHarness.loadRowsForReplay(
            Self.fixturesDir().appendingPathComponent("route_coverage/there_there/features.csv"))
        let drive = rows.prefix(300).map { row -> FeatureVector in
            var fv = SessionReplayHarness.featureForReplay(from: row, aspect: 16 / 9)
            fv.deltaTime = 1 / Self.fps
            return fv
        }
        for (label, width, height) in [("1080p", 1920, 1080), ("1440p (Tier-1 cap, 4K TV)", 2560, 1440),
                                       ("4K", 3840, 2160)] {
            var harness = MultiPassRenderHarness(width: width, height: height, readback: false)
            let log = GPUTimeLog()
            harness.gpuTimes = log
            _ = try harness.render(preset: Self.preset, features: Array(drive), stems: drive.map { _ in .zero }) { _ in 0 }
            let ms = log.ms.dropFirst(10).sorted()
            print(String(format: "[efb-timing] %@ %d×%d: p50 %.2f ms, p95 %.2f ms, max %.2f ms (n=%d)",
                         label, width, height, ms[ms.count / 2], ms[Int(Double(ms.count) * 0.95)], ms.last ?? 0, ms.count))
        }
    }

    // MARK: - Helpers

    /// Frame-mean luma, 0…1, Rec.601 weights on the displayed (sRGB-encoded) bytes — the spike's measure.
    nonisolated static func meanLuma(_ bgra: [UInt8]) -> Double {
        var sum = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            sum += 0.114 * Double(bgra[i]) + 0.587 * Double(bgra[i + 1]) + 0.299 * Double(bgra[i + 2])
        }
        return sum / Double(bgra.count / 4) / 255
    }

    /// Box-averaged grey thumbnail (the spike's 160×90 continuity measure).
    nonisolated static func grey(_ bgra: [UInt8], _ w: Int, _ h: Int, _ gw: Int, _ gh: Int) -> [Double] {
        var out = [Double](repeating: 0, count: gw * gh)
        let sx = w / gw, sy = h / gh
        for y in 0..<(gh * sy) {
            for x in 0..<(gw * sx) {
                let i = (y * w + x) * 4
                out[(y / sy) * gw + x / sx] += 0.114 * Double(bgra[i]) + 0.587 * Double(bgra[i + 1]) + 0.299 * Double(bgra[i + 2])
            }
        }
        return out.map { $0 / Double(sx * sy) / 255 }
    }

    nonisolated static func downsample(_ bgra: [UInt8], _ w: Int, _ h: Int, _ f: Int) -> [UInt8] {
        let ow = w / f, oh = h / f
        var out = [UInt8](repeating: 255, count: ow * oh * 4)
        for y in 0..<oh {
            for x in 0..<ow {
                for c in 0..<3 {
                    var s = 0
                    for dy in 0..<f { for dx in 0..<f { s += Int(bgra[((y * f + dy) * w + x * f + dx) * 4 + c]) } }
                    out[(y * ow + x) * 4 + c] = UInt8(s / (f * f))
                }
            }
        }
        return out
    }

    static func referenceDownbeats(_ capture: String) throws -> [Float] {
        let url = fixturesDir().appendingPathComponent("beat_this_reference/\(capture)_reference.json")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return (json?["downbeats_seconds"] as? [Double] ?? []).map(Float.init)
    }

    static func fixturesDir() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<2 { url.deleteLastPathComponent() }   // → UzumeEngineTests/
        return url.appendingPathComponent("Fixtures")
    }

    static func visualDir() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: "/tmp/uzume_visual/efb_\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func writePNG(_ bgra: [UInt8], _ width: Int, _ height: Int, _ url: URL) throws {
        let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var copy = bgra
        let image = copy.withUnsafeMutableBytes { ptr -> CGImage? in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
            return ctx.makeImage()
        }
        guard let image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }
}
