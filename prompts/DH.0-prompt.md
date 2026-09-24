# Increment DH.0 — Drumhead look spike: harmony chooses the pattern (concept spike, throwaway, no engine code)

**Objective.** After this session, Matt has watched frames of **Drumhead**, the circular sibling of Cymatic
Resonance, on real songs.

**The concept.** Standing-wave patterns on a circular membrane (Bessel modes `J_n(α_nm r/R)·cos(nθ)`).

- **The song's position on the circle of fifths chooses the number of spokes (n),** so a key change
  visibly redraws the figure.
- Brightness (a centroid deviation) chooses the number of rings (m).
- A kick makes the pattern snap and the medium jump.

It must **not** read as a re-skin of Cymatic Resonance.

## Skills to invoke
- `preset-concept` first.
- `session-forensics` before picking data.
- `closeout` at the end.

## Read first (in order)
1. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md`, §00 lane 2 and §4 B1.
2. `docs/presets/psychedelic_geometry/PG_CR_CYMATIC_RESONANCE.md` and the D-196–D-199 rows in
   `docs/DECISIONS.md`. Cymatic's centroid-ladder lessons (D-197: real centroid occupies 0.08–0.18, so use
   *deviation*) apply directly.
3. D-221 (Rosette: *"MUST use motion to smoothly transition from one pattern to another"*) and D-204
   (Faraday was retired on its **image**). Do not revive the Faraday PDE.
4. `docs/AUDIO_CONTRACT.md` §1.2:
   - the TIV fields: `tonal_phase_fifths`, `tonal_consonance`;
   - the D-209 circular-smoothing rule;
   - their liveness notes.
5. **Sources:**
   - LuisReinoso/vibracion, https://github.com/LuisReinoso/vibracion (**MIT**; live-audio circular Bessel
     modes, a water/antinode toggle).
   - evoluteur/cymatics, https://github.com/evoluteur/cymatics (**MIT**; sand on a circular drumhead).

## Pre-flight invariants (each failure stops the session)
- The worktree is created from local `main` *after* the Step 0 commit, and
  `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` is present. If it is absent, STOP.
- Branch `spike/dh-0` in its own worktree. Only `docs/presets/drumhead_spike/` may change.
- There are ≥ 2 recorded local-file sessions with a `clean` verdict whose `features.csv` has the tonal
  columns (added at TONAL.1). One of the tracks must **change key audibly**; name the timestamp from
  listening.
- `python3` with numpy, scipy (`scipy.special.jv`, `jn_zeros`) and pillow, plus `ffmpeg`, are available.
  Playwright is available for task 1.

## Tasks

1. **Artifacts 1 + 2.** Run vibracion headless with a real track as its audio input, in both the circular
   and water modes. Capture 20 s of each and run `motion_gate.sh`. Also capture a 20 s Cymatic Resonance
   sequence from the engine (the `RENDER_SEQUENCE` harness) for side-by-side comparison. Write a verdict
   on what makes the circular source distinct.
   **Done-when:** README §1.

2. **Artifact 4.** Write `drumhead_spike.py`: circular-membrane modes rendered in two media.
   - **Water dish:** a dark dish; the pattern shows as ring-light reflections on the surface slope.
   - **Sand drumhead:** grains collect on the nodal lines.

   Mapping:
   - **fifths → n** through a D-209 circular smoother, with **multi-second crossfades between modes**
     (D-221) and never a jump;
   - centroid deviation → m;
   - `bassDev` → snap, a bounded jump of the medium;
   - consonance → edge sharpness.

   Render 40 s per track, 30 fps, including the key change. Output goes to
   `~/Documents/uzume_spikes/drumhead/`.

   **Done-when:** films exist for both media on ≥ 2 tracks, and `motion_gate.sh` has been read on each.

3. **Rewatch checks.**
   - **R2:** a two-song sheet.
   - **R1:** does the key change visibly redraw the figure? Show frames 4 s before and 4 s after the
     listener-marked key change.
   - **"Not a re-skin":** a contact sheet of Drumhead beside Cymatic Resonance at matched moments.

   **Done-when:** README §3.

4. **Write the See / Move / Music story, then STOP and report to Matt** with the films, the sheets, and the
   DECISION-NEEDED block below.

## DECISION-NEEDED (for Matt, at the stop)
**What is the drum made of?**
- **A. Water in a dark dish under a ring light.** Luminous, jewel-like mandalas: the look of the famous
  cymatics photographs. Clearly different from Cymatic Resonance.
- **B. Sand on a circular drumhead.** The same family look as Cymatic Resonance in a round frame. Safer,
  but closer to a sibling copy.

**Recommendation: A.** **Default if no reply: A.**

## Do NOT
- Write engine code or a sidecar.
- Use the Faraday nonlinear PDE (D-204).
- Jump instantly between modes (D-221).
- Put absolute thresholds on the centroid (D-197 / FA #31).
- Push.

## Verification
```
python3 docs/presets/drumhead_spike/drumhead_spike.py --help
Scripts/motion_gate.sh drumhead ~/Documents/uzume_spikes/drumhead/<file>.mp4
git status --short
Scripts/closeout_evidence.sh
```

## Commits (local only)
- `[DH.0] spike: vibracion + Cymatic capture`
- `[DH.0] spike: water / sand drumhead films`
- `[DH.0] docs: spike README`

## Closeout
Invoke `closeout`: the 8-part report plus the verbatim evidence block as §2. Add:
- the gate artifact checklist;
- the key-change before/after frames;
- the not-a-re-skin sheet;
- the DECISION-NEEDED block.
