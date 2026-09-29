// TrackChangeResetRouterTests — BR.3 (audit G1): a streaming song change's resets run on
// their owners' threads (main for preset / geometry / identity, the analysis queue for MIR
// and mood), whichever thread the Now Playing poller calls from.

import Foundation
import Testing
@testable import Shared

/// Synchronous, so callable from the detached (async) poller task.
private func onMainThread() -> Bool { Thread.isMainThread }

@Suite("Track-change resets run on their owners' threads (BR.3)")
struct TrackChangeResetRouterTests {

    private final class Probe: @unchecked Sendable {
        private let lock = NSLock()
        private var mainRanOnMain: Bool?
        private var analysisRanOnQueue: Bool?
        func setMain(_ onMain: Bool) { lock.withLock { mainRanOnMain = onMain } }
        func setAnalysis(_ onQueue: Bool) { lock.withLock { analysisRanOnQueue = onQueue } }
        var result: (Bool?, Bool?) { lock.withLock { (mainRanOnMain, analysisRanOnQueue) } }
    }

    @Test func fromAPoolThread_mainResetsRunOnMain_analysisResetsOnTheAnalysisQueue() async {
        let key = DispatchSpecificKey<Bool>()
        let analysisQueue = DispatchQueue(label: "test.br3.analysis")
        analysisQueue.setSpecific(key: key, value: true)
        let probe = Probe()

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let pending = Pending(count: 2) { done.resume() }
            // The poller's shape: a detached pool task, never main, never the analysis queue.
            Task.detached {
                #expect(!onMainThread())
                TrackChangeResetRouter.route(
                    analysisQueue: analysisQueue,
                    analysis: {
                        probe.setAnalysis(DispatchQueue.getSpecific(key: key) == true && !Thread.isMainThread)
                        pending.arrive()
                    },
                    main: {
                        probe.setMain(Thread.isMainThread)
                        pending.arrive()
                    }
                )
            }
        }
        let (onMain, onQueue) = probe.result
        #expect(onMain == true, "preset / geometry / identity resets must run on main")
        #expect(onQueue == true, "MIR / mood resets must run on the analysis queue")
    }

    /// Counts down arrivals from any thread; fires `whenDone` once.
    private final class Pending: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private let whenDone: @Sendable () -> Void
        init(count: Int, whenDone: @escaping @Sendable () -> Void) { remaining = count; self.whenDone = whenDone }
        func arrive() {
            let fire = lock.withLock { remaining -= 1; return remaining == 0 }
            if fire { whenDone() }
        }
    }
}
