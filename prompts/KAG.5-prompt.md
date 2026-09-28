# Increment KAG.5 — Kagura: the dances follow the song's measured energy (preset increment)

**Objective.** Today Kagura's song energy comes from the mood classifier: `TrackProfile.mood.arousal`, ranked
against `KaguraRepertoire.energyReference`. D-259 took the classifier out of scene choice because it does not
generalise (arousal agrees with the true sign 50 % of the time, chance level). D-259 §4 kept the certified
scenes' mood reads for "a separate call with Matt's eye". This increment is that call for Kagura (Matt,
2026-09-28: *"the next Kagura increment: song energy"*). After this session:
- Kagura's song energy is D-259's **measured 1–10 energy level**, taken from `TrackProfile.energyCurve` on the
  library scale. No arousal. `energyReference` is retired.
- On local files the **repertoire follows the song's energy sections**. It is re-picked at NRG.4's energy
  changes (for Dance Yrself Clean: the hush, the drop, the breakdown, the re-entry). A steady song keeps one
  repertoire. On streaming, the 30 s preview cannot place a stretch, so the song's typical level stands for
  the whole track (the planner's own rule, `TrackProfile.energyLevel`).
- The **calm rest** (ballet vs sway) reads the same measured energy.
- The Charleston's place follows Matt's answer to the DECISION below.

The gate is: the empirical table first (task 1, a hard stop), then the Kagura suites, routes, goldens and
flash cases green, then **Matt's M7 on the beta playlist (local files)**. Kagura is certified (KAG.4, the
26th), so a look Matt has not seen must not ship before that M7.

## Skills to invoke

- `preset-session`: **before** editing the sidecar or any Kagura source (checklist, Audio Data Hierarchy,
  FA #67).
- `closeout`: at the end. Produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block
  as §2.
- Not expected: `shader-authoring` (no GPU change) and `beat-sync-session` (no grid change). Invoke either one
  only if the work actually crosses into its area.

## Read first (in order)

1. `docs/DECISIONS.md` D-259, the whole entry (≈ line 6090), especially §1 (per stretch, "because songs
   shift"), §4, and the evidence obligation.
2. `docs/presets/KAGURA_DESIGN.md` §6 (the dance choice) and §15, using `grep -n "^## "` and reading only:
   the arousal-source table, the Charleston and ballet paragraphs, and the note on BUG-146 and
   `energyReference` (≈ lines 524–540).
3. `docs/ENGINEERING_PLAN.md`: the Increment NRG.1–NRG.4 entries (≈ lines 1685–1735). They give the beta
   playlist's levels and DYC's change points.
4. `UzumeEngine/Sources/Session/EnergyScale.swift` (the whole file: level, readout, `timedSectionLevels`,
   `level(from:to:)`, `energyChanges`, and `TrackProfile.energyLevel` / `energyChanges(trackDuration:)` /
   `wholeTrackCurve`).
5. `UzumeEngine/Sources/Renderer/Geometry/Kagura/KaguraSelection.swift` (`KaguraRepertoire`),
   `KaguraChoreographer+Selection.swift` (`songIsCalm`, `nextRest`, `pickDance`, `Pick.logLine`).
6. `UzumeApp/VisualizerEngine+Stems.swift` and `+Presets.swift`: `pushKaguraSong` and both log lines.
7. `UzumeEngine/Tests/UzumeEngineTests/Renderer/KaguraRepertoireTests.swift` and `KaguraRestTests.swift`.

## Pre-flight invariants (each failure stops the session)

1. The branch is cut from `origin/main` at or after `a9dbccbf` (#303). `Kagura.json` has `"certified": true`
   and Kagura is in `FidelityRubricTests.certifiedPresets`.
2. NRG.3 and NRG.4 are on main: `TrackProfile.energyChanges(trackDuration:)` and `energyLevel(at:window:trackDuration:)`
   exist, and `tools/data/energy_scale.json` is present.
3. The engine fixtures are linked (`Scripts/link_fixtures.sh` in a worktree).
4. `swift test --package-path UzumeEngine --filter Kagura` passes before any edit. Record the count.

## The prompt author's pre-measurement (2026-09-28; task 1 must reproduce it in Swift)

The data comes from Matt's v17 cache entries via `tools/data/energy_scale.json`. Picks are from
`KaguraRepertoire.pick` with song energy = (typical level − 1) / 9, calm rest = level ≤ 3. The "live now"
column is the `KAGURA_SONG` lines from the KAG.3 M7 session (`2026-09-28T16-18-10Z`).

| Song | Grid BPM | Live now (arousal) | Energy low → high, typical | One number per song (typical) |
|---|---|---|---|---|
| Dance Yrself Clean | 98.0 | egy / cab / **twist**, sway | 2 → 9, **5** | egy / **mac** / cab, sway |
| B.O.B. | 153.8 | cab / twist / charleston, sway | 8 → 10, 10 | same |
| Superstition | 101.4 | egy / mac / cab, sway | 4 → 6, 6 | same |
| Smells Like Teen Spirit | 117.3 | egy / cab / twist, sway | 5 → 8, 7 | same |
| Penny Lane | 113.3 | egy / mac / cab, **ballet** | 5, 5 | same, **sway** |
| Take Five | 171.4 | mac / cab / **charleston**, **sway** | 2, 2 | **egy** / mac / cab, **ballet** |
| Pyramid Song | 95.2 | egy / mac / cab, sway | 4 → 10, 8 | same |
| Teardrop | 78.8 | egy / mac / cab, sway | 5 → 9, 8 | same |
| Moonlight I | 44.5 | egy / mac / cab, ballet | 1, 1 | same |
| Warszawa | 75.2 | egy / mac / cab, **ballet** | 3 → 6, 5 | same, **sway** |

What this shows:
- **A single number per song is the wrong shape.** It loses DYC's twist to its two-minute hush. This is the
  song Matt used to reject whole-song energy (NRG.1: *"dance yourself clean is … both calm and driving"*).
  Following the sections is the fix, and D-259 §1 asks for it.
- **Take Five reads as a quiet song** (2 throughout: a jazz quartet at library scale). Under energy alone it
  loses the Charleston that Matt approved at the KAG.3 M7 and certified at KAG.4. See the DECISION.
- **Ballet moves.** Take Five gains it. Penny Lane and Warszawa lose it as whole songs, but under section
  energy Warszawa's opening (3) may keep it. Matt chose ballet with Warszawa in mind ("ambient tracks such
  as warszawa").
- The macarena appears in more repertoires. Matt, at the KAG.3 M7: *"macarena is a little heavy in this
  set, but it's ok"*. Report its share; do not tune it away.

## Tasks

1. **The empirical table in Swift. STOP and report.** Build a test-only probe (a `KAGURA_ENERGY_TABLE=1`-gated
   test in `KaguraBetaPlaylistReportTests`, reading the fixtures or the local cache the way that suite
   already does). For each beta song, print:
   - the energy sections (`energyChanges`) with each section's level;
   - the repertoire per section, under both the section rule and the per-song-typical rule;
   - the rest style at each section;
   - each dance's share of bars over the playlist under the current rule and under each new rule.

   Use the DECISION's default for the Charleston unless Matt has answered. **Done when** the table is in the
   session notes, the typical-level column matches the table above exactly (Swift and Python agree, as NRG.2
   showed), and you have stopped and shown Matt four things: DYC's per-section repertoires, Take Five's, the
   rests that change, and the macarena share. Continue only on his go.

2. **Song energy from the measured level.** Replace `KaguraRepertoire.songEnergy(arousal:reference:)` and
   `energyReference` with song energy = (level − 1) / 9 on the library scale. The library scale is already a
   rank (deciles of 1,000 songs), so no playlist reference survives. `pick` is unchanged. Rename the
   arousal-named API through the dancer, the choreographer and the harness knobs (`kaguraSongArousal` →
   an energy-level knob). Move the README §9/§10 rows onto `pick(energy:)` directly: they are the spike's
   history, so keep them passing on their printed energies. **Done when** no Kagura source or test reads
   `arousal`, and `grep -rn "energyReference\|songArousal" UzumeEngine/Sources UzumeApp` is empty.

3. **Sections on local files, one level on streaming.** At track start the app passes Kagura the song's
   sections. On a whole-track curve (`TrackProfile.wholeTrackCurve`), that is the change points
   (`energyChanges(trackDuration:)`) and each section's `level(from:to:)`. On a preview curve it is one section
   at `readout().typical`. With no curve (a cache miss) there is no energy, and Kagura behaves as it does today
   with unknown energy. Kagura reads its section from the track's playback position, which is exact on local
   files. A section change re-picks the repertoire. The new repertoire takes effect at the **next clip change**
   (a bar line), never mid-clip, so the handoff bounds that hold today still hold. **Done when** a new
   `KaguraRestTests`-style harness test runs a synthetic two-section song (level 2, then level 9, 120 BPM). It
   must show the repertoire switch at the first clip change after the step, no frame over the per-dance
   handoff bound, and no frozen frames.

4. **The calm rest reads the section.** Ballet when the level of the section the rest falls in is ≤ 3; sway
   otherwise, or when the level is unknown. Silence carries no level (below the curve's −90 dB floor), so a
   silence rest uses the section it interrupts. **Done when** `KaguraRestTests` takes levels instead of
   arousals, and the Warszawa row from task 1 matches what task 1 reported.

5. **The Charleston, per Matt's answer** (the DECISION; default B). **Done when** the build table in
   `KaguraRepertoireTests` is re-derived from task 1's data, one row per section, and the Charleston rows
   match the answer.

6. **Logs.** `KAGURA_SONG` prints each section's start, level, repertoire and rest, plus `curve=whole|preview|none`.
   `KAGURA_PICK` prints the current section's level in place of `songArousal/songEnergy`. **Done when** a local
   launch prints both lines for DYC with its sections.

7. **Sidecar, docs, audio contract.** Update the `Kagura.json` `description` so it says the measured energy of
   each part of the song picks the three dances. Keep `certified: true`. `audio_routes` is unchanged: song
   energy is prepared, not a live primitive. Also update:
   - KAGURA_DESIGN §6 item 1 and §9's repertoire row, plus a §16 "What the build settled (KAG.5)" with task 1's
     table;
   - `docs/AUDIO_CONTRACT.md`, if it names Kagura's arousal read;
   - an **amendment to D-259 §4**: Kagura is the first certified scene moved off the mood classifier, by Matt's
     call on 2026-09-28. No new D-number is needed; if the amendment grows beyond the rule, verify the next
     free ID from the tree.

   **Done when** `DocIntegrityTests` passes.

8. **Gates. STOP before any golden or flash baseline changes.** Run `RouteCoverageTests`,
   `MultiPassFlashHarnessTests` (the three Kagura cases), the Kagura suites, `FidelityRubricTests` and the
   golden suites. If a Kagura golden or flash measurement moves, stop and report the before and after. Do not
   regenerate baselines until Matt says so.

9. **M7 request.** Build Release from this branch, hand Matt the exact app path (never a DerivedData glob),
   and ask for the beta playlist on local files. Tell him what to watch: DYC dancing calm through the hush
   and vigorous from the drop, Take Five per his answer, Warszawa's and Penny Lane's rests, and the macarena
   share. Do not close before his verdict ("pending live M7", never "resolved").

## Do NOT

- Do not read `mood.valence` or `mood.arousal` anywhere in Kagura (D-259 §3; this increment's point).
- Do not change the in-song dance pick (the bar just played ranked against the trailing 60 s of `bass_att`;
  Matt's option A, 2026-09-25). Energy sections choose the **repertoire**, and the bar still chooses **within**
  it. Do not read ahead on the curve for the pick.
- Do not change `EnergyScale`, its tables or `energyChanges` parameters. They are the planner's too (NRG.2–4).
  If a Kagura need seems to call for a different step size, report it.
- No anti-repeat or variety term (KAGURA_DESIGN §6: "follow the song's energy").
- Do not add dances. Tango, salsa, the cha-cha slide and others are Matt's wish list for a later increment.
- Do not bump the cache schema. `energyCurve` has been in v17 since NRG.1. A v14–v16 entry just re-prepares.
- No golden or flash regeneration without Matt (task 8).
- Do not push. Commit locally; pushing needs Matt's "yes, push", and then goes to a branch and a PR, never
  to main.

## Verification

```bash
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build
swift test --package-path UzumeEngine
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test
swift test --package-path UzumeEngine --filter Kagura
swift test --package-path UzumeEngine --filter RouteCoverageTests
swift test --package-path UzumeEngine --filter MultiPassFlashHarnessTests
KAGURA_ENERGY_TABLE=1 swift test --package-path UzumeEngine --filter KaguraBetaPlaylistReportTests
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
```

## Commits (local; small, one per step)

- `[KAG.5] tests: beta-playlist energy table (report-only)`
- `[KAG.5] Renderer: Kagura song energy from the measured level; energyReference retired`
- `[KAG.5] Renderer+App: repertoire follows the song's energy sections`
- `[KAG.5] Renderer: calm rest reads the section's energy`
- `[KAG.5] Renderer: the Charleston per Matt's call`
- `[KAG.5] App: KAGURA_SONG / KAGURA_PICK log energy sections`
- `[KAG.5] docs: Kagura energy (design §16, D-259 §4 amendment, sidecar, release note)`

End each message with the `Co-Authored-By` line from the session's attribution reminder.

## Closeout

Invoke `closeout`. §2 is the verbatim evidence block. Also include:
- task 1's table, as measured and as shipped;
- the local launch's `KAGURA_SONG` lines for DYC and Take Five;
- the flash and golden results with the before/after of anything that moved;
- the M7 request as sent.

The ENGINEERING_PLAN row and the RENDER_CAPABILITY_REGISTRY line say "pending live M7".

## DECISION NEEDED (Matt) — the Charleston on quiet fast songs

**Measured by energy, Take Five is a quiet song (2 of 10), so the Charleston you approved on it would leave.
Should a fast song keep the Charleston even when it plays quietly?**

- **A — Energy decides.** Take Five dances the calm three (Egyptian walk, macarena, cabbage patch), and its
  rests turn to ballet. The Charleston appears only on songs that are both fast and loud, like B.O.B. More
  consistent with "follow the energy", but you lose a pairing you approved: the 1920s dance on a jazz
  standard.
- **B — Tempo earns the Charleston (recommended).** Any song in the Charleston's tempo band (about 137–214
  BPM) keeps it as one of its three, whatever its energy. Energy still picks the other two, and the bar still
  picks among the three. Take Five keeps the Charleston. B.O.B. is unchanged. A quiet fast song would get
  kicks in its loud bars only, because the bar pick puts the Charleston on the vigorous third.
- **C — Tempo plus a floor.** Like B, but only at energy 4 or above. Take Five (2) loses it, and a quiet fast
  ballad never gets it.

**Recommendation: B.** It keeps what you certified, and the in-song bar pick already keeps the kicks on the
loud bars. **Default if no reply: B.**
