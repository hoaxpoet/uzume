# Phase BR — Kickoff: beta readiness remediation (BR.1–BR.20)

> **Paste to start the session:** *"Read `docs/prompts/BR_KICKOFF.md` and `docs/diagnostics/BETA_READINESS_AUDIT_2026-09-29.md`, run the pre-flight, then begin BR.2. Standing approval for this programme: after an ALL GREEN closeout, push that increment's `br-N` branch and open its PR. Never push to main, never merge."*
> Drop the last two sentences if you'd rather approve each push yourself. The approval has to be in your message; a file can't grant it.
> This is the standing brief for Phase BR. Increment type: **fix / infrastructure** — engine and app correctness. This is not a scene programme.

## Objective

When this programme ends, the build a tester installs on Oct 15 meets the accepted Tier 1 plan:

- it keeps its photosensitivity promises;
- the display stays awake;
- a streaming song change can't corrupt memory;
- it can send Matt evidence when it fails;
- it has been compiled and measured beyond Matt's Mac mini.

On top of that, as much of Tier 2 as fits before the **Oct 11 freeze**, in the order below.

**Every product decision the plan raised is settled.** Matt accepted all thirteen defaults on 2026-09-29: see the audit's §Decisions. Treat them as constraints; don't reopen them. His hardware is an M4 MacBook Pro plus a 4K display. There is **no M1 Air**, so the low end gets the conservative cap, blind.

## Where things stand (2026-09-29)

- **The plan:** [`docs/diagnostics/BETA_READINESS_AUDIT_2026-09-29.md`](../diagnostics/BETA_READINESS_AUDIT_2026-09-29.md).
- **Evidence:** [`docs/diagnostics/BETA_READINESS_2026-09-29/`](../diagnostics/BETA_READINESS_2026-09-29/), lane reports A–K. Finding IDs (A1, C2, K1 …) point into them.
- **Status table:** `ENGINEERING_PLAN.md` §Phase BR (rows BR.0–BR.20). Keep its status column current. It's how progress survives context compaction.
- **BR.0 belongs to another session.** "CLEAN.2.5b prompt execution" owns branch `clean-2-5b`: the notarized DMG, macOS 15+/arm64, and `BuildFlavor` (developer | public), which already switches off session recording in the public build. **Several BR items build on `BuildFlavor`.** If it isn't on `origin/main` yet, do the parts that don't need it, and never build a second flavor mechanism.

## Skills

- **`defect-handling`:** before any code change, for every increment. These are defects, and the evidence-before-implementation gate applies. The audit's evidence counts as the diagnosis, but each fix still starts from a failing test or a reproduction artifact.
- **`preset-session`:** before touching any scene sidecar, scene catalog or flash harness (BR.1's Fractal Tree exclusion and flash-gate work; BR.18).
- **`shader-authoring`:** before any renderer or GPU-facing change (BR.6's render cap).
- **`closeout`:** at the end of **every** increment.

## Read first (only what the current increment needs)

1. The audit, sections: §Tier 0, the current increment's section, §Decisions, and §Reliability.
2. The lane report sections cited by the increment's finding IDs.
3. `docs/QUALITY/KNOWN_ISSUES.md` entry `AUDIT-2026-09-29`, plus any BUG-entry the increment touches (grep; don't read the file end to end).
4. The files the finding quotes. Re-read them. Line numbers move, so trust the code over the report.

## Pre-flight (a failed check stops the session)

1. **The plan is on `main`.** `git log origin/main --oneline | grep 'AUDIT.2'` must be non-empty. If PR #312 is unmerged, stop and tell Matt.
2. **The worktree is runnable.** Run `Scripts/link_fixtures.sh`, and confirm `UzumeEngine/Sources/ML/Weights` holds the full set (about 176 entries, not 4).
3. **Baseline is green.** `Scripts/closeout_evidence.sh` on unmodified `origin/main` ends `EVIDENCE: ALL GREEN`. First check `ps aux | grep -E 'swift-test|xcodebuild'` for another session's suite: a contended run fakes timeouts (BUG-156 class).
4. **Record the flavor state.** `git log origin/main --oneline | grep 'CLEAN.2.5b'` and `ls UzumeApp/Services/BuildFlavor.swift` tell you whether BR.4 can start.

## How to run the programme

- **One increment → one branch (`br-N`) off fresh `origin/main` → one PR.** Stay in this worktree: new branch, never a sibling `git worktree add`. Merge `origin/main` into the branch before opening the PR; `main` is strict.
- **Push only with Matt's approval in chat,** either per push or as the standing approval in his opening message. Only `br-N` branches: never `main`. Never merge, and never enable auto-merge; Matt merges.
- **Filing:**
  - **P1 findings** get their own KNOWN_ISSUES entry when picked up. Take the **next free BUG-number from `origin/main` at the moment you file**; `main` and `clean-2-5b` already collided once.
  - **P2/P3 findings** are tracked as status lines under the `AUDIT-2026-09-29` umbrella entry.
  - If a merge conflicts on a number, renumber. Never duplicate a number, and never leave a hole (the DocIntegrity continuity gate).
- **The decision-set D-entry:** once `clean-2-5b` has merged, file one D-entry recording the thirteen accepted defaults, at the next free D-number. It can't be filed before then without a hole.
- **What Matt sees or feels:**
  - Anything outside the accepted decisions is a DECISION-NEEDED for Matt, not an implementation choice: product language, two or three options, a recommendation, a default.
  - A visual or felt fix closes as **"pending live check"**, never "resolved", until Matt confirms. Queue the check into the audit's three listening sessions.
- **When a lane claim doesn't reproduce on re-check:** don't fix it. Record it in the audit's §Reliability as refuted, with the evidence.
- **Performance numbers state their build configuration** (Release; CLAUDE.md), and the hardware.

## The increments, in working order

Order: Tier 1 first, quick safety wins leading; then Tier 2 top-down. The fix directions are in the audit. The done-when criteria below are the minimum.

| # | ID | What | Done-when |
|---|---|---|---|
| 1 | **BR.2** | Keep the display awake (B1) | A display-sleep assertion is held from `.ready` through `.playing` and released on end, idle and window close. A unit test covers the state→assertion mapping through a seam. `pmset -g assertions` names Uzume mid-session (on the M4 MacBook Pro, on battery: Matt's check). |
| 2 | **BR.1** | Photosensitivity safety (F1, F1b, F6, F7, K1/D1, K4, K3/E13/F15/A13) | Each item below has a test: <br>• launched with Reduce Motion on, the engine gets reduced motion before the first frame; <br>• Dim Flashing Lights is read and acts like Reduce Motion; <br>• no route reaches `.playing` without the notice acknowledged (the local-file path included); <br>• the notice button sets in-app Reduced motion "Always on"; <br>• Fractal Tree is excluded when the GPU lacks `.apple8` (stubbed capability); <br>• the flash harness measures Fractal Tree, Ferrofluid Ocean's lit output and Waveform, and **fails if a measured pipeline is a G-buffer state** (negative-controlled). <br>*Public-flavor part* (needs `BuildFlavor`): Shift+→ walks only certified, non-diagnostic scenes; "Show uncertified scenes" and the user-preset folder are off. |
| 3 | **BR.3** | Streaming song-change resets run on their owners' threads (G1) | Preset, geometry and identity resets run on main; `mir` and mood resets run on the analysis queue. A test proves it (thread probe or `dispatchPrecondition` under test). A new TSan stress case, a streaming track change with Witchlight active, is added to `Scripts/tsan_stress.sh` and shows 0 races. The torn-reference reads in the same closure are fixed too. |
| 4 | **BR.5** | Evidence from testers (H3, F16, D3, H5, H7) | **Help › Report a Problem** writes a zip after the tester consents. It holds recent unified-log entries, `Uzume*.ips`/`.hang` files, hardware/OS/GPU, and build number + git SHA; a test runs the builder on fakes. It then opens a pre-filled GitHub issue link. <br>An abnormal-exit marker is set at launch and cleared on clean quit, and the next launch offers the report (test). <br>The stall watchdog no longer hops to the main actor, and a test shows it logs STALL with main blocked. On a stall over 3 s it samples the process. <br>`capture_hang.sh` and `window_state.swift` look for `Uzume`. The build SHA is in Info.plist; coordinate with `release.sh`'s owner. |
| 5 | **BR.6a** (first half of BR.6) | CI compiles Metal and builds Release (H1, H8) | A CI step builds the Release configuration and compiles every shader through the same source assembly the app uses. It is shown red on a deliberately broken shader (negative control, then reverted) and green on `main`. |
| 6 | **BR.6b** (second half of BR.6) | Measure and cap (K2, D4–D6) | Run Release sessions on the M4 MacBook Pro's Retina display (on battery, with Low Power Mode on and off) and on the 4K display, recording `RENDER_TARGET` and `frame_gpu_ms`. Record the cold first launch after a fresh install. Tier-1 Macs get the conservative render cap (about 1440p-equivalent, compositor-upscaled) and Alfvén excluded, both with tests. Numbers go into the audit. Whether any cap applies above tier 1 comes to Matt with the numbers. |
| 7 | **BR.4** | The public build shows tester things (I2/F3/A9, F8, F18, I10, H11, A13/G9, tester notes). Needs `BuildFlavor` on main. | In the public flavor: <br>• the stall card has no Terminal step and stays silent before any audio; <br>• no developer keys or bug IDs appear in help; `+` fires on US and UK layouts; `.` has one binding; <br>• no raw string keys show, and a test checks that every referenced key exists; <br>• the Ended screen shows a real duration and a pluralised count; <br>• no `~/uzume_diag.log` is written; <br>• the hot-reload folder is off. <br>A one-page tester release note exists. |
| 8 | **BR.7** | Preparation never strands the tester (C2, F10, C11, F13, C10, F11) | Tests: a failed track in 1–3 doesn't block Start now; no `.ready` with nothing prepared; the reactive-mode escape is wired; no offline screen for local files; missing weights say so; Cancel during Connecting sticks. |
| 9 | **BR.8** | Long playlists keep their preparation (C1) | A 120-track synthetic session keeps every prepared track planned (test). Stem audio is no longer held in the cache. |
| 10 | **BR.9** | Background preparation gets its own analyzers (C3/G3) | The preparer holds its own `StemAnalyzer` and `MoodClassifier` (test on instance identity). One replay with and without background prep shows the live drivers unaffected. |
| 11 | **BR.10** | The "control Spotify / Music" permission (E1, I3/A6/C6/F12, E12, E14) | −1743 is detected on both paths, and the existing permission screen or card appears (tests). A streaming session with no now-playing falls back to reactive mode. Only the session's own source is polled. `NSAppleEventsUsageDescription` is reworded. |
| 12 | **BR.11** | Real listening habits (E2, E7, E8/B2, E6, E3, G7) | Tests: <br>• a paused player is not a track change; <br>• off-plan songs get reactive scenes; <br>• loops and repeat-one keep their scene timeline; <br>• the local-file clock follows the playhead; <br>• ad-hoc sessions start with no stale plan; <br>• a failed file doesn't shift the plan; <br>• late async results are dropped by generation. |
| 13 | **BR.12** | Audio capture lifecycle (G2/B14, G8, B5, B6, G6) | One serial lifecycle queue with a generation token. A failed reinstall keeps the device monitor alive. A `kAudioHardwarePropertyServiceRestarted` listener recovers the tap. There is no reinstall churn on Ready. The tap rate is validated. A TSan stress case (end session during reinstall) shows 0 races. |
| 14 | **BR.13** | Local-file transport (B3/BUG-056, B4, B10) | A device change resumes at the position and keeps a paused state. Opening a new source stops the old audio. Mono files are analysed correctly (tests). |
| 15 | **BR.14** | Window, keys, cursor, permission (F4/D7, F9, F14, F19, F6, D8, A8/F17) | Fullscreen handling attaches from the view's own window; Esc is not hijacked in Settings or help; closing the window ends the session; the cursor hides with the chrome; ⌘, and an Idle-screen gear open Settings; "Move to primary" works; local-file sessions start without Screen Recording. |
| 16 | **BR.15** | Hide the controls that do nothing (F5/E5, E4, E14) | The three Visuals settings and the live-adaptation keys are hidden in the public flavor. Adaptation toasts are off by default, per UX_SPEC. |
| 17 | **BR.16** | Honest copy and credits (A7, C13, K7/H9, F16) | The decided privacy sentence is in place. MusicBrainz is throttled to 1 request/s. Settings › About › Acknowledgements covers Aurora Veil (CC BY-NC-SA), PANNs, Beat This!, Open-Unmix, CMU mocap and the Milkdrop authors. The licence line, the copyright strings and the CREDITS.md Milkdrop table are corrected. SECURITY_POSTURE lists MusicBrainz. |
| 18 | **BR.17** | Output devices (I4/B7, G4, B9) | Output latency is read from the device (device + stream latency + safety offset) at start and on device change. Stems compute at 88.2 and 96 kHz. High-rate FFT resolution is fixed. All tested, plus one AirPods check by Matt. |
| 19 | **BR.19** | The right song (BUG-152, C7, C8/A10) | The Apple Music path uses the verified lookup. Transient failures retry with backoff, and a non-JSON body is never cached. The storefront comes from the Mac's region, with the US as the fallback. All tested. |
| 20 | **BR.18** | Streaming fidelity for the newest scenes (K6) | A partial energy curve counts as absent on streaming, and the stem warm-up covers every stem route (tests). Then **stop and report**: Matt's streaming review of the top ten scenes decides whether it lands. |
| 21 | **BR.20** | Flash check v2 (I8) | Regional and saturated-red flash detection exists, each negative-controlled. It is run across the certified roster, with results recorded. |

**Oct 11: freeze.** Start no new increment. Reconcile the known-issues ledger (the audit's §Known-issues ledger), file the decision-set D-entry if `clean-2-5b` has merged, and bring Matt the list of pending live checks, grouped into the three listening sessions. Whatever isn't done moves to Tier 3 in the plan.

## Do not

- **Don't touch `clean-2-5b`, `Scripts/release.sh` or BR.0.** Send the owning session a message instead.
- **Don't reopen an accepted decision.** For example: don't start a new scene (the roster is called at 27), don't wire the hidden controls, and don't add crossfades.
- **Don't widen a timeout or budget to make a test pass.** Order the test against the real signal (the BUG-150/154/156 pattern).
- **Don't delete branches, stashes, worktrees or files** without Matt's per-item yes.
- **Don't refactor beyond the finding.** The VisualizerEngine decomposition (R3.3–R3.5, CLEAN Phase 8) is Tier 4.
- **Don't claim a visual or felt fix is resolved** on synthetic evidence.
- **Don't publish performance numbers** without the build configuration and the hardware.

## Verification

```bash
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build
swift test --package-path UzumeEngine
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test
Scripts/closeout_evidence.sh
```

Plus the increment's own gates:
- `Scripts/tsan_stress.sh` for BR.3 and BR.12;
- the multi-pass flash harness for BR.1 and BR.20;
- the Release build for any timing claim: `xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build`.

## Commits

- Format: `[BR.n] <component>: <description>`. Use small commits: the failing test, then the fix, then docs (`[BR.n] KNOWN_ISSUES + release notes + plan: …`).
- Each increment updates `ENGINEERING_PLAN.md` §Phase BR (its row plus a §Recently Completed entry), `KNOWN_ISSUES.md` and `RELEASE_NOTES_DEV.md`.

## Closeout (every increment)

Invoke `closeout`. Produce the 8-part report, with the verbatim `Scripts/closeout_evidence.sh` block as §2 and its commit hash matching HEAD. Also include:
- the TSan result (BR.3, BR.12);
- the flash-harness table (BR.1, BR.20);
- the measured numbers with configuration and hardware (BR.6b);
- which listening session each pending live check was added to.

## Stop and report when

- a suite fails and it is not a known contended-run flake confirmed by an isolated rerun;
- a fix would change what Matt sees or feels beyond an accepted decision;
- an increment needs broader architectural change than its finding;
- a lane claim doesn't reproduce;
- it is Oct 11.
