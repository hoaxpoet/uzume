// PlaylistScanLogicTests — SCAN.1 (D-260) parser + accumulator logic, CI-safe.
//
// Drives `PlaylistFrameParser` / `PlaylistScanAccumulator` with SYNTHETIC recorded
// Vision observations (`Fixtures/playlist_scan/*.json`: strings + normalized
// top-left boxes, authored to the geometry of a real full-window Spotify capture;
// no real library content). No Vision, no images, no network — on the CI allow-list.
// The real-screenshot half is `PlaylistScanFixtureTests` (fixture-gated, not in CI).

import CoreGraphics
import Foundation
import Testing
@testable import Session

// MARK: - Fixture loading

private func frames(_ name: String) throws -> [[ScanTextObservation]] {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "playlist_scan"),
        "playlist_scan/\(name).json not bundled")
    return try JSONDecoder().decode([[ScanTextObservation]].self, from: Data(contentsOf: url))
}

private func parsed(_ name: String) throws -> [PlaylistScanFrame] {
    try frames(name).map(PlaylistFrameParser.parse)
}

// MARK: - Row assembly

@Suite("PlaylistScan — row assembly (SCAN.1)")
struct PlaylistScanRowAssemblyTests {

    @Test("header frame: count, wrapped name, numbered rows; sidebar/now-playing/player bar ignored")
    func headerFrame() throws {
        let frame = try #require(try parsed("frames_normal").first)
        #expect(frame.songCount == 12)
        #expect(frame.playlistName == "TC 98 2026.01.01 Somewhere")
        #expect(!frame.reachedEnd)
        #expect(frame.rows.map(\.number) == [1, 2, 3, 4, 5, 6])
        let titles = frame.rows.map(\.title)
        #expect(!titles.contains("Superstition"), "Now Playing panel leaked into the list")
        #expect(!titles.contains("TC 98 2026.01.01 Somewhere"), "sidebar leaked into the list")
        #expect(frame.rows.first?.duration == 335)
    }

    @Test("hovered row: number inferred from its neighbours, duration read through the ⋯ button")
    func hoveredRow() throws {
        let row = try #require(try parsed("frames_normal")[0].rows.first { $0.number == 4 })
        #expect(row.title == "Glass Hours")
        #expect(row.duration == 131)
        #expect(row.confidence < 1, "an inferred number is marked less certain")
    }

    @Test("badges stripped, lone | read as I, diacritics and punctuation preserved")
    func textCleanup() throws {
        let all = try parsed("frames_normal").flatMap(\.rows)
        let byNumber = Dictionary(all.map { ($0.number, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        #expect(byNumber[3]?.title == "What I Can Do")
        #expect(byNumber[3]?.artist == "CØNTRA, Saturna")
        #expect(byNumber[4]?.artist == "Nilüfer Yanya", "explicit badge E not stripped")
        #expect(byNumber[5]?.artist == "K.Flay, Aire Atlantica", "video badge not stripped")
        #expect(byNumber[6]?.title == "Fantôme X")
        #expect(byNumber[8]?.title == "It´s Up There")
        #expect(byNumber[11]?.artist == "ROSALÍA")
        #expect(byNumber[12]?.duration == 4050, "h:mm:ss durations")
    }

    @Test("truncated titles and artists: ellipsis removed and flagged")
    func truncation() throws {
        let all = try parsed("frames_normal").flatMap(\.rows)
        let row2 = try #require(all.first { $0.number == 2 })
        #expect(row2.title == "Is It Because You Kn")
        #expect(row2.titleTruncated)
        #expect(!row2.artistTruncated)
        let row7 = try #require(all.first { $0.number == 7 })
        #expect(row7.title == "Oh No :: He Said Wh")
        let row10 = try #require(all.first { $0.number == 10 })
        #expect(row10.artist == "Lambert, Marie-Claire")
        #expect(row10.artistTruncated)
        #expect(all.first { $0.number == 1 }?.titleTruncated == false)
    }

    @Test("partial rows: bottom edge keeps the title at half confidence; top edge (title hidden) is dropped")
    func partialRows() throws {
        let frames = try parsed("frames_normal")
        let bottom = try #require(frames[0].rows.first { $0.number == 6 })
        #expect(bottom.artist.isEmpty)
        #expect(bottom.isUnsure)
        #expect(!frames[1].rows.contains { $0.number == 5 }, "a row whose title is hidden must not be read")
        #expect(frames[1].playlistName == "TC 98 2026.01.01 Somewhere", "sticky-bar name")
    }

    @Test("Recommended shelf ends the list; its rows are not playlist rows")
    func recommendedShelf() throws {
        let frame = try parsed("frames_normal")[2]
        #expect(frame.reachedEnd)
        #expect(frame.rows.map(\.number) == [10, 11, 12])
        #expect(!frame.rows.contains { $0.title == "Gimme Some" })
    }

    @Test("compact view: title and artist from side-by-side columns")
    func compactView() throws {
        let frame = try #require(try parsed("frame_compact").first)
        #expect(frame.rows.map(\.number) == Array(3...8))
        let row5 = try #require(frame.rows.first { $0.number == 5 })
        #expect(row5.title == "Blood In The Cut - Ai")
        #expect(row5.artist == "K.Flay, Aire Atlantica")
        #expect(!frame.rows.contains { $0.artist == "Some Album" }, "album column read as artist")
    }

    @Test("wide window: Album / Date added columns, an open context menu, and sidebar rows aligned with the list")
    func albumColumn() throws {
        let frame = try #require(try parsed("frame_album_column").first)
        #expect(frame.rows.map(\.number) == Array(1...5))
        #expect(frame.rows.map(\.artist) == ["Ada Vale", "Len Morrow", "CØNTRA, Saturna", "Nilüfer Yanya",
                                              "K.Flay, Aire Atlantica"])
        #expect(!frame.rows.contains { $0.title.contains("Remove from") || $0.artist.contains("Album") })
    }

    @Test("header without a song count: name read, count nil")
    func headerWithoutCount() throws {
        let frame = try #require(try parsed("frame_header_no_count").first)
        #expect(frame.songCount == nil)
        #expect(frame.playlistName == "Night Drive")
        #expect(frame.rows.map(\.number) == [1, 2, 3])
    }

    @Test("no track list on screen → empty frame")
    func noList() {
        let frame = PlaylistFrameParser.parse([
            ScanTextObservation(text: "Home", confidence: 1, box: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.02))
        ])
        #expect(frame.rows.isEmpty)
    }

    @Test("song count parsing")
    func songCounts() {
        #expect(PlaylistFrameParser.songCount(in: "40 songs, 2 hr 57 min") == 40)
        #expect(PlaylistFrameParser.songCount(in: "1 song, 3 min") == 1)
        #expect(PlaylistFrameParser.songCount(in: "1,204 songs, about 80 hr") == 1204)
        #expect(PlaylistFrameParser.songCount(in: "Tai Zhang • 9 saves") == nil)
    }
}

// MARK: - Merge, dedupe, gaps

@Suite("PlaylistScan — merge, dedupe, gaps (SCAN.1)")
struct PlaylistScanAccumulatorTests {

    @Test("overlapping frames merge to the full playlist; complete readings beat edge ones")
    func mergeAll() throws {
        var scan = PlaylistScanAccumulator()
        for frame in try parsed("frames_normal") { scan.add(frame) }
        #expect(scan.rows.map(\.number) == Array(1...12))
        #expect(scan.gaps.isEmpty)
        #expect(scan.isComplete)
        #expect(scan.rowsByNumber[6]?.artist == "Scratch Massive", "cut-off reading of row 6 won")
        #expect(scan.playlistName == "TC 98 2026.01.01 Somewhere")
        #expect(scan.firstNumberSeen == 1)
    }

    @Test("skipped frame → numbered gap, not a silent miss")
    func gapDetection() throws {
        let all = try parsed("frames_normal")
        var scan = PlaylistScanAccumulator()
        scan.add(all[0])
        scan.add(all[2])
        #expect(scan.gaps == [ScanGap(first: 7, last: 9)])
        #expect(!scan.isComplete)
        scan.add(all[1])
        #expect(scan.gaps.isEmpty, "scrolling back fills the gap")
    }

    @Test("gap at the end, before the list's end was seen, runs to the header count")
    func trailingGap() throws {
        var scan = PlaylistScanAccumulator()
        scan.add(try parsed("frames_normal")[0])
        #expect(scan.expectedCount == 12)
        #expect(scan.gaps == [ScanGap(first: 7, last: 12)])
    }

    @Test("started mid-list: first number seen is not 1, and rows above are a gap")
    func startedMidList() throws {
        var scan = PlaylistScanAccumulator()
        scan.add(try parsed("frames_normal")[1])
        #expect(scan.firstNumberSeen == 6)
        #expect(scan.gaps.first == ScanGap(first: 1, last: 5))
    }

    @Test("no header count: the list's end sets the expected count")
    func countFromEnd() throws {
        var scan = PlaylistScanAccumulator()
        let all = try parsed("frames_normal")
        scan.add(all[1])
        scan.add(all[2])
        #expect(scan.songCount == nil)
        #expect(scan.expectedCount == 12)
        #expect(scan.gaps == [ScanGap(first: 1, last: 5)])
    }

    @Test("higher-confidence reading of a row wins; rows past the header count are dropped")
    func dedupe() {
        var scan = PlaylistScanAccumulator()
        scan.add(PlaylistScanFrame(rows: [ScannedRow(number: 2, title: "Nikk1", artist: "A", confidence: 0.5)], songCount: 2))
        scan.add(PlaylistScanFrame(rows: [
            ScannedRow(number: 2, title: "Nikki", artist: "A", confidence: 1),
            ScannedRow(number: 3, title: "Ghost", artist: "B", confidence: 1)
        ]))
        scan.add(PlaylistScanFrame(rows: [ScannedRow(number: 2, title: "Nikkl", artist: "A", confidence: 0.9)]))
        #expect(scan.rowsByNumber[2]?.title == "Nikki")
        #expect(scan.rowsByNumber[3] == nil)
        #expect(scan.gaps == [ScanGap(first: 1, last: 1)])
    }
}

// MARK: - Row → TrackIdentity

@Suite("PlaylistScan — row → TrackIdentity (SCAN.2)")
struct PlaylistScanIdentityTests {

    @Test("cut-off title drops its partial last word and any dangling separator")
    func searchTitle() {
        let cut = ScannedRow(number: 1, title: "Is It Because You Kn", artist: "Len", confidence: 1, titleTruncated: true)
        #expect(cut.searchTitle == "Is It Because You")
        let dangling = ScannedRow(number: 1, title: "Summer & Smoke -", artist: "C", confidence: 1, titleTruncated: true)
        #expect(dangling.searchTitle == "Summer & Smoke")
        let remix = ScannedRow(number: 1, title: "Blood In The Cut - Ai", artist: "K", confidence: 1, titleTruncated: true)
        #expect(remix.searchTitle == "Blood In The Cut")
        let whole = ScannedRow(number: 1, title: "Oh No :: He Said What?", artist: "N", confidence: 1)
        #expect(whole.searchTitle == "Oh No :: He Said What?")
    }

    @Test("artist: first credited, matching the Spotify Web API connector; a cut-off sole artist loses its last word")
    func searchArtist() {
        let many = ScannedRow(number: 1, title: "T", artist: "Xinobi, Gisela João", confidence: 1)
        #expect(many.searchArtist == "Xinobi")
        let cutSecond = ScannedRow(number: 1, title: "T", artist: "Lambert, Marie-Claire", confidence: 1, artistTruncated: true)
        #expect(cutSecond.searchArtist == "Lambert")
        let cutSole = ScannedRow(number: 1, title: "T", artist: "Joan Jett & the Blackh", confidence: 1, artistTruncated: true)
        #expect(cutSole.searchArtist == "Joan Jett")
    }

    @Test("identity carries search title, first artist and the read duration")
    func identity() {
        let row = ScannedRow(number: 4, title: "Glass Hours", artist: "Nilüfer Yanya, X", duration: 131, confidence: 1)
        #expect(row.trackIdentity == TrackIdentity(title: "Glass Hours", artist: "Nilüfer Yanya", duration: 131))
    }
}
