# Increment VQ.3 — Sharp upscaling everywhere: MetalFX spatial for every stretch, temporal for the ray-march path, native anti-aliasing (engine increment)

**Objective.** After this session the engine has three ways to put a smaller render on a 4K screen, each of
which can stand in for the bilinear stretch Uzume uses today, and each measured against a true native 4K
reference:

- **MetalFX spatial upscaling.** It can replace each of the engine's bilinear stretches. It needs no motion
  vectors, so it works for any scene.
- **MetalFX temporal reconstruction on the ray-march G-buffer path.** MFX.2 did the same for the direct path.
- **A scale-1.0 "anti-aliasing only" mode** for scenes cheap enough to render at full size.

**No shipped scene changes its look in this increment.** Every scene keeps today's stretch. Scenes adopt the new
paths in their own consumer increments, each judged by Matt on a 4K monitor. On screen the order stays Apple's
(WWDC25 session 211): render (jittered) → upscale → finish → present. The upscaler writes a texture, never the
drawable.

**Why now.** On 2026-10-27, Matt chose **pixelation first**, so VQ.3 runs before VQ.2 (HDR). Today the picture is
stretched in three places:

- **Tier-1 Macs.** Every scene renders at about 2560×1440 into the canvas, and the present step stretches it to 4K
  bilinearly (`RenderPipeline+Canvas.swift`, BR.6b cap, A4). Tier 1 is every Mac whose GPU name lacks "m3" or
  "m4", including Matt's M2 Pro mini. This is the *"pixelated on fullscreen"* image.
- **Volumetric Lithograph.** It marches at most 1536×864 pixels (`marchedPixelBudget`). At 4K that is a 2.5×
  bilinear stretch, kept because Matt chose 60 fps over sharpness (PERF.16).
- **Nimbus.** It renders at half resolution through the NB.8 path.

MFX.2 measured both upscalers on a proof scene (D-263, M2 Pro, 4K):

- **Temporal** is crisper than the stretch while the camera is still, but softer in forward flight.
- **Spatial** kept detail at 1.5–1.54 gradient energy on every motion class, where the reference is 1.0.
  - That is above the reference, so it may be over-sharpened.
  - Its frame-to-frame change was 0.043, against the stretch's 0.029, so it may shimmer.
- **Temporal upscaling cost 5.2 ms per 4K frame.**
- **EFB.4 outcome:** Matt rejected temporal for Energetic Flyby: *"the original stretched looks good, the
  reconstructed looks sharper but is also pixelated in places."*
- **What this session must therefore establish:** spatial's crispness has not yet been judged against
  over-sharpening and shimmer, and temporal has to be judged scene by scene.

## Skills to invoke

- `shader-authoring` — before any `.metal` edit (ray jitter, motion vectors, the reactive mask) or new pass.
- `closeout` — at the end.
- (`preset-session` is **not** needed: no scene changes its look.)

## Read first (in order)

1. `docs/VISUAL_QUALITY_PROGRAM_PLAN.md`:
   - §3 item 1;
   - §4 "Resolution" and "Edges";
   - §5;
   - §6, including the order amendment under the table.
2. `docs/DECISIONS.md` **D-263** in full, with its EFB.4 amendment. It carries the measured conventions: the
   jitter is handed to MetalFX negated, the motion scale is 1, and depth makes no difference. It also carries the
   rule *"temporal reconstruction is for scenes whose frame does not mostly move at once; for fly-throughs, judge
   it on the glass."*
3. The MFX.2 row and the EFB.4 row in `docs/ENGINEERING_PLAN.md`. Then `DirectTemporalReconstructor.swift` and
   `RenderPipeline+TemporalReconstruction.swift`; this is the scaler wrapper to reuse.
4. The seam and the stretch:
   - `RenderPipeline+FrameSeam.swift` (frame target, present step, finish);
   - `RenderPipeline+Canvas.swift` (`renderSize`, `updateCanvas`, `copy`);
   - `UzumeApp/Views/MetalView.swift` (`tier1MaxPixels`).
5. The ray-march path:
   - `RayMarchPipeline.swift` (G-buffer formats: `gbuffer0` holds normalized depth in `.rg16Float`; `litTexture`);
   - `RenderPipeline+RayMarch.swift` (`marchScale`, `marchedPixelBudget` and its frame-rate rationale, and the
     composite that upsamples by UV);
   - the shared ray generation in `PresetLoader+Preamble.swift` (~`:654`) and `RayMarch.metal` (`rm_rayDir`).
6. NB.8: `RenderPipeline+DirectDraw.swift`, and `RenderPipeline+Draw.swift` around `:323`.
7. Prior art for ray-march temporal reconstruction is MFX.1 (`git show ffadb100`, deleted at D-213). Read it; do
   not restore it.
8. VQ.0's budget: `RenderTargetBudget` and `docs/diagnostics/VQ0_RENDER_MEMORY_INVENTORY.md`. The ceiling is
   858 MiB. A temporal scaler alone reserves about 322 MB at 4K.

## Pre-flight invariants (each failure stops the session)

- VQ.1 (#366) and VQ.1c (#367) are on `origin/main`. Work on branch `vq-3`, cut from an up-to-date `main`.
- `Scripts/closeout_evidence.sh` is green at the base.
- `Scripts/link_fixtures.sh` has run if this is a worktree.
- Record the current `PresetRegressionTests` dHash values. Capture every certified scene twice, frame-exact at
  frame 60 with fixed features, at 1080p **and** at a tier-1-capped 4K drawable. These are the "nothing changed"
  oracle (VQ.1 task 2 method).

## Tasks

1. **Inventory every upscale.** List each place a smaller image becomes a larger one:
   - the tier-1 canvas stretch;
   - the NB.8 half-resolution direct path;
   - the ray-march composite from march size;
   - MFX.2's copy;
   - anything else found.

   For each, give the formats in and out, linear or encoded, and which scenes reach it.
   **Done-when:** the table is in `docs/ARCHITECTURE.md` §Renderer, and `grep` confirms nothing is missing.

2. **Spatial upscaling as an option at each stretch.**
   - **Mechanism.** Use `MTLFXSpatialScaler` into a budgeted output texture. Use perceptual mode for the encoded
     `.bgra8Unorm_srgb` canvas, and linear or HDR mode for linear inputs.
   - **Order.** For a cinematic scene, the upscale runs **before** the finish. Then bloom and dither happen at
     output size, and the dither is never stretched into blobs.
   - **Who uses it.** Resolve the choice per scene at load. A missing sidecar entry means today's bilinear stretch.
     Also provide one place that switches the default for the whole roster; a consumer increment flips it, not
     this one.
   - **Done-when — proof scene.** Render a test-only proof scene at 4K, upscaled from 1440p and from 1080p, and
     compare it with a 4× supersampled reference. The scene has thin high-contrast lines, a fine noise field and a
     soft gradient, still and slowly panning. Report:
     - (a) gradient energy;
     - (b) overshoot (ringing) beside hard edges, as a percentage of edge contrast;
     - (c) frame-to-frame |Δ| on the pan (shimmer), each for spatial, bilinear stretch and native.
   - **Done-when — rendering.** The forced-legacy scenes render byte-identically, as the oracle says. The goldens
     do not change.

3. **Temporal reconstruction on the ray-march path.**
   - **Jitter.** Halton jitter goes in the **shared** ray generation (preamble and `rm_rayDir`). Add it to any
     scene with its own G-buffer fragment too; grep for them.
   - **Motion vectors** come from reprojecting depth with the previous and current camera.
   - **Reactive mask.** Add one for geometry that the audio moves, such as Volumetric Lithograph's swell and folds.
   - **Input and position.** The input is the lit, linear image **before** tone mapping. The output feeds whichever
     finish the scene has (the legacy `PostProcessChain` or the cinematic stage). That way a consumer can adopt
     reconstruction without also changing its finish; never bundle two look changes in one arm.
   - **Scaler.** Reuse the MFX.2 scaler wrapper. Query the scaler's supported input scale range: Volumetric
     Lithograph's 4K case is a 2.5× upscale.
   - **Opt-in.** The sidecar uses the existing `temporal_reconstruction` block (SHADER_CRAFT §17).
   - **Done-when:**
     - with zero jitter the path is byte-identical to today;
     - a ray-march proof scene, still camera and slow dolly, is compared with a supersampled reference, with ghosting
       measured (D-263 method);
     - **Lumen Mosaic** (still camera) and **Volumetric Lithograph** (forward dolly), forced on **in tests only**,
       each get 4K stills plus the task-2 metrics against their own supersampled reference.

4. **Anti-aliasing only (scale 1.0).** Use the same temporal path with input size equal to output size.
   **Done-when:** stair-stepping on the proof scene's edges is measured for native, AA-only and the supersampled
   reference, and the cost is stated.

5. **Memory and stability.** Charge every new scaler and output texture to the VQ.0 budget. Switching away from a
   scene releases them. A resize drains, releases, then allocates.
   **Done-when:**
   - a test shows Lumen Mosaic and Volumetric Lithograph with reconstruction at 4K fit under the ceiling, with
     the numbers stated;
   - a scene-switch test shows no MetalFX reservation outlives its scene;
   - the floor simulation (8 GB budget plus injected pressure) refuses or steps down and does not crash.

6. **Flash safety.** Sharpening can enlarge a flash. Run `PhotosensitivityCertificationTests` and the
   multi-pass flash suite on the proof scenes and on the forced Lumen Mosaic and Volumetric Lithograph, each with
   spatial and with temporal.
   **Done-when:** both suites are green, and each case's whole-frame, regional and red rates are stated against
   the stretch.

7. **Cost, Release, on the M2 Pro mini at 4K output.** Measure the GPU ms for the spatial upscale, the temporal
   upscale and AA-only, each from 1440p and from 1080p, as p50 and p95.
   - Use `.private` targets (`UZUME_PRIVATE_TARGETS=1`) on a saturated GPU.
   - Run one filter at a time; Swift Testing runs suites in parallel.
   - **Volumetric Lithograph's frame rate must come from a live Release session** (frame GPU ms over a few hundred
     frames inside one preset and one resolution). The harness understates its 4K cost by about 2× (PERF.16).

   **Done-when:**
   - the table is in the closeout with the build configuration stated;
   - the closeout says plainly whether Volumetric Lithograph with reconstruction holds the 60 fps Matt chose, and
     at what march scale;
   - the closeout projects the M1 cost from memory bandwidth.

8. **Docs.**
   - `docs/ARCHITECTURE.md`: §Renderer and §GPU Contract Details (the upscale step, its position in the order, the
     inventory).
   - `docs/SHADER_CRAFT.md` §17: the spatial option, and `temporal_reconstruction` on ray-march scenes.
   - `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`.
   - `docs/ENGINEERING_PLAN.md`: the VQ.3 row.
   - A D-number for the measured spatial and temporal verdicts, assigned at run time.

## Do NOT

- **Shipped scenes.** Do not opt a shipped scene in, and do not flip the roster default. No golden moves; if one
  moves, that is a bug in task 2 or 3, so stop and report.
- **Tier-1 cap.** Do not change the cap, its tier detection, or `marchedPixelBudget`.
  - The render size each Mac uses is not this increment's question.
  - Volumetric Lithograph's cap is Matt's 60 fps decision (PERF.16).
- **Energetic Flyby.** Do not touch it. Matt kept the stretch at EFB.4, and its next lever is frame generation
  (VQ.4a).
- **Out-of-scope features.** Do not add HDR or EDR (VQ.2), frame interpolation or paced presents (VQ.4a), or motion
  blur (VQ.4b).
- **MFX.1 and Fractal Descent.** Do not restore MFX.1's files or Fractal Descent (D-213 / D-201).
- **Other upscalers.** Do not add a third-party upscaler such as FSR. Do not hand-roll a sharpening filter when
  MetalFX already covers it.
- **PostProcessChain.** Do not delete it. It goes after its last legacy consumer leaves (VQ.5).
- **Pushing.** Do not push.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine --filter DirectTemporalReconstruction
swift test --package-path UzumeEngine --filter PresetRegression
swift test --package-path UzumeEngine --filter FinishFormatMatch
swift test --package-path UzumeEngine --filter PhotosensitivityCertification
swift test --package-path UzumeEngine --filter MultiPassFlash
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
Scripts/closeout_evidence.sh
```

Plus the new suites, by name: spatial upscaling, ray-march temporal reconstruction, AA-only, and the budget and
scene-switch tests.

## Commit message templates

- `[VQ.3] Renderer: upscale step — MetalFX spatial at every stretch (opt-in, bilinear default)`
- `[VQ.3] Renderer: ray-march temporal reconstruction — shared jitter, reprojected motion, reactive mask`
- `[VQ.3] Renderer: anti-aliasing-only mode (temporal at scale 1.0)`
- `[VQ.3] Tests: upscale inventory, proof scenes vs supersampled reference, oracle identity, budget, flash`
- `[VQ.3] docs: architecture, sidecar schema, registry, plan, D-number`

Local commits only. Push only on Matt's explicit "yes, push", to the `vq-3` branch with a PR, never to `main`.

## Closeout

Invoke the `closeout` skill and produce the 8-part report, with the verbatim `Scripts/closeout_evidence.sh` block
as §2. Add the following:

- the upscale inventory;
- the oracle identity result;
- the task-2 metric table for each case (still and pan, from 1440p and from 1080p);
- the cost table, with Volumetric Lithograph's live frame rate;
- the memory figures;
- the flash rates;
- one still sheet of the proof scene (native / stretch / spatial / temporal) at 4K, with your verdict on it.

Converge offline before opening any image in Matt's view (memory: *don't iterate renders in Matt's view*). Then
name the consumer increments the evidence supports. The likely ones:

- **VQ.3a:** Lumen Mosaic on temporal reconstruction.
- **VQ.3b:** Volumetric Lithograph on temporal or spatial, if it holds 60 fps.
- **VQ.3s:** the tier-1 roster on spatial.

Each one ends with Matt's 4K side-by-side.

## DECISION-NEEDED (raise at closeout, with the evidence)

**Question:** on Macs that render below 4K, should every scene switch to the sharper upscale at once, or should
scenes switch one at a time?

- **A — all at once (one review).** Matt looks at three or four very different scenes side by side: a feedback
  painting, a particle scene, a ray-marched landscape and a flat 2D scene. If they look right, the whole roster on
  his Mac mini gets crisper together.
  - Fast.
  - Risk: a scene that was not reviewed may look over-sharpened or shimmer.
- **B — scene by scene.** Each scene switches in a roster batch (VQ.5) with its own before/after.
  - Slower; most scenes stay stretched for weeks.
  - Nothing changes that Matt has not looked at.
- **Recommendation:** A, if the task-2 numbers show spatial shimmer no worse than the stretch on the pan. Keep a
  per-scene "stay on the stretch" override for any scene that fails Matt's look.
- **Default if no reply:** B. Nothing changes without his look.
