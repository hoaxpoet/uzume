// ScanPanel — the small floating panel beside Spotify during a live scan (SCAN.4, D-260).
//
// Non-activating: Spotify stays the active app so the user can scroll it; the panel
// floats above. Esc cancels when the panel has focus (clicking it gives focus without
// activating Uzume). Esc typed into Spotify goes to Spotify — catching it would need
// the Accessibility permission, which the scan deliberately does not use.

import AppKit
import Session
import SwiftUI

// MARK: - ScanPanelController

@MainActor
final class ScanPanelController: ScanPanelPresenting {

    private var panel: NSPanel?
    static let size = CGSize(width: 300, height: 196)

    func show(model: SpotifyScanViewModel) {
        close()
        let panel = KeyablePanel(
            contentRect: Self.frame(beside: SystemSpotifyApp.mainWindowFrame()),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ScanPanelView(model: model))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// Beside Spotify's window (right, else left, else inside its bottom-right corner).
    static func frame(beside window: CGRect?) -> NSRect {
        // Window-list bounds are top-left origin on the primary display; AppKit's are bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 900
        let spotify = window.map { NSRect(x: $0.minX, y: primaryHeight - $0.maxY, width: $0.width, height: $0.height) }
        let centre = spotify.map { NSPoint(x: $0.midX, y: $0.midY) }
        let screen = centre.flatMap { point in NSScreen.screens.first { $0.frame.contains(point) } } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        guard let spotify else {
            return NSRect(origin: NSPoint(x: visible.maxX - size.width - 24, y: visible.minY + 24), size: size)
        }
        let y = min(max(spotify.maxY - size.height - 60, visible.minY + 12), visible.maxY - size.height)
        if spotify.maxX + 12 + size.width <= visible.maxX {
            return NSRect(x: spotify.maxX + 12, y: y, width: size.width, height: size.height)
        }
        if spotify.minX - 12 - size.width >= visible.minX {
            return NSRect(x: spotify.minX - 12 - size.width, y: y, width: size.width, height: size.height)
        }
        let inside = NSPoint(x: spotify.maxX - size.width - 16, y: max(spotify.minY + 16, visible.minY + 12))
        return NSRect(origin: inside, size: size)
    }
}

/// A non-activating panel that can still take key focus (for Esc / Return).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - ScanPanelView

struct ScanPanelView: View {
    static let accessibilityID = "uzume.view.scanPanel"

    @ObservedObject var model: SpotifyScanViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "scan.panel.instruction"))
                .font(.callout.weight(.semibold))
                .foregroundColor(UzumeAppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.count(model.progress))
                .font(.title3.monospacedDigit())
                .foregroundColor(UzumeAppColor.textPrimary)
                .accessibilityIdentifier("uzume.scanPanel.count")
            if model.progress.startedMidList {
                prompt(String(localized: "scan.panel.scroll_to_top"))
            } else if let missed = model.progress.missed {
                prompt(String(format: String(localized: "scan.panel.missed"), ScanReviewView.describe([missed])))
            }
            Spacer(minLength: 0)
            HStack {
                Button(String(localized: "scan.panel.cancel")) { model.cancelScan() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("uzume.scanPanel.cancel")
                Spacer()
                Button(String(localized: "scan.panel.done")) { model.finishScan() }
                    .buttonStyle(.borderedProminent)
                    .uzumeTint()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("uzume.scanPanel.done")
            }
        }
        .padding(16)
        .frame(width: ScanPanelController.size.width, height: ScanPanelController.size.height, alignment: .topLeading)
        .background(UzumeAppColor.surfaceRaised)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    private func prompt(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundColor(StatusTone.warning.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "27 of 38 songs" / "27 songs" (no header count read).
    static func count(_ progress: SpotifyScanViewModel.Progress) -> String {
        if let total = progress.songCount {
            return total == 1
                ? String(format: String(localized: "scan.panel.count_of.one"), progress.found)
                : String(format: String(localized: "scan.panel.count_of"), progress.found, total)
        }
        return progress.found == 1
            ? String(localized: "scan.panel.count.one")
            : String(format: String(localized: "scan.panel.count"), progress.found)
    }
}
