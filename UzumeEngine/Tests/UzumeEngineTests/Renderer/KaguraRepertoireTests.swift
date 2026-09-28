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

    /// README §10 "Repertoire after": the beta playlist at the table's printed song ENERGY (the spike's
    /// arousal rank, retired at KAG.5 — this row set is the spike's history and checks `pick` alone).
    /// Pyramid Song's grid jumps levels (67 / 146 / 156); the table's row is its 67 BPM window.
    static let readme10: [Row] = [
        ("Dance Yrself Clean", 98, 1.00, [.chicken, .cabbage, .twist]),
        ("B.O.B.", 154, 0.89, [.chicken, .cabbage, .twist]),
        ("Superstition", 101, 0.67, [.egyptian, .chicken, .cabbage]),
        ("Smells Like Teen Spirit", 117, 0.78, [.chicken, .cabbage, .twist]),
        ("Penny Lane", 113, 0.11, [.egyptian, .macarena, .chicken]),
        ("Take Five", 171, 0.56, [.chicken, .cabbage, .twist]),
        ("Pyramid Song", 67, 0.44, [.macarena, .chicken, .cabbage]),
        ("Teardrop", 77, 0.33, [.egyptian, .macarena, .chicken]),
        ("Moonlight I", 44.5, 0.00, [.egyptian, .macarena, .chicken]),
        ("Warszawa", 80, 0.22, [.egyptian, .macarena, .chicken]),
    ]

    /// The build (KAG.5): one row per energy section of each beta-playlist song on Matt's v17 cache entries
    /// (`KaguraBetaPlaylistReportTests.energyTable`, the `row:` lines): the section's loud-end level, the
    /// dancer's tempo (the grid's median beat interval), the repertoire and whether its rest is ballet.
    /// The Charleston by tempo (Matt, 2026-09-28, B) on B.O.B. and Take Five, whatever the energy.
    static let build: [(song: String, bpm: Double, level: Int, expected: [KaguraDance], ballet: Bool)] = [
        ("Dance Yrself Clean 0:00", 96.8, 2, [.egyptian, .macarena, .cabbage], true),
        ("Dance Yrself Clean 3:08", 96.8, 9, [.egyptian, .cabbage, .twist], false),
        ("Dance Yrself Clean 5:57", 96.8, 3, [.egyptian, .macarena, .cabbage], true),
        ("Dance Yrself Clean 6:35", 96.8, 9, [.egyptian, .cabbage, .twist], false),
        ("Dance Yrself Clean 8:18", 96.8, 3, [.egyptian, .macarena, .cabbage], true),
        ("B.O.B. 0:00", 150.0, 10, [.cabbage, .twist, .charleston], false),
        ("Superstition 0:00", 100.0, 6, [.egyptian, .macarena, .cabbage], false),
        ("Smells Like Teen Spirit 0:00", 115.4, 8, [.egyptian, .cabbage, .twist], false),
        ("Smells Like Teen Spirit 4:42", 115.4, 8, [.egyptian, .cabbage, .twist], false),
        ("Penny Lane 0:00", 115.4, 5, [.egyptian, .macarena, .cabbage], false),
        ("Take Five 0:00", 176.5, 3, [.egyptian, .macarena, .charleston], true),
        ("Pyramid Song 0:00", 107.1, 4, [.egyptian, .macarena, .cabbage], false),
        ("Pyramid Song 0:22", 107.1, 7, [.egyptian, .cabbage, .twist], false),
        ("Pyramid Song 1:56", 107.1, 10, [.egyptian, .cabbage, .twist], false),
        ("Pyramid Song 4:28", 107.1, 10, [.egyptian, .cabbage, .twist], false),
        ("Teardrop 0:00", 76.9, 5, [.egyptian, .macarena, .cabbage], false),
        ("Teardrop 0:44", 76.9, 9, [.macarena, .cabbage, .twist], false),
        ("Teardrop 5:11", 76.9, 6, [.egyptian, .macarena, .cabbage], false),
        ("Moonlight I 0:00", 46.9, 1, [.egyptian, .macarena, .cabbage], true),
        ("Warszawa 0:00", 76.9, 2, [.egyptian, .macarena, .cabbage], true),
        ("Warszawa 0:23", 76.9, 6, [.egyptian, .macarena, .cabbage], false),
    ]

    @Test("README §9: the nine spike songs, from their printed energy")
    func readmeNine() throws {
        let lib = try KaguraClipLibrary.shared()
        for row in Self.readme9 {
            let picked = KaguraRepertoire.pick(bpm: row.bpm, energy: row.input, library: lib, from: KaguraRepertoire.spikeDances)
            #expect(picked == row.expected, "\(row.song)")
        }
    }

    @Test("README §10: the beta playlist, from its printed energy")
    func readmeTen() throws {
        let lib = try KaguraClipLibrary.shared()
        for row in Self.readme10 {
            let picked = KaguraRepertoire.pick(bpm: row.bpm, energy: row.input, library: lib, from: KaguraRepertoire.spikeDances)
            #expect(picked == row.expected, "\(row.song)")
        }
    }

    @Test("The build's table: each section's loud-end level picks its repertoire and rest")
    func buildTable() throws {
        let lib = try KaguraClipLibrary.shared()
        for row in Self.build {
            #expect(KaguraRepertoire.repertoire(bpm: row.bpm, level: row.level, library: lib) == row.expected, "\(row.song)")
            #expect((row.level <= KaguraRepertoire.calmLevel) == row.ballet, "\(row.song) rest")
        }
    }

    @Test("Tempo earns the Charleston (Matt, B): in its band at every level, last (vigorous); never outside it")
    func charlestonByTempo() throws {
        let lib = try KaguraClipLibrary.shared()
        for bpm in [140.0, 150.0, 176.5, 210.0] {
            for level in [nil] + (1...10).map(Optional.some) {
                let rep = KaguraRepertoire.repertoire(bpm: bpm, level: level, library: lib)
                #expect(rep.count == 3 && rep.last == .charleston, "\(bpm) BPM level \(String(describing: level)): \(rep)")
            }
        }
        for bpm in [76.9, 96.8, 115.4, 130.0, 220.0] {
            for level in 1...10 {
                #expect(!KaguraRepertoire.repertoire(bpm: bpm, level: level, library: lib).contains(.charleston), "\(bpm) BPM")
            }
        }
    }

    @Test("Level → energy: (level − 1) / 9 on the library scale; unknown is the middle")
    func levelEnergy() {
        for level in 1...10 { #expect(abs(KaguraRepertoire.energy(level: level) - Double(level - 1) / 9) < 1e-12) }
        #expect(KaguraRepertoire.energy(level: nil) == KaguraRepertoire.unknownEnergy)
        #expect(KaguraRepertoire.energy(level: 0) == 0 && KaguraRepertoire.energy(level: 11) == 1)
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
