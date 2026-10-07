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

    /// The previous frame's camera expressed in THIS frame's level-0 coordinates. Within a cycle the level-0 frame is
    /// the same; across the seam the old level-0 frond became the new level -1, so the old camera maps through the
    /// inverse of child k* (x ↦ o + R(a)·s·x at the end of the old cycle).
    func previousCamera(for frame: FernDive.Frame) -> SIMD4<Float>? {
        guard let last = lastCamera else { return nil }
        guard last.cycle != frame.cycle else { return last.centre }
        guard frame.cycle == last.cycle + 1 else { return nil }
        let child = dive.step(level: 0, frac: 1)
        let delta = SIMD2(last.centre.x - child.origin.x, last.centre.y - child.origin.y)
        let cosA = cos(-child.angle), sinA = sin(-child.angle)
        let centre = SIMD2(cosA * delta.x - sinA * delta.y, sinA * delta.x + cosA * delta.y) / child.scale
        return SIMD4(centre.x, centre.y, last.centre.z / child.scale, last.centre.w - child.angle)
    }

    /// Halton(2, 3) sub-pixel jitter, 8-frame cycle, centred on 0.
    static func jitter(_ index: Int) -> SIMD2<Float> {
        func halton(_ i: Int, _ base: Int) -> Float {
            var weight: Float = 1, value: Float = 0, rest = i
            while rest > 0 { weight /= Float(base); value += weight * Float(rest % base); rest /= base }
            return value
        }
        let i = index % 8 + 1
        return SIMD2(halton(i, 2) - 0.5, halton(i, 3) - 0.5)
    }

    /// The fern into `hdr` (jittered) at the internal resolution, resolved into the TAA history, then
    /// bright → blur H → blur V from the resolved picture into `bloomA`.
    func encodeFrame(into cmd: MTLCommandBuffer) {
        guard let fieldF, let fieldT, let fieldC, let hdr, let bloomA, let bloomB, history.count == 2,
              let enc = cmd.makeComputeCommandEncoder() else { return }
        let frame = dive.frame(time: clock)
        var fronts = music.fronts(at: clock)
        params.lift = frame.lift
        params.zc = frame.centre
        params.tm = SIMD4(clock, frame.phi0, 0.12, Float(fronts.count))
        params.au = SIMD4(music.bassGlow, music.treble, 0.33, hueSpread)
        let prev = historyValid ? previousCamera(for: frame) : nil
        let jit = Self.jitter(frameIndex)
        params.prev = prev ?? frame.centre
        params.taa = SIMD4(jit.x, jit.y, 0.12, prev == nil ? 0 : 1)
        lastCamera = (frame.centre, frame.cycle)
        frameIndex += 1
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
        let resolved = history[1 - historyIndex]
        enc.setComputePipelineState(resolvePSO)
        enc.setTexture(hdr, index: 0)
        enc.setTexture(history[historyIndex], index: 1)
        enc.setTexture(resolved, index: 2)
        enc.setBytes(&params, length: MemoryLayout<FernParams>.stride, index: 1)
        let full = MTLSize(width: resolved.width, height: resolved.height, depth: 1)
        enc.dispatchThreads(full, threadsPerThreadgroup: group)
        historyIndex = 1 - historyIndex
        historyValid = true
        let quarter = MTLSize(width: bloomA.width, height: bloomA.height, depth: 1)
        enc.setComputePipelineState(brightPSO)
        enc.setTexture(resolved, index: 0)
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
