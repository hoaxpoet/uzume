# Lane J: known-issues ledger, beta triage (2026-09-29)

Sources: `docs/QUALITY/KNOWN_ISSUES.md` (the Open Index, every §Open body, Known Limitations, Flakes), `DEFECT_TAXONOMY.md`, `docs/diagnostics/CODE_AUDIT_2026-06-09.md`. Where an entry says something is fixed, I checked it with one grep against the tree. I also read the crash and diagnostic reports already on disk. Beta-priority calls are **my read**.

## 0. Problems with the ledger itself

1. **The index says something that is no longer true.** Its header says *"Everything in this table is now open work; nothing in it is already fixed."* About 29 of its ~60 rows are closed (list in §D). The 08-26 cleanup has built back up again. Right now you can't read the open count off the table.
2. **The index and the entry bodies disagree** (for all six below, the fix is in the code):
   - **BUG-115:** the index says resolved (PR.5.2). The body says "**Open** — fix NOT obvious", Resolved: —. `DragonBloom.metal:381` has the tanh `bass_att_rel` fix.
   - **BUG-116:** the index says live-confirmed 09-11. The body still shows "⏳ Manual … **Outstanding**".
   - **BUG-118:** the index and the body's own blockquote say resolved 09-08. The Status field below them says "**Open.** Default reverted…; Resolved: —". The code has whole-track on by default (`BeatGridAnalyzer.swift:308`). The doc comment at :306 ("opts back in") is also stale.
   - **BUG-119:** the index says live-confirmed 09-11. The body says "⏳ Outstanding — the gate for turning BUG-118's default back on".
   - **BUG-145:** the index row says both "manual check passed" and "Manual check … outstanding". The body's status line says outstanding. Its verification item #4 is ✅ ("the BPMs look right").
   - **BUG-106:** the status line says "pending one live 4K confirmation", but that criterion is ✅. Only the felt half is open.
3. **More stale or conflicting entries:**
   - **BUG-081:** the index row says "3 instances (08-03 ×1, 08-04 ×2)"; the body describes one. The row also has a malformed extra column.
   - **BUG-133:** the verdict was measured against the scorer that NRG.3 replaced. Its list of newly seen scenes includes Plasma, which has since been removed.
   - **BUG-144:** still describes mood as "40 % of every score". `PresetScorer.swift:49` now weights energy at 0.30, and mood is gone from scoring.
4. **Severity labels in the hang family are inconsistent.** DEFECT_TAXONOMY classes any hang as P0. The hang family is filed P1 (085), P2 (081) and P3 (060).
5. **Duplicates:** BUG-054 and BUG-149 are the same capability (key detection). BUG-028 is superseded by BUG-065 plus the whole-track grid work.
6. **BUG-091's candidate mechanism conflicts with the code.** The suspected `catch` fires PUB.5's toast, then `endSession` sends the user to EndedView (`VisualizerEngine+LocalFilePlayback.swift:314-318`). That has been in the code since 07-12 (`43a81629`). But the failing 08-17 session rendered for 84 s and Matt reported only silence. So an early-return branch is more likely than the catch (PLAUSIBLE).

## A. Open or at risk, and relevant to the beta

**BUG-152: streaming tracks are sometimes analysed as a different song.** The visuals are planned to another song's tempo and energy.
- **State:** open; confirmed in code. Non-scan tracks send a limit-1 iTunes search and take `results.first` without checking it (`PreviewResolver.swift:133-148`).
- **Exposure:** Apple Music and paste-a-link Spotify. About 8 % of rows on the fixtures (11/136). Testers see a song whose visuals don't match it.
- **Closes:** apply `ScreenReadMatchPolicy` to every track, then a ScanBench before/after.
- **Read:** should-fix. It's S–M, and the fix already exists on the scan path.

**BUG-156 (product half): local-file Next, Stop or seek could freeze the app, and track changes could lag, while preparation is still running.**
- **State:** a risk nobody has observed yet. It arrived on 09-28 with LFSEEK.1's `.dataPlayedBack` (`LocalFilePlaybackProvider.swift:564`).
  - The mechanism is proven in-process: the completion arrives 8.5 s late when the default/userInitiated pool is saturated.
  - `player.stop()` blocks in `CancelTimer` while that timer is pending.
- **Exposure:** local-file sessions where preparation overlaps playback (large folders). Worst on low-core Macs such as the 8 GB M1 Air. If it happens, it's a freeze that leaves no `.ips`.
- **Closes:** one Release session on a large folder while it is still preparing. Press Next and seek repeatedly. Time `onFileEnded` against the file's end, and time `stop()` on the main thread.
- **Read:** should-verify before the beta.

**BUG-056: changing the audio output restarts the local song from the top.** AirPods, headphones and display speakers all trigger it.
- **State:** open; confirmed in code. `handleConfigurationChange` sets `startSeconds = 0` deliberately (`LocalFilePlaybackProvider.swift:595`). If the restart fails, it only logs, so the tester gets a silent session.
- **Exposure:** every output change during a local-file session. Common with AirPods.
- **Closes:** save the playhead into `startSeconds` before the restart, then one device-swap check. It's S now, because LFSEEK.1 already built the seek primitive.
- **Read:** should-fix.

**BUG-055: after an app update, streaming says "ready" but the visuals are flat (the Screen Recording grant has gone stale).**
- **State:** the detector card is done. The root cause is blocked on CLEAN.2.5b (Developer ID + notarization), which `SECURITY_POSTURE.md:128` still marks "blocked on paid membership". Builds are signed "Apple Development", team `2LBTN9PB4Z`.
- **Exposure:** depends entirely on how beta builds are signed. If signing changes between updates, every streaming tester hits it on every update.
- **Closes:** the signing decision, then an install-then-update test on a clean user account.
- **Read:** must-decide (distribution, not code).

**BUG-091 (P1): one local file is picked, preparation finishes, and no sound ever plays.**
- **State:** instrumented 08-17; never reproduced since. See §0.6.
- **Exposure:** single-file sessions; one known instance.
- **Closes:** one reproduction. `session.log` names the branch, and `SessionRecorder` always records (`VisualizerEngine.swift:996`), so a tester can supply this by zipping their latest `~/Documents/uzume_sessions/` folder.
- **Read:** accept for the beta, with an evidence request.

**BUG-149 (+BUG-054): most songs show "F♯ minor".**
- **State:** open; not diagnosed; 35 % of 993 tracks.
- **Exposure:** only in the opt-in detailed preparation view (the default is "mysterious", `SettingsTypes.swift:36-40`) and the debug overlay. Music-literate testers will notice.
- **Closes:** a fix, or hiding the field. Matt has declined hiding.
- **Read:** accept and document; merge BUG-054 into it.

**SCAN-LIM: the Spotify scan hasn't been tried on a non-English Spotify, the compact list, 100+ songs, small windows or the web player.**
- **Exposure:** international testers and web-player users. The scan still finishes, but shows "27 songs" instead of "27 of 38". The web player can't be scanned at all.
- **Closes:** one real capture each of a non-English interface and the compact view.
- **Read:** accept and document; do the two captures if they're cheap.

**BUG-070 residual (= audit P2 "zombie tap"): ending a streaming session during silence can leave the tap running, and the next start fails with "already capturing".**
- **State:** PUB.6 fixed the failed-reinstall half; its manual check is pending. The race itself is confirmed in code:
  - `attemptTapReinstall` reads the mode once, then `performTapReinstall` does stop → start with no re-check (`AudioInputRouter+SignalState.swift:142-167`).
  - `stopInternal` cancels only *pending* work (`AudioInputRouter.swift:361-381`).
- **Exposure:** reinstalls fire during silence (paused music), which is exactly when users end sessions. The window is under 1 s per attempt.
- **Closes:** re-check the current mode right before `startCapture` (S), plus a device-swap check.
- **Read:** should-fix.

**Audit P3, never filed: display handling is missing for the whole session if Uzume isn't the frontmost app when playback starts.**
- **State:** `PlaybackView.swift:233` attaches the fullscreen observer, `DisplayManager` and the hot-plug coordinator only `if let window = NSApp.keyWindow`, and never retries. Nothing brings the app forward when playback starts (`NSApp.activate` is called only by the scan). In the streaming handoff the user is in Spotify when the first audio arrives.
- **Confidence:** PLAUSIBLE. I haven't confirmed live that `keyWindow` is nil at that `onAppear`.
- **Exposure:** streaming testers using external or multiple displays.
- **Closes:** attach when a window becomes available, then one check.
- **Read:** should-verify.

## B. Fixed, with a check outstanding

- **BUG-139: stopping streaming or changing the output device could freeze the app forever (a deadlock).** Fixed 09-23; the claim/destroy split is in `SystemAudioCapture.swift:400-462`. It has never been checked live on the shipped streaming path.
  - **Exposure:** every streaming stop and every output change.
  - **Closes:** one streaming start → stop, plus one output change.
  - It's also a plausible cause of BUG-058's single freeze: `performReinstall` reaches the same teardown.
  - **Read:** must-verify (cheap to check, severe if wrong).
- **BUG-151: the local queue cut the last second off every song.** The fix is in the code (`:564`). **Closes:** listen to a few song endings. **Read:** must-verify (cheap). Do it with BUG-156.
- **BUG-148: scene choice ignored the music (the mood model was at chance).** Replaced by measured energy (NRG.1–3). **Closes:** Matt's live check. **Read:** should-verify; the planner's core scoring changed one week before the beta.
- **BUG-133: the same few scenes cycle.** The near-tie band is in the code (`SessionPlanner+Selection.swift:52`). Matt's felt verdict is outstanding, and the measurement predates NRG.3. **Closes:** re-count distinct scenes on the current scorer, plus Matt's felt check. **Read:** should-verify.
- **BUG-144: a song's stored mood was its fade-out.** Fixed. The felt check came back "merely ok". Its scorer consumer was removed at NRG.3; Kagura still reads `mood.arousal`. **Read:** re-scope or close; it no longer affects the beta.
- **BUG-106: at 4K, stems ran a period late.** Fixed and measured live. The felt half is outstanding. **Exposure:** streaming testers fullscreen on 4K/5K/6K. **Read:** accept; fold into the streaming session.
- **BUG-134: sync loosens where the grid changes octave.** 14.6 % irregularity remains, and only newly prepared tracks benefit. **Closes:** one M7 on *Ready to Start*. **Read:** accept and document.
- **BUG-117: every beat was treated as a downbeat on grids with no meter.** Fixed (`BeatGrid.swift:56`). The formal confirmation is pending; BUG-120's 09-08 "Witchlight is working now" probably covers it. **Read:** close on Matt's word.
- **BUG-141: stem data was shifted on 48/96 kHz files.** Fixed. The manual check is optional (Ferrofluid Ocean on a 96 kHz file). **Read:** accept.
- **OBS-DS4-1: the detailed preparation view looked uniform.** BPM is fixed and mood is replaced; only the key readout (BUG-149) is left. **Closes:** Matt's recheck. **Read:** close after the local session.
- **BUG-036: memory allocations on the real-time audio thread.** Site 3 (the raw-tap recorder, the first 30 s of every session) is parked. Every tester runs it, because recording is always on; it's untested on low-end Macs. **Read:** accept; watch for glitches.

## C. Parked, known limitations, or low exposure

- **BUG-065 / BUG-028 / BUG-107 / BUG-076: beat-locked visuals are looser on streaming.** Causes: the 30 s preview grid, the cold-start phase, and dense or accelerating songs (Billie Jean ≈100–160 ms off at FF.5). Accepted at FF.5. **Read:** accept and document ("beat sync is tightest on local files"); merge BUG-028.
- **BUG-135:** the downbeat may land on beat 3. Left as is on Matt's call. **Read:** accept.
- **BUG-058:** a rare tap freeze after an output swap. Instrumented, and the stall card surfaces it; may have been BUG-139. **Read:** accept; the streaming session covers it.
- **OBS-DS6-1:** Ferrofluid Ocean went black during about 3 s of near-silence. **Read:** accept.
- **BUG-123:** Dragon Bloom is paler than the reference. Parked. **Read:** accept.
- **BUG-084:** stem deviation spikes to 35, but the output is protected by a soft knee. **Read:** irrelevant to the beta.
- **BUG-077:** differs from the reference post-processor; harmless today. **Read:** irrelevant.
- **A11Y-001, DEAD-001:** a UI-test identifier and a dead property. **Read:** irrelevant.
- **BUG-013, BUG-001, BUG-005:** known limitations. BUG-005's UX criterion looks met ("Skipped — preview unavailable", `Localizable.strings:57`), so that half can close.
- **AUDIT-2026-06-09:** the audit doc has no per-bullet status.
  - All P1s (BUG-030–035, 037) are closed in the history file.
  - The P2 I verified as still present is the zombie tap (§A). Four others I spot-checked are fixed; the rest are marked fixed in the ledger, and I didn't re-check them all.
  - The P3 backlog has not been re-audited. Two items reach testers: the display-handling one (§A) and ">2-channel local files make a corrupt buffer" (I didn't check whether that's still there).

## D. Closed but still in the index (no action needed)

BUG-138, 132, 136, 137, 129, 087, 103, 131, 140, 142, 143, 145, 146, 147, 150, 153, 154, 155, 115, 116, 118, 119, 120, 121, 122, 124, COPY-001, DEAD-002, DEAD-003. I checked that the fixes for 131, 139, 115, 117, 119, 151 and 106 are in the code.

---

## (a) Outstanding manual checks, grouped into three sessions

**Session 1: local files.** Matt's Mac, Release build. Use the beta playlist folder plus a 48 kHz and a 96 kHz file. Turn the detailed preparation view on. Use a folder large enough that preparation is still running after playback starts.
1. Listen to four or five song endings (BUG-151).
2. While preparation is running, press Next and seek repeatedly, and note any beachball or late track change (BUG-156 product risk).
3. Swap output between AirPods and speakers mid-song (BUG-056 baseline; after the fix, it should keep its place).
4. Start a single file from a fresh launch, two or three times (BUG-091 watch).
5. Read the preparation view: BPM, energy, key (OBS-DS4-1, BUG-149).
6. Felt checks: do the scenes suit the songs, and are any of the newly admitted scenes wrong for their song (BUG-148, BUG-133, BUG-144)?
7. *Ready to Start*, after clearing its cache: does sync hold past 9 s (BUG-134)?
8. Witchlight or Membrane on a song whose meter was declined (BUG-117).
9. Optional: Ferrofluid Ocean on the 96 kHz file (BUG-141).

**Session 2: streaming.** Spotify scan and one Apple Music playlist, Release build, Screen Recording granted, preferably with an external 4K/5K display.
1. Start → play → stop, twice (BUG-139).
2. Three to five output-device swaps mid-song (BUG-139 `performReinstall`, BUG-070, BUG-058).
3. Pause Spotify for 30 s or more, then end the session and start a new one (the BUG-070 zombie-tap race).
4. After pressing play in Spotify, drag the Uzume window to the other display and hot-plug it (audit display-handling item).
5. Fullscreen at 4K: do stem-driven scenes follow the music, and is any stutter acceptable (BUG-106)?
6. If possible, one scan in compact view and one with a small window (SCAN-LIM).

**Session 3: distribution.** The real beta artifact on a clean macOS user account. Install it, grant Screen Recording, then install an update build and start streaming. Does audio flow, or does the silent-tap card appear (BUG-055)?

## (b) The hang and crash family

| ID | What's known | Evidence still missing | Can a tester supply it? |
|---|---|---|---|
| **BUG-085** (P1) | The main thread is permanently blocked in `nextDrawable`, at 0 % CPU, while the app holds zero drawables. Audio and ML carry on. The last capture was 08-05; the lead is GPU contention from stem separation, untested. | Why CoreAnimation stops handing out drawables; a run with stem separation suppressed. | Not with `Scripts/capture_hang.sh` (needs the repo and Terminal). |
| **BUG-081** (P2) | A beachball about 78 s in; the renderer was healthy up to the last frame, then stopped. Probably the same bug as BUG-085: same signature, and the index's "08-04 ×2" are BUG-085's day. | Any stack. | Same as above. |
| **BUG-060** (P3) | The render loop died on a switch to Gossamer. It recurred once, undated. | Any stack. | Same as above. |
| **BUG-156** risk | Possible main-thread stall in `player.stop()`, introduced 09-28. | One live measurement. | It would look like a beachball. |
| **BUG-139** | A deadlock; fixed, not live-validated. A regression would look like a freeze on stop, with no `.ips`. | One streaming session. | — |
| **BUG-131, BUG-103** | Crash class, fixed and gated by tests (the Objective-C exception is now a Swift error). | — | — |

- **Crash reports on disk.** There are six Uzume `.ips` reports (09-24/25). All have the BUG-143 signature (`objc_release` in an autorelease-pool pop from the test host). None is a crash from using the app.
- **Other system reports.**
  - `/Library/Logs/DiagnosticReports` holds five Release-build "disk writes" reports from 09-22, about 2.1 GB each. They come from the ProRes/AVAssetWriter capture, which is opt-in via `UZUME_RECORD_VIDEO`, so testers can't trigger it.
  - It also holds seven `cpu_resource` reports (55–85 % CPU for about 90 s), all from Debug builds, so they say nothing about Release.
- **Evidence is being deleted.** The default retention (`lastN10`) has already removed all three original hang sessions (06-17T22-10-50Z, 08-03T22-54-06Z, 08-05T21-21-03Z). Only `_freeze_captures/` survives.
- **The stall watchdog has a new dependency on the main thread.** BUG100.1 (08-26) added a `MainActor.run` hop to the heartbeat branch (`VisualizerEngine+InitHelpers.swift:209`). HANG.1 promised a watchdog that doesn't depend on the render thread. If a hang starts just after a heartbeat boundary, the watchdog parks forever and never writes its `STALL` line. The window is small, but the hop is verified in the code.
- **How testers could supply hang evidence.**
  - Force-quitting produces no `.ips`. I couldn't confirm whether macOS writes a spindump `.hang` for this app; none is on disk.
  - A realistic manual route: Activity Monitor → Uzume ("Not Responding") → ⋯ → Sample Process → Save. No Terminal needed.
  - My read, **must-fix (the instrumentation, not the bug):** a background watchdog that checks the main thread. On a stall longer than 3 s it runs `/usr/bin/sample <own pid> 3` into the session folder and marks that session exempt from retention. The app is unsandboxed, so it can launch `sample`. The stack is then captured even if the tester force-quits afterwards.
  - Pair it with a prompt on next launch: "last session ended abnormally, here's the folder".

**Reviewed and healthy:** the fixes for BUG-131 (`queue.sync` after `cancel`), BUG-139, BUG-151, BUG-117, BUG-119, BUG-115 and BUG-106 are in the tree. BUG-005's copy is present. SessionManager applies its state guard before publishing the source. The unreachable Rule 5 timeout is fixed (PUB.5).

**Could not verify:**
- whether `NSApp.keyWindow` is nil at `PlaybackView.onAppear` in a real handoff;
- whether macOS writes `.hang` reports for Developer-ID builds;
- whether the audit's P3 >2-channel bug is still present;
- why the 08-05 build never logged a `STALL` line.
