# Uzume — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

*(RECON.2 reconciliation pass, 2026-08-03 — the 2026-08-03 production audit found this
index disagreeing with its own entry bodies. Three entries left §Open: **BUG-080**
and **BUG-071** were stamped resolved/closed *in place* while still indexed as open,
and **BUG-041** closed as stale on Matt's call. One entry was added: **BUG-084**,
promoted out of a BUG-041 inline aside so it would survive that closure. **BUG-060
moved the other way** — Matt reported the hang has recurred, which falsifies its
"likely resolved" status. Everything in this table is now open work; nothing in it
is already fixed.)*

*(Merge note, RECON.9, 2026-08-03 — `origin/main` moved 12 commits while this pass was
in flight and landed three defects of its own. **BUG-081** (app beachball, genuinely open)
joins the table below; **BUG-082** and **BUG-083** were already resolved when they landed,
so they went straight to §Resolved under the convention above rather than being indexed as
open. That parallel session hit the same number collision from the other side — its notes
record a 080 → 082 renumber — and this branch renumbered its own new entry to **BUG-084**
for the same reason. BUG-081 and BUG-060 are the same hang class; they are cross-linked.)*

*(Progress pass, 2026-08-07 — **two entries left §Open, both fully resolved**: **BUG-079**
(release-config test build; the DBN.2 budget it was hiding measures 17.9 ms in release against a
50 ms plan figure) and **BUG-078** (the `AVAudioPlayerNode` teardown trap — root-caused as a
concurrent-`start()` overwrite, fixed in `f68efb67`/PR #62, closed on Matt's live local-file
session `2026-08-07T19-10-25Z`). Nothing else changed state. The working order for what remains
is in [`ENGINEERING_PLAN.md`](../ENGINEERING_PLAN.md) §Immediate Next Increments item 5 —
**sorted by whether the work is doable, not by severity label**, because most of the remaining
P1/P2 headline items are blocked on an artifact that only a live failure can produce and cost
nothing while they wait. The one method note worth carrying: BUG-078 sat for a week on "nobody
has captured the trap" while 25 matching `.ips` reports sat in
`~/Library/Logs/DiagnosticReports/`. **Before filing another sighting of an intermittent crash,
read the crash reports already on disk.**)*

*(Audit pass, 2026-08-26 — §Open was carrying **twelve entries whose own bodies said they were
fixed**: BUG-086, BUG-089, BUG-090, BUG-092, BUG-093, BUG-094, BUG-095, BUG-096, BUG-097,
BUG-098, BUG-099, BUG-101. All twelve verified against the tree (fix commit on `main`, and for
the preset entries the sidecar/shader source) and moved out. Six went to §Resolved; the six with
the oldest resolutions were **rotated early** to `KNOWN_ISSUES_HISTORY.md` — verbatim, the same
move `Scripts/rotate_docs.sh` makes at 14 days — because moving all twelve into §Resolved would
have put it at 90 KB against its 50 KB DOC.6 budget. §Open is now 20 entries, and every one of
them is unfinished work. One factual correction landed in place: **BUG-088**'s "three undeclared
reads" are not reads — see the entry.)*

| ID | Sev | Domain | One-liner |
|---|---|---|---|
| BUG-130 | P1 · open 2026-09-11 | audio.pipeline | **Local-file stop/pause FREEZES the feature vector at its last values instead of decaying to silence.** Session `2026-09-11T21-00-42Z`: a 1617-frame (26.9 s) run with `bass/mid/treble` byte-identical at `0.27158/0.02265/0.00522` while `playback_time_s` advanced 0.01 s. Every preset sees a steady non-zero signal with playback stopped; no silence-dependent behaviour can fire. |
| OBS-DS6-1 | P3 · observed 2026-09-03 (DS.6 M7, Spotify session), recorded not chased | preset.fidelity / Ferrofluid Ocean | **Ferrofluid Ocean went black for a stretch mid-track.** Matt: *"the Ferrofluid Ocean preset blacked out at one point, unrelated to this work."* Session `~/Documents/uzume_sessions/2026-09-03T20-04-45Z`; frames were presented throughout (no drawable failures), and the tap saw ~3 s of near-silence (RMS 0.001) right after the preset began — whether the black is the preset's honest response to no energy or a defect is unverified. Needs a reproduction with a timestamp. |
| OBS-DS4-1 | P3 · observed 2026-09-02 (DS.4 live run), recorded not fixed | dsp.mir / mood | **The detailed preparation view makes the analysis legible for the first time, and what it shows on a real 40-track playlist is suspiciously uniform: the first ten heard tracks read 132–138 BPM and nine of ten read "bright".** Tunes Club TC 29 spans ambient, techno and downtempo; a genuine spread would show it. The view reports faithfully (`TrackProfile.bpm` / `.mood` straight from `SessionPreparer+Analysis`), so this is a finding about the readout's *input*, not about DS.4 — it is the same 30 s-preview MIR the Orchestrator has always planned from, now visible. **No root cause asserted** (BUG-061 rule). Candidates worth measuring, not assuming: the mood scaler's valence bias (DYN.6.2 narrowed valence spread; BUG-066), and the preview-window tempo instability BUG-076 records. Evidence: `docs/reviews/DS.4/after/live-mid-detailed.png`. Worth its own increment before the detailed view ships to beta listeners as "what Uzume heard". |
| COPY-001 | P2 · **RESOLVED 2026-09-01** | app.copy / product-claim | **The source picker's footer tells the user Uzume never controls playback, directly above a tile for which that is false.** `connector.picker.footer` = *"Uzume reads what's playing. It doesn't control playback."* renders on `ConnectorPickerView`, which offers Apple Music, Spotify **and Local files**. On the local path Uzume owns the audio and ships a full transport — stop / previous / play-pause / next in `LocalFileTransportBar` (`uzume.playback.lfTransport`). `EXPERIENCE_MODEL.md` states the correct rule: *"Local playback owns transport; streaming handoff listens for external audio and must not promise transport control."* The claim is right for two of three sources and wrong for the third. Matt spotted it on the DS.2 M7 page. **Not fixed here** — DS.2 may not edit `connector.picker.*` copy; the wording is a product call (scope the sentence to streaming, or move it onto the two streaming tiles). |
| A11Y-001 | P3 · observed at DS.2's M7, 2026-09-01 | app.accessibility | **The three local-source tiles do not expose their own accessibility identifiers to the macOS accessibility tree — they report the parent view's.** Read live from both builds: each of the three announces `AXIdentifier = uzume.view.lf_source`, not `uzume.lf_source.tile.folder` / `.file` / `.playlist`. The connector tiles on the previous screen *do* surface theirs (as the value repeated four times, joined by `-`). **Unchanged by DS.2** — identical before on `main` and after on the branch — so it is pre-existing, not a consolidation regression. The constants exist and are unit-pinned by `SourceChoiceIdentifierTests`, but a UI test querying the LF tiles by identifier would not find them. **No root cause asserted** (BUG-061 rule): the observable difference is that `LocalSourceConnectionView` sets `.accessibilityIdentifier` on its root while the connector tiles sit inside a `NavigationLink`, but which of those actually drives it is untested. |
| DEAD-002 | P3 · **RESOLVED 2026-09-02 (DS.4) — affordance deleted** | app.view / dead-affordance | **The preparation banner's dismiss button had never appeared in a shipped build.** DS.3 recorded it; DS.4, which owns the screen, decided it: **deleted, not wired.** Every error routed to the banner either resolves itself (`previewRateLimited` auto-retries) or is the only place a still-true condition is stated (`preparationSlowOnFirstTrack`, `preparationTotalTimeout` — the reactive-mode escape), so dismissing one would hide the truth without changing it. The `onDismiss` closure, the button, `uzume.preparation.topBanner.dismiss` and `"Dismiss warning"` are gone; `StatusPlacementIdentifierTests.bannerDismiss_isRetired` pins the retirement. Detail below |
| DEAD-003 | P3 · recorded, and the code deleted (DS.3, 2026-09-01) | app.view / dead-affordance | **`FullScreenErrorView` was written as a reusable §9.1/§9.2 blocking surface and never acquired a consumer.** Zero construction sites anywhere in `UzumeApp`; the only non-doc references were its own declaration and its path in `DynamicTypeRegressionTests.viewFiles`. It duplicated `PreparationFailureView` almost verbatim — same body, icon, text block, actions, headline, and the same two severity switches — so for its whole life the app carried two copies of a blocking-failure layout and shipped one. **Deleted at DS.3** as part of the `RecoveryScreen` consolidation, which is why this is recorded as history rather than as open work: there was no behaviour to preserve because there was never any behaviour. Detail below |
| DEAD-001 | P3 · recorded not fixed (DS.2, 2026-09-01) | app.viewmodel / dead-code | **`ConnectorPickerViewModel.localFolderEnabled` is dead, and the comment above it claims a v1 gate the shipped build does not have.** Three hits, no reader: the declaration, the comment, and the test asserting its `false`. The view has enabled the local-folder tile unconditionally since GAP A (2026-05-28), and `ENABLE_LOCAL_FOLDER_CONNECTOR` — which the comment blames — gates a different thing entirely (the v2 playlist-connector scaffold in `UzumeEngine`, set in no xcconfig, not on the local-source path that ships). Left in place deliberately: deleting a property whose `false` a test asserts is a behaviour change wearing a cleanup costume, and it belongs with the connector-capability work, not a presentation increment. Pairs with the still-open **CA.3-FU-2**. Detail below |
| BUG-106 | P2 · **FIXED + LIVE-CONFIRMED 2026-08-26 (BUG106.1)** — `ml_forced=0` across a 25 ms/frame 4K session; only the felt half (Matt's eye on stem timing / new stutter) is outstanding | ml.dispatch / calibration | **`MLDispatchScheduler`'s budget is a hardcoded 14/16 ms with no resolution term, so at 4K the gate can never open.** `recentMaxFrameMs` is the WORST frame of the window and 4K's median was 17.6 ms in BUG-100's own session, so every stem dispatch defers to the 1.5–2.0 s ceiling and force-fires — against a 2.0 s stem period. Jank avoidance never happens and stems run ~a period late at 4K. ⚠ **Not** BUG-100's mechanism: the PERF.15 VL session was flat across 172 s at 4K while permanently over the same budget. Needs Matt's call between "stems on time" and "jank-free" at 4K. |
| BUG-129 | P3 · new 2026-09-11 | diagnostics / measurement | **`chain_health.json` reports `peakDBFS` exactly 0 on two consecutive sessions, and the verdict is still `clean`.** Measured: `2026-09-11T19-12-34Z` → −6.03, then `2026-09-11T19-58-15Z` → **0**, `2026-09-11T20-19-03Z` → **0**. An exact 0 is full scale, which would be clipping — yet `reasons` and `notes` are both empty and the verdict is `clean`, so either the peak is not being measured and defaults to 0, or it is measured and the clipping check does not fire on it. **Why it matters beyond tidiness:** the preset-session rule is that a fidelity/M7 closeout must cite the session's chain-health verdict, and D-184 makes a `clean` verdict the precondition for judging fidelity at all. A peak field that silently reads 0 weakens every such citation — including two M7s closed today (VL.2 and WL.11), both of which cite `clean` over a 0 peak and are flagged as such in their entries. Not diagnosed; found while checking a session before quoting its verdict. Start at `ChainAnalyzer`'s peak path and whether `raw_tap.wav` is being read at all. |
| BUG-103 | P2 · open; intermittently kills the whole parallel engine suite (the regression gate) | audio.playback / test-infrastructure | **The parallel engine suite dies with an uncaught NSException from `-[AVAudioPlayerNode play]` — console: `com.apple.coreaudio.avfaudio: 'player did not see an IO cycle'` — thrown inside `LocalFilePlaybackProvider._startLocked()` on a racing-start test thread.** `play()` reports this state as an Objective-C exception, not a Swift error; the crashing tests drive `provider.start()` from raw `Thread.detachNewThread` threads (`try?` cannot catch an NSException), so the exception unwinds off the thread and aborts the entire test process — SIGABRT, no failing test line, same suite-level presentation as BUG-078. **Fourteen `.ips` on 2026-08-25 alone (11:19–17:05), every one the identical stack:** `_startLocked()` → `-[AVAudioPlayerNode play]` → `AVAudioPlayerNodeImpl::StartImpl` → `NSException`; throwers span `LocalFilePlaybackStartRaceTests.rescheduleRacingTeardown…` (11), `SessionLifecycleChurnTests.concurrentDoubleStart…` (2), and `SessionLifecycleChurnTests.completionCallbackVsStop…` (1). **Passes in isolation** (`swift test --filter SessionLifecycleChurn`), fires only under full-suite parallel load — and it is **pre-existing, baseline-verified at merge `8cbf936a` twice** (RECON.14's check, plus a first-hand clean-worktree run at that commit while filing; found at RECON.14 while running closeout evidence). NOT the BUG-078 trap: that was `StopImpl`/dealloc `dispatch_sync` on `CommandQueue` (SIGTRAP); this is `StartImpl` at play-time (SIGABRT). Same family — AVAudioPlayerNode lifecycle under parallel scheduler load. The throw site is the SHIPPED local-file start path (and `resume()` carries a second, unproven `play()` site), so the app-facing form would be a hard crash — P2 by BUG-078's rationale. Detail below |
| BUG-091 | **P1** · instrumentation landed 2026-08-17; awaiting one reproduction | app.session / pipeline-wiring | **A single local file is selected, preparation succeeds, and NO PLAYBACK EVER STARTS — the session runs with every audio field exactly 0.0.** Matt, 2026-08-17. Measured on `2026-08-17T17-19-19Z`: 1262 frames over 84 s of render clock, and `playback_time_s` / `track_elapsed_s` / `accumulatedAudioTime` / `bass` / `mid` / `treble` / `pulse_amp01` / `beatPhase01` each hold **exactly one distinct value, 0.0**, for the whole session. Preparation is healthy — stem-cache hit, BeatGrid installed (94.1 BPM, 47 beats), plan built. **The discriminator is a diff against the working local-file session 1.5 h earlier (`16-19-13Z`, same file, same OS build):** the working run logs `WIRING: provider.start INSTANCE` and an AVAudioEngine node tap (`TAP_BUFFER: requested=1024 delivered=4410 → 10 Hz`) and NO process tap; the failed run has an identical preparation sequence with `provider.start` **absent**, an unexplained 8 s gap, and then `TAP: startCapture → createProcessTap` — the SYSTEM-AUDIO path — installed twice. `resetStemPipeline caller=other` has exactly one call site (`handleLocalFileReady`), so that function ran and cleared all three of its guards, then never reached the router start. **Root cause NOT asserted** (BUG-061's rule): the strongest candidate is the `catch` around `audioRouter.start(mode:.localFilePlayback)`, which logs to `os_log` only and calls `endSession()` → `currentSource = nil` → `startAudio()`'s LF.4 guard misses → the tap is installed and `stopInternal()` tears the provider down. **Unconfirmable from the artifacts: the app's `lfLogger` output is not retained** (`log show --predicate 'subsystem == "com.phosphene.app"'` over the window returns zero lines), which is itself the reason an 84 s silent session left no trace of its cause. Instrumentation for exactly that is now in (see below). Detail below |
| BUG-085 | P1 · HANG.1–2 complete 2026-08-05; remains open | renderer / app.hang | **App intermittently hangs hard in `CAMetalLayer.nextDrawable`; window unresponsive, force-quit required.** The live stack proves a main-thread drawable request blocked at 0 % CPU after healthy frames, but the cause remains unknown; direct render-path leakage, the capture hook, preset-swap skip, inflight semaphore, GPU completion, display sleep, and occlusion have been ruled out. **HANG.1 instrumentation is merged to `main` via PR #37 (`c54a2e7c`)**. HANG.2 completed a full-track control plus a 10 min 36 s Witchlight soak with 34,811/34,811 drawables balanced and no stalls or imbalances, refuting a deterministic per-frame leak but not identifying the intermittent owner. **THE INSTRUMENTED CAPTURE NOW EXISTS (2026-08-05, session `2026-08-05T21-21-03Z`, Fractal Tree / Cherub Rock)** — and every lifecycle counter is BALANCED at the moment of the hang: `drawable=12045/12045`, `unique_presented=6012/6012`, `command_completed=6012/6012`, `failures=0`, `unpresented=0`, one request outstanding (`pending=frame:6013,site:mesh.descriptor`). The app held ZERO drawables and CoreAnimation still would not vend one, which independently confirms HANG.2's soak: there is no app-side leak, and the owner is outside the app. Two captures 98 s apart are byte-identical on those counters — a PERMANENT block, not a long stall. See the detail section. |
| BUG-081 | P2 | app.hang | **3 instances now** (2026-08-03 ×1, 2026-08-04 ×2). | **App beachballed ~78 s into session `2026-08-03T22-54-06Z` and needed a force-quit; no `.ips` exists** (force-quit produces none) and `session.log` ends mid-normal-operation with no fatal. **Evidence-only — no root cause asserted.** What the capture DOES establish: the renderer was healthy to the last frame — steady 60 fps, Fractal Tree at **0.18 ms GPU against a 0.7 ms budget**, no degradation trend across 3756 frames; background ML load rising but modest (`stem_analyzer_ms` 0 → 3.4). **Ruled out by test:** FTR.2's shader overflowing the mesh primitive limit via a bad `branch_count` — no non-finite values in the capture and `branch_count` never exceeds 59 against the 63 ceiling. A frozen UI with a live render loop points away from the preset, but that is inference and BUG-061's rule forbids acting on it. **Same class as BUG-060** (force-quit hang, render loop died, no stack captured, never reproduced) — two instances now, both blocked on the same missing artifact. **Next evidence:** `sample UzumeApp 10 -file ~/Desktop/uzume-hang.txt` run DURING the beachball, before force-quitting |
| BUG-087 | P2 · **RESOLVED 2026-09-11 (BUG087.4) — 10.01 → 59.77 Hz observed on a real session; M7 PASSED, clock now default-on** | audio.capture / calibration | **Local-file playback runs the whole MIR chain at 10 Hz where streaming runs it at 51 Hz — a 5.1× rate loss on the primary development session type.** `LocalFilePlaybackProvider` asks for `installTap(bufferSize: 1024)` (≈47 Hz) and AVAudioEngine ignores it, delivering **0.1-second** buffers instead — 4414 frames measured at 44.1 kHz, 4808/4810 at 48 kHz. `processAnalysisFrame` runs once per audio callback with no time gate, so the callback rate *is* the analysis rate: every `FeatureVector` field — bands, deviation primitives, `beatPhase01`, centroid, flux, mood inputs — updates at 10 Hz on local files. Proven a fixed *duration* rather than a frame count by the rate-independence discriminator (both sample rates land on 0.1 s). This is the same 10 Hz the FTR program hit from the preset side. Diagnosis only — no fix code. Detail below |
| BUG-084 | P3 | dsp.stem | **`StemAnalyzer` deviation reaches 35 where the primitive's real ceiling is ~3.4** — suspected divide-by-near-zero against a not-yet-converged per-track EMA baseline (the stem-side twin of the BUG-027 / AGC2.4.1 cold-start family). No product impact today: FFO's aurora is defended by the FBS.S3.2 soft knee (35 → 1.64), which is what let BUG-041 close. Filed 2026-08-03 (RECON.2) so it survives that closure — the *input* is wrong even though the output is defended. Unreproduced; fixtures retained |
| BUG-070 | P2 | audio.capture / resource-management | **Fix landed 2026-07-12 (PUB.6), pending live validation** — a FAILED device-change tap reinstall left `_isCapturing=true` with zero callbacks: engine health detectors starved (SignalHealthMonitor.evaluate is sample-driven → deadTap never confirms) and the router's recovery restart blocked at the alreadyCapturing guard; only the app-layer poll-based stall card surfaced it. Fix: the catch now clears `_isCapturing` (recovery unblocked) and keeps the monitor as a diagnostic beacon; the false "create steps stopped the monitor" comment corrected. Residual OPEN half: the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery vs user stop) stays unserialized — static-only evidence; restructuring the G1-validated (12/12) path without a reproduced artifact is the BUG-063 pattern. Existing breadcrumbs (per-step diagnostics + install generation) are the instrumentation; serialize only if a live session shows an interleave |
| BUG-120 | **P1** · **FIXED 2026-09-08**, live-confirmed | preset.routing | **Witchlight's per-beat pulse rode BAR position, not the beat grid — so a track with no meter lost both tiers and went silent.** WL.9 is documented as two tiers, *"the steady pulse now rides the BEAT grid, which is the strong signal, while only the ACCENT rides bar position, which is the weak one"*. The code derived beat edges by SUBDIVIDING the bar (`Int(barPhase * beatsPerBar)`), so both tiers rode bar position; with `beatsPerBar == 1` there is one slot, it never changes, and the pulse never fires. Hidden while a meterless grid ramped bar phase at BEAT rate — the accent fired every beat, so it read over-eager rather than dead — and exposed the moment BUG-117 silenced that. Matt, 2026-09-08, on a session with no meter on 57 % of frames: *"Witchlight does not appear to be working."* **Fix:** the pulse tier reads `beatPhase01`, which exists whenever a grid does, so it survives a meterless track and only the bar ACCENT is withheld. Live-confirmed same day: *"Witchlight is working now."* |
| BUG-121 | **P2** · **FIXED 2026-09-08** | audio.capture / calibration | **A single quiet window graded a whole session degraded and nudged the listener that their audio levels are low.** Matt, 2026-09-08: *"in the last few sessions, I was seeing notifications that the signal source was low… this has been a problem historically, and I would like to resolve it once and for all."* Across his entire session history the flag fired on exactly **one** window — 1 of 68, 1 of 20, 1 of 34 — always a lone `band=critical` at −18 to −24 dBFS in the MIDDLE of a track, and `band=low` **never occurred at all**. Those are fades, gaps between tracks and soft intros. D-197 had already patched the version that fired on a quiet OPENING; the false positive moved into the song. **Fix:** both the toast and the verdict now require **3 consecutive** low/critical windows (~15 s at the 5 s cadence) — a misrouted chain is quiet in every window, music is not. Re-grading his real sessions flips every false positive to `clean` while the negative control (a chain quiet in every window) still grades degraded. |
| BUG-119 | **P1** · **RESOLVED 2026-09-11** — live-confirmed by Matt: *"no visible grain observed, spike punches land with the music"* | dsp.beat / preset.routing | **The beat pulse held one whole-track average BPM for a whole track, so a wrong average put every pulse-driven preset off the music.** `BeatPulseClock.setTempo` was called once per track from `grid.bpm` and never revisited; the period is `(60/bpm) x 4`. PR.12's whole-track grid changed that average substantially on real material (bleed 115.0 -> 123.6, money 116.2 -> 129.3, bohemian 78.2 -> 94.2), and a pulse running 7-20 % off drifts against the track — which is what Matt saw as **Ferrofluid Ocean looking "pixelated / grainy"**: its spike-punch regions fire off the music rather than with it. Confirmed by his own report that the grain cleared when the whole-track grid was reverted. **Fix:** the pulse now follows the grid's LOCAL period (`BeatGrid.localTiming`, published by `LiveBeatDriftTracker.lastLocalBeatPeriod`), smoothed over a few beats, re-anchoring on elapsed BEATS so the phase is continuous through a rate change. This is Matt's 2026-09-04 instruction applied where it was still being ignored: *"you should not be averaging BPM / tempo, you should be recording it over the duration of the track."* |
| BUG-118 | **RESOLVED 2026-09-08** — the revert's premise was wrong; whole-track grids are back ON | dsp.beat / measurement | **The tiled whole-track grid is WORSE than the 30 s clamp it replaced, and shipped without the five-suite table the program requires.** PR.12 switched local files to `BeatThisTiledInference` (1500-frame windows, 50 % overlap, averaged at UNIFORM weight) on a partial measurement — one metric, nine fixtures, both arms trimmed to a common span. Run properly at BUG-118 the BPM column is span-independent and damning: bleed truth 114.67, clamped **115.00**, tiled **123.62**; money 121.06 / **116.19** / 129.32; pyramid_song 66.60 / **65.08** / 82.47; yyz 272.27 / **233.61** / 145.85; bohemian 71.10 / **78.18** / 94.23. Beat F regresses on 5 of 9 (bleed 0.99 → 0.76, money 0.44 → 0.24, pyramid 0.52 → 0.22), continuity with it (bleed CMLt 1.00 → 0.56), and billie_jean's downbeat F falls 0.90 → 0.37. **The capability is still wanted** — a 30 s grid extrapolated across a whole track is BUG-065's drift — so this is a defect in the TILING, not a reason to abandon whole-track analysis. `UZUME_WHOLETRACK_GRID=1` opts back in for A/B. Prime suspect: uniform-weight averaging gives a window's poorly-conditioned EDGE frames the same weight as another window's well-conditioned middle; the standard remedy is a tapered cross-fade. Not yet confirmed. |
| BUG-117 | **P1** · open · ⚠ **the 2026-09-07 revert did NOT contain it — `beatsPerBar == 1` on 34.3 % of frames with the flag OFF** | dsp.beat / api-contract | **A declined bar estimate reports `beatsPerBar = 1`, which makes EVERY beat a downbeat.** `BeatGrid.beatsSinceDownbeat` falls back to `idx % max(beatsPerBar, 1)` when `downbeats` is empty, so "no bar information" is encoded as "every beat is bar one" — the exact opposite of declining. PR.17 shipped the windowed bar line default-ON on 2026-09-05 and this broke bar-locked motion across the roster within hours (Matt, 2026-09-07: Witchlight *"has no pulse"*, Aurora Veil *"no longer in sync"*, Fractal Tree *"too animated"*, Ferrofluid Ocean *"beat sync is worse"* — *"Everything is worse."*). Measured on session `2026-09-06T00-17-00Z`: **`beatsPerBar == 1` on 18,040 of 19,833 frames (91 %), `is_downbeat == 1` on 94 %.** The windowed estimator itself is sound (take_five 5/4 and money 7/4 decode for the first time); the DECLINE PATH is the defect, and it predates PR.17 — `applyBarLineEstimate` has encoded a decline the same way since FT.4. **Default reverted to OFF**; the mechanism stays behind `UZUME_BARLINE_LOCAL=1`. Do not re-enable until a declined track reports no bars in a way consumers can read as no bars. ⚠ **CORRECTION 2026-09-11: the revert never contained this.** `BeatGridResolver.computeMeter` returns `max(1, …)` independently of the flag, so declines occur on the DEFAULT path — measured at **34.3 % of frames** (one whole track) in session `2026-09-11T19-12-34Z`. ⚠ **And the consumer reach is SMALLER than this row implies.** A census of every `beatsPerBar` reader found the 2026-09-08 `barPhase01 = 0` hold already protects them: Witchlight's `barPeriod` only updates on a downbeat that can no longer fire, and `MeshGenerator+RenderClock` passes the pinned `barPhase01` as its measured value. Volumetric Lithograph was the sole unprotected reader, and its defect turned out to be a units error worst on a HEALTHY grid (VL.2), not this one. ⚠ Three consumers were wrongly flagged as broken first, each by reading an expression's shape without tracing its inputs. |
| BUG-116 | **P1** · **RESOLVED 2026-09-11** — live-confirmed by Matt: *"no periodic darkening, visuals are steady"*; 0 of 10,789 frames all-stems-zero on a 48 kHz session | dsp.stem / sample-rate | **On any local file that is not 44.1 kHz, the pre-analysed stem series is DEAD for ~0.4 s out of every 2 s — all four stems decay to exactly 0.000 and snap back.** Matt saw it as Ferrofluid Ocean's *"screen goes dark every few seconds"* (session `2026-09-05T18-17-12Z`, 48 kHz local files). `StemSeparator.separate` always resamples to its own 44.1 kHz and pads to 440,320 samples, so its OUTPUT is in the model's time base; `SessionPreparer.analyzeStemSeries` slices that output at offsets computed in the INPUT's rate. At 48 kHz the resampled audio fills only 404,544 of the 440,320 returned samples and the rest is zero padding — and the kept 2 s span sits at the window's tail, squarely in the padding. **A/B on the same file: 44.1 kHz → 0 of 1722 frames near-zero; 48 kHz → 279 of 1875 (14.9 %), holes at 9.62–10.01 s, 11.63–12.01 s, 13.65–14.02 s — the same frame indices as the cached series that fed Matt's session.** ⚠ **Cached entries are poisoned:** the holes are baked into `stem_series.bin` on disk, so any fix must invalidate the cache. Not caused by the 2026-09-05 merges — `SessionPreparer+StemSeries.swift` was last touched at RN.2 (a rename). **Fix:** `analyzeStemSeries` works in the separator's time base — `StemSeparating` gained `outputSampleRate` and the input is resampled once up front. 48 kHz goes 279 of 1875 near-zero frames → **0**; 44.1 kHz is bit-identical (the branch does not fire). **Cache invalidated, schema v10 → v11**, because the holes are baked into `stem_series.bin` and a v10 hit would replay them forever. Regression is parameterised over 44.1/48/96 kHz and both new tests were confirmed to FAIL against the un-fixed code. Evidence: `docs/diagnostics/BUG116_STEM_SERIES_HOLES_2026-09-05.md`. |
| BUG-115 | **RESOLVED 2026-09-08 (PR.5.2, `4d5f75ff`)** — converted to `bass_att_rel` + tanh once the fill was correct | preset.routing | **Dragon Bloom's bass breathing is an absolute threshold on AGC-normalised `f.bass` — the pattern D-026 and FA #31 ban.** `mvWarpPerVertex` reads `clamp(1.0 + 0.06*(f.bass*6.0 - 1.0), 0.97, 1.07)`; the term is only neutral at `f.bass == 1/6`, so on Bowie's *Low* (median 0.236) it sits at **1.024 median / 1.070 at p90** — a 2.4–7 % outward warp every frame against the source's 0.99951 baseline, and the response is a function of the AGC's running mean rather than of the music. **Not fixed at PR.5, deliberately:** converting the route to the signed deviation primitive `bass_rel` was measured through the production path on a real *Low* capture and made the render WORSE (clipped 0.836 → 0.868, saturation 0.265 → 0.099) — the outward push is the conveyor carrying strand colour out from the centre before the warp transfer's B-fade extinguishes it, so slowing it shrinks coverage. A correct fix has to address the fill dynamics and the routing together. Evidence: `docs/diagnostics/PR5_DRAGON_BLOOM_FIX_2026-09-05.md` §3. **Update PR.5.1 (2026-09-08, `762e8862`): the fill dynamics half has moved.** The source's `warp_18..19` dither was restored (it gates the R→G→B transfer at `(ret - 0.05)·99`, so without it pixels under 0.05 never cycle hue), taking field saturation 0.634 → 0.68–0.79 into the butterchurn oracle's 0.74–0.89 band. The falsified arm recorded here was measured against the OLD fill, where the outward push was the only thing carrying colour out before the B-fade killed it; with the transfer now firing on its own, re-running the `bass_rel` conversion is worth one attempt before this row is treated as blocked. Baseline cross-check: this row's clipped 0.836 / saturation 0.265 matches PR.5.1's independently measured 0.831 / 0.262. **RESOLVED at PR.5.2.** The re-test this note invited was run and the arm now WINS: on the 20:12 session nearWhite 0.182 → 0.091, saturation 0.396 → 0.441, clipped 0.168 → 0.150. The mechanism the original falsification missed is that the 1.024–1.070 zoom was evacuating the frame faster than the strands refilled it, and the emptied corners were then driven to black by the R→G→B fade and STUCK — below the 0.05 transfer gate no push fires, so black is an absorbing state, which the comp inverts to white. Slowing the push only looked like "shrinking coverage" while the dither was missing and the transfer could not carry colour on its own. **PR.5.4 correction:** the constant outward push itself was never the defect — the source pushes +3–5 % on most frames (BUG-122); the defects were the FA #31 routing and the uncapped 7 %. |
| BUG-122 | **FIXED 2026-09-08 (PR.5.4)** — premise corrected; **residual parked as BUG-123** | preset.render | **Dragon Bloom's feedback field drained wherever the strands were not, and on quiet passages, and the comp inverted the drained region to white — the last of Matt's "sizable presence of blinding white".** Filed as "a vertical split the reference does not have"; that premise was FALSE. Driven offline from the decoded track (render() paced by sample position, not wall clock — the pane-hidden rAF/timer throttling had made every earlier oracle time-series a single-moment sample), the butterchurn oracle's field swings top/bottom **0.30–2.59** on Seven Nation Army, harder than ours, and shows **nearWhite 0.000 through the drop** (16.5–19.5 s) where ours hit 0.448. The difference is not where the ink lands (position, coverage and colour all balanced) but whether the field stays FED: the source's `zoom *= min(1.05, max(1, max(bass,treb)))` measures at the 1.05 cap on 60 % of frames, mean **+3.15 %** — an almost always-on outward push that flows ink into unfed regions. PR.5.2 had removed ours entirely and PR.5.3 made it signed, whose inward half is itself a drain. **Fix:** an always-on outward baseline of +3 % with bass deviation to the source's 5 % cap. On the 21:12 session: nearWhite **0.000 on every sampled frame** (was 0.448 at the drop), saturation 0.52, no vertical mirroring needed. Falsified on the way: strand-alpha floors, 8-bit feedback emulation, max(bass,treb) on deviation primitives, a post-invert ceiling, and a y-mirrored strand set (fixed the symptom, not the cause). |
| BUG-123 | P3 · **PARKED (Matt, 2026-09-08: "stop and proceed with another PR increment")** | preset.render | **Dragon Bloom is still paler than the reference — a bounded tone gap, measured, not a mystery.** Same track (Seven Nation Army), same method (display, comp on): reference luma **0.37** / saturation **0.89** (offline oracle, 10–40 s); ours luma **0.57** / saturation **0.65** (22:41 session). A fifth brighter, a quarter less saturated — pale pastel where the reference is deep. The `nearWhite` metric (min ≥ 235) is BLIND to this: pale cream sits at 170–230, which is how PR.5.4 reported 0.000 white on a frame Matt read as washed out. Measure saturation and luma against the oracle, not white. Our FIELD runs roughly twice the reference's brightness; the offline oracle (`tools/dragon_bloom_reference/index.html`, `__seek`, `render({audioLevels})`) makes that one comparable number. **Scope if reopened: one increment, hard stop.** What is fixed and stays: colour (PR.5.1), the cold-start flash (PR.5.2), quiet-passage white-outs and the lost coupling (PR.5.4). |
| BUG-124 | **P2 · FIXED 2026-09-09** | dsp.analysis | **`PitchTracker` implemented only half of YIN's step 4, so vocal pitch was discarded rather than estimated — and the primitive was written off twice as "garnish" on the strength of it.** de Cheveigné & Kawahara §4: take the smallest τ below the absolute threshold, *and if none is found, take the global minimum*. `findMinimum` returned −1 instead. Because confidence is `1 − d′[τ]` and τ was only returned below the 0.15 threshold, **confidence could only be 0 or > 0.85, never in between** — 0.0 % of 1290 real frames landed strictly between, so no consumer could gate on it (Gossamer's `> 0.35` emission gate had never done anything; the tracker's own `confidenceThreshold = 0.6` was unreachable dead code). Measured on realistic separation noise the global CMNDF minimum sits at 0.159–0.167, a hair above the gate: the detector ran on a knife-edge. **Window size was measured and is NOT the lever** (2048 → 4096 moves the minimum 0.159 → 0.165, no change in detection). **Fix:** return the global minimum when no τ clears the threshold. **Seven Nation Army, production capture chain, 1290 frames:** conf > 0.35 **23.3 % → 79.9 %**; median confidence **0.000 → 0.610**; frames with 0 < c < 0.85 **0.0 % → 71.5 %**; pitch reported **23.3 % → 51.0 %**. **Recovered frames are signal:** loud-vs-quiet discrimination **+8.7 → +25.1 points**; reported pitch moves from median 76 Hz with **73 % pinned below 85 Hz** (search-range edge — the old output was largely boundary junk) to median **130 Hz**, p10 84 / p90 207, floor-pinning **25.5 %**. **Residual:** 25.5 % still floor-pinned, likely bass bleed in the separated vocal stem; not chased. Prior verdicts to revisit: this file's SPARSE/0.1 % finding and WL.1's 4.5 % "garnish" call were measurements of the defect, not of the primitive. |



| BUG-107 | **P2** · open · **ROOT-CAUSED 2026-08-27 (BUG107.2)** — not a tempo error; the offline grid only ever analyses the first ~30 s of any input | dsp.beat | **Money accelerates ~120 → ~140 → ~130 BPM across the track and the analyzer emits ONE constant tempo for the whole file, so a single grid cannot be right for all of it.** Filed as a "4 % tempo error"; the window sweep refuted that. Surfaced by re-annotating money at BUG102.2: AMLt fell 0.88 → 0.43 and CMLt rose 0.00 → 0.43 with NO engine change, because the old 60.97 reference made 116.19 look like a clean ×1.91 octave (which AMLt forgives by design) while against the true level it is a plain tempo error (which it does not). Owned by the beat-sync program (D-202). No fix proposed — the `dsp.beat` artifact obligations are unmet, see the entry. **Re-surfaced 2026-09-04 (PREP.2) with independent evidence and PARKED by Matt** pending the PREP live validation: PREP.1's per-stage timings show `beat_grid` cost is uncorrelated with track length (**r = −0.02** across 11 tracks, 113–384 s) where `mir` is **r = +0.96** — the fixed 1500-frame / 30.0 s window (`BeatThisModel.tMax`) measured from the outside, without reading the code. ⚠ **That paragraph's follow-on claim was WRONG and is retracted (same day, PR.12/#197).** It said the fix was "measured-and-rejected" on FT.4.1's bleed 115.00 → 123.62 — **a scoring artifact**: BeatBench trims the reference to each grid's OWN span, so the 30 s grid was graded on its first 30 s (the most regular part of any track) and the full-track grid on six minutes. Over an IDENTICAL span, beat F at ±70 ms is equal or better on 8 of 9 fixtures and bleed goes 0.99 → 1.00. D-210, FT.4.1 and BUG-107 all rested on that number. **The window is now fixed** on the local path (PR.12: coverage 7.6–26 % → 92–99 % for +0.26 s/track). Still open, per PR.12: streaming is untouched; no live confirmation. **`computeMeter` no longer divides by the average — PR.13 counts beats between downbeats.** **PR.17 (2026-09-05) decodes money's meter as 7 for the first time** by scoring bar position per ~80-beat window instead of per track (offline downbeat F 0.08 → 0.53); **on by default for local files** from 2026-09-05 — see [D-243]. That addresses the *bar*; money's tempo still accelerates across the track and one `bpm` still describes all of it, which is what this entry is about. |
| BUG-076 | P2 | dsp.beat | **Prep grid is window-position unstable on Bleed (Meshuggah) — a third of 30 s windows give a wrong tempo, and Spotify's preview lands on one.** CORRECTED 2026-07-30 after direct measurement (the original filing inferred a universal 3:2 mis-lock from a single session-log value; that was wrong). Measured across nine 30 s windows of the full track: six read ~115 BPM (correct — matches madmom 115.0, librosa 115.0, drums-stem 115.1), but three read 121.1 / 166.1 / 242.7 — a **2.11× spread**, including non-metrical values. `beatsPerBar` swings 2/3/4 on a 4/4 track and `barConfidence` sits at 0.14–0.64. **Control:** Billie Jean over the same windows is 116.9–117.3 with beatsPerBar 4 and barConfidence 1.00 throughout — so this is dense-transient-specific, not universal, and the existing confidence signal already flags it. The session's 174.6 was the preview excerpt landing in the unstable region. Evidence: `docs/diagnostics/BEATBENCH_BASELINE_2026-07-30.md`; reproduce with `BeatBench --audio <clip> --seconds 30`. Category-4 target for Phase DBN (a sequence decoder over the full activation timeline should not be excerpt-dependent); Phase FT removes the 30 s premise for local files | **2026-08-27 (BUG102.1): the ~115 reading is now backed by a `confirmed` ground truth** — bleed was re-tapped at the quarter note, both backends AGREE, and the grid scores F 0.99 / CMLt 1.00 against it. The BUG-102 contradiction (this row saying 115 is correct while `bleed.groundtruth.json` asserted 226.72) is resolved in this row's favour. The window-position instability itself is unaffected and still open.
| BUG-065 | P3 | dsp.beat | **Live BeatGrid phase drifts off the audible beat over a track** — the cached grid has the right BPM but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it: drift grows ~11 ms (track start) → **50–70 ms (mid/late-track)**, and **28 % of frames exceed the ~60 ms perceptual window** (evidence: session `2026-06-29T12-43-51Z`, Cherub Rock 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; lock_state=2 only 67 %-within-60 ms). **Caps how frame-locked beat-driven presets can feel** — the live example is Glaze's GLAZE.7 downbeat push (reads connected but not *tight*; tightest early, loosens as the track plays). NOT a functional break (phase is approximately right). **NEW EVIDENCE — session `2026-07-30T15-39-21Z` (Lumen Mosaic, 80.45 BPM 4/4). Matt: "feels a little laggy, otherwise working as intended." This is the strongest case yet and it is WORSE than the 2026-06-29 baseline:** **50 % of frames exceed the ~60 ms perceptual window** (baseline 28 %), `lock_state == 2` only 63 % of frames, and drift **grows monotonically across the session** — by 10 s window: **0 / 6 / 8 / 52 / 70 / 59 / 68 / 104 / 119 ms**. `grid_bpm` is rock-constant at 80.45, so the BPM is right and it is purely the PHASE slipping. Frame rate is NOT the cause and was ruled out first: p50 59.9 fps, only 0.08 % of frames below 30 fps, and `frame_cpu_ms` p50 actually IMPROVED to 11.06 (from 17.30 on `2026-07-27T16-31-01Z`). The "lag" a listener feels is the visual falling up to ~119 ms behind the audible beat late in the track, not stutter. Confirms the mechanism in the original report — the tracker BOUNDS drift without TIGHTENING it — and strengthens the case for the suggested live re-lock / cached-BPM-error correction. In scope for the beat-sync program (D-202).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is **mid-track drift convergence** — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session ⚠ **2026-09-08 — the evidence for this defect has always measured the wrong quantity.** `drift_ms` is the CORRECTION the tracker applies (`displayTime = pt + drift + shift`), not the error: it says how hard the tracker is working. The sync ERROR is the residual after correction, which `LiveBeatDriftTracker` computed for its tight-gate check and then discarded — never recorded, in a defect whose entire subject is timing accuracy. The original "0 → 119 ms across a track" reading, and my own "34 ms mean / 77 ms p90" from session `2026-09-08T15-29-59Z`, are both the correction. **Instrumented 2026-09-08:** `onset_residual_ms` now sits beside `drift_ms` in features.csv. No fix is proposed until a session with that column exists — the parking condition (D-206) required a changed GRID premise, which whole-track grids supply, but there is still no measurement of the actual error. **2026-09-08 — measured properly for the first time, and the premise does not reproduce. STAYS OPEN at Matt's call** pending live-played material. On a 544 s continuous track (LCD Soundsystem, *Dance Yrself Clean*, whole-track grid, meter 4) the RESIDUAL — the error that reaches the viewer, newly recorded as `onset_residual_ms` — is **p50 14.9 ms, p90 26.7, max 29.8, signed mean −0.1 ms, 100 % inside the ~60 ms perceptual window**, with no ramp. Meanwhile the CORRECTION (`drift_ms`) goes 0 → −153 ms at 5½ minutes → **+3 ms at the end**: it reverses, and only 26 of 54 buckets move away from zero, where a clock mismatch would move ~all 54. A bounded offset excursion the tracker absorbs, not monotonic drift. ⚠ **This entry's original evidence ("0 → 119 ms across a track") was `drift_ms`, i.e. the compensation read as the error** — the error itself was never recorded until 2026-09-08. **Open because one sequenced-electronic track is not proof for live-played material with real rubato.** The residual floor of ±15 ms is a separate question, plausibly the gap between the assumed 50 ms output latency and the Duet 3's measured 11.2 ms. |
| AUDIT-2026-06-09 | P2/P3 | audit backlog | Full-codebase audit findings not individually filed |
| BUG-060 | P3 | renderer / app.hang | App hang requiring force-quit: render loop died one frame after a `preset → Gossamer` switch (`22-10-50Z`); no stack captured. **RECURRED (Matt, 2026-08-03)** — this falsifies the "likely resolved by NACRE.2b" status, so the preset-apply race is fixed but is **not** the hang mechanism. **One clean instance 2026-09-09 (PR.18 M7, session `2026-09-09T22-36-18Z`):** a live `preset → Gossamer` switch ran 81 s / 5414 frames afterwards with `failures=0` and `unpresented=0` on every heartbeat. That is non-recurrence in ONE run and **not** evidence of a fix — the defect has always been intermittent, PR.18 touched only the fragment shader, and no mechanism was investigated. Recorded so the next occurrence is not read as a regression from the V.8 uplift. Needs a `sample`/stack capture on the next occurrence; do not re-run the non-recurrence watch |
| BUG-058 | P3 | audio.capture / resource-management | RARE intermittent: a mid-session output-device swap *occasionally* freezes the tap (`performReinstall` doesn't complete; stale-buffer freeze, not silence). G1 device-swap recovery is otherwise robust (validated 12/12, 2026-06-17); the single freeze was un-reproduced — likely a `coreaudiod`-settling transient. Instrumented |
| BUG-056 | P3 | local-file / audio | Local-file playback restarts the track from the top on an output-device change (AVAudioEngine teardown/restart, no resume-from-position) |
| BUG-055 | P2 | app.ui / permission | Silent system-audio tap after a rebuild: stale Screen-Recording grant; `CGPreflightScreenCaptureAccess` returns stale-`true` → app shows "ready", renders a flatline. **Symptom half RESOLVED 2026-06-17** (`a0a9ded`, silent-tap detector + fix-ladder card) — the app now explains the failure instead of lying. **Durable root still OPEN and externally BLOCKED** on CLEAN.2.5b: a stable signing identity needs a paid Apple Developer membership. Detector half closes on Matt's manual UX validation of the card |
| BUG-054 | P3 | dsp.key | Key detection has never been accurate enough to use — 1024-pt FFT can't resolve semitones < 1 kHz, full-mix chroma, no constant-Q. Non-load-bearing today |
| BUG-036 | P2 | audio.capture / performance | Heap allocations on the real-time audio thread (three sites) |
| BUG-028 | P2 | dsp.beat | Beat-grid live phase imperfect on ~half of tracks |
| BUG-077 | P3 | dsp.beat / api-contract | **`BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor** — the reference moves *every* downbeat prediction to the closest beat unconditionally; we discard any candidate beyond `snapFrames = 2` (40 ms). Found at DBN.1 while auditing the resolver against the paper. **Currently harmless and NOT the cause of the low downbeat F** — measured, 100 % of candidates survive the gate (median distance 0.0 ms), so nothing is being discarded today (the real cause is a near-degenerate downbeat *stream*, see `docs/design/DBN_DECODER_SPEC.md` §2.1). Filed because it is a genuine spec-fidelity divergence of the D-077 class that will bite the moment downbeat timing loosens — e.g. on a track whose downbeat peaks sit a frame or two off the beat. Fix is one comparison; do it in DBN.3 when the resolver is being touched anyway, not as a standalone change |


---

## Resolved (recent — Root Choir retirement)

---

### BUG-128 — Root Choir substituted generic warped feedback for the selected Liquid Script subject (2026-09-11)

**Severity:** P2
**Domain tag:** preset.fidelity
**Status:** Resolved by preset retirement
**Introduced:** ROOTCHOIR.3 / PR #222
**Resolved:** ROOTCHOIR-RETIRE.1 / D-249

**Expected behavior.** The live preset should be recognizably related to the selected
`Martin - liquid arrows` motion oracle without explanation: discrete pointed luminous heads
actively draw long, fine S-curves that braid and dissolve through persistent negative space.
The moving gesture, rather than the feedback canvas, must remain the primary visual subject.

**Actual behavior.** On the merged PR #222 live build, Matt reported that Root Choir is
reminiscent of Ricercar with warp added and looks nothing like the animated Martin reference.
This is consistent and concept-level, after the earlier Newton version and two Liquid Script
corrections also failed live review. The generic accumulator and warp dominate the frame; the
reference's readable arrow heads and authored drawing action do not survive as the subject.

**Reproduction steps.** Build merged commit `dc4892d3`, enable uncertified presets, play music,
and select Root Choir. Compare the live motion directly with the then-selected
`Martin - liquid arrows` animated motion oracle. The preset-local reference copy was removed with
the retired preset. Minimum reproducer: the dedicated merged review build at
`/private/tmp/uzume-root-choir-review-dd/Build/Products/Debug/Uzume.app`.

**Session artifacts.** The earlier clean sessions and production replays are recorded under
BUG-125 and ROOTCHOIR.3. They establish that the pipeline renders, stays visible, and moves, but
do not establish fidelity. The decisive artifact is Matt's M7 comparison of the merged live
build against the named animated oracle: the two do not share a recognizable moving subject.

**Suspected failure class:** `algorithm`.

**Evidence for this class.** ROOTCHOIR.3 reduced the oracle to compact seed shapes plus generic
`mv_warp` persistence. That combination produces a broad warped feedback field in Uzume's existing
visual vocabulary; it does not implement the oracle's defining head-led drawing behavior. The
design and closeout then described metric compliance as if it demonstrated visual fidelity,
creating a secondary documentation-drift defect.

**Verification criteria (written before retirement).**

- [x] Automated: the production preset count drops by one and the loader returns no descriptor
  named `Root Choir`.
- [x] Automated: no app/runtime catalog, acceptance, rubric, or visual-review test names Root Choir.
- [x] Repository: the Root Choir shader, sidecar, dedicated tests, visual references, and design
  document are removed; generic `feedback_pixel_format` implementation and regression coverage stay.
- [x] Manual-equivalent loader proof: a fresh app test host initializes with 31 presets and no
  Root Choir descriptor; final clean-build picker inspection remains the release smoke check.

**Manual validation required:** Yes — inspect the preset picker after a clean build.

**Fix scope.** Complete preset retirement (`ROOTCHOIR-RETIRE.1`), not another tuning pass. Preserve
the generic sidecar-owned `mv_warp` feedback-format capability because it has other current and
future consumers and is independently regression-tested.

---

### BUG-125 — Root Choir's radial orbit trap and uncalibrated tonal routes defeat its visual and musical premise (2026-09-09)

**Severity:** P1
**Domain tag:** preset.fidelity / renderer
**Status:** Resolved by ROOTCHOIR-RETIRE.1; generic format fix retained
**Introduced:** ROOTCHOIR.1  
**Resolved:** ROOTCHOIR-RETIRE.1 / D-249

**Expected behavior.** Root Choir reads immediately as the selected Liquid Script motion oracle: luminous arrow/leaf heads pull long fine S-curves and curled tendrils through a visible charcoal field, with enamel-hot cores, coloured rims, and persistent negative space. Bass activity changes the advection continuously and beat onsets strengthen only newly written local gestures. There is no global spin, radial particle field, white bloom, or fixed central knot.

**Actual behavior.** Matt's first live review found white particles arranged in circular rings, a muddled flower centre, an odd/disorienting spin, no understandable connection to the music, and no convincing psychedelic character. The first replacement removed those defects but failed the selected concept: Matt's 2026-09-10 review found it **VERY dark**, impossible to read, and unlike the Liquid Script reference. ROOTCHOIR.3.1 corrected that authored output, but the next live review (`2026-09-10T16-39-01Z`) was completely black: no charcoal ground or gestures were visible at any point.

**Reproduction steps.** Build ROOTCHOIR.3.1, play Metric's “Combat Baby,” cycle to Root Choir in the live 900×600 app, and observe a black drawable while playback remains healthy. Minimum live reproducer: `~/Documents/uzume_sessions/2026-09-10T16-39-01Z/`. Earlier authored-darkness reproducer: `~/Documents/uzume_sessions/2026-09-10T14-09-13Z/`. Original Newton reproducer: `~/Documents/uzume_sessions/2026-09-09T20-25-49Z/` plus `~/Desktop/Screenshot 2026-09-09 at 3.27.33 PM.png`.

**Session artifacts.** All three review captures have `clean` chain health. The black live capture presents 2,406/2,406 drawable frames with zero recorded command failures, peaks at **−0.13 dBFS**, and contains 2,901 valid feature rows; route replay reports `bassDev` firing on **53.43%** and `beatComposite` on **99.97%**. The shipped app bundle's Root Choir shader and sidecar hashes are byte-identical to the source tree. Yet replaying 900 rows from that exact capture through the headless production chain renders normally at **0.202 mean luma** (trajectory **0.18…0.21**, zero clipping/near-white). Code inspection supplies the discriminator: `PresetLoader` compiles Root Choir's warp/compose pipelines for declared linear `.bgra8Unorm`, and `MultiPassRenderHarness` allocates matching linear textures, while live `VisualizerEngine.applyPreset` falls through a display-name switch to `MetalContext.pixelFormat` (`.bgra8Unorm_srgb`).

**Current failure class:** `pipeline-wiring`. Earlier visual failures were `algorithm` / `calibration`.

**Evidence for this class.** Root Choir declares `feedback_pixel_format: bgra8Unorm`; the loader compiles all feedback-target pipelines for that exact format. The live app ignores the declaration and allocates `.bgra8Unorm_srgb` textures, while the replay honors it and renders the same session visibly. This one live/replay configuration divergence explains black live output without changing shader math or audio input.

**Verification criteria (written before the fix).**

- [x] Automated live-path configuration gate: every supported `feedback_pixel_format` maps to the same `MTLPixelFormat` in app setup as in `PresetLoader` and `MultiPassRenderHarness`; Root Choir resolves to `.bgra8Unorm`, not `.bgra8Unorm_srgb`.
- [x] Regression gate: app tests fail if mv-warp live setup ignores the sidecar's linear or HDR override; nil retains the drawable format.
- [x] Exact-session render artifact: `2026-09-10T16-39-01Z` remains visible at mean luma **0.202** (trajectory **0.18…0.21**) with no clipping or near-white output; inspected frames contain no rings, central knot, or global spin.
- [x] Automated: focused Root Choir tests pin the `direct+mv_warp` contract and a bounded, moving 96-frame production feedback loop.
- [x] Render artifact: the final real-session sequence contains no white particles, circular rings, radial field, or flower centre.
- [x] Motion artifact: `Scripts/motion_gate.sh` over 430 contiguous attached-session frames reports 0 spike transitions; 70/429 low-motion transitions are concentrated in the deliberately sparse opening.
- [x] Automated visibility: the attached-session production replay holds mean frame luma in **0.18…0.38**, with clipped share below 1% and near-white share below 2%.
- [x] Reference fidelity artifact: the comparison sheet visibly carries pointed luminous heads, fine S-curves, paired tendrils, hot cores, coloured rims, and persistent negative space. Matt's fidelity verdict remains the manual gate.
- [x] Superseded by retirement: Root Choir has no live path or M7 certification candidate.

**Manual validation required:** Yes — musical causality, psychedelic character, and comfort in motion are perceptual criteria.

**Fix scope.** One live app format resolver plus an app regression test; no shader, audio route, `FeatureVector`, or renderer pass change. The sidecar already owns this value and the loader/replay already honor it. Exact black-session replay frames: `/tmp/root-choir-163901-frames/`.

---

## Open

---

### BUG-130 — Local-file stop/pause freezes the feature vector instead of decaying to silence (2026-09-11)

**Reported by Matt**, correcting my misreading of his M7: *"Audio did not play continuously
throughout - I stopped and started playback of a local file a couple times during the session and had
silence for more than 20 seconds."*

**Expected.** Stopping playback produces silence: band energies decay toward zero and
silence-dependent behaviour (D-037 relaxed states, `nearSilent01`, any silence gate) fires.

**Actual.** The last analysed frame is retained and re-published every render frame. Measured on
`2026-09-11T21-00-42Z` (chain_health **clean**, peak 0 dBFS):

| evidence | |
|---|---|
| frozen run | frames 3041–4658 — **1617 frames / 26.9 s**, `bass/mid/treble` byte-identical |
| frozen values | `bass 0.27158  mid 0.02265  treble 0.00522  bassRel 0.10214` — all non-zero |
| `playback_time_s` | 50.7200 → 50.7307 across those 27 s — **playback genuinely stopped** |
| `time` / `wallclock_s` / `deltaTime` | advancing normally — the render loop is healthy |
| `SIGNAL_HEALTH` | a matching **28 s gap** (21:01:44 → 21:02:12): no analysis frames produced |
| `near_silent01` | 0 across all 6088 frames — it cannot fire on frozen loud values |

**Cause.** `LocalFilePlaybackProvider.pause()` pauses the player node only; nothing clears the
published features. With the tap retired for local files (BUG087.5 — the clock is the only analysis
source), a stopped clock produces no new frames and the last one persists indefinitely. This is the
stale-publisher class CLAUDE.md §What NOT To Do names: *a publisher retains its last value
indefinitely; a feature written on one path must be cleared on the complementary path.*

**Blast radius: every preset**, not just Alfvén. With local-file playback stopped, all of them see a
steady non-zero signal and keep animating as though music were playing. Anything silence-dependent is
dead on the local-file path.

**Why three M7 rounds missed it.** It makes stopped playback *indistinguishable* from playing — which
is exactly the symptom Matt reported three times ("silence state looks the same as active state") and
which I misdiagnosed twice: first as a dead tap, then as "the engine never saw silence / audio played
continuously". `SIGNAL_HEALTH` showed no silence because analysis had **stopped**, not because audio
was playing. Matt's correction located it; I had the evidence and drew the wrong conclusion from it.

**Does NOT block ALFVEN.CERT.** Alfvén's own gates are green and its silence gate is correct in the
harness from both a fresh seed and an energised field (ALFVEN.3h/.3i). It simply cannot be exercised
live on the local-file path until this is fixed, so Alfvén's silence state is recorded as
**unvalidated**, not working.

**Suggested fix.** Clear or decay the published `FeatureVector` on the stop/pause path, the
complementary write CLAUDE.md prescribes. Worth checking the streaming path for the same gap.


---

### OBS-DS6-1 — Ferrofluid Ocean blacked out mid-track during the DS.6 M7 (2026-09-03, recorded not chased)

**Severity:** P3 · **Domain:** `preset.fidelity` / Ferrofluid Ocean · **Failure class:** unknown (unverified)

**Observed:** Matt, running the DS.6 M7 on a Spotify session: *"the Ferrofluid Ocean preset blacked out at one point, unrelated to this work."* No timestamp beyond "at one point".

**Artifacts:** `~/Documents/uzume_sessions/2026-09-03T20-04-45Z/` (`session.log`, `features.csv`, `stems.csv`, `raw_tap.wav`, `chain_health.json`). Ferrofluid Ocean was the first real preset of the session (`preset → Ferrofluid Ocean` at 20:06:05Z, on "Billie Jean"). The `DRAWABLE_LIFECYCLE` heartbeats through its run report every frame presented, `failures=0`, `unpresented=0` — so the screen was black because the preset rendered black, not because frames stopped. The tap saw a near-silent window right after the preset began (RMS 0.145 at +5 s, then 0.0008–0.0012 for +6 s to +8 s, back to 0.032 at +9 s; `chain_health.json` verdict `degraded`, reason `tap_reinstalls(2)`).

**What this is and is not:** an observation. Ferrofluid Ocean is driven from continuous energy, so a black frame during three seconds of near-silence could be the preset's honest response to no energy, a wrong-phase cold start, or a genuine render defect; nothing here distinguishes them. Not chased in DS.6 (chrome only). Next step, if it recurs: the moment it happened, so `features.csv` can be read at that row against `raw_tap.wav`, and a `PresetSessionReplay` of the capture through Ferrofluid Ocean.

### OBS-DS4-1 — The detailed preparation view shows a suspiciously uniform readout on a real playlist (2026-09-02, DS.4 live run)

**Status: observed, recorded not fixed.** Found during DS.4's task 10 timing runs. **P3.**

**What was seen.** On Tunes Club TC 29 (40 tracks — ambient, techno, downtempo), the detailed
view's first ten heard tracks read **132–138 BPM** and **nine of ten read "bright"** (the happy
quadrant). A genuine spread across that playlist would show it. Evidence:
`docs/reviews/DS.4/after/live-mid-detailed.png`, `live-early-detailed.png`.

**What it is not.** Not a DS.4 rendering defect: `PreparationTrackRow` prints `TrackProfile.bpm`
and `TrackProfile.mood.quadrant` verbatim, and those come from `SessionPreparer+Analysis` — the
same 30 s-preview MIR the Orchestrator has always planned from. DS.4 made it legible for the first
time; that is the whole finding.

**No root cause asserted** (BUG-061 rule). Two candidates worth *measuring*, not assuming: the mood
scaler's valence behaviour after DYN.6.2 (BUG-066 records the flux residual; DYN.6.2 narrowed
valence spread), and the preview-window tempo instability BUG-076 documents. A third possibility is
that the playlist really is this uniform at the preview excerpt — which is why this is an
observation, not a bug.

**Why it matters for DS.4.** The detailed view's proposition is *"what Uzume heard."* If what it
heard is mostly one word and one tempo, the readout stops being interesting, and the mysterious
view's `PreparationCharacter` (mood spread, rate) has less to work with than the design assumed.
Worth its own increment before the detailed view reaches beta listeners.

---

### COPY-001 — The source picker promises Uzume never controls playback, above a tile where it does (2026-09-01, DS.2 M7)

**Status: RESOLVED 2026-09-01, on Matt's explicit go.** Footer rescoped to
*"With Apple Music or Spotify, you press play and Uzume listens. Local files it plays for you."*
Guarded by `UzumeAppTests/ConnectorPickerFooterTests.swift`, which was proven able to fail against
the old string before being trusted. Verified live: `docs/reviews/COPY-001/picker_footer_after.png`
shows the sentence true for each of the three tiles. **P2** — it was a false product claim on a
screen the user reads while deciding, not a cosmetic defect.

**The string.** `UzumeApp/en.lproj/Localizable.strings:133`

```
"connector.picker.footer" = "Uzume reads what’s playing. It doesn’t control playback.";
```

Rendered at `UzumeApp/Views/ConnectorPickerView.swift:124`, centered under all three source tiles.

**Why it is wrong for one of them.** `UzumeApp/Views/Playback/LocalFileTransportBar.swift`
(`uzume.playback.lfTransport`) ships stop, previous, play/pause and next. On the local-file path
Uzume decodes and drives the audio itself — it is the player. The footer's claim holds only for
Apple Music and Spotify, where Uzume listens to another app's output and the user starts playback
themselves.

`uzume-site`'s `EXPERIENCE_MODEL.md` already states the correct rule and the app's own footer
contradicts it: *"Local playback owns transport; streaming handoff listens for external audio and
must not promise transport control."* `COMPONENTS.md` repeats it for `LocalPlaybackTransport`:
*"available only when Uzume owns local playback."*

**Failure class:** `documentation-drift` — shipped copy asserts a product behaviour the shipped
code contradicts. No algorithm, no state machine; the string and the transport bar simply disagree.

**Reproduction:** open Uzume → "Choose music" → read the footer under the three tiles. It is
unconditional. Then pick Local files, choose any audio file, and watch `LocalFileTransportBar`
appear during playback with working stop / previous / play-pause / next. Captured on the DS.2 M7
page (`docs/reviews/DS.2/after/connector_local.png` shows the footer under the Local files tile).

**Verification criteria (written before the fix, per the defect protocol):**

1. **Automated** — a test asserting the picker footer does not contain the unqualified sentence
   `"It doesn't control playback"`, and that it names the sources the listen-only behaviour
   applies to. This is the regression guard: it fails if the blanket claim returns.
2. **Automated** — `Scripts/check_user_strings.sh` stays green (the replacement is still
   externalized, not inlined), and the app suite passes.
3. **Manual** — re-capture the picker and read the footer against all three tiles: the sentence
   must be true for each one. UX-flow validation per the protocol, since this is a
   session-lifecycle surface.

**Fix when picked up — a product call, not a mechanical one.** Options: scope the sentence to
streaming ("For Apple Music and Spotify, Uzume reads what's playing — it doesn't control
playback."); move it off the shared footer and onto the two streaming tiles; or drop it from this
screen and state each source's capability on the source's own screen, which is what
`EXPERIENCE_MODEL.md` §Add music implies (*"Each source names its actual capabilities; a source
never promises what it cannot honour"*). Belongs with DS.5 (`StreamingHandoff`) or RN.4's
public-copy wording pass.

---

### A11Y-001 — The local-source tiles do not expose their own accessibility identifiers (2026-09-01, DS.2 M7)

**Status: open, pre-existing, recorded not fixed.** **P3.**

**Observed** by reading the macOS accessibility tree of a running build, on `main` and on the DS.2
branch, with identical results:

```
role=AXButton | id=uzume.view.lf_source | desc=Folder. Read every supported file in alphabetical order
role=AXButton | id=uzume.view.lf_source | desc=Single file. .m4a, .mp3, or .flac
role=AXButton | id=uzume.view.lf_source | desc=Playlist. .m3u or .m3u8
```

Each announces the **parent view's** identifier. The connector tiles on the previous screen do
surface theirs:

```
role=AXButton | id=uzume.connector.tile.apple_music-uzume.connector.tile.apple_music-…(×4)
```

**Consequence.** `LocalSourceConnectionView.folderTileID` / `.fileTileID` / `.playlistTileID` exist
and are pinned by `SourceChoiceIdentifierTests`, but that test asserts the *constants*, not that
they reach the accessibility tree. A UI test querying the LF tiles by identifier would not find
them, and neither would assistive tooling keyed on identifier.

**Not a DS.2 regression** — byte-identical behaviour before and after the consolidation.

**No root cause asserted** (BUG-061). The visible structural difference is that
`LocalSourceConnectionView` applies `.accessibilityIdentifier(Self.accessibilityID)` to its root
`ZStack` while the connector tiles sit inside a `NavigationLink`, but which of those drives the
outcome is untested. The cheap experiment is to remove the root identifier and re-read the tree.

---

### DEAD-002 — The preparation banner's dismiss button has never rendered (2026-09-01, DS.3) — RESOLVED at DS.4

**Status: resolved 2026-09-02 (DS.4) — the affordance is deleted.** Found during DS.3's
status-placement consolidation and deliberately left in place there. **P3.**

**The decision (DS.4, D-238).** Wiring it would have required an answer to "what does
dismissing a still-true condition mean?", and the three banner errors give the same answer:
nothing good. `previewRateLimited` clears itself when the throttle lifts; `preparationSlowOnFirstTrack`
and `preparationTotalTimeout` are the only place the reactive-mode escape is offered, and the
condition they describe stays true until preparation catches up — a dismissed banner would
simply hide the one line that tells the listener what they can do. In the mysterious view the
banner is also the only status text on screen. So: **delete**. `NoticeBanner` loses `onDismiss`,
`dismissID` and the button; `a11y.preparation.topBanner.dismiss.label` leaves
`Localizable.strings`; `StatusPlacementIdentifierTests.bannerDismiss_isRetired` replaces the
pin. The banner leaves when `PreparationErrorViewModel` says the condition has, exactly as before.

**The original record follows, unchanged.**

**The affordance.** The banner component renders its dismiss button only when a non-nil
`onDismiss` closure is supplied — before DS.3 in `TopBannerView`, after DS.3 in
`UzumeApp/Views/Components/NoticeBanner.swift:50`:

```swift
if onDismiss != nil {
    Button { onDismiss?() } label: { Image(systemName: "xmark") … }
        .accessibilityIdentifier(Self.dismissID)
        .accessibilityLabel(Text(String(localized: "a11y.preparation.topBanner.dismiss.label")))
}
```

**The proof it never fires.** The component has exactly one construction site, and it
passes no closure — `UzumeApp/Views/Preparation/PreparationProgressView.swift:171`:

```swift
private var bannerSlot: some View {
    if case .banner(let error) = errorViewModel.presentationState {
        NoticeBanner(error: error)
    }
}
```

`onDismiss` defaults to `nil`, so the `if` is never entered. Verified as the only site:
`grep -rn "NoticeBanner(" UzumeApp` returns that line alone. Unchanged across DS.3 —
`TopBannerView(error: error)` at the same line before the rename.

**What is therefore unreachable.** The button; its identifier `uzume.preparation.topBanner.dismiss`;
and the localized string `a11y.preparation.topBanner.dismiss.label` = `"Dismiss warning"`,
which no user has ever heard.

**Why DS.3 did not fix it.** Two directions, both out of scope. Wiring the closure is a
**behaviour change**: the banner currently persists until `PreparationErrorViewModel` changes
state, and making it user-dismissible means deciding what happens when the user dismisses a
condition that is still true. Deleting the identifier **breaks a contract** DS.3 pinned in the
same increment (`StatusPlacementIdentifierTests`). The open question is a product one — should
a preparation banner be dismissible? — and it belongs with DS.4's preparation-stage rebuild,
which owns this screen.

**Related:** DS.3 task 8; `StatusPlacementIdentifierTests.bannerDismiss_hasExpectedID`, which
pins the identifier and carries a comment pointing here.

---

### DEAD-003 — `FullScreenErrorView` shipped for months with no consumer (2026-09-01, DS.3)

**Status: recorded, and the code deleted.** Not open work — the file is gone. Kept as history
because the census listed it as an active duplicate, and the correction is worth having on
record. **P3.**

**The claim, and the evidence.** `UzumeApp/Views/FullScreenErrorView.swift` declared
`struct FullScreenErrorView: View` (line 18) with a documented construction example in its own
header (line 7) — and nothing ever constructed it. At the DS.3 branch point,
`grep -rn "FullScreenErrorView" UzumeApp UzumeAppTests` returned exactly five hits:

| Hit | What it was |
|---|---|
| `UzumeApp/Views/FullScreenErrorView.swift:1, 7, 14, 18` | its own header comment, usage example, `MARK`, and declaration |
| `UzumeAppTests/DynamicTypeRegressionTests.swift:35` | its **path**, as a string in the fixed-font ratchet list |

No call site, in any view, view model, or test.

**What it cost.** It duplicated `PreparationFailureView` almost verbatim: identical `body`,
`icon`, `textBlock`, `actions` and `headline`, and byte-identical `severityIcon` and
`severityColor` switches — including both copies of the `degradation → .yellow` mapping that
was half of DS.3's conflict 1. Two copies of a blocking-failure layout, one of them shipped.
Because the ratchet at line 35 named it, the file was also being *maintained* — kept free of
fixed fonts — for a screen no user could reach.

**Why it was safe to delete.** A view with no construction site has no behaviour to preserve.
This is the reason DS.3's `RecoveryScreen` consolidation carried zero behavioural risk on that
half: the surviving layout is `PreparationFailureView`'s, reached through the same
`PreparationProgressView` `.fullScreen` branch, with the same three accessibility identifiers.

**The census was wrong about this.** `PHOSPHENE-COMPONENT-CENSUS.md` lists both full-screen
views as sources for `RecoveryScreen` without distinguishing the live one from the dead one,
and `APP_VIEWS.md:440` marks `FullScreenErrorView.swift` **`production-active`**. Recorded in
`docs/reviews/DS.3/UPSTREAM-FINDINGS.md`.

**Related:** DS.3 task 4 and task 8; [D-234].

---

### DEAD-001 — `ConnectorPickerViewModel.localFolderEnabled` is dead, and its comment claims a gate the shipped build does not have (2026-09-01, DS.2)

**Status: open, recorded not fixed.** Found during DS.2's tile consolidation. Deliberately
left in place — deleting a property whose `false` a test asserts is a behaviour change wearing
a cleanup costume, and it belongs with the connector-capability work, not a presentation
increment. **P3.**

**The property.** `UzumeApp/ViewModels/ConnectorPickerViewModel.swift:29`

```swift
/// Whether the Local Folder connector tile is enabled.
let localFolderEnabled: Bool = false
```

**The comment**, same file, line 8:

```
// - localFolderEnabled is false in v1; ENABLE_LOCAL_FOLDER_CONNECTOR compile flag gates it.
```

**Why both are wrong.**

1. **The property has no consumer.** `grep -rn "localFolderEnabled" UzumeApp UzumeAppTests`
   returns three hits and no reader: the declaration, the comment above it, and the test that
   asserts its value. No view branches on it.
2. **The view has enabled the tile unconditionally since GAP A (2026-05-28).**
   `ConnectorPickerView.localFolderTile` builds a plain `NavigationLink` to
   `LocalSourceConnectionView` with no reference to the flag. The comment above it says so:
   *"tile is now enabled — LF.5 shipped 24h prior."* So the comment's claim that the Local
   Folder tile is gated in v1 is false about the build that ships.
3. **The compile flag gates something else entirely.** `ENABLE_LOCAL_FOLDER_CONNECTOR` wraps
   the body of `UzumeEngine/Sources/Session/LocalFolderConnector.swift` — the v2 *playlist
   connector* scaffold, never the tile — and is set in no xcconfig or `Package.swift`
   (CA.3 already recorded this: `docs/CAPABILITY_REGISTRY/SESSION.md` §stub). The local-source
   path that actually ships does not go through that class at all; it goes through
   `LocalFileMenuCommands` and `NSOpenPanel`.

**What pins it in place.** `UzumeAppTests/ConnectorPickerViewModelTests.swift:16-20`

```swift
@Test("localFolderEnabled is false by default (v1)")
func localFolderEnabledIsFalse() {
    let vm = ConnectorPickerViewModel()
    #expect(vm.localFolderEnabled == false)
}
```

The test passes and will keep passing; it asserts a constant no product code reads. Removing
the property means removing this test in the same commit.

**Fix when picked up.** Delete the property, the test, and the line-8 comment together, and
decide `LocalFolderConnector.swift`'s fate at the same time — that is the still-open
**CA.3-FU-2**, blocked on Matt's delete-vs-keep call. The two are the same question asked at
two layers, and answering one without the other leaves the other still claiming a gate.

---

### BUG-106 — FIXED (BUG106.1): the ML dispatch gate compared against a hardcoded 14/16 ms, so at 4K it could never open (2026-08-26)

**Status: fixed 2026-08-26, pending one live 4K confirmation.** Matt chose **(a) stems on time**
the same day. The budget now follows the session's own median frame time with the tier constant
as a floor — `max(floorMs, median × 1.5)`, `MLDispatchScheduler.budgetMs`. 1080p is unchanged
(median ≈ 8 ms → the floor wins, so the gate behaves exactly as it did at the only resolution it
ever worked at); a steady 25 ms 4K session now budgets 37.5 ms and dispatches instead of
deferring; a 60 ms spike inside that same session still defers. The threshold is now a deviation
from what this session delivers rather than an absolute millisecond count — the same correction
the audio side made for deviation primitives (D-026 / FA #31).

**Original status: root-caused statically, fix was a product decision.**
Found while working BUG-100; filed separately because it is a defect on its own terms whether or
not it turns out to be part of that entry's degradation.

**Expected.** `MLDispatchScheduler` (D-059) holds the ~142 ms MPSGraph stem separation until
recent frames are inside the render budget, so ML inference does not land on a frame that is
already struggling. Deferral is the exception; a clean window is the norm.

**Actual, at any 4K render target.** The gate is inoperative — it can only ever defer, then
force-dispatch. The chain is static and each link is in the tree today:

1. `VisualizerEngine+Stems.swift:192` — `let budgetMs: Float = self.deviceTier == .tier1 ? 14.0 : 16.0`. **A constant. No resolution term.**
2. `MLDispatchScheduler.decide` requires **every** frame in a 20–30 frame window to be ≤ that budget.
3. The number it compares is `FrameBudgetManager.recentMaxFrameMs` — the **worst** frame in the window, itself `max(cpuFrameMs, gpuFrameMs)` (`FrameBudgetManager.swift:207`).
4. At 3840×2160 the *median* frame in BUG-100's own session was **17.6 ms rising to 44.9 ms** — so the worst frame in any window is never ≤ 16 ms.

⇒ every dispatch defers in 100 ms steps until `pendingForMs` crosses the ceiling
(2000 ms tier 1 / 1500 ms tier 2), then force-fires anyway. **Against a 2.0 s stem period**
(`stemSeparationPeriodSeconds`), so deferral consumes 75–100 % of the period: the next dispatch
is requested at about the moment the previous one is forced. The jank avoidance never happens,
and every stem update at 4K is roughly one whole period later than designed — which compounds
with **BUG-086**'s structural stem latency rather than replacing it.

**Reproduction.** Static; no session needed. Any 4K fullscreen session is the live form — with
the BUG100.1 instrument in, `GPU_PRESSURE … ml_forced=N` climbing by ~one per 2 s is this defect
running.

**Suspected failure class:** `calibration` — a threshold that was correct for the only resolution
the app had when it was written, and was never made a function of the target it describes.

**⚠ What this does NOT explain, stated up front.** It is tempting to hand this to BUG-100 as the
mechanism. **One recorded session refutes that on its own:** the PERF.15 Volumetric Lithograph
run held **flat across 172 s at 4K with p50 ≈ 31 ms** — permanently over the same 16 ms budget,
so forced dispatch was happening there too, and nothing degraded. Forced ML dispatch is therefore
**not sufficient** to produce BUG-100's ramp. Treat the two as separate until a session with
`ml_forced` recorded says otherwise. (This is the BUG-090 failure shape: a mechanism that
predicts the direction of an effect is not an explanation of its magnitude.)

**The fix is a product decision, not an engineering one.** At 4K the app cannot have both:

- **(a) Stems on time** — scale the budget to the real frame target (the vsync interval, or the measured median), so the gate opens normally at 4K. Stem-driven visuals stay current; the 142 ms inference lands on frames that are already over budget, so 4K may show occasional stutter.
- **(b) Jank-free** — keep the fixed budget. 4K stays smoother, and every stem-driven behaviour stays a beat behind — which is what happens today, undocumented.
- **(c) Resolution-aware policy** — (a) below some pixel count, (b) above it.

Recommendation was **(a)**, and **Matt chose (a) on 2026-08-26**. One correction made during
implementation: deriving the budget from the *display's refresh interval* — what the
recommendation actually said — would not have worked. At 60 Hz that interval is 16.7 ms, so a
4K session at 17–45 ms still never clears it and the gate stays shut. The budget has to follow
what the renderer actually delivers at this resolution, which is why the shipped form is
`max(tierFloor, sessionMedian × 1.5)`.

**Verification criteria (written before the fix).**
- [x] A live 4K session logs `ml_forced` **flat** (normal dispatch) after the fix, where before it climbed ~one per 2 s. **CONFIRMED — session `2026-08-26T22-04-58Z`:** 3840×2160, Witchlight, 82 s in one preset at one resolution, `frame_cpu_ms` p50 **25.1–25.8 ms** throughout — i.e. permanently over the old 16 ms constant, the exact condition that used to shut the gate. Every one of the 10 `GPU_PRESSURE` lines reads `ml_forced=0 ml_last=dispatchNow`. The gate was genuinely exercised: `STEM_SEPARATION` fired every 2.0 s at 270–474 ms inference across the whole session, and all four stem energies are non-zero on all 6,545 frames.
- [x] A 1080p session is unchanged — the tier floor decides there, proven by `budget_at1080p_isUnchangedByTheFloor` (median 8 ms → budget stays 14/16, and an 18 ms frame still defers).
- [x] Unit: a 4K-shaped history (median 25 ms, worst 27) returns `.dispatchNow` under the derived budget, and the same window against the old 16 ms constant still returns `.defer` — the case proves it bites. A genuinely janky 4K window (worst 60 ms) defers. `budget_atFourK_steadySessionDispatchesInsteadOfDeferring`, `budget_atFourK_genuineJankStillDefers`.
- [x] The median is robust to one hitch (a mean would raise the bar the next dispatch is judged against): 29 × 25 ms + one 200 ms hitch → median 25.0, max 200. `recentMedianFrameMs_isRobustToASingleHitch`.
- [ ] Manual (musical feel): stem-driven presets at 4K read *with* the music rather than behind it, and Matt's eye on whether any new stutter is acceptable. ⏳

**Related:** BUG-100 (found during it, NOT established as its cause — see above), BUG-086 (stem
latency, compounds), D-059 (the scheduler's rationale), BUG-090 (the reasoning trap this entry
declines).
### BUG-103 — Parallel engine suite dies on an uncaught NSException from `AVAudioPlayerNode.play()`: 'player did not see an IO cycle' (2026-08-25)

**Severity:** P2 · **Domain tag:** audio.playback / test-infrastructure · **Status:** Open — diagnosed to the throw site from on-disk crash reports; the AVFAudio-internal trigger condition is a hypothesis. No fix code (evidence-before-implementation).
**Introduced:** Pre-existing — reproduces at merge `8cbf936a` with no other changes, verified twice independently on 2026-08-25: the RECON.14 baseline check, and a first-hand full-suite run in a clean worktree at that exact commit while filing this entry (crash at 17:00, `.ips` `…-170015`). First *filed* here; the class was previously visible only as BUG-078's SIGTRAP sibling.

P2 by BUG-078's rationale: only ever observed killing the *test* process, but the throw site is the shipped local-file start path — `LocalFilePlaybackProvider._startLocked()` — so the app-facing form would be a hard crash during local-file playback start. Process impact is real even at P2: it takes down the whole parallel suite run (the regression gate) intermittently, presenting as a suite-level abort with **no failing test line**.

#### Expected behavior

`swift test --package-path UzumeEngine` completes; a provider `start()` that cannot begin playback surfaces as a thrown Swift error (which the racing tests already tolerate via `try?`), never as process death.

#### Actual behavior

The test process dies with SIGABRT (`abort() called`) from an uncaught Objective-C NSException. Console output at the kill shows `com.apple.coreaudio.avfaudio: 'player did not see an IO cycle'`. Intermittent, but frequent under full-suite parallelism on 2026-08-25: **fourteen `.ips` reports in one day** (11:19–17:05), across repeated RECON.14 closeout runs, two baseline checks, and the BUG103.0 evidence run. Passes in isolation (`swift test --filter SessionLifecycleChurn` — clean). **Both manifestations can occur in one run:** the BUG103.0 evidence run (17:02–17:05) failed `completionCallbackVsStop_abbaShape` on its 5 s watchdog at a `provider.start` step AND then died — its swift-testing helper (procLaunch 17:03:31) aborted at 17:05:15 with the same `StartImpl` stack, thrower `rescheduleRacingTeardown…` (`.ips` `…-170525`, the fourteenth). RECON.14's "crashed **or failed**" phrasing covers both faces of the same stall; the evidence script's extracted summary line came from the XCTest half and shows how the kill hides behind a passing-looking count (the BUG-078 exit-code-without-failure lesson again).

#### The mechanism, read from the stack (established)

All twelve reports carry the **identical** `lastExceptionBacktrace`:

```
+[NSException exceptionWithName:reason:userInfo:]
AVAudioPlayerNodeImpl::StartImpl(AVAudioTime*)
-[AVAudioPlayerNode play]
LocalFilePlaybackProvider._startLocked()          ← LocalFilePlaybackProvider.swift:327
closure #1 in LocalFilePlaybackProvider.start()   (inside lock.withLock)
LocalFilePlaybackProvider.start()
closure … in <racing-start test>
__NSThread__block_start__                          ← raw detached thread
```

Three facts compose into the process kill:

1. `_startLocked()` runs `try engine.start()` then `player.play()`. `engine.start()` failures are Swift-catchable; **`play()` reports failure as an ObjC NSException** — AVFAudio's `StartImpl` guard for a player asked to start when the engine has not completed an IO cycle.
2. The crashing tests drive `provider.start()` from **raw `Thread.detachNewThread` threads** with `try?` — which catches Swift errors only. No frame on a raw thread can catch an NSException.
3. An NSException unwinding off a pthread with no handler terminates the process. Hence SIGABRT with zero test failures recorded — the BUG-078 presentation (exit-code-without-failure), different signal.

**Which test the runner names is not load-bearing.** The 11/2/1 split (`rescheduleRacingTeardown_neverArmsACommandOnAReleasedNode` / `concurrentDoubleStart_serializesWithoutDeadlock` / `completionCallbackVsStop_abbaShape`) reflects which racing-start test's thread threw; RECON.14's console tails additionally attributed crashes to `transportChurn_…`, `completionCallbackVsStop_…`, and `onFileEnded_…` while they were in flight in the parallel set. The authoritative attribution is the `.ips` exception backtrace, and it is `_startLocked()` in all fourteen retained reports — the churn tests included: the 17:00 report's thrower is `completionCallbackVsStop_abbaShape`'s watchdogged thread.

**The first-hand reproduction adds a sequencing observation (one run — treat as observed-once, not the mechanism).** In the 17:00 crash, `completionCallbackVsStop_abbaShape` first FAILED its 5 s watchdog on `provider.start cycle 4` ("main-thread-hang class … stuck thread is leaked"), the suite moved on (`onFileEnded_queueAdvanceChurn` had started, per the console), and THEN the process died with the exception thrown from that test's watchdogged `provider.start` thread. So in this instance the sequence was: `start()` stalls > 5 s under load → the watchdog abandons and leaks the thread → the leaked thread eventually reaches `player.play()` on an engine that never began cycling → uncaught NSException. The stall-then-throw shape favors candidate (a) below (IO-thread starvation), and means the watchdog's deliberate thread-leak policy — correct for reporting hangs — leaves a live thread positioned to kill the process minutes later.

#### What is NOT established

- **Why the engine has not seen an IO cycle at `play()` time.** Two candidate shapes, not separated: (a) under a CPU-saturated parallel run, `engine.start()` returns while the HAL IO thread is starved and has not yet rendered a cycle; (b) the engine is stopped out from under the provider between `engine.start()` and `play()` (device contention / config change from the many concurrent AVAudioEngine instances other suites create). Isolation-pass vs parallel-fail is consistent with both.
- **Whether `resume()` (`LocalFilePlaybackProvider.swift:251`) ever fires this.** It is the only other `play()` site and `transportChurn` hammers it from detached threads, but no retained report shows it. Same class; unproven.
- **Provenance of the individual `.ips`:** report paths are anonymized (`/Users/USER/Documents/*/UzumeEnginePackageTests`), so the reports cannot distinguish which checkout ran. The RECON.14 session's runs and its baseline check at `8cbf936a` are the provenance.

#### Reproduction

1. `swift test --package-path UzumeEngine` (full parallel suite; tempo fixtures present — in a worktree run `Scripts/link_fixtures.sh` first).
2. Intermittent; on 2026-08-25 it fired in most closeout attempts. On a kill, `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-*.ips` gains a report whose `lastExceptionBacktrace` names `StartImpl`.
3. Control: `swift test --filter SessionLifecycleChurn` passes clean.

**Minimum reproducer:** none deterministic yet — needs full-suite load (the BUG-078 lesson repeats: the churn/race tests enter the window; parallel load springs it).

#### Session artifacts

`~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-08-25-{111953,114756,115256,151059,155635,160241,160558,160917,161743,162300,162849,164635,170015}.ips` — all SIGABRT, all the `StartImpl` exception backtrace. The `170015` report is the first-hand baseline reproduction (worktree at `8cbf936a`, fixtures linked); its console carried the full first-throw stack and the reason string verbatim: `*** Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio', reason: 'player did not see an IO cycle.'` (n/a for features.csv etc. — no session surface.)

#### Suspected failure class

`api-contract` — a shipped code path calls an AVFoundation API whose failure mode is an ObjC exception Swift cannot catch, from contexts (raw test threads; in-app, the MainActor) where an escape is fatal. The *trigger* is parallel-test load (`test-isolation`-shaped), but serializing tests would only hide the contract gap; the class that fits the defect is the contract.

#### Verification criteria (written before any fix)

- [ ] Automated: full parallel engine suite, 5 consecutive runs, exit 0, `~/Library/Logs/DiagnosticReports` gains no `swiftpm-testing-helper` `.ips`. (Same lottery caveat as BUG-078: the streak is supporting evidence, not the load-bearing signal.)
- [ ] Automated: a deterministic gate proving the start path cannot abort the process when the engine is not cycling at `play()` time — e.g. a test that forces the engine-not-running state at the `play()` call and asserts `start()` throws a Swift error (or recovers) rather than dying. Per the deterministic-over-budget-widening rule, the fix must not be "retry with sleeps."
- [ ] Manual: none required for the test-process defect. If the fix touches the shipped start path, one app-level local-file session with start / Next-churn / quit (the BUG-078 manual shape).

#### Fix scope

Contained to `LocalFilePlaybackProvider`'s start path, but the design needs care: any guard must respect the BUG-021 lock constraints (no AVFoundation teardown under the provider lock) and must not reintroduce the BUG-078 windows. Candidate directions, undesigned: check `engine.isRunning` after `engine.start()` and surface a Swift error; or bridge the `play()` call through an ObjC exception catcher so the failure is reportable. Test-side serialization of audio-hardware suites is a mitigation, not a fix — the contract gap ships.

#### Related

- BUG-078 (same family — AVAudioPlayerNode lifecycle under parallel scheduler load; different throw site, different signal, resolved 2026-08-10)
- BUG-021 / BUG-059 (the lock-ordering constraints any fix must preserve)
- `SessionLifecycleChurnTests`, `LocalFilePlaybackStartRaceTests` (the racing-start tests that enter the window)
- RECON.14 (found while running its closeout evidence; not introduced by it)

---

### BUG-107 — money's prep grid is 4 % slow (116.19 vs 121.06), masked until the reference was fixed (2026-08-27)

**Status: open. Premise CORRECTED 2026-08-27 (BUG107.1) by the BUG-076 window sweep — the
original "4 % tempo error" framing is refuted and retained below only for the reasoning trail.**
Still no code changed.

**✅ ROOT CAUSE (BUG107.2, 2026-08-27) — the offline beat grid is structurally scoped to the
first ~30 s of any input, however long.** Diagnosis increment: no fix code, no behavioural change.

**The chain, each link verified:**

1. `BeatThisModel.tMax = 1500` frames — its own comment reads *"Fixed sequence length — covers
   ~30 s at 50 fps (hop=441, sr=22050)"*. Documented architecture (`ARCHITECTURE.md` §Beat This!
   transformer), not a hidden bug.
2. `DefaultBeatGridAnalyzer.analyzeBeatGrid` calls `model.predict` **once**, with no tiling. Any
   input longer than ~30 s is therefore silently truncated — no warning, no log line.
3. `PreviewAudio.fromLocalFile` reads `file.length`, i.e. **the whole track**. So on the
   local-file path the analyzer is handed a full song and uses its opening 30 s.
4. On the streaming path this is a no-op: the Spotify preview is 30 s by construction.
5. **FT.1 (2026-07-31) already built sliding-window tiling**, with a parity test showing
   sub-window input is byte-identical to a single `predict`. The capability to do better exists
   and is simply not wired into this analyzer.

**Direct measurement** — the full file and a 30 s clip produce identical output:

| input | analysed | reported bpm | beats returned | grid actually covers |
|---|---|---|---|---|
| money.wav, whole file | 380.3 s | 116.19 | **51** | ~26 s (51 × 0.5164 s) |
| money.wav, 0–30 s clip | 30.0 s | **116.19** | **51** | ~26 s |
| bleed.wav, whole file | 442.5 s | 115.00 | **58** | ~30 s (58 × 0.5217 s) |

51 beats is what ~26 s of a 116 BPM track contains; a 380 s track at that tempo contains ~735.

**Why money looked like a 4 % error.** Its tempo rises ~17 % across the track, so the opening
30 s is the *least* representative window in the song. The grid reports 116.19 — a correct
reading **of the opening** — and has no beats at all past ~26 s. In `offline-grid`, `gridSpan` is
then ~0–26 s, `refInSpan` clips the 90 s ground truth down to that, and the reported F / CMLt
describe roughly 26 seconds of a 380-second track. Nothing was 4 % slow; the number was
answering a different question than the column header implied.

**⚠ This also scopes BUG102.1's headline.** bleed's F 0.99 / CMLt 1.00 is a real result **over
its first ~30 s**, not over the full track — its ground truth was extended full-length by madmom
but the grid was never longer than 30 s. The conclusion there ("Phosphene's grid was right, suite
4 was never a tracking problem") stands for the opening of the track and should be quoted with
that scope.

**Product consequence, which is the part that matters.** For a **local file** the beat grid is
derived from the first 30 s of the whole song, and nothing in the code or the logs says so. That
is newly relevant: LFSTEM.1 has just moved local-file *stems* to a full-file series sampled by
playback position, so stems now span the track while the beat grid still does not. Any preset
consuming bar position on a local file whose tempo moves is running on an opening-30 s estimate.

**Explicitly NOT determined here** (and not to be assumed): whether wiring FT.1's tiler into
`DefaultBeatGridAnalyzer` improves anything musically. FT.1's own result was that 13–25× more
context *recovered no odd meter and regressed bohemian*, so more context is not automatically
better. Any fix increment starts from that finding, carries a five-suite before/after BeatBench
table per the benchmark obligation, and ships behind an env flag with a one-increment A/B path
(program house rule, plan §4).

---

**Superseded framing (BUG107.1) — retained for the trail:**

**⚠ What the sweep actually found: money has real tempo drift, and the analyzer emits one
constant tempo per file.** 30 s windows stepped across the track, against both reference
backends measured over the same spans:

| span | librosa | madmom | Uzume 30 s window |
|---|---|---|---|
| 0–60 s | 119.68 | 120.00 | 116.19 (@0 s) · 121.05 (@30 s) |
| 60–120 s | 125.00 | 125.00 | 124.25 · 125.59 |
| 120–180 s | 125.00 | 125.00 | 126.27 · 125.68 |
| 180–240 s | 133.93 | 136.36 | 134.24 · 136.27 |
| 240–300 s | 137.20 | 139.53 | 135.37 · 140.19 |
| 300–360 s | 130.81 | 130.43 | 129.73 · 129.82 |

**Windowed, Uzume tracks the references closely at every point in the track.** Matt's own
taps corroborate the shape independently — in 20-tap blocks they run 120.3 / 118.0 / 121.1 /
121.4 / 120.5 / 122.7 / 122.3, i.e. rising across the tapped span. Three independent sources
agree the track speeds up by ~17 %.

**So this is not a 4 % tracking error.** It is a *category* mismatch, in three parts:

1. `DefaultBeatGridAnalyzer` returns a **single scalar BPM for the whole file**. Given money's
   380 s it returns 116.19 — which is exactly the 0–30 s window value, i.e. the opening tempo,
   not a mid-range compromise.
2. money's **ground truth spans only its first 90 s** (4.39–89.97 s), so the reference itself
   describes the opening tempo, not the track.
3. `offline-grid` scores that one constant grid against the reference wherever both exist. A
   constant grid over a track that accelerates 17 % can only be right for part of it, which is
   what CMLt 0.43 looks like: tracked early, lost later.

**The suite-2 AMLt 0.88 → 0.43 movement recorded at BUG102.2 stands as a fact** — the octave
error was real and its removal is what exposed this — but the *reason* is tempo drift, not a
tracking defect at a fixed tempo.

**Open questions this raises, which are bigger than the original filing.**

- **money is probably a suite-3 case, not just suite 2.** Suite 3 is "mid-song tempo changes",
  and D-205 **deferred** its targets "until FT + session-replay". If money belongs there, suite
  2's gate should not be judged on it in its current form.
- **Should a 90 s ground truth score a 380 s grid at all?** bleed's truth was extended to the
  full track by an agreeing backend; money's could not be, because the backends disagree on
  phase and the taps were kept (BUG102.2). A short truth against a long grid is not obviously a
  fair comparison.
- **Does the grid lay uniformly-spaced beats, or adapt within the file?** Not determined here —
  the sweep only shows the reported scalar. This is the first thing to establish in a diagnosis
  increment, and it decides whether the fix is "emit a time-varying grid" or "re-scope the
  benchmark comparison".

**How this differs from BUG-076.** BUG-076 is *window-position instability* on bleed — a third
of 30 s windows give a wrong tempo, spread 2.11×, with no musical trend. money's sweep is a
**monotonic ramp that all three sources agree on**. Same method, opposite diagnosis: bleed's
windows disagree with each other and with the truth; money's windows agree with the references
and with each other, and disagree only with the single whole-file number.

---

**Original filing, refuted — retained for the trail:**

**Expected.** `DefaultBeatGridAnalyzer` returns a grid BPM within the F-measure tolerance of the
track's true tempo. money's ground truth, re-tapped and arbitrated at BUG102.2, is **121.06 BPM,
meter 7** (tempo ratio ×1.01 against both librosa and madmom, which read 122.28 / 122.45).

**Actual.** The grid reads **116.19 BPM** — 4.0 % slow. Scored against the corrected reference:

| | F | Cemgil | CMLt | AMLt |
|---|---|---|---|---|
| against the old 60.97 reference | 0.58 | 0.43 | 0.00 | **0.88** |
| against the corrected 121.06 reference | 0.44 | 0.31 | 0.43 | **0.43** |

**Nothing in the engine changed between those rows.** The metric stopped being fooled: 116.19 is
×1.906 of 60.97, near enough to a clean octave that AMLt — which accepts double/half by design —
scored it 0.88. Against the true level it is not an octave relationship at all, so nothing
forgives the 4 %. This is why the defect was invisible: **the benchmark reported a confident,
passing-looking number in the wrong direction.**

**Reproduction.** Deterministic, offline, no session required:

```
cd UzumeEngine && swift run BeatBench --mode offline-grid --tracks money
```

Reads `money.groundtruth.json` (`status: arbitrated_taps`, 121.06 BPM) and the fixture at
`$BEATBENCH_FIXTURES_DIR/money.wav`.

**Suspected failure class:** `algorithm` (tempo estimation), *not* `calibration` — the error is a
period error, not a phase offset. Note that money's taps also carry a separate systematic −45 ms
phase offset against both backends, which Matt arbitrated in the taps' favour at BUG102.2; that
is a distinct question from this one and is settled.

**Artifact obligations NOT yet met** (`dsp.beat`, per the defect-handling protocol): this entry
has BeatBench before/after, which is the required evidence substrate, but **not** the
`features.csv` beat-sync columns (`lock_state`, `grid_bpm`, `drift_ms`, `barPhase01_permille`),
the SpectralCartograph mode label, or a `BeatSyncSnapshot` from a real session including the
Love Rehab 125 BPM minimum. Those are required before any fix increment opens.

**Open questions for whoever picks this up.**

- Is 116.19 stable, or is it the window-position instability BUG-076 documents on bleed showing
  up on a second track? BUG-076's method (`--audio` over an ffmpeg window sweep) answers this
  directly and cheaply, and the answer changes the diagnosis completely.
- Is money's 7/4 implicated? solsbury_hill is also 7 and reads 102.68 against a 102.44 truth —
  0.2 % — so odd meter alone does not predict the error.
- Does it survive to the live path, or is it confined to the prep grid?

**Related.** Owned by the beat-sync program (D-202). Suite 2's ratified baseline must now be
quoted as AMLt 1.00 / 1.00 / **0.43** / 0.75 / 0.21, not 0.88 — see BUG-102 and
`docs/diagnostics/BEATBENCH_BASELINE_2026-08-27.md`.

### BUG-091 — A single local file selected: preparation succeeds, playback never starts, every audio field is exactly zero (2026-08-17)

**Status: instrumentation increment landed. Root cause NOT asserted — one reproduction with the
new breadcrumbs will name the branch.**

**Expected.** Selecting one local file plays it: `LocalFilePlaybackProvider` starts via
`audioRouter.start(mode: .localFilePlayback(url))`, the AVAudioEngine node tap feeds the chain
(BUG-087: ~10–16 Hz on this path), `playback_time_s` advances, and no Core Audio **process** tap
is installed.

**Actual** (`2026-08-17T17-19-19Z`, *03- Carry The Zero.flac*): 1262 frames / 84 s of render
clock, and every audio-derived field holds **exactly one distinct value, 0.0**:

| field | distinct values | value |
|---|---|---|
| `playback_time_s`, `track_elapsed_s`, `accumulatedAudioTime` | 1 | 0.0 |
| `bass`, `mid`, `treble`, `pulse_amp01`, `beatPhase01`, `spectral_level_rise` | 1 | 0.0 |
| `time` (render clock) | 1262 | advances normally |

So this is not a frozen playback clock with audio flowing, nor a stalled renderer: **no audio
samples ever reached the analysis chain.**

**The discriminator — a working session 1.5 h earlier, same file, same OS build (26.5.1 / 25F80).**

| | `16-19-13Z` (works) | `17-19-19Z` (fails) |
|---|---|---|
| preparation, BeatGrid, plan | identical | identical |
| `WIRING: provider.start INSTANCE` | **present** | **ABSENT** |
| `TAP_BUFFER: requested=1024 delivered=4410 (10 Hz)` — AVAudioEngine node tap | present | absent |
| `TAP: startCapture → createProcessTap` — system-audio path | **absent** | **present, twice** |
| gap between preparation and `→ready` | none (same second) | **8 s** |
| `playback_time_s` span | 0.1 → 34.1 s | 0.0 → 0.0 |

**What that pins down.** `resetStemPipeline(caller: .other)` has exactly ONE call site —
`handleLocalFileReady()` — and it appears in the failed log. So that function ran, cleared all
three of its guards (LF source, URL present, not a duplicate `.ready`), reached `buildPlan()`, and
then never got to the router start.

**Candidate mechanism, deliberately NOT asserted as root cause** (BUG-061: do not infer a cause
from "the path requires X, so X held"): the `catch` around
`audioRouter.start(mode: .localFilePlayback(url))` logs via `lfLogger.error` only, then calls
`sessionManager.endSession()`, which sets `currentSource = nil`. With no local-file source,
`startAudio()`'s LF.4 guard — whose own comment warns that `start(.systemAudio)` would
`stopInternal()` the provider — no longer fires, so the process tap is installed and any provider
is torn down. That chain reproduces every observation, including the two tap installs and the
silence, but the first link is unverified.

**Why it could not be verified from the capture, which is a defect in its own right.** Every
branch in `handleLocalFileReady()` that can end in silence returns without writing to
`session.log`, and its failure path logs only to `os_log` — which is not retained here: a
`log show --last 4h --predicate 'subsystem BEGINSWITH "com.phosphene"'` over the failure window
returns **zero lines**. An 84-second silent session left no evidence of its own cause.

**Instrumentation added (this increment, no fix):**
- every early return in `handleLocalFileReady()` names itself in `session.log`, with the actual
  `currentSource`, `isLocalFile` and URL;
- the `router as? AudioInputRouter` cast — which silently gated the *entire* start — is now a
  logged `guard`;
- the LF start failure writes the error text and the `→ endSession` consequence to `session.log`;
- `startAudio()` logs which path it took **and what `currentSource` was** when it chose the tap;

**⚠ A sixth breadcrumb was attempted in `AudioInputRouter.start(mode:)` and ABANDONED — twice
over, for two independent reasons worth recording.** (1) It first read `activeMode` to report
"replacing=<previous mode>". `activeMode` takes the router's `NSLock`, `start()` is reachable from
the file-ended completion path that already holds it, and NSLock is not recursive — **all three
`SessionLifecycleChurnTests` watchdogs timed out at 5 s. A LOG LINE caused a hang-class failure,
and the churn suite is the only reason it did not ship.** Never take a lock in `start()`.
(2) The lock-free version was then dropped as well: `AudioInputRouter.swift` sits at **exactly**
its 400-line lint cap, so any addition needs a file split, and the line was redundant anyway —
`startAudio()`'s new breadcrumb plus the existing `TAP: startCapture` lines already identify the
mode. If a future increment does need it there, split the file rather than trimming a comment.

**Verification criteria (written before any fix):**
1. Automated: a regression test that drives `handleLocalFileReady()` with a local-file source and
   asserts the router ends in `.localFilePlayback` mode — and that a subsequent `startAudio()`
   does NOT replace it with `.systemAudio`.
2. Manual (required — this is a UX-flow and audio-path defect): select a single local file, confirm
   audible playback, and confirm the capture shows `provider.start INSTANCE`, a `TAP_BUFFER` node-tap
   line, no `createProcessTap`, and `playback_time_s` advancing.

---

### BUG-085 — Main thread hangs in `CAMetalLayer.nextDrawable` ~3.6 min into a session (2026-08-04)

**P1 · renderer / app.hang / resource-management.**

**Expected.** The app renders continuously for the length of a session; the window stays responsive.

**Actual.** ~3.6 minutes in, the app freezes hard — no rendering, no UI response, force-quit required. Matt has now hit this repeatedly ("froze again").

**Evidence — a stack, at last.** Matt left the frozen app running instead of force-quitting, so `sample 42392 5` captured it live. **100 % of 4250 samples on a single stack, 0.0 % CPU:**

```
RenderPipeline.draw(in:) → renderFrame → drawWithFeedback → drawParticleMode
  → MTKView.currentRenderPassDescriptor → MTKView.currentDrawable
  → CAMetalLayer nextDrawable → CAMetalLayerPrivateNextDrawableLocked
  → _dispatch_semaphore_wait_slow → semaphore_timedwait_trap
```

Every other thread is idle — audio, caulk, CVDisplayLink all in normal waits. **No thread holds a Metal command buffer, waits on `waitUntilCompleted`, or blocks on a mutex.** So this is not a GPU hang and not a cross-thread deadlock: the drawable pool is exhausted and nothing is returning drawables to it. Because the main thread never returns to the run loop, the window is dead rather than merely frozen mid-frame.

**Reproduction.** Not deterministic yet. Observed on session `2026-08-04T17-49-50Z` (Witchlight, "Hummer"), 12,911 frames ≈ 3.6 min. Frame timings were **steady right up to the final frame** — `frame_cpu_ms` p50 20.80, `frame_gpu_ms` p50 10.62 across the last 50 — with no upward drift. An abrupt stop after healthy frames is the signature of pool exhaustion (leak N drawables, run fine until the pool empties, then block forever), not of a progressive stall.

**Probably not a new defect, and probably not Witchlight's.** The ~3.6 min timing matches the **unreproduced "~3.7 min crash"** logged against Volumetric Lithograph certification, and BUG-060 is a one-off hang filed with "no stack captured". All three are plausibly one bug. Nothing in the stack is preset-specific below `drawParticleMode`, which every `particles` preset shares.

**Already ruled out.**
- `drawParticleMode` leaking directly — it acquires and unconditionally `present`s on every path.
- The inflight semaphore — the hang is *past* `context.inflightSemaphore.wait()`, so a slot was available.
- A GPU hang or a stuck completion handler — no thread is waiting on either.

**Failure class.** `resource-management` (a finite pool acquired without a guaranteed release path).

**Suspected direction, NOT yet confirmed.** Something acquires a drawable outside the committed command buffer's lifetime, or retains `drawable.texture` past presentation. The session-recording hook in `draw(in:)` reads `view.currentDrawable` a second time and hands `drawable.texture` to a consumer, which is the shape of thing that would do it — but that is a hypothesis, and three hypotheses have already died on this preset today. It gets confirmed against an artifact before any fix.

**Investigation so far (2026-08-04) — leading hypothesis, still UNPROVEN.**

Ruled out by inspection after the stack: the capture hook does not retain the drawable (it blits into a separate texture inside the same command buffer, and with video recording off — as this session's log confirms — `ensureCaptureTexture` returns nil so it does nothing at all); the `willRenderActiveFrame` preset-swap skip still commits its command buffer, so skipped frames do not leak; and **display sleep is excluded** — `pmset -g log` shows `coreaudiod` held `PreventUserIdleDisplaySleep` for the full 33 minutes spanning the freeze.

**What that leaves, and it is a real gap regardless of this hang:** the app has **no occlusion handling of any kind**. `MetalView.swift` sets `view.isPaused = false` and nothing anywhere observes `NSApplication.occlusionState`, `windowDidMiniaturize`, or window visibility. Rendering therefore continues into a layer that may not be composited — and a `CAMetalLayer` whose window is minimised or fully occluded stops recycling drawables, which makes `nextDrawable` block exactly as observed. It fits every measured fact: hard block, 0 % CPU, nothing else holding, healthy frames right up to the stop.

**REFUTED 2026-08-04 — do not spend time here again.** Matt ran the repro and left the instance alive; sampled at **7 min 11 s elapsed**, twice past the ~3.6 min mark, with every `UzumeApp` window reporting `onScreen=false` via `CGWindowList`. The app was **not hung**: 0 of 4145 main-thread samples in `nextDrawable`, 49 % CPU, session still live (stem separation running). The control is the decisive part — **the draw loop was entirely absent** (0 samples in `RenderPipeline.draw`, `MTKView draw`, `drawParticleMode`, `currentDrawable`). When the window is not composited macOS stops the draws rather than letting them block, so rendering-into-an-uncomposited-layer is not a state this app can reach, and occlusion cannot be the cause. The missing occlusion handling is still a (minor) gap, but it is **not** this bug.

**Pre-HANG.1 conclusion (2026-08-04).** The original capture stands unexplained: main thread hard-blocked in `nextDrawable` at 0 % CPU with every other thread idle, ~3.6 min in, after frames that were healthy to the last one. Drawables are being retained by something that is not the render path, not the capture hook, not the preset-swap skip, not the inflight semaphore, and not window state. At that point there was no current hypothesis; the next step was instrumentation that counts drawables acquired against command buffers completed, rather than another guess.

**Status 2026-08-05 — HANG.1 + HANG.2 COMPLETE; BUG-085 remains OPEN.** Instrumentation merged to
`main` through PR #37 (source `f81c36cb`, merge `c54a2e7c`); the required `fast-gate` passed.
HANG.1 gathered no reproduction and made no diagnosis or fix claim. Every
drawable-facing render path now routes its existing `currentRenderPassDescriptor`,
`currentDrawable`, and `present` calls through `DrawableLifecycleProbe`, which correlates the
request site and unique drawable identity with its command buffer's commit and completion.
An independent watchdog writes a balance heartbeat to `session.log` every 600 completions,
logs command-buffer failures or completed frames with unpresented acquisitions immediately,
and emits `DRAWABLE_LIFECYCLE STALL` after a request remains pending for 500 ms. The watchdog
does not depend on the blocked render/main thread, so the next reproduction will identify the
exact request site and the last known acquired/presented/completed balance. State-machine tests
cover balanced duplicate lookups, pending-site/age capture, and failed unpresented completion.
`Scripts/capture_hang.sh` now extracts the lifecycle lines explicitly.

**HANG.2 non-reproduction control (2026-08-05).** Two visible Witchlight/local-file runs
completed cleanly: a full 6 min 50 s Hummer control (24,866 frames) and a 10 min 36 s soak
through two track transitions (35,297 frames at the final snapshot). Both passed the original
~3.6-minute / 12,911-frame failure point. The final durable lifecycle heartbeat balanced
34,811 unique acquisitions with 34,811 presentations, with zero command-buffer failures,
unpresented acquisitions, stalls, or imbalances; process memory remained stable. This refutes
a deterministic per-frame drawable leak and a fixed ~3.6-minute exhaustion time. It does not
identify the intermittent owner and does not justify a render change. Full evidence:
`docs/diagnostics/BUG085_HANG2_SOAK_2026-08-05.md`. On the next live freeze, leave the process
running and execute `Scripts/capture_hang.sh` before force-quit.

**The original note, kept for the record:**

**It was NOT confirmed, and was not fixed on that basis** (the BUG-063/064 rule: no fix for an unreproduced hypothesis). Reproduction was attempted and could not be completed headlessly — the render loop only runs with an active session, and `osascript` lacks assistive access on this machine, so the window could not be driven from a script.

**Next reproduction.** Do not schedule another identical soak: HANG.2 established the clean
control. If the app freezes during ordinary use, leave it running and execute
`Scripts/capture_hang.sh` before force-quit; the capture includes the last 20
`DRAWABLE_LIFECYCLE` records, the blocked request site, and acquired/presented/committed/completed
balances. Do not repeat the occlusion experiment; that hypothesis is refuted above.

**`Scripts/capture_hang.sh` added** so the next freeze is captured in one command instead of improvised: stack, process state (0 % CPU distinguishes a block from a spin), window occlusion state, power-event log, and the session tail. **Run it BEFORE force-quitting** — a force-quit destroys the only evidence, which is why BUG-060 sat unactionable for months.

**Phase verification.** HANG.1 automated criteria are complete: lifecycle state-machine tests
cover balanced duplicate lookups, pending request site/age, and failed unpresented completion;
the app suite, renderer golden hashes, strict lint, documentation gates, and CI `fast-gate`
passed. HANG.2's ≥10-minute particle-preset soak and full-track manual run are complete; both
were clean non-reproductions. The minimised-window check is retired because the occlusion
hypothesis was experimentally refuted. BUG-085 remains open pending a frozen instrumented
capture.

---

**2026-08-05 — THE FROZEN INSTRUMENTED CAPTURE, at last.** Session `2026-08-05T21-21-03Z`
(Fractal Tree on Cherub Rock, local file). Matt left the app frozen; two independent runs of
`Scripts/capture_hang.sh` 98 s apart are preserved at
`~/Documents/uzume_sessions/_freeze_captures/bug085_20260805T224531Z/` and
`…T224709Z/`.

**The stack is the same block, at a different site.** `drawWithMeshShader` →
`instrumentedRenderPassDescriptor` → `currentRenderPassDescriptor` → `currentDrawable` →
`nextDrawable` → `semaphore_timedwait_trap`, 100 % of samples, 0 % CPU. The 2026-08-04
capture blocked in `drawParticleMode`; this one in the MESH path. **The hang is not
preset-path-specific** — it is whichever path happens to ask for the drawable.

**What the instrumentation proves, and it is the important part.** The final heartbeat before
the freeze:

```
DRAWABLE_LIFECYCLE heartbeat frames=6013 descriptor=5905/5906 drawable=12045/12045
  unique_presented=6012/6012 command_completed=6012/6012 failures=0 unpresented=0
  pending=frame:6013,site:mesh.descriptor,age_ms:8
```

Every pair balances. **The app was holding ZERO drawables when `nextDrawable` blocked
forever.** That is not starvation-by-leak; CoreAnimation declined to vend a drawable to a
client that owed it nothing. HANG.2's 34,811/34,811 soak said the same thing from the
negative side; this says it from inside an actual freeze. **Direct app-side leakage is now
refuted twice, by independent methods — stop looking there.**

**Permanent, not slow.** The two captures 98 s apart report the identical frame (6013), site,
counters and `age_ms:8`. The `age_ms` is frozen because the heartbeat writer itself never ran
again — the render thread never took another step in 98 seconds.

**Only the render thread died.** `session.log` continues past the hang: stem separations 18
and 19 logged at 22:43:52 and 22:43:57, `SIGNAL_HEALTH` steady at −0.5 dBFS, `deadTap=false`.
Audio, ML and the analysis queues all ran on normally. Any hypothesis requiring a
process-wide stall (priority inversion on a shared lock, GPU device loss) is inconsistent
with this.

**Occlusion again NOT supported, and beware the tool.** `window_state.txt` shows the render
window (13229) `onScreen=true`, `alpha=1.0`, `901x633`, **COMPOSITED**. The other eight
windows it flags are `1920x30` and `1080x30` — menu-bar windows for secondary displays.
`capture_hang.sh` labelled every one of them "this is the BUG-085 occlusion condition",
which reads as confirmation of a hypothesis that was already refuted. (Label fixed in the
same increment as this note.)

**No display event.** `power.txt` has no display-sleep, wake, or reconfiguration entry
anywhere near the freeze; the only traffic is `coreaudiod` assertion churn five minutes
earlier.

**One lead, explicitly NOT a finding.** The stall began at 22:43:51, ~1 s before stem
separation #18. Stem separation is MPSGraph GPU work on a 5 s timer, so GPU contention
starving the compositor is mechanically plausible — but 17 prior separations in the same
session ran through cleanly, so this is a hypothesis to test, not a cause. A test would
suppress stem separation for a full session and see whether the freeze class survives;
BUG-061's rule forbids acting on it before that.

**What is now excluded:** app-side drawable leakage (twice), occlusion, display sleep,
preset-path specificity, and any process-wide stall. **What remains:** why CoreAnimation
withholds a drawable from a client holding none.

---

### BUG-070 — Failed tap reinstall leaves untruthful capture state; engine detectors starved (2026-07-12)

**P2 · audio.capture / resource-management.** From the 2026-07-11 ultra review (concurrency + audio dimensions); root cause verified in code at PUB.6.

**Expected:** after a failed device-change reinstall, the capture object's state reflects reality (not capturing), engine-side health classification can still fire, and a recovery restart can proceed.
**Actual (pre-fix):** `performReinstall`'s catch did nothing — its comment claimed "the create steps already tore down + stopped the monitor on failure," which was false on both counts. End state: `_isCapturing=true`, monitor running, zero IO callbacks → `SignalHealthMonitor.evaluate` (sample-driven, `ingest` window boundaries) never runs so `deadTap` never confirms; the router's `.silent` recovery is likewise callback-starved; `startCapture` recovery blocked by the alreadyCapturing guard. Only the app-layer Mode-B stall card (1 Hz poll on the tap frame count, ~10 s dwell) surfaced it — detection existed, engine truth and recovery did not.
**Fix (landed, PUB.6):** catch clears `_isCapturing` (unblocks stopCapture+startCapture recovery), monitor deliberately left running as a diagnostic beacon (later fires land in the SKIP branch and breadcrumb), comment corrected.
**Verification criteria:** automated — engine builds; audio suites green (a real failed reinstall cannot be staged headless: Core Audio create-step failures need a live device transition). Manual (pending): a live device-swap session confirming normal reinstalls still work (the G1 12/12 behaviour), and — if a reinstall failure can be provoked — the stall card appears AND a subsequent session restart recovers cleanly.
**Residual (documented, deliberately open):** the 3-queue lifecycle interleave (device-change reinstall vs silence-recovery reinstall vs user stop) is real but static-only evidence; the per-step breadcrumbs + install-generation probes are the instrumentation. Serialize ONLY on a reproduced interleave artifact — restructuring the G1-live-validated path on theory is the BUG-063 class.

---

### BUG-077 — `BeatGridResolver.snapToBeats` diverges from the Beat This! reference post-processor (2026-07-30)

**P3 · dsp.beat / api-contract.** Found at DBN.1 while auditing the resolver against the paper it implements.

**Expected:** `BeatGridResolver` implements Beat This!'s minimal post-processor. That post-processor's third step is *"move all downbeat predictions to the closest beat prediction"* — unconditional, no distance limit (Foscarin et al., ISMIR 2024).

**Actual:** `snapToBeats` applies `if nearestDist <= maxDistance`, where `maxDistance` comes from `snapFrames = 2` (40 ms at 50 fps). Any downbeat candidate further than 40 ms from the nearest beat is **discarded** rather than snapped.

**Currently harmless, and explicitly NOT the cause of the low downbeat F.** Measured at DBN.1 (`DownbeatStreamDiagnosticTests`): **100 % of downbeat candidates survive the gate** on money, billie_jean and solsbury_hill (median distance to nearest beat 0.0 ms; take_five 94 %). Nothing is being discarded today. The real cause of the 0.13–0.26 downbeat F is a near-degenerate downbeat *stream* — the model emits a confident downbeat on 69–90 % of beats on odd-meter tracks — documented in [`docs/design/DBN_DECODER_SPEC.md`](../design/DBN_DECODER_SPEC.md) §2.1. **This entry exists so a future session does not re-derive the divergence and mistake it for the defect.**

**Why file it anyway:** it is a genuine spec-fidelity divergence of the D-077 class (a paraphrased post-processor silently dropping data the reference keeps), and it becomes live the moment downbeat timing loosens — a track whose downbeat peaks sit two or three frames off the beat would have those downbeats deleted rather than snapped, and `computeMeter` would then divide a decimated set.

**Fix:** one comparison. Do it in **DBN.3**, when the resolver is being touched for the decoder A/B anyway — not as a standalone change, since it alters grid output and would need its own golden regeneration for no current behavioural gain.

**Verification criteria.** Automated: a resolver unit test with a downbeat candidate placed >40 ms from any beat, asserting it is snapped rather than dropped. Regression: `BeatGridResolver` goldens + the BeatBench offline-grid table unchanged on all 9 ground-truthed tracks (the fix should be a no-op on today's fixtures — if it is not, that is itself the finding).

---

### BUG-076 — Prep grid is window-position unstable on Bleed (a third of 30 s windows read wrong) (2026-07-27, CORRECTED 2026-07-30)

**Domain tag:** dsp.beat (grid tempo/meter). **Severity:** P2 — one track, but it is the defining case for category 4 (dense transients) and it demonstrates the program's central premise concretely.
**Status:** **Open — deferred by design, do not fix in isolation.** Owned by the beat-sync program (D-202): Phase DBN should dissolve it (a sequence decoder over the full activation timeline is not excerpt-dependent) and Phase FT removes the 30 s premise for local files. A targeted per-track patch here would be tuning against one fixture. *(Status line added at RECON.2, 2026-08-03 — this was the only §Open entry without one, so its disposition lived in prose and the index row alone.)*
**Resolved:** —

**CORRECTION (2026-07-30).** As first filed this bug claimed the grid "locks to a non-metrical tempo (3:2)" on Bleed, generalising from a single number in a session prep log (`bpm=174.6`) without re-measuring. Direct measurement at GT.3 falsified that: run on the fixture, the grid reads **115.00** — the correct value. The real defect is **sensitivity to which 30 s window is analysed**, which the original filing missed entirely. Recorded rather than quietly rewritten, because the mistake is instructive: a logged value is one sample, not a characterisation.

**Expected:** the prep grid returns the same, musically valid tempo regardless of which excerpt of a track it is given.

**Actual — nine 30 s windows of `bleed.wav`:**

| offset | BPM | beatsPerBar | barConfidence |
|---|---|---|---|
| 0 s | **115.00** ✓ | 4 | 0.50 |
| 30 s | 121.10 ✗ | 2 | 0.59 |
| 60 s | 116.88 ✓ | 2 | 0.62 |
| 90 s | **242.71** ✗ | 3 | 0.32 |
| 120 s | **166.09** ✗ | 3 | 0.45 |
| 150 s | 115.38 ✓ | 3 | 0.14 |
| 180 s | 115.07 ✓ | 2 | 0.48 |
| 210 s | 115.15 ✓ | 4 | 0.60 |
| 240 s | 114.92 ✓ | 2 | 0.64 |

Six of nine correct; three wrong across a **2.11× spread**. Ground truth is unambiguous — Matt's taps 226.7 (2:1 of the pulse), madmom 115.0, librosa 115.0, session drums-stem 115.1. `beatsPerBar` also swings 2/3/4 on a track that is 4/4 throughout.

**Control (matters — it bounds the defect):** Billie Jean over the same offsets reads 116.88 / 117.04 / 117.12 / 117.25 / 117.17, `beatsPerBar` 4 and `barConfidence` **1.00** at every window. So this is not a general instability; it is specific to dense-transient material where the activation function has energy at several subdivisions. Notably `barConfidence` already separates the two cases (0.14–0.64 vs 1.00) — the existing signal knows.

**Why the session logged 174.6:** the prep path analyses the 30 s Spotify preview, a mid-track excerpt, which fell in the unstable region. This is the plan's §2 premise made concrete: a grid built once from one arbitrary 30 s excerpt and extrapolated.

**Reproduction:** `swift run BeatBench --audio ~/uzume_beatbench_fixtures/bleed.wav --seconds 30` for the whole file, or cut a window with `ffmpeg -ss <offset> -t 30` and pass that. Fixture sha256 in `Tests/Fixtures/beatbench/manifest.json`.

**Suspected failure class:** `algorithm` — `BeatGridResolver` peak-picking a dominant period from Beat This! activations without a sequence model. Palm-muted 16ths put comparable energy at several metrical levels, so the winner depends on the excerpt.

**Verification criteria (written before any fix):**
1. Automated: BeatBench window-sweep over Bleed — ≥ 8/9 windows within 5 % of a valid metrical level of 115.0, spread < 1.1×. Baseline is 6/9 and 2.11×.
2. No regression: suite 1 stays green (DBN.3 hard gate); Billie Jean's window sweep must remain flat.
3. Manual: Matt confirms beat-driven motion reads on-pulse on Bleed.

**Do not fix in isolation.** The fix is the Phase DBN sequence decoder (and Phase FT, which removes the 30 s premise for local files). A per-track heuristic would be the peak-pick patching the program exists to retire.

### BUG-065 — Live BeatGrid phase drifts off the audible beat over a track (mid-track drift convergence) (2026-06-29)

P3, `dsp.beat`. (Renumbered from BUG-064 on the GLAZE.8→main merge — BUG-064 was already assigned to the Lumen freeze; this beat-sync bug forked the number on `claude/nice-rubin-9c10c7`.)

**Expected:** the live beat phase stays within the ~60 ms perceptual window across a whole track, so frame-locked beat-driven motion (e.g. Glaze's GLAZE.7 downbeat push) reads tight start-to-finish.

**Actual:** the cached grid has the right BPM, but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it — drift grows ~11 ms (track start) → 50–70 ms (mid/late-track), with 28 % of frames exceeding ~60 ms. Evidence: session `2026-06-29T12-43-51Z` (Cherub Rock, 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; `lock_state=2` only 67 %-within-60 ms). NOT a functional break (phase is approximately right); it caps how *tight* beat-locked presets can feel (the live example: GLAZE.7 reads connected but loosens as the track plays).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is mid-track drift *convergence* — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session.

**Status 2026-07-30 — OPEN. Root cause proven (TRK.1); both attempted fixes stopped at their own gates.**

- **TRK.1 (`07dd3bd9`) proved the mechanism.** The drift is a *ramp*, not noise: linear fit **−1.493 ms/s at R² = 0.844** on session `2026-07-30T15-39-21Z` (Hummer, 80.45 BPM), `grid_bpm` rock-constant ⇒ a **0.149 %** cached-grid period error (0.12 BPM). The legacy tracker is a first-order EMA on phase error — proportional-only, which has zero steady-state error against a step but *constant* error against a ramp. It can bound drift; it can never null it. That is exactly "bounds without tightening". A type-2 (PI) controller was implemented behind `UZUME_BEAT_PLL` and **failed real-fixture validation** — `LiveDriftValidationTests` (loveRehab) maxAbsDrift **101.5 ms** (limit 50), beat alignment **0.05** (limit 0.80). Default-off. **Strike 1 on the gain-tuning premise; do not retune gains against sub-bass evidence.**
- **TRK.2 stopped at its evidence gate — the drums-stem premise is FALSIFIED.** The proposed fix was to change the *evidence* (drums-stem onsets instead of sub-bass) rather than the gains. Measured on four captures with the production `StemSeparator` + a separate `BeatDetector` instance (D-075), bias-corrected: drums-stem sub_bass onsets landing within ±50 ms of a grid beat vs the full mix — love_rehab **16.9 % vs 42.2 %**, Hummer **11.0 % vs 14.4 %**, `bleed.wav` **22.4 % vs 22.3 %**, billie_jean **25.5 % vs 24.5 %**. Worse on two, a wash on two, *including Bleed* — the category-4 track the whole argument rested on. Best drums band anywhere: +2.5 pp, inside noise. **Larger finding:** across every capture, band and stem, only **~15–25 % of detected onsets land within ±50 ms of a beat** — FA #68 generalises, the spectral onset-detector family is weak beat evidence wherever it runs. **Second, independent blocker:** the live stem path (`VisualizerEngine+Audio.swift` `runPerFrameStemAnalysis`) deliberately carries **5–10 s of latency** with a sawtooth re-anchor every ~5 s, so drums onsets cannot be timestamped correctly by the tracker without a separate design that threads their true tap time through. No production code was changed. Evidence + reproduction: [`docs/diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md`](../diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md); instrument: `DrumsOnsetEvidenceTests` (env-gated).
- **Corroborated at scale by the GT.3 live baseline (2026-07-30).** `docs/diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md` measures the drift curve across 15 streamed tracks, and the growth this bug describes is the norm, not one capture: billie_jean 26 → 118 ms, stayin_alive 60 → 285 ms, money 20 → 241 ms, superstition 26 → 94 ms, clair_de_lune 39 → 135 ms by 30 s window. Only giorgio_by_moroder and pyramid_song hold flat. The program's live suite-1 target is **p90 < 30 ms**; the measured p90 is 102 ms on billie_jean and 269 ms on stayin_alive. This is systemic to the frozen single-BPM grid premise.
- **PARKED — Matt 2026-07-30 (D-206): "park the tracker, go DBN next session."** Two evidence sources and one controller topology have now been measured against the same frozen single-BPM grid, and the evidence layer has no headroom left. BUG-065 stays **open and bounded** (the visual falls up to ~119 ms behind late in a track; not a functional break); `UZUME_BEAT_PLL` stays default-off. Phase TRK is parked and TRK.3 has no content. The defect is now expected to be addressed — if at all — as a side effect of phase **DBN** replacing the frozen single-BPM grid premise, not by further tracker work. **Do not reopen TRK without a changed premise about the *grid*, not the tracker.**


---

### AUDIT-2026-06-09 — Full-codebase audit backlog (P2/P3 findings not individually filed)

**Status:** Open — index entry (P3 backlog only as of PUB.3: all four formerly-open P2 bullets below verified fixed in code, 2026-07-11). The 2026-06-09 six-agent full-codebase audit (~92k lines, all findings verified at file:line, cross-checked against this tracker and CLAUDE.md FAs) produced 6 P1s, 17 P2s, ~40 P3s. The P1s and three highest-impact P2s are filed individually below (BUG-030 … BUG-037). Everything else lives in **[`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](../diagnostics/CODE_AUDIT_2026-06-09.md)** — treat that document as the evidence record when picking up any item. Remaining P2s in brief (full detail + fix shapes in the audit doc):

- ✅ **RESOLVED (CLEAN.3.2, 2026-06-17; re-verified in code at PUB.3)** — reactive orchestrator hard-exclusion filtering now present (`ReactiveOrchestrator.swift:~220`, exclusion-aware selection with the every-preset-excluded edge handled).
- ✅ **RESOLVED (CLEAN.3.3, 2026-06-17; re-verified at PUB.3)** — zero-duration fallback now routes through the scored/excluded path (`SessionPlanner+Segments.swift:~129`).
- ✅ **RESOLVED (CLEAN.3.x, 2026-06-17; re-verified at PUB.3)** — cooldown reset on track/session boundary (`LiveAdapter.swift:~369-378`).
- ✅ **RESOLVED (CLEAN.3.5, 2026-06-17; re-verified in code at PUB.3)** — in-memory StemCache now has an LRU cap (`maxEntries` + touch-on-track-change eviction, `StemCache.swift:~89-101`).
- **OAuth correctness (re-entrant `login()` leak, refresh double-spend, P3 hardening)** — ✅ **RESOLVED 2026-06-14 (CLEAN.2.2, commit `13cec8b`, integrated `a6f1288`).** Matt's live check passed: Spotify playlist loaded with no problems on the integrated `main` build — the refresh path exercised end-to-end against real Spotify, no regression. The fresh-login `state` guard is unit-test-proven + standard OAuth on unchanged callback routing (accepted without a forced interactive login per Matt 2026-06-14, since a silent refresh does not hit the consent round-trip). `SpotifyOAuthTokenProvider`: a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt → now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array; `finishLogin()` cancels the timeout on every resume path); concurrent `acquire()` each fired their own silent refresh, double-spending the rotating refresh token → now dedups onto a single in-flight `refreshTask`; + P3s (OAuth `state` CSRF/replay guard, form-body percent-encoding of `+ & = /` that `.urlQueryAllowed` leaked, Keychain-save failures logged not swallowed, callback `scheme == uzume` + host validation). `SpotifyOAuthTokenProviderTests` green (4 new regressions).
- ✅ **RESOLVED (CLEAN.2.1, 2026-06-14)** — Spotify client secret baked into the built Info.plist. Removed `SpotifyClientSecret` from `Info.plist` + `Uzume.xcconfig` and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider`. The production flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`), which needs no secret; no build-bundled secret remains. OAuth login E2E confirmed by Matt 2026-06-14 on the integrated `main` build (no regression). See `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- ✅ **RESOLVED (CLEAN.2.3, 2026-06-14)** — honest-UI dead controls (audit T5), each Matt's product call. **2.3.1:** the "Use Apple Music instead" no-op `{ }` cross-link (+ its dismiss-only mirror) now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2:** the `.localFile` "coming later" capture mode (lying + no-op) removed — enum case, picker row, false string, and the now-unreachable reconciler/coordinator branches (remove; supersedes the `.localFile` branch of D-052). **2.3.3:** the disabled "Swap preset" context-menu stub hidden behind `#if ENABLE_PRESET_SWAP` until U.5b (hide). Commits `7800b72` / `d40cfad` / `6e983c8`. `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- ✅ **RESOLVED (CLEAN.4.4, 2026-06-17)** — three renderer over-allocation / cache-key items from audit T7 (the `2026-06-13` audit's restatement of these P3s). (1) **PSO cache key** (`ShaderLibrary` cached by `name` alone, ignoring `pixelFormat`/`supportICB`): **finding = LATENT, not a live bug** — every production caller uses a **unique** name compiled once at init, preset multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`), and `supportICB: true` is test-only, so nothing currently collides; keyed correctly anyway by `PipelineKey(name, pixelFormat.rawValue, supportICB)` so a future name-reuse can't return the wrong-format PSO. (2) **wasted particle-mode warp pass** + (3) **unconditional feedback textures**: both gated to surface-mode feedback presets via `RenderPipeline.activePresetSamplesFeedback` — non-feedback + particle-mode presets allocate zero ping-pong (freed on `setFeedbackParams(nil)`), and particle mode skips the warp. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests` +2, `DrawableResizeRegressionTests` +3. `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. (T7's remaining items — sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race — **were closed by CLEAN.4.3 and CLEAN.4.5, both completed 2026-06-18**; see `docs/diagnostics/CODE_AUDIT_2026-06-13.md`, where they are marked ✅, and `ENGINEERING_PLAN_HISTORY.md`. *Corrected at RECON.2, 2026-08-03: this line previously read "stay open under CLEAN.4.3/4.5", and since both increments have rotated out of the live plan the pointer was unresolvable from here — it read as open work with no owner.*)
- ✅ **RESOLVED (CLEAN.2.3.4, 2026-06-14)** — localization gate only scanned `UzumeApp/Views/`. `check_user_strings.sh` ROOTS widened to `UzumeApp/ViewModels` + `ContentView.swift`, pattern extended with a connection-state `.error("…")` arm (`logger.error` excluded); the bypassing copy (Spotify/AppleMusic error strings, ConnectorType tiles, ReadyViewModel duration/source, ContentView fallback, PreparationProgressView subtitle, PlanPreviewTransitionView labels) externalized to `Localizable.strings`. Gate header documents its honest scope limit (literal-prefix matcher — lowercase/interpolated fragments still rely on review). Commit `46d836b`.

P3 categories indexed in the audit doc: ~25 latent bugs (incl. OAuth refresh double-spend + form-encoding gaps [Resolved CLEAN.2.2, see above], PSO cache key, mv_warp buffer(5) omission, PostProcessChain texture aliasing, malformed-sidecar swallowing, Arachne listening-pose FA #57-gate, >2-channel LF corruption, ~94 Hz vs 60 fps chroma hysteresis), ~11 perf items (autocorrelation 2×/frame, drums FFT 2×/frame, mono STFT 2×/track, serial prep pipeline, wasted particle-mode warp pass, unconditional feedback textures), dead code, and 6 in-code doc-drift items.


---

**GT.3 addendum (2026-07-30) — the ramp is systemic, and one track is 14× worse.** BeatBench session-replay over the 15-track `beat-match-test-session` fits `drift_ms` against time for every track. Each is a linear **ramp**, confirming the TRK root cause (a period error a proportional-only controller can bound but never null) across the whole catalog rather than one capture:

| track | period error | R² | unlocks at | confident-wrong |
|---|---|---|---|---|
| **YYZ** | **+2.070 %** | **0.99** | 47 s | **90.8 %** |
| Dance Yrself Clean | −0.149 % | 0.79 | 58 s | 81.4 % |
| Bohemian Rhapsody | +0.126 % | 0.93 | 0 s | 76.9 % |
| Money | −0.081 % | 0.93 | 122 s | 64.1 % |
| Stayin' Alive | +0.083 % | 0.89 | 48 s | 84.0 % |
| (10 others) | < 0.07 % | — | — | 0–53 % |

**YYZ is the extreme case and it is real, not an artifact** (R² 0.99 over 15,898 frames): a 2.07 % period error accumulates to **4.8 seconds — about 11 beats — by the end of a 266 s track**, while `lock_state == 2` for 92 % of frames. The engine reports "locked" while eleven beats out of phase. Note Dance Yrself Clean's −0.149 % matches the period error TRK measured exactly.

**Two things this reframes.** (1) *Time-to-lock was the wrong metric.* Drift on these tracks starts **inside** the ±70 ms window (YYZ 52.7 ms, Dance Yrself 29.0 ms) and walks out, so "time to lock" reads 0 s and looks healthy; the informative number is **time-to-unlock**, and **13 of 15 tracks leave the window and never return** — only Solsbury Hill and Giorgio stay in. (2) *The suite-1 live target is far off.* Billie Jean's p90 is **102 ms** against a target of < 30 ms.

Evidence: [`BEATBENCH_LIVE_BASELINE_2026-07-30.md`](../diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md). Reproduce: `BeatBench --mode session-replay --session <dir>`.

### BUG-081 — App beachballs during session preparation; no crash report produced (2026-08-03)

**P2 · unclassified · OPEN — evidence only, root cause NOT established.** Reported by Matt from session `2026-08-03T22-54-06Z`; had to force-quit.

**Expected.** The app stays responsive throughout playlist preparation.

**Actual.** The UI froze/beachballed ~78 s into the session and required force-quit. Because it was force-quit rather than crashed, **no `.ips` exists** — the user and system DiagnosticReports directories contain no UzumeApp report at all, and `session.log` ends mid-normal-operation at `22:55:24` with no fatal, assertion, or error line.

**What the artifacts DO establish — the renderer was healthy to the last frame.** From `features.csv` (3756 frames, ending t=82.1 s), by sixth of the session:

| segment | frame_cpu_ms | frame_gpu_ms | deltaTime |
|---|---|---|---|
| 1/6 | 11.51 | 2.91 | 47.8 ms (startup) |
| 4/6 | 1.53 | 0.15 | 16.7 ms |
| 6/6 | 6.84 | 0.18 | 16.7 ms |

Steady 60 fps, Fractal Tree costing **0.18 ms GPU against its 0.7 ms Tier 2 budget**, no degradation trend. Background load was rising but modest (`stem_analyzer_ms` 0 → 3.4, `mir_pipeline_ms` 0.84 → 2.09); `session.log` shows stem separation 10 in progress.

**Ruled out.** FTR.2's mesh shader overflowing the primitive limit via a bad `branch_count` — the hypothesis was tested and **falsified**: no non-finite values in the capture, and derived `branch_count` never exceeds 59 against the 63 ceiling. (A grep appearing to show `nan` was matching "co**nan**ce" in `tonal_consonance`.)

**Not yet established.** Everything else. A frozen UI with a healthy render loop points away from the preset and toward the main thread or the preparation pipeline, but that is an inference, not evidence — do not act on it (BUG-061 rule).

**Sub-finding, FIXED 2026-08-04 (`17ac02fc`): a crashed session left an unreadable `raw_tap.wav`.** The stub header declares a `data` size of 0 and the real sizes were patched in only on the 30 s cap or a graceful `finish()` — so every standard reader saw an empty file. Session `2026-08-04T20-23-15Z` had **28.8 MB of intact float samples behind a header claiming zero bytes**, making the capture useless for diagnosing the crash that produced it. `patchRawTapHeader` now also runs about once per second of audio. **NOT gated by a test:** `RawTapHeaderRecoveryTests` could not be made to run (constructing a recorder and abandoning it mid-capture either crashed the test process with signal 5 or produced no file); the fix reuses the existing patch routine and `test_rawTapCapture_persistsAfterDurationCap` still passes, but there is no regression guard. Worth a second attempt with fresh context.

**Next evidence needed — the one thing that would settle it.** A `sample` of the process while it is hung, which captures the blocked main-thread stack:

```
sample UzumeApp 10 -file ~/Desktop/uzume-hang.txt
```

Run it *during* the beachball, before force-quitting. Without a blocked stack there is no way to distinguish a deadlock from a GPU stall from a preparation-pipeline wedge.

**Note.** Signal health was `critical` (−24 dBFS) for the session's first ~50 s before reaching green; unlikely to be related but recorded because the session is otherwise the only artifact.

---

### BUG-129 — `chain_health.json` reports `peakDBFS` exactly 0, and the verdict stays `clean` (2026-09-11)

**Severity:** P3. Found while checking a session's chain health before quoting its verdict in an M7
closeout — not reported by a user.

#### Expected behavior

`peakDBFS` reports the capture's true peak in dBFS, and a peak at or near 0 (full scale) either
reflects real clipping or trips a chain-health reason.

#### Actual behavior

| session | `peakDBFS` | verdict |
|---|---|---|
| `2026-09-11T19-12-34Z` | −6.03 | clean |
| `2026-09-11T19-58-15Z` | **0** | clean |
| `2026-09-11T20-19-03Z` | **0** | clean |

`reasons` and `notes` are empty on all three, and `raw_tap.wav` is present in every session
directory. So either the peak is not being measured and falls back to 0, or it is measured as full
scale and the clipping check does not fire on it. Both readings are defects; they need different
fixes.

#### Why it matters beyond tidiness

The preset-session rule is that a fidelity/M7 closeout **must cite the session's chain-health
verdict**, and D-184 makes a `clean` verdict the precondition for judging fidelity at all — *"a
fidelity judgment made on degraded audio measures the wrong thing."* A peak field that silently
reads 0 weakens every such citation. **Two M7s closed on 2026-09-11 cite `clean` over a 0 peak —
VL.2 and WL.11** — and both carry the caveat in their plan entries rather than quietly relying on
it.

#### Suspected failure class

`measurement` / `documentation-drift` at the boundary — a diagnostic that reports a value nobody
checks against reality. Start at `ChainAnalyzer`'s peak path and whether `raw_tap.wav` is read at
all when the verdict is computed; `Scripts/analyze_session_chain.sh <dir>` regrades a directory in
place, which makes an A/B against the −6.03 session cheap.

#### Verification criteria (written before any fix)

- Automated: regrade all three sessions above; the two reading 0 must either report a plausible peak
  or produce a non-`clean` verdict with a reason naming why.
- Automated: a session whose `raw_tap.wav` is genuinely full-scale must NOT grade `clean`.
- No manual check required — this is a measurement defect, not a felt one.

### BUG-087 — Local-file playback analyses at 10 Hz where streaming analyses at 51 Hz (AVAudioEngine ignores the tap `bufferSize`) (2026-08-11)

Found while chasing a `beatPhase01` discrepancy across captures. **Diagnosis increment
only — no fix code.**

#### Expected behavior

The MIR chain analyses at a comparable rate whichever way audio arrives.
`LocalFilePlaybackProvider` requests `installTap(onBus: 0, bufferSize: 1024, …)`, which at
44.1–48 kHz is ≈43–47 Hz.

#### Actual behavior

**Local-file playback analyses at 10.0 Hz. Streaming analyses at 51.1 Hz.** A 5.1× rate
loss, on the session type used for essentially all development and all preset work.

#### Reproduction steps

Any local-file session vs any streaming session. Measured across the whole capture corpus
(10 local-file captures, 1 streaming).

#### Session artifacts

`beatPhase01` advance rate × the CSV's own frame rate gives the analysis rate directly:

| capture | path | audio Hz | analysis Hz | implied buffer |
|---|---|---|---|---|
| `2026-08-11T01-07-17Z` | local | 44 100 | 9.99 | **4414 frames** |
| `2026-08-11T23-52-49Z` | local | 48 000 | 9.98 | **4808 frames** |
| `2026-08-11T23-44-40Z` | local | 48 000 | 9.98 | **4810 frames** |
| `beat-match-test-session` | streaming | 48 000 | **51.11** | **939 frames** |

All ten local-file captures read 15.2–16.8 % (16.7 % on eight of ten). The streaming capture
reads 85.4 %.

**The discriminator that makes this a diagnosis and not a correlation:** if the tap delivered
a fixed *frame count*, the analysis rate would differ between the 44.1 kHz and 48 kHz
captures. It does not — 4414 frames at 44.1 kHz and 4808 at 48 kHz are both **exactly 0.1 s**.
The buffer is duration-based, so the `bufferSize: 1024` request is being ignored, not merely
rounded. The streaming path's 939 frames ≈ the 1024 the system tap actually honours.

⚠ **Path and date are perfectly confounded in the corpus** (the sole streaming capture is
2026-07-27; every local-file capture is 2026-08-07 or later), so the *captures alone* cannot
separate "local-file path" from "something regressed in August". The code and the
rate-independence discriminator are what settle it, plus the streaming capture's
`TAP: startCapture: ENTER → createProcessTap` lines, which no local-file capture has — they
are genuinely different audio sources, not the same source at two dates.

#### Suspected failure class

`calibration` — intent (1024 frames) versus reality (~4800), unverified at the boundary.
`api-contract` secondarily: AVFoundation treats `installTap`'s `bufferSize` as a hint, and
nothing here checks what was actually delivered.

#### Root cause (read from source)

- `UzumeEngine/Sources/Audio/LocalFilePlaybackProvider.swift:292` —
  `player.installTap(onBus: 0, bufferSize: 1024, format: tapFormat)`. AVAudioEngine honours
  this loosely and delivers ~0.1 s buffers on macOS.
- `UzumeApp/VisualizerEngine+Audio.swift` `processAnalysisFrame` — invoked once per audio
  callback via `analysisQueue.async`, with **no time-based gate**, and it derives
  `effectiveFps = 1 / dt` from the callback interval. So the callback rate *is* the analysis
  rate, and `dt` correctly reports 0.1 s; nothing is lying, the rate is simply low.
- `handleTapBuffer` is **not** at fault: it resizes `interleavedScratch` when a buffer exceeds
  the 1024-frame allocation, so no samples are dropped. Checked, because a scratch sized 1024
  against a 4800-frame buffer would have been the more serious bug.

#### Impact

Every `FeatureVector` consumer on the local-file path sees 10 Hz: bands, the D-026 deviation
primitives, `beatPhase01`, centroid, flux, and the mood classifier's inputs. This is the same
10 Hz the FTR program discovered from the preset side and carried as a preset-authoring fact;
it is a pipeline property, and it is path-specific.

**For a beat-ruled scrolling preset (Stave / the CHR series) it is a design input**, not a
footnote: gridlines and trace samples would arrive in 100 ms steps on the path that preset
would mostly run on.

**A lead was recorded here and is now REFUTED (2026-08-12).** It read: this may also explain
BUG-086's local-file stem/band correlation of r 0.19–0.46 against streaming's 0.70–0.94, since
stems and bands would be sampled on different clocks. Both halves failed. Stems and bands are
on the **same** clock within a path (streaming `beatPhase01` 85.4 % / stems 97.1 %; local
16.7 % / 14.6–16.0 %), so the proposed mechanism does not exist. And step-holding the streaming
capture's series down to 10 Hz — injecting this defect into strong-r data — barely changes the
result (r 0.788→0.783 … 0.937→0.938, 5.4 s lag intact). **10 Hz does not explain BUG-086's weak
correlation**, and this fix should not be expected to improve it. Kept as a record so the lead
is not re-run; detail in BUG-086's refuted-hypothesis list.

#### Verification criteria (written before any fix)

- Automated: assert the delivered buffer's `frameLength` against what was requested at the
  `installTap` boundary, so an ignored hint fails loudly instead of silently costing 5× rate.
- Automated: an analysis-rate floor measured from a real capture, the same shape as
  `Scripts/measure_stem_latency.py` — `beatPhase01` advance × CSV fps ≥ target.
- Manual: any fix raises the update rate of every deviation primitive on the local-file path,
  which is felt on every preset. M7-class observation required; a 5× change in feature update
  rate is not a silent change.

#### Fix attempted — PARTIAL, and the remedy was wrong (BUG087.2/.3, 2026-08-13)

**Measured on capture `2026-08-13T13-15-36Z`: 10.0 Hz → 16.4 Hz. The ≥ 40 Hz done-when is
NOT met**, and not for a tuning reason.

**What landed and works.** `BUG087.2` moved the analysis time base off wall-clock onto the
audio each callback carried (`frames / rate`) — behaviour-neutral, verified by the full suite
moving **zero** existing expectations, and a prerequisite for producing several analysis
frames per callback. `BUG087.3` slices each delivered buffer into 1024-frame pieces.

**Why it falls short.** Slicing raised the *computation* rate to ~47 Hz but not the rate a
preset observes. All five slices of a buffer complete within microseconds — they process
already-buffered audio, not audio arriving in real time — so the render loop samples ~1.6 of
them as distinct values and supersedes the rest. The gap distribution is bimodal and
unambiguous: **39 % of value changes are 1 render frame apart, 55 % are 5–6 frames
(84–101 ms) apart.** A burst against a 100 ms arrival period.

> **The binding constraint is how often audio ARRIVES, not how finely it is sliced.** A preset
> cannot observe more distinct values per second than buffers are delivered, when every slice
> of a buffer lands at the same instant.

**Kept anyway (Matt's call):** effective rate 10 → 16.4 Hz (+64 %), and fresher values — the
last slice reflects the newest 1024 samples rather than a position inside a 4410-frame buffer,
a latency gain even where the rate did not move. Cost: ~5× the per-callback allocation on the
audio thread, landing at ~47/s — the rate the system-tap path has always run at.

#### Instrumentation — one remaining route ELIMINATED, and a fresh live measurement (2026-09-10)

`TapDeliveryRateTests` measures what each node actually delivers and, crucially, **how far apart
the deliveries land** — two buffers arriving in the same instant are worth one update to a preset
however small they are. Real music (a session `raw_tap.wav`), `BUG087_AUDIO=<wav>`:

| tap node | requested | delivered | rate | arrival gap |
|---|---|---|---|---|
| player | 1024 | 4410 | 10.0 Hz | mean 99.8 ms |
| player | 4096 | 4410 | 10.0 Hz | mean 99.8 ms |
| mixer  | 1024 | **4800** | **10.0 Hz** | mean 99.8 ms |
| mixer  | 4096 | **4800** | **10.0 Hz** | mean 99.8 ms |
| output | any | **nothing** | — | — |

**"Tap a different node" is DEAD as a route.** The mixer delivers on the identical 0.1 s cadence —
4800 frames at 48 kHz against the player's 4410 at 44.1 kHz, i.e. the same fixed *duration*, the
same discriminator BUG087.1 used. `outputNode` delivers no buffers at all. The 0.1 s tap cadence is
AVAudioEngine's, not the node's, and it ignores the requested size at both 1024 and 4096.

**`AVAudioSinkNode` is INCONCLUSIVE, not eliminated.** It is a render-callback node rather than a
tap, so it is not subject to the tap cadence — the right shape for this problem. But wiring it
alongside live playback did not work here: a plain second `connect` from `mainMixerNode` (which
already feeds `outputNode`) **aborts with signal 6 rather than throwing**, and the supported
`AVAudioConnectionPoint` fan-out produced **zero callbacks**. Two configurations tried, both
recorded; neither shows it working and neither proves it cannot. Stopped there per the two-strikes
rule rather than permuting wiring.

**Live rate confirmed independently, from Matt's own sessions** — the analysis rate measured as
"how often does a `FeatureVector` field actually CHANGE across render rows":

| session | type | bass | beatComposite | arousal | render |
|---|---|---|---|---|---|
| `2026-09-10T18-01-30Z` | local file | 10.2 Hz | 9.0 Hz | 9.6 Hz | 59.8 fps |
| `2026-09-10T17-13-10Z` | local file | 10.3 Hz | — | — | ~60 fps |
| `beat-match-test-session` | **streaming** | **58.8 Hz** | — | — | ~60 fps |

So the row's "10 Hz local vs 51 Hz streaming" holds, and streaming now measures **58.8 Hz** —
essentially render rate. **The 16.4 Hz from BUG087.2/.3 is not what a local session shows today;
10 Hz is.** ⚠ **Product consequence worth stating plainly: the roster review was conducted on local
FLAC**, and "sync is weak / loose / tenuous" appears against Membrane, Meniscus, Mitosis, Plasma and
Nebula in it. A driver bus running ~5.8× slower than the renderer is a plausible common factor
behind part of that cluster, and no per-preset tuning touches it.

#### The residual is OFFSET, not rate — measured at ~145 ms transport (2026-09-10)

Matt on a streaming build: *"audio sync is still a little loose, not perfectly synced."* On that
path the rate ceiling is **gone** — bass 60.0 Hz, beatComposite 58.9, spectral_level_rise 59.3
against a 59.9 fps render (`2026-09-10T19-45-58Z`). So whatever remains is not quantisation.

`VisualAudioOffsetTests` turns it into a number. **The alignment is exact, not estimated:**
`session.log` records `raw tap capture started ... wallclock=<t0>` and every `features.csv` row
carries the same `wallclock_s`, so a sample index in `raw_tap.wav` and a feature row sit on ONE
timeline — no CS.1-style onset pairing needed. Offline broadband onset strength (log-energy first
difference, 5 ms grid) is cross-correlated against the recorded columns over the 21.3 s overlap:

| column | best lag | r | r at zero lag |
|---|---|---|---|
| `bass` | **+145 ms** | 0.219 | −0.031 |
| `treble` | **+175 ms** | 0.142 | 0.095 |
| `spectral_level_rise` | **+275 ms** | 0.195 | 0.026 |
| `beatComposite` | −280 ms | **0.060** | 0.016 |

**★ SEVERAL COLUMNS ON PURPOSE — one column cannot tell transport delay from feature shape.**
`bass` is a band energy that tracks the envelope directly and lags **+145 ms**: that is transport.
`spectral_level_rise` lags **+275 ms**, and the extra ~130 ms is its OWN design — it compares level
against a 0.15 s trailing floor, so it peaks after a transient by construction. Reading the 275 ms
as pipeline latency would have over-stated the engine's share by nearly half.

**Actionable consequence for presets, not just the engine:** an event layer keyed to
`spectral_level_rise` (Nebula's, PR.21) is keyed to the *laggiest* available primitive. Roughly
130 ms is recoverable preset-side by driving the accent from a faster one or compensating, without
touching the audio path.

**And `beatComposite` is independently confirmed as not event-aligned** — r = 0.060 at a *negative*
lag, i.e. essentially uncorrelated with audible onsets. That matches the 42.6 %-above-0.9 duty
cycle measured from the preset side, and the FeatureVector's own comment that the `beat_*` fields
score below chance against real events.

⚠ **Bounds.** Correlations are weak in absolute terms (0.14–0.22) because broadband onset strength
and AGC-normalised band energy are different quantities; the corroboration is that `bass` and
`treble` agree (+145/+175 ms) and that every peak is sharp rather than flat. And this measures tap
capture → feature in a rendered row: it **excludes** output-device buffering between the tap point
and the speaker, and display presentation. The true eye-vs-ear gap is ≥ these figures.

#### The feature-shape half is FIXED (PR.22); the ~145 ms transport half is what remains

The +275 ms measured on `spectral_level_rise` decomposed into ~145 ms transport and ~130 ms of the
field's own fixed-lag design. **PR.22 recovers the second half** with `transientRise` — the same
statistic at 15 ms pre-smooth / 40 ms lag, band re-calibrated to 4–10 dB so its fire rate still
matches the parent's. Measured against offline onset strength: **+30 ms against the parent's
+150 ms**, on both a streaming and a local session.

**So BUG-087's remaining scope is the ~145 ms transport term only.** A preset keyed to
`transientRise` should now sit ~145 ms behind the audio rather than ~275 ms.

#### The remaining term decomposes AGAIN, and the fix route is chosen (2026-09-10)

Measured per primitive on a streaming session (offline onset strength, shared wallclock):

| primitive | lag | r |
|---|---|---|
| `transientRise` (PR.22) | **+30…+45 ms** | 0.18–0.33 |
| `bassDev` | +135 ms | 0.202 |
| `bass` / `mid_dev` | +145 ms | 0.219 / **0.250** |
| `bassAttRel` | +145 ms | 0.159 |
| `mid_att_rel` | +170 ms | 0.142 |
| `bass_att` | **+365 ms** | 0.143 |

**Every continuous primitive sits at ~135–170 ms, and most of that is deliberate band smoothing** —
`BandEnergyProcessor.instantSmoothers` run `rate30: 0.65/0.75/0.75`, i.e. **τ ≈ 77 ms (bass) and
116 ms (mid, treble)**. Real transport is therefore only ~40–60 ms of it.

⚠ **A correction worth keeping:** the raw attenuated band `bass_att` (τ ≈ 650 ms) lags +365 ms, and
extrapolating from that to its `_rel` sibling is wrong — `bassAttRel` measures **+145 ms**, the same
as the instant family. **The deviation transform removes almost all of the attenuation lag**, which
makes D-026's "drive from deviation" a latency rule as well as an AGC-independence rule.

**Matt's call on which lever** (2026-09-10): not the smoothing constants — *"i don't like that the
smoothing constants will change the feel of every preset - too risky"* — but true transport. Scoped
as **BUG087.4** in ENGINEERING_PLAN: drive the analysis clock from the decoded file at the smoothed
playhead instead of from tap arrival, on the local-file path only. Honest ceiling: ~40–50 ms of the
~145 ms, plus removal of the 100 ms staircase. ⚠ And the defect there is **cadence, not staleness** —
`FFTProcessor` already analyses the NEWEST samples of each buffer, so a design premised on stale
audio would aim at the wrong thing.

**The remaining route is smaller buffers from AVAudioEngine** — manual rendering mode, an
`AUAudioUnit` render block with a smaller `maximumFramesPerSlice`, or tapping a different
node. BUG087.1 measured that a plain `installTap(bufferSize:)` request is ignored. **Filed as
its own increment, not a follow-on commit. BUG-087 stays OPEN.**

⚠ A regression test here asserted `hz >= 40` from slice count and **passed**, while the live
capture measured 16.4 Hz — it was measuring the computation rate and calling it the delivered
rate. Renamed and re-scoped, because a green tick against a refuted claim is worse than no
test.

#### Fix landed behind a flag — BUG087.4, the analysis clock decoupled from tap arrival (2026-09-10)

`UZUME_LF_ANALYSIS_CLOCK=1` replaces tap arrival with a **playhead-driven clock** on the
`.localFilePlayback` path: `PlayheadAnalysisClock` ticks at 80 Hz on its own queue, reads the span
the smoothed playhead has just passed out of `LoopingFileReader` (bounded read-ahead over the
already-decoded `AVAudioFile`), and calls the same `onAudioSamples` funnel. Streaming is untouched.

**Measured through the real provider, against a 59.8 fps render:**

| arm | produced | **OBSERVED** | delivery gap | bunched (<2 ms) |
|---|---|---|---|---|
| tap (today, `2026-09-10T22-07-34Z`) | ~47 Hz sliced | **10.01 Hz** | mean 99.8 ms | all slices |
| playhead clock | 80.6 Hz | **59.2 Hz** | median 12.1 ms, p95 17.1 ms | **0 of 237** |

**Observed, not produced — and that distinction is the whole increment.** BUG087.3's gate asserted
`hz >= 40` from *slice count* and passed while the live rate was 16.4 Hz. Both new gates measure the
observed quantity: `sessionRateGate` counts how often a column CHANGES between rendered rows of a
real `features.csv` (it **fails at 10.01 Hz** on the pre-fix reference capture, as a real gate must),
and `deliveryRateGate` buckets deliveries into 1/60 s render windows rather than counting them.

**★ Why 80 Hz and not 60.** The gate is how many distinct values a ~59.8 fps sampler can tell apart.
A 60 Hz clock against a 59.8 fps render is two near-equal rates beating against each other, leaving
a share of render frames with no new value. A 12.5 ms period fits inside a 16.7 ms frame with 4.2 ms
of jitter margin, so the observed rate becomes the render rate.

**★ And no app-layer change was needed, which was not obvious.** The FFT does not run on the
callback's samples: `makeAudioSampleCallback` writes them into the `AudioBuffer` ring
(`UzumeApp/VisualizerEngine+Audio.swift:113`) and reads the newest 1024 frames back OUT of it
(`:152`). The analysis WINDOW and the callback's HOP were already decoupled. So delivering hop-sized
spans keeps a full window *and* makes BUG087.2's audio-derived `dt` exactly right — `frames / rate`
is the playhead advance, which is what every seconds-based follower needs.

**Position source gated before anything was built on it** (BUG087.4's own risk section: a drifting
read position desynchronises analysis, which is worse than being uniformly late). Driving
`AVAudioPlayerNode.playerTime` through `PlaybackClockSmoother` across **3.32 laps of a 1.2 s file**:
`backwards=0, behind-player=0, beyond-band=0, max lead 10.7 ms`. The player's `sampleTime` keeps
counting across a `scheduleFile` loop re-arm, so the position is monotone across the boundary and the
smoother never reads the wrap as a seek; `LoopingFileReader` takes the wrap, where it is a modulo.

**Tap consumers — checked, not assumed (the BUG-070 shape).** Every consumer sits downstream of the
same funnel and is still fed, because what changed is the funnel's SOURCE, not the funnel:
`silenceDetector.update` (`AudioInputRouter.swift:301`), `recordRawTapSamples`
(`VisualizerEngine+Audio.swift:119`), `inputLevelMonitor.submitSamples` (`:130`),
`signalHealthMonitor.ingest` (`:134`), `updateTapSampleRate` (`:143`), `stemSampleBuffer.write`
(`:146`), the `AudioBuffer` ring (`:113`). `SilenceDetector` and `SignalHealthMonitor` are both
time-windowed rather than call-counted, so an 8× rate change does not move their thresholds.

⚠ **One consumer's constants ARE per-call:** `InputLevelMonitor.submitSamples`
(`UzumeEngine/Sources/Audio/InputLevelMonitor.swift:199-201`) runs `peakEnvelope * 0.9995` and an RMS
EMA at `0.95/0.05` per invocation, so its decay time constants shorten with the rate. It drives the
diagnostic level meter, not any preset. Not changed here, and not a new regime: the streaming path has
always fed it at ~47–59 Hz.

**The tap is RETIRED (BUG087.5, 2026-09-11, Matt's call once the fix had landed).** The player node
now carries no tap at all — `PlayheadAnalysisClock` is the only analysis source on this path.
`TapBufferSlicing` went with it (its only consumer was the slicing loop), as did
`UZUME_LF_ANALYSIS_CLOCK`: with no tap to return to, `=0` could only produce silence. A clock that
cannot be built is now a thrown start error rather than a silent downgrade.

**Honest ceiling, unchanged from the design:** this recovers the cadence term (~50 ms average, plus
the 100 ms staircase) out of the ~145 ms on continuous primitives. The remaining τ 77–116 ms is
`BandEnergyProcessor` band smoothing, which Matt declined to change (*"i don't like that the
smoothing constants will change the feel of every preset - too risky"*). Not quietly reduced.

#### RESOLVED — M7 PASSED and the clock is default-on (2026-09-11)

**Matt, watching session `2026-09-11T01-22-10Z` live:** *"I like it. It's punchy. Not exact, but
close."* Measured on that capture, `session.log` line 24 confirming `ANALYSIS_CLOCK: playhead-driven,
80 Hz, file rate 44100` before any number was read off it:

| column | before (`2026-09-10T22-07-34Z`, tap) | after (`2026-09-11T01-22-10Z`, clock) |
|---|---|---|
| `bass` | 10.01 Hz | **59.77 Hz** |
| `mid` | 10.01 Hz | **59.61 Hz** |
| `treble` | 10.01 Hz | **59.20 Hz** |
| `spectralCentroid` | 10.01 Hz | **59.66 Hz** |
| `spectralFlux` | 10.01 Hz | **59.34 Hz** |
| render | 59.77 fps | 59.83 fps |

**5.97×, and the slowest column now changes on 99 % of rendered frames.** The local path matches
streaming's 58.8 Hz. `isEnabled` inverted to default-on; `UZUME_LF_ANALYSIS_CLOCK=0` forces the tap
back, kept because this replaces the audio source of the whole MIR chain on the path all development
runs on.

**Goldens did not move.** The option-A question (regenerate before or after Matt watches) turned out
to be moot: `PresetRegressionTests` renders from fixtures through the harness, which never constructs
`LocalFilePlaybackProvider`, so the clock is not in the golden path at all. Verified by running the
full suite with the clock default-on — no golden regenerated, none needed.

⚠ **The VisualAudioOffset table does NOT demonstrate this win, and cannot — the metric's own
reference moved under the fix.** `recordRawTapSamples` sits inside the funnel
(`VisualizerEngine+Audio.swift:119`), so with the clock driving, `raw_tap.wav` is the CLOCK'S OWN
INPUT rather than the tap's output. The test measures "what `raw_tap.wav` recorded → the feature in a
rendered row", which on this path is now analysis→row, not capture→row. On top of that every band
column reads below the correlation floor on BOTH sessions (`bass` r 0.036, `mid_dev` r 0.049 after;
r −0.058 / 0.042 before), and the one readable column moved `transient_rise` +45 → +50 ms, i.e. inside
the noise of a 20 ms lag grid on different material. **Anyone quoting VisualAudioOffset as a transport
number on the local path must re-derive what its reference now is first.** The rate is what carries
this fix; the ear is what confirmed it.

**Still open, and named so it is not mistaken for this defect:** *"not exact, but close"* is the
band-smoothing term — `BandEnergyProcessor.instantSmoothers` at τ 77 ms bass / 116 ms mid-treble,
which Matt declined to change at the design stage (*"too risky"*) and which this increment did not
touch. That is the next lever on local-path sync, and it is a D-004 trade, not a defect. Preset-side,
`transientRise` (PR.22) already sits ~120 ms ahead of `spectral_level_rise` for event accents.

#### Related

**⇄ BUG-086** — same subsystem boundary, independent cause. The lead that this entry might
explain BUG-086's weak local-file correlation is **refuted** (see Impact). A fix here should
still re-run `Scripts/measure_stem_latency.py` on a local-file capture before and after — not
because the correlation is expected to improve, but so the claim is checked rather than assumed.

### BUG-122 — Dragon Bloom's field drained where the strands were not, and inverted to white (2026-09-08)

**Severity:** P2. User-visible: Matt, on the 21:12 session — *"better with respect to color, although there is still a sizable presence of blinding white."*
**Domain tag:** `preset.render` / feedback dynamics · failure class **`fidelity`**.
**Status:** **Fixed 2026-09-08 (PR.5.4).**
**Introduced:** PR.5.2 (removed the outward push); made worse by PR.5.3 (signed breathing — the inward half drains).
**Resolved:** 2026-09-08.

**Reported.** Blinding white remained after PR.5.1–5.3. Measured per frame on his session, `nearWhite` reached **0.448** at frame 1050 (the pre-chorus drop, 16.9–18.9 s), with the field's top half at luma 0.2–0.4 — dim, not black — which invert + gamma render as white.

**What the filing got wrong.** The row was filed as *"a vertical split the reference does not have."* The oracle's "flat" profile came from a single 120-frame sample. Measured properly — `render({audioLevels, elapsedTime})` driven offline from the decoded track at 60 fps, because the Browser pane is hidden and rAF/timers do not run — the reference's field swings **0.30–2.59** top/bottom on this track, harder than ours, and its display shows `nearWhite` **0.000** through the drop. The reference tolerates an unfed half because its field never drains.

**Partition.** Warp loop alone (strand alpha 0, uniform ground): symmetric, 1.08. Strand landing positions 52/48, segment-length coverage 52.7/47.3, injected colour uniform across eight bands. Per-frame ink share is bimodal (p10 0.002 / p90 0.948, mean 0.500) — a tumbling one-sided ribbon — so at any instant one half is unfed. That is faithful; the source's ribbon does the same.

**Cause.** The source keeps the field fed with `zoom *= min(1.05, max(1, max(bass, treb)))`: outward only, capped at +5 %. Measured on the oracle with real audio: at the cap on **60 %** of frames, floor on 35 %, mean **+3.15 %**, median still 1.05 at the drop. Our primitives are deviations (≈0 at the running average), so PR.5.2's music-only outward term was silent exactly during quiet passages, and PR.5.3's signed form pulled inward there — sampling from further out every frame collapses the field toward the centre and the periphery starves.

**Fix.** `z *= 1 + 0.03 + 0.02·tanh(max(0, bass_att_rel)/0.06)` — an always-on +3 % outward baseline (the oracle's mean) with the music to the source's 5 % cap. On the 21:12 session: `nearWhite` **0.000 on every sampled frame**, saturation 0.52, clip 0.062; field ratio 0.60–1.66 (like the reference's), with no white because nothing drains.

**Falsified, recorded so they are not retried.** Strand-alpha floors 0.15/0.30 (0.454/0.458 — no change); 8-bit feedback emulation (0.316); `max(bass, treb)` on our deviation primitives (identical to bass-only — `treb_att_rel` is +0.002 at the drop); a post-invert soft ceiling (cannot brighten an empty field, 0.423); a vertically mirrored second strand set (with the outward-only music term: 0.078 — fixes the symptom by feeding both halves, but the reference does neither and needs neither once the field stays fed).

**Verification.**
1. ✅ Offline oracle at the drop: nearWhite 0.000, saturation 0.84–0.98 — the control the fix is measured against.
2. ✅ Ours, same session, same frames: 0.448 → 0.000; the vertical swing is unchanged and harmless.
3. ⏳ Live: Matt has not seen PR.5.4. Every number is offline replay of his own capture.

### BUG-124 — vocal pitch was thrown away, not absent: YIN's step-4 fallback was missing (2026-09-09)

**Severity:** P2. Two increments wrote `vocalsPitchConfidence` off as unusable on the strength of its output; a preset (Gossamer) keyed its signature visual — hue from vocal pitch — to a primitive that could not deliver.
**Domain tag:** `dsp.analysis` · failure class **`algorithm-incomplete`**.
**Status:** **Fixed 2026-09-09.**
**Found:** Matt pushed back on a ceiling claim — *"there HAS to be a way to improve vocal signal"* — after being told the failure looked like a limit. He was right.

**The defect.** `PitchTracker` documents itself as implementing YIN (de Cheveigne & Kawahara 2002) and implements step 4 halfway. The paper: *set an absolute threshold and choose the smallest tau that gives a minimum of d' deeper than that threshold; if none is found, the global minimum is chosen instead.* `findMinimum` returned -1 on a miss and the frame was discarded.

**Why that hid itself.** Confidence is `1 - d'[tau]`, and tau was only returned when `d' < 0.15`, so confidence was **either 0 or > 0.85** - bimodal by construction. On 1290 real frames, **0.0 %** landed strictly between. A consumer cannot gate on a signal with no middle: Gossamer's `> 0.35` emission gate could never fire on anything the 0.85 branch did not already give it, and the tracker's own `confidenceThreshold = 0.6` was unreachable.

**Why it failed on good material.** On realistic separation noise the global CMNDF minimum sits at **0.159-0.167** - just above the 0.15 gate, so the detector ran on a knife-edge. Seven Nation Army - about as prominent a vocal as exists - gave confidence on 23.3 % of frames and **24.5 % on its loudest vocal quartile**: no better when the vocal was loudest, which is what pointed at the algorithm rather than the material.

**Hypothesis measured and dropped.** Window size is not the lever: 2048 -> 4096 moves the minimum 0.159 -> 0.165 and changes no detection rate, at 100 / 150 / 220 Hz.

**Fix + measurement (production capture chain, Seven Nation Army, 1290 frames).**

| | before | after |
|---|---:|---:|
| confidence > 0.35 | 23.3 % | **79.9 %** |
| median confidence | 0.000 | **0.610** |
| frames with 0 < c < 0.85 | 0.0 % | **71.5 %** |
| pitch reported | 23.3 % | **51.0 %** |
| loud-vs-quiet discrimination | +8.7 pts | **+25.1 pts** |
| reported pitch, median | 76 Hz | **130 Hz** |
| pinned below 85 Hz (range edge) | **73.0 %** | 25.5 % |

**The old output was mostly junk, not scarce signal.** 73 % of pre-fix pitches sat at the bottom of the search range - some below the tracker's own 80 Hz floor via the EMA - the signature of a boundary minimum rather than a detected period. After the fix the distribution is a male vocal register.

**Residual, not chased:** 25.5 % still floor-pinned, most likely the bass riff bleeding into the separated vocal stem.

**Caveat found 2026-09-09, same day: the fix recovers PERIODICITY, not VOCALS.** Measured through the
capture chain, *Weeping Wall* — a purely instrumental Bowie piece — scores a **94.8 %** pitch-confidence
duty cycle, **above** Seven Nation Army's 79.9 % and Combat Baby's 85.6 %. Its separated "vocals" stem
carries median energy **0.301** and reads as pitched at **132 Hz**, against Seven Nation Army's 0.339
and 130 Hz — statistically indistinguishable. The stem is full of periodic bleed on instrumentals.
So `vocalsPitchConfidence` is a *pitched-content* signal, not a vocal-presence signal, and must not be
used as one: it cannot gate "is someone singing", and Gossamer's emission gate now opens on 94.8 % of
an instrumental's frames. This does not diminish the fix — the primitive went from unusable to usable —
but it bounds what it can be used for.

**What this invalidates.** This file recorded `vocalsPitchHz`/`vocalsPitchConfidence` as SPARSE at 0.1 % nonzero and called the pair "garnish"; WL.1 measured 4.5 % and called it garnish there too. Both were measuring this defect. Whether the primitive is a usable hero driver is an open question again, not a settled one.

**Verification.**
1. Before/after through the production capture chain on the same file, same instrument.
2. Recovered frames discriminate loud from quiet vocal 3x better than before - signal, not noise.
3. Recovered pitch lands in a plausible vocal register; boundary-pinning falls 73 % -> 25.5 %.
4. Engine suite 1915 tests pass; PitchTrackerTests 7/7 (its sine-wave cases are unaffected).
5. ✅ **Seen live 2026-09-09** (session `19-09-58Z`, Matt on Gossamer: *"looks pretty good"*). Independent
   generalisation, not a repeat: **different track, different singer, different register, and the LIVE tap
   path** rather than the offline capture chain — Metric, *Combat Baby*, a female vocal, 5367 frames.
   conf > 0.35 **17.1 % → 85.6 %**; median **0.000 → 0.614**; frames with 0 < c < 0.85 **0.0 % → 83.0 %**;
   pitch reported **17.1 % → 51.8 %**; median pitch **76 → 142 Hz**; floor-pinning **73.0 % → 5.9 %**.
   The floor-pinning being far lower here than Seven Nation Army's 25.5 % supports the residual there being
   bass bleed in the separated stem rather than a tracker fault.

### BUG-123 — Dragon Bloom remains paler than the reference (2026-09-08, PARKED)

**Severity:** P3. Matt, on the PR.5.4 build: *"Color is better but still washed out. It doesn't feel like we can solve this. Maybe we should stop and move on?"* — and then: *"stop and proceed with another PR increment."*
**Domain tag:** `preset.render` · failure class **`fidelity`**.
**Status:** **Parked on Matt's call.** Reopen only as a single bounded increment.

**Measured.** Seven Nation Army, display with comp on. Reference (offline oracle, 10–40 s): luma 0.37 (0.25–0.53), saturation 0.89. Ours (22:41 session, 1800 frames): luma 0.57 (max 0.81), saturation 0.65. The gap is tone, not structure: no white-outs (nearWhite 0.006), no flashes, balanced field.

**Why PR.5.4 missed it.** Its success metric was `nearWhite` (all channels ≥ 235). Pale cream is 170–230 in the low channel. The metric measured the thing that was fixed and could not see the thing that remained — record this alongside the span artifact and the track-averaged `nearWhite`.

**Where to look if reopened.** Our accumulator runs roughly twice the reference field's brightness on the same material (ours 0.75 field luma at the drop vs the reference display 0.20 → field ≈ 0.8 inverted… measure it directly, do not infer). Candidates not yet tested: the strand ink stored as HDR (`hi` up to 2.0 in a float target; the reference clamps at 1.0 on write — probe F tested only nearWhite, not luma), and the ×4 boost the oracle applies before analysis (our stem energies are not boosted the same way). One increment, one comparable number, hard stop.

### BUG-120 — Witchlight's pulse tier rode bar position instead of the beat grid (2026-09-08)

**Severity:** P1. On any track without a detected meter the preset lost both of its tiers and went silent.
**Domain tag:** `preset.routing` · failure class **`algorithm`**.
**Status:** **Fixed 2026-09-08 — live-confirmed by Matt the same day.**
**Introduced:** WL.9.
**Resolved:** 2026-09-08.

**Reported.** *"Witchlight does not appear to be working. FFO is working fine."* Session `2026-09-08T14-09-48Z`: `beatsPerBar == 1` on 57 % of frames, bar phase correctly 0 on every one of them.

**Expected.** Two tiers, per WL.9's own comment: every beat pulses, the downbeat harder. Matt's expectation matched it exactly — *"Witchlight… adds a large pulse at every downbeat."*

**Actual.** The pulse tier derived beat edges as `slot = Int(barPhase01 * beatsPerBar)`, so it rode bar position too. With `beatsPerBar == 1` there is a single slot, the slot never changes, `beatEdgeNow` never fires, and the per-beat pulse is dead — leaving only the bass-excursion fallback.

**Why it surfaced only now.** A meterless grid used to ramp `barPhase01` at BEAT rate (BUG-117), so `barDownbeatNow` fired on every beat: Witchlight had accents, just wrong ones, and read as over-eager rather than dead. Fixing BUG-117 correctly silenced the accent and took the pulse with it, because both were reading the same input.

**Fix.** `detectBeatEdge` reads `beatPhase01` and detects its wrap. Beat phase is published whenever a grid exists, meter or not, so the pulse survives a meterless track while the bar ACCENT is withheld — which is the two-tier design as written: the strong signal carries the pulse, the weak one only the emphasis.

**A test encoded the old coupling.** The BUG-097 heavy-frame regression drove `barPhase01` and never `beatPhase01`, which a real grid always publishes together. Invisible while the pulse was derived from the bar; a false failure the moment it was not. The helper now supplies both, and its assertions are unchanged.

### BUG-121 — one quiet window condemned the session and nudged the listener (2026-09-08)

**Severity:** P2. User-visible: a toast telling Matt his audio chain is bad during ordinary listening, and every affected session graded `degraded`, which the closeout protocol requires be flagged before any fidelity judgement.
**Domain tag:** `audio.capture` / calibration · failure class **`calibration`**.
**Status:** **Fixed 2026-09-08.**
**Introduced:** ASH.2 (the toast) and D-197 (the verdict latch).
**Resolved:** 2026-09-08.

**Reported.** *"In the last few sessions, I was seeing notifications that the signal source was low… this has been a problem historically, and I would like to resolve it once and for all."*

**Expected.** The nudge means the capture chain is misrouted or the source is too quiet to drive the visuals.

**Actual.** It fired on a single 5-second window. Across every session on disk:

| session | verdict | healthy | low | critical |
|---|---:|---:|---:|---:|
| 2026-09-06T00-17-00Z | **degraded** | 67 | 0 | **1** |
| 2026-09-08T13-58-15Z | **degraded** | 19 | 0 | **1** |
| 2026-09-08T14-09-48Z | **degraded** | 33 | 0 | **1** |
| four others | clean | 9–31 | 0 | 0 |

Every degraded verdict is exactly one window. `band=low` has **never** fired in his history — the trigger was always a lone `band=critical` at −18.6 to −24.5 dBFS, landing mid-session (sample 59 of 68, 10 of 20, 21 of 34), which is a fade, a gap between tracks or a soft passage.

**Why the previous fix did not hold.** D-197's follow-up already addressed this once, as "degraded only after loud": a low window counts only if a healthy one preceded it. That removes the quiet OPENING and nothing else, so the same false positive simply moved into the middle of the song, where every track has one.

**Fix.** Both the live toast (`PlaybackErrorBridge`) and the offline verdict (`ChainAnalyzer`) now require **3 consecutive** low/critical windows, from one shared constant so the toast the listener sees and the verdict a closeout cites cannot disagree. At the ~5 s cadence that is ~15 s during which the peak never once crossed −15 dBFS. Music does not do that while playing; a misrouted chain does it permanently. A healthy window resets the run, so two separate dips in one song stay two dips.

**Verification.**
1. ✅ Re-grading his real sessions with the corrected rule flips every false positive to `clean`, and the sessions that were already clean stay clean.
2. ✅ Negative control: a chain quiet in **every** window still grades `degraded` — the check keeps working.
3. ✅ Boundary asserted: a run of 2 does not flag, a run of 3 does, so the threshold cannot be loosened silently.
4. ✅ Toast: a lone quiet window raises nothing; a healthy window resets the run.

### BUG-119 — the beat pulse held one average BPM for a whole track (2026-09-08)

**Severity:** P1. It reaches every preset driven by the pulse primitives, on every track.
**Domain tag:** `dsp.beat` / `preset.routing` · failure class **`algorithm`**.
**Status:** **Fixed 2026-09-08 — pending Matt's live confirmation.**
**Introduced:** FBS Stage 1 (D-153) — the pulse has always been seeded this way; PR.12 made it visible by changing which average got installed.
**Resolved:** 2026-09-08, branch `claude/bug118-tiled-grid-regression`.

**Reported.** Matt, 2026-09-07: *"Ferrofluid Ocean is pixelated / grainy - doesn't look like it used to look."* Then, after the reverts: *"Yes, FFO's grain is back to normal"* — which is what identified the cause, because only the beat-grid changes could reach FFO.

**Expected.** The pulse's period tracks the music.

**Actual.** `MIRPipeline.setBeatGrid` called `beatPulseClock.setTempo(bpm: grid?.bpm)` once per track. `setTempo` computes `periodS = (60 / bpm) * 4` and nothing revisits it for the rest of the song. A single median BPM therefore governed the pulse for an entire track — and when PR.12 changed which median was computed, the pulse moved with it: bleed 115.0 → 123.6 BPM, money 116.2 → 129.3, bohemian 78.2 → 94.2. Ferrofluid Ocean's `spike_punch_region` accents then fire 7–20 % off the beat, which reads as spatial incoherence rather than a pulse.

**Fix.** `BeatPulseClock.trackLocalBeatPeriod(_:at:)` follows `BeatGrid.localTiming`'s LOCAL seconds-per-beat, published each frame by `LiveBeatDriftTracker.lastLocalBeatPeriod` (read from the tracker, not the grid, because the tracker owns the mapping from the live clock onto track time). Two properties it has to have, both tested:

- **No phase jump.** Phase is `(time − anchor) / period`, so changing the period without re-anchoring rewrites history. The anchor is rewritten to preserve elapsed **beats**, which keeps `phase01` and `beatIndex` continuous through a rate change.
- **No wobble.** A raw beat-to-beat period is noisy, so it is smoothed (α = 0.02/frame) and the anchor is only rewritten past a 0.5 % relative change. One stray beat does not move the pulse; a sustained change is followed.

**This is the instruction that was still being ignored.** Matt, 2026-09-04: *"you should not be averaging BPM / tempo, you should be recording it over the duration of the track so that visuals are better synced."* PR.12 widened the analysis window and then collapsed the result back into one number at track change, so the averaging survived the fix that was supposed to remove it.

**Verification criteria.**
1. ✅ Automated: phase continuity through a 10 % tempo change; a single outlier period does not move the pulse while a sustained one does.
2. ⏳ Manual: Matt watches Ferrofluid Ocean on a local file and the grain does not return when whole-track grids are re-enabled. **Outstanding — this is the gate for turning BUG-118's default back on.**

### BUG-118 — the tiled whole-track grid is worse than the 30 s clamp it replaced (2026-09-07)

> ⚠ **CORRECTION, same day.** The table below scored each arm over ITS OWN span — a 30 s grid
> graded on 30 s against a whole-track grid graded on six minutes. That is the artifact this
> repo already knew about (PR.12 identified it in FT.4.1's numbers) and it invalidates the
> comparison. **Re-run span-matched, the whole-track grid is equal or better on every track:**
> bleed's headline "0.99 → 0.76" is **0.98 → 0.98** with CMLt 1.00 either way; yyz improves
> 0.57 → 0.63; money's CMLt improves 0.43 → 0.47. Nothing regresses.
>
> **What IS real, and is not a span artifact:** billie_jean's beats are uniformly good across
> the whole track (|IOI − median| flat at 8–9 ms in every tenth) while its downbeat F falls
> **0.90 over the first 30 s → 0.37 across the full track**, against the same full-track
> reference. Whole-track BEATS extend correctly; the model's downbeat head does not.
>
> The lasting fix is the instrument: `BeatBench --span-seconds N` now trims estimate and
> reference to the same window, and every run states which mode it used. This artifact has
> produced two wrong conclusions here — FT.4.1's and this entry's — and should not produce a
> third.
>
> **RESOLVED 2026-09-08 — whole-track grids are ON again** (Matt: *"turn it on"*). Every
> objection to them was a measurement artifact, and Matt caught both. The second one: the
> claim that whole-track analysis degrades DOWNBEATS rested on billie_jean's dbF 0.90 → 0.37,
> and its downbeat reference stops at **69 s of a 286 s track** (librosa extended the beats
> and emits no downbeats), so every correct downbeat past 69 s counted as a false positive —
> precision 34/139. Scored inside the reference's real coverage the same comparison is
> **0.90 → 0.97**, and whole-track wins on 6 of 7 fixtures. `DownbeatScore` now trims to the
> downbeat reference's own extent.
>
> On 17 plain-4/4 tracks (Matt's Bowie album plus the suite-1 rock/disco fixtures) coverage
> goes **18.2 % → 97.8 %** with meter unchanged at 13/17; Giorgio by Moroder covers **0 %**
> clamped because its opening 30 s are spoken word. His session `2026-09-08T14-34-06Z` shows
> why coverage is what he feels: drift is flat inside the first 30 s (15 ms) and ramps past it
> (67 ms at 50–60 s) — the grid's edge.
>
> The two things that made it HURT are fixed separately and verified in that same session:
> BUG-119 (the pulse held one average BPM — FFO's grain) and BUG-117 (a meterless grid faked
> bar position — the roster breakage). Cache schema v13 forces re-analysis, because a clamped
> grid is data and turning the analysis back on does not reach it.

**Severity:** P1. It is the default for every local file, and it degrades the signal every beat-driven preset consumes.
**Domain tag:** `dsp.beat` · failure class **`algorithm`**.
**Status:** **Open.** Default reverted to the clamped grid; the tiler is unfixed.
**Introduced:** PR.12 (2026-09-04, PR #197).
**Resolved:** —

**Reported.** Matt, 2026-09-07, after the BUG-117 revert did not restore the presets: *"There are still issues with FFO due to changes you introduced. You haven't reverted enough if presets are still broken."* Then, on scope: *"we need whole-track grids and counted meters. But perhaps they were not implemented correctly."* He was right on both.

**Expected.** Analysing the whole track instead of its first 30 s gives a grid at least as good as the clamp, over the whole track.

**Actual.** Five-suite BeatBench, clamped arm vs whole-track arm:

| suite | track | truth BPM | clamped | tiled | F clamped | F tiled | CMLt clamped | CMLt tiled |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | billie_jean | 117.44 | 116.88 | 117.13 | 0.97 | 0.99 | 0.97 | 0.97 |
| 2 | pyramid_song | 66.60 | **65.08** | 82.47 | 0.52 | **0.22** | 0.75 | **0.21** |
| 2 | solsbury_hill | 102.44 | 102.68 | 104.80 | 0.97 | 0.98 | 1.00 | 0.94 |
| 2 | take_five | 167.07 | 169.24 | 171.44 | 0.99 | 1.00 | 1.00 | 1.00 |
| 2 | yyz | 272.27 | **233.61** | 145.85 | 0.58 | **0.41** | 0.21 | **0.05** |
| 3 | bohemian_rhapsody | 71.10 | **78.18** | 94.23 | 0.47 | 0.52 | 0.48 | 0.36 |
| 3 | money | 121.06 | **116.19** | 129.32 | 0.44 | **0.24** | 0.43 | **0.17** |
| 4 | bleed | 114.67 | **115.00** | 123.62 | 0.99 | **0.76** | 1.00 | **0.56** |
| 5 | clair_de_lune | 49.91 | 128.63 | 96.44 | 0.14 | 0.06 | 0.00 | 0.01 |

**The BPM column is span-independent** — a tempo estimate is not affected by how much of the reference a scorer trims — and it is worse on 5 of the 6 tracks where the two differ. billie_jean's downbeat F also falls **0.90 → 0.37**.

**How it shipped.** PR.12's closeout claimed "beat F equal or better on 8 of 9 fixtures". That measurement trimmed both arms to a common span to remove a real scoring artifact, which was correct as far as it went — and then it was treated as sufficient. The program requires a **five-suite BeatBench table for any behavioural change to a beat signal**, and that table was never produced for the shipping configuration, through PR.12, PR.17, and two closeouts that cited beat numbers.

**Prime suspect, not yet confirmed.** `BeatThisTiledInference` averages overlapping windows with uniform weight, so frames at a window's EDGE — where the model has little context — are averaged in at the same weight as frames from another window's well-conditioned middle. The standard remedy for overlap-add inference is a tapered cross-fade. A first probe looking for periodic IOI irregularity at the 15 s seam found only 1.11× pooled, which is too weak to call; tempo accuracy rather than IOI regularity is the better place to look next.

### BUG-117 — a declined bar estimate says "every beat is a downbeat" (2026-09-07)

**Severity:** P1. It reaches every preset that consumes bar position, on every track where the estimator declines.
**Domain tag:** `dsp.beat` · failure class **`api-contract`**.
**Status:** **Fixed 2026-09-08** — pending Matt's live confirm. `BeatGrid.hasBarInformation` makes the state expressible; bar phase holds and `isDownbeat` stays false without it. ⚠ **Shipped once with a hole:** the predicate was `!downbeats.isEmpty || beatsPerBar > 1`, and non-empty downbeats do NOT mean the bars are known — the over-firing head fills that array precisely when it knows least. Matt's session `2026-09-08T13-58-15Z` proved it in the field: 2,549 frames correctly claimed no downbeat while bar phase still ramped to 0.99 on every one of them. Corrected to `beatsPerBar > 1` — the meter is the whole test.
**Introduced:** the encoding dates to FT.4 (`applyBarLineEstimate`); PR.17 (2026-09-05) made it reachable by default on local files.
**Resolved:** —

**Reported.** Matt, 2026-09-07, after one session on the 2026-09-05 build: *"Ferrofluid Ocean … the beat sync is worse not better. Fractal Tree is too animated. Witchlight has no pulse. The pulse of Aurora Veil is no longer in sync with music. Everything is worse."*

**Expected.** A grid that found no bar structure reports that it has none, and a preset reading bar position gets nothing to fire on.

**Actual.** It reports `beatsPerBar = 1` with an empty `downbeats` array. `BeatGrid.beatsSinceDownbeat` then falls back to `idx % max(beatsPerBar, 1)`, which is **0 for every beat** — so `beatInBar` is always 1 and `isDownbeat` is always true. A bar-locked event fires on every beat instead of every fourth; a bar-phase reader gets a constant.

Session `2026-09-06T00-17-00Z`: **`beatsPerBar == 1` on 18,040 of 19,833 frames (91 %)**, **`is_downbeat == 1` on 18,559 (94 %)**.

**The mechanism it rode in on is not the defect.** The windowed estimator decodes take_five as 5/4 across 11 of 11 windows and money as 7/4 — cases four previous levers failed on — with 20 correct and 0 incorrect over 68 labelled windows. What it also does, far more often than the model's downbeat head did, is DECLINE. The decline encoding was rare enough to go unnoticed before and became the common case after.

**Why the review did not catch it.** `beatsPerBar = 1` was observed in session `2026-09-05T18-17-12Z` during the BUG-116 investigation, noted, and not followed up. The PR.17 commit message asserts a declined track is *"the same shape a track with no detected bars already produces, so consumers need no new case"* — that claim was never checked against `beatsSinceDownbeat`, and it is false.

**A fix has to decide what "no bars" means on the wire.** `beatsPerBar = 0` with the modulo fallback removed, or an explicit optionality on `BeatGrid`, or `beatsSinceDownbeat` returning nil when `downbeats` is empty. All three touch every consumer, which is why this is its own increment and not a patch to the revert.

### BUG-116 — the pre-analysed stem series is dead ~0.4 s in every 2 s on non-44.1 kHz local files (2026-09-05)

**Severity:** P1. Every local-file session at 48 kHz — which is what the tap reports on this machine — runs with all four stems at zero for roughly 15 % of playback, in a strict 2-second rhythm. Stem-driven presets visibly pulse dark; stem-driven *routing* silently reads zero.
**Domain tag:** `dsp.stem` · failure class **`sample-rate`**.
**Status:** **Fixed 2026-09-05 — pending Matt's live confirmation on a 48 kHz album.**
**Introduced:** LFSTEM.1 (the pre-analysed series). NOT the 2026-09-05 merges — `SessionPreparer+StemSeries.swift` was last touched at RN.2, a rename.
**Resolved:** 2026-09-05, branch `claude/bug116-stem-series-holes`.

**Reported.** *"Now there are issues with Ferrofluid Ocean — screen goes dark every few seconds."* Session `2026-09-05T18-17-12Z`, Broken Social Scene MP3s, local files, `CHAIN_HEALTH: verdict=clean`.

**Expected.** `StemFeatureSeries` carries a continuous per-frame stem reading for the whole track. A preset driven by stem energy sees the music, and nothing else.

**Actual.** All four stems (`drums`, `bass`, `vocals`, `other`) decay smoothly to **exactly 0.000** and snap back, **68 times**, spaced **2.00 s ± 0.03** apart, each lasting **~0.37 s**. The renderer is innocent: `DRAWABLE_LIFECYCLE` reports zero failures and zero unpresented frames throughout, and `stem_series_pos_s` advances smoothly — the clock is right and the data is empty. The holes are baked into `stem_series.bin` in the persistent cache, so this is an offline artifact, not a playback race.

**Root cause.** `StemSeparator.separate(audio:channelCount:sampleRate:)` resamples any input to its own `modelSampleRate` (44,100) and then pads-or-truncates to exactly `requiredMonoSamples` (440,320). Its output is therefore ALWAYS in the model's time base. `SessionPreparer.analyzeStemSeries` slices that output with offsets computed in the **input's** sample rate:

```swift
let offset = absolute - windowStart          // input-rate samples
let slice = stems.map { Array($0[offset..<(offset + hop)]) }   // model-rate samples
```

At 48 kHz, a 440,320-sample input window is 9.17 s of audio; resampled to 44.1 kHz it fills 404,544 samples, and the remaining **35,776 samples are zero padding**. The function deliberately places each kept 2 s span at the very END of the window (one analysis frame of room), so the span lands squarely in that padding — the last ~0.7 s of every span reads silence, of which the ~0.4 s below the 0.01 threshold is what shows up as a hole.

**Reproduction (one variable).** `UZUME_STEM_SERIES_PROBE=1 UZUME_STEM_SERIES_RATE=<44100|48000> UZUME_STEM_TAIL_AUDIO=<file> swift test --package-path UzumeEngine --filter StemWindowTailProbe`

| input rate | near-zero frames | holes |
|---|---|---|
| 44,100 | **0 of 1722** | none |
| 48,000 | **279 of 1875 (14.9 %)** | 9.62–10.01 s, 11.63–12.01 s, 13.65–14.02 s, … |

The 48 kHz frame indices reproduce the cached series that fed Matt's session exactly (451–469, 545–563, 639–657, 734–750, 826–844, 921–938).

**Falsified on the way.** The separator's own window tail was the first suspect and is innocent: measured per-100 ms RMS across a full window, tail/mid is 0.63–0.78 for every stem, tracking the input's own envelope. The model does not fade at its edges; the padding is the whole story.

**⚠ Cached entries are poisoned.** The holes are in `stem_series.bin` on disk. A code fix alone leaves every already-analysed track broken — the fix must invalidate or version the persistent stem cache.

**Why it appeared on 2026-09-05 and not earlier.** Two separate answers. The code broke at **LFSTEM.1a (2026-08-26, `dea021d8`)**, which switched local files from live separation — whose slicing is correct — to the pre-analysed series. It became *visible* tonight because of the album: *Low* is 44,100 Hz, the one rate at which input and model rate agree and the defect cannot occur, and Broken Social Scene is 48,000 Hz on all thirteen tracks. The sibling live path had the rule right all along, under a comment citing D-079: *"Stem waveforms are at the model rate, not the tap rate."*

**Verification criteria (written before the fix), and their outcomes.**
1. ✅ Automated: `analyzeStemSeries` at 48 kHz produces zero near-zero frames, and the frame grid no longer depends on the input rate. Parameterised over **44.1 / 48 / 96 kHz** — 44.1 kHz alone cannot see this, which is how it shipped. **Both new tests were run against the un-fixed code and fail there** (48 kHz arm reads silence; grid 258 vs 281 frames).
2. ✅ Automated: schema v10 → v11 means every poisoned entry is a miss and re-analyses.
3. ⏳ Manual: Matt watches Ferrofluid Ocean on a 48 kHz local file and the periodic darkening is gone. **Outstanding.**

### BUG-115 — Dragon Bloom's bass breathing is an absolute threshold on AGC-normalised bass (FA #31) (2026-09-05)

**Severity:** P3. Visible impact is entangled with the white-out PR.5 addressed separately, and the obvious fix makes the render worse — see Status.
**Domain tag:** `preset.routing` (deviation primitives / D-026).
**Status:** **Open — root cause understood, fix NOT obvious.** Found and measured at PR.5 (2026-09-05).
**Introduced:** D-137 (2026-06-02), present at certification.
**Resolved:** —

**Expected.** D-026 and FA #31: a preset drives from deviation primitives (`bass_rel`, `bass_dev`), never from an absolute threshold on AGC-normalised energy. The AGC's running-average denominator moves with mix density, so the same kick reads different values across tracks.

**Actual.** `mvWarpPerVertex` in `DragonBloom.metal` breathes the bloom with `clamp(1.0 + 0.06 * (f.bass * 6.0 - 1.0), 0.97, 1.07)`. The term is neutral only at `f.bass == 1/6`; everywhere else it is a standing zoom bias whose size depends on the AGC's state rather than on the music. Measured on a real Bowie *Low* capture through the production analysis chain: median `f.bass` 0.236, so the term sits at **1.024 median, 1.070 at p90** — a 2.4–7 % outward warp applied every frame, against the source preset's 0.99951 baseline whose own code comment says it *"prevents the field draining off-edge / white-collapse."*

**Why it is not simply fixed.** Converting the route to the signed deviation primitive `bass_rel` — the textbook remedy — was measured through the production `direct + mv_warp` dispatch on the same capture and made the render **worse**: clipped 0.836 → 0.868, saturation 0.265 → 0.099. The outward push is not draining the field; it is the conveyor that carries strand colour out from the centre before the warp transfer's B-fade extinguishes it. Slow it and the colour dies closer in, so coverage falls. The change was reverted.

**What a real fix needs.** The routing and the fill dynamics together: a `bass_rel`-driven breath plus whatever restores coverage at a near-neutral baseline (faster hue-zoom spread, or a slower B-fade). That is preset-design work, not a constant swap.

**Evidence.** `docs/diagnostics/PR5_DRAGON_BLOOM_FIX_2026-09-05.md` §3 (the falsified arm, with both arms' numbers). Repro: `UZUME_GEN_SESSION_AUDIO=<a Low track> swift test --filter FixtureSessionCaptureGenerator`, then `REPLAY_MULTIPASS=1 REPLAY_PRESET="Dragon Bloom" ... swift test --filter SessionDrivenMultiPassReplay`.

### BUG-084 — `StemAnalyzer` deviation reaches 35 where the primitive's real ceiling is ~3.4 (suspected EMA divide-by-tiny) (2026-08-03)

**Severity:** P3. No known product impact today — the one consumer that could have been hurt (FFO's aurora intensity) is defended by the FBS.S3.2 soft knee, which caps 35 → 1.64. Filed because the *input* is wrong, not the output: any future consumer that reads a stem deviation without a soft knee inherits the bug, and the value silently poisons any statistic computed over stem deviations.
**Domain tag:** `dsp.stem` (deviation primitive / EMA convergence).
**Status:** **Open — unreproduced, not investigated.** Carried as an inline aside inside BUG-041 from 2026-06-10 until that entry closed as stale (RECON.2, 2026-08-03); filed properly here so it survives its parent's closure. This is the whole reason BUG-041 could be closed safely.
**Introduced:** unknown; present at least since 2026-06-10.
**Resolved:** —

**Expected.** Deviation primitives (`bassDev`/`drumsEnergyDev` and siblings, D-026) express a band's deviation from its own running EMA. Measured against real music they spike to roughly **3× with a p99 near 0.85** — the documented real range, and the basis for the "soft-saturate against p99, never against 1.0" rule (CLAUDE.md FA #73).

**Actual.** Session `2026-06-10T17-50-56Z` (So What) produced `dev = 35` — an order of magnitude past the primitive's observed ceiling, and 3–30× the track median across an all-stem burst.

**Suspected mechanism.** `StemAnalyzer` resets per track and its per-stem EMA re-seeds from near-zero. A deviation computed as a *ratio* against that not-yet-converged baseline divides by a near-zero denominator, so the quotient explodes during the convergence window. This is the same shape as the BUG-027 / AGC2.4.1 cold-start family that was fixed for the FeatureVector band devs; the stem-side twin may simply never have received the equivalent guard.

**Reproduction steps.** Not yet attempted. Start point: replay the `fbs/` fixtures that captured the burst (`stemsum_so_what_2026-06-11T01-56-22Z.csv` and siblings retained in `UzumeEngine/Tests/UzumeEngineTests/Fixtures/fbs/`) and log the raw pre-soft-knee deviation alongside the EMA denominator through the first ~10 s of a track.

**Suspected failure class:** `numerical` (divide-by-near-zero during EMA convergence).

**Verification criteria:**
- [ ] Raw stem deviation confirmed against the ~3.4 ceiling on the fixtures above, with the EMA denominator logged — i.e. mechanism *observed*, not inferred, per the evidence-before-implementation gate.
- [ ] If confirmed, a floor on the denominator (or the BUG-027-family guard) brings the primitive inside its documented range without changing musical response — the soft knee's output must not measurably move for normal values.
- [ ] No regression in FFO aurora behaviour (the soft knee stays; this fixes the input, not the defence).

**Manual validation required:** No, if the fix leaves the soft-kneed output unchanged for musical values — the automated FBS gates cover the visible surface. Yes if the fix alters aurora response at all.

**Related:** BUG-041 (closed as stale 2026-08-03 — this was its inline aside); BUG-027 / AGC2.4.1 (the FeatureVector-side twin, fixed); CLAUDE.md FA #73 and [[deviation-primitive-real-range]] for the documented real range.

---

### BUG-060 — One-off app hang: the render loop died on a `preset → Gossamer` switch; force-quit required; not reproduced (2026-06-18)

**Severity:** P3 (a full app hang requiring force-quit is P1-*impact*, but it was seen once and did not reproduce — Gossamer ran 3× clean the next session; filed as **monitored**, like BUG-058, pending a recurrence with a captured stack).
**Domain tag:** renderer / app.hang (suspected preset-apply or first-frame GPU hang on Gossamer).
**Status:** **OPEN — RECURRED (Matt, 2026-08-03; RECON.2).** The prior "likely resolved by NACRE.2b" status is **falsified as a complete explanation** and must not be restored without new evidence. Asked directly during the 2026-08-03 production audit whether the force-quit hang had been seen since mid-July, Matt confirmed it had. No session ID, preset, or stack was captured for the recurrence, so the *mechanism* is still undiagnosed — what changed is that the empty-`activePasses` guard is now known to be **insufficient**, which was the exact residual risk the previous status flagged ("the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains"). That residual is now the leading hypothesis rather than a footnote.

**What the recurrence changes.** Previously this entry was one clean session away from closing. It is now a live P3 with a *narrowed* hypothesis space: the preset-apply race is fixed and verified (BUG-061 is closed on its own evidence), so whatever hangs the render loop is **not** that race. Do not re-run the "confirm by non-recurrence" plan — it has already returned a negative. The next step is evidence capture, not another monitoring window.

**⇄ Same class as BUG-081 — two instances, one missing artifact (linked at RECON.9, 2026-08-03).** A parallel session independently filed **BUG-081** for a beachball ~78 s into session `2026-08-03T22-54-06Z` that also needed a force-quit and also produced no crash report, and reached the *same* conclusion this entry did, separately: force-quit yields no `.ips`, so the artifact must be taken **during** the hang via `sample`. Two sessions converging on that from different evidence is worth more than either alone. **Treat BUG-060 and BUG-081 as one investigation** — differences to keep in view: BUG-081's capture shows the renderer *healthy to the last frame* (steady 60 fps, Fractal Tree 0.18 ms GPU against a 0.7 ms budget, no degradation across 3756 frames) with background ML load rising, which points at a frozen **UI/main thread** rather than a dead render loop; BUG-060's original capture showed the render loop itself stopping one frame after a preset switch. Those may be one bug or two. **Whichever recurs first, capture the sample** — it resolves both. Do not assert a shared root cause before then (BUG-061's rule).

*Prior status, retained for the reasoning trail:* LIKELY RESOLVED by NACRE.2b's BUG-061 fix (2026-06-25), pending non-recurrence. BUG-061 confirmed the suspected **preset-apply race**: `applyPreset` clears `activePasses` to `[]` then republishes them at its end, while `draw(in:)` runs concurrently on the display-link thread; a frame in that window falls to `drawDirect` with the new preset's direct pipeline. Nacre's `.rgba16Float` pipeline made it a deterministic crash and exposed the mechanism; for an 8-bit preset like Gossamer it's the benign/intermittent stray frame seen here. The `willRenderActiveFrame` guard (skip frames while `activePasses` is empty) removes the stray `drawDirect` for ALL presets. Keep monitored until a few clean Gossamer-switch sessions confirm non-recurrence (the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains).
**Introduced:** Unknown (the apply-race predates NACRE.2b).
**Resolved:** Not resolved. The 2026-06-25 empty-passes guard fixed a real adjacent defect (BUG-061) but did not stop this hang.

**Expected:** switching presets (incl. Gossamer) never hangs the app.

**Actual (session `2026-06-17T22-10-50Z`):** the render loop was healthy — 60 fps, `frame_gpu_ms` 0.13–1.5 ms, no `deltaTime` gap — through the **last recorded frame (9459) at `22:14:01Z`**, which is **one second after `session.log`'s last event, `preset → Gossamer` at `22:14:00Z`**. `features.csv` then stops while the stem-separation / orchestrator threads keep logging for ~30 s more → a **render-path hang** (main or GPU), not an analysis stall (cf. BUG-043, a freeze-then-lurch) and not a tap freeze (cf. BUG-058). Video was OFF (BUG-050), so the recorder's video path is excluded. Matt force-quit from Xcode **without hitting Pause**, so no thread stacks were captured.

**Non-reproduction (session `2026-06-18T13-57-23Z`):** Gossamer was applied **3×** (13:58:35, 14:00:13, 14:00:36) and rendered clean; the session ended with a normal `SessionRecorder finished` shutdown. So the hang is rare/intermittent, not a deterministic Gossamer defect.

**Reproduction steps:** unknown trigger. Lead: a `preset → Gossamer` switch under live load (continuous stem separation running) — possibly transient GPU contention between the stem-separation MPSGraph and Gossamer's first-frame render, or a preset-apply race.

**Session artifacts:** `~/Documents/uzume_sessions/2026-06-17T22-10-50Z/` (features.csv ends at frame 9459 / `22:14:01Z`; session.log last line `preset → Gossamer`); clean counter-example `2026-06-18T13-57-23Z`.

**Suspected failure class:** `concurrency` or `render-state` (a hang, not a crash).

**Verification criteria (when diagnosable):**
- [ ] **On the next recurrence, capture a stack BEFORE force-quitting.** A hang produces no crash log, so there is nothing to recover afterwards — the artifact has to be taken while the app is still wedged. Two routes, either is sufficient:
  - **Launched from Xcode:** hit Pause (⏸), then capture the Debug-Navigator thread stacks (main thread + any thread in Metal/MPSGraph). Add `Debug → Capture GPU Frame` if a GPU hang is suspected.
  - **Launched normally (the likely case for a live session):** from Terminal, `sample UzumeApp 10 -file ~/Desktop/uzume_hang.txt` — ten seconds of stacks for every thread, no Xcode needed. `spindump` works too but needs sudo. This is the same instrument that diagnosed the BUG-059 deadlock class.
- [ ] Root cause identified from a captured stack; regression guard added.

*Note (RECON.2, 2026-08-03):* the earlier framing of this criterion assumed an Xcode-attached session, which is not how the recurrence was hit. The `sample` route above is the one that will realistically be available.

**Manual validation required:** Yes — a hang is felt, and only a captured stack diagnoses it.


---

### BUG-058 — Mid-session output-device swap freezes the tap: `performReinstall` (CLEAN.1.5 / G1) doesn't recover; visuals freeze on a stale buffer (2026-06-17)

**Severity:** P3 (downgraded from P2 2026-06-17 — see §Update. RARE intermittent: the G1 device-swap recovery is robust in the common case; a freeze was seen once and not reproduced across 12 subsequent swaps).
**Domain tag:** audio.capture / resource-management (`SystemAudioCapture.performReinstall`, `DefaultOutputDeviceMonitor`)
**Status:** Open — **instrumented + largely validated. G1 device-swap recovery confirmed ROBUST (12/12, 2026-06-17).** The single freeze (`14-28-30Z`, un-instrumented build) was NOT reproduced; breadcrumbs remain in place to pin it if it recurs. Distinct from BUG-057: that's a wedged `coreaudiod` feeding *all* taps zero; this is a rare race in the tap recreate during an OS device transition.
**Introduced:** Unknown — CLEAN.1.5 (`DefaultOutputDeviceMonitor → performReinstall`, 2026-06-13) added the device-change recovery, but its G1 manual validation was never performed; this is its first real test, and it fails. Possibly a macOS-26.5 Core Audio behavior (tap recreate during a device transition).
**Resolved:**

### Expected behavior
Switching the macOS default output mid-session (e.g., Duet 3 → Mac mini Speakers) reinstalls the tap against the new device and visuals keep animating (a brief glitch is acceptable) — what CLEAN.1.5 / G1 promises.

### Actual behavior
On the swap the visualizer freezes and never recovers. Session `2026-06-17T14-28-30Z` (instrumented build, healthy coreaudiod): the tap worked ~39 s (RMS 0.06, `signal quality → green`), then at the switch **`raw_tap.wav` stops at exactly 39.1 s while the session ran ~134 s** — the **IO proc stopped firing entirely.** The render loop coasted on the last buffer for ~95 s → `features.csv` tail is **constant nonzero** (`bass=0.16956, mid=0.00565, treble=0.00073`, identical across the final frames) = the Waveform preset shows a frozen flat line. **No `reinstall via device-change` success/FAILED line**, and **no `audio signal → silent`** (the buffer isn't RMS≈0, so `SilenceDetector` stays `.active` → `.silent → reinstall` never arms either). Both recovery paths miss.

### Reproduction steps
1. Cold-start streaming (Spotify); confirm visuals animate.
2. ~20–30 s in: System Settings → Sound → Output → switch device (Duet 3 ↔ Mac mini Speakers).
3. Observe: visuals freeze on the last frame, no recovery; `raw_tap.wav` stops at the switch; `features.csv` tail constant.

### Session artifacts
`~/Documents/uzume_sessions/2026-06-17T14-28-30Z/` (the failure; `raw_tap.wav` 39.1 s of 134 s, frozen-buffer tail) + `…T14-15-28Z/` (prior run that ended at/before the switch — tap healthy throughout, failure not captured).

### Suspected failure class
`resource-management` / `api-contract` (pending instrumentation). Leading hypothesis: `performReinstall` **fired and ran `teardownTapResources()` (→ the clean IO-proc stop at 39.1 s), but the tap RECREATE stalled/hung** during the device transition (a `createProcessTap` / `createAggregateDevice` / `startDevice` blocking on macOS 26.5), never reaching the success or catch log. Alternative: the `DefaultOutputDeviceMonitor` listener never fired. The os_log lines that would distinguish these are `.info` → not persisted (`log show` empty), hence:

### Instrumentation (step 1 — landed 2026-06-17)
Added `session.log` breadcrumbs (via the existing `onCaptureDiagnostic` sink) the os_log path lacked: the **`DefaultOutputDeviceMonitor` callback firing** (`device-change monitor FIRED`), and **each step of `performReinstall`** (`ENTER → tearing down` / `teardown done` / `tap created` / `aggregate created` / `IO proc created` / success / FAILED / `SKIPPED (not capturing)`). The last breadcrumb before silence pins the exact stall point. No fix code; breadcrumb-only on the non-SPM-testable device-change path.

### Update 2026-06-17 — G1 device-swap recovery validated ROBUST (12/12); freeze un-reproduced

Instrumented re-test (session `2026-06-17T14-54-49Z`): **12 rapid back-and-forth output-device swaps (Duet 3 ↔ Mac mini Speakers), all 12 recovered cleanly** — each logged `device-change monitor FIRED → performReinstall: ENTER → … → reinstall via device-change gen=N` completing in < 1 s, with the new tap immediately recapturing real audio (RMS 0.05–0.49); motion preserved through the last frame; `raw_tap.wav` continuous (67 s). A prior single swap (`2026-06-17T14-49-23Z`) also recovered. Tally: **`monitor FIRED` = 12, reinstall completed = 12, FAILED = 0.** So `DefaultOutputDeviceMonitor → performReinstall` (CLEAN.1.5) is sound — **the G1 manual gate passes.** The one freeze (`14-28-30Z`) ran on the pre-breadcrumb build, minutes after a `sudo killall coreaudiod`, so the leading explanation is a **transient `coreaudiod`-settling race** in the tap recreate, not a systematic defect. Left Open at P3 with the breadcrumbs live: if a freeze recurs, the last `performReinstall:` line before silence pins the stalling Core Audio call.

### Verification criteria
- [x] Instrumentation (step 1): breadcrumbs landed; the happy path is fully captured (session `14-54-49Z`).
- [x] Manual (G1): swap the output device mid-session → visuals stay live, ≥ 2 devices, both directions — **PASSED 12/12 (2026-06-17).**
- [x] No regression: cold-start streaming still animates; BUG-057 workaround unaffected.
- [ ] (Open, low-priority) Reproduce + pin the rare freeze, *if* it recurs.

### Related
- **The open G1 / CLEAN.1.5 manual gate** — this *is* that gate failing. CLEAN.1.5 has unit tests for the monitor mechanism (`DefaultOutputDeviceMonitorTests`) but the live device-swap was never validated.
- BUG-057 (sibling silent-tap; different mechanism — wedged coreaudiod / pure-zero, vs this frozen-buffer / IO-proc-stopped). The planned granted-but-silent **detector** must catch THIS state too (no *fresh* audio / IO-proc-stopped), not just RMS≈0.
  - **Detector landed 2026-06-17** (see BUG-057 §Fix increment): `PlaybackErrorBridge`'s freshness poll catches THIS Mode-B state — `InputLevelMonitor.frameCount` ceasing to advance while `.silent` never fires — and raises the `AudioStallOverlayView` card. This bug stays its own (the rare freeze itself is still un-fixed); the detector just makes the frozen state visible + actionable instead of a silent frozen frame.
- Surfaced 2026-06-17 during the G1 manual test (run right after the BUG-057 coreaudiod fix).


---

### BUG-056 — Local-file playback restarts the track from the top when the macOS output device changes (`LocalFilePlaybackProvider` AVAudioEngine teardown/restart, no resume-from-position) (2026-06-16)

**Severity:** P3 (local-file robustness/UX — no crash, no data loss; a mid-track output swap loses playback position. Annoying, not blocking.)
**Domain tag:** local-file / audio (`LocalFilePlaybackProvider`, AVAudioEngine)
**Suspected failure class:** `resource-management` (the `AVAudioEngineConfigurationChange` handler tears the player down and restarts at frame 0 instead of resuming).
**Status:** Open — observed 2026-06-16; **re-confirmed live 2026-06-18** (session `2026-06-18T13-46-10Z`) during the BUG-059 device-swap validation: several swaps each restarted the track from the top (the engine teardown/restart now always completes cleanly — BUG-059 fixed — so this restart is the remaining, expected behavior). Not yet scheduled — awaiting Matt's prioritization call (resume-from-position is its own increment).
**Resolved:** —

**Expected:** changing the macOS output device during local-file playback continues the track from its current position (a brief audio glitch on the reconfigure is acceptable).
**Actual:** on an output-device change the provider runs a full teardown (`provider.teardown` → removeObserver / player.stop / player.removeTap / engine.stop) and the player restarts from position 0 — the song starts over. The visualizer keeps running; only the audio restarts.
**Reproduction steps:** play a local file; mid-playback change the macOS default output (System Settings → Sound → Output, or ⌥-click the menu-bar volume). The track restarts from the beginning.
**Session artifacts:** `2026-06-16T21-32-50Z` — `session.log` shows `provider.teardown … player.stop … engine.stop` at 21:33:57 and again at 21:34:12 (two output swaps), each followed by a restart from the top.
**Verification criteria (for the fix):**
- [ ] On an `AVAudioEngineConfigurationChange` (output change), the provider reconfigures and **resumes from the saved frame position** rather than restarting at 0.
- [ ] Manual: swap output mid-local-file → playback continues (≤ a small glitch), not a restart.

**Note:** distinct from **G1** (the *system-tap* reinstall on the streaming path — `DefaultOutputDeviceMonitor` / `performReinstall`); local-file uses AVAudioEngine and never engages the tap, so a local-file output-swap does NOT validate G1.


---

### BUG-055 — Silent system-audio tap after a rebuild: `CGPreflightScreenCaptureAccess()` returns stale-`true` (gate passes) but macOS silently denies the re-signed binary's tap → app shows "ready", renders a flatline, no guidance (2026-06-16)

**Severity:** P2 (no crash/data-loss, but a total loss of the core function — no visuals on any streaming / `.systemAudio` session — presented as "ready" with **no actionable feedback**; cost a ~90-minute live-debug session and recurs on every dev rebuild. Not P1: a workaround exists (re-grant + relaunch) and the local-file path is unaffected.)
**Domain tag:** app.ui / permission (TCC "Screen & System Audio Recording") — capture path `SystemAudioCapture` (`AudioHardwareCreateProcessTap`)
**Suspected failure class:** `api-contract` (`CGPreflightScreenCaptureAccess()` returns stale-`true` after a re-signed rebuild — the gate trusts an unreliable preflight) + `pipeline-wiring` (no "granted-but-zero-signal" fallback detection).
**Status:** Symptom RESOLVED 2026-06-17 (detector, validated) — the filed defect (silent flatline reported as "ready," **no guidance**) is addressed: the silent-tap detector surfaces an actionable card with a "re-grant Screen & System Audio Recording, then quit + relaunch" step (Mode A — same validated path; commit `a0a9ded`, surface validated by screenshot). The durable root (stable signing so the grant persists across rebuilds — CLEAN.2.5b) remains open/blocked on no paid Apple membership; end users on a stably-signed build won't hit the re-grant at all. Per Matt, the card is a fallback — the end-state goal is **no** user-facing Terminal/Settings step (self-healing; see BUG-057 §Fix increment + `feedback_self_healing_over_manual_remediation`).
**Resolved:** 2026-06-17 — user-facing symptom via the silent-tap detector (`a0a9ded`). Durable signing recurrence tracked separately as CLEAN.2.5b.

**Expected:** when a live `.systemAudio` session is shown, the tap captures the default output and drives the visuals; if capture is actually denied, the app surfaces an actionable "re-grant Screen Recording" state — never a silent flatline reported as "ready."
**Actual:** after rebuilding the (dev-signed, hardened-runtime) app, streaming sessions render **no motion**. The tap installs cleanly (`raw tap capture started sr=… ch=2`) and `signal quality → red: no signal` fires, but `PermissionMonitor` (→ `CGPreflightScreenCaptureAccess()`, `UzumeApp/Permissions/`) reports **granted**, so the gate (`ContentView`) lets playback proceed. macOS silently denies the actual `AudioHardwareCreateProcessTap` because the rebuilt binary's code signature no longer matches the prior grant — a **denied process tap returns zeros, not an error** — so the tap delivers pure silence. Reproduced with both the Apogee Duet 3 and the built-in Mac-mini Speakers as default output (audio audibly playing on the tapped device). `tccutil reset ScreenCapture com.phosphene.app` cleared **32 orphaned grants** — one per dev rebuild (the dev signature churns every build; hardened-runtime makes the match strict, but Debug churns too).
**Reproduction steps:** rebuild the app, launch, start a streaming session, play audio to the macOS default output → green UI, zero visuals. `raw_tap.wav` RMS=0.0, `features.csv` bass/mid/treble all 0.0. **Fix:** `tccutil reset ScreenCapture com.phosphene.app` → relaunch → grant "Screen & System Audio Recording" → **quit + relaunch** (the grant applies only on a fresh launch).
**Session artifacts:** `2026-06-16T20-58-31Z` (Apogee Duet default) + `2026-06-16T21-15-42Z` (built-in Speakers default) — both `raw_tap.wav` RMS 0.0, all features 0, log `audio signal → silent`. **Contrast** `2026-06-16T21-32-50Z` (a local file on the *same* broken build): green −1 dBFS + full motion — isolating the fault to the tap/permission, not the audio source (local files are file-direct AVAudioEngine and bypass the Screen-Recording gate per `ContentView` LF.4).
**Suspected failure class:** `api-contract` + `pipeline-wiring` (see above).
**Verification criteria (for the fix):**
- [ ] **Detection:** while a session is "ready"/playing and the tap reads ~0 RMS for > N s, the app transitions to an actionable "Screen Recording may be stale — re-grant" state instead of a silent flatline (wire the existing `signal quality → red: no signal` detector to this). Unit-testable.
- [ ] The gate stops treating `CGPreflightScreenCaptureAccess()` alone as proof of working capture (it is unreliable after a re-sign).
- [ ] **Manual:** after a rebuild with a stale grant, the app guides the user to re-grant rather than showing a dead session.

**Durable fix:** dev-signing re-signs every build, so the grant never persists → this recurs every rebuild; the root fix is **stable signing (Developer ID / notarization — CLEAN.2.5b, blocked on no paid Apple membership)**. Related: G1 (CLEAN.1.5 output-device handling) and the `signal quality → red: no signal` detector (BUG-026 domain). Note: a *separate* silent-tap cause is environmental output-routing (audio playing on a device the tap isn't bound to) — this BUG is the distinct, real defect where audio IS on the tapped device but the permission is silently denied.

**Detector fix increment — landed 2026-06-17 (pending Matt's manual UX validation):** the **Detection** criterion above is satisfied by the shared silent-tap detector (see BUG-057 §Fix increment) — `PlaybackErrorBridge` raises the `AudioStallOverlayView` card on sustained RMS≈0 (Mode A) while playing, with "re-grant Screen & System Audio Recording, then quit + relaunch" in the on-card fix ladder, instead of a silent flatline reported as "ready." The durable signing fix (CLEAN.2.5b) is still separate and still blocked. Mark this bug `Resolved` (the detector half) after Matt's manual UX validation of the card.


---

### BUG-054 — Key detection has never been accurate enough to use in playback (chroma algorithm is fundamentally resolution-limited) (2026-06-16)

**Severity:** P3 (non-load-bearing *today* — `estimatedKey` is a debug/UI display value + a fallback; nothing in orchestration or any preset consumes key, and presets drive from energy/deviation, not key. No fps/crash/playback-correctness impact. Sev would rise to P2 if/when a feature is built to *use* key. Matt may rerank). Filed 2026-06-16 after the BUG-053 work surfaced it (Matt: "key has never been correct for as long as Phosphene has tracked it"). Investigation + fix design done this session; **filed for later, not scheduled.**
**Domain tag:** dsp.key (MIR chroma / key estimation)
**Suspected failure class:** `algorithm` (the chroma front-end is resolution-limited by construction) + `calibration` (full-mix input, no harmonic weighting).
**Status:** Open — design complete, **not scheduled** (Matt's call: track for later). Distinct from BUG-053 (that was the live MIR ignoring the *tap rate*; this is the chroma/key *algorithm* being inaccurate even at the correct rate).
**Resolved:** —

**Expected:** the detected musical key matches the track's actual key on clear tonal material (with a confidence gate so it surfaces only when trustworthy). Realistic ceiling: ~70–85 % exact + ~90 %+ within a fifth/relative — never 100 %.
**Actual:** key is reliably wrong. Black Hole Sun (G major) read **F** in session `2026-06-16T16-52-09Z`. Root causes (`ChromaExtractor.swift`, `SessionPreparer+Analysis.analyzeMIR`):
1. **1024-point FFT → ~43 Hz/bin.** A semitone near middle C is ~15 Hz — *under half a bin* — so C/C♯/D below ~1 kHz fall in the same bins; the analyzer can't resolve which semitone owns the energy in the register where the key lives. The `minFrequency = 500 Hz` floor (`ChromaExtractor.swift:63`) sidesteps the worst of it but then reads key off harmonics ≥ 500 Hz, which smear across pitch classes (overtones land on octave/fifth/major-third).
2. **Linear FFT bins → log pitch is the wrong transform** — the field uses a constant-Q transform (uniform log-frequency resolution).
3. **Full-mix chroma** — drums/percussion (broadband) pollute it; no harmonic/percussive split, even though Uzume already computes stems.
4. **No harmonic summation / spectral whitening.**
Krumhansl-Schmuckler template matching at the end is fine; the chroma front-end is the bottleneck. The offline per-track pass (`analyzeMIR`) uses the *same* 1024-pt full-mix `ChromaExtractor`, so the cached key is equally wrong. No metadata fallback in normal use: only `SoundchartsFetcher` returns a key (env-gated, off by default); iTunes/MusicBrainz don't carry key; Spotify's audio-features (key) endpoint is deprecated for new apps.

**Reproduction steps:** play any track with a known key (e.g. Black Hole Sun = G); read the `key=` line in `~/uzume_diag.log` (the MIR's own estimate, not metadata-overridden). It is reliably off, independent of sample rate.
**Session artifacts:** `2026-06-16T16-52-09Z` (Black Hole Sun, true G, read F). A labeled validation set is a prerequisite for the fix (see below).
**Verification criteria (for the eventual fix):**
- [ ] A **labeled ground-truth set** (~15–20 tracks, known keys) added as a test fixture; report **exact-match %** + **within-a-fifth/relative %** before and after.
- [ ] Post-fix exact-match clears an agreed bar (target ~70 %+ exact, ~90 %+ tolerant) on that set.
- [ ] Display/use is **confidence-gated** — a low-confidence estimate shows nothing rather than a wrong key.

**Fix approaches (design from this session; key is a per-track value → spend compute once, offline; exploit Uzume's stems + offline budget):**
1. **Tier 1 (cheap, partial):** in the offline key pass, feed the **drums-removed / harmonic stem** signal (stems already exist → free HPSS), bump to an **8192-pt FFT** (or add harmonic summation), aggregate over the whole clip; keep Krumhansl. Likely "never right" → right on clear tonal tracks.
2. **Tier 2 (proper):** **constant-Q transform** → harmonic-weighted pitch-class profile (HPCP) + spectral whitening → refined templates (Temperley / Albrecht-Shanahan) over the whole track — the librosa-`chroma_cqt` / essentia-`KeyExtractor` design, built in Accelerate (no Swift MIR lib; on-device constraint). The real fix.
Recommended sequencing: Tier 1 measured against the labeled set first; escalate to Tier 2 only if it doesn't clear the bar. Confidence-gate either way.


---

### BUG-036 — Heap allocations on the real-time Core Audio thread at three sites (FFTProcessor, AudioBuffer.latestSamples, SessionRecorder raw tap) (2026-06-09)

**Severity:** P2 (violates the standing "do not allocate in the Core Audio IO proc callback" rule on every callback of every session; priority-inversion / glitch risk under memory pressure rather than observed breakage).
**Domain tag:** audio.capture / performance
**Status:** Open (mostly fixed) — sites 1 + 2 fixed + **validated in production** (2026-06-17, `58a37c0`; session `2026-06-17T20-52-27Z` — no audible glitch, steady 60 Hz cadence, worst gap 84 ms). Site 3 (raw-tap) + the analysis hand-off **parked** as an accepted low-risk residual (re-open the ring rework only if a stall/glitch implicates it — BUG-043 is not recurring; Matt 2026-06-17). See Progress.
**Introduced:** structural — predates the rule's enforcement attention; the "zero-alloc" header comments in both DSP files are currently false.
**Resolved:** — (sites 1 + 2 done; bug stays open until site 3 + the hand-off land)

**Expected:** the IO-proc path allocates nothing (CLAUDE.md What-NOT-To-Do).
**Actual (all three verified on the IO-proc call path via `VisualizerEngine+Audio.makeAudioSampleCallback`):**
1. `FFTProcessor.swift:149,193` — `process()` allocates a fresh `magnitudes` array per call; `processStereo` allocates a fresh `mono` array (called at `VisualizerEngine+Audio.swift:114`).
2. `AudioBuffer.swift:148` — `latestSamples` does 2048 per-element ring reads (`UMARingBuffer.read(at:)` precondition + modulo each) + an allocating `append` loop **under the same NSLock the write path takes**, per callback (`VisualizerEngine+Audio.swift:111`). RMS over the same samples is also computed 3× per callback (AudioBuffer `:179`, SilenceDetector `:106`, InputLevelMonitor `:185`).
3. `SessionRecorder+RawTap.swift:28` — `Data(bytes:count:)` copy + `queue.async` closure allocation per callback for the first 30 s of every session (entire session under `UZUME_FULL_RAW_TAP=1`).
Related P3 (same rule, rarer path): `AudioInputRouter+SignalState.swift:45` — tap-reinstall scheduling (locks, `DispatchWorkItem` alloc, os_log interpolation) runs on the RT thread on silence transitions.
**Session artifacts:** `docs/diagnostics/CODE_AUDIT_2026-06-09.md` (Audio/DSP P2 section).
**Suspected failure class:** `resource-management` (RT-safety).

**Progress (2026-06-17, `58a37c0`) — sites 1 + 2 landed; site 3 + hand-off deferred to BUG-043.** The three named allocations split into two groups by whether they cross the audio-thread boundary:
- **Sites 1 + 2 (RT-thread-local) — FIXED.** `FFTProcessor` reuses a pre-allocated `magnitudesScratch`; a new zero-alloc `processStereo(interleaved: UnsafeBufferPointer)` mixes L/R straight into the windowed-sample scratch (no `mono` array); the array overloads delegate to it. `AudioBuffer.latestSamples(into:)` fills a caller-owned buffer (the callback reuses a pre-allocated `interleavedScratch`). All scratch is touched only on the single RT thread → no lock needed (cf. D-079's cross-core `tapSampleRate`). FFT output is byte-identical (pointer↔array bit-equivalence test + unchanged FFT/Chroma/BeatDetector goldens).
- **Site 3 (raw-tap `Data()` + `queue.async`) + the analysis hand-off (`Array(...prefix())` + `analysisQueue.async`) — PARKED (accepted low-risk residual).** Both cross the thread boundary. Making them allocation-free safely requires a pre-allocated ring drained by a persistent consumer (the "pre-allocated ring for raw-tap" fix below): an unbounded→bounded hand-off is a cadence/concurrency change that lands directly on **BUG-043**'s analysis-stall surface. The hand-off allocates every callback — a *continuous but low-impact* RT-rule violation — and the fix is a real concurrency redesign. With **BUG-043 not recurring** after sites 1 + 2 (the forcing function is gone), the cost/benefit doesn't justify the rework now (Matt 2026-06-17); re-open if a future stall/glitch implicates the remaining allocations. (Originally deferred to sequence *with* BUG-043 per the `036 → re-test → 043` ordering; the re-test came back clean, so it's parked rather than queued.)

**Verification criteria:**
- [x] Automated (sites 1 + 2): `FFTProcessorTests.fftProcessorStereoPointerMatchesArrayPath` + `…ReuseIsStable`, `AudioBufferTests.audioBufferLatestSamplesIntoMatchesAllocating` — pre-allocated members, pointer path bit-for-bit == array path (incl. short/partial-fill + ring-wrap), scratch reuse stable over 64 calls.
- [x] Manual (sites 1 + 2): no audible-glitch regression + healthy analysis cadence — session `2026-06-17T20-52-27Z` (Matt): median Δt 0.0167 s (60 Hz) over 25,017 audible frames / 8 tracks, worst gap 84 ms, no freeze-lurch. (The stricter os-allocator Instruments proof is optional given byte-identical output + green tests + this cadence — not pursued, Matt's call.)
- [—] Automated (site 3 + hand-off): pre-allocated ring + allocation-free hand-off — PARKED with the remainder (see Progress); not required while BUG-043 stays quiet.


---


---

### BUG-028 — Beat-grid live phase imperfect on ~half of tracks (felt "behind the beat / wrong downbeat") (2026-06-05)

**Severity:** P2 (musical-feel ceiling across every beat-coupled preset; not a crash. Bounds Nimbus's beat axis — see M7 r1 below).
**Domain tag:** dsp.beat (grid phase)
**Status:** Open — diagnosed; elevated to its own project per Matt (**D-145**). Scoping note: `docs/diagnostics/BEAT_GRID_LIVE_PHASE_PROJECT_2026-06-05.md`. **Not to be fixed by per-preset tuning, and not by another short-window live-tap iteration (FA #69 — premise retired).**
**Introduced:** structural — the cached `BeatGrid` is built from the 30 s preview and its phase is cross-capture-unstable on live audio (BSAudit.2; CLAUDE.md §Cold-Start Phase Contract).
**Resolved:** —

**Expected:** beat-coupled visuals land on the audible downbeat across the catalog.
**Actual (Nimbus M7 r1, session `2026-06-05T18-26-37Z`):** grids **lock** (`lock_state`=2 ~84 %) with the **right tempo** (grid-vs-drums BPM < 1 % on most tracks), but live **phase** is imperfect — `drift_ms` ~10–35 ms (mixed sign) and meter assumed simple (Money 7/4 logged `beatsPerBar`=2). Reads as "behind the beat / wrong downbeat" on roughly half the tracks; locks well when phase happens to align (Superstition verse).
**Suspected failure class:** `algorithm` (cached-grid phase derivation) — a *new premise* is required (human-tap reference / full-track local analysis / per-track manual calibration), chosen with Matt in the D-145 design session before any increment.
**Verification criteria:** deferred to the D-145 project.


---

## Known Limitations (external / by-construction — not actionable defects)

Reclassified at PUB.3 (2026-07-11, ultra-review): these are bounded by external
APIs or by-construction constraints, kept for reference so contributors don't
mistake them for open work. BUG-005's UX-copy criterion is the one item that
could close via a small increment.

*Reading note (RECON.2, 2026-08-03):* the three entry **bodies** below still carry
`**Status:** Open` and unchecked verification boxes from before the PUB.3
reclassification. **This section header wins** — they are not counted in the open
defect total and none is scheduled work. The bodies are deliberately left intact
rather than rewritten, because their verification criteria are exactly what would
have to be met *if* an external API ever exposes what they need (a `time_signature`
source for BUG-013 and BUG-001) — rewriting them to "closed" would throw away the
reopening condition. Read `Status: Open` there as "unsolved", not "in the queue".

- **BUG-013** · dsp.beat — no `time_signature` source (Soundcharts doesn't expose it); meter wrong on some odd-meter tracks
- **BUG-001** · dsp.beat — Money 7/4 stays REACTIVE on the live path (odd-meter ceiling)
- **BUG-005** · session.ux — Spotify `preview_url` null for some tracks (API-side; degrade path exists)

---

### BUG-013 — Soundcharts does not expose `time_signature`; ML meter detection wrong on some odd-meter tracks

**Severity:** P2 (visual artifact on a subset of odd-meter tracks. Bar-locked motion presets (Ferrofluid Ocean) cycle at the wrong rate on tracks where the ML meter detector guesses wrong AND the metadata source can't override. Current production playlist only surfaces this on Pink Floyd's Money 7/4 → cycles at 5.85 s/cycle on Ferrofluid Ocean instead of the intended 20.5 s/cycle. Visual still reads as "ocean swell" per Matt's 2026-05-15T17-54-49Z review.)
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** Surfaced 2026-05-15 during Ferrofluid Ocean Round 25-26 metadata-override implementation.
**Resolved:** —

---

### Expected behavior

When `MetadataPreFetcher` returns a profile for a track, `PreFetchedTrackProfile.timeSignature` carries the track's time-signature numerator (3 for 3/4, 4 for 4/4, 7 for 7/4, etc.). `SessionPreparer.analyzePreview` overrides `BeatGrid.beatsPerBar` with this value before caching. Downstream consumers (FerrofluidMesh vertex shader's bar-locked wave cycling) use the correct meter.

### Actual behavior

`PreFetchedTrackProfile.timeSignature` is always nil in production. Soundcharts (the only metadata source in production that exposes audio features) does not return `time_signature` in its API response — verified by adding the decode field and observing zero hits in session.log (no `Using pre-fetched time signature: N/X` lines for any of Love Rehab, So What, There There, Pyramid Song, Money).

Result: `BeatGrid.beatsPerBar` retains the ML-detected value. For Money (actual 7/4), the ML detector classifies as `meter=2/X` — wave cycle is `6 × 60 × 2 / 123 = 5.85 s` instead of the intended `6 × 60 × 7 / 123 = 20.5 s`.

### Reproduction steps

1. Build app: `xcodebuild -scheme UzumeApp -destination 'platform=macOS' build`
2. Start a Spotify-prepared session including Money by Pink Floyd.
3. Switch to Ferrofluid Ocean preset.
4. Observe wave cycle period during Money playback (~5.85 s, not the intended 20.5 s).
5. `grep "time signature" session.log` returns no matches.
6. `grep "BeatGrid installed" session.log` shows `meter=2/X` for Money.

**Minimum reproducer:** any Spotify-prepared session containing Money (or Pyramid Song's 16/8, or any other odd-meter track where the ML detector guesses wrong).

---

### Session artifacts

**Session directory:** `~/Documents/uzume_sessions/2026-05-15T17-54-49Z/`

```log
[2026-05-15T17:57:01Z] BeatGrid installed: source=preparedCache, track='Money', bpm=123.2, beats=62, meter=2/X
```

No `Using pre-fetched time signature` lines exist in the file.

---

### Suspected failure class

`api-contract` — Soundcharts' audio-features endpoint doesn't expose `time_signature` (or strips it from the Spotify upstream they proxy). The Uzume-side override mechanism is wired correctly (Round 26); it has no value to consume.

**Evidence for this class:** Decoder was added with `CodingKeys: time_signature` mapping; field stays nil on every track. ML override path fires (Round 25 / 26 code paths) but with nil input → no-op.

---

### Verification criteria

When this defect is resolved:

- [ ] `session.log` includes `Using pre-fetched time signature: N/X` lines for tracks where the value is known.
- [ ] Money's installed BeatGrid logs `meter=7/X`, not `meter=2/X`.
- [ ] Ferrofluid Ocean wave cycle on Money matches the intended `6 × 60 × 7 / 123 = 20.5 s` period.

**Manual validation required:** Yes — visual confirmation that Money's wave rolls at the calmer 20.5 s cadence.

---

### Fix scope

Three potential paths:

1. **Path B — per-track hardcoded overrides.** Maintain a small JSON config mapping `spotifyID → timeSignature` for known-tricky tracks. Works for the few odd-meter tracks Matt's playlists actually contain; doesn't scale. ~40 lines + manual curation.

2. **Add a different metadata source that exposes `time_signature`.** Spotify's `/audio-features` had the field but was deprecated for most apps in late 2024. AudD or AcousticBrainz might. Each new fetcher = ~150-300 lines of integration.

3. **Improve ML meter detection on odd-meter tracks.** Out of scope for Uzume application code — would require either retraining Beat This! or post-processing the downbeat probabilities with a meter-specific search.

Current status: deferred. The Round 26 visual review accepted Money's 5.85 s cycle as "smooth and synced — solid." Revisit if/when a future playlist surfaces an odd-meter track where the visual reads wrong.

### Related

V.9 Session 4.5c Rounds 25-26 (metadata-override wiring), Round 21-24 (Gerstner bar-locked motion), BUG-001 (Money 7/4 live-path detection failure — different code path, related cause).


---

### BUG-001 — Money 7/4 stays REACTIVE on live path

**Severity:** P2
**Domain tag:** dsp.beat
**Status:** Open
**Introduced:** DSP.3.5 (identified; pre-existing limitation of the 10-second live window)
**Resolved:** —

**Expected behavior:** After 20 seconds of playback (two retry attempts), Beat This! produces a usable BeatGrid for Money 7/4 and `lock_state` advances past UNLOCKED.

**Actual behavior:** Beat This! returns an empty grid on both the 10-second and 20-second attempts. The session stays in REACTIVE mode throughout. `grid_bpm=0` in `features.csv`.

**Reproduction steps:**
1. Start an ad-hoc reactive session (no Spotify preparation).
2. Play "Money" by Pink Floyd in Apple Music.
3. Switch to SpectralCartograph preset and observe mode label.
4. Observe "○ REACTIVE" for the full track.

**Minimum reproducer:** "Money" by Pink Floyd, ad-hoc reactive session.

**Session artifacts:**
- `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` — contains the evidence and analysis.

**Suspected failure class:** calibration
**Evidence:** 10-second window at 120 BPM gives ~20 beats, which is insufficient for confident downbeat estimation on 7/4 irregular meter. The retry at 20 seconds sees the same 10-second snapshot (not a longer window), so it does not help. The 30-second Spotify-prepared path gives ~61 beats and reliably detects the meter.

**Verification criteria:**
- [ ] Connecting a Spotify playlist that includes "Money" results in a prepared BeatGrid with `beats_per_bar=7` in `KNOWN_ISSUES.md` test notes.
- [ ] Manual: beat grid ticks in SpectralCartograph align to perceived quarter notes.

**Fix scope:** The durable fix is not to tune the live path — it is to use a Spotify-prepared session. The live path (10-second window) is below the beat-count floor for irregular-meter tracks by construction. See `docs/diagnostics/DSP.3.5-post-validation-beatgrid-triage.md` for the evidence. A potential improvement (not yet planned) would be to extend the live-path snapshot to 20–30 seconds on the retry, but this carries a 1.5–2× memory cost per attempt.

**Related:** DSP.3.5, D-077


---

### BUG-005 — Spotify `preview_url` returns null for some tracks

**Severity:** P3
**Domain tag:** session.ux
**Status:** Open
**Introduced:** U.11 (discovered during integration testing)
**Resolved:** —

**Expected behavior:** `PreviewResolver` finds a 30-second preview for every track in a Spotify playlist and preparation completes for all tracks.

**Actual behavior:** Rights-restricted or region-locked tracks return `null` for `preview_url` from Spotify's `/items` endpoint. These tracks fall through to iTunes Search API, which also returns no preview for some of them. Affected tracks show `TrackPreparationStatus.noPreviewURL` in `PreparationProgressView`.

**Minimum reproducer:** Any playlist containing tracks by Mclusky, or region-restricted regional-exclusives.

**Session artifacts:** `session.log` `noPreviewURL` entries.

**Suspected failure class:** api-contract (external API limitation, not a Uzume bug)

**Verification criteria:**
- [ ] `PreparationProgressView` shows a clear "No preview available" status for affected tracks rather than a spinner or error.
- [ ] Session proceeds to `.ready` state even when some tracks have no preview.

**Fix scope:** UX copy improvement only. The underlying limitation (no preview URL from either Spotify or iTunes) is not fixable by Uzume. See Failed Approach #47.

**Related:** U.11, D-070, Failed Approach #47


---

## Pre-existing Flakes (non-blocking, test infrastructure only)

These test failures are pre-existing, environment-dependent, and do not indicate behavioral regressions. They are tracked here for completeness.

| Test | Condition | Workaround |
|---|---|---|
| `MemoryReporterTests` growth assertions | `phys_footprint` variance across system memory pressure states | Run with other apps quit; or skip with `SKIP_MEMORY_TESTS=1` |
| `PostProcessChainTests.test_fullChain_under2ms_at1080p` | GPU/CPU contention under the full parallel suite inflates a timed submit past the budget | Re-run in isolation to confirm before treating as a regression |
| `RayMarchPipelineTests.test_fullPipeline_under8ms_at1080p` | Same shape as above (wall-clock assertion around a GPU submit) | Re-run in isolation to confirm before treating as a regression |
| `StemSeparationPerformanceTests.test_separate_1SecondAudio_performance` | Same shape; MPSGraph submit under parallel load | Re-run in isolation to confirm before treating as a regression |

*(The three perf rows were added at RECON.2, 2026-08-03. They were declared "confirmed flake" during the BUG-080 investigation but never reached this table — so each run re-litigated them from scratch. **These are the known-flaky *shape*** — a single wall-clock sample around a GPU submit — that CLEAN.7.9→7.14 fixed elsewhere by asserting the **minimum of N warm samples** rather than one sample, or by removing the timing assumption entirely. Per the deterministic-over-budget-widening rule these three should get the same treatment rather than staying in this table; that is a small, well-precedented increment, not a mystery. Until then: a failure here is not evidence of a regression on its own.)*

**Resolved 2026-07-24 (TESTFLAKE.2)** — `SessionLifecycleGenerationTests.endThenRestart_staleOrphanDoesNotMutateNewSession` (never entered the table above — it failed on **every** full run, 3/3, while passing 3/3 in isolation in 2.7 s; the one suite TESTFLAKE.1's sweep missed). The test asserted the orphaned prep's *timing*: two 10 s `waitUntil` wall-clock polls plus a 2.5 s "sleep past 3 × 600 ms of session A's prep" gap. Under parallel load the case stretched to 73–89 s, the polls starved, and the assertions read session A's stale 3-track plan (`tracks.count → 3` vs 2) before session B's was installed. **The generation guard was verified correct first** (a load-only failure can be a real race): `streamingSessionGen`, the post-`await` staleness check, and every `currentPlan`/state write are all `@MainActor`-isolated with **no suspension point between check and act**, so check-then-act is atomic. Per the deterministic-over-budget-widening rule (CLEAN.7.9 → TESTFLAKE.1), the timing assumption is **removed, not widened**: `startSession` already returns with state + plan installed synchronously (so both polls were unnecessary — the tests now `await` it directly), and the 2.5 s sleep is replaced by awaiting session A's **actual** orphaned prep task, captured before `endSession()` drops the handle. The assertion is now the guard's promise — *whenever* the orphan fires, its completion is rejected — not *when* it fires. `SessionReadyWait` gained an `awaitPrepTask(_:)` overload for a captured handle, keeping the 120 s hang-cap race (a slip must not become a hang). Isolated 2.7 s → 0.042 s; green in 4 consecutive full-suite runs. Test-only, no production delta (`SessionManager` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-07-24-164940]`.

**Resolved 2026-06-16 (CLEAN.7.14)** — `SSGITests.test_ssgi_performance_under1ms_at1080p` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run, the same GPU-heavy parallel load the CLEAN.7.6 flash-safety suite added that exposed this whole flake family). It flaked **two** ways under contention, neither a real regression: (1) an `XCTest measure {}` block benchmarking the 1080p SSGI render **failed on relative standard deviation > 10 %** (XCTest's default bound; ~17.7 % observed) — pure variance; and (2) the real gate computed SSGI overhead as a **5-pair MEAN of (with − without) `Date()` timings**, which folds contention spikes straight into the average. Isolated, all 7 SSGI tests run in ~0.13 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11/7.12), the sub-1 ms gate is **kept, not loosened**: the `measure {}` benchmark is removed and overhead is computed from the **minimum of 8 warm samples per path** — contention can only ADD latency to a GPU submit, so each path's min is its clean true-cost floor and `minSSGI − minBase` is the clean overhead estimate, immune to a few starved samples. The SSGI render path is untouched; test-only, no production delta. (The structural twin — the single-sample ICB frame-perf gate `test_gpuDrivenRendering_cpuFrameTimeReduced` — is fixed the same way in **CLEAN.7.13**, consolidated onto this same branch.) See `RELEASE_NOTES_DEV.md [dev-2026-06-16-e]`.

**Resolved 2026-06-16 (CLEAN.7.13)** — `RenderPipelineICBTests.test_gpuDrivenRendering_cpuFrameTimeReduced` made contention-robust (it never entered the table above — it surfaced fresh under the full ~1469-test parallel `swift test` run during the CLEAN.7.12 closeout). Structurally identical to the CLEAN.7.10 flake: a **single-sample `Date()` wall-clock assertion around one warm ICB frame submit** (blit + compute + render), run inside the parallel suite — a saturated GPU/CPU inflates the lone submit past the 2 ms budget (the case-level time was a benign 0.277 s; the *timed inner submit* blew the gate), while isolated it passes in ~0.37 s. Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9, applied to this exact shape on CLEAN.7.10), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The `measure {}` variance block is unchanged. The ICB renderer path is untouched; test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-16-d]`.

**Resolved 2026-06-16 (CLEAN.7.12)** — `UMABufferExtendedTests.test_concurrentWriteRead_noDataRace` made deterministic (it never entered the table above — it surfaced fresh under the full ~1479-test parallel `swift test` run during the CLEAN.7.6 flash-safety closeout, which added GPU-heavy parallel tests that raised pool contention). The test dispatched 200 trivially-fast, lock-free blocks (100 writes + 100 reads to a `UMABuffer`) and asserted a **fixed 30 s** `DispatchGroup.wait(timeout:)` returned `.success`; under contention the GCD thread-pool drain latency exceeded the deadline → `.timedOut` (observed 34.9 s), while isolated the whole class runs in 0.048 s. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10/7.11), the deadline is **removed, not widened**: the test now `wait()`s with no timeout, returning exactly when the blocks drain — it cannot flake on elapsed time, and a genuine deadlock surfaces as a CI hang (same trade as CLEAN.7.11's `await …?.value`). Added a smoke-level post-condition — each writer wrote a distinct index, so after the barrier `buf[i] == Float(i)` for all i — catching gross corruption / lost writes; true data-race detection still requires TSan (per the file header). Test-only, no production delta (`UMABuffer` untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-16-c]`.

**Resolved 2026-06-15 (CLEAN.7.11)** — `ToastManagerTests.autoDismiss_afterDuration` removed from the table above. The test enqueued a `duration: 0.05` toast then slept a **fixed** wall-clock window (ratcheted 400 ms → 1000 ms and still flaking — CLEAN.2.3.8 closeout, 2026-06-15) before asserting `visibleToasts.isEmpty`; under @MainActor parallel-suite contention the auto-dismiss continuation could slip past the fixed window. Per the deterministic-over-budget-widening rule (CLEAN.7.9/7.10), the budget is **removed, not widened**: the test now `await`s the actual auto-dismiss `Task` to completion via a new `#if DEBUG` seam `ToastManager.dismissTask(for:)`, so it blocks exactly until the dismissal lands and races no deadline — **this is the fix the row prescribed**. Behavioural intent preserved — a finite-duration toast auto-dismisses; an `.infinity` one schedules no task (early `guard`). Test-only, no production delta (`ToastManager` dismiss logic untouched). See `RELEASE_NOTES_DEV.md [dev-2026-06-15-g]`.

**Resolved 2026-06-14 (CLEAN.7.10)** — `RayIntersectorTests.test_rayTrace_1000Rays_under2ms` made contention-robust (it never entered the table above — it surfaced fresh on the Mac mini during the CLEAN.1 Phase-0 re-confirmation, having passed 1469/1469 on both prior integration closeouts). The failing line was a **single-sample `Date()` wall-clock assertion around one GPU command-buffer submit**, run inside the ~1469-test parallel suite — about the most contention-fragile shape there is: a saturated GPU/CPU inflates any one submit past the 2 ms budget, while isolated the whole class incl. this test runs in 0.42–0.54 s (5/5 green). Per the deterministic-over-budget-widening rule (proven on CLEAN.7.9), the 2 ms gate was **kept, not loosened**: the assertion now takes the **minimum of 8 warm samples** — contention can only ADD latency to a GPU submit, so the min is the clean estimate of true cost and is robust to a few starved samples. The ray-intersector path is untouched by CLEAN.1 (last modified in render increment 3.3); test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-14-a]`.

**Resolved 2026-06-13 (CLEAN.7.9)** — `MetadataPreFetcherTests.fetch_networkTimeout_returnsWithinBudget` removed from the table above. The wall-clock budget — ratcheted 3 s → 8.25 → 15 → 45 s across prior sessions without ever converging (16.1 s / 22.8 s observed under the ~1460-test parallel suite during the CLEAN.1.x closeouts) — was replaced by a deterministic behavioural assertion: the merged profile carries the fast fetcher's `energy` but **not** the slow fetcher's `bpm` (excluded by the 1 s timeout). The outcome depends only on the 1 s-vs-10 s ordering (the 1 s timer's continuation is enqueued ~9 s before the 10 s one — contention delays both, never inverts them), not on measured elapsed time, so it cannot flake under cooperative-pool contention. Renamed `fetch_networkTimeout_returnsFastResultNotSlow`; adversarially proven to trap a timeout that lets the slow result leak (`bpm → 999` fails `== nil`, a ~10 s block not a hang). Test-only; no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-06-13-b]`.

**Resolved in the 2026-06-01 hardening pass** (made deterministic — no longer wall-clock-dependent, removed from the table above): `FirstAudioDetectorTests` (ManualDelay), `AppleMusicConnectionViewModelTests` (bounded-yield state polling; never required Apple Music.app — uses `MockAppleMusicConnector`), `SessionManagerTests` lifecycle suite (`waitForReady` safety deadline 3 s → 15 s). `PreviewResolverTests` carries no wall-clock waits or `URLProtocol` stubs in current source — the earlier "rate-limit timing / `.serialized` applied" note did not match the code and was dropped.

---

## Resolved (recent)

### BUG-126 — RESOLVED (ALFVEN.3f): the strobing seam bloom is removed, not bounded (2026-09-10)

ALFVEN.3d bounded this defect (`bloomMaxAmount` 0.85 + `bloomSlewPerSecond` 6.0/s), taking max
frame-to-frame Δluma from **0.4153** to **0.0124** against D-157's 0.05 gate. That fixed the RATE of
the flash and left what it looked like unchanged.

**Matt's M7 on the bounded build** (`2026-09-10T23-25-54Z`, `chain_health` verdict **`clean`**,
peak −0.13 dBFS): *"I don't like the brightening effect on the preset. I would remove it."*

Measured on that capture, the glow sat at its 0.30 constant for **65 %** of frames and pinned at the
0.85 ceiling for **5.2 %**, spending 36 % of the track above 0.30 — it pumped between the approved
look and nearly 3× it. Bounding a flash makes it legal under D-157; it does not make it wanted.

**Fix: the `trebRel` → seam-bloom route is removed.** `displayBloomAmount` is a constant 0.30 again —
the exact value ALFVEN.4f shipped and Matt signed off (*"Looks great"*, `2026-09-10T16-07-07Z`).
The defect cannot recur because the mechanism is gone: post-fix the flash metric reads **0.0038**
with treble bursting at the p99 of Matt's own capture, and the glow no longer moves at all.

**Cost, stated plainly:** Alfvén drops from three declared audio routes to two. §7's routing table
named five; three of the five have now failed contact with real music.

---


### BUG-127 — RESOLVED (ALFVEN.3e): `ALFVEN_DRIVE` was inert, voiding every sweep since ALFVEN.3 (2026-09-10)

**Expected.** `ALFVEN_DRIVE=<x>` sets the MHD forcing amplitude, so the solver's equilibrium and the
film harness's decay run can be bisected without editing a test. Both harnesses documented it, and
the film harness's comment specifically promised `ALFVEN_DRIVE=0` yields *"a decay run — the cleanest
comparison against the spike, because an unforced field just relaxes"*.

**Actual.** It set `AlfvenSolverConfiguration.drive`, which **nothing reads**. ALFVEN.3 replaced the
constant with the audio-driven `audioDrive` (`AlfvenSolver.swift`, `drive: audioDrive`) and left the
config field behind — written by the initialiser, never consumed. `ALFVEN_DRIVE=0` did not produce an
unforced field; it produced whatever the audio map resolved to at a zero bass envelope.

**How it surfaced.** A stability sweep across drive 16 / 18 / 20 returned **byte-identical** output
for all three values, including the same `wMax` to three decimals. Identical numbers from a swept
parameter are the signature of a dead knob, not of a flat response.

**Blast radius.** Any measurement taken with `ALFVEN_DRIVE` between ALFVEN.3 and ALFVEN.3e is void
and must not be cited. Measurements from before ALFVEN.3 are unaffected — the field was live then.
No shipped behaviour was ever wrong: the knob is diagnostic-only, and production always ran
`audioDrive`. The cost was to evidence, not to users.

**Fix.** The dead `drive` field is removed from `AlfvenSolverConfiguration`. Both harnesses now
override `ALFVEN_DRIVEFLOOR` / `ALFVEN_DRIVECEIL`, pinning them together to hold forcing at one
value. Cross-check that the replacement is live: drive 16 reproduces the previously documented
`wMax 57.029`, and 18 / 20 / 24 now differ as they should (67.4 / 77.1 / 94.2).

**Lesson, already in memory as a recurring class.** An override placed on a field the production path
stopped reading fails silently and *looks like* a measurement. When a sweep returns the same number
twice, verify the knob before drawing a conclusion from the flatness.

---


### BUG-114 — RESOLVED (PR.3): the bar-line estimator ran at half its calibrated analysis window (2026-09-04)

**Expected.** `BarLineEstimator` is a verbatim port of `tools/barline_probe.py`, and
`declineThreshold = 1.24` was derived in FT.3 from that reference's margin distribution at
**22050 Hz**, where the fixed `nFFT = 2048` window spans **92.9 ms** per beat.

**Actual.** `BeatGridAnalyzer.applyBarLineEstimate` passed the analyzer's own samples and rate
through unchanged, and `nFFT` is fixed in *samples* — so the per-beat window silently became
**46.4 ms** at 44.1 kHz and 42.7 ms at 48 kHz: under 10 % of a 500 ms beat at 120 BPM, and the part
dominated by the attack transient rather than the beat's harmonic body. Bin maps *do* use
`sampleRate`, so frequency mapping stayed correct and only the duration moved — no wrong-looking
numbers, just uniformly smaller margins.

**Why no gate caught it.** `BarLineEstimatorParityTests` calls `estimate(beats:audio:)` on the
**default** `sampleRate: 22050` — it proves the port matches Python at the reference rate and says
nothing about the rate production passes.

**Evidence + fix.** `BarLineWindowProbe` over 7 fixtures: the margin falls at the short window on
**6 of 7**, and around_the_world flips **1.265 ANSWER → 0.147 decline** across the 1.24 threshold.
`Options.resampleToReferenceRate` now resamples to 22050 before feature extraction and
`applyBarLineEstimate` passes it; `Options.legacy` (the parity default) is unchanged and every
legacy margin reproduces exactly.

**Not fixed:** bleed, bohemian_rhapsody, clair_de_lune, girl_from_ipanema decline at both windows
(the first two are D-210 wrong-level cases). **The probe counts ANSWERS, not CORRECT answers** — no
downbeat ground truth. Two beat-averaging arms measured and **not adopted**. Full per-arm table and
reasoning: [`PR3_BARLINE_WINDOW_2026-09-04.md`](../diagnostics/PR3_BARLINE_WINDOW_2026-09-04.md).

### BUG-113 — RESOLVED (DS.6): every toast rendered as a floor-to-ceiling panel inside the chrome (2026-09-03)

**Severity:** P2 · **Domain:** `app.ui` / playback chrome · **Failure class:** `api-contract`

**Expected:** a `PerformanceToast` is one or two lines of copy tall (UX_SPEC §9.4: "the quietest thing that can still be noticed"), bottom-trailing, clear of the controls cluster.

**Actual:** inside `PlaybackChromeView` every toast rendered as a panel the full height of the window, its 4 pt accent bar clipped to 100 pt at the top and the copy floating mid-panel, drawn over the top-trailing cluster. Present since the toast was written (the accent bar has been a `Color.frame(width: 4)` since U.6; DS.3's `PerformanceToast` kept it); never seen because no capture of the chrome with a toast in it existed until DS.6's harness rendered one.

**Reproduce:** any toast during playback — the DS.6 harness `chrome-toast-*` scenarios, or live: press `l` (diagnostic hold) in a session.

**Artifacts:** `docs/reviews/DS.6/before/chrome-toast-info.png` (harness, `main` at `d4fb16ea`) and `docs/reviews/DS.6/after/live-toast-BUG113-before-fix.png` (the real app, local-file session, 2026-09-03 — the "Diagnostic hold ON" toast covering the cluster).

**Root cause:** `ToastRegion` sits in a `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)`, so its `VStack` is offered the whole window height and offers it on to the toast's `HStack`. The accent bar is a `Color`, which accepts any proposal, so the `HStack` — and the toast — took the full height. The DS.3 harness never saw it because it rendered `PerformanceToast` alone in `.frame(width: 360)` with no height proposed.

**Fix:** `.fixedSize(horizontal: false, vertical: true)` on the toast (one line, `PerformanceToast.swift`). Collapsed into one increment under the trivial-fix rule (<5 lines, root cause read straight off the view tree, no architectural risk); P2, so the multi-increment rule does not apply.

**Verification:** *automated* — `PerformanceToastLayoutTests` hosts a toast the way the chrome does (a 960 × 600 frame, bottom-trailing) and measures the rendered accent bar: < 100 pt, red before the fix. Harness re-render: `docs/reviews/DS.6/after/chrome-toast-*.png` at copy height. *Manual* — Matt's DS.6 M7 (a toast during the live walk).

### BUG-112 — RESOLVED (DS.5 M7): Ready's first-audio autodetect never listened — the tap was installed after `.playing`, so Ready always self-advanced (2026-09-03)

**Severity:** P1 · **Domain:** `app.ui` / session flow · **Failure class:** `wiring`

**Expected:** a streaming session at `.ready` waits until real audio is detected (`.silent → .active` sustained ≥250 ms, UX_SPEC §6.3) or the listener taps "Begin now".

**Actual:** Matt, session `2026-09-03T15-58-14Z`: *"Uzume transitioned from preparing to ready but then automatically proceeded from the ready screen to start the show without me pressing any buttons."* The log: `startSession→ready` 15:59:47, `startAudio → SYSTEM-AUDIO TAP` 15:59:48, `tap RMS 0.000`, `signal quality → red: no signal`. Playback began one second after Ready with no audio at all.

**Root cause:** the system-audio tap was installed only by `PlaybackView.setup()` — after `.playing`. During Ready there was no tap, so `FirstAudioDetector` subscribed to `CaptureStateSurface.audioSignalState` at its default value, `.active`; the detector's cold-start rule ("an initial `.active` counts") fired 250 ms later. U.5's autodetect had never actually run: Ready always self-advanced a quarter-second in, and until DS.5 made Ready a screen worth looking at, nobody noticed.

**Fix (D-240 §8):** the engine's `.ready` sink calls `VisualizerEngine.startListeningForFirstAudio()` for streaming sessions — resets the surface to `.silent` (nothing heard yet), preflights the Screen Recording grant (never requests; the gate above the state switch already did), installs the tap. `startAudio()` at playback now leaves a running tap alone (`AudioInputRouter.start` begins with `stopInternal()`, which would have torn it down and reset the silence detector at the handoff). Matt chose this over removing autodetect and making "Begin now" the only door.

**Verification:** ✅ Matt, live, same day, on the fixed build: *"Ready waited for Spotify this time."* Ready held on the open cave until play was pressed in Spotify.

### BUG-111 — RESOLVED (BUG111.1): the first-run permission card could not lead to a grant (2026-08-31)

**Severity:** P1 · **Domain:** `app.ui` / permission · **Failure class:** `api-contract`

**Expected:** on a machine with no Screen Recording grant, the permission card's primary action leads to a state where the user can grant capture.

**Actual:** the card's only action deep-links to Privacy & Security → Screen & System Audio Recording, which does not list the app at all. There is nothing to toggle, and no other UI is reachable — the permission gate in `ContentView` sits above the session-state switch, so the app cannot be entered.

**Reproduce:** `tccutil reset ScreenCapture io.uzume.mac`, relaunch. (Equivalently: a fresh install, or the RN.1 bundle-ID change, which orphaned the `com.phosphene.app` grant.)

**Artifacts:** source verification, not a session capture — `grep -rn CGRequestScreenCaptureAccess --include='*.swift'` returns exactly one call site, `UzumeApp/VisualizerEngine+PublicAPI.swift:56`, on `startAudio()`. Matt confirmed on the live app that no path reaches it from the gated state.

**Root cause:** macOS registers an app in the Screen & System Audio Recording list only when the app calls `CGRequestScreenCaptureAccess()`. U.2 (2026-04-22, `63908e94`) chose preflight + URL scheme and explicitly never prompted — "the request API's system dialog doesn't compose with 'Open System Settings and return'" (`ENGINEERING_PLAN.md` §U.2 Key decisions). **That rationale silently assumed the app was already listed.** It holds for the revoke-and-re-grant case it was written for; it does not hold on first run, where the deep link has no target. (The rationale dates from U.2, not U.11 — verified against the commit that introduced the file.)

**Fix (BUG111.1):** `PermissionOnboardingView`'s primary CTA now calls `CGRequestScreenCaptureAccess()` ("Allow Access"), which registers the app with TCC and shows the OS dialog. The old deep link is kept as a secondary link ("Already allowed it? Open System Settings") for the already-denied case, where macOS suppresses the dialog but the app *is* listed. No state, no branch — both routes are always available, so the card is actionable whatever the TCC state. `SystemScreenCapturePermissionProvider` still never prompts: it stays the passive probe `PermissionMonitor` polls, and its header comment now says why rather than repeating the retired rationale.

**Verification criteria:** *automated* — app build green, `PermissionOnboardingViewTests` identifier set covers `uzume.onboarding.grantAccess`, `Scripts/check_user_strings.sh` PASS, `swiftlint --strict` 0. *Manual (Matt, required — UX-flow change per the defect skill)* — `tccutil reset ScreenCapture <bundle id>`, relaunch, press **Allow Access**: the OS dialog appears, the app is thereafter listed in the pane, and after toggling it on the app auto-advances past the card without a relaunch (`PermissionMonitor`'s `didBecomeActive` refresh).

**Status:** fix landed and green on the automated gates; **not resolved until Matt's live first-run walk.** Per the defect skill's multi-increment rule the instrumentation and diagnosis increments were collapsed into the fix — the root cause was established from source and Matt's live observation with nothing left for instrumentation to expose. **Matt approved the collapse in chat, 2026-08-31** ("yes, collapsing them is fine").

---

**Live validation (Matt, 2026-08-31).** Walked on a machine reset to the first-run state with
`tccutil reset ScreenCapture com.phosphene.app`. All four steps held: the card showed **Allow
Access** as its primary button; clicking it raised the macOS system dialog — the thing that did
not previously exist, and the whole deadlock; the app then appeared in Privacy & Security →
Screen & System Audio Recording without being added by hand; and the card advanced to the normal
UI with no manual relaunch, `pollForScreenCapturePermission()` picking the grant up on its own.

**Validated on the pre-rename identity, deliberately.** This branch predates RN.1, so it builds
`com.phosphene.app` / `Uzume.app`. The fix is identity-independent — it is about whether
the card calls `CGRequestScreenCaptureAccess()` at all — and testing on `io.uzume.mac` would have
burned the Screen Recording grant set up for RN.1's own verification. Worth an opportunistic
re-check under the new identity, but nothing in the fix touches identity.

**One false negative en route, tooling not code.** The first walk launched via a
`DerivedData/UzumeApp-*` glob and hit a stale build (25 such directories exist on this
machine), reporting "only Open System Settings" — indistinguishable from the fix not working.
Resolve the exact `BUILT_PRODUCTS_DIR` before quoting a launch path in any manual walk.
