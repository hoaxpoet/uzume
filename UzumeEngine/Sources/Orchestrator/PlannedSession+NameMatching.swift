// PlannedSession+NameMatching — tolerant now-playing → planned-track matching (SCAN.2, D-260).
//
// `canonicalIdentity(matchingTitle:artist:)` first tries the exact title+artist
// match (BUG-006.2). A scanned playlist breaks exactness: its planned titles are
// what fit on screen ("Is It Because You"), while the Now Playing AppleScript
// reports the whole title. These fallbacks run only when the exact match fails,
// and — like the exact one — only a UNIQUE match counts:
//
//   1. normalized names: case, accents, punctuation and "- Remix" vs "(Remix)"
//      ignored; compared against the planned names AND the catalog's full names
//      carried on the profile (`TrackProfile.catalogTitle`/`catalogArtist`);
//   2. prefix: the now-playing title starts with the planned title, whole words
//      only — covers a cut-off title whose catalog lookup found another version.

import Foundation
import Session

// MARK: - Fallback matching

extension PlannedSession {

    /// The tolerant fallbacks, in order. Returns the unique match of the first
    /// tier that has exactly one; nil when none does.
    func fallbackCanonicalIdentity(matchingTitle title: String, artist: String) -> TrackIdentity? {
        let wantTitle = TrackNameKey.normalize(title)
        guard !wantTitle.isEmpty else { return nil }
        let artistMatches = tracks.filter { planned in
            TrackNameKey.artistsMatch(artist, planned.track.artist)
                || planned.trackProfile.catalogArtist.map { TrackNameKey.artistsMatch(artist, $0) } == true
        }
        let named = artistMatches.filter { planned in
            TrackNameKey.normalize(planned.track.title) == wantTitle
                || planned.trackProfile.catalogTitle.map(TrackNameKey.normalize) == wantTitle
        }
        if named.count == 1 { return named[0].track }
        guard named.isEmpty else { return nil }
        // ponytail: a same-artist song whose title extends a planned one ("Ride" → "Ride On")
        // would match here when it is not itself in the plan. Revisit if a real session shows one.
        let prefixed = artistMatches.filter { planned in
            let plannedTitle = TrackNameKey.normalize(planned.track.title)
            return !plannedTitle.isEmpty && wantTitle.hasPrefix(plannedTitle + " ")
        }
        return prefixed.count == 1 ? prefixed[0].track : nil
    }
}
