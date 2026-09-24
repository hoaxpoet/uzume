# Increment KAG.0 — Kagura look spike: a point-light dancer on the beat (concept spike, throwaway, no engine code)

**Objective.** After this session, Matt has watched frames of **Kagura** and can say go or no-go on the concept.

**The concept.** Kagura is about 15 glowing points on black that the eye reads as a person dancing
(Johansson biological motion). The motion comes from real motion capture, time-warped so the steps land on
the song's beat grid. The name is the mythic origin of *kagura*: Ame-no-Uzume's drummed dance, per
`docs/planning/MYTH_RESEARCH.md`.

**The spike answers three questions, with frames:**
1. Does retimed motion capture read as *a person dancing to this song*, rather than over it?
2. Which dance families survive time-warping across tempi?
3. How bad are foot-slide artefacts at a given warp ratio?

This is `preset-concept` gate artifacts 1, 2 and 4. **No Metal, no Swift, no sidecar.**

## Skills to invoke
- `preset-concept` **first**. This session *is* that gate; follow its four-artifact rule literally.
- `session-forensics` before choosing recorded sessions for the beat grids (replay-before-live).
- `closeout` at the end.
- Not `preset-session` or `shader-authoring`: no engine code is written.

## Read first (in order)
1. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md`: §00 (lane 4) and §4 entry A3 (Kagura).
2. `.claude/skills/preset-concept/SKILL.md`, then `docs/PRESET_SESSION_CHECKLIST.md` Part 2 (the three-part bar).
3. `docs/AUDIO_CONTRACT.md` §1.2 (beat_phase01, bar_phase01, beats_per_bar, pulse_* fields) and §3 (the
   local vs. streaming split).
4. The D-154 / D-210 summaries in `docs/DECISIONS.md` §Index: irregular tracks, and declining the bar.
5. `docs/presets/alfven_spike/README.md`, the precedent for an offline Python spike in `docs/presets/<slug>_spike/`.
6. `Scripts/motion_gate.sh` (header).
7. **Sources:**
   - CMU Graphics Lab Motion Capture Database, http://mocap.cs.cmu.edu/, and its FAQ on terms. Dance
     trials include:
     - 60_01–60_15 and 61_01–61_15 (salsa)
     - 93_03–93_08 and 103_03–103_08 (Charleston / Lindy Hop)
     - 05_02–05_20 (modern dance)
     - 15_04, 15_05, 15_12 (the twist, cabbage patch)
     - 55_01, 55_02 (dance, lambada)
     - 143_35 (macarena)

     Take ASF/AMC from CMU or the cgspeed BVH conversion, whichever parses more cleanly.
   - Look reference: BioMotionLab BML walker, https://www.biomotionlab.ca/Demos/BMLwalker.html. Watch it
     in motion; it is reference only, with no stated licence, so copy nothing.

## Pre-flight invariants (each failure stops the session)
- The worktree is created from local `main` *after* the Step 0 commit, and
  `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` is present. If it is absent, STOP.
- Work on branch `spike/kag-0` in its own worktree. Only `docs/presets/kagura_spike/` may change.
- `python3` with numpy, scipy and pillow, plus `ffmpeg`, are available.
- At least two recorded **local-file** sessions exist under `~/Documents/uzume_sessions/`:
  - their `chain_health.json` verdict is `clean`;
  - their `features.csv` carries `beat_phase01` and the grid BPM;
  - their tracks have clearly different tempos.

  If they don't exist, say so and use `BeatThisActivationDumper` or `TempoDumpRunner` on
  `UzumeEngine/Tests/Fixtures/tempo/*.m4a` instead. **Never synthesise a beat grid** (FA #27).
- CMU data is downloadable. If the network refuses, stop and ask Matt to download the trials listed above
  into `~/Documents/uzume_spikes/kagura/mocap/`.

## Tasks

1. **Artifact 1 + 2: watch the sources in motion.**
   - Render three CMU clips (one salsa, one Lindy, one modern) as plain point-lights at native speed, with
     no audio, 10 s each.
   - Run `Scripts/motion_gate.sh kagura <dir>` on each.
   - Write a motion verdict: does it read as a person at a glance? Which joints are needed (13, 15 or 17
     points)?

   **Done-when:** `docs/presets/kagura_spike/README.md` §1 holds the verdict table and the chosen joint set.

2. **Estimate each clip's own tempo.**
   - Use the autocorrelation of vertical pelvis motion and foot-contact events (ankle height and velocity
     minima).
   - Report BPM per clip and the clip's beat phase (where its footfalls land).
   - Measure foot-slide at native speed as a baseline (horizontal ankle velocity during contact).

   **Done-when:** a table of clip → BPM, stability and foot-slide.

3. **Artifact 4: the look spike.** Write `docs/presets/kagura_spike/kagura.py`.
   - **Time-warp** each clip to the session's grid BPM. Pick the metrical level (×½, ×1, ×2) that keeps
     the warp ratio closest to 1.
   - **Phase-align** the footfalls to `beat_phase01 ≈ 0`, applying a smooth phase correction and never a
     jump.
   - **Energy chooses scale, not speed:** a smoothed bass or arousal envelope scales limb excursion about
     the pelvis by at most ±25 %.
   - **Look:** soft-glow points on near-black, plus 0.4 s light-painting trails. The camera is orthographic
     at three-quarter view and does not move.
   - **Clip changes** happen on bar boundaries, as a crossfade over 1 beat.
   - **Beat-irregular or bar-declined material** (D-154 / D-210): the dancer falls back to an unwarped
     slow sway clip and does not force steps.
   - Render 30 s at 30 fps for ≥ 3 tracks: slow (≤ 95 BPM), mid (~120), fast (≥ 160), plus one irregular
     track. Output goes to `~/Documents/uzume_spikes/kagura/`, never to git (D-211).

   **Done-when:** the four films exist, and `motion_gate.sh` has been run and **read** for each, with a
   motion verdict written.

4. **Rewatch checks.**
   - **R1 decoy:** render one track twice, once aligned to the true grid and once to a grid shifted by half
     a beat. Put them side by side unlabelled. Write whether *you* can tell which is correct from the frames
     plus the beat ticks overlaid on a strip, and record the answer.
   - **R2:** a two-song contact sheet.
   - **Foot-slide at each warp ratio,** measured. State the ratio beyond which sliding is visible.

   **Done-when:** README §4 carries the three results.

5. **Write the three-sentence story** (See / Move / Music: checkable, no adjectives), the three-part-bar
   check, and the answers to R1–R5. Put them at the top of the README. Then **STOP and report to Matt**
   with:
   - the GIF paths;
   - the chosen joint set;
   - the dance families that survived;
   - the DECISION-NEEDED block below, copied into the report.

   No design doc, no sidecar, no Metal.

## DECISION-NEEDED (for Matt, at the stop)
**What should the dancer look like?**
- **A. Dots only.** The classic point-light figure. Eerie, minimal, unmistakably human in motion, but
  sparse on a big screen.
- **B. Dots with light-painting trails.** Each joint leaves a short ribbon of light, so the dance draws
  itself into the air. It is richer, and it reads as a visualizer rather than a lab demo.
- **C. Dots with faint limb lines.** Reads as a person even in a still, but it drifts toward a stick
  figure, which is the "cheap" risk.

**Recommendation: B.** **Default if no reply: B.**

## Do NOT
- Write engine code, a sidecar, or reference images to git.
- Commit motion-capture files to the repo. CMU terms allow inclusion in a product but not resale, and the
  shipping format is decided in the design doc.
- Hand-animate or synthesise motion. The realism must come from captured data; that is the concept.
- Synthesise beat grids (FA #27).
- Tune past the spike. Two look passes at most; then report.
- Push.

## Verification
```
python3 docs/presets/kagura_spike/kagura.py --help
Scripts/motion_gate.sh kagura ~/Documents/uzume_spikes/kagura/<track>/   # per film
git status --short   # only docs/presets/kagura_spike/ changed
Scripts/closeout_evidence.sh
```

## Commits (local only)
- `[KAG.0] spike: CMU point-light loader + clip tempo estimation`
- `[KAG.0] spike: beat-grid time-warp + look pass`
- `[KAG.0] docs: spike README — story, verdicts, rewatch checks`

## Closeout
Invoke `closeout`: the 8-part report with the verbatim `closeout_evidence.sh` block as §2. Add:
- the gate artifact checklist (1–4, each with its path);
- the motion verdicts;
- the R1 decoy result;
- the foot-slide table;
- the DECISION-NEEDED block.
