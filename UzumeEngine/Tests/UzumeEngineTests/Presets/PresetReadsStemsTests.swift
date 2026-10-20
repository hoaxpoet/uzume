// PresetReadsStemsTests — BUG-181: a scene that declares `"reads_stems": false` pauses live stem
// separation while it is on screen, so the declaration must be TRUE. A wrong `false` silently starves a
// stem-driven scene (the BUG-138 class: route manifests under-declared what scenes read).
//
// Every adopter is checked three ways: its shader (comments stripped) never touches the stem buffer;
// its route manifest names no stem primitive; and a behavioural check of its CPU state, registered in
// `stateChecks` below. An adopter with no registered check FAILS — declaring the key means writing one.

import Testing
import Metal
import Foundation
@testable import Presets
@testable import Shared

@Suite("Preset reads_stems declarations (BUG-181)")
struct PresetReadsStemsTests {

    /// Behavioural proof, per adopter, that its CPU state ignores stems.
    private static let stateChecks: [String: @Sendable () throws -> Void] = [
        "Energetic Flyby": energeticFlybyIgnoresStems
    ]

    @Test("The key defaults to true: an undeclared scene keeps live stems")
    func defaultsToTrue() throws {
        let json = #"{"name": "X"}"#
        let descriptor = try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
        #expect(descriptor.readsStems)
    }

    @Test("Every reads_stems: false scene really reads no stems")
    func adoptersReadNoStems() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, loadBuiltIn: true)
        let adopters = loader.presets.filter { !$0.descriptor.readsStems }
        #expect(!adopters.isEmpty, "no adopters loaded — the gate would pass vacuously")
        let stemFields = Set(Mirror(reflecting: StemFeatures.zero).children.compactMap(\.label))
        for preset in adopters {
            let name = preset.descriptor.name
            let routed = preset.descriptor.audioRoutes.map(\.primitive).filter(stemFields.contains)
            #expect(routed.isEmpty, "'\(name)' declares reads_stems: false but routes \(routed)")

            let source = try Self.shaderSource(preset.descriptor.shaderFileName)
            for pattern in [#"\bstems\s*\."#, #"StemFeatures"#, #"\[\[\s*buffer\s*\(\s*3\s*\)\s*\]\]"#] {
                #expect(source.range(of: pattern, options: .regularExpression) == nil,
                        "'\(name)' declares reads_stems: false but its shader matches \(pattern)")
            }

            guard let check = Self.stateChecks[name] else {
                Issue.record("'\(name)' declares reads_stems: false with no behavioural check in `stateChecks`")
                continue
            }
            try check()
        }
    }

    /// `EnergeticFlybyState.tick` takes stems and must ignore them: identical output for silence and
    /// for loud random stems, on the same music.
    private static func energeticFlybyIgnoresStems() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let quiet = try #require(EnergeticFlybyState(device: device, faithful: false))
        let loud = try #require(EnergeticFlybyState(device: device, faithful: false))
        var rng = SystemRandomNumberGenerator()
        for i in 0..<600 {
            var fv = FeatureVector(deltaTime: 1 / 60)
            fv.barPhase01 = Float(i % 120) / 120
            fv.spectralFlux = Float(i % 7) * 0.1
            fv.bassDev = Float(i % 5) * 0.2
            var stems = StemFeatures.zero
            stems.drumsEnergy = .random(in: 0...1, using: &rng)
            stems.bassEnergyDev = .random(in: 0...1, using: &rng)
            stems.vocalsEnergy = .random(in: 0...1, using: &rng)
            stems.otherEnergyDev = .random(in: 0...1, using: &rng)
            quiet.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            loud.tick(deltaTime: fv.deltaTime, features: fv, stems: stems)
            #expect(quiet.gpuState == loud.gpuState, "Energetic Flyby's state moved with the stems at frame \(i)")
        }
    }

    /// The shader as compiled, with `//` and `/* */` comments removed (a comment mentioning stems is
    /// not a read — the `.metal` grep trap).
    private static func shaderSource(_ fileName: String) throws -> String {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // → UzumeEngine/
        let raw = try String(contentsOf: url.appendingPathComponent("Sources/Presets/Shaders/\(fileName)"),
                             encoding: .utf8)
        let noBlocks = raw.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        return noBlocks.replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
    }
}
