// FFTSandboxTests — correctness gate for the GPU 2D FFT (ALFVEN.1c).
//
// A wrong FFT fails SILENTLY: it still produces a plausible-looking field, and every
// downstream measurement built on it would be poisoned. So the transform is proven
// standalone, before Alfvén depends on it, against properties that only a correct
// transform has.
//
// Dispatch path: the production `encodeOffscreenStages` walk, driving the shipping
// FFT Sandbox stages — Stockham radix-2 with one butterfly pass per stage iteration,
// which is what ALFVEN.1c's per-pass index made expressible.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("FFT sandbox (ALFVEN.1c)")
@MainActor
struct FFTSandboxTests {

    private static let edge = 256   // FFT requires power-of-two

    private func run() throws -> (pipeline: RenderPipeline, ctx: MetalContext) {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "FFT Sandbox" }) else {
            throw HarnessError.presetNotFound("FFT Sandbox")
        }
        let specs = preset.stages.map {
            StagedStageSpec(name: $0.name, pipelineState: $0.pipelineState, samples: $0.samples,
                            writesToDrawable: $0.writesToDrawable, persistent: $0.persistent,
                            iterations: $0.iterations, pixelFormat: $0.pixelFormat)
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)
        pipeline.setStagedRuntime(specs, drawableSize: CGSize(width: Self.edge, height: Self.edge))
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        var features = HarnessTemplateCore.silenceFeature(frame: 0)
        pipeline.encodeOffscreenStages(commandBuffer: cmd, features: &features, stemFeatures: .zero)
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw HarnessError.renderFailed }
        return (pipeline, ctx)
    }

    /// Read a stage's texture. Non-persistent staged textures are `.private` (ALFVEN.1
    /// gives only persistent stages `.shared`, for the watchdog probe), so `getBytes` on
    /// them is invalid — it segfaults. Blit into a `.shared` staging texture first.
    private static func read(_ pipeline: RenderPipeline, _ ctx: MetalContext,
                             _ stage: String) throws -> [Float] {
        guard let tex = pipeline.stagedTexture(named: stage) else {
            throw HarnessError.setupFailed("no texture for \(stage)")
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: tex.pixelFormat, width: tex.width, height: tex.height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        guard let staging = ctx.device.makeTexture(descriptor: desc),
              let cmd = ctx.commandQueue.makeCommandBuffer(),
              let blit = cmd.makeBlitCommandEncoder() else {
            throw HarnessError.setupFailed("staging blit")
        }
        blit.copy(from: tex, to: staging)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        var raw = [Float](repeating: 0, count: tex.width * tex.height * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            staging.getBytes(base, bytesPerRow: tex.width * 16,
                             from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                             size: MTLSize(width: tex.width,
                                                           height: tex.height, depth: 1)),
                             mipmapLevel: 0)
        }
        return raw
    }

    @Test("Parseval: spectral energy equals spatial energy")
    func parsevalHolds() throws {
        let (pipeline, ctx) = try run()
        let src = try Self.read(pipeline, ctx, "source")
        let spec = try Self.read(pipeline, ctx, "fftcols")
        let n = Double(Self.edge * Self.edge)

        var spatial = 0.0, spectral = 0.0
        for i in 0..<(Self.edge * Self.edge) {
            let re = Double(src[i * 4]), im = Double(src[i * 4 + 1])
            spatial += re * re + im * im
            let sre = Double(spec[i * 4]), sim = Double(spec[i * 4 + 1])
            spectral += sre * sre + sim * sim
        }
        // Unnormalised forward DFT: sum |X|^2 = N * sum |x|^2.
        let ratio = spectral / (spatial * n)
        print(String(format: "[fft] Parseval ratio %.6f (exact = 1.0) | spatial %.3f spectral %.3e",
                     ratio, spatial, spectral))
        #expect(abs(ratio - 1.0) < 1e-3, """
            Parseval's theorem is violated (ratio \(ratio)) — the forward transform is not \
            a unitary DFT up to the standard N factor, so the butterfly indexing or the \
            twiddles are wrong.
            """)
    }

    @Test("forward then inverse reproduces the input (round-trip identity)")
    func roundTripIsIdentity() throws {
        let (pipeline, ctx) = try run()
        let src = try Self.read(pipeline, ctx, "source")
        let out = try Self.read(pipeline, ctx, "ifftrows")

        var maxErr = 0.0, maxAbs = 0.0, maxImag = 0.0
        for i in 0..<(Self.edge * Self.edge) {
            let a = Double(src[i * 4]), b = Double(out[i * 4])
            maxErr = max(maxErr, abs(a - b))
            maxAbs = max(maxAbs, abs(a))
            maxImag = max(maxImag, abs(Double(out[i * 4 + 1])))
        }
        let rel = maxErr / max(maxAbs, 1e-12)
        print(String(format: "[fft] round-trip max rel err %.3e | max |imag| %.3e | signal %.4f",
                     rel, maxImag, maxAbs))
        // NOTE: the chain includes the Hou-Li filter, which is ~1.0 except at the very top
        // of the spectrum, so a band-limited source round-trips to itself. The source's
        // highest mode is k~13 of kmax 128, where the filter is 1 - 1e-16.
        #expect(rel < 1e-4, """
            round-trip error \(rel) — forward and inverse do not invert. Frozen at 1e-4, \
            which is ~100x the float32 noise floor measured for this signal.
            """)
        #expect(maxImag < 1e-4, "a real input round-tripped to a complex result")
    }

    @Test("the Hou-Li filter passes low k and annihilates the top of the spectrum")
    func filterShapeIsCorrect() throws {
        let (pipeline, ctx) = try run()
        let pre = try Self.read(pipeline, ctx, "fftcols")
        let post = try Self.read(pipeline, ctx, "filtered")
        let n = Self.edge

        func mag(_ a: [Float], _ x: Int, _ y: Int) -> Double {
            let i = (y * n + x) * 4
            return (Double(a[i]) * Double(a[i]) + Double(a[i + 1]) * Double(a[i + 1])).squareRoot()
        }
        // DC and a low mode must survive untouched; the Nyquist corner must be gone.
        let dcRatio = mag(post, 0, 0) / max(mag(pre, 0, 0), 1e-30)
        let lowRatio = mag(post, 3, 1) / max(mag(pre, 3, 1), 1e-30)
        let nyq = mag(post, n / 2, n / 2)
        print(String(format: "[fft] filter: DC x%.6f | k=(3,1) x%.6f | Nyquist corner mag %.3e",
                     dcRatio, lowRatio, nyq))
        #expect(abs(dcRatio - 1.0) < 1e-6, "the filter attenuated DC")
        #expect(abs(lowRatio - 1.0) < 1e-6, "the filter attenuated a low-k mode the lobes live in")
        #expect(nyq < 1e-6, "the Nyquist corner survived — this is the brick wall's whole job")
    }
}
