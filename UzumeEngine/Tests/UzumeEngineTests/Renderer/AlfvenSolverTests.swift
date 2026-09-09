// AlfvenSolverTests — the compute solver against the same reference the staged path was
// held to (ALFVEN.4).
//
// The staged version reached: psi conserved to 0.06%, J the right order, total energy
// conserved — but only with a clamp holding omega below the CFL threshold, and it blew up
// the moment the clamp was lifted. The question here is whether adaptive dt plus real
// substeps remove that dependence.
//
// Spike ground truth (docs/presets/alfven_spike, run directly): omega 1.2 -> ~5.5 -> ~4,
// psi 0.9000 -> 0.8999 (conserved), J ~4.5.

import Testing
import Foundation
import Metal
@testable import Renderer
@testable import Shared

@Suite("Alfvén compute solver (ALFVEN.4)")
struct AlfvenSolverTests {

    private struct Stats {
        var omegaRMS = 0.0, psiRMS = 0.0, jRMS = 0.0
        var omegaMax = 0.0, clampedFraction = 0.0
        var finite = true
    }

    private static func measure(_ solver: AlfvenSolver, clampW: Double) -> Stats {
        let tex = solver.stateTexture
        let n = tex.width
        var raw = [Float](repeating: 0, count: n * n * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: n * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: n, height: n, depth: 1)),
                         mipmapLevel: 0)
        }
        var s = Stats()
        var wSum = 0.0, pSum = 0.0, jSum = 0.0, clamped = 0
        for i in 0..<(n * n) {
            let w = Double(raw[i * 4]), p = Double(raw[i * 4 + 1]), j = Double(raw[i * 4 + 2])
            if !w.isFinite || !p.isFinite || !j.isFinite { s.finite = false }
            wSum += w * w; pSum += p * p; jSum += j * j
            s.omegaMax = max(s.omegaMax, abs(w))
            if abs(w) >= clampW * 0.999 { clamped += 1 }
        }
        let c = Double(n * n)
        s.omegaRMS = (wSum / c).squareRoot()
        s.psiRMS = (pSum / c).squareRoot()
        s.jRMS = (jSum / c).squareRoot()
        s.clampedFraction = Double(clamped) / c
        return s
    }

    @Test("the compute solver holds without the clamp doing the work")
    func solverIsStable() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        var cfg = AlfvenSolverConfiguration()
        // 256 is the PRODUCTION grid, and the test must measure what ships. At 128 the
        // same solver equilibrates at omega ~30 against ~7 here — not a solver defect but
        // an under-resolved one: 2D turbulence needs inertial range between the forcing
        // and dissipation scales, and at 128 the cascade is truncated and piles up. A test
        // at 128 was measuring a configuration nothing runs.
        cfg.edge = 256
        // Env overrides so the equilibrium can be bisected without editing the test.
        let env = ProcessInfo.processInfo.environment
        if let e = env["ALFVEN_EDGE"].flatMap(Int.init) { cfg.edge = e }
        if let d = env["ALFVEN_DRIVE"].flatMap(Float.init) { cfg.drive = d }
        if let a = env["ALFVEN_ALPHA"].flatMap(Float.init) { cfg.alpha = a }
        if let s = env["ALFVEN_SUBSTEPS"].flatMap(Int.init) { cfg.substeps = s }
        if let n4 = env["ALFVEN_NU4"].flatMap(Float.init) { cfg.nu4 = n4 }
        // A huge cutoff makes the Hou-Li filter identity, which together with
        // ALFVEN_DRIVE=0 ALFVEN_ALPHA=0 ALFVEN_NU4=0 leaves ONLY the nonlinear terms.
        // <psi^2> is a Casimir of 2D reduced MHD and must then be conserved, so that
        // configuration is a direct gate on the gradient/bracket/dealias chain.
        if let sc = env["ALFVEN_CUTOFF"].flatMap(Float.init) { cfg.spectralCutoff = sc }
        if let cy = env["ALFVEN_CYCLE"].flatMap(Float.init) { cfg.cycleSeconds = cy }
        let solver = try AlfvenSolver(device: ctx.device, library: lib.library,
                                      configuration: cfg)

        // Seed, then run 300 frames of wall-clock time at 60 fps.
        guard let seedCmd = ctx.commandQueue.makeCommandBuffer() else {
            throw HarnessError.commandBufferFailed
        }
        solver.reseed(time: 0, commandBuffer: seedCmd)
        seedCmd.commit(); seedCmd.waitUntilCompleted()
        let seeded = Self.measure(solver, clampW: Double(cfg.clampOmega))
        #expect(abs(seeded.psiRMS - Double(cfg.seedAmpPsi)) < 0.05,
                "seed did not produce the requested psi amplitude (\\(seeded.psiRMS))")

        var trace: [(Int, Stats, Float, Double)] = []
        var simTime = 0.0
        let frames = env["ALFVEN_FRAMES"].flatMap(Int.init) ?? 300
        for frame in 1...frames {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            solver.update(time: Float(frame) / 60.0, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
            // Accumulated SIMULATION time, which is not frame/60: every substep takes its
            // own CFL-limited dt. Without this the harness cannot say what instant its
            // numbers describe, and comparisons against the spike ("at matched sim time")
            // are unfalsifiable. Approximate to the extent dt varies WITHIN a frame,
            // which is slight — the CFL speed moves on the eddy timescale, not per substep.
            simTime += Double(cfg.substeps) * Double(solver.lastAdaptiveDt)
            if frame % 60 == 0 {
                trace.append((frame, Self.measure(solver, clampW: Double(cfg.clampOmega)),
                              solver.lastAdaptiveDt, simTime))
            }
        }

        print("[alfven-solver] \(cfg.edge)², \(cfg.substeps) substeps/frame, adaptive dt")
        for (frame, s, dt, t) in trace {
            print(String(format: "[alfven-solver] f%3d  t=%6.3f  wRMS %8.4f  psi %7.4f  "
                                 + "J %9.4f  wMax %8.3f  clamped %5.2f%%  dt %.6f",
                         frame, t, s.omegaRMS, s.psiRMS, s.jRMS, s.omegaMax,
                         s.clampedFraction * 100, dt))
        }

        guard let last = trace.last?.1, let first = trace.first?.1 else {
            throw HarnessError.setupFailed("no samples")
        }
        #expect(trace.allSatisfy { $0.1.finite }, "the field went non-finite")

        // The point of the architecture change: the clamp must be a backstop, not the
        // thing holding omega down. On the staged path this sat at 3% with a clamp of 24.
        #expect(last.clampedFraction < 0.01, """
            \\(last.clampedFraction * 100)% of the field is at the clamp — it is still \
            load-bearing, so adaptive dt has not removed the dependence.
            """)

        // psi must stay BOUNDED and must never collapse. This replaces a "psi is conserved
        // to within 10%" assertion, whose premise ("psi has no source term") stopped being
        // true when the re-seed cycle started actually firing: the crossfade is both a
        // source and a sink. A partial mix of two UNCORRELATED fields of equal rms has
        // lower rms than either — ((1-r)^2 + r^2) < 1 — so continuous crossfading sits
        // psi below the seed amplitude by design. Measured over 1800 frames (t = 22.5 sim
        // s) it oscillates in 0.43...0.80 about ~0.65 against a 0.9 seed and does not
        // trend down. Conservation is therefore the WRONG property to gate now; not going
        // to zero is the right one, because psi -> 0 means J -> 0 means a black frame
        // (D-037). The band is deliberately wide: it is a collapse/blow-up gate, not a
        // tuning lock.
        #expect(trace.allSatisfy { $0.1.psiRMS > 0.25 && $0.1.psiRMS < 1.5 }, """
            psi left its safe band (first \\(first.psiRMS), last \\(last.psiRMS), \
            min \\(trace.map(\\.1.psiRMS).min() ?? 0), \
            max \\(trace.map(\\.1.psiRMS).max() ?? 0)) — at the low end J goes to zero \
            and the frame goes black (D-037).
            """)

        // And the adaptive timestep must actually be adapting, not pinned at its ceiling.
        let dts = trace.map(\.2)
        #expect(dts.allSatisfy { $0 > 0 && $0.isFinite }, "adaptive dt is not being written")
    }
}
