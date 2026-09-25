# Increment KAG.2 — Kagura dancer geometry, one dance: the twist (preset increment)

**Objective.** After this session a `Kagura` scene exists and renders: fifteen warm-white points on near-black,
each dragging a 0.4 s amber trail, dancing the **twist** in place with every hip-turn extreme landing on a
cached-grid beat. It:
- is a `KaguraDancer: ParticleGeometry` in `Renderer/Geometry/Kagura/`, reading KAG.1's `KaguraClipLibrary`;
- time-warps the twist clips onto the grid (KAGURA_DESIGN §5) from a **continuous** beat position;
- alternates the two twist clips on bar lines with a one-beat crossfade;
- sways (unwarped, never frozen) when there is no grid or, on the streaming path, no lock yet (§3a cold start);
- is wired through the registries, ships an uncertified sidecar, and has a harness case.

The gate is a still sheet, a motion gate and a **replay pulse-lock test** on the three checked-in
route-coverage captures (KAGURA_DESIGN §11).

**Not here** (KAG.3): dance selection, the other four dances, arm reach, the per-section grid-CV safety net,
the silence rest, `requires_regular_beat`, `audio_routes`, and M7.

## Skills to invoke

- `preset-session` — **before** opening any `.metal` file or writing the sidecar. It carries the scene
  session-start checklist (`docs/PRESET_SESSION_CHECKLIST.md`, mandatory), the Audio Data Hierarchy and the
  Cold-Start Phase Contract.
- `shader-authoring` — before writing any `.metal`, render pass or GPU-facing Swift.
- `closeout` — at the end: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## Read first (in order)

1. `docs/presets/KAGURA_DESIGN.md`: §1, §3, §3a, §5, §6 item 4 (the handoff), §7 (the declined-bar rule
   only), §8, §9, §11 (the KAG.2 row is the scope boundary), §12.
2. `docs/presets/kagura_spike/kagura.py`: `choose_level`, `warp_map`, `sample`, `build_dancer` (the
   segment loop, the one-beat crossfade, the ankle-midpoint handoff `offs`, the sway ping-pong `segs`, the
   leash), `render`/`_splat`/`project`, and `_extrema` + the `hipyaw` branch of `beat_events` (the
   pulse-lock detector). `cmd_film`'s pulse-lock block is the measurement you reproduce.
3. `docs/presets/kagura_spike/README.md` §5 (the twist films and their pulse-lock numbers) and §3 (look B).
4. `docs/VISUAL_REFERENCES/kagura/README.md` and its three images: the port anchors (look B, the sway, and
   the travelling-smear anti-reference).
5. `UzumeEngine/Sources/Renderer/Geometry/Kagura/KaguraClipLibrary.swift` (KAG.1): `shared()`,
   `clips(for:)`, `sway`, `pose(at:)`, `clipTime(atPulse:)`, `pulseEvents`, `pulsePeriod`, `allowedLevels`.
6. `UzumeEngine/Sources/Renderer/Geometry/ParticleGeometry.swift` (the protocol; `ensureAllocated` has a
   no-op default a geometry-owned trail must override).
7. The two proven precedents:
   - `Witchlight`: `WitchlightStroke.swift:198-231` (instanced bead quads); `WitchlightPath.swift:317` (the
     `deltaTime` clamp) and `:368-381`; and `bindWitchlightRuntime` in
     `UzumeApp/VisualizerEngine+Presets.swift:580-605` (pushing grid-derived data into a geometry).
   - `RicercarEcho`: `RicercarEchoGeometry.swift:125-145` and `:195-232` (geometry-owned ping-pong trail);
     `RicercarEchoGeometry+Sizing.swift:27` (`ensureAllocated`).
8. Registration surfaces:
   - `ParticleGeometryRegistry.swift:4-7` (its four-edit recipe) and `:57-74` (`StatefulRuntimeRegistry`);
   - `UzumeApp/VisualizerEngine.swift:320`, `:328`, `:980-982`, `:1384-1423`, `:1453-1467`;
   - `VisualizerEngine+Presets.swift:89-113` (`resetPerTrackPresetState`) and `:565-578`.
9. Grid and clock:
   - `DSP/BeatGrid.swift:19`, `MIRPipeline.swift:437-458` (what `FeatureVector` carries with and without a
     grid), `VisualizerEngine+Stems.swift:571-585` and `:705-727` (grid install and clear, both paths);
   - `LiveBeatDriftTracker.swift:68-75`, `:288-325`, `:406-430`;
   - `VisualizerEngine+Audio.swift:283` and `:390-400`, `PlaybackClockSmoother.swift:73`,
     `RenderPipeline.swift:786-793`, `RenderPipeline+Draw.swift:96-135` (the `features.time`/`deltaTime`
     overwrite; `particles.update` runs **before** the stateful tick, so tick data lands one frame late);
   - `DancePhase.swift` (the BUG-096 lesson).
10. Harness:
    - `MultiPassRenderHarness.swift:56-113` and `:309-340` (the render switch and Ricercar's case);
    - `Presets/WitchlightMotionSequenceTests.swift:43-99` (the `RENDER_VISUAL` sequence template);
    - `WitchlightFixtureDrive` (`:61-167`; capture CSV to `[FeatureVector]`);
    - `Fixtures/route_coverage/{love_rehab,so_what,there_there}/features.csv` (about 30 s, 43 Hz, with
      `playback_time_s`, `lock_state`, `drift_ms`);
    - `Fixtures/beat_this_reference/{love_rehab,so_what,there_there}_reference.json` (`beats_seconds`,
      `downbeats_seconds`);
    - `Scripts/compare_render.sh`, `Scripts/motion_gate.sh`.

## Pre-flight invariants (each failure stops the session)

- **Base.** This prompt and the Kagura references were committed on branch `kag-2-prompt`, which is on top
  of `main` after KAG.1 (#269).
  - If `kag-2-prompt` has been merged into `main`, branch `kag-2` from an up-to-date `main`.
  - Otherwise branch `kag-2` from `kag-2-prompt`: local if it was never pushed, `origin/kag-2-prompt` if it
    was.
  - Either way, the base contains KAG.1: `git log --oneline -1 --
    UzumeEngine/Sources/Renderer/Geometry/Kagura/KaguraClipLibrary.swift` must print a `[KAG.1]` commit.
  - `swift test --package-path UzumeEngine --filter KaguraClipLibrary` passes 7/7.
- **References.** `docs/VISUAL_REFERENCES/kagura/` holds the README and three PNGs.
- **Fixtures.** Worktrees lack the gitignored engine fixtures: run `Scripts/link_fixtures.sh` first. The three
  route-coverage captures and their `beat_this_reference` JSONs must be present.
- **Baseline.** `Scripts/closeout_evidence.sh` is green at the base commit.
  - Timing and performance gates fail under load when another session's suite runs at the same time. On
    2026-09-25 that produced DSP perf, PostProcess 2 ms, RayMarch 8 ms, SessionRecorder ProRes, and Stave
    61 ms; all five passed in isolation.
  - If a baseline test fails, re-run it isolated and record both results. Do not "fix" it here.
- **The spike runs.** `~/Documents/uzume_spikes/kagura/.venv/bin/python docs/presets/kagura_spike/kagura.py
  --help` works. The spike is the oracle for behavioural questions: run it before theorising.

## Tasks

1. **Clock and grid input: plain data into Renderer.** Renderer cannot see `BeatGrid` (DSP), so the app
   pushes plain data.
   - **The grid:** beat times, downbeat times, `beatsPerBar` and `hasBarInformation`. Push it on each grid
     install or clear on both paths, and reset it per track.
   - **The musical position:** the dancer's beat position `p(t)` must be **continuous at render rate**.
     - Compute it from the grid's beat times and a render-rate playback position.
     - Never compute it from the stepped `beatPhase01` (about 14.6 Hz, BUG-096; KAGURA_DESIGN §5).
     - *Local-file path:* the playback clock is the only source (BUG-087). Use the smoothed position
       (`PlaybackClockSmoother`), and verify it is live on the local-file path even when no stem series is
       installed; if it is not, find what is.
     - *Streaming path:* `playbackTime + drift`, as the drift tracker's relative beat times use it.
   - **The one-frame lag.** The stateful tick runs after `particles.update`. Stamp each pushed position with
     the render clock and extrapolate by elapsed render time in `update`, so the dancer never runs one frame
     behind.
   - **Lock state (streaming)** for cold start.

   **Done-when:**
   - a unit test drives the input at 60 Hz from a real beat list and a jittery clock (steps like the
     capture's 43 Hz `playback_time_s`), and asserts `p(t)` is strictly increasing with no step larger than
     twice the nominal per-frame advance;
   - the same test fails if `p` is computed from `beatPhase01`.

2. **`KaguraDancer`: the warp and the dance, CPU side.** A pure, testable core, kept separate from the GPU
   code.
   - **Level.** Choose `m` from the clip's `allowedLevels` with `choose_level`'s rule. The twist never uses
     ×½.
   - **Warp.** Pulse position `u = u0 + (p − p0)/m`, clip time `c = clip.clipTime(atPulse: u)`, pose
     `clip.pose(at: c)`. Pulse events land on integer beats, so the phase correction is spread across each
     beat. Anchor `u0`/`p0` so each clip's first pulse lands on a beat.
   - **Clip changes.** On a bar line, at most every 4 bars, sooner if the clip's pulse map runs out.
     - Alternate the two twist clips.
     - With no bar information (`beatsPerBar == 1` or no downbeats), change every 4 beats (D-210).
   - **Handoff.** Crossfade over one beat with smoothstep. The incoming clip is placed so the midpoint of
     its ankles matches the outgoing clip's at the cut; the camera never moves.
   - **Sway.** Clip `sway`, unwarped, played ping-pong (forward then backward; a modulo wrap teleports the
     figure).
     - It plays when there is no grid, and on the streaming path until `lockState ≥ 1`.
     - It joins or leaves the dance at a bar line with the same one-beat crossfade.
     - It never freezes.
   - **Framing.** The spike's leash is a **zero-phase** Gaussian of the pelvis floor path; it cannot run in
     real time. Choose a causal equivalent that keeps the figure framed across many clip changes, and
     measure its foot-slide cost against the spike's (README §5 foot-slide columns).
   - **Clock.** Use render-rate time throughout. Clamp `features.deltaTime` as Witchlight does.

   **Done-when:** `KaguraDancerTests` pass, covering:
   - level choice at 80, 117 and 166 BPM (never ×½ for the twist);
   - clip changes only on bar lines, and every 4 beats when the bar is declined;
   - crossfade continuity: no joint moves more than a small fixed bound between consecutive 60 fps frames
     across a handoff, and the same holds at the sway↔dance transitions;
   - the sway with no grid and while unlocked;
   - the sway's ping-pong never teleports;
   - the figure's pelvis stays inside a fixed frame box over 5 minutes of synthetic 120 BPM grid.

3. **Render: look B** (KAGURA_DESIGN §8). Geometry kernels go in
   `UzumeEngine/Sources/Renderer/Shaders/Kagura.metal`.
   - **Trails.** A geometry-owned ping-pong `rgba16Float` trail texture, following Ricercar's pattern.
     - Each frame: decay by **`0.05^(dt / 0.4 s)` per elapsed time, not per frame** (BUG-097). Then deposit
       line segments from each joint's previous to its current projected position, in amber
       (`255, 170, 110`).
   - **Points.** Instanced quads (Witchlight's bead pattern) with a soft core and a wide dim halo, warm white
     (`255, 236, 214`).
   - **Composite.** Trail, then halo, then core, then the soft filmic shoulder `1 − exp(−1.6·x)`, over ground
     `4, 5, 9`.
   - **Projection.** Orthographic, 35° yaw, fixed.
     - The spike's framing at 720 px tall is 255 px per metre with the floor at 0.88·H, a core σ of 2.6 px
       and a halo σ of 9 px. Scale all of these with drawable **height**, and centre on the width.
   - **Luminance stays steady:** nothing brightens on the beat (D-157).

   **Done-when:**
   - a test renders the same 2 s of motion at 30, 60 and 120 fps and shows the trail's decay is the same in
     wall time;
   - the still frames' framing matches reference `01` (compared in task 6).

4. **Wiring.**
   - **Scene files.** Add `UzumeEngine/Sources/Presets/Shaders/Kagura.metal` (a near-black backdrop
     fragment) and `Kagura.json`: `name` "Kagura", `family` "dancer", `passes` `["feedback", "particles"]`,
     `rubric_profile` "lightweight", `certified: false`.
     - The sidecar carries no `audio_routes` and no `requires_regular_beat` (KAG.3).
     - Its `description` names no identifier the scene does not read (`SidecarDescriptionDriftTests`).
   - **Registries.** Follow `ParticleGeometryRegistry`'s four-edit recipe and add the `StatefulRuntimeRegistry`
     entry and binding for task 1's push. Add the per-track reset in `resetPerTrackPresetState`.
   - **Tests that need a Kagura entry:**
     - `PresetLoaderCompileFailureTest.expectedProductionPresetCount` (and the roster in
       `GoldenSessionTests.catalog_isTheShippedRoster`);
     - `FidelityRubricTests.expectedAutomatedGate`;
     - the black-backdrop name guards in `PresetAcceptanceTests` (the `:100` and `:281` patterns);
     - `PresetSidecarKeyGateTests`.
   - **Harness.** Add a `MultiPassRenderHarness` case and `renderKagura`, add Kagura to `multiPassPresets`
     (frame budget), and add a `MultiPassFlashHarnessTests` `@Test`.

   **Done-when:** `xcodebuild -scheme UzumeApp -destination 'platform=macOS' build` succeeds, and the full
   engine suite is green.

5. **STOP AND REPORT if any golden session plan changes.** `certified: false` should keep Kagura out of the
   planner (`PresetScorer.swift:206-211`), so `GoldenSessionTests` plans must not move.
   - If any plan changes, do **not** regenerate goldens. Stop and report the diff.

   **Done-when:** `swift test --package-path UzumeEngine --filter GoldenSession` passes with no golden file
   edited.

6. **Replay pulse-lock test + look evidence.**
   - **The pulse-lock test.** `KaguraPulseLockReplayTests` drives each route-coverage capture frame by frame.
     - Inputs: the capture's `playback_time_s` as the clock, and the matching `beat_this_reference`
       `beats_seconds`/`downbeats_seconds` as the grid.
     - Detection: port the spike's `_extrema` and `hipyaw` detector into the test **verbatim** (FA #73), and
       run it on the **dancer's output joint positions**, not on the pulse map; checking the pulse map
       would only confirm the design.
     - Report per capture: the fraction of hip-yaw events within ±⅛ beat of a grid beat (chance 25 %), the
       fraction on the half-beat, and n.
   - **The decoy (negative control).** Re-run with the grid shifted +½ beat. The events must move wholesale
     to the half-beat. Quote the chance level beside every figure.
   - **Setting the threshold.** Measure first. The spike's twist figure is ≥ 90 % (100 % in README §5).
     - If any capture measures **below 90 %, STOP and report**; do not tune toward the number.
     - Otherwise set the assertion threshold from your own first measurement minus a stated margin, never
       below 90 %.
   - **Look evidence.**
     - A `RENDER_VISUAL=1` Kagura sequence test on the Witchlight template, writing `kagura_seq_*.png`.
     - `Scripts/compare_render.sh kagura` against `docs/VISUAL_REFERENCES/kagura/`, with a written verdict
       table (trait | reference | PASS/FAIL | what differs). The anti-reference row is mandatory.
     - `Scripts/motion_gate.sh kagura`: spike count, sampled frames read as a sequence, and the
       `target_animated.gif`.
     - The frame budget in **Release**, with the build configuration stated.

   **Done-when:**
   - the replay test passes on all three captures and the decoy flips;
   - the sheet and motion-gate artifacts exist and are read, with verdicts written;
   - the Release frame cost is recorded.

7. **Docs.**
   - `docs/ARCHITECTURE.md` Module Map: a row for every new `.swift` and `.metal` file (DocIntegrityTests
     enforces it).
   - `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`: a row for *beat-grid time-warped captured motion (a
     `ParticleGeometry` fed grid beat times from the app)*, plus a preset-implications line.
   - `docs/ENGINEERING_PLAN.md`: flip the KAG.2 row, with evidence.
   - `KAGURA_DESIGN.md`: record what the build settled (the causal leash, how `p(t)` is sourced on each
     path).
     - Note that the QG.1 route schema has **no `grid` kind** (only continuous / accent / structural /
       gate), which §9 assumed. KAG.3 must choose the declaration; do not add a kind here.

   **Done-when:** `swift test --package-path UzumeEngine --filter DocIntegrityTests` passes.

8. **Closeout** (see below).

## Do NOT

- Do not build dance selection, the other four dances, arm reach, the grid-CV safety net, the silence rest,
  `requires_regular_beat`, `audio_routes`, or the arousal work. That is KAG.3.
- Do not certify, add Kagura to `certifiedPresets`, or enrol it in `PhotosensitivityCertificationTests`.
  That is KAG.4.
- Do not change the clips, windows, pulse maps or `bake_clips.py`. The KAG.1 resource is fixed. If the warp
  seems to need different data, stop and report.
- Do not drive motion from raw live onsets or from `beatPhase01`'s staircase. Use the cached grid only,
  with a continuous `p(t)` (Audio Data Hierarchy; BUG-096).
- Do not use a per-frame trail decay constant (BUG-097), or anything that brightens on the beat (D-157).
- Do not use the mv_warp `point` primitive (KAGURA_DESIGN §8: its warp would displace the trails).
- Do not add a route kind, touch D-154 thresholds or `assessBeatIrregularity`, or regenerate goldens (task
  5).
- Do not push without Matt's explicit "yes, push". When approved, push the branch and open a PR. **Never
  push to `main`.**

## Verification

```bash
swift test --package-path UzumeEngine --filter "KaguraDancer|KaguraPulseLockReplay|KaguraClipLibrary"
```
```bash
RENDER_VISUAL=1 swift test --package-path UzumeEngine --filter KaguraMotionSequence
```
```bash
Scripts/compare_render.sh kagura
```
```bash
Scripts/motion_gate.sh kagura
```
```bash
swift test --package-path UzumeEngine --filter "GoldenSession|PresetLoaderCompileFailure|FidelityRubric|PresetAcceptance|ParticleDispatchRegistry|StatefulRuntimeRegistry|SidecarDescriptionDrift|PresetSidecarKeyGate|MultiPassFlashHarness|PresetFrameBudget"
```
```bash
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
```
```bash
swiftlint lint --strict --config .swiftlint.yml
```
```bash
Scripts/closeout_evidence.sh
```

## Commits (local; small, one per step)

- `[KAG.2] Renderer: Kagura clock + grid input (continuous beat position)`
- `[KAG.2] Renderer: KaguraDancer warp, clip changes, sway, framing`
- `[KAG.2] Renderer: Kagura look B — trail texture, point sprites, composite`
- `[KAG.2] Presets+App: Kagura sidecar, backdrop, registry + runtime wiring`
- `[KAG.2] tests: KaguraDancerTests, pulse-lock replay + decoy, harness case`
- `[KAG.2] docs: Module Map, capability registry, EP row, design notes`

## Closeout

Invoke `closeout`: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Add:
- **The pulse-lock table:** per capture, on-beat %, half-beat %, n, and chance (25 %), beside the decoy's
  figures and the spike's README §5 twist figures.
- **§3:** the `compare_render.sh` sheet path with its verdict table, and the `motion_gate.sh` verdict, spike
  count and GIF path.
- **The Release frame cost**, with the build configuration stated.
- **How `p(t)` is sourced** on the local-file and streaming paths, and the measured one-frame-lag handling.
- **The causal leash's foot-slide** against the spike's.
- **Status:** "pending live M7 (KAG.3)". The live look with audio is the R1 question the concept rests on.
  Offer Matt a live look at the twist on a steady local track, but it does not block KAG.2.

## DECISION-NEEDED

None. Every product call this increment depends on is recorded (KAGURA_DESIGN §3a, §5, §6 item 4, §8, §11).
Engineering choices (how the clock reaches the geometry, the causal leash) are the session's, measured and
recorded in the closeout.
