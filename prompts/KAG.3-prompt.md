# Increment KAG.3 — Kagura: five dances, dance selection, the safety nets (preset increment)

**Objective.** After this session Kagura dances all five dances and chooses between them the way Matt
approved in the spike, and it is ready for his live look:
- the song's **tempo and arousal pick a three-dance repertoire** at track start (KAGURA_DESIGN §6 items 1–2);
- at each clip change the **bar-level bass energy of the bar just played picks** the calm, middle or
  vigorous dance of the three (§6 item 3; Matt chose this timing, 2026-09-25 — see DECISION below);
- **arm reach** swells and settles by at most ±25 % with the smoothed bass (§8);
- the dancer **sways** through beat-irregular stretches (the per-section grid-CV safety net, §7) and through
  **silence** (§3a);
- the sidecar declares `requires_regular_beat: true` and a QG.1 `audio_routes` manifest.

The gate is: the arousal-source check first; the repertoire table reproduced on the beta playlist; pulse lock
per dance against the spike on the same captures; `RouteCoverageTests` green; and then **Matt's M7 on the
beta playlist (local files), followed by the streaming pass**. The session ends with the M7 request. It does
not certify (KAG.4).

**Built already (KAG.2, #274):** `KaguraBeatClock` (grid + continuous `p(t)`), `KaguraChoreographer` (warp,
bar-line clip changes, handoff, sway, causal leash), `KaguraDancer` (look B), the wiring
(`installBeatGrid`, `bindKaguraRuntime`), and the twist's replay pulse-lock test. The KAG.1 clip resource
already carries all five dances with their pulse maps, allowed levels and vigor.

## Skills to invoke

- `preset-session` — **before** opening any `.metal` file or editing the sidecar (the scene session-start
  checklist, the Audio Data Hierarchy, FA #67 one primitive per layer).
- `shader-authoring` — before any `.metal`, render pass or GPU-facing Swift. (Arm reach is CPU-side and no
  shader change is expected; invoke it if one turns out to be needed.)
- `beat-sync-session` — **only if** the safety net or the silence rest leads you to touch `BeatGrid`,
  `LiveBeatDriftTracker`, `assessBeatIrregularity` or D-154's thresholds. The expectation is that it does not.
- `closeout` — at the end: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## Read first (in order)

1. `docs/presets/KAGURA_DESIGN.md`: §3, §3a, §6 (including the 2026-09-25 correction and the one-bar note),
   §7, §8 (arm reach), §9 (including the schema note), §10, §11 (the KAG.3 row is the scope boundary), §12, §14.
2. `docs/presets/kagura_spike/README.md` §7–§11: the five dances and their pulse-lock figures, the repertoire
   rule and its tables, the beta-playlist calibration, the safety net's measured CV bands.
3. `docs/presets/kagura_spike/kagura.py`: `DANCES`, `ENERGY_REFERENCE`, `song_energy`, `dance_profile`,
   `pick_repertoire`, `GRID_CV_SWAY`; in `build_dancer`, the arm-reach `scale_of` block and the `family ==
   "auto"` branch; in `beat_events`, the `wrists` and `gesture` branches; in `cmd_film`, the per-segment
   pulse block (for gesture dances it detects **raw landings** in the output, not the re-fitted lattice).
4. The KAG.2 code you are extending:
   - `Renderer/Geometry/Kagura/KaguraChoreographer.swift`, `KaguraBeatClock.swift`, `KaguraDancer.swift`;
   - `UzumeApp/VisualizerEngine+Presets.swift`: `bindKaguraRuntime`, `installBeatGrid`, `pushKaguraGrid`;
   - Tests: `KaguraDancerTests`, `KaguraPulseLockReplayTests`, `KaguraSpikeDetector`, `KaguraFixture`.
5. Where the song-level inputs live:
   - `TrackProfile.mood.arousal`: `Session/TrackProfile.swift`, filled by `SessionPreparer+Analysis.swift`
     (offline MIR); the app reads it through `sessionManager.cache.trackProfile(for:)`
     (`VisualizerEngine+Orchestrator.currentTrackProfile()`, `VisualizerEngine+Stems.swift` near its
     `profile.mood.arousal` read).
   - `Shared/LoudnessProfile.swift` (what the local-file pre-analysis does carry; see the §6 correction).
   - `PrepTimingRunner` (runs the shipping `LocalFilePreparationPipeline` offline over a file list).
6. The D-154 path the sidecar flag joins: `PresetScorer.swift` (the `requiresRegularBeat` exclusion),
   `docs/QUALITY/KNOWN_ISSUES.md` BUG-140 (resolved: Superstition is no longer flagged), and
   `Membrane.json` (the one existing `requires_regular_beat` sidecar).
7. QG.1: `docs/SHADER_CRAFT.md` §17.1 (the `audio_routes` schema; kinds are continuous / accent / structural /
   gate) and `RouteCoverageTests`.

## Pre-flight invariants (each failure stops the session)

- **Base.** Branch `kag-3` from an up-to-date `main` that contains KAG.2: `git log --oneline -1 --
  UzumeEngine/Sources/Renderer/Geometry/Kagura/KaguraChoreographer.swift` prints a `[KAG.2]` commit.
- **KAG.2 is green.** `swift test --package-path UzumeEngine --filter Kagura` passes (24 tests in 6 suites at KAG.2; the motion-sequence test is a no-op without `RENDER_VISUAL=1`).
- **Fixtures.** Run `Scripts/link_fixtures.sh` first. The three route-coverage captures and their
  `beat_this_reference` JSONs must be present.
- **Beta-playlist material.** `~/Documents/uzume_spikes/kagura/sessions_beta/` holds the 30 production-chain
  captures (`fixturegen-bNN_p20|p50|p80`), and the audio in `tools/data/beta_test_playlist.m3u` is reachable
  (`/Volumes/Extreme SSD` mounted). Without them tasks 1 and 3 cannot be measured: stop.
- **The spike runs.** `~/Documents/uzume_spikes/kagura/.venv/bin/python docs/presets/kagura_spike/kagura.py
  --help` works. It is the oracle: run it before theorising.
- **Baseline.** `Scripts/closeout_evidence.sh` is green at the base commit. Timing and performance gates fail
  under load when another session's suite runs at the same time. If a baseline test fails, re-run it
  isolated and record both results. Do not "fix" it here.

## Tasks

1. **The arousal-source check (first, before any selection code).** `ENERGY_REFERENCE` is the median of
   per-frame `FeatureVector.arousal` over three 30 s production-chain windows per beta song. The build will
   read `TrackProfile.mood.arousal`. Show whether they agree.
   - Compute `TrackProfile.mood.arousal` for the ten beta songs through the shipping preparation path
     (`PrepTimingRunner` / `LocalFilePreparationPipeline`; Release build, and never alongside a CENSUS run).
   - Compare, song by song, against the README §10 medians, and compare the **ranks** (the reference is used
     as a rank, `song_energy`).
   - **If the ranks agree** (Spearman ρ ≥ 0.9 and no song moves across a repertoire boundary), keep
     `ENERGY_REFERENCE` as the spike's constant.
   - **If they do not**, re-derive the reference from the ten `TrackProfile` values (§6 authorises this), and
     re-run the repertoire table (task 3) on the new reference.
   - The CENSUS `arousal` column is on a different scale; do not use it (README §10).

   **Done-when:** a table in the closeout (song | README §10 median | `TrackProfile` arousal | both ranks) and
   the decision. **STOP AND REPORT** if `TrackProfile` arousal cannot be produced offline for the ten songs, or
   if re-deriving would move more than three songs to a different repertoire. That changes what Matt approved.

2. **Song-level inputs into the geometry.** Push to `KaguraDancer` as plain data, the same way KAG.2 pushes
   the grid:
   - **song arousal** (from task 1's source) at track start, on both paths, re-pushed when the profile arrives
     late (streaming prefetch). Clear it on every track change (the `@Published`-style trap in CLAUDE.md
     §What NOT To Do applies to any per-track value: write-or-clear it on every path that changes the track).
   - **grid BPM** already arrives with the grid (`KaguraGrid.beatPeriod`).
   - With no arousal yet, use the middle of the reference (energy 0.5) until it arrives, then re-pick the
     repertoire at the next bar line.

   **Done-when:** a unit test shows the pushed arousal reaching the repertoire, and that a track change clears
   it before the next track's value arrives.

3. **The repertoire (§6 items 1–2).** Port `dance_profile`, `song_energy` and `pick_repertoire` verbatim
   (FA #73). The profile inputs (vigor, pulse period, allowed levels) come from the KAG.1 manifest, which the
   KAG.1 bake reproduced from the spike (`--check`).

   **Done-when:** `KaguraRepertoireTests` reproduces the README §10 "Repertoire after" column for all ten beta
   songs **exactly**, from their README arousal and grid BPM (or from task 1's re-derived reference, with the
   new table in the closeout), and README §9's table for the nine spike songs.

4. **The dance pick at each clip change (§6 item 3).**
   - The signal: `bass_att` through a 1.5 s EMA (the spike's envelope), per-bar mean, ranked against the
     song's own distribution. A trailing running rank over the last ~60 s, primed from the first bars, on both
     paths (the §6 correction: no whole-track `bass_att` exists).
   - The window: **the bar just played**, on both paths (Matt, 2026-09-25, option A). No read-ahead, not even
     on local files.
   - Terciles pick calm / middle / vigorous within the repertoire, ordered by vigor. Each dance alternates its
     clips. **No anti-repeat or variety term** (Matt: "follow the song's energy").
   - Clip changes keep KAG.2's rules (bar lines, at most 4 bars, sooner if the pulse map runs out; every 4
     beats with the bar declined), the one-beat handoff and the ankle-midpoint placement. Level `m` per dance
     from its own allowed levels (`choose_level`).

   **Done-when:** `KaguraDancerTests` extended: the pick follows a synthetic energy staircase tercile by
   tercile; a loud stretch keeps the vigorous dance (no rotation); every handoff between any two of the five
   dances and the sway stays under a **per-dance** continuity bound. The bound is each dance's native maximum
   per-frame joint step (at 60 fps: twist 0.030/0.040, cabbage 0.034/0.046, chicken 0.044/0.054, macarena
   0.071, Egyptian 0.043/0.034, sway 0.055) × its fastest measured local warp rate × 1.25. A teleport control
   must exceed it.
   Report, per beta capture, how often the build's pick agrees with the spike's `--family auto` sequence on
   the same capture. This is a report, not a gate; the spike ranked a 30 s window with lookahead.

5. **Arm reach (§8).** Elbow and wrist offsets about the shoulder scale by `1 + 0.25·tanh(...)` of the
   song-normalised 1.5 s bass envelope. The spike normalised by the window's p10–p90; use a trailing running
   p10–p90 (same ~60 s window as task 4). **Legs are never scaled** (a scaled planted foot drags; spike §3).
   One primitive per layer (FA #67): arm reach and the dance pick both read `bass_att`, but at different
   timescales (~1.5 s continuous vs per bar). State that in the routing table.

   **Done-when:** a test shows the arm-length ratio bounded in [0.75, 1.25], the leg joints bit-identical with
   and without reach, and foot-slide on the three route-coverage captures within 10 % of KAG.2's
   (21.9 / 25.2 / 23.1 cm/s, spike `foot_slide` on a `KAGURA_DUMP`).

6. **The per-section grid-CV safety net (§7).**
   - The coefficient of variation of the last 16 grid inter-beat intervals, evaluated as the dance advances.
     Above **0.08** it sways (joining at the next bar line with the usual crossfade). It rejoins at a bar line
     once the CV has stayed below a hysteresis level for a measured span. Choose both, and justify them from
     the README §11 bands.
   - A declined bar is **not** a reason to sway (D-210).
   - Do not change `requires_regular_beat` semantics, D-154's thresholds or `assessBeatIrregularity`.

   **Done-when:** on the 30 beta captures (the grid built from each capture, as the spike did), the dancer
   sways on Pyramid Song, Moonlight I, Warszawa's 80 % window and Dance Yrself Clean's intro, and dances on the
   steady songs; a table in the closeout against README §11. A committed unit test covers the hysteresis on a
   synthetic grid that turns irregular and back.

7. **The silence rest (§3a).** When the bass envelope stays under a floor for a full bar, crossfade at the next
   bar line to the sway; return at the first bar line after energy comes back. The sway never freezes.
   - The floor must separate real silence from quiet music that still has a beat. Measure it: a track end or
     pause from a recorded local-file session (silence is reachable on this path since BUG-130), against the
     quietest beat-bearing beta window (Penny Lane).
   - This mechanism is grounding level 3 (§12); M7 judges it.

   **Done-when:** a test drives silence → music → silence on real feature rows and shows sway → dance → sway at
   bar lines; the floor and its measurement are in the closeout.

8. **Pulse lock per dance.** Port the spike's `wrists` branch and `cmd_film`'s raw-landing gesture detector
   into `KaguraSpikeDetector` **verbatim** (pin each to scipy's output on a known signal, as KAG.2 did for
   `_extrema`). Extend `KaguraPulseLockReplayTests` to force each dance in turn over the three route-coverage
   captures (true grid and +½-beat decoy).
   - **The gesture dances do not lock like the twist.** Spike, Billie Jean: chicken 42 % on the beat + 38 % on
     the "and"; macarena 55 %, skewed early; Egyptian walk 47 % + 53 % on the "and"; cabbage 100 %. Do not
     assert 90 % for them.
   - First run the spike on the same three captures for each dance (`kagura.py film <capture> none /dev/null
     --family <dance> --metrics-only`, with and without `--shift-beats 0.5`), as KAG.2 did for the twist.
   - The assertion per dance and capture: the build's on-beat fraction, and its on-beat + half-beat fraction,
     each no more than **10 points below the spike's** on the same capture; and the decoy moves the on-beat
     share toward the half-beat. Set thresholds from your first measurement, with a stated margin.

   **Done-when:** the replay passes for all five dances on all three captures. **STOP AND REPORT** if any dance
   measures more than 10 points below the spike on any capture. Do not tune toward the number.

9. **Sidecar + routes.**
   - `"requires_regular_beat": true`.
   - `audio_routes` (QG.1 schema): declare only what the code reads, audit first (a declared route the code
     does not read is as wrong as an undeclared one). Expected: `bassAtt` `continuous` for `arm_reach` and for
     `dance_pick`.
   - The grid-driven rows (moves on the beat, clip-change timing) have **no schema kind** (§9 note). Do not add
     one and do not misdeclare them as `accent`; they are gated by `KaguraPulseLockReplayTests`. Record this in
     §9. The repertoire reads `TrackProfile`, not a `FeatureVector` field; it is not declarable either.
   - The `description` names no identifier the scene does not read (`SidecarDescriptionDriftTests`).
   - `certified` stays `false`.

   **Done-when:** `RouteCoverageTests` and `SidecarDescriptionDriftTests` pass with Kagura enrolled.

10. **STOP AND REPORT if any golden session plan changes.** `certified: false` keeps Kagura out of the planner
    (`PresetScorer`), so `requires_regular_beat` must not move a golden plan. Do not regenerate goldens.

    **Done-when:** `swift test --package-path UzumeEngine --filter GoldenSession` passes with no golden file
    edited.

11. **Look + motion evidence, and the M7 request.**
    - `RENDER_VISUAL=1` sequences (`KaguraMotionSequenceTests`) on the three captures in `auto` mode, plus one
      forced sequence per dance. Then `Scripts/compare_render.sh kagura` with the verdict table (the
      anti-reference row is mandatory) and `Scripts/motion_gate.sh kagura` per sequence, read as sequences.
      Gate the spike's own `final_h/` films the same way as the reference.
    - Frame cost in **Release**, with the build configuration stated (TESTREL.1's `swift test -c release
      --enable-testable-imports` if it has merged; otherwise KAG.2's throwaway-package method).
    - Write the M7 request for Matt: the beta playlist as local files first, then a streaming pass. Say what to
      look for, in his terms: do the moves land on the beat (R1)? Do calm and energetic songs get different
      dances (R2)? Is the sway right on Pyramid Song and in silence? Does the macarena read as early? Name the
      tracks to play and the build to use.

    **Done-when:** the sheet, gate outputs and verdicts exist and are read; the Release cost is recorded; the M7
    request is in the closeout.

12. **Docs.** ARCHITECTURE Module Map rows for any new file; the RENDER_CAPABILITY_REGISTRY row updated
    (five dances, selection, safety nets); `ENGINEERING_PLAN.md` KAG.3 row with evidence, marked **pending
    M7**; `KAGURA_DESIGN.md`: what the build settled (the arousal source, the pick window and distribution,
    the CV hysteresis, the silence floor), and the §12 grounding rows updated.

    **Done-when:** `swift test --package-path UzumeEngine --filter DocIntegrityTests` passes.

13. **Closeout** (see below).

## Do NOT

- Do not certify, add Kagura to `certifiedPresets`, or enrol it in `PhotosensitivityCertificationTests`. That
  is KAG.4.
- Do not change the clips, windows, pulse maps or `bake_clips.py` (the KAG.1 resource is fixed). If a dance
  seems to need different data, stop and report.
- Do not add an anti-repeat, variety or rotation term to the dance pick (Matt, KAG.0f).
- Do not add a route kind, misdeclare the grid rows, or touch D-154's thresholds, `assessBeatIrregularity`,
  `BeatGrid`, `LiveBeatDriftTracker` or the drift tracker's lock logic.
- Do not use the CENSUS `arousal` column (a different scale), and do not tune `ENERGY_REFERENCE` by hand. It
  is a constant with provenance (§6).
- Do not drive anything from raw live onsets or from `beatPhase01` (BUG-096). Do not use a per-frame decay
  constant (BUG-097). Do not brighten anything on the beat (D-157).
- Do not regenerate goldens (task 10).
- Do not push without Matt's explicit "yes, push". When approved, push the branch and open a PR. **Never push
  to `main`.**

## Verification

```bash
swift test --package-path UzumeEngine --filter "Kagura"
```
```bash
RENDER_VISUAL=1 swift test --package-path UzumeEngine --filter KaguraMotionSequence
```
```bash
Scripts/compare_render.sh kagura
```
```bash
Scripts/motion_gate.sh kagura
```
```bash
swift test --package-path UzumeEngine --filter "RouteCoverage|GoldenSession|PresetLoaderCompileFailure|FidelityRubric|PresetAcceptance|SidecarDescriptionDrift|PresetSidecarKeyGate|MultiPassFlashHarness|PresetFrameBudget"
```
```bash
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
```
```bash
swiftlint lint --strict --config .swiftlint.yml
```
```bash
Scripts/closeout_evidence.sh
```

## Commits (local; small, one per step)

- `[KAG.3] Renderer: Kagura song inputs (arousal push) + repertoire`
- `[KAG.3] Renderer: Kagura dance pick, five dances, per-dance levels`
- `[KAG.3] Renderer: Kagura arm reach`
- `[KAG.3] Renderer: Kagura grid-CV safety net + silence rest`
- `[KAG.3] Presets+App: Kagura sidecar routes + requires_regular_beat, arousal wiring`
- `[KAG.3] tests: repertoire, per-dance pulse lock + decoy, safety nets, continuity`
- `[KAG.3] docs: Module Map, capability registry, EP row, design notes`

## Closeout

Invoke `closeout`: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Add:
- **The arousal-source table** (task 1) and the decision.
- **The repertoire table** reproduced on the beta playlist, beside README §10.
- **Pulse lock per dance and capture:** on-beat %, half-beat %, n and chance (25 %), beside the decoy and the
  spike's figures on the same capture.
- **The safety-net table** on the 30 beta captures, beside README §11; the silence floor and how it was
  measured.
- **Pick agreement** with the spike's `auto` sequences (a report).
- **§3:** the compare sheet and verdict table; the motion-gate verdicts, spike counts and paths.
- **The Release frame cost**, with the build configuration stated.
- **Which dispatch path the tests exercised** (the production `KaguraDancer.update` → `render` path, with the
  app tick's push order).
- **Status:** "pending live M7". The M7 request for Matt (task 11) goes at the end.

## DECISION (answered — Matt, 2026-09-25: **A**)

**When the music gets louder, should Kagura switch to a more vigorous dance on that bar, or one bar later?**

- **A — one bar later, the same everywhere (recommended).** At each dance change Kagura looks at the bar that
  just played. A loud chorus gets the vigorous dance starting one bar in. Local files and streaming behave the
  same, which keeps the local M7 a true preview of streaming.
- **B — on the bar for local files, one bar later when streaming.** For local files Kagura reads ahead in the
  pre-analysed track, the way the spike films you approved did, so the vigorous dance lands with the loud bar.
  Streaming cannot see ahead, so it stays a bar late there. The two paths then behave differently, and the
  read-ahead uses the bass instrument's own track rather than the overall bass, which the spike never tested.

Dance changes come every two to four bars, so under A a change lags the music by at most one of those bars.
Under B, local files match the approved films more closely.

**Matt chose A.** Build the pick from the bar just played, identically on both paths. Do not read ahead.
