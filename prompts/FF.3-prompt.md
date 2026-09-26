# Increment FF.3 — Fireflies: the light (preset increment)

**Objective.** After this session, each firefly is a LIGHT in the screenprint world FF.2 built, drawn the
way the FF.R2 prints draw light (D-258):
- a near-white core with a coloured bloom, the brightest thing in the frame;
- light that falls only on what is right around it: the grass strokes, the mist and the nearby
  branches brighten locally when a firefly flashes near them;
- fireflies behind a tree trunk, a branch or a foreground grass stalk are hidden by it;
- the nearest fireflies read as soft, out-of-focus discs;
- a unison flash is still hundreds of small lights, never a frame-wide lift (D-157).

**The session's first deliverable is ONE still beside `09` and `07`, and it stops there for Matt to
accept or reject the direction (Task 3).** Nothing past Task 3 happens without his yes.

**Not here:** FF.4 (M7 on the beta playlist, certification, removing `exclude_from_cycling`). No change to
the swarm's behaviour, the world's geometry or composition, or the breath route (FF.1/FF.2 are the
gates).

## Skills to invoke

- `preset-session`: before opening any `.metal` file or editing the sidecar (checklist, Audio Data
  Hierarchy, FA #67).
- `shader-authoring`: before any `.metal`, render pass or GPU-facing Swift. Its FA #64/#65/#73
  desk-research rules govern Task 1.
- `session-forensics`: before replaying any capture.
- `closeout`: at the end, the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## Read first (in order)

1. `docs/presets/FIREFLIES_DESIGN.md`: all of it (short). §3 and §4.4 are this increment.
2. `docs/VISUAL_REFERENCES/fireflies/README.md` §FF.R2: the style rules and what each print is for.
3. The local-only prints in `~/Documents/uzume_spikes/fireflies/references_danger/`: look at **`09`**
   (how a point light reads: hot core, halo, starburst), **`07`** (one glow lighting only its
   surroundings), **`04`** (a glow as the light source in dark woods) and **`06`** (many small lights
   over layered distance) at full size. The same rules as FF.2: never copy them into the repo, never
   trace or reproduce a print, never name the artist in user-facing text (the sidecar `description`
   included).
4. `docs/DECISIONS.md`: D-258, D-157, D-037, D-029 (use the §Index).
5. FF.2's code — the world you are lighting; do not recompose it:
   - `UzumeEngine/Sources/Renderer/Geometry/FirefliesWorld.swift` (the shared camera, the breath, the
     branch and grass skeletons in far → near painter's order);
   - `FirefliesGeometry.swift` (`upload`: each firefly's 3D point and its FF.1 size/brightness formulas;
     `render`: branches, then sprites);
   - `Renderer/Shaders/Fireflies.metal` (sprites + `fireflies_branch_*`);
   - `Presets/Shaders/Fireflies.metal` (the world fragment: `ff_ink`, `ff_print`, the mist).
6. `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` rows:
   - the three FF.2 rows (screenprint treatment, shared camera, static 3D line skeletons);
   - the Fireflies pulse-coupled swarm row;
   - Ricercar's HDR trail (a `ParticleGeometry` that owns a resolution-dependent offscreen target via
     `ensureAllocated` and composites it in `render`);
   - "Bloom (bright-pass + ping-pong blur)" and "ACES tone-map composite": `PostProcessChain`. **Verify
     whether it runs on the `particles` / `drawDirect` path at all before planning around it.**
   - the photosensitivity flash-safety gate row.
7. `docs/ARCHITECTURE.md §GPU Contract Details`: before authoring any pass. Slots 7 and 8 of the direct
   path are bound from `setDirectPresetFragmentBuffer2/3` when non-nil.
8. The harness: `MultiPassRenderHarness.renderFireflies`; `FirefliesRenderTests` (`lookStills`,
   `spikeCapturesAt1080p`, `silenceFilm`, `breathIsVisible`, `frameCostAt1080p`); `FirefliesSwarmTests`
   (`FirefliesDrive`, the parity probe); `PresetFrameBudgetTests` (Fireflies' baseline row);
   `Scripts/compare_render.sh` (`COMPARE_REF_DIR`), `Scripts/motion_gate.sh`.

## Pre-flight invariants (each failure stops the session)

- **Base.** `main` at or after `3c3ddd1d` (FF.2, #281). If this prompt's branch `ff-3-prompt` has been
  merged, branch `ff-3` from an up-to-date `main`; otherwise from `origin/ff-3-prompt`. Stay in this
  session's own worktree: never `git worktree add`.
- **References.** The nine `0N_*.jpg` prints are in `references_danger/`. If missing, stop and ask Matt.
- **Captures.** `~/Documents/uzume_spikes/fireflies/sessions/` holds the four parity captures plus
  `fixturegen-Warszawa_tail` (the near-silence film).
- **Fixtures.** Run `Scripts/link_fixtures.sh` first.
- **FF.2 is green at the base.** Record the numbers:
  - `swift test --package-path UzumeEngine --filter Fireflies` passes;
  - `FIREFLIES_PARITY=1 FIREFLIES_SEEDS=20 FIREFLIES_PARITY_OUT=<dir> swift test --package-path
    UzumeEngine --filter FirefliesSpikeParityProbe` passes with FF.2's 20-seed means: DYC R 0.972 /
    on-beat +0.843, Pyramid 0.975 / +0.812, Warszawa 0.196 / +0.007, Teardrop 0.137 / −0.008;
  - FF.2's 1080p flash (max Δ frame-mean luma): DYC 0.0099, Pyramid 0.0124, Warszawa 0.0016, Teardrop
    0.0014 (gate 0.05). **This is the number the bloom will push on.**
  - ⚠ Run every env-gated probe **filtered, never inside the full suite**.
- **Baseline.** `Scripts/closeout_evidence.sh` at the base commit. A known pre-existing failure may
  still be present: the app test host SIGSEGVs when the app tests run straight after the engine suite
  (being fixed in its own session). If step 2 fails, re-run `xcodebuild … test` isolated and record
  both results; do not fix it here.

## Tasks

1. **Ground the technique before building it.** Four mechanisms, each needing a grounded approach:
   - **(a) the light itself**, in the screenprint style: near-white core, coloured bloom/halo, `09`'s
     starburst — and how it survives the six-ink quantisation (is the light printed in ink 5 plus the
     firefly colour, or drawn above the print?);
   - **(b) light on the surroundings**: the grass strokes, mist and near branches brighten only within a
     short radius of a lit firefly. The world fragment would need to know where the lit fireflies are
     (a light list at slot 7, or a geometry-owned light-field target, or another route);
   - **(c) occlusion** by tree trunks, branches and foreground grass. There is no depth attachment on
     the direct path; depth-banded painter's order (interleaving the far → near segment bands with the
     sprites) is one route within the geometry;
   - **(d) out-of-focus near fireflies**: disc shape and size from true depth.

   Do the desk research the `shader-authoring` skill requires, for example:
   - many-light shading with a bounded per-pixel cost (tiled/clustered or binned light lists);
   - screen-space glow/bloom without a post chain, and point-light starbursts;
   - bokeh / circle-of-confusion sprites;
   - how the engine's existing paths can host it (slots 7/8, a geometry-owned target, the post chain
     if and only if it runs on this path).

   Grounding levels, in order of preference: a working code reference; a paper with implementable
   math; nothing. Prefer adopting a working reference over deriving one (FA #73).
   - **Done-when:** a grounding table (mechanism × approach × level × citation) in the transcript and
     later the closeout.
   - **If any mechanism is level 3, or needs a new engine surface** (a depth attachment on the direct
     path, a new pass kind, a protocol change), **stop and bring it to Matt** with the named
     infrastructure; don't bundle it.
2. **The look still.** Build just enough light to render the real scene through the production draw
   path.
   - **Two frames at 1920×1080:** DYC's locked-unison peak (frame 1221, `lookStills`) and a free-swarm
     moment from the Warszawa capture (scattered single flashes — the light at its sparsest).
   - **Done-when:** both PNGs exist; a comparison sheet (`COMPARE_REF_DIR` pointing at a local folder
     of `09`, `07`, `04`, `06` — symlinks, never copies in the repo); a verdict table in the transcript,
     one row per FF.R2 rule and per anti-reference plus the §4.4 requirements: `trait | reference |
     PASS/FAIL | what differs`; and the 1080p D-157 max Δ on DYC measured on this build.
3. **HARD STOP — Matt's accept/reject.** Show Matt the sheet, the two frames, the verdict table and the
   DYC flash number. Ask one question: *does this light clear the bar?* **Stop and wait.**
   - **Reject** or "not yet": record his words and one sentence on what you now believe is wrong.
     Revise at most once and come back. Two consecutive rejections whose cause you cannot articulate
     are a `preset-session` escalation.
   - **Accept:** continue to Task 4.
4. **Complete the light** (after acceptance): all of §4.4 — the light on grass, mist and branches;
   occlusion by trunks, branches and foreground grass; out-of-focus near fireflies; a flash's light
   rising and decaying with the FF.1 envelope (40 ms rise, 0.11 s decay), never slower.
   - **Done-when:** `RENDER_VISUAL=1` stills and a contiguous frame sequence exist; the comparison sheet
     against the FF.R2 set carries a verdict table; a `Scripts/motion_gate.sh` verdict is written
     (smooth, on-concept in motion — a unison flash reads as many lights, occlusion never pops).
5. **Evidence in the real pipeline.**
   - **Flash (the binding constraint):** D-157 at 1920×1080 through the real draw path on all four
     captures (max Δ frame-mean luma < 0.05; report the per-second range). **If the bloom breaks it,
     shrink the bloom — never the gate.**
   - **Films** for all four parity captures plus the Warszawa-tail silence film, each with a motion-gate
     reading; the silence film must stay lit and keep moving (D-037).
   - **Parity:** the filtered 20-seed probe still returns FF.2's means (the model is not touched).
   - **Breath:** `FIREFLIES_BREATH=1` still shows the world answering the breath (FF.2: 3.3× DYC, 1.7×
     Pyramid, camera held still) — the light must not swamp it.
   - **Performance:** Release frame time at 1080p (`FIREFLIES_TIMING=1 swift test -c release
     --enable-testable-imports …`), stating the configuration of every number; 60 fps is the bar. The
     Debug `PresetFrameBudgetTests` stays inside its outlier (8×) and absolute (60 ms) nets; if
     Fireflies' cost changes, re-record its baseline row from an **isolated** run only, with a comment.
   - **Rubric** (`FidelityRubricTests`), reported honestly against FF.2's 2/15.
   - **Done-when:** all measured and tabled; a red gate is reported, never widened.
6. **Docs.** Update in the same branch:
   - `ENGINEERING_PLAN.md`: the FF.3 row and a completed entry;
   - `RENDER_CAPABILITY_REGISTRY.md`: new capability rows (e.g. many-light local lighting in a
     screenprint world, occlusion by depth-banded painter's order, bokeh sprites) and the Fireflies row;
   - `ARCHITECTURE.md` Module Map rows for every new or changed file (`DocIntegrityTests` enforces it);
   - `FIREFLIES_DESIGN.md` status line;
   - the sidecar `description`, rewritten truthfully (BUG-138).

## Do NOT

- **Do NOT retune or restructure the swarm model** (`FirefliesSwarm`): no constant, tempo-source or
  coupling change. FF.1's parity is the gate. If the light seems to need a model change, stop and report.
- **Do NOT recompose the world** (camera path, tree layout, tree line, inks, hatching) or change the
  breath route. If the light only works with a changed world, stop and bring it to Matt.
- **Do NOT make the light frame-wide:** no global exposure lift, no full-frame bloom wash on a unison
  flash (D-157). A flash lights only what is right around each firefly.
- **Do NOT go photographic** (D-258): the light is printed, not a physically based lens effect.
- **Do NOT widen D-157** or any frame-budget threshold, and do not use synthetic audio as diagnostic
  evidence (FA #27).
- **Do NOT touch** `certified`, `rubric_profile` or `exclude_from_cycling`, and do not lower a rubric
  expectation to go green.
- **Do NOT bundle new engine infrastructure** (Task 1's stop rule).
- **Do NOT commit, copy, trace or reproduce any print**, or name the artist in user-facing text.
- **Do NOT push without Matt's explicit "yes, push".** Push to a branch and open a PR; never push to
  `main`. If any push prints `Bypassed rule violations for refs/heads/main`, say so immediately.

## Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build
swift test --package-path UzumeEngine
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test
swift test --package-path UzumeEngine --filter Fireflies
FIREFLIES_PARITY=1 FIREFLIES_SEEDS=20 FIREFLIES_PARITY_OUT=<dir> swift test --package-path UzumeEngine --filter FirefliesSpikeParityProbe
FIREFLIES_PARITY=1 FIREFLIES_PARITY_OUT=<dir> FIREFLIES_SILENCE_OUT=<dir> swift test --package-path UzumeEngine --filter "FirefliesRenderTests/(spikeCapturesAt1080p|silenceFilm)"
FIREFLIES_BREATH=1 swift test --package-path UzumeEngine --filter "FirefliesRenderTests/breathIsVisible"
FIREFLIES_TIMING=1 swift test -c release --enable-testable-imports --package-path UzumeEngine --filter "FirefliesRenderTests/frameCostAt1080p"
Scripts/motion_gate.sh fireflies <film-dir>
COMPARE_REF_DIR=<local folder of prints> Scripts/compare_render.sh fireflies <frames-dir>
Scripts/closeout_evidence.sh
```

⚠ The DOC.6 rotation gate flips at UTC midnight (19:00 CDT): if `DocIntegrityTests` goes red on
"entries older than 14 days", run `Scripts/rotate_docs.sh` and commit that alone as `[DOC.6]`.

## Commits (on `ff-3`, local, small, one per step)

- `[FF.3] Renderer: <the light / occlusion / bokeh>`
- `[FF.3] Presets: Fireflies world — <light on the surroundings>`
- `[FF.3] Tests: <what the gates now cover>`
- `[FF.3] docs: plan row, registry, Module Map`

End each message with the attribution line the harness gives you. Push only on Matt's "yes, push", to
the branch plus a PR.

## Closeout

Invoke the `closeout` skill: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as
§2. Add:
- the Task 1 grounding table;
- Matt's Task 3 verdict, verbatim;
- the final comparison sheet against the FF.R2 set, with its verdict table;
- the motion-gate verdict per film;
- the flash table at 1080p, FF.3 against FF.2;
- the Release frame time;
- the 20-seed parity table and the breath-visibility ratios, FF.3 against FF.2;
- the rubric result;
- a one-line statement of which dispatch path the render tests exercised.

## DECISION — RESOLVED before the session (Matt, 2026-09-26: "A")

**What colour is a firefly's light?** (Everything else in the frame stays blue ink; this is the one warm
colour — §3.)

- **A. Yellow-green, as now.** The true colour of a real firefly (Photinus). Against the blue it reads
  unmistakably as fireflies, a little cool for a "warm" light.
- **B. Warm gold.** The classic warm lamp in a blue print: cosier and more storybook, less like a real
  firefly.
- **C. Near-white with a faint yellow-green edge.** Closest to how the prints draw light (`09`'s white-hot
  lamps); the firefly colour survives only at the rim of each glow.

**Matt chose A: yellow-green**, the swarm's existing colour, with the near-white core on top. Build it.
Do not ask again.
