// TapLifecycleTests — BR.12 (audit G2/B14, G8, B6, G6): the system-audio tap's lifecycle runs on
// one serial queue with a generation token; a failed reinstall keeps the intent (the next device
// change retries); Ready holds the cold-install ladder; unusable tap rates are rejected.
//
// Tap creation needs hardware and Screen Recording, so these drive the lifecycle rules through
// internal hooks; a real create in this process may fail or succeed — both are handled.

import Foundation
import Testing
@testable import Audio
@testable import Shared

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ line: String) { lock.withLock { items.append(line) } }
    var all: [String] { lock.withLock { items } }
}

@Suite("System-audio tap lifecycle (BR.12)", .serialized)
struct TapLifecycleTests {

    @Test func aReinstallOvertakenByAStop_isSkipped() {
        let capture = SystemAudioCapture()
        let lines = Lines()
        capture.onCaptureDiagnostic = { lines.add($0) }
        capture.seedCaptureIntentForTesting(.systemAudio)
        let queuedAt = capture.lifecycleGenerationForTesting

        capture.stopCapture()   // End Session lands between the device change and its reinstall
        capture.performReinstallForTesting(generation: queuedAt)

        #expect(lines.all.contains { $0.contains("performReinstall: SKIPPED") })
        #expect(!lines.all.contains { $0.contains("performReinstall: ENTER") }, "no orphan tap is created")
        #expect(!capture.hasCaptureIntentForTesting)
    }

    @Test func aFailedReinstall_keepsTheIntent_soTheNextDeviceChangeRetries() {
        let capture = SystemAudioCapture()
        let lines = Lines()
        capture.onCaptureDiagnostic = { lines.add($0) }
        capture.seedCaptureIntentForTesting(.systemAudio)

        capture.performReinstallForTesting(generation: capture.lifecycleGenerationForTesting)

        if lines.all.contains(where: { $0.contains("reinstall via device-change FAILED") }) {
            #expect(capture.hasCaptureIntentForTesting, "G8: the intent survives a failed reinstall")
            #expect(!capture.isCapturing)
        } else {
            #expect(capture.isCapturing, "this process could create a real tap; it's running")
        }
        capture.stopCapture()
        capture.drainLifecycleQueueForTesting()
        #expect(!capture.isCapturing)
        #expect(!capture.hasCaptureIntentForTesting)
    }

    @Test func unusableTapRates_areRejected() {
        #expect(SystemAudioCapture.isUsableSampleRate(48_000))
        #expect(!SystemAudioCapture.isUsableSampleRate(0))
        #expect(!SystemAudioCapture.isUsableSampleRate(-1))
        #expect(!SystemAudioCapture.isUsableSampleRate(.nan))
        #expect(!SystemAudioCapture.isUsableSampleRate(.infinity))
    }

    @Test func readyHoldsTheColdInstallLadder_untilPlayback() {
        let router = AudioInputRouter(capture: MockAudioCapture(), metadata: nil)
        router.lock.withLock { router.currentMode = .systemAudio }
        defer { router.cancelPendingReinstall() }

        router.holdColdInstallLadder()
        router.scheduleNextReinstall()
        #expect(router.lock.withLock { router.reinstallWorkItem } == nil, "no reinstall of a working tap at Ready")
        #expect(router.reinstallAttempts == 0)

        router.releaseColdInstallLadder()
        router.scheduleNextReinstall()
        #expect(router.lock.withLock { router.reinstallWorkItem } != nil, "the ladder runs once playback began")
    }
}

// MARK: - TSan stress (UZUME_STRESS=1, Scripts/tsan_stress.sh)

@Suite("Tap lifecycle under TSan (BR.12)", .serialized)
struct TapLifecycleStressTests {

    /// End Session during a device-change reinstall, many times over, from three threads — the
    /// shape of audit G2 (a). Under TSan: no data race. A real create may fail here (no Screen
    /// Recording for the test process) or succeed; the lifecycle state is exercised either way.
    @Test func tapLifecycle_endDuringReinstall_raceFree() async {
        guard ProcessInfo.processInfo.environment["UZUME_STRESS"] == "1" else { return }
        let capture = SystemAudioCapture()
        capture.onCaptureDiagnostic = { _ in }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {   // main-ish: start / stop sessions
                for _ in 0..<25 {
                    try? capture.startCapture(mode: .systemAudio)
                    capture.stopCapture()
                }
            }
            group.addTask {   // the device monitor firing
                for _ in 0..<50 { capture.simulateDeviceChangeForTesting() }
            }
            group.addTask {   // the router's silence ladder: stop + start
                for _ in 0..<25 {
                    capture.stopCapture()
                    try? capture.startCapture(mode: .systemAudio)
                }
            }
        }
        capture.stopCapture()
        capture.drainLifecycleQueueForTesting()
        #expect(!capture.isCapturing)
    }
}

// MARK: - BR.17 (I4 / B7): the beat-phase offset follows the output device

@Suite("Output latency (BR.17)")
struct OutputLatencyTests {

    @Test func builtInAndWired_keepTheTunedBaseline_bluetoothRaisesIt() {
        #expect(OutputLatency.compensationMs(deviceMs: 12, enabled: true) == 50, "fast device: calibrated 50 ms")
        #expect(OutputLatency.compensationMs(deviceMs: 180, enabled: true) == 180, "Bluetooth: its own latency")
        #expect(OutputLatency.compensationMs(deviceMs: nil, enabled: true) == 50, "unreadable: baseline")
        #expect(OutputLatency.compensationMs(deviceMs: 180, enabled: false) == 50, "UZUME_DEVICE_LATENCY=0 arm")
    }

    @Test func framesToMilliseconds() {
        // 8820 frames at 44.1 kHz = 200 ms (a typical AirPods report).
        #expect(OutputLatency.milliseconds(deviceFrames: 8_000, safetyFrames: 500, streamFrames: 320,
                                           sampleRate: 44_100) == 200)
        #expect(OutputLatency.milliseconds(deviceFrames: 1, safetyFrames: 0, streamFrames: 0, sampleRate: 0) == nil)
    }

    /// Reads this Mac's real default output device — a readable, sane number (or none at all on
    /// a headless runner). Recorded, not pinned: the device differs per machine.
    @Test func theCurrentDeviceReadsSanely() {
        let device = DefaultOutputDeviceMonitor().currentDefaultOutputDeviceID()
        guard device != 0, let ms = OutputLatency.milliseconds(of: device) else { return }
        #expect(ms >= 0 && ms < 1_000, "\(ms) ms")
    }
}
