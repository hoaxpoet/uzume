// UnderstoryShimmer — Understory's beat sequencer (UND.4, design §4.3 / §6.1).
//
// One frond per beat, in an order the ear can learn: the downbeat (a `barPhase01` wrap) goes
// to the lead frond; beats 2…N (`beatPhase01` wraps, N = `beatsPerBar`) go to a set of N − 1
// mid-layer fronds, played left to right; the same set repeats for 4 bars, then the next group
// takes over. Layer 4 on the CACHED grid (D-153…D-158): bounded footprint — one frond, a band
// that travels, never a whole-frond flash (D-157).
//
// Grid trust (the Witchlight precedent): `barPhase01` is 0 whenever no grid is installed, so
// nothing fires until it has wrapped at least once AND 4 s of the track have passed. That covers
// cold start (no wrong-phase shimmers in the first seconds — the scene's own suppression, per
// the Cold-Start Phase Contract) and D-154 beat-irregular tracks (no grid → no sequence).
// Without a grid (no bar wrap for 6 s; Matt's §10-2 default), shimmers follow `drumsEnergyDev`
// peaks, at least 0.35 s apart, on a random mid-layer frond.

import Foundation

// MARK: - UnderstoryShimmer

/// Decides which frond, if any, shimmers this frame.
struct UnderstoryShimmer {

    /// Why a shimmer fired (logged for the replay evidence).
    enum Kind: String, Sendable { case downbeat, beat, drum }

    /// One fired shimmer.
    struct Event: Sendable, Equatable {
        let time: Float
        let frond: Int
        let kind: Kind
    }

    static let trustDelay: Float = 4
    static let gridTimeout: Float = 6
    static let drumThreshold: Float = 0.30
    static let drumRefractory: Float = 0.35
    static let barsPerSet = 4

    private var prevBeat: Float?
    private var prevBar: Float?
    private var barWraps = 0
    private var lastBarWrap: Float = -100
    private var lastDrum: Float = -100
    private var prevDrumDev: Float = 0
    private var started: Float = 0
    private var rng: SplitMix64

    init(seed: UInt32) {
        rng = SplitMix64(seed: UInt64(seed) &+ 0x5A1E)
    }

    /// Restart for a new track: grid trust is earned again.
    mutating func reset(seed: UInt32, at clock: Float) {
        self = UnderstoryShimmer(seed: seed)
        started = clock
    }

    /// One render frame's inputs: the frame ends at `clock` and lasts `dt`.
    struct Frame {
        var clock: Float
        var dt: Float
        var beatPhase: Float
        var barPhase: Float
        var beatsPerBar: Float
        var drumsDev: Float
    }

    /// One render frame. Returns the fired shimmer, if any, with its onset interpolated inside
    /// the frame.
    mutating func step(_ frame: Frame, layout: UnderstoryLayout) -> Event? {
        let clock = frame.clock, dt = frame.dt, beatPhase = frame.beatPhase, barPhase = frame.barPhase
        let beatsPerBar = frame.beatsPerBar, drumsDev = frame.drumsDev
        let barWrapAt = Self.wrap(prev: prevBar, now: barPhase, dt: dt)
        let beatWrapAt = Self.wrap(prev: prevBeat, now: beatPhase, dt: dt)
        prevBar = barPhase
        prevBeat = beatPhase
        defer { prevDrumDev = drumsDev }

        let elapsed = clock - started
        if let at = barWrapAt {
            barWraps += 1
            lastBarWrap = clock - (dt - at)
            guard elapsed > Self.trustDelay else { return nil }
            return Event(time: lastBarWrap, frond: layout.leadIndex, kind: .downbeat)
        }
        let gridLive = barWraps > 0 && clock - lastBarWrap < Self.gridTimeout
        if gridLive, let at = beatWrapAt {
            guard elapsed > Self.trustDelay else { return nil }
            // The beat's place in the bar comes from the grid's own bar phase, not a counter: a
            // bar wrap the grid skips while re-anchoring (there_there, 15.6 s) must not push the
            // count past the meter and silence the rest of the bar.
            let meter = max(Int(beatsPerBar.rounded()), 1)
            let position = Int((barPhase * Float(meter)).rounded()) % meter
            guard position > 0 else { return nil }                       // the downbeat's own path
            let members = Self.set(barIndex: barWraps - 1, beatsPerBar: beatsPerBar, layout: layout)
            let slot = position - 1
            guard members.indices.contains(slot) else { return nil }
            return Event(time: clock - (dt - at), frond: members[slot], kind: .beat)
        }
        // No grid: drum peaks on a random mid frond.
        guard !gridLive, elapsed > Self.trustDelay,
              prevDrumDev < Self.drumThreshold, drumsDev >= Self.drumThreshold,
              clock - lastDrum >= Self.drumRefractory else { return nil }
        lastDrum = clock
        let mids = layout.fronds.indices.filter { layout.fronds[$0].layer == .mid }
        guard !mids.isEmpty else { return nil }
        return Event(time: clock, frond: mids[Int(rng.next() % UInt64(mids.count))], kind: .drum)
    }

    /// The N − 1 mid-layer fronds that take beats 2…N in bar `barIndex`, left to right; the
    /// group advances every `barsPerSet` bars.
    static func set(barIndex: Int, beatsPerBar: Float, layout: UnderstoryLayout) -> [Int] {
        let mids = layout.fronds.indices.filter { layout.fronds[$0].layer == .mid }
            .sorted { layout.fronds[$0].root.x < layout.fronds[$1].root.x }
        let size = min(max(Int(beatsPerBar.rounded()) - 1, 1), mids.count)
        let group = max(barIndex, 0) / barsPerSet
        let start = (group * size) % mids.count
        let chosen = (0..<size).map { mids[(start + $0) % mids.count] }
        return chosen.sorted { layout.fronds[$0].root.x < layout.fronds[$1].root.x }
    }

    /// A phase wrap inside the frame: its offset from the frame start (seconds), or nil.
    static func wrap(prev: Float?, now: Float, dt: Float) -> Float? {
        guard let prev, now < prev - 0.5 else { return nil }
        return (1 - prev) / max(now + 1 - prev, 1e-4) * dt
    }
}
