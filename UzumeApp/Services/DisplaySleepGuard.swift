// DisplaySleepGuard — Keeps the display awake while a session is on screen (BR.2 / BUG-162).

import Foundation
import Session

// MARK: - DisplaySleepAsserting

/// Seam over the OS power assertion so the state→assertion mapping is testable.
protocol DisplaySleepAsserting {
    /// Begin preventing idle display sleep. Returns a token to pass to `end`.
    func begin(reason: String) -> NSObjectProtocol
    /// Release a token returned by `begin`.
    func end(_ token: NSObjectProtocol)
}

// MARK: - ProcessInfoDisplaySleepAsserter

/// Live asserter: `ProcessInfo.beginActivity` with `.idleDisplaySleepDisabled`
/// (shows in `pmset -g assertions` as `PreventUserIdleDisplaySleep` for Uzume).
struct ProcessInfoDisplaySleepAsserter: DisplaySleepAsserting {
    func begin(reason: String) -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: reason
        )
    }

    func end(_ token: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(token)
    }
}

// MARK: - DisplaySleepGuard

/// Holds a display-sleep assertion from `.ready` through `.playing` while the
/// window is open; releases it on `.ended`, `.idle` and window close.
@MainActor
final class DisplaySleepGuard {

    // MARK: - State

    private let asserter: DisplaySleepAsserting
    private var token: NSObjectProtocol?
    private var state: SessionState = .idle
    private var windowOpen = true

    /// Whether the assertion is currently held.
    var isHeld: Bool { token != nil }

    // MARK: - Init

    init(asserter: DisplaySleepAsserting = ProcessInfoDisplaySleepAsserter()) {
        self.asserter = asserter
    }

    // MARK: - Inputs

    /// Feed every session-state change.
    func update(state: SessionState) {
        self.state = state
        reconcile()
    }

    /// Feed window open/close (the session can outlive a closed window, F14).
    func setWindowOpen(_ open: Bool) {
        windowOpen = open
        reconcile()
    }

    /// The pure mapping: hold only while a session is on screen.
    static func shouldHold(state: SessionState, windowOpen: Bool) -> Bool {
        windowOpen && (state == .ready || state == .playing)
    }

    // MARK: - Private

    private func reconcile() {
        let hold = Self.shouldHold(state: state, windowOpen: windowOpen)
        if hold, token == nil {
            token = asserter.begin(reason: "Uzume visual session")
        } else if !hold, let held = token {
            asserter.end(held)
            token = nil
        }
    }
}
