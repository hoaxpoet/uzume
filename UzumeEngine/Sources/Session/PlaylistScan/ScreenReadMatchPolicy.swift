// ScreenReadMatchPolicy — pick the catalog hit that IS the song on screen (SCAN, D-260).
//
// The streaming path trusts the catalog's first hit for "artist title". A title
// read off the screen is often cut off ("Spitting Off the…"), and the first hit
// for a shortened title is frequently another song entirely (the SCAN.0 bench:
// Usher's "Yeah!"). For screen-read tracks `PreviewResolver` fetches
// `candidateLimit` hits and this policy keeps only one that matches what was on
// screen — title, primary artist, and the duration shown in the row — or none.
// No match is the safe outcome: the user would rather see a skipped track than
// visuals planned for the wrong music.

import Foundation

// MARK: - ScreenReadMatchPolicy

/// Verification rules for catalog hits against a screen reading.
public enum ScreenReadMatchPolicy {

    /// Hits requested per screen-read track.
    public static let candidateLimit = 25
    /// Largest duration difference (s) for a hit whose title matches what was shown
    /// exactly (or, for a cut-off title, starts with it). Catalogs disagree by a
    /// second or two on the same recording; a different mix is usually minutes off.
    static let exactTitleTolerance = 20.0
    /// Tighter bound for a looser title match: same title before any version
    /// suffix ("Snail - Remastered 2011" vs "Snail (2011 Remaster)"), or the
    /// catalog title extends the shown one ("… (feat. Perfume Genius)").
    static let looseTitleTolerance = 4.0

    /// A candidate that passed verification: its title tier and duration difference.
    struct Scored {
        let tier: Int
        let diff: Double
        let candidate: Candidate
    }

    /// One search hit.
    struct Candidate: Equatable {
        let title: String
        let artist: String
        let previewURL: URL
        let duration: Double?
    }

    /// The verified match in an iTunes Search response, or nil.
    public static func bestMatch(in data: Data, for track: TrackIdentity, reading: ScreenReading) -> PreviewMatch? {
        best(of: candidates(in: data), duration: track.duration, reading: reading).map {
            PreviewMatch(previewURL: $0.previewURL, catalogTitle: $0.title, catalogArtist: $0.artist)
        }
    }

    static func candidates(in data: Data) -> [Candidate] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { result in
            guard let title = result["trackName"] as? String,
                  let preview = (result["previewUrl"] as? String).flatMap(URL.init(string:)) else { return nil }
            let millis = result["trackTimeMillis"] as? Double ?? (result["trackTimeMillis"] as? Int).map(Double.init)
            return Candidate(
                title: title,
                artist: result["artistName"] as? String ?? "",
                previewURL: preview,
                duration: millis.map { $0 / 1000 }
            )
        }
    }

    /// Best verified candidate: exact-title hits before loose ones, then the
    /// closest duration; nothing outside its tier's tolerance.
    static func best(of candidates: [Candidate], duration: Double?, reading: ScreenReading) -> Candidate? {
        let scored = candidates.compactMap { candidate -> Scored? in
            guard artistMatches(candidate.artist, reading: reading),
                  let tier = titleTier(candidate.title, reading: reading) else { return nil }
            var diff = 0.0
            if let catalog = candidate.duration, let shown = duration { diff = abs(catalog - shown) }
            let tolerance = tier == 2 ? exactTitleTolerance : looseTitleTolerance
            // With no artist to check, only the tightest evidence counts.
            let bound = reading.artistLine.isEmpty ? min(tolerance, looseTitleTolerance) : tolerance
            return diff <= bound ? Scored(tier: tier, diff: diff, candidate: candidate) : nil
        }
        return scored.min { lhs, rhs in
            lhs.tier != rhs.tier ? lhs.tier > rhs.tier : lhs.diff < rhs.diff
        }?.candidate
    }

    /// 2 = the title shown (a prefix, if cut off) matches the catalog title;
    /// 1 = a looser match (see `looseTitleTolerance`); nil = a different title.
    static func titleTier(_ catalogTitle: String, reading: ScreenReading) -> Int? {
        let shown = TrackNameKey.normalize(reading.title)
        let full = TrackNameKey.normalize(catalogTitle)
        guard !shown.isEmpty else { return nil }
        if reading.titleCutOff ? full.hasPrefix(shown) : full == shown { return 2 }
        if !reading.titleCutOff, full.hasPrefix(shown + " ") { return 1 }
        let base = TrackNameKey.baseTitle(reading.title)
        return !base.isEmpty && base == TrackNameKey.baseTitle(catalogTitle) ? 1 : nil
    }

    /// Primary artist agrees; a cut-off sole artist only needs to be a prefix; and
    /// up to `badgeJunkLimit` leading characters may be Spotify's music-video badge
    /// fused onto the name ("DSZA", "L] Big Wild", "EOJENNIE" — SCAN.0 bench).
    /// An unread artist line checks nothing (the title/duration bound tightens instead).
    static func artistMatches(_ catalogArtist: String, reading: ScreenReading) -> Bool {
        guard !reading.artistLine.isEmpty else { return true }
        if TrackNameKey.artistsMatch(reading.artistLine, catalogArtist) { return true }
        let shown = TrackNameKey.normalize(reading.artistLine)
        if reading.artistCutOff && !reading.artistLine.contains(","),
           TrackNameKey.normalize(catalogArtist).hasPrefix(shown) { return true }
        let catalogPrimary = compact(catalogArtist)
        let shownPrimary = compact(reading.artistLine)
        guard catalogPrimary.count >= 2 else { return false }
        return (1...badgeJunkLimit).contains { shownPrimary.dropFirst($0) == catalogPrimary }
    }

    /// Characters a fused badge can add before an artist name.
    static let badgeJunkLimit = 3

    /// First credited artist, normalized, spaces removed.
    private static func compact(_ artist: String) -> String {
        let first = artist.components(separatedBy: ",").first ?? artist
        return TrackNameKey.normalize(first).replacingOccurrences(of: " ", with: "")
    }
}
