// AlfvenParams — the CPU mirror of the solver's GPU uniform block.
//
// Split from AlfvenSolver.swift at ALFVEN.3g for the 400-line lint ceiling. A coherent
// seam rather than an arbitrary cut: this struct is a CONTRACT, not behaviour — its field
// order and types must match `AlfvenParams` in AlfvenSolver.metal exactly, and the two are
// always edited in the same commit. Keeping it alone makes that pairing obvious.

import Foundation

/// Mirrors `AlfvenParams` in AlfvenSolver.metal. Layout is the GPU contract.
struct AlfvenParams {
    var dt: Float = 0
    var alpha: Float = 0
    var nu4: Float = 0
    var drive: Float = 0
    var time: Float = 0
    var cutoff: Float = 0
    var clampW: Float = 0
    var clampP: Float = 0
    var gridEdge: UInt32 = 0
    var seedKOmega: UInt32 = 0
    var seedKPsi: UInt32 = 0
    var seedAmpOmega: Float = 0
    var seedAmpPsi: Float = 0
    var seedPhase: Float = 0
    var blendRate: Float = 0
    /// Band limit for the DISPLAY quantity J; see `alfven_j_spectrum`.
    var jCutoff: Float = 0
    /// EMA coefficient for the mean|J| auto-exposure, derived from REAL dt (ALFVEN.3g).
    var expoAlpha: Float = 0
    /// Partial-adaptation exponent: 0 = the fixed constant, 1 = film.py exactly.
    var expoBeta: Float = 0
}

extension AlfvenSolver {

    func makeParams(time: Float) -> AlfvenParams {
        let cfg = configuration
        // Per-substep share of the re-seed crossfade, raised cosine (the spike's
        // advance_blend). Zero outside the blend window.
        let cycleStart = floor(time / cfg.cycleSeconds) * cfg.cycleSeconds
        let blendPhase = min(max((time - cycleStart) / cfg.blendTau, 0), 1)
        // Per-substep share of the crossfade, raised cosine (the spike's advance_blend,
        // alfven.py:115-127). The spike divides by its ACTUAL dt; this used `cfg.maxDt`,
        // the 0.005 ceiling, so the crossfade ran ~2.5x fast whenever the CFL was biting.
        let stepDt = lastAdaptiveDt > 0 ? lastAdaptiveDt : cfg.maxDt
        let blendRate: Float = blendPhase < 1
            ? (0.5 - 0.5 * cos(.pi * blendPhase)) * (stepDt / cfg.blendTau) * .pi
            : 0
        return AlfvenParams(
            dt: cfg.maxDt,
            alpha: cfg.alpha,
            nu4: cfg.nu4,
            drive: audioDrive,   // ALFVEN.3: bassDev envelope -> stirring vigour (§7)
            time: time,
            cutoff: cfg.spectralCutoff,
            clampW: cfg.clampOmega,
            clampP: cfg.clampPsi,
            gridEdge: UInt32(cfg.edge),
            seedKOmega: UInt32(cfg.seedKOmega),
            seedKPsi: UInt32(cfg.seedKPsi),
            seedAmpOmega: cfg.seedAmpOmega,
            seedAmpPsi: cfg.seedAmpPsi,
            seedPhase: 7.31 * floor(time / cfg.cycleSeconds) + 1.7,
            blendRate: blendRate,
            jCutoff: cfg.jCutoff,
            // REAL seconds, like the palette drift: exposure is perceptual, and an
            // adaptation that sped up when the field energised would read as the image
            // reacting to itself rather than to the music.
            expoAlpha: 1.0 - exp(-max(lastRealDt, 1e-4) / max(cfg.exposureTau, 1e-4)),
            expoBeta: cfg.exposureBeta)
    }
}
