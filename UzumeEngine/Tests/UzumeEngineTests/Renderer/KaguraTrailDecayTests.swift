// KaguraTrailDecayTests — the trail fades in WALL time, whatever the frame rate (KAG.2 task 3).
//
// BUG-097 is the lesson: a per-frame constant ties a duration to the frame rate. Kagura's trail
// decays by `0.05^(dt / 0.4 s)` and deposits `rate · dt` per segment, so the same 2 s of motion
// rendered at 30, 60 and 120 fps must leave the same trail. The negative control renders the
// 120 fps run with the 60 fps per-frame multiplier and deposit — the per-frame-constant bug — and
// must NOT match.

import Foundation
import Metal
import simd
import Testing
@testable import Renderer

@Suite("Kagura trail decays per elapsed time (KAG.2)", .serialized)
struct KaguraTrailDecayTests {

    private static let width = 1280, height = 720

    /// Deterministic motion: fifteen joints circling at 1 rev/s. Kept moving to the end: a joint
    /// held still builds a steady-state blob whose energy (rate × time constant) a per-frame bug
    /// leaves unchanged, which is exactly what made the first version of the control toothless.
    private static func joints(at time: Double) -> [SIMD3<Float>] {
        (0..<15).map { index -> SIMD3<Float> in
            let phase = 2 * Double.pi * time + Double(index) * 0.4
            return SIMD3(Float(0.3 * cos(phase)), Float(0.3 + 0.1 * Double(index) + 0.2 * sin(phase)), 0)
        }
    }

    /// Render 2 s at `fps` and read back the trail (rgba16Float → Float, red channel).
    private static func trail(fps: Double, perFrameConstantAt constantFps: Double? = nil) throws -> [Float] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let dancer = try KaguraDancer(device: ctx.device, library: lib.library)
        dancer.ensureAllocated(width: width, height: height)
        let frames = Int(2 * fps)
        for frame in 0...frames {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            // The bug under test: a decay/deposit sized for one frame rate, applied at another.
            let dt = Float(1 / (constantFps ?? fps))
            dancer.encodeFrame(joints: joints(at: Double(frame) / fps), deltaTime: dt, commandBuffer: cmd)
            cmd.commit()
        }
        let texture = try #require(dancer.trailTexture)
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        let staging = try #require(ctx.device.makeTexture(descriptor: desc))
        let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
        let blit = try #require(cmd.makeBlitCommandEncoder())
        blit.copy(from: texture, to: staging)
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var halves = [Float16](repeating: 0, count: width * height * 4)
        halves.withUnsafeMutableBytes {
            staging.getBytes($0.baseAddress!, bytesPerRow: width * 8,   // swiftlint:disable:this force_unwrapping
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        let red = stride(from: 0, to: halves.count, by: 4).map { Float(halves[$0]) }
        if let dir = ProcessInfo.processInfo.environment["KAGURA_TRAIL_DUMP"] {   // eyes-on debugging
            let peak = max(red.max() ?? 1, 1e-6)
            var pgm = Data("P5\n\(width) \(height)\n255\n".utf8)
            pgm.append(contentsOf: red.map { UInt8(min(255, sqrt($0 / peak) * 255)) })
            try pgm.write(to: URL(fileURLWithPath: dir).appendingPathComponent(
                "trail_\(Int(fps))\(constantFps.map { "_bug\(Int($0))" } ?? "").pgm"))
        }
        return red
    }

    private static func relativeL1(_ lhs: [Float], _ rhs: [Float]) -> Float {
        let diff = zip(lhs, rhs).reduce(Float(0)) { $0 + abs($1.0 - $1.1) }
        return diff / max(rhs.reduce(0, +), 1e-6)
    }

    @Test("The same motion at 30, 60 and 120 fps leaves the same trail")
    func frameRateIndependent() throws {
        let reference = try Self.trail(fps: 60)
        let total = reference.reduce(0, +)
        #expect(total > 1, "nothing was deposited")
        var worst: Float = 0
        for fps in [30.0, 120.0] {
            let other = try Self.trail(fps: fps)
            let energy = other.reduce(0, +) / total
            let l1 = Self.relativeL1(other, reference)
            worst = max(worst, l1)
            print("[kagura-trail] \(Int(fps)) fps vs 60: energy ratio \(String(format: "%.4f", energy)), "
                  + "relative L1 \(String(format: "%.4f", l1))")
            #expect(abs(energy - 1) < 0.03, "\(Int(fps)) fps trail energy differs by \(energy - 1)")
            #expect(l1 < 0.08, "\(Int(fps)) fps trail differs from 60 fps by L1 \(l1)")
        }
        // Negative control: 120 fps with the 60 fps per-frame constants — twice the decay steps
        // and twice the deposits per second.
        let buggy = try Self.trail(fps: 120, perFrameConstantAt: 60)
        let buggyL1 = Self.relativeL1(buggy, reference)
        print("[kagura-trail] per-frame-constant bug at 120 fps: relative L1 \(String(format: "%.4f", buggyL1))")
        #expect(buggyL1 > 4 * worst && buggyL1 > 0.2, "the control does not separate — the check has no teeth")
    }
}
