// SystemAudioCaptureTeardownTests — BUG-139 regression gate.
//
// `teardownTapResources()` used to hold `stateLock` across `AudioDeviceStop`,
// which blocks until the CoreAudio IO proc drains — while the IO proc itself
// took `stateLock` in `probeInstallRMS`. Teardown waited for the IO proc, the
// IO proc waited for the lock, and the engine suite hung forever: no timeout,
// no failing test, no crash report.
//
// What this gate can and cannot do, stated plainly:
//
//   - It CANNOT reproduce the deadlock. That needs a real aggregate device,
//     which needs audio hardware and the Screen Recording permission. Same
//     limit BUG-103 hit with its HAL race.
//   - It CAN pin the property that makes the deadlock impossible: teardown
//     claims the handles under the lock and RETURNS before anything is
//     destroyed, so no blocking CoreAudio call can run with the lock held.
//
// The destroy half is enforced by the compiler rather than here:
// `destroyTapResources` is `nonisolated static` and takes a value type, so it
// cannot reach `stateLock` even by accident. Keep it that way.

import AVFoundation
import Foundation
import Testing

@testable import Audio

@Suite("BUG-139 — tap teardown must not hold the lock across CoreAudio calls")
struct SystemAudioCaptureTeardownTests {

    @Test("claiming returns the handles and clears them in one locked step")
    func claimReturnsAndClears() {
        guard #available(macOS 14.2, *) else { return }
        let capture = SystemAudioCapture()
        capture.seedTapResourcesForTesting(aggregate: 4_242, tap: 77)

        let claimed = capture.claimTapResourcesForTeardown()
        #expect(claimed.aggregate == 4_242)
        #expect(claimed.tap == 77)
        #expect(!claimed.isEmpty)
    }

    @Test("a second claim gets nothing — teardown cannot double-destroy")
    func claimIsIdempotent() {
        guard #available(macOS 14.2, *) else { return }
        let capture = SystemAudioCapture()
        capture.seedTapResourcesForTesting(aggregate: 9, tap: 9)

        _ = capture.claimTapResourcesForTeardown()
        let second = capture.claimTapResourcesForTeardown()

        // A racing stopCapture() and deinit both reach teardown; only one may
        // ever hold a live handle, or the HAL is asked to destroy it twice.
        #expect(second.isEmpty, "a second claim must yield nothing to destroy")
    }

    @Test("the lock is free the moment claiming returns")
    func lockIsNotHeldAfterClaim() throws {
        guard #available(macOS 14.2, *) else { return }
        let capture = SystemAudioCapture()
        capture.seedTapResourcesForTesting(aggregate: 1, tap: 1)

        _ = capture.claimTapResourcesForTeardown()

        // `isCapturing` takes `stateLock`. If claiming ever returned with the
        // lock still held — the shape that deadlocked — this never completes.
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = capture.isCapturing
            done.signal()
        }
        #expect(done.wait(timeout: .now() + 5) == .success,
                "stateLock was still held after claim returned")
    }

    @Test("teardown and lock-taking callers interleave without wedging")
    func concurrentTeardownAndLockTakersComplete() throws {
        guard #available(macOS 14.2, *) else { return }
        let capture = SystemAudioCapture()
        let finished = DispatchSemaphore(value: 0)

        // Stands in for the IO proc's per-buffer `stateLock` traffic. With no
        // real device the handles are zero, so nothing is destroyed; what is
        // under test is that the teardown path never parks holding the lock.
        Thread.detachNewThread {
            for _ in 0..<2_000 { _ = capture.isCapturing }
            finished.signal()
        }
        Thread.detachNewThread {
            for _ in 0..<200 { _ = capture.claimTapResourcesForTeardown() }
            finished.signal()
        }

        #expect(finished.wait(timeout: .now() + 10) == .success)
        #expect(finished.wait(timeout: .now() + 10) == .success)
    }
}
