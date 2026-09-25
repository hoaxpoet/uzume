# Increment FF.2 — Fireflies: the world, in 3D, as a screenprint (preset increment)

**Objective.** After this session, Fireflies' meadow is a real 3D place rendered as a stylized screenprint
(D-258), not the FF.0 placeholder painting:
- a slow camera drift makes near and far separate;
- the ground recedes to a ragged, layered tree line under a glowing blue sky, with mist in the low ground;
- the fireflies from FF.1 live *in* that space: near ones bigger and brighter, far ones smaller, drifting
  past each other through the same camera as the world;
- the world has its own life (wind in the grass, drifting mist) and coasts at silence;
- the whole frame reads as one blue ink family plus near-black, with texture from fine hatched line
  density, and the fireflies as the only warm light.

**The session's first deliverable is ONE still beside the hero reference `07`, and it stops there for
Matt to accept or reject the direction (Task 4).** Nothing past Task 4 happens without his yes.

**Not here** (FF.3): the light itself — the bloom, fireflies lighting the grass and mist around them,
occlusion by grass and trees, out-of-focus near fireflies. **Not here** (FF.4): M7, certification,
removing `exclude_from_cycling`.

## Skills to invoke

- `preset-session`: invoke **before** opening any `.metal` file or editing the sidecar. It carries the
  mandatory checklist (`docs/PRESET_SESSION_CHECKLIST.md`), the Audio Data Hierarchy and FA #67.
- `shader-authoring`: before any `.metal`, render pass or GPU-facing Swift. Its FA #64/#65/#73 desk-research
  rules govern Task 1.
- `session-forensics`: before replaying any capture.
- `closeout`: at the end, the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## Read first (in order)

1. `docs/presets/FIREFLIES_DESIGN.md`: all of it (short). §4 and §5 are this increment.
2. `docs/VISUAL_REFERENCES/fireflies/README.md`: §FF.R2 (the style rules, what each print is for, the
   anti-references), then the FF.R table for composition only.
3. The nine local-only prints in `~/Documents/uzume_spikes/fireflies/references_danger/`: read `README.md`
   and `_sheet.jpg`, then **look at `07`, `03`, `06`, `09` at full size**. Rules for these files:
   - They are commercial art: never copy them into the repo.
   - Never trace them or reproduce a specific print.
   - Never name the artist in any user-facing text, and that includes the sidecar `description`.
4. `docs/DECISIONS.md`: D-258, D-257, D-157, D-029, D-026 (use the §Index).
5. FF.1's code — the behaviour you place in 3D; do not retune it:
   - `UzumeEngine/Sources/Renderer/Geometry/FirefliesSwarm.swift`: the header, `installTempo`,
     `buildNeighbours`, `depth`, `envelope`;
   - `FirefliesGeometry.swift` (`upload` maps the swarm to NDC);
   - `Renderer/Shaders/Fireflies.metal`;
   - `Presets/Shaders/Fireflies.{metal,json}` (the placeholder world this increment replaces).
6. `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` rows:
   - the Fireflies pulse-coupled swarm row;
   - Witchlight's instanced screen-space sprites (WL.2-g);
   - Nimbus volumetric fog;
   - the Fractal Tree mesh-shader row (the engine already grows branching trees);
   - the "Structural-section signal reaching a `ParticleGeometry`" row (how a particles preset also gets a
     per-frame tick);
   - `ParticleGeometryRegistry.swift`, `StatefulRuntimeRegistry`: Nebula is the precedent for a `direct`
     world fragment with a slot-6 state buffer.
7. `docs/ARCHITECTURE.md §GPU Contract Details`: before authoring any pass.
8. The harness:
   - `MultiPassRenderHarness.renderFireflies` (mirrors `drawDirect` → `encodePresetVisualization`);
   - `FirefliesRenderTests` (the D-157 gate and the 1080p/film probe);
   - `FirefliesSwarmTests` (`FirefliesDrive`, the parity probe);
   - `docs/presets/fireflies_spike/plot_parity.py`;
   - `Scripts/compare_render.sh`, `Scripts/motion_gate.sh`.

## Pre-flight invariants (each failure stops the session)

- **Base.** This prompt and `FIREFLIES_DESIGN.md` were committed on branch `ff-2-prompt`, on top of `main`
  at `22db2729` (FF.1 #273 and FF.R2 #276 merged).
  - If `ff-2-prompt` has been merged into `main`, branch `ff-2` from an up-to-date `main`.
  - Otherwise branch `ff-2` from `ff-2-prompt`: the local branch if it was never pushed,
    `origin/ff-2-prompt` if it was.
  - Stay in this session's own worktree: never `git worktree add`, never write another worktree's files.
- **References.** `~/Documents/uzume_spikes/fireflies/references_danger/` holds nine `0N_*.jpg` files plus
  `README.md` and `_sheet.jpg`. If they are missing, stop and ask Matt; do not re-download them yourself.
- **Captures.** `~/Documents/uzume_spikes/fireflies/sessions/` holds the four parity captures
  (`fixturegen-01_Dance_Yrself_Clean`, `-02_Pyramid_Song`, `-08_-_Warszawa`,
  `-03_-_Massive_Attack_-_Teardrop`).
- **Fixtures.** Worktrees lack the gitignored ML weights and fixtures. Run `Scripts/link_fixtures.sh` first,
  or the stem and preparation tests fail fast.
- **FF.1 is green at the base.** Run both commands and record the numbers:
  - `swift test --package-path UzumeEngine --filter Fireflies` passes (the always-on swarm and flash gates).
  - `FIREFLIES_PARITY=1 FIREFLIES_SEEDS=20 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine
    --filter FirefliesSpikeParityProbe` passes. FF.1's 20-seed means are DYC R 0.972 / on-beat +0.843,
    Pyramid 0.975 / +0.812, Warszawa 0.196 / +0.007, Teardrop 0.137 / −0.008.
  - ⚠ Run the env-gated probes **filtered, never inside the full suite**: they hold the main actor for
    minutes and starve the SessionManager tests.
- **Baseline.** `Scripts/closeout_evidence.sh` is green at the base commit.
  - Timing gates fail under load when another session's suite runs at the same time. If a baseline test
    fails, re-run it isolated and record both results. Do not "fix" it here.

## Tasks

1. **Ground the technique before building it.** Three mechanisms, each needing a grounded approach:
   - **(a) the 3D world:** receding ground, 2–3 tree-line depth layers with fine branching, sky, mist;
   - **(b) the screenprint treatment:** quantising to a blue ink family plus near-black, tone expressed as
     hatched line density, paper/ink grain;
   - **(c) one shared camera:** the world pass and the swarm sprites project through the same slowly
     drifting camera.

   Do the desk research the `shader-authoring` skill requires, for example:
   - real-time hatching and tonal art maps;
   - screenprint/posterisation shaders;
   - layered 3D cards versus ray-marched terrain for stylized landscapes;
   - how the engine's existing paths (direct fragment, ray-march, mesh-shader branches) can host it.

   Grounding levels, in order of preference:
   1. a working code reference;
   2. a paper with implementable math;
   3. nothing.

   Prefer adopting a working reference over deriving one (FA #73).

   - **Done-when:** a grounding table (mechanism × chosen approach × grounding level × citation) is
     written into the transcript and later into the closeout.
   - **If any mechanism is level 3, or needs a new engine surface, stop and bring it to Matt** before
     building. Name the infrastructure; don't bundle it.
   - Existing mechanisms are fair game: a slot-6 state buffer via `StatefulRuntimeRegistry` (the Nebula
     precedent), the `SpectralHistoryBuffer` pattern FF.1 used, the per-frame tick bridge.
2. **Let the comparison sheet see the local references.**
   - Add an optional reference-folder override to `Scripts/compare_render.sh` (e.g. `COMPARE_REF_DIR`),
     leaving the default behaviour byte-identical.
   - **Done-when:**
     - a sheet composites a Fireflies render against `~/Documents/uzume_spikes/fireflies/references_danger/`;
     - a run for another preset without the variable is unchanged;
     - no print is copied into the repo (`git status` shows none).
3. **The look still.** Build just enough of the world and the screenprint treatment to render the real
   scene through the production draw path.
   - **Two frames at 1920×1080:**
     - Frame 1 at the locked-unison peak of the DYC capture (FF.1's films found it near frame 1221).
     - Frame 2 is the same moment with the camera drifted, to show the parallax.
   - The swarm may still be FF.1's screen-space layer in this still if the shared camera (Task 6) is not
     built yet. Say so on the sheet.
   - **Done-when:**
     - both PNGs exist;
     - a comparison sheet sits against `07`, `03`, `06` and `09`;
     - there is a verdict table in the transcript with one row per FF.R2 style rule and per anti-reference:
       `trait | reference | PASS/FAIL | what differs`.
4. **HARD STOP — Matt's accept/reject.** Show Matt:
   - the sheet;
   - the two frames;
   - the verdict table;

   Ask one question: *does this direction clear the bar for the world?* **Stop and wait.**
   - **Reject** or "not yet": record his words and what you now believe is wrong in one sentence. Revise
     at most once and come back. Two consecutive rejections whose cause you cannot articulate are a
     `preset-session` escalation: stop and re-scope with Matt; don't iterate.
   - **Accept:** continue to Task 5.
5. **Complete the world** (after acceptance). Build all of FIREFLIES_DESIGN §4:
   - the composition of §4.1, taking `03` for the branching and `05` for the layers;
   - foreground grass and seed-head silhouettes at the bottom edge;
   - mist pooled in the low ground;
   - the ambient life of §4.3 (wind in the grass, drifting mist, the camera drift);
   - coasting at near-silence, never black (D-037).

   **The world breathes with the music (Matt chose B, D-258 addendum):**
   - drive it from one slow, heavily smoothed deviation primitive (D-026), never at beat rate;
   - declare it in `audio_routes`, add the `SessionReplayHarness`/drive column if missing, and keep
     `RouteCoverageTests` green;
   - the beat stays the fireflies' alone (FA #67).

   - **Done-when:**
     - `RENDER_VISUAL=1` stills and a contiguous frame sequence exist;
     - the comparison sheet against the FF.R2 set carries a verdict table;
     - a `Scripts/motion_gate.sh` motion verdict is written (smooth, on-concept in motion, alive at
       silence).
6. **Place the swarm in depth, through the shared camera.**
   - Give each firefly a position in the world that projects through the same camera as the world pass,
     with size and brightness from true depth.
   - **FF.1's behaviour must not change.** Keep the simulation's coupling domain (the neighbour relation,
     the tempo source, every constant) so the parity gate still holds. Derive the 3D placement from it
     rather than re-deriving the model.
   - **Done-when:**
     - `swift test --package-path UzumeEngine --filter Fireflies` passes;
     - the filtered parity probe's 20-seed means sit within ±0.1 of the spike's (and near FF.1's numbers
       above);
     - in the film, fireflies visibly drift past one another with parallax as the camera moves.
7. **Evidence in the real pipeline.**
   - **Films:** for all four parity captures (`FIREFLIES_PARITY_OUT`), each with a motion-gate reading.
   - **Flash:** safety at 1920×1080 through the real draw path (D-157: max Δ frame-mean luma < 0.05;
     report the per-second range).
   - **Performance:**
     - frame time at 1080p **in Release**, and state the configuration of every number;
     - the Debug-built `PresetFrameBudgetTests` stays within its outlier and absolute nets (it times CPU
       work at `-Onone`);
     - record a baseline row for Fireflies from an **isolated** run only.
   - **Rubric** (`FidelityRubricTests`), reported honestly.
   - **Done-when:** all four measured and tabled; a red gate is reported, never widened.
8. **Docs.** Update in the same branch:
   - `ENGINEERING_PLAN.md`: the FF.2 row and a completed entry;
   - `RENDER_CAPABILITY_REGISTRY.md`: new capability rows (e.g. screenprint/NPR treatment, shared world +
     sprite camera);
   - `ARCHITECTURE.md` Module Map rows for every new file (`DocIntegrityTests` enforces this);
   - the sidecar `description`, rewritten truthfully for the new look (BUG-138: a description is ungated
     and must not overstate).

## Do NOT

- **Do NOT do FF.3's work:** no bloom, no fireflies lighting the grass or mist, no occlusion, no depth of
  field, no bokeh.
- **Do NOT retune or restructure the swarm model.** No constant changes, no tempo-source change, no
  coupling change. FF.1's parity is the gate. If placing the swarm in 3D seems to require changing the
  model, stop and report.
- **Do NOT go photographic, and do NOT ship a flat backdrop with sprites on top** (D-258 anti-references).
- **Do NOT commit, copy, trace or reproduce any of the nine prints**, and do not name the artist in any
  user-facing text.
- **Do NOT touch the rotation or certification settings:**
  - don't change `certified`, `rubric_profile` or `exclude_from_cycling`;
  - don't lower a rubric expectation or a gate floor to go green.
- **Do NOT widen D-157** or any frame-budget threshold, and do not use synthetic audio as diagnostic
  evidence (FA #27).
- **Do NOT bundle new engine infrastructure.** If the chosen technique needs one, stop and name it (Task 1).
- **Do NOT push without Matt's explicit "yes, push".** Push to a branch and open a PR; never push to `main`.
  If any push prints `Bypassed rule violations for refs/heads/main`, say so immediately.

## Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build
swift test --package-path UzumeEngine
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test
swift test --package-path UzumeEngine --filter Fireflies
FIREFLIES_PARITY=1 FIREFLIES_SEEDS=20 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine --filter FirefliesSpikeParityProbe
FIREFLIES_PARITY=1 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine --filter FirefliesRenderTests
Scripts/motion_gate.sh fireflies <film-dir>
COMPARE_REF_DIR=~/Documents/uzume_spikes/fireflies/references_danger Scripts/compare_render.sh fireflies <frames-dir>
Scripts/closeout_evidence.sh
```

Performance numbers are Release: `swift build -c release --package-path UzumeEngine`, or a standalone
`swiftc -O` bench. ⚠ `swift test -c release` does not currently run the engine suite; a separate task is
fixing that. State which you used.

## Commits (on `ff-2`, local, small, one per step)

- `[FF.2] tools: compare_render.sh optional reference-folder override`
- `[FF.2] Presets: Fireflies world — <what landed>`
- `[FF.2] Renderer: <shared camera / swarm placement in depth>`
- `[FF.2] Tests: <what the gates now cover>`
- `[FF.2] docs: plan row, registry, Module Map`

End each message with the attribution line the harness gives you. Push only on Matt's "yes, push", to the
branch plus a PR.

## Closeout

Invoke the `closeout` skill: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.
Add:
- the Task 1 grounding table;
- Matt's Task 4 verdict, verbatim;
- the final comparison sheet against the FF.R2 set, with its verdict table;
- the motion-gate verdict per film;
- the flash table at 1080p;
- the Release frame time;
- the 20-seed parity table, FF.2 against FF.1 against the spike;
- the rubric result;
- a one-line statement of which dispatch path the render tests exercised.

## DECISION — RESOLVED before the session (Matt, 2026-09-25: "B")

**Should the world itself respond to the music, or only the fireflies?**

- **A. Only the fireflies respond.** The wind and mist move on their own, steady and calm. On a track
  whose beat is irregular or unclear, the fireflies stay free, so almost nothing on screen tracks the
  music except the dimming at silence.
- **B. The world breathes with the music's energy, slowly.** The wind stirs the grass and the mist moves
  more in louder, fuller passages, swelling over several seconds and never pulsing on the beat. The beat
  stays the fireflies' alone. Every track, including the free ones, gets a visible connection to the
  music.

**Matt chose B.** Build it in Task 5. Do not ask again.
