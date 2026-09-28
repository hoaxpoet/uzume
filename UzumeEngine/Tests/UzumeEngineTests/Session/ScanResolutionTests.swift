// ScanResolutionTests — SCAN.2 (D-260): verified catalog resolution for screen-read
// tracks, the unchanged streaming request, and now-playing matching of cut-off titles.
// No network (injected fetcher), no Metal.

import Foundation
import Testing
@testable import Orchestrator
@testable import Presets
@testable import Session

// MARK: - Helpers

private func hit(_ title: String, _ artist: String, seconds: Double, id: Int) -> [String: Any] {
    ["trackName": title, "artistName": artist, "trackTimeMillis": seconds * 1000,
     "previewUrl": "https://audio.example/\(id).m4a"]
}

private func searchResponse(_ results: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["resultCount": results.count, "results": results])
}

private func reading(_ title: String, cut: Bool, artist: String) -> ScreenReading {
    ScreenReading(title: title, titleCutOff: cut, artistLine: artist)
}

/// Resolver whose fetcher records requests and serves one canned response.
private final class RecordingFetch: @unchecked Sendable {
    var requests: [URLRequest] = []
    let body: Data
    init(_ body: Data) { self.body = body }
    func fetch(_ request: URLRequest) -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

private func resolver(serving body: Data) -> (PreviewResolver, RecordingFetch) {
    let recorder = RecordingFetch(body)
    let resolver = PreviewResolver(rateLimiter: ITunesRateLimiter(maxRequestsPerWindow: 1000))
    resolver.networkFetcher = { recorder.fetch($0) }
    return (resolver, recorder)
}

private func limit(of request: URLRequest?) -> String? {
    request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
        .queryItems?.first { $0.name == "limit" }?.value
}

// MARK: - Policy

@Suite("ScreenReadMatchPolicy (SCAN.2)")
struct ScreenReadMatchPolicyTests {

    @Test("cut-off title: the version whose duration matches the row wins (remix, not original)")
    func remixByDuration() throws {
        let data = try searchResponse([
            hit("Cheap and Cheerful", "The Kills", seconds: 210, id: 1),
            hit("Cheap and Cheerful (Sebastian Remix)", "The Kills", seconds: 355, id: 2)
        ])
        let track = TrackIdentity(title: "Cheap And", artist: "The Kills", duration: 356)
        let match = ScreenReadMatchPolicy.bestMatch(
            in: data, for: track, reading: reading("Cheap And Cheerfu", cut: true, artist: "The Kills, SebastiAn"))
        #expect(match?.catalogTitle == "Cheap and Cheerful (Sebastian Remix)")
    }

    @Test("a hit that is another song is refused — nothing beats the wrong song")
    func refusesOtherSong() throws {
        let data = try searchResponse([hit("Yeah! (feat. Lil Jon & Ludacris)", "USHER", seconds: 250, id: 1)])
        let track = TrackIdentity(title: "Spitting Off the", artist: "Yeah Yeah Yeahs", duration: 258)
        let match = ScreenReadMatchPolicy.bestMatch(
            in: data, for: track, reading: reading("Spitting Off the Edg", cut: true, artist: "Yeah Yeah Yeahs, Pe"))
        #expect(match == nil)
    }

    @Test("right title and artist but minutes off in length is a different mix — refused")
    func refusesWrongLength() throws {
        let data = try searchResponse([hit("Summer & Smoke (Mixed)", "Cubicolor", seconds: 400, id: 1)])
        let track = TrackIdentity(title: "Summer & Smoke", artist: "Cubicolor", duration: 224)
        #expect(ScreenReadMatchPolicy.bestMatch(
            in: data, for: track, reading: reading("Summer & Smoke - ", cut: true, artist: "Cubicolor, Trikk")) == nil)
    }

    @Test("full title: punctuation/version-suffix differences still match; loose tier needs a tight length")
    func looseTier() throws {
        let data = try searchResponse([hit("Snail (2011 Remaster)", "The Smashing Pumpkins", seconds: 309, id: 1)])
        let near = TrackIdentity(title: "Snail - Remastered 2011", artist: "The Smashing Pumpkins", duration: 308)
        let shown = reading("Snail - Remastered 2011", cut: false, artist: "The Smashing Pumpkins")
        #expect(ScreenReadMatchPolicy.bestMatch(in: data, for: near, reading: shown) != nil)
        let far = TrackIdentity(title: "Snail - Remastered 2011", artist: "The Smashing Pumpkins", duration: 290)
        #expect(ScreenReadMatchPolicy.bestMatch(in: data, for: far, reading: shown) == nil)
    }

    @Test("artist read without spaces, or cut off, still matches")
    func artistVariants() {
        #expect(ScreenReadMatchPolicy.artistMatches("SOFI TUKKER", reading: reading("Purple Hat", cut: false, artist: "SOFITUKKER")))
        #expect(ScreenReadMatchPolicy.artistMatches(
            "Ruby Friedman Orchestra", reading: ScreenReading(
                title: "T", titleCutOff: false, artistLine: "Ruby Friedman Orches", artistCutOff: true)))
        #expect(!ScreenReadMatchPolicy.artistMatches("Patty Loveless", reading: reading("T", cut: false, artist: "Ruby Friedman")))
    }
}

// MARK: - PreviewResolver

@Suite("PreviewResolver — screen-read mode (SCAN.2)")
struct PreviewResolverScreenReadTests {

    @Test("streaming tracks: unchanged limit-1 request, first hit taken, catalog names returned")
    func streamingUnchanged() async throws {
        let (resolver, recorder) = resolver(serving: try searchResponse([hit("Any Title", "Someone Else", seconds: 100, id: 9)]))
        let match = try await resolver.resolvePreviewMatch(for: TrackIdentity(title: "Ride", artist: "Klangkarussell"))
        #expect(limit(of: recorder.requests.first) == "1")
        #expect(match?.previewURL.absoluteString == "https://audio.example/9.m4a")
        #expect(match?.catalogTitle == "Any Title")
    }

    @Test("screen-read tracks: wider request, verified pick, cached")
    func screenReadVerified() async throws {
        let (resolver, recorder) = resolver(serving: try searchResponse([
            hit("get well soon", "Ariana Grande", seconds: 322, id: 1),
            hit("One for Your Workout", "Get Well Soon", seconds: 242, id: 2)
        ]))
        let row = ScannedRow(number: 2, title: "One For Your Worko", artist: "Get Well Soon", duration: 242,
                             confidence: 1, titleTruncated: true)
        let match = try await resolver.resolvePreviewMatch(for: row.trackIdentity)
        #expect(limit(of: recorder.requests.first) == String(ScreenReadMatchPolicy.candidateLimit))
        #expect(match?.catalogTitle == "One for Your Workout")
        _ = try await resolver.resolvePreviewMatch(for: row.trackIdentity)
        #expect(recorder.requests.count == 1, "second resolution must come from the cache")
    }
}

// MARK: - Now-playing matching

private func descriptor() throws -> PresetDescriptor {
    let json = #"{"name": "Test Preset", "family": "sparkle", "certified": true, "complexity_cost": {"tier1": 1.0, "tier2": 1.0}}"#
    return try JSONDecoder().decode(PresetDescriptor.self, from: Data(json.utf8))
}

private func plan(_ entries: [(TrackIdentity, catalog: (String, String)?)]) throws -> PlannedSession {
    let preset = try descriptor()
    let breakdown = PresetScoreBreakdown(
        energy: 1, tempoMotion: 1, stemAffinity: 1, sectionSuitability: 1, familyRepeatMultiplier: 1,
        fatigueMultiplier: 1, excluded: false, exclusionReason: nil, familyBoost: 0, excludedReason: nil, total: 1)
    let tracks = entries.enumerated().map { index, entry in
        var profile = TrackProfile.empty
        profile.catalogTitle = entry.catalog?.0
        profile.catalogArtist = entry.catalog?.1
        return PlannedTrack(
            track: entry.0, trackProfile: profile, preset: preset, presetScore: 1, scoreBreakdown: breakdown,
            plannedStartTime: Double(index) * 200, plannedEndTime: Double(index + 1) * 200, incomingTransition: nil)
    }
    return PlannedSession(deviceTier: .tier1, tracks: tracks, totalDuration: Double(tracks.count) * 200, warnings: [])
}

@Suite("PlannedSession — cut-off title matching (SCAN.2)")
struct ScannedNowPlayingMatchTests {

    @Test("a cut-off planned title matches the full now-playing title via the catalog name")
    func viaCatalogName() throws {
        let scanned = TrackIdentity(title: "Is It Because You", artist: "Len Sander", duration: 235)
        let session = try plan([
            (scanned, catalog: ("Is It Because You Know I Love You", "Len Sander")),
            (TrackIdentity(title: "Non Believer", artist: "London Grammar"), catalog: nil)
        ])
        #expect(session.canonicalIdentity(matchingTitle: "Is It Because You Know I Love You", artist: "Len Sander") == scanned)
    }

    @Test("Spotify's '- Radio Edit' vs the catalog's '(Radio Edit)' match after normalization")
    func punctuationVariants() throws {
        let scanned = TrackIdentity(title: "Flashbacks - Radio", artist: "Emika", duration: 219)
        let session = try plan([(scanned, catalog: ("Flashbacks (Radio Edit)", "Emika"))])
        #expect(session.canonicalIdentity(matchingTitle: "Flashbacks - Radio Edit", artist: "Emika") == scanned)
    }

    @Test("no catalog name (older cache entry): whole-word prefix match with the artist")
    func viaPrefix() throws {
        let scanned = TrackIdentity(title: "Spitting Off the", artist: "Yeah Yeah Yeahs", duration: 258)
        let session = try plan([(scanned, catalog: nil)])
        #expect(session.canonicalIdentity(
            matchingTitle: "Spitting Off the Edge of the World", artist: "Yeah Yeah Yeahs") == scanned)
        #expect(session.canonicalIdentity(matchingTitle: "Spitting Off the Edge", artist: "Other Band") == nil)
    }

    @Test("exact match still wins; ambiguity still returns nil")
    func exactAndAmbiguous() throws {
        let one = TrackIdentity(title: "Ride", artist: "Klangkarussell")
        let two = TrackIdentity(title: "Ride", artist: "joe unknown")
        let session = try plan([(one, catalog: nil), (two, catalog: nil)])
        #expect(session.canonicalIdentity(matchingTitle: "Ride", artist: "joe unknown") == two)
        let twins = try plan([
            (TrackIdentity(title: "Run", artist: "Emika", duration: 1), catalog: nil),
            (TrackIdentity(title: "Run", artist: "Emika", duration: 2), catalog: nil)
        ])
        #expect(twins.canonicalIdentity(matchingTitle: "Run!", artist: "Emika") == nil)
    }
}
