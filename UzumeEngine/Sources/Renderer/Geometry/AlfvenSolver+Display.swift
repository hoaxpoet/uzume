// AlfvenSolver+Display — how the field is COLOURED, split from the solver for the
// 400-line lint ceiling.
//
// A coherent seam rather than an arbitrary cut: nothing here touches the physics, and
// everything here is a stand-in for a reduction film.py can do on the CPU and a fragment
// cannot (percentile auto-exposure, std(J), and the seam bloom that is still absent).
// Every constant is calibrated against a measurement, in DISPLAYED-LINEAR space — see
// `displayExposure` for the sRGB trap that invalidates raw byte comparisons.

import Foundation
import Metal
import simd
import Shared

/// Mirrors `AlfvenDisplayParams` in AlfvenSolver.metal. Layout is the GPU contract.
struct AlfvenDisplayParams {
    var exposure: Float
    var polarityScale: Float
    var hueCentre: Float
    var bloomAmount: Float
}

extension AlfvenSolver {

    /// Draw the current field. `J` is what the fragment colours (§4); omega and psi are
    /// state and supply nothing visual on their own.
    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let displayPipeline else { return }
        var params = AlfvenDisplayParams(exposure: displayExposure,
                                         polarityScale: displayPolarityScale,
                                         hueCentre: audioHueCentre(at: features.time),
                                         bloomAmount: displayBloomAmount)
        encoder.setRenderPipelineState(displayPipeline)
        encoder.setFragmentBytes(&params,
                                 length: MemoryLayout<AlfvenDisplayParams>.stride,
                                 index: 0)
        encoder.setFragmentBuffer(exposureBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(stateTexture, index: 0)
        encoder.setFragmentTexture(fields.bloomNear, index: 1)
        encoder.setFragmentTexture(fields.bloomFar, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// The seam bloom, once per frame off the settled field.
    ///
    /// Two Gaussians compose exactly — blurring by `a` then `b` is a blur by
    /// `sqrt(a^2 + b^2)` — so the sigma-7 level is the sigma-2 level blurred again by
    /// sqrt(45), rather than a second wide pass over the core. Four separable passes
    /// instead of six, and the wide one runs on already-smooth data.
    func encodeBloom(_ params: inout AlfvenParams, into cmd: MTLCommandBuffer) {
        let (gridSize, tgSize) = grid()
        let dims = DispatchDims(grid: gridSize,
                                threadgroup: tgSize,
                                edge: configuration.edge)
        let ops = Ops(solver: self, cmd: cmd, dims: dims)
        ops.encode { enc in
            enc.setComputePipelineState(self.bloomCorePSO)
            enc.setTexture(self.state[self.stateIndex], index: 0)
            enc.setTexture(self.fields.bloomCore, index: 1)
            enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 0)
            var exposure = self.displayBloomExposure
            enc.setBytes(&exposure, length: MemoryLayout<Float>.size, index: 1)
            enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        }
        ops.blur(&params,
                 from: fields.bloomCore,
                 via: fields.bloomTmp,
                 into: fields.bloomNear,
                 sigma: 2.0)
        ops.blur(&params,
                 from: fields.bloomNear,
                 via: fields.bloomTmp,
                 into: fields.bloomFar,
                 sigma: (49.0 - 4.0).squareRoot())
    }

    /// ALFVEN.3g — the mean|J| reduction and the exposure factor it yields.
    ///
    /// Mirrors `encodeCFL`: a field-wide atomic reduction, then a single thread turning it
    /// into one number the rest of the frame reads. Costs one extra dispatch pair per
    /// frame at the production grid, against the four the CFL already runs per substep.
    func encodeExposure(_ params: inout AlfvenParams, into cmd: MTLCommandBuffer) {
        exposureScratch.contents().assumingMemoryBound(to: UInt32.self).pointee = 0
        let (gridSize, tgSize) = grid()
        guard let enc = cmd.makeComputeCommandEncoder() else { return }
        enc.setComputePipelineState(exposureReducePSO)
        enc.setTexture(stateTexture, index: 0)
        enc.setBuffer(exposureScratch, offset: 0, index: 0)
        enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 1)
        enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
        enc.setComputePipelineState(exposureFinishPSO)
        enc.setBuffer(exposureScratch, offset: 0, index: 0)
        enc.setBuffer(exposureBuffer, offset: 0, index: 1)
        enc.setBytes(&params, length: MemoryLayout<AlfvenParams>.stride, index: 2)
        enc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        enc.endEncoding()
    }
}
