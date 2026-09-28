// SpotifyScanView — the Spotify connector's primary flow: scan a playlist from the
// screen, or drop screenshots of it (SCAN, D-260; UX_SPEC §4.4).
//
// No Spotify login, no request to Spotify: Uzume reads the track names in the
// Spotify window while the user scrolls. The paste-a-link flow survives only in
// developer builds (D-260 decision 1, default A) behind "Paste a link instead".

import AppKit
import Session
import SwiftUI
import UniformTypeIdentifiers

// MARK: - SpotifyScanView

struct SpotifyScanView: View {
    static let accessibilityID = "uzume.view.spotify.scan"

    @ObservedObject var viewModel: SpotifyScanViewModel
    let onConnect: @Sendable ([TrackIdentity], PlaylistSource) async -> Void
    /// Developer builds only: push the paste-a-link flow.
    let onPasteLinkInstead: (() -> Void)?

    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()
            Group {
                if viewModel.phase == .review {
                    ScanReviewView(viewModel: viewModel, onConnect: onConnect)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        phaseContent
                        if let notice = viewModel.notice { noticeLine(notice) }
                        Spacer()
                        footer
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 520, alignment: .leading)
                }
            }
        }
        .navigationTitle(String(localized: "connector.spotify.title"))
        .accessibilityIdentifier(Self.accessibilityID)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshPermission()
        }
        .onDisappear { viewModel.cancelScan() }
    }

    // MARK: - Phases

    @ViewBuilder
    private var phaseContent: some View {
        switch viewModel.phase {
        case .spotifyNotRunning:
            notRunningBody
        case .ready:
            readyBody
        case .needsPermission:
            permissionBody
        case .scanning:
            progressLine(String(localized: "connector.spotify.scan.scanning_status"))
            Button(String(localized: "scan.panel.cancel")) { viewModel.cancelScan() }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
        case .readingScreenshots:
            progressLine(String(localized: "connector.spotify.scan.reading"))
        case .review:
            EmptyView()   // ScanReviewView replaces the whole pane
        }
    }

    private var notRunningBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "connector.spotify.scan.not_running.headline"))
                .font(.title3.weight(.semibold))
                .foregroundColor(UzumeAppColor.textPrimary)
            Button(String(localized: "connector.spotify.scan.open_button")) { viewModel.openSpotify() }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("uzume.spotify.scan.openSpotify")
            dropTarget
        }
    }

    private var readyBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "connector.spotify.scan.headline"))
                .font(.title3.weight(.semibold))
                .foregroundColor(UzumeAppColor.textPrimary)
            Text(String(localized: "connector.spotify.scan.body"))
                .font(.body)
                .foregroundColor(UzumeAppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "connector.spotify.scan.start_button")) { viewModel.startScan() }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("uzume.spotify.scan.start")
            dropTarget
        }
    }

    private var permissionBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "connector.spotify.scan.permission.body"))
                .font(.body)
                .foregroundColor(UzumeAppColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "connector.spotify.scan.permission.button")) { viewModel.allowAccess() }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("uzume.spotify.scan.allowAccess")
            Button(String(localized: "connector.spotify.scan.permission.settings_link")) {
                let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                if let url = URL(string: pane) { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link)
        }
    }

    // MARK: - Drop target

    private var dropTarget: some View {
        Text(String(localized: "connector.spotify.scan.drop_prompt"))
            .font(.callout)
            .foregroundColor(isDropTargeted ? UzumeAppColor.textPrimary : UzumeAppColor.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(isDropTargeted ? UzumeAppColor.surfaceSelected : UzumeAppColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: UzumeAppRadius.md)
                    .strokeBorder(isDropTargeted ? UzumeAppColor.focus : UzumeAppColor.line,
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: UzumeAppRadius.md))
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadFileURLs(providers) { viewModel.importScreenshots($0) }
                return true
            }
            .accessibilityIdentifier("uzume.spotify.scan.dropTarget")
    }

    // MARK: - Pieces

    private func progressLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(UzumeAppColor.textTertiary)
            Text(text)
                .font(.body)
                .foregroundColor(UzumeAppColor.textSecondary)
        }
    }

    private func noticeLine(_ notice: SpotifyScanViewModel.Notice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(StatusTone.warning.foreground).frame(width: 6, height: 6).padding(.top, 6)
            Text(Self.copy(for: notice))
                .font(.footnote)
                .foregroundColor(UzumeAppColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("uzume.spotify.scan.notice")
    }

    /// UX_SPEC §9.2 copy for each notice.
    static func copy(for notice: SpotifyScanViewModel.Notice) -> String {
        switch notice {
        case .spotifyClosedDuringScan: return String(localized: "connector.spotify.scan.notice.spotify_closed")
        case .windowUnavailable: return String(localized: "connector.spotify.scan.notice.window_unavailable")
        case .nothingInScreenshots: return String(localized: "connector.spotify.scan.notice.nothing_in_screenshots")
        case .nothingRead: return String(localized: "connector.spotify.scan.notice.nothing_read")
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let onPasteLinkInstead {
            Button(String(localized: "connector.spotify.scan.paste_link")) { onPasteLinkInstead() }
                .buttonStyle(.link)
                .accessibilityIdentifier("uzume.spotify.scan.pasteLink")
        }
    }
}

// MARK: - Drop helpers

/// Resolve dropped file URLs (off the providers' callback queues) and hand them back on the main actor.
func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let collected = LockedURLs()
    let group = DispatchGroup()
    for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { collected.append(url) }
            group.leave()
        }
    }
    group.notify(queue: .main) { MainActor.assumeIsolated { completion(collected.urls) } }
}

private final class LockedURLs: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []
    func append(_ url: URL) { lock.withLock { storage.append(url) } }
    var urls: [URL] { lock.withLock { storage } }
}
