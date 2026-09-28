# Increment FF.5 — Fireflies: patches take turns, a smooth glow, then M7 and certification (preset increment)

**Objective.** After this session, Fireflies no longer flashes as one whole meadow. On a clear beat the
meadow organises itself into 2–4 patches that take turns flashing on the beat, so a flash walks across
the meadow beat by beat. Each firefly's glow is a smooth yellow-green light instead of a one-pixel
stipple. Matt has accepted that on a film, judged it live in an M7 and on one streaming pass, and, only
if he passes both, it is certified with every certified-set gate measured.

This answers FF.4's M7 (2026-09-28), which Matt did not pass:
- testers found the unison *"overwhelming"* and wanted *"some level of orchestration across the firefly
  swarm, so it looks like a coordinated rhythm"*;
- Matt: *"It's everyone at once — go with option A"*;
- Matt: *"fireflies look pixelated"*, and he picked *"A"*, a smooth glow.

His exact words and the options he chose from are in `docs/presets/FIREFLIES_DESIGN.md` §1a. Build to
those words, not to a metaphor of your own (D-188).

**Not here:** the world (composition, inks, camera, breath: FF.2), the light pools, depth of field and
occlusion (FF.3), and the free swarm on an unclear beat (FF.1). All stay exactly as they are.

## Skills to invoke

- `preset-session`: at the start, before any `.metal` or sidecar edit. Its escalation thresholds apply
  to the look check and the M7.
- `shader-authoring`: before editing `fireflies_sprite_fragment` (Task 3).
- `session-forensics`: before reading any M7 or streaming capture.
- `defect-handling`: if a gate or the M7 surfaces a defect (a `BUG-*`), before any code change.
- `closeout`: at the end.

## Read first (in order)

1. `docs/presets/FIREFLIES_DESIGN.md`: §1 and §1a (the new musical role and Matt's decisions), §2 (the
   temporal contract, including the corrected near-silence row), §4.4 (the light; its "as built" note is
   superseded for the glow), §5 row 1, §8 (the patches-collapsing risk).
2. `docs/ENGINEERING_PLAN.md`: the FF.4 entry (the M7 evidence and the pre-M7 packet you will re-run).
3. `prompts/FF.4-prompt.md`: Tasks 3–7. You reuse them for the M7, the streaming pass and the
   certification. Its per-song expectations are corrected in Task 7 below.
4. `docs/presets/fireflies_spike/README.md` §2–4 (the model, and how R1–R5 were first read).
5. Code you will change: `UzumeEngine/Sources/Renderer/Geometry/FirefliesSwarm.swift` (the model) and
   `fireflies_sprite_fragment` in `UzumeEngine/Sources/Renderer/Shaders/Fireflies.metal`.
6. Tests you will touch: `FirefliesSwarmTests` (fixture gates, `FirefliesSpikeParityProbe`, the FF.4
   decoy arm), `FirefliesRenderTests`, and `MultiPassFlashHarnessTests.firefliesIsFlashSafe` (FF.4).

## Pre-flight invariants (each failure stops the session)

- **Base.** `ff-4` is merged to `main`: branch `ff-5` from an up-to-date `main`. If it is not merged,
  branch from `ff-4` and say so. Stay in this session's own worktree.
- **Fixtures and drive.** `Scripts/link_fixtures.sh` run. `/Volumes/Extreme SSD` mounted. `test -r`
  passes on all ten paths in `tools/data/beta_test_playlist.m3u`. The parity captures are in
  `~/Documents/uzume_spikes/fireflies/sessions/`.
- **FF.4 green at the base.** Record each number:
  - `swift test --package-path UzumeEngine --filter Fireflies` passes;
  - 20-seed parity: DYC 0.972 / +0.843, Pyramid 0.975 / +0.812, Warszawa 0.196 / +0.007, Teardrop
    0.137 / −0.008;
  - the decoy arm: +0.843 / −0.841;
  - `firefliesIsFlashSafe`: 0.00 flashes/s.
  - ⚠ Run every env-gated probe **filtered, never inside the full suite**.
- **Baseline.** `Scripts/closeout_evidence.sh` at the base commit. If the app step exits 65 ("Could not
  launch UzumeAppTests"), a Uzume app is running (BUG-072). Ask Matt to quit it; never kill it.

## Tasks

1. **Ground the patches before code.** Write a short note in the transcript, then add it to
   FIREFLIES_DESIGN §5 once it is built. The note says how the patches self-organise, what happens at a
   patch boundary, and how a firefly's own cycle stays about 1–2 s across tempos. The target is 2–4
   patches, one lit per beat, walking across the meadow. It also says what stays identical when the beat
   is not clear.
   - Grounding. Each patch is the existing model (the FF.0 spike, gated at FF.1) driven on its own grid
     tick. That is level 1, working code. The part that needs proving is the boundary: neighbour relay
     across a patch edge pulls neighbouring patches together, and the whole meadow is the model's natural
     attractor (§8).
   - If the approach needs anything with no working-code or paper grounding, surface it as level 3 and
     stop. Do not build it.
   - Patch count, patch shape and the cycle rule are engineering calls; make them. Matt judges the
     result on the film in Task 4.
   - **Done-when:** the note is in the transcript and names the boundary rule and its grounding.

2. **Build the patches in `FirefliesSwarm`.**
   - On an unclear beat (K = 0) the swarm must be **unchanged**. Gates:
     - Warszawa and Teardrop parity hold at FF.4's numbers;
     - `clarityGovernsTheLock`'s unknown-equals-irregular equality holds;
     - the near-silence straggler fade and the track-change restart tests pass.
   - New always-on gates on the real `route_coverage` fixtures, never synthetic audio (FA #27). With
     K = 1:
     - each patch is coherent;
     - the whole swarm is not (no unison);
     - successive beats light different patches;
     - the lock arrives within about 15 s.
   - Set each threshold from the first measured run, with margin, and write the measurement in the
     test's comment. Never tune a threshold to pass.
   - Rework the env-gated probe for clear beats. DYC and Pyramid with clarity 1 now measure per-patch
     coherence and per-patch on-beat against each patch's own beat. The decoy arm must still separate
     the true grid from the half-beat decoy, against the chance band.
   - **Done-when:** the Fireflies filter is green, the K = 0 parity is unchanged, and the new gates each
     carry their measured numbers.

3. **The smooth glow.**
   - In `fireflies_sprite_fragment`, the halo and starburst become a continuous soft yellow-green light
     around the white core, with no per-pixel stipple.
   - The core, the depth-of-field discs, the pools, occlusion and the world's print grain are
     unchanged.
   - Re-measure flash safety through the real draw path (D-157). If the glow breaks it, the glow
     shrinks; the gate never widens.
   - Make a 6× crop of a near and a far patch at 1080p, the FF.4 `pixel_crop_*_x6.png` method, before
     and after.
   - **Done-when:** the crops show no pixel dither on the fireflies, and 1080p D-157 on the four
     captures is < 0.05 and stated against FF.4's 0.0296 / 0.0374 / 0.0038 / 0.0036.

4. **HARD STOP: Matt's look check on a film.**
   - Render DYC's lock (the parity capture, clarity 1) and one free capture (Warszawa) at 1080p through
     `renderFireflies`. Include the capture's audio if the session has it.
   - Put the films on `/Volumes/Extreme SSD/uzume_spikes/fireflies/ff5/`. Run `Scripts/motion_gate.sh`
     on each and write your motion verdict.
   - Also send the before/after glow crops.
   - Ask two questions: **does it read as a coordinated rhythm, not everyone at once? Is the
     pixelation gone?**
   - Ask the DECISION below at the same time.
   - Stop and wait.
   - **Done-when:** Matt's words, verbatim. If he rejects it, record his words and the one sentence
     "what I now believe is wrong", recommend a next step with a default, and stop.

5. **The pre-M7 packet (FF.4 Task 1, re-run on the new swarm).**
   - R1 (the decoy), R2 (the DYC | Warszawa sheet), R3 (coherence and patch curves), R4, and R5 (1080p
     D-157, the silence film with a motion-gate verdict).
   - Update `firefliesIsFlashSafe` so its comment and drive describe locked patches, not a unison. It
     must still clear the `responded` floor, with 0.00 flashes/s required.
   - **Done-when:** the R1–R5 table in the transcript, each row with its number and source. If R1 does
     not separate, or the flash test flashes, stop and report.

6. **Reach Matt's build.**
   - If `ff-4-reachable` or `ff-4` is on `main`, the arrow keys already reach Fireflies. If not, the
     reachability commit rides in this increment's PR.
   - Build the checkout Matt will run. Name the exact app path (resolve `BUILT_PRODUCTS_DIR`; never a
     DerivedData glob). Check the bundled `Fireflies.json` and the binary's build time.
   - **Done-when:** Matt has the path, and you have confirmed the build contains FF.5.

7. **HARD STOP: the M7, then read the captures (FF.4 Tasks 3–4).**
   - Use FF.4's how-to and watch list, with these per-song expectations:
     - **Patches take turns on the beat:** DYC (after its quiet opening), B.O.B., Take Five,
       Smells Like Teen Spirit, Superstition, Penny Lane. BUG140.2 made Superstition and Penny Lane
       regular.
     - **Free:** Pyramid Song, Warszawa.
     - **Read from the capture:** Teardrop, Moonlight I.
     - **Whole-song arc:** minute 1 vs minute 4.
   - Ask one question: **does Fireflies pass M7?**
   - Read the captures:
     - `chain_health.json` (`clean` required);
     - fps and GPU p50/p95 against 16.6 ms;
     - drawable failures;
     - `stems.beatClarity01` per song.
   - **The lock, which FF.4 could not verify:** replay each song's recorded features through
     `FirefliesDrive` at the recorded clarity, 20 seeds. Report lock time and patch separation per song.
     This replay is the instrument; do not add a recorder column in this increment.
   - **Done-when:** Matt's verdict, verbatim. If he does not pass it: his words, the "what I now believe
     is wrong" sentence (and whether it changed since FF.4's), a recommended FF.6 with a default, then
     stop. Two rejections whose cause you cannot articulate are a `preset-session` escalation.

8. **On a pass: FF.4 Tasks 5–7.**
   - The streaming pass (HARD STOP).
   - Then certification.
     - **The Session C golden:** NRG.3/NRG.4 changed the planner after FF.4 measured it, so re-measure
       which golden moves when Fireflies certifies. Regenerate only with a scoring trace in the comment.
     - `multiPassMeasured`: this task's `firefliesIsFlashSafe` numbers go in the comment.
     - `expectedAutomatedGate["Fireflies"]`: keep it at the measured value, with its comment rewritten
       (the Membrane / Filigree precedent).
     - The rubric: reported honestly; the profile stays `full`.
     - The RUNBOOK battery: `FidelityRubric|Photosensitivity|MultiPassFlash|RouteCoverage`, plus the
       full engine suite.
   - Then the docs:
     - the plan row and a completed entry with the `ALFVEN.CERT` evidence table;
     - the registry;
     - the design status;
     - the slate roster count, 25 → 26;
     - release notes.
   - **Done-when:** as in FF.4 Tasks 6 and 7.

## Do NOT

- **Do NOT change the world, the pools, the depth of field, occlusion or the free swarm.** A request to
  change one of them becomes FF.6.
- **Do NOT let the grid choose which fireflies flash** (option B, rejected at FF.4: the self-organising
  is what makes it fireflies). **Do NOT add a whole-meadow flash on beat 1** (option C, rejected: it
  needs a reliable bar start, which is parked under BUG-065 / D-206).
- **Do NOT change the K mapping or unknown → free** (D-257).
- **Do NOT thin the swarm in quiet passages unless Matt picks it** (the DECISION below).
- **Do NOT widen D-157, `responsiveLumaRange`, the frame-budget nets or any flash threshold.** Do not
  tune a new gate's threshold to pass.
- **Do NOT use synthetic audio as evidence** (FA #27).
- **Do NOT certify without both of Matt's passes**, never on a `degraded` capture, and never without
  each changed expectation carrying its evidence.
- **Do NOT commit, copy, trace or reproduce any print**, or name the artist in user-facing text.
- **Do NOT kill or relaunch Matt's running app**, and never launch a globbed DerivedData path.
- **Do NOT push without Matt's explicit "yes, push".** Push to a branch and open a PR; never push to
  `main`. If any push prints `Bypassed rule violations for refs/heads/main`, say so immediately.

## Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build
swift test --package-path UzumeEngine
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test
swift test --package-path UzumeEngine --filter Fireflies
swift test --package-path UzumeEngine --filter "MultiPassFlashHarnessTests/firefliesIsFlashSafe"
FIREFLIES_PARITY=1 FIREFLIES_SEEDS=20 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine --filter FirefliesSpikeParityProbe
FIREFLIES_DECOY=1 swift test --package-path UzumeEngine --filter "FirefliesSpikeParityProbe/decoyIsDistinguishable"
FIREFLIES_PARITY=1 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine --filter "FirefliesRenderTests/spikeCapturesAt1080p"
FIREFLIES_SILENCE_OUT=<dir> swift test --package-path UzumeEngine --filter "FirefliesRenderTests/silenceFilm"
Scripts/motion_gate.sh fireflies <film-dir>
COMPARE_REF_DIR=~/Documents/uzume_spikes/fireflies/references_danger Scripts/compare_render.sh fireflies <frames-dir>
Scripts/analyze_session_chain.sh ~/Documents/uzume_sessions/<timestamp>
Scripts/closeout_evidence.sh
```

On certification, also run:

```
swift test --package-path UzumeEngine --filter "FidelityRubric|Photosensitivity|MultiPassFlash|RouteCoverage"
swift test --package-path UzumeEngine --filter "GoldenSession|OrchestratorCertifiedFilter"
```

⚠ The DOC.6 rotation gate flips at UTC midnight (19:00 CDT). If `DocIntegrityTests` goes red on
"entries older than 14 days", run `Scripts/rotate_docs.sh` and commit that alone as `[DOC.6]`.

## Commits (on `ff-5`, local, small, one per step)

- `[FF.5] Swarm: patches take turns on a clear beat (free swarm unchanged)`
- `[FF.5] Tests: patch gates on real fixtures; parity probe and decoy per patch`
- `[FF.5] Shaders: Fireflies glow drawn smooth (no stipple)`
- `[FF.5] Tests: flash measurement on locked patches`
- On a pass: `[FF.5] Presets: Fireflies certified`, `[FF.5] Tests: certified tables, multiPassMeasured, golden (with trace)`
- `[FF.5] docs: design §5, plan row + entry, registry, release notes`

End each commit message with the attribution line the harness gives you.

## Closeout

Invoke the `closeout` skill: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as
§2. Add:
- the boundary rule and its grounding;
- the new gates, each with its measured number;
- K = 0 parity against FF.4's;
- the glow crops before and after;
- D-157, FF.5 against FF.4;
- the look-check, M7 and streaming verdicts, verbatim, with session IDs and chain health;
- the per-song replay (lock time, patch separation);
- on certification, FF.4's certified-gate list and the golden before → after with its trace;
- a one-line statement of which dispatch path the render tests exercised.

## DECISION NEEDED: ask at the Task 4 look check

**When the music is quiet but not silent, should the fireflies thin out?** In FF.4's M7 the full swarm
flashed through DYC's quiet three-minute opening, because the quiet detector only fires on silence
(design §2).

- **A. Thin with the music.** Quiet stretches show a sparse meadow, a few patches of a few lights, and
  it fills as the song builds. DYC opens as the design first promised, with a few lights waiting, and
  the drop fills the meadow. It adds an arc across a song.
- **B. Leave it.** The full swarm, now in patches, plays whenever there is a clear beat; only real
  silence thins it. It is simpler and keeps the scene the same from start to finish.

**Recommendation: A.** It gives the scene a beginning, middle and end across a song (R3), and it
answers part of the "overwhelming" note directly.

**Default if no reply: B.** Nothing Matt has not picked gets built.

If A is chosen, the thinning must not reuse the world's breath (`bassAttRel` over 4 s) as a second
channel on the same slow timescale (FA #67). Pick a different primitive, or state why sharing it is
deliberate.
