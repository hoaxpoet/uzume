// KaguraRestTests — ballet as the calm songs' rest, and the Charleston's handoffs (KAG.3; Matt, 2026-09-28).
//
// A calm stretch (measured level ≤ 3, KAG.5) rests in ballet, rotating its three clips; every other
// stretch, and one whose energy is unknown, keeps the sway. Structural properties on synthetic grids (the harness).

import Foundation
import simd
import Testing
@testable import Renderer

@Suite("Kagura rests and the Charleston (KAG.3)")
struct KaguraRestTests {

    typealias Harness = KaguraChoreographyHarness
    static let fps = Harness.fps

    /// Rest-to-rest and rest-to-dance steps stay under the rests' own native maximum × 1.25.
    static func restBound(_ library: KaguraClipLibrary) -> Float {
        ([library.sway].compactMap { $0 } + library.clips(for: .ballet)).map(KaguraSelectionTests.nativeStep).max()! * 1.25
    }

    @Test("A calm song rests in ballet, rotating its clips; energetic and unknown songs keep the sway",
          arguments: [(1, true), (3, true), (4, false), (10, false), (nil, false)] as [(Int?, Bool)])
    func restMatchesTheSong(level: Int?, calm: Bool) throws {
        let lib = try KaguraClipLibrary.shared()
        let run = try Harness.run(seconds: 70, grid: nil, sequence: [], sections: Harness.steady(level))
        let rests = run.rest.compactMap { $0 }
        let ballet = Set(lib.clips(for: .ballet).map(\.id))
        let seen = Set(rests)
        print("[kagura-rest] level \(String(describing: level)): rests \(seen.sorted())")
        #expect(rests.count == run.rest.count, "no grid: the dancer must rest throughout")
        if calm {
            // Frame 0 starts in the sway before the first advance reads the song; it fades to ballet at once.
            #expect(rests.dropFirst(Int(2 * Self.fps)).allSatisfy { ballet.contains($0) })
            #expect(seen.intersection(ballet).count >= 2, "a long rest did not rotate its ballet clips: \(seen)")
        } else {
            #expect(seen == ["05_12"], "a non-calm song left the sway: \(seen)")
        }
        #expect(Harness.frozenFrames(run).isEmpty, "\(Harness.frozenFrames(run).count) frozen frames")
        let worst = Harness.maxStep(run.joints)
        #expect(worst < Self.restBound(lib), "rest change stepped \(worst) m (bound \(Self.restBound(lib)))")
    }

    @Test("On a calm song, silence rests in ballet and the dance returns with the music")
    func calmSongSilence() throws {
        let run = try Harness.run(seconds: 50, grid: Harness.grid(bpm: 120, seconds: 50), sequence: [],
                                  sections: Harness.steady(1), bass: { $0 >= 20 && $0 < 35 ? 0 : 0.2 })
        let at = { (seconds: Double) in run.rest[Int(seconds * Self.fps)] }
        #expect(at(15) == nil, "not dancing before the silence")
        #expect(at(30).map { $0.hasPrefix("49_") } == true, "the calm song's silence did not rest in ballet: \(String(describing: at(30)))")
        #expect(at(45) == nil, "did not return to the dance after the silence")
        #expect(Harness.frozenFrames(run).isEmpty)
    }

    // MARK: - Energy sections (KAG.5)

    @Test("A section change re-picks the repertoire at the next clip change, within the handoff bounds")
    func sectionChangeRepicks() throws {
        let lib = try KaguraClipLibrary.shared()
        let step = 60.0
        let sections = [KaguraSection(start: 0, level: 2), KaguraSection(start: step, level: 9)]
        let grid = try Harness.grid(bpm: 120, seconds: 120)
        let quiet = KaguraRepertoire.repertoire(bpm: 60 / grid.beatPeriod, level: 2, library: lib)
        let loud = KaguraRepertoire.repertoire(bpm: 60 / grid.beatPeriod, level: 9, library: lib)
        #expect(quiet != loud, "the fixture cannot tell the sections apart")
        let run = try Harness.run(seconds: 120, grid: grid, sequence: [], sections: sections,
                                  bass: { 0.2 + 0.08 * sin(2 * .pi * $0 / 7) })
        let picks = run.choreographer.picks
        let first = try #require(run.pickTimes.firstIndex { $0 >= step }, "no clip change after the step")
        print("[kagura-sections] step at \(step) s; first clip change after it at \(run.pickTimes[first]) s: "
              + "\(picks[first].repertoire) (level \(String(describing: picks[first].level)))")
        #expect(first > 0 && picks[..<first].allSatisfy { $0.repertoire == quiet && $0.level == 2 })
        #expect(picks[first...].allSatisfy { $0.repertoire == loud && $0.level == 9 })
        // The switch waits for the clip change: a clip at most 4 bars (8 s at 120 BPM) after the step.
        #expect(run.pickTimes[first] - step <= 8.5)
        try Self.expectWithinBounds(run, bpm: 120, library: lib)
        #expect(Harness.frozenFrames(run).isEmpty, "\(Harness.frozenFrames(run).count) frozen frames")
    }

    /// Every frame's largest joint step stays under the bound of the dance (or rest) on screen, and of the
    /// one it fades from.
    static func expectWithinBounds(_ run: Harness.Run, bpm: Double, library: KaguraClipLibrary) throws {
        var bounds: [KaguraDance?: Float] = [nil: restBound(library)]
        for dance in KaguraRepertoire.dances { bounds[dance] = KaguraSelectionTests.bound(dance, bpm: bpm, library: library) }
        for index in 1..<run.joints.count {
            let limit = max(bounds[run.dance[index]] ?? 0, run.fading[index] ? bounds[run.fadingFrom[index]] ?? 0 : 0)
            let moved = Harness.step(run.joints, at: index)
            #expect(moved < limit, "frame \(index) (\(String(describing: run.dance[index]))): \(moved) m over \(limit)")
            if moved >= limit { break }
        }
    }

    @Test("A silence rests by the section it interrupts: Warszawa's calm opening in ballet, its body in the sway")
    func silenceReadsItsSection() throws {
        // Warszawa's sections as task 1 measured them (loud end 2 to 0:23, then 6), at its dancer tempo.
        let sections = [KaguraSection(start: 0, level: 2), KaguraSection(start: 23, level: 6)]
        let silent = { (t: Double) in (8..<21).contains(t) || (60..<80).contains(t) }
        let run = try Harness.run(seconds: 90, grid: Harness.grid(bpm: 76.9, seconds: 90), sequence: [],
                                  sections: sections, bass: { silent($0) ? 0 : 0.2 })
        let at = { (seconds: Double) in run.rest[Int(seconds * Self.fps)] }
        #expect(at(19).map { $0.hasPrefix("49_") } == true, "the calm opening's silence: \(String(describing: at(19)))")
        #expect(at(50) == nil, "not dancing between the silences")
        #expect(at(76) == "05_12", "the body's silence did not keep the sway: \(String(describing: at(76)))")
        #expect(Harness.frozenFrames(run).isEmpty)
        try Self.expectWithinBounds(run, bpm: 76.9, library: try KaguraClipLibrary.shared())
    }

    // MARK: - Seeks (BUG-155) and the warm-up (KAG.5 M7, option A)

    @Test("A seek fades to the rest and rejoins at the next bar line — no replayed cuts, forward or back",
          arguments: [(31.3, 110.0), (61.3, -40.0)])   // mid-clip, past the clip change's crossfade
    func seekRejoins(at seek: Double, by jump: Double) throws {
        let lib = try KaguraClipLibrary.shared()
        let run = try Harness.run(seconds: 90, grid: Harness.grid(bpm: 120, seconds: 200), sequence: [],
                                  sections: Harness.steady(6), bass: { 0.2 + 0.08 * sin(2 * .pi * $0 / 7) },
                                  playback: { $0 < seek ? $0 : $0 + jump })
        let after = run.pickTimes.filter { $0 >= seek && $0 < seek + 1 }
        let index = { (seconds: Double) in Int(seconds * Self.fps) }
        print("[kagura-seek] \(jump > 0 ? "forward" : "back") at \(seek) s: \(after.count) picks in the next second; "
              + "dancing again at \(run.dancing[index(seek)...].firstIndex(of: true).map { Double($0) / Self.fps } ?? -1) s")
        #expect(run.dancing[index(seek) - 1], "not dancing before the seek")
        #expect(after.count <= 1, "a seek replayed \(after.count) clip changes in one second")
        #expect(run.rest[index(seek) + 2] != nil, "the seek did not fade to the rest")
        // Rejoins within a bar (2 s) and a beat of fade, and keeps dancing.
        #expect(run.dancing[index(seek + 3)...].allSatisfy { $0 }, "did not rejoin the dance after the seek")
        try Self.expectWithinBounds(run, bpm: 120, library: lib)
        #expect(Harness.frozenFrames(run).isEmpty, "\(Harness.frozenFrames(run).count) frozen frames")
    }

    @Test("A song opens on its calm dance for its first bars, then the bar pick ranks")
    func warmUpOpensCalm() throws {
        let grid = try Harness.grid(bpm: 120, seconds: 60)
        let run = try Harness.run(seconds: 40, grid: grid, sequence: [], sections: Harness.steady(5),
                                  bass: { 0.2 + 0.08 * sin(2 * .pi * $0 / 7) })
        let picks = run.choreographer.picks
        let warmUp = KaguraChoreographer.warmUpBars * KaguraChoreographer.barSeconds(grid)
        let early = picks.indices.filter { run.pickTimes[$0] < warmUp }
        print("[kagura-warmup] \(early.count) warm-up picks: \(early.map { picks[$0].dance.rawValue }); "
              + "first ranked \(picks.first { !$0.warmingUp }?.logLine ?? "none")")
        #expect(!early.isEmpty && early.allSatisfy { picks[$0].warmingUp && picks[$0].dance == picks[$0].repertoire.first })
        #expect(picks.indices.filter { run.pickTimes[$0] >= warmUp + 0.1 }.allSatisfy { !picks[$0].warmingUp })
        #expect(picks.first?.logLine.contains("barRank=warm-up") == true)
    }

    @Test("Every handoff into and out of the Charleston stays under its per-dance bound", arguments: [140.0, 171.0])
    func charlestonHandoffs(bpm: Double) throws {
        let lib = try KaguraClipLibrary.shared()
        let sequence: [KaguraDance] = [.twist, .charleston, .cabbage, .charleston, .egyptian, .charleston,
                                       .macarena, .charleston, .chicken, .charleston, .twist]
        let seconds = Double(sequence.count) * 4 * 4 * 60 / bpm + 20
        let run = try Harness.run(seconds: seconds, grid: Harness.grid(bpm: bpm, seconds: seconds), sequence: sequence)
        var bounds: [KaguraDance?: Float] = [nil: Self.restBound(lib)]
        for dance in KaguraRepertoire.spikeDances + [.charleston] {
            bounds[dance] = KaguraSelectionTests.bound(dance, bpm: bpm, library: lib)
        }
        var worst: Float = 0
        for index in 1..<run.joints.count {
            let limit = max(bounds[run.dance[index]] ?? 0, run.fading[index] ? bounds[run.fadingFrom[index]] ?? 0 : 0)
            let step = Harness.step(run.joints, at: index)
            worst = max(worst, step / limit)
            #expect(step < limit, "frame \(index): \(step) m over \(limit)")
            if step >= limit { break }
        }
        let order = run.choreographer.chosenDances
        print("[kagura-charleston] \(bpm) BPM: \(order.count) dances, worst step / bound \(worst)")
        #expect(order.filter { $0 == .charleston }.count >= 5)
    }
}
