import Foundation
import Renderer
import SwiftUI
import os.log

private let lfLogger = Logger(subsystem: "io.uzume.mac", category: "LF1")

/// Uzume application entry point.
///
/// Creates a single window containing the Metal-backed visualizer.
/// `VisualizerEngine` is the primary long-lived object — it owns the render
/// loop, audio capture, ML pipelines, and the `SessionManager`. `ContentView`
/// routes to the correct top-level view based on `SessionManager.state`.
///
/// `AccessibilityState` (U.9) is a `@StateObject` here so it can observe
/// `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` independently
/// of the settings store. `UzumeApp.body` wires the two together via `.task`
/// (subscribes to `settingsStore.$reducedMotion`) and `.onReceive(engineFlags)`
/// (pushes engine flags at launch and on every change, BR.1).
///
/// `spotifyOAuth` (U.11) is a long-lived actor that owns the Spotify OAuth
/// Authorization Code + PKCE token lifecycle. It is created once here and passed
/// to `ConnectorPickerView` via environment injection. The `.onOpenURL` modifier
/// routes `uzume://spotify-callback` redirects back to the actor.
@main
struct UzumeApp: App {
    @StateObject private var engine = VisualizerEngine()
    @StateObject private var permissionMonitor = PermissionMonitor()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var accessibilityState = AccessibilityState()

    /// LF.5 Recents store — last 10 local-file / folder / M3U opens persisted
    /// in `uzume.lf.recents` UserDefaults. Drives `File → Open Recent ▸`.
    @StateObject private var recentsStore = LocalFileRecentsStore()

    /// Long-lived Spotify OAuth actor — not `@StateObject` because actors are not
    /// `ObservableObject`; stored as a plain `let` since `UzumeApp` is `@MainActor`.
    private let spotifyOAuth = SpotifyOAuthTokenProvider.makeLive()

    /// BR.5 (audit D3): notices a blocked main thread from its own thread, in every build.
    private let mainThreadWatchdog = MainThreadWatchdog()

    /// BR.5: whether the previous run ended without a clean quit (read once at launch).
    private let previousRunEndedAbnormally: Bool

    init() {
        // RN.1: adopt state stranded by the bundle-ID change (settings domain,
        // stem cache). Runs before SettingsMigrator so the key migration below
        // sees the carried-over values. Idempotent; a no-op after first launch.
        IdentityMigrator.migrate()
        // Migrate legacy phosphene.* UserDefaults keys into the uzume.* scheme (D-231).
        SettingsMigrator.migrate()
        // Prune old session folders according to the persisted retention policy.
        // Read the key directly to avoid a second SettingsStore allocation before @StateObject init.
        let rawPolicy = UserDefaults.standard.string(forKey: "uzume.settings.diagnostics.sessionRetention")
        let policy = SessionRetentionPolicy(rawValue: rawPolicy ?? "") ?? .lastN10
        // The public build keeps no session records and never touches ~/Documents (BUG-158).
        if BuildFlavor.current.recordsSessions {
            SessionRecorderRetentionPolicy.apply(policy: policy)
        }
        // Register Epilogue + Clash Display from the Renderer bundle so the
        // SwiftUI dashboard can resolve them via `.custom(_:size:)`. Falls back
        // silently to system fonts if the TTF/OTF files aren't bundled
        // (DASH.7.1, D-088). Idempotent — safe to call repeatedly.
        _ = DashboardFontLoader.resolveFonts(in: nil)
        mainThreadWatchdog.start()
        // BR.5: set at launch, cleared on a clean quit. Not under XCTest — every test run
        // kills its host app, which would otherwise read as a crash on the next real launch.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            let marker = AbnormalExitMarker(defaults: .standard)
            previousRunEndedAbnormally = marker.markLaunch()
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { _ in AbnormalExitMarker(defaults: .standard).markCleanQuit() }
        } else {
            previousRunEndedAbnormally = false
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: SessionStateViewModel(
                    sessionManager: engine.sessionManager,
                    accessibilityState: accessibilityState
                )
            )
            // DS.1 / D-232 — Uzume is always dark. The token roles in
            // `UzumeAppColor` are pinned to the dark block of tokens.css, so the
            // native controls composed beside them must resolve dark too; without
            // this a Mac set to Light Mode renders light buttons and pickers over
            // an unconditionally near-black canvas.
            .preferredColorScheme(.dark)
            .environmentObject(engine)
            // BR.2 (BUG-162): a closed window releases the display-sleep
            // assertion; BR.14 (F14): and ends a live session.
            .onAppear { engine.displaySleepGuard.setWindowOpen(true) }
            .onDisappear { engine.handleWindowClosed() }
            .environmentObject(permissionMonitor)
            .environmentObject(settingsStore)
            .environmentObject(accessibilityState)
            // GAP A (2026-05-28) — inject recentsStore so
            // LocalSourceConnectionView (and any future LF surface) can read
            // it via @EnvironmentObject instead of being threaded down through
            // every wrapping view. Existing call sites that take recentsStore
            // as a parameter are unchanged.
            .environmentObject(recentsStore)
            // GAP F (2026-05-28) — inject the LF error store so IdleView and
            // LocalSourceConnectionView can render inline error banners that
            // replace NSAlert modals for non-destructive errors.
            .environmentObject(LocalFileErrorStore.shared)
            // Inject the OAuth provider so ConnectorPickerView can build SpotifyConnectionViewModel.
            .environment(\.spotifyOAuthProvider, spotifyOAuth)
            // Wire SettingsStore preference → AccessibilityState on every change.
            .task {
                accessibilityState.applyPreference(settingsStore.reducedMotion)
                for await pref in settingsStore.$reducedMotion.values {
                    accessibilityState.applyPreference(pref)
                }
            }
            // Push accessibility flags into the engine at launch AND on every change
            // (BR.1 / F1: `.onChange` never fired when Reduce Motion was already on).
            .onReceive(accessibilityState.engineFlags) { reduce, scale in
                engine.applyAccessibility(reduceMotion: reduce, beatAmplitudeScale: scale)
            }
            // Push uncertified-presets preference into the engine so reactive mode
            // honours the setting without requiring a SettingsStore dependency in the engine.
            // BR.1 (F15): a value stored by a developer build never reaches a public one.
            .task {
                let allowed = BuildFlavor.current.exposesUncheckedScenes
                for await value in settingsStore.$showUncertifiedPresets.values {
                    engine.applyShowUncertifiedPresets(allowed && value)
                }
            }
            // Route uzume://spotify-callback back to the OAuth actor (U.11)
            // and file:// URLs to the LF.5 file-association dispatch path.
            .onOpenURL { url in
                if url.scheme == "uzume", url.host == "spotify-callback" {
                    Task { await spotifyOAuth.handleCallback(url: url) }
                    return
                }
                if url.isFileURL {
                    Task { @MainActor in
                        await dispatchFileURL(url)
                    }
                }
            }
            // LF.4 — Local-file playback hook. When the
            // `UZUME_LOCAL_FILE_PLAYBACK` env var points at a readable
            // audio file, bypass IdleView and drive the SessionManager LF
            // path (idle → preparing → ready → playing). The LF.2/LF.3
            // pre-analysis + persistent cache flow runs through
            // `VisualizerEngine`'s `LocalFilePreparing` conformance, so
            // BeatGrid + StemFeatures are installed from frame 0 (no ~10 s
            // live-analyzer warmup gap). Empty / absent / unreadable env
            // var: no log, normal launch proceeds.
            //
            // LF.1.5 — Process-tap autostart hook (dev-only, env-var-gated).
            // When `UZUME_AUTOSTART_ADHOC=1` is set AND the LF env var is
            // NOT, fire the same code path IdleView's "Start listening now"
            // button uses. Makes the LF-vs-tap A/B reproducible without a
            // manual UI click. LF env var takes precedence.
            .task {
                let env = ProcessInfo.processInfo.environment
                if let raw = env["UZUME_LOCAL_FILE_PLAYBACK"], !raw.isEmpty {
                    let url = URL(fileURLWithPath: raw)
                    guard FileManager.default.isReadableFile(atPath: url.path) else { return }
                    lfLogger.info("[LF.4] local-file playback mode: \(url.path, privacy: .public)")
                    await engine.sessionManager.startLocalFile(at: url)
                    return
                }
                if env["UZUME_AUTOSTART_ADHOC"] == "1" {
                    lfLogger.info("[LF.1.5] autostart ad-hoc session (UZUME_AUTOSTART_ADHOC=1)")
                    engine.sessionManager.startAdHocSession()
                }
            }
            // LF.4 + LF.5 — drag-and-drop into the app window. LF.4 supported
            // a single audio file; LF.5 extends to multi-file drops, folders
            // (recursive walk), `.m3u` playlists (parsed via M3UParser), and
            // any combination thereof. Mixed drops are flattened in drop
            // order.
            // BR.7 (C10): missing ML weights say so, once per launch, instead of every track
            // silently preparing as "partial".
            .task {
                if engine.analysisUnavailable { MissingAnalysisNotice.show() }
            }
            // BR.5: offer the report after a run that didn't quit cleanly. Public build only:
            // developer builds are stopped from Xcode and killed by scripts all day.
            .task {
                if previousRunEndedAbnormally, BuildFlavor.current == .public {
                    ProblemReporter.offer(.abnormalExit)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                LocalFileMenuCommands.handleDrop(
                    providers: providers,
                    engine: engine,
                    recentsStore: recentsStore
                )
            }
        }
        // LF.4 + LF.5 — File menu + Uzume-menu additions.
        //
        // File menu:
        //   - "Open Local File…"      (⌘O)            — LF.4
        //   - "Open Local Folder…"                    — LF.5
        //   - "Open Recent ▸" submenu                 — LF.5
        //
        // Uzume (.appInfo): "Clear Local-File Cache (<size>)" item that
        // surfaces the current disk footprint in the menu label. The size
        // auto-refreshes via the `localFileCacheBytes` publisher.
        .commands {
            // BR.5: Help › Report a Problem (replaces the empty "Uzume Help" item).
            CommandGroup(replacing: .help) {
                Button(String(localized: "menu.help.report_problem")) {
                    ProblemReporter.offer(.userRequested)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(String(localized: "menu.file.open_local_file")) {
                    LocalFileMenuCommands.openLocalFilePanel(
                        engine: engine,
                        recentsStore: recentsStore
                    )
                }
                .keyboardShortcut("o", modifiers: .command)

                Button(String(localized: "menu.file.open_local_folder")) {
                    LocalFileMenuCommands.openLocalFolderPanel(
                        engine: engine,
                        recentsStore: recentsStore
                    )
                }

                Divider()

                Menu(String(localized: "menu.file.open_recent")) {
                    if recentsStore.recents.isEmpty {
                        Button(String(localized: "menu.file.open_recent.empty")) {}
                            .disabled(true)
                    } else {
                        ForEach(recentsStore.recents) { item in
                            recentsMenuButton(for: item)
                        }
                        Divider()
                        Button(String(localized: "menu.file.open_recent.clear")) {
                            recentsStore.clearAll()
                        }
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                Divider()
                let clearLabel = String(
                    format: String(localized: "menu.app.clear_local_file_cache"),
                    LocalFileMenuCommands.formatBytes(engine.localFileCacheBytes)
                )
                Button(clearLabel) {
                    LocalFileMenuCommands.clearLocalFileCache(engine: engine)
                }
            }
        }

        // BR.14 / F6: Settings from every screen — Uzume › Settings… and ⌘, (the Idle gear opens
        // it too). Playback keeps its own sheet from the chrome's gear.
        Settings {
            SettingsView(store: settingsStore)
                .preferredColorScheme(.dark)
                .environmentObject(engine)
                .environmentObject(recentsStore)
        }
    }

    // MARK: - LF.5 file-association dispatch

    /// Route a `file://` URL received via `.onOpenURL` (Finder double-click,
    /// `open -a Uzume <path>`, drag-onto-Dock-icon) into the right
    /// LocalFileMenuCommands entry point. Unsupported extensions and
    /// non-existent paths are silently ignored — file-association handlers
    /// shouldn't pop alerts on unexpected URLs the OS chose to route here.
    @MainActor
    private func dispatchFileURL(_ url: URL) async {
        let ext = url.pathExtension.lowercased()
        if LocalFileMenuCommands.allowedExtensions.contains(ext) {
            await LocalFileMenuCommands.openLocalFile(
                at: url, engine: engine, recentsStore: recentsStore
            )
            return
        }
        if LocalFileMenuCommands.playlistExtensions.contains(ext) {
            await LocalFileMenuCommands.openLocalM3U(
                at: url, engine: engine, recentsStore: recentsStore
            )
            return
        }
        if LocalFileMenuCommands.isFolder(url) {
            await LocalFileMenuCommands.openLocalFolder(
                at: url, engine: engine, recentsStore: recentsStore
            )
        }
    }

    // MARK: - LF.5 Recents submenu row builder

    /// One button in the `File → Open Recent ▸` submenu. Stale entries (file
    /// moved or deleted) render with a "(missing)" suffix and the click
    /// removes the entry from the list instead of opening it.
    @ViewBuilder
    private func recentsMenuButton(for item: RecentItem) -> some View {
        let baseLabel = item.displayLabel
        let missing = item.isMissing
        let label = missing
            ? baseLabel + String(localized: "menu.file.open_recent.missing_suffix")
            : baseLabel
        Button {
            if missing {
                recentsStore.remove(item)
                return
            }
            Task { @MainActor in
                switch item.kind {
                case .file:
                    await LocalFileMenuCommands.openLocalFile(
                        at: item.url, engine: engine, recentsStore: recentsStore
                    )
                case .folder:
                    await LocalFileMenuCommands.openLocalFolder(
                        at: item.url, engine: engine, recentsStore: recentsStore
                    )
                case .m3u:
                    await LocalFileMenuCommands.openLocalM3U(
                        at: item.url, engine: engine, recentsStore: recentsStore
                    )
                }
            }
        } label: {
            // GAP E (2026-05-28): leading SF Symbol per kind replaces the
            // old "Folder: " / "Playlist: " prefix. macOS menu convention.
            // Missing items stay clickable (the click removes them); the
            // "(missing)" suffix is the user-visible cue, not .disabled().
            Label(label, systemImage: item.systemImage)
        }
    }
}

// MARK: - EnvironmentKey for SpotifyOAuthTokenProvider

private struct SpotifyOAuthProviderKey: EnvironmentKey {
    static let defaultValue: SpotifyOAuthTokenProvider? = nil
}

extension EnvironmentValues {
    /// The app-level Spotify OAuth token provider, set by `UzumeApp`.
    var spotifyOAuthProvider: SpotifyOAuthTokenProvider? {
        get { self[SpotifyOAuthProviderKey.self] }
        set { self[SpotifyOAuthProviderKey.self] = newValue }
    }
}

// MARK: - MissingAnalysisNotice

/// BR.7 (C10): shown once at launch when the stem separator couldn't load its weights.
@MainActor
enum MissingAnalysisNotice {
    static func show() {
        // Lands in the unified log, so Help › Report a Problem carries it too.
        lfLogger.error("ANALYSIS_UNAVAILABLE: stem separator failed to load (ML weights missing or damaged)")
        let alert = NSAlert()
        alert.messageText = String(localized: "analysis_unavailable.title")
        alert.informativeText = String(localized: "analysis_unavailable.body")
        alert.runModal()
    }
}
