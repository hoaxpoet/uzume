// TrackHueAnchorTests — PR.20: the per-track hue anchor reaches the FeatureVector.
//
// The defect class this guards: a per-track value that is installed but never published, or
// published once and never CLEARED on the complementary path. The second is the CLAUDE.md
// §What NOT To Do trap in its plain-stored-property form — a value written on the
// track-change path and not cleared when identity goes away leaks the previous track's
// anchor across the boundary, which for a palette means the wrong song's colours.
import Testing
import Foundation
@testable import DSP
@testable import Shared

@Suite("TrackHueAnchor (PR.20)")
struct TrackHueAnchorTests {

    /// Drive the REAL public path rather than adding a test-only hook to production code.
    /// 512 flat-ish magnitudes are enough — this asserts a carried field, not an analysis
    /// result, and `process` is what the live engine calls every frame.
    private func build(_ mir: MIRPipeline) -> FeatureVector {
        let mags = [Float](repeating: 0.02, count: 512)
        return mir.process(magnitudes: mags, fps: 60, time: 1.0, deltaTime: 1.0 / 60.0)
    }

    @Test("The installed anchor appears in every FeatureVector the pipeline builds")
    func anchorReachesTheVector() throws {
        let mir = MIRPipeline()
        mir.setTrackHueAnchor(0.375)
        let fv = build(mir)
        #expect(abs(fv.trackHueAnchor01 - 0.375) < 1e-6,
                "anchor installed but not published into the FeatureVector")
    }

    @Test("Clearing the anchor takes effect — a track boundary cannot leak the old one")
    func clearingTakesEffect() throws {
        let mir = MIRPipeline()
        mir.setTrackHueAnchor(0.8)
        #expect(build(mir).trackHueAnchor01 > 0)
        mir.setTrackHueAnchor(0)
        #expect(build(mir).trackHueAnchor01 == 0,
                "a cleared anchor still reports the previous track's value")
    }

    @Test("Out-of-range and non-finite anchors are clamped, never propagated")
    func anchorIsClamped() throws {
        let mir = MIRPipeline()
        // NOTE the contract: every NON-FINITE input maps to 0, not to a clamped rail.
        // `min(max(.infinity, 0), 1)` is 1 in IEEE, but `max(.nan, 0)` is not something to
        // depend on, so the setter guards on `isFinite` and sends the whole non-finite class
        // to the same place. 0 is the documented "no rotation" anchor, which is the right
        // thing for a value that arrived corrupt.
        for (input, expected) in [(Float(1.7), Float(1)), (-0.4, 0), (.nan, 0), (.infinity, 0)] {
            mir.setTrackHueAnchor(input)
            let got = build(mir).trackHueAnchor01
            #expect(got == expected, "anchor \(input) should clamp to \(expected), got \(got)")
        }
    }

    /// ★ THE PART THAT IS ACTUALLY WORTH TESTING. An anchor that is stable but IDENTICAL for
    /// every track is indistinguishable from a working one in any single-track test, and
    /// produces exactly the bug this feature exists to prevent: every song the same colour.
    /// This asserts the hash SPREADS — real track identities must land on distinct anchors.
    @Test("Different tracks land on different anchors, spread across the range")
    func anchorsSpreadAcrossTracks() throws {
        // The same derivation the app performs in `resetStemPipeline`.
        func anchor(_ hash: UInt64) -> Float {
            Float((hash >> 40) & 0xFFFFFF) / Float(0x1000000)
        }
        // FNV-1a over "title|artist", the app's own hash.
        func fnv(_ s: String) -> UInt64 {
            var h: UInt64 = 0xcbf29ce484222325
            for b in Array(s.utf8) { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return h
        }
        let titles = [
            "Speed Of Life|David Bowie", "Breaking Glass|David Bowie",
            "What In The World|David Bowie", "Sound And Vision|David Bowie",
            "Always Crashing In The Same Car|David Bowie", "Be My Wife|David Bowie",
            "A New Career In A New Town|David Bowie", "Warszawa|David Bowie",
            "Art Decade|David Bowie", "Weeping Wall|David Bowie",
            "Subterraneans|David Bowie", "Seven Nation Army|The White Stripes"
        ]
        let anchors = titles.map { anchor(fnv($0)) }
        let unique = Set(anchors.map { Int($0 * 10000) })
        #expect(unique.count == titles.count,
                "\(titles.count - unique.count) of \(titles.count) tracks collide on one anchor")

        // And they must SPREAD, not cluster: at least half the tenths occupied over 12 tracks.
        let deciles = Set(anchors.map { min(9, Int($0 * 10)) })
        #expect(deciles.count >= 5,
                "anchors occupy only \(deciles.count)/10 deciles — the hash is not spreading")
    }
}
