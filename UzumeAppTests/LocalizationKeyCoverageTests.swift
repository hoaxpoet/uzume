// LocalizationKeyCoverageTests — BR.4 / audit F18: every string key the app references
// exists, so no raw key ("settings.about.app.title") ever reaches the screen.
// `Scripts/check_user_strings.sh` checks that copy is externalized, not that the key exists.

import Foundation
import Testing
@testable import UzumeApp

@Suite("Every referenced localization key exists (BR.4)")
struct LocalizationKeyCoverageTests {

    /// Keys passed to `String(localized:)`, `NSLocalizedString(` or `LocalizedStringKey(` in UzumeApp/.
    private func referencedKeys() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UzumeApp")
        let pattern = try NSRegularExpression(
            pattern: #"(?:String\(localized:\s*|NSLocalizedString\(\s*|LocalizedStringKey\(\s*)"([^"\\]+)""#)
        var keys: [String: String] = [:]
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            let src = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(src.startIndex..., in: src)
            for match in pattern.matches(in: src, range: range) {
                if let hit = Range(match.range(at: 1), in: src) { keys[String(src[hit])] = file.lastPathComponent }
            }
        }
        return keys
    }

    @Test func everyReferencedKeyResolvesInTheAppBundle() throws {
        let keys = try referencedKeys()
        #expect(keys.count > 200, "the scan found the app's keys (\(keys.count))")
        let sentinel = "\u{0}missing"
        let missing = keys.filter { key, _ in
            Bundle.main.localizedString(forKey: key, value: sentinel, table: nil) == sentinel
        }
        #expect(missing.isEmpty, "keys with no string (shown raw): \(missing.sorted { $0.key < $1.key })")
    }
}
