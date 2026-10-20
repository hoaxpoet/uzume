# Increment EFB.1 — Energetic Flyby: faithful port, music drivers, photosensitivity fix, wiring (preset increment)

**Objective.** After this session an `Energetic Flyby` scene (working name) exists in Uzume and runs live:
Kali's *Energetic Flyby* (Shadertoy `csjGDD`) ported verbatim to a `direct` single-pass Metal fragment, driven by
an `EnergeticFlybyState` CPU buffer at slot 6 (the Nimbus pattern) that carries the music:
- **downbeat** → the sphere cluster's light bursts and its colour turns (0.35× echo on beat 3, nothing on 2 and 4);
- **energy** (self-normalised spectral flux) → flight speed and glow floor;
- **bass** (self-normalised `bassDev`) → sphere spin;
- **every second downbeat** → a quarter-turn camera bank, eased over 1 s, alternating direction.

The camera flies continuously: no holds, no cuts. The burst is bounded to the sphere light so global luminance
stays steady (D-157), and the one-frame white-out the spike found is fixed and measured. The scene ships
`certified: false`, is reachable with `UZUME_PIN_SCENE` and ⌘]/⌘[, and has harness, flash and timing evidence.
The session ends at a hard stop for **Matt's live look**.

**Not here:** M7 tuning (EFB.2), certification, `requires_regular_beat`, cold-start suppression, the scene's
final name.

## Skills to invoke

- `preset-session` — **before** opening any `.metal` file or writing the sidecar (session-start checklist, Audio
  Data Hierarchy, Cold-Start Phase Contract, FA #31/#67).
- `shader-authoring` — before writing any `.metal` or GPU-facing Swift. FA #73/#64/#65 apply in full: **port
  Kali's code verbatim and adapt only bindings**; do not "improve" the look.
- `closeout` — at the end: the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.

## Read first (in order)

1. `docs/presets/ENERGETIC_FLYBY_DESIGN.md` — all of it (short). §3 is the routing table; §4 the camera rule;
   §5 the photosensitivity requirements; §8 the licence obligations.
2. `docs/VISUAL_REFERENCES/energetic_flyby/README.md` and its five images. 01–04 are renders of the verbatim
   source; 05 is the anti-reference.
3. `docs/presets/energetic_flyby_spike/README.md`, then `energetic_flyby_kali.glsl` (**the porting source**) and
   `energetic_flyby_music_v3.glsl` (every spike change is marked `// MUSIC:` / `// FIX:`), and `prep_flyby3.py`
   (the driver maths the CPU state reproduces).
4. The Nimbus precedent, the closest shipped sibling (`direct`, `passes: []`, slot-6 state, per-frame tick):
   - `UzumeEngine/Sources/Presets/Nimbus/NimbusState.swift` (struct layout, `tick`, `reset`, `writeToGPU`);
   - `UzumeEngine/Sources/Presets/Shaders/Nimbus.metal:145-160` (`NimbusStateGPU` mirror) and `:372-382` (the
     fragment signature: `FeatureVector` at buffer 0, state at buffer 6);
   - `UzumeEngine/Sources/Presets/Shaders/Nimbus.json` (sidecar shape for a `direct` scene);
   - `UzumeApp/VisualizerEngine+Presets.swift`: `bindStatefulPresetRuntime` (`:581-600`), `bindNimbusRuntime`
     (`:855-883`, including `setDirectRenderScale`), `resetPerTrackPresetState` (`:91-115`), the teardown block in
     `applyPreset` (`:180-200`).
5. The downbeat and self-normalisation precedent: `UzumeEngine/Sources/Renderer/Geometry/FiddleheadFern+Dive.swift:100-140`
   (`squash` with the warm-up running mean, and the downbeat as `barPhase01` wrap). Read the comment on the
   FH.17 flash finding: the normaliser cold start caused a whole-frame flash transition.
6. The licence pattern: `UzumeEngine/Sources/Presets/Shaders/AuroraVeil.metal:1-30` (header) and
   `docs/CREDITS.md` §nimitz "Auroras" (entry format); `docs/DECISIONS.md` D-252.
7. Registries and gates that need an entry:
   - `UzumeEngine/Sources/Renderer/Geometry/ParticleGeometryRegistry.swift:65` (`StatefulRuntimeRegistry.knownPresetNames`);
   - `PresetLoaderCompileFailureTest.swift:147` (`expectedProductionPresetCount`, 34 at the base);
   - `GoldenSessionTests.catalog_isTheShippedRoster` (`:213`);
   - `FidelityRubricTests.expectedAutomatedGate`;
   - `PresetSidecarKeyGateTests`, `SidecarDescriptionDriftTests`, the black-backdrop name guards in `PresetAcceptanceTests`;
   - `PhotosensitivityCertificationTests.swift:260` (how `renderLuminanceSequence` ticks the real `NimbusState`)
     and `MultiPassFlashHarnessTests` (`fiddleheadIsFlashSafe`, `:246`) for the measured flash route;
   - `MultiPassRenderHarness.swift:60` (`multiPassPresets`) and `PresetFrameBudgetTests`.
8. `Scripts/compare_render.sh`, `Scripts/motion_gate.sh`, and the route-coverage fixtures
   `Fixtures/route_coverage/{love_rehab,so_what,there_there}/features.csv` with
   `Fixtures/beat_this_reference/*_reference.json`.

## Pre-flight invariants (each failure stops the session)

- **Docs committed first.** This prompt, `docs/presets/ENERGETIC_FLYBY_DESIGN.md`,
  `docs/VISUAL_REFERENCES/energetic_flyby/` (README + five JPGs) and `docs/presets/energetic_flyby_spike/` were
  authored in the design seat and left **untracked** in Matt's checkout. Step 0: create branch `efb-0` from an
  up-to-date `main`, commit exactly those files as `[EFB.0] docs: Energetic Flyby design, references, spike, EFB.1 prompt`,
  then branch `efb-1` from `efb-0` in its own worktree. If any of the files is missing, STOP.
- **References lint.** `swift run --package-path UzumeTools CheckVisualReferences` passes with the new folder.
- **Fixtures.** Worktrees lack the gitignored engine fixtures: run `Scripts/link_fixtures.sh`. The three
  route-coverage captures and their `beat_this_reference` JSONs must be present.
- **Baseline.** `Scripts/closeout_evidence.sh` is green at the base. Timing gates fail under parallel load; if a
  baseline test fails, re-run it isolated and record both results. Do not fix it here.
- **The spike reproduces.** `python3 docs/presets/energetic_flyby_spike/st_render.py
  docs/presets/energetic_flyby_spike/energetic_flyby_kali.glsl /tmp/efb_src 1280 720 3.0 3.04 30` writes a frame
  matching `01_macro_shell_tunnel.jpg` (needs `pip install moderngl pillow numpy`; on macOS use the default
  backend if `egl` is unavailable — edit only the spike copy in `/tmp`). This is the oracle for "what does the
  source do here": run it before theorising.

## Tasks

1. **Faithful port.** Add `UzumeEngine/Sources/Presets/Shaders/EnergeticFlyby.metal`: Kali's algorithm and
   constants verbatim in MSL.
   - Adaptations are **bindings only**, each listed in the file header the way `AuroraVeil.metal` lists its own:
     `iTime`/`time` → the state's clocks (task 2), `iResolution`/`gl_FragCoord` → `in.uv` + `features.aspect_ratio`,
     the y-flip, the 200-step loop as written.
   - Header: Kali's credit, `https://www.shadertoy.com/view/csjGDD`, Inércia Shader Royale 2022, and the
     **CC BY-NC-SA 3.0** notice (design doc §8). Add the `docs/CREDITS.md` entry in the nimitz format, naming the
     clean-room replacement from design doc §8.
   - **Faithful mode** for the fidelity check: an `EFB_FAITHFUL=1` environment path in the state (task 2) that
     feeds Kali's own behaviour: travel = time, spin = time, the burst = Kali's `fract(sin(time)*123.456)`, hue 0,
     roll 0, and Kali's camera park (`mod(time,10.)>5.`). It exists only to compare against the references; the
     shipped path never parks.

   **Done-when:** in faithful mode, `RENDER_VISUAL=1` stills at t = 3.0, 7.0, 12.5, 18.0 s go through
   `Scripts/compare_render.sh energetic_flyby` against 01–04, and the verdict table (one row per mandatory trait in
   the reference README, plus the anti-reference row) is all PASS. Differences from GPU vs llvmpipe precision are
   expected to be small; a structural difference (missing rods, wrong shell count, wrong palette) is a FAIL that
   changes the next action.

2. **`EnergeticFlybyState`** in `UzumeEngine/Sources/Presets/EnergeticFlyby/`, on the `NimbusState` pattern:
   a `tick(deltaTime:features:stems:)` that integrates and writes a small GPU struct (mirror it in the `.metal`,
   byte-for-byte, with a layout test).
   - `travel`: ∫ speed dt, speed = `0.65 + 0.8·energy` (spike values; constants are starting points).
   - `energy`: `spectralFlux` self-normalised against its own running mean with Fiddlehead's warm-up rule (plain
     running average until 8 s heard, then an 8 s follower), smoothed 0.6 s. **Never** a fixed p5–p95 or an
     absolute threshold (FA #31); the spike's offline percentile normalisation is not available live.
   - `spin`: ∫ `(1 + 3·bass)` dt, `bass` = positive `bassDev` self-normalised the same way, attack 30 ms /
     release 300 ms.
   - `burst`: on a downbeat (`barPhase01` wraps by more than 0.5) set to 1 and decay with τ 0.35 s; on beat 3
     (`barPhase01·beatsPerBar` crosses 2, only when `beatsPerBar ≥ 4`) take max with 0.35 and τ 0.20 s.
   - `hue`: +0.7 rad per downbeat, eased (smoothstep) over 0.25 s. `roll`: every second downbeat, ±π/2 eased over
     1.0 s, alternating sign.
   - `glowBase`: `0.45 + 0.5·energy`.
   - Clamp `deltaTime` (Witchlight precedent). `reset()` clears normalisers, envelopes and the bank sequence;
     `travel` and `hue` are **not** reset (design doc §6).

   **Done-when:** `EnergeticFlybyStateTests` pass, covering: a downbeat produces exactly one burst and one hue
   step; beat 3 produces the 0.35 echo and beats 2/4 nothing; roll is continuous (no step larger than a fixed
   per-frame bound) across a bank; travel is strictly increasing and never jumps; silence (all-zero features)
   keeps travel advancing at the floor speed; the normalisers' first 8 s do not produce a level more than 1.5× the
   settled level for a constant input (the FH.17 lesson); `reset()` leaves travel and hue untouched.

3. **Music in the shader + photosensitivity.** Wire the state into the fragment exactly where the spike did
   (`energetic_flyby_music_v3.glsl`), with two changes the spike did not have:
   - **Bound the burst** (design doc §5): the burst multiplies only the sphere-rod glow (`g`), not the tunnel
     glow (`li`) and not the combined term. The colour turn (`hue` added to the glow rotation) applies as in the
     spike.
   - **Keep the white-out fix** (`camGlow`: rods evaluated at the camera at the top of `march`, glow ×
     `mix(0.3, 1, smoothstep(0, 0.2, brCam))`), or replace it with something better that you measure.
   - **No camera park.** Delete Kali's `mod(time,10.)` branch on the shipped path (design doc §4).

   **Done-when:**
   - `MultiPassFlashHarnessTests` (or `PhotosensitivityCertificationTests` ticking the real state, as it does for
     Nimbus at `:260`; pick the one that runs the shipped path and say which) measures the scene on the worst-case
     train: **0.00 flashes/s**, regional ≤ 3/s, red 0.00;
   - a replay of `there_there` reports max Δ frame-mean luma per frame and the count of frames above 0.05, beside
     the spike's 0.168 / 7-above-0.1 numbers;
   - a white-out test renders frames on both sides of a forced rod-through-camera moment and shows the middle frame's
     mean luma within 1.25× of its neighbours.

4. **Wiring.**
   - `Shaders/EnergeticFlyby.json`: `name` "Energetic Flyby", `family` "fractal", `passes` `[]`,
     `fragment_function`, `vertex_function` "fullscreen_vertex", `rubric_profile` "full", `certified: false`,
     `complexity_cost` from task 7, and `audio_routes` for the three continuous/accent routes the code reads
     (`barPhase01` accent for the burst/hue/bank, `spectralFlux` continuous for speed/glow, `bassDev` continuous for
     spin). The `description` names only identifiers the scene reads (`SidecarDescriptionDriftTests`).
   - App: a `case "Energetic Flyby"` in `bindStatefulPresetRuntime` with a `bindEnergeticFlybyRuntime` on the
     Nimbus model (state at slot 6 + `setMeshPresetTick`); nil it out in the `applyPreset` teardown block; reset it
     in `resetPerTrackPresetState`. Add the name to `StatefulRuntimeRegistry.knownPresetNames`.
   - Tests needing an entry: `expectedProductionPresetCount` 34 → 35, `catalog_isTheShippedRoster`,
     `FidelityRubricTests.expectedAutomatedGate` (paste the measured value), `PresetSidecarKeyGateTests`, the
     black-backdrop guards if they apply, `multiPassPresets`/frame budget, and the flash route from task 3.
   - `docs/ARCHITECTURE.md` §Module Map: one behavioural line per new Swift file (D-168 gate).

   **Done-when:** `xcodebuild -scheme UzumeApp -destination 'platform=macOS' build` succeeds and the full engine
   suite is green.

5. **STOP AND REPORT if any golden session plan changes.** `certified: false` keeps the scene out of the planner;
   `GoldenSessionTests` plans must not move. If one does, do **not** regenerate goldens: stop and report the diff.

   **Done-when:** `swift test --package-path UzumeEngine --filter GoldenSession` passes with no golden file edited.

6. **Replay evidence on real music** (production dispatch path: the live `RenderPipeline` direct path with the
   slot-6 state ticked per frame, not `preset.pipelineState` alone).
   - Render 20 s of each route-coverage capture at 1080p with the capture's features as input.
   - **Continuity:** frame-to-frame structural difference, 0 frames above 3× median (the spike's measure), and
     `Scripts/motion_gate.sh energetic_flyby <frames>` with its motion verdict written into the transcript.
   - **Downbeat timing:** for every downbeat in `*_reference.json`, the frame of peak sphere-light burst is within
     ±1 frame (60 fps) of the downbeat. Report the hit rate per capture and n.
   - **Look:** `Scripts/compare_render.sh` on mid-song frames from two contrasting captures, verdict table.

   **Done-when:** the three numbers per capture and the two verdict tables are in the closeout.

7. **Release timing.** Measure GPU time in Release at 1080p and 4K on the dev Mac (state the machine).
   - If 1080p p95 is above 12 ms (the D-254 Tier-2 flagship ceiling), try `setDirectRenderScale` at 0.75 and 0.5,
     capture a still at each beside full resolution, and **do not choose**: Kali's look has fine edges, so the
     trade-off goes to Matt with the stills (DECISION-NEEDED below).
   - Set `complexity_cost` from the measurement.

   **Done-when:** p50/p95 per resolution and scale are in the closeout, with the stills if any scale was needed.

8. **HARD STOP — Matt's live look.** Build the app. Write Matt a short how-to: pin the scene
   (`UZUME_PIN_SCENE=Energetic Flyby`), the beta test playlist on local files, then one streaming pass. Ask him to
   watch for: whether the downbeat reads, whether the light burst is too much or too little, whether the speed
   following the energy reads, the bank, and any flash or pop. Stop.

## Do NOT

- **Do not add to the look.** No extra fog, bloom, grading, geometry or noise Kali did not write (FA #65, the
  Aurora Veil AV.2–AV.6 accretion). The music drivers and the photosensitivity fix are the only changes.
- **No camera holds, cuts or resets** on the shipped path (Matt, 2026-10-19; design doc §4).
- **No every-beat pulses.** The spike's round 2 failed Matt's blind A/B precisely because everything pulsed per beat.
- **No stems** (Matt: stem separation is not reliable enough; Inari's stem-bleed finding).
- No raw live onsets as drivers; no absolute thresholds on AGC-normalised values (FA #31).
- No cold-start beat-phase derivation (Cold-Start Phase Contract: retired; do not iterate).
- Do not certify, do not set `requires_regular_beat`, do not rename the scene.
- Do not regenerate goldens (task 5). Do not push.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine --filter EnergeticFlyby
swift test --package-path UzumeEngine --filter GoldenSession
swift run --package-path UzumeTools CheckVisualReferences
Scripts/closeout_evidence.sh
```

Performance numbers are Release-only (`xcodebuild -scheme UzumeApp -configuration Release …`); state the build
configuration with every number.

## Commit message templates

Small commits per logical step, local only:

- `[EFB.0] docs: Energetic Flyby design, references, spike, EFB.1 prompt`
- `[EFB.1] Presets: Energetic Flyby faithful port (Kali, csjGDD, CC BY-NC-SA 3.0) + CREDITS`
- `[EFB.1] Presets: EnergeticFlybyState — downbeat burst/hue/bank, energy speed, bass spin`
- `[EFB.1] Presets: bounded burst + camera-rod white-out fix; flash measured`
- `[EFB.1] App: wire Energetic Flyby (slot-6 state, tick, reset, teardown)`
- `[EFB.1] Tests: roster, rubric gate, flash route, frame budget`
- `[EFB.1] docs: module map, plan row, replay + timing evidence`

Push only on Matt's explicit "yes, push", to a branch with a PR; never directly to `main`.

## Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2.
Increment-specific additions:
- which dispatch path each test exercised (shipped direct path with ticked state vs. single-pass);
- the faithful-mode verdict table (task 1) and the replay verdict tables (task 6);
- per-capture continuity, downbeat hit rate and luminance numbers beside the spike's;
- the flash numbers (flashes/s, regional, red) and the white-out test result;
- Release timing per resolution and scale, with the machine named;
- `docs/ENGINEERING_PLAN.md` gets a Lane · Energetic Flyby table (EFB.0–EFB.3), and the render capability
  registry gets its row.

## DECISION-NEEDED (only if task 7 finds the scene over budget)

- **Question:** the scene costs more than the frame budget at full resolution; how should it trade sharpness for speed?
- **A — full sharpness, flagship only:** keep full resolution; the planner uses it only on Macs fast enough
  (Tier 2). Slower Macs never see it.
- **B — slightly softer everywhere:** render at 75 % resolution and upscale; fine shell edges and perforations
  soften a little, every Mac can run it.
- **C — noticeably softer:** 50 % resolution (Nimbus does this); the cheapest, but Kali's crisp edges are the
  look Matt chose it for.
- **Recommendation:** A if it fits Tier 2, else B, decided on the stills from task 7.
- **Default if no reply:** A.
