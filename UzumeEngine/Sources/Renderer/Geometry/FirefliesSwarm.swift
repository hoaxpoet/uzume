// FirefliesSwarm — the pulse-coupled firefly model behind the Fireflies preset (FF.1).
//
// A PORT, not a derivation (FA #73): every constant and every step order below comes from
// the FF.0 spike, `docs/presets/fireflies_spike/fireflies_spike.py` (`Swarm`,
// `simulate_frame`, `render`), which is itself Nicky Case's *Fireflies* (CC0,
// github.com/ncase/fireflies @ 165d16c) plus three measured additions. The spike is RUNNABLE
// and is the oracle for behavioural questions — run it before theorising.
//
//   • ncase: each firefly runs a clock θ 0→1 and flashes at 1; each flashing neighbour
//     inside the radius multiplies a clock by (1 + 0.02).
//   • relay latency: a nudged clock is capped 60 ms short of 1, so a relay travels one
//     radius per ~60 ms — the visible sweep before the lock (Sarfati et al. 2021).
//   • music: on every m-th beat tick (`beatPhase01` wraps, sub-frame interpolated) each clock
//     is pulled toward 0 by K·0.30 of its wrapped error, and each period retunes by K·0.05
//     (Ermentrout 1991 — without it the swarm locks EARLY of the beat and oscillates).
//   • near-silence: all but 5 % stragglers fade to 2 % visibility, τ 1.5 s. The world
//     behind stays lit (D-037); that is the preset fragment's job, not this file's.
//
// K is the track's beat clarity (`stems.beatClarity01`, BC.1 / D-257) mapped so that
// UNKNOWN behaves as FREE — Matt, 2026-09-24: "unknown stays free".
//
// What is adapted for context, not changed: distances are in frame HEIGHTS instead of 720p
// pixels, the substep is a fixed ≤ 1/120 s instead of "4 per 30 fps frame" (the same
// 8.3 ms), and the tempo arrives as a separate argument because `FeatureVector` carries no
// BPM: the engine publishes the installed grid's BPM in `SpectralHistoryBuffer` (slot 2418,
// the same `grid.bpm` the captures record as `grid_bpm`), and `FirefliesGeometry` reads it.

import Foundation
import Shared

// MARK: - FirefliesSwarm

/// CPU model of 600 pulse-coupled fireflies. `@unchecked Sendable`: advanced and read only
/// from the render thread via `FirefliesGeometry`, or from a test.
public final class FirefliesSwarm: @unchecked Sendable {

    // MARK: Spike constants (fireflies_spike.py)

    public static let count = 600
    static let top: Float = 0.36            // highest firefly, fraction of frame height
    static let eta: Float = 0.05            // period adaptation per tick (Ermentrout 1991)
    static let latency: Float = 0.06        // s, relay reaction delay
    static let epsMutual: Float = 0.02      // ncase nudge per flashing neighbour
    static let epsBeat: Float = 0.30        // music nudge × K
    static let sigma: Float = 0.05          // natural-period spread
    static let radius: Float = 80.0 / 720.0 // neighbour radius, frame heights
    static let stragglerShare = 0.05
    static let silentVisibility: Float = 0.02
    static let silenceTau: Float = 1.5
    static let maxSubstep: Float = 1.0 / 120.0
    /// Natural period while no grid is installed.
    static let defaultPeriod: Float = 1.0

    // MARK: Per-firefly state

    public private(set) var clock = [Float](repeating: 0, count: count)
    private(set) var period = [Float](repeating: 1, count: count)
    private var spread = [Float](repeating: 1, count: count)
    private(set) var posU = [Float](repeating: 0, count: count)
    private(set) var posV = [Float](repeating: 0, count: count)
    private var velU = [Float](repeating: 0, count: count)
    private var velV = [Float](repeating: 0, count: count)
    private var flashT = [Double](repeating: -99, count: count)
    private var straggler = [Bool](repeating: false, count: count)
    private(set) var vis = [Float](repeating: 1, count: count)

    // MARK: Beat state

    /// Seconds since the swarm started (the envelope clock).
    public private(set) var now: Double = 0
    /// Current beat coupling, 0 (free) … 1 (full).
    public private(set) var coupling: Float = 0
    /// Beats per flash cycle (1, 2 or 4 — the cycle nearest 1 s).
    public private(set) var cycleBeats = 1
    /// The installed grid's beat period the natural periods are built on; nil with no grid.
    public private(set) var beatPeriod: Float?
    private var prevBeatPhase: Float?
    private var prevTrackElapsed: Float = 0
    private var tickIndex = 0

    /// When non-nil, every flash appends its time (`now` units). Harness-only.
    public var flashLog: [Double]?

    private var rng: SplitMix64
    private var hits = [Int32](repeating: 0, count: count)
    private var neighbourStart = [Int32](repeating: 0, count: count + 1)
    private var neighbours: [Int32] = []
    private var cellStart: [Int32] = []
    private var cellItems = [Int32](repeating: 0, count: count)

    public init(seed: UInt64 = 7) {
        rng = SplitMix64(seed: seed)
        restart()
    }

    // MARK: - Lifecycle

    /// Random start — cold start is incoherent BY DESIGN (the arc is the swarm finding the
    /// beat). Also called on a track change so every track gets its own arc.
    public func restart() {
        for i in 0..<Self.count {
            clock[i] = rng.unit()
            spread[i] = 1 + Self.sigma * rng.gaussian()
            period[i] = Self.defaultPeriod * spread[i]
            posU[i] = rng.unit()
            posV[i] = Self.top + (1 - Self.top) * pow(rng.unit(), 0.8)
            velU[i] = rng.gaussian() * 0.004
            velV[i] = rng.gaussian() * 0.004
            flashT[i] = -99
            straggler[i] = Double(rng.unit()) < Self.stragglerShare
        }
        beatPeriod = nil
        cycleBeats = 1
        prevBeatPhase = nil
        tickIndex = 0
    }

    // MARK: - Advance

    /// Advance one render frame. `clarity` is `stems.beatClarity01` (1 steady, 0 irregular,
    /// 0.5 unknown); `gridBPM` is the installed grid's tempo, 0 when none.
    public func advance(features frame: FeatureVector, clarity: Float, gridBPM: Float) {
        let dt = min(max(frame.deltaTime, 0), 0.1)
        guard dt > 0 else { return }
        if frame.trackElapsedS < prevTrackElapsed - 1 { restart() }
        prevTrackElapsed = frame.trackElapsedS
        // 1 → 1, 0.5 (unknown) → 0, 0 → 0.
        coupling = min(max(2 * clarity - 1, 0), 1)
        installTempo(bpm: gridBPM)

        let tickAt = beatTick(phase: frame.beatPhase01, dt: dt)

        // Near-silence: fade to stragglers (spike: before simulate_frame).
        let silent = frame.nearSilent01 > 0.5
        let keep = 1 - exp(-dt / Self.silenceTau)
        for i in 0..<Self.count {
            let target: Float = silent && !straggler[i] ? Self.silentVisibility : 1
            vis[i] += (target - vis[i]) * keep
        }

        buildNeighbours(aspect: frame.aspectRatio > 0 ? frame.aspectRatio : 16.0 / 9.0)
        let steps = max(1, Int((dt / Self.maxSubstep).rounded(.up)))
        let sdt = dt / Float(steps)
        for step in 0..<steps {
            substep(sdt, start: Float(step) * sdt, tickAt: tickAt, time: now + Double(Float(step) * sdt))
        }
        now += Double(dt)
        drift(dt)
    }

    /// Detects a `beatPhase01` wrap (a grid tick) inside this frame and returns its offset into
    /// the frame (seconds) when it is a TARGET tick — every m-th beat, the spike's `ticks[::m]`.
    /// No target ticks while no grid is installed.
    private func beatTick(phase: Float, dt: Float) -> Float? {
        defer { prevBeatPhase = phase }
        guard let prev = prevBeatPhase, phase < prev - 0.5, beatPeriod != nil else { return nil }
        defer { tickIndex += 1 }
        return tickIndex % cycleBeats == 0 ? (1 - prev) / (phase + 1 - prev) * dt : nil
    }

    /// Builds the natural periods on the installed grid's tempo — the spike's `grid_bpm`, one
    /// steady value per track — and re-builds them only when the grid itself changes.
    ///
    /// ⚠ FF.1 measured every alternative first. The tempo MUST be the grid's, not measured:
    ///   • a rolling median of the per-frame `beatPhase01` ramp rate re-based 11 times in 30 s
    ///     on Pyramid Song (its drift-corrected ramp spans p10 54.6 → p90 73.2 BPM on a flat
    ///     66.2 grid), wiping the Ermentrout adaptation each time — R 0.88 vs the spike's 0.97;
    ///   • any per-frame ramp rate breaks when features update slower than the render (a 43 Hz
    ///     cadence under 60 fps reads ~1.4× the tempo; the swarm never locks, R 0.35);
    ///   • a median of the first five tick intervals is cadence-proof but lags the grid (DYC's
    ///     early ticks run 2.6 % slow) and delays coupling ~5 s: on-beat +0.78 vs +0.84.
    /// Given the grid tempo from t = 0, the engine reproduces the spike's seed distributions
    /// on all four parity captures (FF.1 closeout), so the model port itself is faithful.
    private func installTempo(bpm: Float) {
        guard bpm > 0 else { beatPeriod = nil; return }          // no grid: free, keep periods
        let beat = 60 / bpm
        if let current = beatPeriod, abs(current - beat) < 1e-4 { return }
        beatPeriod = beat
        tickIndex = 0
        // Beats per flash cycle: 1, 2 or 4, whichever puts the period nearest 1 s.
        cycleBeats = [1, 2, 4].min { abs(log(Float($0) * beat)) < abs(log(Float($1) * beat)) } ?? 1
        for i in 0..<Self.count { period[i] = Float(cycleBeats) * beat * spread[i] }
    }

    /// One substep of `simulate_frame`: advance clocks, music nudge, flash + relay.
    private func substep(_ sdt: Float, start: Float, tickAt: Float?, time: Double) {
        for i in 0..<Self.count { clock[i] += sdt / period[i] }

        if coupling > 0, let tick = tickAt, tick >= start, tick < start + sdt {
            for i in 0..<Self.count {
                let wrap = clock[i] > 0.5 ? 1 - clock[i] : -clock[i]
                clock[i] += coupling * Self.epsBeat * wrap
                // Late → shorten; removes the steady lead the neighbour nudges leave.
                period[i] *= 1 - coupling * Self.eta * wrap
            }
        }

        var fired: [Int] = []
        for i in 0..<Self.count where clock[i] >= 1 {
            fired.append(i)
            clock[i] = 0
            flashT[i] = time
        }
        guard !fired.isEmpty else { return }
        flashLog?.append(contentsOf: repeatElement(time, count: fired.count))
        // ncase applies the pull once per flashing neighbour: clock *= (1 + pull)^hits.
        for i in fired {
            for k in Int(neighbourStart[i])..<Int(neighbourStart[i + 1]) { hits[Int(neighbours[k])] += 1 }
        }
        for i in fired { hits[i] = 0 }
        for j in 0..<Self.count where hits[j] > 0 {
            let cap = 1 - Self.latency / period[j]
            clock[j] = max(clock[j], min(cap, clock[j] * pow(1 + Self.epsMutual, Float(hits[j]))))
            hits[j] = 0
        }
    }

    /// Neighbour lists, rebuilt once per frame (the spike's `near` matrix), via a uniform grid of
    /// radius-sized cells: each firefly tests the 3 × 3 cells around its own (~60 candidates)
    /// instead of all 600. The neighbour SETS are identical to a full pair scan.
    ///
    /// FF.1: the full O(N²) scan was 0.6 ms/frame at `-O` but 79 ms at `-Onone` — 80 % of it
    /// in this loop's range iteration — and the Debug-built `PresetFrameBudgetTests` measured
    /// the preset at 15× the roster median. The grid is the fix for both configurations.
    private func buildNeighbours(aspect: Float) {
        let cell = Self.radius
        let cols = max(1, Int((aspect / cell).rounded(.up)))
        let rows = max(1, Int((1 / cell).rounded(.up)))
        func cellOf(_ i: Int) -> (Int, Int) {
            (min(cols - 1, max(0, Int(posU[i] * aspect / cell))), min(rows - 1, max(0, Int(posV[i] / cell))))
        }
        // Counting sort of firefly indices by cell.
        cellStart = [Int32](repeating: 0, count: cols * rows + 1)
        for i in 0..<Self.count {
            let (cx, cy) = cellOf(i)
            cellStart[cy * cols + cx + 1] += 1
        }
        for bucket in 0..<cols * rows { cellStart[bucket + 1] += cellStart[bucket] }
        var fill = cellStart
        for i in 0..<Self.count {
            let (cx, cy) = cellOf(i)
            cellItems[Int(fill[cy * cols + cx])] = Int32(i)
            fill[cy * cols + cx] += 1
        }

        neighbours.removeAll(keepingCapacity: true)
        let r2 = Self.radius * Self.radius
        for i in 0..<Self.count {
            neighbourStart[i] = Int32(neighbours.count)
            let xi = posU[i] * aspect, yi = posV[i]
            let (cx, cy) = cellOf(i)
            for ny in max(0, cy - 1)...min(rows - 1, cy + 1) {
                for nx in max(0, cx - 1)...min(cols - 1, cx + 1) {
                    let bucket = ny * cols + nx
                    var k = Int(cellStart[bucket])
                    while k < Int(cellStart[bucket + 1]) {
                        let j = Int(cellItems[k])
                        k += 1
                        let dx = posU[j] * aspect - xi, dy = posV[j] - yi
                        if j != i, dx * dx + dy * dy < r2 { neighbours.append(Int32(j)) }
                    }
                }
            }
        }
        neighbourStart[Self.count] = Int32(neighbours.count)
    }

    /// Slow random-walk hover. Rate-independent form of the spike's per-30-fps-frame walk.
    private func drift(_ dt: Float) {
        let frames = dt * 30
        let damp = pow(Float(0.985), frames), kick = 0.0015 * frames.squareRoot()
        for i in 0..<Self.count {
            velU[i] = velU[i] * damp + rng.gaussian() * kick
            velV[i] = velV[i] * damp + rng.gaussian() * kick
            let dep = depth(i)
            posU[i] = (posU[i] + velU[i] * dt * 2 / dep).truncatingRemainder(dividingBy: 1)
            if posU[i] < 0 { posU[i] += 1 }
            posV[i] = min(max(posV[i] + velV[i] * dt / dep, Self.top), 0.98)
        }
    }

    // MARK: - Readouts

    /// 2.5-D depth: higher on screen = farther (1 near … 9 far).
    func depth(_ i: Int) -> Float {
        let far = (1 - posV[i]) / (1 - Self.top)
        return 1 + 8 * far * far
    }

    /// Flash envelope at `now`: 40 ms attack, exp decay τ 0.11 s, dark between flashes.
    func envelope(_ i: Int) -> Float {
        let age = Float(now - flashT[i])
        if age < 0 { return 0 }
        return age < 0.04 ? age / 0.04 : exp(-(age - 0.04) / 0.11)
    }

    /// Swarm coherence R = |mean e^{2πiθ}| (1 = unison).
    public var coherence: Float {
        var re: Float = 0, im: Float = 0
        for phase in clock {
            re += cos(2 * .pi * phase)
            im += sin(2 * .pi * phase)
        }
        return (re * re + im * im).squareRoot() / Float(Self.count)
    }
}

// MARK: - SplitMix64

/// Deterministic seeded generator (the spike seeds numpy; a fixed seed keeps harness runs
/// reproducible, not bit-identical to numpy).
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }

    /// Standard normal (Box–Muller).
    mutating func gaussian() -> Float {
        let first = max(unit(), 1e-7), second = unit()
        return (-2 * log(first)).squareRoot() * cos(2 * .pi * second)
    }
}
