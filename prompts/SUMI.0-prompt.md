# Increment SUMI.0 — Sumi look spike: floating ink, coloured by the instrument playing (concept spike, throwaway, no engine code)

**Objective.** After this session, Matt has watched frames of **Sumi** on real songs.

**The concept.** Suminagashi (floating-ink marbling) driven by the music:

- **each full-mix onset drops a ring of ink whose colour is the stem dominating at that moment**;
- bass stirs a slow current;
- a section boundary drags a comb through the surface;
- at track end the paper lifts and the water is clean.

## Skills to invoke
- `preset-concept` first.
- `session-forensics` before picking data.
- `closeout` at the end.

## Read first (in order)
1. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md`, §00 lane 3 and §4 A2.
2. `docs/AUDIO_CONTRACT.md` §1.2 and §3. Stems lag ≈ 2.5 s on streaming; **stems are
   section-and-envelope drivers, never transient drivers**. The drop comes from a full-mix onset; only its
   colour comes from the stems.
3. `docs/presets/ALFVEN_DESIGN.md` §6 and D-244. The staged persistent/iterated surface already ports
   PavelDoGreat's projection. Read it to judge build feasibility; this spike does not use it.
4. `tools/milkdrop-render/README.md`, for headless Chrome capture (`setTimeout`, not
   `requestAnimationFrame`).
5. `docs/SHADER_CRAFT.md`, the pale-tone ≤ 30 % rule (relevant to the DECISION below).
6. **Sources:**
   - PavelDoGreat/WebGL-Fluid-Simulation, https://github.com/PavelDoGreat/WebGL-Fluid-Simulation (**MIT**;
     `splat()`, `multipleSplats`, curl/vorticity).
   - MarinovM03/suminagashi, https://github.com/MarinovM03/suminagashi (**MIT**; subtractive
     Beer-Lambert ink, rings, combing).

## Pre-flight invariants (each failure stops the session)
- The worktree is created from local `main` *after* the Step 0 commit, and
  `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` is present. If it is absent, STOP.
- Branch `spike/sumi-0` in its own worktree. Only `docs/presets/sumi_spike/` may change. Vendored MIT code
  keeps its licence header.
- There are ≥ 2 recorded local-file sessions with a `clean` verdict and **both** `features.csv` and
  `stems.csv`, covering a dense rhythmic track and a sparse one.
- Playwright Chromium, `node` and `ffmpeg` are available.

## Tasks

1. **Artifacts 1 + 2.** Run both sources headless untouched, capture 20 s of each, run `motion_gate.sh`,
   and write a verdict. Name which one supplies the *look* and which the *motion*.
   **Done-when:** README §1.

2. **Artifact 4.** Build `docs/presets/sumi_spike/`: a local copy of the chosen source(s), keeping the MIT
   headers, plus an `events.json` built from the session CSVs:
   - **full-mix onsets → ring drops.** Position is a slow deterministic walk, so drops cluster rather than
     scatter. The size scales with onset strength.
   - **colour = the stem with the highest energy deviation at that moment.** Palette: drums sumi-black,
     bass indigo, vocals vermilion, other ochre, adjusted for the chosen ground (see DECISION).
   - **bass envelope → curl strength** (the slow current).
   - **section boundaries** (from `sectionIndex` if recorded; otherwise listener-marked, and labelled as
     such) **→ one comb stroke across the surface.**
   - **track end → the surface clears** over about 3 s.

   Drive the page with a `setTimeout` loop at 30 fps and capture 45 s per track to
   `~/Documents/uzume_spikes/sumi/`.

   **Done-when:** films exist for ≥ 2 tracks, `motion_gate.sh` has been read, and a note records whether
   the surface stays legible or goes to mush after 40 s.

3. **Rewatch checks.**
   - **R1 decoy:** the same film with drops on onsets shifted half a beat.
   - **R2:** a two-song sheet.
   - **R4:** the novelty source is emergent flow. Confirm that the minute-1 and minute-2 frames differ in
     structure, not just in colour.

   **Done-when:** README §3.

4. **Write the See / Move / Music story, then STOP and report to Matt** with the films and the
   DECISION-NEEDED block below.

## DECISION-NEEDED (for Matt, at the stop)
**What is the ink floating on?**
- **A. Indigo-black water.** The inks glow like lit dye. It suits a dark room or a projector and matches
  the rest of Uzume.
- **B. Cream paper.** Traditional suminagashi: dark inks on light. It is beautiful, but it is a bright
  frame that dominates a dark room, and it breaks the pale-tone ≤ 30 % floor.

**Recommendation: A.** **Default if no reply: A.**

## Do NOT
- Write engine code or a sidecar, and do not touch the staged pipeline.
- Drive the drops from stem onsets. They lag on streaming (AUDIO_CONTRACT §3).
- Strip the MIT licence headers from vendored code.
- Push.

## Verification
```
node docs/presets/sumi_spike/capture.js --help
Scripts/motion_gate.sh sumi ~/Documents/uzume_spikes/sumi/<track>.mp4
git status --short
Scripts/closeout_evidence.sh
```

## Commits (local only)
- `[SUMI.0] spike: source captures`
- `[SUMI.0] spike: event-driven ink films`
- `[SUMI.0] docs: spike README`

## Closeout
Invoke `closeout`: the 8-part report plus the verbatim evidence block as §2. Add:
- the gate artifact checklist;
- the legibility-at-40 s note;
- the DECISION-NEEDED block.
