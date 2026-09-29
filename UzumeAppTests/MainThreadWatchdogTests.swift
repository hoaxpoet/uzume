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
        func add(_ line: String) { lock.withLock { items.append((line, Date())) } }
        var all: [(String, Date)] { lock.withLock { items } }
    }

    /// A synchronous block of the main thread (the suite is `@MainActor`).
    private func hangTheMainThread(for seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }

    @Test func logsStallAndSamplesWhileMainIsBlocked_thenRecovers() async throws {
        let events = Events()
        let watchdog = MainThreadWatchdog(
            stallThreshold: 0.3,
            sampleThreshold: 0.8,
            tick: 0.05,
            log: { events.add($0) },
            sample: { events.add("SAMPLE") }
        )
        watchdog.start()
        defer { watchdog.stop() }
        // Start from a healthy main thread. Under full-suite load other main-actor work can
        // hold main past the stall threshold first — the watchdog then (correctly) reports a
        // REAL stall — so order on the watchdog's own state, not on a fixed warm-up: wait
        // (capped) until it has either said nothing or last said RECOVERED.
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<100 where !(events.all.last.map { $0.0 == "MAIN_THREAD RECOVERED" } ?? true) {
            try await Task.sleep(for: .milliseconds(50))
        }

        let hangStart = Date()
        hangTheMainThread(for: 1.4)                                 // THE HANG: main blocked
        let released = Date()

        let during = events.all.filter { $0.1 >= hangStart && $0.1 < released }.map(\.0)
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
