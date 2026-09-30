// StemFFT+Batch — PREP.3 batched inverse STFT.
//
// `StemSeparator` used to run one inverse STFT per stem per channel: eight MPSGraph round
// trips per separation, each recomputing sin/cos of the same phase grid on the CPU. This
// runs any number of spectrograms through ONE inverse graph over `count × 431` rows, and
// computes each distinct phase grid's sin/cos once. The per-row math is the fixed-size path's
// (`StemFFT+GPU`): same scaling, same DC/Nyquist zeroing, same overlap-add and normalisation.

import Accelerate
import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - State

/// Batched inverse graphs keyed by spectrogram count, and one set of buffers sized for the
/// largest count seen so far. A class so `StemFFTEngine`'s extension can hold it.
final class InverseBatchState: @unchecked Sendable {
    struct Graph {
        let graph: MPSGraph
        let real: MPSGraphTensor
        let imag: MPSGraphTensor
        let output: MPSGraphTensor
    }

    var graphs: [Int: Graph] = [:]
    var capacity = 0
    var realBuffer: MTLBuffer?
    var imagBuffer: MTLBuffer?
    var outputBuffer: MTLBuffer?
}

// MARK: - Batched inverse

extension StemFFTEngine {

    /// Inverse STFT of `magnitudes.count` fixed-size (431-frame) spectrograms in one graph run.
    ///
    /// - Parameters:
    ///   - magnitudes: Spectrograms, `modelFrameCount × nBins` each.
    ///   - phases: The distinct phase grids.
    ///   - phaseIndex: `phases[phaseIndex[i]]` is the phase for `magnitudes[i]`.
    ///   - originalLength: Center padding is stripped to this length.
    /// - Returns: One waveform per magnitude, in order.
    public func inverseBatch(
        magnitudes: [[Float]], phases: [[Float]], phaseIndex: [Int], originalLength: Int
    ) -> [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        if forceCPUFallback {
            return magnitudes.indices.map {
                cpuInverse(
                    magnitude: magnitudes[$0],
                    phase: phases[phaseIndex[$0]],
                    nbFrames: Self.modelFrameCount,
                    originalLength: originalLength)
            }
        }
        let count = magnitudes.count
        guard count > 0, let buffers = batchBuffers(count: count) else { return [] }
        packBatch(magnitudes: magnitudes, phases: phases, phaseIndex: phaseIndex, buffers: buffers)
        runBatchGraph(count: count, buffers: buffers)

        let pad = Self.nFFT / 2
        let rowFloats = Self.modelFrameCount * Self.nFFT
        let out = buffers.output.contents().bindMemory(to: Float.self, capacity: count * rowFloats)
        return (0..<count).map { item in
            let full = overlapAddAndNormalize(frames: out + item * rowFloats)
            let start = min(pad, full.count)
            return Array(full[start..<min(start + originalLength, full.count)])
        }
    }

    // MARK: Buffers and graphs

    private struct BatchBuffers {
        let real: MTLBuffer
        let imag: MTLBuffer
        let output: MTLBuffer
    }

    private func batchBuffers(count: Int) -> BatchBuffers? {
        let state = batchState
        if count > state.capacity {
            let bins = MemoryLayout<Float>.stride * count * Self.modelFrameCount * Self.nBins
            let frames = MemoryLayout<Float>.stride * count * Self.modelFrameCount * Self.nFFT
            state.realBuffer = device.makeBuffer(length: bins, options: .storageModeShared)
            state.imagBuffer = device.makeBuffer(length: bins, options: .storageModeShared)
            state.outputBuffer = device.makeBuffer(length: frames, options: .storageModeShared)
            state.capacity = count
        }
        guard let real = state.realBuffer, let imag = state.imagBuffer, let output = state.outputBuffer else {
            return nil
        }
        return BatchBuffers(real: real, imag: imag, output: output)
    }

    private func batchGraph(count: Int) -> InverseBatchState.Graph {
        if let graph = batchState.graphs[count] { return graph }
        let graph = MPSGraph()
        let shape: [NSNumber] = [NSNumber(value: count * Self.modelFrameCount), NSNumber(value: Self.nBins)]
        let real = graph.placeholder(shape: shape, dataType: .float32, name: "real")
        let imag = graph.placeholder(shape: shape, dataType: .float32, name: "imag")
        let complex = graph.complexTensor(realTensor: real, imaginaryTensor: imag, name: "complex")
        let desc = MPSGraphFFTDescriptor()
        desc.inverse = true
        desc.scalingMode = .size
        let output = graph.HermiteanToRealFFT(complex, axes: [NSNumber(value: 1)], descriptor: desc, name: "iFFT")
        let built = InverseBatchState.Graph(graph: graph, real: real, imag: imag, output: output)
        batchState.graphs[count] = built
        return built
    }

    // MARK: Pack / run

    /// Real/imag = magnitude × cos/sin(phase) × nFFT/2, as `packInverseInputs` does, with each
    /// distinct phase grid's sin/cos computed once.
    private func packBatch(magnitudes: [[Float]], phases: [[Float]], phaseIndex: [Int], buffers: BatchBuffers) {
        let totalBins = Self.modelFrameCount * Self.nBins
        var amp = Float(Self.nFFT) / 2
        let trig: [(cos: [Float], sin: [Float])] = phases.map { phase in
            var cosine = [Float](repeating: 0, count: totalBins)
            var sine = [Float](repeating: 0, count: totalBins)
            var elements = Int32(totalBins)
            phase.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                vvsincosf(&sine, &cosine, base, &elements)
            }
            return (cosine, sine)
        }
        let realBase = buffers.real.contents().bindMemory(to: Float.self, capacity: magnitudes.count * totalBins)
        let imagBase = buffers.imag.contents().bindMemory(to: Float.self, capacity: magnitudes.count * totalBins)
        let length = vDSP_Length(totalBins)
        let halfN = Self.nFFT / 2
        for (item, magnitude) in magnitudes.enumerated() {
            let realPtr = realBase + item * totalBins
            let imagPtr = imagBase + item * totalBins
            let (cosine, sine) = trig[phaseIndex[item]]
            magnitude.withUnsafeBufferPointer { magPtr in
                guard let mag = magPtr.baseAddress else { return }
                vDSP_vmul(mag, 1, cosine, 1, realPtr, 1, length)
                vDSP_vsmul(realPtr, 1, &amp, realPtr, 1, length)
                vDSP_vmul(mag, 1, sine, 1, imagPtr, 1, length)
                vDSP_vsmul(imagPtr, 1, &amp, imagPtr, 1, length)
            }
            for frame in 0..<Self.modelFrameCount {
                imagPtr[frame * Self.nBins] = 0
                imagPtr[frame * Self.nBins + halfN] = 0
            }
        }
    }

    private func runBatchGraph(count: Int, buffers: BatchBuffers) {
        let graph = batchGraph(count: count)
        let rows = NSNumber(value: count * Self.modelFrameCount)
        let binsShape: [NSNumber] = [rows, NSNumber(value: Self.nBins)]
        let outShape: [NSNumber] = [rows, NSNumber(value: Self.nFFT)]
        autoreleasepool {
            graph.graph.run(
                with: commandQueue,
                feeds: [
                    graph.real: MPSGraphTensorData(buffers.real, shape: binsShape, dataType: .float32),
                    graph.imag: MPSGraphTensorData(buffers.imag, shape: binsShape, dataType: .float32)
                ],
                targetOperations: nil,
                resultsDictionary: [
                    graph.output: MPSGraphTensorData(buffers.output, shape: outShape, dataType: .float32)
                ])
        }
    }
}
