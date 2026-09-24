# Increment FF.0 — Fireflies look spike: a swarm that finds the beat (concept spike, throwaway, no engine code)

**Objective.** After this session, Matt has watched frames of **Fireflies** on real songs.

**The concept.** A dusk meadow of fireflies that blink at random. Pulled by one another and by the music's
beat grid, they gradually fall into unison, and **coupling strength follows how clear the beat is**:

- rhythmically clear music entrains them;
- rubato and ambient music leaves them free;
- the top of every track (cold start) is incoherent *by design*.

This is gate artifacts 1, 2 and 4, plus one engine fact the build depends on.

## Skills to invoke
- `preset-concept` first.
- `session-forensics` before picking data.
- `closeout` at the end.
- Not `preset-session` or `shader-authoring`.

## Read first (in order)
1. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md`, §00 lane 1 and §4 D1.
2. `docs/AUDIO_CONTRACT.md` §1.2:
   - `beat_phase01`, `beats_until_next`;
   - `pulse_amp01`, described there as *"a GATE, not an envelope"*;
   - `near_silent01`.
3. D-154 (beat-irregularity exclusion), D-157 (bounded per-beat footprint, steady luminance) and D-164
   (flash safety by measurement), via the `docs/DECISIONS.md` §Index.
4. `docs/presets/EQUATION_PRESET_CANDIDATES_2026-09-09.md`, the Kuramoto chimera row. It died as
   per-pixel "TV snow"; discrete points are the answer to that.
5. **Sources:**
   - Nicky Case, *Fireflies*: https://ncase.me/fireflies/ and https://github.com/ncase/fireflies
     (**CC0 / public domain**). This is the pulse-coupled "nudge the clock" model.
   - Real footage of synchronous fireflies, as a *reference for motion only* (any public video). Record
     the URL.

## Pre-flight invariants (each failure stops the session)
- The worktree is created from local `main` *after* the Step 0 commit, and
  `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` is present. If it is absent, STOP.
- Branch `spike/ff-0` in its own worktree. Only `docs/presets/fireflies_spike/` may change.
- There are recorded local-file sessions with a `clean` chain verdict for three kinds of track:
  - (a) a strongly regular 4/4 track;
  - (b) a swung or rubato track (`so_what` is the fixture precedent);
  - (c) a near-beatless track (e.g. *Low*, "Warszawa").

  If any is missing, stop and ask Matt.
- `python3` with numpy and pillow, plus `ffmpeg`, are available. Playwright Chromium is available for
  task 1.

## Tasks

1. **Artifacts 1 + 2.** Run ncase's simulation headless (Playwright; use a `setTimeout` loop, because
   `requestAnimationFrame` does not fire headless, per `tools/milkdrop-render/README.md`). Capture 20 s from
   a random start through synchronisation, run `motion_gate.sh`, and write a verdict. Watch the real
   footage too. Note what makes the real thing magical: the waves of flashes sweeping the swarm just
   before lock.
   **Done-when:** README §1.

2. **The engine fact.** Find the best signal *already reaching a shader* that says how clear the beat is
   on this track right now. Candidates to check:
   - `pulse_amp01` (is it gated off on irregular tracks?);
   - grid presence;
   - `beats_per_bar` declines (D-210).

   `assessBeatIrregularity` is **CPU-side** (`StemCache.swift`, `TrackProfile.swift`). If no GPU-visible
   carrier exists, **name** the one-float infrastructure increment it would take. **Do not build it**:
   infrastructure never ships bundled with a scene.
   **Done-when:** README §2 carries the answer with file:line evidence.

3. **Artifact 4.** Write `fireflies_spike.py`: N = 400–800 pulse-coupled oscillators in a 2.5-D dusk
   meadow.
   - The scene: a gradient sky, a tree-line silhouette, and depth fog. Each firefly is a tiny warm point
     with a soft glow and a slow drift.
   - **Mutual coupling:** the ncase nudge.
   - **Music coupling:** on each beat-grid tick every firefly is nudged toward the beat by K. K comes from
     the task-2 signal, or from the session's recorded irregularity flag as a stand-in if there is no
     carrier yet. Label that clearly.
   - **Near silence** (`near_silent01`): fireflies dim to a few stragglers. The frame is never black
     (D-037).
   - **Flash safety:** measure the frame-mean luminance range per second and report it. **The global frame
     must not pulse.** Each flash is a point, not a frame.
   - Render 45 s per track from the track start (cold start included), 30 fps. Output goes to
     `~/Documents/uzume_spikes/fireflies/`.

   **Done-when:**
   - three films exist and `motion_gate.sh` has been read on each;
   - a plot of the order parameter (coherence) against time for each track shows entrainment on (a) and
     not on (c).

4. **Rewatch checks.**
   - **R1 decoy:** entrain to a grid shifted by half a beat, side by side with the true grid. State whether
     the true one is distinguishable.
   - **R2:** a two-song sheet.
   - **R3:** the entrainment arc, shown as the coherence plot.

   **Done-when:** README §4.

5. **Write the See / Move / Music story, then STOP and report to Matt** with the films, the coherence
   plots, the task-2 finding, and the DECISION-NEEDED block below.

## DECISION-NEEDED (for Matt, at the stop)
**Where do the fireflies live?**
- **A. A dusk meadow with a tree line.** Naturalistic and calm, with a horizon that gives scale. It is the
  second-screen look.
- **B. A pure black field.** Abstract and minimal; the swarm is the only subject.
- **C. A forest interior with fog.** More depth and mood, but darker and busier.

**Recommendation: A.** **Default if no reply: A.**

## Do NOT
- Write Metal, Swift or a sidecar. Do not build the task-2 infrastructure.
- Let flashes brighten the whole frame. D-157's steady luminance is the rule, and flash safety is
  measured, not asserted.
- Synthesise beat grids (FA #27).
- Push.

## Verification
```
python3 docs/presets/fireflies_spike/fireflies_spike.py --help
Scripts/motion_gate.sh fireflies ~/Documents/uzume_spikes/fireflies/<track>.mp4
git status --short   # only docs/presets/fireflies_spike/
Scripts/closeout_evidence.sh
```

## Commits (local only)
- `[FF.0] spike: ncase source capture + beat-clarity carrier audit`
- `[FF.0] spike: pulse-coupled swarm films on three tracks`
- `[FF.0] docs: spike README — story, verdicts, rewatch checks`

## Closeout
Invoke `closeout`: the 8-part report plus the verbatim evidence block as §2. Add:
- the gate artifact checklist;
- the coherence plots;
- the luminance-range table;
- the task-2 finding (named infrastructure or not);
- the DECISION-NEEDED block.
