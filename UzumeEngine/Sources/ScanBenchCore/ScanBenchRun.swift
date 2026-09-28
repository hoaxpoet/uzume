// ScanBenchRun — SCAN.0 evaluation core (D-260), shared by the `ScanBench` CLI and the
// fixture-gated `PlaylistScanFixtureTests`, so the test reproduces the bench's numbers
// with the same code rather than a copy.
//
// For one fixture playlist folder (full-window Spotify screenshots + one Exportify CSV
// as ground truth): read every capture with the production `PlaylistScreenReader`, merge
// with `PlaylistScanAccumulator`, then resolve BOTH the scanned rows and the ground truth
// through the real `PreviewResolver` and compare. Metric definitions:
// docs/diagnostics/SCAN_FEASIBILITY_2026-09-28.md.

import AppKit
import Foundation
import Session

// MARK: - Reading mode

/// How each capture is read.
public enum ScanReadingMode: String, Sendable {
    /// Production: find the list pane once, then read the pane only.
    case reader
    /// The whole window, every capture.
    case whole
    /// Whole window and pane, both merged.
    case both
}

// MARK: - Results

/// One row that was not simply identified.
public struct ScanBenchOutcome: Sendable {
    /// Playlist row number.
    public let number: Int
    /// "title — artist" from the CSV.
    public let truth: String
    /// What the scan read.
    public let scanned: String
    /// Outcome label.
    public let verdict: String
    /// What each side resolved to.
    public let detail: String

    init(_ number: Int, _ truth: String, _ scanned: String, _ verdict: String, _ detail: String) {
        self.number = number
        self.truth = truth
        self.scanned = scanned
        self.verdict = verdict
        self.detail = detail
    }
}

/// Everything measured on one playlist.
public struct ScanBenchResult: Sendable {
    /// Folder name.
    public var name: String
    /// Rows in the CSV.
    public var truthCount = 0
    /// Header "N songs", when read.
    public var songCountRead: Int?
    /// Playlist name, when read.
    public var playlistNameRead: String?
    /// Per-capture read time (ms).
    public var frameMillis: [Double] = []
    /// Coverage counts.
    public var found = 0, gapReported = 0, silentMiss = 0
    /// Resolution counts (see the feasibility doc for definitions).
    public var truthNoPreview = 0, identified = 0, wrong = 0, unresolved = 0
    /// Strict identification + the "ground truth resolves elsewhere" exclusion.
    public var strictIdentified = 0, truthElsewhere = 0, truthElsewhereScanRight = 0
    /// Rows that were not simply identified, in playlist order.
    public var failures: [ScanBenchOutcome] = []

    /// Create an empty result.
    public init(name: String) { self.name = name }

    /// Rows judged for identification / wrong song.
    public var judged: Int { found - truthNoPreview - truthElsewhere }
    /// Rows judged for the strict figure.
    public var strictJudged: Int { found - truthNoPreview }
}

// MARK: - Evaluation

/// Evaluate one fixture playlist folder.
public func evaluateScanFixture(
    folder: URL, cache: ScanBenchResponseCache, mode: ScanReadingMode = .reader
) async throws -> ScanBenchResult {
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    guard let csvURL = files.first(where: { $0.pathExtension.lowercased() == "csv" }) else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: folder.appendingPathComponent("*.csv").path])
    }
    let truth = groundTruth(csv: try String(contentsOf: csvURL, encoding: .utf8))
    let images = files.filter { $0.pathExtension.lowercased() == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var result = ScanBenchResult(name: folder.lastPathComponent)
    result.truthCount = truth.count
    let scan = try read(images, mode: mode, millis: &result.frameMillis)
    result.songCountRead = scan.songCount
    result.playlistNameRead = scan.playlistName

    let resolver = PreviewResolver(rateLimiter: ITunesRateLimiter(maxRequestsPerWindow: 1_000_000))
    resolver.networkFetcher = { try await cache.fetch($0) }
    let gaps = Set(scan.gaps.flatMap { $0.first...$0.last })
    for (index, track) in truth.enumerated() {
        let number = index + 1
        guard let row = scan.rowsByNumber[number] else {
            recordMissing(number: number, track: track, reported: gaps.contains(number), into: &result)
            continue
        }
        result.found += 1
        try await judge(row: row, truth: track, resolver: resolver, into: &result)
    }
    return result
}

/// CSV rows → identities the way the Spotify Web API connector builds them (first artist).
func groundTruth(csv: String) -> [TrackIdentity] {
    parseCSV(csv).map { record in
        let artists = record["Artist Name(s)"] ?? ""
        let first = (artists.components(separatedBy: ",").first ?? artists).trimmingCharacters(in: .whitespaces)
        let millis = Double(record["Track Duration (ms)"] ?? "") ?? 0
        return TrackIdentity(title: record["Track Name"] ?? "", artist: first, duration: millis / 1000)
    }
}

private func read(
    _ images: [URL],
    mode: ScanReadingMode,
    millis: inout [Double]
) throws -> PlaylistScanAccumulator {
    let reader = PlaylistScreenReader()
    let recognizer = PlaylistFrameRecognizer()
    let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    var scan = PlaylistScanAccumulator()
    for file in images {
        let loaded = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        guard let image = loaded else { continue }
        let start = DispatchTime.now().uptimeNanoseconds
        switch mode {
        case .reader:
            scan.add(try reader.read(image))
        case .whole:
            scan.add(PlaylistFrameParser.parse(try recognizer.recognize(image, in: whole)))
        case .both:
            let wholeFrame = PlaylistFrameParser.parse(try recognizer.recognize(image, in: whole))
            scan.add(wholeFrame)
            if let pane = wholeFrame.listRegion {
                scan.add(PlaylistFrameParser.parse(try recognizer.recognize(image, in: pane)))
            }
        }
        millis.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }
    return scan
}

private func recordMissing(number: Int, track: TrackIdentity, reported: Bool, into result: inout ScanBenchResult) {
    if reported { result.gapReported += 1 } else { result.silentMiss += 1 }
    let verdict = reported ? "gap (reported)" : "SILENT MISS"
    result.failures.append(ScanBenchOutcome(number, "\(track.title) — \(track.artist)", "—", verdict, ""))
}

private func judge(
    row: ScannedRow,
    truth: TrackIdentity,
    resolver: PreviewResolver,
    into result: inout ScanBenchResult
) async throws {
    let truthLabel = "\(truth.title) — \(truth.artist)"
    let scanned = "\(row.title)\(row.titleTruncated ? "…" : "") — \(row.artist)"
    guard let truthMatch = try await resolver.resolvePreviewMatch(for: truth) else {
        result.truthNoPreview += 1
        return
    }
    let scanMatch = try await resolver.resolvePreviewMatch(for: row.trackIdentity)
    let strictSame = scanMatch.map { isSameSong($0, truthMatch) } ?? false
    if strictSame { result.strictIdentified += 1 }
    guard isSong(truthMatch, title: truth.title, artist: truth.artist) else {
        // The reference itself lands on another song: no valid reference to judge against.
        result.truthElsewhere += 1
        let scanRight = scanMatch.map { isSong($0, title: truth.title, artist: truth.artist) } ?? false
        if scanRight { result.truthElsewhereScanRight += 1 }
        let detail = "truth → \(describe(truthMatch)); scan → \(describe(scanMatch))\(scanRight ? " (right song)" : "")"
        result.failures.append(ScanBenchOutcome(row.number, truthLabel, scanned, "truth resolves elsewhere", detail))
        return
    }
    // Identified: the reference's track, or exactly the playlist's own song when the
    // reference lookup picked another version (e.g. a remix of an original).
    if strictSame || scanMatch.map({ isExactly($0, title: truth.title, artist: truth.artist) }) == true {
        result.identified += 1
    } else if let scanMatch {
        result.wrong += 1
        let detail = "scan → \(describe(scanMatch)); truth → \(describe(truthMatch))"
        result.failures.append(ScanBenchOutcome(row.number, truthLabel, scanned, "WRONG SONG", detail))
    } else {
        result.unresolved += 1
        let detail = "truth → \(describe(truthMatch))"
        result.failures.append(ScanBenchOutcome(row.number, truthLabel, scanned, "not identified", detail))
    }
}

// MARK: - Song comparison

/// Same recording: same preview, or the catalog's same title and artist
/// (a single and its album release carry different preview URLs).
func isSameSong(_ lhs: PreviewMatch, _ rhs: PreviewMatch) -> Bool {
    lhs.previewURL == rhs.previewURL
        || (TrackNameKey.normalize(lhs.catalogTitle ?? "") == TrackNameKey.normalize(rhs.catalogTitle ?? "")
            && TrackNameKey.normalize(lhs.catalogArtist ?? "") == TrackNameKey.normalize(rhs.catalogArtist ?? ""))
}

/// Does a match name the song asked for (title before any version suffix + primary artist)?
func isSong(_ match: PreviewMatch, title: String, artist: String) -> Bool {
    TrackNameKey.baseTitle(match.catalogTitle ?? "") == TrackNameKey.baseTitle(title)
        && TrackNameKey.artistsMatch(artist, match.catalogArtist ?? "")
}

/// Is a match exactly this song — full title (ignoring "feat." credits) and primary artist?
func isExactly(_ match: PreviewMatch, title: String, artist: String) -> Bool {
    let bare = { (text: String) -> String in
        TrackNameKey.normalize(text.replacingOccurrences(
            of: #"\s*[\(\[](feat|with)\.?[^\)\]]*[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive]))
    }
    return bare(match.catalogTitle ?? "") == bare(title) && TrackNameKey.artistsMatch(artist, match.catalogArtist ?? "")
}

func describe(_ match: PreviewMatch?) -> String {
    match.map { "\($0.catalogTitle ?? "?") — \($0.catalogArtist ?? "?")" } ?? "(no match)"
}

// MARK: - CSV (RFC 4180, header-keyed)

/// Parse CSV text into header-keyed records. Quoted fields may hold commas, quotes, newlines.
public func parseCSV(_ text: String) -> [[String: String]] {
    var parser = CSVState()
    for char in text.replacingOccurrences(of: "\u{FEFF}", with: "") { parser.consume(char) }
    let records = parser.finish()
    guard let header = records.first else { return [] }
    return records.dropFirst()
        .filter { $0.count == header.count }
        .map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
}

private struct CSVState {
    var records: [[String]] = []
    var field = ""
    var record: [String] = []
    var quoted = false
    var pendingQuote = false

    mutating func consume(_ char: Character) {
        if pendingQuote {
            pendingQuote = false
            if char == "\"" { field.append(char); return }   // "" inside quotes
            quoted = false
        }
        if quoted {
            if char == "\"" { pendingQuote = true } else { field.append(char) }
            return
        }
        switch char {
        case "\"": quoted = true
        case ",": endField()
        case "\n", "\r\n": endField(); endRecord()
        default: field.append(char)
        }
    }

    mutating func finish() -> [[String]] {
        if !field.isEmpty || !record.isEmpty { endField(); endRecord() }
        return records
    }

    private mutating func endField() {
        record.append(field)
        field = ""
    }

    private mutating func endRecord() {
        records.append(record)
        record = []
    }
}
