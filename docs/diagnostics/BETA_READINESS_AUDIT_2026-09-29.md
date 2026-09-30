# Uzume — Beta readiness review and improvement plan (AUDIT.2, 2026-09-29)

> **What this is.** A read-only review of the whole codebase ahead of the **October 15, 2026 public beta**, combined with the known-issues ledger and a sweep of the docs for abandoned work, turned into one prioritized plan. Nothing in the product was changed by this increment.
>
> **Baseline.** Code reviewed at `main@efb3eed3` (2026-09-29 morning); `origin/main` has since moved to `567ed3d2` (test-only BUG157.1). The in-flight release branch `clean-2-5b` (`b18d475c`, local, unmerged) was read, not changed; where it already fixes a finding, this doc says so.
>
> **Evidence.** Eleven review lanes, one per area. Their full reports (file:line quotes, failure scenarios, "reviewed and healthy" and "could not verify" lists) are in [`BETA_READINESS_2026-09-29/`](BETA_READINESS_2026-09-29/) — cite those for detail. Finding IDs below (A1, C2, K1 …) are the lane IDs used in those reports.
>
> **Citing the release branch.** Its distribution decision is cited as "the CLEAN.2.5b decision", not by D-number: that number exists only on the unmerged `clean-2-5b` branch, so citing it from `main` would not resolve.
>
> **Status (2026-09-29): Matt accepted every default in §Decisions.** He has an M4 MacBook Pro and a 4K display, not an M1 Air, so BR.6 measures the high-resolution half and the conservative cap covers the low end.
>
> **Proposed work is numbered BR.0–BR.20 (Phase BR, "beta readiness").** No new BUG-numbers were filed: `origin/main` and `clean-2-5b` already collide on BUG-157, and filing here would add a third claimant. Take the next free ID from the tree when an item is picked up.

---

## The short version

Uzume can reach testers on Oct 15. The release branch already solves the hardest part: a notarized DMG, the correct audio permission, and a public build that records nothing. What stands between that DMG and a beta that goes well is mostly small, specific work. Six areas carry the risk:

1. **Photosensitivity promises the app does not keep.**
   - If macOS Reduce Motion is on when Uzume launches, the visuals ignore it.
   - Opening a local file skips the flashing-lights notice.
   - On every M1-family Mac, Fractal Tree is a full-screen colour field that flashes with the music, and no flash test has ever measured it.
   - Diagnostic and uncertified scenes are one keypress away in the tester build.
2. **The screen goes to sleep mid-song.** Nothing keeps the display awake during a session. A laptop on battery dims, blacks out and locks while the music plays.
3. **A crash risk on every streaming song change.** Spotify and Apple Music song changes reset renderer and analysis state from a background thread, racing the render loop.
4. **When something goes wrong, nothing comes back.** A tester who hits a hang or crash has no way to send evidence. The hang-capture script looks for the pre-rename process name, and builds carry no identifying build number or commit.
5. **Common listening habits break the plan.**
   - Pausing Spotify for more than two seconds counts as a new song.
   - Declining the "control Spotify / Music" prompt leaves one scene for the whole session (Spotify) or an endless "Checking every 2 seconds…" (Apple Music).
   - On about one Spotify session in five, "Start now" never appears until the whole playlist is prepared.
   - Playlists over 64 tracks quietly lose their preparation.
6. **Nobody has run the app on a tester's hardware.**
   - Every performance number comes from one M2 Pro at 1080p.
   - A Retina laptop renders 2.5× those pixels and a 5K display 7×; rendering has no resolution ceiling outside the ray-march scenes, and the quality governor cannot claw most of it back.
   - The app has never run on macOS 15 (the new floor). Shaders compile on the tester's Mac at launch, and a core shader failure there is a crash on every launch.

On scenes: two of the eleven planned beta scenes were built, and both certified. The other nine have not started, and the new-scene cutoff is Oct 11. **The honest beta roster is 27 certified scenes.** It is 26 in practice, because Volumetric Lithograph is certified but never selected (K5).

---

## How to read the plan

- **Tier 0**: already in flight. Land it; don't redo it.
- **Tier 1**: must be in the first build a tester installs.
- **Tier 2**: should land before Oct 15; each is a real, likely tester experience.
- **Tier 3**: fix during the beta, or when a tester reports it.
- **Tier 4**: after the beta.

"**Needs Matt**" marks items with a product decision or a live look in them. Everything else is engineering that a session can take on its own under the defect-handling skill.

**Verification labels** (from the lanes, re-checked by the author where marked ✔︎):
- **VERIFIED**: the code path was traced end to end.
- **PLAUSIBLE**: one link was not confirmed, and it is stated which.
- **✔︎**: re-read against the code or artifacts by the synthesizing session, 2026-09-29. See §Reliability.

---

## Tier 0 — Already in flight: land it (Sep 30 – Oct 2)

### BR.0 · Merge the release branch (`clean-2-5b`), owned by the CLEAN.2.5b session

**What it already fixes from this review:**
- **Distribution (A3).** A Developer ID DMG notarized by Apple, and `Scripts/release.sh`.
- **Permission (A5).** `NSAudioCaptureUsageDescription` is now declared.
- **Supported Macs (A11, B12, H5 in part).** macOS 15.0+, Apple silicon only, version 0.9.0.
- **Recording (A1, A2, F2, B11).** The public build keeps no session records: no raw system audio, no per-stem WAVs, no session.log, no Documents-folder prompt (BUG-157 there).

**Still owed on that branch:**
- **Renumber its BUG-157/158 at merge.** `origin/main` PR #311 already took BUG-157 (the owning session has been told).
- **Run the fresh-account rehearsal** (its Task 8).
- **Merge before the soak.** Today every release-critical change exists only on a local, unpushed branch (H2). A DMG built from `main` would still ask for Documents access, still record, and cannot archive for arm64.
- **Close three `release.sh` gaps (H5, H6, H14):**
  - Embed the git SHA and keep the debug symbols (dSYM) for every build.
  - Make the clean-tree check count untracked files. The engine is an SPM package that compiles every file in its folders, so a stray `.metal` in the checkout would ship as a scene, or crash every launch if it lands in the renderer folder.
  - Stop the GitHub "Latest" release pointing at the ML-weights tarball before the download page links to `/releases/latest`.

Also in flight: PR #309 (POSTURE.1). It corrects SECURITY_POSTURE §2 (the sandbox was never shown incompatible with the tap) and files MAS.0. It is docs only.

---

## Tier 1 — Before the first tester build

### BR.1 · Photosensitivity safety (P1 · M)

The first-run notice is the only protection a photosensitive tester gets. Today it can be skipped, and the mitigations it points to don't hold.

| Finding | What the tester sees | Fix direction |
|---|---|---|
| **F1** ✔︎ Reduce Motion ignored at launch | They turn on macOS Reduce Motion as the notice suggests. It works that session; on every later launch the visuals run full feedback trails and full beat strength. `AccessibilityState.init` seeds `reduceMotion` from the system flag, so the `.onChange` that pushes it into the engine (`UzumeApp.swift:97`) never fires. | Push the state into the engine at startup, not only on change. |
| **F1b** macOS "Dim flashing lights" never read | The one setting made for this audience does nothing. | Read MediaAccessibility's `MADimFlashingLightsEnabled()` (public since macOS 13) and treat it like Reduce Motion. |
| **F7** Notice skipped on the local-file path | ⌘O, Finder "Open With", or a drop goes straight to preparing → 3-2-1 → flashing visuals, with no warning. The notice lives only on the Idle screen. | Require the acknowledgement before any playback, on every path. |
| **F6** The notice's "Enable Reduce motion" button opens System Settings | The tester changes a system-wide setting that F1 then ignores. | Set the in-app "Reduced motion: Always on". |
| **K1 / D1** ✔︎ Fractal Tree on M1, M1 Pro, Max, Ultra | Mesh shading is gated on `.apple8` (`PresetLoader+Mesh.swift:50`, `MeshGenerator.swift:249`), and M1 is Apple7. The fallback is a full-screen triangle (`FractalTree.metal:1297`) whose brightness follows `bass_dev` and jumps with every onset: the whole-frame flash D-157 removed from the real tree. The planner has no capability gate. | **Decided (decision 3):** exclude Fractal Tree on pre-Apple8 GPUs for the beta. Gating the native path on Apple7 waits for an M1 run; Metal 3 mesh shaders are documented for Apple7. |
| **K4** The "27/27 flash-measured" claim has holes | Fractal Tree is skipped. Ferrofluid Ocean's gate measures its G-buffer (depth and material IDs), not light, so the aurora and specular highlights are unmeasured; it is the scene behind BUG-041. Murmuration's birds, Gossamer's and Membrane's feedback, and Waveform (the launch default) are also unmeasured. | Add Fractal Tree (both paths), Ferrofluid Ocean's lit output and Waveform to the multi-pass flash harness. Fail when a scene's measured pipeline is its G-buffer state. |
| **K3 / E13 / F15 / A13** Unchecked scenes reachable | Shift+→ ("cut to next scene", listed in the help screen) walks all 32 loaded scenes, including the three sandboxes and Spectral Cartograph. "Show uncertified scenes" is a Release setting. A scene dropped into the watched user-preset folder is trusted if its sidecar says `certified: true`. | In the public build: filter the walk to certified, non-diagnostic scenes; hide the toggle; turn off the user-preset folder. |

**Done when:** a Reduce-Motion-on launch renders reduced; there is no path to playback without the acknowledgement; no rotation-reachable scene lacks a real flash measurement; Fractal Tree is never selected on Apple7.

### BR.2 · Keep the display awake (P1 · S)

**B1** ✔︎. No power assertion exists anywhere in the app or engine. After the idle timeout the display dims, then sleeps, then the Mac locks, mid-song. On a laptop on battery that's a few minutes.

**Fix:** hold a display-sleep assertion (`ProcessInfo.beginActivity(.idleDisplaySleepDisabled…)`) from Ready through Playing, and release it on end, pause-timeout or window close.

### BR.3 · The streaming song-change crash risk (P1 · M)

**G1** ✔︎. The Now Playing poller runs on a Swift concurrency pool thread (`StreamingMetadata.swift:187`). The engine's track-change closure (`VisualizerEngine+Capture.swift:242-258`) wraps only its UI publishing in `Task { @MainActor … }`. `mir.reset()`, `resetPerTrackPresetState()` and `resetStemPipeline(…)` run inline on the pool thread.

What they race, with no lock on either side:
- Witchlight's bead array and Meniscus's wave state, both owned by the render loop on main.
- `TonalAnalyzer`, `bandDeviationTracker` and `moodAccumulator`, owned by the analysis queue.

A reset landing mid-mutation is an "Index out of range", an `EXC_BAD_ACCESS`, or silent heap corruption that crashes later somewhere unrelated. Each song change is unlikely to hit it, but every streaming song change runs the risk. Lead, not proven: the unexplained freeze "about 3.6 min in" (BUG-085) is about one song long.

**Fix:** send each reset to the owner of its state: preset, geometry and identity to main; `mir` and mood to the analysis queue. Add a TSan run of a streaming track change with Witchlight active. Includes the smaller torn-reference reads in the same closure (`skeinState`, `nimbusState`, `lumenPatternEngine`, `lastResolvedTrackIdentity`).

### BR.4 · The public build shows testers only tester things (P2 · S–M · fold into the public flavor)

`clean-2-5b` added `BuildFlavor` (developer | public) and has already used it to switch off session recording. These are the remaining developer surfaces a tester would meet:

- **The "no audio" card (I2 / F3 / A9)** ✔︎
  - It tells testers to paste `sudo killall coreaudiod` into Terminal (`AudioStallOverlayView.swift:41`) and says "If you just rebuilt Uzume…" (`Localizable.strings:95`).
  - It fires about 10 s after "Start listening now" if the tester is still opening Spotify, because the pause-suppression only arms after audio has been heard once.
  - D-165 said "soften before any public build".
  - **Fix:** show only the Listening badge before any audio. Replace the Terminal step with an in-app "Restart listening" action; see B5 in BR.12.
- **Developer keys in the help overlay (F8 / I2).**
  - L, `[` `]`, ⇧B, `,` `.` and `d` are live, and listed under "DEVELOPER" with bug IDs.
  - `,` shifts the visuals off the beat with no way back until relaunch.
  - `.` is bound twice, so latency +5 ms never fires.
  - `+` never fires on US and UK keyboards, because it needs Shift and the monitor requires an exact modifier match.
- **Raw string keys shown in Settings (F18).** `settings.about.app.title` and two more. Add the missing keys, plus a test that every referenced key exists: `check_user_strings.sh` checks externalization, not existence.
- **The Ended screen (I10 / F18).** It shows "—" for duration and "1 tracks", and offers "Open sessions folder", which the public build hides via BUG-157.
- **`~/uzume_diag.log` (H11 / A12)** ✔︎. It is written into every tester's home folder. It is truncated each launch, so it stays small, but `FileHandle.write` raises an uncatchable exception on a full disk.
- **User-preset hot-reload folder (A13 / G9).** It is live in Release. A `.metal` file there whose name contains `"` or `\` and has no sidecar hits a `fatalError` in `init`, crashing every launch until the file is removed.
- **Tester-facing release notes (I2).** `RELEASE_NOTES_DEV.md:5` says they are out of scope "until a public build". Write one page of known limits: DIST-LIM, SCAN-LIM, streaming vs local-file sync, Bluetooth latency until BR.17.

### BR.5 · Get evidence back from testers (P1 · M · decided: zip plus a GitHub issue link)

BUG-085 is still an open P1 hang, and today nothing a tester experiences can reach Matt.

- **No report path (H3 / F16).**
  - There's no Help menu and no "Report a problem" item.
  - "Copy debug info" is three lines and only reachable during playback.
  - Every build says "1.0 (1)" on `main`.
  - Apple does not forward crash reports for Developer ID apps.
- **Hang evidence is lost (J, D3).**
  - A force-quit produces no `.ips`.
  - `Scripts/capture_hang.sh:18` ✔︎ and `window_state.swift:19` look for a process named `UzumeApp`. The binary has been `Uzume` since RN.1, so the only BUG-085 capture instrument reports "not running" during a real freeze.
  - The stall watchdog's heartbeat now awaits the main actor (`VisualizerEngine+InitHelpers.swift:209` ✔︎), so it is no longer independent of the thread it watches.
  - The keep-last-10 retention has already deleted all three original hang sessions; only `_freeze_captures/` survives.
- **Unidentifiable builds (H5).** No SHA is embedded, and the dSYMs stay in a local `build/` folder.

**Fix direction:**
- **Help › Report a Problem.** Consent-first. It writes a zip the tester sends: recent unified-log entries for the app (`OSLogStore`), any `Uzume*.ips` / `.hang` in `~/Library/Logs/DiagnosticReports`, hardware, OS and GPU, and the build number plus SHA. The public build keeps no session folder, so this is the whole evidence path.
- **An "ended abnormally" marker.** Written at launch and cleared on clean quit. On the next launch it offers the report.
- **An independent watchdog.** When the main thread stalls for more than 3 s it runs `/usr/bin/sample` on its own process into the report folder. The app is unsandboxed, so it can.
- **Two small fixes:** the script's process name and the watchdog's main-actor hop.

### BR.6 · Reality check on tester hardware and macOS 15 (P1 · S to measure, M to act · hardware: M4 MacBook Pro + 4K display, no M1)

The app has run on one machine (macOS 26, M2 Pro, a 1080p display at 1×).

- **Shaders (H1 / H8).**
  - All shaders compile from source on the tester's Mac at launch, with that Mac's Metal compiler. A core renderer shader failure is `fatalError` (`VisualizerEngine.swift:911` ✔︎), so the app crashes on every launch. A scene shader failure silently removes the scene.
  - CI never compiles Metal and never builds Release.
  - **Do:** add a CI step that builds the Release configuration and compiles every `.metal` file. Launch the notarized DMG once on macOS 15, in a VM or on a spare Mac.
- **Resolution and performance (K2 / D4 / D5).**
  - Nothing has been measured on an 8 GB M1, a Retina laptop or a 5K display.
  - The 1080p baselines on the M2 Pro are already 13–15 ms for Cytokinesis, Stave and Skein. Alfvén measured a p50 of 9.99 ms against its declared 2.2 ms.
  - There is no render-resolution cap outside ray-march. Tier detection is a name match on "m3"/"m4".
  - The governor's particle and mesh rungs are dead, and Low Power Mode only turns off bloom.
  - **Do (per decision 4):**
    - Run one session on the M4 MacBook Pro's built-in Retina display, on battery with Low Power Mode on and off, and one on the 4K display. Read `RENDER_TARGET` and `frame_gpu_ms`. `FRAME_BUDGET_RES=2880x1864` and `3840x2160` also run the harness.
    - Apply the conservative cap (about 1440p-equivalent, compositor-upscaled) and exclude Alfvén on tier-1 Macs, which can't be measured without an M1.
    - Use the M4 and 4K numbers to decide whether a cap is also needed above tier 1.
    - The M4 is tier 2 by the name match, so it says nothing about base-M1 frame rates. Scale from it with care.
- **Measured so far (BR.6b, 2026-09-29).** Configuration: **Release** (`swift test -c release --enable-testable-imports`, `PresetFrameBudgetTests.presetFrameCost`, `FRAME_BUDGET_RES=…`). Hardware: **Mac mini M2 Pro (tier 1 by the name match), macOS 26.5.1**. Harness ms per frame (minimum of the timing passes, 24 timed frames after 6 settle frames, with readback), **not** live `frame_gpu_ms`. Bold is over the 16.6 ms 60 fps budget. The harness does not cover Aurora Veil, Ferrofluid Ocean, Membrane, Murmuration or Nimbus (Alfvén is not in its list either).

| Scene | 1920×1080 | 2560×1440 (tier-1 cap) | 3840×2160 |
|---|---|---|---|
| Volumetric Lithograph | 12.23 | **20.09** | **42.64** |
| Cytokinesis | 7.75 | 13.20 | **29.16** |
| Gossamer | 7.95 | 12.80 | **26.70** |
| Fireflies | 7.82 | 12.58 | **26.29** |
| Lumen Mosaic | 7.02 | 11.93 | **24.61** |
| Skein | 6.36 | 9.72 | **19.63** |
| Dragon Bloom | 5.75 | 9.12 | **19.31** |
| Filigree | 5.77 | 8.96 | **18.27** |
| Cymatic Resonance | 5.45 | 8.55 | **17.75** |
| Waveform | 5.86 | 8.82 | 16.59 |
| Nacre | 5.43 | 8.67 | 16.42 |
| Ricercar | 5.33 | 8.38 | 15.77 |
| Nebula | 5.35 | 7.94 | 15.64 |
| Fata Morgana | 5.29 | 7.70 | 14.34 |
| Witchlight | 4.63 | 6.99 | 13.67 |
| Stave | 4.23 | 6.64 | 12.92 |
| Floret | 4.28 | 6.43 | 12.82 |
| Glaze | 4.46 | 6.42 | 11.98 |
| Meniscus | 4.01 | 6.15 | 11.63 |
| Spectral Cartograph | 3.87 | 5.18 | 8.66 |
| Kagura | 2.59 | 3.57 | 6.81 |
| Fractal Tree | 3.32 | 4.30 | 6.50 |
| Mitosis | 2.54 | 3.42 | 5.71 |

  - **Reading.** At native 4K, 13 of 23 measured scenes miss 60 fps on this GPU. At the tier-1 cap (2560×1440) only Volumetric Lithograph does, and it is already excluded by its own complexity cost (decision 2). So the cap does what decision 4 intended on this class of GPU.
  - **Still owed (Matt's sessions, decision 4):** the M4 MacBook Pro's Retina display on battery with Low Power Mode off and on, and the 4K display, reading `RENDER_TARGET` and `frame_gpu_ms`; `FRAME_BUDGET_RES=2880x1864` and `3840x2160` on the M4; the cold first launch after a fresh install. Those numbers decide whether any cap applies above tier 1.
- **Cold first launch (D6).** Measured about 4.2 s of main-thread shader compilation on the installed 0.9.0 build before any window appears, plus 5.6 s unattributed before the first log. That happens again after every app or OS update, and is likely 8–10 s on an M1. If the M1 run confirms it, show the window first and compile off the main thread (or ship a precompiled library).

---

## Tier 2 — Before Oct 15

### BR.7 · Preparation never strands the tester (P1 · M)

- **C2** ✔︎: "Start now" is blocked by one early failure.
  - Readiness counts only a run of `.ready` tracks from position 1 (`SessionManager+Readiness.swift:64`). If any of tracks 1–3 has no preview, the session stays "preparing" until every track is terminal.
  - That's about 3.5 min for 40 tracks and 10 for 100, with only Cancel and no explanation.
  - It hits roughly one Spotify-scan session in five (6–13 % of scanned rows have no usable preview).
  - Fix: count failed tracks as skippable in the prefix.
- **F10 / C11:** "Ready" when nothing was prepared. A connection failure or an all-failed playlist goes to Ready with no plan and no message (`SessionManager.swift:224-231, 333-344`), and the recovery screen is replaced within a frame.
- **F13:** preparation has no escape routes.
  - The banners have no reactive-mode or retry button.
  - "Start reactive mode" is never wired on the recovery screen (`ContentView.swift:178-186`).
  - The "You're offline" screen appears for local-file sessions too, and its button cancels.
- **C10:** missing ML weights degrade silently. Every track becomes partial and Start now never appears. Show a clear error. `release.sh` checks weights, but a build made any other way does not.
- **F11:** Cancel during "Connecting" doesn't stick; the app later jumps to Preparing.

### BR.8 · Long playlists keep their preparation (P1 · S)

**C1** ✔︎. The in-memory cache caps at 64 tracks (`StemCache.swift:176`), and streaming preparation runs far ahead of playback. So on a 120-track playlist, tracks about 6–56 are evicted before they play. They fall back to live-only: no prepared grid, no planned scene, and the screen says "52 tracks not yet prepared".

The 7 MB of separated stem audio per entry is what forces the cap, and nothing reads it at playback. **Fix:** drop it and lift the cap.

### BR.9 · Background preparation stops disturbing live visuals (P1 · S)

**C3 / G3** ✔︎. The preparer is handed the engine's live `StemAnalyzer` and `MoodClassifier` (`VisualizerEngine.swift:1011`). Each prepared track pushes another song's frames through the live AGC, deviation baselines and mood.

For the whole background preparation, stem- and mood-driven motion lurches every few seconds while the preparer analyses the next song, and the stored stem balance absorbs live frames. **Fix:** give the preparer its own instances, as the local-file stem series already does. Confirm with one replay with and without background preparation.

### BR.10 · The "control Spotify / Music" permission and its fallbacks (P1 · M)

- **E1 (streaming, Automation denied):**
  - Error −1743 is logged at debug level only (`StreamingMetadata.swift:95-102`).
  - With no now-playing, the plan never advances. The starting scene holds all session, track 1's beat grid drives every song, and the title shows "—".
  - Spotify users meet the prompt at Ready, and the prompt text ("to display what's currently playing") makes declining look harmless.
  - **Fix:**
    - Show a card with "Open Automation settings".
    - Fall back to reactive mode when there's a plan but no now-playing.
    - Stop pre-loading track 1 on the streaming path.
    - Reword `NSAppleEventsUsageDescription`.
- **I3 / A6 / C6 / F12 (Apple Music, denied)** ✔︎: −1743 becomes "no current playlist" (`PlaylistConnector.swift:247-254`), so the tester sees "Checking every 2 seconds…" forever. The `.permissionDenied` screen exists and is never reached. This has been a TODO since 2026-04-23.
- **E12 / E14:**
  - Local-file sessions also poll Music and Spotify: testers get Automation prompts mid-session, and a streaming app that is playing overrides the local track.
  - Spotify users also get a Music prompt whenever Music is running.
  - Poll only the source the session uses.

### BR.11 · Real listening habits (P1/P2 · M)

- **E2** ✔︎: a pause of more than 2 s is a new song.
  - Both AppleScripts answer only while the player is playing, so a paused player clears the current track. On resume the same song fires as a new track.
  - Analysis re-warms, beat-locked scenes re-enter cold start, Skein's canvas wipes, the first planned scene cuts back in, and every later scene change in that song lands offset.
  - **Fix:** report paused as paused, not as no track.
- **E7:** songs outside the plan (Spotify autoplay after the playlist, ads, podcasts) freeze the last scene indefinitely. Run reactive mode.
- **E8 / B2:** a song that plays past its planned length snaps back to scene 1 and stays there.
  - This covers single-file loops and streaming repeat-one. On the local-file path the analysis clock counts delivered audio rather than following the playhead.
  - From the second loop, stems freeze on the last frame.
  - Each pause adds up to 1.5 s of lead (`PlayheadAnalysisClock.swift:63`).
  - **Fix:** drive the clock from the playhead, wrapped at the file length.
- **E6:** "Start listening now" after a session inherits that session's plan (BUG-024 class). The session clear runs only on `.connecting` / `.preparing`, and ad-hoc goes idle → playing.
- **E3:** one local file that fails preparation shifts every later track onto the wrong plan entry (plan by prepared-list index, playback by queue position).
- **G7:** slow async results land on the next song (pre-fetched BPM, key and meter; a live Beat This! grid). Tag results with a track generation.

### BR.12 · Audio capture lifecycle (P2 · M–L)

- **G2 / B14:** start, stop and reinstall run on three threads with no shared ordering. Ending a session during an AirPods switch can leave an orphan tap feeding analysis, and two IO procs can feed one callback: analysis runs at 2×, beat sync goes wrong, and scratch buffers race. **Fix:** one serial lifecycle queue plus a generation token.
- **G8 (BUG-070 incomplete):** a failed device-change reinstall calls `cleanup()`, which stops the device monitor, so there is no further recovery.
- **B5:** a tap that dies mid-session never recovers.
  - There is no `kAudioHardwarePropertyServiceRestarted` listener.
  - The retry ladder is skipped once audio has been heard.
  - The card's own advice (restart coreaudiod) therefore guarantees Uzume stays silent until the session ends.
- **B6:** a DS.5 regression. The tap now starts at Ready, and with nothing playing the cold-install ladder recreates a working tap at about 6, 16 and 46 s: the "recreate lottery" BUG-057 once lost.
- **G6:** the tap sample rate is never validated, and a rate of 0 traps in `InputLevelMonitor`.

### BR.13 · Local-file transport (P2 · M)

- **B3 (extends BUG-056):** an output-device change during a paused local track restarts it from the top and plays it aloud on the new device while the UI shows paused. A failed restart only logs. **Fix:** resume from the last position (LFSEEK.1 has the machinery) and keep the paused state.
- **B4** ✔︎: opening a new local source while one plays leaves the old audio running. The router stops only on `.ended`. Cancel lands on Idle with music playing and no Stop, and the old track's end-of-file advance starts the new queue mid-preparation.
- **B10:** mono files are analysed an octave high (`processStereo` averages sample pairs).

### BR.14 · Window, keys, cursor (P2 · S each)

- **F4 / D7** ✔︎: fullscreen and display handling attach only if `NSApp.keyWindow` exists at `onAppear` (`PlaybackView.swift:233`), with no retry. In the usual streaming flow Spotify is frontmost, so ⌘F does nothing and Esc in green-button fullscreen asks "End this session?". Take the window from the view.
- **F9:** the playback key monitor catches Esc in Settings and in the help overlay, and asks to end the session.
- **F14:** closing the window doesn't end the session. Capture, the recording indicator and ML keep running with no window.
- **F19:** the cursor never hides during playback.
- **F6:** Settings is reachable only during playback. Add ⌘, and the Idle gear from UX_SPEC §4.1.
- **D8:** "Move to primary display" uses `NSScreen.main` (the key window's screen), so it does nothing from the secondary display.

### BR.15 · Controls that do nothing (P2 · S · decided: hide)

- **F5 / E5:** "Hidden scene families", "Quality ceiling" and "Device tier" never reach scene selection. The quality ceiling is also saved as data but read back as a string, so it is always nil.
- **E4:** the live-adaptation keys (`-` `+` `.` `←` `→`) use wall-clock time against a session-relative plan, so none does what its toast says. `-` re-applies the excluded scene 8 s later and pins it.
- **E14:** adaptation toasts are on by default, though UX_SPEC says off.

**Decided (decision 6): hide all of these for the beta**, and wire them after.

### BR.16 · Honest copy and credits (P2 · S)

- **A7.** The permission screen says "Nothing ever leaves your Mac", and Info.plist says "Nothing is recorded or sent anywhere". But every track's title and artist go to itunes.apple.com and musicbrainz.org, and SECURITY_POSTURE doesn't list MusicBrainz, whose fetcher is unthrottled (C13). **Decided copy (decision 9):** "Your audio never leaves your Mac. Uzume looks up song details on Apple's iTunes and MusicBrainz." Throttle MusicBrainz to its 1 request/s rule.
- **K7 / H9.** There is no attribution surface, and About says "MIT License" for everything. Unmet obligations:
  - Aurora Veil is CC BY-NC-SA 3.0.
  - PANNs is CC BY 4.0.
  - Beat This!, Open-Unmix, CMU mocap (Kagura) and the authors of the Milkdrop presets that inspired scenes get no in-app credit.
  - CREDITS.md's Milkdrop table lists 7 of 8 scenes (Stave is missing).

  **Fix:** add Settings › About › Acknowledgements and correct the licence line. The copyright also reads "© 2024 Matt" in one place, "© 2026 Uzume contributors" in another, and "Plait & Pattern" on the release branch (F16, the CLEAN.2.5b decision §6).

### BR.17 · Output devices as testers have them (P2 · M)

- **I4 / B7.** Beat-phase compensation is a fixed 50 ms tuned for built-in speakers (`VisualizerEngine.swift:952-956`). Bluetooth adds 100–300 ms (BUG-007.6's own figures), so for AirPods listeners Kagura's steps, Fireflies' flashes and Membrane's strikes land visibly early. **Fix:** read the output device's latency (device + stream latency + safety offset) at start and on device change.
- **G4.** At 88.2 or 96 kHz output, live stems never compute: the ring buffer is sized for 44.1 kHz × 15 s, and a 10 s window at 96 kHz doesn't fit. Stem-driven scenes idle with no warning. Size the buffer from the tap rate.
- **B9.** At 96 or 192 kHz the live 1024-point FFT leaves bass three bins wide. BUG-146 fixed preparation only.

### BR.18 · Streaming fidelity for the newest scenes (P2 · M · Needs Matt: one streaming review pass)

Most testers will stream.
- **K6a.** On streaming, the energy curve collapses to one "typical" preview level (`EnergyScale.swift:180`), so Fireflies never thins in quiet stretches and Kagura's section-based dance choice sees a single level. Both were validated on local files.
- **K6c.** Streaming stems start at zero, then overshoot 1.2–3.3× for about 10 s. The BUG-041 warm-up protects only Ferrofluid Ocean's aurora. Eleven certified scenes read the stem deviation primitives unprotected (BUG-084's "no product impact" considered one scene).

**Fix:** treat a partial energy curve as absent on streaming and fall back to the live level, and extend the warm-up to every stem route. Then Matt watches the top ten scenes on a streaming pass.

### BR.19 · The right song, found reliably (P2 · S–M)

- **BUG-152.** The Apple Music path still takes the iTunes search's first hit, and 8 % of rows land on a different song. The verified lookup the scan uses already exists; route Apple Music through it.
- **C7.** A transient iTunes failure (429, 5xx, timeout) is final for the session, and captive-portal HTML is cached permanently as "no preview". Retry with backoff; never cache a non-JSON body.
- **C8 / A10 (decided: the Mac's region, US fallback).** No storefront `country` is ever sent, so non-US testers match against the US catalog. Use the Mac's region, with US as the fallback.

### BR.20 · Flash check v2 (P2 · M)

**I8.** The flash analyzer measures the whole-frame mean only (`FlashAnalyzer.swift:15-25`). Regional flashes and the saturated-red channel have been listed follow-ups since 2026-06-16. The beta's newest scenes flash regionally by design (Fireflies' patches take turns). No scene is known to be unsafe, but the check can't tell, and it is the only enforcement behind the photosensitivity notice.

---

## Tier 3 — During the beta (or when a tester reports it)

Grouped by area. Each is P2/P3 and small to medium; lane reports have the detail.

- **Preparation and network:**
  - **C4:** the iTunes rate limiter busy-spins after cancellation and holds slots.
  - **C5:** 7–10 tracks a minute; the metadata call is redundant with the preview lookup.
  - **C9 / B8:** long local mixes decode whole into memory: about 1.3 GB for a 1 h file, about 3.8 GB for 2 h.
  - **C12:** the main thread reads about 7 MB per local track change.
  - **C13:** artwork bypasses the limiter; `&` and `+` go unescaped.
  - **C14:** cancellation leaks.
  - **C15:** Apple Music durations in comma-decimal locales.
- **Audio:**
  - **B13:** date formatter built on the IO thread; a lock held during a 3.8 MB copy.
  - **B15:** main-thread folder enumeration and file opens (a NAS beachball).
  - **B16:** no media keys or AirPods controls for local playback.
  - **B17:** capture OSStatus failures never reach the log.
- **Renderer:**
  - **D5:** add resolution and 30 fps governor rungs; remove the dead particle rung; time the governor on GPU time, not drawable wait.
  - **D9:** the capture hook re-requests a drawable after a nil.
  - **D10:** `waitUntilCompleted` on main at scene switch and resize.
  - **D11:** `framebufferOnly = false` for developer-only video.
  - **G5:** Volumetric Lithograph loses its half-resolution march after a resize.
- **Planner:**
  - **E9:** planned crossfades are never performed. Every change is a hard cut on a 2–3 Hz tick, not on a bar. **Decided:** keep hard cuts for the beta.
  - **E10:** reactive mode opens on the same scene every time.
  - **E11:** duplicate songs in a playlist, or consecutive same-title songs.
- **Scan:**
  - **G11 / A15:** a stop/start race can leave window capture running.
  - **G12:** a zero row height gives `Int(NaN)` mid-scan.
  - **SCAN-LIM:** non-English Spotify, compact view, 100+ songs.
- **App:**
  - **A8 / F17:** local-file-only use sits behind the Screen Recording permission, and users see it again after every session. **Decided:** let local-file sessions start without it (they don't use the tap). This is small, so take it with BR.14.
  - **G10:** permission poll loops stack.
  - **A14:** file paths are logged publicly.
- **Scenes:**
  - **K8:** Cytokinesis "hangs for seconds" (Matt, 09-04, never filed) is probably its designed 4 s hold (`MitosisGen2Geometry.swift:220`). File it; keep the cells breathing through the hold.
  - **K9:** no test that any scene is visible at silence.
  - **OBS-DS6-1:** Ferrofluid Ocean blackout.
- **Tests:** **H12:** about 135 fixed-time waits remain, the pattern behind five recent flakes (BUG-137/143/150/154/156).

## Tier 4 — After the beta

These come from the abandoned-work sweep, §Abandoned work:
- CLEAN Phase 8 / PUB R3.3–R3.5: VisualizerEngine decomposition (I11).
- CLEAN Phase 6, including 6.6 GPU and drawable recovery (I12).
- PREP.3 (I13).
- Phase PR's register of Matt's asks on certified scenes (I14).
- The beat-sync tail (I15), CENSUS retunes (I16) and DS.7 (I17).
- CI "Option B" widening (I9).
- MAS.0.
- Volumetric Lithograph's cost re-measure (K5).

---

## Suggested sequence (12 days to the cutoff)

| When | Work | Matt's time |
|---|---|---|
| Sep 30 – Oct 2 | BR.0 merge + rehearsal. BR.1, BR.2, BR.3, BR.4, BR.5 in parallel sessions (independent files). BR.6 CI step. | The rehearsal (decisions settled 09-29) |
| Oct 1 – 3 | BR.6 measurement: M4 MacBook Pro built-in Retina (plus battery and Low Power Mode) and the 4K display; macOS 15 if the MacBook Pro runs it | Two short sessions |
| Oct 3 – Oct 8 | BR.7–BR.14 (engineering), in the order listed | None until review |
| Oct 6 – Oct 10 | BR.15–BR.20 | The BR.18 streaming pass |
| Oct 11 | Freeze. Ledger reconciliation (§Known-issues ledger) | — |
| Oct 12 – 14 | Soak on the notarized DMG, run as the three listening sessions below | Three sessions |
| Oct 15 | Ship | — |

If this is more than the fortnight holds, cut from the bottom of Tier 2. BR.7–BR.11 are the ones testers will hit in their first hour.

---

## Manual verification debt: three listening sessions

These are the live checks owed by already-landed fixes (from lane J), grouped so that three sessions clear most of them. Run them on the notarized Release DMG, launched from Finder (not Xcode; see §Hangs).

1. **Local-file session.**
   - **Setup:** a large folder, so preparation overlaps playback; the detailed view on; include a 48 kHz and a 96 kHz file.
   - Listen to song endings: BUG-151.
   - Press Next and seek while preparation runs: BUG-156's product half.
   - Swap AirPods and speakers mid-song, then while paused: BUG-056 and B3.
   - Start a single file a few times: BUG-091.
   - Read the preparation readout and judge whether the scenes suit the songs: OBS-DS4-1, BUG-148, BUG-133, BUG-144, NRG.3, NRG.4.
   - Ready to Start after clearing its cache: BUG-134.
   - A bar-locked scene on a meterless song: BUG-117.
   - Ferrofluid Ocean on the 96 kHz file: BUG-141.
   - Launch with macOS Reduce Motion on, then again with Dim Flashing Lights on: no feedback trails and half beat strength from the first frame (BUG-163, BR.1).
   - Reset the notice (Settings › Diagnostics › Reset onboarding, then relaunch), then open a file with ⌘O: the notice appears before any visuals; "Enable Reduce motion" turns on Uzume's Reduced motion (BR.1, F7/F6).
2. **Streaming session** (an external 4K display if possible).
   - Start and stop twice, and swap output devices: BUG-139 (never live-validated), BUG-070 (pending since 07-12), BUG-058.
   - Pause Spotify for 30 s or more, then end and restart: the tap race, and E2.
   - Move the window between displays after pressing play in Spotify: F4 / D7.
   - Judge stem timing at 4K: BUG-106.
   - Start a long Spotify playlist early (Start now) and watch the first minutes while preparation continues behind playback: no energy / stem twitch each time a song finishes preparing (BR.9).
   - On the M4 MacBook Pro on battery, leave a session untouched past the display-off interval and run `pmset -g assertions` mid-session: BUG-162 (BR.2).
3. **Fresh-account session:** install the DMG, grant permissions, stream, install an update build, stream again: BUG-055, BUG-157 (Documents prompt gone), DIST-LIM. Then force-quit Uzume and reopen it: it offers a problem report; create one and check the zip opens in Finder and the GitHub issue page opens (BUG-166, BR.5).

---

## Hangs and crashes: what changed

- **BUG-085's record misreads its own capture (D2).** ✔︎ in part.
  - The entry says the render loop blocked permanently in `nextDrawable` while "audio/ML ran on normally".
  - The instrumented capture `_freeze_captures/bug085_20260805T224531Z` shows otherwise:
    - `features rows: 6449`, which is one row per completed frame, against a last heartbeat of `frames=6013`. So at least 436 frames completed after the "frozen" heartbeat, which prints only every 600 frames.
    - The last `session.log` line of any kind is about one second after the last frame.
    - All non-main threads are parked.
    - The HANG.1 watchdog never logged a STALL.
    - The process's parent is `debugserver`: a Debug build launched from Xcode.
  - `allowsNextDrawableTimeout` defaults on, so one `nextDrawable` cannot block for 98 s.
  - **Reading:** the whole process stopped, or its recorder stopped, rather than a render-only block. The debugger is a confounder to control, not an explanation.
  - **Next step:** a long session on a Release build launched from Finder, and on the next freeze one question: did the music keep playing?
- **BUG-081 is probably BUG-085** (same signature; the index's 08-04 instances are BUG-085's day). BUG-060 recurred once, undated.
- **G1 (BR.3) is a fresh crash lead** with the right timing for a failure "about one song in".
- **No evidence path from testers** until BR.5.
- **On disk today:** all six recent `Uzume*.ips` reports are BUG-143's test-host crash. None is from using the app.
- **Severity drift:** DEFECT_TAXONOMY classes any hang as P0; the family is filed P1, P2 and P3. Reconcile when the ledger is cleaned.

---

## Known-issues ledger: reconcile before the beta (DOC, S)

From lane J:
- **The Open Index says "Everything in this table is now open work", but about 29 of its roughly 60 rows are closed.** The closed rows are BUG-138, 132, 136, 137, 129, 087, 103, 131, 140, 142, 143, 145, 146, 147, 150, 153, 154, 155, 115, 116, 118, 119, 120, 121, 122 and 124, plus COPY-001, DEAD-002 and DEAD-003.
- **Six index/body contradictions** (in every case the fix is in the code):
  - BUG-115: the index says resolved; the body says "Open, fix NOT obvious".
  - BUG-116: the index says live-confirmed; the body still shows the check outstanding.
  - BUG-118: the Status field says Open; the blockquote says resolved.
  - BUG-119: the index says live-confirmed; the body still shows the check outstanding.
  - BUG-145: the index row says both "passed" and "outstanding".
  - BUG-106: the status line still says the 4K check is pending; the criterion is ✅.
- **Stale entries:**
  - BUG-081's index claims three instances; the body describes one.
  - BUG-133 is measured against the pre-NRG.3 scorer and lists Plasma, which was removed.
  - BUG-144 still says mood is 40 % of every score.
- **Duplicates:** BUG-054 and BUG-149 (key detection); BUG-028 is superseded by BUG-065 and the whole-track grid work.
- **Never filed:**
  - I3 (Apple Music permission denied, a TODO since 04-23)
  - I4 (Bluetooth latency)
  - K8 (the Cytokinesis hold)
  - The Tier 1–2 items above, as each is picked up.

---

## Abandoned work: what each item is, so Matt can decide

This follows the explanations-not-verdicts format: what each item is, why it existed, and what dropping it versus finishing it means. The beta-relevance column is this review's read, labelled as such. Lane I's report has the full per-item text.

**Should be resolved before Oct 15:**

| Item | What it is | Why it existed | Dropped vs finished | Read |
|---|---|---|---|---|
| **I1** CLEAN.2.5b | Notarized DMG, public build flavor | GAP-10, June audit; blocked on membership until 09-29 | No beta vs a beta | BR.0 |
| **I2** "Before any public build" promises | D-165 stall copy; D-169 deferred CLEAN.7.7 (Reduce Transparency / Increase Contrast) and 7.8 (honest first run); developer surfaces; tester notes | Each was deferred with the public build as its trigger, and that trigger fired today | Testers meet developer copy and keys | BR.4. CLEAN.7.7 needs a re-decision |
| **I3** Apple Music permission denied | Never detected since U.3 (04-23) | U.3 found −1728 and −1743 indistinguishable | An endless loop for anyone who clicks Don't Allow | BR.10 |
| **I4** Bluetooth latency setting | Promised in a comment since 05-07 | BUG-007.6's own figures, 100–300 ms | Beat scenes visibly early on AirPods | BR.17 |
| **I5** Nine of eleven beta scene attempts | Pendulums, Harmonograph, Drumhead, Rain on Glass, Pool, Sumi, Physarum Species, Galaxy, Goldengrove: no commits. DH.0, SUMI.0 and GG.0 prompts never run | D-251…D-256 slate | At about five days of Matt's time per scene, one more at most by Oct 11 | Decision 1 |
| **I6** Pending live checks | NRG.3/.4, BUG-148/133/144/151/139/117/070/106 | Code complete, awaiting Matt | Fixed-but-unconfirmed going to testers | The three sessions above |
| **I7** Cytokinesis "hangs"; OBS-DS6-1 | Recorded, never filed or chased | PR.4 done-when said "file both" | The most-selected scene may look frozen | Tier 3 (K8) |
| **I8** Flash check v2 | Regional and red flash detection | FlashAnalyzer follow-ups since 06-16 | The photosensitivity claim rests on a whole-frame mean | BR.20 |
| **I9** CI Option B | Run the whole suite minus a skip-list | Deferred at CLEAN.5.1 (06-15) | About 8 % of engine tests and no app tests gate merges during the busiest fortnight | BR.6 does the Metal/Release part; widening after the beta |
| **I10** Ended-screen duration | Always "—" since QR.4 | TODO follow-up | Visible placeholder | BR.4 |

**After the beta (real work, wrong fortnight):**
- **I11:** R3.3–R3.5 decomposition.
- **I12:** CLEAN Phase 6 (6.6 overlaps the hang family).
- **I13:** PREP.3 pacing; only ever measured on the Mac mini.
- **I14:** Phase PR's register of Matt's asks, e.g. Fata Morgana "too dark", Floret "kinda boring", Nacre "too fast".
- **I15:** the beat-sync tail. DBN.3's decision has been owed since 08-03.
- **I16:** CENSUS retunes, partly overtaken by D-259 and BUG-140.
- **I17:** DS.7 `PerformancePreflight`, awaiting a design pass.
- **I18:** the D-113 Milkdrop notification. The repo has been public since about 08-31, and D-113's trigger was publication.

**Retire candidates (confirm before anything is deleted):**
- **I19:** unmerged branches with superseded work: `ricercar-echo-look-prompt`, `wl13-kickoff`, `alfven-1c-fft`, `codex/gate-1-release-engine-tests` (still checked out in a `.codex` worktree), `wl-m7-diagnosis` and `clean-2.5b-notarize-staged`. Also the prompt-only branches (`chr3-prompt`, `md0-phase-md-reconciliation`, `ds1-prompt-authoring`), three stale stashes and about 16 worktrees on merged branches.
- **I20:** prompts never run: FARADAY.1, and DH.0, SUMI.0 and GG.0 if the roster is called.
- **I21:** specs never acted on: HG_SDF vendoring (its consumers are retired), Crystalline Cavern, Aurora Curtain, U.5b/c, MD.5–7, WHIT, and RENDER_ENVIRONMENT_SCOPING's "RMENV retained" (it was deleted at RECON.14).
- **I22:** plan and doc drift:
  - Phase headers for RN, PREP, CENSUS and PUB still show 🔨.
  - ASH still says "not yet merged".
  - DYN.1c still says "NEXT SESSION STARTS HERE".
  - §Immediate Next Increments was last refreshed 08-27, never mentions the beta, and calls BarLineEstimator "NOT WIRED".
  - `PlaybackActionRouter.swift:7` claims "all implementations are stubs".

---

## Decisions — accepted by Matt, 2026-09-29

Matt's answer: *"accept all the defaults. note that I cannot get an M1 Air, but I have a 4k display and an M4 Macbook Pro."* Each decision below is now settled as stated.

These are recorded here and in `ENGINEERING_PLAN.md` §Phase BR, not as a D-number yet. The next free D-number on `main` is held by the unmerged `clean-2-5b` branch, and filing past it would break the D-number continuity gate. File one D-entry for this set once that branch merges.

1. **Beta roster: call it at 27.** Oct 1–11 goes to Tier 1–2. DH.0 / SUMI.0 / GG.0 move to the post-beta slate.
2. **Volumetric Lithograph: ships excluded** (never auto-selected). In practice the roster is 26. Re-measure after the beta.
3. **Fractal Tree: excluded on pre-Apple8 GPUs** (M1 family) for the beta (BR.1). Try the native path on Apple7 when an M1 is available.
4. **Tester hardware.** No M1 Air is available, so the low-end default applies. Matt has a 4K display and an M4 MacBook Pro, so the high-resolution half of BR.6 is measured, not guessed.
   - **Low end (unmeasurable):** a conservative render cap of about 1440p-equivalent, upscaled by the compositor, on tier-1 Macs, and Alfvén excluded on tier 1.
   - **High resolution (measured):** one session on the M4 MacBook Pro's built-in Retina display (about 2.9–3.5 MP drawn at 2×) and one at 4K (8.3 MP), reading `RENDER_TARGET` and `frame_gpu_ms`. Whether the cap also applies above tier 1 is decided from those numbers.
   - **The MacBook Pro is also the first laptop run.** It covers:
     - the display-sleep fix (BR.2) on battery;
     - Low Power Mode;
     - a thermal soak;
     - the fresh-account DMG session, and DIST-LIM's macOS 15 check if that Mac runs 15.
5. **Tester reports: a consent-first zip plus a pre-filled GitHub issue link** (BR.5).
6. **Dead controls: hidden for the beta.** That covers "Hidden scene families", "Quality ceiling", "Device tier" and the live-adaptation keys (BR.15). They get wired after the beta.
7. **Local files start without the Screen Recording permission** (A8 / F17). Local-file sessions don't use the tap.
8. **Song lookups use the Mac's region** for the iTunes storefront, with the US as the fallback (BR.19).
9. **Privacy copy:** "Your audio never leaves your Mac. Uzume looks up song details on Apple's iTunes and MusicBrainz." (BR.16).
10. **Scene changes stay hard cuts for the beta** (E9). Crossfades or bar-aligned cuts come after.
11. **Recruiting copy states macOS 15+ and Apple silicon only.**
12. **D-113 (the Milkdrop authors notification) stays open.** It remains Matt's call; the default was no default.
13. **No branch, stash or worktree is deleted** without Matt's per-item yes (I19 remains a list).

---

## Reliability of this review

- **Method.** Eleven parallel read-only lanes:
  - A: security, privacy and distribution
  - B: audio
  - C: preparation, network and ML
  - D: renderer and performance
  - E: orchestrator
  - F: app UX
  - G: crash and concurrency
  - H: build and release
  - I: abandoned work
  - J: known issues
  - K: scene roster
- **Lane rules.** Each lane was told to trace every claim end to end, to dedupe against KNOWN_ISSUES, and not to run suites (other sessions share the Mac).
- **Re-verified by the synthesizing session (✔︎):** the most severe claims, read against code or artifacts. These were F1, K1/D1, G1, B1, B4, C1, C2, C3, E2, H1 (the `fatalError`), H6 (`--untracked-files=no`), H7 (`pgrep -x UzumeApp`), I2, I3, I10, the watchdog's main-actor hop, `PlaybackView.swift:233`, the diag-log cadence, the public-flavor recorder switch on `clean-2-5b`, and D2's frame-count and parent-process facts.
- **Corrected or stale lane claims:**
  - **A3** ("no notarization; the release script never ran"): stale. Lane A saw the older `clean-2.5b-notarize-staged` branch; `clean-2-5b` has notarized builds 2–4.
  - **A1 / F2 / B11** (recording): fixed in the public build by `clean-2-5b` `2340d771`, and still true of developer builds.
  - **I5** reported "eight of eleven" not started; the slate lists nine.
  - **I's "zero fatalError markers"** misses `VisualizerEngine.swift:911`. That one is deliberate: Metal init.
  - **D1 and K1 disagree on the fallback's colour** ("green" vs "blue-violet"); the code draws the canopy colour at mid-depth. This doesn't change the finding.
  - **Lane G's report file** was rewritten on disk after the lane finished. The evidence copy restores the lane's own grouping of its "could not verify" list.
- **Not measured anywhere:** frame rates on tester hardware, macOS 15 behaviour, crash frequencies of G1 and G2, and how visible C3 and K6 are. These are the BR.6 and BR.18 sessions.
- **Past-audit lesson** (preset audit 2026-08-25): its counts were wrong three times. Counts here, such as "29 closed rows" and "about 135 fixed waits", are leads. Re-verify before acting on a count.
