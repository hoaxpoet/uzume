// MainThreadWatchdogTests — BR.5 / audit D3: the watchdog reports a blocked main thread from
// its own thread, while main is still blocked, and samples once past the sample threshold.

import Foundation
import Testing
@testable import UzumeApp

@Suite("MainThreadWatchdog", .serialized)
@MainActor
struct MainThreadWatchdogTests {

    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(String, Date)] = []
        func add(_ s: String) { lock.withLock { items.append((s, Date())) } }
        var all: [(String, Date)] { lock.withLock { items } }
    }

    /// A synchronous block of the main thread (the suite is `@MainActor`).
    private func hangTheMainThread(for seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    @Test func logsStallAndSamplesWhileMainIsBlocked_thenRecovers() async throws {
        let events = Events()
        let watchdog = MainThreadWatchdog(
            stallThreshold: 0.3, sampleThreshold: 0.8, tick: 0.05,
            log: { events.add($0) }, sample: { events.add("SAMPLE") })
        watchdog.start()
        defer { watchdog.stop() }
        try await Task.sleep(for: .milliseconds(300))              // main free: pings answered
        #expect(events.all.isEmpty, "no stall while main answers")

        hangTheMainThread(for: 1.4)                                 // THE HANG: main blocked
        let released = Date()

        let during = events.all.filter { $0.1 < released }.map(\.0)
        #expect(during.contains { $0.hasPrefix("MAIN_THREAD STALL") }, "STALL logged while main was blocked")
        #expect(during.contains("SAMPLE"), "sampled once past the sample threshold")
        #expect(during.filter { $0 == "SAMPLE" }.count == 1)

        // Main free again: wait on the RECOVERED signal itself (capped), not a fixed delay.
        for _ in 0..<100 where events.all.last?.0 != "MAIN_THREAD RECOVERED" {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(events.all.map(\.0).last == "MAIN_THREAD RECOVERED")
    }
}
