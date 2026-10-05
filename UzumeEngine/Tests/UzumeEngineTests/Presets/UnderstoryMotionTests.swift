// UnderstoryMotionTests — UND.6: each instrument moves its own fronds (Matt's pick).

import Foundation
import Testing
@testable import Presets
@testable import Shared

// MARK: - UnderstoryMotionTests

@Suite("UnderstoryMotion")
struct UnderstoryMotionTests {

    private static let layout = UnderstoryLayout(seed: 5, aspect: 16.0 / 9.0)

    private static func indices(_ layer: UnderstoryLayout.Layer) -> [Int] {
        layout.fronds.indices.filter { layout.fronds[$0].layer == layer }
    }

    @Test("a drum hit flicks only the far row, sharply, on the hit")
    func drumHitFlicksFarRow() {
        var motion = UnderstoryMotion()
        let dt: Float = 1.0 / 240.0
        var f = FeatureVector()
        var peak: (time: Float, value: Float) = (0, 0)
        for i in 0..<240 {
            let t = Float(i) * dt
            f.spectralLevelRise = t >= 0.5 ? 0.9 : 0.0          // a hit at 0.5 s
            motion.step(f, .zero, presence: 0, clock: t, dt: dt)
            let far = abs(motion.bend(index: Self.indices(.far)[0], layout: Self.layout, clock: t))
            if far > peak.value { peak = (t, far) }
            #expect(Self.indices(.mid).allSatisfy { motion.bend(index: $0, layout: Self.layout, clock: t) == 0 })
            #expect(Self.indices(.near).allSatisfy { motion.bend(index: $0, layout: Self.layout, clock: t) == 0 })
        }
        #expect(motion.hits == 1)
        #expect(abs(peak.time - 0.5 - UnderstoryMotion.flickRise) < 0.01, "peak \(peak.time - 0.5) s after the hit")
        #expect(peak.value > 0.04)
    }

    @Test("hits closer than the refractory count once")
    func refractory() {
        var motion = UnderstoryMotion()
        var f = FeatureVector()
        let dt: Float = 1.0 / 120.0
        for i in 0..<120 {
            let t = Float(i) * dt
            f.spectralLevelRise = i.isMultiple(of: 4) ? 0.9 : 0.0   // a rising edge every 33 ms
            motion.step(f, .zero, presence: 0, clock: t, dt: dt)
        }
        #expect(motion.hits <= Int(1.0 / UnderstoryMotion.hitRefractory) + 1)
    }

    @Test("a bass note pushes the mid row outward, then lets go")
    func bassPushesMidRow() {
        var motion = UnderstoryMotion()
        var f = FeatureVector()
        let dt: Float = 1.0 / 60.0
        f.bassDev = 0.6
        for i in 0..<6 { motion.step(f, .zero, presence: 0, clock: Float(i) * dt, dt: dt) }
        let mids = Self.indices(.mid)
        let pushed = mids.map { motion.bend(index: $0, layout: Self.layout, clock: 0.1) }
        #expect(pushed.allSatisfy { abs($0) > 0.04 })
        for (index, bend) in zip(mids, pushed) {
            #expect((Self.layout.fronds[index].root.x < 0.5) == (bend < 0), "leans away from the centre")
        }
        f.bassDev = 0
        for i in 6..<66 { motion.step(f, .zero, presence: 0, clock: Float(i) * dt, dt: dt) }
        #expect(abs(motion.bend(index: mids[0], layout: Self.layout, clock: 1.1)) < 0.005, "released within a second")
    }

    @Test("the vocal line sways the near row only while a voice is present")
    func vocalLineSwaysNearRow() {
        func swayAfterRise(presence: Float) -> Float {
            var motion = UnderstoryMotion()
            var stems = StemFeatures.zero
            let dt: Float = 1.0 / 60.0
            stems.vocalsCentroid = 0.10
            for i in 0..<300 { motion.step(FeatureVector(), stems, presence: presence, clock: Float(i) * dt, dt: dt) }
            stems.vocalsCentroid = 0.20                       // the line rises
            for i in 300..<330 { motion.step(FeatureVector(), stems, presence: presence, clock: Float(i) * dt, dt: dt) }
            return motion.bend(index: Self.indices(.near)[0], layout: Self.layout, clock: 5.5)
        }
        #expect(swayAfterRise(presence: 1) > 0.05)
        #expect(swayAfterRise(presence: 0) == 0)
    }
}
