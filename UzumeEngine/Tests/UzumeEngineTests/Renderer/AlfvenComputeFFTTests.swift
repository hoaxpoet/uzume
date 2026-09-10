// AlfvenComputeFFTTests — the compute FFT, gated the same way the fragment one was.
//
// ALFVEN.4 moves Alfvén's solver off the staged fragment path onto compute, because
// ALFVEN.2 measured three limits that are architectural rather than tuning: substeps
// evaluate stale derivative spectra (psi 0.90 -> 0.049), adaptive dt needs a global
// reduction fed back into the same frame which a staged DAG cannot express, and a 2D FFT
// costs 16 render passes.
//
// This gates the piece the other two depend on. A threadgroup-memory FFT does all
// log2(N) butterfly stages for one line in ONE dispatch, so a full axis is one dispatch
// instead of eight passes — 2 dispatches per 2D transform against 16 passes.
//
// Same properties the fragment FFT is held to (FFTSandboxTests), because a wrong FFT
// fails silently and would poison everything downstream.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Shared

@Suite("Alfvén compute FFT (ALFVEN.4)")
struct AlfvenComputeFFTTests {

    private static let n = 256

    private struct Rig {
        let ctx: MetalContext
        let rows: MTLComputePipelineState
        let cols: MTLComputePipelineState
        let a: MTLTexture
        let b: MTLTexture
    }

    private func makeRig() throws -> Rig {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let fRows = lib.library.makeFunction(name: "alfven_fft_rows"),
              let fCols = lib.library.makeFunction(name: "alfven_fft_cols") else {
            throw HarnessError.setupFailed("compute FFT kernels not found in the library")
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: Self.n, height: Self.n, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .shared
        guard let a = ctx.device.makeTexture(descriptor: desc),
              let b = ctx.device.makeTexture(descriptor: desc) else {
            throw HarnessError.setupFailed("texture allocation")
        }
        return Rig(ctx: ctx,
                   rows: try ctx.device.makeComputePipelineState(function: fRows),
                   cols: try ctx.device.makeComputePipelineState(function: fCols),
                   a: a, b: b)
    }

    /// One axis = ONE dispatch: `n` threadgroups of `n/2` threads, each owning a line.
    private func encode(_ rig: Rig, _ pso: MTLComputePipelineState,
                        _ src: MTLTexture, _ dst: MTLTexture,
                        forward: Bool, on cmd: MTLCommandBuffer) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(pso)
        enc.setTexture(src, index: 0)
        enc.setTexture(dst, index: 1)
        var fwd: UInt32 = forward ? 1 : 0
        enc.setBytes(&fwd, length: MemoryLayout<UInt32>.size, index: 0)
        enc.dispatchThreadgroups(MTLSize(width: Self.n, height: Self.n, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: Self.n / 2, height: 1, depth: 1))
        enc.endEncoding()
    }

    private static func fill(_ tex: MTLTexture) -> [Float] {
        let n = Self.n
        var data = [Float](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let u = Float(x) / Float(n), v = Float(y) / Float(n)
                let tau = Float.pi * 2
                let s = sin(tau * (3 * u + v) + 0.7)
                      + 0.5 * sin(tau * (u - 5 * v) + 2.1)
                      + 0.25 * sin(tau * (11 * u + 7 * v))
                data[(y * n + x) * 4] = s
            }
        }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            tex.replace(region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                          size: MTLSize(width: n, height: n, depth: 1)),
                        mipmapLevel: 0, withBytes: base, bytesPerRow: n * 16)
        }
        return data
    }

    private static func read(_ tex: MTLTexture) -> [Float] {
        var out = [Float](repeating: 0, count: Self.n * Self.n * 4)
        out.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: Self.n * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: Self.n, height: Self.n, depth: 1)),
                         mipmapLevel: 0)
        }
        return out
    }

    @Test("compute FFT round-trips to the input, in 4 dispatches instead of 32 passes")
    func roundTripIsIdentity() throws {
        let rig = try makeRig()
        let src = Self.fill(rig.a)

        guard let cmd = rig.ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        encode(rig, rig.rows, rig.a, rig.b, forward: true,  on: cmd)   // 1
        encode(rig, rig.cols, rig.b, rig.a, forward: true,  on: cmd)   // 2
        encode(rig, rig.cols, rig.a, rig.b, forward: false, on: cmd)   // 3
        encode(rig, rig.rows, rig.b, rig.a, forward: false, on: cmd)   // 4
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw HarnessError.renderFailed }

        let out = Self.read(rig.a)
        var maxErr = 0.0, maxAbs = 0.0, maxImag = 0.0
        for i in 0..<(Self.n * Self.n) {
            let a = Double(src[i * 4]), b = Double(out[i * 4])
            maxErr = max(maxErr, abs(a - b))
            maxAbs = max(maxAbs, abs(a))
            maxImag = max(maxImag, abs(Double(out[i * 4 + 1])))
        }
        let rel = maxErr / max(maxAbs, 1e-12)
        print(String(format: "[alfven-compute-fft] round-trip max rel err %.3e | max |imag| %.3e "
                             + "| 4 dispatches vs 32 fragment passes", rel, maxImag))
        #expect(rel < 1e-4, """
            compute FFT round-trip error \\(rel) — the threadgroup butterfly, the \
            bit-reversal permutation or the barriers are wrong.
            """)
        #expect(maxImag < 1e-4, "a real input round-tripped to a complex result")
    }

    @Test("Parseval holds for the compute forward transform")
    func parsevalHolds() throws {
        let rig = try makeRig()
        let src = Self.fill(rig.a)
        guard let cmd = rig.ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        encode(rig, rig.rows, rig.a, rig.b, forward: true, on: cmd)
        encode(rig, rig.cols, rig.b, rig.a, forward: true, on: cmd)
        cmd.commit()
        cmd.waitUntilCompleted()

        let spec = Self.read(rig.a)
        var spatial = 0.0, spectral = 0.0
        for i in 0..<(Self.n * Self.n) {
            let re = Double(src[i * 4]), im = Double(src[i * 4 + 1])
            spatial += re * re + im * im
            let sre = Double(spec[i * 4]), sim = Double(spec[i * 4 + 1])
            spectral += sre * sre + sim * sim
        }
        let ratio = spectral / (spatial * Double(Self.n * Self.n))
        print(String(format: "[alfven-compute-fft] Parseval ratio %.6f (exact 1.0)", ratio))
        #expect(abs(ratio - 1.0) < 1e-3, "Parseval violated (ratio \\(ratio))")
    }
}
