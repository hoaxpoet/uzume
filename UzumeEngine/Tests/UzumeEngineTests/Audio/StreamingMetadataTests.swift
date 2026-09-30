// StreamingMetadataTests — Tests for Now Playing polling and track change detection.

import Testing
import Foundation
@testable import Audio
@testable import Shared

/// Thread-safe wrapper for mutable test state.
private final class AtomicValue<T: Sendable>: @unchecked Sendable {
    private var _value: T
    private let lock = NSLock()

    init(_ value: T) { _value = value }

    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// Parks a `nowPlayingReader` call until the test releases it (BUG-142).
private actor ReaderGate {
    private var parked: CheckedContinuation<Void, Never>?
    private var parkedWaiter: CheckedContinuation<Void, Never>?

    func park() async {
        await withCheckedContinuation { continuation in
            parked = continuation
            parkedWaiter?.resume()
            parkedWaiter = nil
        }
    }

    func waitUntilParked() async {
        if parked != nil { return }
        await withCheckedContinuation { parkedWaiter = $0 }
    }

    func release() {
        parked?.resume()
        parked = nil
    }
}

@Suite("StreamingMetadata")
struct StreamingMetadataTests {

    // MARK: - Helpers

    private func makeInfo(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        duration: Double? = nil
    ) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: artist, album: album, duration: duration)
    }

    // MARK: - Tests

    @Test func trackChange_differentTitle_emitsEvent() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)
        let info = makeInfo(title: "Bohemian Rhapsody", artist: "Queen")
        metadata.nowPlayingReader = { info }

        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(callCount.value == 1)
    }

    @Test func trackChange_sameTitle_noRedundantEvent() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)
        let info = makeInfo(title: "Hey Jude", artist: "The Beatles")
        metadata.nowPlayingReader = { info }

        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(300))
        metadata.stopObserving()

        #expect(callCount.value == 1)
    }

    @Test func trackChange_eventContainsTitleAndArtist() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let receivedEvent = AtomicValue<TrackChangeEvent?>(nil)
        let info = makeInfo(title: "Stairway to Heaven", artist: "Led Zeppelin", duration: 482)
        metadata.nowPlayingReader = { info }

        metadata.onTrackChange = { event in
            receivedEvent.value = event
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        let event = receivedEvent.value
        #expect(event != nil)
        #expect(event?.current.title == "Stairway to Heaven")
        #expect(event?.current.artist == "Led Zeppelin")
        #expect(event?.current.duration == 482)
        #expect(event?.previous == nil)
    }

    @Test func trackChange_secondTrack_hasPrevious() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let events = AtomicValue<[TrackChangeEvent]>([])

        let trackA = makeInfo(title: "Track A", artist: "Artist A")
        let trackB = makeInfo(title: "Track B", artist: "Artist B")
        let currentInfo = AtomicValue<NowPlayingInfo>(trackA)

        metadata.nowPlayingReader = { currentInfo.value }
        metadata.onTrackChange = { event in
            events.value.append(event)
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))

        currentInfo.value = trackB
        // 300ms gives 250ms margin over the 50ms poll interval — accounts for
        // scheduling jitter under parallel test execution.
        try await Task.sleep(for: .milliseconds(300))
        metadata.stopObserving()

        #expect(events.value.count == 2)
        #expect(events.value[1].previous?.title == "Track A")
        #expect(events.value[1].current.title == "Track B")
    }

    /// BUG-142: a poll in flight when `stopObserving()` runs must not fire an
    /// event or repopulate `currentTrack` once it resumes.
    @Test func stopObserving_whilePollInFlight_firesNoEvent() async {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)
        let gate = ReaderGate()
        let info = makeInfo(title: "Track A", artist: "Artist A")
        metadata.nowPlayingReader = {
            await gate.park()
            return info
        }
        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        await gate.waitUntilParked()
        let poll = metadata.pollingTask
        metadata.stopObserving()
        await gate.release()
        await poll?.value

        #expect(callCount.value == 0)
        #expect(metadata.currentTrack == nil)
    }

    @Test func noNowPlaying_returnsNilMetadata() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)

        metadata.nowPlayingReader = { nil }
        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(200))
        metadata.stopObserving()

        #expect(metadata.currentTrack == nil)
        #expect(callCount.value == 0)
    }

    @Test func conformsToMetadataProviding() {
        let metadata = StreamingMetadata()
        let provider: any MetadataProviding = metadata
        #expect(provider.currentTrack == nil)
    }

    @Test func trackIdentity_caseInsensitive() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(50))
        let callCount = AtomicValue(0)

        let infoUpper = makeInfo(title: "SONG", artist: "ARTIST")
        let infoLower = makeInfo(title: "song", artist: "artist")
        let currentInfo = AtomicValue<NowPlayingInfo>(infoUpper)

        metadata.nowPlayingReader = { currentInfo.value }
        metadata.onTrackChange = { _ in
            callCount.value += 1
        }

        metadata.startObserving()
        try await Task.sleep(for: .milliseconds(150))

        currentInfo.value = infoLower
        try await Task.sleep(for: .milliseconds(150))
        metadata.stopObserving()

        #expect(callCount.value == 1)
    }
}

// MARK: - BR.11 (audit E2): a pause is not a new song

@Suite("A pause is not a new song (BR.11)")
struct PauseIsNotANewSongTests {

    /// Scripted poll results, one per poll, then the last forever; counts polls.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var steps: [NowPlayingInfo?]
        private var polls = 0
        init(_ steps: [NowPlayingInfo?]) { self.steps = steps }
        func next() -> NowPlayingInfo? {
            lock.withLock {
                polls += 1
                return steps.count > 1 ? steps.removeFirst() : steps.first ?? nil
            }
        }
        var pollCount: Int { lock.withLock { polls } }
    }

    private func info(_ title: String) -> NowPlayingInfo {
        NowPlayingInfo(title: title, artist: "Artist", album: nil, duration: 200)
    }

    private func run(_ script: Script, untilPolls polls: Int) async throws -> [TrackChangeEvent] {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(5))
        let events = AtomicValue<[TrackChangeEvent]>([])
        metadata.nowPlayingReader = { script.next() }
        metadata.onTrackChange = { events.value.append($0) }
        metadata.startObserving()
        for _ in 0..<400 where script.pollCount < polls { try await Task.sleep(for: .milliseconds(10)) }
        metadata.stopObserving()
        return events.value
    }

    @Test func pausedThenResumed_sameSong_firesOnce() async throws {
        // Playing A, then paused (nil) for several polls, then A again.
        let script = Script([info("A"), nil, nil, nil, info("A"), info("A")])
        let events = try await run(script, untilPolls: 8)
        #expect(events.count == 1, "the resume is not a second track change")
        #expect(events.first?.current.title == "A")
    }

    @Test func pausedThenADifferentSong_isATrackChange() async throws {
        let script = Script([info("A"), nil, nil, info("B"), info("B")])
        let events = try await run(script, untilPolls: 7)
        #expect(events.map(\.current.title) == ["A", "B"])
        #expect(events.last?.previous?.title == "A", "B's previous is A, not nil")
    }
}

// MARK: - BR.10 (audit E1, E12, E14): Automation denied; only the session's own app

@Suite("Now Playing: Automation denied, and only the session's own app (BR.10)")
struct NowPlayingPermissionTests {

    /// Counts polls and denials from any thread; `waitUntil` orders on the signal, not the clock.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var polls = 0
        private var denials: [MetadataSource] = []
        func poll() { lock.withLock { polls += 1 } }
        func deny(_ source: MetadataSource) { lock.withLock { denials.append(source) } }
        var pollCount: Int { lock.withLock { polls } }
        var denied: [MetadataSource] { lock.withLock { denials } }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<400 where !condition() { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func automationDenied_isReportedOncePerObservation() async throws {
        let metadata = StreamingMetadata(pollInterval: .milliseconds(10))
        let counter = Counter()
        metadata.queryReader = { counter.poll(); return .automationDenied(.spotify) }
        metadata.onAutomationDenied = { counter.deny($0) }

        metadata.startObserving()
        try await waitUntil { counter.pollCount >= 5 }
        metadata.stopObserving()
        #expect(counter.pollCount >= 5)
        #expect(counter.denied == [.spotify], "one report, not one per 2 s poll")

        metadata.startObserving()        // a new session reports again
        try await waitUntil { counter.denied.count >= 2 }
        metadata.stopObserving()
        #expect(counter.denied == [.spotify, .spotify])
    }

    @Test func aSpotifySession_neverAsksMusic_andAClosedAppIsNeverAsked() {
        #expect(StreamingMetadata.appsToQuery(allowed: [.spotify], appleMusicRunning: true, spotifyRunning: true)
                == [.spotify])
        #expect(StreamingMetadata.appsToQuery(allowed: [.appleMusic], appleMusicRunning: true, spotifyRunning: true)
                == [.appleMusic])
        #expect(StreamingMetadata.appsToQuery(allowed: [.appleMusic, .spotify],
                                              appleMusicRunning: false, spotifyRunning: true) == [.spotify])
    }

    @Test func localFileModes_startNoNowPlayingPolling() {
        #expect(InputMode.systemAudio.isCapture)
        #expect(!InputMode.localFilePlayback(URL(fileURLWithPath: "/tmp/a.m4a")).isCapture)
        #expect(!InputMode.localFile(URL(fileURLWithPath: "/tmp/a.m4a")).isCapture)
    }
}
