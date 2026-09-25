// CommonLayoutTest — D-099 layout invariant for buffer(0) / buffer(3) bindings.
//
// Swift `FeatureVector` (224 bytes / 56 floats) and `StemFeatures`
// (256 bytes / 64 floats) are bound directly to MSL preset preambles
// (PresetLoader+Preamble.swift) and to the engine library Common.metal.
// If either Swift struct ever shrinks, every shader that reads past the
// smaller boundary over-reads its bound buffer — silently on release
// builds, with undefined values feeding the rendered frame.
//
// This test fails fast at CI time before MSL ever sees the regression. It
// is the Swift-side companion to D-099; locking on the engine MSL side is
// not portable in MSL, so the gate lives here.

import Testing
import Foundation
@testable import Shared

// MARK: - CommonLayoutTest

struct CommonLayoutTest {

    /// Locks Swift `FeatureVector` and `StemFeatures` sizes to the values
    /// Common.metal's MSL structs were extended to in D-099. Failing this
    /// test is the canary that the buffer(2) / buffer(3) layout contract
    /// has drifted between Swift and MSL.
    @Test func featureVector_stemFeatures_layouts_locked() {
        #expect(MemoryLayout<FeatureVector>.size == 224 /* 56 floats = 224 bytes. DYN.1 added spectral_density/_slow (floats 49-50) taking it to 200, which is NOT 16-byte aligned; floats 51-52 were padding that restored it and were then claimed by DYN.1b/DYN.2. FTR.24 adds spectral_level_rise (float 53) and floats 54-56 are the padding that restores the alignment every preset depends on at buffer(0). */)
        #expect(MemoryLayout<StemFeatures>.size == 256)
    }

    // MARK: - MSL parity (DYN.2 regression)

    /// Locates the repo root from this file's path so the test can read the two MSL
    /// declaration sites directly.
    ///
    /// **Ascend to an anchor, not to a name and not by a count (FTR.6, hardened QG.6).**
    /// The original form walked up until it found a directory literally named `uzume` —
    /// which in a git worktree at `uzume/.claude/worktrees/<name>/` sails straight past
    /// the worktree and lands on the PRIMARY checkout. The gate then read the worktree's
    /// Swift struct and the primary's `.metal`, so an MSL edit made in a worktree was
    /// invisible to it while an untouched primary reported a phantom mismatch. Both
    /// directions are silent, and FTR.6 hit the second.
    ///
    /// FTR.6 replaced the name search with a fixed component count, which fixes the
    /// worktree case but re-breaks the moment this file moves — and a wrong root reads as
    /// "sources unreadable", which the parity test used to treat as a *pass*. Ascending to
    /// the nearest ancestor containing `UzumeEngine/Package.swift` is self-validating:
    /// a worktree root matches before the primary ever comes into range, and the result is
    /// either provably the enclosing checkout or `nil`.
    ///
    /// `nil` means this is not a source checkout (a bundled test product run outside the
    /// tree) — the ONLY legitimate reason the MSL sources are unreadable. Same
    /// arm-the-gate-or-skip-cleanly distinction `DocIntegrityTests.docsPresent` draws.
    private static let repoRoot: URL? = {
        var url = URL(fileURLWithPath: #filePath)
        // file → Shared → UzumeEngineTests → Tests → UzumeEngine → root is 5,
        // but never rely on that: search, and bound the search so it cannot run away.
        for _ in 0..<12 {
            url.deleteLastPathComponent()
            guard url.pathComponents.count > 1 else { return nil }
            let anchor = url.appendingPathComponent("UzumeEngine/Package.swift")
            if FileManager.default.fileExists(atPath: anchor.path) { return url }
        }
        return nil
    }()

    /// Extract the `float` field names of an MSL struct (default `FeatureVector`), in
    /// declaration order.
    private static func mslFields(of source: String, struct name: String = "FeatureVector") -> [String] {
        guard let start = source.range(of: "struct \(name) {"),
              let end = source.range(of: "};", range: start.upperBound..<source.endIndex)
        else { return [] }
        return source[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            // Strip trailing `//` comments FIRST — several declarations carry them, and a
            // parser that drops those lines invents a divergence that is not there.
            .map { line -> String in
                line.components(separatedBy: "//").first ?? String(line)
            }
            .joined(separator: " ")
            // Split on STATEMENTS, not lines: `StemFeatures` declares two floats per line
            // (`float strings_activity; float strings_activity_dev;`), which a per-line
            // parser reads as one mangled name (BC.1).
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("float ") }
            .flatMap { stmt -> [String] in
                stmt.dropFirst("float ".count)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            }
            .filter { !$0.isEmpty }
    }

    /// **THE GATE THIS FILE WAS MISSING, and it shipped a broken build to `main`.**
    ///
    /// DYN.2 added a field by claiming Swift's `_pad52` (net zero bytes) while *inserting*
    /// a field on the MSL side without removing its pad. Swift stayed 208 bytes so the
    /// assertion above stayed green; the shader struct became 212, and every draw died at
    /// runtime: *"argument features[0] from Buffer(0) … has space for 208 bytes, but
    /// argument has a length(212)."* The same edit also placed the new field BEFORE
    /// `spectral_surge` in MSL and AFTER it in Swift — so even at a matching size the two
    /// fields would have silently swapped, which a byte-count check alone cannot see.
    ///
    /// Order is the contract, not just the count.
    ///
    /// **An unreadable source is a FAILURE here, not a skip (QG.6).** The gate previously
    /// printed and returned green whenever either file could not be read, which made a
    /// wrong `repoRoot` indistinguishable from a pass — the same silent-success shape the
    /// gate exists to prevent, one level up. The only legitimate absence is "not a source
    /// checkout", and `repoRoot` now decides that explicitly by finding the enclosing
    /// package or returning `nil`. Past that point the files must exist.
    @Test func mslFeatureVector_matchesSwiftSizeAndAgreesAcrossBothSites() throws {
        guard let root = Self.repoRoot else {
            print("CommonLayoutTest: not a source checkout — skipping MSL parity")
            return
        }
        // The FTR.6 bug in one assertion: the root must enclose THIS file. A root that
        // resolves outside our own tree is how the gate came to compare two checkouts.
        #expect(
            URL(fileURLWithPath: #filePath).path.hasPrefix(root.path + "/"),
            "repoRoot \(root.path) does not contain \(#filePath) — the gate would read another checkout"
        )

        let commonURL = root
            .appendingPathComponent("UzumeEngine/Sources/Renderer/Shaders/Common.metal")
        let preambleURL = root
            .appendingPathComponent("UzumeEngine/Sources/Presets/PresetLoader+Preamble.swift")
        let common = try #require(
            try? String(contentsOf: commonURL, encoding: .utf8),
            "Common.metal unreadable at \(commonURL.path). This is a source checkout (\(root.path) has UzumeEngine/Package.swift), so the GPU contract is unverified — never a pass."
        )
        let preamble = try #require(
            try? String(contentsOf: preambleURL, encoding: .utf8),
            "PresetLoader+Preamble.swift unreadable at \(preambleURL.path). This is a source checkout, so the GPU contract is unverified — never a pass."
        )
        let commonFields = Self.mslFields(of: common)
        let preambleFields = Self.mslFields(of: preamble)

        #expect(commonFields.count > 40, "Common.metal FeatureVector parse imploded")
        #expect(commonFields.count * 4 == MemoryLayout<FeatureVector>.size, """
            Common.metal declares \(commonFields.count) floats = \(commonFields.count * 4) bytes, \
            but Swift FeatureVector is \(MemoryLayout<FeatureVector>.size). Every draw binding \
            buffer(0) fails Metal validation at runtime with exactly this delta.
            """)
        #expect(commonFields == preambleFields, """
            The two MSL declaration sites disagree. Runtime-compiled presets use the \
            PresetLoader preamble and engine shaders use Common.metal, so a divergence \
            silently corrupts one of them. First difference: \
            \(zip(commonFields, preambleFields).first { $0 != $1 }.map { "\($0) vs \($1)" } ?? "length")
            """)
    }

    /// BC.1 — the same order-is-the-contract gate for `StemFeatures` (buffer(3)), which had
    /// none. Both MSL sites must declare the same 64 floats in the same order, and the
    /// first reclaimed pad, `beat_clarity01`, must sit at float 56 (index 55) — exactly
    /// where Swift writes `beatClarity01`. A field that lands one slot off on either side
    /// reads a neighbour's value with no error anywhere.
    @Test func mslStemFeatures_matchesSwiftAndAgreesAcrossBothSites() throws {
        guard let root = Self.repoRoot else {
            print("CommonLayoutTest: not a source checkout — skipping MSL parity")
            return
        }
        let common = try #require(try? String(contentsOf: root.appendingPathComponent(
            "UzumeEngine/Sources/Renderer/Shaders/Common.metal"), encoding: .utf8),
            "Common.metal unreadable in a source checkout — never a pass")
        let preamble = try #require(try? String(contentsOf: root.appendingPathComponent(
            "UzumeEngine/Sources/Presets/PresetLoader+Preamble.swift"), encoding: .utf8),
            "PresetLoader+Preamble.swift unreadable in a source checkout — never a pass")
        let commonFields = Self.mslFields(of: common, struct: "StemFeatures")
        let preambleFields = Self.mslFields(of: preamble, struct: "StemFeatures")

        #expect(commonFields.count * 4 == MemoryLayout<StemFeatures>.size,
                "Common.metal StemFeatures is \(commonFields.count) floats; Swift is \(MemoryLayout<StemFeatures>.size / 4)")
        #expect(commonFields == preambleFields, """
            The two MSL StemFeatures declarations disagree. First difference: \
            \(zip(commonFields, preambleFields).first { $0 != $1 }.map { "\($0) vs \($1)" } ?? "length")
            """)
        #expect(commonFields.firstIndex(of: "beat_clarity01") == 55,
                "beat_clarity01 must be float 56 (index 55) in MSL")
        #expect(MemoryLayout<StemFeatures>.offset(of: \StemFeatures.beatClarity01) == 55 * 4,
                "Swift beatClarity01 must sit at byte 220 to match MSL")
    }

    // MARK: - Prose parity (BUG-138)

    /// Structs whose size is restated in prose, with the expected values **derived** rather
    /// than written down. A gate that hardcodes `56` becomes the ninth stale copy of the
    /// number the moment a field lands; reading `MemoryLayout` means this gate cannot rot.
    private static var gatedStructSizes: [String: (floats: Int, bytes: Int)] {
        [
            "FeatureVector": (MemoryLayout<FeatureVector>.size / 4, MemoryLayout<FeatureVector>.size),
            "StemFeatures": (MemoryLayout<StemFeatures>.size / 4, MemoryLayout<StemFeatures>.size),
            "FeedbackParams": (MemoryLayout<FeedbackParams>.size / 4, MemoryLayout<FeedbackParams>.size),
        ]
    }

    /// A size claim written in prose, with the struct it is about and where it was found.
    struct ProseSizeClaim: Sendable {
        let file: String, structName: String, floats: Int, bytes: Int, text: String
    }

    /// Normalise source for prose scanning.
    ///
    /// Two deliberate transforms, each load-bearing:
    ///
    /// 1. **Double-quoted spans are blanked.** A number inside quotes is a CITATION of a past
    ///    claim, not a claim — `AudioFeatures+Analyzed.swift` and `PresetLoader+Preamble.swift`
    ///    both quote the old wrong `"48 floats = 192 bytes"` while explaining the drift, and a
    ///    gate that failed on those would punish the two comments that got it right. (Same rule
    ///    as the brand sweep: never rewrite a quotation.)
    /// 2. **Comment markers are dropped and whitespace collapsed**, so a claim wrapped across
    ///    two `///` lines reads as one string. The original defect spanned lines exactly that way.
    static func normalisedForProse(_ source: String) -> String {
        let unquoted = source.replacingOccurrences(
            of: "\"[^\"]{0,400}\"", with: "\"\"",
            options: [.regularExpression])
        let uncommented = unquoted.replacingOccurrences(
            of: "^[ \\t]*(///|//|\\*)", with: " ",
            options: [.regularExpression])
        return uncommented.replacingOccurrences(
            of: "\\s+", with: " ", options: [.regularExpression])
    }

    /// How far back a claim may sit from the struct name it describes. These are written as
    /// `FeatureVector (56 floats / 224 B)`, so the subject is always close — and attributing a
    /// claim to the NEAREST PRECEDING name is what stops `FeatureVector (…) + StemFeatures (…)`
    /// reading the neighbour's correct numbers as this struct's wrong ones.
    private static let subjectLookbackChars = 60

    /// Every prose `N floats / M bytes` claim about a gated struct, in one file.
    static func proseSizeClaims(in source: String, file: String) -> [ProseSizeClaim] {
        let text = normalisedForProse(source)
        // Either order: "56 floats = 224 bytes" or "224 bytes / 56 floats".
        let pattern = "(\\d+)\\s*floats?\\s*(?:=|/|,|is)\\s*(\\d+)\\s*(?:bytes|B)\\b"
            + "|(\\d+)\\s*(?:bytes|B)\\s*(?:=|/|,)\\s*(\\d+)\\s*floats?\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var claims: [ProseSizeClaim] = []
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            func group(_ i: Int) -> Int? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : Int(ns.substring(with: r))
            }
            let floats: Int, bytes: Int
            if let f = group(1), let b = group(2) { (floats, bytes) = (f, b) }
            else if let b = group(3), let f = group(4) { (floats, bytes) = (f, b) }
            else { return }

            let backStart = max(0, m.range.location - subjectLookbackChars)
            let back = ns.substring(with: NSRange(location: backStart,
                                                 length: m.range.location - backStart))
            // Nearest preceding gated name wins; no name means this is not our claim.
            let subject = gatedStructSizes.keys
                .compactMap { name in back.range(of: name, options: .backwards).map { (name, $0.lowerBound) } }
                .max { $0.1 < $1.1 }?.0
            guard let subject else { return }
            claims.append(ProseSizeClaim(file: file, structName: subject,
                                         floats: floats, bytes: bytes,
                                         text: ns.substring(with: m.range)))
        }
        return claims
    }

    /// **The gate FTR.6 decided not to build, and the prose grew back in eight places.**
    ///
    /// FTR.6 found `FeatureVector`'s doc comment claiming `48 floats = 192 bytes` two
    /// increments after it stopped being true, diagnosed it exactly — *"nothing caught it,
    /// because no gate reads prose"* — and chose to DELETE that copy rather than gate the
    /// pattern. By BUG-138 the claim was wrong again in `Common.metal`, `AnalyzedFrame.swift`,
    /// `SpectralCartograph.metal`, three places in `ARCHITECTURE.md`, and in the very doc
    /// comment that carries the FTR.6 lecture (as `52 floats = 208 bytes`). Deleting one copy
    /// does not stop copies; this does.
    ///
    /// Expected values come from `MemoryLayout`, so adding a field moves the gate with the
    /// struct instead of against it.
    @Test func proseSizeClaims_agreeWithMemoryLayout() throws {
        guard let root = Self.repoRoot else {
            print("CommonLayoutTest: not a source checkout — skipping prose parity")
            return
        }
        let fm = FileManager.default
        var files: [(url: URL, label: String)] = []
        let sources = root.appendingPathComponent("UzumeEngine/Sources")
        if let walk = fm.enumerator(at: sources, includingPropertiesForKeys: nil) {
            for case let url as URL in walk where ["swift", "metal"].contains(url.pathExtension) {
                files.append((url, url.lastPathComponent))
            }
        }
        let architecture = root.appendingPathComponent("docs/ARCHITECTURE.md")
        files.append((architecture, "docs/ARCHITECTURE.md"))

        #expect(files.count > 200, "source walk imploded — found only \(files.count) files")
        #expect(fm.fileExists(atPath: architecture.path),
                "docs/ARCHITECTURE.md missing from a source checkout — the doc half is unverified, never a pass")

        var claims: [ProseSizeClaim] = []
        for (url, label) in files {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            claims += Self.proseSizeClaims(in: text, file: label)
        }
        // Arm-or-fail: if the scanner finds nothing, it is broken, not the tree clean.
        #expect(claims.count >= 8, "prose scanner found only \(claims.count) size claims — it has stopped working")

        let wrong = claims.filter { claim in
            guard let expected = Self.gatedStructSizes[claim.structName] else { return false }
            return (claim.floats, claim.bytes) != (expected.floats, expected.bytes)
        }
        #expect(wrong.isEmpty, """
            Prose restates a gated struct's size incorrectly. \
            `CommonLayoutTest` locks the LAYOUT; this locks the SENTENCES that describe it, \
            because the sentence is the half a human reads first (BUG-138):
            \(wrong.map { claim in "  \(claim.file): \(claim.structName) written as \"\(claim.text)\", but MemoryLayout says \(Self.gatedStructSizes[claim.structName].map { "\($0.floats) floats / \($0.bytes) bytes" } ?? "?") " }.joined(separator: "\n"))
            """)
    }

    /// Guards the guard: the exact sentence BUG-138 found must be caught, the corrected one
    /// must pass, and a quoted citation of the old value must NOT be treated as a claim.
    @Test func proseSizeGate_catchesTheOriginalDefect() throws {
        let stale = Self.proseSizeClaims(
            in: "// Matches Swift FeatureVector layout (48 floats = 192 bytes, MV-1/MV-3b).",
            file: "probe")
        #expect(stale.count == 1, "the original BUG-138 sentence must register as one claim")
        #expect(stale.first?.structName == "FeatureVector")
        let expected = try #require(Self.gatedStructSizes["FeatureVector"])
        let staleClaim = try #require(stale.first)
        #expect((staleClaim.floats, staleClaim.bytes) != (expected.floats, expected.bytes),
                "the stale sentence must not compare equal to the real layout")

        let fixed = Self.proseSizeClaims(
            in: "// Matches Swift FeatureVector layout (56 floats = 224 bytes).", file: "probe")
        let fixedClaim = try #require(fixed.first)
        #expect((fixedClaim.floats, fixedClaim.bytes) == (expected.floats, expected.bytes))

        // A CITATION, not a claim — FTR.6's own explanation of the drift must stay legal.
        let quoted = Self.proseSizeClaims(
            in: "/// it had drifted to \"48 floats = 192 bytes\" and was wrong for FeatureVector",
            file: "probe")
        #expect(quoted.isEmpty, "a quoted past value is a citation and must not fail the gate")

        // The neighbour trap: two structs on one line must each get their own numbers.
        let pair = Self.proseSizeClaims(
            in: "// FeatureVector (56 floats / 224 B) + StemFeatures (64 floats / 256 B)", file: "probe")
        #expect(pair.count == 2)
        #expect(pair.first?.structName == "FeatureVector")
        #expect(pair.last?.structName == "StemFeatures")
    }
}
