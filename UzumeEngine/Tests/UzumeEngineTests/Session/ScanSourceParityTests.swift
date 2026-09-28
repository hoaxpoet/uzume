// ScanSourceParityTests — SCAN.2 (D-260): a scanned playlist is a Spotify session
// everywhere "the music is playing in Spotify" matters. CI-safe (no Metal, no network).

import Testing
@testable import Session

@Suite("Scanned playlist source parity (SCAN.2)")
struct ScanSourceParityTests {

    @Test("same display name and Spotify-ness as the paste-link source")
    func parityWithPasteLink() {
        let scan = PlaylistSource.spotifyScan(playlistName: "Mix")
        let link = PlaylistSource.spotifyPlaylistURL("https://open.spotify.com/playlist/abc")
        #expect(scan.displayName == link.displayName)
        #expect(scan.isSpotify == link.isSpotify)
        #expect(scan.isSpotify, "drives the 'Check Spotify's Normalize Volume' toast (ASH.2)")
        #expect(PlaylistSource.spotifyScan(playlistName: nil).isSpotify)
    }

    @Test("the connector never re-reads a scan (tracks arrive pre-fetched; no Spotify request)")
    func connectorRefusesScan() async {
        let connector = PlaylistConnector()
        await #expect(throws: PlaylistConnectorError.self) {
            _ = try await connector.connect(source: .spotifyScan(playlistName: nil))
        }
    }
}
