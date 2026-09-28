// KaguraRepertoireTests — the song's tempo and energy pick three dances (KAG.3; KAGURA_DESIGN §6).
//
// `KaguraRepertoire` is the spike's `song_energy` / `dance_profile` / `pick_repertoire` ported verbatim
// (FA #73), with the dance profiles read from the KAG.1 manifest. Every expected row below is the
// spike's own output (`kagura.py`, run 2026-09-25) and matches the README table it cites.

import Foundation
import Testing
@testable import Renderer

@Suite("Kagura repertoire (KAG.3)")
struct KaguraRepertoireTests {

    typealias Row = (song: String, bpm: Double, input: Double, expected: [KaguraDance])

    /// The spike's KAG.0g reference (README §10): production-chain window-median arousals.
    static let spikeReference = [-0.28, -0.04, 0.19, 0.43, 0.45, 0.48, 0.51, 0.54, 0.67, 0.69]

    /// README §9: the nine spike songs under KAG.0f's mapping. The input is the table's printed song
    /// ENERGY (that mapping was retired at KAG.0g), so this row set checks `pick` alone.
    static let readme9: [Row] = [
        ("Dreams of You", 123, 0.00, [.egyptian, .macarena, .chicken]),
        ("Olive Drab", 86, 0.13, [.egyptian, .macarena, .chicken]),
        ("Dracula", 97, 0.43, [.egyptian, .chicken, .cabbage]),
        ("Superstition", 99, 0.63, [.egyptian, .chicken, .cabbage]),
        ("Around the World", 126, 0.67, [.chicken, .cabbage, .twist]),
        ("GAYBLEVISION", 143, 0.66, [.chicken, .cabbage, .twist]),
        ("Wild Rose", 166, 0.78, [.chicken, .cabbage, .twist]),
        ("Stayin' Alive", 104, 0.88, [.chicken, .cabbage, .twist]),
        ("Billie Jean", 117, 0.98, [.chicken, .cabbage, .twist]),
    ]

    /// README §10 "Repertoire after": the beta playlist, the README's arousal medians against the spike's
    /// reference. Pyramid Song's grid jumps levels (67 / 146 / 156); the table's row is its 67 BPM window.
    static let readme10: [Row] = [
        ("Dance Yrself Clean", 98, 0.69, [.chicken, .cabbage, .twist]),
        ("B.O.B.", 154, 0.67, [.chicken, .cabbage, .twist]),
        ("Superstition", 101, 0.51, [.egyptian, .chicken, .cabbage]),
        ("Smells Like Teen Spirit", 117, 0.54, [.chicken, .cabbage, .twist]),
        ("Penny Lane", 113, -0.04, [.egyptian, .macarena, .chicken]),
        ("Take Five", 171, 0.48, [.chicken, .cabbage, .twist]),
        ("Pyramid Song", 67, 0.45, [.macarena, .chicken, .cabbage]),
        ("Teardrop", 77, 0.43, [.egyptian, .macarena, .chicken]),
        ("Moonlight I", 44.5, -0.28, [.egyptian, .macarena, .chicken]),
        ("Warszawa", 80, 0.19, [.egyptian, .macarena, .chicken]),
    ]

    /// The build (Matt, 2026-09-25, option A): `TrackProfile.songArousal` and the grid BPM from the shipping
    /// local-file preparation (PrepTimingRunner, Release), against `KaguraRepertoire.energyReference`, picking
    /// from the four dances left after the chicken dance went (Matt, 2026-09-28). The spike's rule (oracle:
    /// `kagura.py` with `DANCES` minus chicken) yields two repertoires on this playlist.
    static let build: [Row] = [
        ("Dance Yrself Clean", 98.0, 0.609, [.egyptian, .cabbage, .twist]),
        ("B.O.B.", 153.8, 0.569, [.macarena, .cabbage, .twist]),
        ("Superstition", 101.4, 0.206, [.egyptian, .macarena, .cabbage]),
        ("Smells Like Teen Spirit", 117.3, 0.597, [.egyptian, .cabbage, .twist]),
        ("Penny Lane", 113.3, -0.426, [.egyptian, .macarena, .cabbage]),
        ("Take Five", 171.4, 0.327, [.egyptian, .macarena, .cabbage]),
        ("Pyramid Song", 95.2, 0.334, [.egyptian, .macarena, .cabbage]),
        ("Teardrop", 78.8, 0.479, [.egyptian, .macarena, .cabbage]),
        ("Moonlight I", 44.5, -0.355, [.egyptian, .macarena, .cabbage]),
        ("Warszawa", 75.2, 0.040, [.egyptian, .macarena, .cabbage]),
    ]

    @Test("README §9: the nine spike songs, from their printed energy")
    func readmeNine() throws {
        let lib = try KaguraClipLibrary.shared()
        for row in Self.readme9 {
            let picked = KaguraRepertoire.pick(bpm: row.bpm, energy: row.input, library: lib, from: KaguraRepertoire.spikeDances)
            #expect(picked == row.expected, "\(row.song)")
        }
    }

    @Test("README §10: the beta playlist against the spike's reference")
    func readmeTen() throws {
        let lib = try KaguraClipLibrary.shared()
        for row in Self.readme10 {
            let energy = KaguraRepertoire.songEnergy(arousal: row.input, reference: Self.spikeReference)
            let picked = KaguraRepertoire.pick(bpm: row.bpm, energy: energy, library: lib, from: KaguraRepertoire.spikeDances)
            #expect(picked == row.expected, "\(row.song)")
        }
    }

    @Test("The build's table: songArousal against the re-derived reference")
    func buildTable() throws {
        let lib = try KaguraClipLibrary.shared()
        for row in Self.build {
            let energy = KaguraRepertoire.songEnergy(arousal: row.input)
            #expect(KaguraRepertoire.pick(bpm: row.bpm, energy: energy, library: lib) == row.expected, "\(row.song)")
        }
        // Each playlist song is one reference point, so its energy is its rank: 0, 1/9, … 1.
        let energies = Self.build.map { KaguraRepertoire.songEnergy(arousal: $0.input) }.sorted()
        for (index, energy) in energies.enumerated() { #expect(abs(energy - Double(index) / 9) < 1e-9) }
    }

    @Test("Vigor profile matches README §9 (twist 0.71 … Egyptian 0.38 m/s)")
    func vigor() throws {
        let lib = try KaguraClipLibrary.shared()
        let expected: [KaguraDance: Double] = [.twist: 0.71, .cabbage: 0.60, .chicken: 0.45, .macarena: 0.38, .egyptian: 0.38]
        for (dance, vigor) in expected {
            let profile = try #require(KaguraRepertoire.profile(dance, library: lib))
            #expect(abs(profile.vigor - vigor) < 0.006, "\(dance): \(profile.vigor)")
        }
    }

    @Test("Terciles pick calm, middle, vigorous")
    func terciles() {
        let rep: [KaguraDance] = [.egyptian, .chicken, .cabbage]
        #expect(KaguraRepertoire.dance(forRank: 0.1, in: rep) == .egyptian)
        #expect(KaguraRepertoire.dance(forRank: 0.5, in: rep) == .chicken)
        #expect(KaguraRepertoire.dance(forRank: 0.9, in: rep) == .cabbage)
        #expect(KaguraRepertoire.dance(forRank: 1.0, in: rep) == .cabbage)
    }
}
