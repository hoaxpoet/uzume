// AlfvenSolver+Substep — one MHD step, encoded as compute dispatches.
//
// Split from AlfvenSolver.swift for the 400-line lint ceiling. The ordering here IS the
// scheme: integrating-factor Heun (RK2), ported from the spike's `step()`
// (docs/presets/alfven_spike/alfven.py:93-105) rather than derived.
//
//   k1 = rhs(w)
//   w1 = E(w + dt*k1)
//   k2 = rhs(w1)
//   w  = E(w + 0.5*dt*k1) + 0.5*dt*k2
//   w  = FILT(w)
//
// WHY NOT EULER. An earlier revision used forward Euler and was reverted BACK to Euler
// after an RK2 attempt measured worse — but that measurement was taken while the Poisson
// sign bug was still live (phi = +omega/k^2 instead of -omega/k^2), so advection was
// FEEDING energy and no integrator could have been stable. That evidence was void.
// Euler's amplification on the imaginary axis is |1 + iy| = sqrt(1 + y^2): growth O(y^2),
// strongest at the highest wavenumbers and localised where advection is fastest. That is
// precisely the fine diagonal hatching that appeared on the steepest J ridges. Heun gives
// sqrt(1 + y^4/4) — O(y^4) — which the integrating factor then damps. Running the spike
// (docs/presets/alfven_spike/alfven.py) at the matched sim time t = 2.2 settles it: its
// field is clean, and ours carried 1.8x the vorticity.

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

    /// One full step: two RHS evaluations composed as integrating-factor Heun.
    func encodeSubstep(_ params: inout AlfvenParams, into cmd: MTLCommandBuffer) {
        let (gridSize, tgSize) = grid()
        let dims = DispatchDims(grid: gridSize,
                                threadgroup: tgSize,
                                edge: configuration.edge)
        let source = state[stateIndex]
        let target = state[1 - stateIndex]
        let ops = Ops(solver: self, cmd: cmd, dims: dims)

        // k1 = rhs(w). The CFL reduction rides on this evaluation's gradients, so dt for
        // the whole step is fixed before any of it is used.
        encodeRHS(&params, ops: ops, source: source, withCFL: true)
        ops.copy(fields.nonlinear, to: fields.k1)

        // w1 = E(w + dt*k1)  -> predictor, staged in `filtered`
        ops.accumulate(&params,
                       base: source,
                       nl: fields.k1,
                       dst: fields.filtered,
                       coef: 1.0)
        ops.spectral(&params, efactorPSO, fields.filtered, into: fields.filtered, dt: true)

        // k2 = rhs(w1)
        encodeRHS(&params, ops: ops, source: fields.filtered, withCFL: false)

        // w = E(w + 0.5*dt*k1) + 0.5*dt*k2, then FILT, then blend/clamp/J.
        ops.accumulate(&params,
                       base: source,
                       nl: fields.k1,
                       dst: fields.rk,
                       coef: 0.5)
        ops.spectral(&params, efactorPSO, fields.rk, into: fields.rk, dt: true)
        ops.accumulate(&params,
                       base: fields.rk,
                       nl: fields.nonlinear,
                       dst: fields.filtered,
                       coef: 0.5)
        ops.spectral(&params, houliPSO, fields.filtered, into: fields.filtered, dt: false)
        ops.finalize(&params, src: fields.filtered, dst: target)

        stateIndex = 1 - stateIndex
    }

    /// The right-hand side: brackets of the spectral derivatives, dealiased in k-space.
    /// Leaves the result in `fields.nonlinear` and, as a by-product of the psi chain,
    /// the display quantity J in `fields.jField`.
    private func encodeRHS(_ params: inout AlfvenParams, ops: Ops,
                           source: MTLTexture, withCFL: Bool) {
        // state -> spectrum
        ops.fft(fftRows, source, fields.scratchB, forward: true, rows: true)
        ops.fft(fftCols, fields.scratchB, fields.scratchA, forward: true, rows: false)

        // J = lap(psi) spectrally. A local stencil here reads the raw state and is what
        // put grid-scale content into the one quantity the fragment colours.
        ops.kernel(&params, jSpectrumPSO, fields.scratchA, into: fields.scratchB)
        ops.fft(fftCols, fields.scratchB, fields.scratchC, forward: false, rows: false)
        ops.fft(fftRows, fields.scratchC, fields.jField, forward: false, rows: true)

        // Four derivative-spectra chains. Each yields both partials of one field from a
        // single inverse transform, because the x- and y-derivatives are separately real.
        let targets = [fields.gradPhi, fields.gradOmega, fields.gradPsi, fields.gradJ]
        for (mode, gradTarget) in targets.enumerated() {
            ops.gradient(&params, mode: mode, src: fields.scratchA, into: fields.scratchB)
            // Inverse straight into `gradTarget`. An earlier version ran a dealias pass
            // here "as a copy" — badly wrong: `alfven_dealias` masks on
            // alf_wavenumber(gid), i.e. it treats the TEXEL INDEX as a wavenumber, so on a
            // real-space field it zeroes ~55% of the image by position. Dealiasing belongs
            // only on the brackets, in k-space, which is where it is applied below.
            ops.fft(fftCols, fields.scratchB, fields.scratchC, forward: false, rows: false)
            ops.fft(fftRows, fields.scratchC, gradTarget, forward: false, rows: true)
        }

        if withCFL { encodeCFL(&params, ops: ops) }

        ops.brackets(&params, into: fields.nonlinear)

        // Dealias the bracket PRODUCT in k-space — the only place the 2/3 mask belongs
        // (alfven.py:79, where `DA` multiplies the bracket and nothing else).
        ops.fft(fftRows, fields.nonlinear, fields.scratchA, forward: true, rows: true)
        ops.fft(fftCols, fields.scratchA, fields.scratchB, forward: true, rows: false)
        ops.kernel(&params, dealiasPSO, fields.scratchB, into: fields.scratchA)
        ops.fft(fftCols, fields.scratchA, fields.scratchB, forward: false, rows: false)
        ops.fft(fftRows, fields.scratchB, fields.nonlinear, forward: false, rows: true)
    }

    /// Adaptive dt from a field-wide max — the mechanism the staged DAG could not host.
    private func encodeCFL(_ params: inout AlfvenParams, ops: Ops) {
        cflScratch.contents().assumingMemoryBound(to: UInt32.self).pointee = 0
        ops.encode { enc in
            enc.setComputePipelineState(self.cflReducePSO)
            enc.setTexture(self.fields.gradPhi, index: 0)
            enc.setTexture(self.fields.gradPsi, index: 1)
            enc.setBuffer(self.cflScratch, offset: 0, index: 0)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 1)
            enc.dispatchThreads(ops.dims.grid, threadsPerThreadgroup: ops.dims.threadgroup)
        }
        ops.encode { enc in
            enc.setComputePipelineState(self.cflFinishPSO)
            enc.setBuffer(self.cflScratch, offset: 0, index: 0)
            enc.setBuffer(self.dtBuffer, offset: 0, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 2)
            enc.dispatchThreads(
                MTLSize(width: 1, height: 1, depth: 1),
                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        }
    }
}
