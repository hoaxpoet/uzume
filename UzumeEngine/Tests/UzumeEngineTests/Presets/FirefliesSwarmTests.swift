// FirefliesSwarmTests — FF.1 behaviour gates for the Fireflies swarm model.
//
// Two tiers:
//
//   • Always-on: the committed `route_coverage` fixtures (real preview clips through the
//     production chain — FA #27) drive the model, and the concept's two claims are asserted:
//     a clear beat locks the swarm, and UNKNOWN clarity is FREE (D-257, Matt 2026-09-24).
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
        gridBPM = column("grid_bpm")
        features = (0..<series.frameCount).map { i in
            var f = FeatureVector(time: 0, deltaTime: delta[i], accumulatedAudioTime: 0)
            f.beatPhase01 = phase[i]
            f.nearSilent01 = silent[i]
            f.trackElapsedS = elapsed[i]
            f.aspectRatio = 16.0 / 9.0
            return f
        }
    }

    /// Result of one run: per-frame (t, R, on-beat) in the spike's metric definitions.
    struct Run {
        var t: [Double] = [], coherence: [Float] = [], onBeat: [Float] = []

        func mean(_ values: [Float], from start: Double, to end: Double) -> Float {
            let window = zip(t, values).filter { $0.0 >= start && $0.0 < end && !$0.1.isNaN }.map(\.1)
            return window.reduce(0, +) / Float(max(window.count, 1))
        }
    }

    func run(clarity: Float, seed: UInt64 = 7) -> Run {
        let swarm = FirefliesSwarm(seed: seed)
        swarm.flashLog = []
        var beats: [Double] = []
        var prev: Float?
        var run = Run()
        let offset = Double(features.first?.deltaTime ?? 0)   // capture row 0 is t = 0
        for (f, bpm) in zip(features, gridBPM) {
            if let p = prev, f.beatPhase01 < p - 0.5 {
                beats.append(swarm.now + Double((1 - p) / (f.beatPhase01 + 1 - p) * f.deltaTime))
            }
            prev = f.beatPhase01
            swarm.advance(features: f, clarity: clarity, gridBPM: bpm)
            run.t.append(swarm.now - offset)
            run.coherence.append(swarm.coherence)
            run.onBeat.append(Self.onBeat(flashes: swarm.flashLog ?? [], beats: beats, now: swarm.now))
        }
        return run
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

    @Test("A clear beat locks the swarm; an unknown one leaves it free (D-257)",
          arguments: ["love_rehab", "so_what", "there_there"])
    func clarityGovernsTheLock(track: String) throws {
        let drive = try Self.fixture(track)
        let steady = drive.run(clarity: 1), unknown = drive.run(clarity: 0.5), irregular = drive.run(clarity: 0)
        let end = (steady.t.last ?? 0) - 5
        let rSteady = steady.mean(steady.coherence, from: end, to: end + 5)
        let rUnknown = unknown.mean(unknown.coherence, from: end, to: end + 5)
        let rFree = irregular.mean(irregular.coherence, from: end, to: end + 5)
        print("[fireflies] \(track): R last 5 s steady \(rSteady) unknown \(rUnknown) irregular \(rFree)")
        #expect(rSteady > 0.8, "steady beat did not lock the swarm")
        #expect(rUnknown < 0.35 && rFree < 0.35, "a free swarm locked on neighbours alone")
        // Unknown is not "half coupled" — it is exactly free.
        #expect(unknown.coherence == irregular.coherence)
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
        #expect(swarm.coherence > 0.8)
        var f = try #require(drive.features.first)
        f.trackElapsedS = 0
        swarm.advance(features: f, clarity: 1, gridBPM: drive.gridBPM[0])
        #expect(swarm.coherence < 0.2)
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

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FIREFLIES_PARITY"] == "1"))
    func coherenceMatchesTheSpike() throws {
        let out = ProcessInfo.processInfo.environment["FIREFLIES_PARITY_OUT"].map { URL(fileURLWithPath: $0) }
        let seedCount = Int(ProcessInfo.processInfo.environment["FIREFLIES_SEEDS"] ?? "") ?? 20
        for (session, stem, clarity, spikeR, spikeB) in Self.tracks {
            let drive = try FirefliesDrive(directory: Self.root.appendingPathComponent("sessions/\(session)"))
            var rs: [Float] = [], bs: [Float] = []
            for seed in 0..<UInt64(max(seedCount, 1)) {
                let run = drive.run(clarity: clarity, seed: seed)
                rs.append(run.mean(run.coherence, from: 25, to: 30))
                bs.append(run.mean(run.onBeat, from: 25, to: 30))
                guard seed == 7 else { continue }
                // The literal done-when: engine seed 7 against the spike's seed-7 metrics file.
                let ref = try Self.spike(stem)
                let refR = ref.mean(ref.coherence, from: 25, to: 30), refB = ref.mean(ref.onBeat, from: 25, to: 30)
                print(String(format: "[parity] %@ seed 7 vs spike seed 7: R %.3f / %.3f (Δ %+.3f)  on-beat %+.3f / %+.3f (Δ %+.3f)",
                             stem, rs[7], refR, rs[7] - refR, bs[7], refB, bs[7] - refB))
                guard let out else { continue }
                var csv = "t,R_swarm,onbeat_true_grid\n"
                for i in run.t.indices {
                    csv += String(format: "%.4f,%.4f,%.4f\n", run.t[i], run.coherence[i], run.onBeat[i])
                }
                try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                try csv.write(to: out.appendingPathComponent("engine_\(stem).csv"), atomically: true, encoding: .utf8)
            }
            let r = rs.reduce(0, +) / Float(rs.count), b = bs.reduce(0, +) / Float(bs.count)
            print(String(format: "[parity] %@ %d seeds: R %.3f (spike %.3f, Δ %+.3f)  on-beat %+.3f (spike %+.3f, Δ %+.3f)  R range [%.2f, %.2f]",
                         stem, rs.count, r, spikeR, r - spikeR, b, spikeB, b - spikeB, rs.min() ?? 0, rs.max() ?? 0))
            #expect(abs(r - spikeR) <= 0.1, "\(stem): seed-mean R \(r) vs spike \(spikeR)")
            #expect(abs(b - spikeB) <= 0.1, "\(stem): seed-mean on-beat \(b) vs spike \(spikeB)")
        }
    }
}
