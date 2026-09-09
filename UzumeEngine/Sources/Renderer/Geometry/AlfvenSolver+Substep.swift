// AlfvenSolver+Substep — one explicit MHD step, encoded as compute dispatches.
//
// Split from AlfvenSolver.swift for the 400-line lint ceiling. The ordering here IS the
// scheme: state -> spectrum -> filtered spectrum -> four derivative-spectra chains ->
// CFL reduction -> brackets -> dealias in k-space -> integrate.

import Foundation
import Metal
import Shared

/// The three numbers every dispatch in a substep needs, bundled so the phase helpers
/// stay inside the parameter-count limit.
struct DispatchDims {
    let grid: MTLSize
    let threadgroup: MTLSize
    let edge: Int
}

extension AlfvenSolver {

    /// One full explicit step. Each substep re-evaluates the RHS from scratch, which is
    /// exactly what the staged path could not do.
    func encodeSubstep(_ params: inout AlfvenParams, into cmd: MTLCommandBuffer) {
        let edge = configuration.edge
        let (gridSize, tgSize) = grid()
        let source = state[stateIndex]
        let target = state[1 - stateIndex]

        func compute(_ body: (MTLComputeCommandEncoder) -> Void) {
            guard let enc = cmd.makeComputeCommandEncoder() else { return }
            body(enc)
            enc.endEncoding()
        }
        // ROWS is dispatched as (1, edge) and COLS as (edge, 1): one threadgroup per
        // LINE. Dispatching (edge, edge) launched edge^2 groups, so every line was
        // transformed `edge` times by groups all writing identical values — benign, which
        // is why the FFT gate passed, but 256x the work at N = 256.
        func fft(_ pso: MTLComputePipelineState, _ input: MTLTexture,
                 _ output: MTLTexture, forward: Bool, rows: Bool) {
            compute { enc in
                enc.setComputePipelineState(pso)
                enc.setTexture(input, index: 0)
                enc.setTexture(output, index: 1)
                var fwd: UInt32 = forward ? 1 : 0
                enc.setBytes(&fwd, length: MemoryLayout<UInt32>.size, index: 0)
                enc.dispatchThreadgroups(
                    rows ? MTLSize(width: 1, height: edge, depth: 1)
                         : MTLSize(width: edge, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: edge / 2, height: 1, depth: 1))
            }
        }

        // state -> spectrum -> filtered spectrum
        fft(fftRows, source, fields.scratchB, forward: true, rows: true)
        fft(fftCols, fields.scratchB, fields.scratchA, forward: true, rows: false)
        compute { enc in
            enc.setComputePipelineState(filterPSO)
            enc.setTexture(fields.scratchA, index: 0)
            enc.setTexture(fields.scratchB, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }

        // Bring the filtered spectrum back to real space: this is the state the step
        // actually advances from.
        fft(fftCols, fields.scratchB, fields.scratchC, forward: false, rows: false)
        fft(fftRows, fields.scratchC, fields.filtered, forward: false, rows: true)

        // Four derivative-spectra chains. Each yields both partials of one field from a
        // single inverse transform, because the x- and y-derivatives are separately real.
        let targets = [fields.gradPhi, fields.gradOmega, fields.gradPsi, fields.gradJ]
        for (mode, gradTarget) in targets.enumerated() {
            compute { enc in
                enc.setComputePipelineState(gradPSO)
                enc.setTexture(fields.scratchB, index: 0)
                enc.setTexture(fields.scratchA, index: 1)
                enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
                var modeValue = UInt32(mode)
                enc.setBytes(&modeValue, length: MemoryLayout<UInt32>.size, index: 1)
                enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
            }
            // Inverse straight into `target`. An earlier version ran a dealias pass here
            // "as a copy" — badly wrong: `alfven_dealias` masks on alf_wavenumber(gid),
            // i.e. it treats the TEXEL INDEX as a wavenumber, so on a real-space field it
            // zeroes ~55% of the image by position. Dealiasing belongs only on the
            // brackets, in k-space, which is where it is applied below.
            fft(fftCols, fields.scratchA, fields.scratchC, forward: false, rows: false)
            fft(fftRows, fields.scratchC, gradTarget, forward: false, rows: true)
        }

        encodeCFL(&params, into: cmd, gridSize: gridSize, tgSize: tgSize)
        encodeNonlinear(&params,
                        into: cmd,
                        states: (source, target),
                        dims: DispatchDims(grid: gridSize, threadgroup: tgSize, edge: edge))
        stateIndex = 1 - stateIndex
    }

    /// Adaptive dt from a field-wide max — the mechanism the staged DAG could not host.
    private func encodeCFL(_ params: inout AlfvenParams, into cmd: MTLCommandBuffer,
                           gridSize: MTLSize, tgSize: MTLSize) {
        func compute(_ body: (MTLComputeCommandEncoder) -> Void) {
            guard let enc = cmd.makeComputeCommandEncoder() else { return }
            body(enc)
            enc.endEncoding()
        }
        cflScratch.contents().assumingMemoryBound(to: UInt32.self).pointee = 0
        compute { enc in
            enc.setComputePipelineState(cflReducePSO)
            enc.setTexture(fields.gradPhi, index: 0)
            enc.setTexture(fields.gradPsi, index: 1)
            enc.setBuffer(cflScratch, offset: 0, index: 0)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
        compute { enc in
            enc.setComputePipelineState(cflFinishPSO)
            enc.setBuffer(cflScratch, offset: 0, index: 0)
            enc.setBuffer(dtBuffer, offset: 0, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 2)
            enc.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        }
    }

    /// Brackets -> transform -> dealias in k-space -> back, then integrate.
    private func encodeNonlinear(_ params: inout AlfvenParams,
                                 into cmd: MTLCommandBuffer,
                                 states: (source: MTLTexture, target: MTLTexture),
                                 dims: DispatchDims) {
        let (gridSize, tgSize, edge) = (dims.grid, dims.threadgroup, dims.edge)
        let (source, target) = states
        func compute(_ body: (MTLComputeCommandEncoder) -> Void) {
            guard let enc = cmd.makeComputeCommandEncoder() else { return }
            body(enc)
            enc.endEncoding()
        }
        // ROWS is dispatched as (1, edge) and COLS as (edge, 1): one threadgroup per
        // LINE. Dispatching (edge, edge) launched edge^2 groups, so every line was
        // transformed `edge` times by groups all writing identical values — benign, which
        // is why the FFT gate passed, but 256x the work at N = 256.
        func fft(_ pso: MTLComputePipelineState, _ input: MTLTexture,
                 _ output: MTLTexture, forward: Bool, rows: Bool) {
            compute { enc in
                enc.setComputePipelineState(pso)
                enc.setTexture(input, index: 0)
                enc.setTexture(output, index: 1)
                var fwd: UInt32 = forward ? 1 : 0
                enc.setBytes(&fwd, length: MemoryLayout<UInt32>.size, index: 0)
                enc.dispatchThreadgroups(
                    rows ? MTLSize(width: 1, height: edge, depth: 1)
                         : MTLSize(width: edge, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: edge / 2, height: 1, depth: 1))
            }
        }
        compute { enc in
            enc.setComputePipelineState(bracketPSO)
            enc.setTexture(fields.gradPhi, index: 0)
            enc.setTexture(fields.gradOmega, index: 1)
            enc.setTexture(fields.gradPsi, index: 2)
            enc.setTexture(fields.gradJ, index: 3)
            enc.setTexture(fields.nonlinear, index: 4)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
        fft(fftRows, fields.nonlinear, fields.scratchA, forward: true, rows: true)
        fft(fftCols, fields.scratchA, fields.scratchB, forward: true, rows: false)
        compute { enc in
            enc.setComputePipelineState(dealiasPSO)
            enc.setTexture(fields.scratchB, index: 0)
            enc.setTexture(fields.scratchA, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
        fft(fftCols, fields.scratchA, fields.scratchB, forward: false, rows: false)
        fft(fftRows, fields.scratchB, fields.nonlinear, forward: false, rows: true)

        compute { enc in
            enc.setComputePipelineState(integratePSO)
            // The FILTERED state, not the raw one. The filter was previously computed
            // and used only for the derivative chains, so it never reached the state and
            // grid-scale energy accumulated forever — visible as axis-aligned hatching
            // over the whole frame. The spike applies FILT to w and p themselves every
            // step (alfven.py:104-105).
            enc.setTexture(fields.filtered, index: 0)
            enc.setTexture(fields.nonlinear, index: 1)
            enc.setTexture(fields.gradPsi, index: 2)
            enc.setTexture(target, index: 3)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            enc.setBuffer(dtBuffer, offset: 0, index: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
    }
}
