// TrackNameKey — name normalization for matching one song across sources (SCAN, D-260).
//
// Used by the scan resolver (is this catalog hit the song on screen?) and by
// the now-playing matcher (`PlannedSession+NameMatching`).

import Foundation

// MARK: - TrackNameKey

/// Name normalization for matching the same song across sources.
public enum TrackNameKey {

    /// Lowercased, accent-folded, punctuation → spaces, whitespace collapsed:
    /// "Flashbacks - Radio Edit" and "Flashbacks (Radio Edit)" → "flashbacks radio edit".
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let spaced = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Same primary artist: the first comma-separated credit of each, compared
    /// normalized, where one may extend the other by whole words ("Joan Jett" vs
    /// "Joan Jett & the Blackhearts"; "K.Flay" vs iTunes' "K.Flay & Aire Atlantica"),
    /// or equal once spaces are ignored (a screen read of "SOFI TUKKER" as "SOFITUKKER").
    public static func artistsMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalize(lhs.components(separatedBy: ",").first ?? lhs)
        let right = normalize(rhs.components(separatedBy: ",").first ?? rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left == right || left.hasPrefix(right + " ") || right.hasPrefix(left + " ")
            || left.replacingOccurrences(of: " ", with: "") == right.replacingOccurrences(of: " ", with: "")
    }

    /// The title without its version suffix: "Snail - Remastered 2011" and
    /// "Snail (2011 Remaster)" → "snail". Normalized.
    public static func baseTitle(_ title: String) -> String {
        let cut = title.range(of: " - ").map { String(title[..<$0.lowerBound]) } ?? title
        let bare = cut.range(of: " (").map { String(cut[..<$0.lowerBound]) } ?? cut
        return normalize(bare.range(of: " [").map { String(bare[..<$0.lowerBound]) } ?? bare)
    }
}
