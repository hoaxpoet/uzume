// PlayedBackWait — BUG-156 (2026-09-29). Waiting for a local-file end-of-track without racing
// the rest of the test process.
//
// With `onFileEnded` set, `LocalFilePlaybackProvider` schedules the file `.dataPlayedBack`
// (LFSEEK.1). AVFAudio delivers that completion from a dispatch timer (`AVAEDispatchQueueTimer`)
// in the process's constrained DEFAULT-QoS pool. Measured in isolation: saturate that pool (or
// higher) and the completion waits exactly as long as the saturation does (8.5 s behind 8 s of
// spinners). Background or utility spinners don't delay it (0.32 s), and `.dataConsumed` is
// unaffected. The parallel engine suite keeps that pool saturated with CPU-bound synchronous tests,
// so a fixed deadline on the callback measured the neighbours, not the provider. That was the
// flake.
//
// So the verdict is an ORDERING. After the budget, queue a canary on the same pool behind the
// overdue completion. Until the canary runs, the pool has not had its turn, and a callback that
// lands in the meantime passes the moment it lands. Once the canary has run, the completion has
// been dequeued. The callback then gets the same budget again, and missing that means lost, not
// late.
//
// While the canary is pending there is no deadline, on purpose. It can only stall while the pool
// is saturated, which ends when the neighbouring tests finish. It does not wait on the provider,
// so it does not mask a provider hang.

import Foundation
import Testing

// MARK: - Played-back wait

/// Waits for `ended` (signalled by `onFileEnded`) and returns whether it fired.
///
/// - Parameters:
///   - budget: how long the callback gets, first from the call and again once `pool` has served
///     work queued behind it. The same 5 s the callers used before BUG-156, not widened.
///   - pool: the queue the completion is delivered through. Injectable only for the gate below.
func awaitPlayedBackEnd(
    _ ended: DispatchSemaphore,
    budget: TimeInterval = 5.0,
    pool: DispatchQueue = .global(qos: .default)
) -> Bool {
    if ended.wait(timeout: .now() + budget) == .success { return true }
    let canary = DispatchSemaphore(value: 0)
    pool.async { canary.signal() }
    // ponytail: 50 ms poll, not a merged wakeup; resolution is all it costs.
    while canary.wait(timeout: .now()) == .timedOut {
        if ended.wait(timeout: .now() + 0.05) == .success { return true }
    }
    return ended.wait(timeout: .now() + budget) == .success
}

// MARK: - Gate

@Suite("BUG-156 played-back wait")
struct PlayedBackWaitTests {

    /// The flake's shape. The pool is starved (a suspended queue: deterministic, no spinning) and
    /// the callback lands after the budget. A bare `wait(budget)` fails this; the ordered wait
    /// must not.
    @Test func lateBehindAStarvedPool_isNotLost() {
        let budget: TimeInterval = 0.2
        let starved = DispatchQueue(label: "io.uzume.test.starved-pool")
        starved.suspend()
        defer { starved.resume() }
        let ended = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: budget * 4)
            ended.signal()
        }
        #expect(awaitPlayedBackEnd(ended, budget: budget, pool: starved))
    }

    /// Lost stays lost: once the pool has had its turn, a callback that never comes fails.
    @Test func neverSignalled_withALivePool_fails() {
        let live = DispatchQueue(label: "io.uzume.test.live-pool")
        #expect(!awaitPlayedBackEnd(DispatchSemaphore(value: 0), budget: 0.1, pool: live))
    }
}
