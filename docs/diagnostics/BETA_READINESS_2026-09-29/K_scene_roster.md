# Lane K: scene roster as a beta tester sees it

Read-only review of `main@efb3eed3`. Nothing was built or run. Every claim below comes from reading the code path or the named doc.

## Roster at a glance (Q1)

- **Loaded:** 32 scenes compiled from `Presets/Shaders/*.metal`.
- **Certified:** 27. Every sidecar `certified: true` matches `FidelityRubricTests.certifiedPresets`, and a gate enforces that.
- **Auto-rotation by default:** 26. **Volumetric Lithograph (VL) never gets picked** (see K5).
  - Kagura and Membrane (`requires_regular_beat`) drop out on beat-irregular tracks (D-154).
  - The planner's hard gates live in `PresetScorer.exclusionReasonAndTag`: diagnostic, uncertified, blocklist, budget, and beat-irregular.
- **Not in the product but loaded:**
  - Spectral Cartograph (diagnostic).
  - FFT Sandbox, Poisson Sandbox and Staged Sandbox (diagnostic plus `exclude_from_cycling`).
  - Waveform (uncertified).
- **Default and fallback: Waveform.** It is installed at engine init (`VisualizerEngine.swift:938`). `cheapestFallback` also lands on it (0.4/0.2 ms, the cheapest non-diagnostic scene). This matches D-253.
- **Release reachability of uncertified or diagnostic scenes:** yes, through Shift+←/→ (K3) and the Settings toggle "Show uncertified scenes". There is no scene picker UI. ⌘[/⌘] is `#if DEBUG` only.

---

## Findings (most severe first)

### K1: On M1-family Macs, Fractal Tree shows a full-screen pulsing colour field instead of a tree, and that image has never been flash-tested
- **Severity:** P1
- **Confidence:** VERIFIED for the render path. PLAUSIBLE for the flash rate.
- **Where:**
  - `PresetLoader+Mesh.swift:50` `if device.supportsFamily(.apple8) {` … `else { compileMeshPipelineFallback(...)`
  - `MeshGenerator.swift:249` `usesMeshShaderPath = device.supportsFamily(.apple8)` → `drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)`
  - `FractalTree.metal:1297` `fractal_tree_fallback_vertex` (a full-screen triangle, `depth_norm = 0.5`)
- **What happens:**
  - M1, M1 Pro, M1 Max and M1 Ultra are Apple7 GPUs. M2 and later are Apple8. So every M1 tester gets the fallback. That includes the 8 GB M1 Air, which is in the beta hardware range.
  - The fragment shader then fills about 88 % of the screen with one blue-violet colour. It has a dark band at the bottom and no branches.
  - Its brightness follows `bass_dev` and `arousal`, and jumps by `spectral_level_rise × 0.55 × 0.5` whenever a sound lands (`val += spark * 0.55`). My estimate is that frame luminance goes from about 0.06 to about 0.3 on each onset, over the whole frame. That is exactly the global flash D-157 and FTR.3 removed from the real tree.
- **Why nobody caught it:**
  - Matt's M2 Pro is Apple8, so he has never seen the fallback. The comments saying "M3+" and "M1/M2 fallback" are wrong, as `RENDER_CAPABILITY_REGISTRY.md:47` already notes.
  - The planner has no mesh-capability gate, so Fractal Tree (certified, 1.2 ms on tier 1) is scheduled on M1 like any other scene.
  - No flash test covers Fractal Tree on either path (K4).
- **Failure scenario:** An M1 Air tester plays a busy track. The "Fractal Tree" banner appears over a flat field that brightens on every onset, potentially at 2–4 Hz across the whole screen.
- **Fix direction:**
  - Fastest: exclude `mesh_shader` scenes from planning and from Shift+→ when the native mesh path is unavailable.
  - Better: check whether Apple7 supports mesh shading. Apple's feature tables list Apple7+. If it does, gate on `.apple7`.
- **Effort:** S

### K2: Nothing has measured tester-class hardware, and the frame-budget system can't protect a base M1 or a high-resolution display
- **Severity:** P1
- **Confidence:** PLAUSIBLE. The mechanism is verified; the frame rates are extrapolated.
- **The cost numbers are all from one machine:**
  - Every `complexity_cost` figure, every frame-budget baseline and every live `frame_gpu_ms` in the docs comes from Matt's M2 Pro Mac mini. A search for M1, MacBook Air, 8 GB or 7-core measurements finds nothing.
  - `detectDeviceTier` (`VisualizerEngine+InitHelpers.swift:378`) returns tier 2 only for names containing "m3" or "m4". Everything else is tier 1, including M5 and an M1 with a 7-core GPU.
  - Both tiers use the same 16.6 ms gate, which has no resolution term (`QualityCeiling.swift:36`).
  - The drawable is the full backing store (`MetalView.swift`: no size cap). That is roughly 4.6–5.2 MP on an Air's built-in display at full screen, 14.7 MP on a 5K Studio Display, and 20.4 MP on a 6K display.
- **The runtime governor almost never helps:**
  - `applyQualityLevel` (`RenderPipeline+BudgetGovernor.swift:20`) has four rungs: bloom off, ray-march steps ×0.75, particles ×0.5, and mesh ×0.5.
  - **The particles rung does nothing.** All 12 `ParticleGeometry` conformers declare `activeParticleFraction` and none of them ever reads it. `AlfvenSolver.swift:43` even says "accepted and ignored — the lever here is `substeps`", and nothing sets `substeps`.
  - So the governor changes only Ferrofluid Ocean, Lumen Mosaic, VL and Fractal Tree (mesh rung, M2+ only). For 23 of 27 certified scenes, including every mv_warp, direct, feedback and particle scene, a heavy frame just drops frames.
  - The governor never lowers resolution, never switches scene, and never tells the planner.
- **Evidence on the M2 Pro itself:**
  - **Alfvén:** its sidecar claims 2.2 ms, but live GPU time at certification was p50 9.99 ms and p95 14.83 ms (ENGINEERING_PLAN ALFVEN.CERT). Its solver cost does not depend on resolution.
  - **Median scene at 4K:** 11.4 ms with readback off (BUG-099 history).
  - **Cheap scenes at 4K on 2026-08-19:** Witchlight delivered 49 fps and Stave 51 fps, even though their GPU times were only 6.4 and 2.9 ms (PERF.10).
- **Extrapolation to tester hardware:**
  - A base M1 with a 7/8-core GPU has about 1/2.5 to 1/3 of an M2 Pro's GPU throughput and bandwidth.
  - Alfvén would run at about 25–30 ms, so under 60 fps even at 1080p.
  - The median scene at full screen on an Air would take about 18–21 ms.
  - On a 5K display, the median scene would take about 20 ms even on an M2 Pro.
  - A fanless Air will also throttle during long sessions.
  - VL's 0.4 minimum scale lets it exceed its own 1536×864 march budget at 5K (1.8×) and 6K (2.5×).
  - Nimbus is hard-coded to 0.5 scale (`VisualizerEngine+Presets.swift:834`) and is not covered by the frame-budget harness.
- **Failure scenario:** A tester on an 8 GB M1 Air at full screen, or on any Mac driving a Studio Display, sees much of the roster run at 30–50 fps. Stem separation competes for the same GPU on the streaming path.
- **Fix direction:**
  - Before Oct 15, run one session on a base M1 and one at 5K, reading `RENDER_TARGET` and `frame_gpu_ms`.
  - Add a global megapixel cap: render fragment-bound paths at no more than about 1440p-equivalent and upscale.
  - Either implement the particle rung or delete it.
  - Correct Alfvén's declared cost, or exclude it on tier 1.
- **Effort:** M

### K3: The help-listed "Cut to next preset immediately" reaches all 32 loaded scenes, including three test patterns, a diagnostic readout and Waveform
- **Severity:** P2
- **Confidence:** VERIFIED
- **Where:**
  - `PlaybackShortcutRegistry.swift:298–311` binds Shift+→/← to `presetNudge(..., immediate: true)`.
  - `DefaultPlaybackActionRouter.reactiveWalkNudge` sorts the whole catalog alphabetically with no filter: `let eligible = catalog.sorted { $0.name < $1.name }`.
  - `getCatalog` is `engine?.presetLoader.presets.map(\.descriptor)`.
  - `applyPresetByID` shows the scene's name banner.
- **What a tester lands on:** FFT Sandbox (right after Dragon Bloom), Poisson Sandbox, Spectral Cartograph, Staged Sandbox and Waveform, with their names on screen.
- **Why it's inconsistent:**
  - Matt's PR.0 call was to hide Staged Sandbox. That call was implemented only in `PresetLoader.cyclableIndex`, which only the DEBUG ⌘] path uses.
  - The comment on the walk ("must reach anything loaded — diagnostics … included") reflects Matt's dev-navigation request, not a beta decision.
- **Also reachable:**
  - Settings → "Show uncertified scenes" is not DEBUG-gated. Today it only adds Waveform to planning, despite its "work-in-progress scenes" copy.
  - The user-preset folder `~/Library/Application Support/Uzume/Presets` is watched in Release. A deliberate drop-in whose sidecar says `certified: true` would enter rotation with no gates. That needs deliberate action, so it's low risk.
- **Failure scenario:** A tester presses Shift+→ to skip a scene and gets a grey test pattern labelled "FFT Sandbox". They report a broken scene.
- **Fix direction:** In Release builds, filter the walk to `!isDiagnostic && !excludeFromCycling`, and possibly `certified` too. Gate the uncertified toggle behind a build flag.
- **Effort:** S

### K4: The photosensitivity gate's "27/27 certified measured" claim is wrong for 5 scenes
- **Severity:** P2
- **Confidence:** VERIFIED
- **Where:** `PhotosensitivityCertificationTests.swift:124` `guard !preset.descriptor.passes.contains(.meshShader) else { return }`, plus the list of tests in `MultiPassFlashHarnessTests.swift`.
- **Fractal Tree:**
  - It is skipped by the single-pass gate, is not in `multiPassMeasured`, and has no multi-pass test.
  - It has never had a flashes-per-second measurement. The harness can drive it (PERF.7). The only related check is FTR.25's single-frame "frame lift < 1.25" on the mesh path.
  - The M1 path (K1) cannot be measured on Matt's machine at all.
- **Ferrofluid Ocean:**
  - It has no `fragment_function`, so `pipelineState` is the G-buffer pipeline (`PresetLoader.swift:697–699`).
  - The single-pass gate therefore measures `gbuf0 = (depthNorm, matID, 0, 0)`, which is surface height, not light. Its aurora sky, specular spikes, bloom and particles are unmeasured.
  - This is the scene whose track-start flashing produced BUG-041. The faithful measurement, `FerrofluidFlashForensicsTests`, is env-gated and "diagnostic, not a gate".
- **Murmuration:** only its backdrop fragment is measured. The 14K birds are drawn by particle geometry the single-pass harness never runs.
- **Gossamer and Membrane:** measured without their mv_warp or feedback accumulation. Gossamer's own shader notes that feedback gives about 22× gain on held content, and its wave pool (slot 6) is zeroed.
- **Waveform** (launch default and fallback) is uncertified and never flash-tested. It draws unsmoothed raw-FFT bars (`×10`, saturated).
- **Failure scenario:** The team tells testers "every scene is flash-tested" when two scenes with global luminance motion have no valid measurement.
- **Fix direction:** Add Fractal Tree and Ferrofluid Ocean to `MultiPassFlashHarnessTests`. The multi-pass harness already handles ray-march for Lumen Mosaic and VL, and mesh for Fractal Tree. Also add a guard that fails if `pipelineState` is the G-buffer state.
- **Effort:** M

### K5: Volumetric Lithograph is certified but no tester will ever see it at default settings
- **Severity:** P2
- **Confidence:** VERIFIED
- **Where:**
  - `VolumetricLithograph.json` declares `"complexity_cost": {"tier1": 24.0, "tier2": 18.0}`.
  - `QualityCeiling.complexityThresholdMs` sets `.auto` (the default in `SettingsStore:121`) to `tier.frameBudgetMs` = 16.6 ms on both tiers.
- **Why it's excluded:** 24 ms and 18 ms both exceed 16.6 ms, so VL is `budget_exceeded` on M1 through M4 alike.
- **Status in the plan:** ENGINEERING_PLAN:399 says VL is excluded "on tier 1 … it may simply not be appearing". It is actually excluded on tier 2 as well.
- **Why the numbers are misleading:** the 18 ms tier-2 figure is an M2 Pro measurement copied over. VL now runs capped at about 56 fps at 4K on that machine.
- **Failure scenario:** The roster is announced as 27 scenes and testers see 26. VL appears only via Ultra quality or Shift+→.
- **Fix direction:** Product call for Matt. Either re-measure VL's cost at its capped scale and correct the sidecar, or intentionally ship it tier-2 only and count the roster as 26.
- **Effort:** S

### K6: On streaming (most testers), the newest scenes lose musical behaviour that was only validated on local files
- **Severity:** P2
- **Confidence:** VERIFIED for (a). PLAUSIBLE for the visual impact of (c).
- **(a) Energy curve collapses to one number:**
  - `EnergyScale.energyLevelsPerSecond` (`EnergyScale.swift:180`) returns a single "typical" preview level for the whole track when the curve does not cover it. That is always the case on streaming, which only analyses the 30 s preview.
  - Fireflies' "a quiet stretch shows about a tenth of the fireflies … fills as the song builds" therefore never happens on streaming.
  - Kagura's energy-section dance choice (KAG.5) sees one level.
  - Kagura's streaming pass was on the KAG.3 build, before Charleston and ballet existed. Fireflies' streaming pass found it "does not lock to the beat". The slate's "one streaming pass per scene" rule only started on 2026-09-24.
- **(b) The beat grid comes from the preview only.** This is the same as BUG-065 and BUG-107; it is not new.
- **(c) Stem data is late and spikes at every track start:**
  - Stems are 2.5 s late, zero until the first separation lands, and then overshoot by 1.2–3.3× for about 10 s (AUDIO_CONTRACT §3).
  - The track-start warmup gate exists only for Ferrofluid Ocean's aurora (`RenderPipeline+AudioDrivers.swift`).
  - BUG-084's "no product impact" considered only Ferrofluid Ocean. Eleven other certified scenes route `*EnergyDev` stems without that gate: Glaze, Dragon Bloom, Fata Morgana, Cymatic Resonance, Filigree, Mitosis, Cytokinesis, Skein, Nimbus, Gossamer and Lumen Mosaic.
- **Failure scenario:** A Spotify tester sees the meadow at constant density from a quiet intro through the drop, and stem-driven accents that land about a bar late and overreact for the first 10 s of every song.
- **Fix direction:** Run a streaming M7 pass on the top 10 scenes before the beta. Treat the energy curve as absent on streaming, falling back to live `spectral_level_rise` the way the Goldengrove plan describes. Extend the BUG-041 warmup to the stem routes as a whole.
- **Effort:** M

### K7: The app has no attribution screen, and its About section says "MIT License" for everything
- **Severity:** P2
- **Confidence:** VERIFIED
- **Where:**
  - `Localizable.strings:363` reads `"MIT License. © 2026 Uzume contributors."`
  - There is no Credits.rtf, acknowledgements view or CREDITS surface in the app.
  - `docs/CREDITS.md` obligation #2 says to make it "reachable from a user-visible surface — e.g. an About panel". That obligation is unmet.
- **What that leaves unattributed:**
  - `AuroraVeil.metal` is CC BY-NC-SA 3.0. Its header carries the notice, and the source ships inside the bundle.
  - PANNs weights (CC-BY-4.0), Beat This! and Open-Unmix (MIT), CMU mocap, and the Milkdrop authors all get no in-app credit. The CMU credit exists only inside `kagura_clips.json`.
- **Smaller gaps:**
  - The CREDITS Milkdrop table says "Eight scenes" but lists seven. It omits **Stave** ("Martin – charisma", declared in its `inspired_by` block), and still calls Meniscus uncertified.
  - D-252 requires a named clean-room replacement for Aurora Veil. None is named.
  - The root `LICENSE` has no exception listing the non-MIT file.
- **Failure scenario:** A public binary ships a CC BY-NC-SA work while its only licence statement says MIT, with no author credit.
- **Fix direction:** Add an "Acknowledgements" section under Settings → About that renders CREDITS. Fix the licence line. Add Stave to the table and name Aurora Veil's replacement.
- **Effort:** S

### K8: Cytokinesis's "hangs for seconds before restart" is probably its designed 4-second hold, which will read as a freeze
- **Severity:** P3
- **Confidence:** PLAUSIBLE
- **Where:**
  - `MitosisGen2Geometry.swift:220` `if stage == .growing { cells[i].phase += ... }`
  - `holdSeconds: Float = 4`, followed by a 5 s dissolve and a re-seed.
- **What happens:** In `.holding`, cell phases freeze and the radius and packing have already converged, so the structure stops moving for about 4 s. This matches Matt's report (PR.4: "no repro … max frame gap 199 ms"). It is not a render hang, and it is not filed in KNOWN_ISSUES.
- **Failure scenario:** A tester watching Cytokinesis reports that the app froze.
- **Fix direction:** Keep the cells cycling or breathing during the hold, then file it and close PR.4's hang half.
- **Effort:** S

### K9: No automated check that any scene is visible at silence, and the rubric's silence item always passes
- **Severity:** P3
- **Confidence:** VERIFIED
- **Where:**
  - `PresetCertificationStore.swift:114–115`: `// assume the 5.2 acceptance gate already enforces non-black output at silence` / `RuntimeCheckResults(silenceNonBlack: true)`
  - `PresetAcceptanceTests.swift:8–11` explains it deliberately uses steady energy, not silence.
- **Known dark-at-silence cases:**
  - Ferrofluid Ocean blacked out after about 3 s of near-silence (= OBS-DS6-1).
  - Alfvén's silence state has never been observed live (ALFVEN.CERT).
  - The "Listening…" pill mitigates this for true silence.
- **Fix direction:** Add a per-scene luminance floor test at `near_silent01 = 1`, and remove the hard-coded `true`.
- **Effort:** S

---

## Reviewed and healthy
- **Certified-flag integrity:** the sidecars and `certifiedPresets` agree (27), and a gate enforces it. The fallback pools keep the categorical exclusions (CLEAN.3.2).
- **Debug-only navigation:** ⌘[/⌘] is `#if DEBUG`. The preset-completion cycle is unreachable (`activePresetSignaling()` returns nil).
- **Compile failures:**
  - A shader that fails to compile leaves the scene absent from the catalog, so the planner never schedules it. There is no black screen.
  - The diagnostics are `.public` and the source is dumped to disk.
  - MSL 3.1 matches the macOS 14 floor.
  - No ray tracing or Apple9-only features are used. Mesh shading is the only family-gated feature.
- **Runtime failures:** subsystem failures in `applyPreset` log and degrade (no bloom, placeholder, static) rather than crash.
- **Flash testing:** 20 scenes are measured through their real multi-pass paths at 0–1 flashes/s. A first-run photosensitivity notice exists. D-157 steady-luminance discipline is visible in the Fireflies and Kagura tests.
- **Dragon Bloom:** BUG-122 (white-out) is fixed. BUG-123 is a paler tone, not a flash risk. The scene is multi-pass flash-measured.
- **Licences and bundled assets:**
  - Only one NC-SA port exists, well inside the cap of about three.
  - All 8 Milkdrop-inspired sidecars carry `inspired_by`, and those sidecars are bundled. No `.milk` file ships.
  - No reference art is bundled: Presets ships `Shaders/` only; Renderer ships a fonts README and the Kagura clips.
- **Frame pacing:** MTKView runs at its default 60 fps, so ProMotion displays don't double the load.

## Dedupe notes (known, not re-reported)
- OBS-DS6-1: Ferrofluid Ocean blackout.
- BUG-065 and BUG-107: streaming grid drift and tempo.
- BUG-060: hang after switching to Gossamer, still open.
- BUG-123: Dragon Bloom tone.
- BUG-084 and BUG-041: stem-deviation overshoot. K6 extends their scope.
- The ENGINEERING_PLAN VL tier-1 note. K5 corrects it to both tiers.

## Could not verify
- Real fps on a base M1 or M2 (8 GB), on 5K and 6K panels, and after thermal throttling on a fanless Air. This needs one `RENDER_TARGET`/`frame_gpu_ms` session per device.
- Whether Apple7 (M1) can take the native mesh path.
- The actual flash rate of the Fractal Tree fallback and of Ferrofluid Ocean's lit image.
- Launch cost: all 32 scenes, each prefixed with about 5k lines of utility MSL, compile synchronously on the main actor in `VisualizerEngine.init`. First-launch time on a cold 8 GB M1 is unmeasured, and it overlaps lanes F and H.
- Live stem separation's GPU duty on a base M1. It is about 70 % on the M2 Pro per the PERF notes; this is the ML lane's area.
- Whether any scene fails to compile under the macOS 26 Metal compiler or on Apple7. No test runs on either.
- The visual size of the streaming stem overshoot on the 11 ungated scenes.
