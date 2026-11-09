// EnergeticFlybyHDRTests — VQ.2b evidence for Energetic Flyby on HDR.
//
//   • clipCensus (EFB_CLIP=1) — task 1: the light the fragment's `saturate` removes today. A test-only
//     copy of the shader (source patched here, nothing shipped) writes Kali's colour before the clip
//     and, in a second draw, where it came from (rods / sphere cluster / tunnel glow / surfaces). The
//     three route-coverage captures, 1920×1080, 600 frames each; masks every 60 frames to EFB_CLIP_OUT.
//   • sdrOracle (EFB_ORACLE_BASE=<dir>) — task 2: frame 60 of FinishLegacyOracle's fixed drive through the
//     shipped cinematic, display-referred finish, against today's legacy captures taken before VQ.2b
//     (`<dir>/oracle1080_A`, `<dir>/oracle4k_A` from `FINISH_ORACLE=capture FINISH_ORACLE_ONLY="Energetic
//     Flyby"`, the second with `FINISH_ORACLE_SIZE=capped4k`). 1080p native, and the tier-1 case: 2560×1440
//     finished straight into a 3840×2160 drawable, as production's present step does. Max |Δ| ≤ 1 code.

import Testing
import Metal
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("EnergeticFlybyHDR (VQ.2b)")
@MainActor
struct EnergeticFlybyHDRTests {

    private static let tracks = ["so_what", "there_there", "love_rehab"]

    // MARK: - Task 2: SDR oracle

    @Test("SDR is today's picture: the display-referred finish against the pre-VQ.2b legacy oracle (EFB_ORACLE_BASE)")
    func sdrOracle() throws {
        guard let base = ProcessInfo.processInfo.environment["EFB_ORACLE_BASE"] else { return }
        for (dir, render, output) in [("oracle1080_A", (1920, 1080), (1920, 1080)),
                                      ("oracle4k_A", (2560, 1440), (3840, 2160))] {
            let oracle = try [UInt8](Data(contentsOf: URL(fileURLWithPath: base)
                .appendingPathComponent("\(dir)/Energetic_Flyby.bgra")))
            let now = try Self.finishedOracleFrame(render: render, output: output)
            #expect(now.count == oracle.count)
            var histogram = [Int](repeating: 0, count: 256)
            for i in now.indices where i % 4 != 3 { histogram[abs(Int(now[i]) - Int(oracle[i]))] += 1 }
            let worst = histogram.lastIndex { $0 > 0 } ?? 0
            let channels = Double(now.count / 4 * 3)
            let shares = (1...max(worst, 1)).map { String(format: "%d: %.4f %%", $0, Double(histogram[$0]) / channels * 100) }
            print("[efb-oracle] \(render.0)×\(render.1) → \(output.0)×\(output.1): max |Δ| \(worst) code; channels differing by "
                  + shares.joined(separator: ", "))
            #expect(worst <= 1, "\(dir): SDR moved by \(worst) codes")
        }
    }

    /// Frame 60 of FinishLegacyOracleTests' drive: the shipped pipeline into the finish's float frame target,
    /// the shipped finish (SDR, production dither setting) into an 8-bit output of `output` size.
    static func finishedOracleFrame(render: (Int, Int), output: (Int, Int)) throws -> [UInt8] {
        let ctx = try MetalContext()
        let preset = try #require(_acceptanceFixture.presets.first { $0.descriptor.name == "Energetic Flyby" })
        #expect(preset.descriptor.finish.mode == .cinematic && preset.descriptor.finish.displayReferred)
        let stage = try FinishingStage(device: ctx.device, library: try ShaderLibrary(context: ctx).library,
                                       outputFormat: .bgra8Unorm_srgb, spec: preset.descriptor.finish, budget: nil)
        let source = try #require(stage.ensureFrameTarget(width: render.0, height: render.1))
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: output.0,
                                                         height: output.1, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        let out = try #require(ctx.device.makeTexture(descriptor: d))
        let state = try #require(EnergeticFlybyState(device: ctx.device))
        for frame in 0..<FinishLegacyOracleTests.frames {
            var features = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: Float(frame) / 60, deltaTime: 1.0 / 60)
            state.tick(deltaTime: features.deltaTime, features: features, stems: .zero)
            guard frame == FinishLegacyOracleTests.frames - 1 else { continue }
            let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = source
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            let enc = try #require(cmd.makeRenderCommandEncoder(descriptor: pass))
            var temporal = DirectTemporalFrame()
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
            enc.setFragmentBuffer(state.stateBuffer, offset: 0, index: 6)
            enc.setFragmentBytes(&temporal, length: MemoryLayout<DirectTemporalFrame>.size, index: 9)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            stage.encode(source: source, output: out, commandBuffer: cmd)
            cmd.commit()
            cmd.waitUntilCompleted()
        }
        var bytes = [UInt8](repeating: 0, count: output.0 * output.1 * 4)
        out.getBytes(&bytes, bytesPerRow: output.0 * 4, from: MTLRegionMake2D(0, 0, output.0, output.1), mipmapLevel: 0)
        return bytes
    }

    // MARK: - Task 1: clip census

    @Test("What Energetic Flyby clips today (EFB_CLIP=1)")
    func clipCensus() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["EFB_CLIP"] == "1" else { return }
        let width = 1920, height = 1080, frames = Int(env["EFB_CLIP_FRAMES"] ?? "") ?? 600
        let outDir = env["EFB_CLIP_OUT"].map { URL(fileURLWithPath: $0) }
        if let outDir { try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true) }

        let ctx = try MetalContext()
        let colourPSO = try Self.diagnosticPipeline(ctx, output: "o.color = float4(col, 1.);")
        let sourcePSO = try Self.diagnosticPipeline(ctx, output: "o.color = float4(h.rod, h.glow, h.surface, h.core);")
        func target() throws -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height,
                                                             mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .shared
            return try #require(ctx.device.makeTexture(descriptor: d))
        }
        let colourTex = try target(), sourceTex = try target()
        var colour = [Float16](repeating: 0, count: width * height * 4)
        var source = [Float16](repeating: 0, count: width * height * 4)

        for track in Self.tracks {
            let dir = Self.fixtureDir(track)
            let rows = try SessionReplayHarness.loadRowsForReplay(dir.appendingPathComponent("features.csv"))
            let stems = SessionReplayHarness.loadStemsForReplay(dir.appendingPathComponent("stems.csv"))
            let first = rows.firstIndex { $0.accumulatedAudioTime > 0 } ?? 0
            let state = try #require(EnergeticFlybyState(device: ctx.device))
            var census = ClipCensus()
            for frame in 0..<min(frames, rows.count - first) {
                let i = first + frame
                var features = SessionReplayHarness.featureForReplay(from: rows[i], aspect: Float(width) / Float(height))
                state.tick(deltaTime: features.deltaTime, features: features,
                           stems: stems.isEmpty ? .zero : stems[min(i, stems.count - 1)])
                let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
                for (pso, tex) in [(colourPSO, colourTex), (sourcePSO, sourceTex)] {
                    let pass = MTLRenderPassDescriptor()
                    pass.colorAttachments[0].texture = tex
                    pass.colorAttachments[0].loadAction = .dontCare
                    pass.colorAttachments[0].storeAction = .store
                    let enc = try #require(cmd.makeRenderCommandEncoder(descriptor: pass))
                    var temporal = DirectTemporalFrame()
                    enc.setRenderPipelineState(pso)
                    enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
                    enc.setFragmentBuffer(state.stateBuffer, offset: 0, index: 6)
                    enc.setFragmentBytes(&temporal, length: MemoryLayout<DirectTemporalFrame>.size, index: 9)
                    enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                    enc.endEncoding()
                }
                cmd.commit()
                cmd.waitUntilCompleted()
                let region = MTLRegionMake2D(0, 0, width, height)
                colourTex.getBytes(&colour, bytesPerRow: width * 8, from: region, mipmapLevel: 0)
                sourceTex.getBytes(&source, bytesPerRow: width * 8, from: region, mipmapLevel: 0)
                let mask = outDir != nil && frame % 60 == 0
                let bgra = census.add(colour: colour, source: source, mask: mask)
                if let outDir, let bgra {
                    try SessionDrivenMultiPassReplay.writePNG(
                        bgra: bgra, width: width, height: height,
                        to: outDir.appendingPathComponent(String(format: "%@_%04d.png", track, frame)))
                }
            }
            print(census.report(track))
        }
    }

    /// The shipped fragment with its colour output replaced by `output` (the hit record already carries
    /// `rod`, `glow` and `core`). The edit must apply, or the census is of a shader that no longer exists.
    static func diagnosticPipeline(_ ctx: MetalContext, output: String) throws -> MTLRenderPipelineState {
        var src = try String(contentsOf: shaderURL, encoding: .utf8)
        let old = "    o.color = float4(sdr + (lin - sdr) * shine, 1.);"
        #expect(src.contains(old), "shader edit no longer applies")
        src = src.replacingOccurrences(of: old, with: "    " + output)
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1
        let library = try ctx.device.makeLibrary(source: PresetLoader.shaderPreamble + "\n\n" + src, options: options)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        desc.fragmentFunction = library.makeFunction(name: "energetic_flyby_fragment")
        desc.colorAttachments[0].pixelFormat = .rgba16Float
        return try ctx.device.makeRenderPipelineState(descriptor: desc)
    }

    static let shaderURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/Presets/Shaders/EnergeticFlyby.metal")

    static func fixtureDir(_ track: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/route_coverage/\(track)")
    }
}

// MARK: - ClipCensus

/// Per-frame share of pixels Kali's colour puts above 1 (any channel), the p99.9 brightest channel,
/// and where the clipped light comes from. Values are Kali's display-referred colour (what `saturate`
/// clips); the linear equivalent is its sRGB decode.
private struct ClipCensus {
    enum Source: Int, CaseIterable { case cluster, rods, tunnelGlow, surface }
    static let names = ["sphere cluster", "rods", "tunnel glow", "surfaces"]
    var share: [Double] = [], p999: [Double] = [], peak: [Double] = []
    var count = [Double](repeating: 0, count: 4), energy = [Double](repeating: 0, count: 4)

    /// `mask`: also return today's picture with clipped pixels marked by source
    /// (yellow cluster, magenta rods, cyan tunnel glow, green surfaces).
    mutating func add(colour: [Float16], source: [Float16], mask: Bool) -> [UInt8]? {
        let n = colour.count / 4
        var histogram = [Int](repeating: 0, count: 4_001)   // 0…16 in steps of 1/250
        var over = 0, top: Float = 0
        var bgra = mask ? [UInt8](repeating: 0, count: n * 4) : []
        colour.withUnsafeBufferPointer { c in
            source.withUnsafeBufferPointer { s in
                for i in 0..<n {
                    let r = Float(c[i * 4]), g = Float(c[i * 4 + 1]), b = Float(c[i * 4 + 2])
                    let m = max(r, g, b)
                    histogram[min(max(Int(m * 250), 0), 4_000)] += 1
                    top = max(top, m)
                    if mask {
                        bgra[i * 4] = UInt8(min(max(b, 0), 1) * 255)
                        bgra[i * 4 + 1] = UInt8(min(max(g, 0), 1) * 255)
                        bgra[i * 4 + 2] = UInt8(min(max(r, 0), 1) * 255)
                        bgra[i * 4 + 3] = 255
                    }
                    guard m > 1 else { continue }
                    over += 1
                    let rod = Float(s[i * 4]), glow = Float(s[i * 4 + 1]), core = Float(s[i * 4 + 3])
                    let src: Source = glow < 0.5 ? .surface : rod < 0.5 ? .tunnelGlow : core >= 0.5 ? .cluster : .rods
                    count[src.rawValue] += 1
                    energy[src.rawValue] += Double(max(r - 1, 0) + max(g - 1, 0) + max(b - 1, 0))
                    if mask {
                        let colours: [(UInt8, UInt8, UInt8)] = [(0, 255, 255), (255, 0, 255), (255, 255, 0), (0, 255, 0)]
                        (bgra[i * 4], bgra[i * 4 + 1], bgra[i * 4 + 2]) = colours[src.rawValue]
                    }
                }
            }
        }
        share.append(Double(over) / Double(n))
        var seen = 0, rank = Int(Double(n) * 0.999)
        for (bin, k) in histogram.enumerated() {
            seen += k
            if seen > rank { p999.append(Double(bin) / 250); rank = .max; break }
        }
        peak.append(Double(top))
        return mask ? bgra : nil
    }

    func report(_ track: String) -> String {
        func mean(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        func f(_ v: Double) -> String { String(format: "%.4f", v) }
        let total = count.reduce(0, +), totalEnergy = energy.reduce(0, +)
        let split = Source.allCases.map { s in
            "\(Self.names[s.rawValue]) \(f(count[s.rawValue] / max(total, 1)))/\(f(energy[s.rawValue] / max(totalEnergy, 1e-9)))"
        }.joined(separator: ", ")
        let framesWithClip = share.filter { $0 > 0 }.count
        return """
        [efb-clip] \(track) over \(share.count) frames (1920×1080):
          share of pixels > 1   mean \(f(mean(share)))  p95 \(f(share.sorted()[Int(Double(share.count) * 0.95)]))  max \(f(share.max() ?? 0))  frames with any \(framesWithClip)
          p99.9 brightest       mean \(f(mean(p999)))  max \(f(p999.max() ?? 0))  (Kali's colour; 1 = SDR white)
          brightest pixel       mean \(f(mean(peak)))  max \(f(peak.max() ?? 0))
          source (pixels/over-1 light)  \(split)
        """
    }
}
