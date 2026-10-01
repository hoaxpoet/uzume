// LocalFilePrefetcher — PREP.3: read the next local file while the current one analyses.
//
// Each local track's preparation starts with I/O and decoding — content hash, tags and
// artwork, the whole-file decode — before any analysis can run. None of that depends on the
// track before it, so the walk reads track k+1 while track k analyses, mirroring streaming's
// `prefetchWindow` (PREPPERF.2), but ONE file ahead: a decoded long track is tens of MB.
//
// Analysis, completion and publication stay strictly in playlist order — the prefetcher only
// moves reading earlier. Starting a new prefetch cancels an unclaimed one, so at most one
// decoded file of lookahead is ever held.

import Foundation
import Shared

// MARK: - Prefetcher

/// One-slot lookahead for `LocalFilePreparationPipeline`.
public final class LocalFilePrefetcher: @unchecked Sendable {

    /// What reading a file ahead produced. `preview` is `nil` when the persistent cache already
    /// holds the file (no decode needed) or the decode failed (the pipeline retries it inline).
    public struct Fetched: Sendable {
        public let contentHash: String
        public let metadata: LocalFileMetadata?
        public let artwork: Data?
        public let preview: PreviewAudio?
    }

    private let lock = NSLock()
    private var slotURL: URL?
    private var slotTask: Task<Fetched?, Never>?

    public init() {}

    /// Start reading `url` ahead, replacing (and cancelling) any lookahead not yet claimed.
    ///
    /// - Parameters:
    ///   - persistentCache: When it already holds the file, the decode is skipped.
    ///   - sink: PREP.1 timing sink — the read-ahead stages are recorded under the file's name,
    ///     so they still appear in `preparation.csv`, outside the track's `TRACK_TOTAL`.
    public func prefetch(url: URL, persistentCache: PersistentStemCache?, sink: PrepStageSink?) {
        let task = Task.detached(priority: .utility) { () -> Fetched? in
            let probe = PrepStageProbe(sink: sink, track: url.lastPathComponent)
            guard let hash = try? probe.measure(PrepStage.contentHash, { try PreviewAudio.sha256(of: url) }) else {
                return nil
            }
            if persistentCache?.contains(hash: hash) == true {
                return Fetched(contentHash: hash, metadata: nil, artwork: nil, preview: nil)
            }
            let (metadata, artwork) = await probe.measureAsync(PrepStage.metadata) {
                (await PreviewAudio.extractMetadata(at: url), await PreviewAudio.extractArtwork(at: url))
            }
            guard !Task.isCancelled else { return nil }
            let preview = try? probe.measure(PrepStage.decode) {
                try PreviewAudio.fromLocalFile(at: url, contentHash: hash)
            }
            return Fetched(contentHash: hash, metadata: metadata, artwork: artwork, preview: preview)
        }
        let replaced = lock.withLock { () -> Task<Fetched?, Never>? in
            defer {
                slotURL = url
                slotTask = task
            }
            return slotTask
        }
        replaced?.cancel()
    }

    /// The lookahead for `url`, awaited, if the last `prefetch` was for it; otherwise `nil`.
    /// Clears the slot either way it matches.
    public func take(url: URL) async -> Fetched? {
        let task = lock.withLock { () -> Task<Fetched?, Never>? in
            guard slotURL == url, let task = slotTask else { return nil }
            slotURL = nil
            slotTask = nil
            return task
        }
        return await task?.value
    }
}
