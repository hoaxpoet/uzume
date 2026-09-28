// KaguraRestTests — ballet as the calm songs' rest, and the Charleston's handoffs (KAG.3; Matt, 2026-09-28).
//
// Calm songs (song energy in the calm third) rest in ballet, rotating its three clips; every other song,
// and a song whose energy is unknown, keeps the sway. Structural properties on synthetic grids (the harness).

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
          arguments: [(-0.426, true), (0.609, false), (nil, false)] as [(Double?, Bool)])
    func restMatchesTheSong(arousal: Double?, calm: Bool) throws {
        let lib = try KaguraClipLibrary.shared()
        let run = try Harness.run(seconds: 70, grid: nil, sequence: [], songArousal: arousal)
        let rests = run.rest.compactMap { $0 }
        let ballet = Set(lib.clips(for: .ballet).map(\.id))
        let seen = Set(rests)
        print("[kagura-rest] arousal \(String(describing: arousal)): rests \(seen.sorted())")
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
                                  songArousal: -0.426, bass: { $0 >= 20 && $0 < 35 ? 0 : 0.2 })
        let at = { (seconds: Double) in run.rest[Int(seconds * Self.fps)] }
        #expect(at(15) == nil, "not dancing before the silence")
        #expect(at(30).map { $0.hasPrefix("49_") } == true, "the calm song's silence did not rest in ballet: \(String(describing: at(30)))")
        #expect(at(45) == nil, "did not return to the dance after the silence")
        #expect(Harness.frozenFrames(run).isEmpty)
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
