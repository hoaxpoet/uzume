// FullscreenObserver — Tracks NSWindow fullscreen state via system notifications.

import AppKit
import Foundation
import SwiftUI

// MARK: - FullscreenObserver

/// Observes `NSWindow.didEnterFullScreenNotification` and `didExitFullScreenNotification`
/// to maintain an authoritative `isFullscreen` flag.
///
/// Associated with a single `NSWindow`. Call `attach(to:)` from `PlaybackView.onAppear`
/// and `detach()` from `onDisappear`.
@MainActor
final class FullscreenObserver: ObservableObject {

    // MARK: - Published

    @Published private(set) var isFullscreen: Bool = false

    // MARK: - Private

    nonisolated(unsafe) private var enterObserver: Any?
    nonisolated(unsafe) private var exitObserver: Any?
    private weak var window: NSWindow?

    // MARK: - Init

    init() {}

    // MARK: - Attach / Detach

    /// Start observing fullscreen transitions on `window`.
    func attach(to window: NSWindow) {
        self.window = window
        isFullscreen = window.styleMask.contains(.fullScreen)

        enterObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isFullscreen = true }
        }

        exitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isFullscreen = false }
        }
    }

    /// Stop observing and release the window reference.
    func detach() {
        if let obs = enterObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = exitObserver { NotificationCenter.default.removeObserver(obs) }
        enterObserver = nil
        exitObserver = nil
        window = nil
    }

    // MARK: - Actions

    /// Toggle fullscreen on the associated window.
    func toggleFullscreen() {
        window?.toggleFullScreen(nil)
    }

    deinit {
        // Safe: observers are removed before retain cycle can form.
        if let obs = enterObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = exitObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - HostWindowReader

/// Hands a SwiftUI view the `NSWindow` it is actually in (BR.14 / F4, D7). `NSApp.keyWindow` at
/// `onAppear` is whichever app is frontmost — in the streaming flow, Spotify — so fullscreen and
/// display handling never attached: ⌘F did nothing and Esc in green-button fullscreen asked to end
/// the session. The window is reported whenever the view joins one, so a late join is not lost.
struct HostWindowReader: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { ReportingView(onWindow: onWindow) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        let onWindow: @MainActor (NSWindow) -> Void
        init(onWindow: @escaping @MainActor (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}
