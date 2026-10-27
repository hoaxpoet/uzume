# Visual Quality Program — the TV bar (Phase VQ)

**Opened:** 2026-10-21 · **Owner:** Matt (product/design), Claude Code (implementation)
**Status (2026-10-26):** VQ.0 (#364), MFX.2 (#363) and EFB.4 (#365, not adopted — Matt kept the stretch) merged; VQ.1 built (local, `vq-1`); live status in `docs/ENGINEERING_PLAN.md` §Phase VQ. MFX.2 and EFB.4 (prompts written earlier on 2026-10-21) are folded in as
increments of this phase; each prompt carries a dated "Phase VQ amendments" block that overrides its tasks where
they conflict with this plan. Reviewed 2026-10-21 by an independent graphics review; its corrections are applied
throughout.

## 1. The goal, in Matt's words

> *"I want to significantly improve the visual quality of Uzume without crashing machines or causing application
> memory outages. I want the same quality of visuals and motion as a modern video game. Should be able to project
> out from an HDMI or USB-C port on a laptop or desktop computer to a 4K HDTV. Mac hardware only for now."*
> — 2026-10-21

Earlier the same day, on Energetic Flyby: *"I'm looking for a solution where we can significantly upgrade graphical
quality and visual / motion design polish without as much load on the machine"*; on the stretched 4K image:
*"still pixelated on fullscreen"*; on bilinear upscaling: *"it needs to be crisp and clean."*

## 2. Matt's decisions (2026-10-21)

Recorded as one D-number at VQ.0 closeout (number assigned at run time).

| Question | Decision | What it commits us to |
|---|---|---|
| Which Macs get the full native-4K TV experience? | **Every Apple Silicon Mac** | Every Mac outputs the display's native resolution. Heavier scenes render smaller internally and reconstruct; slower Macs get lighter effects, never a stretched image. |
| HDR on HDR TVs? | **Yes, on by default** | Real highlight brightness and wider colour when the display reports HDR headroom; SDR displays unchanged; flash safety (BR.1) re-measured for HDR. A setting turns it off. |
| Frame rate for heavy scenes? | **Generate frames to 60** | Heavy scenes may render at 30 and present at 60 via MetalFX frame interpolation (macOS 26). The added presentation delay is measured and the audio clock compensates for it, so beat sync does not slip. |
| Which gaps matter, in what order? | **All four: pixelation → flat light and colour → cheap motion → simple scenes** | Sets the increment order below. The fourth gap belongs to the scene programme, not this engine phase (§7). |

## 3. Where Uzume stands (verified against the code, 2026-10-21)

1. **The final image is stretched on most Macs.** `CappedMTKView.tier1MaxPixels` (`UzumeApp/Views/MetalView.swift:63`)
   caps the drawable at 2560×1440 on every Mac whose GPU name lacks "m3"/"m4"
   (`VisualizerEngine+InitHelpers.swift:376`) — including Matt's M2 Pro mini and every M1/M2 Max — and the
   compositor stretches it to 4K. That is the "pixelated on fullscreen" image. The tier test is a string match,
   not a measurement.
2. **There is no shared finishing stage.** Bloom and tone mapping (`PostProcessChain`) run on exactly three of the
   27 certified scenes (Ferrofluid Ocean, Lumen Mosaic, Volumetric Lithograph). The other 24 write the drawable
   from their own last pass, so finishing quality varies scene by scene and there is no single place to add
   anti-aliasing, HDR, grading, dithering or motion blur.
3. **The bloom that exists gets smaller as the screen gets bigger.** `PostProcess.metal` uses a hard 0.9 luminance
   cut (`:43`, no soft knee) and one 9-tap σ≈1.5 Gaussian at half resolution (`:29`). Its radius is fixed in
   pixels, so at 4K the glow covers a quarter of the screen area it covers at 1080p: light reads flatter on the
   bigger screen.
4. **Output is 8-bit SDR.** `MetalContext.pixelFormat = .bgra8Unorm_srgb` (`MetalContext.swift:55`; the comment
   above it already anticipates `.rgba16Float` EDR). Dark gradients band on a large TV, nothing dithers, and an HDR
   TV's headroom goes unused.
5. **No general anti-aliasing, motion blur or depth.** The registry records depth attachments and DoF as Missing.
   MFX.1 (MetalFX temporal, ray-march path), SSGI and the RMENV gallery environment were built, then deleted for
   having no consumer (D-213, RECON.18).
6. **GPU memory has no ceiling.** Render targets are allocated per subsystem at drawable size
   (`RenderPipeline.mtkView(_:drawableSizeWillChange:)`, `RenderPipeline.swift:753`), mostly `.shared`
   (`MetalContext.makeSharedTexture`, `:90`). One `.rgba16Float` full-screen target is ~66 MB at 4K vs ~17 MB at
   1080p; a ray-march scene holds several. Nothing totals them or refuses an allocation. `gpuPressureDescription`
   logs `currentAllocatedSize` vs `recommendedMaxWorkingSetSize` but enforces nothing.
7. **The stability record.** The one machine-exhausting event (BUG-176, 42.6 GB) came from stem preparation, not
   rendering, and has a bounded fix in flight (UND.R1–R3). The whole-app freezes BUG-085 / BUG-081 / BUG-060 remain
   unexplained. The budget governor (`FrameBudgetManager`, D-057) steps down on a 3-frame overrun but has no hard
   GPU-time ceiling and no thermal input.

## 4. The TV bar — what "done" means for the phase

Measured in Release on named machines, on a 4K display, with the build configuration stated (CLAUDE.md rule).

- **Resolution.** The drawable is the display's native **pixel** resolution (`CGDisplayMode` pixel width × height,
  e.g. 3840×2160 on a 4K TV — not the larger backing of a scaled "looks like" mode) on every Apple Silicon Mac, and
  it does not change on a scene switch. Only the internal render size varies. No scene is compositor-stretched;
  the output is reconstructed (MetalFX temporal, or MetalFX spatial as the interim for scenes without motion
  vectors), not bilinearly scaled.
- **Edges.** No visible stair-stepping or shimmer on high-contrast edges at normal viewing distance; reconstructed
  output judged against true native 4K by Matt on the TV (the EFB.4 side-by-side is the template).
- **Light and colour.** One finishing stage on every scene: resolution-independent bloom, a filmic display
  transform, per-scene grade, blue-noise dither (no banding in dark gradients on the TV), HDR when the display
  supports it.
- **Motion.** Presented frame interval p95 ≤ 17.5 ms at 60 Hz; no more than one hitch (> 25 ms) per minute
  outside scene changes; heavy scenes interpolate 30 → 60 on macOS 26 with the audio clock leading by the
  measured presentation delay. Per-pixel motion blur where the scene publishes motion vectors.
- **Stability (non-negotiable, gates every increment).**
  - Uzume's **render memory** — size-scaled targets, the drawable pool, MetalFX scaler/interpolator reservations,
    each charged at Metal's own `allocatedSize` — never exceeds its budget (VQ.0). **Over budget, the scene is
    skipped on that Mac and the next one plays** (pending Matt's confirmation in VQ.0); once a path has
    reconstruction, dropping its internal scale becomes the preferred response. Never a stretch, never a crash.
  - The whole app's footprint stays under **3 GB** (BUG-176's expected bound) on every Mac, including during stem
    preparation. Soaks kill the app at 4 GB, and a floor simulation runs with the 8 GB-Mac budget forced and
    `memory_pressure` applied.
  - A display change (plugging the TV in or out, 1080p ↔ 4K, SDR ↔ HDR) drains the frames in flight, releases the
    old render set, then allocates the new one; after the GPU is idle, footprint is back at its baseline.
  - A 60-minute 4K soak cycling every certified scene, with display-size changes every 5 minutes and stem
    preparation active, shows no drift once the first full roster cycle has loaded every scene; zero command-buffer
    errors; zero frames over 250 ms outside scene switches (switch frames are tracked separately).
  - Long GPU frames are prevented, not only reacted to: every shader loop has a compile-time bound (a single
    multi-second command buffer freezes the whole desktop through the shared WindowServer, and no governor can
    interrupt it), and the governor drops quality hard after two frames over 50 ms of GPU time.

## 5. Principles

1. **Stability floor before pixels.** Nothing raises a pixel count until VQ.0's budget, drain-release-allocate
   resize and soak exist. MFX.2 moves the drawable to the display's full pixel resolution, so VQ.0 lands first; if MFX.2 is
   already running, VQ.0 rebases onto it.
2. **Every capability ships with a named consumer, judged on the TV** (D-213: *good work is not a reason to keep
   code with no consumer*). Engine increments name their first consumer scene; the consumer increment is separate
   and ends with Matt's side-by-side on the 4K TV.
3. **One finishing stage.** HDR, grading, dither, bloom and motion blur are built once, in the shared stage, never
   per scene.
4. **No shipped scene changes look inside an engine increment.** Goldens do not move; a scene opts in at its own
   increment, where Matt judges it.
5. **Measure the floor honestly.** Matt has an M4 MacBook Pro and an M2 Pro mini; there is no M1 to measure on
   (BR.6 note). §8 says how the M1 floor is covered.

## 6. Increments

Order follows Matt's priorities. Engine and preset increments are never bundled.

| ID | Type | What exists afterwards | First consumer | Depends on |
|---|---|---|---|---|
| **VQ.0** Stability floor | engine | A render-memory budget charged at Metal's own sizes (targets, drawable pool, MetalFX reservations); drain-release-allocate on resize and hot-plug; governor inputs for GPU time, command-buffer errors, thermal state, Low Power Mode and memory pressure; a shader loop-bound audit; a GPU capability log line; a 4K render soak and a floor simulation. Prompt: `prompts/VQ.0-prompt.md`. | The whole roster (it is a safety floor) | — |
| **MFX.2** Temporal reconstruction, direct path | engine | MetalFX temporal upscaling into a budgeted output texture for opted-in direct scenes; the drawable fixed at the display's pixel mode; device depth from a declared virtual camera; frame interpolation only if paced presents can be added without moving the render loop (otherwise it moves after VQ.4a). Prompt exists; its amendments block applies this plan. | Energetic Flyby | VQ.0 |
| **EFB.4** Energetic Flyby on reconstruction | preset | Native-4K Energetic Flyby; 60 presented if MFX.2 delivered interpolation; Matt's TV side-by-side decides whether reconstruction ships. Prompt exists; its amendments block adds on-glass timing and the audio lead. | — | MFX.2 |
| **VQ.1** One finishing stage | engine | Every path renders through one seam; a shared `FinishingStage` writes a finished image; a separate present step (direct, copy or interpolator) puts it on screen and is where flash analysis and recording read. `legacy` mode is the scene's current pixels; `cinematic` adds height-relative mip-chain bloom, a filmic display transform with a headroom input (1.0 until VQ.2), per-scene grade and encoded-domain TPDF dither, fused into one pass. Prompt: `prompts/VQ.1-prompt.md`. | Ferrofluid Ocean (VQ.1c) | VQ.0; MFX.2 if it has landed |
| **VQ.1c** Ferrofluid Ocean, cinematic finish | preset | Ferrofluid Ocean on the cinematic finish; Matt's 4K-monitor side-by-side legacy vs cinematic (never gated on a TV test). | — | VQ.1 |
| **VQ.2** HDR output | engine | `.rgba16Float` drawable in extended linear Display P3 with EDR. HDR is chosen from the display's **potential** headroom (`maximumPotentialExtendedDynamicRangeColorComponentValue` > 1; built-in SDR panels report current headroom > 1 when dimmed, so current headroom alone is the wrong test); tone mapping follows the current headroom and re-reads it on change; flashes get a capped share of the headroom (full-screen HDR flashes are the real photosensitivity risk; BR.1, D-157 re-measured in linear luminance); legacy scenes keep their fixed 8-bit frame target and the finish converts, so no legacy pipeline recompiles (the BUG-061 class). A setting, on by default. | Ferrofluid Ocean, Energetic Flyby | VQ.1 |
| **VQ.3** Reconstruction for the ray-march path + native anti-aliasing | engine | MetalFX temporal on the ray-march G-buffer path (MFX.1 as prior art, `git show ffadb100`); a scale-1.0 "anti-aliasing only" mode for scenes cheap enough to render native; MetalFX **spatial** upscaling in the finish as the interim for capped scenes that publish no motion vectors (replacing the compositor stretch). | Lumen Mosaic, Volumetric Lithograph | VQ.1 |
| **VQ.4a** Frame pacing | engine | A display-link clock with rendering off the main thread and paced presents (`present(_:afterMinimumDuration:)`; Apple's frame-interpolation sample uses a separate present thread); `framebufferOnly` restored when not recording; an opaque full-screen layer so macOS can scan it out directly; on-glass time measured from `addPresentedHandler`. **Frame interpolation lands here if MFX.2 had to skip it.** | Energetic Flyby | MFX.2 |
| **VQ.4b** Motion blur | engine | Per-pixel motion blur in the finishing stage from the motion vectors MFX.2/VQ.3 already require. | Energetic Flyby + one ray-march scene | VQ.1, VQ.3, VQ.4a |
| **VQ.5** Roster on the TV | preset (batches) | The certified roster moves to the cinematic finish in batches of 4–6; each batch: Matt's TV review with a before/after toggle, flash and contrast certification re-run, 4K frame budget measured on both machines. | — | VQ.1–VQ.4 |
| **VQ.6** TV mode | UX | Choosing the TV as the output display; Uzume fullscreen there while controls stay on the laptop; behaviour when the TV is unplugged mid-session; reading the real output mode (adapters, 4:2:0 chroma, 30 Hz links); an **A/V offset calibration** for TVs that delay the picture (15–100+ ms outside Game Mode), separate from the interpolation lead. Product decisions surfaced at the time. | — | VQ.0, VQ.2, VQ.4a |

MFX.2 and VQ.1 both touch the path from the scene to the screen. The order on screen, fixed by Apple's MetalFX
guidance (WWDC25 session 211): **render (jittered) → temporal upscale → finish (bloom, tone, grade, dither, motion
blur) → frame interpolation → present.** The upscaler writes a texture, never the drawable; the interpolator, when
present, is the only thing besides the plain present step that writes the drawable, and it needs the previous
finished frame.

**Order amended 2026-10-27 (Matt): pixelation first — VQ.3 runs before VQ.2.** Prompt: `prompts/VQ.3-prompt.md`.

Prompts are written for VQ.0, VQ.1 and VQ.3. Later prompts are written from what those increments measure
(CLAUDE.md: commit decisions when the work has produced evidence).

## 7. What this phase will not do

- **Make a simple scene astonishing.** The engine raises every scene's ceiling — crisp 4K, HDR light, smooth motion —
  but a scene with a thin concept stays thin. Matt's fourth priority ("the scenes look simple") belongs to the scene
  programme under `preset-concept`; new scenes are built on the finishing stage from day one.
- **Revive deleted capabilities without a consumer.** SSGI, the RMENV gallery and the D-201 Fractal Fly-By case stay
  dead unless a named scene needs them.
- **Use frame interpolation on scenes whose frames share no structure** (D-201: they boil).

## 8. Open items

1. **The M1 floor cannot be measured here.** Options: borrow or buy a base M1 MacBook Air (8 GB, USB-C to HDMI
   adapter: the slowest and most memory-constrained target), or rely on tester reports through BR.5's
   Report a Problem. Recommendation: get an M1 Air for the phase; the memory budget's worst case lives there.
2. **USB-C to HDMI adapters set the ceiling on Airs.** Apple: adapters are not supported for 8K or 4K240 and each
   adapter's specs apply; built-in HDMI reaches 8K60 / 4K240 on M2 Pro and later MacBook Pros, M2 Pro / M4 Mac
   minis and 2023+ Studios; older Macs are 4K60. Many cheap adapters are 4K30, and 4K60 HDR over HDMI 2.0 drops to
   4:2:0 / 4:2:2 chroma. VQ.6 reads the actual mode rather than assuming it.
3. **The picture on a TV can lag the sound.** TVs outside Game Mode add 15–100+ ms of processing; when the music
   plays from the Mac's speakers, the visuals arrive late however well Uzume times its own frames. On-glass time
   is measured from VQ.4a; a user calibration lands in VQ.6. The interpolation lead (EFB.4) only covers Uzume's own
   delay.
4. **macOS 15–25 have no frame interpolation.** On those, heavy scenes run at 30 presented (today's behaviour) or
   drop internal scale to hold 60 — chosen per scene from EFB.4's measurements.

## 9. Sources

- Apple, *Connect to HDMI from your Mac* — https://support.apple.com/en-gb/108928
- Metal 4 / MetalFX frame interpolation overview — https://lowendmac.com/2025/metal-4-an-overview/
- Apple Developer, `MTLFXFrameInterpolatorDescriptor` — https://developer.apple.com/documentation/metalfx/mtlfxframeinterpolatordescriptor
- Apple, WWDC25 session 211, *Go further with Metal 4 games* (upscale before post, interpolate after tone mapping,
  paced presents) — https://developer.apple.com/videos/play/wwdc2025/211/
