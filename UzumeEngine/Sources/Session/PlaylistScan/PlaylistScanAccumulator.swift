// PlaylistScanAccumulator — merges frames into one playlist while the user scrolls (SCAN, D-260).
//
// Incremental by design: the live scan feeds one frame at a time; a dropped set
// of screenshots feeds them in name order. Rows are keyed by their playlist
// number, so overlapping captures dedupe for free and the best reading of each
// row wins (a complete row beats one cut off at a frame edge).

import Foundation

// MARK: - PlaylistScanAccumulator

/// Accumulates `PlaylistScanFrame`s into a playlist with gap detection.
public struct PlaylistScanAccumulator: Sendable, Equatable {

    // MARK: State

    /// Best reading per row number.
    public private(set) var rowsByNumber: [Int: ScannedRow] = [:]
    /// The header's "N songs" count, once read.
    public private(set) var songCount: Int?
    /// The playlist name, once read.
    public private(set) var playlistName: String?
    /// The "Recommended" shelf has been seen: the list's end is on screen.
    public private(set) var reachedEnd = false
    /// The lowest row number seen in the first frame that had rows. Drives the
    /// "Scroll to the top of the playlist first." prompt.
    public private(set) var firstNumberSeen: Int?

    // MARK: Init

    /// Create an empty accumulator.
    public init() {}

    // MARK: Merge

    /// Merge one frame. Returns true when it changed anything.
    @discardableResult
    public mutating func add(_ frame: PlaylistScanFrame) -> Bool {
        let before = self
        if let count = frame.songCount, count > 0 { songCount = count }
        if let name = frame.playlistName, !name.isEmpty, Self.prefer(name, over: playlistName) { playlistName = name }
        if frame.reachedEnd { reachedEnd = true }
        if firstNumberSeen == nil, let first = frame.rows.map(\.number).min() { firstNumberSeen = first }
        for row in frame.rows where songCount.map({ row.number <= $0 }) ?? true {
            if let held = rowsByNumber[row.number], held.confidence >= row.confidence { continue }
            rowsByNumber[row.number] = row
        }
        if let count = songCount { rowsByNumber = rowsByNumber.filter { $0.key <= count } }
        return self != before
    }

    /// A complete name beats a cut-off one; otherwise the longer reading wins.
    static func prefer(_ candidate: String, over held: String?) -> Bool {
        guard let held else { return true }
        return candidate.count > held.count
    }

    // MARK: Derived

    /// All rows read so far, in playlist order.
    public var rows: [ScannedRow] { rowsByNumber.values.sorted { $0.number < $1.number } }

    /// How many songs the playlist has: the header count, or — when the header
    /// was never read — the last row number once the list's end was seen.
    public var expectedCount: Int? {
        songCount ?? (reachedEnd ? rowsByNumber.keys.max() : nil)
    }

    /// Runs of row numbers never read, up to the expected count (or the highest
    /// number seen when the count is unknown).
    public var gaps: [ScanGap] {
        let upper = expectedCount ?? rowsByNumber.keys.max() ?? 0
        var result: [ScanGap] = []
        var start: Int?
        for number in 1...max(upper, 1) where upper > 0 {
            if rowsByNumber[number] == nil {
                if start == nil { start = number }
            } else if let open = start {
                result.append(ScanGap(first: open, last: number - 1))
                start = nil
            }
        }
        if let open = start, upper > 0 { result.append(ScanGap(first: open, last: upper)) }
        return result
    }

    /// Every song in the header count has been read.
    public var isComplete: Bool {
        guard let expected = expectedCount, expected > 0 else { return false }
        return rowsByNumber.count == expected && gaps.isEmpty
    }
}
