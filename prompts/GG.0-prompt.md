# Increment GG.0 — Goldengrove growth-timing spike: does a tree that knows where the peak is read as musical? (concept spike, throwaway, no engine code)

**Objective.** After this session, Matt has watched two versions of the same growing tree side by side, on
real songs.

- **Reactive:** the June-shelved model. The tree fills as the music intensifies.
- **Anticipatory:** the new hook. Uzume analyses the whole local file before playback, so the tree's
  growth is *scheduled* to reach full bloom as the song reaches its measured peak, and to shed afterwards.

Matt's call on these films decides whether Goldengrove is revived. **No look work happens here:** there is
no bark, no leaves beyond simple blobs, and no painterly pass. The fidelity question is a separate spike
that only runs if this one passes.

## Why this spike, and not the June plan
`docs/presets/GOLDENGROVE_PLAN.md` carries Matt's 2026-06-01 shelving note: *"Do not revive without a
fundamentally stronger, signal-grounded musical hook."* Matt asked on 2026-09-24 for Goldengrove to be
developed. Two things have changed since June:

1. **Section-scale signals now reach scenes.** `spectral_level_rise`, `spectral_section_ratio` and
   `spectral_surge` exist; Fractal Tree consumes the first two. `sectionIndex` reaches scenes via the CPU
   bridge (D-151).
2. **On the local-file path the whole track is analysed before playback** (LFSTEM.1). The schedule can
   therefore be computed ahead of time.

The spike tests (2) against the June model. It must not assume that either one works.

## Skills to invoke
- `preset-concept` **first**; this is gate artifacts 1, 2 and 4 for the *musical role*.
- `session-forensics` before picking session data.
- `closeout` at the end.
- Not `preset-session` or `shader-authoring`.

## Read first (in order)
1. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md`, §00 lane 5 and §4 D3.
2. `docs/presets/GOLDENGROVE_CONCEPT.md` (the experience) and `docs/presets/GOLDENGROVE_PLAN.md` §1, §4
   and §5 Spike 1. This increment *is* Spike 1, re-aimed.
3. `docs/AUDIO_CONTRACT.md` §1.2, floats 49–56 (the `spectral_*` fields: what they mean and why they
   survive AGC), and §3 (the streaming path has a 30 s preview, so anticipation is **local-file only**).
4. The FTR entries in `docs/ENGINEERING_PLAN.md` that wired `spectralLevelRise` and
   `spectralSectionRatio` into Fractal Tree. They record how those fields behave on real music.
5. `docs/presets/alfven_spike/README.md`, the offline-spike precedent.
6. **Artifact-1 sources** (growth in motion):
   - Runions et al. 2007, space colonization,
     https://algorithmicbotany.org/papers/colonization.egwnp2007.large.pdf (the algorithm; public paper).
   - Jason Webb's live demo, https://jasonwebb.github.io/2d-space-colonization-experiments/. Watch only;
     its licence is unconfirmed, so copy no code.

## Pre-flight invariants (each failure stops the session)
- The worktree is created from local `main` *after* the Step 0 commit, and
  `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` is present. If it is absent, STOP.
- Branch `spike/gg-0` in its own worktree. Only `docs/presets/goldengrove_spike/` may change.
- There are at least 3 recorded **local-file** sessions with a `clean` chain verdict. Each one's
  `features.csv` must cover an entire track, since that is what emulates pre-analysis, and must carry the
  `spectral_*` columns. They must be shaped differently:
  - (a) a quiet intro building to a big chorus or drop;
  - (b) flat, steady energy;
  - (c) a slow build across the whole track.

  If fewer exist, stop and ask Matt to play three such tracks through the app once. Do not synthesise
  curves (FA #27).
- `python3` with numpy, scipy and pillow, plus `ffmpeg`, are available.

## Tasks

1. **Artifact 1 + 2.** Watch the space-colonization demo in motion: capture 10 s, run `motion_gate.sh`,
   and write a verdict on whether it reads as *growing* rather than *spreading*. This sets the grammar for
   task 3.
   **Done-when:** README §1.

2. **Measure the hook's raw material.** For each session:
   - plot `spectral_level_rise`, `spectral_section_ratio`, `spectral_surge`, a 4 s-smoothed loudness curve
     and `sectionIndex` (if recorded);
   - mark where a listener would say the peak is. Name the timestamp from the audio; do not infer it from
     the curve.

   Then write a peak-finder on the **whole-track** curve (the anticipatory input) and report its error
   against the listener mark for each track.
   **Done-when:** README §2 shows per-track plots and error in seconds. **If the peak-finder misses by more
   than one bar on 2 of 3 tracks, stop here and report.** The hook is not real.

3. **Artifact 4: the two trees.** Write `goldengrove_spike.py`: a 2D space-colonization tree drawn as warm
   lines on dark, with blob leaves.
   - **Reactive** (June §4): canopy fullness follows a smoothed intensity envelope; sheds at track end.
   - **Anticipatory:** growth is a schedule solved from the whole-track curve. It is sparse at the start,
     reaches full canopy *at* the detected peak, and releases leaves after the last peak, falling to a
     settled state by the end.
   - **Both:** leaf shimmer on the beat grid as an accent only (Layer 4, bounded), and wind sway from a mid
     envelope. The **same seed and geometry** are used for both versions, so only timing differs.
   - Render each track as one film with the two versions side by side, unlabelled (randomise left/right
     and keep the key in the README), 30 fps, the whole track or at least 90 s spanning the peak. Output
     goes to `~/Documents/uzume_spikes/goldengrove/`, never git.

   **Done-when:** three films exist, and `motion_gate.sh` has been run and read on each.

4. **Rewatch checks.**
   - R2: a two-song sheet.
   - R3: minute 1 vs the peak.
   - A written paragraph: does the anticipatory tree read as *knowing the song*, or as a timer?

   **Done-when:** README §4.

5. **Write the See / Move / Music story** (checkable sentences), answer the three-part bar honestly, and
   **STOP and report to Matt**. The report carries:
   - the films;
   - the unlabelled left/right key, sealed at the end of the report so Matt can judge blind first;
   - the peak-finder error table;
   - the DECISION-NEEDED block below.

## DECISION-NEEDED (for Matt, at the stop)
**How should the tree keep time with a song?**
- **A. Anticipatory.** The canopy is full exactly as the chorus or drop lands, and lets go afterwards: it
  looks like it knows the song. This is local files only; on streaming it quietly behaves like B.
- **B. Reactive.** The tree fills as the music gets bigger and thins when it quiets. It is always a little
  behind the peak, which was the June concern.
- **C. Neither reads as musical: keep Goldengrove shelved.**

**Recommendation:** A, *only if* the films show it. **Default if no reply: C.** It was shelved by Matt; a
revival needs his yes.

## Do NOT
- Do any look work: bark, SSS, painterly post, golden-hour lighting. That is a later spike, and only if
  this one passes.
- Revive the deleted mesh G-buffer path (RECON.15) or write any engine code.
- Synthesise energy curves or peak labels (FA #27). The listener-marked peak comes from listening.
- Push.

## Verification
```
python3 docs/presets/goldengrove_spike/goldengrove_spike.py --help
Scripts/motion_gate.sh goldengrove ~/Documents/uzume_spikes/goldengrove/<track>.mp4
git status --short   # only docs/presets/goldengrove_spike/ changed
Scripts/closeout_evidence.sh
```

## Commits (local only)
- `[GG.0] spike: whole-track peak finder vs listener marks`
- `[GG.0] spike: reactive vs anticipatory growth films`
- `[GG.0] docs: spike README — story, verdicts, rewatch checks`

## Closeout
Invoke `closeout`: the 8-part report plus the verbatim evidence block as §2. Add:
- the peak-finder error table;
- the motion verdicts;
- the blind-judgement key;
- the DECISION-NEEDED block;
- one sentence: *what I now believe about whether growth can be musical.*
