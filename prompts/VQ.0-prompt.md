# Increment VQ.0 — Stability floor: a GPU memory budget, safe display changes, a 4K render soak (engine increment)

**Objective.** After this session every render target whose size follows the display goes through one budgeted
allocator that charges Metal's own sizes (targets, the drawable pool, MetalFX reservations); Uzume's render memory
has a ceiling it never crosses; a display change (TV plugged in or out, 1080p ↔ 4K) drains the frames in flight,
releases the old render set, then allocates the new one; the budget governor reacts to GPU time, command-buffer
errors, heat, Low Power Mode and memory pressure; every shader loop is known to be bounded; and a 60-minute 4K
render soak plus an 8 GB-Mac floor simulation run with the app killed at 4 GB. **No scene changes how it looks.** This is the floor the rest of
Phase VQ stands on: nothing raises a pixel count until it exists (`docs/VISUAL_QUALITY_PROGRAM_PLAN.md` §5.1).

Why (Matt, 2026-10-21): *"significantly improve the visual quality of Uzume without crashing machines or causing
application memory outages … project out from an HDMI or USB-C port … to a 4K HDTV."* Matt chose **every Apple
Silicon Mac** as the target, so the floor is a base 8 GB M1 Air on a USB-C adapter.

## Skills to invoke

- `shader-authoring` — before any render-pass or GPU-facing Swift, and before task 5's loop-bound edits in `.metal`.
- `defect-handling` — **only if** the soak reproduces a freeze or a memory runaway (BUG-085 / BUG-081 / BUG-060 class):
  stop the increment and open the defect under that skill.
- `closeout` — at the end.

## Read first (in order)

1. `docs/VISUAL_QUALITY_PROGRAM_PLAN.md` (all; §3 items 6–7 and §4 "Stability" are this increment's spec).
2. `UzumeEngine/Sources/Renderer/RenderPipeline.swift:~775` (`mtkView(_:drawableSizeWillChange:)`: the per-subsystem
   reallocation this increment funnels through the budget) and `MetalContext.swift:78-93` (`makeSharedTexture`).
3. Every other size-scaled allocation: `grep -rn "makeTexture\|makeSharedTexture\|storageMode" UzumeEngine/Sources/Renderer UzumeEngine/Sources/Presets`
   — `PostProcessChain.allocateTextures`, `RayMarchPipeline.allocateTextures`, `RenderPipeline+MVWarpSetup.swift`,
   `RenderPipeline+Staged.swift:~200`, `RenderPipeline+DirectDraw.swift` (`halfResTarget`), the `Geometry/*` sims.
4. `FrameBudgetManager.swift` (D-057 governor, `QualityLevel`) and `RenderPipeline+BudgetGovernor.swift`.
5. `UzumeApp/VisualizerEngine+InitHelpers.swift:100-150` (`gpuPressureDescription`: what is logged today) and `:376`
   (`detectDeviceTier`, a GPU-name string match).
6. `UzumeApp/Services/DisplayChangeCoordinator.swift` (D-061(a)) and
   `UzumeEngine/Tests/UzumeEngineTests/Renderer/DrawableResizeRegressionTests.swift`.
7. Soak and watchdog prior art: `UzumeEngine/Sources/Diagnostics/SoakTestHarness.swift` (audio + MIR only — it does not
   render), `Sources/SoakRunner/main.swift`, `Tests/.../Diagnostics/MemorySoakGateTests.swift` (isolated
   `SOAK_TESTS=1` gate), `Scripts/memrepro.sh` (8 GB kill-switch pattern — it exists only on the Understory branch: read it with
   `git show 17782edd:Scripts/memrepro.sh` and copy the pattern into `tv_soak.sh`; do not cherry-pick UND.R0),
   `Scripts/capture_hang.sh`.

## Pre-flight invariants (each failure stops the session)

- Branch `vq-0` in its own worktree from `main` once MFX.2 has merged, **or from the `mfx-2` branch if it has not**
  (MFX.2 rewrites the same resize, drawable-cap and direct-draw code this increment changes; never run the two in
  parallel). **Do not base on `claude/rec2-prompt-193a14`**: it carries uncommitted Understory work that is not
  yours.
- As of 2026-10-22 MFX.2 is built and pushed (`origin/mfx-2` = `a089d726`) but **not merged**: base on `mfx-2`.
  A4 is applied there (drawable fixed at the display's pixel mode), so task 3's A4 clean-up is already done —
  confirm it, don't redo it. MFX.2's closeout is its row in `ENGINEERING_PLAN.md` on that branch; A1 (budget
  hook) was skipped pending this increment, so its scaler's `currentAllocatedSize` delta is the reservation to charge.
- `docs/VISUAL_QUALITY_PROGRAM_PLAN.md` and this prompt are **untracked files in the main checkout only**; copy both
  into the new worktree before reading, and commit the plan with task 9's docs.
- `Scripts/closeout_evidence.sh` green at the base (timing gates are load-sensitive: re-run a failing one isolated
  and record both runs).
- Record in the transcript: the dev Mac's chip, GPU core count, physical memory and `recommendedMaxWorkingSetSize`.
- If MFX.2 has merged, read its closeout first: its reconstructor's targets are size-scaled allocations and go
  through the budget too.

## Tasks

1. **Inventory before changing anything.** Label every size-scaled `MTLTexture`/`MTLBuffer` (`.label`). Add a
   test-only inventory that renders each certified scene for 120 frames through its production path at 1920×1080,
   2560×1440 and 3840×2160 and records, per scene and size: the sum of labelled allocations,
   `device.currentAllocatedSize` before/after, and each target's label, size, format and storage mode.
   **Done-when:** `docs/diagnostics/VQ0_RENDER_MEMORY_INVENTORY.md` holds the table (Release, machine named); the
   labelled sum matches Metal's own delta within 10 % per scene, or the gap is explained.

2. **One budgeted allocator.** A `RenderTargetBudget` (Renderer) through which every size-scaled allocation goes. It
   keeps a running total, owns release, and refuses an allocation that would cross the ceiling. **Charge what Metal
   charges:** each texture's `allocatedSize` (or `device.heapTextureSizeAndAlign` before creation), not w×h×bpp;
   the drawable pool (set `maximumDrawableCount` explicitly and charge count × drawable size); and an opaque
   reservation for any MetalFX scaler/interpolator, measured as the `currentAllocatedSize` delta at its creation.
   Derive the ceiling from task 1's evidence, not a guess: start from the largest scene's 4K set × 1.5, capped at
   `min(15 % of physical memory, 25 % of recommendedMaxWorkingSetSize)`; record the formula and its numbers for an
   8 GB, 16 GB and 36 GB Mac in the D-number. On refusal: the scene is skipped for this session on this Mac and
   the next scene plays (see DECISION-NEEDED); never allocate past the ceiling, never crash.
   Switch GPU-only targets to `.private` (Apple GPUs can compress private render targets losslessly: less
   bandwidth); use `.memoryless` for attachments that live inside one render pass; keep `.shared` only where the
   CPU reads back (recorder, tests, `AlfvenSolver`) and list those.
   **Done-when:** a test with a forced tiny ceiling shows a refused scene skipped with no crash and no partial
   allocation left behind; a test asserts the budget's total equals the sum of live labelled targets after a scene
   switch; inventory re-run shows the storage changes; `PresetRegressionTests` dHash goldens unchanged.

3. **Display changes drain, release, then allocate.** Metal frees a texture only after every in-flight command
   buffer that references it completes, so "release first" means nothing without a drain: in
   `drawableSizeWillChange`, wait for the frames in flight (the `inflightSemaphore`, or the last command buffer's
   completion), release each subsystem's old set through the budget, then allocate. **Coalesce resizes by default**
   (the fullscreen animation alone sends many size callbacks; a TV handshake sends more): render at the old size
   until the size has been stable ~150 ms, then reallocate once. Log how many callbacks a real hot-plug and a
   fullscreen toggle produce. Keep D-061(a): no torn frames.
   **Done-when:** a test toggles 1920×1080 ↔ 3840×2160 fifty times across a feedback, an mv_warp, a ray-march and a
   staged scene, sampling only after the GPU is idle: `currentAllocatedSize` returns to its baseline within 16 MB
   and the peak stays ≤ 2× the steady 4K set; a burst of 20 size callbacks inside 100 ms produces one reallocation;
   `DrawableResizeRegressionTests` still green. **If MFX.2 left the drawable resizing on a switch between
   reconstructing and non-reconstructing scenes** (its amendment A4 not applied), remove that here: the drawable
   stays at the display's pixel mode and only internal sizes change; a test asserts a reconstructing ↔
   non-reconstructing switch performs no drawable reallocation.

4. **The governor's new inputs.** Extend the governor (pure-state, testable like D-057). Know its limits: GPU
   start/end times include time other processes pre-empted, and with three frames in flight it reacts 3–5 frames
   late, so these are backstops; task 5 is the prevention.
   - two consecutive frames with GPU time > 50 ms → drop to the lowest quality rung, **hold it ≥ 5 s**, then climb
     one rung at a time through the existing 180-frame recovery (no oscillation);
   - a command buffer completing with `.error` (set `errorOptions = .encoderExecutionStatus` so the failing encoder
     is named) → log the code and encoder, drop to the lowest rung; three errors inside 10 s → a designated light
     fallback scene;
   - `ProcessInfo.thermalState` `.fair` → one rung down; `.serious` → cap 30 fps and one more; `.critical` → the
     fallback scene; Low Power Mode → cap 30 fps;
   - a `DispatchSource.makeMemoryPressureSource` warning → lowest rung and no new scene allocation larger than the
     current one; critical → the fallback scene.
   **Done-when:** governor unit tests drive each input synthetically (including no oscillation under a square-wave
   overrun); a wiring test shows the completed-handler feeds GPU time and status into it; the session log names
   every forced step with its cause.

5. **Bounded shader loops (prevention).** A single command buffer that runs for seconds freezes the whole desktop
   through the shared WindowServer, and no governor can interrupt it. Audit every `for`/`while` in every certified
   scene's shaders and the shared utilities: each loop's trip count must have a compile-time bound (a constant or a
   `min(uniform, CONST)`). Fix only bounds that do not change the image (a cap above the largest value ever
   reached); list any other unbounded loop for VQ.5 with its scene.
   **Done-when:** `docs/diagnostics/VQ0_SHADER_LOOP_AUDIT.md` lists every loop with its bound; a lint script
   (`Scripts/check_shader_loop_bounds.sh`) fails on a new unbounded loop; goldens unchanged.

6. **Measure the GPU, do not reclassify it yet.** At launch, log one line: chip name, GPU core count (IORegistry
   `gpu-core-count`), physical memory, `recommendedMaxWorkingSetSize`, the computed budget ceiling and the
   drawable's native size. Include it in the Report a Problem bundle (BR.5). **Do not change `DeviceTier` or
   `detectDeviceTier`**: the tier feeds the Orchestrator's plans; reclassification is decided later from data.
   **Done-when:** the line appears in a Release launch's session log; a test covers the formatter.

7. **The 4K render soak and the floor simulation.** A render soak (a `--render` mode on `SoakRunner`, or a new runner
   beside it): the real `RenderPipeline` offscreen at 3840×2160, cycling every certified scene 20 s each (one full
   roster cycle ≈ 9 minutes), switching to 1920×1080 and back every 5 minutes, for 60 minutes; per-minute footprint
   (`phys_footprint`), Metal allocation, budget total, GPU ms p50/p95 (GPU time from the command buffer), CPU frame
   wall time, command-buffer errors, forced governor steps; switch and resize frames tagged and reported separately.
   It kills itself at **4 GB**. Run it twice: once normally, and once as the **floor simulation** — the 8 GB-Mac
   ceiling forced and `memory_pressure -l warn` then `-l critical` applied mid-run. Add a 10-minute version gated by
   `SOAK_TESTS=1`.
   **Done-when:** Release 60-minute runs on the dev Mac meet these gates, **with the baseline taken after the first
   full roster cycle:** footprint drift ≤ 50 MB and a fitted slope ≤ 5 MB per 10 minutes over the rest of the run;
   zero command-buffer errors; zero non-switch frames > 250 ms CPU wall time; switch-frame p95 stated; budget never
   crossed; under the floor simulation, refused scenes skipped and no crash. Reports in `docs/diagnostics/`. **If a freeze or a runaway reproduces, stop and report under `defect-handling`** — that is
   BUG-085's first reproduction and matters more than this increment.

8. **The live check, scripted for Matt.** `Scripts/tv_soak.sh`: launches a named Release build on a local-file
   playlist whose stem caches are moved aside (so **stem preparation runs during the soak** — BUG-176's failure was
   preparation, not rendering; reuse `memrepro.sh`'s move-aside-and-restore trap), with a developer env var that
   cycles certified scenes every 20 s; samples footprint every 2 s, kills at 4 GB, and prints the session folder. Write the 6-line instructions Matt follows: plug the TV in and out twice
   during the hour. **Done-when:** the script runs end-to-end for 2 minutes on the dev Mac; the full hour on the TV
   is Matt's and stays pending in the closeout.

9. **Docs.** `docs/ARCHITECTURE.md` §Renderer (the budget, the drain-release-allocate rule, the governor's new
   inputs); `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` row; `docs/RUNBOOK.md` (how to run both soaks);
   `docs/ENGINEERING_PLAN.md` a "Phase VQ" table copied from the program plan §6 with VQ.0's row filled; one new
   D-number recording Matt's four 2026-10-21 decisions (program plan §2) and the budget rule (number and date
   assigned at run time).

## DECISION-NEEDED (bring to Matt only if the inventory shows a real scene can cross the ceiling)

**When a scene cannot fit in a Mac's memory budget, what should the viewer see?**
- **A — Uzume skips it on that Mac** and plays the next scene in the plan; nothing looks different, that scene just
  never appears there.
- **B — the scene plays softer** (rendered smaller and stretched) until reconstruction (MFX.2 / VQ.3) can make it
  crisp.

**Recommendation: A** — it keeps the "never stretched" promise Matt made for every Mac. **Default if no reply: A.**
(Once a path has reconstruction, a lower internal scale replaces skipping for that path; that is not this
increment.)

## Do NOT

- Do not lift the BR.6b drawable cap or add reconstruction (MFX.2's job).
- Do not change any scene's look; `PresetRegressionTests` / `GoldenSessionTests` goldens must not move. If one moves,
  stop and report; do not regenerate.
- Do not change `DeviceTier` mapping or plan scoring.
- Do not lower any scene's fidelity to fit a budget at sizes where the budget is not actually crossed.
- Do not touch Understory files or the BUG-176 stem-preparation work (UND.R*).
- No third-party dependency. Do not push.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine --filter DrawableResizeRegression
swift test --package-path UzumeEngine --filter PresetRegression
SOAK_TESTS=1 swift test --package-path UzumeEngine --filter MemorySoakGate
SOAK_TESTS=1 swift test --package-path UzumeEngine --filter RenderSoak
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
Scripts/closeout_evidence.sh
```

Every performance or memory number quoted in Release, with the machine named.

## Commit message templates

- `[VQ.0] Renderer: label size-scaled targets + render-memory inventory`
- `[VQ.0] Renderer: RenderTargetBudget — one budgeted allocator, private storage for GPU-only targets`
- `[VQ.0] Renderer: release-before-allocate on drawable resize`
- `[VQ.0] Renderer: governor GPU-time ceiling, command-buffer errors, thermal, Low Power, memory pressure`
- `[VQ.0] Presets: bounded shader loops + loop-bound lint`
- `[VQ.0] App: GPU capability line in session log and problem report`
- `[VQ.0] Tools: 4K render soak + tv_soak.sh`
- `[VQ.0] docs: inventory, registry, runbook, plan, D-number`

Local commits only. Push only on Matt's explicit "yes, push", to the `vq-0` branch with a PR — never to `main`.

## Closeout

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as
§2. Add: the inventory table's 4K column and the chosen ceiling with its formula for 8 / 16 / 36 GB Macs; the
hot-plug and fullscreen callback counts and peaks; both 60-minute soaks' per-minute tables; the loop audit's
count of unbounded loops left for VQ.5; every target left `.shared` and why;
Matt's TV soak marked pending.
