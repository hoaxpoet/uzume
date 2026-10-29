// HDROutputTests — VQ.2: the HDR rule, legacy pixels unchanged on the HDR drawable, the finish's
// headroom, the regional flash cap (with its negative control), and the drawable switch's memory.
//
// Readback convention: the HDR drawable holds LINEAR values in the display's own colour space, SDR
// white = 1.0 (HDROutput). A legacy pixel matches SDR when its linear value, re-encoded with the sRGB
// curve the SDR drawable's store uses, lands on the same 8-bit code.

import Foundation
import Metal
import MetalKit
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private enum HDRTestSupport {

    static func texture(_ ctx: MetalContext, _ format: MTLPixelFormat, _ width: Int, _ height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height,
                                                            mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        return try #require(ctx.device.makeTexture(descriptor: desc))
    }

    /// An `.rgba16Float` texture read back as Float RGBA.
    static func floats(_ tex: MTLTexture) -> [Float] {
        var half = [Float16](repeating: 0, count: tex.width * tex.height * 4)
        tex.getBytes(&half, bytesPerRow: tex.width * 8, from: MTLRegionMake2D(0, 0, tex.width, tex.height),
                     mipmapLevel: 0)
        return half.map(Float.init)
    }

    /// Float RGBA written into an `.rgba16Float` texture.
    static func upload(_ values: [Float], to tex: MTLTexture) {
        let half = values.map(Float16.init)
        tex.replace(region: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0, withBytes: half,
                    bytesPerRow: tex.width * 8)
    }

    static func bytes(_ tex: MTLTexture) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: tex.width * tex.height * 4)
        tex.getBytes(&px, bytesPerRow: tex.width * 4, from: MTLRegionMake2D(0, 0, tex.width, tex.height), mipmapLevel: 0)
        return px
    }

    /// Linear → nearest 8-bit sRGB code.
    static func code(_ linear: Float) -> Int {
        let v = Double(min(max(linear, 0), 1))
        let e = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return Int((e * 255).rounded())
    }

    static func run(_ ctx: MetalContext, _ body: (MTLCommandBuffer) -> Void) throws {
        let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
        body(cmd)
        cmd.commit()
        cmd.waitUntilCompleted()
        #expect(cmd.status == .completed)
    }
}

// MARK: - Rule

@Suite("HDR output rule (VQ.2)")
struct HDROutputRuleTests {

    @Test("HDR follows the display's POTENTIAL headroom and the setting; headroom capped at 4×; none under Reduce Motion")
    func rule() {
        // A plain SDR display, and a built-in SDR panel dimmed (current > 1, potential 1): SDR.
        #expect(!HDROutput.isActive(settingOn: true, potentialHeadroom: 1.0))
        #expect(!HDROutput.isActive(settingOn: true, potentialHeadroom: 1.0), "a dimmed SDR panel's current headroom is not asked")
        #expect(HDROutput.isActive(settingOn: true, potentialHeadroom: 2.0))
        #expect(HDROutput.isActive(settingOn: true, potentialHeadroom: 16.0))
        #expect(!HDROutput.isActive(settingOn: false, potentialHeadroom: 16.0), "the setting turns it off")
        #expect(HDROutput.headroom(current: 1, reduceMotion: false) == 1)
        #expect(HDROutput.headroom(current: 0.5, reduceMotion: false) == 1, "never below SDR white")
        #expect(HDROutput.headroom(current: 2, reduceMotion: false) == 2)
        #expect(HDROutput.headroom(current: 16, reduceMotion: false) == HDROutput.peakCap)
        #expect(HDROutput.headroom(current: 16, reduceMotion: true) == 1, "Reduce Motion / Dim Flashing Lights")
        #expect(HDROutput.peakCap == 4, "Matt 2026-10-29: highlights up to 4× SDR white")
    }

    @Test("Sidecar `finish.hdr`: absent = off; no shipped scene opts in yet")
    func sidecarOptIn() throws {
        let decoded = try JSONDecoder().decode(FinishSpec.self, from: Data(#"{"mode":"cinematic","hdr":true}"#.utf8))
        #expect(decoded.hdr)
        #expect(!FinishSpec().hdr)
        let loader = PresetLoader(device: try #require(MTLCreateSystemDefaultDevice()), pixelFormat: .bgra8Unorm_srgb,
                                  loadBuiltIn: true)
        let adopters = loader.presets.filter { $0.descriptor.finish.hdr }.map(\.descriptor.name)
        #expect(adopters.isEmpty, "a scene opts into HDR in its own consumer increment, with Matt's look: \(adopters)")
    }
}

// MARK: - Legacy on the HDR drawable

@Suite("HDR legacy identity (VQ.2)", .serialized)
@MainActor
struct HDRLegacyIdentityTests {

    /// Every 8-bit code, in each channel, through the production present step at the same size.
    @Test("Every 8-bit code reaches the HDR drawable as the same code (same-size copy); nothing above white")
    func everyCodeRoundTrips() throws {
        let rig = try OraclePresentRig.shared()
        let ctx = rig.context
        let source = try HDRTestSupport.texture(ctx, FinishSpec.legacyFrameTargetFormat, 256, 3)
        var bgra = [UInt8](repeating: 255, count: 256 * 3 * 4)
        for i in 0..<256 {
            for row in 0..<3 {
                let p = (row * 256 + i) * 4
                bgra[p] = UInt8(i)                       // B
                bgra[p + 1] = UInt8((i * 7) % 256)       // G
                bgra[p + 2] = UInt8(255 - i)             // R
            }
        }
        source.replace(region: MTLRegionMake2D(0, 0, 256, 3), mipmapLevel: 0, withBytes: bgra, bytesPerRow: 256 * 4)
        let output = try HDRTestSupport.texture(ctx, HDROutput.drawableFormat, 256, 3)
        try HDRTestSupport.run(ctx) { _ = rig.pipeline.encodeLegacyPresent(source, into: output, commandBuffer: $0) }
        let out = HDRTestSupport.floats(output)
        var worst = 0
        for i in 0..<(256 * 3) {
            for (channel, byte) in [(0, 2), (1, 1), (2, 0)] {   // RGBA out vs BGRA in
                worst = max(worst, abs(HDRTestSupport.code(out[i * 4 + channel]) - Int(bgra[i * 4 + byte])))
            }
        }
        print("[vq2-identity] every code, same-size copy: worst |Δ| \(worst) code(s), max value \(out.max() ?? 0)")
        #expect(worst == 0)
        #expect((out.max() ?? 0) <= 1.0)
    }

    /// The tier-1 stretch (2560×1440 → 3840×2160) of noise, SDR drawable vs HDR drawable.
    @Test("The tier-1 stretch on the HDR drawable matches the SDR drawable within 1 code")
    func stretchMatchesSDR() throws {
        let rig = try OraclePresentRig.shared()
        let ctx = rig.context
        let (w, h, ow, oh) = (2560, 1440, 3840, 2160)
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        var seed: UInt32 = 0x9E37_79B9
        for i in bytes.indices where i % 4 != 3 {
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            bytes[i] = UInt8(truncatingIfNeeded: seed)
        }
        let sdrOut = try rig.stretch(bytes, width: w, height: h, toWidth: ow, toHeight: oh)
        let source = try HDRTestSupport.texture(ctx, FinishSpec.legacyFrameTargetFormat, w, h)
        source.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        let output = try HDRTestSupport.texture(ctx, HDROutput.drawableFormat, ow, oh)
        try HDRTestSupport.run(ctx) { _ = rig.pipeline.encodeLegacyPresent(source, into: output, commandBuffer: $0) }
        let hdr = HDRTestSupport.floats(output)
        var worst = 0, offByOne = 0
        for i in 0..<(ow * oh) {
            for (channel, byte) in [(0, 2), (1, 1), (2, 0)] {
                let d = abs(HDRTestSupport.code(hdr[i * 4 + channel]) - Int(sdrOut[i * 4 + byte]))
                worst = max(worst, d)
                if d > 0 { offByOne += 1 }
            }
        }
        let share = Double(offByOne) / Double(ow * oh * 3)
        print(String(format: "[vq2-identity] tier-1 stretch: worst |Δ| %d code(s), %.2f %% of channels off by one",
                     worst, share * 100))
        #expect(worst <= 1)
        #expect((hdr.max() ?? 0) <= 1.0)
    }
}

// MARK: - Cinematic without the opt-in

@Suite("HDR cinematic identity (VQ.2)")
struct HDRCinematicIdentityTests {

    @Test("A cinematic scene without `finish.hdr` (Ferrofluid Ocean's case) shows the same codes on the HDR drawable")
    func cinematicWithoutOptIn() throws {
        let rig = try FinishProofRig(width: 1920, height: 1080)
        let params = rig.params()
        let sdr = try rig.encoded(stage: try rig.stage(output: .bgra8Unorm_srgb, dither: true), params: params)
        let stage = try rig.stage(output: HDROutput.drawableFormat, dither: true)
        // The pipeline keeps headroom 1 for a scene that has not opted in (`updateDynamicRange`).
        stage.headroom = 1
        let out = try rig.texture(HDROutput.drawableFormat)
        try rig.run(stage: stage, params: params, output: out)
        let hdr = HDRTestSupport.floats(out)
        var worst = 0
        for i in 0..<(rig.width * rig.height) {
            for (channel, byte) in [(0, 2), (1, 1), (2, 0)] {
                worst = max(worst, abs(HDRTestSupport.code(hdr[i * 4 + channel]) - Int(sdr[i * 4 + byte])))
            }
        }
        print("[vq2-identity] cinematic proof scene, headroom 1: worst |Δ| \(worst) code(s), max \(hdr.max() ?? 0)")
        #expect(worst == 0)
        #expect((hdr.max() ?? 0) <= 1.0)
    }
}

// MARK: - Headroom

@Suite("HDR finish headroom (VQ.2)")
struct HDRHeadroomTests {

    /// A 192×108 source: left half mid-grey (0.18), right half black with a 2×2 hot spot (1000).
    static func source(_ ctx: MetalContext) throws -> MTLTexture {
        let (w, h) = (192, 108)
        var px = [Float](repeating: 0, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let p = (y * w + x) * 4
                let v: Float = x < w / 2 ? 0.18 : ((x == 150 || x == 151) && (y == 50 || y == 51) ? 1000 : 0)
                px[p] = v; px[p + 1] = v; px[p + 2] = v; px[p + 3] = 1
            }
        }
        let tex = try HDRTestSupport.texture(ctx, FinishSpec.cinematicFrameTargetFormat, w, h)
        HDRTestSupport.upload(px, to: tex)
        return tex
    }

    @Test("Mid-grey holds still; the peak follows the display up to 4× SDR white")
    func headroomTable() throws {
        let ctx = try MetalContext()
        let library = try ShaderLibrary(context: ctx).library
        var spec = FinishSpec(mode: .cinematic, hdr: true)
        spec.bloom.strength = 0
        let src = try Self.source(ctx)
        var mids: [Float] = []
        for display in [1.0, 2.0, 4.0, 16.0] as [CGFloat] {
            let stage = try FinishingStage(device: ctx.device, library: library, outputFormat: HDROutput.drawableFormat,
                                           spec: spec, budget: nil)
            stage.ditherLSB = 0
            stage.headroom = HDROutput.headroom(current: display, reduceMotion: false)
            let out = try HDRTestSupport.texture(ctx, HDROutput.drawableFormat, src.width, src.height)
            try HDRTestSupport.run(ctx) { stage.encode(source: src, output: out, commandBuffer: $0) }
            let px = HDRTestSupport.floats(out)
            let mid = px[(54 * src.width + 40) * 4 + 1]
            let peak = px[(50 * src.width + 150) * 4 + 1]
            mids.append(mid)
            print(String(format: "[vq2-headroom] display %.0f× → headroom %.0f: mid-grey %.4f, peak %.3f",
                         display, stage.headroom, mid, peak))
            #expect(abs(peak - stage.headroom) <= 0.01 * stage.headroom, "peak = min(display, 4)")
        }
        #expect((mids.max() ?? 0) - (mids.min() ?? 0) <= 0.002, "mid-grey holds still: \(mids)")
        #expect(abs((mids.first ?? 0) - FinishingStage.lottesMidOut) <= 0.002)
    }

    @Test("Banding on the HDR drawable: dark-gradient 16×16-block means within 0.25 LSB, as on SDR")
    func banding() throws {
        let rig = try FinishProofRig(width: 1920, height: 1080)
        let params = rig.params(gradientOnly: true)
        var spec = FinishSpec(mode: .cinematic, hdr: true)
        spec.bloom.strength = 0
        let ideal = try rig.stage(output: .rgba32Float, spec: spec, dither: false)
        ideal.headroom = HDROutput.peakCap
        let idealLinear = try rig.linear(stage: ideal, params: params)
        let dithered = try rig.stage(output: HDROutput.drawableFormat, spec: spec, dither: true)
        dithered.headroom = HDROutput.peakCap
        let out = try rig.texture(HDROutput.drawableFormat)
        try rig.run(stage: dithered, params: params, output: out)
        let hdr = HDRTestSupport.floats(out)
        // Compare green-channel block means in 8-bit code units (the SDR test's measure).
        let encode: (Float) -> Double = { FinishingStageTests.encode(Double($0)) * 255 }
        var worst = 0.0
        for by in stride(from: 0, to: rig.height - 15, by: 16) {
            for bx in stride(from: 0, to: rig.width - 15, by: 16) {
                var got = 0.0, want = 0.0
                for y in by..<(by + 16) {
                    for x in bx..<(bx + 16) {
                        let i = (y * rig.width + x) * 4 + 1
                        got += encode(hdr[i]); want += encode(idealLinear[i])
                    }
                }
                worst = max(worst, abs(got - want) / 256)
            }
        }
        print(String(format: "[vq2-banding] 1920×1080 dark gradient at headroom 4, HDR drawable: worst 16×16 block |Δ| %.3f LSB", worst))
        #expect(worst <= 0.25)
    }
}

// MARK: - Flash cap

@Suite("HDR flash cap (VQ.2)")
struct HDRFlashCapTests {

    enum Strobe: String, CaseIterable { case fullScreen, centreNinth, red }

    static let (width, height) = (384, 216)   // 6×6 cells of 64×36; FlashAnalyzer's thirds land on cell edges
    static let frames = 60                    // 1 s at 60 fps, toggling every 3 frames = 10 Hz

    /// A scene value whose display value is 0.95 SDR white at `headroom` (the strobe's low state:
    /// steady enough that SDR shows no flash, white or red).
    static func lowState(headroom: Float) -> Float {
        var lo: Float = 0, hi: Float = 8
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if FinishingStage.displayTransform(mid, headroom: headroom) < 0.95 { lo = mid } else { hi = mid }
        }
        return lo
    }

    static func frame(_ strobe: Strobe, high: Bool, low: Float) -> [Float] {
        var px = [Float](repeating: 0, count: width * height * 4)
        let value: Float = high ? 1000 : low
        for y in 0..<height {
            for x in 0..<width {
                let p = (y * width + x) * 4
                px[p + 3] = 1
                switch strobe {
                case .fullScreen: px[p] = value; px[p + 1] = value; px[p + 2] = value
                case .red: px[p] = value
                case .centreNinth:
                    if x >= width / 3, x < 2 * width / 3, y >= height / 3, y < 2 * height / 3 {
                        px[p] = value; px[p + 1] = value; px[p + 2] = value
                    }
                }
            }
        }
        return px
    }

    struct Arm {
        let maxRegionChannelMean: Double   // SDR-white units
        let sdrAnchored: [FlashReport]     // whole-frame, regional, red
        let peakAnchored: [FlashReport]
    }

    static func measure(_ strobe: Strobe, headroom: Float, capped: Bool) throws -> Arm {
        let ctx = try MetalContext()
        let library = try ShaderLibrary(context: ctx).library
        var spec = FinishSpec(mode: .cinematic, hdr: true)
        spec.bloom.strength = 0
        let stage = try FinishingStage(device: ctx.device, library: library, outputFormat: HDROutput.drawableFormat,
                                       spec: spec, budget: nil)
        stage.headroom = headroom
        stage.regionCapEnabled = capped
        let src = try HDRTestSupport.texture(ctx, FinishSpec.cinematicFrameTargetFormat, width, height)
        let out = try HDRTestSupport.texture(ctx, HDROutput.drawableFormat, width, height)
        let low = lowState(headroom: headroom)
        var maxMean = 0.0
        var sdr: [[FlashRegionSample]] = [], peak: [[FlashRegionSample]] = []
        var sdrWhole: [Double] = [], peakWhole: [Double] = []
        for f in 0..<frames {
            HDRTestSupport.upload(frame(strobe, high: (f / 3) % 2 == 1, low: low), to: src)
            try HDRTestSupport.run(ctx) { stage.encode(source: src, output: out, commandBuffer: $0) }
            let px = HDRTestSupport.floats(out)
            let regions = FlashAnalyzer.regions(linearRGBA: px, width: width, height: height)
            maxMean = max(maxMean, regions.map { max($0.red, $0.green, $0.blue) }.max() ?? 0)
            sdr.append(regions)
            peak.append(FlashAnalyzer.regions(linearRGBA: px, width: width, height: height, anchor: Double(headroom)))
            let whole = FlashAnalyzer.regions(linearRGBA: px, width: width, height: height)
                .prefix(9).map(\.luminance).reduce(0, +) / 9
            sdrWhole.append(whole)
            peakWhole.append(whole / Double(headroom))
        }
        func reports(_ whole: [Double], _ regions: [[FlashRegionSample]]) -> [FlashReport] {
            [FlashAnalyzer.analyze(relativeLuminance: whole, fps: 60),
             FlashAnalyzer.analyzeRegional(regions, fps: 60),
             FlashAnalyzer.analyzeRed(regions, fps: 60)]
        }
        return Arm(maxRegionChannelMean: maxMean, sdrAnchored: reports(sdrWhole, sdr),
                   peakAnchored: reports(peakWhole, peak))
    }

    @Test("10 Hz strobes to 1000× white: capped, no ninth averages above SDR white and nothing flashes; uncapped flashes",
          arguments: Strobe.allCases)
    func strobe(_ strobe: Strobe) throws {
        // The display's headroom 16 is capped to 4 by HDROutput; 16 raw shows the region cap alone holds.
        for headroom in [HDROutput.peakCap, 16] {
            let capped = try Self.measure(strobe, headroom: headroom, capped: true)
            let uncapped = try Self.measure(strobe, headroom: headroom, capped: false)
            func rates(_ r: [FlashReport]) -> String {
                r.map { String(format: "%.1f", $0.peakFlashesPerSecond) }.joined(separator: "/")
            }
            print(String(format: "[vq2-flash] %@ headroom %.0f — capped: max ninth %.3f, flashes/s whole/regional/red "
                         + "SDR-anchored %@, peak-anchored %@ | uncapped: max ninth %.3f, peak-anchored %@",
                         strobe.rawValue, headroom, capped.maxRegionChannelMean, rates(capped.sdrAnchored),
                         rates(capped.peakAnchored), uncapped.maxRegionChannelMean, rates(uncapped.peakAnchored)))
            #expect(capped.maxRegionChannelMean <= 1.02, "no ninth of the screen averages above SDR white")
            let cappedSafe = (capped.sdrAnchored + capped.peakAnchored).allSatisfy { $0.isSafe }
            #expect(cappedSafe)
            // Negative control: without the cap the same strobe is a flash measured against the display's peak.
            #expect(uncapped.maxRegionChannelMean > 1.5)
            let uncappedFlashes = uncapped.peakAnchored.contains { !$0.isSafe }
            #expect(uncappedFlashes, "the gate can see an HDR flash")
        }
    }
}

// MARK: - Memory

@Suite("HDR drawable memory (VQ.2)", .serialized)
@MainActor
struct HDRMemoryTests {

    @Test("SDR ↔ HDR ×10 at 4K: the pool follows the format, the canvas appears and goes, back to baseline")
    func toggleReturnsToBaseline() throws {
        let rig = try RenderBudgetRig()
        rig.pipeline.setFeedbackParams(FeedbackParams())
        rig.resize(vq0UHD)
        rig.idle()
        let baseline = rig.budget.totalBytes
        let pool = { rig.budget.reservedBytes["drawable pool"] ?? 0 }
        let sdrPool = pool()
        let floatDrawable = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: HDROutput.drawableFormat, width: Int(vq0UHD.width), height: Int(vq0UHD.height), mipmapped: false)
        floatDrawable.usage = [.renderTarget, .shaderRead]
        floatDrawable.storageMode = .private
        let hdrPool = RenderPipeline.drawablePoolCount * rig.budget.estimatedBytes(floatDrawable)
        for _ in 0..<10 {
            rig.pipeline.setOutputEDR(true, view: rig.view, displayColorSpace: nil)
            rig.idle()
            #expect(rig.view.colorPixelFormat == HDROutput.drawableFormat)
            #expect(pool() == hdrPool, "the pool is charged at the float format's Metal size")
            #expect(rig.pipeline.canvasTexture?.pixelFormat == FinishSpec.legacyFrameTargetFormat,
                    "a legacy scene keeps an 8-bit target on HDR")
            #expect(rig.chargedEqualsLive)
            rig.pipeline.setOutputEDR(false, view: rig.view, displayColorSpace: nil)
            rig.idle()
            #expect(rig.view.colorPixelFormat == rig.ctx.pixelFormat)
            #expect(rig.pipeline.canvasTexture == nil)
            #expect(rig.budget.totalBytes == baseline)
        }
        print("[vq2-memory] 4K drawable pool: SDR \(sdrPool >> 20) MiB, HDR \(hdrPool >> 20) MiB")
    }

    @Test("Floor: an 8 GB-Mac budget under pressure refuses the 8-bit target; the next frame falls back to SDR, no crash")
    func floorFallsBackToSDR() throws {
        let rig = try RenderBudgetRig()
        rig.resize(vq0UHD)
        let floorCeiling = RenderTargetBudget.ceiling(physicalMemory: 8 << 30,
                                                      recommendedWorkingSet: rig.ctx.device.recommendedMaxWorkingSetSize)
        rig.budget.ceiling = floorCeiling
        #expect(rig.budget.reserve("injected pressure", bytes: floorCeiling - rig.budget.totalBytes - (20 << 20), force: true))
        rig.pipeline.setOutputEDR(true, view: rig.view, displayColorSpace: nil)
        #expect(rig.pipeline.canvasTexture == nil, "the 33 MB 8-bit target does not fit in 20 MiB")
        #expect(!rig.budget.refusals.isEmpty)
        rig.pipeline.updateDynamicRange(view: rig.view)   // what the next frame does first
        #expect(!rig.pipeline.isOutputEDR, "fell back to SDR rather than draw 8-bit pipelines into a float drawable")
        #expect(rig.view.colorPixelFormat == rig.ctx.pixelFormat)
        print("[vq2-memory] floor ceiling \(floorCeiling >> 20) MiB: \(rig.budget.refusals.count) refusal(s), back on SDR")
        rig.budget.releaseReservation("injected pressure")
    }

    @Test("A cinematic finish rebuilt for the HDR drawable keeps light above white; legacy finish none")
    func finishFollowsFormat() throws {
        let rig = try RenderBudgetRig()
        rig.resize(vq0HD)
        rig.pipeline.setFinish(FinishSpec(mode: .cinematic, hdr: true))
        #expect(rig.pipeline.finishingStage?.hdrOutput == false)
        rig.pipeline.setOutputEDR(true, view: rig.view, displayColorSpace: nil)
        #expect(rig.pipeline.finishingStage?.hdrOutput == true)
        rig.pipeline.setOutputEDR(false, view: rig.view, displayColorSpace: nil)
        #expect(rig.pipeline.finishingStage?.hdrOutput == false)
    }

    @Test("Largest 4K sets with the HDR pool against the 858 MiB ceiling (arithmetic from Metal's sizes)")
    func largestSetsFit() throws {
        let ctx = try MetalContext()
        func bytes(_ format: MTLPixelFormat) -> Int {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 3840, height: 2160, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            return ctx.renderTargetBudget.estimatedBytes(d)
        }
        let poolDelta = RenderPipeline.drawablePoolCount * (bytes(HDROutput.drawableFormat) - bytes(.bgra8Unorm_srgb))
        let canvas = bytes(FinishSpec.legacyFrameTargetFormat)   // an uncapped Mac's full-size 8-bit target
        let ceiling = RenderTargetBudget.ceiling(physicalMemory: 16 << 30, recommendedWorkingSet: 12 << 30)
        let mib = { (b: Int) in Double(b) / 1_048_576 }
        for (name, set) in [("largest certified (Ferrofluid Ocean / Lumen Mosaic)", RenderTargetBudget.largestCertified4KSetBytes),
                            ("reconstructing", RenderTargetBudget.reconstructing4KSetBytes)] {
            let hdr = set + poolDelta + canvas
            print(String(format: "[vq2-memory] %@: SDR %.1f MiB → HDR %.1f MiB (pool +%.1f, 8-bit target +%.1f) of %.1f MiB",
                         name, mib(set), mib(hdr), mib(poolDelta), mib(canvas), mib(ceiling)))
            #expect(hdr <= ceiling)
        }
    }
}
