// SpotifyScanViewModel — the Spotify view's state machine: scan a playlist from the
// screen or from dropped screenshots, review it, hand it to preparation (SCAN, D-260).
//
// UX contract: UX_SPEC §4.4. Phases:
//   spotifyNotRunning → "Open Spotify and go to the playlist you want."
//   ready             → Start scan / drop screenshots
//   needsPermission   → scan-specific screen-reading explainer + Allow Access
//   scanning          → floating panel beside Spotify; live count, prompts, gaps
//   readingScreenshots→ dropped images being read
//   review            → the list; fix / remove rows; Scan again; Continue
// A `notice` carries the one-line reason the flow came back to a start state.

import AppKit
import Combine
import Foundation
import Session

// MARK: - SpotifyScanViewModel

@MainActor
final class SpotifyScanViewModel: ObservableObject {

    // MARK: Types

    enum Phase: Equatable {
        case spotifyNotRunning
        case ready
        case needsPermission
        case scanning
        case readingScreenshots
        case review
    }

    /// Why the flow returned to a start state. Every notice sits next to the action that fixes it.
    enum Notice: Equatable {
        case spotifyClosedDuringScan
        case windowUnavailable
        case nothingInScreenshots
        case nothingRead
    }

    /// What the scan panel shows.
    struct Progress: Equatable {
        var found = 0
        var songCount: Int?
        /// The first run of skipped rows above the furthest row read.
        var missed: ScanGap?
        /// The first row seen wasn't #1 and #1 hasn't been read.
        var startedMidList = false
        // No "widen the window" tip: SCAN.0 measured cut-off titles resolving 25/26 once
        // resolution is verified, so the contract's conditional tip is left out.
    }

    // MARK: Published

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var notice: Notice?
    @Published private(set) var progress = Progress()
    @Published private(set) var reviewRows: [ScannedRow] = []
    @Published private(set) var reviewName: String?
    @Published private(set) var reviewMissing: [ScanGap] = []

    // MARK: Dependencies

    private let spotify: any SpotifyAppControlling
    private let permission: any ScreenCapturePermissionProviding
    private let requestPermission: () -> Void
    private let makeFrameSource: () -> any PlaylistFrameSource
    private let readScreenshots: ([URL]) async -> [PlaylistScanFrame]
    private let panel: (any ScanPanelPresenting)?
    private let bringUzumeToFront: () -> Void

    // MARK: State

    private var scan = PlaylistScanAccumulator()
    private var source: (any PlaylistFrameSource)?
    private var scanTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init(
        spotify: any SpotifyAppControlling,
        permission: any ScreenCapturePermissionProviding = SystemScreenCapturePermissionProvider(),
        requestPermission: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() },
        makeFrameSource: @escaping () -> any PlaylistFrameSource = { SpotifyWindowFrameSource() },
        readScreenshots: @escaping ([URL]) async -> [PlaylistScanFrame] = PlaylistScreenshotReader.read,
        panel: (any ScanPanelPresenting)? = nil,
        bringUzumeToFront: @escaping () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    ) {
        self.spotify = spotify
        self.permission = permission
        self.requestPermission = requestPermission
        self.makeFrameSource = makeFrameSource
        self.readScreenshots = readScreenshots
        self.panel = panel
        self.bringUzumeToFront = bringUzumeToFront
        phase = spotify.isRunning ? .ready : .spotifyNotRunning
        spotify.runningChanges
            .sink { [weak self] running in self?.spotifyRunningChanged(running) }
            .store(in: &cancellables)
    }

    // MARK: Start states

    /// "Open Spotify" — the user asked; never automatic.
    func openSpotify() {
        spotify.open()
    }

    /// Re-read permission on app foreground (return from System Settings, UX_SPEC §3.2).
    func refreshPermission() {
        if phase == .needsPermission, permission.isGranted() { phase = .ready }
    }

    /// "Allow Access" — registers Uzume and shows the system prompt (same mechanics as §3.2).
    func allowAccess() {
        requestPermission()
        refreshPermission()
    }

    // MARK: Live scan

    /// "Start scan". Checks permission at scan start, not only at onboarding.
    func startScan() {
        guard spotify.isRunning else {
            phase = .spotifyNotRunning
            return
        }
        guard permission.isGranted() else {
            phase = .needsPermission
            return
        }
        notice = nil
        scan = PlaylistScanAccumulator()
        progress = Progress()
        phase = .scanning
        panel?.show(model: self)
        spotify.bringToFront()
        let source = makeFrameSource()
        self.source = source
        let frames = source.frames()
        scanTask = Task { [weak self] in
            do {
                for try await frame in frames {
                    guard let self, self.phase == .scanning else { return }
                    self.apply(frame)
                    if self.scan.isComplete {
                        self.finishScan()
                        return
                    }
                }
            } catch let error as SpotifyScanError {
                self?.abandonScan(error == .spotifyClosed ? .spotifyClosedDuringScan : .windowUnavailable)
            } catch {
                self?.abandonScan(.windowUnavailable)
            }
        }
    }

    /// "Done" — always available. Stops reading and shows what was found.
    func finishScan() {
        guard phase == .scanning else { return }
        stopCapture()
        bringUzumeToFront()
        if scan.rows.isEmpty {
            phase = spotify.isRunning ? .ready : .spotifyNotRunning
            notice = .nothingRead
        } else {
            enterReview(scan)
        }
    }

    /// "Cancel" / Esc — back to the Spotify view, nothing kept.
    func cancelScan() {
        guard phase == .scanning else { return }
        stopCapture()
        bringUzumeToFront()
        phase = spotify.isRunning ? .ready : .spotifyNotRunning
    }

    private func apply(_ frame: PlaylistScanFrame) {
        guard scan.add(frame) else { return }
        let maxRead = scan.rowsByNumber.keys.max() ?? 0
        let startedMidList = (scan.firstNumberSeen ?? 1) > 1 && scan.rowsByNumber[1] == nil
        progress = Progress(
            found: scan.rowsByNumber.count,
            songCount: scan.songCount,
            // Rows skipped above the furthest one read. The unread top of a list
            // started mid-way is the "scroll to the top" prompt instead.
            missed: scan.gaps.first { $0.last < maxRead && !(startedMidList && $0.first == 1) },
            startedMidList: startedMidList
        )
    }

    private func abandonScan(_ reason: Notice) {
        guard phase == .scanning else { return }
        stopCapture()
        bringUzumeToFront()
        notice = reason
        phase = spotify.isRunning ? .ready : .spotifyNotRunning
    }

    private func stopCapture() {
        scanTask?.cancel()
        scanTask = nil
        source?.stop()
        source = nil
        panel?.close()
    }

    private func spotifyRunningChanged(_ running: Bool) {
        switch phase {
        case .scanning where !running:
            abandonScan(.spotifyClosedDuringScan)
        case .ready where !running, .needsPermission where !running:
            phase = .spotifyNotRunning
        case .spotifyNotRunning where running:
            phase = .ready
        default:
            break
        }
    }

    // MARK: Screenshots

    /// Screenshots dropped on the Spotify view.
    func importScreenshots(_ urls: [URL]) {
        guard !urls.isEmpty, phase != .scanning, phase != .readingScreenshots else { return }
        let returnPhase: Phase = phase == .review ? .review : (spotify.isRunning ? .ready : .spotifyNotRunning)
        notice = nil
        phase = .readingScreenshots
        Task { [weak self] in
            guard let self else { return }
            var accumulated = PlaylistScanAccumulator()
            for frame in await self.readScreenshots(urls) { accumulated.add(frame) }
            if accumulated.rows.isEmpty {
                self.phase = returnPhase
                self.notice = .nothingInScreenshots
            } else {
                self.enterReview(accumulated)
            }
        }
    }

    // MARK: Review

    private func enterReview(_ result: PlaylistScanAccumulator) {
        reviewRows = result.rows
        reviewName = result.playlistName
        reviewMissing = result.gaps
        phase = .review
    }

    /// Fix a row's text. The user's reading is authoritative: no longer cut off, no longer unsure.
    func updateRow(number: Int, title: String, artist: String) {
        guard let index = reviewRows.firstIndex(where: { $0.number == number }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        reviewRows[index].title = cleanTitle
        reviewRows[index].artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        reviewRows[index].titleTruncated = false
        reviewRows[index].artistTruncated = false
        reviewRows[index].confidence = 1
    }

    /// Remove a row the user doesn't want (a misread, a duplicate).
    func removeRow(number: Int) {
        reviewRows.removeAll { $0.number == number }
    }

    /// "Scan again" — straight back into a live scan.
    func scanAgain() {
        reviewRows = []
        reviewName = nil
        reviewMissing = []
        phase = spotify.isRunning ? .ready : .spotifyNotRunning
        startScan()
    }

    /// The tracks Continue hands to preparation, in playlist order.
    var reviewTracks: [TrackIdentity] { reviewRows.map(\.trackIdentity) }

    /// "Continue" — start preparation with the reviewed list.
    func continueToPreparation(startSession: @Sendable ([TrackIdentity], PlaylistSource) async -> Void) async {
        guard phase == .review, !reviewRows.isEmpty else { return }
        await startSession(reviewTracks, .spotifyScan(playlistName: reviewName))
    }
}

// MARK: - ScanPanelPresenting

/// The floating panel beside Spotify. Behind a protocol so view-model tests don't open windows.
@MainActor
protocol ScanPanelPresenting: AnyObject {
    func show(model: SpotifyScanViewModel)
    func close()
}
