// StemCacheEvictionTests — CLEAN.3.5: the in-memory StemCache is LRU-bounded.
//
// Before CLEAN.3.5 `StemCache` was an unbounded `[TrackIdentity: CachedTrackData]`
// with no eviction and no disk backing for streaming preview data (~7 MB/track), so
// it grew without limit across the engine's lifetime under track churn. It now caps at
// `maxEntries` and evicts the least-recently-used track (bumped on store + loadForPlayback).

import Testing
import Foundation
@testable import Session
@testable import Shared

@Suite("StemCache LRU eviction")
struct StemCacheEvictionTests {

    private func identity(_ title: String) -> TrackIdentity {
        TrackIdentity(title: title, artist: "Artist", duration: 180)
    }

    private func data() -> CachedTrackData {
        CachedTrackData(stemWaveforms: [], stemFeatures: .zero, trackProfile: .empty)
    }

    @Test("Storing past maxEntries evicts the least-recently-used track")
    func evictsLRUOverCap() {
        let cache = StemCache(maxEntries: 2)
        let a = identity("A"), b = identity("B"), c = identity("C")

        cache.store(data(), for: a)
        cache.store(data(), for: b)
        _ = cache.loadForPlayback(track: a)   // A is now more-recently-used than B
        cache.store(data(), for: c)           // exceeds cap 2 → evict the LRU (B)

        #expect(cache.count == 2, "cache must stay bounded at maxEntries")
        #expect(cache.loadForPlayback(track: b) == nil, "B (least-recently-used) should be evicted")
        #expect(cache.loadForPlayback(track: a) != nil, "A (recently used) should survive")
        #expect(cache.loadForPlayback(track: c) != nil, "C (just stored) should be present")
    }

    @Test("Re-storing an existing key updates in place without growing the cache")
    func reStoreSameKeyDoesNotGrow() {
        let cache = StemCache(maxEntries: 2)
        let a = identity("A")
        cache.store(data(), for: a)
        cache.store(data(), for: a)
        #expect(cache.count == 1, "re-storing the same key must not double-count")
    }

    @Test("clear() empties the cache and its LRU order")
    func clearEmpties() {
        let cache = StemCache(maxEntries: 4)
        cache.store(data(), for: identity("A"))
        cache.store(data(), for: identity("B"))
        cache.clear()
        #expect(cache.count == 0)
    }
}

// MARK: - BR.8 (audit C1): long playlists keep their preparation

@Suite("A long playlist keeps every prepared track (BR.8)")
struct LongPlaylistCacheTests {

    private func entry() -> CachedTrackData {
        CachedTrackData(
            stemWaveforms: (0..<4).map { _ in [Float](repeating: 0.1, count: 441_000) },   // ~7 MB
            stemFeatures: .zero,
            trackProfile: TrackProfile(bpm: 120)
        )
    }

    /// Streaming preparation runs ~30× ahead of playback; at the old 64 cap tracks ~6–56 of a
    /// 120-track playlist were evicted before they played, and nothing re-prepared them.
    @Test func a120TrackSession_keepsEveryPreparedTrack() {
        let cache = StemCache()
        let tracks = (0..<120).map { TrackIdentity(title: "Track \($0)", artist: "A") }
        for track in tracks { cache.store(entry(), for: track) }
        #expect(cache.count == 120)
        #expect(tracks.allSatisfy { cache.trackProfile(for: $0) != nil }, "every prepared track stays planned")
    }

    @Test func storedEntries_dropTheSeparatedAudio() throws {
        let cache = StemCache()
        let track = TrackIdentity(title: "T", artist: "A")
        cache.store(entry(), for: track)
        let kept = try #require(cache.loadForPlayback(track: track))
        #expect(kept.stemWaveforms.isEmpty, "the 7 MB of stems is not held in memory")
        #expect(kept.trackProfile.bpm == 120, "the playback fields survive")
    }
}
