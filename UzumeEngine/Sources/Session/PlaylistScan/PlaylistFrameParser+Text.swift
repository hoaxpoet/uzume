// PlaylistFrameParser+Text — cleaning what Vision read off a playlist row (SCAN, D-260).
//
// Ellipses, badges fused onto artists, the "|" Vision reads for a capital I, duration
// cells, and the chrome text (buttons, tooltips, context menus) that is never a title.

import Foundation

// MARK: - Text

extension PlaylistFrameParser {

    /// Text that is chrome, never a title or artist: row buttons, tooltips, and the
    /// row / playlist context-menu items (a menu left open floats over the list).
    static let chromeText: Set<String> = [
        "add", "+ add", "add to liked songs", "remove from liked songs", "save to your liked songs",
        "add to playlist", "add to other playlist", "save to your library", "remove from your library",
        "more options", "add to queue", "start a jam", "turn on mix", "add to profile", "report", "download",
        "leave playlist", "exclude from your taste profile", "move to folder", "share", "go to artist",
        "go to album", "go to song radio", "view credits", "remove from this playlist", "edit details", "delete"
    ]

    // MARK: Text cleanup

    static func isChrome(_ text: String) -> Bool {
        chromeText.contains(text.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Normalize one displayed string: strip a trailing ellipsis (reporting it),
    /// map Vision's "|" / "l" for a lone capital I, collapse whitespace.
    static func clean(_ raw: String) -> (text: String, truncated: Bool) {
        var text = raw.replacingOccurrences(of: "\u{2026}", with: "...")
        var truncated = false
        while let last = text.last, last == "." || last == " " {
            // A single trailing "." can be real ("The Radio Dept."); two+ is an ellipsis.
            if text.hasSuffix("..") { truncated = true } else if last == ".", !truncated { break }
            text.removeLast()
        }
        let words = text
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { $0 == "|" || $0 == "l" ? "I" : String($0) }
        return (words.joined(separator: " "), truncated)
    }

    /// Strip the badges Spotify draws before an artist ("E" explicit, ▶ music
    /// video — Vision reads the latter as "•", "D", "▶" or "►").
    static func stripBadges(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        // Vision's readings of the explicit (E) and music-video (▶) badges, as seen on
        // real captures (SCAN.0). "DJ" is deliberately absent — it is a real first word.
        let badges: Set<String> = ["E", "D", "L", "J", "LI", "L]", "D]", "E]", "ED", "EO", "EL", "[E]",
                                   "•", "▶", "►", "▷", "⊳", "■", "□", "回"]
        let glyphs = CharacterSet(charactersIn: "•▶►▷⊳■□回")
        // ponytail: a real artist whose first word is a lone "E"/"D" loses it; none seen, revisit if one is
        while words.count > 1, badges.contains(words[0])
                || (words[0].count <= 2 && words[0].unicodeScalars.contains(where: glyphs.contains)) {
            words.removeFirst()
        }
        // A badge's edge can fuse onto the first word as a bar: "|ZHU".
        if let first = words.first, first.count > 1, first.hasPrefix("|") {
            words[0] = String(first.dropFirst())
        }
        return words.joined(separator: " ")
    }

    /// A duration at the start of a cell with trailing junk ("3:27 ...").
    static func leadingDuration(_ text: String) -> Double? {
        guard let match = text.firstMatch(of: /^\s*((?:\d{1,2}:)?\d{1,2}:\d{2})(?:\s|$)/) else { return nil }
        return duration(String(match.1))
    }

    static func duration(_ text: String) -> Double? {
        guard let match = text.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(?:(\d{1,2}):)?(\d{1,2}):(\d{2})/) else { return nil }
        let hours = match.1.flatMap { Double($0) } ?? 0
        guard let minutes = Double(match.2), let seconds = Double(match.3) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
