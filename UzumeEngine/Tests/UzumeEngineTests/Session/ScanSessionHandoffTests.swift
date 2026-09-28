// ScanSessionHandoffTests — SCAN.2 (D-260): a scanned playlist reaches `.ready`
// through `startSession(preFetchedTracks:source:)`, and the catalog's full names
// ride on the prepared profiles. Test doubles for every stage; Metal for the stem
// buffers (not a CI-allow-list suite). Source parity lives in `ScanSourceParityTests`.

import Foundation
import Metal
import Testing
@testable import Audio
@testable import DSP
@testable import Session
@testable import Shared

// MARK: - Doubles

private final class FlatSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels = ["vocals", "drums", "bass", "other"]
    let stemBuffers: [UMABuffer<Float>]
    init(device: MTLDevice) throws {
        stemBuffers = try (0..<4).map { _ in try UMABuffer<Float>(device: device, capacity: 4096) }
        for buffer in stemBuffers { buffer.write((0..<4096).map { Float($0) * 0.0001 }) }
    }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        let frame = AudioFrame(sampleRate: sampleRate, sampleCount: 4096, channelCount: 1)
        return StemSeparationResult(
            stemData: StemData(vocals: frame, drums: frame, bass: frame, other: frame), sampleCount: 4096,
            stemWaveforms: stemBuffers.map { Array($0.pointer.prefix(4096)) })
    }
}

private final class FlatAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { .zero }
    func reset() {}
}

/// Catalog double: answers every track with its "full" name (title + " (Full)").
private final class CatalogResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? {
        try await resolvePreviewMatch(for: track)?.previewURL
    }
    func resolvePreviewMatch(for track: TrackIdentity) async throws -> PreviewMatch? {
        PreviewMatch(previewURL: URL(string: "https://audio.example/\(track.title.hashValue).m4a")!,
                     catalogTitle: track.title + " (Full)", catalogArtist: track.artist)
    }
}

private final class SineDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? {
        PreviewAudio(trackIdentity: track, pcmSamples: (0..<44100).map { 0.05 * sin(Float($0) * 0.01) },
                     sampleRate: 44100, duration: 1)
    }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

// MARK: - Suite

@Suite("Scanned playlist → session (SCAN.2)")
@MainActor
struct ScanSessionHandoffTests {

    @Test("synthetic scan reaches .ready as a Spotify session; profiles carry catalog names")
    func scanReachesReady() async throws {
        let device = try #require(MTLCreateSystemDefaultDevice(), "Metal device required")
        let url = try #require(Bundle.module.url(forResource: "frames_normal", withExtension: "json", subdirectory: "playlist_scan"))
        let frames = try JSONDecoder().decode([[ScanTextObservation]].self, from: Data(contentsOf: url))
        var scan = PlaylistScanAccumulator()
        for observations in frames { scan.add(PlaylistFrameParser.parse(observations)) }
        let tracks = scan.rows.map(\.trackIdentity)
        #expect(tracks.count == 12)

        let preparer = SessionPreparer(
            resolver: CatalogResolver(), downloader: SineDownloader(),
            stemSeparator: try FlatSeparator(device: device), stemAnalyzer: FlatAnalyzer(),
            moodClassifier: MockMoodClassifier())
        let manager = SessionManager(connector: PlaylistConnector(), preparer: preparer)
        await manager.startSession(preFetchedTracks: tracks, source: .spotifyScan(playlistName: scan.playlistName))
        await awaitSessionReady(manager)

        #expect(manager.state == .ready)
        guard case .spotifyScan(let name)? = manager.sessionSource else {
            Issue.record("session source is not the scan: \(String(describing: manager.sessionSource))")
            return
        }
        #expect(name == "TC 98 2026.01.01 Somewhere")
        let truncated = try #require(tracks.first { $0.title == "Is It Because You" })
        #expect(manager.cache.trackProfile(for: truncated)?.catalogTitle == "Is It Because You (Full)")
    }
}
