// SpotifyScanViewModelTests — SCAN.3/SCAN.4 (D-260): every Spotify-scan phase, driven by
// fakes — a scripted frame source (no ScreenCaptureKit), a fake Spotify app, a fake
// permission, a recording panel. No wall-clock waits: frames are awaited by condition
// (`settle`), which yields the main actor until the view model has consumed them (BUG-150).

import Combine
import Foundation
import Session
import Testing
@testable import UzumeApp

// MARK: - Fakes

@MainActor
private final class FakeSpotify: SpotifyAppControlling {
    var isRunning: Bool
    let changes = PassthroughSubject<Bool, Never>()
    var opened = 0
    var broughtToFront = 0
    init(running: Bool) { isRunning = running }
    var runningChanges: AnyPublisher<Bool, Never> { changes.eraseToAnyPublisher() }
    func open() { opened += 1 }
    func bringToFront() { broughtToFront += 1 }
    func set(running: Bool) {
        isRunning = running
        changes.send(running)
    }
}

private final class FakePermission: ScreenCapturePermissionProviding, @unchecked Sendable {
    var granted: Bool
    init(granted: Bool) { self.granted = granted }
    func isGranted() -> Bool { granted }
}

private final class ScriptedFrames: PlaylistFrameSource, @unchecked Sendable {
    private var continuation: AsyncThrowingStream<PlaylistScanFrame, Error>.Continuation?
    private(set) var stopped = 0
    func frames() -> AsyncThrowingStream<PlaylistScanFrame, Error> {
        AsyncThrowingStream { self.continuation = $0 }
    }
    func stop() {
        stopped += 1
        continuation?.finish()
    }
    func send(_ frame: PlaylistScanFrame) { continuation?.yield(frame) }
    func fail(_ error: Error) { continuation?.finish(throwing: error) }
}

@MainActor
private final class RecordingPanel: ScanPanelPresenting {
    var shown = 0
    var closed = 0
    func show(model: SpotifyScanViewModel) { shown += 1 }
    func close() { closed += 1 }
}

// MARK: - Helpers

private func rows(_ numbers: ClosedRange<Int>, cutOff: Bool = false) -> [ScannedRow] {
    numbers.map {
        ScannedRow(
            number: $0,
            title: "Song \($0)",
            artist: "Artist \($0)",
            duration: 200,
            confidence: 1,
            titleTruncated: cutOff
        )
    }
}

private func frame(_ numbers: ClosedRange<Int>, count: Int? = nil, name: String? = nil) -> PlaylistScanFrame {
    PlaylistScanFrame(rows: rows(numbers), songCount: count, playlistName: name)
}

@MainActor
private struct Harness {
    let spotify: FakeSpotify
    let permission: FakePermission
    let frames = ScriptedFrames()
    let panel = RecordingPanel()
    let vm: SpotifyScanViewModel
    var permissionRequests: Box

    final class Box { var value = 0 }

    init(running: Bool = true, granted: Bool = true, screenshots: [PlaylistScanFrame] = []) {
        let spotify = FakeSpotify(running: running)
        let permission = FakePermission(granted: granted)
        let frames = self.frames
        let requests = Box()
        self.spotify = spotify
        self.permission = permission
        self.permissionRequests = requests
        vm = SpotifyScanViewModel(
            spotify: spotify,
            permission: permission,
            requestPermission: { requests.value += 1 },
            makeFrameSource: { frames },
            readScreenshots: { _ in screenshots },
            panel: panel,
            bringUzumeToFront: {})
    }
}

/// Yield the main actor until `condition` holds (bounded; no wall clock).
@MainActor
private func settle(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
}

// MARK: - Tests

@Suite("SpotifyScanViewModel (SCAN.3/SCAN.4)")
@MainActor
struct SpotifyScanViewModelTests {

    // MARK: Start states

    @Test("Spotify not running → not-running phase; launching and quitting move between start states")
    func spotifyLifecycle() {
        let scan = Harness(running: false)
        #expect(scan.vm.phase == .spotifyNotRunning)
        scan.vm.openSpotify()
        #expect(scan.spotify.opened == 1, "Open Spotify only on the user's click")
        scan.spotify.set(running: true)
        #expect(scan.vm.phase == .ready)
        scan.spotify.set(running: false)
        #expect(scan.vm.phase == .spotifyNotRunning)
    }

    @Test("permission denied at scan start → explainer; no capture starts; granting returns to ready")
    func permissionDenied() {
        let scan = Harness(granted: false)
        scan.vm.startScan()
        #expect(scan.vm.phase == .needsPermission)
        #expect(scan.panel.shown == 0)
        scan.vm.allowAccess()
        #expect(scan.permissionRequests.value == 1)
        #expect(scan.vm.phase == .needsPermission, "still denied")
        scan.permission.granted = true
        scan.vm.refreshPermission()
        #expect(scan.vm.phase == .ready)
    }

    // MARK: Live scan

    @Test("scan start: panel shown, Spotify brought forward, live count follows the frames")
    func liveCount() async {
        let scan = Harness()
        scan.vm.startScan()
        #expect(scan.vm.phase == .scanning)
        #expect(scan.panel.shown == 1)
        #expect(scan.spotify.broughtToFront == 1)
        scan.frames.send(frame(1...5, count: 38, name: "Mix"))
        await settle { scan.vm.progress.found == 5 }
        #expect(scan.vm.progress.found == 5)
        #expect(scan.vm.progress.songCount == 38)
        #expect(ScanPanelView.count(scan.vm.progress) == "5 of 38 songs")
    }

    @Test("started mid-list → scroll-to-top prompt, cleared once row 1 is read")
    func startedMidList() async {
        let scan = Harness()
        scan.vm.startScan()
        scan.frames.send(frame(6...10))
        await settle { scan.vm.progress.found == 5 }
        #expect(scan.vm.progress.startedMidList)
        #expect(scan.vm.progress.missed == nil, "the unread top is the prompt, not a gap warning")
        scan.frames.send(frame(1...5))
        await settle { scan.vm.progress.found == 10 }
        #expect(!scan.vm.progress.startedMidList)
    }

    @Test("fast scroll skips rows → numbered warning; scrolling back fills the gap")
    func gapAndScrollBack() async {
        let scan = Harness()
        scan.vm.startScan()
        scan.frames.send(frame(1...5, count: 20))
        scan.frames.send(frame(9...13))
        await settle { scan.vm.progress.found == 10 }
        #expect(scan.vm.progress.missed == ScanGap(first: 6, last: 8))
        scan.frames.send(frame(5...9))
        await settle { scan.vm.progress.found == 13 }
        #expect(scan.vm.progress.missed == nil)
    }

    @Test("every song in the header count read → finishes by itself into review")
    func autoComplete() async {
        let scan = Harness()
        scan.vm.startScan()
        scan.frames.send(frame(1...6, count: 10, name: "Mix"))
        scan.frames.send(frame(5...10))
        await settle { scan.vm.phase == .review }
        #expect(scan.vm.phase == .review)
        #expect(scan.vm.reviewRows.count == 10)
        #expect(scan.vm.reviewName == "Mix")
        #expect(scan.frames.stopped >= 1, "capture stops when the scan completes")
        #expect(scan.panel.closed >= 1)
    }

    @Test("Done mid-scan → review with the missing numbers listed")
    func doneEarly() async {
        let scan = Harness()
        scan.vm.startScan()
        scan.frames.send(frame(1...5, count: 8))
        await settle { scan.vm.progress.found == 5 }
        scan.vm.finishScan()
        #expect(scan.vm.phase == .review)
        #expect(scan.vm.reviewMissing == [ScanGap(first: 6, last: 8)])
        #expect(ScanReviewView.describe(scan.vm.reviewMissing) == "6–8")
    }

    @Test("Done before anything was read → back to start with a notice")
    func doneWithNothing() {
        let scan = Harness()
        scan.vm.startScan()
        scan.vm.finishScan()
        #expect(scan.vm.phase == .ready)
        #expect(scan.vm.notice == .nothingRead)
    }

    @Test("Cancel / Esc → back to the Spotify view, capture stopped, nothing kept")
    func cancel() async {
        let scan = Harness()
        scan.vm.startScan()
        scan.frames.send(frame(1...5))
        await settle { scan.vm.progress.found == 5 }
        scan.vm.cancelScan()
        #expect(scan.vm.phase == .ready)
        #expect(scan.vm.reviewRows.isEmpty)
        #expect(scan.frames.stopped >= 1)
        #expect(scan.panel.closed >= 1)
    }

    @Test("Spotify quits mid-scan → stops immediately, not-running phase, notice")
    func spotifyQuitsMidScan() async {
        let scan = Harness()
        scan.vm.startScan()
        scan.frames.send(frame(1...5))
        await settle { scan.vm.progress.found == 5 }
        scan.spotify.set(running: false)
        #expect(scan.vm.phase == .spotifyNotRunning)
        #expect(scan.vm.notice == .spotifyClosedDuringScan)
        #expect(scan.frames.stopped >= 1)
    }

    @Test("the capture ending with an error → back to start with the matching notice")
    func captureErrors() async {
        let closed = Harness()
        closed.vm.startScan()
        closed.frames.fail(SpotifyScanError.spotifyClosed)
        await settle { closed.vm.phase != .scanning }
        #expect(closed.vm.notice == .spotifyClosedDuringScan)
        let hidden = Harness()
        hidden.vm.startScan()
        hidden.frames.fail(SpotifyScanError.windowUnavailable)
        await settle { hidden.vm.phase != .scanning }
        #expect(hidden.vm.phase == .ready)
        #expect(hidden.vm.notice == .windowUnavailable)
    }

    // MARK: Screenshots

    @Test("dropped screenshots → reading → review")
    func screenshotsToReview() async {
        let scan = Harness(screenshots: [frame(1...4, count: 6, name: "Mix"), frame(4...6)])
        scan.vm.importScreenshots([URL(fileURLWithPath: "/tmp/a.png")])
        #expect(scan.vm.phase == .readingScreenshots)
        await settle { scan.vm.phase == .review }
        #expect(scan.vm.reviewRows.map(\.number) == Array(1...6))
        #expect(ScanReviewView.heading(count: 6, name: "Mix") == "Found 6 songs from Mix")
    }

    @Test("screenshots with no playlist in them → notice, back where the user was")
    func screenshotsWithNothing() async {
        let scan = Harness(running: false)
        scan.vm.importScreenshots([URL(fileURLWithPath: "/tmp/a.png")])
        await settle { scan.vm.phase != .readingScreenshots }
        #expect(scan.vm.phase == .spotifyNotRunning)
        #expect(scan.vm.notice == .nothingInScreenshots)
    }

    // MARK: Review

    @Test("review: fix a row, remove a row, Continue hands the list over as a Spotify scan")
    func reviewEditsAndContinue() async {
        let scan = Harness(screenshots: [frame(1...3, count: 3, name: "Mix")])
        scan.vm.importScreenshots([URL(fileURLWithPath: "/tmp/a.png")])
        await settle { scan.vm.phase == .review }
        scan.vm.updateRow(number: 2, title: "  Song Two (Full)  ", artist: "Artist Two")
        #expect(scan.vm.reviewRows[1].title == "Song Two (Full)")
        #expect(!scan.vm.reviewRows[1].titleTruncated)
        scan.vm.updateRow(number: 2, title: "   ", artist: "x")
        #expect(scan.vm.reviewRows[1].title == "Song Two (Full)", "an empty title is ignored")
        scan.vm.removeRow(number: 3)
        #expect(scan.vm.reviewRows.map(\.number) == [1, 2])

        let captured = CapturedStart()
        await scan.vm.continueToPreparation { tracks, source in await captured.set(tracks, source) }
        let (tracks, source) = await captured.value
        #expect(tracks.map(\.title) == ["Song 1", "Song Two (Full)"])
        guard case .spotifyScan(let name)? = source else {
            Issue.record("expected .spotifyScan, got \(String(describing: source))")
            return
        }
        #expect(name == "Mix")
        #expect(source?.isSpotify == true)
    }

    @Test("Scan again → straight into a new live scan")
    func scanAgain() async {
        let scan = Harness(screenshots: [frame(1...3)])
        scan.vm.importScreenshots([URL(fileURLWithPath: "/tmp/a.png")])
        await settle { scan.vm.phase == .review }
        scan.vm.scanAgain()
        #expect(scan.vm.phase == .scanning)
        #expect(scan.vm.reviewRows.isEmpty)
    }

    @Test("panel copy: count without a header, singulars")
    func panelCopy() {
        #expect(ScanPanelView.count(.init(found: 27)) == "27 songs")
        #expect(ScanPanelView.count(.init(found: 1)) == "1 song")
        #expect(ScanReviewView.heading(count: 38, name: nil) == "Found 38 songs")
        #expect(ScanReviewView.describe([ScanGap(first: 14, last: 16), ScanGap(first: 22, last: 22)]) == "14–16, 22")
    }
}

// MARK: - Capture helper

private actor CapturedStart {
    var value: ([TrackIdentity], PlaylistSource?) = ([], nil)
    func set(_ tracks: [TrackIdentity], _ source: PlaylistSource) { value = (tracks, source) }
}
