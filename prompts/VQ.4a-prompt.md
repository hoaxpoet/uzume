# Increment VQ.4a — Frame pacing: every frame on the glass on time, and generated frames for heavy scenes (engine increment)

**Objective.** After this session the engine puts frames on the screen at an even beat. For heavy scenes, it can
also present 60 frames a second from 30 rendered:

- **Paced presents, measured on the glass.** Every scene's frames reach the screen at a steady interval. The engine
  knows when each frame actually appeared (`addPresentedHandler`), not just when it was submitted. The TV bar's
  motion targets (plan §4) become measurable: presented-interval p95 ≤ 17.5 ms at 60 Hz, at most one hitch
  (> 25 ms) per minute outside scene changes.
- **Frame interpolation as a capability.** MetalFX frame interpolation (macOS 26) can generate the in-between frame
  for a scene that renders at 30 and publishes depth and motion. It runs after the finish and presents 60. It is
  proven on a test-only proof scene and on Energetic Flyby **offline**.
- **Picture delay measured and led.** The extra delay the interpolator adds is measured on the glass. The
  beat-grid clock leads by that amount, so a downbeat colour turn still lands on the beat.
- **No shipped scene changes its look or its frame rate in this increment.** Energetic Flyby keeps 30 fps. Its
  adoption is its own increment, **EFB.5**, decided by Matt's side-by-side on the 4K monitor (the MFX.2 → EFB.4
  template).

**Why now.** D-264 (Matt, 2026-10-21): *"Generate frames to 60"*: heavy scenes may render at 30 and present 60,
with the audio clock compensating for the added delay. MFX.2 skipped interpolation (D-263 amendment A5) for two
reasons. Two presents per frame need a present clock that the main-thread MTKView loop lacks. And interpolated
frames would bypass the recorder that the flash analyzer reads. EFB.4's lesson (D-263 amendment): for a forward
fly-through, temporal upscaling bought neither crispness nor frames, and *"frame generation (VQ.4a) is the next
lever for this scene."* VQ.1–VQ.3 are merged, so the order on screen is settled: render → upscale → finish →
**interpolate** → present.

**What is already true** (verified 2026-11-12 against `main` at a7232c4a):

- **The render loop is the MTKView's own, on the main thread.** `PixelModeMTKView`
  (`UzumeApp/Views/MetalView.swift`): `isPaused = false`, `enableSetNeedsDisplay = false`. `RenderPipeline.draw(in:)`
  is `@MainActor` (`RenderPipeline.swift:893`). The comment at `RenderPipeline.swift:962` says the draw runs on
  "MTKView's CVDisplayLink thread". That comment is stale for the draw itself. The per-field locks it describes
  guard against `applyPreset`, and they matter more once the draw leaves the main thread.
- **The frame-rate cap is `preferredFramesPerSecond`.** `applyFrameRateCap(to:)`
  (`RenderPipeline+PresetSwitching.swift`) takes the minimum of the scene's cap (Energetic Flyby: 30, EFB.1) and
  the governor's thermal / Low Power cap (VQ.0).
- **One present, one place.** `instrumentedPresent` (`RenderPipeline+FrameSeam.swift`) finishes into the drawable,
  records what reached the glass (`recordAtCanvasSize`, `presentedFrameTexture`), then calls
  `commandBuffer.present(drawable)`. Nothing uses `present(_:afterMinimumDuration:)` or `addPresentedHandler`.
- **`framebufferOnly = false` always**, for the session recorder's blit (`MetalView.swift:50`).
- **No on-glass timing exists.** The timing columns are `frame_cpu_ms` (which includes the drawable wait; memory:
  frame_cpu_ms is not CPU) and `frame_gpu_ms`. Neither is when the frame appeared.
- **The interpolator API exists on this SDK.** `MTLFXFrameInterpolatorDescriptor` (macOS 26.0+,
  `supportsDevice:`).
  - Inputs: `colorTexture`, `prevColorTexture`, `depthTexture`, `motionTexture`, motion scale, `deltaTime`,
    near/far/FOV/aspect, jitter, an optional UI texture, `shouldResetHistory`.
  - Separate input and output sizes.
  - Matt's machines run macOS 26.5. The deployment target is macOS 15 (D-261), so the capability is
    `@available(macOS 26, *)` with a fallback.
- **Energetic Flyby can publish depth and motion** (EFB.4). Its fragment writes NDC depth and closed-form motion on
  the reconstruct path only. On the plain path, `render_size` is zero and it writes `depth = 1`, `motion = 0`
  (`EnergeticFlyby.metal:381`). D-263's amendment kept those outputs for VQ.4a and VQ.4b.
- **Offline, MetalFX interpolation already beat a blend** (MFX.2): it landed 2.4× closer to the true midpoint
  (|Δ| 0.031 vs 0.073), with 0 motion-gate spikes.
- **A beat-grid lead exists.** `LiveBeatDriftTracker.audioOutputLatencyMs` (BR.17 / BUG-007.6) is the output
  device's latency (at least 50 ms) plus a developer trim, and offsets the beat phase. An interpolation lead adds
  to it. It does not replace it.
- **Energetic Flyby's flash margin is zero.** It reads regional 3.00/s on the worst-case train
  (`energeticFlybyIsFlashSafe`) and on three real songs at the captures' own 43.1 Hz
  (`energeticFlybyIsFlashSafeOnRealMusic`, BUG-182). A recorded sequence is counted at its own frame rate
  (`FlashHarnessSupport.captureFPS`), never an assumed 60.

## Matt's decisions so far

- **D-264:** frame generation to 60 for heavy scenes; the added delay is measured and the audio clock compensates;
  every Apple Silicon Mac; a TV test is never a gate (the 4K monitor stands in).
- **EFB.1:** smooth 30 fps over crisp lower rates; no upscaling for Energetic Flyby, ever (EFB.4 option B).
- **EFB.4:** reconstruction rejected on the glass. Lesson: judge a fly-through on the glass, never from metrics.
- **Plan §7:** no interpolation on scenes whose frames share no structure (D-201, they boil).
- **Plan §8.4:** on macOS 15–25 there is no interpolation; heavy scenes run at 30 presented, as today.
- **This prompt (Matt, 2026-11-12):**
  - Energetic Flyby's move to 60 is its own increment, **EFB.5**, decided by his 4K-monitor side-by-side.
  - **When a Mac can't keep up with 60, the scene drops to a steady 30 and stays there until the scene changes.**
    One visible step, then no flicker; never switching back and forth with load.
  - The Spotify question below is decided **on the measured numbers**.

## DECISION-NEEDED (asked at task 5, after task 4's measurements)

Ask it in words, quoting task 4's numbers. Do not open images in Matt's view to ask (memory: don't
iterate renders in Matt's view).

**On Spotify, how should generated frames handle the delay?**

On local files, Uzume plays the audio and knows every reaction ahead of time. The whole picture can lead, so
nothing slips. On Spotify, the downbeat colour turns follow the cached beat grid and can lead too. The energy
reactions (flight speed, glow, sphere spin) are heard live and cannot. With generated frames, they would land
about one rendered frame later than today (task 4 measures the real figure, about 33–50 ms expected).

- **A. Generate frames on both.** Smoother on Spotify. Energy reactions trail the sound by the measured extra
  delay, while the downbeats stay on the beat.
- **B. Local files only.** On Spotify, the scene stays at today's 30 with today's timing. Smoothness depends on
  the audio source.

**Recommendation:** A if task 4's extra delay is ≤ 40 ms, which is about one video frame at 24 fps and below what
most listeners notice on a continuous reaction. Otherwise B. **Default if no reply:** B. It changes nothing a
listener can hear against. (Matt chose, 2026-11-12, to decide this on the measured numbers, with this
recommendation.)

## Skills to invoke

- `shader-authoring`: before GPU-facing code (interpolator encode, the proof scene).
- `closeout`: at the end.
- `preset-session`: only if a sidecar or `.metal` file is touched (Energetic Flyby's depth/motion on the plain
  path, task 6).

## Read first (in order)

1. `docs/VISUAL_QUALITY_PROGRAM_PLAN.md`: §2, §4 (Motion, Stability), the VQ.4a row in §6 and the order note after
   the table, §8.3–8.4.
2. `docs/DECISIONS.md`: D-263 (amendment A5 and the EFB.4 amendment), D-264, D-201, D-267–D-269 (via the §Index).
3. `docs/ARCHITECTURE.md`: the frame seam / present step (grep `VQ.4a`, around lines 240–250).
4. `UzumeApp/Views/MetalView.swift` (`PixelModeMTKView`).
5. `UzumeEngine/Sources/Renderer/RenderPipeline.swift` (`draw(in:)`), `RenderPipeline+FrameSeam.swift`
   (`instrumentedPresent`, `frameTarget(for:)`), `RenderPipeline+PresetSwitching.swift`
   (`applyFrameRateCap`, `applyPreset`).
6. `UzumeEngine/Sources/Renderer/DirectTemporalReconstructor.swift` and `RenderPipeline+TemporalReconstruction.swift`.
   The MRT path, motion conventions and budget charging the interpolator will reuse.
7. `UzumeEngine/Sources/Renderer/RenderTargetBudget.swift` (VQ.0). The interpolator's textures are charged here.
8. `UzumeEngine/Sources/Presets/Shaders/EnergeticFlyby.metal` (the EFB.4 depth/motion block).
9. `UzumeEngine/Tests/UzumeEngineTests/Renderer/MultiPassFlashHarnessTests.swift` (both Energetic Flyby gates),
   `FlashHarnessSupport.swift` (`captureFPS`).
10. Memory / docs on the render clock: per-frame `dt` used as a DURATION breaks when frame timing changes (BUG-097,
    FTR.31).

## Pre-flight invariants (each failure stops the session)

- Work on branch `vq-4a`, cut from an up-to-date `main` (at or after a7232c4a).
- `Scripts/link_fixtures.sh` has run if this is a worktree.
- `Scripts/closeout_evidence.sh` is green at the base.
- Record the baseline: `PresetRegressionTests` dHash values, both Energetic Flyby flash gates (whole, regional,
  red), and `RenderTargetBudget`'s largest certified 4K set (VQ.0: 858 MiB ceiling).

## Tasks

1. **Measure today on the glass, before changing anything.** Add `addPresentedHandler` timing behind a log flag
   (no behaviour change) and record presented time and interval per frame.
   - Live Release app, Developer ID build (memory: Apple-Dev builds loop on Screen Recording).
   - Machines: the M2 Pro mini on the LG 4K, and the M4 MacBook Pro on its own panel at 120 Hz.
   - Scenes: one light scene, Energetic Flyby (30 fps cap), and a heavy ray-march scene (Volumetric Lithograph).
   - 60 s clean windows each. Check `RENDER_TARGET` first: a near-square window costs ~1.5×.
   - Report per run: presented-interval p50/p95/p99, hitches > 25 ms per minute, and the submit → on-glass delay.

   **Done-when:** the table exists, and you can say in one sentence where today's uneven frames come from.
   Candidates: main-thread stalls, drawable wait, GPU overrun, or 60/30 beat against the display.

2. **Pace the presents.** Give the render loop a display-link clock off the main thread, and present at the
   scene's interval (`present(_:afterMinimumDuration:)`), so a 30 fps scene shows every frame for exactly two
   60 Hz refreshes.
   - Every main-thread entry point the draw touches (`applyPreset`, SwiftUI-driven setters, the recorder) must be
     made safe. The swap-window guard (BUG-061 / BUG-060) must still hold under the new thread.
   - Restore `framebufferOnly = true` when no recording is running.
   - Make the full-screen layer opaque so macOS can scan it out directly.
   - Decide whether this needs `CAMetalDisplayLink` or `CVDisplayLink` and a present thread (Apple's interpolation
     sample uses a separate present thread). Record why.

   **Done-when:**
   - task 1's table, re-run, meets plan §4 on the light scene and on Energetic Flyby on both machines;
   - no new main-thread assertions;
   - `PresetRegressionTests` unchanged;
   - the full engine and app suites pass.

3. **Interpolation, the capability.** Build an `@available(macOS 26, *)` frame interpolator after the finish.
   - It takes the previous and current finished frames, the scene's depth and motion, and presents the generated
     frame then the real one.
   - Charge every texture it holds to `RenderTargetBudget`. Over budget, it declines and the scene presents 30,
     never crashes.
   - Opt-in is a sidecar field (SHADER_CRAFT §17). No shipped scene opts in.
   - **Both presented frames pass through the recorder and the flash analyzer's read point.** The analyzer counts
     at the presented rate (60), and a capture records its own rate (BUG-182).
   - On macOS 15–25, or when `supportsDevice:` is false, the scene presents as today.
   - Prove it on a test-only proof scene with known motion (the MFX.2 lattice is the template). Measure: distance
     from the true midpoint vs a blend, motion-gate spikes, ghosting.

   **Done-when:**
   - the proof scene interpolates closer to the truth than a blend;
   - 0 motion-gate spikes;
   - the format matrix passes under `MTL_DEBUG_LAYER=1`;
   - a negative control (interpolator removed) fails the "two presents per rendered frame" check.

4. **Measure the delay and Energetic Flyby offline.**
   - **Delay.** On the glass, with the proof scene at 30 → 60, measure the extra submit → on-glass delay the
     interpolator adds, p50 and p95.
   - **Energetic Flyby, offline only.** Drive its plain path with depth and motion live (the EFB.4 outputs,
     `render_size` set, no temporal scaler) through the interpolator. Use the three real-audio route fixtures
     (`so_what`, `there_there`, `love_rehab`), each at its own rate. Report:
     - GPU cost per presented frame at 2560×1440 → the 4K drawable on the M2 Pro (Release, `.private`, GPU
       saturated), and the share of frames that miss 16.7 ms;
     - motion-gate spikes;
     - both flash gates on the 60-presented sequence: regional must stay ≤ 3.00/s, at the limit, as today;
     - where the generated frames are wrong (disocclusion around the spheres and rods; the thin shells).
       Write masks and look at them yourself.

   **Done-when:** the delay and Energetic Flyby tables exist. If interpolation adds a flash, **stop and report.** Do
   not dim, slow or change the scene to buy margin. Its look is Matt's call (EFB.1), and its margin is zero.

5. **Ask Matt the DECISION-NEEDED question** with task 4's numbers. **Stop and wait for his answer** (or apply the
   default if he says to go on without one).

6. **Lead the clock, and fall back to a steady 30.** Add the measured interpolation delay to the beat-grid lead,
   but only while a scene is interpolating. On local files, also lead the pre-analysed feature series by the same
   amount.
   - Apply Matt's answer to the Spotify path.
   - Fallback (Matt's decision): after a sustained miss of 60, stop interpolating and present a steady 30 until
     the next scene change. Never switch back mid-scene. You choose the miss rule; record it.

   **Done-when:**
   - a downbeat's colour turn lands within ±1 rendered frame of the grid's downbeat on the glass, with
     interpolation on and off (`features.csv` beat columns plus presented times);
   - a log trace from a forced GPU overrun shows one step to 30 and no return within the scene.

7. **Docs.**
   - A D-number for frame pacing and interpolation, assigned at run time from the tree (D-270 if free).
   - ARCHITECTURE: the render loop, the present step, the interpolator, the lead.
   - SHADER_CRAFT §17: the opt-in field.
   - RUNBOOK: the on-glass log flag and how to read it.
   - ENGINEERING_PLAN: the VQ.4a row, plus an **EFB.5** row: Energetic Flyby at 60 presented, decided by Matt's
     4K-monitor side-by-side (prompt written from task 4's numbers).
   - RENDER_CAPABILITY_REGISTRY: new rows for paced presents / on-glass timing and for frame interpolation (proof
     scene only, no shipped consumer).

## Do NOT

- **Shipped scenes.** No shipped scene opts into interpolation, changes its look, or changes its frame-rate cap.
  Energetic Flyby stays at 30 until EFB.5.
- **Energetic Flyby.** No upscaling, no cuts to its march to pay for interpolation (EFB.1), no brightness or
  coupling change to buy flash margin.
- **Boiling scenes.** Do not interpolate a scene whose frames share no structure (D-201, plan §7).
- **The flash analyzer.** Do not let any presented frame bypass the recorder or the analyzer's read point, and do
  not count a sequence at a rate other than its own (BUG-182).
- **Render clock.** Do not use the per-frame `dt` as a duration anywhere new (BUG-097). Pacing changes its
  distribution.
- **Budget.** Do not exceed the VQ.0 memory ceiling or hold interpolator textures outside `RenderTargetBudget`.
- **Pushing.** Do not push. Matt approves each push ("yes, push"), to the `vq-4a` branch with a PR, never to
  `main`.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
swift test --package-path UzumeEngine 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine --filter PresetRegression
swift test --package-path UzumeEngine --filter MultiPassFlash
swift test --package-path UzumeEngine --filter EnergeticFlyby
swift test --package-path UzumeEngine --filter FinishingStage
MTL_DEBUG_LAYER=1 swift test --package-path UzumeEngine --filter FinishFormatMatch
swift test --package-path UzumeEngine --filter RenderTargetBudget
swift test -c release --enable-testable-imports --package-path UzumeEngine --filter <timing suites>
xcodebuild -scheme UzumeApp -configuration Release -destination 'platform=macOS' build
Scripts/closeout_evidence.sh
```

Plus `Scripts/motion_gate.sh` (D-195) on the proof scene and on Energetic Flyby's offline interpolated sequence.
Every timing figure states its build configuration and machine (CLAUDE.md).

## Commit message templates

- `[VQ.4a] Renderer: log when each frame reaches the glass`
- `[VQ.4a] Renderer: display-link clock off the main thread, paced presents`
- `[VQ.4a] Renderer: framebufferOnly when not recording, opaque full-screen layer`
- `[VQ.4a] Renderer: MetalFX frame interpolation after the finish, opt-in, budgeted`
- `[VQ.4a] Tests: interpolation proof scene, flash at the presented rate`
- `[VQ.4a] Renderer: the beat-grid clock leads by the interpolation delay`
- `[VQ.4a] docs: D-number, architecture, shader craft, runbook, registry, plan (+ EFB.5 row)`

## Closeout

Invoke the `closeout` skill and produce the 8-part report, with the verbatim `Scripts/closeout_evidence.sh` block
as §2. Add the following:

- task 1's before table and task 2's after table (both machines, three scenes);
- the thread / display-link choice and why;
- the proof scene's interpolation results;
- the delay table, and Energetic Flyby's offline table (cost, missed frames, motion gate, flash at 60 presented);
- Matt's DECISION-NEEDED answer, quoted, and the fallback trace;
- the downbeat-on-the-glass check;
- what EFB.5 should show Matt.
