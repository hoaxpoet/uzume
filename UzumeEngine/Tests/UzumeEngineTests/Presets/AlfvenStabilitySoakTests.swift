// AlfvenStabilitySoakTests — ALFVEN.2's FIRST gate, ahead of any look comparison.
//
// WHY THIS IS FIRST. The design (§11) puts a look comparison first. The port sources say
// otherwise: `docs/presets/alfven_spike/alfven.py` is PSEUDO-SPECTRAL, and its stabiliser
// `FILT = exp(-36 (k/kmax)^36)` (Hou–Li) is described in that file as "the standard
// pseudo-spectral stabiliser -- kills the grid-scale energy pile-up that made the earlier
// spikes blow up." It has NO real-space port. `ALFVEN_DESIGN.md` §8.1 substitutes "the GPU
// analogue … a small explicit diffusion pass", which is grounding level 3 (design-doc
// assertion only, PRESET_SESSION_CHECKLIST Part 2). Three NaN blow-ups happened on the CPU
// spike, and on stage a blow-up is a P0 black frame.
//
// A look comparison cannot be trusted on a field that is quietly diverging, and the look
// half needs engine surfaces that do not exist yet (film.py's percentile auto-exposure and
// two-sigma bloom are global/multi-scale). So this measures the physics first, on a
// PLACEHOLDER exposure, where the answer is unambiguous.
//
// Dispatch path: `RenderPipeline.encodeOffscreenStages` — the production stage walk
// `drawWithStaged` runs. phi (persistent, 24 Jacobi sweeps) → state (persistent MHD
// advance) → compose. Nothing here reimplements the walk or the ping-pong.
//
// What it measures, per frame, from the live persistent state texture:
//   omega RMS / max      — is the vorticity bounded, or running away?
//   psi   RMS / max       — same for the flux function
//   J     RMS             — the VISUAL signal (§4: "J is what the fragment colours")
//   checkerboard energy   — the grid-scale pile-up Hou–Li existed to kill. This is the
//                           number that says whether the §8.1 substitute actually works.
//   watchdog trips        — ALFVEN.1's guard firing means the field went non-finite
//
// A soak that ends finite, bounded, non-zero AND with flat checkerboard energy is the
// evidence that the substitute holds. Rising checkerboard energy is the Hou–Li gap showing
// up, and is a finding to report, not a constant to tune away.

import Testing
import Foundation
import Metal
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Alfvén stability soak (ALFVEN.2)")
@MainActor
struct AlfvenStabilitySoakTests {

    private static let edge = 256          // the spike's grid (ALF_N=256)
    private static let subject = "Alfvén"

    /// Frames to soak. 900 ≈ 15 s at 60 fps — past the ~12 s at which the CPU spike's
    /// driven steady state condensed into `06_anti_static_quilt.png` (§5), so the soak
    /// covers the window where the physics is known to misbehave.
    private static var frameCount: Int {
        ProcessInfo.processInfo.environment["ALFVEN_SOAK_FRAMES"].flatMap(Int.init) ?? 900
    }

    private struct Sample {
        var omegaRMS = 0.0, omegaMax = 0.0
        var psiRMS = 0.0, psiMax = 0.0
        var jRMS = 0.0
        var checker = 0.0
        var phiRMS = 0.0
        var uMaxTexels = 0.0
        var finite = true
    }

    @Test("the MHD field stays finite, bounded and non-degenerate across a long soak")
    func fieldIsStable() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subject }) else {
            Issue.record("\(Self.subject) not found — sidecar decode or shader compile failed")
            return
        }
        let specs = preset.stages.map {
            StagedStageSpec(name: $0.name, pipelineState: $0.pipelineState, samples: $0.samples,
                            writesToDrawable: $0.writesToDrawable, persistent: $0.persistent,
                            iterations: $0.iterations, pixelFormat: $0.pixelFormat)
        }
        let hasPhi = specs.contains { $0.name == "phi" && $0.persistent && $0.iterations == 24 }
        let hasState = specs.contains { $0.name == "state" && $0.persistent }
        #expect(hasPhi, "phi must be the persistent 24-sweep Jacobi stage")
        #expect(hasState, "state must be the persistent MHD advance stage")

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib,
                                          fftBuffer: buffers.fft, waveformBuffer: buffers.waveform)
        pipeline.setStagedRuntime(specs, drawableSize: CGSize(width: Self.edge, height: Self.edge))

        var trace: [Sample] = []
        trace.reserveCapacity(Self.frameCount)
        let total = Self.frameCount
        for i in 0..<total {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            pipeline.encodeOffscreenStages(commandBuffer: cmd, features: &features,
                                           stemFeatures: .zero)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
            // Sample sparsely in time; a full readback every frame dominates the soak.
            if i % 30 == 0 || i == total - 1 {
                var sample = try Self.measure(pipeline)
                try Self.measurePhi(pipeline, into: &sample)
                trace.append(sample)
            }
        }

        guard let first = trace.first, let last = trace.last else {
            throw HarnessError.setupFailed("no samples")
        }
        print("[alfven-soak] \(total) frames at \(Self.edge)² — omega/psi/J RMS and grid-scale energy")
        for (idx, s) in trace.enumerated() where idx % 4 == 0 || idx == trace.count - 1 {
            print(String(format: "[alfven-soak] f%4d  wRMS %8.4f | pRMS %7.4f | jRMS %8.5f "
                                 + "| checker %8.5f | phiRMS %10.3f | uMax %7.3f tx/frame",
                         idx * 30, s.omegaRMS, s.psiRMS, s.jRMS, s.checker,
                         s.phiRMS, s.uMaxTexels))
        }
        print("[alfven-soak] watchdog trips: \(pipeline.stagedWatchdogTripCount)")

        // ── Finiteness and the watchdog ──
        let allFinite = trace.allSatisfy { $0.finite }
        #expect(allFinite, "the MHD field went non-finite during the soak")
        #expect(pipeline.stagedWatchdogTripCount == 0, """
            ALFVEN.1's non-finite watchdog fired \(pipeline.stagedWatchdogTripCount) time(s) — \
            the field blew up. This is the §8.1 Hou–Li substitute failing, which is the \
            level-3 grounding risk, not a tuning problem.
            """)

        // ── Seeded, and still carrying signal ──
        #expect(first.psiRMS > 1e-3, "the field never seeded — psi is empty on the first sample")
        #expect(last.jRMS > 1e-3, """
            J decayed to nothing by frame \(total) — the field is dead and the render would be \
            the flat ground colour. §4: J is what the fragment colours.
            """)

        // ── Bounded: the clamps are a backstop, not the operating point ──
        #expect(last.omegaMax < 0.95 * 24.0, """
            omega is pinned at its clamp (\(last.omegaMax) vs 24.0) — the field is being held \
            together by clamping rather than by the diffusion, which is a divergence wearing \
            a seatbelt.
            """)
        #expect(last.psiMax < 0.95 * 12.0,
                "psi is pinned at its clamp (\(last.psiMax) vs 12.0)")
    }

    /// Read phi and derive the velocity the advection actually sees. This is the
    /// consumer-side measurement: omega only becomes motion via `u = curl(phi)`, so a
    /// healthy omega with a still-converging phi is a field that cannot stir yet.
    private static func measurePhi(_ pipeline: RenderPipeline, into s: inout Sample) throws {
        guard let tex = pipeline.stagedTexture(named: "phi") else {
            throw HarnessError.setupFailed("no phi texture")
        }
        let w = tex.width, h = tex.height
        var raw = [Float](repeating: 0, count: w * h * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: w * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: w, height: h, depth: 1)),
                         mipmapLevel: 0)
        }
        var sum = 0.0
        var uMax = 0.0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let phi = Double(raw[(y * w + x) * 4])
                sum += phi * phi
                let l = Double(raw[(y * w + x - 1) * 4]), r = Double(raw[(y * w + x + 1) * 4])
                let t = Double(raw[((y + 1) * w + x) * 4]), b = Double(raw[((y - 1) * w + x) * 4])
                // u = (-phi_y, phi_x), central differences, texels per unit time.
                let ux = -(t - b) * 0.5, uy = (r - l) * 0.5
                uMax = max(uMax, (ux * ux + uy * uy).squareRoot())
            }
        }
        s.phiRMS = (sum / Double((w - 2) * (h - 2))).squareRoot()
        // Displacement per frame is what the semi-Lagrangian trace actually uses.
        s.uMaxTexels = uMax * 0.016
    }

    /// Read the live persistent state texture and reduce it on the CPU.
    /// `.r = omega  .g = psi  .b = J`
    private static func measure(_ pipeline: RenderPipeline) throws -> Sample {
        guard let tex = pipeline.stagedTexture(named: "state") else {
            throw HarnessError.setupFailed("no state texture")
        }
        let w = tex.width, h = tex.height
        var raw = [Float](repeating: 0, count: w * h * 4)
        raw.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            tex.getBytes(base, bytesPerRow: w * 16,
                         from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                         size: MTLSize(width: w, height: h, depth: 1)),
                         mipmapLevel: 0)
        }
        var s = Sample()
        var wSum = 0.0, pSum = 0.0, jSum = 0.0
        for i in 0..<(w * h) {
            let omega = Double(raw[i * 4]), psi = Double(raw[i * 4 + 1]), j = Double(raw[i * 4 + 2])
            if !omega.isFinite || !psi.isFinite || !j.isFinite { s.finite = false }
            wSum += omega * omega; pSum += psi * psi; jSum += j * j
            s.omegaMax = max(s.omegaMax, abs(omega))
            s.psiMax = max(s.psiMax, abs(psi))
        }
        let n = Double(w * h)
        s.omegaRMS = (wSum / n).squareRoot()
        s.psiRMS = (pSum / n).squareRoot()
        s.jRMS = (jSum / n).squareRoot()

        // Grid-scale (checkerboard) energy in psi: the discrete operator that is zero on
        // any smooth field and maximal on the alternating mode Hou–Li was there to kill.
        // Interior only, so no wrap handling is needed.
        var cSum = 0.0
        var count = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = Double(raw[(y * w + x) * 4 + 1])
                let l = Double(raw[(y * w + x - 1) * 4 + 1])
                let r = Double(raw[(y * w + x + 1) * 4 + 1])
                let t = Double(raw[((y + 1) * w + x) * 4 + 1])
                let b = Double(raw[((y - 1) * w + x) * 4 + 1])
                let dgl = Double(raw[((y + 1) * w + x - 1) * 4 + 1])
                let dgr = Double(raw[((y + 1) * w + x + 1) * 4 + 1])
                let dbl = Double(raw[((y - 1) * w + x - 1) * 4 + 1])
                let dbr = Double(raw[((y - 1) * w + x + 1) * 4 + 1])
                let v = c - 0.5 * (l + r + t + b) + 0.25 * (dgl + dgr + dbl + dbr)
                cSum += v * v
                count += 1
            }
        }
        s.checker = (cSum / Double(max(count, 1))).squareRoot()
        return s
    }
}
