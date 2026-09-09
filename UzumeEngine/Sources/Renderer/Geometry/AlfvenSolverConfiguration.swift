// AlfvenSolverConfiguration — the solver's tunables.
//
// Split from AlfvenSolver.swift for the 400-line lint ceiling. Values that are DERIVED
// from the grid rather than copied from the spike carry their reasoning inline; the
// short version is that k^4 hyperdiffusion and the Hou-Li filter are both violently
// resolution-dependent, so a constant tuned at one N is wrong at another.

import Foundation
import Metal
import simd
import Shared

// MARK: - Configuration

/// Tunables for the solver. Values are the spike's where the spike has one.
public struct AlfvenSolverConfiguration: Sendable {
    /// Grid edge. Must be a power of two (the FFT requires it) and <= 1024 (threadgroup
    /// memory). Fixed rather than drawable-sized: D-244's N^2 finding and the FFT's
    /// power-of-two requirement both point the same way, and it caps cost independently
    /// of display resolution.
    public var edge: Int
    /// Upper bound on the timestep. The CFL reduction lowers it as the field energises;
    /// it never raises it above this.
    public var maxDt: Float
    /// Substeps per frame. Free here — each runs its own full RHS evaluation, so none of
    /// them sees stale derivatives.
    public var substeps: Int
    public var alpha: Float
    /// k^4 hyperdiffusion. DERIVED from the grid rather than copied: the spike's
    /// nu4 = 2.5e-7 is tuned for N = 256, and k^4 damping is violently
    /// resolution-dependent — the same constant at N = 128 gives 17x less dissipation at
    /// the dealias cutoff (13.3/s vs 0.83/s), which is exactly the enstrophy pile-up seen
    /// as omega climbing. What should be held fixed is the dissipation RATE at the cutoff,
    /// so nu4 = C / k_cut^4 with C taken from the spike's own operating point.
    public var nu4: Float
    public var drive: Float
    /// Hou-Li filter kmax. DERIVED, like `nu4`, and for the same reason: the spike uses
    /// `kmax = N/2` (alfven.py:37,41-42) — the Nyquist wavenumber — so the filter's shape
    /// relative to the grid is resolution-independent. A fixed constant here (it was 100)
    /// is a far harder wall on a 256 grid than the spike's own, and a brick wall in
    /// k-space is sinc ringing in real space: visible as hatching along steep J ridges.
    /// The 2/3 dealias mask is separate and applies only to the bracket product.
    public var spectralCutoff: Float
    public var clampOmega: Float
    public var clampPsi: Float
    public var seedKOmega: Int
    public var seedKPsi: Int
    public var seedAmpOmega: Float
    public var seedAmpPsi: Float
    /// SIMULATION seconds per re-seed — not real seconds; see `AlfvenSolver.simClock`.
    /// §5: a sustained driven MHD state condenses into a static quilt, so the look is a
    /// sequence of transients.
    ///
    /// This length IS the look. Brightness across one transient (drive 0, N=256, through
    /// film.py's own mapping) peaks at meanLum 0.33 for the first ~1.5 sim seconds, falls
    /// to 0.13 by t = 2.75 and recovers only to 0.19 by t = 5.5 — so the cycle decides
    /// whether the preset lives in the reference look or in the trough. Measured over
    /// 900 frames, mean(aJ) averaged / fraction of frames at-or-above REF 01:
    ///
    ///     cycle  2.0 -> 0.233, 70%   (min 0.114 — never reaches the trough)
    ///     cycle  3.0 -> 0.185, 40%
    ///     cycle  4.0 -> 0.164, 27%
    ///     cycle  6.0 -> 0.154, 26%   (~the spike film's own 7.9 s cadence)
    ///     cycle 22.0 -> 0.143, 18%   (the previous value, and it was in REAL seconds)
    ///
    /// 2.0 is set because the silence target (`05_atmosphere_relaxed_state`, meanLum
    /// 0.422) is explicitly the broad-lobed, soft-seamed, few-seamed state, and that is
    /// the early transient. It is a TRADE: with `blendTau` 1.1 the crossfade fills over
    /// half of each cycle, so the field re-braids continuously and never fully sharpens
    /// its current sheets — and the seam, not the lobe, is what REF 02 says the eye should
    /// land on. Longer cycles buy sharper seams and pay in darkness. Matt's call.
    public var cycleSeconds: Float
    /// Crossfade duration for a re-seed, seconds (the spike's advance_blend tau).
    public var blendTau: Float
    /// Band limit for the DISPLAY quantity J, in mode numbers. See `alfven_j_spectrum`:
    /// J = lap(psi) multiplies psi by k^2, which lifts the float32 FFT noise floor into
    /// the visible range as grid-scale striping. psi has no real content up there, so
    /// this removes numerical noise only. The state is not filtered by it.
    public var jCutoff: Float
    /// Half-range of the palette drift, in hue turns. film.py drifts the opponent centre
    /// (`hue = 0.46 + 0.26*centroid01`) and `04_palette_opponent_drift.png` annotates both
    /// ends — "left = early (acid green ↔ violet), right = late (magenta ↔ teal)". We had
    /// pinned it at the late end because that is the column Matt picked; this un-pins the
    /// drift that was designed in rather than inventing one, so the traverse stays inside
    /// the referenced palette family instead of touring the whole wheel.
    ///
    /// 0.26 is film.py's own span: the centre travels 0.72 → 0.46 and back.
    public var displayHueSpan: Float
    /// Seconds for one full there-and-back palette traverse, on the LISTENER's clock.
    ///
    /// Deliberately not `simClock`: the field's evolution rate is a numerics matter (it
    /// moves with the CFL), whereas the palette is perceptual and should not speed up or
    /// slow down with the field's energy. Slow by design — the design doc calls the centre
    /// "slowly drifting" — and much slower than the 2 s re-seed so structure and colour do
    /// not beat against each other.
    public var displayHuePeriodSeconds: Float
    /// How strongly the traverse LINGERS at the anchor rather than at the far end.
    ///
    /// A plain raised cosine has zero derivative at both ends, so it dwells equally at
    /// 0.72 and at 0.46 — which would spend as much time in acid-green<->violet as in the
    /// magenta<->teal Matt asked to keep. Raising the normalised traverse to this power
    /// biases the dwell toward the anchor while still reaching the far end: at 2.0 the
    /// centre spends roughly twice as long in the near half of the range as the far half.
    /// 1.0 restores the symmetric cosine.
    public var displayHueDwell: Float

    public init(
        edge: Int = 256,
        maxDt: Float = 0.005,          // the spike's own ceiling
        substeps: Int = 4,
        alpha: Float = 0.16,
        nu4: Float? = nil,     // nil => derived from `edge`, see the property comment
        drive: Float = 0.020,
        spectralCutoff: Float? = nil,  // nil => Nyquist, edge/2
        clampOmega: Float = 200.0,     // a genuine backstop: ~25x the measured equilibrium
        clampPsi: Float = 100.0,
        seedKOmega: Int = 3,
        seedKPsi: Int = 2,
        seedAmpOmega: Float = 1.2,
        seedAmpPsi: Float = 0.9,
        cycleSeconds: Float = 2.0,   // SIM seconds; see the property comment
        blendTau: Float = 1.1,
        jCutoff: Float = 48.0,
        displayHueSpan: Float = 0.26,
        displayHuePeriodSeconds: Float = 80.0,
        displayHueDwell: Float = 2.0
    ) {
        self.edge = edge
        self.maxDt = maxDt
        self.substeps = substeps
        self.alpha = alpha
        // C = 2.5e-7 * ((2/3)*128)^4 — the spike's dissipation rate at its own cutoff.
        let kCut = (2.0 / 3.0) * (Float(edge) / 2.0)
        self.nu4 = nu4 ?? (13.256 / (kCut * kCut * kCut * kCut))
        self.drive = drive
        self.spectralCutoff = spectralCutoff ?? (Float(edge) / 2.0)
        self.clampOmega = clampOmega
        self.clampPsi = clampPsi
        self.seedKOmega = seedKOmega
        self.seedKPsi = seedKPsi
        self.seedAmpOmega = seedAmpOmega
        self.seedAmpPsi = seedAmpPsi
        self.cycleSeconds = cycleSeconds
        self.blendTau = blendTau
        self.jCutoff = jCutoff
        self.displayHueSpan = displayHueSpan
        self.displayHuePeriodSeconds = displayHuePeriodSeconds
        self.displayHueDwell = displayHueDwell
    }
}

/// Mirrors `AlfvenDisplayParams` in AlfvenSolver.metal. Layout is the GPU contract.
