// PreviewResolver — Resolves 30-second preview URLs for playlist tracks.
// Primary source: TrackIdentity.spotifyPreviewURL (Spotify Web API, inline in /items response).
// Fallback: iTunes Search API (free, no auth, 20 req/min) for non-Spotify tracks or tracks
// where Spotify returns null for preview_url.
// Results are cached in memory so each track is only ever fetched once.

import Foundation
import os

// MARK: - Protocol

/// Resolves a downloadable 30-second preview URL for a track.
public protocol PreviewResolving: Sendable {
    /// Returns a preview URL for the given track, or `nil` if none is available.
    /// Implementations must be safe to call concurrently.
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL?

    /// Returns the preview URL plus the catalog's own names for the matched
    /// track (SCAN.2 — a scanned title may be cut off; the catalog's is whole).
    func resolvePreviewMatch(for track: TrackIdentity) async throws -> PreviewMatch?
}

extension PreviewResolving {
    /// Default: URL only, no catalog names (resolvers that don't search a catalog).
    public func resolvePreviewMatch(for track: TrackIdentity) async throws -> PreviewMatch? {
        try await resolvePreviewURL(for: track).map { PreviewMatch(previewURL: $0) }
    }
}

// MARK: - PreviewMatch

/// A resolved preview and, when it came from a catalog search, that catalog's
/// full title and artist for the matched track.
public struct PreviewMatch: Sendable, Equatable {
    /// The 30-second preview.
    public let previewURL: URL
    /// The catalog's title (iTunes `trackName`), when known.
    public let catalogTitle: String?
    /// The catalog's artist (iTunes `artistName`), when known.
    public let catalogArtist: String?

    /// Create a match.
    public init(previewURL: URL, catalogTitle: String? = nil, catalogArtist: String? = nil) {
        self.previewURL = previewURL
        self.catalogTitle = catalogTitle
        self.catalogArtist = catalogArtist
    }
}

// MARK: - Concrete Implementation

/// Resolves 30-second preview URLs for tracks.
///
/// Primary source: `TrackIdentity.spotifyPreviewURL` (inline from the Spotify
/// Web API `/items` response — no network request needed).
/// Fallback: iTunes Search API (free, no auth, 20 req/min) for non-Spotify tracks
/// or tracks where Spotify returns `null` for `preview_url`.
///
/// Results are cached in memory — a second call for the same `TrackIdentity`
/// returns immediately without a network request. Rate-limiting is enforced
/// transparently: if the request window is full, callers are suspended until
/// a slot opens rather than receiving an error.
public final class PreviewResolver: PreviewResolving, @unchecked Sendable {

    // MARK: - Dependencies

    /// Injectable network fetcher. Defaults to `URLSession.shared`.
    /// Replace in tests to avoid real network calls.
    public var networkFetcher: (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    // MARK: - Rate-limit Configuration

    /// The sliding-window limiter this resolver acquires from. Production uses
    /// `ITunesRateLimiter.shared` so the resolver and the app's metadata
    /// fetcher share ONE 20/min window (PUB.6, ultra-review — previously each
    /// client ran its own, and the fetcher had none). Tests inject a private
    /// instance for isolation.
    private let rateLimiter: ITunesRateLimiter

    /// Maximum requests allowed within `rateLimitWindow`. Defaults to 20 (iTunes limit).
    /// Forwards to the limiter (kept for API/test compatibility).
    public var rateLimitPerWindow: Int {
        get { rateLimiter.maxRequestsPerWindow }
        set { rateLimiter.maxRequestsPerWindow = newValue }
    }

    /// Duration of the sliding rate-limit window in seconds. Defaults to 60.
    /// Forwards to the limiter (kept for API/test compatibility).
    public var rateLimitWindow: TimeInterval {
        get { rateLimiter.window }
        set { rateLimiter.window = newValue }
    }

    // MARK: - State

    private let stateLock = NSLock()
    // nil outer = not cached; inner = .some(match) or .some(nil)
    private var cache: [TrackIdentity: PreviewMatch?] = [:]

    private static let baseURL = "https://itunes.apple.com/search"

    // MARK: - Init

    public init(rateLimiter: ITunesRateLimiter = .shared) {
        self.rateLimiter = rateLimiter
    }

    // MARK: - PreviewResolving

    public func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        try await resolvePreviewMatch(for: track)?.previewURL
    }

    public func resolvePreviewMatch(for track: TrackIdentity) async throws -> PreviewMatch? {
        // Fast path: return cached result if present (including "no preview" nil).
        if let cached = lockedCachedMatch(for: track) {
            return cached
        }

        // Fast path: Spotify already provided the preview URL in the playlist response.
        // Seed the cache and return immediately — no iTunes Search API call needed.
        if let spotifyURL = track.spotifyPreviewURL {
            let match = PreviewMatch(previewURL: spotifyURL)
            stateLock.withLock { cache[track] = .some(match) }
            return match
        }

        // SCAN (D-260) verification for EVERY track (BR.19 / BUG-152): the first hit
        // for "artist title" was a different song for 8 % of rows (an underscore or an
        // accent breaks the search; a song the catalog lacks returns whatever ranks
        // first), and stems, grid and energy were then measured on the wrong music.
        // A track that wasn't read off a screen is its own uncut reading.
        let reading = track.screenReading
            ?? ScreenReading(title: track.title, titleCutOff: false, artistLine: track.artist)
        let limit = ScreenReadMatchPolicy.candidateLimit
        guard let data = await search(term: "\(track.artist) \(track.title)", limit: limit, for: track) else {
            return nil   // transient failure — uncached (PUB.2)
        }
        var match = ScreenReadMatchPolicy.bestMatch(in: data, for: track, reading: reading)
        // A badge fused onto a screen-read artist ("DSZA"), or a character the search
        // can't take in the artist, spoils the term itself: one title-only retry,
        // verified the same way.
        if match == nil, !track.artist.isEmpty {
            guard let retry = await search(term: track.title, limit: limit, for: track) else { return nil }
            match = ScreenReadMatchPolicy.bestMatch(in: retry, for: track, reading: reading)
        }
        stateLock.withLock { cache[track] = .some(match) }
        if let match {
            logger.debug("Resolved preview for '\(track.title)': \(match.previewURL)")
        } else {
            logger.info("No preview URL found for '\(track.title)'")
        }
        return match
    }

    // MARK: - Private Helpers

    /// Returns the cached result for `track`, or `nil` if not yet cached.
    ///
    /// Returns `PreviewMatch??`:
    ///  - `.none` — not in cache at all (caller must fetch)
    ///  - `.some(.none)` — cached as "no preview available"
    ///  - `.some(.some(match))` — cached preview
    private func lockedCachedMatch(for track: TrackIdentity) -> PreviewMatch?? {
        stateLock.withLock { cache[track] }
    }

    /// One rate-limited iTunes Search request. Returns the body of a 200, or nil
    /// for a transient failure (thrown error / non-200), which callers must NOT
    /// cache: a poisoned entry made the D-061(d) network-recovery retry
    /// permanently unable to succeed for the track (PUB.2, ultra-review).
    ///
    /// BR.19 / C7: a 429, a 5xx or a thrown error (timeout, offline) is retried after each of
    /// `retryDelays` — before, one blip was final for the session. A 200 whose body is not JSON
    /// (a captive portal's login page) is transient too, never parsed into a cached "no preview".
    private func search(term: String, limit: Int, for track: TrackIdentity) async -> Data? {
        guard let request = buildRequest(term: term, limit: limit) else {
            logger.error("Could not build iTunes search request for '\(track.title)'")
            return nil
        }
        for attempt in 0...retryDelays.count {
            if attempt > 0 { try? await Task.sleep(for: retryDelays[attempt - 1]) }
            // Enforce rate limit before sending a request.
            await rateLimiter.acquire()
            do {
                let (data, response) = try await networkFetcher(request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 {
                    guard Self.isJSON(data) else {
                        logger.info("Non-JSON 200 for '\(track.title)' (captive portal?) — uncached")
                        return nil
                    }
                    return data
                }
                guard status == 429 || (500...599).contains(status) else {
                    logger.info("HTTP \(status) for '\(track.title)' — returning nil uncached")
                    return nil
                }
                logger.info("HTTP \(status) for '\(track.title)' — retry \(attempt + 1)")
            } catch {
                logger.error("iTunes Search request failed for '\(track.title)': \(error) — retry \(attempt + 1)")
            }
        }
        return nil   // still failing after the retries: transient, uncached (PUB.2)
    }

    /// Backoff between attempts of one lookup (BR.19 / C7). Tests shorten it.
    var retryDelays: [Duration] = [.seconds(2), .seconds(6)]

    static func isJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    private func buildRequest(term: String, limit: Int) -> URLRequest? {
        guard var components = URLComponents(string: Self.baseURL) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "country", value: ITunesStorefront.country)   // BR.19 / C8
        ]
        guard let url = components.url else { return nil }
        return URLRequest(url: url, timeoutInterval: 10)
    }
}

// MARK: - Logger

private let logger = Logger(subsystem: "io.uzume", category: "PreviewResolver")
