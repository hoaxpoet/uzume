// UnderstoryFieldTests — UND.1 spring + drive invariants for Understory's CPU state.

import Testing
import Metal
@testable import Presets
@testable import Shared

// MARK: - UnderstoryFieldTests

@Suite("UnderstoryField")
struct UnderstoryFieldTests {

    private static func field() throws -> UnderstoryField {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try #require(UnderstoryField(device: device))
    }

    private static func features(bass: Float, treble: Float, dt: Float = 1 / 60) -> FeatureVector {
        var f = FeatureVector(bass: bass, treble: treble)
        f.deltaTime = dt
        f.aspectRatio = 16.0 / 9.0
        return f
    }

    @Test("Milkdrop levels: a steady band reads 1, a doubling reads 2, silence reads 1")
    func milkdropLevels() {
        var levels = UnderstoryField.MilkdropLevels()
        var last = (bass: Float(0), treble: Float(0))
        for _ in 0..<3000 { last = levels.step(bass: 0.3, treble: 0.01) }
        #expect(abs(last.bass - 1) < 1e-3 && abs(last.treble - 1) < 1e-3)
        last = levels.step(bass: 0.6, treble: 0.01)
        #expect(abs(last.bass - 2) < 0.02, "an instant doubling over a ~4 s average reads ~2 (\(last.bass))")
        var quiet = UnderstoryField.MilkdropLevels()
        for _ in 0..<6000 { last = quiet.step(bass: 0, treble: 0) }
        #expect(last.bass == 1 && last.treble == 1, "below the silence floor the level is pinned at average")
        var seeded = UnderstoryField.MilkdropLevels()
        let first = seeded.step(bass: 0.25, treble: 0.002)
        #expect(first.bass == 1 && first.treble == 1, "the average seeds from the first sample, not from 1.0")
    }

    @Test("silence leaves the frond upright; balanced bands bend it nowhere")
    func silenceIsUpright() throws {
        let field = try Self.field()
        for _ in 0..<600 { field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0, treble: 0)) }
        let frond = try #require(field.frondsForTesting().first)
        #expect(abs(frond.bend) < 1e-4)
        #expect(abs(frond.direction) < 1e-3)
    }

    @Test("bass leans the frond one way and treble the other")
    func bassAndTrebleOppose() throws {
        /// Settle at a steady mix, then swell one band to 2× and read the bend 0.5 s later.
        func bendAfterSwell(bassGain: Float, trebleGain: Float) throws -> Float {
            let field = try Self.field()
            for _ in 0..<3000 { field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01)) }
            for _ in 0..<30 {
                field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3 * bassGain, treble: 0.01 * trebleGain))
            }
            return try #require(field.frondsForTesting().first).bend
        }
        let bassy = try bendAfterSwell(bassGain: 2, trebleGain: 1)
        let trebly = try bendAfterSwell(bassGain: 1, trebleGain: 2)
        #expect(bassy < -0.01 && trebly > 0.01, "bass bend \(bassy), treble bend \(trebly)")
        #expect(abs(bassy + trebly) < 1e-3, "equal relative swells in either band mirror (scale-free levels)")
    }

    @Test("the springs integrate at 60 Hz whatever the render rate")
    func substepsAreRateIndependent() throws {
        func bend(after seconds: Float, at hz: Float) throws -> Float {
            let field = try Self.field()
            let dt = 1 / hz
            for _ in 0..<Int(seconds * hz) {
                field.tick(deltaTime: dt, features: Self.features(bass: 0.5, treble: 0.1, dt: dt))
            }
            return try #require(field.frondsForTesting().first).bend
        }
        let at60 = try bend(after: 2, at: 60)
        let at120 = try bend(after: 2, at: 120)
        let at30 = try bend(after: 2, at: 30)
        #expect(abs(at60 - at120) < 1e-5 && abs(at60 - at30) < 1e-5, "60 \(at60) / 120 \(at120) / 30 \(at30)")
    }

    @Test("the centred tile is the source's 4:3 frame")
    func centredTileIsFourByThree() {
        let tile = UnderstoryField.centredTile(aspect: 16.0 / 9.0)
        #expect(abs(tile.z * 16 / 9 / tile.w - 4.0 / 3.0) < 1e-5)
        #expect(abs(tile.x + tile.z / 2 - 0.5) < 1e-6)
        #expect(UnderstoryField.centredTile(aspect: 4.0 / 3.0) == SIMD4<Float>(0, 0, 1, 1))
    }
}
