// BeatClarityTests — BC.1: the D-154 beat-regularity flag reaches the GPU as
// `StemFeatures.beatClarity01` (1 steady / 0 irregular / 0.5 unknown).
//
// Two contracts: the mapping, and track-scoped preservation — live per-frame stem pushes
// must never overwrite the value (the CSP.3 `cachedBassProportion` contract). The MSL
// offset parity lives in `CommonLayoutTest`.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Shared

// MARK: - BeatClarityTests

@Suite("BC.1 — beat clarity reaches the GPU")
struct BeatClarityTests {

    private static func makePipeline() throws -> RenderPipeline {
        let context = try MetalContext()
        let library = try ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        let fftBuf = try #require(context.makeSharedBuffer(length: 512 * floatStride))
        let waveBuf = try #require(context.makeSharedBuffer(length: 2048 * floatStride))
        return try RenderPipeline(context: context, shaderLibrary: library,
                                  fftBuffer: fftBuf, waveformBuffer: waveBuf)
    }

    @Test func mapping_steadyIrregularUnknown() {
        #expect(StemFeatures.beatClarity01(beatIrregular: false) == 1)
        #expect(StemFeatures.beatClarity01(beatIrregular: true) == 0)
        #expect(StemFeatures.beatClarity01(beatIrregular: nil) == 0.5)
        #expect(StemFeatures.beatClarityUnknown == 0.5)
    }

    @Test func setBeatClarity_isPreservedAcrossLiveStemPushes() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setBeatClarity(beatIrregular: false)
        for i in 1...10 {
            var live = StemFeatures(drumsEnergy: Float(i) * 0.05)
            live.beatClarity01 = 0          // a live push must not win
            pipeline.setStemFeatures(live, live: i.isMultiple(of: 2))
        }
        let snapshot = pipeline.currentStemFeatures()
        #expect(snapshot.beatClarity01 == 1, "beat clarity overwritten by a live push: \(snapshot.beatClarity01)")
        #expect(abs(snapshot.drumsEnergy - 0.5) < 1e-5, "live fields must still apply")
    }

    /// The session-boundary / uncached-track write: `nil` must land as UNKNOWN, replacing
    /// whatever the previous track installed — never leaving it in place.
    @Test func nil_replacesThePreviousTracksValueWithUnknown() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setBeatClarity(beatIrregular: true)
        #expect(pipeline.currentStemFeatures().beatClarity01 == 0)
        pipeline.setBeatClarity(beatIrregular: nil)
        #expect(pipeline.currentStemFeatures().beatClarity01 == 0.5)
    }

    @Test func stemsCSV_recordsTheValue() {
        var stems = StemFeatures.zero
        stems.beatClarity01 = 1
        let header = SessionRecorder.stemsCSVHeader.trimmingCharacters(in: .newlines)
            .split(separator: ",").map(String.init)
        let row = SessionRecorder.csvRow(stems: stems, frame: 1, wallclock: 0)
            .trimmingCharacters(in: .newlines).split(separator: ",", omittingEmptySubsequences: false)
        let col = header.firstIndex(of: "beatClarity01")
        #expect(col != nil, "stems.csv must carry beatClarity01")
        if let col { #expect(Float(row[col]) == 1) }
    }
}
