// PlaybackKeyMonitor — Installs an NSEvent local monitor for playback keyboard shortcuts.
//
// Uses NSEvent.addLocalMonitorForEvents(matching: .keyDown) because .onKeyPress has
// limitations with modifier-heavy shortcuts (⌘F, ⌘⇧F, ⌘R, ⌘Z) and Esc handling
// inside a focused view. The monitor intercepts before AppKit's default handlers.

import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "io.uzume.mac", category: "PlaybackKeyMonitor")

// MARK: - PlaybackKeyMonitor

/// Installs and manages an NSEvent local key monitor for PlaybackView shortcuts.
///
/// Call `install(registry:)` on `PlaybackView.onAppear` and `uninstall()` on
/// `.onDisappear`. The monitor lives only during the `.playing` state.
@MainActor
final class PlaybackKeyMonitor {

    // MARK: - Private

    private var monitor: Any?

    /// The playback window (BR.14 / F9). Keys aimed at any other window — the Settings sheet, a
    /// panel — pass through, so Esc there closes that window instead of asking to end the session.
    /// Nil until the view reports its window; then every key is dispatched as before.
    weak var window: NSWindow?

    // MARK: - Install / Uninstall

    /// Begin intercepting key-down events and dispatching them via `registry`.
    func install(registry: PlaybackShortcutRegistry) {
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event: event, registry: registry)
        }
        logger.info("PlaybackKeyMonitor: installed")
    }

    /// Stop intercepting events.
    func uninstall() {
        guard let mon = monitor else { return }
        NSEvent.removeMonitor(mon)
        monitor = nil
        logger.info("PlaybackKeyMonitor: uninstalled")
    }

    // MARK: - Private

    /// Match the event against the registry. Returns nil (consume) if matched; the
    /// original event otherwise (pass through to AppKit default handling).
    @MainActor
    private func handle(event: NSEvent, registry: PlaybackShortcutRegistry) -> NSEvent? {
        guard Self.targetsPlayback(eventWindow: event.window, playbackWindow: window) else { return event }
        for shortcut in registry.shortcuts {
            guard shortcut.matches(event: event) else { continue }   // one rule (BR.4 / F8)
            shortcut.action()
            logger.debug("PlaybackKeyMonitor: dispatched '\(shortcut.id)'")
            return nil // Consume — don't pass to AppKit
        }
        return event // Pass through
    }

    /// A key belongs to playback when it is aimed at the playback window (or the window is not
    /// known yet). BR.14 / F9.
    nonisolated static func targetsPlayback(eventWindow: NSWindow?, playbackWindow: NSWindow?) -> Bool {
        guard let playbackWindow else { return true }
        return eventWindow === playbackWindow
    }
}
