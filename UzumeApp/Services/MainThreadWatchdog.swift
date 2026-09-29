// MainThreadWatchdog — notices a blocked main thread from outside it (BR.5 / audit D3).

import Foundation
import os.log

// MARK: - MainThreadWatchdog

/// Pings the main thread from its own `Thread` and reports when the ping goes unanswered.
///
/// The drawable watchdog (`setupDrawableLifecycleWatchdog`) sees only a stuck drawable
/// request and runs only in developer builds (it writes to the session recorder). A tester's
/// freeze needs something that works in the public build and does not depend on the thread
/// it watches: a dedicated `Thread` (not the Swift cooperative pool, which a hang can starve,
/// and never the main actor).
///
/// - `stallThreshold` without an answer → one `MAIN_THREAD STALL` fault in the unified log
///   (Help › Report a Problem collects it).
/// - `sampleThreshold` → one `sample` of the process into `reportDirectory`, for the report.
/// - The answer arriving → one `MAIN_THREAD RECOVERED` line with the stall's length.
final class MainThreadWatchdog: @unchecked Sendable {

    // MARK: - Configuration

    private let stallThreshold: TimeInterval
    private let sampleThreshold: TimeInterval
    private let tick: TimeInterval
    private let log: @Sendable (String) -> Void
    private let sample: @Sendable () -> Void

    // MARK: - State (lock-guarded)

    private let lock = NSLock()
    private var lastAnswer = Date()
    private var pingInFlight = false
    private var running = false

    // MARK: - Init

    init(
        stallThreshold: TimeInterval = 1.0,
        sampleThreshold: TimeInterval = 3.0,
        tick: TimeInterval = 0.25,
        log: @escaping @Sendable (String) -> Void = MainThreadWatchdog.logToUnifiedLog,
        sample: @escaping @Sendable () -> Void = { MainThreadWatchdog.sampleSelf() }
    ) {
        self.stallThreshold = stallThreshold
        self.sampleThreshold = sampleThreshold
        self.tick = tick
        self.log = log
        self.sample = sample
    }

    // MARK: - Lifecycle

    /// Start watching. Idempotent.
    func start() {
        let alreadyRunning = lock.withLock { () -> Bool in
            let was = running
            running = true
            lastAnswer = Date()
            return was
        }
        guard !alreadyRunning else { return }
        let thread = Thread { [weak self] in self?.loop() }
        thread.name = "io.uzume.mainThreadWatchdog"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Stop watching (the loop exits at its next tick).
    func stop() {
        lock.withLock { running = false }
    }

    // MARK: - Loop

    private func loop() {
        var stallLogged = false
        var sampled = false
        while lock.withLock({ running }) {
            Thread.sleep(forTimeInterval: tick)
            let sendPing = lock.withLock { () -> Bool in
                if pingInFlight { return false }
                pingInFlight = true
                return true
            }
            if sendPing {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.lock.withLock {
                        self.lastAnswer = Date()
                        self.pingInFlight = false
                    }
                }
            }
            let age = Date().timeIntervalSince(lock.withLock { lastAnswer })
            if age >= stallThreshold, !stallLogged {
                stallLogged = true
                log("MAIN_THREAD STALL age_ms=\(Int(age * 1000))")
            }
            if age >= sampleThreshold, !sampled {
                sampled = true
                sample()
            }
            if age < stallThreshold, stallLogged {
                log("MAIN_THREAD RECOVERED")
                stallLogged = false
                sampled = false
            }
        }
    }

    // MARK: - Defaults

    /// Where stall samples go; `ProblemReportBuilder` includes the folder.
    static var reportDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Uzume", isDirectory: true)
    }

    private static let logger = Logger(subsystem: "io.uzume.mac", category: "Watchdog")

    @Sendable static func logToUnifiedLog(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }

    /// `/usr/bin/sample <own pid> 2` into `reportDirectory` (the app is not sandboxed).
    static func sampleSelf() {
        let dir = reportDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [
            String(ProcessInfo.processInfo.processIdentifier), "2",
            "-file", dir.appendingPathComponent("stall-\(stamp).txt").path
        ]
        try? process.run()
    }
}
