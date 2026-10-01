# Uzume — Known Issues

Open and recently-resolved defects. Filed using `BUG_REPORT_TEMPLATE.md`. See `DEFECT_TAXONOMY.md` for severity definitions and process.

## Open Index

*(Ledger reconciliation, 2026-09-30 (BR.KI). The 2026-09-29 beta-readiness audit (lane J,
[`BETA_READINESS_2026-09-29/J_known_issues.md`](../diagnostics/BETA_READINESS_2026-09-29/J_known_issues.md))
found this index claiming "everything in this table is open work" while about 29 of its ~60 rows were
closed, six rows contradicting their own entry bodies, and most of BUG-150–172 missing. BR.11–13 merged while this pass was open; their entries (BUG-173, BUG-056) are in the tables below. In this pass:
every closed entry left §Open, verbatim. Fixes from the last 14 days went to §Resolved (recent). Older
ones went to [`KNOWN_ISSUES_HISTORY.md`](KNOWN_ISSUES_HISTORY.md), along with the four oldest recent
ones (BUG-136, 137, 138, 140), so §Resolved stays inside its 50 KB budget. BUG-054 closed as a
duplicate of BUG-149, and BUG-028 as superseded by BUG-065. Every body whose status was wrong carries a
dated **Reconciled** note. The index is now two tables: work with no fix yet, and fixes waiting on a
live check. Earlier reconciliation notes (RECON.2, RECON.9, the 08-07 and 08-26 passes) are in git
history. The one method note they carried still stands: **before filing another sighting of an
intermittent crash, read the crash reports already on disk** (`~/Library/Logs/DiagnosticReports/`).)*

**Keeping this true.** An entry leaves §Open when its fix is in the tree and its live check (if it
has one) has passed. It does not stay here marked "RESOLVED". A fix that is waiting on a live check
belongs in the second table, not the first.

### Open — no fix in the tree yet

| ID | Sev | Domain | What happens | Next step |
|---|---|---|---|---|
| BUG-085 | P1 | renderer / app.hang | The app freezes and needs a force-quit, minutes into a session. The cause is unknown. The 08-05 capture came from a Debug build under Xcode, and it shows the whole process stopping, not only the renderer (audit D2). | A long Release session launched from Finder. On a freeze, note whether the music kept playing. From testers: BR.5's Report a Problem. |
| BUG-081 | P2 | app.hang | A beachball about 78 s into one session (2026-08-03), with no stack. One instance: the "08-04 ×2" formerly listed here were BUG-085's. Probably the same defect as BUG-085. | With BUG-085. |
| BUG-060 | P3 | renderer / app.hang | The render loop died on a switch to Gossamer (2026-06-18). It recurred once, undated. No stack. | With BUG-085. |
| BUG-091 | P1 | app.session / pipeline-wiring | One local file selected: preparation finishes and nothing ever plays; every audio field is 0. One instance (2026-08-17). Instrumented. | One reproduction: listening session 1, "start a single file a few times". |
| BUG-058 | P3 | audio.capture | Rare: an output-device swap froze the streaming visuals once (2026-06-17); 12 of 12 swaps recovered since. It may have been BUG-139. | Watch in listening session 2. **Session 2 (2026-10-01):** 10 of 10 swaps recovered; BUG-139 closed. |
| BUG-159 | P3 | app / settings | The Settings "record sessions" switch does nothing. | BR.15 (hide). |
| BUG-036 | P2 | audio.capture / performance | Memory allocations on the real-time audio thread (three sites). A glitch risk under memory pressure; never observed. | During the beta, if a tester reports audio glitches. |
| BUG-175 | P2 | preset.fidelity / Kagura · dsp.beat | Kagura sways for a song's first ~16 s instead of dancing when the intro's beat grid is uneven. It reads as warm-up exercises, out of sync. | Measure how many songs it hits (cached grids), then Matt's call on the fix direction. |
| BUG-174 | P3 | preset.fidelity / Cytokinesis | Cytokinesis stops for 4 s before it regrows. The designed hold reads as a freeze (audit K8). | During the beta. |
| OBS-DS6-1 | P3 | preset.fidelity / Ferrofluid Ocean | Ferrofluid Ocean went black for a few seconds of near-silence once (2026-09-03). | Only if seen again. |
| BUG-149 | P3 | dsp.mir / key | Most songs read "F♯ minor" (35 % of 993 tracks). Display-only. BUG-054 merged here. | After the beta. |
| BUG-084 | P3 | dsp.stem | Stem deviation spikes to 35 against a ~3.4 ceiling. The one consumer is soft-kneed, so there is no visible effect. | After the beta. |
| BUG-065 | P3 | dsp.beat | Beat-locked visuals drift 11 ms → 50–70 ms off the beat over a track. Parked (D-206). | After the beta. |
| BUG-076 | P2 | dsp.beat | The prep grid's tempo depends on which 30 s window it reads, on one dense song (Bleed). | After the beta (beat-sync tail). |
| BUG-107 | P2 | dsp.beat | *Money*'s grid is 4 % slow. Root-caused 08-27: the offline grid analysed only the first ~30 s. | After the beta (beat-sync tail). |
| BUG-077 | P3 | dsp.beat / api-contract | `snapToBeats` differs from the Beat This! reference post-processor. Harmless today. | After the beta. |
| BUG-135 | P3 | dsp.beat | The grid's bar "one" can't be confirmed to be the musical downbeat. Left alone on Matt's call (2026-09-14). | — |
| BUG-123 | P3 | preset.fidelity / Dragon Bloom | Dragon Bloom is paler than its reference. Parked on Matt's call. | — |
| A11Y-001 | P3 | app.accessibility | The three local-source tiles report their parent's accessibility identifier. | After the beta. |
| DEAD-001 | P3 | app.viewmodel / dead-code | `ConnectorPickerViewModel.localFolderEnabled` is dead, and its comment claims a gate the build doesn't have. | With connector-capability work. |
| DIST-LIM | P3 | build / distribution | The notarized build has never run on macOS 15, the stated minimum. Intel is unsupported (arm64 only). | One launch-and-stream on macOS 15 (also closes BUG-167). |
| SCAN-LIM | P3 | session / playlist scan | The scan is untested on non-English Spotify, the compact list, 100+ songs and small windows. The web player can't be scanned. | Two real captures (non-English, compact), if cheap. |
| AUDIT-2026-09-29 | P1–P3 | audit backlog | Beta-readiness findings not yet filed individually. | Phase BR (BR.11–BR.20); file each at pickup. |
| AUDIT-2026-06-09 | P3 | audit backlog | The June audit's remaining P3 backlog. | After the beta. |

### Fixed — waiting on a live check

Each row is cleared by one of the three listening sessions in the beta-readiness audit's
§Manual verification debt (run on the notarized Release DMG, launched from Finder). When the check
passes, the entry moves to §Resolved (recent).

| ID | Sev | Domain | What was fixed | Live check |
|---|---|---|---|---|
| BUG-177 | P1 | ml.stem / memory | Local-file preparation grew memory with song length — 23 GB for a 9-minute song, 34 GB in a session, until the Mac ran out of memory and the app hung. Each separation now frees its GPU objects: 1.4 GB (BR.MEM). | Session 1 again from the start, on build 10. |
| BUG-178 | P2 | session.lf / transport | A local-file listener who skips ahead of preparation lands on an unprepared song: the track bar reads zero and seek does nothing (Next still works). Matt chose **A** (2026-10-01): seek always works from the file's own length, and the walk prepares the song being played next. **Fixed (BUG178.1, `a042e84d`).** | Matt re-runs a skip-ahead past the prepared songs and seeks on each. |
| BUG-152 | P2 | session / preview | 8 % of streaming tracks were analysed as a different song. Every track now goes through the verified lookup: ScanBench 11 → 0 wrong, 125 → 129 right (BR.19). | Session 2: on an Apple Music playlist, the preparation readout names the listed songs. |
| BUG-056 | P3 | audio.localfile | Changing the output device restarted the local song from the top. It now resumes at the playhead and keeps a pause (BR.13). | Session 1: swap AirPods and speakers mid-song, then while paused. |
| BUG-151 | P2 | audio.localfile | The local queue cut the last second off every song. | Session 1: listen to four or five song endings. |
| BUG-163 | P1 | app / accessibility | Reduce Motion and Dim Flashing Lights weren't honoured at launch. | Session 1: launch with each one on. |
| BUG-106 | P2 | ml.stem | At 4K, stems ran a period late. The timing was measured live ✅; the felt half remains. | Session 2: stem-driven scenes, fullscreen at 4K. |
| BUG-162 | P1 | app / session | The display slept and the Mac locked mid-session. | Session 2: on battery, past the display-off interval; run `pmset -g assertions`. |
| BUG-168 | P1 | renderer / performance | Retina and 5K displays rendered 2.5–7× the budgeted pixels. Tier-1 Macs are now capped. | BR.6 measurement: the M4 MacBook Pro (battery, Low Power Mode) and the 4K display. |
| BUG-055 | P2 | app / permission | After an update, streaming said "ready" but the tap was silent (stale Screen Recording grant). | Session 3: install the DMG, stream, install an update build, stream again. |
| BUG-166 | P1 | app / diagnostics | Nothing a tester experienced could reach Matt. | Session 3: force-quit, reopen, make a report. |
| BUG-172 | P1 | session | Declining "control Spotify / Music" froze the session on one scene. | Session 3: click Don't Allow on the Spotify and Music prompts. |
| BUG-167 | P1 | build / renderer | A shader failure crashed launch, and CI never compiled a shader. CI now does. | One launch on macOS 15 (with DIST-LIM). |

---

## Open

### BUG-178 — skipping ahead of preparation leaves a local song with no length and no seek (2026-10-01)

**Severity:** P2 (transport looks broken on the songs a listener chose to jump to; music and Next still
work) · **Domain:** `session.lf` / transport (`advanceLocalFileQueue`, the LF.1 no-cache fallthrough,
`SessionPreparer` walk order) · **Failure class:** `pipeline-wiring` · **Status:** Fixed (BUG178.1, `a042e84d`) — pending Matt's live
skip-ahead · **Found by:** Matt, PREP.3 task 7 live run, 2026-10-01 (*"from Push Downstairs onwards I cannot seek
(time is zeroed out), but I can advance to the next song"*)

**Actual.** Session `2026-10-01T13-48-05Z` (PREP.3 Developer-ID diagnostic build, `PREP3_task7_B_tracks.m3u`,
41 tracks). After Start now, the walk is paced at 2× realtime (PREP.2). Matt moved through tracks 1–8 sampling
endings and reached track 9 at 14:02:27 while the walk was still on track 8:
`StemCache.loadForPlayback track='09 Push Downstairs.m4a' … duration=0.00 … engineCacheHit=false`. Every later
song he reached (10, 11, …) loaded the same way. Push Downstairs finished preparing at 14:04:27; tracks after it
were still unprepared when he reached them.
**Expected.** Seek works on any playing song; preparation never decides whether transport works.
**Cause (from the log, not yet confirmed in code).** An unprepared song plays through the LF.1 no-cache path,
which carries no decoded duration, so the track bar has length 0. The walk keeps playlist order regardless of
where the listener is.
**Decision (Matt, 2026-10-01): option A.** (1) The track bar shows the song's length from the file itself, so
seek works at once, prepared or not. (2) When the listener lands on an unprepared song, the walk prepares THAT
song next (then carries on from there) instead of continuing in playlist order. Until it is prepared the visuals
stay live-reactive, as now. Rejected: B (seek only; walk stays in order — long live-reactive stretches after a
far jump) and C (leave it).
**Not PREP.3.** PREP.3 made the walk faster; pacing (PREP.2) still caps it at 2× realtime once music plays, and
any listener who skips faster than that outruns it.
**Fix (BUG178.1, `a042e84d`, 2026-10-01).** Cause confirmed in code: `localFileTrackProgress` read the length only
from `lastResolvedTrackIdentity`, a placeholder with duration 0 until the walk prepares the song.
(1) `LocalFilePlaybackProvider.fileDurationSeconds` gives the playing file's own length, and the track bar reads it
first. (2) `advanceLocalFileQueue` calls `SessionManager.prioritizeLocalPreparation(at:)`; the walk
(`SessionPreparer.nextLocalWalkIndex`) takes an unstarted priority next, carries on after it, then wraps back. A
pending priority ends the PREP.2 pacing idle (checked every 250 ms). The walk now runs out of playlist order, so
the final plan comes from the slotted `orderedLocalTracks`, not the walk-order outcomes (BUG-068).
**Tests:** `LocalFileEarlyStartTests` — walk-order policy; priority reorders the walk and keeps the plan in queue
order; a priority cuts a 12.5 s pacing idle short. `LocalFileSeekTests` — the provider reports the file's length.
**Negative controls:** `prioritizeLocalFile` as a no-op fails the reorder and pacing tests; pacing without the
interrupt fails the pacing test (2.5 s vs the 1.5 s bound).
**Verification (written before the fix):** a test that a song with no prepared entry exposes its file duration
to the track bar; a test that landing on unprepared song k makes k the next prepared track; Matt re-runs a
skip-ahead past the prepared prefix and can seek on every song.

### BUG-175 — Kagura sways through a song's opening instead of dancing when the intro's beat grid is uneven (2026-09-30)

**Severity:** P2 (a certified scene misses its defining behaviour for the opening quarter-minute, which is where a
listener forms their first read of it) · **Domain:** `preset.fidelity` (Kagura, `KaguraChoreographer` /
`KaguraSafetyNet`) with a `dsp.beat` cause (the cached grid in a quiet intro) · **Failure class:** `algorithm`
· **Status:** Open, not fixed · **Found by:** Matt, 2026-09-30, reviewing the PROMO.1 cut (*"kagura should be doing
the twist instead of warm-up exercises - it does not appear to be synced to the music"*)

**Expected:** from the song's first bar, Kagura dances a beat-locked dance chosen by the song's energy, as it does
once a song is under way.

**Actual:** on *Sherman's March to the Sea* (The Goddamn Shame, `track.mp3`, local file), Kagura makes **no dance
pick before 16.47 s**. `session.log` has `KAGURA_SONG … sections=[0:00 level=10 [egyptian, cabbage, twist] …]` at
load, then the first `KAGURA_PICK` at `beat=35 … playback=16.47s`. The first twist is at 24.31 s. Until then the
dancer plays the rest sway, which is unwarped and so not on the beat. An earlier Kagura run of the same song
(`15-43-59Z`) showed the same late start; the grid is cached, so a reshoot reproduces it.

**Evidence (root cause, from artifacts; not yet confirmed by a code-level repro):**
- Session `2026-09-30T15-45-51Z` (REC.2 take 1, Release build, `UZUME_PIN_SCENE=Kagura`). ⚠ The folder is **gone**:
  the app's `lastN10` session retention pruned it within the hour, as later app and test launches arrived. The
  numbers here were read from it before that. Its frame map survives as
  `~/Documents/uzume_promo/linkedin-2026-10/take_1_kagura_map.csv` (`is_downbeat`, `beat_in_bar` per frame, 0.5–34 s).
  To re-derive: `UZUME_PIN_SCENE=Kagura` + `UZUME_LOCAL_FILE_PLAYBACK`, and copy the session folder out at once.
  Beat instants rebuilt from `features.csv` `beat_in_bar` transitions, first 20: 1.39, 1.88, **2.12, 2.38, 2.59**,
  2.84, 3.33, 3.79, 4.28, 4.52, **5.25**, 5.73 … The grid puts half-beats into the quiet intro (intervals 0.245,
  0.256, 0.213, 0.245 s against a 0.49 s beat) and misses one near 5 s (a 0.725 s gap).
- `KaguraSafetyNet` (`KaguraSelection.swift`) sways while the coefficient of variation of the last 16 beat intervals
  is above `enterCV` 0.08, and rejoins only after 8 consecutive beats under `exitCV` 0.06. On this grid the CV is
  0.34–0.42 through 2–8 s, 0.18 at 10.6–12 s, and first under 0.06 at 12.99 s (0.041). Eight steady beats later,
  plus the next bar line, is beat 35 at 16.47 s: exactly the first pick in the log.
- The engine's steady-state downbeats on this song also run ≈ 90–140 ms ahead of the offline bars and the audible
  kick (PROMO.1 onset check: kick at 8.700 / 26.290 / 30.230 s against engine 8.62 / 26.15 / 30.07). That is the
  BUG-065 / BUG-135 family and not this entry's cause, but it matters for "synced" once Kagura does dance.

**Why it matters beyond this song:** any track whose opening defeats the beat grid (a quiet or rubato intro, a
count-in, sparse percussion) will open on the sway. How many songs that is has **not** been measured.

**Workaround in use:** the PROMO.1 video retimes Kagura's twist 12 bars earlier (`tools/promo/edit.json`,
`source_offset_s` 23.27). That is an edit, not a fix.

**Fix directions (a look and behaviour decision for Matt; none chosen):**
1. The grid: stop the prepared grid putting half-beats and gaps into quiet intros (`dsp.beat`; load the
   `beat-sync-session` skill, BeatBench before/after).
2. The safety net: judge regularity on the grid's steady tempo rather than a 16-beat window that includes the
   intro's cold start, or allow the calm dance while the CV settles.
3. The rest itself: make the sway beat-locked, so the opening at least moves on the beat.

**Verification criteria (written before any fix):**
- Automated: a Kagura choreographer test fed this song's cached grid (or a synthetic grid with the same intro
  pattern) makes its first dance pick within the first 2 bars of the first steady bar, and the existing
  irregular-grid safety-net tests still sway on a genuinely irregular grid.
- Corpus: count the songs in the local stem cache whose first `KAGURA_PICK` would land after 8 s, before and after.
- Manual (musical feel): Matt watches Kagura from the start of *Sherman's March to the Sea* and one more song with
  a quiet intro, at normal volume, and says it dances in time from the opening.

### BUG-174 — Cytokinesis stops for four seconds before it regrows, and it reads as a freeze (2026-09-30)

**Severity:** P3 (a scene reads as stalled; it recovers by itself) · **Domain:** `preset.fidelity` (Cytokinesis, `MitosisGen2`) · **Failure class:** `algorithm` (a designed hold with no motion in it) · **Status:** Open, not fixed · **Found by:** Matt, 2026-09-04 (*"Hangs for seconds before restart"*, the ENGINEERING_PLAN §Phase PR register); first filed here by the 2026-09-30 ledger reconciliation (audit item K8)

**Expected:** the colony keeps visibly living between one growth cycle and the next.

**Actual:** once the colony reaches its crowd size, `advanceStage` enters `.holding` for `holdSeconds` (default **4 s**, `MitosisGen2Geometry.swift:71`). During the hold, cell phase advances only in `.growing` and every radius already sits at its packing target, so nothing on screen moves. Then it dissolves and regrows.

**Evidence:** the code path above; PR.4 found no frame stall in any recorded session (max frame gap 199 ms). This is the designed hold, not a renderer hang. That reading is **PLAUSIBLE**; Matt hasn't confirmed it's the moment he saw.

**Fix direction (audit K8):** keep the cells breathing through the hold (a slow phase drift or membrane motion), or shorten it. The choice is a look decision for Matt.


### BUG-177 — local-file preparation ran the Mac out of memory on long songs (2026-09-30)

**Severity:** P1 (hangs the app and the Mac) · **Domain:** `ml.stem` / memory · **Failure class:** `resource-management` · **Status:** Fixed 2026-09-30 (BR.MEM) — pending a re-run of listening session 1 · **Found by:** Matt, listening session 1 (build 9)

**Actual.** Session 1 on `session1_local.m3u`: stutter, sputter, then a hang, and macOS reported the Mac out of application memory while the song kept playing. The freeze watchdog's samples (`~/Library/Logs/Uzume/stall-2026-09-30T21-4*.txt`): footprint **24 GB → 34.4 GB** seven to eleven minutes after launch; the busy thread was local-file preparation (`LocalFilePreparationPipeline.analyzeWholeFile` → `SessionPreparer.analyzeStemSeries` → `StemSeparator.separate`); the main thread was idle between stalls (memory pressure, not a deadlock).
**Diagnosis (measured, not the output swap).** `PrepTimingRunner` on one song, no playback: Dance Yrself Clean (9 min) **23.3 GB** peak, Superstition (96 kHz) 5.5 GB; the pre-Phase-BR code 26.3 GB — pre-existing. Polling the footprint during the run: flat until `stem_series_sweep`, then linear at ~0.5 GB/s. The sweep separates the song span by span on one background thread; each `separate` leaves ~32 MB of MPSGraph autoreleased objects that the loop's pool never drains until the song is done.
**Fix.** `StemSeparator.separate` runs inside its own `autoreleasepool`. Dance Yrself Clean **1.41 GB**, and 4 long songs back to back 1.50 GB; the prepared cache is **byte-identical** (6 of 6 files) and preparation ~10 % faster. The per-call stem-FFT probe lines moved from notice to info — 60 000 lines in 15 minutes had flooded the unified log and hidden everything else.
**Gates.** `StemSeparatorMemoryTests` — batches of 20 separations on one background thread: 2 MB growth fixed, 646 MB unfixed (bound 150 MB). The footprint is process-wide, so concurrent suites added 170–327 MB of noise in a filtered parallel run; the gate takes the minimum over up to 3 batches (stops at the first clean one). Negative control with the pool removed: [642, 639, 708] MB — fails; filtered parallel run 5/5 green.
**Open.** Whether BR.13's device-change restart behaved in that session is unknown (its log lines were flooded out); it stays in session 1.
**PREP.3 addition (2026-09-30).** The per-length curve, Release, one Bowie *Low* track per process (`docs/diagnostics/PREP3/scaling-*/scaling.csv`): peak footprint **2.78 → 11.93 GB** (113 s → 339 s) before BR.MEM, **1.18 → 1.42 GB** after it, **1.10 → 1.24 GB** with PREP.3's two additions — `StemModelEngine.predict()` now writes its four outputs into pre-allocated buffers through `resultsDictionary` (no per-call result tensors, no `readBytes` copy; the `StemFFT+GPU` pattern), and the Beat This! and PANNs per-call bodies drain their own pools (whole-track grid tiling and the family sweep are the same long synchronous loops). The residue grows ~0.5 MB per second of audio, about three copies of the track's decoded mono PCM — the track's own data, not a per-call leak (estimate; not attributed allocation by allocation). Four tracks at once (`--concurrency 4`), killed at 23–45 GB in PREP.1, now completes at a **3.1 GB** peak. Stem series and a sweep window's stems are **bit-identical** to goldens captured before either change. ⚠ `StemSeparatorMemoryTests` reads process-wide footprint, so it fails intermittently when other suites run in the same process (170 MB in a filtered parallel run on unmodified main); it passes alone every time. Deflaked in #346 (minimum growth over up to three batches; bound unchanged).

### BUG-152 — the streaming preview lookup lands on another song for 8 % of rows (2026-09-28)

**Severity:** P2 · **Domain:** `session` (preview resolution) · **Failure class:** `algorithm` (first hit trusted without verification) · **Status:** Fixed 2026-09-30 (BR.19) — pending a spot-check in listening session 2 · **Found by:** SCAN.0 (the ground-truth resolution in ScanBench is exactly this path) · **Related:** D-260, `ScreenReadMatchPolicy`

**Expected:** a planned track's preview is the song in the playlist.
**Actual:** `PreviewResolver` asks iTunes Search for one result for "artist title" and takes it. On the four SCAN fixture playlists, 11 of the 136 rows that have a preview resolve to a different song (`docs/diagnostics/SCAN_FEASIBILITY_2026-09-28.md` §Failures, "truth resolves elsewhere"): an underscore or acute accent in a name breaks the search, and when the catalog lacks the song the first hit is whatever else ranks first. Stems, beat grid and energy are then measured on the wrong music.

**Fix (BR.19, 2026-09-30).** `PreviewResolver` sends every track through `ScreenReadMatchPolicy` (a track not read off a screen is its own uncut reading): 25 candidates, title + primary artist + duration must agree, one title-only retry, else no match. A zero duration counts as unknown.
**Before / after (ScanBench, the four SCAN fixture playlists, 144 ground-truth rows):** right song 125 → **129**; a different song **11 → 0**; no preview 8 → 15. The scan side is unchanged (0 wrong); `PlaylistScanFixtureTests` re-pinned to 127/129.

**Likely fix (as filed).** Apply the verified lookup SCAN built for screen-read rows (title, primary artist and duration must agree; else no match) to every track. The prompt that built it forbade changing the streaming path without a before/after on a known playlist; that measurement is the fix increment's first step (ScanBench's ground-truth column already gives the "before").

### BUG-159 — the Settings "record sessions" switch does nothing (2026-09-29)

**Severity:** P3 · **Domain:** app / settings · **Failure class:** `pipeline-wiring` · **Status:** Open

**Expected.** Settings → Diagnostics → record sessions off → the next session writes nothing to `~/Documents/uzume_sessions`.
**Actual.** `VisualizerEngine` builds `SessionRecorder()` with its default `enabled: true`; `SettingsStore.sessionRecorderEnabled` is written by the switch and read by nothing else (`git grep sessionRecorderEnabled`). The switch describes behaviour the app doesn't have (UX_SPEC: controls describe what they do now).
**Found** while tracing BUG-158; not fixed there (the public build hides the switch; developer builds keep it). Fix: pass the setting into the recorder at session start, or remove the switch.

### BUG-162 — the display slept and the Mac locked mid-session (2026-09-29)

**Severity:** P1 (breaks the core use: leaving the visuals running) · **Domain:** app / session · **Failure class:** `pipeline-wiring` (a missing OS integration) · **Status:** Fixed 2026-09-29 (BR.2, `9e4403c2`) — **pending live check** by Matt: `pmset -g assertions` names Uzume mid-session on the M4 MacBook Pro on battery (streaming listening session, audit §Manual verification debt #2)

**Expected.** From Ready through Playing the display stays on and the Mac does not lock, with no keyboard or mouse input. At End, Idle or window close, normal idle sleep resumes.

**Actual.** Audit B1 (lane B, re-verified ✔︎): nothing in `UzumeApp/` or `UzumeEngine/Sources/` called `ProcessInfo.beginActivity`, `IOPMAssertionCreateWithName` or `.idleDisplaySleepDisabled`. Audio playback and Metal rendering do not hold off display sleep, so an untouched session dimmed, blacked out and (with "require password") locked after the idle timeout — a few minutes on a laptop on battery.

**Reproduction.** Start any session, touch nothing, wait past System Settings › Lock Screen's "Turn display off" interval. `pmset -g assertions` shows no Uzume assertion.

**Fix.** `DisplaySleepGuard` (`UzumeApp/Services/DisplaySleepGuard.swift`) behind a `DisplaySleepAsserting` seam: holds `ProcessInfo.beginActivity([.userInitiated, .idleDisplaySleepDisabled])` iff the session state is `.ready`/`.playing` **and** the window is open. Fed from the engine's session-state observer and from the root view's `onAppear`/`onDisappear` (a closed window releases it even though the session outlives the window — F14, BR.14).

**Gate.** `DisplaySleepGuardTests`: the full state × window mapping; one assertion spans ready → playing and ends at `.ended`; release at `.idle`; release on window close and re-acquire on reopen mid-session.

**Smoke (Debug build, Mac mini M2 Pro on AC, macOS 26.5.1, 2026-09-29).** Launched on `so_what.m4a` via `UZUME_LOCAL_FILE_PLAYBACK`: `pmset -g assertions` showed no Uzume line before launch, then `PreventUserIdleDisplaySleep` + `PreventUserIdleSystemSleep` named "Uzume visual session" once the session reached Ready/Playing, and none after exit. This proves the wiring, not the laptop-on-battery behaviour.

**Closes on** Matt's `pmset -g assertions` check mid-session on the M4 MacBook Pro on battery, and the display staying on past the idle timeout.
### BUG-163 — Reduce Motion ignored at launch; "Dim flashing lights" never read (2026-09-29)

**Severity:** P1 (a photosensitivity mitigation that silently doesn't hold) · **Domain:** app / accessibility · **Failure class:** `pipeline-wiring` · **Status:** Fixed 2026-09-29 (BR.1, `cf9cc978`) — **pending live check** (listening session 1: launch with macOS Reduce Motion on, then with Dim Flashing Lights on; the visuals run without feedback trails and at half beat strength from the first frame)

*(Numbering: filed as BUG-162 on `br-1`; renumbered to BUG-163 (and K1 to BUG-164) when BR.2's #316 merged first with its own BUG-162.)*

**Expected.** With macOS Reduce Motion (or Dim Flashing Lights) on at launch, the engine renders reduced from its first frame: mv_warp feedback skipped, beat amplitude × 0.5 (D-054).

**Actual** (audit F1, re-verified ✔︎). `AccessibilityState.init` seeds `reduceMotion` from the system flag, and the only push into the engine was `.onChange(of: accessibilityState.reduceMotion)` — which never fires for the initial value. The chrome read Reduce Motion as on; the renderer ran `frameReduceMotion = false`, `beatAmplitudeScale = 1.0`. `MADimFlashingLightsEnabled()` was read nowhere (F1b).

**Fix.** `AccessibilityState.engineFlags` (current value synchronously on subscribe, then each change) feeds `engine.applyAccessibility` via `.onReceive`. `MADimFlashingLightsEnabled()` ORs into the system flag; `kMADimFlashingLightsChangedNotification` is observed with NSWorkspace's.

**Gates.** `AccessibilityStateTests`: `engineFlags_deliverTheLaunchStateOnSubscription` (Reduce Motion on / Dim Flashing Lights on, each delivered synchronously on subscribe), `dimFlashingLights_actsLikeReduceMotion`, `engineFlags_followPreferenceChanges`; `AccessibilityLaunchWiringTests` (source shape: `.onReceive(accessibilityState.engineFlags)`, no `.onChange` on `reduceMotion`). The existing tests now pin Dim Flashing Lights off so they no longer read the host Mac.

### BUG-166 — nothing a tester experienced could reach Matt (2026-09-29)

**Severity:** P1 (the beta finds defects and cannot diagnose any) · **Domain:** app / diagnostics · **Failure class:** `pipeline-wiring` (missing evidence path) · **Status:** Fixed 2026-09-29 (BR.5, `4b6dd533`…`a2e8ae9c`) — the report flow is live-verified on a Debug build; **pending live check** of the public build's unclean-exit offer (listening session 3, fresh-account DMG).

**Actual** (audit H3/F16, D3, H7). No Help menu, no report item, no crash handler; "Copy debug info" was three lines, reachable only mid-session. Apple forwards no crash reports for Developer ID apps. A force-quit leaves no `.ips`. The public build keeps no `session.log`. The drawable watchdog `await`ed the main actor in its heartbeat branch, and runs only when the session recorder exists (developer builds). `capture_hang.sh`, `window_state.swift` and the closeout's BUG-072 check looked for `UzumeApp`, not `Uzume`.

**Fix.**
- **Help › Report a Problem** (`ProblemReport.swift`): consent alert → zip in `~/Library/Logs/Uzume` (last 2 h of `io.uzume` unified log; `Uzume*` `.ips`/`.hang`/`.diag`; watchdog stall samples; version, build, git SHA, flavor, model, RAM, macOS, GPU, displays) → Finder → a pre-filled `hoaxpoet/uzume` issue. No audio; the app sends nothing.
- **Abnormal-exit marker**: set at launch, cleared on willTerminate; the public build offers the report at the next launch (never under XCTest).
- **`MainThreadWatchdog`**: pings main from its own `Thread`; `MAIN_THREAD STALL` fault at 1 s, one `/usr/bin/sample` at 3 s, `MAIN_THREAD RECOVERED` after. Every build.
- The drawable watchdog's GPU_PRESSURE read is fire-and-forget on main. Scripts look for `Uzume`; `capture_hang.sh` also saves `log show` and `df -h`.
- Build SHA: already embedded by `release.sh` (Info.plist `UzumeGitSHA`, CLEAN.2.5b); the report carries it.

**Gates.** `ProblemReportTests` (builder on fakes: only Uzume's reports + stall samples, no AppleDouble files; live system summary; marker launch/quit; issue URL); `MainThreadWatchdogTests` (main really blocked 1.4 s: STALL and exactly one sample recorded while blocked, RECOVERED after; 3/3 runs).

**Live (Debug, Mac mini M2 Pro, 2026-09-29).** Help › Report a Problem → Create Report: a 10-file zip in ~4 s holding this Mac's real `Uzume-2026-09-25-*.ips` reports; Finder reveal and the issue page opened. `capture_hang.sh` against a running build: sample, ps, window state, power, unified log, df all written.

### BUG-167 — every shader compiles on the tester's Mac at launch, and CI never compiled one (2026-09-29)

**Severity:** P1 (a core-shader failure crashes every launch on that OS/GPU) · **Domain:** build / renderer · **Failure class:** `pipeline-wiring` (an unguarded build path) · **Status:** Mitigated 2026-09-29 (BR.6a). CI now compiles every shader and builds Release. **Open:** the notarized DMG has still never launched on macOS 15 (BR.6b / DIST-LIM); only that closes it.

**Actual** (audit H1 PLAUSIBLE, H8 VERIFIED). `ShaderLibrary` concatenates the renderer's `.metal` files and calls `device.makeLibrary(source:)` at launch. A throw is `fatalError` in `VisualizerEngine` (no dialog, every launch). `PresetLoader` compiles each scene's unit(s); a failure removes the scene silently. CI ran the scheme's Debug build only, and no Metal: `PresetLoaderCompileFailureTest` skips without a device and checks only a count.

**Fix.** Two CI steps (`ci.yml`): **Build Release (arm64, signing disabled)**, and the **shader compile gate**, `ShaderCompileGateTests`. The gate compiles through `ShaderLibrary` and `PresetLoader` (the app's own source assembly) with the runtime Metal compiler on the runner's paravirtual GPU. It fails, never skips, without a device, and names every dropped scene file.

**Gates.** Local negative controls: `int half = 1;` in `Nebula.metal` → `dropped → ["Nebula.metal"]`; in `NoiseGen.metal` → `MTLLibraryErrorDomain`. CI negative control on PR #320: the same break in `Nebula.metal` (`a03d5da8`), then its revert (`8be6121e`) — results recorded in the PR.

### BUG-168 — no render-resolution ceiling outside ray-march (2026-09-29)

**Severity:** P1 (frame rate on tester laptops and large displays; the main-thread render loop also lags the chrome) · **Domain:** renderer / performance · **Failure class:** `resource-management` · **Status:** Mitigated 2026-09-29 (BR.6b, `d04aa80d`), per decision 4. **Pending:** Matt's M4 MacBook Pro (Retina, battery, Low Power Mode on/off) and 4K sessions, which decide whether any cap applies above tier 1; the cold-first-launch time.

**Actual** (audit D4 PLAUSIBLE, K2). `MetalView` left `autoResizeDrawable` on, so every non-ray-march path allocated and shaded at the native backing size. Only ray-march (`marchScale`) and Nimbus had caps.

**Measured (Release, Mac mini M2 Pro, macOS 26.5.1, `PresetFrameBudgetTests.presetFrameCost`, harness ms).** At 3840×2160, 13 of 23 measured scenes are over 16.6 ms. At the 2560×1440 cap, only Volumetric Lithograph is (already excluded, decision 2). The full table is in the audit, §BR.6.

**Fix.** `CappedMTKView` (`MetalView.swift`): on tier-1 GPUs (`detectDeviceTier` — the m3/m4 name match, so the M2 Pro Mac mini is tier 1) `drawableSize` ≤ 2560×1440 pixels, aspect kept, never upscaled; the compositor scales it to the window. `capableCatalog` drops Alfvén on tier 1.

**Gates.** `Tier1RenderBudgetTests`: the sizing math (Air 13", 5K, 4K, ≤ budget untouched); the cap only when set; in a real 3840×2160 offscreen window the drawable is capped **and** the render pipeline's `drawableSizeWillChange` receives the capped size; Alfvén excluded on tier 1 and kept on tier 2.

### BUG-172 — declining "control Spotify / Music" froze the session on one scene (2026-09-29)

*(Numbering: filed as BUG-168 on `br-10`; renumbered to BUG-172 behind BR.6b, BR.7, BR.8 and BR.9.)*

**Severity:** P1 (a common first-run choice breaks the session with no explanation) · **Domain:** session / app · **Failure class:** `pipeline-wiring` · **Status:** Fixed 2026-09-29 (BR.10, `e28da378`) — **pending live check** (listening session 3: fresh account, click Don't Allow on the Spotify and Music prompts)

**Actual** (audit E1 VERIFIED; I3/A6/C6/F12 ✔︎).
- **Streaming.** `StreamingMetadata` logged −1743 at `.debug` and returned nil. No track change ever fired, so the orchestrator returned early on every tick. The whole playlist ran on the starting scene with track 1's pre-fired grid and stems, and the title read "—". Spotify testers first meet the prompt at Ready, and its copy ("to display what's currently playing") made declining look harmless.
- **Apple Music.** `PlaylistConnector` turned −1743 into an empty playlist, so the view looped "Checking every 2 seconds…" forever. The `.permissionDenied` screen was unreachable (a TODO since 2026-04-23).
- **Polling (E12/E14).** Local-file sessions polled Music and Spotify (prompts mid-session; a playing streaming app overrode the local track), and Spotify sessions prompted for Music.

**Fix.**
- Apple Music: −1743 → `PlaylistConnectorError.automationPermissionDenied` → the existing `.permissionDenied` screen.
- Streaming: the poll returns playing / nothing / `automationDenied`, reported once per observation. The engine then:
  - sets `nowPlayingUnavailable`, so a planned session runs **reactive** instead of freezing;
  - drops the track-1 pre-fire;
  - publishes `nowPlayingDeniedApp`, which the playback error bridge shows as a toast naming the app and the Automation setting (new `UserFacingError.nowPlayingPermissionDenied`, UX_SPEC §9.4).
  - Both flags are cleared at every session boundary and on a real track change.
- Polling: local-file modes start no poller; a streaming session asks only its own app, and never a closed one.
- `NSAppleEventsUsageDescription` is reworded to say what declining costs.

**Gates.** `NowPlayingPermissionTests` (denial reported once per observation, again after restart, ordered on poll count; which apps are asked; local-file modes don't poll); `PlaylistConnectorTests` (−1743 case); `AppleMusicConnectionViewModelTests` (→ `.permissionDenied`, no retry loop); `NowPlayingDenialWiringTests` (reactive fallback, toast, clearing on every path; source shape); `UserFacingErrorTests` (30 cases).

### DIST-LIM — what the notarized build has not been shown to run on (2026-09-29)

**Severity:** P3 · **Domain:** build / distribution · **Status:** Open (recorded limits, D-261)

- **macOS 15 Sequoia.** In range (`LSMinimumSystemVersion` 15.0) but never run. The Core Audio tap, the audio-capture permission prompt, ScreenCaptureKit's window filter (the Spotify scan) and MusicKit lookups are the parts most likely to differ; the first tester on 15 is the first test.
- **Intel Macs.** Not supported: the app is arm64-only, and macOS refuses to open it on Intel. The engine's `Float16` math does not exist on x86_64, and Intel Macs can't reach the 60 fps target.
- **Tested so far:** macOS 26.5.1 on Apple Silicon (Mac mini M2 Pro) — Matt's account and a fresh standard account with every Uzume permission reset (CLEAN.2.5b Task 8, build 0.9.0 (5), *"Passes all steps."*).

### SCAN-LIM — what the playlist scan has not been shown to handle (2026-09-28)

**Severity:** P3 · **Domain:** `session` (playlist scan) · **Status:** Open (recorded limits, D-260)

- **Non-English Spotify interface.** The header's "N songs" is matched in English. Elsewhere the count is unread; the "Recommended" shelf (also English) or the user's Done ends the scan, and the panel shows "27 songs" instead of "27 of 38 songs".
- **Compact list view.** Parsed from synthetic observations only; no real compact capture was measured.
- **100+ song playlists.** Not measured; nothing in the reader depends on length, but no long capture exists.
- **The Spotify web player.** Only the desktop app's window (`com.spotify.client`) is read.
- **Very small windows.** Heavier truncation. The pass bar was measured with both side panels open (heavy truncation: 26 of 144 titles cut off, 25 identified).
- **Esc typed into Spotify** goes to Spotify; the panel's Esc works once the panel has focus (the scan does not use the Accessibility permission).
- **Spotify's music-video badge** can fuse onto an artist name in the review list ("DSZA"); resolution tolerates it, the display does not.

### BUG-151 — a local-file queue cut the last second of every song (2026-09-28)

**Severity:** P2 · **Domain:** `audio.localfile` (transport) · **Failure class:** `api-semantics` (a completion callback that fires on read, not on playback) · **Status:** Fixed (LFSEEK.1); manual check outstanding · **Found by:** LFSEEK.1's seek test; Matt: *"don't flag, fix"* · **Related:** LF.5 (D-132, the EOF-driven queue advance), BUG-059 (the completion-handler hop)

**Expected:** in a multi-file local session each song plays to its end before the next begins.
**Actual:** the next song started about a second early. `LocalFilePlaybackProvider` armed its end-of-file callback with `scheduleFile`'s default completion type, `.dataConsumed`, which fires once the player has *read* the last audio into its buffers, not once it has *played* it. Since LF.5, `onFileEnded` drives `advanceLocalFileQueue`, which stops the engine, so each advance cut the buffered tail.

**Measurement.** On the real engine with the `love_rehab.m4a` fixture, a seek to 3 s before the end reported end-of-file 2.0 s later: a 1.0 s lead.

**Fix.** When `onFileEnded` is set (a queue advances), schedule with `.dataPlayedBack`. The single-file loop (`onFileEnded == nil`) keeps `.dataConsumed`, because re-arming while the tail still plays is what makes that loop seamless.

**Verification.**
1. ✅ Automated: `LocalFileSeekTests.seekMovesThePlayhead` requires the end ≥ 2.8 s into a 3 s remainder; the old code measured 2.0 s. `SessionLifecycleChurnTests` (the BUG-021/059/078 completion-race net) passes unchanged.
2. Manual: in a multi-song local session, the last second of a song is heard before the next starts.

### BUG-149 — the key estimate reads F# minor far too often (2026-09-26)

> **Reconciled 2026-09-30 (BR.KI ledger pass).** BUG-054 (key detection resolution-limited) closed as a duplicate of this entry.

**Severity:** P3 (display-only today) · **Domain:** `dsp.mir` (`ChromaExtractor` Krumhansl–Schmuckler) · **Failure class:** not yet assigned · **Status:** Open, not diagnosed · **Related:** CENSUS.3 §4 (`docs/diagnostics/CENSUS_PILOT_REPORT.md`), BUG-146, TONAL phase (D-178)

**Evidence.** The app's cache on the beta playlist (2026-09-26, schema v16, MIR at 44.1 kHz) stores F# minor on 7/10 songs; Teardrop reads A minor, Moonlight I C major and Warszawa F major. The CENSUS.3 pilot found the same attractor at scale: F# minor on **347 of 993** tracks (35 %), next C major at 176, with a median K-S confidence of 0.53. The source comment already calls the estimator "unreliable". No per-song ground truth is in the repo yet (Essentia is not installed; `tools/essentia_ground_truth.py` exists), so accuracy per song is unmeasured. The attractor is established statistically. **Consumers:** the preparation row, `DebugOverlayView`, and `VisualizerEngine+Capture`; the scorer and planner do not read key. **Matt's call (2026-09-26):** keep it visible and make it accurate. Hiding it was declined.

### BUG-135 — the grid's bar position cannot be confirmed to be the true musical downbeat (2026-09-14)

**Severity:** P3 · **Domain:** `dsp.beat` · **Failure class:** unverifiable · **Related:** Cold-Start Phase Contract

**Observed:** Matt, M7 on Membrane (PR.27), 2026-09-14: *"I think they land on the actual downbeat,
but if not they land on the beat."*

**Attempted verification** on `2026-09-14T18-14-07Z` (verdict **clean**). Grouping each grid beat by
its bar position and measuring what arrives there:

| signal | The Suburbs | Ready to Start | Rococo |
|---|---|---|---|
| `bassDev` | pos 2 (1.33× lead) | pos 0 (1.00× — none) | pos 2 (1.23×) |
| `harmonic_flux` | pos 1 | pos 2 | pos 1 |
| `spectral_surge` | pos 0 | pos 3 | pos 3 |
| `spectralFlux` | pos 3 | pos 3 | pos 3 |

`bassDev` is the only signal with real separation, and it cannot distinguish beat 1 from beat 3 (a
kick commonly plays both). Every independent signal disagrees with it and with each other, across a
span of ~2 % — no bar-position discrimination at all. **The recorded feature set cannot answer this
question.**

**Deliberately not chased.** Automated cold-start downbeat-phase derivation was empirically falsified
across six iterations and retired on Matt's Choice A (2026-05-25); the `preset-session` skill marks it
*do not iterate*. Inventing a seventh heuristic here is the thing that rule exists to prevent.

**Consequence is bounded, which is why it reads well.** Membrane's metric accent is
1.00 / 0.22 / 0.52 / 0.22, so a half-bar error swaps the strong and secondary accents: a hard strike
every four beats with a medium one between, displaced but structurally intact. Matt's call
2026-09-14, presented with this measurement: **leave it** — the scene reads correctly and the
alignment is not worth reopening retired work for. Recorded so a later session does not "fix" a
displacement it cannot measure.
### OBS-DS6-1 — Ferrofluid Ocean blacked out mid-track during the DS.6 M7 (2026-09-03, recorded not chased)

**Severity:** P3 · **Domain:** `preset.fidelity` / Ferrofluid Ocean · **Failure class:** unknown (unverified)

**Observed:** Matt, running the DS.6 M7 on a Spotify session: *"the Ferrofluid Ocean scene blacked out at one point, unrelated to this work."* No timestamp beyond "at one point".

**Artifacts:** `~/Documents/uzume_sessions/2026-09-03T20-04-45Z/` (`session.log`, `features.csv`, `stems.csv`, `raw_tap.wav`, `chain_health.json`). Ferrofluid Ocean was the first real scene of the session (`preset → Ferrofluid Ocean` at 20:06:05Z, on "Billie Jean"). The `DRAWABLE_LIFECYCLE` heartbeats through its run report every frame presented, `failures=0`, `unpresented=0` — so the screen was black because the scene rendered black, not because frames stopped. The tap saw a near-silent window right after the scene began (RMS 0.145 at +5 s, then 0.0008–0.0012 for +6 s to +8 s, back to 0.032 at +9 s; `chain_health.json` verdict `degraded`, reason `tap_reinstalls(2)`).

**What this is and is not:** an observation. Ferrofluid Ocean is driven from continuous energy, so a black frame during three seconds of near-silence could be the scene's honest response to no energy, a wrong-phase cold start, or a genuine render defect; nothing here distinguishes them. Not chased in DS.6 (chrome only). Next step, if it recurs: the moment it happened, so `features.csv` can be read at that row against `raw_tap.wav`, and a `PresetSessionReplay` of the capture through Ferrofluid Ocean.

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

> **Reconciled 2026-09-30 (BR.KI ledger pass).** The 4K timing criterion is ✅ (measured live); only the felt half remains (listening session 2).

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
- [x] A live 4K session logs `ml_forced` **flat** (normal dispatch) after the fix, where before it climbed ~one per 2 s. **CONFIRMED — session `2026-08-26T22-04-58Z`:** 3840×2160, Witchlight, 82 s in one scene at one resolution, `frame_cpu_ms` p50 **25.1–25.8 ms** throughout — i.e. permanently over the old 16 ms constant, the exact condition that used to shut the gate. Every one of the 10 `GPU_PRESSURE` lines reads `ml_forced=0 ml_last=dispatchNow`. The gate was genuinely exercised: `STEM_SEPARATION` fired every 2.0 s at 270–474 ms inference across the whole session, and all four stem energies are non-zero on all 6,545 frames.
- [x] A 1080p session is unchanged — the tier floor decides there, proven by `budget_at1080p_isUnchangedByTheFloor` (median 8 ms → budget stays 14/16, and an 18 ms frame still defers).
- [x] Unit: a 4K-shaped history (median 25 ms, worst 27) returns `.dispatchNow` under the derived budget, and the same window against the old 16 ms constant still returns `.defer` — the case proves it bites. A genuinely janky 4K window (worst 60 ms) defers. `budget_atFourK_steadySessionDispatchesInsteadOfDeferring`, `budget_atFourK_genuineJankStillDefers`.
- [x] The median is robust to one hitch (a mean would raise the bar the next dispatch is judged against): 29 × 25 ms + one 200 ms hitch → median 25.0, max 200. `recentMedianFrameMs_isRobustToASingleHitch`.
- [ ] Manual (musical feel): stem-driven scenes at 4K read *with* the music rather than behind it, and Matt's eye on whether any new stutter is acceptable. ⏳

**Related:** BUG-100 (found during it, NOT established as its cause — see above), BUG-086 (stem
latency, compounds), D-059 (the scheduler's rationale), BUG-090 (the reasoning trap this entry
declines).
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
playback position, so stems now span the track while the beat grid still does not. Any scene
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

**Probably not a new defect, and probably not Witchlight's.** The ~3.6 min timing matches the **unreproduced "~3.7 min crash"** logged against Volumetric Lithograph certification, and BUG-060 is a one-off hang filed with "no stack captured". All three are plausibly one bug. Nothing in the stack is scene-specific below `drawParticleMode`, which every `particles` scene shares.

**Already ruled out.**
- `drawParticleMode` leaking directly — it acquires and unconditionally `present`s on every path.
- The inflight semaphore — the hang is *past* `context.inflightSemaphore.wait()`, so a slot was available.
- A GPU hang or a stuck completion handler — no thread is waiting on either.

**Failure class.** `resource-management` (a finite pool acquired without a guaranteed release path).

**Suspected direction, NOT yet confirmed.** Something acquires a drawable outside the committed command buffer's lifetime, or retains `drawable.texture` past presentation. The session-recording hook in `draw(in:)` reads `view.currentDrawable` a second time and hands `drawable.texture` to a consumer, which is the shape of thing that would do it — but that is a hypothesis, and three hypotheses have already died on this scene today. It gets confirmed against an artifact before any fix.

**Investigation so far (2026-08-04) — leading hypothesis, still UNPROVEN.**

Ruled out by inspection after the stack: the capture hook does not retain the drawable (it blits into a separate texture inside the same command buffer, and with video recording off — as this session's log confirms — `ensureCaptureTexture` returns nil so it does nothing at all); the `willRenderActiveFrame` scene-swap skip still commits its command buffer, so skipped frames do not leak; and **display sleep is excluded** — `pmset -g log` shows `coreaudiod` held `PreventUserIdleDisplaySleep` for the full 33 minutes spanning the freeze.

**What that leaves, and it is a real gap regardless of this hang:** the app has **no occlusion handling of any kind**. `MetalView.swift` sets `view.isPaused = false` and nothing anywhere observes `NSApplication.occlusionState`, `windowDidMiniaturize`, or window visibility. Rendering therefore continues into a layer that may not be composited — and a `CAMetalLayer` whose window is minimised or fully occluded stops recycling drawables, which makes `nextDrawable` block exactly as observed. It fits every measured fact: hard block, 0 % CPU, nothing else holding, healthy frames right up to the stop.

**REFUTED 2026-08-04 — do not spend time here again.** Matt ran the repro and left the instance alive; sampled at **7 min 11 s elapsed**, twice past the ~3.6 min mark, with every `UzumeApp` window reporting `onScreen=false` via `CGWindowList`. The app was **not hung**: 0 of 4145 main-thread samples in `nextDrawable`, 49 % CPU, session still live (stem separation running). The control is the decisive part — **the draw loop was entirely absent** (0 samples in `RenderPipeline.draw`, `MTKView draw`, `drawParticleMode`, `currentDrawable`). When the window is not composited macOS stops the draws rather than letting them block, so rendering-into-an-uncomposited-layer is not a state this app can reach, and occlusion cannot be the cause. The missing occlusion handling is still a (minor) gap, but it is **not** this bug.

**Pre-HANG.1 conclusion (2026-08-04).** The original capture stands unexplained: main thread hard-blocked in `nextDrawable` at 0 % CPU with every other thread idle, ~3.6 min in, after frames that were healthy to the last one. Drawables are being retained by something that is not the render path, not the capture hook, not the scene-swap skip, not the inflight semaphore, and not window state. At that point there was no current hypothesis; the next step was instrumentation that counts drawables acquired against command buffers completed, rather than another guess.

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
passed. HANG.2's ≥10-minute particle-scene soak and full-track manual run are complete; both
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
scene-path-specific** — it is whichever path happens to ask for the drawable.

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
scene-path specificity, and any process-wide stall. **What remains:** why CoreAnimation
withholds a drawable from a client holding none.

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

**Actual:** the cached grid has the right BPM, but `LiveBeatDriftTracker` *bounds* the live drift without *tightening* it — drift grows ~11 ms (track start) → 50–70 ms (mid/late-track), with 28 % of frames exceeding ~60 ms. Evidence: session `2026-06-29T12-43-51Z` (Cherub Rock, 171.3 BPM 4/4 — drift-by-10s-window 11/37/49/54/69/66/55/48 ms; `lock_state=2` only 67 %-within-60 ms). NOT a functional break (phase is approximately right); it caps how *tight* beat-locked scenes can feel (the live example: GLAZE.7 reads connected but loosens as the track plays).

**Suggested improvement (Matt 2026-06-29):** live re-lock / cached-BPM-error correction so drift holds < ~30 ms across the track. The cold-start *automated phase* premise was retired (CLAUDE.md §Cold-Start), but this is mid-track drift *convergence* — a different surface (the tracker should tighten, not just bound). Logged for a dedicated beat-sync session.

**Status 2026-07-30 — OPEN. Root cause proven (TRK.1); both attempted fixes stopped at their own gates.**

- **TRK.1 (`07dd3bd9`) proved the mechanism.** The drift is a *ramp*, not noise: linear fit **−1.493 ms/s at R² = 0.844** on session `2026-07-30T15-39-21Z` (Hummer, 80.45 BPM), `grid_bpm` rock-constant ⇒ a **0.149 %** cached-grid period error (0.12 BPM). The legacy tracker is a first-order EMA on phase error — proportional-only, which has zero steady-state error against a step but *constant* error against a ramp. It can bound drift; it can never null it. That is exactly "bounds without tightening". A type-2 (PI) controller was implemented behind `UZUME_BEAT_PLL` and **failed real-fixture validation** — `LiveDriftValidationTests` (loveRehab) maxAbsDrift **101.5 ms** (limit 50), beat alignment **0.05** (limit 0.80). Default-off. **Strike 1 on the gain-tuning premise; do not retune gains against sub-bass evidence.**
- **TRK.2 stopped at its evidence gate — the drums-stem premise is FALSIFIED.** The proposed fix was to change the *evidence* (drums-stem onsets instead of sub-bass) rather than the gains. Measured on four captures with the production `StemSeparator` + a separate `BeatDetector` instance (D-075), bias-corrected: drums-stem sub_bass onsets landing within ±50 ms of a grid beat vs the full mix — love_rehab **16.9 % vs 42.2 %**, Hummer **11.0 % vs 14.4 %**, `bleed.wav` **22.4 % vs 22.3 %**, billie_jean **25.5 % vs 24.5 %**. Worse on two, a wash on two, *including Bleed* — the category-4 track the whole argument rested on. Best drums band anywhere: +2.5 pp, inside noise. **Larger finding:** across every capture, band and stem, only **~15–25 % of detected onsets land within ±50 ms of a beat** — FA #68 generalises, the spectral onset-detector family is weak beat evidence wherever it runs. **Second, independent blocker:** the live stem path (`VisualizerEngine+Audio.swift` `runPerFrameStemAnalysis`) deliberately carries **5–10 s of latency** with a sawtooth re-anchor every ~5 s, so drums onsets cannot be timestamped correctly by the tracker without a separate design that threads their true tap time through. No production code was changed. Evidence + reproduction: [`docs/diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md`](../diagnostics/TRK2_DRUMS_STEM_EVIDENCE_2026-07-30.md); instrument: `DrumsOnsetEvidenceTests` (env-gated).
- **Corroborated at scale by the GT.3 live baseline (2026-07-30).** `docs/diagnostics/BEATBENCH_LIVE_BASELINE_2026-07-30.md` measures the drift curve across 15 streamed tracks, and the growth this bug describes is the norm, not one capture: billie_jean 26 → 118 ms, stayin_alive 60 → 285 ms, money 20 → 241 ms, superstition 26 → 94 ms, clair_de_lune 39 → 135 ms by 30 s window. Only giorgio_by_moroder and pyramid_song hold flat. The program's live suite-1 target is **p90 < 30 ms**; the measured p90 is 102 ms on billie_jean and 269 ms on stayin_alive. This is systemic to the frozen single-BPM grid premise.
- **PARKED — Matt 2026-07-30 (D-206): "park the tracker, go DBN next session."** Two evidence sources and one controller topology have now been measured against the same frozen single-BPM grid, and the evidence layer has no headroom left. BUG-065 stays **open and bounded** (the visual falls up to ~119 ms behind late in a track; not a functional break); `UZUME_BEAT_PLL` stays default-off. Phase TRK is parked and TRK.3 has no content. The defect is now expected to be addressed — if at all — as a side effect of phase **DBN** replacing the frozen single-BPM grid premise, not by further tracker work. **Do not reopen TRK without a changed premise about the *grid*, not the tracker.**


---

### AUDIT-2026-09-29 — Beta-readiness review backlog (findings not individually filed)

**Status:** Open — index entry. The 2026-09-29 beta-readiness review (AUDIT.2, eleven read-only lanes) records 126 code findings (lane IDs A1–K9) and 22 abandoned-work items in [`docs/diagnostics/BETA_READINESS_AUDIT_2026-09-29.md`](../diagnostics/BETA_READINESS_AUDIT_2026-09-29.md), with full evidence in [`docs/diagnostics/BETA_READINESS_2026-09-29/`](../diagnostics/BETA_READINESS_2026-09-29/). They are grouped into proposed increments BR.0–BR.20 (`ENGINEERING_PLAN.md` §Phase BR). They were deliberately **not** given BUG-numbers at review time: `main` (#311) and the unmerged `clean-2-5b` already both claim BUG-157. File each finding with the next free number from the tree when an increment picks it up. The review also lists this ledger's own drift (≈29 closed rows still in the Open Index, six index/body contradictions) for a reconciliation pass before the beta.

- **B1 → BUG-162** (BR.2, 2026-09-29): fixed, pending live check.
- **E2 → BUG-173** (BR.11, 2026-09-29). The rest of BR.11, fixed in the same increment:
  - **E7** — a song that isn't in the plan (autoplay after the playlist, an ad, a podcast) runs reactive instead of holding the last planned scene (`f3303199`).
  - **E8 / B2** — the local-file track clock is the playhead wrapped at the file length (loops wrap it, pauses hold it: no more ~1.5 s lead per pause), and the planned-scene lookup wraps at the track's planned length (a loop or repeat-one walks its scenes again) (`f3303199`, `8a844712`). Live loop check queued (session 1); the recorder's `features.csv` stayed empty on the Debug runs, so it wasn't shown live here.
  - **E6** — the session clear also runs at `.idle`, so "Start listening now" after a session starts clean, including the reactive switch clock (`461224a8`).
  - **E3** — local-file playback finds its plan entry by identity, so one failed file no longer shifts every later file (`461224a8`).
  - **G7** — the metadata pre-fetch and the live Beat This! grid are dropped if the song changed while they ran (`461224a8`).
- **E1 / I3 / A6 / C6 / F12 → BUG-172** (BR.10, 2026-09-29); **E12 / E14** fixed in the same increment (only the session's own app is polled; none for local files).
- **C3 / G3 → BUG-171** (BR.9, 2026-09-29): fixed.
- **C1 → BUG-170** (BR.8, 2026-09-29): fixed.
- **BR.7 (2026-09-29).** C2 → **BUG-169**. The rest, fixed in the same increment:
  - **F10 / C11** — a failed connection or an all-failed playlist holds `.preparing` (the §9.3 recovery screen) instead of a "Ready" with nothing prepared (`b0156ae1`).
  - **F13** — "Start reactive mode" on the recovery screen is wired (streaming; `SessionManager.startReactiveMode()`), and local-file sessions can't show "You're offline" (`b0156ae1`). The >90 s / >120 s banners still carry no button (not in BR.7's done-when).
  - **F11** — Cancel during Connecting sticks: a connect finishing after it is ignored (`0f648f4f`).
  - **C10** — missing ML weights say so once at launch, plus an `ANALYSIS_UNAVAILABLE` log line (`331202c2`); live-verified by hiding the app's Weights folder. A build-phase weights check is still open (release.sh checks; other builds don't).
- **BR.4 (2026-09-29), the public build's tester surface** (`BuildFlavor.showsDeveloperDiagnostics`; verified by tests; no public-flavor build was run):
  - **I2 / F3 / A9** — the no-audio card has no Terminal step, and a live-but-silent tap never raises it (a frozen tap still does). Fixed (`b4a33412`).
  - **F8** — no developer keys or bug IDs (the `.developer` shortcuts are dropped); `+` fires on US/UK layouts (Shift ignored for symbol keys only); `.` has one binding. Fixed (`cfb4b5c4`). The developer build still binds `.` twice (latency +5 unreachable); that's a developer-only leftover.
  - **F18** — the three raw keys in Settings got strings; `LocalizationKeyCoverageTests` checks every referenced key resolves. Fixed (`384c7963`).
  - **I10** — the Ended screen shows the real playing time and "1 track" / "N tracks". Fixed (`b87e191e`).
  - **H11 / A12** — no `~/uzume_diag.log` in the public build. Fixed (`a450ccad`).
  - **A13 / G9** — the user-preset (hot-reload) folder is off in the public build: done at BR.1 (`1e47cca9`).
  - **I2 tester notes** — [`docs/TESTER_RELEASE_NOTES.md`](../TESTER_RELEASE_NOTES.md).
- **D4 / K2 → BUG-168** (BR.6b, 2026-09-29): tier-1 cap + Alfvén exclusion; M4/4K measurement pending (Matt).
- **H1 → BUG-167** (BR.6a, 2026-09-29): CI compiles every shader + builds Release; macOS 15 launch open (BR.6b). **H8** fixed in the same increment.
- **H3/F16 → BUG-166** (BR.5, 2026-09-29); **D3, H7** fixed in the same increment (independent watchdog; scripts look for `Uzume`).
- **G1 → BUG-165** (BR.3, 2026-09-29): fixed, TSan-clean.
- **BR.20 (2026-09-30), flash check v2 (I8; P2, tracked here):** `FlashAnalyzer.analyzeRegional` (13 regions: a 3×3 grid + a half-shifted 2×2, each a ninth of the frame — WCAG's small-safe area) and `analyzeRed` (R/(R+G+B) ≥ 0.8, (R−G−B)×320 swing > 20), each negative-controlled (a flashing ninth v1 misses; a dim red pulse the luminance checks miss). Both flash harnesses assert them for every measured scene. Roster run: two scenes over → **BUG-176** (fixed); everything else ≤ 2.5 regional, ≤ 3.0 red (Fata Morgana, at the limit). Fixed.
- **BR.18 (2026-09-30), streaming fidelity for the newest scenes (P2, tracked here):**
  - **K6c** — every live stem deviation route now warms up over a track's first 10 s (the BUG-041 quadratic gate, on the render snapshot, live separation only; Ferrofluid's aurora no longer gates twice). Fixed (tests on the real BUG-041 session series; red arm: ungated, the same data breaks the bound). ⏳ Matt's streaming review of the top ten scenes (listening session 2).
  - **K6a** — **kept as is for the beta (Matt, 2026-09-30, option A).** On streaming, Fireflies and Kagura see the preview's one typical energy level for the whole song (the meadow doesn't thin in quiet stretches; Kagura's dance is chosen from one level). A live energy measure was declined for the beta: no grounded way to keep it independent of the app's volume. Stated in the tester notes.
- **BR.19 (2026-09-30), the right song, reliably (P2, tracked here):**
  - **BUG-152** — fixed; see its entry (ScanBench 11 → 0 wrong songs).
  - **C7** — a 429, 5xx or thrown error (timeout, offline) is retried after 2 s and 6 s, then left uncached; a 200 that isn't JSON (a captive portal's page) is transient, never a cached "no preview". Fixed (tests).
  - **C8 / A10** — every iTunes request (preview, artwork, metadata) names the Mac's region as `country`, US when the region is unknown or not a country. Fixed (tests). **Not done:** a region with no iTunes store gets an error and no preview — no second US attempt.
- **BR.17 (2026-09-30), output devices as testers have them (P2, tracked here):**
  - **I4 / B7** — the beat-phase display offset is the tuned 50 ms raised to the output device's own latency (device + safety offset + stream, read at launch and on every device change); built-in and wired output keep exactly 50 ms (this Mac mini reads 0.6 ms). `UZUME_DEVICE_LATENCY=0` is the A/B arm. Fixed (tests); ⏳ AirPods A/B, listening session 2 — the Bluetooth figure has not been read on a real Bluetooth device.
  - **G4** — the live stem buffer holds 192 kHz × 13 s, so every ≤ 12 s window fits at 88.2 / 96 / 192 kHz; before, a 10 s window at 96 kHz returned 6.9 s and live stems never ran. Fixed (test; negative control: old sizing → red at 88.2 / 96 / 192).
  - **B9** — above 80 kHz the live FFT input is averaged to 44.1 / 48 kHz (`HighRateDecimator`), keeping ~46 Hz bins. Fixed (test: tones at 96 / 192 kHz peak in the 48 kHz bin; negative control red). **Ceiling:** a box-car average is a weak anti-alias filter.
- **BR.16 (2026-09-30), honest copy and credits (P2, tracked here):**
  - **A7** — the permission screens, both Info.plist usage strings and the scan permission now say *"Your audio never leaves your Mac. Uzume looks up song details on Apple's iTunes and MusicBrainz."* (decision 9); UX_SPEC, the tester notes and SECURITY_POSTURE follow. Fixed.
  - **C13** — MusicBrainz lookups share one process-wide `RateGate`: one request per second (test).
  - **K7 / H9** — Settings › About › Acknowledgements credits Beat This!, Open-Unmix, PANNs (CC BY 4.0) + AudioSet, nimitz's "Auroras" (CC BY-NC-SA 3.0), WebGL Fluid Simulation, the CMU mocap database (its requested wording) and the eight Milkdrop-inspired scenes, each linking to its source, plus a link to CREDITS.md. The licence line no longer claims MIT for everything. CREDITS.md's table gains Stave. Fixed (test: every row resolves and the named credits are present).
  - **F16** — one copyright holder, Plait & Pattern (Matt, 2026-09-30): `LICENSE` now matches the About box, and Settings no longer says "© 2026 Uzume contributors". The "© 2024 Matt" the audit saw is no longer in the tree. Fixed.
- **BR.15 (2026-09-30), controls that do nothing — hidden for the beta (decision 6; P2, tracked here).** `BuildFlavor.exposesUnwiredControls` (developer only):
  - **F5 / E5** — Settings' "Device tier", "Quality ceiling" and "Hidden scene families" are hidden in the public build (none reaches scene selection). **Open:** wiring them after the beta; the quality ceiling's data-vs-string read-back goes with it.
  - **E4** — the keys `+` `-` `.` `←` `→` and `⌘R` are hidden in the public build and gone from its `?` overlay; ⇧← ⇧→ and ⌘Z stay. **Open:** the session-clock, exclusion and re-plan fixes (E4's fix direction), after the beta.
  - **E14** — the adaptation-toast toggle is hidden in the public build with the keys, and toasts are **off until turned on** (Matt 2026-09-30, reversing U.6b's default-on): `LiveAdaptationToastBridge` now reads an unset key as off, like the Settings toggle and UX_SPEC §7.4. Fixed (test; negative control: default-on → red — the older timing test passed under both).
- **BR.14 (2026-09-30), window, keys, cursor, Settings (P2, tracked here):**
  - **F4 / D7** — playback takes its window from its own view (`HostWindowReader`), not `NSApp.keyWindow` (Spotify's, in the streaming flow), so ⌘F, Esc-exits-fullscreen and display handling attach. Fixed (tests); ⏳ ⌘F and Esc in green-button fullscreen with Spotify started first, listening session 2.
  - **F9** — the key monitor ignores keys aimed at another window (the Settings sheet), and Esc closes the help overlay before anything else. Fixed (tests).
  - **F14** — closing the window ends a live session (capture, recording indicator and stem separation stop). Fixed (test). *Chosen over quitting: the Dock reopens onto the Ended screen.*
  - **F19** — the pointer hides with the playback chrome and returns on the next mouse move. Fixed (tests).
  - **F6** — Settings from every screen: Uzume › Settings… / ⌘, (a `Settings` scene) and the Idle gear (UX_SPEC §4.1). Fixed (test + live: ⌘, opened Settings on the Debug build).
  - **D8** — "Move to primary display" targets the menu-bar screen (`NSScreen.screens[0]`), not `NSScreen.main`. Fixed (test); ⏳ from the secondary display, listening session 2.
- **BR.13 (2026-09-29), local-file transport (P2, tracked here):**
  - **B3 (extends BUG-056)** — an output-device change resumes at the last playhead, keeps a pause (no audible restart behind a paused UI), and retries once before reporting. Fixed (`LocalFileSeekTests`; negative control red); ⏳ AirPods swap mid-song and while paused, listening session 1.
  - **B4** — every session boundary (Connecting, Preparing, Idle, End) stops the previous session's audio, so a new local source or Cancel no longer leaves the old track playing or its end-of-file advance firing mid-preparation. Fixed (test); ⏳ open a second file while one plays, listening session 1.
  - **B10** — a mono local file is emitted as stereo (the same sample on both channels) instead of being averaged in pairs an octave high. Fixed (`PlayheadAnalysisClockTests`; negative control red).
- **BR.12 (2026-09-29), audio capture lifecycle (P2, tracked here):**
  - **G2 / B14** — start, stop and reinstall run on one serial lifecycle queue; `stopCapture` bumps a generation token and a reinstall scheduled before it does nothing. Fixed; TSan-clean (`TapLifecycleStressTests`; negative control without the queue: 10 races).
  - **G8** — a failed device-change reinstall keeps the capture intent and the device monitor, so the next device change retries. Fixed (test).
  - **B5** — a Core Audio restart (`kAudioHardwarePropertyServiceRestarted`) re-registers the monitor's listeners and reinstalls the tap. Fixed (test via the seam); ⏳ live `killall coreaudiod` mid-session, listening session 2. **Not done:** a tap that goes silent *without* a service restart still skips the retry ladder once audio has been heard.
  - **B6** — the cold-install ladder is held while Ready waits for audio (released at Playing / Ended / Idle), and Ready's Retry reinstalls the tap on demand. Fixed (test).
  - **G6** — a tap reporting a non-finite or zero sample rate is rejected at install. Fixed (test).
- **BR.1 (2026-09-29).** F1/F1b → **BUG-163**; K1/D1 → **BUG-164**. P2 findings fixed in the same increment, tracked here:
  - **F7** — the photosensitivity notice gates every path to visuals (ContentView; ⌘O / Open With / drop included). Fixed (`8d294d8f`); live-verified on the local-file path (ack forced NO stops at `.ready`, YES logs `playback started`).
  - **F6** — the notice's "Enable Reduce motion" sets the in-app Reduced motion to Always on (UX_SPEC §3.3). Fixed (`8d294d8f`).
  - **K3 / E13 / F15 / A13** — the public build walks only certified, non-diagnostic scenes on Shift+→, hides "Show uncertified scenes" (a stored true never reaches the engine) and loads no user-preset folder (`BuildFlavor.exposesUncheckedScenes`). Fixed (`1e47cca9`); verified by test only — no public-flavor build was run.
  - **K4** — flash measurements added for Fractal Tree (native mesh path, over the tree's own box), Ferrofluid Ocean's lit output and Waveform; all 0.00 flashes/s. The single-pass gate now fails on a G-buffer draw — which also caught **Volumetric Lithograph**'s single-pass "measurement" (surface height; its lit multi-pass test was already green). Fixed (`1ede2e2b`). **Still unmeasured:** Murmuration's birds, Gossamer's and Membrane's feedback accumulation (K4's other holes; not in BR.1's done-when).

### AUDIT-2026-06-09 — Full-codebase audit backlog (P2/P3 findings not individually filed)

**Status:** Open — index entry (P3 backlog only as of PUB.3: all four formerly-open P2 bullets below verified fixed in code, 2026-07-11). The 2026-06-09 six-agent full-codebase audit (~92k lines, all findings verified at file:line, cross-checked against this tracker and CLAUDE.md FAs) produced 6 P1s, 17 P2s, ~40 P3s. The P1s and three highest-impact P2s are filed individually below (BUG-030 … BUG-037). Everything else lives in **[`docs/diagnostics/CODE_AUDIT_2026-06-09.md`](../diagnostics/CODE_AUDIT_2026-06-09.md)** — treat that document as the evidence record when picking up any item. Remaining P2s in brief (full detail + fix shapes in the audit doc):

- ✅ **RESOLVED (CLEAN.3.2, 2026-06-17; re-verified in code at PUB.3)** — reactive orchestrator hard-exclusion filtering now present (`ReactiveOrchestrator.swift:~220`, exclusion-aware selection with the every-scene-excluded edge handled).
- ✅ **RESOLVED (CLEAN.3.3, 2026-06-17; re-verified at PUB.3)** — zero-duration fallback now routes through the scored/excluded path (`SessionPlanner+Segments.swift:~129`).
- ✅ **RESOLVED (CLEAN.3.x, 2026-06-17; re-verified at PUB.3)** — cooldown reset on track/session boundary (`LiveAdapter.swift:~369-378`).
- ✅ **RESOLVED (CLEAN.3.5, 2026-06-17; re-verified in code at PUB.3)** — in-memory StemCache now has an LRU cap (`maxEntries` + touch-on-track-change eviction, `StemCache.swift:~89-101`).
- **OAuth correctness (re-entrant `login()` leak, refresh double-spend, P3 hardening)** — ✅ **RESOLVED 2026-06-14 (CLEAN.2.2, commit `13cec8b`, integrated `a6f1288`).** Matt's live check passed: Spotify playlist loaded with no problems on the integrated `main` build — the refresh path exercised end-to-end against real Spotify, no regression. The fresh-login `state` guard is unit-test-proven + standard OAuth on unchanged callback routing (accepted without a forced interactive login per Matt 2026-06-14, since a silent refresh does not hit the consent round-trip). `SpotifyOAuthTokenProvider`: a second `login()` while one was pending overwrote `pendingContinuation` (orphaning the first caller until the 5-min timeout) + armed a stray timeout against the wrong attempt → now coalesces concurrent logins onto one in-flight attempt (`pendingContinuations` array; `finishLogin()` cancels the timeout on every resume path); concurrent `acquire()` each fired their own silent refresh, double-spending the rotating refresh token → now dedups onto a single in-flight `refreshTask`; + P3s (OAuth `state` CSRF/replay guard, form-body percent-encoding of `+ & = /` that `.urlQueryAllowed` leaked, Keychain-save failures logged not swallowed, callback `scheme == uzume` + host validation). `SpotifyOAuthTokenProviderTests` green (4 new regressions).
- ✅ **RESOLVED (CLEAN.2.1, 2026-06-14)** — Spotify client secret baked into the built Info.plist. Removed `SpotifyClientSecret` from `Info.plist` + `Uzume.xcconfig` and deleted its only consumer, the D-068 client-credentials `DefaultSpotifyTokenProvider`. The production flow already used OAuth Authorization Code + PKCE (`SpotifyOAuthTokenProvider`), which needs no secret; no build-bundled secret remains. OAuth login E2E confirmed by Matt 2026-06-14 on the integrated `main` build (no regression). See `RELEASE_NOTES_DEV.md [dev-2026-06-14-d]`.
- ✅ **RESOLVED (CLEAN.2.3, 2026-06-14)** — honest-UI dead controls (audit T5), each Matt's product call. **2.3.1:** the "Use Apple Music instead" no-op `{ }` cross-link (+ its dismiss-only mirror) now drive a real `NavigationStack` switch via `ConnectorPickerViewModel.switchConnector(to:)` (wire). **2.3.2:** the `.localFile` "coming later" capture mode (lying + no-op) removed — enum case, picker row, false string, and the now-unreachable reconciler/coordinator branches (remove; supersedes the `.localFile` branch of D-052). **2.3.3:** the disabled "Swap scene" context-menu stub hidden behind `#if ENABLE_PRESET_SWAP` until U.5b (hide). Commits `7800b72` / `d40cfad` / `6e983c8`. `RELEASE_NOTES_DEV.md [dev-2026-06-14-f]`.
- ✅ **RESOLVED (CLEAN.4.4, 2026-06-17)** — three renderer over-allocation / cache-key items from audit T7 (the `2026-06-13` audit's restatement of these P3s). (1) **PSO cache key** (`ShaderLibrary` cached by `name` alone, ignoring `pixelFormat`/`supportICB`): **finding = LATENT, not a live bug** — every production caller uses a **unique** name compiled once at init, scene multi-pass PSOs bypass the cache (`PresetLoader` → `device.makeRenderPipelineState`), and `supportICB: true` is test-only, so nothing currently collides; keyed correctly anyway by `PipelineKey(name, pixelFormat.rawValue, supportICB)` so a future name-reuse can't return the wrong-format PSO. (2) **wasted particle-mode warp pass** + (3) **unconditional feedback textures**: both gated to surface-mode feedback scenes via `RenderPipeline.activePresetSamplesFeedback` — non-feedback + particle-mode scenes allocate zero ping-pong (freed on `setFeedbackParams(nil)`), and particle mode skips the warp. Output-preserving (PresetRegression goldens byte-identical). Gates: `ShaderLibraryTests` +2, `DrawableResizeRegressionTests` +3. `RELEASE_NOTES_DEV.md [dev-2026-06-17-215601]`. (T7's remaining items — sceneTexture aliasing, resize stale-size, ray-march /height NaN, DynamicTextOverlay race — **were closed by CLEAN.4.3 and CLEAN.4.5, both completed 2026-06-18**; see `docs/diagnostics/CODE_AUDIT_2026-06-13.md`, where they are marked ✅, and `ENGINEERING_PLAN_HISTORY.md`. *Corrected at RECON.2, 2026-08-03: this line previously read "stay open under CLEAN.4.3/4.5", and since both increments have rotated out of the live plan the pointer was unresolvable from here — it read as open work with no owner.*)
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

> **Reconciled 2026-09-30 (BR.KI ledger pass).** One instance (2026-08-03). The index's former "3 instances (08-04 ×2)" were BUG-085's day. Probably the same defect as BUG-085 (audit D2).

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

**Not yet established.** Everything else. A frozen UI with a healthy render loop points away from the scene and toward the main thread or the preparation pipeline, but that is an inference, not evidence — do not act on it (BUG-061 rule).

**Sub-finding, FIXED 2026-08-04 (`17ac02fc`): a crashed session left an unreadable `raw_tap.wav`.** The stub header declares a `data` size of 0 and the real sizes were patched in only on the 30 s cap or a graceful `finish()` — so every standard reader saw an empty file. Session `2026-08-04T20-23-15Z` had **28.8 MB of intact float samples behind a header claiming zero bytes**, making the capture useless for diagnosing the crash that produced it. `patchRawTapHeader` now also runs about once per second of audio. **NOT gated by a test:** `RawTapHeaderRecoveryTests` could not be made to run (constructing a recorder and abandoning it mid-capture either crashed the test process with signal 5 or produced no file); the fix reuses the existing patch routine and `test_rawTapCapture_persistsAfterDurationCap` still passes, but there is no regression guard. Worth a second attempt with fresh context.

**Next evidence needed — the one thing that would settle it.** A `sample` of the process while it is hung, which captures the blocked main-thread stack:

```
sample UzumeApp 10 -file ~/Desktop/uzume-hang.txt
```

Run it *during* the beachball, before force-quitting. Without a blocked stack there is no way to distinguish a deadlock from a GPU stall from a preparation-pipeline wedge.

**Note.** Signal health was `critical` (−24 dBFS) for the session's first ~50 s before reaching green; unlikely to be related but recorded because the session is otherwise the only artifact.

---

### BUG-123 — Dragon Bloom remains paler than the reference (2026-09-08, PARKED)

**Severity:** P3. Matt, on the PR.5.4 build: *"Color is better but still washed out. It doesn't feel like we can solve this. Maybe we should stop and move on?"* — and then: *"stop and proceed with another PR increment."*
**Domain tag:** `preset.render` · failure class **`fidelity`**.
**Status:** **Parked on Matt's call.** Reopen only as a single bounded increment.

**Measured.** Seven Nation Army, display with comp on. Reference (offline oracle, 10–40 s): luma 0.37 (0.25–0.53), saturation 0.89. Ours (22:41 session, 1800 frames): luma 0.57 (max 0.81), saturation 0.65. The gap is tone, not structure: no white-outs (nearWhite 0.006), no flashes, balanced field.

**Why PR.5.4 missed it.** Its success metric was `nearWhite` (all channels ≥ 235). Pale cream is 170–230 in the low channel. The metric measured the thing that was fixed and could not see the thing that remained — record this alongside the span artifact and the track-averaged `nearWhite`.

**Where to look if reopened.** Our accumulator runs roughly twice the reference field's brightness on the same material (ours 0.75 field luma at the drop vs the reference display 0.20 → field ≈ 0.8 inverted… measure it directly, do not infer). Candidates not yet tested: the strand ink stored as HDR (`hi` up to 2.0 in a float target; the reference clamps at 1.0 on write — probe F tested only nearWhite, not luma), and the ×4 boost the oracle applies before analysis (our stem energies are not boosted the same way). One increment, one comparable number, hard stop.

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
**Domain tag:** renderer / app.hang (suspected scene-apply or first-frame GPU hang on Gossamer).
**Status:** **OPEN — RECURRED (Matt, 2026-08-03; RECON.2).** The prior "likely resolved by NACRE.2b" status is **falsified as a complete explanation** and must not be restored without new evidence. Asked directly during the 2026-08-03 production audit whether the force-quit hang had been seen since mid-July, Matt confirmed it had. No session ID, scene, or stack was captured for the recurrence, so the *mechanism* is still undiagnosed — what changed is that the empty-`activePasses` guard is now known to be **insufficient**, which was the exact residual risk the previous status flagged ("the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains"). That residual is now the leading hypothesis rather than a footnote.

**What the recurrence changes.** Previously this entry was one clean session away from closing. It is now a live P3 with a *narrowed* hypothesis space: the scene-apply race is fixed and verified (BUG-061 is closed on its own evidence), so whatever hangs the render loop is **not** that race. Do not re-run the "confirm by non-recurrence" plan — it has already returned a negative. The next step is evidence capture, not another monitoring window.

**⇄ Same class as BUG-081 — two instances, one missing artifact (linked at RECON.9, 2026-08-03).** A parallel session independently filed **BUG-081** for a beachball ~78 s into session `2026-08-03T22-54-06Z` that also needed a force-quit and also produced no crash report, and reached the *same* conclusion this entry did, separately: force-quit yields no `.ips`, so the artifact must be taken **during** the hang via `sample`. Two sessions converging on that from different evidence is worth more than either alone. **Treat BUG-060 and BUG-081 as one investigation** — differences to keep in view: BUG-081's capture shows the renderer *healthy to the last frame* (steady 60 fps, Fractal Tree 0.18 ms GPU against a 0.7 ms budget, no degradation across 3756 frames) with background ML load rising, which points at a frozen **UI/main thread** rather than a dead render loop; BUG-060's original capture showed the render loop itself stopping one frame after a scene switch. Those may be one bug or two. **Whichever recurs first, capture the sample** — it resolves both. Do not assert a shared root cause before then (BUG-061's rule).

*Prior status, retained for the reasoning trail:* LIKELY RESOLVED by NACRE.2b's BUG-061 fix (2026-06-25), pending non-recurrence. BUG-061 confirmed the suspected **scene-apply race**: `applyPreset` clears `activePasses` to `[]` then republishes them at its end, while `draw(in:)` runs concurrently on the display-link thread; a frame in that window falls to `drawDirect` with the new scene's direct pipeline. Nacre's `.rgba16Float` pipeline made it a deterministic crash and exposed the mechanism; for an 8-bit scene like Gossamer it's the benign/intermittent stray frame seen here. The `willRenderActiveFrame` guard (skip frames while `activePasses` is empty) removes the stray `drawDirect` for ALL scenes. Keep monitored until a few clean Gossamer-switch sessions confirm non-recurrence (the original was a *hang*, not a crash, so a small chance it's a distinct GPU-contention issue remains).
**Introduced:** Unknown (the apply-race predates NACRE.2b).
**Resolved:** Not resolved. The 2026-06-25 empty-passes guard fixed a real adjacent defect (BUG-061) but did not stop this hang.

**Expected:** switching scenes (incl. Gossamer) never hangs the app.

**Actual (session `2026-06-17T22-10-50Z`):** the render loop was healthy — 60 fps, `frame_gpu_ms` 0.13–1.5 ms, no `deltaTime` gap — through the **last recorded frame (9459) at `22:14:01Z`**, which is **one second after `session.log`'s last event, `preset → Gossamer` at `22:14:00Z`**. `features.csv` then stops while the stem-separation / orchestrator threads keep logging for ~30 s more → a **render-path hang** (main or GPU), not an analysis stall (cf. BUG-043, a freeze-then-lurch) and not a tap freeze (cf. BUG-058). Video was OFF (BUG-050), so the recorder's video path is excluded. Matt force-quit from Xcode **without hitting Pause**, so no thread stacks were captured.

**Non-reproduction (session `2026-06-18T13-57-23Z`):** Gossamer was applied **3×** (13:58:35, 14:00:13, 14:00:36) and rendered clean; the session ended with a normal `SessionRecorder finished` shutdown. So the hang is rare/intermittent, not a deterministic Gossamer defect.

**Reproduction steps:** unknown trigger. Lead: a `preset → Gossamer` switch under live load (continuous stem separation running) — possibly transient GPU contention between the stem-separation MPSGraph and Gossamer's first-frame render, or a scene-apply race.

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
On the swap the visualizer freezes and never recovers. Session `2026-06-17T14-28-30Z` (instrumented build, healthy coreaudiod): the tap worked ~39 s (RMS 0.06, `signal quality → green`), then at the switch **`raw_tap.wav` stops at exactly 39.1 s while the session ran ~134 s** — the **IO proc stopped firing entirely.** The render loop coasted on the last buffer for ~95 s → `features.csv` tail is **constant nonzero** (`bass=0.16956, mid=0.00565, treble=0.00073`, identical across the final frames) = the Waveform scene shows a frozen flat line. **No `reinstall via device-change` success/FAILED line**, and **no `audio signal → silent`** (the buffer isn't RMS≈0, so `SilenceDetector` stays `.active` → `.silent → reinstall` never arms either). Both recovery paths miss.

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
- [x] On an `AVAudioEngineConfigurationChange` (output change), the provider reconfigures and **resumes from the saved frame position** rather than restarting at 0. *(BR.13, 2026-09-29: resumes at the clock's last playhead, keeps a pause, retries once; `LocalFileSeekTests`, negative control red.)*
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

**Severity:** P2 (visual artifact on a subset of odd-meter tracks. Bar-locked motion scenes (Ferrofluid Ocean) cycle at the wrong rate on tracks where the ML meter detector guesses wrong AND the metadata source can't override. Current production playlist only surfaces this on Pink Floyd's Money 7/4 → cycles at 5.85 s/cycle on Ferrofluid Ocean instead of the intended 20.5 s/cycle. Visual still reads as "ocean swell" per Matt's 2026-05-15T17-54-49Z review.)
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
3. Switch to Ferrofluid Ocean scene.
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
3. Switch to SpectralCartograph scene and observe mode label.
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
| `PlayheadAnalysisClockTests` — "A stalled or paused playhead delivers silence, not the last frame forever" | Asserts an **exact** delivered-tick count (`delivered.count == stallFlushTicks - 20`) on a timer-driven dispatch source; under parallel load the clock over-delivers (observed 106 vs 100, and some frames not yet flushed to zero). Not a GPU submit — a counting assumption. Observed 1/5 full runs, BUG139.1, 2026-09-23 | Re-run in isolation. **The real fix is to drop the exact-count assumption**, per the deterministic-over-budget-widening rule (CLEAN.7.9–7.14) — assert the flush *reaches* silence, not how many ticks it took |
| `StagedPersistenceTests` — "the watchdog probe's cost is set by the block, not by the texture" | Asserts a cost-growth **ratio** (`growth < 2.0`; observed 2.32) under the full parallel suite. Observed 1/5 full runs, BUG139.1, 2026-09-23 | Re-run in isolation. Same remedy shape as the rows above: take a min over warm samples rather than a single contended measurement |

*(The three perf rows were added at RECON.2, 2026-08-03. They were declared "confirmed flake" during the BUG-080 investigation but never reached this table — so each run re-litigated them from scratch. **These are the known-flaky *shape*** — a single wall-clock sample around a GPU submit — that CLEAN.7.9→7.14 fixed elsewhere by asserting the **minimum of N warm samples** rather than one sample, or by removing the timing assumption entirely. Per the deterministic-over-budget-widening rule these three should get the same treatment rather than staying in this table; that is a small, well-precedented increment, not a mystery. Until then: a failure here is not evidence of a regression on its own.)*

**Resolved 2026-09-29 (TESTFLAKE.3)**: `PlaybackChromeViewModelTests` (`firstShow_waitsForTheArrival_thenThreeSeconds`, `overlayAutoHides_afterDelay`, `onActivity_fromHidden_restoresTheChrome`) and `ReadyViewModelTests` (`firstAudioDetected_emitsAdvanceSignal`, `audioDetectedBeforeTimeout_hasDetectedAudioFlips`, `retry_resetsDetectorAndClearsTimeout`). None of them was ever in the table above. Each failed once under full-suite load during CLEAN.2.5b and passed on immediate rerun. Each slept a fixed wall-clock window (50 ms to 1500 ms, twice widened since U.11) and then asserted on work a main-actor `Task` does after an injected `DelayProviding` returns. Under load the task had not run yet (e.g. `RecordingDelay` not yet called at the 50 ms mark). Per the deterministic-over-budget-widening rule, the windows are **removed, not widened**. The tests await the event: the `@Published` value (`$overlayVisible.values`, `$hasDetectedAudio.values`), or each armed timer through `RecordingDelay.requests`. `receive(on: .main)` deliveries, including the negative "first track does not re-arm" check, go through `drainMainQueue()`, a FIFO main-queue barrier. It returns after the delivery and any MainActor task that delivery spawned. A mutant that re-arms on the first track fails that check. The same 1500 ms sleep in `ReadyViewTimeoutIntegrationTests` got the same fix. The suites carry `.timeLimit(.minutes(1))`, so a regression fails instead of hanging. Test-only, no production delta. See `RELEASE_NOTES_DEV.md [dev-2026-09-29-174949]`.

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

### BUG-156 — the local-file end-of-track tests wait on a thread pool the suite keeps busy (2026-09-29)

**Resolved 2026-10-01 — live check passed (build 10 and the PREP.3 build, Matt):** Next and seek while preparation ran never stalled.

**Severity:** P3 (test flake; the product risk below is open and unobserved) · **Domain:** `test-infra` / `audio.playback` · **Failure class:** `concurrency` (a wall-clock deadline on a callback delivered through a starved pool) · **Status:** Fixed (BUG156.1, `35abbcf1`) · **Introduced:** LFSEEK.1 (`2639294d`, 2026-09-28 09:08), which switched the queue-advance completion to `.dataPlayedBack`. The flake first appeared eight hours later. · **Related:** BUG-103 (the same suite's other face), BUG-151 (why `.dataPlayedBack`), BUG-154 (same fix shape)

**Expected:** `SessionLifecycleChurnTests.onFileEnded_queueAdvanceChurn_neverHangs` passes however loaded the test process is. A missing `onFileEnded` still fails it.
**Actual:** it failed once in a full engine run on `ff-5` (`b706c315`, 2026-09-28 17:09): *"failed after 10.317 seconds with 1 issue"*. It then passed 5/5 alone (~2.75 s each), and the next full run was 2107/2107. Reproduced first-hand on 2026-09-28 with a probe in the test: **2 of 2 full runs stalled at advance 0.** A peer session's engine suite was running at the same time, so this is not a clean "no peer" repro; the mechanism below does not depend on it.

**What the stall looks like** (probe snapshot at the 5 s timeout): engine running, player playing, playhead at sample 219 957 of an 11 025-frame file (0.25 s of audio, played 20 times over), no stale reschedule, no config change, and **AVFAudio's completion handler never invoked.** The playhead kept advancing in real time. The callback arrived **late, not lost:** after 20.0 s in run 1 and 14.9 s in run 2.

**Mechanism (established).**
1. A `sample` of the test process taken during the stall shows no thread running AVFAudio's played-back timer. `LocalFileSeekTests.seekMovesThePlayhead` sat the whole 2 s in `-[AVAudioPlayerNode stop]` → `StopImpl` → `AVAEDispatchQueueTimer::CancelTimer()` → `semaphore_wait`. About eight of the ten `com.apple.root.default-qos.cooperative` threads were busy in CPU-bound synchronous tests (Mitosis, Skein, Witchlight luma loops).
2. A controlled experiment in one process (a 0.25 s file, 2 × ncpu spinner blocks for 8 s) isolates it:

   | spinners at | `.dataPlayedBack` latency | `.dataConsumed` latency |
   |---|---|---|
   | none | 0.317 s | 0.007 s |
   | background / utility | 0.316 / 0.315 s | — |
   | **default / userInitiated** | **8.50 / 8.55 s** (released with the spinners) | 0.002–0.010 s |

   The caller's QoS doesn't matter: `play()` from a userInteractive, userInitiated or default thread all waited ~8.3–8.5 s. With the spinners never released, the completion never came, and the `player.stop()` after it blocked in `CancelTimer` for **14 h** (sampled, then killed).

So `.dataPlayedBack` completions are delivered from a timer in the process's constrained default-QoS dispatch pool. The parallel suite fills that pool with Swift Testing's synchronous CPU-bound tests; in one run it stayed saturated for **212 s**. A 5 s deadline on the callback was measuring the neighbours. External CPU load (`yes` × 20, plus audio churn in another process) did **not** reproduce it, 15/15 green: the pool is per process. `.dataConsumed`, the type before LFSEEK.1, doesn't go through it, which is why the suite was quiet until 2026-09-28.

**Reproduction.** A full `swift test --package-path UzumeEngine` with a probe logging the provider state at the timeout; or the in-process spinner experiment above, which is deterministic.

**Fix (test-only).** `awaitPlayedBackEnd` (`Tests/UzumeEngineTests/Audio/PlayedBackWait.swift`) replaces the bare `wait(5 s)` in the churn test and in `LocalFileSeekTests.seekMovesThePlayhead`, the sibling caught in the stall sample. After the 5 s budget it queues a canary on the default-QoS pool, behind the overdue completion. While the canary is pending, the pool hasn't had its turn, so a callback that lands then passes the moment it lands. Once the canary has run, the completion has been dequeued; the callback gets the same 5 s again, and missing it means lost. The verdict is an ordering. **No timeout was widened.** A lost callback still fails, 5 s after the pool proves it has had its turn. `LocalFilePlaybackProvider` is unchanged.

**Verification.**
1. ✅ Deterministic gate: `PlayedBackWaitTests`. A suspended queue stands in for the starved pool, and a callback landing at 4× the budget passes; with a live pool, a callback that never comes fails. **Negative control:** the bare `wait(budget)` fails the first test (run 2026-09-29).
2. ✅ Three consecutive full engine runs on the fixed tree (a temporary late-path log line added for evidence, removed before commit): **runs 2 and 3 green, 2117/2117.** In run 1 the churn test passed through the late path in 13.1 s, where the old wait would have failed at 5 s. Run 1 went red on `StemSeparatorConcurrencyTests` (see *Sibling* below): same mechanism, not this change.
3. Manual: none (test-only change).

**Sibling, same mechanism (fixed separately as BUG-157, BUG157.1).** `StemSeparatorConcurrencyTests.concurrentSeparations_returnPerCallerOwnStems` dispatches its eight separations to a private concurrent queue at default QoS, the pool above, and asserts a fixed `group.wait(timeout: 180 s)`. In run 1 of this increment's verification that wait timed out (198 s), and all three assertions after it failed on the empty collector. It was in the BUG-156 stall sample too, blocked at line 101. The remedy has the same shape: its work is not stuck, it is queued. Its wait could be ordered the same way, or the queue given a QoS above the saturated band.

**Open — product risk, not observed.** The app depends on the same pool. With `onFileEnded` set, the local-file queue advance waits for that completion, and `stop()` (Next, Stop, a seek) calls `player.stop()`, which waits in `CancelTimer` while a played-back timer is pending. If the process's default-and-above pool is saturated during local-file playback, a track advance would be late, and a MainActor `stop()` could stall for as long as the saturation lasts. `SessionPreparer` runs its analysis as `Task.detached(priority: .userInitiated)`, a band the experiment shows delays the completion just as much. **Not established:** whether preparation ever overlaps local-file playback with enough parallel CPU work to saturate the pool, and no app session has shown a late advance or a Next-press stall. Evidence needed before any provider change: a live local-file session with preparation running, timing `onFileEnded` against the file's end and `stop()` on the MainActor.

### BUG-148 — stored valence is negative on every beta-playlist song (2026-09-26)

**Resolved 2026-10-01 — live check passed (build 10, Matt):** scene choice *"Looks good. Good variety overall."*

**Severity:** P2 · **Domain:** `ml.mood` → `orchestrator` · **Failure class:** `algorithm` (a model that does not generalise beyond its 12 training songs) · **Status:** Fixed by replacement (D-259, NRG.1–3, 2026-09-27); Matt's live check pending · **Found by:** Matt's BUG-144 check, 2026-09-26: *"all of the moods were listed as 'restless'"* · **Related:** BUG-144, BUG-149, OBS-DS4-1, BUG-066, DYN.6.2

**Expected:** stored valence spreads with the music: cheerful songs (Penny Lane) positive, dark ones negative. **Actual:** the app's own cache after the BUG-144/145/146 build (schema v16, 2026-09-26 14:48–14:59) stores negative valence on **10/10** songs: Dance Yrself Clean −0.41, B.O.B. −0.34, Superstition −0.37, Teen Spirit −0.83, Penny Lane −0.25, Take Five −0.22, Pyramid Song −0.03, Teardrop −0.27, Moonlight I −0.02, Warszawa −0.03. The label is only a quadrant (`EmotionalState.quadrant`: negative valence with positive arousal reads "restless", negative with negative reads "wistful"). By these values Penny Lane and Moonlight I should read "wistful".

**Consumers:** `PresetScorer.moodSubScore`. Valence → colour-temperature target (0.5 + 0.4·v), half of the mood term, which is 40 % of each score. Also the preparation view's mood word.

**First facts (diagnosis in progress; no root cause asserted).**
- The shipping model was trained at `d586e57` (2026-04-07) on **818 frames from 12 hand-labelled songs** (`~/phosphene_features_annotated.csv`), recorded from the live path at the time.
- At the scaler's mean feature vector the model outputs valence **−0.42**, arousal +0.41. An "average" input reads restless.
- Replayed on its own training features, it still separates valence: Love Shack +0.45, Love Rehab +0.68, No Surprises +0.22, Pyramid Song −0.50. With the pre-DYN.6.2 flux scaler those read +0.66 / +0.71 / +0.43, so the corpus flux re-fit trims valence by 0.1–0.2 without flipping it.
- The open question is what differs in the features preparation feeds the model today (post BUG-066 / DYN.4–7 / BUG-146).

**Diagnosis (2026-09-26).** Evidence is in `~/Documents/uzume_spikes/bug148/`: the Python replica `mood_mlp.py`, `loso.py`, the per-frame inputs `feat/`, and the uncommitted recorder patch.
1. **Instrument.** `PrepTimingRunner` with a recording classifier captured every frame's 10 inputs and output on the ten songs (Release, shipping pipeline). A Python replica of the model, parsed from `MoodClassifier+Weights.swift` and the scaler, reproduces the app's per-frame state to **3×10⁻⁵** on all ten.
2. **Input shift.** Against the 12 training songs, today's preparation inputs sit within ±0.3 training σ on bands and centroid. Flux sits **+2.5 σ** (median 0.75 vs 0.23; beta max 1.71 vs training max 0.43), and both key correlations sit about **−0.75 σ**.
3. **No single input explains it.** Resetting one input group to its typical-training value swings valence erratically in both directions: flux takes Dance Yrself Clean −0.42 → +0.59 but Penny Lane −0.25 → −0.42. The typical-training input vector itself reads −0.56.
4. **The model does not generalise.** Leave-one-song-out with the exact `train_mood_from_live.py` recipe, 3 seeds, 12 held-out songs. Valence sign agreement is **42 %** (chance 50 %), Pearson r **−0.30**, MAE 0.62. Arousal sign agreement is **50 %**, r −0.04, MAE 0.50. The seed spread is small (0.13). The shipping recipe's validation split shuffles frames, so its validation frames came from the training songs; the `d586e57` "✓ per-track accuracy" measured memorisation.
5. **Library scale** (census proxy: the model applied to each track's mean inputs, `full_results.csv`, n = 27,638): median valence **−0.15**, 61.5 % negative. Labels would read restless 43.5 %, bright 33.0 %, wistful 18.1 %, calm 5.5 %.

**Root cause:** the valence (and arousal) the model outputs on unseen music is not better than chance. It was trained on 818 frames of 12 hand-labelled songs, validated on frames of those same songs, and today's flux runs far outside the range it saw. The beta playlist's 10/10 negative valence and the library's 61.5 % are that model's bias, not a measurement. A 12-song held-out test is itself small, so the chance-level result is a floor on the evidence, not a precise estimate.

**Verification criteria for any fix (written before the fix).**
1. Automated: leave-one-song-out (or a held-out-artist split) on the training set, reporting sign agreement and r against their chance levels. It must clearly beat chance: valence sign ≥ 70 %, r ≥ 0.5.
2. Beta playlist: Penny Lane reads positive valence; Teen Spirit and Pyramid Song read negative.
3. Library proxy: the quadrant split is reported, not asserted.
4. Manual: Matt's mood check on the beta playlist.

**Resolution (D-259, 2026-09-27).** Matt judged the mood taxonomy itself unusable and chose a measured energy value instead. Nothing was retrained, and valence and arousal left scene choice:
- NRG.1 (#290) measures each song's energy curve.
- NRG.2 (#292) puts it on a library-calibrated 1–10 scale in the preparation view.
- NRG.3 makes the planner score scenes and transitions against the energy of each stretch, and removes the mood-driven live override. Reactive mode stops scoring mood.

**Still reading the model:** the live classifier's `valence` / `arousal` inside about a dozen certified scenes, and Lumen Mosaic's palette pick (Matt: *"leave the certified scenes alone for now"*). The verification criteria above for a retrained model no longer apply to scene choice.

### BUG-176 — Membrane and Waveform flashed in part of the screen at fast tempos (2026-09-30)

**Resolved 2026-10-01 — both halves passed live (build 10).** Membrane on B.O.B. (session 1), Matt: *"No flickers."* Waveform for 23 s with music in session `2026-10-01T18-05-22Z` (from 18:13:12Z), Matt: *"Waveform did not flicker."*

*(Numbering: filed as BUG-175 on `br-20`; renumbered to BUG-176 when #342 merged first with its own BUG-175.)*

**Severity:** P1 (photosensitivity) · **Domain:** renderer / photosensitivity · **Failure class:** `render-state` · **Status:** Fixed 2026-09-30 (BR.20) — pending the felt check in listening session 1 · **Found by:** the flash check v2 (BR.20 / audit I8)

**Expected.** No region of the frame the size of WCAG's small-safe area (a ninth of the screen) flashes more than three times a second, under the 270 BPM worst-case beat train the gate uses.
**Actual.** The whole-frame check (v1) passed both; the new regional check did not. **Membrane** (certified) — 4.0 regional flashes/s: each strike ring's bright crest and dark trough sweeping across a patch of skin. **Waveform** (uncertified, but the launch screen and the fallback) — 5.0: its 64 bars read the raw spectrum, so a kick's bars jumped to full and dropped straight back.
**Diagnosis (measured, two premises falsified on the way).** Membrane: capping strikes to every other beat above 180 BPM made it WORSE (5.0 — a longer-lived ring crosses more of the frame); fixing the bass weight left it at 5.0; the ring's lighting contrast is the lever. Waveform: freezing the bars removed the flash (0.0), so the bars are the source; the first-approved 0.15 s fall still flashed.
**Fix (Matt, 2026-09-30).** Membrane: `kMembraneStrikeContrast = 0.8` scales the ring's crest gain, trough loss and glint — sweep 1.0 / 0.9 → 4.0, 0.8 and below → 3.0 (at the limit, allowed); approved from a before/after on Speed Of Life (the light/dark pair stays, ~20 % softer; palette untouched). Waveform: `WaveformState` holds the bars — instant rise, 0.6 s fall (sweep 0.15–0.5 → 5.0, 0.6 / 0.75 → 0.0; option A′).
**Gates.** `PhotosensitivityCertificationTests` + `MultiPassFlashHarnessTests` now assert regional and saturated-red safety for every measured scene; `WaveformStateTests`.

### BUG-173 — pausing Spotify / Music for more than ~2 s counted as a new song (2026-09-29)

**Resolved 2026-10-01 — listening session 2 (`2026-10-01T18-05-22Z`).** A 44 s Spotify pause (18:10:01–18:10:45Z) resumed on the same song with no track change; the next change (18:11:31Z) was the real next song.

*(Numbering: filed as BUG-168 on `br-11`; renumbered to BUG-173 behind BR.6b, BR.7, BR.8, BR.9 and BR.10.)*

**Severity:** P1 (every tester pauses; each time is a visible reset) · **Domain:** audio / session · **Failure class:** `api-contract` (a paused player answers like a stopped one) · **Status:** Fixed 2026-09-29 (BR.11, `1a160ba0`) — **pending live check** (listening session 2: pause Spotify for 30 s or more, then resume)

**Actual** (audit E2, re-verified ✔︎). Both AppleScripts answer only `if player state is playing`. So a paused player returned nothing, and `StreamingMetadata` cleared `lastTrackIdentity`. On resume, the same song fired `TrackChangeEvent(previous: nil, …)`, which the BUG-020 same-title gate doesn't catch. Every pause over ~2 s then:
- reset MIR and reinstalled the grid (beat-locked scenes re-entered cold start);
- wiped Skein's canvas and settled Nimbus, Witchlight and Kagura;
- cut the song's first planned scene back in;
- restarted the track clock at 0, so every later planned change landed offset.

A single failed poll mid-song did the same.

**Fix.** A poll that finds nothing playing no longer forgets the song (only `stopObserving` does), so the same song returning is a resume. The last-played track survives too, so a real change after a pause keeps its `previous`.

**Gates.** `PauseIsNotANewSongTests`: A, pause, A → one track change; A, pause, B → two, with B's `previous` = A. Both are red on the old behaviour.

### BUG-171 — background preparation disturbed the live visuals' drivers (2026-09-29)

**Resolved 2026-10-01 — listening session 2 (`2026-10-01T18-05-22Z`).** *Start now* with 7 of 40 songs prepared; the other 33 finished behind playback. Matt saw no twitch as songs finished preparing.

*(Numbering: filed as BUG-167 on `br-9`; renumbered to BUG-171 behind BR.6a, BR.6b, BR.7 and BR.8.)*

**Severity:** P1 (the primary visual drivers jump during normal streaming sessions) · **Domain:** session / `dsp.stem` · **Failure class:** `concurrency` (shared mutable analysis state) · **Status:** Fixed 2026-09-29 (BR.9). Visibility was never measured live; see the listening note below.

**Actual** (audit C3/G3, re-verified ✔︎). `makeSessionManager` handed the engine's live `StemAnalyzer` and `MoodClassifier` to `SessionPreparer`, "to avoid double-loading the ML weights". Neither object has weights. Preparation runs about 430 `analyze` frames and about 1,300 `classify` calls per track on them, with no reset. That happens behind playback every few seconds, for minutes. So the live AGC level was ~97 % replaced and the deviation EMA moved ~38 %: live `bass` / `drums` energy and the `*Dev` drivers jumped or flattened for 1–2 s, and live mood snapped to the other song.

**Fix.** The preparer builds its own through `VisualizerEngine.makePreparerAnalysis()`. `makeSessionManager` no longer accepts the live instances.

**Gates.** `PreparerAnalysisIsolationTests` (app): fresh instances; the factory takes no analyzer or classifier and uses `makePreparerAnalysis`. `PreparerAnalyzerIsolationTests` (engine): a 400-frame live drums-deviation trace with two 430-frame preparation bursts on a **separate** analyzer is bit-identical to the baseline; the same bursts on the **shared** analyzer move it (negative control, the pre-fix wiring).

### BUG-157 — the StemSeparator concurrency test waited on a thread pool the suite keeps busy (2026-09-29)

**Severity:** P3 · **Domain:** `test-infra` (UzumeEngineTests, `ml.stem`) · **Failure class:** `concurrency` (a wall-clock wait on pooled work) · **Status:** Fixed (BUG157.1, `f0078ebb`) · **Related:** BUG-156 (same mechanism; its KNOWN_ISSUES entry named this test as a sibling), BUG-031 (what the test guards)

**Expected:** the test passes however loaded the machine is, and fails only on cross-caller contamination or a real hang in `separate()`.
**Actual:** 2026-09-29, one full `swift test --package-path UzumeEngine` run (BUG156.1 verification, run 1). `group.wait(timeout: .now() + 180)` returned `.timedOut` after 198 s, and all three assertions after it failed on the empty collector. The next two full runs passed. The BUG-156 stall sample caught the same test blocked at the wait.
**Cause:** the eight separations went to a private concurrent `DispatchQueue` at default QoS. Its workers come from the process's default-QoS pool, and the parallel suite keeps that pool saturated with CPU-bound synchronous tests (212 s measured once). The jobs didn't start until the pool freed up, so the wait was timing the neighbouring tests.

**Reproduction (in-process, not committed).** Saturate the default-QoS pool with 4 × ncpu spinners for 10 s, then time the start of 8 jobs. On a private default-QoS concurrent queue they started at 9.79 s. On `Thread.detachNewThread` they started in 0.1 ms. Under 60 s of the same saturation, eight real `separate()` calls on detached threads took 0.97 s, against 0.90 s with the pool idle. `separate()` itself does not wait on that pool, so thread placement is the whole defect.

**Fix.** Each caller runs on its own detached thread, not a pooled queue. The 180 s wait is unchanged and is a hang detector again (about 200× the work). All eight callers now overlap from the start, which is at least as much contention as the pool gave. `StemSeparator` is unchanged: no evidence of a product defect.

**Verification.**
1. ✅ Automated: the test passes alone (3.5 s). It still detects BUG-031. With the lock defeated (a per-call `NSLock()`, not committed), the new version went red 7 of 9 runs and the old queue version 5 of 6. Detection is probabilistic either way; this change didn't make it so. Two full engine runs passed it. Instrumented under full load, the body took 3.45 s, and the eight jobs started 0.1 ms after dispatch. The 157–170 s Swift Testing reports for this test is the time before the body gets a thread, which no in-test timeout covers.
2. Manual: none required (test-only change).

---

### BUG-158 — a new user is asked for Documents-folder access at first launch (2026-09-29)

**Severity:** P2 · **Domain:** app / diagnostics · **Failure class:** `api-contract` (macOS privacy / TCC) · **Status:** Resolved 2026-09-29 (`2340d771`) — public build keeps no session records; no Documents question on Matt's rehearsal (build 4) or the fresh-account re-run (build 5)

**Expected.** A new user of the public (notarized) build answers only the permission questions onboarding explains: Screen & System Audio Recording, and Apple Music when they connect a playlist.

**Actual.** The first question macOS asks, at launch, is "Uzume would like to access files in your Documents folder", with generic wording that gives no reason. Seen on the CLEAN.2.5b Task 7 rehearsal (notarized build 2, launched from `/Applications` after `tccutil reset` of ScreenCapture + AudioCapture on Matt's account). TCC log: `09:29:52.829 AUTHREQ_PROMPTING service=kTCCServiceSystemPolicyDocumentsFolder subject=io.uzume.mac`, then `09:30:36 Modify service=kTCCServiceScreenCapture` (the expected grant). Every tester would see it; Matt never did, because his Mac already held the grant.

**Reproduction.** On an account that has never granted Uzume Documents access, launch the notarized app.

**Cause.** The diagnostic session recorder lives in `~/Documents/uzume_sessions`. `UzumeApp.init` prunes that folder at every launch (`SessionRecorderRetentionPolicy.apply`), and every session creates its folder there (`SessionRecorder`, `VisualizerEngine`). Settings → Diagnostics and the Ended screen open it.

**Decision (Matt, 2026-09-29).** *"For the public release, why do we need a diagnostic record of every session? We need to start distinguishing between the developer version of the app and the public release, which would have few features."* The public build records no sessions and never touches Documents; developer builds (Debug and Release) keep recording.

**Verification criteria (written before the fix).** (1) Automated: `BuildFlavorTests` — the developer flavor records sessions, the public flavor does not — and `Scripts/release.sh` fails unless the exported app's Info.plist says `UzumeBuildFlavor = public`. (2) Manual: Task 8 on a fresh account shows no Documents question, and the rehearsal on Matt's account after resetting the Documents grant shows none either.

---

### BUG-160 — Ready never advanced when music started within 1.5 s of the tap coming up (2026-09-29)

**Severity:** P1 (the streaming hand-off hangs until the user clicks Start session) · **Domain:** audio.capture / session · **Failure class:** `pipeline-wiring` · **Status:** Resolved 2026-09-29 (`35cc3be7`, collapsed diagnose+fix with Matt's approval) — live-verified on the Task 8 re-run (build 5, fresh account): Matt waited at Ready, pressed play, Ready advanced by itself (*"Passes all steps."*)

**Expected.** Ready → press play in Spotify → visuals within about a second (UX_SPEC §6.3, FirstAudioDetector ≥ 250 ms).

**Actual.** Seen twice on the "Uzume Test" account (notarized build 4, 11:54; developer-flavor diagnostic build, 17:32 UTC). Ready never advanced; "Haven't heard anything for a while" appeared; after **Start session** the overlay showed SIGNAL green, peak −2 dBFS, health healthy. First filed as a silent tap — the log disproved that.

**Evidence** (`/Volumes/Extreme SSD/uzume_screens_testing/2026-09-29T17-30-29Z/session.log`): `startListeningForFirstAudio → SYSTEM-AUDIO TAP at .ready` at 17:32:14; `tap RMS … t=+2.6s rms=0.000000`, then audio from +3.6 s rising to peak 0.43; `signal quality → green`; **zero `audio signal →` lines for the whole session** (every `AudioSignalState` change is logged). `sessionState=playing` at 17:32:21 is the Start-session click. Both TCC services were granted at tap start (log `authValue=2` for AudioCapture and ScreenCapture) — not a permission failure.

**Root cause.** `SilenceDetector` starts at `.active` and emits only transitions. At `.ready` the engine forces `CaptureStateSurface` to `.silent` (BUG-112 / DS.5) but left the detector at `.active`. Music that begins before `suspectDuration` (1.5 s) of silence never produces a transition, so the surface stays `.silent` and FirstAudioDetector never fires. Waiting ≥ 3 s before pressing play (silent → recovering → active) hid it — why it rarely showed on Matt's own runs.

**Fix.** `SilenceDetector.resetToSilent()` + `AudioInputRouter.markAwaitingFirstAudio()`, called in `startListeningForFirstAudio` after the tap starts: the first audio now always arrives as `.recovering → .active`. The emitted `.silent` also arms the BUG-057 reinstall ladder for a cold tap that never delivers (slightly earlier than before: at Ready rather than after 3 s of silence).

**Gates.** `SilenceDetectorTests`: `test_resetToSilent_musicWithinSuspectWindow_isReported` (the log's shape → `[.silent, .recovering, .active]`), the control `test_withoutReset_…_isNeverReported` (pins the old behaviour), `test_resetToSilent_whenAlreadySilent_doesNotReEmit`; `ReadyFirstAudioWiringTests` (source shape: the call sits in `startListeningForFirstAudio`, after the tap starts).

**Closes on** a passing fresh-account run: press play within a second of Ready and Ready advances.

---

### BUG-161 — crash on the scan review's Continue (2026-09-29)

**Severity:** P1 (crash on the main tester path) · **Domain:** app / UI · **Failure class:** `render-state` (SwiftUI/AppKit presentation lifetime) · **Status:** Resolved 2026-09-29 (`b49a9722`, collapsed with Matt's approval) — live-verified on the Task 8 re-run (build 5): scan → review → Continue, no crash, no crash report

**Actual.** "Uzume Test" account, notarized build 4, 12:06:45: Spotify scan → review → **Continue** → crash. Report `Uzume-2026-09-29-120709.ips` (copy on `/Volumes/Extreme SSD/uzume_screens_testing/`): `EXC_BAD_ACCESS (SIGSEGV) KERN_INVALID_ADDRESS at 0x0`, pc 0, main thread; `UC::DriverCore::continueProcessing()` (UpdateCycle) ← CFRunLoop observer ← `-[NSMoveHelper _doAnimation]` ← `-[NSSheetMoveHelper closeSheet]` ← `NSWindowEndWindowModalSession` ← SwiftUI `SheetBridge.updateSheetPresentations` teardown ← `NSHostingView.layout`. No Uzume frame.

**Cause.** `IdleView`'s connector sheet started the session inside `ConnectorPickerView`'s callback ("no explicit dismiss needed"). The state flip to `.connecting` made ContentView replace IdleView while its sheet was still presented, so SwiftUI tore the sheet down from a departing host and AppKit's close animation ran a nested run loop into a null UpdateCycle callback. Intermittent (animation timing): the 11:24 Apple Music connect on the same build survived.

**Fix.** The callback stores the choice and closes the sheet; `.sheet(…, onDismiss: startPendingConnection)` starts the session once AppKit has finished closing it. Covers Apple Music connects as well.

**Gate.** `ConnectorSheetDismissOrderTests` (source shape: the session starts from `onDismiss`, never inside the picker callback).

**Closes on** a passing fresh-account run through Continue.

---

### BUG-164 — Fractal Tree on M1-family Macs is a full-screen field that flashes with the music (2026-09-29)

**Severity:** P1 (photosensitivity) · **Domain:** renderer / orchestrator · **Failure class:** `api-contract` (GPU family capability) · **Status:** Fixed by exclusion 2026-09-29 (BR.1, `c5f33aa1`, Matt's decision 3). The Apple7 fallback is unchanged and still unmeasured — it cannot be driven on an Apple8 host; gating the native path on Apple7 waits for an M1.

**Actual** (audit K1/D1, re-verified ✔︎). `PresetLoader+Mesh.swift` and `MeshGenerator.swift` take the mesh path only on `.apple8`; M1/M1 Pro/Max/Ultra are Apple7. The fallback `fractal_tree_fallback_vertex` is a full-screen triangle whose fragment brightness follows `bass_dev` and jumps with every onset — the whole-frame flash D-157 removed from the real tree. The planner had no capability gate.

**Fix.** `VisualizerEngine.capableCatalog(_:supportsNativeMeshShaders:)` drops `.meshShader` scenes when the device lacks `.apple8`; `plannableCatalog` feeds the planner (build + regenerate), reactive mode and the Shift+→ walk.

**Gate.** `MeshCapabilityCatalogTests`: stubbed capability (Apple7 drops Fractal Tree, Apple8 keeps it) + source shape (every catalog site reads the gated catalog).

---

### BUG-165 — a streaming song change reset renderer and analysis state from a background thread (2026-09-29)

**Severity:** P1 (memory corruption / crash risk on every streaming song change) · **Domain:** app / concurrency · **Failure class:** `concurrency` · **Status:** Fixed 2026-09-29 (BR.3, `1fb1dbe4` + `773f6a24`). TSan-clean under stress. Not user-observable on demand (the audit could not measure a crash frequency), so there is no live check; BUG-085's unexplained ~3.6 min freeze stays a lead, not a closure.

**Expected.** Renderer and geometry state is touched only by the render loop's thread (main); MIR and mood state only by the analysis queue.

**Actual** (audit G1, re-verified ✔︎). `StreamingMetadata` polls on a Swift concurrency pool thread. The engine's track-change closure (`VisualizerEngine+Capture.swift`) wrapped only its UI publish in `Task { @MainActor }`; `mir.reset()`, `pipeline.resetAccumulatedAudioTime()`, `resetPerTrackPresetState()` (Witchlight path, Meniscus surface, Kagura, Skein, Nimbus) and `resetStemPipeline` (mood accumulator, stem series) ran inline on the pool thread. Same closure: unsynchronized reads of `skeinState`, `nimbusState`, `lumenPatternEngine` and a write of `lastResolvedTrackIdentity`.

**Reproduction (instrumented).** `TrackChangeResetStressTests` under `--sanitize=thread`: the render loop advances a `WitchlightPath` on main and MIR runs on an analysis queue while a detached "poller" fires 80 song changes. Resetting inline (the pre-fix shape): **100 ThreadSanitizer data-race reports**, first `WitchlightPath.reset()` (poller) vs `WitchlightPath.advance` → `advanceHarmonicPhase` (render loop).

**Fix.** `TrackChangeResetRouter.route(analysisQueue:analysis:main:)` (engine `Shared`): `mir.reset()` → analysis queue; the publish, renderer clock, identity, per-track preset/geometry and stem-pipeline resets → main, in their old order. `resetStemPipeline`'s `moodAccumulator.reset()` hops to the analysis queue (the local-file callers are on main too).

**Gates.** `TrackChangeResetRouterTests` (called from a detached task: the main closure runs on main, the analysis closure on the analysis queue); `TrackChangeResetStressTests` in `Scripts/tsan_stress.sh` — **VERDICT: TSAN CLEAN, 0 race lines**; `StreamingTrackChangeRoutingTests` (source shape; origin/main's callback fails it).

---

### BUG-169 — one failed track among the first three hid "Start now" (2026-09-29)

*(Numbering: filed as BUG-167 on `br-7`; renumbered to BUG-169 when BR.6a (#320, BUG-167) and BR.6b (#325, BUG-168) merged first.)*

**Severity:** P1 (a common session strands the tester) · **Domain:** session / preparation · **Failure class:** `algorithm` · **Status:** Fixed 2026-09-29 (BR.7, `ad30a7b2`)

**Actual** (audit C2, re-verified ✔︎). `computeReadiness` counted a run of `.ready` tracks from position 1, and any `.failed` or `.partial` track ended it. About 8 % of scanned rows get no verified preview, so roughly one Spotify-scan session in five had a failure in rows 1–3. "Start now" then stayed hidden until every track was terminal: about 3.5 min for 40 tracks, 10 for 100. Only Cancel was on screen, with no explanation.

**Fix.** The prefix counts `.ready` tracks from position 1 and **skips** terminal non-ready ones (`.failed`, `.partial`); only a track still in flight ends it. Only `.ready` counts (PUB.6 unchanged).

**Gates.** `ProgressiveReadinessTests`: one failure at position 0 / 1 / 2 with three ready → `readyForFirstTracks` (red on the old rule, all three); a queued track still ends the prefix; the older cases renamed to the new semantics.

---

### BUG-170 — a playlist over ~64 tracks lost its preparation before it played (2026-09-29)

*(Numbering: filed as BUG-167 on `br-8`; renumbered to BUG-170 behind BR.6a, BR.6b and BR.7.)*

**Severity:** P1 · **Domain:** session / cache · **Failure class:** `resource-management` · **Status:** Fixed 2026-09-29 (BR.8, `6d78eaf3`)

**Actual** (audit C1, re-verified ✔︎). `StemCache.defaultMaxEntries = 64`, evicting LRU. Each entry held ~7 MB of separated stems. Streaming preparation is never paced, so it runs about 30× ahead of playback. On a 120-track playlist, tracks ~6–56 were evicted before they played. They then played live-only: no prepared grid, no planned scene (the plan is built only from cached profiles), and "52 tracks not yet prepared" on screen. Nothing re-prepares an evicted track.

**Fix.** `StemCache.store` keeps each entry **without its stem waveforms** (`CachedTrackData.withoutStemWaveforms()`). Nothing at playback reads them: the cache-hit branch uses the stem features, grids, stem series and profile. The on-disk `PersistentStemCache` is written from the preparation outcome and is unchanged. With small entries, the count cap is now a 2048 safety bound.

**Gates.** `LongPlaylistCacheTests`: 120 tracks stored → all 120 still planned (red at the old 64 cap); stored entries drop the audio but keep the playback fields. Four tests that asserted the in-memory entry held 4 waveforms now assert it holds none.

---

### BUG-153 — a live scan keeps the first, edge-of-frame reading of a row (2026-09-28)

**Severity:** P2 · **Domain:** `session` (playlist scan) · **Failure class:** `algorithm` · **Status:** Fixed `832e8102`, live-verified 2026-09-28 · **Found by:** Matt's SCAN.4 live check · **Related:** D-260, SCAN.1 (`PlaylistScanAccumulator`)

**Expected:** every row in the review list shows the title and artist Spotify shows for it; for TC 27 row 9, "Prizefighter — Youth Lagoon".
**Actual:** Matt, live Release scan of TC 27 2023.12.16 Los Angeles (fixture playlist 3, 38 rows, 15:09:44–15:09:53): *"it just misread one track (Prizefighter - has the wrong artist, which should be Youth Lagoon)."* One row of 38; the other 37 correct by his read. The wrong text itself was not logged (the scan logged frame counts only).

**Reproduction / artifacts.**
- Frame log (`io.uzume.mac`/`SpotifyScan`, 15:09:45–53): rows #1–#7, #1–#7, **#1–#9** (15:09:46.39 — #9 first seen as the frame's bottom row), then #1–#12 onward.
- Fixture captures of the same playlist (`playlist 3`, capture 1): #9 is the bottom row with its artist line cut off (read with an empty artist, confidence 0.5; complete in capture 2). Live, the clip line falls differently frame to frame.
- Mechanism in code: `PlaylistScanAccumulator.add` keeps the held reading unless the new one is *strictly* more confident; Vision reports confidence 1.0 for most text, including text cut by the frame edge. So a clipped but confidently misread artist, seen first, is never replaced by the ~10 complete readings that follow.

**Suspected failure class:** `algorithm`.

**Verification (written before the fix).**
1. Automated: an accumulator test where a row's first reading comes from a frame edge with a wrong artist and later interior readings agree on the right one — the review keeps the right one; and a one-off misread among agreeing readings loses. The fixture gate (`PlaylistScanFixtureTests`) must not lose any row it had.
2. Manual: Matt re-scans TC 27 in the instrumented Release build; the logged review diffs clean against the CSV (row 9 "Prizefighter — Youth Lagoon").

**Fix (`832e8102`).** Identical readings of a row pool their confidence and the most-supported reading wins (ties: the more confident single reading); a frame's first and last rows count ×0.8 (the last row is whole when the Recommended shelf shows). `PlaylistScanAccumulatorTests.oneOffMisreadOutvoted` fails on the old accumulator ("NikkiR" sticks) and passes now; the fixture gate is unchanged (144/144, 124/125, 0 wrong).

**Verification.** 1. ✅ Automated, above. 2. ✅ Manual: Matt's re-scan (Release, 15:21:30–15:21:36, 22 frames, 5.3 s) — the logged review diffs 38/38 against the Exportify CSV, 0 differing, 0 missing; row 9 "Prizefighter — Youth Lagoon" from 8 readings; row 16 "Nikki" (the offline bench's one misread) also right. The per-row log lines added to diagnose it (`ScanDiagnostics`) were removed after verification; the per-frame timing line stays.

---

### BUG-154 — the network-recovery tests assert before the debounce fires (2026-09-28)

**Severity:** P3 · **Domain:** `test-infra` (UzumeAppTests) · **Failure class:** `concurrency` (a wall-clock wait for async work) · **Status:** Fixed (BUG154.1, `83fb016a`) · **Numbering:** 154, because 152 and 153 are taken by `scan` (merged #305) · **Related:** BUG-150 (same fix shape: await the task, don't sleep), BUG-142

**Expected:** the `NetworkRecoveryCoordinator` tests pass however loaded the machine is.
**Actual:** observed 2026-09-28 in `Scripts/closeout_evidence.sh` on branch `scan` (`6ec6b7e1`): the full app suite failed `test_online_preparing_countsAttempt` with `(recoveryAttemptCount → 0) == 1` and `test_resetForNewSession_resetsCount` with `→ 2 == 3`. The suite then passed 3/3 alone and 491/491 on a full re-run. Every wait slept `recoveryDebounceSecs + 1 s` (3 s) after `setOnline(true)` and asserted. The coordinator's `debounceTask` sleeps 2 s and then hops back to the main actor; under full-suite main-actor load that hop can land after the assert. In the looping tests the next cycle's `setOnline(true)` then cancels the late task, so the count comes up short (`2 == 3`).

**Reproduction.** A 1.5 s extra sleep inside the debounce task (not committed) fails 4 of 7 old tests with the observed shapes (`0 == 1`, `0 == 3`).

**Fix.** `debounceTask` becomes `private(set)` (internal), and each wait is `await coordinator.debounceTask?.value`. The cancellation test captures the task before `resetForNewSession()` and awaits it to its end. The state-guard test used to sleep 50 ms before asserting zero, which would pass even with a broken guard; it now awaits the task too. No budget widened. Production behaviour is unchanged.

**Verification.**
1. ✅ Automated: under the 1.5 s probe the suite passes 7/7 (4/7 failed before). Three consecutive full `xcodebuild -scheme UzumeApp test` runs pass (see BUG154.1 in `ENGINEERING_PLAN.md`); SwiftLint strict clean on both files.
2. Manual: none required (test-only change).

---

### BUG-155 — a seek inside a song made Kagura flick through dozens of dances (2026-09-28)

**Severity:** P3 (a brief rendering artifact on an edge case; it recovers by itself) · **Domain:** `preset.fidelity` (Kagura) · **Failure class:** `algorithm` (the clip-change schedule assumed a continuous playhead) · **Status:** Fixed + live-verified (KAG.5, `90ec6189`; M7 `2026-09-28T22-22-30Z`) · **Found:** Matt's KAG.5 M7, session `2026-09-28T21-31-31Z` · **Related:** LFSEEK.1 (the local-file seek bar), KAG.3

**Expected:** after a seek, the dancer settles at the new position within about a bar, with no pops.
**Actual:** `WIRING: seekLocalFile to=181.6s` in Dance Yrself Clean, from 71 s. Then 36 `KAGURA_PICK` lines between playback 181.61 and 182.20 s: one clip change per frame for 0.6 s.
**Cause:** the next clip change is scheduled as a beat index. A forward seek leaves it behind the playhead, so it fires at once; the next one is planned from the old entry beat, so it fires on the next frame, until the schedule catches up. On a backward seek the scheduled beat lies ahead, so the current clip holds past its end until playback reaches it (0.13 m pose pop in the harness). Pre-existing since KAG.3; the seek bar (LFSEEK.1) made it reachable.
**Fix:** a beat position that moves more than one beat in a frame, either way, is a seek (a playing clock moves ≤ ~0.14 beat per frame). The stranded cut is dropped, and the dancer fades to its rest over one beat, the path a replaced grid already uses. It rejoins at the next bar line from where playback landed.

**Verification.**
1. ✅ Automated: `KaguraRestTests.seekRejoins` jumps +110 s and −40 s mid-clip at 120 BPM. Without the fix: 23 clip changes in one second forward, and a 0.96 m / 0.13 m pose step. With it: one clip change (the rejoin), the rest within two frames, dancing again within a bar, every frame under the per-dance bound, no frozen frames.
2. ✅ Manual: Matt's KAG.5 M7 round 2 (`2026-09-28T22-22-30Z`, *"Looks good"*): two seeks in Dance Yrself Clean (to 98.9 s and 174.4 s), each followed by one rejoin pick 1.6–2 s later, no burst.

---

### BUG-150 — the Spotify connection tests assert before the connect finishes (2026-09-26)

**Severity:** P3 · **Domain:** `test-infra` (UzumeAppTests) · **Failure class:** `concurrency` (a wall-clock wait for async work) · **Status:** Fixed (BUG150.1, `55c62b90`), merged #291 (`5327841f`) · **Numbering:** 150, because 148 and 149 were already taken on `claude/bug148-valence` (merged #290) · **Related:** BUG-143 (the same `closeout_evidence.sh` step), BUG-142 (same fix shape: await the task, don't sleep)

**Expected:** the Spotify connection view-model tests pass however loaded the machine is.
**Actual:** observed 2026-09-25 in `Scripts/closeout_evidence.sh`, with the app tests running straight after the full engine suite: `connectLoginRequiredUnauthenticated` failed at `#expect(vm.state == .requiresLogin)` with `(vm.state → .preview(playlistID: "abc")) == .requiresLogin`. Re-running the suite alone passed 12/12. The test sets `vm.text`, sleeps 1500 ms for the 300 ms debounce, calls `vm.connect`, sleeps 400 ms, then asserts. `runConnect` leaves the state at `.preview` until the connector returns and `applyResult` runs, and the connect path hops off and back onto the main actor twice (the connector, then the OAuth provider actor). On a contended main actor that takes longer than 400 ms. The other connect and login tests in both suites (sleeps of 200–700 ms) and every debounce wait (1500 ms, already widened once "for parallel-suite contention") had the same weakness.

**Reproduction.** Plain CPU load (40 busy loops, 3 runs) did not trip it, because macOS keeps the main thread responsive. The mechanism was confirmed by injecting 500 ms of latency into `MockOAuthConnector.connect` (not committed): 3 of 4 OAuth tests failed, `connectLoginRequiredUnauthenticated` with the exact observed message.

**Fix.** Each wait now awaits the VM's own task: `await vm.debounceTask?.value` after setting `text`, and `await vm.connectTask?.value` after `connect` / `login`. `debounceTask` becomes internal, like `connectTask`, which was already exposed for this reason. `retryOutsideErrorIsNoOp` drops its sleep, because `retry` returns synchronously outside `.error`. No budget was widened, and the suites no longer sleep (about 15 s saved).

**Verification.**
1. ✅ Automated: with 500 ms of latency injected into both mock connectors, both suites pass 16/16 (before the fix, 3/4 OAuth tests failed). Full app suite 476/476; SwiftLint strict clean.
2. Manual: none required (test-only change; the VM's behaviour is unchanged).

---

### BUG-146 — preparation-time mood depends on the file's sample rate (2026-09-25)

**Severity:** P3 (a single song measured; raise if 48 kHz shifts prove common) · **Domain:** `dsp.mir` · **Failure class:** `sample-rate` · **Status:** Fixed (BUG146.2, 2026-09-26) · **Related:** BUG-141 (the same class, in the stem analyzers)

**Evidence.** Superstition, the same shipping local pipeline, with the per-frame median after the first sixth:

| Source | Median arousal | Median valence |
|---|---|---|
| Original FLAC, **96 kHz** | **+0.21** | −0.13 |
| ffmpeg-resampled to 48 kHz | +0.45 | −0.36 |
| ffmpeg-resampled to 44.1 kHz | +0.52 | −0.46 |
| Production chain, 44.1 kHz windows (KAG.0g) | +0.51 | — |

`analyzeMIR` runs a fixed 1024-point FFT at the file's rate. At 96 kHz that means 93.75 fps and 93.75 Hz bins, against ~43 of each at 44.1 kHz. Per BUG-141, about 14 % of the pilot corpus is 48 kHz and about 2 % is 96 kHz.

**Diagnosis (2026-09-26).** `CorpusCensusRunner --dual-rate --window-seconds 120` on Superstition gives the ten mood-feature means at native 96 kHz and resampled to 44.1 and 48 kHz. Shift at 96 vs 44.1 kHz, in scaler σ:

| Feature | Shift (σ) |
|---|---|
| Six band energies | within ±0.23 |
| `spectralCentroid` | **−0.87**: it is normalised by Nyquist, so the same Hz reads half (0.068 vs 0.133) |
| Raw flux | **−0.40**: a sum over twice as many bins, each twice as wide |
| Major key correlation | **+1.62** |
| Minor key correlation | **+1.94**: chroma from 93.75 Hz bins cannot resolve pitch in the low register |

48 kHz sits much closer to 44.1 kHz on every feature. The rate this path should run at is settled by existing decisions: the stems are 44.1 kHz (`StemSeparator.modelSampleRate`, BUG-141), and D-128's sample-rate note records LF analysis at 44.1 kHz. (The DEAM classifier was trained at 48 kHz; that cross-path delta is the ~9 % centroid skew CENSUS.3 measured and D-128 accepts, and it is out of scope here.)

**Verification criteria (before the fix).**
1. Automated: the same synthetic tone mix sampled at 44.1 kHz and at 96 kHz, prepared through `analyzePreview`, stores the same `spectralCentroidAvg` (±5 %) and mood (±0.05). It fails on current code, where the centroid halves.
2. Real file: Superstition's 96 kHz FLAC through the shipping pipeline stores arousal within 0.05 of its 44.1 kHz resample (today 0.21 vs 0.52). Its 48 kHz resample does likewise.
3. Cache schema bump.
4. No change on 44.1 kHz files: the beta-playlist gates (ρ, BPM spread) still pass.

**Fix (BUG146.2).** Before `analyzeMIR`, `analyzePreview` resamples the preview to `StemSeparator.modelSampleRate` with `BeatThisPreprocessor.resample`; 44.1 kHz input passes through untouched. This is an engineering call with no product decision: the rate is the one the stems and D-128 already use. Folded into this branch's schema v16.
**Verification.**
1. ✅ `MIRSampleRateTests`: a tone mix sampled at 44.1 and 96 kHz stores the same centroid and mood. It **failed** on the old code (centroid off 50 %, mood outside ±0.05) and passes.
2. ✅ Real file, Release `PrepTimingRunner`, Superstition. Stored arousal: 96 kHz original **0.494** (was 0.21), 48 kHz resample 0.499 (was 0.45), 44.1 kHz resample 0.517 (unchanged). All within 0.023. **Residual:** valence at 96 kHz is −0.37 vs −0.46 at 44.1 kHz (0.09 apart; it was 0.33 apart). This is the resampling path itself, not diagnosed further.
3. ✅ Cache schema v16.
4. ✅ Beta playlist on the final code: the nine 44.1 kHz songs are unchanged to three decimals; the BPM gate still passes; the BUG-144 ρ **rises 0.855 → 0.927** because Superstition now matches the production chain (0.494 vs 0.51).

---

