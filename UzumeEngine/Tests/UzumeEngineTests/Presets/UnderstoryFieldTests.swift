// UnderstoryFieldTests — spring, drive, wind and layout invariants for Understory's CPU state
// (UND.1 → UND.2).

import Foundation
import Testing
import Metal
@testable import Presets
@testable import Shared

// MARK: - UnderstoryFieldTests

@Suite("UnderstoryField")
struct UnderstoryFieldTests {

    private static func field(seed: UInt32 = 7) throws -> UnderstoryField {
        let device = try #require(MTLCreateSystemDefaultDevice())
        return try #require(UnderstoryField(device: device, seed: seed))
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

    @Test("silence is still air: the field barely sways, and keeps swaying")
    func silenceIsStillAir() throws {
        let field = try Self.field()
        var samples: [Float] = []
        for i in 0..<1200 {
            field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0, treble: 0))
            if i >= 600 { samples.append(field.swayForTesting()[0]) }
        }
        let peak = samples.map(abs).max() ?? 0
        #expect(peak < 0.02, "idle breeze must stay small (peak sway \(peak))")
        #expect((samples.max() ?? 0) - (samples.min() ?? 0) > 1e-4, "silence must not freeze the field")
    }

    @Test("bass leans the field one way and treble the other")
    func bassAndTrebleOppose() throws {
        /// Settle at a steady mix, swell one band to 2× for 2.5 s (longer than the gust takes to
        /// cross the screen), and read every frond's sway relative to an unswelled run.
        func sway(bassGain: Float, trebleGain: Float) throws -> [Float] {
            let field = try Self.field()
            for _ in 0..<3000 { field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01)) }
            for _ in 0..<150 {
                field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3 * bassGain, treble: 0.01 * trebleGain))
            }
            return field.swayForTesting()
        }
        let base = try sway(bassGain: 1, trebleGain: 1)
        let bassy = zip(try sway(bassGain: 2, trebleGain: 1), base).map { $0 - $1 }
        let trebly = zip(try sway(bassGain: 1, trebleGain: 2), base).map { $0 - $1 }
        #expect(bassy.allSatisfy { $0 < -0.005 } && trebly.allSatisfy { $0 > 0.005 },
                "bass \(bassy.map { ($0 * 1000).rounded() / 1000 }) treble \(trebly.map { ($0 * 1000).rounded() / 1000 })")
    }

    @Test("the gust travels: a frond further right feels a swell later")
    func gustTravelsLeftToRight() throws {
        // Two identical fields; one gets a bass swell. The idle breeze moves both alike, so the
        // first frame a frond's sway DIVERGES between them is when the gust reached it.
        let calm = try Self.field(), gusty = try Self.field()
        let layout = calm.layoutForTesting
        let left = try #require(layout.fronds.indices.min { layout.fronds[$0].root.x < layout.fronds[$1].root.x })
        let right = try #require(layout.fronds.indices.max { layout.fronds[$0].root.x < layout.fronds[$1].root.x })
        for _ in 0..<3000 {
            calm.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01))
            gusty.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01))
        }
        var leftMoved: Int?, rightMoved: Int?
        for frame in 0..<180 {
            calm.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01))
            gusty.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.6, treble: 0.01))
            let gap = zip(gusty.swayForTesting(), calm.swayForTesting()).map { abs($0 - $1) }
            if leftMoved == nil, gap[left] > 1e-4 { leftMoved = frame }
            if rightMoved == nil, gap[right] > 1e-4 { rightMoved = frame }
        }
        let leftFrame = try #require(leftMoved), rightFrame = try #require(rightMoved)
        let expected = layout.fronds[right].delaySubsteps - layout.fronds[left].delaySubsteps
        #expect(abs((rightFrame - leftFrame) - expected) <= 2,
                "left felt it at frame \(leftFrame), right at \(rightFrame); delay gap \(expected) substeps")
    }

    @Test("GPU layout: a 32 B header and 80 B fronds, as Understory.metal declares them")
    func gpuLayout() {
        // The shader's frond array is float4-aligned: it starts at 32 only if the header is 32.
        #expect(MemoryLayout<UnderstoryField.Header>.stride == 32)
        #expect(MemoryLayout<UnderstoryField.Frond>.stride == 80)
    }

    @Test("palette follows harmony and holds when atonal; trails lengthen with arousal")
    func colourRoutes() throws {
        func run(fifths: Float, consonance: Float, arousal: Float) throws -> (Float, Float) {
            let field = try Self.field()
            var f = Self.features(bass: 0.3, treble: 0.01)
            f.tonalPhaseFifths = fifths; f.tonalConsonance = consonance; f.arousal = arousal
            for _ in 0..<1200 { field.tick(deltaTime: 1 / 60, features: f) }
            let colour = field.colourForTesting()
            return (colour.rotation, colour.trailDecay)
        }
        let tonal = try run(fifths: .pi / 2, consonance: 0.5, arousal: 0)
        // Noisy harmony (the phase flipping half a turn every frame, just above the gate) must
        // never pop the palette: no published step larger than the slew allows.
        let noisy = try Self.field()
        var last: Float = 0, worst: Float = 0
        for i in 0..<600 {
            var f = Self.features(bass: 0.3, treble: 0.01)
            f.tonalPhaseFifths = i.isMultiple(of: 2) ? 2.6 : -0.5
            f.tonalConsonance = 0.09
            noisy.tick(deltaTime: 1 / 60, features: f)
            let now = noisy.colourForTesting().rotation
            var step = now - last; step -= step.rounded()
            worst = max(worst, abs(step)); last = now
        }
        #expect(worst <= UnderstoryField.paletteSlew / 60 + 1e-5, "largest per-frame palette step \(worst)")
        #expect(abs(tonal.0 - 0.25) < 0.01, "fifths at π/2 → a quarter turn (\(tonal.0))")
        let atonal = try run(fifths: .pi / 2, consonance: 0.0, arousal: 0)
        #expect(abs(atonal.0) < 1e-4, "atonal music holds the palette (\(atonal.0))")
        let calm = try run(fifths: 0, consonance: 0, arousal: -0.4).1
        let intense = try run(fifths: 0, consonance: 0, arousal: 0.7).1
        #expect(calm < intense && calm >= UnderstoryField.trailDecayCalm - 1e-4
                && intense <= UnderstoryField.trailDecayIntense + 1e-4)
    }

    private static func stems(voice: Float, brass: Float) -> StemFeatures {
        var stems = StemFeatures.zero
        stems.vocalsEnergyRel = voice
        stems.vocalsEnergy = 0.3; stems.drumsEnergy = 0.2; stems.bassEnergy = 0.2; stems.otherEnergy = 0.2
        stems.brassActivity = brass
        return stems
    }

    @Test("a sung line uncoils the fiddleheads; the same energy from a horn does not")
    func voiceUncoils() throws {
        func unfurl(voice: Float, brass: Float, seconds: Float) throws -> Float {
            let field = try Self.field()
            for _ in 0..<Int(seconds * 60) {
                field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01),
                           stems: Self.stems(voice: voice, brass: brass))
            }
            return field.unfurlForTesting
        }
        let sung = try unfurl(voice: 0.5, brass: 0.001, seconds: 1.5)
        #expect(abs(sung - (1 - exp(-1))) < 0.05, "one attack time → ~63 % open (\(sung))")
        #expect(try unfurl(voice: 0.5, brass: 0.2, seconds: 10) < 0.01, "a horn in the vocal stem is vetoed")
        #expect(try unfurl(voice: 0.0, brass: 0.0, seconds: 10) < 0.01, "no voice, no unfurl")
    }

    @Test("silence after a sung line lets them coil back over the release")
    func voiceRelease() throws {
        let field = try Self.field()
        for _ in 0..<(20 * 60) {
            field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01),
                       stems: Self.stems(voice: 0.5, brass: 0))
        }
        let open = field.unfurlForTesting
        for _ in 0..<(5 * 60) {
            field.tick(deltaTime: 1 / 60, features: Self.features(bass: 0.3, treble: 0.01),
                       stems: Self.stems(voice: 0, brass: 0))
        }
        #expect(open > 0.99 && abs(field.unfurlForTesting - exp(-1)) < 0.05, "\(open) → \(field.unfurlForTesting)")
    }

    @Test("the fiddleheads open in a wave, left to right, and fully at the top of the envelope")
    func openingStagger() {
        let mid = (0..<4).map { UnderstoryVoice.opening(order: $0, unfurl: 0.5) }
        #expect(mid == mid.sorted(by: >), "left opens first: \(mid)")
        #expect((0..<4).allSatisfy { UnderstoryVoice.opening(order: $0, unfurl: 1) == 1 })
        #expect((0..<4).allSatisfy { UnderstoryVoice.opening(order: $0, unfurl: 0) == 0 })
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
}

// MARK: - UnderstoryLayoutTests

@Suite("UnderstoryLayout")
struct UnderstoryLayoutTests {

    @Test("a field: 10 open fronds and 4 fiddleheads, far drawn before near, lead frond near and open")
    func fieldComposition() {
        let layout = UnderstoryLayout(seed: 1, aspect: 16.0 / 9.0)
        #expect(layout.fronds.count == UnderstoryLayout.frondCount)
        #expect(layout.fronds.filter(\.isFiddlehead).count == 4)
        let layers = layout.fronds.map(\.layer.rawValue)
        #expect(layers == layers.sorted(), "painter's order is far → near")
        let lead = layout.fronds[layout.leadIndex]
        #expect(lead.layer == .near && !lead.isFiddlehead)
    }

    @Test("tiles tile the atlas exactly, with square pixels, at several aspects")
    func tilesPackTheAtlas() {
        for aspect: Float in [16.0 / 9.0, 16.0 / 10.0, 21.0 / 9.0, 4.0 / 3.0] {
            let layout = UnderstoryLayout(seed: 3, aspect: aspect)
            let area = layout.fronds.reduce(Float(0)) { $0 + $1.tile.z * $1.tile.w }
            #expect(abs(area - 1) < 1e-5, "tiles cover the atlas once (aspect \(aspect))")
            for frond in layout.fronds {
                #expect(frond.tile.x >= 0 && frond.tile.y >= 0
                        && frond.tile.x + frond.tile.z <= 1 + 1e-6 && frond.tile.y + frond.tile.w <= 1 + 1e-6)
                // tile px aspect == crop aspect in a 4:3 frame
                let tilePx = frond.tile.z * aspect / frond.tile.w
                let cropPx = (frond.crop.z - frond.crop.x) * (4.0 / 3.0) / (frond.crop.w - frond.crop.y)
                #expect(abs(tilePx - cropPx) < 1e-4, "square texels (aspect \(aspect))")
                #expect(frond.crop.w > 0.53, "the crop keeps the whole seed")
            }
        }
    }

    @Test("a seed always grows the same field; another seed grows another")
    func seededLayout() {
        let first = UnderstoryLayout(seed: 42, aspect: 16.0 / 9.0)
        #expect(first == UnderstoryLayout(seed: 42, aspect: 16.0 / 9.0))
        #expect(first.fronds.map(\.root) != UnderstoryLayout(seed: 43, aspect: 16.0 / 9.0).fronds.map(\.root))
    }

    @Test("UNDERSTORY_LAYOUT=<seed> prints a field's layout (diagnostics)")
    func dumpLayout() {
        guard let raw = ProcessInfo.processInfo.environment["UNDERSTORY_LAYOUT"], let seed = UInt32(raw) else { return }
        let layout = UnderstoryLayout(seed: seed, aspect: 16.0 / 9.0)
        for (i, f) in layout.fronds.enumerated() {
            print(String(format: "[understory-layout] %2d %@ root (%.2f, %.2f) scale %.2f curl %+.2f%@", i,
                         String(describing: f.layer), f.root.x, f.root.y, f.scale, f.curl,
                         i == layout.leadIndex ? " LEAD" : ""))
        }
    }

    @Test("roots spread across the screen without a mirror (FA #44)")
    func noMirrorSymmetry() throws {
        for seed: UInt32 in 0..<20 {
            let xs = UnderstoryLayout(seed: seed, aspect: 16.0 / 9.0).fronds.map(\.root.x)
            let low = try #require(xs.min()), high = try #require(xs.max())
            #expect(low < 0.25 && high > 0.75, "seed \(seed) leaves a side empty")
            let mirrored = xs.map { 1 - $0 }.sorted()
            let paired = zip(xs.sorted(), mirrored).allSatisfy { abs($0 - $1) < 0.01 }
            #expect(!paired, "seed \(seed) is mirror-symmetric")
        }
    }
}
