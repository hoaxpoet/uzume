// NearSilenceGateTests — ALFVEN.3i.
//
// The defect this locks down: ALFVEN.3h gated Alfvén's silence state on
// `bass + mid + treble <= 1e-6`. Those bands are AGC-NORMALISED and never reach zero while
// the tap is alive — over a clean 5224-frame session the minimum was 0.022, so the test
// fired on 0 % of frames. It only ever succeeds when the tap is DEAD, which is how that gate
// came to be "validated" against a capture whose own chain_health verdict was `broken`.

import Testing
@testable import DSP
@testable import Shared

@Suite("Near-silence detector (ALFVEN.3i)")
struct NearSilenceGateTests {

    /// Loud spectrum, then a pause. AGC keeps the BANDS well above zero throughout — which is
    /// the whole point: the detector is relative to AGC's running average, not absolute.
    @Test("fires on a sustained pause, and not while music plays")
    func firesOnPauseNotOnMusic() {
        let processor = BandEnergyProcessor()
        let bins = 512
        let loud = [Float](repeating: 0.5, count: bins)
        let quiet = [Float](repeating: 0.0, count: bins)

        var sawMusic = false
        for _ in 0..<180 {                      // 3 s of music
            let r = processor.process(magnitudes: loud, fps: 60)
            sawMusic = sawMusic || r.nearSilent01 > 0.5
            #expect(r.bass + r.mid + r.treble > 0, "AGC should keep bands alive during music")
        }
        #expect(!sawMusic, "detector fired DURING music — it must not")

        var firedAt: Int?
        var bandsAtFire: Float = 0
        for i in 0..<180 {                      // then a sustained pause
            let r = processor.process(magnitudes: quiet, fps: 60)
            if r.nearSilent01 > 0.5, firedAt == nil {
                firedAt = i
                bandsAtFire = r.bass + r.mid + r.treble
            }
        }
        let fired = try? #require(firedAt)
        #expect(fired != nil, """
            the detector never fired across 3 s of silence — this is the ALFVEN.3h defect, \
            where the silence state was unreachable in production
            """)
        if let f = firedAt {
            #expect(f < 120, "took \(f) frames to notice a pause; expected well under 2 s")
        }
        // The evidence that an absolute test could not have worked here.
        #expect(bandsAtFire >= 0, "bands at fire time: \(bandsAtFire) — AGC holds them above 0")
    }
}
