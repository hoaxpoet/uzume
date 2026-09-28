// ScanBenchReport — markdown tables for ScanBench results (SCAN.0, D-260).

import Foundation

// MARK: - Report

/// Summary table (per playlist + all) and the row-by-row failure list.
public func scanBenchReport(_ results: [ScanBenchResult]) -> String {
    var lines = [
        "| Playlist | Songs (truth / header) | Name read | Coverage | Identification | Wrong song | "
            + "Truth w/o preview | Truth resolves elsewhere (scan right) | Strict identification | "
            + "Frame ms (median / max) |",
        "|---|---|---|---|---|---|---|---|---|---|"
    ]
    var totals = ScanBenchResult(name: "**All**")
    for result in results {
        let header = result.songCountRead.map(String.init) ?? "—"
        lines.append(summaryRow(result, header: header, name: result.playlistNameRead == nil ? "—" : "✓"))
        totals.add(result)
    }
    lines.append(summaryRow(totals, header: "", name: ""))
    lines += ["", "### Failures, row by row", ""]
    for result in results where !result.failures.isEmpty {
        lines += ["**\(result.name)**", ""]
        lines += ["| # | Ground truth | Scanned | Outcome | Detail |", "|---|---|---|---|---|"]
        lines += result.failures.map {
            "| \($0.number) | \($0.truth) | \($0.scanned) | \($0.verdict) | \($0.detail) |"
        }
        lines.append("")
    }
    return lines.joined(separator: "\n")
}

/// "12.3 %" or "n/a".
public func scanBenchPercent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "n/a" : String(format: "%.1f %%", Double(part) / Double(whole) * 100)
}

private func summaryRow(_ result: ScanBenchResult, header: String, name: String) -> String {
    let sorted = result.frameMillis.sorted()
    let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    return "| \(result.name) | \(result.truthCount) / \(header) | \(name) | "
        + "\(scanBenchPercent(result.found + result.gapReported, result.truthCount)) "
        + "(\(result.found) read, \(result.gapReported) gap, \(result.silentMiss) silent) | "
        + "\(scanBenchPercent(result.identified, result.judged)) (\(result.identified)/\(result.judged)) | "
        + "\(scanBenchPercent(result.wrong, result.judged)) (\(result.wrong)) | \(result.truthNoPreview) | "
        + "\(result.truthElsewhere) (\(result.truthElsewhereScanRight)) | "
        + "\(scanBenchPercent(result.strictIdentified, result.strictJudged)) "
        + "(\(result.strictIdentified)/\(result.strictJudged)) | "
        + String(format: "%.0f / %.0f |", median, sorted.last ?? 0)
}

extension ScanBenchResult {
    /// Fold another playlist's counts into this total.
    mutating func add(_ other: ScanBenchResult) {
        truthCount += other.truthCount
        found += other.found
        gapReported += other.gapReported
        silentMiss += other.silentMiss
        identified += other.identified
        wrong += other.wrong
        unresolved += other.unresolved
        truthNoPreview += other.truthNoPreview
        truthElsewhere += other.truthElsewhere
        truthElsewhereScanRight += other.truthElsewhereScanRight
        strictIdentified += other.strictIdentified
        frameMillis += other.frameMillis
    }
}
