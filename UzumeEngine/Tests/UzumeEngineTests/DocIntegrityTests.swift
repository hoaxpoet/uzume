// DocIntegrityTests — the doc-set's referential-integrity gate (DOC.4.1, 2026-06-11).
//
// Born from two silent corruptions found by the DOC.4 pruning sweep:
//   • The parallel FBS.S5c commit (`5ac5ad90`) accidentally DELETED the whole D-155 entry
//     from DECISIONS.md while editing the adjacent D-154 amendment — undetected for a day,
//     found only by a manual grep sweep.
//   • D-145 was number-reserved at the Nimbus renumbering and cited across docs/code/tests,
//     but the entry was never actually written.
// Parallel sessions edit the shared inventory docs (DECISIONS, KNOWN_ISSUES, CLAUDE.md)
// concurrently; nothing structural caught either failure. This suite makes the invariants
// executable so the regression gate (run on every increment) catches the class.
//
// Invariants:
//   1. D-number CONTINUITY — every D-001…D-max has a `## D-NNN` header in DECISIONS.md or
//      DECISIONS_HISTORY.md (catches whole-entry deletion even when nothing cites it, and
//      reserved-but-never-filed numbers).
//   2. D-header UNIQUENESS — at most one non-Amendment header per number across both files
//      (catches the D-086 class: a half-landed move leaving the entry in both files).
//      Explicit `— Amendment` headers (the D-082 convention) are allowed.
//   3. D-citation RESOLUTION — every `D-NNN` token cited in CLAUDE.md, engine/app source,
//      or the active docs tree resolves to a header in one of the two files.
//   4. BUG continuity + uniqueness in KNOWN_ISSUES.md (top-level `### BUG-NNN` entries;
//      dotted sub-entries like BUG-007.4 are the BUG-007 convention and don't count).
//   5. Failed-Approach RESOLUTION — every `Failed Approach #N` / `FA #N` citation resolves
//      to an active CLAUDE.md entry or a gap-table row (the DOC.3 relocation convention).
//
// House rule this suite enforces, stated once: doc entries are MOVED, never deleted; a
// number once assigned must forever resolve somewhere greppable.

import Foundation
import Testing

@Suite("Doc referential integrity (DOC.4.1)")
struct DocIntegrityTests {

    // MARK: - Repo file access

    /// Repo root derived from this file's path (…/UzumeEngine/Tests/UzumeEngineTests/…).
    private static let repoRoot: URL = {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url.deleteLastPathComponent() }   // file → Tests dir ×2 → UzumeEngine → root
        return url
    }()

    private static func read(_ relative: String) -> String? {
        try? String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// Skip everything cleanly when the repo docs aren't present (e.g. a bundled test
    /// product run outside the checkout) — same print-skip pattern as the session-artifact
    /// gates. A MISSING doc in a real checkout is itself a failure, so distinguish: the
    /// docs directory must exist for the gate to arm.
    private static var docsPresent: Bool {
        FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("docs/DECISIONS.md").path)
            && FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("CLAUDE.md").path)
    }

    private static func matches(_ pattern: String, _ text: String, options: NSRegularExpression.Options = [.anchorsMatchLines]) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.numberOfRanges > 1 ? $0.range(at: 1) : $0.range)
        }
    }

    /// Every file whose citations must resolve: CLAUDE.md + Swift/Metal/JSON sources + the
    /// docs tree (all of it — history files keep entries forever, so even changelog and
    /// archive citations must resolve SOMEWHERE; that is the invariant).
    private static func citationCorpus() -> String {
        var parts: [String] = []
        if let c = read("CLAUDE.md") { parts.append(c) }
        let fm = FileManager.default
        for top in ["UzumeEngine/Sources", "UzumeApp", "UzumeEngine/Tests", "docs"] {
            let base = repoRoot.appendingPathComponent(top)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                let ext = url.pathExtension
                guard ["swift", "metal", "md", "json"].contains(ext) else { continue }
                if let t = try? String(contentsOf: url, encoding: .utf8) { parts.append(t) }
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - Gates

    @Test("D-numbers: continuous, unique, and every citation resolves (DECISIONS + HISTORY)")
    func decisionsIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let dec = Self.read("docs/DECISIONS.md") ?? ""
        let hist = Self.read("docs/DECISIONS_HISTORY.md") ?? ""
        #expect(!dec.isEmpty && !hist.isEmpty, "DECISIONS.md / DECISIONS_HISTORY.md unreadable")

        // Header inventory (numeric decisions). Amendment headers (D-082 convention) are
        // separate lines re-using the number with an explicit "Amendment" marker.
        let headerLines = Self.matches(#"^## (D-\d{3}[^\n]*)"#, dec + "\n" + hist)
        var primary: [Int: Int] = [:]
        for line in headerLines {
            let num = Int(line.dropFirst(2).prefix(3)) ?? -1
            if line.contains("Amendment") { continue }
            primary[num, default: 0] += 1
        }
        let maxN = primary.keys.max() ?? 0
        #expect(maxN >= 160, "Decision inventory imploded (max D-\(maxN)) — wholesale loss?")

        // 1. CONTINUITY — a vanished entry shows up as a hole.
        let holes = (1...maxN).filter { primary[$0] == nil }
        #expect(holes.isEmpty, "D-number hole(s) \(holes.map { "D-\(String(format: "%03d", $0))" }): an entry was deleted or a reserved number was never filed. Entries are MOVED to DECISIONS_HISTORY.md, never deleted (the D-155/D-145 classes — see this suite's header).")

        // 2. UNIQUENESS — the D-086 both-files class.
        let dupes = primary.filter { $0.value > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "Duplicate non-Amendment header(s) for \(dupes.map { "D-\(String(format: "%03d", $0))" }) across DECISIONS.md + DECISIONS_HISTORY.md — a move must DELETE the source copy.")

        // 3. RESOLUTION — every cited token has a header somewhere.
        let defined = Set(headerLines.compactMap { Int($0.dropFirst(2).prefix(3)) })
        let cited = Set(Self.matches(#"D-(\d{3})(?![\d.\w])"#, Self.citationCorpus(), options: []).compactMap(Int.init))
        let unresolved = cited.subtracting(defined).sorted()
        #expect(unresolved.isEmpty, "Cited but undefined decision(s): \(unresolved.map { "D-\(String(format: "%03d", $0))" }) — either the entry was deleted (restore it) or the number was used without filing (file it).")
    }

    @Test("BUG-numbers: continuous + unique across KNOWN_ISSUES.md + KNOWN_ISSUES_HISTORY.md (top-level entries)")
    func knownIssuesIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        #expect(!ki.isEmpty, "KNOWN_ISSUES.md unreadable")
        // Resolved entries older than 14 days rotate to KNOWN_ISSUES_HISTORY.md
        // (Scripts/rotate_docs.sh, DOC.6) — continuity spans both files,
        // mirroring the DECISIONS + DECISIONS_HISTORY convention above.
        let hist = Self.read("docs/QUALITY/KNOWN_ISSUES_HISTORY.md") ?? ""
        // Top-level entries only — `### BUG-007.4` sub-entries are the BUG-007 convention.
        let nums = Self.matches(#"^### BUG-(\d+)(?![.\d])"#, ki + "\n" + hist).compactMap(Int.init)
        var counts: [Int: Int] = [:]
        for n in nums { counts[n, default: 0] += 1 }
        let maxN = counts.keys.max() ?? 0
        #expect(maxN >= 46, "BUG inventory imploded (max BUG-\(maxN))")
        // BUG-10 was never filed (pre-existing, verified at DOC.4.1 against full git history).
        let allowedHoles: Set<Int> = [10]
        let holes = (1...maxN).filter { counts[$0] == nil && !allowedHoles.contains($0) }
        #expect(holes.isEmpty, "BUG-number hole(s) \(holes.map { "BUG-\(String(format: "%03d", $0))" }): an entry was deleted. Resolved entries move to §Resolved, then to KNOWN_ISSUES_HISTORY.md via Scripts/rotate_docs.sh — never out of both files.")
        let dupes = counts.filter { $0.value > 1 }.keys.sorted()
        #expect(dupes.isEmpty, "Duplicate top-level BUG entr\(dupes.count == 1 ? "y" : "ies"): \(dupes.map { "BUG-\(String(format: "%03d", $0))" }) — parallel-session number collision landed twice, or a rotation left the entry in both KNOWN_ISSUES.md and KNOWN_ISSUES_HISTORY.md (a move must DELETE the source copy).")
    }

    @Test("CLAUDE.md stays within the always-loaded token budget (D-161: ≤ 7,000 est. tokens)")
    func claudeMdTokenBudget() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let claude = Self.read("CLAUDE.md") ?? ""
        #expect(!claude.isEmpty, "CLAUDE.md unreadable")
        let words = claude.split(whereSeparator: { $0.isWhitespace }).count
        let estTokens = Int(Double(words) * 1.35)
        #expect(estTokens <= 7000, "CLAUDE.md ≈ \(estTokens) est. tokens (\(words) words) — over the 7,000-token cap (D-161). One-in-one-out: demote or retire equal mass in the same commit (handbooks, PRESET_SESSION_CHECKLIST.md, HISTORICAL_DEAD_ENDS.md, DECISIONS_HISTORY.md).")
    }

    @Test("Failed-Approach citations resolve to an active CLAUDE.md entry or the gap table")
    func failedApproachIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let claude = Self.read("CLAUDE.md") ?? ""
        let active = Set(Self.matches(#"^(\d+)\. \*\*"#, claude).compactMap(Int.init))
        // Gap-table rows: `| #14, #20 | destination |`
        var gapped = Set<Int>()
        for row in Self.matches(#"^\| (#[^|]+) \|"#, claude) {
            gapped.formUnion(Self.matches(#"#(\d+)"#, row, options: []).compactMap(Int.init))
        }
        // At DOC.9 the last six always-loaded FAs (#27/#31/#67 → preset-session,
        // #64/#65/#73 → shader-authoring) moved to .claude/skills, so `active` (numbered-bold
        // entries in CLAUDE.md) may now be EMPTY — the full text is gated in the skill bodies
        // by skillIntegrity(). The invariant here is resolution, not a live-entry floor: the
        // gap table must be non-empty and the six relocated numbers must resolve via it.
        let relocated: Set<Int> = [27, 31, 64, 65, 67, 73]
        let resolvableHere = active.union(gapped)
        #expect(!gapped.isEmpty, "Failed-Approach gap table imploded (\(gapped.count) gapped) — wholesale loss?")
        let lostRelocated = relocated.subtracting(resolvableHere).sorted()
        #expect(lostRelocated.isEmpty, "Relocated FA(s) #\(lostRelocated) resolve to neither an active CLAUDE.md entry nor a gap-table row — they live in .claude/skills as of DOC.9 and must keep a gap-table row.")
        let cited = Set(Self.matches(#"(?:Failed Approach|FA) #(\d+)"#, Self.citationCorpus(), options: []).compactMap(Int.init))
        let unresolved = cited.subtracting(resolvableHere).sorted()
        #expect(unresolved.isEmpty, "Failed Approach citation(s) #\(unresolved) resolve to neither an active CLAUDE.md entry nor a gap-table row — extend the gap table when relocating entries (the DOC.3/DOC.4 convention).")
    }

    // MARK: - DOC.6 rotation / budget / index gates
    //
    // The pruning-pass prose convention failed twice (measured 2026-06-12: EP narratives
    // four weeks past the RB.3 window; KNOWN_ISSUES 71 % resolved-history; release notes
    // unrotated at 696 KB). Per the D-161 ratchet rule 3 it converts to mechanism:
    // Scripts/rotate_docs.sh performs the moves; these gates make skipping it red.

    /// Cutoff date (`YYYY-MM-DD`) for the rotation gate — entries dated strictly
    /// BEFORE this string belong in the history files. Computed as today − 14 days
    /// **in UTC** and compared as a STRING, byte-for-byte matching
    /// `Scripts/rotate_docs.sh` (`date -u -v-14d +%Y-%m-%d` then awk string `<`).
    /// Comparing dates-as-strings (not `Date` objects) is what keeps the gate and
    /// the tool agreeing on the exact boundary day: a datetime cutoff flagged
    /// day-14 entries that the date-only script refused to move (the CLEAN.2.3.5
    /// closeout red-gate class).
    ///
    /// **UTC, not local (fixed DOC.7).** The gate and the script were matched to each
    /// other on the local clock, which is exact on one machine and wrong across two.
    /// CI runs in UTC; a dev machine usually does not, so for the hours between the
    /// two midnights the same tree is green locally and red in CI. That is not a
    /// hypothetical: on 2026-08-09 this gate passed at 18:25 EST and `fast-gate`
    /// failed at 01:31 UTC on `VL.CERT (2026-07-26)` — 14 days old locally, 15 in
    /// UTC — and `rotate_docs.sh` could not clear it, because it read the same local
    /// clock and correctly reported nothing to move. The month-rotation check further
    /// down this file was already on UTC, so local here was also internally
    /// inconsistent.
    static func rotationCutoffString(asOf now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let cutoff = calendar.date(byAdding: .day, value: -14, to: now)
            ?? now.addingTimeInterval(-14 * 86_400)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return df.string(from: cutoff)
    }

    private static var rotationCutoffString: String { rotationCutoffString(asOf: Date()) }

    /// The LAST `YYYY-MM-DD` string in a header line (ranges use the end date) —
    /// the same rule `Scripts/rotate_docs.sh` applies. Returned as a string so the
    /// comparison against `rotationCutoffString` is chronological-via-lexicographic.
    private static func lastISODateString(in line: String) -> String? {
        matches(#"\d{4}-\d{2}-\d{2}"#, line, options: []).last
    }

    /// True when an EP §Recently Completed entry should already be header-only in
    /// the plan (its body rotated to history). Selection mirrors `rotate_docs.sh`
    /// exactly — ✅/⏳-marked, dated strictly before `cutoff`, still carrying a body —
    /// so the gate flags only entries the tool will actually move. Extracted from the
    /// gate loop so the boundary/marker logic is unit-testable (it was a red-gate
    /// source: CLEAN.2.3.5 closeout).
    static func epEntryNeedsRotation(header: String, bodyLines: Int, cutoff: String) -> Bool {
        guard header.contains("✅") || header.contains("⏳") else { return false }
        guard let dated = lastISODateString(in: header), dated < cutoff else { return false }
        return bodyLines > 0   // mirrors rotate_docs.sh (`bodylines > 0`); >3 under-reported 1–3-line bodies the script rotates
    }

    /// Lines of the section starting at the exact `header` line, up to (exclusive) the
    /// next top-level `## ` line. Nil when the header is absent.
    private static func sectionLines(of text: String, header: String) -> [String]? {
        var inSection = false
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line == header { inSection = true; continue }
            if inSection && line.hasPrefix("## ") { break }
            if inSection { out.append(line) }
        }
        return inSection ? out : nil
    }

    @Test("EP §Recently Completed: entries older than 14 days are header-only (DOC.6 rotation gate)")
    func engineeringPlanRotationGate() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ep = Self.read("docs/ENGINEERING_PLAN.md") ?? ""
        let section = try #require(Self.sectionLines(of: ep, header: "## Recently Completed"),
                                    "ENGINEERING_PLAN.md has no §Recently Completed")
        var violations: [String] = []
        var header: String?
        var bodyLines = 0
        let cutoff = Self.rotationCutoffString
        func closeEntry() {
            if let h = header, Self.epEntryNeedsRotation(header: h, bodyLines: bodyLines, cutoff: cutoff) {
                violations.append(h)
            }
            header = nil; bodyLines = 0
        }
        for line in section {
            if line.hasPrefix("### ") { closeEntry(); header = line }
            else if header != nil && !line.trimmingCharacters(in: .whitespaces).isEmpty { bodyLines += 1 }
        }
        closeEntry()
        #expect(violations.isEmpty, "EP §Recently Completed ✅/⏳ entr\(violations.count == 1 ? "y" : "ies") older than 14 days still carr\(violations.count == 1 ? "ies" : "y") a body: \(violations) — run Scripts/rotate_docs.sh (bodies move to ENGINEERING_PLAN_HISTORY.md; headers stay).")
    }

    @Test("Rotation cutoff is UTC, so CI and a dev machine never disagree (DOC.7)")
    func rotationCutoffIsUTC() {
        // The exact instant fast-gate failed on PR #73: 2026-08-10T01:31Z. In UTC that
        // is 2026-08-10, so the cutoff is 2026-07-27. West of Greenwich the local date
        // is still 2026-08-09, which yields 2026-07-26 — and `VL.CERT (2026-07-26)` is
        // then NOT flagged, because the comparison is strict `<`. That one-day gap is
        // the whole bug: green here, red in CI, on a byte-identical tree.
        let instant = Date(timeIntervalSince1970: 1_786_325_460)   // 2026-08-10T01:31:00Z
        #expect(
            Self.rotationCutoffString(asOf: instant) == "2026-07-27",
            "cutoff must be derived in UTC regardless of the machine's time zone (TZ here: \(TimeZone.current.identifier))"
        )
        // And the entry that actually broke CI is flagged at that cutoff.
        #expect(Self.epEntryNeedsRotation(
            header: "### Increment VL.CERT — Volumetric Lithograph certified ✅ (2026-07-26)",
            bodyLines: 10,
            cutoff: Self.rotationCutoffString(asOf: instant)
        ))
        // Midnight UTC exactly — the boundary the two clocks straddle.
        #expect(Self.rotationCutoffString(asOf: Date(timeIntervalSince1970: 1_786_320_000)) == "2026-07-27")
        // One second earlier is the previous UTC day, and one day earlier a cutoff.
        #expect(Self.rotationCutoffString(asOf: Date(timeIntervalSince1970: 1_786_319_999)) == "2026-07-26")
    }

    @Test("EP rotation predicate matches rotate_docs selection — boundary + ✅/⏳ marker (DOC.6)")
    func engineeringPlanRotationPredicate() {
        // Deterministic (fixed cutoff, no wall-clock). Guards the gate against
        // silently going green and re-pins the two CLEAN.2.3.5 boundary bugs.
        let cutoff = "2026-06-01"
        // old + ✅ + body → must rotate (flagged)
        #expect(Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-05-01)", bodyLines: 10, cutoff: cutoff))
        // ⏳ marker also counts
        #expect(Self.epEntryNeedsRotation(header: "### Bar ⏳ (2026-05-01)", bodyLines: 10, cutoff: cutoff))
        // BOUNDARY: dated exactly == cutoff → NOT flagged (string `<` is false), matching
        // the date-only script — this is the day-14 false-positive the old datetime cutoff hit.
        #expect(!Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-06-01)", bodyLines: 10, cutoff: cutoff))
        // recent → not flagged
        #expect(!Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-06-10)", bodyLines: 10, cutoff: cutoff))
        // old but UNMARKED → not flagged (rotate_docs leaves it for manual triage)
        #expect(!Self.epEntryNeedsRotation(header: "### Foo (2026-05-01)", bodyLines: 10, cutoff: cutoff))
        // old + ✅ but already header-only (no body) → not flagged
        #expect(!Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-05-01)", bodyLines: 0, cutoff: cutoff))
        // old + ✅ + a SINGLE body line → flagged (mirrors rotate_docs `bodylines > 0`; the >3 under-report bug)
        #expect(Self.epEntryNeedsRotation(header: "### Foo ✅ (2026-05-01)", bodyLines: 1, cutoff: cutoff))
    }

    @Test("KNOWN_ISSUES §Resolved (recent) stays within its 50 KB budget (DOC.6)")
    func knownIssuesResolvedBudget() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        let section = try #require(Self.sectionLines(of: ki, header: "## Resolved (recent)"),
                                    "KNOWN_ISSUES.md has no §Resolved (recent)")
        let bytes = section.joined(separator: "\n").utf8.count
        #expect(bytes <= 50 * 1024, "KNOWN_ISSUES §Resolved (recent) is \(bytes / 1024) KB (budget 50 KB) — run Scripts/rotate_docs.sh (resolved entries older than 14 days move to KNOWN_ISSUES_HISTORY.md).")
    }

    @Test("RELEASE_NOTES_DEV: pre-current-month content stays within its 50 KB budget (DOC.6)")
    func releaseNotesRotationBudget() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let rn = Self.read("docs/RELEASE_NOTES_DEV.md") ?? ""
        #expect(!rn.isEmpty, "RELEASE_NOTES_DEV.md unreadable")
        // The budget is on ROTATION DEBT (entries from months before the current one),
        // not the whole file: the current month legitimately lives in the active file
        // and alone measured 72 KB on 2026-06-12 — a raw whole-file cap cannot coexist
        // with the monthly rotation. 50 KB of stale-month content ≈ a rotation skipped
        // for a couple of weeks past a month boundary.
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(identifier: "UTC")
        let currentMonth = df.string(from: Date())
        var staleBytes = 0
        var inStale = false
        for line in rn.components(separatedBy: "\n") {
            if line.hasPrefix("## [dev-") {
                let month = String(line.dropFirst("## [dev-".count).prefix(7))
                inStale = month < currentMonth
            }
            if inStale { staleBytes += line.utf8.count + 1 }
        }
        #expect(staleBytes <= 50 * 1024, "RELEASE_NOTES_DEV.md carries \(staleBytes / 1024) KB of entries from before \(currentMonth) (budget 50 KB) — run Scripts/rotate_docs.sh (whole months move to RELEASE_NOTES_DEV_YYYY-MM.md files).")
    }

    @Test("DECISIONS §Index is complete: every ## D- header has a row and vice versa (DOC.6)")
    func decisionsIndexCompleteness() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let dec = Self.read("docs/DECISIONS.md") ?? ""
        #expect(!dec.isEmpty, "DECISIONS.md unreadable")
        let headers = Set(Self.matches(#"^## (D-[A-Za-z0-9-]+)"#, dec))
        let rows = Set(Self.matches(#"^\| (D-[A-Za-z0-9-]+) \|"#, dec)).subtracting(["D-###"])
        #expect(!headers.isEmpty && !rows.isEmpty, "DECISIONS.md header/index inventory empty — §Index missing?")
        let missingRows = headers.subtracting(rows).sorted()
        let staleRows = rows.subtracting(headers).sorted()
        #expect(missingRows.isEmpty, "DECISIONS entr\(missingRows.count == 1 ? "y" : "ies") \(missingRows) ha\(missingRows.count == 1 ? "s" : "ve") no §Index row — update the index table.")
        #expect(staleRows.isEmpty, "DECISIONS §Index row(s) \(staleRows) have no matching entry — update the index table (rotated entries lose their row; the entry itself lives in DECISIONS_HISTORY.md).")
    }

    @Test("KNOWN_ISSUES §Open Index is complete: every open entry has a row and vice versa (DOC.6)")
    func knownIssuesOpenIndexCompleteness() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let ki = Self.read("docs/QUALITY/KNOWN_ISSUES.md") ?? ""
        let openSection = try #require(Self.sectionLines(of: ki, header: "## Open"),
                                        "KNOWN_ISSUES.md has no §Open")
        // Top-level open entries carry an ALL-CAPS ID prefix (BUG-NNN, AUDIT-…);
        // narrative sub-headers (### Expected behavior, …) do not match.
        let openText = openSection.joined(separator: "\n")
        let entries = Set(Self.matches(#"^### ([A-Z]{2,}-[^\s]+)"#, openText))
        let rows = Set(Self.matches(#"^\| ([A-Z]{2,}-[^\s]+) \|"#, ki)).subtracting(["ID"])
        #expect(!entries.isEmpty && !rows.isEmpty, "KNOWN_ISSUES open-entry/index inventory empty — §Open Index missing?")
        let missingRows = entries.subtracting(rows).sorted()
        let staleRows = rows.subtracting(entries).sorted()
        #expect(missingRows.isEmpty, "Open entr\(missingRows.count == 1 ? "y" : "ies") \(missingRows) ha\(missingRows.count == 1 ? "s" : "ve") no §Open Index row — update the index table.")
        #expect(staleRows.isEmpty, "§Open Index row(s) \(staleRows) have no matching open entry — update the index table (resolved entries lose their row when they move to §Resolved).")
    }

    // MARK: - Module Map completeness gate (CLEAN.7.3 / D-168)
    //
    // The ARCHITECTURE Module Map claims to be a per-file behavioural reference for
    // every source file. With no enforcement it drifted: the 2026-06-13 audit found 18
    // undocumented files; by 2026-06-18 it was 62 — including four entire CERTIFIED
    // presets (Skein, Murmuration, Dragon Bloom, Fata Morgana) and recent infra
    // (FlashAnalyzer, DefaultOutputDeviceMonitor). An incomplete "read this before
    // grep-ing" index is worse than none. Per the D-161 ratchet rule 3 (violated twice
    // → mechanize) this converts to a gate.

    /// Every `.swift` / `.metal` under UzumeEngine/Sources + UzumeApp must be
    /// findable in the Module Map by its filename-minus-extension (a substring match).
    /// Diagnostic/tooling modules and utility trees are documented as ONE group entry
    /// that names its files, so a stem match — not a per-file entry line — is the
    /// contract.
    ///
    /// ponytail: substring membership, not entry-line parsing. A short common stem
    /// ("main", "Audio") can match spuriously, so the gate is permissive — it never
    /// false-reds an unrelated increment (the BUG-049 class). Its job is catching a
    /// whole file/subsystem added with NO mention (the FlashAnalyzer / Skein-cluster
    /// class), which it does. Tighten to entry-line parsing only if spurious passes bite.
    @Test("ARCHITECTURE Module Map documents every Swift/Metal source file (CLEAN.7.3 / D-168)")
    func moduleMapCompleteness() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let arch = Self.read("docs/ARCHITECTURE.md") ?? ""
        #expect(!arch.isEmpty, "ARCHITECTURE.md unreadable")
        let mapText = try #require(Self.sectionLines(of: arch, header: "## Module Map"),
                                   "ARCHITECTURE.md has no ## Module Map section").joined(separator: "\n")
        let fm = FileManager.default
        var undocumented: [String] = []
        for root in ["UzumeEngine/Sources", "UzumeApp"] {
            let base = Self.repoRoot.appendingPathComponent(root)
            guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker {
                guard ["swift", "metal"].contains(url.pathExtension) else { continue }
                let stem = url.deletingPathExtension().lastPathComponent
                if !mapText.contains(stem) { undocumented.append(url.lastPathComponent) }
            }
        }
        undocumented.sort()
        let shown = undocumented.prefix(25).joined(separator: ", ")
        #expect(undocumented.isEmpty, "ARCHITECTURE Module Map omits \(undocumented.count) source file(s) under UzumeEngine/Sources or UzumeApp/: \(shown). Add a one-line entry under ## Module Map (or name the file in its module's group entry) — per-file completeness is the map's contract (CLEAN.7.3 / D-168).")
    }

    // MARK: - Skill-integrity gate (DOC.9 / D-179)
    //
    // DOC.9 moved the increment-type-scoped protocols (closeout, defect-handling, doc-pruning)
    // plus the preset audio-data-hierarchy and reference-porting rules out of always-loaded
    // CLAUDE.md into .claude/skills/*/SKILL.md (progressive disclosure). A skill that silently
    // loses a doc pointer or a D-/FA citation is the same drift class the earlier gates catch,
    // so the same referential-integrity contract applies to the skills.

    private static let expectedSkills = ["closeout", "defect-handling", "doc-pruning", "preset-session", "shader-authoring"]

    @Test("Skills: present, well-formed frontmatter, and every doc/D-/FA citation resolves (DOC.9)")
    func skillIntegrity() throws {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let fm = FileManager.default
        let skillsDir = Self.repoRoot.appendingPathComponent(".claude/skills")

        // (a) each expected skill dir has a SKILL.md; (b) frontmatter name matches the dir and
        // description is present and ≤ 500 chars.
        var bodies: [String: String] = [:]
        for name in Self.expectedSkills {
            let path = skillsDir.appendingPathComponent("\(name)/SKILL.md")
            guard let text = try? String(contentsOf: path, encoding: .utf8) else {
                Issue.record("Skill '\(name)' has no SKILL.md at .claude/skills/\(name)/SKILL.md")
                continue
            }
            bodies[name] = text
            let fmName = Self.matches(#"^name:\s*(.+?)\s*$"#, text).first
            let fmDesc = Self.matches(#"^description:\s*(.+?)\s*$"#, text).first
            #expect(fmName == name, "Skill '\(name)' frontmatter name is \(fmName.map { "'\($0)'" } ?? "missing") — must equal the directory name.")
            #expect((fmDesc?.isEmpty == false) && (fmDesc?.count ?? .max) <= 500, "Skill '\(name)' frontmatter description is missing, empty, or > 500 chars.")
        }

        // (c) every docs/… path token in a skill body resolves (placeholders containing '<' skipped).
        var missingPaths: [String] = []
        for (name, text) in bodies {
            for token in Self.matches(#"docs/[\w./-]+"#, text, options: []) {
                if token.contains("<") { continue }
                let clean = token.hasSuffix(".") ? String(token.dropLast()) : token
                if !fm.fileExists(atPath: Self.repoRoot.appendingPathComponent(clean).path) {
                    missingPaths.append("\(name): \(clean)")
                }
            }
        }
        #expect(missingPaths.isEmpty, "Skill doc pointer(s) do not resolve: \(missingPaths.sorted()) — fix the path or the skill body.")

        // (d) D-NNN and FA #N citations in skill bodies resolve (same resolvers as the gates above).
        let dec = (Self.read("docs/DECISIONS.md") ?? "") + "\n" + (Self.read("docs/DECISIONS_HISTORY.md") ?? "")
        let definedD = Set(Self.matches(#"^## D-(\d{3})"#, dec).compactMap(Int.init))
        let claude = Self.read("CLAUDE.md") ?? ""
        var faResolvable = Set(Self.matches(#"^(\d+)\. \*\*"#, claude).compactMap(Int.init))
        for row in Self.matches(#"^\| (#[^|]+) \|"#, claude) {
            faResolvable.formUnion(Self.matches(#"#(\d+)"#, row, options: []).compactMap(Int.init))
        }
        let skillText = bodies.values.joined(separator: "\n")
        let citedD = Set(Self.matches(#"D-(\d{3})(?![\d.\w])"#, skillText, options: []).compactMap(Int.init))
        let unresolvedD = citedD.subtracting(definedD).sorted()
        #expect(unresolvedD.isEmpty, "Skill-body decision citation(s) \(unresolvedD.map { "D-\(String(format: "%03d", $0))" }) resolve to no DECISIONS header.")
        let citedFA = Set(Self.matches(#"(?:Failed Approach|FA) #(\d+)"#, skillText, options: []).compactMap(Int.init))
        let unresolvedFA = citedFA.subtracting(faResolvable).sorted()
        #expect(unresolvedFA.isEmpty, "Skill-body Failed-Approach citation(s) #\(unresolvedFA) resolve to neither a CLAUDE.md entry nor a gap-table row.")

        // (e) CLAUDE.md `.claude/skills/<name>` pointers reference only existing skills.
        let pointered = Set(Self.matches(#"\.claude/skills/([\w-]+)"#, claude, options: []))
        let unknown = pointered.subtracting(Set(Self.expectedSkills)).sorted()
        #expect(unknown.isEmpty, "CLAUDE.md points to non-existent skill(s): \(unknown) — pointers reference only .claude/skills/{\(Self.expectedSkills.joined(separator: ","))}.")
    }
}

// MARK: - DOC.14 — stale increment rows

/// Mechanizes the staleness that four separate rows carried on 2026-09-11 (D-161 rule 3:
/// violated twice → mechanize). All four were the same failure with different faces — a row
/// claiming work is open when it is not — and each was found by a person reading, which is
/// exactly the detection method that had already failed for a month.
///
/// What was actually found that day:
///
/// 1. **WL.4 … WL.10** — eight rows reading *"pending live M7"* while `WL.CERT` had certified
///    Witchlight on 2026-08-07. The reviews were given, not owed.
/// 2. **PR.19 / PR.20 / PR.21** — *"M7 owed"* a day after Matt certified the Nebula build that
///    contained all three.
/// 3. **FD.2** — a 🔨 row under a preset's OLD name ("Fractal Descent") for a preset retired at
///    FLY.14 / D-201. Open work for something that no longer exists.
/// 4. **VL.1** — an increment ID reused for a second, unrelated increment.
///
/// ⚠ **What this gate deliberately does NOT try to catch.** WL.11 looked identical to the eight
/// superseded rows — same preset, same date, same marker — and was the one genuinely open item,
/// because it landed 24 minutes AFTER the certification commit. Only `git merge-base` separates
/// those two cases, and a doc test has no business shelling out to git. So a certified preset's
/// unfinished row is reported as **something to check**, and the row itself says which: if it
/// really is superseded, close it; if it postdates certification, say so in the row and this gate
/// accepts it. The escape hatch is deliberate — a gate that cannot express "genuinely still open"
/// would be closed by deleting true information.
extension DocIntegrityTests {

    /// Increment-ID prefix → the preset it belongs to. Only prefixes that map to ONE preset
    /// belong here; `PR.*` (the preset-roster program) spans the whole roster and is excluded by
    /// construction, not by oversight.
    static let incrementPrefixPreset: [String: String] = [
        "WL": "Witchlight",
        "VL": "Volumetric Lithograph",
        "SKEIN": "Skein",
        "FBS": "Ferrofluid Ocean",
        "AV": "Aurora Veil",
        "FTR": "Fractal Tree",
        "CR": "Cymatic Resonance"
    ]

    /// A row is exempt when it SAYS why it is still open against a certified preset. The phrase
    /// is required to be explicit so the exemption cannot be taken accidentally.
    static let postCertExemption = "POSTDATES CERTIFICATION"

    private static func planHeaders() -> [String] {
        guard let plan = read("docs/ENGINEERING_PLAN.md") else { return [] }
        return plan.components(separatedBy: "\n").filter { $0.hasPrefix("### ") }
    }

    /// `### Increment WL.4 — …` / `### PR.22 — …` → `("WL.4", "…")`. Requires the ` — ` so a
    /// prose heading cannot masquerade as an increment row.
    private static func incrementRow(_ header: String) -> (id: String, title: String)? {
        let body = header.hasPrefix("### Increment ") ? String(header.dropFirst(14))
                                                     : String(header.dropFirst(4))
        guard let dash = body.range(of: " — ") else { return nil }
        let id = String(body[body.startIndex..<dash.lowerBound])
        guard !id.isEmpty, id.first!.isLetter,
              id.contains(".") || id.contains("-"),
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" })
        else { return nil }
        return (id, String(body[dash.upperBound...]))
    }

    /// Title with status markers and trailing dates removed, for comparing two rows that carry
    /// the same ID.
    private static func normalizedTitle(_ title: String) -> String {
        var t = title
        if let i = t.rangeOfCharacter(from: CharacterSet(charactersIn: "✅⏸🔨📋")) { t = String(t[t.startIndex..<i.lowerBound]) }
        if let i = t.range(of: "(20") { t = String(t[t.startIndex..<i.lowerBound]) }
        return t.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// IDs reused by two genuinely different increments BEFORE this gate existed. They are listed
    /// rather than fixed because renaming a historical increment breaks every citation that
    /// resolves to it (the `citationCorpus` gate above would fail), and the history is not worth
    /// rewriting to satisfy a new rule.
    ///
    /// ⚠ **This is a record of debt, not a tolerance.** Do not add to it: an ID reused today is a
    /// mistake being made now, and the fix is to pick a free one. `VL.1` was reused on 2026-09-11
    /// and renumbered to `VL.2` the same day rather than landing here.
    static let knownDuplicateIncrementIDs: Set<String> = [
        "CA.5", "CA.6", "MD.0",                                   // reworded rotation headers
        "CHR.3j", "DOC.7", "PERF.1", "PERF.2", "PERF.2-render", "PERF.3"   // genuinely two increments each
    ]

    @Test("EP: no increment ID is reused for two different increments (DOC.14)")
    func incrementIDsAreUnique() {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        var titles: [String: Set<String>] = [:]
        for h in Self.planHeaders() {
            guard let row = Self.incrementRow(h) else { continue }
            let t = Self.normalizedTitle(row.title)
            guard !t.isEmpty else { continue }
            titles[row.id, default: []].insert(t)
        }
        // A rotated header is a PREFIX of the full title (the body moves to history and the
        // shortened header stays) — that is the DOC.6 convention, not a reuse. A reuse is two
        // titles where neither contains the other from the start.
        var dupes: [String] = []
        for (id, set) in titles where set.count > 1 {
            let list = Array(set)
            let collides = list.indices.contains { i in
                list[(i + 1)...].contains { !($0.hasPrefix(list[i]) || list[i].hasPrefix($0)) }
            }
            if collides && !Self.knownDuplicateIncrementIDs.contains(id) { dupes.append(id) }
        }

        #expect(dupes.sorted().isEmpty,
                """
                ENGINEERING_PLAN.md reuses \(dupes.sorted()) for two DIFFERENT increments.                 Derive the next free ID from the TREE, and grep BOTH `^### <PREFIX>` and                 `^### Increment <PREFIX>` — the rows use both forms, and grepping only the first                 is exactly how `VL.1` was reused on 2026-09-11.
                """)
    }

    @Test("EP: an unfinished row for a certified or absent preset is stale until it says otherwise (DOC.14)")
    func unfinishedRowsAreNotSuperseded() {
        guard Self.docsPresent else { print("DocIntegrityTests: repo docs not present — skipping"); return }
        let shaders = Self.repoRoot.appendingPathComponent("UzumeEngine/Sources/Presets/Shaders")
        let sidecars = (try? FileManager.default.contentsOfDirectory(atPath: shaders.path))?
            .filter { $0.hasSuffix(".json") } ?? []
        guard !sidecars.isEmpty else { print("DocIntegrityTests: shaders dir not present — skipping"); return }

        // Preset name → certified, read from the sidecars themselves (the same ground truth the
        // rubric gate uses), never from a list duplicated here.
        var certified: [String: Bool] = [:]
        for file in sidecars {
            guard let data = try? Data(contentsOf: shaders.appendingPathComponent(file)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = obj["name"] as? String else { continue }
            certified[name] = (obj["certified"] as? Bool) ?? false
        }

        var findings: [String] = []
        for header in Self.planHeaders() where header.contains("🔨") {
            guard let row = Self.incrementRow(header) else { continue }
            let id = row.id
            let prefix = id.components(separatedBy: CharacterSet(charactersIn: ".-")).first ?? id
            guard let preset = Self.incrementPrefixPreset[prefix] else { continue }
            if header.contains(Self.postCertExemption) { continue }
            if certified[preset] == true {
                findings.append("\(id) is unfinished but \(preset) is CERTIFIED")
            } else if certified[preset] == nil {
                findings.append("\(id) is unfinished but \(preset) has no sidecar — retired?")
            }
        }

        #expect(findings.isEmpty,
                """
                \(findings.joined(separator: "; ")).
                Either the review was already given (close the row — this is what eight Witchlight \
                rows and PR.19/.20/.21 carried for weeks), or the preset is gone (FD.2's ghost row \
                for retired Fractal Descent), or the increment genuinely postdates certification — \
                in which case say so in the header with the words "\(Self.postCertExemption)" and \
                state the evidence, as WL.11 did. ⚠ Establish supersession from COMMIT ORDER, not \
                dates: WL.10, WL.CERT and WL.11 all landed on 2026-08-07 and only the commit times \
                separate the superseded rows from the one that was genuinely open.
                """)
    }
}
