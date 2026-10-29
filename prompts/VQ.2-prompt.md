# Increment VQ.2 — HDR output: an EDR drawable from the display's potential headroom, highlights above SDR white, flashes capped (engine increment)

**Objective.** After this session, Uzume can put real HDR light on an HDR display:

- **An EDR drawable.** On a display that can show more than SDR white, and with the HDR setting on, the drawable
  is `.rgba16Float` in **extended linear Display P3** with EDR. Everywhere else the drawable is today's
  `.bgra8Unorm_srgb`, untouched.
- **The finish uses the headroom.** The cinematic finish's display transform (VQ.1, `headroom` 1.0 until now)
  maps a scene's linear light into `[0, headroom]`, following the display's **current** headroom as it changes.
- **Flashes stay safe in HDR.** Brightness above SDR white is allowed only where it cannot flash: no region of the
  screen may average above SDR white, and the per-pixel peak is capped at Matt's chosen multiple (decisions below).
- **A setting, on by default** (D-264), that turns HDR off.

**No shipped scene changes its look in this increment.** Legacy scenes keep their fixed 8-bit frame target; on an
EDR drawable the present step converts their pixels so they look the same as on SDR. The one cinematic scene
(Ferrofluid Ocean) keeps `headroom` 1.0 until a consumer increment opts it in. The order on screen stays Apple's
(WWDC25 session 211): render → upscale → finish → present.

**Why now.** Matt's order is pixelation → flat light and colour → motion. VQ.3 took pixelation. Today the output
is 8-bit SDR (`MetalContext.pixelFormat`, plan §3 item 4): an HDR TV's or the LG's headroom goes unused, and
the brightest thing Uzume can show is the same white as a menu bar. Matt decided on 2026-10-21 that HDR is
**on by default** on displays that support it (D-264).

**What is already true** (verified 2026-10-29):

- Every scene pipeline compiles for its **frame target** format, resolved once at load
  (`PresetLoader.frameTargetFormat`, `FinishSpec.frameTargetFormat`): legacy `.bgra8Unorm_srgb`, cinematic
  `.rgba16Float`. These do not depend on the drawable, so an EDR drawable needs **no scene pipeline recompile**
  (the BUG-061 class).
- But `context.pixelFormat` is also used by the ray-march composite, `PostProcessChain`, the renderer's blits,
  the finishing stage's output and `MetalView.colorPixelFormat`. Those are two different things — the legacy
  frame format and the drawable format — sharing one name. Splitting them is task 1.
- On a Mac that renders at the display's size (M3/M4), a legacy scene draws **straight into the drawable**
  (zero copies). On an EDR drawable it needs its own 8-bit frame target, like the tier-1 canvas, plus a
  converting copy. That costs memory and a full-screen pass.
- A `.rgba16Float` 4K drawable pool is 3 × 66 MB ≈ 199 MB, double today's ≈ 100 MB. The VQ.0 ceiling is
  858 MiB. The largest set, Lumen Mosaic reconstructing, measured 665.6 MiB with the 8-bit pool.

## Matt's decisions (2026-10-29)

Agreed with Matt on 2026-10-29, when this prompt was agreed.

| Question | Decision | What it commits us to |
|---|---|---|
| How bright do the brightest moments get? | **Highlights pop, the picture stays** (Matt's pick, the recommendation) | Small bright things (sparks, glints, the cores of glows) may go up to **4× SDR white**, or the display's limit if lower. No ninth of the screen averages above SDR white, so a full-screen flash is never brighter than today. |
| HDR on by default? | **Yes** (D-264, 2026-10-21; re-confirmed 2026-10-29) | On every display that reports HDR headroom, the MacBook Pro's own screen included. A setting turns it off. |

## Skills to invoke

- `shader-authoring` — before any `.metal` edit (the conversion pass, the finish's headroom and cap).
- `closeout` — at the end.
- (`preset-session` is **not** needed: no scene changes its look.)

## Read first (in order)

1. `docs/VISUAL_QUALITY_PROGRAM_PLAN.md`: §3 item 4; §4 "Light and colour" and "Stability"; §5; the VQ.2 row in §6
   and the order note under it.
2. `docs/DECISIONS.md` (use the §Index): **D-264** (the budget, display changes, the 2026-10-21 HDR decision),
   **D-265** (cost conventions: completion spacing, `.private` targets), **D-157** (flash: bounded footprint,
   steady luminance).
3. The VQ.1 and VQ.1c rows in `docs/ENGINEERING_PLAN.md` §Phase VQ, and BR.1's increment entry (the photosensitivity
   gate).
4. The seam and the finish:
   - `RenderPipeline+FrameSeam.swift` (frame target, present step, `presentUpscale`, `recordAtCanvasSize`);
   - `FinishingStage.swift` and `Shaders/FinishingStage.metal` (`headroom`, `lottesCoefficients`, the dither,
     which rounds to the output **code** — that assumption changes on a float drawable);
   - `Shared/FinishSpec.swift` (`frameTargetFormat`).
5. Every user of `context.pixelFormat`: `grep -rn "context.pixelFormat\|ctx.pixelFormat" UzumeEngine/Sources UzumeApp`
   (`MetalView.swift`, `RenderPipeline.swift` ~`:781`, `RenderPipeline+Resize.swift` ~`:185`,
   `PostProcessChain.swift`, `RayMarchPipeline+PipelineStates.swift`, `VisualizerEngine.swift`,
   `VisualizerEngine+Presets.swift`).
6. `RenderPipeline+Canvas.swift` (the tier-1 canvas and `copy`), `UzumeApp/Views/MetalView.swift`
   (`PixelModeMTKView`, display-change handling).
7. `RenderTargetBudget.swift` (the drawable-pool reservation) and `docs/diagnostics/VQ0_RENDER_MEMORY_INVENTORY.md`.
8. Flash: `FlashAnalyzer.swift` (the 0…1 relative-luminance assumption), `PhotosensitivityCertificationTests`,
   `MultiPassFlashHarnessTests`, `MultiPassFlashUpscaleTests`, `FlashHarnessSupport.swift`.
9. `UzumeApp/Services/SettingsStore.swift` and its key scheme; `docs/UX_SPEC.md` §9.5 (copy) and the settings
   section; `Scripts/check_user_strings.sh`.
10. Apple: `CAMetalLayer.wantsExtendedDynamicRangeContent`, `CGColorSpace.extendedLinearDisplayP3`,
    `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue` (can this display ever go above SDR white),
    `maximumExtendedDynamicRangeColorComponentValue` (how far above it right now), and
    `NSApplication.didChangeScreenParametersNotification`.

## Pre-flight invariants (each failure stops the session)

- LM.10 (#370) is on `origin/main`. Work on branch `vq-2`, cut from an up-to-date `main`.
- `Scripts/closeout_evidence.sh` is green at the base.
- `Scripts/link_fixtures.sh` has run if this is a worktree.
- Record the current `PresetRegressionTests` dHash values, and capture the legacy oracle (`FinishLegacyOracleTests`,
  frame 60, fixed drive) at 1080p and at a tier-1-capped 4K drawable. This is the "nothing changed" oracle on an
  SDR drawable.

## Tasks

1. **Split the two formats.** `MetalContext` keeps the **legacy frame format** (`.bgra8Unorm_srgb`, a constant —
   what the ray-march composite, `PostProcessChain` and legacy blits compile for) and gains a **drawable format**
   that follows the HDR state. Every `context.pixelFormat` call site is assigned to one or the other.
   **Done-when:** `grep` shows no call site left ambiguous; with HDR off, every certified scene matches the SDR
   oracle byte for byte (Ferrofluid Ocean and Fiddlehead within their measured run-to-run spread, D-265).

2. **Choose HDR from the display's potential headroom.** HDR is active when the setting is on **and** the window's
   screen reports `maximumPotentialExtendedDynamicRangeColorComponentValue` > 1. Current headroom alone is the
   wrong test: a built-in SDR panel reports current headroom > 1 when dimmed. When active: drawable
   `.rgba16Float`, layer colorspace extended linear Display P3, `wantsExtendedDynamicRangeContent = true`.
   Re-decide when the window changes screen, the screen parameters change (HDR toggled in System Settings, a TV
   plugged in), or the setting changes. A format change is a **display change**: drain → release → allocate
   (D-264), never mid-frame.
   **Done-when:** a test drives the decision with a fake screen (potential 1.0 / 1.0 dimmed with current > 1 /
   2.0 / 16.0, setting on and off); a live run on Matt's LG logs `HDR_STATE` lines (potential, current, active)
   when HDR is toggled in System Settings and when the window moves between the HP and the LG; footprint is back
   at baseline after each change once the GPU is idle.

3. **Legacy scenes on an EDR drawable look the same.** On an EDR drawable a legacy scene draws into an 8-bit
   frame target at its render size: the tier-1 canvas where one exists, a budgeted one otherwise. The present
   step converts: sRGB decode → Rec.709 primaries to Display P3 → linear, SDR white at 1.0. MetalFX spatial,
   when a scene takes it, runs before the conversion (VQ.3 order).
   **Done-when:** for every certified scene, the EDR drawable's readback re-encoded to sRGB matches the SDR
   drawable within **1 code** per channel (state the worst pixel and its share); no value exceeds 1.0; the
   recorder still writes 8-bit video at canvas size.

4. **The finish uses the headroom.** The cinematic finish outputs into `[0, headroom]`, with `headroom` taken
   from the display's **current** value, re-read when it changes, and limited by the peak cap (Matt's decision:
   4×). Mid-grey holds still (`lottesCoefficients` already solves for it). The dither stops rounding to an
   8-bit code on a float drawable: it dithers at the half-float's step, or is shown to be unnecessary (measure
   banding on the VQ.1 proof gradient). A scene opts in through its sidecar `finish`. **Absent means headroom 1.0**,
   so Ferrofluid Ocean is unchanged until its consumer increment.
   **Done-when:** the VQ.1 proof scene at headroom 1, 2, 4 and 16 shows mid-grey unchanged (state the value) and
   peaks at `min(headroom, cap)`; banding on the proof gradient is stated against VQ.1's 0.053 LSB; Ferrofluid
   Ocean on an EDR drawable matches its SDR look within 1 code after re-encoding.

5. **Flashes capped in linear luminance.** Above SDR white, brightness is allowed only in small areas:
   - **Per pixel:** at most the peak cap (Matt's decision: 4× SDR white).
   - **Per region:** no ninth of the screen (the FlashAnalyzer v2 grid: 3×3 plus a half-shifted 2×2) averages
     above SDR white. The finish enforces this itself, from the bloom chain's smallest level or an equivalent
     cheap reduction. The whole-frame rule follows from the regional one.
   - **The analyzer measures in SDR-white units.** Luminance is measured relative to SDR white, not clamped to
     0…1. A swing counts at ≥ 0.10 of SDR white, and its darker state must be < 0.80 of SDR white — WCAG's
     thresholds anchored to SDR white, which is stricter than anchoring them to the HDR peak.
   **Done-when:** a test-only stress scene — a full-screen strobe at 10× SDR white, a regional strobe, a red strobe —
   is held to ≤ 3 flashes/s whole-frame, regional and red at headroom 4 and 16; `PhotosensitivityCertificationTests`
   and the multi-pass flash suite are green with HDR on and off; Reduce Motion and Dim Flashing Lights (BR.1)
   still act; the negative control (cap removed) **fails** the stress scene, with both arms' numbers printed.

6. **The setting.** `SettingsStore` gains an HDR preference, **on by default**, under the existing key scheme. A
   toggle sits in Settings with copy per UX_SPEC §9.5; it says what it does now ("Use HDR on displays that
   support it"). Turning it off takes effect without restarting, through the task-2 display change.
   **Done-when:** `SettingsStoreEnvironmentRegressionTests` and `Scripts/check_user_strings.sh` are green;
   toggling it live switches the drawable both ways (`HDR_STATE` lines).

7. **Memory and stability.** The drawable-pool reservation follows the drawable format (float: 8 bytes per pixel).
   The legacy frame target from task 3 is charged. Recompute the ceiling rule's inputs (largest 4K set with an EDR
   pool) and say whether 858 MiB still holds; if it moves, show the arithmetic.
   **Done-when:**
   - a test states Lumen Mosaic and Ferrofluid Ocean at 4K with an EDR pool, against the ceiling;
   - the floor simulation (8 GB budget plus injected pressure) with HDR on refuses or steps down and does not crash;
   - a hot-plug test (SDR 1080p ↔ HDR 4K, repeated) shows no reservation outliving its display and footprint back
     at baseline.

8. **A proof Matt can see on his LG.** The VQ.1 proof scene (or a successor) runs **in the Release app** behind a
   developer flag, never in the shipped roster. It shows the chosen cap: glints and the cores of glows above
   white over a mid-grey field, plus a slow sweep of a bright small object. Toggling the HDR setting compares HDR
   with SDR live.
   **Done-when:** Matt has looked at it on the LG at 1:1 (no forced drawable size; memory: VQ.3a soak windows on
   the HP were downscaled), and has swept the roster with HDR on to confirm nothing else looks different. His
   words are recorded in the plan row.

9. **Cost, Release, on the M2 Pro mini at 4K output.** Measure, as p50 and p95 GPU ms: the legacy conversion pass
   (native 4K and from the tier-1 canvas), and the finish with headroom and the cap versus VQ.1's 1.02 ms. Use
   `.private` targets (`UZUME_PRIVATE_TARGETS=1`) on a saturated GPU, one filter at a time, and completion spacing
   (D-265). Then run one live Release session of a heavy legacy scene at 4K on the LG with HDR on and off: frame
   GPU ms and presented fps over a few hundred frames. An EDR layer can cost the compositor more, which the
   harness cannot see.
   **Done-when:** the table is in the closeout **with the build configuration stated** (CLAUDE.md: a Debug number
   means nothing); the closeout says whether any scene that held 60 fps on SDR loses it on HDR, and projects the
   M1 cost from memory bandwidth.

10. **Docs.**
    - `docs/ARCHITECTURE.md`: §Renderer (the two formats, the HDR decision, the conversion step) and §GPU Contract
      Details.
    - `docs/SHADER_CRAFT.md` §17: the `finish` HDR opt-in and the cap.
    - `docs/UX_SPEC.md`: the setting.
    - `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`; `docs/ENGINEERING_PLAN.md` (the VQ.2 row); `docs/RUNBOOK.md`
      (turning HDR on for the LG in System Settings; reading `HDR_STATE`).
    - A D-number for the HDR rule, the cap and the flash measurement, assigned at run time.

## Do NOT

- **Shipped scenes.** Do not opt a shipped scene into headroom > 1, and do not move a golden. Ferrofluid Ocean's
  HDR is its own consumer increment, and Energetic Flyby's follows it, each with Matt's side-by-side on the LG.
- **Legacy pipelines.** Do not recompile any scene pipeline for `.rgba16Float`. Legacy scenes keep their 8-bit
  frame target.
- **Two-way format changes per scene.** Do not switch the drawable format on a scene switch. It follows the
  display and the setting only.
- **HDR video formats.** Do not add PQ or HLG output, tone-mapping metadata (`CAEDRMetadata`) or HDR video
  recording. The recorder stays 8-bit SDR.
- **Governor and thermal.** Do not add an HDR rung to the governor. If HDR costs enough to matter, report it.
- **Out-of-scope features.** Do not add frame pacing (VQ.4a), motion blur (VQ.4b) or TV-mode UX (VQ.6).
- **PostProcessChain.** Do not delete it. It goes after its last legacy consumer leaves (VQ.5).
- **Pushing.** Do not push.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine --filter FinishLegacyOracle
swift test --package-path UzumeEngine --filter FinishFormatMatch
swift test --package-path UzumeEngine --filter FinishingStage
swift test --package-path UzumeEngine --filter PresetRegression
swift test --package-path UzumeEngine --filter PhotosensitivityCertification
swift test --package-path UzumeEngine --filter MultiPassFlash
swift test --package-path UzumeEngine --filter RenderTargetBudget
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
Scripts/closeout_evidence.sh
```

Plus the new suites, by name: the HDR decision, legacy-on-EDR identity, headroom and cap, the HDR flash stress,
and the hot-plug budget test.

## Commit message templates

- `[VQ.2] Renderer: split the legacy frame format from the drawable format`
- `[VQ.2] Renderer: EDR drawable from the display's potential headroom; display change on HDR toggle`
- `[VQ.2] Renderer: legacy present converts sRGB to extended linear P3`
- `[VQ.2] Renderer: finish follows current headroom; per-pixel peak cap and regional SDR-white cap`
- `[VQ.2] App: HDR setting, on by default`
- `[VQ.2] Tests: HDR decision, legacy identity on EDR, headroom, flash stress, hot-plug budget`
- `[VQ.2] docs: architecture, sidecar schema, UX, registry, plan, D-number`

Local commits only. Push only on Matt's explicit "yes, push", to the `vq-2` branch with a PR, never to `main`.

## Closeout

Invoke the `closeout` skill and produce the 8-part report, with the verbatim `Scripts/closeout_evidence.sh` block
as §2. Add the following:

- the format split, with the call-site list;
- the oracle result with HDR off, and the legacy-on-EDR identity result;
- the headroom table (mid-grey and peak at each headroom) and the banding figure;
- the flash stress table, both arms;
- the memory figures and the ceiling;
- the cost table and the live LG run;
- Matt's words after his look on the LG.

Converge offline before opening any image in Matt's view (memory: *don't iterate renders in Matt's view*). Then
name the consumer increments the evidence supports. The likely ones:

- **VQ.2a:** Ferrofluid Ocean on HDR. Its highlights peak near 0.6 linear (VQ.1c), so HDR shows only if its grade
  lifts the glints. That is Matt's look.
- **VQ.2b:** Energetic Flyby on the cinematic finish with HDR.

Each one ends with Matt's side-by-side on the LG.
