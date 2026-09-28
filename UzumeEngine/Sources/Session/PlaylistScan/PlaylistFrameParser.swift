// PlaylistFrameParser — recognized text lines → playlist rows (SCAN, D-260).
//
// A Spotify desktop window holds far more text than the playlist: the library
// sidebar, the Now Playing panel, the player bar, the "Recommended" shelf. The
// parser anchors on the one thing only track rows have — a right-aligned column
// of durations ("5:35") — and builds each row around it:
//
//   #   [art]  Title (upper line)                 ✓   5:35
//              E ▶ Artist, Artist (lower line)
//
// Row numbers come from the "#" column, re-derived from vertical position so a
// hovered row (number replaced by ▶) or a misread digit still lands on the right
// number. Compact view (title and artist on one line, in separate columns) is
// recognized per frame from the row geometry.

import CoreGraphics
import Foundation

// MARK: - PlaylistFrameParser

/// Stateless parser for one frame's observations.
public enum PlaylistFrameParser {

    // MARK: Tuning

    /// Durations belong to one column when their right edges agree this closely
    /// (normalized width). The player bar's elapsed/total times sit ~0.009 away.
    static let durationColumnTolerance: CGFloat = 0.004

    // MARK: Parse

    /// Parse one frame. Returns an empty frame when no track list is visible.
    public static func parse(_ observations: [ScanTextObservation]) -> PlaylistScanFrame {
        let songCount = observations.lazy.compactMap { Self.songCount(in: $0.text) }.first
        let endY = observations.first { isRecommendedHeading($0.text) }?.box.minY
        guard let layout = Layout(observations) else {
            return PlaylistScanFrame(songCount: songCount, playlistName: nil, reachedEnd: endY != nil)
        }
        let rows = layout.rows(endY: endY)
        let left = max(0, layout.paneMinX - 0.03)
        return PlaylistScanFrame(
            rows: rows,
            songCount: songCount,
            playlistName: playlistName(observations, layout: layout),
            reachedEnd: endY != nil,
            listRegion: CGRect(x: left, y: 0, width: min(1, layout.paneMaxX + 0.02) - left, height: 1)
        )
    }

    // MARK: Header

    /// "40 songs, 2 hr 57 min" → 40. English UI only (KNOWN_ISSUES).
    static func songCount(in text: String) -> Int? {
        guard let match = text.firstMatch(of: /(?i)\b(\d[\d,]*)\s+songs?\b/) else { return nil }
        return Int(match.1.replacingOccurrences(of: ",", with: ""))
    }

    static func isRecommendedHeading(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespaces).lowercased() == "recommended"
    }

    /// The playlist name: the large text above the list. On the first capture it
    /// sits between the "Public Playlist" label and the owner/"N songs" lines (and
    /// may wrap); once scrolled it is the sticky bar just above the "# Title" row.
    static func playlistName(_ observations: [ScanTextObservation], layout: Layout) -> String? {
        let inPane = observations.filter {
            $0.box.minX >= layout.paneMinX && $0.box.maxX <= layout.paneMaxX + 0.02
                && $0.box.maxY <= layout.listTopY && !isChrome($0.text)
        }
        if let countLine = inPane.first(where: { songCount(in: $0.text) != nil }) {
            let label = inPane
                .filter { $0.text.lowercased().hasSuffix("playlist") && $0.box.maxY <= countLine.box.minY }
                .max { $0.box.minY < $1.box.minY }
            let floorY = label?.box.maxY ?? 0
            // Between the label and the count line, left-aligned with it (cover-art text
            // sits further left), minus the owner line ("… • 9 saves •"). Without a
            // label, only text clearly larger than the count line qualifies.
            let lines = inPane
                .filter {
                    $0.box.minY >= floorY - 0.002 && $0.box.maxY <= countLine.box.minY + 0.002
                        && abs($0.box.minX - countLine.box.minX) < 0.01
                        && songCount(in: $0.text) == nil && !$0.text.contains("•")
                        && (label != nil || $0.box.height >= countLine.box.height * 1.3)
                }
                .sorted { $0.box.minY < $1.box.minY }
            if !lines.isEmpty { return clean(lines.map(\.text).joined(separator: " ")).text }
        }
        guard let header = layout.columnHeader else { return nil }
        let sticky = inPane
            .filter { $0.box.maxY <= header.box.minY && $0.box.height >= header.box.height * 1.5 }
            .max { $0.box.minY < $1.box.minY }
        return sticky.map { clean($0.text).text }
    }
}

// MARK: - Layout

extension PlaylistFrameParser {

    /// One duration cell and its value in seconds.
    struct DurationCell {
        let obs: ScanTextObservation
        let seconds: Double
    }

    /// A row before numbering: its centre line and the number read beside it, if any.
    struct RowCandidate {
        let slotY: CGFloat
        let number: Int?
        let row: ScannedRow
    }

    /// Where the track list is in this frame.
    struct Layout {
        let observations: [ScanTextObservation]
        /// Duration cells of the list, top to bottom.
        let durations: [DurationCell]
        /// Typical row pitch (normalized height).
        let rowHeight: CGFloat
        /// Typical text line height (normalized), from the duration cells.
        let textHeight: CGFloat
        /// Left edge of the title/artist column.
        let textMinX: CGFloat
        /// Horizontal extent of the playlist pane.
        let paneMinX: CGFloat
        let paneMaxX: CGFloat
        /// The "# Title" column-header row, when visible.
        let columnHeader: ScanTextObservation?
        /// Where the title column ends: the next header label ("Album", "Date added");
        /// "Artist" is a column of its own only in compact view, so it doesn't count.
        /// The duration column when no other label is visible.
        let titleColumnMaxX: CGFloat
        /// Top of the first list row.
        let listTopY: CGFloat

        init?(_ observations: [ScanTextObservation]) {
            let timed = observations.compactMap { obs in
                PlaylistFrameParser.duration(obs.text).map { DurationCell(obs: obs, seconds: $0) }
            }
            guard var column = Self.largestColumn(timed) else { return nil }
            // A hovered row's cell can merge with the "⋯" button ("3:27 ...") or
            // widen; its LEFT edge still lines up with the column.
            let columnMinX = column.map(\.obs.box.minX).sorted()[column.count / 2]
            for obs in observations where !column.contains(where: { $0.obs == obs })
                && abs(obs.box.minX - columnMinX) < PlaylistFrameParser.durationColumnTolerance {
                if let seconds = PlaylistFrameParser.leadingDuration(obs.text) {
                    column.append(DurationCell(obs: obs, seconds: seconds))
                }
            }
            let durations = column.sorted { $0.obs.box.midY < $1.obs.box.midY }
            let pitches = zip(durations.dropFirst(), durations)
                .map { $0.obs.box.midY - $1.obs.box.midY }
                .sorted()
            let textHeight = durations.map(\.obs.box.height).sorted()[durations.count / 2]
            let rowHeight = pitches.isEmpty ? textHeight * 3.8 : pitches[pitches.count / 2]
            let durationMinX = durations.map(\.obs.box.minX).min() ?? 1
            let inRowBand = { (obs: ScanTextObservation, fraction: CGFloat) in
                durations.contains { abs($0.obs.box.midY - obs.box.midY) < rowHeight * fraction }
            }
            // Row numbers: whole numbers on a duration's line. They anchor the pane —
            // the library sidebar's text can line up with the rows too, but never right
            // of the "#" column.
            let numbers = observations.filter {
                Int($0.text) != nil && $0.box.maxX < durationMinX && inRowBand($0, 0.3)
            }
            let numbersMaxX = numbers.map(\.box.maxX).sorted().dropFirst(numbers.count / 2).first ?? 0
            // Text column: the modal left edge of text inside row bands, right of the
            // numbers, left of the durations and — with the header row in view — of the
            // next column's label. Chrome (a context menu left open) doesn't vote.
            let headerGuess = observations.first {
                ["title", "# title"].contains($0.text.lowercased()) && $0.box.maxX < durationMinX
            }
            let titleEnd = Self.titleColumnEnd(observations, header: headerGuess, durationMinX: durationMinX)
            let lefts = observations
                .filter { obs in
                    obs.box.minX > numbersMaxX && obs.box.minX < titleEnd && obs.box.maxX < durationMinX
                        && !PlaylistFrameParser.isChrome(obs.text) && PlaylistFrameParser.duration(obs.text) == nil
                        && Int(obs.text) == nil && inRowBand(obs, 0.45)
                }
                .map(\.box.minX)
            guard let textMinX = Self.mode(lefts, bin: 0.006) else { return nil }
            let paneMinX = (numbers.map(\.box.minX).min() ?? textMinX - 0.08) - 0.005
            let columnHeader = observations.first {
                ["title", "# title"].contains($0.text.lowercased())
                    && $0.box.minX >= paneMinX && $0.box.maxX < durationMinX
            }
            self.observations = observations
            self.durations = durations
            self.rowHeight = rowHeight
            self.textHeight = textHeight
            self.textMinX = textMinX
            self.paneMinX = paneMinX
            self.paneMaxX = durations.map(\.obs.box.maxX).max() ?? 1
            self.columnHeader = columnHeader
            self.titleColumnMaxX = Self.titleColumnEnd(observations, header: columnHeader, durationMinX: durationMinX)
            self.listTopY = columnHeader?.box.maxY ?? ((durations.first?.obs.box.midY ?? 0) - rowHeight / 2)
        }

        /// Left edge of the first header label right of "Title" (other than "Artist").
        static func titleColumnEnd(
            _ observations: [ScanTextObservation],
            header: ScanTextObservation?,
            durationMinX: CGFloat
        ) -> CGFloat {
            guard let header else { return durationMinX }
            let labels = observations.filter {
                abs($0.box.midY - header.box.midY) < header.box.height && $0.box.minX > header.box.maxX
                    && $0.box.maxX < durationMinX && $0.text.lowercased() != "artist"
            }
            return (labels.map(\.box.minX).min() ?? durationMinX) - 0.004
        }

        /// The biggest set of durations sharing a right edge.
        static func largestColumn(_ timed: [DurationCell]) -> [DurationCell]? {
            let bin = { (cell: DurationCell) in
                Int((cell.obs.box.maxX / PlaylistFrameParser.durationColumnTolerance).rounded())
            }
            guard let best = Dictionary(grouping: timed, by: bin).max(by: { $0.value.count < $1.value.count }) else {
                return nil
            }
            // Neighbouring bins catch edges that straddle a boundary.
            return timed.filter { abs(bin($0) - best.key) <= 1 }
        }

        static func mode(_ values: [CGFloat], bin: CGFloat) -> CGFloat? {
            let groups = Dictionary(grouping: values) { Int(($0 / bin).rounded()) }
            // Most members wins; ties go to the leftmost bin.
            let best = groups.max { ($0.value.count, -$0.key) < ($1.value.count, -$1.key) }
            guard let best else { return nil }
            return best.value.min()
        }

        // MARK: Rows

        func rows(endY: CGFloat?) -> [ScannedRow] {
            let durationMinX = durations.map(\.obs.box.minX).min() ?? 1
            let textCells = observations.filter { obs in
                obs.box.minX >= textMinX - 0.006 && obs.box.maxX <= durationMinX
                    && obs.box.minX < titleColumnMaxX
                    && PlaylistFrameParser.duration(obs.text) == nil && !PlaylistFrameParser.isChrome(obs.text)
                    && obs.text.contains(where: { $0.isLetter || $0.isNumber })
            }
            let candidates = durations.filter { endY.map($0.obs.box.midY.isLess(than:)) ?? true }
            let bands = candidates.map { duration in
                (duration, textCells.filter { abs($0.box.midY - duration.obs.box.midY) < rowHeight * 0.5 })
            }
            // Compact view: most rows are one line (title and artist side by side).
            let singleLine = bands.filter { lines(of: $0.1).count == 1 }.count
            let compact = !bands.isEmpty && singleLine * 2 > bands.count
            var built: [RowCandidate] = []
            for (duration, cells) in bands {
                guard let row = compact
                    ? compactRow(duration: duration, cells: cells)
                    : normalRow(duration: duration, cells: cells) else { continue }
                let centre = duration.obs.box.midY
                built.append(RowCandidate(slotY: centre, number: readNumber(near: centre), row: row))
            }
            return numbered(built)
        }

        /// Two-line row: title above the duration's centre line, artist below.
        func normalRow(duration: DurationCell, cells: [ScanTextObservation]) -> ScannedRow? {
            let centre = duration.obs.box.midY
            let lines = lines(of: cells)
            guard let first = lines.first else { return nil }
            let titleLine: [ScanTextObservation]
            let artistLine: [ScanTextObservation]?
            if lines.count >= 2 {
                // A third, centred line (an album column with no header in view) sits
                // between them: the artist is the lowest line.
                titleLine = first
                artistLine = lines[lines.count - 1]
            } else if first[0].box.midY <= centre {
                titleLine = first    // bottom edge: artist cut off
                artistLine = nil
            } else {
                return nil           // top edge: title hidden under the sticky bar
            }
            return makeRow(duration: duration, title: titleLine, artist: artistLine)
        }

        /// Group cells into text lines, top to bottom, each sorted left to right.
        /// Cells share a line when their centres are within half a text height.
        func lines(of cells: [ScanTextObservation]) -> [[ScanTextObservation]] {
            var result: [[ScanTextObservation]] = []
            for cell in cells.sorted(by: { $0.box.midY < $1.box.midY }) {
                if let anchor = result.last?.first, cell.box.midY - anchor.box.midY < textHeight * 0.5 {
                    result[result.count - 1].append(cell)
                } else {
                    result.append([cell])
                }
            }
            return result.map { $0.sorted { $0.box.minX < $1.box.minX } }
        }

        /// One-line row: title cell at the text column, artist the next cell right.
        func compactRow(duration: DurationCell, cells: [ScanTextObservation]) -> ScannedRow? {
            let line = cells.sorted { $0.box.minX < $1.box.minX }
            guard let title = line.first else { return nil }
            return makeRow(duration: duration, title: [title], artist: line.count > 1 ? [line[1]] : nil)
        }

        func makeRow(
            duration: DurationCell,
            title: [ScanTextObservation],
            artist: [ScanTextObservation]?
        ) -> ScannedRow? {
            let display = { (cells: [ScanTextObservation]) in
                PlaylistFrameParser.clean(PlaylistFrameParser.stripBadges(cells.map(\.text).joined(separator: " ")))
            }
            let titleText = display(title)
            guard !titleText.text.isEmpty else { return nil }
            let artistText = artist.map(display)
            let cells = title + (artist ?? []) + [duration.obs]
            var confidence = cells.map(\.confidence).min() ?? 0
            if artistText == nil || artistText?.text.isEmpty == true { confidence *= 0.5 }
            return ScannedRow(
                number: 0,
                title: titleText.text,
                artist: artistText?.text ?? "",
                duration: duration.seconds,
                confidence: confidence,
                titleTruncated: titleText.truncated,
                artistTruncated: artistText?.truncated ?? false
            )
        }

        func readNumber(near centre: CGFloat) -> Int? {
            observations
                .filter {
                    $0.box.maxX < textMinX && $0.box.minX >= paneMinX - 0.001
                        && abs($0.box.midY - centre) < rowHeight * 0.3
                }
                .compactMap { Int($0.text.trimmingCharacters(in: .whitespaces)) }
                .first
        }

        /// Assign every row its number from vertical position + the modal
        /// (number − slot) offset, so a hovered (▶) or misread cell cannot
        /// break the sequence. Rows whose own reading disagrees lose confidence.
        func numbered(_ built: [RowCandidate]) -> [ScannedRow] {
            guard let top = built.first?.slotY else { return [] }
            let slots = built.map { Int((($0.slotY - top) / rowHeight).rounded()) }
            let offsets = zip(built, slots).compactMap { entry, slot in entry.number.map { $0 - slot } }
            let votes = Dictionary(grouping: offsets, by: { $0 })
            guard let offset = votes.max(by: { $0.value.count < $1.value.count })?.key else {
                return []   // no row number visible at all: position unknown
            }
            return zip(built, slots).compactMap { entry, slot in
                var row = entry.row
                row.number = slot + offset
                guard row.number >= 1 else { return nil }
                if entry.number != row.number { row.confidence *= 0.9 }
                return row
            }
        }
    }
}
