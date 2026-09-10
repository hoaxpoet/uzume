// TransientRiseTests — PR.22: `transientRise` must peak EARLIER than `levelRise`.
//
// The defect this guards is subtle: both fields are the same statistic and differ only in
// their time constants, so a build where the constants drift together — or where someone
// "tidies" the sibling to reuse the parent's — still produces a plausible-looking signal that
// fires on transients. It just fires late again, which is the whole thing PR.22 fixed.
//
// ⚠ ON THE INPUT. `SpectralAnalyzer+Density` carries a warning that a synthetic step is the
//   wrong probe for RATE INVARIANCE, and that is correct — a +12 dB step saturates the band at
//   any rate, which is why the old `LevelRiseTests` passed while the field was rate-dependent.
//   This test asks a different question: given the SAME input, which of two filters peaks
//   first. That is a timing property of the filters, and a controlled edge is the right probe
//   for it. The real-material evidence is the offline cross-correlation recorded in
//   KNOWN_ISSUES (+150 ms vs +30 ms against onset strength on two sessions); this test exists
//   so the ordering cannot silently invert.
import Testing
import Foundation
@testable import DSP

@Suite("TransientRise (PR.22)")
struct TransientRiseTests {

    /// Drive both filters with one level track and report the frame each first crosses `level`.
    ///
    /// ★ A RAMP, NOT A STEP, and the difference matters. A +10 dB STEP saturates the 2–7 dB
    ///   band within two frames whatever the lag window is, so it measured only 33 ms of lead
    ///   and would pass with the constants nearly identical — the exact failure mode
    ///   `SpectralAnalyzer+Density` warns about for the old `LevelRiseTests`. Real transients
    ///   have finite rise, and a ramp is what lets a 40 ms lag window separate from a 150 ms one.
    ///   30 ms, because that is the order of a real drum transient — a 250 ms ramp is not a
    ///   transient at all, and at that slope a 40 ms window spans too few dB to leave the floor,
    ///   which made the first version of this test assert the opposite of the truth.
    private func framesToCross(_ level: Float, dt: Float, quietDB: Float, loudDB: Float,
                               quietFrames: Int, rampSeconds: Float,
                               loudFrames: Int) -> (fast: Int?, slow: Int?) {
        let a = SpectralAnalyzer()
        var fast: Int?, slow: Int?
        var frame = 0
        for _ in 0..<quietFrames {
            a.advanceLevelRise(deltaTime: dt, levelDB: quietDB)
            frame += 1
        }
        let rampFrames = max(1, Int(rampSeconds / dt))
        for r in 0..<rampFrames {
            let t = Float(r) / Float(rampFrames)
            a.advanceLevelRise(deltaTime: dt, levelDB: quietDB + (loudDB - quietDB) * t)
            if fast == nil, a.transientRise >= level { fast = frame }
            if slow == nil, a.levelRise >= level { slow = frame }
            frame += 1
        }
        for _ in 0..<loudFrames {
            a.advanceLevelRise(deltaTime: dt, levelDB: loudDB)
            if fast == nil, a.transientRise >= level { fast = frame }
            if slow == nil, a.levelRise >= level { slow = frame }
            frame += 1
        }
        return (fast, slow)
    }

    /// ★ MEASURES ELEVATED DURATION, NOT CROSSING TIME — and the difference is the whole test.
    ///
    /// Two earlier versions of this asserted how soon each filter CROSSES a threshold on a
    /// synthetic edge, and both were wrong: a step saturates the dB band within two frames at
    /// any window (33 ms apparent lead), and a sharp ramp does the same (17 ms). Neither
    /// reproduces the ~120 ms measured on real music, because that figure is where a
    /// correlation PEAK sits over a whole track, not when one edge first crosses.
    ///
    /// The mechanism is that a fixed-lag difference stays elevated until its lagged term
    /// catches up: the parent holds for its 150 ms window, the sibling for 40 ms, on top of a
    /// release both share. So the honest synthetic probe is how long each STAYS up after a
    /// brief transient — which is exactly the quantity that would collapse if the two sets of
    /// constants ever drifted together.
    @Test("At 60 Hz the fast sibling stays elevated for much less time after a transient")
    func fastReleasesEarlierAt60Hz() throws {
        let dt: Float = 1.0 / 60.0
        let a = SpectralAnalyzer()
        for _ in 0..<120 { a.advanceLevelRise(deltaTime: dt, levelDB: -40) }

        // ★ A SUSTAINED step, not a brief burst. On a burst both filters see their difference
        //   return to zero at the same instant and the shared release dominates — measured, a
        //   50 ms burst gave only 17 ms of separation and said nothing about the windows. On a
        //   sustained rise the parent keeps comparing NOW against quiet-150-ms-ago while the
        //   sibling stops at 40 ms, and that gap is the thing being tested.
        var fastDown: Int?, slowDown: Int?
        for frame in 0..<240 {
            a.advanceLevelRise(deltaTime: dt, levelDB: -26)
            if fastDown == nil, a.transientRise < 0.5 { fastDown = frame }
            if slowDown == nil, a.levelRise < 0.5 { slowDown = frame }
            if fastDown != nil && slowDown != nil { break }
        }
        let f = try #require(fastDown, "transientRise never came back down")
        let sD = try #require(slowDown, "levelRise never came back down")
        let leadMs = Double(sD - f) * Double(dt) * 1000
        print("[transient-rise] 60 Hz: fast down at +\(f) frames, slow at +\(sD) "
              + "— sibling clears \(String(format: "%.0f", leadMs)) ms earlier")
        #expect(f < sD, "transientRise (\(f)) must clear before levelRise (\(sD))")
        #expect(leadMs >= 60,
                "the sibling clears only \(leadMs) ms earlier; the two window sets have drifted together and it has stopped being worth its own field")
    }

    /// It must never be WORSE than the parent on a slow path. At the 10 Hz local-file rate a
    /// 40 ms lag rounds to one frame — it cannot beat the data — but it must not regress.
    @Test("At the 10 Hz local-file rate it degrades gracefully, never worse than levelRise")
    func degradesGracefullyAt10Hz() throws {
        let dt: Float = 0.1
        let (fast, slow) = framesToCross(0.9, dt: dt, quietDB: -40, loudDB: -30,
                                         quietFrames: 40, rampSeconds: 0.03, loudFrames: 40)
        let f = try #require(fast, "transientRise never crossed at 10 Hz")
        let s = try #require(slow, "levelRise never crossed at 10 Hz")
        print("[transient-rise] 10 Hz: fast at frame \(f), slow at frame \(s)")
        #expect(f <= s, "at 10 Hz the fast sibling (frame \(f)) is LATER than levelRise (frame \(s))")
    }

    @Test("Both settle to zero on a flat level, and neither goes negative or non-finite")
    func settlesCleanly() throws {
        let a = SpectralAnalyzer()
        for _ in 0..<600 { a.advanceLevelRise(deltaTime: 1.0 / 60.0, levelDB: -35) }
        #expect(a.transientRise.isFinite && a.transientRise >= 0)
        #expect(a.transientRise < 0.02, "transientRise did not settle on a flat level: \(a.transientRise)")
        #expect(a.levelRise < 0.02, "levelRise did not settle on a flat level: \(a.levelRise)")
    }

    @Test("A reset clears the sibling's state as well as the parent's")
    func resetClearsBoth() throws {
        let a = SpectralAnalyzer()
        for _ in 0..<60 { a.advanceLevelRise(deltaTime: 1.0 / 60.0, levelDB: -40) }
        for _ in 0..<30 { a.advanceLevelRise(deltaTime: 1.0 / 60.0, levelDB: -25) }
        #expect(a.transientRise > 0.1, "precondition: the sibling should be elevated here")
        a.reset()
        #expect(a.transientRise == 0, "reset left transientRise at \(a.transientRise)")
        #expect(a.levelRise == 0, "reset left levelRise at \(a.levelRise)")
    }
}
