// StemModel+Batch — PREP.3 batched Open-Unmix inference for the offline sweep.
//
// The LFSTEM.1 sweep separates ~one window per 2 s of audio, one blocking graph run each, and
// the model run is ~77 % of a separation. Open-Unmix's bidirectional LSTM walks 431 steps in
// sequence whatever the batch, so N windows through one run cost far less than N runs. The
// windows are independent — the LSTM state starts fresh per sequence — so batching changes
// nothing about any one window's math beyond float rounding in the batched kernels.
//
// A SEPARATE graph from the live batch-1 graph, built on first use from a second load of the
// weights. Live separation keeps its graph, its buffers and its call untouched.

import Foundation
import Metal
import MetalPerformanceShadersGraph
import Shared

// MARK: - State

/// The batched graph and its I/O buffers. One batch size at a time: a larger request rebuilds.
final class StemModelBatchState: @unchecked Sendable {
    var batch = 0
    var bundle: StemModelGraphBundle?
    var input: MTLBuffer?
    var outputs: [MTLBuffer] = []
    var results: [MPSGraphTensor: MPSGraphTensorData] = [:]
    var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
}

/// One window's four stems as L/R magnitude spectrograms (`431 × 2049` each), stem order
/// vocals, drums, bass, other.
public struct StemMagnitudes: Sendable {
    public let magL: [[Float]]
    public let magR: [[Float]]
}

// MARK: - Batched predict

extension StemModelEngine {

    /// Run the model over several MONO windows in one graph run.
    ///
    /// Mono means the network sees the same magnitude on both channels, as `StemSeparator`
    /// feeds it for mono input (CLEAN.4.2). Fewer windows than the built batch are padded with
    /// silent windows, whose outputs are discarded.
    ///
    /// - Parameters:
    ///   - monoMagnitudes: One `431 × 2049` magnitude spectrogram per window.
    ///   - batch: Graph batch size to use (≥ `monoMagnitudes.count`); a size larger than the
    ///     one built so far rebuilds the graph and buffers.
    /// - Returns: Per window, the four stems' L/R magnitudes.
    public func predictBatch(monoMagnitudes: [[Float]], batch: Int) throws -> [StemMagnitudes] {
        lock.lock()
        defer { lock.unlock() }
        let count = monoMagnitudes.count
        guard count > 0 else { return [] }
        try prepareBatch(max(batch, count))
        let state = batchState
        guard let bundle = state.bundle, let input = state.input else {
            throw StemModelError.predictionFailed("batched graph unavailable")
        }
        return try autoreleasepool {
            assembleBatch(monoMagnitudes, into: input, capacity: state.batch)
            SeparationSplit.measure("model_run") {
                bundle.graph.run(
                    with: commandQueue,
                    feeds: state.feeds,
                    targetOperations: nil,
                    resultsDictionary: state.results)
            }
            return SeparationSplit.measure("readback") {
                (0..<count).map { disassembleBatch(window: $0, outputs: state.outputs) }
            }
        }
    }

    // MARK: Build

    private func prepareBatch(_ batch: Int) throws {
        let state = batchState
        guard batch > state.batch else { return }
        let bundle = Self.buildGraph(allWeights: try loadAllStemWeights(), batch: batch)
        let bytes = batch * Self.modelFrameCount * 2 * Self.nBins * MemoryLayout<Float>.size
        guard let input = device.makeBuffer(length: bytes, options: .storageModeShared) else {
            throw StemModelError.bufferAllocationFailed(bytes)
        }
        var outputs: [MTLBuffer] = []
        for _ in 0..<Self.stemCount {
            guard let output = device.makeBuffer(length: bytes, options: .storageModeShared) else {
                throw StemModelError.bufferAllocationFailed(bytes)
            }
            outputs.append(output)
        }
        let shape: [NSNumber] = [NSNumber(value: batch * Self.modelFrameCount), 2, NSNumber(value: Self.nBins)]
        state.feeds = [bundle.inputTensor: MPSGraphTensorData(input, shape: shape, dataType: .float32)]
        state.results = Dictionary(uniqueKeysWithValues: zip(bundle.stemOutputTensors, outputs).map {
            ($0, MPSGraphTensorData($1, shape: shape, dataType: .float32))
        })
        state.bundle = bundle
        state.input = input
        state.outputs = outputs
        state.batch = batch
    }

    // MARK: Layout

    /// Window-major `[window, frame, channel, bin]`, the same magnitude on both channels; rows
    /// past `windows.count` zeroed.
    private func assembleBatch(_ windows: [[Float]], into buffer: MTLBuffer, capacity: Int) {
        let bins = Self.nBins
        let rowBytes = bins * MemoryLayout<Float>.size
        let dst = buffer.contents().assumingMemoryBound(to: Float.self)
        for (window, magnitude) in windows.enumerated() {
            magnitude.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                for frame in 0..<Self.modelFrameCount {
                    let row = dst + ((window * Self.modelFrameCount + frame) * 2 * bins)
                    memcpy(row, base + frame * bins, rowBytes)
                    memcpy(row + bins, base + frame * bins, rowBytes)
                }
            }
        }
        let used = windows.count * Self.modelFrameCount * 2 * bins
        let total = capacity * Self.modelFrameCount * 2 * bins
        if used < total { (dst + used).update(repeating: 0, count: total - used) }
    }

    private func disassembleBatch(window: Int, outputs: [MTLBuffer]) -> StemMagnitudes {
        let bins = Self.nBins
        let frames = Self.modelFrameCount
        var magL: [[Float]] = []
        var magR: [[Float]] = []
        for output in outputs {
            let src = output.contents().assumingMemoryBound(to: Float.self) + window * frames * 2 * bins
            func channel(_ offset: Int) -> [Float] {
                [Float](unsafeUninitializedCapacity: frames * bins) { buffer, initialized in
                    initialized = 0
                    guard let base = buffer.baseAddress else { return }
                    for frame in 0..<frames {
                        (base + frame * bins).initialize(from: src + frame * 2 * bins + offset, count: bins)
                    }
                    initialized = frames * bins
                }
            }
            magL.append(channel(0))
            magR.append(channel(bins))
        }
        return StemMagnitudes(magL: magL, magR: magR)
    }
}
