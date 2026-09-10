// AlfvenSolver+Ops — the dispatch vocabulary the substep is written in.
//
// Extracted so AlfvenSolver+Substep reads as the SCHEME (alfven.py:93-105) rather than as
// several hundred lines of encoder boilerplate. Nothing here makes a physics decision.

import Foundation
import Metal
import Shared

/// One command buffer's worth of solver dispatches, at a fixed grid size.
struct Ops {
    let solver: AlfvenSolver
    let cmd: MTLCommandBuffer
    let dims: DispatchDims

    func encode(_ body: (MTLComputeCommandEncoder) -> Void) {
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        body(enc)
        enc.endEncoding()
    }

    /// ROWS is dispatched as (1, edge) and COLS as (edge, 1): one threadgroup per LINE.
    /// Dispatching (edge, edge) launched edge^2 groups, so every line was transformed
    /// `edge` times by groups all writing identical values — benign, which is why the FFT
    /// gate passed, but 256x the work at N = 256.
    func fft(_ pso: MTLComputePipelineState, _ input: MTLTexture,
             _ output: MTLTexture, forward: Bool, rows: Bool) {
        encode { enc in
            enc.setComputePipelineState(pso)
            enc.setTexture(input, index: 0)
            enc.setTexture(output, index: 1)
            var fwd: UInt32 = forward ? 1 : 0
            enc.setBytes(&fwd, length: MemoryLayout<UInt32>.size, index: 0)
            enc.dispatchThreadgroups(
                rows ? MTLSize(width: 1, height: dims.edge, depth: 1)
                     : MTLSize(width: dims.edge, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: dims.edge / 2, height: 1, depth: 1))
        }
    }

    /// A one-in/one-out kernel taking only `AlfvenParams`.
    func kernel(_ params: inout AlfvenParams, _ pso: MTLComputePipelineState,
                _ src: MTLTexture, into dst: MTLTexture) {
        encode { enc in
            enc.setComputePipelineState(pso)
            enc.setTexture(src, index: 0)
            enc.setTexture(dst, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.dispatchThreads(dims.grid, threadsPerThreadgroup: dims.threadgroup)
        }
    }

    func gradient(_ params: inout AlfvenParams, mode: Int,
                  src: MTLTexture, into dst: MTLTexture) {
        encode { enc in
            enc.setComputePipelineState(solver.gradPSO)
            enc.setTexture(src, index: 0)
            enc.setTexture(dst, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            var modeValue = UInt32(mode)
            enc.setBytes(&modeValue, length: MemoryLayout<UInt32>.size, index: 1)
            enc.dispatchThreads(dims.grid, threadsPerThreadgroup: dims.threadgroup)
        }
    }

    func brackets(_ params: inout AlfvenParams, into dst: MTLTexture) {
        encode { enc in
            enc.setComputePipelineState(solver.bracketPSO)
            enc.setTexture(solver.fields.gradPhi, index: 0)
            enc.setTexture(solver.fields.gradOmega, index: 1)
            enc.setTexture(solver.fields.gradPsi, index: 2)   // grad psi = B. NOT jField.
            enc.setTexture(solver.fields.gradJ, index: 3)
            enc.setTexture(dst, index: 4)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.dispatchThreads(dims.grid, threadsPerThreadgroup: dims.threadgroup)
        }
    }

    /// dst = base + coef*dt*(nl + force). `dst` may alias `base`.
    func accumulate(_ params: inout AlfvenParams, base: MTLTexture, nl: MTLTexture,
                    dst: MTLTexture, coef: Float) {
        encode { enc in
            enc.setComputePipelineState(solver.accumulatePSO)
            enc.setTexture(base, index: 0)
            enc.setTexture(nl, index: 1)
            enc.setTexture(dst, index: 2)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.setBuffer(solver.dtBuffer, offset: 0, index: 1)
            var coefficient = coef
            enc.setBytes(&coefficient,
                         length: MemoryLayout<Float>.size,
                         index: 2)
            enc.dispatchThreads(dims.grid, threadsPerThreadgroup: dims.threadgroup)
        }
    }

    /// A spectral round trip: forward transform, apply `pso` in k-space, transform back.
    /// `dst` may alias `src` — `src` is consumed by the first dispatch only.
    func spectral(_ params: inout AlfvenParams, _ pso: MTLComputePipelineState,
                  _ src: MTLTexture, into dst: MTLTexture, dt: Bool) {
        let tex = solver.fields
        fft(solver.fftRows, src, tex.scratchB, forward: true, rows: true)
        fft(solver.fftCols, tex.scratchB, tex.scratchA, forward: true, rows: false)
        encode { enc in
            enc.setComputePipelineState(pso)
            enc.setTexture(tex.scratchA, index: 0)
            enc.setTexture(tex.scratchB, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            if dt { enc.setBuffer(solver.dtBuffer, offset: 0, index: 1) }
            enc.dispatchThreads(dims.grid, threadsPerThreadgroup: dims.threadgroup)
        }
        fft(solver.fftCols, tex.scratchB, tex.scratchC, forward: false, rows: false)
        fft(solver.fftRows, tex.scratchC, dst, forward: false, rows: true)
    }

    /// Re-seed crossfade, clamp backstop, and the J channel the fragment colours.
    ///
    /// J is taken from the CORRECTOR stage's evaluation — i.e. J(w1) rather than
    /// J(w_{n+1}). The two differ at O(dt^2), and this is the display quantity, not state.
    func finalize(_ params: inout AlfvenParams, src: MTLTexture, dst: MTLTexture) {
        encode { enc in
            enc.setComputePipelineState(solver.finalizePSO)
            enc.setTexture(src, index: 0)
            enc.setTexture(solver.fields.jField, index: 1)
            enc.setTexture(dst, index: 2)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.dispatchThreads(dims.grid, threadsPerThreadgroup: dims.threadgroup)
        }
    }

    func copy(_ src: MTLTexture, to dst: MTLTexture) {
        guard let blit = cmd.makeBlitCommandEncoder() else { return }
        blit.copy(from: src, to: dst)
        blit.endEncoding()
    }
}
