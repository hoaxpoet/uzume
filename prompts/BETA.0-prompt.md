# Increment BETA.0 — decisions recorded, Plasma removed, beta test playlist written (docs + fix-scope removal)

**Objective.** After this session:
- the beta scene programme exists in the plan of record;
- Matt's six 2026-09-24 decisions carry D-numbers;
- Aurora Veil's ported shader carries the licence notice its source requires;
- Plasma is gone from the repo;
- Matt's approved 10-track test playlist exists as an `.m3u` Uzume can open, plus a doc that says what each
  track tests.

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
5. `UzumeEngine/Sources/Session/M3UParser.swift` header. Absolute paths are accepted; `.m4a`, `.mp3` and
   `.flac` are allowed; unreadable entries are skipped.

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

5. **Write the beta test playlist.** Matt approved it on 2026-09-24. It is the fixed review material for
   every Phase BETA scene: each spike, M7 and rewatch check runs against these ten songs. Local files are the
   review path (whole-track analysis, stems on time). Matt mirrors the same ten songs by hand as a Spotify
   playlist for the streaming pass.

   **(a) Write `tools/data/beta_test_playlist.m3u` with exactly this content.** Every path was checked
   against `tools/data/corpus_manifest.csv.gz`.
   ```
   #EXTM3U
   #EXTINF:538,LCD Soundsystem — Dance Yrself Clean
   /Volumes/Extreme SSD/L/LCD Soundsystem/[2010] - This Is Happening/01 Dance Yrself Clean.mp3
   #EXTINF:304,OutKast — B.O.B.
   /Volumes/Extreme SSD/O/OutKast/[2000] - Stankonia/1-11 B.O.B..mp3
   #EXTINF:266,Stevie Wonder — Superstition
   /Volumes/Extreme SSD/UVW/Wonder, Stevie/[1972] - Talking Book - FLAC/06-Superstition.flac
   #EXTINF:301,Nirvana — Smells Like Teen Spirit
   /Volumes/Extreme SSD/N/Nirvana/[1991] - Nevermind/01 Smells Like Teen Spirit.m4a
   #EXTINF:181,The Beatles — Penny Lane
   /Volumes/Extreme SSD/B/The Beatles/[1967] - Magical Mystery Tour - FLAC/Penny Lane (stereo).flac
   #EXTINF:327,Dave Brubeck Quartet — Take Five
   /Volumes/Extreme SSD/B/Brubeck, Dave/[1959] - Time Out/1-03 Take Five.mp3
   #EXTINF:289,Radiohead — Pyramid Song
   /Volumes/Extreme SSD/R/Radiohead/[2001] - Amnesiac/FLAC/02. Pyramid Song.flac
   #EXTINF:331,Massive Attack — Teardrop
   /Volumes/Extreme SSD/M/Massive Attack/[1998] - Mezzanine - FLAC/03 - Massive Attack - Teardrop.flac
   #EXTINF:426,Beethoven (Barenboim) — Piano Sonata No. 14 "Moonlight", I. Adagio sostenuto
   /Volumes/Extreme SSD/B/Beethoven/[1989] - The Complete Piano Sonatas (Daniel Barenboim)/CD05/04 - Sonata No.14 in C sharp minor, Op.27 No.2 Moonlight - 1. Adagio sostenuto.flac
   #EXTINF:384,David Bowie — Warszawa
   /Volumes/Extreme SSD/B/Bowie, David/[1977] - Low/08 - Warszawa.flac
   ```

   **(b) Write `docs/presets/BETA_TEST_PLAYLIST.md`.** It holds:
   - where the `.m3u` lives, and how to open it (File → Open, or drag it onto the window; it then stays in
     File → Open Recent);
   - a note that Matt keeps a Spotify mirror of the same ten songs;
   - this table, verbatim:

   | # | Track | Genre | What it tests |
   |---|---|---|---|
   | 1 | LCD Soundsystem, "Dance Yrself Clean" | electronic | About three minutes of near-hush, then the drop. Goldengrove bloom timing, Supernova build and detonation, Fireflies at near-silence, four-on-the-floor. |
   | 2 | OutKast, "B.O.B." | hip-hop | Very fast and dense. Kagura's fast-tempo case; stress for stem-driven scenes. |
   | 3 | Stevie Wonder, "Superstition" | soul/funk | Mid-tempo groove with horns. "Does it dance?" (Kagura, Pendulums). |
   | 4 | Nirvana, "Smells Like Teen Spirit" | rock | Quiet-verse/loud-chorus switches. Section boundaries (Sumi's comb stroke, Physarum rule changes), calming at verses. |
   | 5 | The Beatles, "Penny Lane" | pop | Audible key changes. Drumhead, Harmonograph, harmony-driven colour. |
   | 6 | Dave Brubeck Quartet, "Take Five" | jazz | 5/4 with swing. The *"everything seems like 4/4"* note (FFO); meter-aware Pendulums. |
   | 7 | Radiohead, "Pyramid Song" | art rock | The "where's the beat?" track (the census's disagreement example). Fireflies stay free; Kagura falls back to its sway. |
   | 8 | Massive Attack, "Teardrop" | trip-hop | Slow, heartbeat kick, deep bass, lead vocal. The slow-tempo case; Lantern, Pool. |
   | 9 | Beethoven, "Moonlight" I (Barenboim) | classical | Solo piano, no drums, slow harmonic drift. Restraint; harmony-driven scenes without a beat. |
   | 10 | David Bowie, "Warszawa" | ambient | Nearly beatless. The anchor to the 2026-09-04 roster review; near-silence behaviour. |

   **(c) Verify.**
   - If `/Volumes/Extreme SSD` is mounted, run `test -r` on each of the ten paths and parse the file once
     through `M3UParser` (a throwaway `swift` snippet or a one-off test run is fine; do not commit it).
     Report `10/10 resolved`.
   - If the census results are on the SSD, add measured BPM and the beat-irregularity flag per track to the
     doc table, and cite the source file. Do not type BPMs from memory.
   - If the SSD is not mounted, say so in the closeout and mark the verification **owed**. Do not fail the
     session over it.

   **Done-when:** both files exist and the verification result is stated. No hard stop: the list is already
   approved.

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
- `[BETA.0] docs+tools: the beta test playlist (.m3u + what each track tests)`

## Closeout
Invoke `closeout`: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Add:
- the D-number → decision table;
- the list of files that referenced Plasma and what happened to each;
- the playlist verification result (`N/10 resolved`, or owed if the SSD was not mounted).
