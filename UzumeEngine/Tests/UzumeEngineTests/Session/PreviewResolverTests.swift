// PreviewResolverTests — Unit tests for PreviewResolver.
// All network calls are injected via the networkFetcher closure.
// No real iTunes or network access required.

import Testing
import Foundation
@testable import Session

// MARK: - Thread-safe counter for concurrent test assertions

private final class AtomicCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

// MARK: - Helpers

/// Records the `country` of every request (BR.19 / C8).
private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String?] = []
    func record(_ request: URLRequest) {
        let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
        lock.withLock { seen.append(items?.first { $0.name == "country" }?.value) }
    }
    var countries: [String?] { lock.withLock { seen } }
}

private func makeResolver() -> PreviewResolver {
    // PUB.6: a PRIVATE limiter per test — the production default is the
    // process-wide ITunesRateLimiter.shared, which parallel test suites would
    // contend on (and rateLimiting_respectsLimit mutates the window config).
    let resolver = PreviewResolver(rateLimiter: ITunesRateLimiter())
    resolver.retryDelays = [.zero, .zero]   // BR.19: the backoff's order, not its wall-clock
    return resolver
}

private func makeTrack(
    title: String = "Bohemian Rhapsody",
    artist: String = "Queen"
) -> TrackIdentity {
    TrackIdentity(title: title, artist: artist)
}

/// Build a fake iTunes Search API response containing one result with `previewUrl`.
private func itunesResponse(previewURL: String = "https://example.com/preview.m4a") -> Data {
    let json: [String: Any] = [
        "resultCount": 1,
        "results": [[
            "trackName": "Bohemian Rhapsody",
            "artistName": "Queen",
            "previewUrl": previewURL,
            "kind": "song"
        ]]
    ]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

/// Build a fake iTunes response with no results.
private func emptyItunesResponse() -> Data {
    let json: [String: Any] = ["resultCount": 0, "results": []]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

private func ok200() -> HTTPURLResponse {
    // swiftlint:disable:next force_unwrapping
    HTTPURLResponse(url: URL(string: "https://itunes.apple.com/search")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

// MARK: - Suite

@Suite("PreviewResolver")
struct PreviewResolverTests {

    // MARK: - Known Track

    @Test func knownTrack_resolvesToURL() async throws {
        let resolver = makeResolver()
        let expectedURL = URL(string: "https://example.com/preview.m4a")

        resolver.networkFetcher = { _ in
            (itunesResponse(previewURL: "https://example.com/preview.m4a"), ok200())
        }

        let url = try await resolver.resolvePreviewURL(for: makeTrack())

        #expect(url == expectedURL)
    }

    // MARK: - Unknown Track

    @Test func unknownTrack_returnsNil() async throws {
        let resolver = makeResolver()

        resolver.networkFetcher = { _ in
            (emptyItunesResponse(), ok200())
        }

        let url = try await resolver.resolvePreviewURL(for: makeTrack(title: "Nonexistent Song XYZ"))

        #expect(url == nil)
    }

    // MARK: - Preview URL Format

    @Test func previewURL_isValidAAC() async throws {
        let resolver = makeResolver()
        // iTunes preview URLs end in .m4a (AAC in an MPEG-4 container).
        let aacURL = "https://audio-ssl.itunes.apple.com/itunes-assets/Music/track.m4a"
        resolver.networkFetcher = { _ in
            (itunesResponse(previewURL: aacURL), ok200())
        }

        let url = try await resolver.resolvePreviewURL(for: makeTrack())
        let resolved = try #require(url)

        // iTunes preview URLs are HTTPS and typically end in .m4a.
        #expect(resolved.scheme == "https")
        #expect(resolved.pathExtension == "m4a" || resolved.absoluteString.contains("itunes"))
    }

    // MARK: - Rate Limiting

    @Test func rateLimiting_respectsLimit() async throws {
        let resolver = makeResolver()
        // Use a very short window so the test completes quickly.
        resolver.rateLimitPerWindow = 3
        resolver.rateLimitWindow = 0.5

        // Use a thread-safe counter — networkFetcher is called from concurrent tasks.
        let counter = AtomicCounter()
        resolver.networkFetcher = { _ in
            counter.increment()
            return (itunesResponse(), ok200())
        }

        // Fire more requests than the rate limit allows in the window.
        // All four should eventually complete (after throttling), not throw.
        let tracks = (0..<4).map { i in makeTrack(title: "Track \(i)", artist: "Artist \(i)") }
        let start = Date()

        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask {
                    _ = try? await resolver.resolvePreviewURL(for: track)
                }
            }
        }

        let elapsed = Date().timeIntervalSince(start)
        // 4 requests at 3/0.5s limit means the 4th must wait at least ~0.5s.
        #expect(elapsed >= 0.4)
        // All 4 lookups went through; each is two requests, because the stub answers every
        // track with "Bohemian Rhapsody — Queen" and a non-matching first hit gets one
        // title-only retry (BR.19 / BUG-152 verification).
        #expect(counter.value == 8)
    }

    // MARK: - Network Timeout

    @Test func networkTimeout_returnsNilGracefully() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in
            throw URLError(.timedOut)
        }

        // Should not throw — returns nil instead.
        let url = try await resolver.resolvePreviewURL(for: makeTrack())
        #expect(url == nil)
    }

    // MARK: - Spotify fast path

    @Test func spotifyPreviewURL_returnedWithoutNetworkCall() async throws {
        let resolver = makeResolver()
        var networkCallCount = 0
        resolver.networkFetcher = { _ in
            networkCallCount += 1
            return (itunesResponse(), ok200())
        }

        let spotifyURL = URL(string: "https://p.scdn.co/mp3-preview/abc123.mp3")
        let track = TrackIdentity(title: "Roslyn", artist: "Bon Iver", spotifyPreviewURL: spotifyURL)

        let resolved = try await resolver.resolvePreviewURL(for: track)
        #expect(resolved == spotifyURL)
        #expect(networkCallCount == 0, "iTunes Search API must not be called when Spotify provides a URL")
    }

    @Test func spotifyPreviewURL_cachedOnSecondCall() async throws {
        let resolver = makeResolver()
        var networkCallCount = 0
        resolver.networkFetcher = { _ in
            networkCallCount += 1
            return (itunesResponse(), ok200())
        }

        let spotifyURL = URL(string: "https://p.scdn.co/mp3-preview/abc123.mp3")
        let track = TrackIdentity(title: "Roslyn", artist: "Bon Iver", spotifyPreviewURL: spotifyURL)

        _ = try await resolver.resolvePreviewURL(for: track)
        let second = try await resolver.resolvePreviewURL(for: track)
        #expect(second == spotifyURL)
        #expect(networkCallCount == 0)
    }

    @Test func nullSpotifyPreviewURL_fallsBackToItunes() async throws {
        let resolver = makeResolver()
        var networkCallCount = 0
        resolver.networkFetcher = { _ in
            networkCallCount += 1
            return (itunesResponse(previewURL: "https://example.com/fallback.m4a"), ok200())
        }

        // spotifyPreviewURL == nil means Spotify had no preview; fall through to iTunes.
        let track = TrackIdentity(title: "Bohemian Rhapsody", artist: "Queen", spotifyPreviewURL: nil)
        let resolved = try await resolver.resolvePreviewURL(for: track)
        #expect(resolved == URL(string: "https://example.com/fallback.m4a"))
        #expect(networkCallCount == 1)
    }

    // MARK: - Cache

    @Test func multipleResolves_usesCache() async throws {
        let resolver = makeResolver()
        var fetchCount = 0

        resolver.networkFetcher = { _ in
            fetchCount += 1
            return (itunesResponse(), ok200())
        }

        let track = makeTrack()
        let first = try await resolver.resolvePreviewURL(for: track)
        let second = try await resolver.resolvePreviewURL(for: track)
        let third = try await resolver.resolvePreviewURL(for: track)

        // Network should be called exactly once; subsequent calls hit the cache.
        #expect(fetchCount == 1)
        #expect(first == second)
        #expect(second == third)
    }

    // PUB.2 regression (ultra-review): a transient non-200 (429/5xx) must NOT
    // poison the cache — the old `cache[track] = .some(nil)` made the
    // D-061(d) network-recovery retry permanently unable to succeed.
    @Test func transientNon200_isNotCached_retryCanSucceed() async throws {
        let resolver = makeResolver()
        var fetchCount = 0

        resolver.networkFetcher = { req in
            fetchCount += 1
            if fetchCount == 1 {
                // swiftlint:disable:next force_unwrapping
                let rateLimited = HTTPURLResponse(
                    url: req.url ?? URL(fileURLWithPath: "/"),
                    statusCode: 429, httpVersion: nil, headerFields: nil)!
                return (Data(), rateLimited)
            }
            return (itunesResponse(), ok200())
        }

        // BR.19 / C7: the 429 is retried inside the lookup, so it succeeds on attempt two.
        let track = makeTrack()
        let first = try await resolver.resolvePreviewURL(for: track)
        #expect(fetchCount == 2, "one retry after the 429")
        #expect(first != nil, "a transient failure is retried, not final")
    }

    // A definitive 200-with-empty-results IS cached (that genuinely means
    // "no preview exists") — unchanged behaviour, pinned here.
    @Test func definitiveNoPreview_staysCached() async throws {
        let resolver = makeResolver()
        var fetchCount = 0

        resolver.networkFetcher = { _ in
            fetchCount += 1
            return (emptyItunesResponse(), ok200())
        }

        let track = makeTrack()
        _ = try await resolver.resolvePreviewURL(for: track)
        _ = try await resolver.resolvePreviewURL(for: track)
        #expect(fetchCount == 2, "the full search + one title-only retry; then cached, no re-query")
    }

    // MARK: - BR.19

    /// C7: every attempt failing still leaves the track uncached — the next lookup re-queries.
    @Test func persistentFailure_isRetried_thenLeftUncached() async throws {
        let resolver = makeResolver()
        let counter = AtomicCounter()
        resolver.networkFetcher = { req in
            counter.increment()
            // swiftlint:disable:next force_unwrapping
            return (Data(), HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        let track = makeTrack()
        #expect(try await resolver.resolvePreviewURL(for: track) == nil)
        #expect(counter.value == 3, "the first attempt + two retries")
        _ = try await resolver.resolvePreviewURL(for: track)
        #expect(counter.value == 6, "not cached: the next lookup asks again")
    }

    /// C7: a captive portal answers 200 with HTML — transient, never a cached "no preview".
    @Test func captivePortalHTML_isNotCached() async throws {
        let resolver = makeResolver()
        let counter = AtomicCounter()
        resolver.networkFetcher = { _ in
            counter.increment()
            return counter.value == 1 ? (Data("<html>Log in to Wi-Fi</html>".utf8), ok200()) : (itunesResponse(), ok200())
        }
        let track = makeTrack()
        #expect(try await resolver.resolvePreviewURL(for: track) == nil)
        #expect(try await resolver.resolvePreviewURL(for: track) != nil, "the portal page was not cached")
    }

    /// BUG-152: a first hit that is another song is rejected, not trusted.
    @Test func aDifferentSong_isRejected() async throws {
        let resolver = makeResolver()
        resolver.networkFetcher = { _ in (itunesResponse(), ok200()) }   // always "Bohemian Rhapsody — Queen"
        let wrong = try await resolver.resolvePreviewURL(for: makeTrack(title: "Not Techno", artist: "i_o"))
        #expect(wrong == nil)
        let right = try await resolver.resolvePreviewURL(for: makeTrack())
        #expect(right != nil)
    }

    /// C8: the request names the Mac's storefront; an unknown region asks the US store.
    @Test func requestsNameTheStorefront() async throws {
        #expect(ITunesStorefront.country(for: "GB") == "GB")
        #expect(ITunesStorefront.country(for: "de") == "DE")
        #expect(ITunesStorefront.country(for: nil) == "US")
        #expect(ITunesStorefront.country(for: "419") == "US", "a UN region code is not a store")
        let resolver = makeResolver()
        let asked = RequestLog()
        resolver.networkFetcher = { req in
            asked.record(req)
            return (itunesResponse(), ok200())
        }
        _ = try await resolver.resolvePreviewURL(for: makeTrack())
        #expect(asked.countries == [ITunesStorefront.country])
    }
}
