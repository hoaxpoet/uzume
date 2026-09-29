# Lane E: Orchestrator, session planning, now-playing, live adaptation

Read-only review of `UzumeEngine/Sources/Orchestrator/**`, `VisualizerEngine+Orchestrator/+TrackIdentityResolution/+Capture/+LocalFilePlayback`, `StreamingMetadata.swift`, `AudioInputRouter` metadata wiring, `NowPlayingSurface`, `DefaultPlaybackActionRouter`, `LiveAdaptationToastBridge`, `PresetScoringContextProvider`, and Settings → Visuals. Checked against the KNOWN_ISSUES Open Index and entry bodies. BUG-132/133/147/148 are not re-reported; their fixes are intact.

## Findings (most severe first)

### E1 — If now-playing can't be read, a streaming session shows one scene all session and runs every song on track 1's beat grid
**P1 · VERIFIED · effort M**
- **Where:** `StreamingMetadata.swift:95-102`. Error -1743 (Automation denied) is logged at `.debug` and returns nil, with no user-facing surface. `VisualizerEngine+Orchestrator.swift:355` `if snapshot.hasPlan, snapshot.trackIndex == nil { return }`. `:147` pre-fires `plan.tracks.first` into the live pipeline while the state is `.ready`.
- **Scenario:** A Spotify tester never sees an Automation prompt until `.ready`, because the playlist comes from a screen scan. The first now-playing poll then raises "Uzume wants access to control Spotify". The prompt copy (`Info.plist:19`) says the access is only "to display what's currently playing", so declining looks harmless. After Don't Allow, or when music plays in the Spotify web player or any other app:
  - no track change ever fires, so `liveTrackPlanIndex` stays nil;
  - the orchestrator wire returns early on every tick, so no planned scene and no reactive scene ever applies;
  - the scene is whatever the loader had current at start, frozen for the whole playlist;
  - the grid, stems, energy levels and beat-irregular flag pre-fired for track 1 drive every song, so beat-locked scenes run at track 1's tempo;
  - the title reads "—";
  - nothing explains any of this.
- **Fix direction:** Detect -1743 and "no supported player", and show a card with an Open Automation Settings button. When there is a plan but no now-playing, fall back to reactive mode instead of freezing. Don't pre-fire for streaming sessions, or clear the pre-fire once audio starts with no identity. Reword the prompt copy.

### E2 — Pausing Spotify or Music for more than ~2 s counts as a new song when it resumes
**P1 (every tester pauses; each time is a moderate, visible reset) · VERIFIED · effort M**
- **Where:** Both scripts only answer `if player state is playing` (`StreamingMetadata.swift:51,67`), so a paused player returns nil. `:229-235` clears `lastTrackIdentity` on nil. On resume the same song fires `TrackChangeEvent(previous: nil, …)`. The BUG-020 gate at `VisualizerEngine+Capture.swift:171` (`event.previous?.title == event.current.title`) does not catch `nil`.
- **Scenario:** Mid-song pause, then resume. On resume the app:
  - resets MIR, so levels re-warm;
  - reinstalls the grid from zero, so beat-locked scenes enter the cold-start phase window again;
  - wipes the Skein canvas and settles Nimbus, Witchlight and Kagura;
  - resets `lastAppliedPlannedPresetID`, so the song's first planned scene cuts back in;
  - restarts the track clock at 0, so every later planned change for that song lands offset by the pre-pause position;
  - re-runs the network pre-fetch and flashes the artwork.

  The same reset happens after any single failed poll mid-song (a transient AppleScript error; PLAUSIBLE). Streaming seek is invisible, so the clock drifts from the music. Repeat-one never resets (see E8).
- **Fix direction:** Also query `player state` and `player position`. Keep the identity while paused. Treat the same song reappearing as a resume, not a change. Use the player position (or a detected jump in it) as the streaming track clock.

### E3 — One local file that fails preparation pairs every later track with the wrong plan (and file 1 failing puts file 2's beat grid under file 1)
**P2 · VERIFIED · effort S**
- **Where:**
  - `livePlan` keeps only cached tracks: `VisualizerEngine+Orchestrator.swift:83-84` `compactMap … guard var profile = cache.trackProfile(for:) else { return nil }`.
  - The local-file path indexes that plan by queue position: `+LocalFilePlayback.swift:195` `planIndex: 0` and `:550` `liveTrackPlanIndex = planIndex`, with `nextIdx` taken from the URL queue (`:367`).
  - `currentPlan` keeps failed placeholders in queue order (BUG-068), so the two index spaces diverge.
  - `handleLocalFileReady` calls `buildPlan()` (`:187`) while the state is `.ready`, and the pre-fire (`+Orchestrator:147`) then installs `plan.tracks.first`, the first *cached* file.
- **Scenario:** Queue [A ok, B failed (corrupt, unsupported or DRM, or an analysis throw), C, D]. `livePlan` is [A, C, D].
  - C (queue index 2) runs D's scenes and segment times.
  - D (index 3) is out of range and never gets a planned change.
  - The D-154 exclusion is applied to the wrong song, so a beat-locked scene can land on an irregular track.
  - Progress counts 3 tracks while the position counts 4.
  - If A itself fails, A plays under C's grid, stems and energy levels until the first advance (BUG-132 class).
- **Fix direction:** Resolve the live plan index by identity (`plan.tracks.firstIndex { $0.track == identity }`), not by queue position. Pre-fire the identity that is about to play, not `plan.tracks.first`.

### E4 — The live-adaptation keys (listed in the `?` overlay) do the opposite of, or nothing like, what their toasts say
**P2 · VERIFIED · effort M**
- **Where:**
  - `DefaultPlaybackActionRouter.swift:490` passes `getSessionTime` = `currentAbsoluteTime` = `Date().timeIntervalSinceReferenceDate` (≈8×10⁸ s; `+Orchestrator:520`). Plan times are session-relative seconds from 0. So `currentTrackIndexInPlan()` (`:580-586`) always returns 0, `extendingCurrentPreset(at:)` always returns `self`, and `nextPlannedSegment` always returns nil.
  - `:287` `self.onApplyPresetOverride(currentID, true)`
  - `:507` ignores the `immediate` flag.
  - `recordPresetTransition` has no callers.
  - The planner and reactive contexts never read `familyBoosts`, `temporarilyExcludedFamilies` or `sessionExcludedPresets`.
- **Scenario, key by key:**
  - **`-` "Excluding X for 10 min":** 8 s later the router re-applies the *same* scene, which restarts it and wipes its state. `applyPresetByID` then sets the manual hold, so the disliked scene stays pinned for the rest of the song. The planner never sees the exclusion, so the family can return on the next song.
  - **`+` "Boosted X":** does nothing to the plan. The extend is a no-op and the boost reaches only the nudge scorer.
  - **`.` reshuffle:** locks track 0 instead of the current track, so the current scene can change (the spec says "current scene unaffected"). `regeneratePlan` plans *all* tracks, uncached ones with `.empty` profiles. If any track is unprepared or failed, the plan's index space changes under the live `liveTrackPlanIndex`, and the current song runs another song's segments until the next track change. The next `extendPlan` then drops the lock and reverts to the compacted plan.
  - **`←`:** always a silent no-op, because `lastPlayedPresetID` is never set.
  - **`→`:** toasts "— at next boundary" but cuts immediately. It scores against `currentTrackProfile()`, which builds a partial identity, misses the cache and gets `.empty`, so repeated presses toggle between the same two scenes (the PR.8.2 pattern, still live on the non-Shift path).
- **Fix direction:** Pass the session or track clock the plan uses. Make the `-` ceiling nudge *away* from the excluded scene. Feed the adaptation fields into the planner and wire `recordPresetTransition`. Or hide these keys for the beta.

### E5 — Settings → Visuals "Hidden scene families", "Quality ceiling" and "Device tier" have no effect on which scenes play
**P2 · VERIFIED · effort S (wire) / S (hide)**
- **Where:**
  - `PresetScoringContextProvider` is never instantiated in the app; only tests build it (`git log -S`: tests only since U.8).
  - The planner builds its context at `SessionPlanner+Segments.swift:204-212` without `excludedFamilies` or `qualityCeiling` (so it defaults to `.auto`). The reactive, nudge and `buildScoringContext` paths do the same.
  - `_buildPlan` uses `detectDeviceTier` and ignores `deviceTierOverride`.
  - `excludedPresetCategories` has no consumer outside Settings.
  - The `SettingsStore.swift:5` header claims they apply at the "next preset transition".
- **Scenario:** A tester hides "Particles" and still gets Cytokinesis, Nebula and Fireflies. Choosing "Ultra" never admits Volumetric Lithograph: it stays budget-excluded on both tiers (24/18 ms > 16.6 ms), so no setting can make the planner pick it. This breaks the UX rule that a control describes what it does *now*.
- **Fix direction:** Build every scoring context from `PresetScoringContextProvider`, or hide the three controls behind a build flag.

### E6 — "Start listening now" after any session inherits the previous session's plan (BUG-024 class)
**P2 · VERIFIED · effort S**
- **Where:**
  - `clearSessionScopedSurfaces()` runs only on `.connecting` and `.preparing` (`VisualizerEngine.swift:1114-1135`).
  - "Start another session" calls `cancel()`, which goes `.ended → .idle` (`ContentView.swift:87`).
  - `startAdHocSession()` goes `.idle → .playing` directly (`SessionManager.swift:383-388`).
  - None of these clears `livePlan`, `liveTrackPlanIndex`, `livePlannedSession`, the energy levels or the beat clarity.
  - `lastReactiveSwitchTime` (`VisualizerEngine.swift:868`) is never reset anywhere.
- **Scenario:** Playlist session → end → Idle → "Start listening now":
  - The first ticks apply the old plan's scenes for the old `liveTrackPlanIndex`.
  - On the first song change, `indexInLivePlan` misses the stale plan, so the wire skips every tick and the ad-hoc session freezes on one scene instead of running reactive mode.
  - The progress chrome shows the old playlist.
  - Separately: after a long reactive session, a later session that falls back to reactive (for example every preview failed) won't switch scenes until its elapsed time passes the old session's last switch time plus 60 s.
- **Fix direction:** Run the session-scoped clear on ad-hoc entry (or on `.ended`/`.idle`), and include `lastReactiveSwitchTime`, `lastAppliedPlannedPresetID` and the manual hold in it.

### E7 — Songs that aren't in the plan freeze the scene for as long as they play, including Spotify's autoplay after the playlist ends
**P2 · VERIFIED · effort S-M**
- **Where:** `+Orchestrator.swift:355-360` ("Off-plan track in session mode … Skip silently").
- **Scenario:** Spotify plays autoplay/radio songs after the last playlist track by default. A tester who keeps listening sees the last planned scene held indefinitely: no reactive rotation, no D-154 check against the new song. The same happens for any unplanned song, a podcast, a Free-tier ad (brief), and the E11 ambiguity cases.
- **Fix direction:** Run the reactive orchestrator for off-plan tracks while a plan exists.

### E8 — A song that plays past its planned length snaps back to its first scene and never changes again
**P2 · VERIFIED · effort S**
- **Where:** `+Orchestrator.swift:235-239`. When the elapsed time is past every segment, `activeSegment` falls back to `?? track.segments.first`. The clock keeps running: a single-file queue loops seamlessly without resetting it (the comment at `+LocalFilePlayback:500` says so), and streaming repeat-one fires no change.
- **Scenario:** Dropping one song (a very common first try) loops it. After the first play-through, the scene cuts to scene 1 and holds for every later loop. Streaming repeat-one does the same.
- **Fix direction:** Map the elapsed time modulo the track duration (single-file loop), or use the player position (streaming), before choosing the segment.

### E9 — Planned transitions are computed but never performed: every scene change is an instant hard cut at an arbitrary moment
**P2 (product gap; Matt may have accepted it through use) · VERIFIED · effort M-L**
- **Where:**
  - `applyPlannedSegment` → `applyPreset` (`VisualizerEngine+Presets.swift:150`) tears down and swaps with no fade. Nothing outside Orchestrator references `TransitionAffordance` or `.crossfade`.
  - The apply fires on the next ~2–3 Hz wire tick, deferred by the 20 s/15 s gates, not on a bar or downbeat.
  - The `LiveAdapter` boundary reschedule only rewrites `incomingTransition.scheduledAt`, which nothing reads, so live adaptation has no visible effect.
- **Scenario:** Scene changes every ~15–25 s land mid-phrase as hard cuts. D-259/NRG.3 specifies "crossfades that lengthen as the music gets calmer", and that never happens.
- **Fix direction:** Defer the apply to the next downbeat on the installed grid (KAG.5 already does bar-line rejoin), and execute `style`/`duration`. This is Matt's product call on priority.

### E10 — "Start listening now" (reactive mode) opens on the same scene every session and rarely leaves it
**P2 · PLAUSIBLE (the argmax logic is verified; "rarely leaves" is inferred) · effort S**
- **Where:** `ReactiveOrchestrator.swift:166-172,180`: `recentHistory: []`, no seed noise, no near-tie band. Energy and tempo are neutral (nil), so the rank is a deterministic argmax. A switch needs a gap above 0.2, or a boundary with a gap above 0.05, against the current scene scored as unexcluded.
- **Scenario:** The BUG-133 fix (near-tie sampling, per-preset fatigue) went into the planner only. The prominent Idle-screen path shows one or two scenes per session, and the same opener every time.
- **Fix direction:** Reuse the planner's seeded near-tie pick, and track per-preset history in reactive mode.

### E11 — The same song twice in a playlist (or two tracks with the same title and artist) loses its plan and its prepared analysis
**P3 · VERIFIED · effort S**
- **Where:** `PlannedSession.swift:303-308`. Two exact matches mean ambiguity, which returns nil even when both matches are the *same* identity. There is no playlist dedupe. Also `Capture.swift:171` drops a real change between consecutive songs with the same title by different artists ("Intro", covers).
- **Scenario:** The duplicate plays off-plan (frozen scene, E7) with no cached grid. A same-title follow-on song keeps the previous song's grid and plan index.
- **Fix direction:** Treat identical-identity matches as unique, or disambiguate by duration or play order. Gate the BUG-020 check on title *and* artist.

### E12 — Local-file sessions also poll Music and Spotify
**P3 · VERIFIED · effort S**
- **Where:** `AudioInputRouter.swift:221-226` starts `metadataProvider.startObserving()` for *every* mode, including `.localFilePlayback`. The track-change callback is not mode-gated.
- **Scenario:**
  - A local-files-only tester with Music or Spotify open gets "Uzume wants to control Music/Spotify" prompts mid-session.
  - If a streaming app is playing, its title replaces the local track's title, and its (uncached) identity uninstalls the local track's grid and stem series and takes the plan index off-plan until the next advance.
- **Fix direction:** Don't start the metadata provider in local-file modes.

### E13 — Shift+→ lands testers on engine test patterns
**P3 · VERIFIED · effort S**
- **Where:** `DefaultPlaybackActionRouter.swift:405-414` walks every loaded preset alphabetically. That includes FFT, Poisson and Staged Sandbox (`exclude_from_cycling`), Spectral Cartograph (diagnostic), uncertified Waveform, and 24 ms Volumetric Lithograph on an 8 GB M1.
- **Scenario:** This is Matt's explicit call for his own navigation. For the public beta, a tester exploring the shortcuts lands on "Poisson Sandbox".
- **Fix direction:** Skip `exclude_from_cycling` and diagnostics in release builds.

### E14 — Toast and permission polish
**P3 · VERIFIED (the relaunch race is PLAUSIBLE) · effort S**
- Adaptation toasts default **on** (`LiveAdaptationToastBridge.swift:40-45`), but UX_SPEC §7.4/§8 says "Default off", so viewers on a shared display see "Boosted Particles".
- The "— at next boundary" copy is false (see E4).
- The toast copy is hardcoded English.
- Spotify users also get a Music Automation prompt whenever Music is running.
- `isAppRunning` → `tell application` leaves a small window: a player quit mid-poll could be relaunched by AppleScript.

## Reviewed and healthy
- **Now-playing poller:** 2 s interval, runs off the main thread (detached task), guarded by `isAppRunning` (it does not launch apps), and the BUG-142 generation guard is correct.
- **Name matching:** exact, then normalized (case, diacritics, width, punctuation; non-Latin letters preserved), then whole-word prefix; only a unique match counts. It handles "- Radio Edit" vs "(Radio Edit)" and truncated scanned titles. Shuffled or out-of-order play is fine because matching is by name, not position.
- **BUG-132:** the pre-fire is gated on `.playing`. Streaming `extendPlan` only appends (same seed; network recovery runs only in `.preparing`).
- **BUG-133/147:** the near-tie band, per-preset fatigue and FNV noise are all present. Planner output is deterministic per seed.
- **D-154** is enforced in the scorer, both planner fallbacks (`categoricallyEligiblePool`) and reactive mode. Diagnostics can never be auto-selected. Uncertified scenes are reachable only if every certified scene is excluded, which is degenerate.
- **Planner edge cases:** 0 tracks or all failed → no plan → reactive. 1–2 tracks, zero-duration tracks (defensive segment) and the force-unwrap (guarded by a non-empty catalog) are all safe.
- **Off-plan track change** installs a nil grid, so there is no stale-grid leak across songs.
- **Local-file transport:** a seek re-applies the new position's scene, queue end → `.ended`, and "previous" at index 0 is a no-op.
- **Toasts** come only from user keystrokes and are coalesced over 2 s, so they're not spammy. The LFPLAN.4 20 s / 15 s gates stop machine-gun switching.

## Could not verify
- **Thread safety of the streaming track-change callback.** It runs `mir.reset()`, `resetStemPipeline` and `resetPerTrackPresetState` on the poller's cooperative-pool thread, while the analysis queue runs `mir.process` and the main thread renders. `MIRPipeline.reset()` takes no lock. Needs a TSan run.
- **NSAppleScript concurrency.** A local-file advance restarts the poller while the old detached query may still be running.
- **Spotify's AppleScript behaviour** for ads and podcasts, and whether transient -1728/-1712 errors occur mid-song (another E2 trigger). Needs a live Spotify Free session.
- **Beat grid and stem series past the first loop** of a single-file session (lanes B/C).
- **How often testers deny the Automation prompt** (sets E1's real reach).
