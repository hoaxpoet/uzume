// SidecarDescriptionDriftTests — BUG-138. The gate for the OTHER half of a sidecar.
//
// A preset sidecar describes the same shader twice. `audio_routes` is read by
// `AudioRouteSchemaTests` (every primitive must be recordable) and by `RouteCoverageTests`
// (every declared route must actually fire). `description` was read by nothing — and it is
// the half a human reads first, so it is the half that reaches a design doc, a roster
// review, or a published caption.
//
// It drifted, twice, in the way an ungated surface always does:
//
//   • `FerrofluidOcean.json` claimed `bass_energy_dev → spike height` for three months
//     after D-153 removed it (AGC-levelled bass barely moved the spikes — motion std 0.09),
//     plus the `accumulated_audio_time × arousal` drift product BUG-047 removed and the raw
//     `vocals_pitch_hz` palette read D-158 replaced. Its `audio_routes` was correct
//     throughout. That sentence is the likely origin of a live uzume.io caption.
//   • `VolumetricLithograph.json` credited its peak lift to `drums_beat` /
//     `drums_attack_ratio`. Those two names appear in that shader's COMMENTS eight times and
//     in no executable line of it; the peaks actually ride `pulse_beat_index +
//     pulse_phase01` with per-stem onset rates doing the polish.
//
// THE RULE. A field name written in a `description` must be one the preset can actually be
// shown to use: declared in its own `audio_routes`, or read by its own `.metal` with comments
// stripped. Comment-stripping is the whole point — VL's claim looked substantiated to a plain
// grep, which is how it survived a first pass of this very investigation.
//
// Why not the simpler rule "named in prose ⇒ declared in `audio_routes`": VL's onset-rate and
// pulse reads are real but undeclared, so that rule would have failed VL for a route-coverage
// problem (tracked separately) instead of for the drift, and a gate that fails for the wrong
// reason gets exempted rather than fixed.
//
// SCOPE. Only identifier-shaped mentions are checked — snake_case with an underscore, or
// camelCase. Single-word fields (`bass`, `mid`, `treble`, `arousal`, `valence`) are ordinary
// English and matching them would make a description unwritable; all eight stale claims
// BUG-138 found were multi-word identifiers, so that is the surface worth gating.
//
// KNOWN LIMITATION, stated rather than papered over: some presets route on the CPU
// (`NimbusState`, `SkeinState`, `RenderPipeline+Nacre`, the FFO aurora drivers), so a field
// read only in Swift is invisible to the read-set. Every such preset today declares those
// fields in `audio_routes` and so passes on the first branch. If one ever legitimately does
// not, the right answer is to declare it — not to widen this gate.
//
// Sidecars and shaders are enumerated via `PresetLoader.bundledShadersURL`, matching
// `AudioRouteSchemaTests` (`Bundle.module` from a test target resolves to the test bundle,
// which carries no Shaders resource — BUG-002 / NACRE.6).

import Foundation
import Testing
@testable import Presets

// MARK: - SidecarDescriptionDriftTests

struct SidecarDescriptionDriftTests {

    // MARK: - Field vocabulary

    /// Every real audio field name, in MSL snake_case, parsed from the authoritative MSL
    /// declaration. Derived, never listed: a hand-written vocabulary is one more copy to rot.
    /// Padding is excluded — `_pad17` is not a routable idea.
    static func audioFieldNames(commonMetal: String) -> Set<String> {
        var names: Set<String> = []
        for structName in ["FeatureVector", "StemFeatures"] {
            guard let start = commonMetal.range(of: "struct \(structName) {"),
                  let end = commonMetal.range(of: "\n};", range: start.upperBound..<commonMetal.endIndex)
            else { continue }
            // Strip `//` comments per line first, then scan the WHOLE body for `float …;`
            // declarations. Line-based splitting is wrong here: StemFeatures packs two
            // declarations onto one line (`float vocals_energy;      float vocals_band0;`),
            // which a line parser reads as one absurd field name and a 86-name vocabulary
            // with every stem field missing — a gate that then passes everything.
            let body = commonMetal[start.upperBound..<end.lowerBound]
                .split(separator: "\n")
                .map { $0.components(separatedBy: "//").first ?? String($0) }
                .joined(separator: "\n")
            guard let decl = try? NSRegularExpression(pattern: "\\bfloat\\s+([^;]+);") else { continue }
            let ns = body as NSString
            for match in decl.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                for field in ns.substring(with: match.range(at: 1)).split(separator: ",") {
                    let name = field.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty, !name.hasPrefix("_pad") { names.insert(name) }
                }
            }
        }
        return names
    }

    /// `drumsEnergyDev` → `drums_energy_dev`. Sidecars declare camelCase; MSL reads snake_case;
    /// descriptions have historically used either.
    static func snakeCased(_ token: String) -> String {
        guard token.contains(where: \.isUppercase) else { return token }
        var out = ""
        for (i, ch) in token.enumerated() {
            if ch.isUppercase {
                if i > 0 { out.append("_") }
                out.append(Character(ch.lowercased()))
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// Identifier-shaped tokens only — snake_case with at least one underscore, or camelCase.
    /// Scoped this way on purpose: the drift always took the form of an identifier with an
    /// arrow after it, and a gate that tried to parse English prose would be unmaintainable.
    static func identifierTokens(in text: String) -> [String] {
        let pattern = "\\b[a-z][a-z0-9]*(?:_[a-z0-9]+)+\\b|\\b[a-z]+(?:[A-Z][a-zA-Z0-9]*)+\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// Field names a shader genuinely reads. **Comments stripped first** — that strip is the
    /// difference between catching VolumetricLithograph and believing its description.
    static func shaderReadSet(msl: String, vocabulary: Set<String>) -> Set<String> {
        var code = msl.replacingOccurrences(
            of: "/\\*.*?\\*/", with: " ",
            options: [.regularExpression])
        code = code.replacingOccurrences(
            of: "//[^\\n]*", with: " ",
            options: [.regularExpression])
        let pattern = "\\.([a-z][a-z0-9_]*)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = code as NSString
        var reads: Set<String> = []
        for match in regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            if vocabulary.contains(name) { reads.insert(name) }
        }
        return reads
    }

    // MARK: - The gate

    @Test("A sidecar description may only name audio fields the preset actually uses (BUG-138)")
    func descriptionsNameOnlyFieldsThePresetUses() throws {
        let shadersURL = try #require(PresetLoader.bundledShadersURL,
            "Shaders resource not found via PresetLoader.bundledShadersURL")
        let commonURL = shadersURL
            .deletingLastPathComponent()
            .appendingPathComponent("Renderer/Shaders/Common.metal")
        // Bundled resources flatten differently per build; fall back to the repo copy.
        let commonMetal = (try? String(contentsOf: commonURL, encoding: .utf8))
            ?? (try? String(contentsOf: Self.repoCommonMetalURL(), encoding: .utf8))
        let common = try #require(commonMetal,
            "Common.metal unreadable — the field vocabulary is underivable, which is never a pass")

        let vocabulary = Self.audioFieldNames(commonMetal: common)
        #expect(vocabulary.count > 90,
                "field vocabulary parse imploded (\(vocabulary.count) names) — the gate would pass everything")

        let jsonFiles = try FileManager.default.contentsOfDirectory(
            at: shadersURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(jsonFiles.count >= 13, "expected at least 13 JSON sidecars, found \(jsonFiles.count)")

        let decoder = JSONDecoder()
        var unsupported: [String] = []
        var namesChecked = 0

        for jsonURL in jsonFiles {
            let name = jsonURL.lastPathComponent
            guard let data = try? Data(contentsOf: jsonURL),
                  let descriptor = try? decoder.decode(PresetDescriptor.self, from: data)
            else {
                Issue.record("\(name): decode failed")
                continue
            }
            guard !descriptor.description.isEmpty else { continue }

            var declared: Set<String> = []
            for route in descriptor.audioRoutes {
                declared.insert(route.primitive)
                declared.insert(Self.snakeCased(route.primitive))
            }

            let mslURL = jsonURL.deletingPathExtension().appendingPathExtension("metal")
            let readSet = (try? String(contentsOf: mslURL, encoding: .utf8))
                .map { Self.shaderReadSet(msl: $0, vocabulary: vocabulary) } ?? []

            let mentioned = Set(Self.identifierTokens(in: descriptor.description)
                .map(Self.snakeCased))
                .intersection(vocabulary)

            for field in mentioned.sorted() {
                namesChecked += 1
                guard !declared.contains(field), !readSet.contains(field) else { continue }
                unsupported.append(
                    "\(name): description names '\(field)', which is neither declared in its "
                    + "audio_routes nor read by \(mslURL.lastPathComponent) (comments stripped)")
            }
        }

        #expect(namesChecked > 0,
                "no sidecar description named a single audio field — the token scanner has stopped working")
        #expect(unsupported.isEmpty, """
            A sidecar `description` asserts audio routing the preset cannot be shown to do. \
            Either the route was retired and the sentence was not (BUG-138 — say what the preset \
            LOOKS like and let `audio_routes` carry the field names), or the route is real and \
            undeclared (add it to `audio_routes`, where RouteCoverageTests will prove it fires):
            \(unsupported.joined(separator: "\n"))
            """)
    }

    /// Guards the guard, on the two sentences that actually shipped.
    @Test("The gate catches both shapes of the BUG-138 drift")
    func gateCatchesTheRealDefects() throws {
        let common = try #require(try? String(contentsOf: Self.repoCommonMetalURL(), encoding: .utf8))
        let vocabulary = Self.audioFieldNames(commonMetal: common)

        // The vocabulary must contain the retired names, or the gate cannot see them.
        #expect(vocabulary.contains("bass_energy_dev"))
        #expect(vocabulary.contains("drums_beat"))
        #expect(vocabulary.contains("drums_attack_ratio"))

        // FFO's shipped sentence, in both spellings a sidecar might use.
        let ffo = "Audio routing per round 65: bass_energy_dev → spike height; arousal → swell amplitude."
        let ffoNames = Set(Self.identifierTokens(in: ffo).map(Self.snakeCased)).intersection(vocabulary)
        #expect(ffoNames.contains("bass_energy_dev"), "the retired FFO route must be detected in prose")
        // SCOPE, asserted so it cannot be mistaken for a bug later: single-word field names
        // (`arousal`, `bass`, `mid`, `treble`, `valence`) are deliberately NOT matched. They are
        // ordinary English — "the swell drifts slowly with arousal" is a sentence, not a claim
        // about a field — and matching them would make every description unwritable. All eight
        // stale claims BUG-138 found used multi-word identifiers, which is the covered surface.
        #expect(!ffoNames.contains("arousal"),
                "bare lowercase words must stay out of scope — see the note above")

        // VL's shipped sentence — and the reason comment-stripping is load-bearing: the two
        // names ARE present in its shader, but only ever inside comments.
        let vlLikeShader = """
        // Kick pulse (peak lift): max(stems.drums_beat, f.beat_bass * 0.8),
        //   smoothstep(1.3, 2.0, stems.drums_attack_ratio)
        float beatPos = f.pulse_beat_index + clamp(f.pulse_phase01, 0.0f, 1.0f);
        """
        let reads = Self.shaderReadSet(msl: vlLikeShader, vocabulary: vocabulary)
        #expect(!reads.contains("drums_beat"),
                "a commented-out read must NOT count as a read — this is the VL trap")
        #expect(!reads.contains("drums_attack_ratio"))
        #expect(reads.contains("pulse_beat_index"), "a real read must still be found")
        #expect(reads.contains("pulse_phase01"))

        // And a field genuinely read in code is accepted.
        let realShader = "float h = stems.bass_energy_dev * 2.0f + stems.drums_beat;"
        #expect(Self.shaderReadSet(msl: realShader, vocabulary: vocabulary).contains("bass_energy_dev"))

        // Non-field identifiers must be ignored, or every sidecar fails on `mv_warp`.
        let noise = "passes are direct and mv_warp; pixel_format is rgba16Float; see Nacre.metal"
        #expect(Set(Self.identifierTokens(in: noise).map(Self.snakeCased))
            .intersection(vocabulary).isEmpty)
    }

    // MARK: - Source location

    /// `Common.metal` in the enclosing checkout. Ascends to the nearest ancestor holding
    /// `UzumeEngine/Package.swift` — an anchor, not a name and not a hop count, so a worktree
    /// resolves to itself rather than sailing up into the primary checkout (FTR.6 / QG.6, the
    /// same reasoning as `CommonLayoutTest.repoRoot`).
    static func repoCommonMetalURL() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("UzumeEngine/Package.swift").path) {
                return url.appendingPathComponent("UzumeEngine/Sources/Renderer/Shaders/Common.metal")
            }
            if url.pathComponents.count <= 1 { break }
        }
        return URL(fileURLWithPath: "/nonexistent/Common.metal")
    }
}
