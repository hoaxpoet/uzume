// StemSeparatorMemoryTests — BUG-177: a loop of separations must not accumulate memory.
//
// Local-file preparation separates a song span by span on a background thread. MPSGraph hands
// back autoreleased objects (~32 MB a call) that such a loop never drained, so a 9-minute song
// peaked at 23 GB and a playlist of long songs ran the Mac out of memory (measured with
// PrepTimingRunner: 23.3 GB → 1.4 GB with the fix; the prepared cache byte-identical).
// This runs the production separator the way the preparation loop does and bounds the growth.

import Darwin
import Foundation
import Metal
import Testing
@testable import ML

@Suite("StemSeparator memory (BUG-177)", .serialized)
struct StemSeparatorMemoryTests {

    private static func footprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// Twenty separations on one background thread, as preparation runs them. Unfixed, each call
    /// leaves ~32 MB behind (646 MB here); fixed, the footprint barely moves (2 MB).
    ///
    /// The footprint is process-wide, so suites allocating concurrently in a parallel run add
    /// noise (170 MB and 327 MB observed). That noise is transient; the leak repeats on every
    /// batch. So the gate takes the minimum growth over up to three batches, stopping at the
    /// first clean one — a real leak fails all three.
    @Test func aLoopOfSeparations_doesNotAccumulate() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let separator = try StemSeparator(device: device)
        let tone = (0..<StemSeparator.requiredMonoSamples).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        _ = try separator.separate(audio: tone, channelCount: 1, sampleRate: StemSeparator.modelSampleRate)

        let bound: UInt64 = 150_000_000
        let done = DispatchSemaphore(value: 0)
        var growths: [UInt64] = []
        var failure: Error?
        let thread = Thread {
            do {
                for _ in 0..<3 {
                    let before = Self.footprintBytes()
                    for _ in 0..<20 {
                        _ = try separator.separate(audio: tone, channelCount: 1, sampleRate: StemSeparator.modelSampleRate)
                    }
                    let after = Self.footprintBytes()
                    let growth = after > before ? after - before : 0
                    growths.append(growth)
                    if growth < bound { break }
                }
            } catch { failure = error }
            done.signal()
        }
        thread.start()
        done.wait()
        if let failure { throw failure }
        // Measured: fixed 2 MB; unfixed 646 MB (~32 MB a call — hundreds of calls for a long song).
        let mb = growths.map { $0 / 1_000_000 }
        #expect((growths.min() ?? .max) < bound, "every batch of 20 separations grew the footprint: \(mb) MB")
    }
}
