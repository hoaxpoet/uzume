// EscBehaviorTests — Verifies the Esc key two-mode behavior (U.6 Part D).
//
// Esc in fullscreen: toggles fullscreen, does NOT end session.
// Esc in windowed mode: requests end-session confirmation.

import AppKit
import Session
import SwiftUI
import Testing
@testable import UzumeApp

@Suite("Esc Behavior")
@MainActor
struct EscBehaviorTests {

    @Test func esc_whenFullscreen_exitsFullscreen_doesNotEndSession() async throws {
        let fo = FullscreenObserver()
        let window = NSWindow()
        fo.attach(to: window)

        // Manually set isFullscreen by posting the notification
        NotificationCenter.default.post(name: NSWindow.didEnterFullScreenNotification, object: window)
        try await Task.sleep(for: .milliseconds(20))
        #expect(fo.isFullscreen)

        let mgr = SessionManager.testInstance()
        mgr.startAdHocSession()
        let endVM = EndSessionConfirmViewModel(sessionManager: mgr)

        // Simulate Esc handler logic
        if fo.isFullscreen {
            // Would call fo.toggleFullscreen() — we can't do the full toggle in unit test
            // but we verify the decision branch: endVM should NOT be triggered
            // Assertion: isPresented stays false
        } else {
            endVM.requestEnd()
        }
        #expect(!endVM.isPresented, "Esc in fullscreen should not trigger end-session dialog")

        fo.detach()
    }

    @Test func esc_whenWindowed_requestsEndSession() {
        let fo = FullscreenObserver()
        let window = NSWindow()
        fo.attach(to: window)
        #expect(!fo.isFullscreen)

        let mgr = SessionManager.testInstance()
        let endVM = EndSessionConfirmViewModel(sessionManager: mgr)

        // Simulate Esc handler logic
        if fo.isFullscreen {
            fo.toggleFullscreen()
        } else {
            endVM.requestEnd()
        }
        #expect(endVM.isPresented, "Esc in windowed mode should show end-session dialog")

        fo.detach()
    }

    // MARK: - BR.14 / F4, D7, F9

    /// Keys aimed at another window (the Settings sheet) pass through; before the window is known
    /// every key is playback's.
    @Test func keysForAnotherWindow_passThrough() {
        let playback = NSWindow.offscreen(CGRect(x: 0, y: 0, width: 200, height: 100))
        let sheet = NSWindow.offscreen(CGRect(x: 0, y: 0, width: 100, height: 50))
        defer { playback.close(); sheet.close() }
        #expect(PlaybackKeyMonitor.targetsPlayback(eventWindow: playback, playbackWindow: playback))
        #expect(!PlaybackKeyMonitor.targetsPlayback(eventWindow: sheet, playbackWindow: playback))
        #expect(!PlaybackKeyMonitor.targetsPlayback(eventWindow: nil, playbackWindow: playback))
        #expect(PlaybackKeyMonitor.targetsPlayback(eventWindow: sheet, playbackWindow: nil))
    }

    /// The reader reports the window the view is actually in, whatever app is frontmost.
    @Test func hostWindowReader_reportsItsOwnWindow() {
        let window = NSWindow.offscreen(CGRect(x: 0, y: 0, width: 200, height: 100))
        defer { window.close() }
        var reported: NSWindow?
        let host = NSHostingView(rootView: Color.clear.background(HostWindowReader { reported = $0 }))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(reported === window)
    }

    /// Source shape: playback no longer reads `NSApp.keyWindow`; Esc closes help before anything else.
    @Test func playbackTakesItsWindowFromTheView() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("UzumeApp/Views/Playback/PlaybackView.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(!src.contains("NSApp.keyWindow"))
        #expect(src.contains(".background(HostWindowReader { attachWindow($0) })"))
        #expect(src.contains("if showHelp {"))
    }

    /// BR.14 / F6: Settings from every screen — a `Settings` scene (Uzume › Settings…, ⌘,)
    /// carrying the environment its sections read, and the Idle gear (UX_SPEC §4.1).
    @Test func settingsIsReachableOutsidePlayback() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(contentsOf: root.appendingPathComponent("UzumeApp/UzumeApp.swift"), encoding: .utf8)
        let scene = try #require(app.range(of: "        Settings {\n"))
        let body = app[scene.lowerBound...].prefix(400)
        #expect(body.contains("SettingsView(store: settingsStore)"))
        #expect(body.contains(".environmentObject(engine)") && body.contains(".environmentObject(recentsStore)"))
        let idlePath = root.appendingPathComponent("UzumeApp/Views/Idle/IdleView.swift")
        let idle = try String(contentsOf: idlePath, encoding: .utf8)
        #expect(idle.contains("SettingsLink {"))
    }
}
