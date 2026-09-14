// MembraneRealAudioMotionHarness — PR.25 diagnostic.
//
// Copy-adapt of `FeedbackPathHarnessTemplate` (D-182, the named `feedback`
// template) with the two things a *diagnosis* needs that the template does not
// have: REAL audio, and PNGs to look at.
//
//   * Drives the production seam — `runWarpPass` → additive compose → ping-pong
//     swap — exactly as `drawSurfaceMode` does, so what lands in the PNG is what
//     the accumulator actually holds (PRESET_SESSION_CHECKLIST Part 2).
//   * Feeds it a recorded `features.csv` row per frame, from a
//     FixtureSessionCaptureGenerator capture: real audio through the production
//     analysis chain, so the pipeline noise and cross-band correlation that
//     hand-authored envelopes cannot reproduce are present (FA #27).
//   * EVERY column the CSV carries is mapped onto the FeatureVector. An unmapped
//     field reads ZERO on the GPU and a live route then looks dead in the harness
//     — the failure mode recorded in `project_harness_must_carry_every_route`.
//
// Env-gated; never part of the default run.
//
//   MEMBRANE_MOTION=1 \
//   MEMBRANE_SESSION=~/Documents/uzume_sessions/fixturegen-01_-_Speed_Of_Life \
//   swift test --package-path UzumeEngine --filter MembraneRealAudioMotion

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("MembraneRealAudioMotion", .serialized)
struct MembraneRealAudioMotionHarness {

    private static let width = 640
    private static let height = 400
    private static let subjectName = "Membrane"

    // MARK: - CSV → FeatureVector

    /// Every recorded column, mapped. Keyed by the `features.csv` header name.
    private static func features(from row: [String: Float], frame: Int) -> FeatureVector {
        var f = FeatureVector()
        func g(_ k: String, _ d: Float = 0) -> Float { row[k] ?? d }
        f.bass = g("bass");            f.mid = g("mid");              f.treble = g("treble")
        f.bassAtt = g("bass_att");     f.midAtt = g("mid_att");       f.trebleAtt = g("treble_att")
        f.subBass = g("subBass");      f.lowBass = g("lowBass");      f.lowMid = g("lowMid")
        f.midHigh = g("midHigh");      f.highMid = g("highMid");      f.high = g("high")
        f.beatBass = g("beatBass");    f.beatMid = g("beatMid")
        f.beatTreble = g("beatTreble"); f.beatComposite = g("beatComposite")
        f.spectralCentroid = g("spectralCentroid"); f.spectralFlux = g("spectralFlux")
        f.valence = g("valence");      f.arousal = g("arousal")
        f.time = g("time");            f.deltaTime = g("deltaTime", 1.0 / 60.0)
        f.waveformOccupancy = g("waveform_occupancy")
        f.aspectRatio = Float(width) / Float(height)
        f.accumulatedAudioTime = g("accumulatedAudioTime")
        f.bassRel = g("bassRel");      f.bassDev = g("bassDev")
        f.midRel = g("mid_rel");       f.midDev = g("mid_dev")
        f.trebRel = g("treb_rel");     f.trebDev = g("treb_dev")
        f.bassAttRel = g("bassAttRel"); f.midAttRel = g("mid_att_rel"); f.trebAttRel = g("treb_att_rel")
        f.beatPhase01 = g("beatPhase01"); f.beatsUntilNext = g("beats_until_next")
        f.barPhase01 = g("barPhase01_permille") / 1000.0
        f.beatsPerBar = g("beatsPerBar", 4)
        f.trackElapsedS = g("track_elapsed_s")
        f.pulsePhase01 = g("pulse_phase01"); f.pulseAmp01 = g("pulse_amp01")
        f.pulseBeatIndex = g("pulse_beat_index")
        f.pulseRegionalBlend01 = g("pulse_regional_blend01")
        f.tonalPhaseFifths = g("tonal_phase_fifths"); f.tonalPhaseThirds = g("tonal_phase_thirds")
        f.tonalConsonance = g("tonal_consonance");    f.tonalTension = g("tonal_tension")
        f.harmonicFlux = g("harmonic_flux")
        f.spectralDensity = g("spectral_density");    f.spectralDensitySlow = g("spectral_density_slow")
        f.spectralSurge = g("spectral_surge");        f.spectralSectionRatio = g("spectral_section_ratio")
        f.spectralLevelRise = g("spectral_level_rise")
        _ = frame
        return f
    }

    private static func readCSV(_ url: URL) throws -> [[String: Float]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        return lines.compactMap { line in
            let cells = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cells.count == header.count else { return nil }
            var row = [String: Float](minimumCapacity: header.count)
            for (i, key) in header.enumerated() { if let v = Float(cells[i]) { row[key] = v } }
            return row
        }
    }

    // MARK: - Harness

    @Test("Membrane on the production feedback path, driven by a recorded session")
    func membraneRealAudioMotion() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["MEMBRANE_MOTION"] == "1", let sessionPath = env["MEMBRANE_SESSION"] else {
            print("MembraneRealAudioMotion: MEMBRANE_MOTION / MEMBRANE_SESSION not set, skipping")
            return
        }
        let sessionURL = URL(fileURLWithPath: (sessionPath as NSString).expandingTildeInPath)
        let rows = try Self.readCSV(sessionURL.appendingPathComponent("features.csv"))
        guard !rows.isEmpty else { throw HarnessError.setupFailed("no rows in features.csv") }

        let stride = Int(env["MEMBRANE_STRIDE"] ?? "12") ?? 12        // PNG every Nth frame
        let limit = min(Int(env["MEMBRANE_FRAMES"] ?? "900") ?? 900, rows.count)

        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }) else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        guard let composePipeline = preset.feedbackPipelineState else {
            throw HarnessError.setupFailed("Membrane feedbackPipelineState missing")
        }
        let desc = preset.descriptor

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)
        var params = FeedbackParams(
            decay: desc.decay, baseZoom: desc.baseZoom, baseRot: desc.baseRot,
            beatZoom: desc.beatZoom, beatRot: desc.beatRot, beatSensitivity: desc.beatSensitivity)

        let texA = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)
        let texB = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)
        try HarnessTemplateCore.clear([texA, texB], ctx)
        let textures = [texA, texB]
        var idx = 0

        let tag = env["MEMBRANE_TAG"] ?? sessionURL.lastPathComponent
        let outDir = URL(fileURLWithPath: env["MEMBRANE_OUT"] ?? "/tmp/uzume_membrane")
            .appendingPathComponent(tag)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var prevPixels: [UInt8] = []
        var motion: [Double] = []
        var luma: [Double] = []          // tonal range — is there any dark on screen?

        for i in 0..<limit {
            var f = Self.features(from: rows[i], frame: i)
            // Production sets beatValue from the same max() the live switcher uses.
            params.beatValue = max(f.beatBass, f.beatComposite)
            let cur = textures[idx], prev = textures[1 - idx]
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
            pipeline.runWarpPass(commandBuffer: cmd, features: &f, params: &params,
                                 target: cur, source: prev)
            try Self.encodeCompose(cmd: cmd, composePipeline: composePipeline, target: cur,
                                   features: &f, buffers: buffers)
            cmd.commit(); cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }

            let pixels = HarnessTemplateCore.readBGRA(cur, width: Self.width, height: Self.height)
            if !prevPixels.isEmpty { motion.append(Self.meanAbsDiff(pixels, prevPixels)) }
            if i >= limit / 4 { luma.append(contentsOf: Self.lumaSample(pixels)) }
            prevPixels = pixels
            if i % stride == 0 {
                try Self.writePNG(pixels, to: outDir.appendingPathComponent(String(format: "f%04d.png", i)))
            }
            idx = 1 - idx
        }

        // Motion signal — the gate the still sheet cannot give (checklist step 7).
        let m = motion.sorted()
        let mean = motion.reduce(0, +) / Double(motion.count)
        let p50 = m[m.count / 2], p99 = m[min(m.count - 1, Int(Double(m.count) * 0.99))]
        let spikes = motion.filter { $0 > p50 * 4 }.count
        print(String(format: """
            [membrane-motion] %@  frames=%d  pngs→%@
              frame-to-frame motion: mean %.5f  p50 %.5f  p99 %.5f  max %.5f
              spikes (>4×p50): %d   frozen frames (<p50/8): %d
            """, tag, limit, outDir.path, mean, p50, p99, m.last ?? 0,
            spikes, motion.filter { $0 < p50 / 8 }.count))

        // Tonal range. A preset with no dark pixels has no negative space, so
        // nothing in it can read as bright by contrast — the reason Membrane's
        // strike was invisible before PR.25 (old ambient floor was 0.40).
        luma.sort()
        let lp = { (q: Double) -> Double in luma[min(luma.count - 1, Int(Double(luma.count) * q))] }
        print(String(format: "  luma: p01 %.3f  p10 %.3f  p50 %.3f  p90 %.3f  p99 %.3f  mean %.3f",
                     lp(0.01), lp(0.10), lp(0.50), lp(0.90), lp(0.99),
                     luma.reduce(0, +) / Double(luma.count)))

        #expect(mean > 0.0, "accumulator never changed — frozen")
    }

    /// Every 16th pixel's Rec.709 luma.
    private static func lumaSample(_ bgra: [UInt8]) -> [Double] {
        var out: [Double] = []
        var i = 0
        while i + 2 < bgra.count {
            out.append((0.0722 * Double(bgra[i]) + 0.7152 * Double(bgra[i + 1])
                        + 0.2126 * Double(bgra[i + 2])) / 255.0)
            i += 64
        }
        return out
    }

    private static func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var acc = 0.0
        var i = 0
        while i < a.count { acc += Double(abs(Int(a[i]) - Int(b[i]))); i += 4 }   // B channel stride
        return acc / Double(a.count / 4) / 255.0
    }

    private static func encodeCompose(
        cmd: MTLCommandBuffer, composePipeline: MTLRenderPipelineState, target: MTLTexture,
        features: inout FeatureVector, buffers: HarnessTemplateCore.SilenceBuffers
    ) throws {
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = target
        d.colorAttachments[0].loadAction = .load
        d.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: d) else {
            throw HarnessError.encoderCreationFailed
        }
        enc.setRenderPipelineState(composePipeline)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentBuffer(buffers.fft, offset: 0, index: 1)
        enc.setFragmentBuffer(buffers.waveform, offset: 0, index: 2)
        var stems = StemFeatures.zero
        enc.setFragmentBytes(&stems, length: MemoryLayout<StemFeatures>.size, index: 3)
        enc.setFragmentBuffer(buffers.history, offset: 0, index: 5)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private static func writePNG(_ bgra: [UInt8], to url: URL) throws {
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                | CGBitmapInfo.byteOrder32Little.rawValue)
        var data = bgra
        guard let provider = CGDataProvider(data: Data(data) as CFData),
              let img = CGImage(width: width, height: height, bitsPerComponent: 8,
                                bitsPerPixel: 32, bytesPerRow: width * 4, space: cs,
                                bitmapInfo: info, provider: provider, decode: nil,
                                shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw HarnessError.setupFailed("PNG encode failed") }
        data.removeAll()
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw HarnessError.setupFailed("PNG write failed") }
    }
}
