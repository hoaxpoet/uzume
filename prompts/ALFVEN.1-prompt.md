# Increment ALFVEN.1 — persistent + iterated staged stages, and the Poisson projection (infrastructure increment)

**Objective.** After this session the `staged` paradigm can express a **stateful, iterated GPU
solver**: a stage may own a ping-pong texture pair that survives across frames, may run N times
per frame ping-ponging its own output, and may declare its own pixel format. On top of that
surface, a new `Poisson Sandbox` diagnostic preset solves `∇²p = f` by Jacobi iteration and is
asserted to converge against an analytic solution. **No Alfvén preset, no shader art, no audio
routing** — this increment builds and proves the engine surface that ALFVEN.2 will consume.

The motivating design is `docs/presets/ALFVEN_DESIGN.md` §6. Read it for the *why*, but nothing
in this increment is Alfvén-specific: `persistent`, `iterations` and `pixel_format` are generic
staged-composition capabilities and must be built and named as such.

## Skills to invoke

- `shader-authoring` — BEFORE writing any `.metal` or GPU-facing Swift (GPU contract, quality
  floor, and the FA #73/#65 porting discipline that governs task 4).
- `closeout` — at the end (8-part report + verbatim `Scripts/closeout_evidence.sh` block as §2).
- **Do NOT** invoke `preset-session`: no shipping preset is authored here. The Poisson Sandbox is
  a diagnostic (`is_diagnostic: true`), the same class as `Staged Sandbox`.

## Read first (in order)

1. `docs/presets/ALFVEN_DESIGN.md` §6 (engine surface required), §8 (stability requirements),
   §10 (increment plan) — the scope boundary for this session lives in §10.
2. `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` — the staged-composition entry; this increment
   extends it and must update it.
3. `UzumeEngine/Sources/Presets/PresetStage.swift` — the sidecar type being extended.
4. `UzumeEngine/Sources/Renderer/RenderPipeline+Staged.swift` — the encoder. Note `encodeStage`
   is `internal` so tests drive it without an `MTKView`, and sampled stage outputs bind from
   `kStagedSampledTextureFirstSlot` (= 13). Both properties must survive this change.
5. `UzumeEngine/Sources/Presets/Shaders/StagedSandbox.json` + `StagedSandbox.metal` — the
   canonical staged authoring pattern the new diagnostic copy-adapts.
6. `UzumeEngine/Tests/UzumeEngineTests/Presets/StagedPathHarnessTemplate.swift` and
   `HarnessTemplateCore.swift` — the harness spine to extend (QG.4 / D-182: adapt the template
   matching the paradigm; do not reinvent).
7. `docs/ARCHITECTURE.md` §GPU Contract Details — texture/buffer slot allocation, before adding
   any binding.
8. **The port reference** — https://github.com/PavelDoGreat/WebGL-Fluid-Simulation (MIT),
   `script.js`: `divergenceShader`, `pressureShader`, `gradientSubtractShader`. Read these three
   before writing task 4. Also Harris, *Fast Fluid Dynamics Simulation on the GPU* (GPU Gems 3
   ch. 38) for the pass structure.

## Pre-flight invariants (each failure stops the session)

- Branch: start from `main` at a clean tree. This increment has no predecessor branch.
- Gates green at head before any edit: `swiftlint lint --strict` = 0 violations;
  `xcodebuild -scheme UzumeApp -destination 'platform=macOS' build` = SUCCEEDED;
  `swift test --package-path UzumeEngine` = pass.
- `docs/presets/ALFVEN_DESIGN.md`, `docs/presets/ALFVEN_CONCEPT_2026-09-08.md`,
  `docs/presets/ALFVEN_PORT_SURVEY_2026-09-08.md` and `docs/VISUAL_REFERENCES/alfven/` are
  present and committed. If any is missing, STOP — the design is authored in Matt's seat, never
  mid-session.
- `Staged Sandbox` renders today: `swift test --package-path UzumeEngine --filter StagedPath`
  passes. If the staged path is already red, fix nothing — report and stop.

## Numbered tasks

1. **Extend `PresetStage` with three optional keys.** `persistent: Bool = false`,
   `iterations: Int = 1`, `pixelFormat: String? = nil` (`"pixel_format"`), decoded with
   `decodeIfPresent` so every existing sidecar keeps byte-identical behaviour. Validate at
   decode: `iterations` in `1...64`; `pixel_format` in a small allowlist
   (`rgba16Float`, `rgba32Float`, `rg32Float`); unknown value warns and falls back to
   `rgba16Float` (the `feedback_pixel_format` precedent, PUB.4). A `persistent` stage that is
   also the final drawable-writing stage is a **decode error**, not a warning.
   **Done-when:** a round-trip Codable test asserts defaults on every shipping sidecar are
   unchanged, and the three validation rules each have a failing-input test.

2. **Give persistent stages a ping-pong pair with a documented lifecycle.** Allocate both
   textures at preset-compile time in the stage's declared pixel format; on each frame the stage
   samples the *previous* frame's texture and renders to the other, then swaps. Bind the previous
   texture at the stage's own slot — **document the slot choice in `ARCHITECTURE.md §GPU Contract
   Details` in the same commit**; do not overload 13+, which belongs to `samples`. Persistent
   textures must be cleared to zero on preset switch and on `reset()`.
   **Done-when:** a test drives two frames through the production `encodeStage` path and asserts
   frame 2 reads frame 1's output (write a known value in frame 1, read it back in frame 2), and
   a third test asserts the pair is zeroed after a preset switch.

3. **Implement `iterations`.** A stage with `iterations: N` encodes N render passes per frame,
   ping-ponging its own two textures, with the *sampled* inputs held constant across all N. This
   composes with `persistent`: an iterated persistent stage starts iteration 1 from the previous
   frame's state. Keep this in the existing loop in `RenderPipeline+Staged.swift`; do not fork a
   parallel code path.
   **Done-when:** a test with a stage whose fragment is `out = in + 1` and `iterations: 8`
   asserts the output is exactly `+8` after one frame, and `+16` after two frames when persistent.

4. **Port the projection shaders** into a new `PoissonSandbox.metal` — divergence, the Jacobi
   pressure iteration, and gradient-subtract, adopted from WebGL-Fluid-Simulation (MIT) verbatim
   in structure, adapting only context: Metal syntax, our texel-offset convention, and the
   texture bindings from tasks 2–3. **Do not re-derive the stencil** (FA #73), and do not drop a
   component because it looks redundant without a rendering test proving it (FA #65). Add the
   attribution row to `docs/CREDITS.md` in the same commit: project, author, MIT, what was taken.
   **Done-when:** `PoissonSandbox.metal` compiles and `docs/CREDITS.md` carries the row.

5. **Add the `Poisson Sandbox` diagnostic preset** — `PoissonSandbox.json`, `is_diagnostic: true`,
   `certified: false`, `rubric_profile: "lightweight"`, `passes: ["staged"]`, exercising all three
   new keys: a source stage, a `persistent` + `iterations: 24` + `rgba32Float` pressure stage, and
   a compose stage. Render the pressure field so a human can see it converge; a solved field must
   not be black (it is a diagnostic, but a black diagnostic teaches nothing).
   **Done-when:** the preset loads, renders, and appears in the diagnostic list but not in planner
   selection (D-074).

6. **Assert convergence against an analytic solution — this is the real gate.** For
   `f = -2 sin(x) sin(y)` on the doubly-periodic unit box, `p = sin(x) sin(y)` exactly. Read the
   pressure texture back after 24 iterations and assert the max relative error against the
   analytic field is below a threshold you determine empirically and then **freeze in the test
   with a comment recording the measured value** — do not pick a round number and tune the solver
   to it. Also assert the error strictly decreases from 4 → 8 → 16 → 24 iterations. **A residual
   that plateaus above the threshold is a real finding: report it, do not raise the threshold.**
   **Done-when:** `PoissonProjectionConvergenceTests` passes and its comment records the measured
   error at each iteration count.

7. **Extend the harness template.** Add `PersistentStagedPathHarnessTemplate` beside the existing
   three, on the `HarnessTemplateCore` spine, env-gated `HARNESS_TEMPLATES=1`: 60 frames at
   silence through the production dispatch path, capturing the persistent state each frame, with
   a quantitative metric asserting the state neither saturates nor decays to zero. This is the
   template ALFVEN.2 will adapt — it exists so the multi-frame harness precedes the preset, per
   `PRESET_SESSION_CHECKLIST.md` Part 2.
   **Done-when:** `HARNESS_TEMPLATES=1 swift test --package-path UzumeEngine --filter
   PersistentStagedPathHarness` passes and the metric is printed in the test output.

8. **Non-finite watchdog on persistent state** (`ALFVEN_DESIGN.md` §8.3). Add an engine-side
   guard that detects a non-finite persistent texture and re-clears the pair. Detection must not
   cost a per-frame full-texture readback — sample sparsely, or reduce on the GPU; state which you
   chose and why in the closeout.
   **Done-when:** a test injects a NaN into persistent state and asserts the next frame renders
   finite output, and the guard's per-frame cost is measured and reported.

9. **Update the docs in the same session, not later.**
   `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` (the three new keys and their semantics),
   `docs/SHADER_CRAFT.md` §17 (sidecar schema — the three keys in the engine/advanced table),
   `docs/ARCHITECTURE.md` (§Module Map + §GPU Contract Details slot allocation from task 2),
   `docs/DECISIONS.md` (**D-197 — verify this is the next free number at run time**; the decision
   is "staged stages gain persistence, iteration and per-stage pixel format; the projection is a
   port of an MIT reference, not a derivation"), and `docs/ENGINEERING_PLAN.md` (ALFVEN.1 row).
   **Done-when:** `DocIntegrity` passes and each file above carries the change.

10. **Stop and report before claiming done.** Post: the convergence numbers from task 6, the
    watchdog cost from task 8, and one sentence on whether the projection's diffusion looks likely
    to threaten the seam sharpness ALFVEN.2 needs (`docs/VISUAL_REFERENCES/alfven/README.md`
    provenance caveat, and `ALFVEN_DESIGN.md` §11). That sentence is the input to ALFVEN.2's
    go/no-go. **Stop and report — do not begin ALFVEN.2.**

## Do NOT

- Do NOT author `Alfven.metal`, an `Alfven.json`, or any Alfvén-specific shader code. That is
  ALFVEN.2. Infrastructure increments are never bundled with the preset that motivated them.
- Do NOT wire any audio primitive into the Poisson Sandbox. Audio routing is ALFVEN.3.
- Do NOT re-derive the Jacobi stencil, the divergence stencil, or gradient-subtract from first
  principles — port them (FA #73). Do NOT drop a component of the working reference on a
  first-principles redundancy argument without a rendering test (FA #65).
- Do NOT raise the task-6 convergence threshold to make the test pass. A plateauing residual is a
  finding to report (QG.1: a red gate is the gate working).
- Do NOT copy any code from `pmocz/constrainedtransport-python`. It is **GPL-3** and this is an
  MIT repo. It was watch-only concept material.
- Do NOT change `kStagedSampledTextureFirstSlot` or the `samples` binding order — existing staged
  presets (Arachne, Staged Sandbox) hold dHash goldens against it.
- Do NOT make `encodeStage` private or otherwise break the test-drivable seam.
- Do NOT touch `rubric_profile` semantics, `FidelityRubric`, or any shipping preset's sidecar.
- Do NOT regenerate any golden. If `PresetRegressionTests` dHash moves for an existing preset,
  that is a regression in this change, not a golden to refresh — stop and report.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
swift test --package-path UzumeEngine --filter PoissonProjectionConvergenceTests 2>&1
swift test --package-path UzumeEngine --filter StagedPath 2>&1
swift test --package-path UzumeEngine --filter PresetRegressionTests 2>&1
HARNESS_TEMPLATES=1 swift test --package-path UzumeEngine --filter PersistentStagedPathHarness 2>&1
RENDER_VISUAL=1 swift test --package-path UzumeEngine --filter PresetVisualReviewTests 2>&1
swift run --package-path UzumeTools CheckVisualReferences 2>&1
```

## Commit + closeout

- Small commits per logical step, `git commit -F <message-file>` (never `-m` with backticks):
  `[ALFVEN.1] PresetStage: persistent / iterations / pixel_format keys`
  `[ALFVEN.1] Staged: persistent ping-pong pair + iterated encode`
  `[ALFVEN.1] Shaders: port divergence / Jacobi / gradient-subtract (MIT, WebGL-Fluid-Simulation)`
  `[ALFVEN.1] Diagnostics: Poisson Sandbox + analytic convergence gate`
  `[ALFVEN.1] Tests: PersistentStagedPathHarnessTemplate`
  `[ALFVEN.1] Docs: capability registry, sidecar schema, D-197`
- Local commits only. **Push only on Matt's explicit "yes, push".**
- Closeout: invoke `closeout`; 8-part report with the verbatim `Scripts/closeout_evidence.sh`
  block as §2. Increment-specific additions: (i) which dispatch path each test exercised —
  "tests pass" is not evidence (Part 2); (ii) the task-6 convergence table; (iii) the task-8
  watchdog cost and detection method; (iv) the task-10 sentence on projection diffusion.

## DECISION-NEEDED — surface at task 10, not before

**Question.** The Jacobi solver's iteration count trades sharpness against frame budget — how
sharp should the seams be?

- **24 iterations (recommended).** Seams read as bright lines with a soft shoulder, close to the
  reference frames. Costs the most of the three; still small next to a ray march.
- **12 iterations.** Seams read softer and slightly smeared; the lobes are unaffected. Cheapest,
  and safest for the frame budget on older hardware.
- **40 iterations.** Marginally crisper than 24 — in the CPU spike the difference at this end was
  hard to see, so this is likely paying for nothing.

**Recommendation:** 24. **Default if no reply:** 24, revisited in ALFVEN.2 against the reference
frames once the look is actually on screen.
