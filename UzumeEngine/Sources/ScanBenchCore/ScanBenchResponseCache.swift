// ScanBenchResponseCache — disk cache of iTunes Search responses for ScanBench (SCAN.0).
//
// Keyed by the exact request URL, so the real `PreviewResolver` builds and parses
// requests unchanged; only the transport is cached. Network misses wait on the
// process-wide `ITunesRateLimiter.shared` (20/min). `offline` turns a miss into a
// thrown error — the fixture test's mode, so it never touches the network.

import Foundation
import Session

// MARK: - ScanBenchResponseCache

/// iTunes response cache at ~/.uzume/scanbench/itunes_cache.json.
public final class ScanBenchResponseCache: @unchecked Sendable {

    private struct Entry: Codable {
        let status: Int
        let body: Data
    }

    /// Where the cache lives.
    public static let defaultURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".uzume/scanbench/itunes_cache.json")

    /// A request that would need the network while offline.
    public struct OfflineMiss: Error {
        /// The request URL.
        public let url: String
    }

    private let url: URL
    private let offline: Bool
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var requests = 0

    /// Load the cache. `offline`: never go to the network.
    public init(url: URL = ScanBenchResponseCache.defaultURL, offline: Bool = false) {
        self.url = url
        self.offline = offline
        entries = (try? JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: url))) ?? [:]
    }

    /// Cached entries (0 when the cache file is absent).
    public var count: Int { lock.withLock { entries.count } }

    /// Network requests made by this instance.
    public var networkRequests: Int { lock.withLock { requests } }

    /// `PreviewResolver.networkFetcher` replacement.
    public func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard let requestURL = request.url else { throw URLError(.badURL) }
        let key = requestURL.absoluteString
        if let hit = lock.withLock({ entries[key] }) {
            let response = HTTPURLResponse(url: requestURL, statusCode: hit.status, httpVersion: nil, headerFields: nil)
            return (hit.body, response ?? URLResponse())
        }
        guard !offline else { throw OfflineMiss(url: key) }
        await ITunesRateLimiter.shared.acquire()
        let (data, response) = try await URLSession.shared.data(for: request)
        lock.withLock { requests += 1 }
        if (response as? HTTPURLResponse)?.statusCode == 200 {
            let snapshot = lock.withLock { entries[key] = Entry(status: 200, body: data); return entries }
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? JSONEncoder().encode(snapshot).write(to: url)
        }
        return (data, response)
    }
}
