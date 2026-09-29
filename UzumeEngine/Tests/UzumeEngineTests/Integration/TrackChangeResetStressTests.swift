// TrackChangeResetStressTests — BR.3 (audit G1) under ThreadSanitizer.
//
// The shape of a streaming song change with Witchlight active: the render loop (main)
// advances Witchlight's bead path and the analysis queue runs MIR, while the Now Playing
// poller — a detached pool task — fires song changes. Before BR.3 the poller reset both
// inline, racing each owner with no lock on either side (audit G1). Every reset now goes
// through `TrackChangeResetRouter` to its owner, so TSan must report nothing.
//
// Opt-in (UZUME_STRESS=1) like ConcurrencyStressTests; run it via `Scripts/tsan_stress.sh`.
// Negative control (BR.3 closeout): calling `path.reset()` directly from the poller task
// instead of through the router makes TSan report a data race on the path's state.

import Foundation
import Testing
@testable import DSP
@testable import Renderer
@testable import Shared

private var stressEnabled: Bool {
    ProcessInfo.processInfo.environment["UZUME_STRESS"] == "1"
}

/// Hands main-owned / analysis-owned objects to @Sendable closures. Safe only because every
/// access goes through the owning thread — which is exactly what the test checks.
private final class Owned<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func stop() { lock.withLock { stopped = true } }
    var isStopped: Bool { lock.withLock { stopped } }
}

@Suite("Streaming song change with Witchlight active (BR.3, TSan)", .serialized)
struct TrackChangeResetStressTests {

    @Test @MainActor func streamingTrackChange_witchlightActive_raceFree() async throws {
        guard stressEnabled else { return }
        let path = Owned(WitchlightPath())          // render-loop state (main)
        let mir = Owned(MIRPipeline())              // analysis-queue state
        let analysisQueue = DispatchQueue(label: "test.br3.analysis", qos: .userInteractive)
        let drive = FlashHarnessSupport.worstCaseBeatTrain(seconds: 10)
        let magnitudes = (0..<512).map { Float(($0 * 7) % 13) / 13 }
        let stop = StopFlag()

        // The analysis queue's own work, one frame per hop until stopped.
        @Sendable func analyse(_ frame: Int) {
            guard !stop.isStopped else { return }
            _ = mir.value.process(magnitudes: magnitudes, fps: 60, time: Float(frame) / 60, deltaTime: 1.0 / 60)
            analysisQueue.async { analyse(frame + 1) }
        }
        analysisQueue.async { analyse(0) }

        // The Now Playing poller: a detached pool task firing song changes.
        let poller = Task.detached {
            for _ in 0..<80 {
                TrackChangeResetRouter.route(
                    analysisQueue: analysisQueue,
                    analysis: { mir.value.reset() },
                    main: { path.value.reset() }
                )
                try? await Task.sleep(nanoseconds: 3_000_000)
            }
        }

        // The render loop: Witchlight advancing every frame on main, yielding between frames
        // so the routed main-actor resets interleave with it.
        var frame = 0
        while frame < 900 {
            path.value.advance(deltaTime: 1.0 / 60, features: drive[frame % drive.count], stems: .zero)
            frame += 1
            await Task.yield()
        }
        await poller.value
        stop.stop()
        analysisQueue.sync {}
    }
}
