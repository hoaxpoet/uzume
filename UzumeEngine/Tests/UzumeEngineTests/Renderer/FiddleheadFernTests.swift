// FiddleheadFernTests — the Fiddlehead preset's renderer (FH.16), through the same calls the app makes per frame:
// `ensureAllocated` → `update(features:stemFeatures:commandBuffer:)` → `render(encoder:)` into an sRGB target.
//
// Default-on: shape + dive invariants, and one rendered frame that must be a fern (not black, not clipped, varied).
// `FIDDLEHEAD_FILM=1` additionally renders a sequence at 1080p to `$TMPDIR/fiddlehead_film/` (PNG frames) and prints
// GPU frame-time percentiles — run it with `-c release`; it uses a SYNTHETIC beat clock (a beatPhase01 ramp), so it
// judges look, motion and cost, never music coupling (FA #27). `FIDDLEHEAD_SOAK=1` runs ten minutes of scene time at
// 1080p (FH.17 certification soak).

import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Shared
import Diagnostics

@Suite("Fiddlehead fern (FH.16)")
struct FiddleheadFernTests {

    // MARK: Pure

    @Test("the shape builds every curl state with children more rolled than their parent")
    func shapeIsSane() {
        let shape = FernShape()
        let built = shape.build()
        #expect(built.spines.count == shape.spineSamples * shape.states)
        #expect(built.children.count == shape.sites.count * 2 * shape.states)
        #expect(built.children.allSatisfy { $0.shift > 0 && $0.scale > 0 && $0.scale < 1 })
        #expect(built.boxMin.x < 0 && built.boxMax.x > 0.5)
    }

    @Test("the dive loops: one period later the camera frame is the same, one level down")
    func diveLoops() {
        let shape = FernShape()
        let dive = FernDive(shape: shape, children: shape.build().children)
        #expect(dive.children[dive.kStar].mirror < 0.5)
        for t: Float in [0.3, 2.9, 6.1] {
            let a = dive.frame(time: t), b = dive.frame(time: t + dive.period)
            #expect(simd_length(a.lift - b.lift) < 1e-4)
            #expect(simd_length(a.centre - b.centre) < 1e-4)
            #expect(abs((b.phi0 - a.phi0) - dive.arcStar) < 1e-4)            // the impulse path advances one stem
        }
    }

    @Test("an impulse fires once per bar (barPhase01 wrap), not on every beat")
    func pulsesOnBarWraps() {
        let shape = FernShape()
        let dive = FernDive(shape: shape, children: shape.build().children)
        var music = FernMusic(), f = FeatureVector()
        f.beatPhase01 = 0.95; f.barPhase01 = 0.2
        music.update(features: f, time: 0, dt: 1 / 60, dive: dive)
        f.beatPhase01 = 0.02; f.barPhase01 = 0.26                           // a beat inside the bar: no impulse
        music.update(features: f, time: 0.1, dt: 1 / 60, dive: dive)
        #expect(music.pulses.isEmpty)
        f.beatPhase01 = 0.97; f.barPhase01 = 0.98
        music.update(features: f, time: 1.0, dt: 1 / 60, dive: dive)
        f.beatPhase01 = 0.01; f.barPhase01 = 0.01                           // the downbeat
        music.update(features: f, time: 1.02, dt: 1 / 60, dive: dive)
        #expect(music.pulses.count == 1 && music.pulses[0].amp == FernMusic.impulseStrength)
    }

    @Test("bass glow attacks instantly and decays")
    func bassGlowEnvelope() {
        let shape = FernShape()
        let dive = FernDive(shape: shape, children: shape.build().children)
        var music = FernMusic(), f = FeatureVector()
        for i in 0..<120 { f.bassDev = 0.05; music.update(features: f, time: Float(i) / 60, dt: 1 / 60, dive: dive) }
        let base = music.bassGlow
        f.bassDev = 0.6
        music.update(features: f, time: 2.0, dt: 1 / 60, dive: dive)
        #expect(music.bassGlow > base + 0.3)
        let hit = music.bassGlow
        f.bassDev = 0
        for i in 1...30 { music.update(features: f, time: 2.0 + Float(i) / 60, dt: 1 / 60, dive: dive) }
        #expect(music.bassGlow < hit * 0.2)
    }

    // MARK: Palette plan

    @Test("the rotation holds all fifteen looks, consecutive looks from different families")
    func rotationOrder() {
        let looks = FernPalette.rotation
        #expect(looks.count == FernPalette.allCases.count && Set(looks).count == looks.count)
        #expect(zip(looks, looks.dropFirst()).prefix(11).allSatisfy { $0.family != $1.family })
        #expect(FernFamily.allCases.allSatisfy { !FernPalette.members(of: $0).isEmpty })
    }

    /// Drives a plan at 60 fps with a downbeat every `bar` seconds.
    private func run(_ plan: inout FernPalettePlan, from t0: Float, seconds: Float, key: Float = 0.37, bar: Float = 2) {
        var t = t0
        while t < t0 + seconds {
            let downbeat = floor(t / bar) != floor((t - 1 / 60) / bar)
            plan.update(time: t, trackKey: key, downbeat: downbeat)
            t += 1 / 60
        }
    }

    @Test("a look holds 32 bars, changes on a downbeat, and crossfades")
    func lookChange() {
        var plan = FernPalettePlan()
        run(&plan, from: 0, seconds: 1)
        let first = plan.current
        run(&plan, from: 1, seconds: 60)                                           // 30 bars
        #expect(plan.current == first)
        run(&plan, from: 61, seconds: 6)                                           // past bar 32
        #expect(plan.current != first && plan.current.family != first.family)
        #expect(plan.look(at: 200) == plan.current.look)                           // settled after the fade
        #expect((61...67).contains { plan.look(at: Float($0)) != plan.current.look })   // and it DID fade
    }

    @Test("the same track replays the same sequence; another track starts elsewhere")
    func perTrackOrder() {
        var a = FernPalettePlan(), b = FernPalettePlan(), c = FernPalettePlan()
        run(&a, from: 0, seconds: 200); run(&b, from: 0, seconds: 200); run(&c, from: 0, seconds: 200, key: 0.81)
        #expect(a.current == b.current)
        #expect(a.current != c.current)
    }

    @Test("without a beat grid the look changes every 60 s")
    func noGridRotation() {
        var plan = FernPalettePlan()
        var t: Float = 0
        while t < 61 { plan.update(time: t, trackKey: 0.2, downbeat: false); t += 1 / 60 }
        #expect(plan.current != FernPalette.rotation[Int(0.2 * Float(FernPalette.rotation.count))])
    }

    // MARK: GPU

    struct Rig {
        let ctx: MetalContext
        let fern: FiddleheadFern
        let target: MTLTexture
        let readback: MTLBuffer

        init(width: Int, height: Int) throws {
            ctx = try MetalContext()
            let lib = try ShaderLibrary(context: ctx)
            fern = try FiddleheadFern(device: ctx.device, library: lib.library, pixelFormat: .bgra8Unorm_srgb)
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            guard let t = ctx.device.makeTexture(descriptor: d),
                  let b = ctx.device.makeBuffer(length: width * height * 4, options: .storageModeShared) else {
                throw FiddleheadFernError.allocationFailed
            }
            target = t; readback = b
            fern.ensureAllocated(width: width, height: height)
        }

        /// One app frame. Returns GPU milliseconds.
        @discardableResult
        func frame(_ f: FeatureVector) -> Double {
            guard let cb = ctx.commandQueue.makeCommandBuffer() else { return 0 }
            fern.update(features: f, stemFeatures: StemFeatures(), commandBuffer: cb)
            let rp = MTLRenderPassDescriptor()
            rp.colorAttachments[0].texture = target
            rp.colorAttachments[0].loadAction = .clear
            rp.colorAttachments[0].clearColor = MTLClearColor(red: 0.01, green: 0.012, blue: 0.05, alpha: 1)
            rp.colorAttachments[0].storeAction = .store
            if let enc = cb.makeRenderCommandEncoder(descriptor: rp) {
                fern.render(encoder: enc, features: f)
                enc.endEncoding()
            }
            if let blit = cb.makeBlitCommandEncoder() {
                blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                          sourceSize: MTLSize(width: target.width, height: target.height, depth: 1),
                          to: readback, destinationOffset: 0, destinationBytesPerRow: target.width * 4,
                          destinationBytesPerImage: target.width * target.height * 4)
                blit.endEncoding()
            }
            cb.commit(); cb.waitUntilCompleted()
            return (cb.gpuEndTime - cb.gpuStartTime) * 1000
        }

        /// Frames until the bake lands (it runs on its own queue). Bounded: a bake that never completes is a failure.
        func waitForBake(_ f: FeatureVector) -> Bool {
            for _ in 0..<600 where !fern.isReady {
                frame(f)
                Thread.sleep(forTimeInterval: 0.01)
            }
            return fern.isReady
        }

        /// (mean luma 0…255, fraction of near-white pixels, luma std) of the last frame.
        func stats() -> (mean: Double, white: Double, std: Double) {
            let p = readback.contents().assumingMemoryBound(to: UInt8.self)
            let n = target.width * target.height
            var sum = 0.0, sq = 0.0, white = 0
            for i in 0..<n {
                let y = 0.0722 * Double(p[i * 4]) + 0.7152 * Double(p[i * 4 + 1]) + 0.2126 * Double(p[i * 4 + 2])   // BGRA
                sum += y; sq += y * y
                if y > 250 { white += 1 }
            }
            let mean = sum / Double(n)
            return (mean, Double(white) / Double(n), (sq / Double(n) - mean * mean).squareRoot())
        }

        func writePNG(_ url: URL) {
            guard let ctxCG = CGContext(data: readback.contents(), width: target.width, height: target.height, bitsPerComponent: 8,
                                        bytesPerRow: target.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                  let img = ctxCG.makeImage(),
                  let dst = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
        }
    }

    static func features(frame i: Int, fps: Float = 30, bpm: Float = 118) -> FeatureVector {
        var f = FeatureVector()
        let t = Float(i) / fps, beats = t * bpm / 60
        f.time = t; f.deltaTime = 1 / fps
        f.beatPhase01 = beats - floor(beats)
        f.barPhase01 = beats / 4 - floor(beats / 4)
        f.bassDev = 0.3 * exp(-(beats - floor(beats)) * 4); f.trebDev = 0.004; f.spectralSurge = 0.6
        return f
    }

    @Test("bakes, then renders a fern: lit, varied, not clipped")
    func rendersAFern() throws {
        let rig = try Rig(width: 640, height: 360)
        #expect(rig.waitForBake(Self.features(frame: 0)))
        for i in 0..<45 { rig.frame(Self.features(frame: i)) }
        let s = rig.stats()
        #expect(s.mean > 20 && s.mean < 200, "mean luma \(s.mean)")
        #expect(s.white < 0.05, "clipped fraction \(s.white)")
        #expect(s.std > 15, "luma std \(s.std) — a flat frame is not a fern")
    }

    @Test("FIDDLEHEAD_FILM=1: 1080p sequence + GPU frame-time percentiles",
          .enabled(if: ProcessInfo.processInfo.environment["FIDDLEHEAD_FILM"] == "1"))
    func film() throws {
        let env = ProcessInfo.processInfo.environment
        let w = Int(env["FIDDLEHEAD_W"] ?? "") ?? 1920, h = Int(env["FIDDLEHEAD_H"] ?? "") ?? 1080
        let frames = Int(env["FIDDLEHEAD_FRAMES"] ?? "") ?? 300
        let rig = try Rig(width: w, height: h)
        #expect(rig.waitForBake(Self.features(frame: 0)))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fiddlehead_film")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var times: [Double] = []
        for i in 0..<frames {
            times.append(rig.frame(Self.features(frame: i)))
            // PNGs only on request: encoding one takes ~150 ms of CPU, the GPU idles and clocks down, and the
            // timings measure a cold GPU (31 ms here against 19 ms back-to-back)
            if env["FIDDLEHEAD_PNG"] == "1" { rig.writePNG(dir.appendingPathComponent(String(format: "f%05d.png", i))) }
        }
        times.sort()
        print(String(format: "FIDDLEHEAD %dx%d GPU ms p50 %.1f p95 %.1f max %.1f → %@", w, h,
                     times[times.count / 2], times[times.count * 95 / 100], times[times.count - 1], dir.path))
    }

    @Test("FIDDLEHEAD_SOAK=1: ten minutes of scene time — memory flat, every minute still a lit fern, cost steady",
          .enabled(if: ProcessInfo.processInfo.environment["FIDDLEHEAD_SOAK"] == "1"))
    func soak() throws {
        let rig = try Rig(width: 1920, height: 1080)
        #expect(rig.waitForBake(Self.features(frame: 0)))
        let perMinute = 1800                                     // features(frame:) runs at 30 fps
        var baseline: MemorySnapshot?, firstP50 = 0.0, lastMean = -1.0
        for minute in 0..<10 {
            var times: [Double] = []
            // one autorelease pool per frame, as the app's draw loop drains one (else Metal's autoreleased
            // descriptors pile up in the test and read as a leak)
            for i in 0..<perMinute {
                autoreleasepool { times.append(rig.frame(Self.features(frame: minute * perMinute + i))) }
            }
            times.sort()
            let s = rig.stats(), p50 = times[times.count / 2]
            let mem = MemoryReporter.snapshot()
            if minute == 0 { baseline = mem; firstP50 = p50 }
            let growth = (Double(mem?.residentBytes ?? 0) - Double(baseline?.residentBytes ?? 0)) / (1024 * 1024)
            print(String(format: "FIDDLEHEAD SOAK min %d: luma %.1f std %.1f white %.3f | GPU p50 %.1f ms | +%.1f MB",
                         minute + 1, s.mean, s.std, s.white, p50, growth))
            #expect(s.mean > 20 && s.mean < 200 && s.white < 0.05 && s.std > 15, "minute \(minute + 1): \(s)")
            #expect(s.mean != lastMean, "minute \(minute + 1): frame identical to the last sample — frozen?")
            #expect(growth < 25, "minute \(minute + 1): resident +\(growth) MB since minute 1")
            #expect(p50 < firstP50 * 1.5, "minute \(minute + 1): GPU p50 \(p50) ms vs \(firstP50) ms in minute 1")
            lastMean = s.mean
        }
    }

    // MARK: Session replay

    /// A recorded session's REAL feature rows (`features.csv`), resampled to the film's frame rate by wallclock and
    /// aligned to `raw_tap.wav`'s start, so the film plays with the audio the session heard (FA #27: real pipeline
    /// data, not synthetic envelopes). Only the fields FiddleheadFern reads are carried.
    /// ⚠ NOT carried: `StemFeatures.energyLevel` — sessions do not record it (stems.csv has no column), so a replay
    /// runs the palette plan on its live-loudness fallback. The session.log `ENERGY_LEVELS`/`KAGURA_SONG` lines show
    /// what the live run's levels were.
    struct SessionRows {
        let wall: [Double], time: [Float], beat: [Float], bar: [Float], bass: [Float], treb: [Float], surge: [Float]
        let tapStart: Double

        init(dir: URL) throws {
            let text = try String(contentsOf: dir.appendingPathComponent("features.csv"), encoding: .utf8)
            let lines = text.split(separator: "\n")
            let head = lines[0].split(separator: ",").map(String.init)
            func col(_ name: String) -> Int { head.firstIndex(of: name) ?? -1 }
            let idx = ["wallclock_s", "time", "beatPhase01", "barPhase01_permille", "bassDev", "treb_dev", "spectral_surge"].map(col)
            var cols = [[Double]](repeating: [], count: idx.count)
            for line in lines.dropFirst() {
                let f = line.split(separator: ",", omittingEmptySubsequences: false)
                for (k, i) in idx.enumerated() { cols[k].append(i >= 0 && i < f.count ? Double(f[i]) ?? 0 : 0) }
            }
            wall = cols[0]; time = cols[1].map(Float.init); beat = cols[2].map(Float.init)
            bar = cols[3].map { Float($0 / 1000) }; bass = cols[4].map(Float.init); treb = cols[5].map(Float.init)
            surge = cols[6].map(Float.init)
            let log = try String(contentsOf: dir.appendingPathComponent("session.log"), encoding: .utf8)
            let tag = "raw tap capture started"
            let line = log.split(separator: "\n").first { $0.contains(tag) }.map(String.init) ?? ""
            tapStart = line.components(separatedBy: "wallclock=").last.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) } ?? wall[0]
        }

        func features(at t: Double, fps: Float) -> FeatureVector {
            let target = tapStart + t
            var lo = 0, hi = wall.count - 1
            while lo < hi { let mid = (lo + hi + 1) / 2; if wall[mid] <= target { lo = mid } else { hi = mid - 1 } }
            var f = FeatureVector()
            f.time = time[lo]; f.deltaTime = 1 / fps
            f.beatPhase01 = beat[lo]; f.barPhase01 = bar[lo]
            f.bassDev = bass[lo]; f.trebDev = treb[lo]; f.spectralSurge = surge[lo]
            return f
        }
    }

    @Test("FIDDLEHEAD_REPLAY=<session dir>: real-session film with its audio, at the fullscreen drawable size",
          .enabled(if: ProcessInfo.processInfo.environment["FIDDLEHEAD_REPLAY"] != nil))
    func replay() throws {
        let env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: env["FIDDLEHEAD_REPLAY"] ?? "")
        let w = Int(env["FIDDLEHEAD_W"] ?? "") ?? 3840, h = Int(env["FIDDLEHEAD_H"] ?? "") ?? 2160
        let fps: Float = 30, seconds = Double(env["FIDDLEHEAD_SECONDS"] ?? "") ?? 30
        let out = env["FIDDLEHEAD_OUT"] ?? FileManager.default.temporaryDirectory.appendingPathComponent("fiddlehead_replay.mp4").path
        let rows = try SessionRows(dir: dir)
        let rig = try Rig(width: w, height: h)
        #expect(rig.waitForBake(rows.features(at: 0, fps: fps)))
        let ff = Process()
        ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(w)x\(h)", "-r", "30", "-i", "-",
                        "-i", dir.appendingPathComponent("raw_tap.wav").path, "-c:a", "aac", "-b:a", "192k", "-shortest",
                        "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p", out]
        let pipe = Pipe(); ff.standardInput = pipe
        try ff.run()
        for i in 0..<Int(seconds * Double(fps)) {
            rig.frame(rows.features(at: Double(i) / Double(fps), fps: fps))
            pipe.fileHandleForWriting.write(Data(bytes: rig.readback.contents(), count: w * h * 4))
        }
        try pipe.fileHandleForWriting.close()
        ff.waitUntilExit()
        print("FIDDLEHEAD replay \(w)x\(h) → \(out)")
    }

    /// Palette candidates for curation: `FIDDLEHEAD_PALETTES=<file>` holds lines `name|r,g,b;r,g,b;…[|spread|lum]` (6 sRGB
    /// anchors; optional hue spread and palette luminance target). Each renders the same stretch of a replayed session (`FIDDLEHEAD_REPLAY`) to `<out dir>/<name>.mp4`
    /// — the anchors are written straight into the renderer's palette buffer, so the product code is untouched.
    @Test("FIDDLEHEAD_PALETTES=<file>: the same replayed moment in each candidate palette",
          .enabled(if: ProcessInfo.processInfo.environment["FIDDLEHEAD_PALETTES"] != nil))
    func palettes() throws {
        let env = ProcessInfo.processInfo.environment
        let lines = try String(contentsOfFile: env["FIDDLEHEAD_PALETTES"] ?? "", encoding: .utf8).split(separator: "\n")
        let rows = try SessionRows(dir: URL(fileURLWithPath: env["FIDDLEHEAD_REPLAY"] ?? ""))
        let outDir = env["FIDDLEHEAD_OUT"] ?? FileManager.default.temporaryDirectory.path
        let w = Int(env["FIDDLEHEAD_W"] ?? "") ?? 640, h = Int(env["FIDDLEHEAD_H"] ?? "") ?? 360
        let start = Double(env["FIDDLEHEAD_START"] ?? "") ?? 8, seconds = Double(env["FIDDLEHEAD_SECONDS"] ?? "") ?? 15
        let fps: Float = 30
        for line in lines where line.contains("|") {
            let parts = line.split(separator: "|")
            let anchors = parts[1].split(separator: ";").map { triple -> SIMD4<Float> in
                let v = triple.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                return SIMD4(v[0], v[1], v[2], 0)
            }
            #expect(anchors.count == 6, "\(parts[0]) needs 6 anchors")
            let rig = try Rig(width: w, height: h)
            func field(_ i: Int, _ fallback: Float) -> Float { parts.count > i ? Float(parts[i]) ?? fallback : fallback }
            rig.fern.lookOverride = FernLook(anchors: anchors, spread: field(2, 1.4), luminance: field(3, 0.08),
                                             veinWhite: field(4, 0.2), glow: field(5, 1), edge: field(6, 1))
            // warm up through the replay from 0 so the music state at `start` is the session's own
            let warm = Int(start * Double(fps))
            #expect(rig.waitForBake(rows.features(at: 0, fps: fps)))
            for i in 0..<warm { rig.frame(rows.features(at: Double(i) / Double(fps), fps: fps)) }
            let ff = Process()
            ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            ff.arguments = ["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "bgra", "-s", "\(w)x\(h)", "-r", "30",
                            "-i", "-", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", "\(outDir)/\(parts[0]).mp4"]
            let pipe = Pipe(); ff.standardInput = pipe
            try ff.run()
            for i in warm..<(warm + Int(seconds * Double(fps))) {
                rig.frame(rows.features(at: Double(i) / Double(fps), fps: fps))
                pipe.fileHandleForWriting.write(Data(bytes: rig.readback.contents(), count: w * h * 4))
            }
            try pipe.fileHandleForWriting.close()
            ff.waitUntilExit()
        }
    }
}

