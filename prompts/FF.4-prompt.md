# Increment FF.4 — Fireflies: M7 and certification (preset increment)

**Objective.** After this session, Fireflies has been judged live by Matt on the beta playlist and, only if he
passes it, is a certified scene: `certified: true`, reachable by the arrow keys, planned into sessions by
default, and enrolled in every gate scoped to the certified set with real measurements behind each one.
If Matt does not pass it, the session ends with his words recorded, the failure stated in one sentence, and
a recommended next increment. Nothing is fixed without his pick.

The work is mostly **preparation and verification around two live reviews that only Matt can run**: the
local-file M7 (the gate) and one streaming pass on his Spotify mirror (slate §00). The session stops and
waits at each.

**Not here:** any change to the swarm (FF.1), the world (FF.2) or the light (FF.3). Those are accepted and
gated. If the M7 asks for a change to one of them, that is a new increment (FF.5), not a tweak inside this one.

## Skills to invoke

- `preset-session`: at the start. Its escalation thresholds apply to the M7 outcome.
- `session-forensics`: before reading any M7 capture (`~/Documents/uzume_sessions/<timestamp>/`).
- `shader-authoring`: only if a GPU-facing test harness needs editing (Task 1's flash test). No `.metal`
  change is expected in this increment.
- `defect-handling`: if the M7 or a gate surfaces a defect (a `BUG-*`), before any code change.
- `closeout`: at the end, the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## Read first (in order)

1. `docs/presets/FIREFLIES_DESIGN.md`: §1 (the musical role), §2 (the temporal contract: what Matt should
   see), §4.4 "As built" (the light and its known limit).
2. `docs/presets/BETA_TEST_PLAYLIST.md`: the ten songs, what each tests, and how to open the `.m3u`.
3. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` §00 (local-file M7 + one streaming pass before
   certifying) and §2 (the rewatch bar R1–R5).
4. `docs/presets/fireflies_spike/README.md` §4 (how R1–R5 were first read on the spike).
5. `docs/ENGINEERING_PLAN.md`: the FF.3 entry (the evidence this increment starts from) and the
   `ALFVEN.CERT` entry (the certification evidence table to reproduce).
6. `docs/RUNBOOK.md` §"Certifying a scene" and §"Post-session chain analyzer".
7. The memory note on certification: certifying is not a flag flip, it enrols new gates, and a preset whose
   response arrives through CPU geometry renders **static** in the single-pass flash harness (Nebula,
   PR.24).
8. Tests you will touch: `FidelityRubricTests` (`certifiedPresets`, `expectedAutomatedGate["Fireflies"]`),
   `PhotosensitivityCertificationTests` (`multiPassMeasured`), `MultiPassFlashHarnessTests` (one test per
   preset; the Witchlight test for a small-bright-subject precedent), `GoldenSessionTests` (Session C),
   `FirefliesSwarmTests` / `FirefliesSpikeParityProbe`, `FirefliesRenderTests`.

## What this seat already verified (2026-09-26, on `main` at `530ccfe3`)

- **Certifying Fireflies changes one golden plan.** With only `"certified": true` flipped locally,
  `GoldenSessionTests` Session C fails. Its last track opens on Cymatic Resonance instead of Mitosis, even
  though Fireflies is not in the plan (it takes an earlier slot and moves the reuse windows). Every other
  golden and `OrchestratorCertifiedFilterTests` stay green. Regenerate Session C **with a scoring trace**
  (the GOLDEN.1 precedent) at certification; never edit the expectation without the trace.
- **The single-pass flash gate cannot see Fireflies.** It draws only the world fragment with a zeroed
  slot 6, so the fireflies are never drawn. Its `responded` guard will fail loud. Fireflies needs a real
  test in `MultiPassFlashHarnessTests` (`MultiPassRenderHarness.renderFireflies` already binds slot 6 and
  draws the geometry) and a place in `multiPassMeasured` **with the measured numbers in the comment**.
- **The arrow keys cannot reach Fireflies today** (`exclude_from_cycling: true`). There is no pick-by-name
  in the UI. Matt can only see it in the M7 once that flag is gone from the build he runs (Task 2).
- **`certified` gates the planner, the reactive picker and Shift+→ nudges** (`PresetScorer`, unless "Show
  uncertified scenes" is on). **`exclude_from_cycling` gates only the arrow keys and segment advance.**
- The rubric profile is `full` and scores 2/15. Nothing enforces a minimum at certification (RUNBOOK,
  PUB.7). Report it honestly, never re-profile it.

## Pre-flight invariants (each failure stops the session)

- **Base.** `main` at or after `530ccfe3` (FF.3, #289). If `ff-4-prompt` is merged, branch `ff-4` from an
  up-to-date `main`; otherwise from `origin/ff-4-prompt`. Stay in this session's own worktree.
- **Fixtures and drive.** `Scripts/link_fixtures.sh` run. `/Volumes/Extreme SSD` mounted, and `test -r`
  passes on all ten paths in `tools/data/beta_test_playlist.m3u`. The four parity captures and
  `fixturegen-Warszawa_tail` are in `~/Documents/uzume_spikes/fireflies/sessions/`.
- **FF.3 green at the base.** Record the numbers:
  - `swift test --package-path UzumeEngine --filter Fireflies` passes (11 tests);
  - the 20-seed parity probe returns FF.3's means: DYC 0.972 / +0.843, Pyramid 0.975 / +0.812, Warszawa
    0.196 / +0.007, Teardrop 0.137 / −0.008;
  - 1080p D-157 max Δ: DYC 0.0296, Pyramid 0.0374, Warszawa 0.0038, Teardrop 0.0036.
  - ⚠ Run every env-gated probe **filtered, never inside the full suite**.
- **Baseline.** `Scripts/closeout_evidence.sh` at the base commit. If the app step exits 65 with "Could not
  launch UzumeAppTests", a Uzume app is running (BUG-072). Ask Matt to quit it and re-run; never kill it
  yourself.

## Tasks

1. **The pre-M7 packet: the rewatch checks on the real pipeline.** Every check runs through
   `MultiPassRenderHarness.renderFireflies` (the production draw path) or the engine's swarm on real
   captures, never synthetic audio (FA #27).
   - **R1, legible (decoy):** on DYC, the swarm against the true grid vs the same grid shifted half a beat,
     20 seeds each. Report on-beat for both against the chance band. The spike read **+0.86 vs −0.85**. If
     `FirefliesSpikeParityProbe` has no decoy arm, add an env-gated, test-only one
     (`FIREFLIES_DECOY=1`). No change to `FirefliesSwarm`.
   - **R2, per-track identity:** a two-song sheet, DYC | Warszawa (`Scripts/compare_render.sh` with
     `COMPARE_REF_DIR` on the local prints, plus the coherence curves). A verdict: do they read as
     different scenes?
   - **R3, arc:** the coherence curve per capture (random → coherent → on the beat for a clear beat, flat
     for a free one). The whole-song arc (minute 1 vs minute 4) is judged live in the M7, so name it in the
     request.
   - **R4, novelty:** one sentence. Emergent simulation; the lock time and phase path differ per track
     and per seed.
   - **R5, restraint:** 1080p D-157 on the four captures (FF.3's numbers are the baseline) and the
     Warszawa-tail silence film with a `Scripts/motion_gate.sh` verdict. **Plus the WCAG gate, measured
     now rather than at certification:** add `firefliesIsFlashSafe` to `MultiPassFlashHarnessTests`
     through `renderFireflies`, and report flashes/s and the response range. It must clear the
     `responded` floor on a render that actually flashes (a locked unison, not a free swarm on an
     untimed drive; see the Witchlight test for settle length). The test is not keyed on `certified`, so
     it can land before the M7. 0.00 flashes/s is required.
   - Put large outputs on `/Volumes/Extreme SSD/uzume_spikes/fireflies/ff4/` (the internal disk is ~90 %
     full); keep logs and sheets under `~/Documents/uzume_spikes/fireflies/ff4/`.
   - **Done-when:** a table in the transcript, R1–R5 each with its number or verdict and its source, and
     the flash test green with its numbers.
   - **If R1 fails** (no measurable separation from the decoy) **or the WCAG test flashes:** stop and report.
     Do not request an M7 on a scene that fails its own restraint or legibility check.

2. **Make Fireflies reachable for the M7.** In its own commit: remove `exclude_from_cycling` from the
   sidecar, fix the sidecar `description`'s last sentence (still "Not certified"; drop "excluded from manual
   cycling"), and update `FIREFLIES_DESIGN.md` (status line, §6 Rotation). `certified` stays `false`.
   - This must reach **the build Matt runs** (primary `main`). Open a small PR and ask for "yes, push".
     After it merges, Matt pulls and builds the primary checkout.
   - **Done-when:** the PR is merged, and Matt confirms his build contains it. Name the commit and the app
     path he should launch (never a globbed DerivedData path).

3. **HARD STOP: Matt's local-file M7.** Write the M7 request in his terms, then **stop and wait**.
   - **How to run it:**
     - Open `tools/data/beta_test_playlist.m3u` (Local files → Playlist, or drag it onto the window).
     - On each track, press → until Fireflies shows. A manual pick holds only until the next track
       (LFPLAN.3), so it has to be picked again on every song.
     - Play each song long enough to see it settle. DYC needs its whole near-hush and the drop.
   - **What to look for, per song** (from the design's temporal contract and the playlist doc):
     - **DYC:** about three minutes of near-hush (a few stragglers, the meadow lit and moving), then the
       drop. The swarm finds the beat within ~15 s and flashes as one on it.
     - **B.O.B., Take Five, Smells Like Teen Spirit:** a clear beat, so they lock. Take Five's 5/4: does the
       unison sit on the music?
     - **Pyramid Song, Warszawa:** free; scattered clusters and relays, never a unison on a beat.
     - **Superstition, Penny Lane, Teardrop, Moonlight I:** flagged beat-irregular in the census, so free.
       Does "free" still read as connected to the music (the world breathing)?
     - **Whole-song arc (R3):** does minute 1 differ from minute 4?
   - **Watch in particular (FF.3's open risks):**
     - Does the brighter unison (about 3× FF.2's frame-to-frame change, inside D-157) read as the whole
       meadow pulsing, or as hundreds of lights?
     - The nearest trunks stay dark beside a light.
     - The soft near discs: too photographic?
     - The starburst only shows on the brightest lights.
   - Ask one question: **does Fireflies pass M7?**
   - **Done-when:** Matt's verdict, verbatim, in the transcript.

4. **Read the M7 captures, then record the outcome.** Read the session dirs (`session-forensics`):
   - the `chain_health.json` verdict (**`clean` required**; a `degraded` capture is flagged and re-captured,
     never certified on);
   - fps median, GPU p50/p95 against 16.6 ms, drawable failures and unpresented frames;
   - per song, `stems.beatClarity01` and whether the swarm locked (coherence or on-beat, if logged; else say
     "cannot verify" and name the missing diagnostic);
   - the near-silent span on DYC.
   - **On a reject, or "not yet":** record his words. Write the one sentence "what I now believe is wrong".
     Recommend the next increment (FF.5) at the product level, with a default. Then **stop**. Do not fix
     anything he has not picked. Two consecutive M7 rejections whose cause you cannot articulate are a
     `preset-session` escalation.
   - **On a pass:** continue to Task 5.

5. **HARD STOP: the streaming pass.** Ask Matt for one pass on his Spotify mirror of the same ten songs
   (slate §00: once per scene, before certifying).
   - What differs on streaming, for him to watch: stems arrive ~2.5 s late, which Fireflies barely uses. The
     beat grid and clarity come from the same analysis. Near-silence depends on the tap.
   - After his pass, read the capture: chain health is required, and a silent tap goes through the
     streaming-tap runbook first. **Stop and wait** for his verdict.
   - **Done-when:** his streaming verdict, verbatim. A reject here is handled like Task 4's reject.

6. **Certify (only after both passes).** Each step is measured and run, not just listed:
   - `Fireflies.json`: `"certified": true`. The `description` loses "Not certified" and says what is true
     (BUG-138).
   - `FidelityRubricTests`:
     - add `"Fireflies"` to `certifiedPresets`;
     - keep `expectedAutomatedGate["Fireflies"]` at the **measured** value;
     - rewrite its stale comment ("FF.1 is BEHAVIOUR ONLY …") to explain the `false` (the Membrane /
       Filigree precedent: a non-PBR look with no `mat_*` calls).
   - `PhotosensitivityCertificationTests.multiPassMeasured`: add `"Fireflies"` with Task 1's numbers in the
     comment. Never without them.
   - `GoldenSessionTests` Session C: regenerate with a scoring trace in the comment. Re-run all goldens and
     `OrchestratorCertifiedFilterTests`.
   - Run the RUNBOOK battery:
     `--filter "FidelityRubric|Photosensitivity|MultiPassFlash|RouteCoverage"` (both routes green).
   - `docs/VISUAL_REFERENCES/fireflies/README.md`: score the rubric checklist by hand, honestly (the
     Membrane precedent: an item counts as "adapted" only where the look really delivers it; the rest are
     N/A). The profile stays `full`.
   - **Done-when:** the battery and the full engine suite are green, and every changed expectation carries
     its evidence in a comment.

7. **Docs.**
   - `ENGINEERING_PLAN.md`: the FF.4 row, and a completed entry with the `ALFVEN.CERT` evidence table
     (Matt's quote and session ID, chain health, duration and frames, fps, GPU p50/p95, drawable failures,
     routes, and deviations accepted at certification).
   - `RENDER_CAPABILITY_REGISTRY.md`: the Fireflies rows lose "`certified: false`". The flash-gate row's
     count is stale ("15/15" while 25 are certified): correct it and name Fireflies' measurement.
   - `FIREFLIES_DESIGN.md`: the status line.
   - `BETA_SCENE_SLATE_2026-09-24.md` §1: the roster count (25 → 26) and the particles family.
   - `RELEASE_NOTES_DEV.md`: an entry (the Nebula precedent).
   - Optionally, add `"FF": "Fireflies"` to `DocIntegrityTests.incrementPrefixPreset` so FF rows are
     checked like other scene lanes.
   - **Done-when:** `DocIntegrityTests` green.

## Do NOT

- **Do NOT change the swarm, the world or the light.** No constant, route or look change. Parity, D-157 and
  the FF.3 still are the gates, and an M7 note that asks for a change becomes FF.5.
- **Do NOT certify without both of Matt's passes** (local M7 and streaming), and never on a `degraded`
  capture. The automated gates are the floor; M7 is the bar.
- **Do NOT add Fireflies to `multiPassMeasured` without a real measurement** (the vacuous pass the gate
  exists to stop), and do not widen `responsiveLumaRange`, D-157, the frame-budget nets or any flash
  threshold.
- **Do NOT edit a golden expectation without a scoring trace**, or change `rubric_profile` to pass.
- **Do NOT fix M7 findings Matt has not picked.** His feedback is observations, not work orders. Diagnose,
  recommend, wait.
- **Do NOT kill or relaunch Matt's running app**, and never launch a globbed DerivedData path.
- **Do NOT use synthetic audio as evidence** (FA #27), or close a felt question on anything but a real
  capture.
- **Do NOT commit, copy, trace or reproduce any print**, or name the artist in user-facing text.
- **Do NOT push without Matt's explicit "yes, push".** Push to a branch and open a PR; never push to
  `main`. If any push prints `Bypassed rule violations for refs/heads/main`, say so immediately.

## Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build
swift test --package-path UzumeEngine
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test
swift test --package-path UzumeEngine --filter Fireflies
swift test --package-path UzumeEngine --filter "FidelityRubric|Photosensitivity|MultiPassFlash|RouteCoverage"
swift test --package-path UzumeEngine --filter "GoldenSession|OrchestratorCertifiedFilter"
FIREFLIES_PARITY=1 FIREFLIES_SEEDS=20 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine --filter FirefliesSpikeParityProbe
FIREFLIES_PARITY=1 swift test --package-path UzumeEngine --filter "FirefliesRenderTests/spikeCapturesAt1080p"
FIREFLIES_SILENCE_OUT=<dir> swift test --package-path UzumeEngine --filter "FirefliesRenderTests/silenceFilm"
Scripts/motion_gate.sh fireflies <film-dir>
COMPARE_REF_DIR=<local folder of prints> Scripts/compare_render.sh fireflies <frames-dir>
Scripts/analyze_session_chain.sh ~/Documents/uzume_sessions/<timestamp>
Scripts/closeout_evidence.sh
```

⚠ The DOC.6 rotation gate flips at UTC midnight (19:00 CDT). If `DocIntegrityTests` goes red on "entries
older than 14 days", run `Scripts/rotate_docs.sh` and commit that alone as `[DOC.6]`.

## Commits (on `ff-4`, local, small, one per step)

- `[FF.4] Tests: Fireflies WCAG flash measurement (+ R1 decoy arm)`
- `[FF.4] Presets: Fireflies reachable by the arrow keys (exclude_from_cycling removed)`: its own PR,
  before the M7
- `[FF.4] Presets: Fireflies certified`: after both passes
- `[FF.4] Tests: certified tables, multiPassMeasured, Session C golden (with trace)`
- `[FF.4] docs: plan row + entry, registry, design status, slate count, release notes`

End each commit message with the attribution line the harness gives you. Push only on Matt's "yes, push",
to a branch plus a PR.

## Closeout

Invoke the `closeout` skill: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as
§2. Add:
- the R1–R5 table with sources;
- Matt's M7 and streaming verdicts, verbatim, with session IDs and chain-health verdicts;
- the live performance numbers (fps, GPU p50/p95, drawable failures);
- the WCAG flash numbers and the D-157 table, FF.4 against FF.3;
- the certified-gate list and what each measured;
- the Session C golden, before → after, with its trace;
- the rubric, reported honestly;
- a one-line statement of which dispatch path the render tests exercised.

## DECISION — none open before the session

The M7 is the decision, and it is Matt's alone (Tasks 3 and 5). One engineering call is made here, not
brought to him: `exclude_from_cycling` comes off **before** the M7 (Task 2), because it is the only way his
build can show the scene. It is still uncertified, so it stays out of default session plans.
