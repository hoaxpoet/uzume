// EnergeticFlybyStateTests — EFB.1 task 2: the music drivers for Energetic Flyby, on synthetic grids.
//
// Pure CPU checks of `EnergeticFlybyState`: a downbeat turns the colour exactly once, the turn stays in
// Kali's range, the bank eases with no per-frame step, travel never jumps and keeps moving at silence, the
// normalisers' warm-up does not overshoot (FH.17), and the per-track reset keeps travel and hue. Plus the GPU
// layout against the MSL struct, read through Metal reflection.

import Testing
import Metal
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("EnergeticFlybyState (EFB.1)")
struct EnergeticFlybyStateTests {

    private static let fps: Float = 60
    private static let dt: Float = 1 / fps

    /// A steady 4/4 grid at `bpm`, `seconds` long: barPhase01 ramps 0→1 per bar.
    private static func grid(bpm: Float = 120, seconds: Float, beatsPerBar: Float = 4) -> [FeatureVector] {
        let bar = beatsPerBar * 60 / bpm
        return (0..<Int(seconds * fps)).map { i in
            let t = Float(i) * dt
            var fv = FeatureVector(time: t, deltaTime: dt)
            fv.barPhase01 = (t / bar).truncatingRemainder(dividingBy: 1)
            fv.beatsPerBar = beatsPerBar
            fv.spectralFlux = 0.3
            fv.bassDev = 0.2
            return fv
        }
    }

    private static func run(_ drive: [FeatureVector], faithful: Bool = false) throws -> (EnergeticFlybyState, [EnergeticFlybyStateGPU]) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let state = try #require(EnergeticFlybyState(device: device, faithful: faithful))
        let trace = drive.map { fv -> EnergeticFlybyStateGPU in
            state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            return state.gpuState
        }
        return (state, trace)
    }

    // MARK: - Downbeat

    @Test("A downbeat produces exactly one colour step")
    func downbeatIsOneHueStep() throws {
        // 120 BPM 4/4: a bar is 2 s; 2.5 s crosses exactly one downbeat (t = 2.0).
        let (state, trace) = try Self.run(Self.grid(seconds: 2.5))
        let starts = trace.indices.dropFirst(2).filter {
            trace[$0].hue != trace[$0 - 1].hue && trace[$0 - 1].hue == trace[$0 - 2].hue
        }
        #expect(starts.count == 1, "colour steps start at frames \(starts)")
        let hueStep = trace.last!.hue - trace.first!.hue
        #expect(abs(hueStep - EnergeticFlybyState.hueStep) < 1e-4, "hue moved \(hueStep)")
        #expect(trace.allSatisfy { $0.flicker == 0 }, "no brightness flare on the shipped path")
        _ = state
    }

    @Test("The colour turn swings pink → orange → pink → blue and never leaves Kali's ±0.7 rad")
    func colourTurnStaysInKalisRange() throws {
        let (state, trace) = try Self.run(Self.grid(seconds: 33))   // 16 downbeats
        let limit = EnergeticFlybyState.hueStep + 1e-4
        #expect(trace.allSatisfy { abs($0.hue) <= limit }, "hue range \(trace.map(\.hue).min()!)…\(trace.map(\.hue).max()!)")
        // Settled hue half a bar after each of the first four downbeats (t = 2, 4, 6, 8).
        let settled = [3, 5, 7, 9].map { trace[$0 * 60].hue }
        let expected: [Float] = [0.7, 0, -0.7, 0]
        for (got, want) in zip(settled, expected) { #expect(abs(got - want) < 1e-3, "settled \(settled)") }
        // A track change continues the swing from where it is: no snap, and no repeated colour.
        state.reset()
        #expect(state.gpuState.hue == trace.last!.hue)
    }

    // MARK: - Bank

    @Test("The bank turns a quarter every second downbeat, alternating, with no per-frame step")
    func bankIsContinuousAndAlternates() throws {
        let (_, trace) = try Self.run(Self.grid(seconds: 17))   // downbeats at 2, 4, …, 16
        // smoothstep's peak slope is 1.5 × (π/2) / 1 s ≈ 2.36 rad/s → 0.039 rad per 60 fps frame.
        let bound: Float = 0.05
        let maxStep = zip(trace, trace.dropFirst()).map { abs($1.roll - $0.roll) }.max() ?? 0
        #expect(maxStep < bound, "max roll step \(maxStep) rad/frame")
        // Banks start on downbeats 1, 3, 5, 7 (t = 2, 6, 10, 14) and settle 1 s later.
        func roll(at t: Float) -> Float { trace[Int(t * Self.fps)].roll }
        #expect(abs(roll(at: 3.5) - .pi / 2) < 1e-3)
        #expect(abs(roll(at: 7.5)) < 1e-3)
        #expect(abs(roll(at: 11.5) - .pi / 2) < 1e-3)
        #expect(abs(roll(at: 5.5) - .pi / 2) < 1e-3, "no bank on the second downbeat")
    }

    // MARK: - Travel

    @Test("Travel is strictly increasing and never jumps")
    func travelNeverJumps() throws {
        var drive = Self.grid(seconds: 10)
        for i in drive.indices { drive[i].spectralFlux = i % 37 < 3 ? 5 : 0.05 }   // spiky energy
        let (_, trace) = try Self.run(drive)
        let maxStep = (EnergeticFlybyState.speedFloor + EnergeticFlybyState.speedGain) * Self.dt * 1.001
        for (a, b) in zip(trace, trace.dropFirst()) {
            #expect(b.travel > a.travel)
            #expect(b.travel - a.travel <= maxStep)
        }
        #expect(trace.allSatisfy { $0.camT == $0.travel }, "the shipped camera never parks")
    }

    @Test("Silence keeps the flight moving at the floor speed, at the glow floor")
    func silenceFliesAtTheFloor() throws {
        let drive = (0..<600).map { _ in FeatureVector(deltaTime: Self.dt) }
        let (_, trace) = try Self.run(drive)
        let expected = EnergeticFlybyState.speedFloor * Self.dt * Float(drive.count)
        #expect(abs(trace.last!.travel - expected) < 1e-3, "travel \(trace.last!.travel) vs \(expected)")
        #expect(trace.allSatisfy { $0.flicker == 0 && $0.glowBase == EnergeticFlybyState.glowFloor })
    }

    // MARK: - Normalisers

    @Test("The normalisers' first 8 s stay within 1.5x of the settled level on a constant input")
    func warmUpDoesNotOvershoot() throws {
        var drive = (0..<Int(20 * Self.fps)).map { _ in FeatureVector(deltaTime: Self.dt) }
        for i in drive.indices { drive[i].spectralFlux = 0.4; drive[i].bassDev = 0.3 }
        let device = try #require(MTLCreateSystemDefaultDevice())
        let state = try #require(EnergeticFlybyState(device: device, faithful: false))
        var energy: [Float] = [], bass: [Float] = []
        for fv in drive {
            state.tick(deltaTime: fv.deltaTime, features: fv, stems: .zero)
            energy.append(state.energy); bass.append(state.bass)
        }
        let early = Int(8 * Self.fps)
        for (name, series) in [("energy", energy), ("bass", bass)] {
            let settled = series.last!
            let peak = series[..<early].max()!
            #expect(peak <= 1.5 * settled, "\(name): first-8 s peak \(peak) vs settled \(settled)")
        }
        // Negative control: the same squash with a plain 8 s follower started at zero (no warm-up)
        // reads the first hits as huge — the FH.17 flash transition this rule exists to prevent.
        var mean: Float = 0
        let naive = EnergeticFlybyState.squash(0.3, mean: &mean, heard: 8, dt: Self.dt, gain: 3)
        var settledMean: Float = 0.3
        let settled = EnergeticFlybyState.squash(0.3, mean: &settledMean, heard: 8, dt: Self.dt, gain: 3)
        #expect(naive > 1.5 * settled, "negative control: naive \(naive) vs settled \(settled)")
    }

    // MARK: - Reset

    @Test("reset() clears normalisers and envelopes; travel and hue are untouched")
    func resetKeepsTravelAndHue() throws {
        let (state, trace) = try Self.run(Self.grid(seconds: 5))
        let before = trace.last!
        state.reset()
        let after = state.gpuState
        #expect(after.travel == before.travel)
        #expect(after.hue == before.hue)
        #expect(after.roll == before.roll, "the bank settles where it is — no snap")
        #expect(state.energy == 0 && state.bass == 0)
    }

    // MARK: - Faithful mode

    @Test("Faithful mode feeds Kali's own drivers")
    func faithfulModeIsKali() throws {
        let drive = (0..<70).map { _ in FeatureVector(deltaTime: 0.1) }   // clock → 7.0 s
        let (_, trace) = try Self.run(drive, faithful: true)
        let last = trace.last!
        #expect(abs(last.time - 7) < 1e-4 && last.travel == last.time && last.spin == last.time)
        #expect(last.camT == 8, "Kali parks at floor(t/4 + .5)·4 while mod(t, 10) > 5")
        let sine = sin(last.time) * 123.456
        #expect(abs(last.flicker - (sine - sine.rounded(.down))) < 1e-3)
        #expect(last.faithful == 1 && last.hue == 0 && last.roll == 0 && last.glowBase == 0.5)
    }

    // MARK: - Previous frame (EFB.4)

    @Test("Each frame carries the previous frame's camera, spin and hue (the motion vectors' source)")
    func previousFrameValues() throws {
        let (_, trace) = try Self.run(Self.grid(seconds: 3))
        for i in trace.indices.dropFirst() {
            let (now, last) = (trace[i], trace[i - 1])
            #expect(now.prevTime == last.time && now.prevTravel == last.travel && now.prevCamT == last.camT
                    && now.prevSpin == last.spin && now.prevRoll == last.roll && now.prevHue == last.hue,
                    "frame \(i)")
        }
    }

    // MARK: - GPU layout

    @Test("EnergeticFlybyStateGPU matches the MSL struct byte for byte (Metal reflection)")
    func gpuLayoutMatchesMSL() throws {
        #expect(MemoryLayout<EnergeticFlybyStateGPU>.stride == 64)
        let device = try #require(MTLCreateSystemDefaultDevice())
        // Compile exactly as PresetLoader does (shared preamble + the scene file, fast math, MSL 3.1).
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // → UzumeEngine/
        let source = try String(contentsOf: url.appendingPathComponent("Sources/Presets/Shaders/EnergeticFlyby.metal"),
                                encoding: .utf8)
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1
        let library = try device.makeLibrary(source: PresetLoader.shaderPreamble + "\n\n" + source, options: options)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        desc.fragmentFunction = library.makeFunction(name: "energetic_flyby_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        var reflection: MTLRenderPipelineReflection?
        _ = try device.makeRenderPipelineState(descriptor: desc, options: [.bindingInfo], reflection: &reflection)
        let binding = try #require(reflection?.fragmentBindings.first { $0.index == 6 } as? MTLBufferBinding)
        let members = try #require(binding.bufferStructType?.members)
        #expect(binding.bufferDataSize == MemoryLayout<EnergeticFlybyStateGPU>.size)
        let swiftOffsets: [String: Int] = [
            "time": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.time)!,
            "travel": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.travel)!,
            "camT": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.camT)!,
            "spin": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.spin)!,
            "flicker": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.flicker)!,
            "glowBase": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.glowBase)!,
            "hue": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.hue)!,
            "roll": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.roll)!,
            "faithful": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.faithful)!,
            "prevTime": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.prevTime)!,
            "prevTravel": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.prevTravel)!,
            "prevCamT": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.prevCamT)!,
            "prevSpin": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.prevSpin)!,
            "prevRoll": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.prevRoll)!,
            "prevHue": MemoryLayout<EnergeticFlybyStateGPU>.offset(of: \.prevHue)!
        ]
        for (name, offset) in swiftOffsets {
            let member = members.first { $0.name == name }
            #expect(member?.offset == offset, "\(name): MSL \(String(describing: member?.offset)) vs Swift \(offset)")
        }
    }
}
