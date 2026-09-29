// ProblemReport — Help › Report a Problem: a consent-first zip plus a pre-filled GitHub
// issue link (BR.5 / audit H3, F16, D3; Matt's decision 5).

import AppKit
import Foundation
import Metal
import os.log

private let reportLogger = Logger(subsystem: "io.uzume.mac", category: "ProblemReport")

// MARK: - ProblemReportBuilder

/// Gathers the evidence a tester can send into one zip. Nothing leaves the Mac: the tester
/// attaches the zip to the issue themselves. No audio is ever included.
enum ProblemReportBuilder {

    /// Where reports (and the watchdog's stall samples) are written. Not Desktop / Downloads:
    /// those are privacy-protected folders and would add a permission prompt (BUG-158 class).
    static var reportsDirectory: URL { MainThreadWatchdog.reportDirectory }

    /// Crash / hang reports macOS keeps for the current user.
    static var diagnosticReportsDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
    }

    /// Write `Uzume-Report-<stamp>.zip` into `outputDirectory` and return its URL.
    ///
    /// - Parameters:
    ///   - logText: recent unified-log entries for the app (`recentUnifiedLog()` live).
    ///   - systemSummary: build, SHA, hardware, OS, GPU (`systemSummary()` live).
    ///   - diagnosticReports: folder scanned for `Uzume*` `.ips` / `.hang` / `.diag` files.
    ///   - watchdogSamples: folder whose `stall-*.txt` samples are included.
    static func build(
        into outputDirectory: URL,
        logText: String,
        systemSummary: String,
        diagnosticReports: URL,
        watchdogSamples: URL,
        now: Date = Date()
    ) throws -> URL {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let name = "Uzume-Report-\(stamp)"
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging.deletingLastPathComponent()) }

        try systemSummary.write(to: staging.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
        try logText.write(to: staging.appendingPathComponent("unified_log.txt"), atomically: true, encoding: .utf8)

        let crashes = staging.appendingPathComponent("DiagnosticReports", isDirectory: true)
        try fm.createDirectory(at: crashes, withIntermediateDirectories: true)
        for file in (try? fm.contentsOfDirectory(at: diagnosticReports, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix("Uzume") && ["ips", "hang", "diag"].contains(file.pathExtension) {
            try? fm.copyItem(at: file, to: crashes.appendingPathComponent(file.lastPathComponent))
        }
        for file in (try? fm.contentsOfDirectory(at: watchdogSamples, includingPropertiesForKeys: nil)) ?? []
        where file.lastPathComponent.hasPrefix("stall-") {
            try? fm.copyItem(at: file, to: staging.appendingPathComponent(file.lastPathComponent))
        }

        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let zip = outputDirectory.appendingPathComponent("\(name).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--keepParent", staging.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return zip
    }

    // MARK: Live inputs

    /// Build, SHA, flavor, Mac model, memory, macOS, GPU, displays.
    static func systemSummary() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let sha = info["UzumeGitSHA"] as? String ?? "?"
        let flavor = BuildFlavor.current == .public ? "public" : "developer"
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let displays = NSScreen.screens.map { screen in
            let px = screen.convertRectToBacking(screen.frame).size
            return "\(Int(px.width))x\(Int(px.height)) @\(screen.backingScaleFactor)x"
        }
        return """
        Uzume \(version) (\(build)) sha=\(sha) flavor=\(flavor)
        Mac: \(sysctlString("hw.model") ?? "?"), \(String(format: "%.0f", memoryGB)) GB
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        GPU: \(MTLCreateSystemDefaultDevice()?.name ?? "?")
        Displays: \(displays.joined(separator: ", "))
        """
    }

    /// The last two hours of the app's own unified-log entries (`log show`; persisted across
    /// launches, so a crash's lead-up is included).
    static func recentUnifiedLog() -> String {
        let log = Process()
        log.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        log.arguments = ["show", "--last", "2h", "--info", "--style", "compact",
                         "--predicate", "subsystem BEGINSWITH \"io.uzume\""]
        let pipe = Pipe()
        log.standardOutput = pipe
        log.standardError = pipe
        do { try log.run() } catch { return "log show failed: \(error)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        log.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? "(log output was not UTF-8)"
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
    }
}

// MARK: - AbnormalExitMarker

/// Set at launch, cleared on a clean quit. Still set at the next launch → the last run
/// crashed, hung and was force-quit, or was killed.
struct AbnormalExitMarker {
    static let key = "uzume.diagnostics.runningMarker"
    let defaults: UserDefaults

    /// Record this launch; returns whether the previous run ended abnormally.
    func markLaunch() -> Bool {
        let previousRunDidNotQuit = defaults.bool(forKey: Self.key)
        defaults.set(true, forKey: Self.key)
        return previousRunDidNotQuit
    }

    /// Record a clean quit.
    func markCleanQuit() {
        defaults.set(false, forKey: Self.key)
    }
}

// MARK: - ProblemReporter

/// The consent → build → reveal → issue-link flow.
@MainActor
enum ProblemReporter {

    /// Why the report is being offered — changes only the consent dialog's headline.
    enum Reason { case userRequested, abnormalExit }

    static let newIssueURL = "https://github.com/hoaxpoet/uzume/issues/new"

    /// Ask first; on consent write the zip, show it in Finder and open a pre-filled issue.
    static func offer(_ reason: Reason) {
        let alert = NSAlert()
        alert.messageText = reason == .abnormalExit
            ? String(localized: "report.consent.title.abnormal_exit")
            : String(localized: "report.consent.title")
        alert.informativeText = String(localized: "report.consent.body")
        alert.addButton(withTitle: String(localized: "report.consent.create"))
        alert.addButton(withTitle: String(localized: "report.consent.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task.detached(priority: .userInitiated) {
            do {
                let zip = try ProblemReportBuilder.build(
                    into: ProblemReportBuilder.reportsDirectory,
                    logText: ProblemReportBuilder.recentUnifiedLog(),
                    systemSummary: ProblemReportBuilder.systemSummary(),
                    diagnosticReports: ProblemReportBuilder.diagnosticReportsDirectory,
                    watchdogSamples: MainThreadWatchdog.reportDirectory)
                await MainActor.run { finish(zip: zip) }
            } catch {
                reportLogger.error("report build failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { showFailure() }
            }
        }
    }

    /// The pre-filled issue: a title, the prompts, and the build line — nothing personal.
    static func issueURL(zipName: String, summaryFirstLine: String) -> URL? {
        var components = URLComponents(string: newIssueURL)
        let body = String(format: String(localized: "report.issue.body"), zipName, summaryFirstLine)
        components?.queryItems = [
            URLQueryItem(name: "title", value: String(localized: "report.issue.title")),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }

    private static func finish(zip: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([zip])
        let firstLine = ProblemReportBuilder.systemSummary().split(separator: "\n").first.map(String.init) ?? ""
        if let url = issueURL(zipName: zip.lastPathComponent, summaryFirstLine: firstLine) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func showFailure() {
        let alert = NSAlert()
        alert.messageText = String(localized: "report.failed.title")
        alert.informativeText = String(localized: "report.failed.body")
        alert.runModal()
    }
}
