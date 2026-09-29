# Lane I: abandoned, stalled or unfinished work (read-only sweep, 2026-09-29)

**Scope swept:** ENGINEERING_PLAN phase headers and non-✅ rows, §Immediate Next Increments, CODE_AUDIT_2026-06-13 Part C against `git log --all`, PUBLISHING / SECURITY_POSTURE / D-113, the BETA slate and preset design docs, `prompts/` and `docs/prompts/` against commit IDs, scoping and proposal docs, production-code markers, and all 67 unmerged refs mapped to GitHub PR state.

**Headline.** Most "🔨 in progress" headers in the plan are stale; the work behind them finished. What is actually unfinished and matters for Oct 15 falls into four groups:
1. The distribution path (CLEAN.2.5b) is still in flight.
2. Several promises were deferred until "there is a public build". That trigger has now fired, and nobody has picked them up.
3. Two old follow-ups affect testers directly: the Apple Music permission-denied state and Bluetooth output latency.
4. Eight of the eleven beta scene attempts never started.

Beta-relevance calls below are my honest read, not decisions.

---

## BLOCKS the beta

### I1. CLEAN.2.5b: the notarized DMG (in flight, unmerged, no PR)
- **What it is.** Developer ID signing, notarization and the `Scripts/release.sh` DMG. Without it, no tester can open the app. It lives on branch `clean-2-5b`: 13 commits, all dated today, no PR yet.
- **When it stalled.** It was deferred 2026-06-15 ("blocked on a paid Apple Developer Program membership", SECURITY_POSTURE §3) and sat for 3.5 months. It restarted today, when the Plait & Pattern team was added.
- **Why it existed.** GAP-10 of the June audit. The hardened-runtime half (2.5a) shipped in June.
- **Dropped vs finished.** Dropped means no beta. Finished means testers can install and open a DMG. Three things ride on this branch and are still open:
  - **The public build flavor.** Matt decided today: *"start distinguishing between the developer version … and the public release."* BUG-157 (the Documents-folder prompt at first launch) is filed with a fix plan (`UZUME_PUBLIC`), but it is not implemented yet.
  - **The fresh-account rehearsal** (Task 8).
  - **The merge itself.**
- **Two things to know.**
  - **ID collision.** `clean-2-5b` files **BUG-157** (Documents prompt) and **BUG-158**. Open PR #311 (`claude/bug-157-stemsep-threads`) *also* files **BUG-157**, for an unrelated StemSeparator test fix. Whichever merges second has to renumber.
  - **Tester floor.** The CLEAN.2.5b decision, on this branch, raises the floor to **macOS 15.0, arm64 only**. The beta brief assumes testers on macOS 14.x. Recruiting needs to know this now. DIST-LIM also records that only macOS 26 has been run.
- **Effort.** M: flavor gating, rehearsal, merge.

---

## SHOULD FINISH before Oct 15 (my read)

### I2. Public-build promises whose trigger has fired
Four separate deferrals were each written as "not until there is a public build". None has been revisited.

- **The stall card still tells users to use Terminal.** VERIFIED.
  - D-165 (2026-06-17) item 3 and UX_SPEC §7.5 say: *"soften its copy before any public build."*
  - The shipped card, which is not DEBUG-gated (`PlaybackView.swift:152`), shows `sudo killall coreaudiod` as step 1 (`AudioStallOverlayView.swift:41–42`). Step 2 reads *"If you just rebuilt Uzume, re-grant…"* (`Localizable.strings:94–95`).
  - A tester whose audio drops would be told to paste a sudo command, with copy aimed at a developer. Effort **S**.
- **CLEAN.7.7 and 7.8 were deferred "until Uzume has a public build".**
  - D-169 (2026-06-18) deferred 7.7 (Reduce Transparency and Increase Contrast) and 7.8 (a degraded-but-honest first run on a fresh install). Its trigger to revisit is literally "a public-build / release-readiness pass".
  - 7.8 is partly being exercised by the CLEAN.2.5b rehearsal. 7.7 matters more now that DS.4 added vibrancy.
  - Needs at least a re-decision. Effort **S** to decide, **M** to build 7.7.
- **Developer surfaces in the tester build.** VERIFIED.
  - These keys are live in Release and listed in the `?` help overlay:
    - `L` diagnostic hold
    - `[` / `]` beat-phase calibration
    - `b` "Cycle bar-phase offset (BUG-007.4)"
    - `,` / `.` "Audio output latency (BUG-007.6)"
    - `d` debug overlay
  - Only the scene-cycle and stall-card keys are `#if DEBUG` (`PlaybackShortcutRegistry.swift:99–151` vs `:156`; `PlaybackView.swift:285–319`).
  - Other developer surfaces: the Ended screen's **"Open sessions folder"**, the Settings record-sessions switch (BUG-158), and Spectral Cartograph reachable by arrow keys (a diagnostic scene, not excluded from cycling).
  - These are exactly what today's public/developer split is meant to sort, but only BUG-157 is scoped. Effort **S–M**.
- **Tester-facing notes don't exist yet.** `RELEASE_NOTES_DEV.md:5` says *"User-visible release notes are not yet in scope (no public build)."* `QUALITY/RELEASE_CHECKLIST.md` is a developer-review checklist. Nothing tells testers the known limits: DIST-LIM, SCAN-LIM (non-English Spotify untested), BUG-152. Effort **S**.

### I3. Apple Music: "permission denied" was never detected (TODO since 2026-04-23)
- **What it is.** VERIFIED.
  - `TODO(U.3-followup)` at `AppleMusicConnectionViewModel.swift:13–14`.
  - AppleScript error −1743 (Automation denied) is swallowed and returns nil (`PlaylistConnector.swift:247–254`). That becomes `[]` and then `.noCurrentPlaylist`.
  - The `.permissionDenied` state and its view branch exist (`AppleMusicConnectionView.swift:67`), but no code ever assigns it.
- **When it stalled.** U.3, 2026-04-23. Never filed in KNOWN_ISSUES.
- **Why it existed.** U.3's pre-flight found that −1728 and −1743 were indistinguishable in how the connector handled them.
- **Dropped vs finished.** A tester who clicks "Don't Allow" on macOS's Automation prompt sees *"Start a playlist in Apple Music, then come back. Checking every 2 seconds…"* forever, even while a playlist plays. macOS does not ask again. Finished, they would get the existing "Open System Settings → Automation" card.
- **Effort.** S.

### I4. Bluetooth / AirPods output latency: the promised setting never shipped (since 2026-05-07)
- **What it is.**
  - Beat-phase display is shifted by a fixed **50 ms**, tuned to internal Mac speakers (`VisualizerEngine.swift:952–956`).
  - The comment reads: *"AirPods / Bluetooth users will need a higher value; surfaces as a setting in a future increment."*
  - BUG-007.6's own record (KNOWN_ISSUES_HISTORY:5808, 5823) gives 100–300 ms for Bluetooth and 500–1500 ms for AirPlay, and leaves *"per-output-device automatic detection … future increment if needed."*
  - No production code reads device latency: no `kAudioDevicePropertyLatency`, no `presentationLatency`. The only adjustment is the developer `,` / `.` keys.
- **When it stalled.** 2026-05-07. No KNOWN_ISSUES entry.
- **Why it matters now.** Beat-locked scenes are now headline features: Kagura, Fireflies' walking flashes, Membrane's strikes. The tester profile explicitly includes AirPods.
- **Dropped vs finished.** Dropped: Bluetooth listeners likely see beat accents land noticeably off what they hear. Finished: an automatic per-device offset, or a simple setting.
- **Confidence.** VERIFIED that there is no device-aware compensation. PLAUSIBLE on exactly which paths and scenes it affects: I didn't trace the local-file playhead clock end to end.
- **Effort.** M.

### I5. Eight of eleven beta scene attempts never started (cutoff Oct 11, 12 days away)
- **What it is.** The slate (§00) planned eleven originals in parallel lanes and expected 8–10 to certify, for about 33–35 certified at beta.
  - **Delivered:** Fireflies (FF.5, the 27th) and Kagura (KAG.4, the 26th), plus SCAN, which isn't a scene.
  - **No commits, branches or worktrees:**
    - Lane 1's next two (Pendulums, Harmonograph)
    - All of Lane 2 (Drumhead, Rain on Glass, Pool)
    - All of Lane 3 (Sumi, Physarum Species, Galaxy)
    - Lane 5 (Goldengrove)
  - The session prompts `prompts/DH.0`, `SUMI.0` and `GG.0` were written 2026-09-24 and never ran.
- **Why it stalled.** Matt's review time went to Fireflies (5 rounds), Kagura (6 increments), SCAN and defects. The slate named review time as "the real constraint".
- **Dropped vs finished.** At the observed pace (about 5 days of heavy Matt involvement per scene), one more scene at most is realistic. The beta roster is 27 certified plus uncertified Waveform as the launch default, not 33–35.
- **Beta relevance.** Should-decide now: name the one scene to attempt, or declare 27 the roster so the Oct 12–14 soak isn't squeezed.
- **Effort.** L per scene.

### I6. Pending live checks piling up on the paths every session uses
These are "✅ code-complete, Matt's live check pending" items. Each needs a few minutes of Matt watching or listening. None is abandoned yet, but together they are the stalled tail. The Oct 12–14 soak is the natural place to close them.
- **Every session:**
  - NRG.3 (scene choice reads the energy curve) and NRG.4 (scene changes land on energy changes), 2026-09-27
  - BUG-148 live check
  - BUG-133 felt verdict (09-14)
  - BUG-144 feel check
- **Local files:** LFSEEK.1 / BUG-151, where the last second of a track should be heard.
- **Streaming and audio:**
  - BUG-139 streaming validation (09-23)
  - BUG-117 live confirm (09-08)
  - BUG-070, the device-change reinstall. Pending since **2026-07-12**, and relevant to AirPods swaps.
  - BUG-106 felt half
- **Effort.** S each.

### I7. Recorded-but-never-chased observations on certified scenes
- **Cytokinesis "hangs for seconds before restart"** (Matt, 2026-09-04).
  - PR.4's done-when was "both are filed with BUG IDs". Neither was filed, and PR was superseded 09-24.
  - Cytokinesis was the most-selected scene in PR.8's census: 11 of 50 selections.
  - A tester would read a multi-second freeze as a hang. It may be a simulation reset rather than a render stall: the max recorded frame gap was 199 ms.
- **OBS-DS6-1: Ferrofluid Ocean blacked out mid-track** (2026-09-03). "Recorded, not chased."
- **Effort.** S to file and try to reproduce; M to fix.

### I8. The photosensitivity gate is v1 full-frame only (follow-ups since 2026-06-16)
- **What it is.** `FlashAnalyzer.swift:15–25` lists as "Follow-up" regional/area flashes (*"a flash confined to < the full frame can move the full-frame mean by < 10 % and be missed"*) and the separate saturated-red flash channel. Neither was built. The runtime clamp was declined (D-166).
- **Why it matters now.** This is the only enforcement behind a public photosensitivity claim. New beat-flash scenes are regional by design: Fireflies' patches take turns flashing across the meadow. I'm not saying any scene is unsafe; the gate can't tell.
- **Effort.** M. My read: should-finish because it's a safety claim, not a feature.

### I9. CI "Option B": the required check runs a sliver of the suite (since 2026-06-15)
- **What it is.** The required `fast-gate` runs about 21 hand-picked engine suites (`ci.yml:128–151`) out of about 2,700 test functions. The "full-suite-minus-skip-list" widening was deferred at CLEAN.5.1 and re-listed at RECON (2026-08-03). It was never done.
- **Why it matters now.** The next two weeks bring many parallel-session merges, gated only by manual closeouts.
- **Beta relevance.** Should-finish-lite, flagged as my read.
- **Effort.** M.

### I10. Small, user-visible: the Ended screen's duration is always "—"
- **What it is.** VERIFIED. `ContentView.swift:86` passes `sessionDuration: nil`, so `EndedView` always renders a line that is just "—" (`ended.summary.duration = "%@"`). QR.4 wrote "TODO follow-up" in May.
- **Effort.** S. Fold into the public-flavor pass, which also has to decide the "Open sessions folder" button beside it.

---

## AFTER the beta (real work, wrong fortnight)

- **I11. CLEAN Phase 8 = PUB R3.3–R3.5.** Decompose VisualizerEngine (5.1k LOC, 8 locks) and the RenderPipeline switchboard. Queued since 2026-07-12.
  - Dropped: the concurrency-risk surface stays large.
  - Finished: safer change velocity.
  - Starting it before a beta would be the risk. **L.**
- **I12. CLEAN Phase 6 rows.** Screen-space texture sampling (6.3); anchor, depth and per-pass GPU timing (6.4); Glass Brutalist and light-shafts wire-or-retire (6.5); **GPU / drawable-invalid recovery (6.6)**. All "After" since June. 6.6 overlaps the open hang class BUG-085 / BUG-081 / BUG-060. **L.**
- **I13. PREP.3 candidates** (since 2026-09-14): tune `pacingRate` against live numbers, the unexplained 23–45 GB at four workers, and Option 2 ("fully prepared inside 300 s"). PREP.2's early start was live-validated and BUG-132 is resolved. Pacing was only measured on the Mac mini (see Could not verify). **M.**
- **I14. Phase PR's open register rows** (superseded by BETA 2026-09-24, D-255). These are Matt's own asks on certified scenes, never done:
  - Filigree "movie on a loop"
  - Mitosis "speed uniform"
  - Nacre "too fast"
  - Floret "kinda boring"
  - Witchlight "more looping"
  - The colour cluster: Aurora Veil, Glaze "quite bright", Fata Morgana "too dark"
  - Volumetric Lithograph excluded on tier 1 ("may simply not be appearing")
  - Stave "hazy"
  - Fractal Tree "more trees"

  If dropped, the beta ships the roster with these known weaknesses. Each is **M**.
- **I15. Beat-sync program tail.**
  - DBN.3's decision has been "awaiting Matt" since 2026-08-03.
  - FT.2 needs re-scoping.
  - RLG (the rolling grid for streaming) is research-gated.
  - BUG-065 is parked (D-206).

  The slate explicitly excludes all of this from the window. **L.**
- **I16. CENSUS retune candidates** (the phase has been 🔨 since 2026-07-10): the mood-scaler re-estimate, the D-154 threshold, and the K-S key bias (= BUG-149 / BUG-054). Partly overtaken: D-259 means scene choice no longer reads mood, and BUG-140 reworked the D-154 gate. **S–M** each, or close the phase.
- **I17. DS.7 `PerformancePreflight`.** Awaits a design pass with Matt (since 2026-09-03). The prototype lives in uzume-site, and the integration point doesn't exist yet. **M.**
- **I18. The D-113 Milkdrop notification decision.** PUBLISHING §4 says publication *is* the trigger and "needs Matt's pick + a DECISIONS entry." The repo has been public since about 2026-08-31, and no D-number has resolved it. It's a courtesy and policy call. The beta distributes 7 Milkdrop-inspired scenes, but D-113's trigger is about contributors, not app distribution. **S** (a decision).

---

## RETIRE candidates (terse)

**I19. Unmerged branches with real but superseded work.** Nothing here looks wanted; confirm before deleting.
- `origin/claude/ricercar-echo-look-prompt-bd7993`: 25 commits, 07-10. Ricercar was certified via #145–147.
- `claude/wl13-kickoff-3693fa`: 915 lines, 08-07. An alternate WL.13; the landed WL.13 is the 08-18 BUG-095 follow-up.
- `claude/alfven-1c-fft`: a WIP split. Its content landed in #209.
- `codex/gate-1-release-engine-tests`: PR #41 closed, superseded by BUG079.1. It is still checked out at `~/.codex/worktrees/85ac`.
- `claude/wl-m7-diagnosis`: WL.2-e/f, 08-03.
- `clean-2.5b-notarize-staged`: superseded by `clean-2-5b`.
- Prompt-only branches: `chr3-prompt`, `md0-phase-md-reconciliation`, `ds1-prompt-authoring`.

Every other `--no-merged` ref maps to a merged (squash) PR. The only open PRs are #311 and #309, both from today. There are also 3 stale stashes (PR.17 WIP 09-05, which already landed; MEN.3g 08-05; WL.3 08-04) and 16 worktrees, most on merged branches.

**I20. Prompts written, never run.**
- FARADAY.1 (09-09): Faraday was spiked and "design locked", then displaced by BETA.
- MD.1: retired by D-215.
- NB.9-cert, DM_*, V.7.7C.2-commit2/3, AV.6-band-footprint: historical.
- DH.0, SUMI.0, GG.0: retire if I5 narrows the slate.

**I21. Specs and scoping never actioned.**
- `HG_SDF_VENDORING_SPEC` (SDF.1): no commits, and its named consumers (Glass Brutalist, Kinetic Sculpture) are retired.
- `PHYSARUM_SKETCH_SPEC`: only live if Physarum Species starts.
- `MULTI_INSTRUMENT_SEPARATION_RESEARCH`: a memo.
- `RENDER_ENVIRONMENT_SCOPING`: says RMENV "is retained", but RMENV.2/.3 were deleted at RECON.14.
- Plan rows never built:
  - Phase CC (Crystalline Cavern)
  - Phase AC (Aurora Curtain)
  - AV.2.3
  - U.5b / U.5c (plan preview was deleted at DS.5)
  - MD.5's remaining 3, MD.6, MD.7 (D-251)
  - V.7.7C.5.3 / .6 (Arachne removed)
  - WHIT (Rosette retired)
  - `EQUATION_PRESET_CANDIDATES`

**I22. Doc and header drift.** Not unfinished work, but each misleads a planner:
- **Plan headers:**
  - Phase RN is still 🔨, but it closed at RN.6 on 09-01 (RN.4's scope was done by RN.5 and RN.6).
  - PREP, CENSUS and PUB are still 🔨.
  - Phase ASH says "Branch pushed, not yet merged", but ASH.2 is on main.
  - DYN.1c still says "NEXT SESSION STARTS HERE", but it was done 08-05.
  - Phase RIC still says "FL.14 NEXT" and "unmerged", but Ricercar is certified.
  - MM.1, CA-Audio and V.7.5 are still "pending Matt".
- **§Immediate Next Increments** was last refreshed 08-27. It never mentions the Oct 15 beta, Phase BETA, SCAN or CLEAN.2.5b, and item 1 still says BarLineEstimator is "NOT WIRED" (it is wired: `BeatGridAnalyzer.swift:225/351`).
- **Code comments:**
  - `PlaybackActionRouter.swift:7` ("all implementations are stubs") is false; `DefaultPlaybackActionRouter` implements U.6b.
  - `SystemAudioCapture.swift:15` still carries "temporary diagnostic mass" from BUG-057.
- **Scoping doc:** `INSTRUMENT_FAMILY_CAPTURE_SCOPING` says "Next is IFC.3".

---

## Reviewed and healthy
- **Phase 6 and Phase 7:** both fully ✅ since April.
- **CLEAN Phases 0–5 and 7:** closed; `git log` has commits for every row.
- **PUBLISHING:** §1 weights cutover done; §2 history rewrite formally retired (D-229); hot-reload decision 4 shipped (PUB.7).
- **Security follow-ups:** D-B ratified as D-205; BUG-051 fixed.
- **PR.9 "certify or remove before beta":** met. Every non-diagnostic scene is certified except Waveform, which is kept by decision D-253.
- **RN.4's persisted keys and paths:** migrated (RN.5, RN.6, `SettingsMigrator`).
- **Release weights:** `release.sh` verifies them (`fetch_weights.sh`).
- **Production code markers:** zero FIXME / HACK / fatalError. The TODOs that describe unfinished user behaviour are I3, I4 and I10. `LocalFolderConnector` is unreachable (DEAD-001).

## Could not verify
- Whether I4's fixed offset also governs the local-file playhead clock that Kagura and Fireflies read. That needs a trace of `PlayheadAnalysisClock` into the scene clocks, or one AirPods session.
- Preparation time and memory on an 8 GB M1 (I13). All PREP numbers are from the Mac mini.
- Whether the Cytokinesis "hang" is a render stall or a simulation reset (I7). That needs a capture.
- Whether anything on the ricercar-echo or wl13 branches is wanted. That's Matt's eye, not the diff.
