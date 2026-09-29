// EndedViewTests — QR.4 / D-091.
//
// Verifies the post-stub session-summary card resolves the right localization
// keys, exposes the static accessibility identifiers documented in the view,
// and that the injected closures fire when invoked. SwiftUI subview traversal
// in unit tests is unreliable (Failed Approach #41 — accessibility tree only
// materialises with an active accessibility client), so behavioural assertions
// are made by invoking closures directly and by inspecting source / localized
// strings.

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import UzumeApp

@Suite("EndedView")
@MainActor
struct EndedViewTests {

    @Test("required localization keys resolve to non-empty strings")
    func test_localizationKeys_resolve() {
        let keys = [
            "ended.headline",
            "ended.cta.newSession",
            "ended.cta.openFolder",
            "ended.summary.tracks",
            "ended.summary.duration"
        ]
        for key in keys {
            let value = String(localized: String.LocalizationValue(key))
            #expect(!value.isEmpty, "Localizable.strings missing key '\(key)'")
            #expect(value != key, "Localizable.strings key '\(key)' is unresolved (returned the key itself)")
        }
    }

    @Test("accessibility identifier constants are defined and unique")
    func test_accessibilityIDs_areDistinct() {
        #expect(EndedView.accessibilityID == "uzume.view.ended")
        #expect(EndedView.newSessionButtonID == "uzume.ended.newSession")
        #expect(EndedView.openFolderButtonID == "uzume.ended.openFolder")
        let ids = [EndedView.accessibilityID, EndedView.newSessionButtonID, EndedView.openFolderButtonID]
        #expect(Set(ids).count == ids.count, "EndedView accessibility identifiers must be distinct")
    }

    @Test("view constructs successfully with concrete inputs")
    func test_viewConstructs() {
        var startCalls = 0
        var folderCalls = 0
        let view = EndedView(
            trackCount: 4,
            sessionDuration: 180,
            onStartNewSession: { startCalls += 1 },
            onOpenSessionsFolder: { folderCalls += 1 }
        )
        // Render once to force body evaluation; ignore the view tree.
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        host.layoutSubtreeIfNeeded()
        #expect(startCalls == 0, "init must not invoke the start-session closure")
        #expect(folderCalls == 0, "init must not invoke the open-folder closure")
    }

    @Test("ended.summary.tracks formatter substitutes the count")
    func test_trackCountFormatter() {
        let template = String(localized: "ended.summary.tracks")
        let formatted = String(format: template, 4)
        #expect(formatted.contains("4"), "track-count format must place the count: got '\(formatted)'")
        #expect(formatted.contains("track"), "track-count format must contain 'track': got '\(formatted)'")
    }

    @Test("openSessionsFolder helper creates the directory")
    func test_openSessionsFolder_createsDirectoryIfMissing() {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("uzume_sessions")
        let preExisted = FileManager.default.fileExists(atPath: url.path)
        EndedView.openSessionsFolder()
        let postExists = FileManager.default.fileExists(atPath: url.path)
        #expect(postExists, "uzume_sessions/ must exist after openSessionsFolder()")
        if !preExisted {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - BR.4 (I10): a real duration and a pluralised count

@Suite("Ended screen summary (BR.4)")
@MainActor
struct EndedSummaryTests {

    @Test func trackCount_isPluralised_andHiddenAtZero() {
        #expect(EndedView.trackCountText(1) == "1 track")
        #expect(EndedView.trackCountText(12) == "12 tracks")
        #expect(EndedView.trackCountText(0) == nil)
    }

    @Test func duration_isReal_andHiddenWhenNeverPlayed() {
        #expect(EndedView.durationText(725) == "12m 5s")
        #expect(EndedView.durationText(nil) == nil, "no '—' placeholder")
    }

    @Test func durationClock_measuresPlayingToEnded_andResetsPerSession() {
        var clock = PlaybackDurationClock()
        let t0 = Date(timeIntervalSince1970: 1_000)
        clock.update(state: .preparing, now: t0)
        clock.update(state: .ready, now: t0.addingTimeInterval(5))
        clock.update(state: .playing, now: t0.addingTimeInterval(10))
        clock.update(state: .ended, now: t0.addingTimeInterval(735))
        #expect(clock.lastSessionSeconds == 725, "playing → ended, not from preparation")
        clock.update(state: .idle, now: t0.addingTimeInterval(800))
        #expect(clock.lastSessionSeconds == 725)
        clock.update(state: .connecting, now: t0.addingTimeInterval(900))
        #expect(clock.lastSessionSeconds == nil, "a new session forgets the last")
        clock.update(state: .ended, now: t0.addingTimeInterval(950))
        #expect(clock.lastSessionSeconds == nil, "never played → no duration")
    }

    /// Source shape: ContentView passes the engine's measured duration, not a literal nil.
    @Test func contentView_passesTheMeasuredDuration() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UzumeApp/ContentView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("sessionDuration: engine.lastSessionPlaybackSeconds"))
        #expect(!src.contains("sessionDuration: nil"))
    }
}
