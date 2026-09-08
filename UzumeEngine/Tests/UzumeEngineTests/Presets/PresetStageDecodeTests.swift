// PresetStageDecodeTests — ALFVEN.1 task 1 (D-244).
//
// The three new sidecar keys (`persistent`, `iterations`, `pixel_format`) are all
// `decodeIfPresent`, so the point of this suite is twofold:
//
//   1. Every SHIPPING sidecar keeps byte-identical behaviour — no stage anywhere
//      in the roster silently acquires persistence, extra iterations, or a
//      different pixel format because a default moved.
//   2. Each validation rule rejects its bad input: iterations outside 1…64, a
//      persistent final stage, and an over-wide `samples` list are decode errors;
//      an unknown `pixel_format` warns and falls back (the PUB.4 precedent).

import Testing
import Foundation
import Metal
@testable import Presets

@Suite("PresetStage decode (ALFVEN.1)")
struct PresetStageDecodeTests {

    private func decodeStage(_ json: String) throws -> PresetStage {
        try JSONDecoder().decode(PresetStage.self, from: Data(json.utf8))
    }

    private func decodeDescriptor(_ json: String) throws -> PresetDescriptor {
        try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
    }

    // MARK: Defaults are unchanged

    @Test("a minimal stage decodes to the pre-ALFVEN.1 behaviour")
    func minimalStageKeepsLegacyDefaults() throws {
        let stage = try decodeStage(#"{ "name": "world", "fragment_function": "world_fragment" }"#)
        #expect(stage.persistent == false)
        #expect(stage.iterations == 1)
        #expect(stage.pixelFormat == nil)
        #expect(stage.resolvedPixelFormat == .rgba16Float)
        #expect(stage.needsPingPongPair == false)
    }

    @Test("every shipping sidecar's stages still decode to the legacy defaults")
    func shippingSidecarsAreUnchanged() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
        let descriptors = loader.presets.map(\.descriptor)
        #expect(!descriptors.isEmpty, "no sidecars found — the sweep would be vacuous")

        // `Poisson Sandbox` is the ALFVEN.1 diagnostic and is the one preset that
        // is SUPPOSED to use the new keys; every other stage must be untouched.
        for descriptor in descriptors where descriptor.name != "Poisson Sandbox" {
            for stage in descriptor.stages {
                #expect(stage.persistent == false,
                        "\(descriptor.name)/\(stage.name) unexpectedly persistent")
                #expect(stage.iterations == 1,
                        "\(descriptor.name)/\(stage.name) unexpectedly iterated")
                #expect(stage.resolvedPixelFormat == .rgba16Float,
                        "\(descriptor.name)/\(stage.name) unexpectedly changed pixel format")
            }
        }
    }

    @Test("a stage round-trips through Codable with the new keys intact")
    func roundTripsWithNewKeys() throws {
        let original = PresetStage(name: "pressure", fragmentFunction: "p_fragment",
                                   samples: ["divergence"], persistent: true,
                                   iterations: 24, pixelFormat: .rgba32Float)
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(PresetStage.self, from: data)
        #expect(restored == original)
    }

    // MARK: Validation rule 1 — iterations range

    @Test("iterations outside 1…64 is a decode error", arguments: [0, -3, 65, 4096])
    func iterationsOutOfRangeRejected(_ value: Int) {
        let json = """
            { "name": "s", "fragment_function": "f", "iterations": \(value) }
            """
        #expect(throws: DecodingError.self) { try decodeStage(json) }
    }

    @Test("iterations at both ends of the range decodes", arguments: [1, 64])
    func iterationsInRangeAccepted(_ value: Int) throws {
        let stage = try decodeStage("""
            { "name": "s", "fragment_function": "f", "iterations": \(value) }
            """)
        #expect(stage.iterations == value)
    }

    // MARK: Validation rule 2 — pixel_format allowlist

    @Test("each allowlisted pixel_format maps to its Metal format")
    func pixelFormatAllowlist() throws {
        let expected: [PresetStage.StagePixelFormat: MTLPixelFormat] = [
            .rgba16Float: .rgba16Float, .rgba32Float: .rgba32Float, .rg32Float: .rg32Float
        ]
        for (raw, metal) in expected {
            let stage = try decodeStage("""
                { "name": "s", "fragment_function": "f", "pixel_format": "\(raw.rawValue)" }
                """)
            #expect(stage.resolvedPixelFormat == metal)
        }
    }

    @Test("an unknown pixel_format warns and falls back to rgba16Float")
    func unknownPixelFormatFallsBack() throws {
        let stage = try decodeStage("""
            { "name": "s", "fragment_function": "f", "pixel_format": "bgra8Unorm" }
            """)
        #expect(stage.pixelFormat == nil)
        #expect(stage.resolvedPixelFormat == .rgba16Float)
    }

    // MARK: Validation rule 3 — a persistent final stage

    @Test("a persistent final stage is a decode error")
    func persistentFinalStageRejected() {
        let json = """
            { "name": "Bad", "stages": [
                { "name": "a", "fragment_function": "fa" },
                { "name": "b", "fragment_function": "fb", "persistent": true }
            ] }
            """
        #expect(throws: DecodingError.self) { try decodeDescriptor(json) }
    }

    @Test("a persistent non-final stage decodes")
    func persistentNonFinalStageAccepted() throws {
        let descriptor = try decodeDescriptor("""
            { "name": "Good", "stages": [
                { "name": "a", "fragment_function": "fa", "persistent": true },
                { "name": "b", "fragment_function": "fb", "samples": ["a"] }
            ] }
            """)
        #expect(descriptor.stages.first?.persistent == true)
        #expect(descriptor.stages.last?.persistent == false)
    }

    // MARK: Slot-window guard

    @Test("more samples than the texture(13…19) window is a decode error")
    func tooManySamplesRejected() {
        let names = (0..<(PresetStage.maxSamples + 1)).map { "\"s\($0)\"" }.joined(separator: ", ")
        let json = """
            { "name": "s", "fragment_function": "f", "samples": [\(names)] }
            """
        #expect(throws: DecodingError.self) { try decodeStage(json) }
    }
}
