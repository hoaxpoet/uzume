// PlaylistScanTypes — value types for reading a playlist off the screen (SCAN, D-260).
//
// The scan path reads a streaming app's track list from pixels, on device, so a
// playlist can be brought in without that service's Web API. Recognition turns an
// image into `ScanTextObservation`s; `PlaylistFrameParser` turns those into one
// `PlaylistScanFrame`; `PlaylistScanAccumulator` merges frames into the playlist.
// Splitting at the observation boundary keeps the parser testable with authored
// JSON (no Vision, no fixtures) — the CI-safe half of the SCAN test surface.

import CoreGraphics
import Foundation

// MARK: - ScanTextObservation

/// One recognized line of text and where it sits in the image.
///
/// `box` is normalized to the image (0…1 on both axes) with a **top-left**
/// origin — y grows downward, matching reading order. (Vision reports a
/// bottom-left origin; `PlaylistFrameRecognizer` flips it.)
public struct ScanTextObservation: Sendable, Codable, Equatable {
    /// The recognized string, exactly as read.
    public let text: String
    /// Recognizer confidence, 0…1.
    public let confidence: Double
    /// Normalized bounding box, top-left origin.
    public let box: CGRect

    /// Create an observation.
    public init(text: String, confidence: Double, box: CGRect) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}

// MARK: - ScannedRow

/// One playlist row as read off the screen.
public struct ScannedRow: Sendable, Codable, Equatable {
    /// The row's position in the playlist (Spotify's "#" column), 1-based.
    public var number: Int
    /// Title as displayed — may be cut off (see `titleTruncated`). Ellipsis removed.
    public var title: String
    /// Artist line as displayed (all credited artists, comma-separated). Ellipsis removed.
    public var artist: String
    /// Duration in seconds, when the duration column was read.
    public var duration: Double?
    /// 0…1 — how sure the reader is of this row. Rows below
    /// `ScannedRow.unsureThreshold` are flagged for review.
    public var confidence: Double
    /// The title ended in an ellipsis: only a prefix of the real title is known.
    public var titleTruncated: Bool
    /// The artist line ended in an ellipsis.
    public var artistTruncated: Bool

    /// Rows under this confidence are marked as unsure in the review list.
    public static let unsureThreshold = 0.6

    /// Create a row.
    public init(
        number: Int, title: String, artist: String, duration: Double? = nil,
        confidence: Double, titleTruncated: Bool = false, artistTruncated: Bool = false
    ) {
        self.number = number
        self.title = title
        self.artist = artist
        self.duration = duration
        self.confidence = confidence
        self.titleTruncated = titleTruncated
        self.artistTruncated = artistTruncated
    }

    /// True when the review list should mark this row as one to check.
    public var isUnsure: Bool { confidence < Self.unsureThreshold }

    /// The first credited artist — what the Spotify Web API connector uses as
    /// `TrackIdentity.artist`, so scanned and API-sourced identities agree.
    public var primaryArtist: String {
        let first = artist.components(separatedBy: ", ").first ?? artist
        return first.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - PlaylistScanFrame

/// Everything read from one image of the playlist.
public struct PlaylistScanFrame: Sendable, Equatable {
    /// Rows found in this frame, top to bottom.
    public var rows: [ScannedRow]
    /// The "N songs" count from the playlist header, when visible.
    public var songCount: Int?
    /// The playlist name (header or sticky bar), when read.
    public var playlistName: String?
    /// True when the "Recommended" section is visible: the list has ended.
    public var reachedEnd: Bool
    /// The playlist pane's horizontal extent (full height), normalized — where
    /// to look in the next frame. nil when no track list was found.
    public var listRegion: CGRect?

    /// Create a frame.
    public init(
        rows: [ScannedRow] = [], songCount: Int? = nil, playlistName: String? = nil,
        reachedEnd: Bool = false, listRegion: CGRect? = nil
    ) {
        self.rows = rows
        self.songCount = songCount
        self.playlistName = playlistName
        self.reachedEnd = reachedEnd
        self.listRegion = listRegion
    }
}

// MARK: - Gap ranges

/// A run of consecutive row numbers that were never read, e.g. 14–16.
public struct ScanGap: Sendable, Equatable, Codable {
    /// First missing row number.
    public let first: Int
    /// Last missing row number (== `first` for a single row).
    public let last: Int

    /// Create a gap.
    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }

    /// Number of missing rows.
    public var count: Int { last - first + 1 }
}

// MARK: - ScannedRow → TrackIdentity

extension ScannedRow {

    /// The title to search the catalog with. A cut-off title ("Is It Because
    /// You Kn…") drops its last, possibly partial, word and any separator left
    /// dangling ("Summer & Smoke - …" → "Summer & Smoke").
    public var searchTitle: String {
        titleTruncated ? Self.withoutCutOffTail(title) : title
    }

    /// The identity handed to preparation. `artist` is the first credited
    /// artist, matching `SpotifyWebAPIConnector`.
    public var trackIdentity: TrackIdentity {
        TrackIdentity(
            title: searchTitle,
            artist: searchArtist,
            duration: duration,
            screenReading: ScreenReading(
                title: title,
                titleCutOff: titleTruncated,
                artistLine: artist,
                artistCutOff: artistTruncated
            )
        )
    }

    /// The artist to search with: the first credited artist, minus a cut-off
    /// last word when that first artist is itself the truncated one.
    public var searchArtist: String {
        guard artistTruncated, !artist.contains(", ") else { return primaryArtist }
        return Self.withoutCutOffTail(primaryArtist)
    }

    /// Drop the last (possibly partial) word, then any words left dangling
    /// ("Summer & Smoke - Tri…" → "Summer & Smoke"). Never empties the text.
    static func withoutCutOffTail(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        if words.count > 1 { words.removeLast() }
        let dangling: Set<String> = ["-", "–", "—", "(", "[", "&", "+", "x", "and", "the", "with", "feat.", "ft."]
        while words.count > 1, let last = words.last,
              dangling.contains(last.lowercased()) || last.hasSuffix(",") || last.hasPrefix("(") {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }
}
