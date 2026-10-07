// FiddleheadFern+Encode — the GPU work: the one-time field bake and the per-frame render + bloom.

import Foundation
import Metal
import Shared

extension FiddleheadFern {

    // MARK: Bake

    /// Fields for every curl state: spine distance (F), the true distance to the whole infinite tree (T, iterated
    /// from its own definition — the tightest state on itself, then each looser state from its children's, which
    /// are always tighter), and the nearest-child lookup (C). Returns false if the textures cannot be allocated.
    func encodeBake(into cmd: MTLCommandBuffer) -> Bool {
        let res = fieldResolution, states = shape.states
        guard let spineField = makeTexture(.rg16Float, res, res, slices: states),
              let treeField = makeTexture(.r16Float, res, res, slices: states),
              let childField = makeTexture(.r16Float, res, res, slices: states),
              let scratch = makeTexture(.r16Float, res, res) else { return false }
        fieldF = spineField; fieldT = treeField; fieldC = childField
        let grid = MTLSize(width: res, height: res, depth: 1), group = MTLSize(width: 16, height: 16, depth: 1)
        var bakeParams = params

        func pass(_ pso: MTLComputePipelineState, _ state: Int, _ textures: [MTLTexture], buffer: MTLBuffer?) {
            guard let enc = cmd.makeComputeCommandEncoder() else { return }
            var stateIndex = Int32(state)
            enc.setComputePipelineState(pso)
            for (index, tex) in textures.enumerated() { enc.setTexture(tex, index: index) }
            if let buffer { enc.setBuffer(buffer, offset: 0, index: 0) }
            enc.setBytes(&bakeParams, length: MemoryLayout<FernParams>.stride, index: 1)
            enc.setBytes(&stateIndex, length: 4, index: 2)
            enc.dispatchThreads(grid, threadsPerThreadgroup: group)
            enc.endEncoding()
        }
        func step(_ state: Int) {
            pass(stepPSO, state, [spineField, treeField, scratch], buffer: childBuffer)
            guard let blit = cmd.makeBlitCommandEncoder() else { return }
            blit.copy(from: scratch,
                      sourceSlice: 0,
                      sourceLevel: 0,
                      sourceOrigin: MTLOrigin(),
                      sourceSize: grid,
                      to: treeField,
                      destinationSlice: state,
                      destinationLevel: 0,
                      destinationOrigin: MTLOrigin())
            blit.endEncoding()
        }
        for state in 0..<states { pass(spinePSO, state, [spineField], buffer: spineBuffer) }
        for state in 0..<states { pass(seedPSO, state, [spineField, treeField], buffer: nil) }
        for _ in 0..<8 { step(states - 1) }                                  // tightest state converges on itself
        for state in stride(from: states - 2, through: 0, by: -1) { step(state) }
        for state in 0..<states { pass(childPSO, state, [treeField, childField], buffer: childBuffer) }
        return true
    }

    // MARK: Frame

    /// The fern into `hdr` at the internal resolution, then bright → blur H → blur V into `bloomA`.
    func encodeFrame(into cmd: MTLCommandBuffer) {
        guard let fieldF, let fieldT, let fieldC, let hdr, let bloomA, let bloomB,
              let enc = cmd.makeComputeCommandEncoder() else { return }
        let frame = dive.frame(time: clock)
        var fronts = music.fronts(at: clock)
        params.lift = frame.lift
        params.zc = frame.centre
        params.tm = SIMD4(clock, frame.phi0, 0.12, Float(fronts.count))
        params.au = SIMD4(music.bass, music.treble, 0.33, 1.4)
        if !fronts.isEmpty {
            memcpy(pulseBuffer.contents(), &fronts, MemoryLayout<SIMD2<Float>>.stride * fronts.count)
        }
        let group = MTLSize(width: 16, height: 16, depth: 1)
        enc.setComputePipelineState(renderPSO)
        enc.setTexture(fieldF, index: 0)
        enc.setTexture(fieldT, index: 1)
        enc.setTexture(fieldC, index: 2)
        enc.setTexture(hdr, index: 3)
        enc.setBuffer(childBuffer, offset: 0, index: 0)
        enc.setBytes(&params, length: MemoryLayout<FernParams>.stride, index: 1)
        enc.setBuffer(pulseBuffer, offset: 0, index: 2)
        enc.setBuffer(paletteBuffer, offset: 0, index: 3)
        // whole threadgroups: the relief normals read neighbours across SIMD lanes (see fh_render)
        let groups = MTLSize(width: (hdr.width + 15) / 16, height: (hdr.height + 15) / 16, depth: 1)
        enc.dispatchThreadgroups(groups, threadsPerThreadgroup: group)
        let quarter = MTLSize(width: bloomA.width, height: bloomA.height, depth: 1)
        enc.setComputePipelineState(brightPSO)
        enc.setTexture(hdr, index: 0)
        enc.setTexture(bloomA, index: 1)
        enc.dispatchThreads(quarter, threadsPerThreadgroup: group)
        var horizontal = SIMD2<Int32>(1, 0), vertical = SIMD2<Int32>(0, 1)
        enc.setComputePipelineState(blurPSO)
        enc.setTexture(bloomA, index: 0)
        enc.setTexture(bloomB, index: 1)
        enc.setBytes(&horizontal, length: 8, index: 0)
        enc.dispatchThreads(quarter, threadsPerThreadgroup: group)
        enc.setTexture(bloomB, index: 0)
        enc.setTexture(bloomA, index: 1)
        enc.setBytes(&vertical, length: 8, index: 0)
        enc.dispatchThreads(quarter, threadsPerThreadgroup: group)
        enc.endEncoding()
    }
}
