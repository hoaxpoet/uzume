// DisplayManagerTests — Unit tests for DisplayManager (U.6 Part D).
//
// NSScreen cannot be mocked (it's a system type with no protocol). Tests cover
// the observable state transitions using NSApplication.didChangeScreenParametersNotification.

import AppKit
import Testing
@testable import UzumeApp

@Suite("DisplayManager")
@MainActor
struct DisplayManagerTests {

    @Test func init_allScreens_matchesNSScreenScreens() {
        let fo = FullscreenObserver()
        let dm = DisplayManager(fullscreenObserver: fo)
        // allScreens should match the live list at init
        #expect(dm.allScreens.count == NSScreen.screens.count)
    }

    /// BR.14 / D8: the primary display is the menu-bar screen (`screens[0]`), not `NSScreen.main`
    /// — the key window's screen, which from the secondary display named the secondary.
    @Test func init_primaryScreen_isTheMenuBarScreen() throws {
        let fo = FullscreenObserver()
        let dm = DisplayManager(fullscreenObserver: fo)
        #expect(dm.primaryScreen == NSScreen.screens.first)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("UzumeApp/Services/DisplayManager.swift")
        let code = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        #expect(!code.contains { $0.contains("NSScreen.main") }, "DisplayManager reads NSScreen.main again")
    }

    @Test func screenParametersChange_updatesAllScreens() async throws {
        let fo = FullscreenObserver()
        let dm = DisplayManager(fullscreenObserver: fo)
        let initial = dm.allScreens.count

        // Post the notification (simulates plug/unplug)
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification,
            object: NSApp
        )
        try await Task.sleep(for: .milliseconds(20))
        // After the notification the manager re-queries NSScreen.screens
        #expect(dm.allScreens.count == NSScreen.screens.count)
        _ = initial // suppress unused warning
    }

    @Test func moveToSecondary_withOneDisplay_logsNoOp() {
        let fo = FullscreenObserver()
        let dm = DisplayManager(fullscreenObserver: fo)
        // On a single-display CI machine this should not crash
        dm.moveToSecondaryDisplay()
        #expect(dm.allScreens.count >= 1)
    }
}
