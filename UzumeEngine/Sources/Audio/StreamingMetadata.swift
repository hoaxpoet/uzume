// StreamingMetadata — Polls running music apps for track changes.
// Uses AppleScript to query Apple Music and Spotify directly.
// MediaRemote private framework is blocked for signed apps on macOS 15+.
// Conforms to MetadataProviding for dependency injection.

import AppKit
import Foundation
import Shared
import os.log

private let logger = Logging.metadata

// MARK: - NowPlayingInfo

/// Parsed Now Playing info in a Sendable form.
public struct NowPlayingInfo: Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let duration: Double?
    public let source: MetadataSource

    public init(
        title: String?,
        artist: String?,
        album: String?,
        duration: Double?,
        source: MetadataSource = .nowPlaying
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.source = source
    }
}

// MARK: - NowPlayingQuery

/// One poll's result (BR.10): a playing track, nothing playing, or Automation denied (−1743).
public enum NowPlayingQuery: Sendable {
    case playing(NowPlayingInfo)
    case nothing
    case automationDenied(MetadataSource)
}

// MARK: - AppleScript Bridge

/// Queries running music apps via AppleScript for Now Playing info.
///
/// AppleScript works reliably from signed apps via the Automation framework.
/// Each target app triggers a one-time permission prompt. Supports Apple Music
/// and Spotify. Falls back gracefully if neither is running.
private enum AppleScriptBridge {

    /// Query Apple Music for the current track.
    static func queryAppleMusic() -> NowPlayingQuery {
        let script = """
        tell application "Music"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & (trackDuration as text)
            end if
        end tell
        """
        return executeScript(script, appName: "Music", source: .appleMusic)
    }

    /// Query Spotify for the current track.
    static func querySpotify() -> NowPlayingQuery {
        let script = """
        tell application "Spotify"
            if player state is playing then
                set trackName to name of current track
                set trackArtist to artist of current track
                set trackAlbum to album of current track
                set trackDuration to duration of current track
                return trackName & "||" & trackArtist & "||" & trackAlbum & "||" & ((trackDuration / 1000) as text)
            end if
        end tell
        """
        return executeScript(script, appName: "Spotify", source: .spotify)
    }

    /// Check if an app is running without launching it.
    static func isAppRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    /// Execute an AppleScript and parse the result.
    private static func executeScript(
        _ source: String,
        appName: String,
        source metadataSource: MetadataSource
    ) -> NowPlayingQuery {
        guard let script = NSAppleScript(source: source) else { return .nothing }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // BR.10 (E1): −1743 = Automation denied. Surfaced, not swallowed at .debug.
            if code == -1743 { return .automationDenied(metadataSource) }
            // -600 = app not running, -1728 = no current track — both expected.
            if code != -600 && code != -1728 {
                let message = error[NSAppleScript.errorMessage] as? String ?? "unknown"
                logger.debug("AppleScript error for \(appName): \(message)")
            }
            return .nothing
        }

        guard let output = result.stringValue else { return .nothing }
        let parts = output.components(separatedBy: "||")
        guard parts.count >= 4 else { return .nothing }

        return .playing(NowPlayingInfo(
            title: parts[0].isEmpty ? nil : parts[0],
            artist: parts[1].isEmpty ? nil : parts[1],
            album: parts[2].isEmpty ? nil : parts[2],
            duration: Double(parts[3]),
            source: metadataSource
        ))
    }

    /// Query the allowed music apps, returning the first playing track. A denial is returned
    /// when nothing was playing in an allowed app that answered (BR.10).
    static func queryNowPlaying(allowed: Set<MetadataSource>) -> NowPlayingQuery {
        var denied: NowPlayingQuery?
        let apps = StreamingMetadata.appsToQuery(
            allowed: allowed,
            appleMusicRunning: isAppRunning("com.apple.Music"),
            spotifyRunning: isAppRunning("com.spotify.client"))
        for app in apps {
            let result = app == .appleMusic ? queryAppleMusic() : querySpotify()
            if case .playing = result { return result }
            if case .automationDenied = result { denied = result }
        }
        return denied ?? .nothing
    }
}

// MARK: - StreamingMetadata

/// Observes running music apps and detects track changes.
///
/// Polls Apple Music and Spotify via AppleScript at a 2-second interval.
/// When the playing track identity changes (title + artist), fires `onTrackChange`.
/// All metadata is optional — gracefully handles no music app running.
public final class StreamingMetadata: MetadataProviding, @unchecked Sendable {

    // MARK: - State

    private(set) var pollingTask: Task<Void, Never>?
    private var _currentTrack: TrackMetadata?
    private var lastTrackIdentity: String?
    /// Bumped by every `stopObserving()`. A poll only writes state or fires if
    /// the generation it started under is still current (BUG-142).
    private var generation = 0
    private let lock = NSLock()

    /// Polling interval.
    private let pollInterval: Duration

    // MARK: - Testability

    /// Override this closure in tests to inject canned Now Playing info.
    /// Defaults to querying music apps via AppleScript.
    var nowPlayingReader: (@Sendable () async -> NowPlayingInfo?)?

    /// Override in tests to inject a full poll result, denial included (BR.10). Wins over
    /// `nowPlayingReader`.
    var queryReader: (@Sendable () async -> NowPlayingQuery)?

    /// Which apps to ask (BR.10 / E14). The session's own source; both for an ad-hoc session.
    public var allowedSources: Set<MetadataSource> {
        get { lock.withLock { _allowedSources } }
        set { lock.withLock { _allowedSources = newValue } }
    }
    private var _allowedSources: Set<MetadataSource> = [.appleMusic, .spotify]

    /// Fired once per `startObserving()` when macOS denies Automation for an allowed app (BR.10 / E1).
    public var onAutomationDenied: ((_ source: MetadataSource) -> Void)?
    private var deniedReported = false

    // MARK: - Init

    /// Create a streaming metadata observer.
    ///
    /// - Parameter pollInterval: How often to check Now Playing (default 2 seconds).
    public init(pollInterval: Duration = .seconds(2)) {
        self.pollInterval = pollInterval
    }

    // MARK: - MetadataProviding

    public var onTrackChange: ((_ event: TrackChangeEvent) -> Void)?

    public var currentTrack: TrackMetadata? {
        lock.withLock { _currentTrack }
    }

    public func startObserving() {
        stopObserving()
        let gen = lock.withLock { generation }

        pollingTask = Task { [weak self] in
            guard let self else { return }
            logger.info("Started observing Now Playing metadata via AppleScript")

            while !Task.isCancelled {
                await self.pollNowPlaying(generation: gen)

                do {
                    try await Task.sleep(for: self.pollInterval)
                } catch {
                    break
                }
            }
        }
    }

    public func stopObserving() {
        pollingTask?.cancel()
        pollingTask = nil
        lock.withLock {
            generation &+= 1
            _currentTrack = nil
            lastTrackIdentity = nil
            deniedReported = false
        }
        logger.info("Stopped observing Now Playing metadata")
    }

    // MARK: - Polling

    /// A poll whose `generation` is stale (stop ran while `reader()` was
    /// suspended) discards its result instead of firing across the boundary.
    private func pollNowPlaying(generation gen: Int) async {
        let query: NowPlayingQuery
        if let reader = queryReader {
            query = await reader()
        } else if let reader = nowPlayingReader {
            query = await reader().map { .playing($0) } ?? .nothing
        } else {
            // AppleScript is synchronous — run off the cooperative pool.
            let allowed = allowedSources
            query = await Task.detached {
                AppleScriptBridge.queryNowPlaying(allowed: allowed)
            }.value
        }

        if case .automationDenied(let source) = query {
            let report = lock.withLock { () -> Bool in
                guard generation == gen, !deniedReported else { return false }
                deniedReported = true
                return true
            }
            if report {
                logger.error("Now Playing: Automation denied for \(source.rawValue) (-1743)")
                onAutomationDenied?(source)
            }
        }

        let info: NowPlayingInfo?
        if case .playing(let playing) = query { info = playing } else { info = nil }

        guard let info else {
            lock.withLock {
                guard generation == gen else { return }
                _currentTrack = nil
                lastTrackIdentity = nil
            }
            return
        }

        let title = info.title
        let artist = info.artist
        let album = info.album
        let duration = info.duration

        let identity = trackIdentity(title: title, artist: artist)

        let track = TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            source: info.source
        )

        let (shouldFire, previous) = lock.withLock { () -> (Bool, TrackMetadata?) in
            guard generation == gen else { return (false, nil) }
            let prev = _currentTrack
            let changed = identity != lastTrackIdentity
            _currentTrack = track
            lastTrackIdentity = identity
            return (changed, prev)
        }

        if shouldFire {
            logger.info("Track change detected: \(track.title ?? "?") — \(track.artist ?? "?")")
            let event = TrackChangeEvent(previous: previous, current: track)
            onTrackChange?(event)
        }
    }

    // MARK: - Which apps to ask (BR.10 / E14)

    /// Apple Music first (most common on macOS), then Spotify — each only if the session uses it
    /// AND it is running (asking a closed app launches it; asking an unused one prompts for it).
    static func appsToQuery(
        allowed: Set<MetadataSource>, appleMusicRunning: Bool, spotifyRunning: Bool
    ) -> [MetadataSource] {
        var apps: [MetadataSource] = []
        if allowed.contains(.appleMusic), appleMusicRunning { apps.append(.appleMusic) }
        if allowed.contains(.spotify), spotifyRunning { apps.append(.spotify) }
        return apps
    }

    // MARK: - Identity

    /// Normalized track identity for change detection.
    /// Case-insensitive to avoid spurious events from metadata formatting.
    private func trackIdentity(title: String?, artist: String?) -> String {
        let normalizedTitle = title?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        let normalizedArtist = artist?.lowercased().trimmingCharacters(in: .whitespaces) ?? ""
        return "\(normalizedTitle)|\(normalizedArtist)"
    }
}
