// SpotifyConnectionViewModelTests — Unit tests for SpotifyConnectionViewModel.
// Uses MockSpotifyConnector with InstantDelay for synchronous retry testing.
// Increment U.10: silent-degrade tests removed; new error-state tests added.
// BUG-150: waits await the VM's own `debounceTask` / `connectTask` — never a
// wall-clock sleep, which a loaded main actor can outlast.

import Foundation
import Session
import Testing
@testable import UzumeApp

// MARK: - Tests

@Suite("SpotifyConnectionViewModel")
@MainActor
struct SpotifyConnectionViewModelTests {

    @Test("paste valid playlist URL populates preview state")
    func pasteValidPlaylist() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        await vm.debounceTask?.value
        if case .preview(let id) = vm.state {
            #expect(id == "37i9dQZF1DXcBWIGoYBM5M")
        } else {
            Issue.record("Expected .preview, got \(vm.state)")
        }
    }

    @Test("paste Spotify track URL sets .rejectedKind(.track)")
    func pasteTrackURL() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC"
        await vm.debounceTask?.value
        if case .rejectedKind(.track) = vm.state { } else {
            Issue.record("Expected .rejectedKind(.track), got \(vm.state)")
        }
    }

    @Test("paste garbage URL sets .invalid")
    func pasteGarbage() async throws {
        let vm = makeVM(connector: MockSpotifyConnector(result: .success([])))
        vm.text = "not a spotify link at all"
        await vm.debounceTask?.value
        #expect(vm.state == .invalid)
    }

    @Test("connect with 429 retries at backoff schedule [2s, 5s, 15s]")
    func connectRateLimitedRetriesAtBackoffSchedule() async throws {
        // Connector returns 429 every time (initial + 3 retries = 4 calls total).
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.rateLimited(retryAfterSeconds: 1.0))
        )
        let vm = makeVM(connector: connector)

        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value

        guard case .preview = vm.state else {
            Issue.record("Debounce did not fire: expected .preview, got \(vm.state)")
            return
        }

        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value

        if case .error = vm.state { } else {
            Issue.record("Expected .error after exhausting retries, got \(vm.state)")
        }
        #expect(connector.callCount == 4)
    }

    @Test("connect with spotifyPlaylistNotFound sets .notFound state")
    func connectNotFound() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.spotifyPlaylistNotFound)
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value
        #expect(vm.state == .notFound)
    }

    @Test("connect with spotifyPlaylistInaccessible sets .privatePlaylist state")
    func connectPrivatePlaylist() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.spotifyPlaylistInaccessible)
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value
        #expect(vm.state == .privatePlaylist)
    }

    @Test("connect with spotifyAuthFailure sets .authFailure state")
    func connectAuthFailure() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.spotifyAuthFailure("bad creds"))
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value
        #expect(vm.state == .authFailure)
    }

    @Test("authFailure copy names the xcconfig fix only when the Client ID is missing")
    func authFailureCopyDistinguishesMissingClientID() {
        let missing = String(localized: "connector.spotify.auth_failure.missing_client_id")
        let generic = String(localized: "connector.spotify.auth_failure")
        #expect(SpotifyConnectionViewModel.authFailureMessage(clientID: nil) == missing)
        #expect(SpotifyConnectionViewModel.authFailureMessage(clientID: "") == missing)
        #expect(SpotifyConnectionViewModel.authFailureMessage(clientID: "abc123") == generic)
    }

    @Test("successful connect calls startSession with .spotifyPlaylistURL source")
    func successfulConnectCallsStartSession() async throws {
        let connector = MockSpotifyConnector(result: .success([]))
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        await vm.debounceTask?.value

        // nonisolated(unsafe): written only once in this @Sendable closure, read after the connect task completes.
        nonisolated(unsafe) var capturedSource: PlaylistSource?
        vm.connect(startSession: { _, source in capturedSource = source })
        await vm.connectTask?.value

        if case .spotifyPlaylistURL = capturedSource {
            // Expected — no accessToken associated value.
        } else {
            Issue.record("Expected .spotifyPlaylistURL, got \(String(describing: capturedSource))")
        }
    }

    @Test("SpotifyConnectionView carries correct accessibilityID")
    func viewIdentifier() {
        #expect(SpotifyConnectionView.accessibilityID == "uzume.view.spotify.connection")
    }

    // PUB.2 regression (ultra-review): the error-state "Try Again" CTA called
    // connect(), whose .preview guard made it a silent no-op from .error —
    // zero new connector calls. retry() must actually re-attempt.
    @Test("retry from .error re-attempts the connection with the stored playlist ID")
    func retryFromErrorReattempts() async throws {
        let connector = MockSpotifyConnector(
            result: .failure(PlaylistConnectorError.rateLimited(retryAfterSeconds: 1.0))
        )
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value
        guard case .error = vm.state else {
            Issue.record("Setup failed: expected .error, got \(vm.state)")
            return
        }
        let callsAfterConnect = connector.callCount
        #expect(callsAfterConnect == 4)   // initial + 3 backoff retries

        vm.retry(startSession: { _, _ in })
        await vm.connectTask?.value

        // The old code path made ZERO further calls (dead button). retry()
        // runs a full fresh attempt (another initial + 3 backoff retries).
        #expect(connector.callCount == callsAfterConnect + 4,
                "retry must re-invoke the connector from .error")
        if case .error = vm.state { } else {
            Issue.record("Expected .error after failed retry, got \(vm.state)")
        }
    }

    @Test("retry outside .error is a no-op")
    func retryOutsideErrorIsNoOp() async throws {
        let connector = MockSpotifyConnector(result: .success([]))
        let vm = makeVM(connector: connector)
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        guard case .preview = vm.state else {
            Issue.record("Setup failed: expected .preview, got \(vm.state)")
            return
        }
        vm.retry(startSession: { _, _ in })
        #expect(connector.callCount == 0, "retry must not fire outside .error")
    }

    // MARK: - Helpers

    private func makeVM(connector: MockSpotifyConnector) -> SpotifyConnectionViewModel {
        SpotifyConnectionViewModel(connector: connector, delayProvider: InstantDelay())
    }
}

// MARK: - MockSpotifyConnector

private final class MockSpotifyConnector: PlaylistConnecting, @unchecked Sendable {
    private let result: Result<[TrackIdentity], PlaylistConnectorError>
    private(set) var callCount = 0

    init(result: Result<[TrackIdentity], PlaylistConnectorError>) {
        self.result = result
    }

    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        callCount += 1
        switch result {
        case .success(let tracks): return tracks
        case .failure(let error):  throw error
        }
    }
}

// MARK: - SpotifyConnectionViewModel — OAuth state tests

@Suite("SpotifyConnectionViewModel — OAuth states")
@MainActor
struct SpotifyConnectionViewModelOAuthTests {

    @Test("connect with spotifyLoginRequired and unauthenticated provider sets .requiresLogin")
    func connectLoginRequiredUnauthenticated() async throws {
        let connector = MockOAuthConnector(
            result: .failure(PlaylistConnectorError.spotifyLoginRequired)
        )
        let vm = SpotifyConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay(),
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: false)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value
        #expect(vm.state == .requiresLogin)
    }

    @Test("connect with spotifyLoginRequired and authenticated provider sets .privatePlaylist")
    func connectLoginRequiredAuthenticated() async throws {
        let connector = MockOAuthConnector(
            result: .failure(PlaylistConnectorError.spotifyLoginRequired)
        )
        let vm = SpotifyConnectionViewModel(
            connector: connector,
            delayProvider: InstantDelay(),
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: true)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.connect(startSession: { _, _ in })
        await vm.connectTask?.value
        #expect(vm.state == .privatePlaylist)
    }

    @Test("login action success retries connect and calls startSession")
    func loginActionSuccess() async throws {
        nonisolated(unsafe) var sessionStarted = false
        let vm = SpotifyConnectionViewModel(
            connector: MockOAuthConnector(result: .success([])),
            delayProvider: InstantDelay(),
            loginAction: { },
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: true)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.login(startSession: { _, _ in sessionStarted = true })
        await vm.connectTask?.value
        #expect(sessionStarted)
    }

    @Test("login action failure sets .authFailure")
    func loginActionFailure() async throws {
        let vm = SpotifyConnectionViewModel(
            connector: MockOAuthConnector(result: .success([])),
            delayProvider: InstantDelay(),
            loginAction: { throw PlaylistConnectorError.spotifyAuthFailure("denied") },
            oauthProvider: MockOAuthLoginProvider(isAuthenticated: false)
        )
        vm.text = "https://open.spotify.com/playlist/abc"
        await vm.debounceTask?.value
        vm.login(startSession: { _, _ in })
        await vm.connectTask?.value
        #expect(vm.state == .authFailure)
    }
}

// MARK: - OAuth Mocks

private final class MockOAuthConnector: PlaylistConnecting, @unchecked Sendable {
    private let result: Result<[TrackIdentity], PlaylistConnectorError>

    init(result: Result<[TrackIdentity], PlaylistConnectorError>) {
        self.result = result
    }

    func connect(source: PlaylistSource) async throws -> [TrackIdentity] {
        switch result {
        case .success(let tracks): return tracks
        case .failure(let error):  throw error
        }
    }
}

private actor MockOAuthLoginProvider: SpotifyOAuthLoginProviding {
    private let _isAuthenticated: Bool
    init(isAuthenticated: Bool) { self._isAuthenticated = isAuthenticated }
    var isAuthenticated: Bool { _isAuthenticated }
    func login() async throws {}
    func handleCallback(url: URL) async {}
    func logout() async {}
}
