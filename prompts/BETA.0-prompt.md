# Increment BETA.0 — decisions recorded, Plasma removed, beta test playlist proposed (docs + fix-scope removal)

**Objective.** After this session:
- the beta scene programme exists in the plan of record;
- Matt's six 2026-09-24 decisions carry D-numbers;
- Aurora Veil's ported shader carries the licence notice its source requires;
- Plasma is gone from the repo;
- a genre-spread test playlist is proposed for Matt's approval.

Waveform is **not** touched: Matt keeps it for now.

## Skills to invoke
- `closeout` at the end.
- `doc-pruning` is **not** invoked. This session adds decision records; it does not prune. It does still
  obey the CLAUDE.md token cap (untouched here).
- Do **not** invoke `preset-session`. No scene is authored. Plasma's removal is a deletion, not a scene edit.

## Read first (in order)
1. `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` §00. It is the source for every decision below; quote it
   and do not paraphrase.
2. `docs/DECISIONS.md` §Index (format of rows), and D-119, D-115, D-185, D-246 (the removal precedent).
3. `docs/ENGINEERING_PLAN.md` §Phase PR (lines ~233–345) and PR.9.
4. `UzumeEngine/Sources/Presets/Shaders/AuroraVeil.metal` (header only) and `docs/CREDITS.md`.
5. `tools/data/corpus_pilot_1000.csv` (column `genre_bucket`) and `docs/diagnostics/CENSUS_FULL_REPORT.md`
   §headline (what per-track data the census holds).

## Pre-flight invariants (each failure stops the session)
- Clean tree on a new branch `claude/beta-0`, created from `main`.
- **Step 0 has already been done on local `main`:** `docs/presets/BETA_SCENE_SLATE_2026-09-24.md` and the
  six first-wave prompts (`prompts/{BETA,KAG,GG,FF,DH,SUMI}.0-prompt.md`) are committed there, so the
  parallel spike worktrees can see them. If they are missing, STOP and ask Matt.
- Gates green before any edit:
  - `swiftlint lint --strict --config .swiftlint.yml` returns 0.
  - The app build succeeds.
  - `swift test --package-path UzumeEngine` passes.
- `grep -c '"name": "Plasma"' UzumeEngine/Sources/Presets/Shaders/Plasma.json` returns 1. If Plasma is
  already gone, skip task 4 and say so.

## Tasks

1. **Confirm the slate doc on `main` is the version Matt approved.** Do not edit it; decisions are
   recorded in DECISIONS.md (task 2), not in the slate.
   **Done-when:** `git log --oneline -- docs/presets/BETA_SCENE_SLATE_2026-09-24.md` shows the Step 0 commit.

2. **Record six decisions as D-251…D-256.** Each gets an Index row and a section with Matt's verbatim
   words from slate §00, the date **2026-09-24**, and a **References** line. They are:
   - (a) D-119 retired as a rule; originals preferred.
   - (b) NC-SA ports allowed, marked, capped at about 3, each with a clean-room replacement named.
   - (c) Plasma removed, Waveform kept uncertified as the launch default.
   - (d) Tier-2-first flagship scenes allowed.
   - (e) the beta programme supersedes Phase PR.
   - (f) 50 is a goal, not a floor; the quality bar governs.

   Also:
   - Amend D-119's Index row to "Superseded by D-251".
   - Add a **Phase BETA** header to `ENGINEERING_PLAN.md` above Phase PR. It gets one paragraph plus a
     pointer to the slate doc, and **no increment narratives**.
   - Mark Phase PR "⏸ superseded by Phase BETA (Matt, 2026-09-24)". Keep its register table intact: the
     observations remain true.

   **Done-when:** `swift test --package-path UzumeEngine --filter DocIntegrity` passes (the index and
   stale-row gates).

3. **Aurora Veil licence notice.** Add to the `AuroraVeil.metal` header block:
   - a CC BY-NC-SA 3.0 notice for the adapted nimitz code (Shadertoy XtGGRt);
   - "Contact the author for other licensing options";
   - a statement that this file is not MIT.

   Add the matching row to `docs/CREDITS.md`. **Comment-only change.**
   **Done-when:** `PresetRegressionTests` passes with the Aurora Veil golden unchanged (the dHash is
   bit-identical).

4. **Remove Plasma** using the D-246 Arachne removal as the pattern.
   - Delete `Plasma.metal`, `Plasma.json` and `docs/VISUAL_REFERENCES/plasma/`.
   - Fix every test that enumerates presets. Grep `Plasma` across `UzumeEngine/Tests` (PresetLoaderTests,
     PresetRegressionTests, FidelityRubricTests, MultiPassRenderHarness, PresetFrameBudgetTests,
     MaxDurationFrameworkTests, PresetLoaderCompileFailureTest, AlfvenFilmPreviewTests at minimum).
   - Update the roster counts and Plasma rows in `ARCHITECTURE.md` Module Map,
     `RENDER_CAPABILITY_REGISTRY.md`, `KNOWN_ISSUES.md`, and the PR.9 / roster register (annotate the rows,
     do not delete them).
   - Historical docs (DECISIONS_HISTORY, RELEASE_NOTES_*, prompts/) are **not** edited.

   **Done-when:**
   - `grep -rn "Plasma" UzumeEngine/Sources UzumeEngine/Tests` returns nothing.
   - The full engine suite plus the app build pass.
   - `RELEASE_NOTES_DEV.md` carries one line.

5. **Propose the beta test playlist, then STOP.**
   - Write a small script at `tools/beta_playlist_candidates.py`. It picks **2 candidates per genre
     bucket** from `corpus_pilot_1000.csv` for: electronic, hiphop, rock_alt_indie, jazz, classical, pop,
     soul_rnb, folk_country, world_latin, soundtrack.
   - Prefer FLAC/lossless tracks, 3–6 minutes long, spread across decades.
   - If the census results on `/Volumes/Extreme SSD` are mounted, include per-track BPM and the
     beat-irregularity flag, and make sure the set includes ≥ 2 beat-irregular tracks and one track in a
     meter other than 4/4 if the census can identify one.
   - Add Bowie, *Low* ("Speed of Life" + "Warszawa") as the fixed anchors.
   - Write `docs/presets/BETA_TEST_PLAYLIST_CANDIDATES.md`: a table with artist, title, bucket, BPM,
     irregular, duration, and why.

   **Hard stop:** report the table and wait for Matt to choose about 10. Do **not** write an .m3u until he
   approves.
   **Done-when:** the candidates doc exists and the session has stopped.

## Do NOT
- Touch Waveform in any way (D-253 keeps it; it remains the launch default).
- Edit any other scene's shader, sidecar or golden.
- Rewrite history docs or `prompts/`.
- Commit audio files or raster images (D-211).
- Push. The commits stay local on `claude/beta-0` until Matt says "yes, push" (then branch + PR, never
  `main`).

## Verification
```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1 | tail -3
swift test --package-path UzumeEngine 2>&1 | tail -5
swift test --package-path UzumeEngine --filter "DocIntegrity|PresetRegression|PresetLoader" 2>&1 | tail -5
grep -rn "Plasma" UzumeEngine/Sources UzumeEngine/Tests
```

## Commits (small, one per task)
- `[BETA.0] docs: D-251…D-256 — Matt's 2026-09-24 beta decisions; Phase BETA supersedes PR`
- `[BETA.0] AuroraVeil: CC BY-NC-SA notice for the adapted nimitz code`
- `[BETA.0] Presets: remove Plasma (D-253)`
- `[BETA.0] tools: beta test-playlist candidates for Matt's pick`

## Closeout
Invoke `closeout`: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Add:
- the D-number → decision table;
- the list of files that referenced Plasma and what happened to each;
- the playlist candidates table (repeat it, so Matt can answer from the report).
