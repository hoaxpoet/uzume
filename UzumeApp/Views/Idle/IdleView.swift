// IdleView — Shown when SessionManager.state == .idle.
// U.1 stub: displays state name on black background.
// U.2: photosensitivity sheet — moved to ContentView at BR.1 so it gates every path (F7).
// U.3: connector picker CTA + ad-hoc "Start listening now" CTA.

import Session
import SwiftUI

// MARK: - IdleView

@MainActor
struct IdleView: View {
    static let accessibilityID        = "uzume.view.idle"
    static let connectButtonID        = "uzume.idle.connectPlaylist"
    static let adHocButtonID          = "uzume.idle.startListening"

    @EnvironmentObject private var engine: VisualizerEngine
    @EnvironmentObject private var errorStore: LocalFileErrorStore

    @State private var showConnectorPicker = false
    /// A connect chosen in the picker, held until its sheet has finished closing (BUG-161).
    @State private var pendingConnection: PendingConnection?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(String(localized: "appName"))
                .font(.largeTitle)
                .fontWeight(.thin)
                .foregroundColor(UzumeAppColor.textPrimary)

            Spacer().frame(height: 8)

            VStack(spacing: 12) {
                Button(String(localized: "idle.connect_button")) {
                    showConnectorPicker = true
                }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(Self.connectButtonID)

                Button(String(localized: "idle.adhoc_button")) {
                    engine.sessionManager.startAdHocSession()
                }
                .foregroundColor(UzumeAppColor.textTertiary)
                .font(.subheadline)
                .accessibilityIdentifier(Self.adHocButtonID)
            }

            // GAP F (2026-05-28): inline LF error surface. Renders only when
            // a non-destructive LF error fires (unsupported format, unreadable,
            // M3U parse, empty folder). Auto-clears after 6 s; tap to dismiss
            // earlier. Replaces NSAlert modals for these cases.
            if let error = errorStore.lastError {
                InlineNotice(message: error.localizedMessage) {
                    errorStore.clear()
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(UzumeAppColor.canvas)
        .accessibilityIdentifier(Self.accessibilityID)
        .sheet(isPresented: $showConnectorPicker, onDismiss: startPendingConnection) {
            ConnectorPickerView { tracks, source in
                // BUG-161: close the sheet FIRST and start the session from `onDismiss`.
                // Starting it here flipped the state to .connecting, so ContentView removed
                // IdleView while its sheet was still up; SwiftUI then tore the sheet down
                // mid-close and AppKit's sheet animation crashed (EXC_BAD_ACCESS in
                // UpdateCycle, macOS 26, on the scan review's Continue).
                await MainActor.run {
                    pendingConnection = PendingConnection(tracks: tracks, source: source)
                    showConnectorPicker = false
                }
            }
        }
    }

    // MARK: - Private

    private struct PendingConnection {
        let tracks: [TrackIdentity]
        let source: PlaylistSource
    }

    /// Start the session the picker chose, once its sheet is gone.
    ///
    /// Route by SOURCE, not tracks.isEmpty:
    /// - Spotify: always use preFetchedTracks (even if empty) to avoid SessionManager
    ///   re-fetching via client-credentials (→ 401). A scanned playlist (SCAN) has no
    ///   fetch at all — its rows ARE the tracks.
    /// - Apple Music / other: no pre-fetched tracks; SM fetches itself.
    private func startPendingConnection() {
        guard let pending = pendingConnection else { return }
        pendingConnection = nil
        let sessionManager = engine.sessionManager
        Task {
            switch pending.source {
            case .spotifyPlaylistURL, .spotifyCurrentQueue, .spotifyScan:
                await sessionManager.startSession(preFetchedTracks: pending.tracks, source: pending.source)
            default:
                await sessionManager.startSession(source: pending.source)
            }
        }
    }
}
