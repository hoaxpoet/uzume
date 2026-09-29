# Lane D: renderer core, performance, memory and hangs

Read-only review. I did not run any builds or suites. The evidence comes from the code, the BUG-085 freeze artifacts in `~/Documents/uzume_sessions/_freeze_captures/`, `/Library/Logs/DiagnosticReports`, and the unified log for today's first launch of the installed `/Applications/Uzume.app` (0.9.0 build 4, M2 Pro).

**Headline.** Four things matter most for the beta:
- **Fractal Tree is broken on every M1-family Mac.** It is a certified scene on the beta slate.
- **The BUG-085 record misreads its own freeze capture.** The capture shows new facts that change where to look.
- **Resolution has no ceiling outside the ray-march scenes.** Retina and 5K testers render 2.5–7× the pixels anyone has measured, and the quality governor can't take any of it back.
- **First launch spends about 4 s compiling shaders on the main thread before a window appears.**

---

## Findings (most severe first)

### D1 — Fractal Tree shows a flat green gradient on all M1 / M1 Pro / Max / Ultra Macs
**P1 · VERIFIED · effort S–M**
- **Where:**
  - `Presets/PresetLoader+Mesh.swift:50`: `if device.supportsFamily(.apple8) { …native mesh… } else { compileMeshPipelineFallback… }`
  - `Renderer/Geometry/MeshGenerator.swift:249`: same gate.
  - `Shaders/FractalTree.metal:1297` `fractal_tree_fallback_vertex` is a fullscreen triangle with a constant normal: *"renders a visible gradient rather than solid black"*.
- **Scenario:**
  - M1 is GPU family Apple7 and M2 is Apple8, so every M1-family Mac takes the fallback. That is the 8 GB M1 Air low end of the beta.
  - The fallback still loads, and the planner has no device exclusion. The only tier gate is `complexity_cost`: tier1 = 1.2 ms, far under budget. So Fractal Tree gets scheduled normally.
  - The tester sees a full-screen green wash where a dancing tree should be, for a whole segment.
  - Matt's dev machine is an M2 Pro, so this path has never been seen live. `GOLDENGROVE_RESEARCH.md:11` notes "M1/M2 fallback = fullscreen gradient", but it is not in KNOWN_ISSUES.
- **Fix direction:** Metal 3 mesh shaders are supported on Apple7, so gating the native path on `.apple7`/`.metal3` probably makes it render on M1. That needs one run on an M1. Failing that, exclude mesh-only scenes from the catalog when `!supportsFamily(.apple8)`.

### D2 — New evidence on BUG-085: the instrumented freeze capture does not show what the entry says it shows
**P1 (it redirects the only open P1 hang) · VERIFIED against the artifacts · effort S (docs + next test)**

KNOWN_ISSUES §BUG-085 says:
- the counters were balanced "at the moment of the hang";
- the block was "PERMANENT… the render thread never took another step in 98 seconds";
- "Only the render thread died… Audio, ML and the analysis queues all ran on normally."

The artifacts in `_freeze_captures/bug085_20260805T224531Z/` contradict all three:
1. **The render loop kept running about 7 s past the "frozen" heartbeat.**
   - `session.txt` reports `features rows: 6449`.
   - `features.csv` gets exactly one row per completed rendered frame (the `recordFrame` completion handler in that build's `setupCaptureHook`). The probe counts every frame, including skipped ones, so frames ≥ 6449.
   - The last heartbeat says `frames=6013`, so at least 436 more frames completed after it.
   - Its `pending=frame:6013,site:mesh.descriptor,age_ms:8` is an ordinary in-flight request. A healthy heartbeat has the same shape: `frames=4813 … pending=frame:4813,site:mesh.descriptor,age_ms:0`.
   - The heartbeat only prints every 600 completions, so "byte-identical 98 s apart" happens by construction for any stop.
2. **Everything stopped at the same moment.**
   - At 60.7 fps (heartbeats 5406 → 6013), frame 6449 lands at about 22:43:58.
   - The last `session.log` line of any kind is at 22:43:57.
   - SIGNAL_HEALTH and stem-separation lines, both on a roughly 5 s cadence, never appear again, and the capture was 94 s later.
   - In all three samples (22:44:33, :45:31, :47:09), every non-main thread is parked, including the audio `IOThread.client`, at 0 % CPU.
3. **The HANG.1 watchdog never logged a STALL.**
   - In that build (`f81c36cb`) it was a `Task.detached` that logs `DRAWABLE_LIFECYCLE STALL` within 0.5–0.75 s of a blocked request. It had no main-thread dependency.
   - No STALL line exists. So either the whole process stopped being scheduled, or the recorder stopped writing at that instant. `safeWrite` halts silently on a write error (disk-full guard), and the only halt message goes to the unified log.
4. **Both BUG-085 captures are Debug builds launched from Xcode.** `Parent Process: debugserver` appears in both samples and in `docs/diagnostics/BUG085_NEXTDRAWABLE_HANG_2026-08-04.md`. The June BUG-060 instance was also force-quit from Xcode. By the entry's own note, the Aug-3 BUG-060 recurrence was not an Xcode launch, so the debugger is a confounder to control, not an explanation.
5. **The "permanent block" claim conflicts with CAMetalLayer's defaults.**
   - `allowsNextDrawableTimeout` is never set, so it is on, and `nextDrawable` returns nil after 1 s. The stack's `semaphore_timedwait_trap` is a timed wait.
   - A single call cannot block for 98 s. Either the loop kept retrying (which would have produced STALL lines) or the process was not running.

- **Tester impact:** the investigation is aimed at "CoreAnimation withholds drawables from one thread" when the evidence points to a whole-process stop or a recorder halt.
- **Fix direction:**
  - Correct the entry.
  - Run a Release build launched from Finder for a long session. This is the decisive control, since testers run Release outside Xcode.
  - On the next freeze, ask the one discriminating question for local files: did the music keep playing?
  - The watchdog should log a 1 Hz "last completion age" beacon, independent of completions, so a process-wide stop can be told apart from a render-only stop.

### D3 — The hang-capture path is broken, and the beta has none at all
**P2 · VERIFIED · effort S**
- **Where:**
  - `Scripts/capture_hang.sh:18` `PID=$(pgrep -x UzumeApp | head -1)`, and `Scripts/support/window_state.swift:19` filters on owner `"UzumeApp"`. Since RN.1, `PRODUCT_NAME = Uzume` in Debug and Release (`project.pbxproj:1364,1395`); the unified log shows process `Uzume[91117]`. The script exits "UzumeApp is not running — nothing to sample." This is the instrument BUG-085/081/060 all say to run next.
  - The current watchdog (`VisualizerEngine+InitHelpers.swift:211`) now does `await MainActor.run { gpuPressureDescription() }` in its heartbeat branch. It is no longer independent of the thread it watches: if a heartbeat bucket rolls over after main blocks, from in-flight completions, STALL is never written.
  - `capture_hang.sh` does not collect `log show`, even though the watchdog also writes STALL as `.fault`, which the unified log persists.
- **Scenario:** testers won't run scripts. A hang on a tester's Mac yields nothing: force-quit leaves no `.ips`, and `session.log` stops.
- **Fix direction:**
  - Fix the process name.
  - Drop the MainActor hop from the watchdog.
  - Add `log show --last 15m --predicate 'process == "Uzume"'` and `df -h` to the script.
  - For the beta: when the watchdog sees no completions for more than 5 s with a session live, persist a marker. On next launch, offer "Uzume froze last time — send diagnostics".

### D4 — No render-resolution ceiling outside ray-march; Retina and 5K testers render 2.5–7× the budgeted pixels
**P1 · PLAUSIBLE (scaling from the repo's own measurements; not measured on M1 or Retina) · effort M**
- **Where:**
  - `MetalView.swift` leaves `autoResizeDrawable` on, so the drawable is at native backing resolution.
  - The only caps are `RenderPipeline+RayMarch.swift:66` `marchScale` (ray-march only) and Nimbus's `directRenderScale`.
  - Feedback, mv_warp, staged, direct and particle paths allocate and shade at full drawable size.
- **Evidence:**
  - Every `RENDER_TARGET` line in Matt's recent sessions reads `width=1920 height=1080` or `901×601`. His display is 1080p at 1×, so no live session has ever run at Retina pixel counts.
  - `PresetFrameBudgetTests` baselines are at 1920×1080 on an M2 Pro: Cytokinesis 14.6 ms, Stave 14.5, Skein 13.2, Gossamer 9.8 harness-ms; the harness reads about 0.56× live.
  - A fullscreen M1/M2 Air is about 2.5× those pixels on a GPU about 2× slower than an M2 Pro. A 5K Studio Display is 7.1×.
- **Scenario:** an 8 GB M1 Air goes fullscreen and many scenes drop to roughly 10–30 fps. Rendering runs on the main thread (`draw(in:)` is `@MainActor`, with `inflightSemaphore.wait()` and `nextDrawable` inline), so the chrome, Esc, shortcuts and End Session also lag.
- **Fix direction:**
  - Before Oct 15, measure the roster with the existing `FRAME_BUDGET_RES=2880x1864` (and 5120x2880) on an M1-class GPU.
  - The cheapest mitigation is a global pixel budget: set `autoResizeDrawable = false` and a capped `drawableSize`, and let the compositor upscale. That is the same idea as the ray-march cap, applied to every path.

### D5 — The quality governor can't take back GPU cost for most scenes; Low Power Mode barely changes anything
**P2 · VERIFIED · effort M**
- **Where** (`RenderPipeline+BudgetGovernor.swift`):
  - `.reducedParticles` writes `activeParticleFraction`, which no geometry ever reads. Grepping every conformer finds only the stored property; `AlfvenSolver.swift:43` says "accepted and ignored".
  - `.reducedMesh` passes a density value at buffer(1), which Fractal Tree (the only mesh scene) never binds.
  - `.noBloom` only affects scenes with a PostProcessChain.
  - `.reducedRayMarch` only affects scenes using the preamble's default march loop.
  - Low Power Mode floors at `.noBloom` (`FrameBudgetManager.swift` `qualityFloor`).
  - There is no frame-rate or resolution rung.
- **Scenario:** on battery, in Low Power Mode or under thermal pressure, direct, mv_warp, staged, feedback and particle scenes (most of the roster) keep full GPU cost. Laptops run hot and drain, and frame rate still falls.
- **A second, PLAUSIBLE problem:** the governor's `cpuMs` includes drawable and vsync wait, which ramps 0 → 8.7 ms per the existing frame_cpu_ms note. Against the tier-1 threshold of 14.3 ms, a mid-cost scene on M1/M2 can downshift (bloom off, steps 0.75) with no real overload.
- **Fix direction:** add a resolution-scale rung and a 30 fps rung (`preferredFramesPerSecond`), and drive the governor from `gpuEndTime - gpuStartTime` only. Delete or wire the two dead rungs.

### D6 — Cold first launch blocks the main thread about 4.2 s compiling every shader from source, before any window appears
**P2 · VERIFIED (unified log, installed 0.9.0, M2 Pro, 2026-09-29) · effort M**
- **Where:** `UzumeApp.swift:27` `@StateObject private var engine = VisualizerEngine()`. This builds `ShaderLibrary` (`makeLibrary(source:)`) and `PresetLoader`, which compiles 32 presets, each about 5.2k utility lines + preamble + scene, plus their pipeline states. All of it is synchronous on thread `6560b7`, the main thread; AppKit logs "No windows open yet" on that thread.
- **Measured** for pid 91117, the first launch of `/Applications/Uzume.app` today:
  - `ShaderLibrary` 09:46:20.900 → 21.446 (0.55 s).
  - Presets 21.452 → 25.094 (3.64 s, about 110 ms each).
  - A further 5.6 s passed between process spawn (09:46:15.1) and the first app log (unattributed; possibly the first-launch Gatekeeper check).
  - A warm launch of the Debug build took 43 ms, so Metal's cache hides this from developers.
- **Scenario:** a tester's first launch shows a bouncing Dock icon with no window for about 5 s on an M2 Pro, likely 8–10 s on an M1 including the pre-main gap. It recurs after every app update and macOS update (cache invalidation).
- **Fix direction:** ship a precompiled `.metallib` (compile at build time), and optionally `MTLBinaryArchive`. At minimum, show the window first and compile off main.

### D7 — Fullscreen, move-display and hot-plug handling silently absent for streaming sessions
**P2 · VERIFIED code path; one API-semantics link PLAUSIBLE · effort S**
- **Where:** `PlaybackView.swift:233` `if let window = NSApp.keyWindow { fullscreenObserver.attach…; DisplayManager…; MultiDisplayToastBridge…; DisplayChangeCoordinator… }`. It runs once, in `onAppear`, with no retry.
- **Scenario:**
  - In the streaming flow, `ReadyViewModel` auto-advances to `.playing` when first audio is detected. That is right after the tester presses play in Spotify or Music, so that app is frontmost and `NSApp.keyWindow` is nil (an inactive app has no key window).
  - For the whole session: ⌘F does nothing (`window?.toggleFullScreen` on nil), and ⌘⇧F does nothing.
  - If the tester fullscreens with the green button, **Esc opens "End session?" instead of leaving fullscreen**, because `onHandleEsc` checks `fo.isFullscreen`, which is never observed.
  - Display hot-plug toasts and the coordinator never exist.
- **Fix direction:** resolve the hosting window from the view itself (an `NSViewRepresentable` window accessor or `viewDidMoveToWindow`) instead of `NSApp.keyWindow`.

### D8 — DisplayManager treats `NSScreen.main` as the menu-bar display
**P3 · VERIFIED · effort S**
- **Where:** `DisplayManager.swift:3` ("NSScreen.main is the primary (menu bar) screen"), and `moveToPrimaryDisplay`/`moveToSecondaryDisplay`. `NSScreen.main` is the key-window screen; the menu-bar screen is `NSScreen.screens.first`.
- **Scenarios:**
  - "Move to primary" moves the window to the screen it is already on.
  - The "Move Uzume there" toast doesn't target the newly added screen.
  - `MultiDisplayToastBridge.swift:55` compares the removed screens with `currentScreen`, which `handleScreenChange` has already updated. So the "Moved to main display" path rarely fires.
- **Fix direction:** use `NSScreen.screens.first` and pass the added or removed `NSScreen` through.

### D9 — The capture hook re-requests the drawable after the render path got none
**P3 · VERIFIED · effort S**
- **Where:** `RenderPipeline.swift:847` calls `captureRenderedFrame` → `view.currentDrawable` on every frame. The hook is always installed (features.csv plus the dashboard).
- **Scenario:** MTKView caches only non-nil drawables. When `nextDrawable` times out, which takes 1 s, the hook immediately waits another second, so each frame costs about 2 s of main thread. A transient drawable stall becomes a beachball.
- **Fix direction:** skip the hook when the frame's render path didn't obtain a drawable, and back off after a nil.

### D10 — Synchronous GPU waits on the main thread at scene switch and resize
**P3 · VERIFIED · effort S**
- **Where:** `RenderPipeline+Staged.swift:232` `zeroTextures` → `waitUntilCompleted()`. It is called from `setStagedRuntime` (in `applyPreset`, on main) and from `drawableSizeWillChange`.
- **Scenario:**
  - It queues behind up to 3 in-flight frames. On a slow GPU at high resolution, that is a 100 ms+ hitch at every switch into a staged scene.
  - Every live-resize step or fullscreen animation reallocates about 10 full-size textures (feedback, post, G-buffer, mv_warp, staged).
- **Fix direction:** use clear load-actions on first use instead of a blocking clear, and debounce reallocation during live resize.

### D11 — Every user pays for developer-only video capture on the drawable
**P3 · VERIFIED · effort S**
- **Where:**
  - `MetalView.swift:37` `view.framebufferOnly = false` ("Required for the SessionRecorder's blit"). Video is off by default (`UZUME_RECORD_VIDEO`).
  - `MetalContext.makeSharedTexture` creates full-resolution feedback render targets in `.shared` storage.
- **Impact:** lost framebuffer compression and bandwidth on every frame for everyone, which matters most on M1 at Retina resolution.
- **Fix direction:** set `framebufferOnly = !videoRecordingEnabled`, and make render targets `.private` unless the CPU reads them.

---

## Reviewed and healthy
- **Drawable ownership:** every render path presents what it acquires. The capture hook blits inside the same command buffer and retains neither the drawable nor its texture (REC.1 uses a separate `VideoFrame`).
- **Command-buffer lifecycle:** `draw(in:)` always commits, including on skip frames, and the completion handler signals `inflightSemaphore` on every path, error path included.
- **Scene-swap skip** (`willRenderActiveFrame`): it commits an empty command buffer, and `applyPreset` is main-only (`dispatchPrecondition`).
- **Per-frame allocations:** no per-frame `MTLBuffer` or texture creation in the render loop. `halfResTarget` and ping-pong textures are cached; the staged probe reuses its scratch buffer.
- **Scheduling reads:** `FrameBudgetManager` rolling-window reads for ML dispatch are on the MainActor, so there is no cross-thread race.
- **Pipeline states:** cached by (name, format); the ray-march lighting pipelines are rebuilt per switch, but Metal's cache makes that cheap after first use.
- **GPU-error path:** a command buffer that fails with an error still signals completion, so a GPU fault cannot deadlock the semaphore. It is also not surfaced or recovered from (see Could not verify).
- **Preset hot-reload:** the watcher callback hops to main before `applyPreset`, so no precondition trap.
- **Window hidden or minimised:** the draw loop stops, per the refuted occlusion experiment in BUG-085. There is no wasted GPU work in that state.
- **Crash reports:** the six `Uzume-2026-09-2x.ips` on this Mac are all the objc_release / autorelease-pop signature, which is BUG-143 (test host). Nothing renderer-related.

## Could not verify
- **D4 real numbers:** an M1 or M1 Air at 2880×1864, or a 5K fullscreen run, with `RENDER_TARGET` plus `frame_gpu_ms`.
- **D1 on real hardware:** whether gating on `.apple7` renders Fractal Tree correctly needs an M1.
- **GPU fault or timeout on a heavy scene on a base M1 at 5K/6K:** no command-buffer error is surfaced or recovered from (`recordCompletion` only counts it). Proving the risk needs a live M1 plus 6K run.
- **Occluded but on-screen windows:** whether a visible-but-covered window keeps rendering at full cost (power) needs a live Instruments run.
- **Display changes:** behaviour when the display under a fullscreen window is unplugged, and moving between 1× and 2× or 60 and 120 Hz displays. The code path is benign, but it is untested live.
- **Aug-5 recorder halt:** whether the recorder halted at 22:43:58 (disk full). The unified log for that date has rolled off.

## Cross-lane pointers (not deduped; verify in the owning lane)
- **Stem WAV dumps (storage):** `SessionRecorder.recordStemSeparation` writes 4 × 16-bit WAVs, about 3.5 MB per live separation, into `~/Documents/uzume_sessions` for every streaming session by default. Separations run every `stemSeparationPeriodSeconds`, so that is tens of MB per minute, plus raw-tap audio. Retention defaults to the last 10 sessions.
- **Diagnosability:** Release unified logs redact preset names and paths as `<private>`, so tester sysdiagnoses won't show which scene was running.
- **Pre-main delay (distribution):** the 5.6 s spawn-to-first-log gap on first launch of the installed build.
