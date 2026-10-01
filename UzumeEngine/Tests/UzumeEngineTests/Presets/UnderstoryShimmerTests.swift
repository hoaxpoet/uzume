// UnderstoryShimmerTests — UND.4: Understory's beat sequencer (design §4.3 / §6.1).

import Foundation
import Testing
@testable import Presets

// MARK: - UnderstoryShimmerTests

@Suite("UnderstoryShimmer")
struct UnderstoryShimmerTests {

    private static let layout = UnderstoryLayout(seed: 9, aspect: 16.0 / 9.0)

    /// Drive the sequencer at 60 fps on a steady grid: `bpm`, `beatsPerBar`, for `seconds`.
    private static func runGrid(bpm: Float, beatsPerBar: Int, seconds: Float,
                                grid: Bool = true) -> [UnderstoryShimmer.Event] {
        var shimmer = UnderstoryShimmer(seed: 1)
        var events: [UnderstoryShimmer.Event] = []
        let dt: Float = 1 / 60
        let beat = 60 / bpm
        for i in 1...Int(seconds * 60) {
            let t = Float(i) * dt
            let beats = t / beat
            let beatPhase = beats - floor(beats)
            let bars = beats / Float(beatsPerBar)
            let barPhase = grid ? bars - floor(bars) : 0
            let frame = UnderstoryShimmer.Frame(clock: t, dt: dt, beatPhase: beatPhase, barPhase: barPhase,
                                                beatsPerBar: Float(beatsPerBar), drumsDev: 0)
            if let event = shimmer.step(frame, layout: layout) {
                events.append(event)
            }
        }
        return events
    }

    @Test("one shimmer per beat after the trust delay; the downbeat is the lead frond")
    func onePerBeat() {
        let events = Self.runGrid(bpm: 120, beatsPerBar: 4, seconds: 20)
        #expect(events.allSatisfy { $0.time > UnderstoryShimmer.trustDelay }, "nothing before the grid is trusted")
        // 120 BPM from t > 4 s to 20 s: beats at 4.5 … 19.5 → 32 beats.
        #expect(events.count == 32, "\(events.count) shimmers")
        let downbeats = events.filter { $0.kind == .downbeat }
        #expect(downbeats.count == 8 && downbeats.allSatisfy { $0.frond == Self.layout.leadIndex })
        let gaps = zip(events.dropFirst(), events).map { $0.time - $1.time }
        #expect(gaps.allSatisfy { abs($0 - 0.5) < 0.02 }, "on the beat, 0.5 s apart: \(gaps.prefix(6))")
    }

    @Test("beats 2…N walk the same mid-layer set left to right; the set moves on every 4 bars")
    func setWalksLeftToRight() {
        let events = Self.runGrid(bpm: 120, beatsPerBar: 4, seconds: 40).filter { $0.kind == .beat }
        let bars = stride(from: 0, to: events.count - 2, by: 3).map { Array(events[$0..<$0 + 3]) }
        for bar in bars {
            let xs = bar.map { Self.layout.fronds[$0.frond].root.x }
            #expect(xs == xs.sorted(), "left to right within a bar")
            #expect(bar.allSatisfy { Self.layout.fronds[$0.frond].layer == .mid })
        }
        let sets = bars.map { Set($0.map(\.frond)) }
        // Bars of one group repeat exactly; the next group differs.
        #expect(sets.count >= 6 && sets[0] == sets[1] && sets[1] == sets[2])
        #expect(Set(sets).count >= 2, "the set rotates")
    }

    @Test("3/4: each bar has two beat shimmers on two different fronds")
    func threeFour() {
        let events = Self.runGrid(bpm: 120, beatsPerBar: 3, seconds: 20)
        // Between consecutive downbeats: exactly two beat shimmers, on two different fronds.
        let downs = events.indices.filter { events[$0].kind == .downbeat }
        for (a, b) in zip(downs, downs.dropFirst()) {
            let between = events[(a + 1)..<b]
            #expect(between.count == 2 && Set(between.map(\.frond)).count == 2)
        }
    }

    @Test("no grid: nothing on the beat clock alone; drum peaks fire, 0.35 s apart at least")
    func noGridFallsBackToDrums() {
        #expect(Self.runGrid(bpm: 120, beatsPerBar: 4, seconds: 20, grid: false).isEmpty,
                "a beat clock without a bar grid must not drive the sequence")
        var shimmer = UnderstoryShimmer(seed: 3)
        var events: [UnderstoryShimmer.Event] = []
        let dt: Float = 1 / 60
        for i in 1...(20 * 60) {
            let t = Float(i) * dt
            let drums: Float = (i % 12) < 2 ? 0.6 : 0.0   // a peak every 0.2 s
            let frame = UnderstoryShimmer.Frame(clock: t, dt: dt, beatPhase: 0, barPhase: 0, beatsPerBar: 4,
                                                drumsDev: drums)
            if let e = shimmer.step(frame, layout: Self.layout) { events.append(e) }
        }
        #expect(!events.isEmpty && events.allSatisfy { $0.kind == .drum && $0.time > UnderstoryShimmer.trustDelay })
        let gaps = zip(events.dropFirst(), events).map { $0.time - $1.time }
        #expect(gaps.allSatisfy { $0 >= UnderstoryShimmer.drumRefractory - 1e-4 })
        #expect(events.allSatisfy { Self.layout.fronds[$0.frond].layer == .mid })
    }

    @Test("wrap detection interpolates the beat inside the frame")
    func wrapInterpolation() {
        // prev 0.9, now 0.1 over a 0.1 s frame: the wrap is halfway through.
        let at = UnderstoryShimmer.wrap(prev: 0.9, now: 0.1, dt: 0.1)
        #expect(at.map { abs($0 - 0.05) < 1e-5 } == true)
        #expect(UnderstoryShimmer.wrap(prev: 0.4, now: 0.5, dt: 0.1) == nil)
    }
}
