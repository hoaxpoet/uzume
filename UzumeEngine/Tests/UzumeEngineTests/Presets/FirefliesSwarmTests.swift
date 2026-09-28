// FirefliesSwarmTests — FF.1 behaviour gates for the Fireflies swarm model; FF.5 strips.
//
// Two tiers:
//
//   • Always-on: the committed `route_coverage` fixtures (real preview clips through the
//     production chain — FA #27) drive the model, and the concept's two claims are asserted:
//     a clear beat locks the swarm — since FF.5 into 2–4 strips taking turns on the beat —
//     and UNKNOWN clarity is FREE (D-257, Matt 2026-09-24).
//     Plus the near-silence straggler fade and the per-track restart.
//
//   • Env-gated parity (`FIREFLIES_PARITY=1`): the FF.0 spike's own four captures, compared
//     against the spike's `*_metrics.csv` over 25–30 s (FF.1 done-when #1). The captures
//     PREDATE `beatClarity01`, so a plain replay would read unknown → free on every track;
//     the spike's per-track stand-in is INJECTED here instead (DYC 1, Pyramid 1,
//     Warszawa 0.5 — which the model maps to free — Teardrop 0). Writes each run's metrics to
//     `FIREFLIES_PARITY_OUT` for `docs/presets/fireflies_spike/plot_parity.py`.

import Foundation
import Testing
@testable import PresetSessionReplay
@testable import Renderer
@testable import Shared

// MARK: - Drive

/// One recorded session as the frames the model sees, plus the TRUE beat times (every
/// `beatPhase01` wrap, sub-frame interpolated) in the model's own clock.
struct FirefliesDrive {
    let features: [FeatureVector]
    /// The installed grid's BPM per frame (`grid_bpm`) — what production reads from
    /// `SpectralHistoryBuffer` slot 2418. `FeatureVector` does not carry it.
    let gridBPM: [Float]

    init(directory: URL) throws {
        let series = try SessionColumnSeries.load(directory: directory)
        func column(_ name: String) -> [Float] {
            // An absent column (e.g. `near_silent01` in the route_coverage fixtures) reads 0.
            let raw = series.floatSeries(name) ?? []
            return (0..<series.frameCount).map { $0 < raw.count ? raw[$0] ?? 0 : 0 }
        }
        let delta = column("deltaTime"), phase = column("beatPhase01")
        let silent = column("near_silent01"), elapsed = column("track_elapsed_s")
        // FF.2 — the world's breath route (FirefliesWorld.advance).
        let bassAttRel = column("bassAttRel")
        gridBPM = column("grid_bpm")
        features = (0..<series.frameCount).map { i in
            var f = FeatureVector(time: 0, deltaTime: delta[i], accumulatedAudioTime: 0)
            f.beatPhase01 = phase[i]
            f.nearSilent01 = silent[i]
            f.bassAttRel = bassAttRel[i]
            f.trackElapsedS = elapsed[i]
            f.aspectRatio = 16.0 / 9.0
            return f
        }
    }

    /// Result of one run: per-frame (t, R, on-beat) in the spike's metric definitions, plus the
    /// FF.5 per-strip readouts (equal to R and on-beat while the swarm is one meadow).
    struct Run {
        var t: [Double] = [], coherence: [Float] = [], onBeat: [Float] = []
        /// Each strip's R (size-weighted), and on-beat scored against each strip's OWN ticks.
        var patchCoherence: [Float] = [], patchOnBeat: [Float] = []
        var patchCount = 0
        /// The swarm's flash and target-tick logs, in run time (`t` units).
        var flashes: [(t: Double, patch: Int)] = [], ticks: [(t: Double, patch: Int)] = []

        func mean(_ values: [Float], from start: Double, to end: Double) -> Float {
            let window = zip(t, values).filter { $0.0 >= start && $0.0 < end && !$0.1.isNaN }.map(\.1)
            return window.reduce(0, +) / Float(max(window.count, 1))
        }

        /// FF.5 "successive beats light different patches": of the flashes within ±¼ beat of each
        /// tick in [start, end), the share in the strip that tick nudges. Chance, and a meadow
        /// collapsed back into one unison, both read 1/P.
        func turnShare(from start: Double, to end: Double) -> Float {
            let window = ticks.filter { $0.t >= start && $0.t < end }
            guard window.count >= 2, let first = window.first, let last = window.last else { return .nan }
            let reach = 0.25 * (last.t - first.t) / Double(window.count - 1)
            var own = 0, all = 0
            for tick in window {
                for flash in flashes where abs(flash.t - tick.t) < reach {
                    all += 1
                    if flash.patch == tick.patch { own += 1 }
                }
            }
            return Float(own) / Float(max(all, 1))
        }

        /// When the lock arrives: the first `t` after which `values` stays ≥ `level` to the end of
        /// the run (nil if it never settles).
        func settles(_ values: [Float], at level: Float) -> Double? {
            guard let lastMiss = values.indices.last(where: { !(values[$0] >= level) }) else { return t.first }
            return lastMiss + 1 < t.count ? t[lastMiss + 1] : nil
        }
    }

    /// `phaseShift` (FF.4 R1 decoy) feeds the swarm a grid shifted by that fraction of a beat;
    /// on-beat is still scored against the TRUE beats.
    func run(clarity: Float, seed: UInt64 = 7, phaseShift: Float = 0) -> Run {
        let swarm = FirefliesSwarm(seed: seed)
        swarm.flashLog = []
        swarm.tickLog = []
        var beats: [Double] = []
        var prev: Float?
        var run = Run()
        let offset = Double(features.first?.deltaTime ?? 0)   // capture row 0 is t = 0
        for (f, bpm) in zip(features, gridBPM) {
            if let p = prev, f.beatPhase01 < p - 0.5 {
                beats.append(swarm.now + Double((1 - p) / (f.beatPhase01 + 1 - p) * f.deltaTime))
            }
            prev = f.beatPhase01
            var fed = f
            fed.beatPhase01 = (f.beatPhase01 + phaseShift).truncatingRemainder(dividingBy: 1)
            swarm.advance(features: fed, clarity: clarity, gridBPM: bpm)
            let flashes = swarm.flashLog ?? []
            run.t.append(swarm.now - offset)
            run.coherence.append(swarm.coherence)
            run.onBeat.append(Self.onBeat(flashes: flashes.map(\.t), beats: beats, now: swarm.now))
            run.patchCoherence.append(swarm.patchCoherence)
            run.patchOnBeat.append(swarm.patchCount > 0
                ? Self.patchOnBeat(flashes: flashes, ticks: swarm.tickLog ?? [], now: swarm.now)
                : run.onBeat[run.onBeat.count - 1])
            run.patchCount = swarm.patchCount
        }
        run.flashes = (swarm.flashLog ?? []).map { ($0.t - offset, $0.patch) }
        run.ticks = (swarm.tickLog ?? []).map { ($0.t - offset, $0.patch) }
        return run
    }

    /// FF.5: `onBeat` per strip, each flash scored inside its OWN strip's tick interval (a strip
    /// is nudged every P beats), pooled over the strips. +1 each strip on its own beat.
    static func patchOnBeat(flashes: [(t: Double, patch: Int)], ticks: [(t: Double, patch: Int)], now: Double) -> Float {
        var own: [Int: [Double]] = [:]
        for tick in ticks { own[tick.patch, default: []].append(tick.t) }
        var sum = 0.0, n = 0
        for flash in flashes.reversed() {
            guard flash.t > now - 2 else { break }
            guard let beats = own[flash.patch], beats.count >= 2 else { continue }
            var lo = 0, hi = beats.count
            while lo < hi { let m = (lo + hi) / 2; if beats[m] < flash.t { lo = m + 1 } else { hi = m } }
            let idx = min(max(lo - 1, 0), beats.count - 2)
            sum += cos(2 * .pi * (flash.t - beats[idx]) / (beats[idx + 1] - beats[idx]))
            n += 1
        }
        return n < 5 ? .nan : Float(sum / Double(n))
    }

    /// The spike's `beat_lock`: Re(mean e^{2πiψ}) of the flashes in the last 2 s, ψ = position
    /// inside the true beat interval. +1 all on the beat, −1 all half a beat off, ~0 random.
    static func onBeat(flashes: [Double], beats: [Double], now: Double) -> Float {
        guard beats.count >= 2 else { return .nan }
        var sum = 0.0, n = 0
        for ft in flashes.reversed() {
            guard ft > now - 2 else { break }
            // Index of the last beat before ft, clamped as numpy's searchsorted − 1.
            var lo = 0, hi = beats.count
            while lo < hi { let m = (lo + hi) / 2; if beats[m] < ft { lo = m + 1 } else { hi = m } }
            let idx = min(max(lo - 1, 0), beats.count - 2)
            let psi = (ft - beats[idx]) / (beats[idx + 1] - beats[idx])
            sum += cos(2 * .pi * psi)
            n += 1
        }
        return n < 5 ? .nan : Float(sum / Double(n))
    }
}

// MARK: - Always-on gates

@Suite("Fireflies swarm (FF.1)")
struct FirefliesSwarmTests {

    private static func fixture(_ track: String) throws -> FirefliesDrive {
        let base = try #require(Bundle.module.url(forResource: "route_coverage", withExtension: nil),
                                "route_coverage fixtures not bundled")
        return try FirefliesDrive(directory: base.appendingPathComponent(track))
    }

    /// FF.5: a clear beat locks each STRIP (per-strip R), not the whole meadow — the whole-meadow
    /// claim moved to `patchesTakeTurns`. The per-strip floor keeps FF.1's 0.8: first measured
    /// run, seeds 0–4, per-strip R 0.90–0.93 on all three fixtures.
    @Test("A clear beat locks the swarm; an unknown one leaves it free (D-257)",
          arguments: ["love_rehab", "so_what", "there_there"])
    func clarityGovernsTheLock(track: String) throws {
        let drive = try Self.fixture(track)
        let steady = drive.run(clarity: 1), unknown = drive.run(clarity: 0.5), irregular = drive.run(clarity: 0)
        let end = (steady.t.last ?? 0) - 5
        let rSteady = steady.mean(steady.patchCoherence, from: end, to: end + 5)
        let rUnknown = unknown.mean(unknown.coherence, from: end, to: end + 5)
        let rFree = irregular.mean(irregular.coherence, from: end, to: end + 5)
        print("[fireflies] \(track): R last 5 s steady (per strip) \(rSteady) unknown \(rUnknown) irregular \(rFree)")
        #expect(rSteady > 0.8, "steady beat did not lock the strips")
        #expect(rUnknown < 0.35 && rFree < 0.35, "a free swarm locked on neighbours alone")
        // Unknown is not "half coupled" — it is exactly free.
        #expect(unknown.coherence == irregular.coherence)
    }

    /// FF.5 (FIREFLIES_DESIGN §1a, Matt: "It's everyone at once — go with option A"): on a clear
    /// beat the meadow settles into 2–4 strips that take turns, one per beat, within ~15 s.
    /// Real fixtures (FA #27), K = 1, the default seed. Measured on the shipped model (seeds 0–4,
    /// before any threshold existed): whole-meadow R 0.061–0.137 (FF.4's unison read 0.98); turn
    /// share 0.963–0.990 against a chance — and collapsed-unison — level of 1/P (0.25 / 0.33);
    /// lock (per-strip on-beat ≥ 0.5 from then on) 9.4–11.0 s love_rehab, 12.0–12.8 s so_what
    /// and there_there. Floors: R < 0.3, share > 0.8, lock < 15 s (the design's "about 15 s").
    /// Without the boundary rule (relay across straight strip edges; measured once, not built)
    /// the lock took 12.1–16.0 s and the share fell to 0.92–0.99.
    @Test("A clear beat organises the meadow into strips that take turns (FF.5)",
          arguments: ["love_rehab", "so_what", "there_there"])
    func patchesTakeTurns(track: String) throws {
        let run = try Self.fixture(track).run(clarity: 1)
        let end = (run.t.last ?? 0) - 5
        let whole = run.mean(run.coherence, from: end, to: end + 5)
        let share = run.turnShare(from: end - 5, to: end + 5)
        let lock = run.settles(run.patchOnBeat, at: 0.5)
        print(String(format: "[fireflies] %@: %d strips  whole R %.3f  turn share %.3f (chance %.3f)  lock %.1f s",
                     track, run.patchCount, whole, share, 1 / Float(max(run.patchCount, 1)), lock ?? -1))
        #expect((2...4).contains(run.patchCount))
        #expect(whole < 0.3, "the whole meadow flashed together (unison)")
        #expect(share > 0.8, "successive beats did not light successive strips")
        #expect((lock ?? .infinity) < 15, "the strips did not lock within ~15 s")
    }

    @Test("Near-silence fades all but ~5 % stragglers within a few seconds")
    func nearSilenceLeavesStragglers() {
        let swarm = FirefliesSwarm()
        var f = FeatureVector(time: 0, deltaTime: 1.0 / 60, accumulatedAudioTime: 0)
        f.nearSilent01 = 1
        for _ in 0..<(60 * 6) { swarm.advance(features: f, clarity: 1, gridBPM: 120) }
        let lit = swarm.vis.filter { $0 > 0.5 }.count
        #expect(lit > 10 && lit < 60, "\(lit) of 600 still visible after 6 s of near-silence")
        f.nearSilent01 = 0
        for _ in 0..<(60 * 6) { swarm.advance(features: f, clarity: 1, gridBPM: 120) }
        #expect(swarm.vis.allSatisfy { $0 > 0.9 })
    }

    @Test("A track change restarts the swarm incoherent")
    func trackChangeRestarts() throws {
        let drive = try Self.fixture("love_rehab")
        let swarm = FirefliesSwarm()
        for (f, bpm) in zip(drive.features, drive.gridBPM) { swarm.advance(features: f, clarity: 1, gridBPM: bpm) }
        // FF.5: the lock is per strip.
        #expect(swarm.patchCoherence > 0.8)
        var f = try #require(drive.features.first)
        f.trackElapsedS = 0
        swarm.advance(features: f, clarity: 1, gridBPM: drive.gridBPM[0])
        #expect(swarm.patchCoherence < 0.2)
    }
}

// MARK: - Parity probe (env-gated)

@Suite("Fireflies spike parity (FF.1, FIREFLIES_PARITY=1)")
struct FirefliesSpikeParityProbe {

    /// (capture dir, spike metrics stem, injected clarity, spike 20-seed mean R, mean on-beat).
    ///
    /// The means are the spike's own seed distribution over the 25–30 s window —
    /// `fireflies_spike.py <capture> --K <stand-in> --seed 0…19 --no-video`, FF.1, 2026-09-25.
    /// They are the reference because a FREE swarm's R varies 0.07–0.34 across the spike's own
    /// seeds: a single engine seed against the spike's single seed-7 `*_metrics.csv` would fail
    /// the spike against itself. That literal seed-7 comparison is still printed.
    static let tracks: [(String, String, Float, Float, Float)] = [
        ("fixturegen-01_Dance_Yrself_Clean", "a_dance_yrself_clean", 1, 0.968, 0.843),
        ("fixturegen-02_Pyramid_Song", "b_pyramid_song", 1, 0.972, 0.839),
        ("fixturegen-08_-_Warszawa", "c_warszawa_K0", 0.5, 0.179, -0.007),
        ("fixturegen-03_-_Massive_Attack_-_Teardrop", "m_teardrop", 0, 0.140, -0.006)
    ]

    static var root: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["FIREFLIES_PARITY_DIR"]
            ?? NSHomeDirectory() + "/Documents/uzume_spikes/fireflies")
    }

    /// Spike `*_metrics.csv` → (t, R, on-beat vs true grid).
    static func spike(_ stem: String) throws -> FirefliesDrive.Run {
        let text = try String(contentsOf: root.appendingPathComponent("\(stem)_metrics.csv"), encoding: .utf8)
        var run = FirefliesDrive.Run()
        for line in text.split(whereSeparator: \.isNewline).dropFirst() {
            let c = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            run.t.append(Double(c[0]) ?? 0)
            run.coherence.append(Float(c[1]) ?? .nan)
            run.onBeat.append(Float(c[6]) ?? .nan)
        }
        return run
    }

    /// FF.1 parity on the FREE captures (Warszawa, Teardrop): unchanged since FF.1 — a free swarm
    /// has no strips. FF.5: on the CLEAR captures (DYC, Pyramid at clarity 1) the spike is no
    /// longer the reference (it has no strips); they report per-strip R and per-strip on-beat
    /// against each strip's own ticks over 25–30 s, whole-meadow R, turn share and lock time,
    /// 20 seeds, against floors set from the first measured run (see `patchFloors`).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_PARITY"] == "1"))
    func coherenceMatchesTheSpike() throws {
        let out = ProcessInfo.processInfo.environment["FIREFLIES_PARITY_OUT"].map { URL(fileURLWithPath: $0) }
        let seedCount = Int(ProcessInfo.processInfo.environment["FIREFLIES_SEEDS"] ?? "") ?? 20
        for (session, stem, clarity, spikeR, spikeB) in Self.tracks {
            let drive = try FirefliesDrive(directory: Self.root.appendingPathComponent("sessions/\(session)"))
            let patched = clarity > 0.5
            var rs: [Float] = [], bs: [Float] = [], wholes: [Float] = [], shares: [Float] = [], locks: [Double] = []
            for seed in 0..<UInt64(max(seedCount, 1)) {
                let run = drive.run(clarity: clarity, seed: seed)
                rs.append(run.mean(patched ? run.patchCoherence : run.coherence, from: 25, to: 30))
                bs.append(run.mean(patched ? run.patchOnBeat : run.onBeat, from: 25, to: 30))
                wholes.append(run.mean(run.coherence, from: 25, to: 30))
                shares.append(run.turnShare(from: 20, to: 30))
                locks.append(run.settles(run.patchOnBeat, at: 0.5) ?? .infinity)
                guard seed == 7 else { continue }
                if !patched {
                    // The literal done-when: engine seed 7 against the spike's seed-7 metrics file.
                    let ref = try Self.spike(stem)
                    let refR = ref.mean(ref.coherence, from: 25, to: 30), refB = ref.mean(ref.onBeat, from: 25, to: 30)
                    print(String(format: "[parity] %@ seed 7 vs spike seed 7: R %.3f / %.3f (Δ %+.3f)  on-beat %+.3f / %+.3f (Δ %+.3f)",
                                 stem, rs[7], refR, rs[7] - refR, bs[7], refB, bs[7] - refB))
                }
                guard let out else { continue }
                var csv = "t,R_swarm,onbeat_true_grid,R_patch,onbeat_patch\n"
                for i in run.t.indices {
                    csv += String(format: "%.4f,%.4f,%.4f,%.4f,%.4f\n", run.t[i], run.coherence[i], run.onBeat[i],
                                  run.patchCoherence[i], run.patchOnBeat[i])
                }
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try csv.write(to: out.appendingPathComponent("engine_\(stem).csv"), atomically: true, encoding: .utf8)
            }
            let mean = { (v: [Float]) in v.reduce(0, +) / Float(v.count) }
            let r = mean(rs), b = mean(bs)
            guard patched else {
                print(String(format: "[parity] %@ %d seeds: R %.3f (spike %.3f, Δ %+.3f)  on-beat %+.3f (spike %+.3f, Δ %+.3f)  R range [%.2f, %.2f]",
                             stem, rs.count, r, spikeR, r - spikeR, b, spikeB, b - spikeB, rs.min() ?? 0, rs.max() ?? 0))
                #expect(abs(r - spikeR) <= 0.1, "\(stem): seed-mean R \(r) vs spike \(spikeR)")
                #expect(abs(b - spikeB) <= 0.1, "\(stem): seed-mean on-beat \(b) vs spike \(spikeB)")
                continue
            }
            let lockMax = locks.max() ?? .infinity
            print(String(format: "[parity] %@ %d seeds, strips: per-strip R %.3f [%.2f, %.2f]  per-strip on-beat %+.3f [%+.2f, %+.2f]  "
                         + "whole R %.3f [%.2f, %.2f]  turn share %.3f [%.2f, %.2f]  lock %.1f s [%.1f, %.1f]",
                         stem, rs.count, r, rs.min() ?? 0, rs.max() ?? 0, b, bs.min() ?? 0, bs.max() ?? 0,
                         mean(wholes), wholes.min() ?? 0, wholes.max() ?? 0, mean(shares), shares.min() ?? 0, shares.max() ?? 0,
                         locks.reduce(0, +) / Double(locks.count), locks.min() ?? 0, lockMax))
            let floor = Self.patchFloors
            #expect(r > floor.r, "\(stem): per-strip R \(r)")
            #expect(b > floor.onBeat, "\(stem): per-strip on-beat \(b)")
            #expect((wholes.max() ?? 1) < floor.whole, "\(stem): a seed flashed in unison")
            #expect((shares.min() ?? 0) > floor.share, "\(stem): a seed did not take turns")
            #expect(lockMax < floor.lock, "\(stem): a seed locked late (\(lockMax) s)")
        }
    }

    /// FF.5 floors for the clear captures, set from the first measured run (20 seeds, 2026-09-28):
    /// DYC per-strip R 0.906 [0.89, 0.92], per-strip on-beat +0.907 [+0.89, +0.93], whole R 0.088
    /// [0.06, 0.13], turn share 0.974 [0.96, 0.98], lock 14.5 s [12.3, 16.4]; Pyramid 0.902
    /// [0.88, 0.92], +0.824 [+0.79, +0.85], 0.078 [0.06, 0.13], 0.988 [0.98, 0.99], 23.3 s
    /// [23.1, 24.0]. Pyramid's slow lock is the capture's, not the strips': on the same
    /// definition (on-beat ≥ 0.5 from then on, seed 7) FF.4's whole-meadow unison locked at 25.9 s
    /// (DYC 14.8 s); FF.5's strips lock at 23.1 s (DYC 12.6 s).
    static let patchFloors = (r: Float(0.8), onBeat: Float(0.7), whole: Float(0.3), share: Float(0.8), lock: 26.0)

    /// FF.4 R1 (rewatch bar, legible): DYC, the swarm on the true grid vs the same grid shifted
    /// half a beat (the decoy), plus a free swarm (clarity 0) for the chance band — 20 seeds each,
    /// on-beat scored against the TRUE beats over 25–30 s. The spike read +0.86 vs −0.85; FF.4's
    /// unison +0.843 ± 0.014 vs −0.841 ± 0.012. FF.5's strips (DYC: 3 strips, a 3-beat cycle):
    /// +0.626 ± 0.039 vs −0.617 ± 0.046, chance −0.005 ± 0.018 — lower because this score sits
    /// inside ONE beat, so a strip's phase spread over its 3-beat cycle costs 3× here (per strip,
    /// against its own ticks, on-beat is +0.907 — `coherenceMatchesTheSpike`).
    /// Env-gated (`FIREFLIES_DECOY=1`); report + a separation floor, no swarm change.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_DECOY"] == "1"))
    func decoyIsDistinguishable() throws {
        let drive = try FirefliesDrive(directory: Self.root.appendingPathComponent("sessions/fixturegen-01_Dance_Yrself_Clean"))
        func onBeat(_ clarity: Float, _ shift: Float) -> [Float] {
            (0..<UInt64(20)).map { seed in
                let run = drive.run(clarity: clarity, seed: seed, phaseShift: shift)
                return run.mean(run.onBeat, from: 25, to: 30)
            }
        }
        let truth = onBeat(1, 0), decoy = onBeat(1, 0.5), free = onBeat(0, 0)
        func stats(_ v: [Float]) -> (mean: Float, sd: Float) {
            let m = v.reduce(0, +) / Float(v.count)
            return (m, (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Float(v.count)).squareRoot())
        }
        let (t, d, f) = (stats(truth), stats(decoy), stats(free))
        print(String(format: "[decoy] DYC 20 seeds, 25–30 s on-beat vs true grid: truth %+.3f ± %.3f [%+.2f, %+.2f]  "
                     + "half-beat decoy %+.3f ± %.3f [%+.2f, %+.2f]  free (chance) %+.3f ± %.3f",
                     t.mean, t.sd, truth.min() ?? 0, truth.max() ?? 0,
                     d.mean, d.sd, decoy.min() ?? 0, decoy.max() ?? 0, f.mean, f.sd))
        let chance = abs(f.mean) + 2 * f.sd
        #expect(t.mean > chance && d.mean < -chance, "truth and decoy must sit on opposite sides of the chance band")
    }
}
