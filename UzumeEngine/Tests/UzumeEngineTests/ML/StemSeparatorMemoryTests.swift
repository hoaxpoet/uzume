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
    @Test func aLoopOfSeparations_doesNotAccumulate() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let separator = try StemSeparator(device: device)
        let tone = (0..<StemSeparator.requiredMonoSamples).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        _ = try separator.separate(audio: tone, channelCount: 1, sampleRate: StemSeparator.modelSampleRate)

        let done = DispatchSemaphore(value: 0)
        var growth: UInt64 = 0
        var failure: Error?
        let thread = Thread {
            let before = Self.footprintBytes()
            do {
                for _ in 0..<20 {
                    _ = try separator.separate(audio: tone, channelCount: 1, sampleRate: StemSeparator.modelSampleRate)
                }
            } catch { failure = error }
            let after = Self.footprintBytes()
            growth = after > before ? after - before : 0
            done.signal()
        }
        thread.start()
        done.wait()
        if let failure { throw failure }
        // Measured: fixed 2 MB; unfixed 646 MB (~32 MB a call — hundreds of calls for a long song).
        #expect(growth < 150_000_000, "20 separations grew the footprint by \(growth / 1_000_000) MB")
    }
}
