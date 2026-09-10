// RenderPipeline+StagedEncode — the encode half of a staged frame (V.ENGINE.1;
// persistent + iterated stages at ALFVEN.1 / D-244).
//
// `encodeOffscreenStages` is THE production seam for the offscreen half of a
// staged frame: `drawWithStaged` and the multi-frame harness templates both call
// it, so "the test passes" and "the app renders" exercise the same encode. It
// walks the stages in declaration order, runs each stage's `iterations` loop over
// its ping-pong pair, and commits the swaps so the next frame reads this frame's
// output.
//
// Split from `RenderPipeline+Staged.swift` to keep both files under the 400-line
// lint ceiling; the configuration / allocation / draw half stays there.

import Metal
import Shared

extension RenderPipeline {

    /// Run one frame of every non-final stage: probe persistent state, encode each
    /// stage in declaration order, and commit the ping-pong swaps so the next frame
    /// reads this frame's output. Returns the resulting front-texture map — what
    /// the final drawable stage samples.
    ///
    /// THE production seam for the offscreen half of a staged frame.
    /// `drawWithStaged` and the multi-frame harness templates both go through it,
    /// so "the test passes" and "the app renders" exercise the same encode.
    /// `internal` for the same reason `encodeStage` is: tests drive it without an
    /// `MTKView`.
    @discardableResult
    func encodeOffscreenStages(
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        stemFeatures: StemFeatures
    ) -> [String: MTLTexture] {
        probeStagedPersistentState()

        let snapshot = stagedLock.withLock {
            StagedFrameSnapshot(stages: stagedStages,
                                textures: StagedTextureSet(front: stagedTextures,
                                                           back: stagedBackTextures))
        }
        var textures = snapshot.textures
        guard !snapshot.stages.isEmpty else { return textures.front }

        // `front` is mutated as we go, so a later stage's `samples` see the
        // freshest output of the stages before it.
        for stage in snapshot.stages where !stage.writesToDrawable {
            encodeOffscreenStage(stage: stage,
                                 commandBuffer: commandBuffer,
                                 features: &features,
                                 stemFeatures: stemFeatures,
                                 textures: &textures)
        }

        // Persist the ping-pong swaps so the next frame reads this frame's output.
        stagedLock.withLock {
            stagedTextures = textures.front
            stagedBackTextures = textures.back
        }
        return textures.front
    }

    /// Encode one non-final stage: create its render pass(es) and run its
    /// `iterations` loop, ping-ponging front/back for stages that own a pair.
    ///
    /// Called only from `encodeOffscreenStages`, which owns the snapshot and the
    /// write-back.
    private func encodeOffscreenStage(
        stage: StagedStageSpec,
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        textures: inout StagedTextureSet
    ) {
        guard let current = textures.front[stage.name] else { return }

        // `samples` inputs are read from the front map as it stands BEFORE this
        // stage runs, and held constant across every iteration below.
        let sampled = textures.front

        /// One render pass of this stage into `target`, reading `previous` at the
        /// persistent slot. Nested so it can share `features` without pushing the
        /// parameter list past what a reader can hold.
        func encodePass(into target: MTLTexture, previous: MTLTexture?, index: Int) {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = target
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor =
                MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            descriptor.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            encodeStage(stage: stage,
                        encoder: encoder,
                        features: &features,
                        stemFeatures: stemFeatures,
                        textures: sampled,
                        previousPersistent: previous,
                        pass: StagedPassInfo(index: Int32(index),
                                             count: Int32(stage.iterations)))
            encoder.endEncoding()
        }

        // Plain single-shot stage: one pass into its own texture, no pair.
        guard stage.needsPingPongPair, let spare = textures.back[stage.name] else {
            encodePass(into: current, previous: nil, index: 0)
            return
        }

        // Ping-pong stage. `read` starts at the previous frame's state (zeroed on
        // the first frame after a preset switch) and each iteration writes the
        // other half.
        var read = current
        var write = spare
        for iteration in 0..<stage.iterations {
            encodePass(into: write, previous: read, index: iteration)
            swap(&read, &write)
        }
        // `read` now holds the newest output — it becomes the front texture.
        textures.front[stage.name] = read
        textures.back[stage.name] = write
    }

    /// Encode one staged-composition stage onto the supplied render encoder.
    /// `internal` so unit tests can drive the binding logic directly without
    /// constructing an `MTKView` (see `StagedPresetBufferBindingTests`).
    ///
    /// `previousPersistent` — a ping-pong stage's previous state, bound at
    /// `kStagedPersistentTextureSlot`. `nil` for ordinary single-shot stages.
    func encodeStage(
        stage: StagedStageSpec,
        encoder: MTLRenderCommandEncoder,
        features: inout FeatureVector,
        stemFeatures: StemFeatures,
        textures: [String: MTLTexture],
        previousPersistent: MTLTexture? = nil,
        pass: StagedPassInfo = StagedPassInfo(index: 0, count: 1)
    ) {
        encoder.setRenderPipelineState(stage.pipelineState)
        encoder.setFragmentBytes(&features,
                                 length: MemoryLayout<FeatureVector>.size,
                                 index: 0)
        encoder.setFragmentBuffer(fftMagnitudeBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
        var stems = stemFeatures
        encoder.setFragmentBytes(&stems,
                                 length: MemoryLayout<StemFeatures>.size,
                                 index: 3)
        encoder.setFragmentBuffer(spectralHistory.gpuBuffer, offset: 0, index: 5)

        // MARK: Per-preset fragment buffers (slots 6 / 7 / 8)
        //
        // Reserved for the same per-preset buffers the legacy mv_warp / direct
        // paths bind via `setDirectPresetFragmentBuffer` / `…Buffer2` /
        // `…Buffer3` (e.g. `ArachneState.webBuffer` at index 6 +
        // `ArachneState.spiderBuffer` at index 7; Lumen Mosaic's
        // `LumenPatternState` at index 8). Binding here is per-frame uniform
        // across every stage of a staged preset — both WORLD and COMPOSITE
        // see the same snapshot, so sampling decisions in COMPOSITE remain
        // consistent with what WORLD rendered. New per-preset buffers must
        // extend `RenderPipeline` with `directPresetFragmentBuffer4` /
        // beyond; never overload 6 / 7 / 8 for a different purpose. (Slot 9
        // is unallocated since the §5.8 stage-rig removal.)
        if let presetBuf = directPresetFragmentBufferLock.withLock({ directPresetFragmentBuffer }) {
            encoder.setFragmentBuffer(presetBuf, offset: 0, index: 6)
        }
        if let presetBuf2 = directPresetFragmentBuffer2Lock.withLock({ directPresetFragmentBuffer2 }) {
            encoder.setFragmentBuffer(presetBuf2, offset: 0, index: 7)
        }
        if let presetBuf3 = directPresetFragmentBuffer3Lock.withLock({ directPresetFragmentBuffer3 }) {
            encoder.setFragmentBuffer(presetBuf3, offset: 0, index: 8)
        }

        // Which pass of an iterated stage this is (ALFVEN.1c). `iterations` alone runs N
        // byte-identical passes, which is right for a relaxation sweep but cannot express
        // any algorithm whose passes differ — an FFT butterfly span, a multigrid level, a
        // jump-flood step. Binding the index makes those authorable without a stage per
        // pass in the sidecar. Slot 9, unallocated since the §5.8 stage-rig removal.
        var passInfo = pass
        encoder.setFragmentBytes(&passInfo,
                                 length: MemoryLayout<StagedPassInfo>.stride,
                                 index: 9)

        bindNoiseTextures(to: encoder)

        // Bind sampled stage outputs at texture(13)+.
        for (offset, sampleName) in stage.samples.enumerated() {
            guard let tex = textures[sampleName] else { continue }
            encoder.setFragmentTexture(tex,
                                       index: kStagedSampledTextureFirstSlot + offset)
        }

        // Bind this stage's previous state at texture(20) — previous frame for a
        // persistent stage, previous iteration inside an `iterations` loop.
        if let previousPersistent {
            encoder.setFragmentTexture(previousPersistent, index: kStagedPersistentTextureSlot)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
