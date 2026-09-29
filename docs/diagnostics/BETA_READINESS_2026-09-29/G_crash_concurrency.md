# Lane G: crash-risk and concurrency sweep of production code

**Scope.** `UzumeApp/**` and `UzumeEngine/Sources/{Audio,DSP,ML,Orchestrator,Presets,Renderer,Session,Shared,ObjCShim}`. The work was read-only.

**Method.**
- Mechanical sweeps for every trap class in the brief.
- Three parallel deep reads, one each on `VisualizerEngine`, the Audio module and Renderer/Presets.
- I re-read every finding below against the code myself before including it.
- Grep counts were used only as leads.

**The headline.** The streaming track-change callback runs on a Swift concurrency thread, not the main thread. It then resets state that the render loop and the analysis queue own, without locks. That is the one P1.

---

## G1: Song changes on Spotify or Apple Music reset render-loop and analysis state from a background thread (heap-corruption crash)

**Severity:** P1 · **Confidence:** VERIFIED (code path, both sides traced); crash frequency not measured · **Effort:** M

**Where**
- `StreamingMetadata.startObserving()` is nonisolated, so `pollingTask = Task { … }` (`UzumeEngine/Sources/Audio/StreamingMetadata.swift:187`) runs on the cooperative pool.
- The poll calls `onTrackChange?(event)` at `:265`. The router relays it synchronously (`AudioInputRouter.swift:222-224`).
- The engine closure (`UzumeApp/VisualizerEngine+Capture.swift:242-258`) runs these inline on that thread:
  ```
  mir.reset()
  self.resetPerTrackPresetState()
  self.resetStemPipeline(for: identity, caller: .trackChange)
  ```

**Racing state, each with no lock on either side**
- **Render loop, on main.**
  - `WitchlightPath.reset()` → `beads.removeAll(keepingCapacity: true)` (`WitchlightPath.swift:251-252`). The class is documented "render loop only" (`:35-36`).
  - Meanwhile `draw(in:)` on main → `particles?.update` (`RenderPipeline+Draw.swift:137`) → bead `append` / `beads[index].age += dt` / `removeFirst(expired)` (`WitchlightPath+Events.swift:179-197`).
  - `MeniscusSurface.reset()` (`MeniscusSurface.swift:223-229`) races with its `stepWave` in the same way.
- **Analysis queue.**
  - `TonalAnalyzer.reset()` reassigns six arrays (`TonalAnalyzer.swift:244-247`; the class has no lock) while `tonalAnalyzer.process` mutates them element by element (`MIRPipeline.swift:247`).
  - `bandDeviationTracker.reset()` is called outside `MIRPipeline.lock` (`MIRPipeline.swift:515`), against `derive` at `:560`.
  - `moodAccumulator.reset()` (`VisualizerEngine+Stems.swift:629`) races with `moodAccumulator.update` (`VisualizerEngine+Audio.swift:477`).
- The comment at `+Stems.swift:631-632` says this code runs on "MainActor". It does not on this path.
- **Local-file path.**
  - The local-file advance runs `mirPipeline.reset()` and `resetStemPipeline` on main (`VisualizerEngine+LocalFilePlayback.swift:397-400`). Analysis blocks already queued by the playhead clock can still be running, so the analysis-queue half of this race applies there too.
  - Witchlight is safe on that path, because its reset and its render both run on main.

**Failure scenario**
- A tester plays a Spotify or Apple Music playlist and the song changes.
- If Witchlight or Meniscus (both certified) is on screen, or on any scene for the analysis-queue arrays, a reset can land mid-mutation. The result is an `Index out of range` trap, an `EXC_BAD_ACCESS` in `swift_release`, or silent heap corruption that crashes later somewhere unrelated.
- The odds on any one song change are low, but every streaming song change carries the risk.
- **Lead only, not proven.** The unreproduced "~3.6–3.7 min" crash/hang (KNOWN_ISSUES around line 2527, recorded on a Witchlight session) lands at about one song's length. It is worth checking whether those sessions were streaming and whether a song boundary fell at the stop.

**Fix direction**
- Route each reset to the thread that owns the state: geometry, preset and identity resets to main, and `mir.reset` / `moodAccumulator.reset` to `analysisQueue`. Alternatively, have `StreamingMetadata` deliver on main and hop only the analysis resets.
- Add a ThreadSanitizer run of a streaming track change.

**Also**
- The same off-main callback writes `lastResolvedTrackIdentity` (a String-heavy struct, `+Capture.swift:253`). It also reads `skeinState` / `nimbusState` / `lumenPatternEngine` while main's `applyPreset` rewrites them (`+Presets.swift:177-183`). These are narrower torn-reference risks of the same class.

**Dedupe:** not in KNOWN_ISSUES. BUG-142 fixed only the stop/poll generation race.

---

## G2: Three threads can start, stop and reinstall the system-audio tap at once, leaving an orphaned tap and doubled audio

**Severity:** P2 · **Confidence:** VERIFIED (interleavings traced); timing-dependent · **Effort:** M

**Where**
- `SystemAudioCapture` is driven from three places:
  - **main:** `router.start` / `stop`;
  - **`tapMgmtQueue`:** the silence-retry ladder, `stopCapture` + `startCapture` (`AudioInputRouter+SignalState.swift:158-163`);
  - **`reinstallQueue`:** the device-change reinstall (`SystemAudioCapture.swift:172-178` → `performReinstall` at `:341-367`).
- `performReinstall` checks `_isCapturing` once (`:342`) and never again.
- `createProcessTap` writes `tapUUID` without the lock (`:197`).
- Each create step overwrites `tapID` / `aggregateID` / `procID` without destroying a previous set (`:207`, `:230`, `:264`).

**Failure scenario**
- **(a) End Session during a device-change reinstall.**
  - Main's `cleanup()` claims nothing, because the fields are already zeroed.
  - The reinstall then creates and starts a tap that nothing owns. The router's mode is now nil, so `stopInternal` never stops it (`AudioInputRouter.swift:364-375`).
  - The next session's `startCapture` overwrites the handles, and the orphan leaks until the app quits.
- **(b) Two sequences create together.** On the Ready screen, silence retries fire at about 6, 16 and 46 s, before the first signal. If AirPods connect in that window, both sequences create at once.
- **What the tester sees:**
  - Two IO procs feed the same callback, so audio is analysed twice. The analysis clock runs about 2× and beat sync is wrong.
  - The single-thread scratch buffers are raced, which is a crash risk.
  - Capture keeps running after End Session.
- The closure properties `onCaptureDiagnostic` / `onAudioBuffer` are also rewritten on main while reinstall and IO threads read them (`:95`, `:236`).

**Fix direction:** one serial lifecycle queue for start, stop and reinstall, plus a generation token re-checked after each create step.

**Dedupe:** not in BUG-058 / 070 / 139.

---

## G3: Live analysis and background preparation share one StemAnalyzer and one MoodClassifier

**Severity:** P2 · **Confidence:** VERIFIED sharing and concurrency; visual magnitude PLAUSIBLE · **Effort:** S

**Where**
- One instance of each is passed to both the live pipeline and the preparer (`VisualizerEngine.swift:901,993,1009-1012` → `VisualizerEngine+InitHelpers.swift:313-314`).
- **Preparation** pumps about 1,300 frames of another song through `analyzer.analyze` (`SessionPreparer+Analysis.swift:251`) and `classifier.classify` (`:330`).
- **Live** calls the same instances: per-frame stems at about 94 Hz (`VisualizerEngine+Audio.swift:458`) and mood (`:322-331`).
- Preparation keeps running after Play (`SessionManager.swift:533-538`). Every song change also calls `stemAnalyzer.reset()` (`+Stems.swift:621`), which can land mid-preparation.
- Both classes are locked, so memory is safe. The AGC / EMA / deviation baselines / drum beat detector / mood EMA are shared state.

**Failure scenario**
- In a streaming session whose playlist is still preparing, stem- and mood-driven motion lurches each time another track is analysed. At 2× pacing on 30 s previews, that is roughly every 15 s.
- Stored stem balance and mood absorb live frames.
- The MoodClassifier half is BUG-144's "lead, not asserted". The StemAnalyzer half is unrecorded.

**Fix direction:** give the preparer its own StemAnalyzer and MoodClassifier. The local-file stem series already constructs a fresh one (`LocalFilePreparationPipeline.swift:231`).

---

## G4: Live stems never compute on 88.2 or 96 kHz output devices (outside lane, found by the capacity sweep)

**Severity:** P2 · **Confidence:** PLAUSIBLE (assumes the tap runs at the device rate, as `SignalHealthMonitor` does) · **Effort:** S

**Where**
- The ring holds 44.1k × 2 × 15 = 1,323,000 floats (`VisualizerEngine.swift:469-472`).
- The separator needs `Int(rate*10)*2` samples (`+Stems.swift:321-326`): 1,764,000 at 88.2 kHz and 1,920,000 at 96 kHz.
- `snapshotLatest` clamps to capacity (`StemSampleBuffer.swift:89-92`), so the run logs "warmup" forever.
- `UserFacingError.sampleRateMismatch` exists, but nothing in the app emits it.

**Failure scenario:** a tester whose DAC or interface is set to 96 kHz uses Spotify or Apple Music. Every stem-driven scene idles, with no warning shown.

**Fix direction:** size the buffer from the tap rate (or a 192 kHz worst case), or resample on write.

---

## G5: Volumetric Lithograph loses its half-resolution render after any resize (outside lane)

**Severity:** P2 · **Confidence:** VERIFIED allocation path; frame-rate impact PLAUSIBLE · **Effort:** S

**Where**
- The resize handler reallocates the ray-march G-buffer and the post chain at full drawable size (`RenderPipeline.swift:756-763`).
- The draw path sizes them only through `ensureAllocated(marchWidth…)` (`RenderPipeline+RayMarch.swift:172-175,197`). That call does nothing once the textures exist (`RayMarchPipeline.swift:335-338`).

**Failure scenario:** entering fullscreen, or moving to a 4K/5K display, while VL is playing makes it march 4× the pixels until the next scene. That is the BUG-101 frame-rate regime.

**Fix direction:** reallocate at march scale on resize, or have `ensureAllocated` compare sizes.

---

## G6: The tap sample rate is never validated, and a 0 or NaN rate traps

**Severity:** P3 · **Confidence:** trap VERIFIED; trigger PLAUSIBLE · **Effort:** S

**Where**
- `readTapFormat` accepts any `mSampleRate` (`SystemAudioCapture.swift:328-330`).
- `InputLevelMonitor.submitMagnitudes` computes `binWidth = nyquist/binCount` and then `Int(loHz / binWidth)` (`InputLevelMonitor.swift:215-220`). A rate of 0 gives `Int(+inf)`, which is a fatal trap. Every other DSP consumer guards `> 0`.
- `UInt32(sampleRate)` on the IO thread (`SessionRecorder+RawTap.swift:29`) traps on NaN.

**Fix direction:** reject a non-positive or non-finite rate at `readTapFormat` and fall back to 48 kHz.

---

## G7: Slow async results are applied to the song that follows

**Severity:** P3 · **Confidence:** VERIFIED code; timing-dependent · **Effort:** S

**Where**
- **Metadata prefetch.** `kickoffPreFetch` (`VisualizerEngine+Capture.swift:264-295`) has no track or generation check. Skipping A→B, where B hits the prefetch cache and A is still on the network, lands A's BPM / key / profile on B. `overrideBeatsPerBar` gives B A's meter.
- **Live beat grid.** Live Beat This! inference installs its grid on main unconditionally (`+Stems.swift:581-584`). A grid from the previous song's audio can replace the next song's prepared grid.

**Fix direction:** capture a track generation and drop results on mismatch.

---

## G8: A failed device-change reinstall stops the monitor, so the next device change cannot recover (= BUG-070, fix incomplete)

**Severity:** P3 · **Confidence:** VERIFIED · **Effort:** S

**Where**
- The PUB.6 comment (`SystemAudioCapture.swift:369-390`) says the monitor keeps running.
- In fact, failures in `createAggregateDevice` / `createIOProc` / `startDevice` call `cleanup()` (`:226,:260,:271`), which stops the monitor (`:534`).
- The retry ladder is also skipped once any audio has been heard (`AudioInputRouter+SignalState.swift:88`).

**Failure scenario:** an AirPods switch whose reinstall fails leaves the session silent. Only the stall card remains.

---

## G9: The hot-reload preset folder can crash the app on every launch

**Severity:** P3 · **Confidence:** VERIFIED; unusual input · **Effort:** S

**Where**
- `defaultDescriptor` builds JSON by string interpolation (`PresetLoader.swift:401-409`):
  ```
  {"name": "\(name)"}
  ```
  A `.metal` file in `~/Library/Application Support/Uzume/Presets` whose name contains `"` or `\`, and that has no valid sidecar, hits `fatalError`.
- This runs from `init` (`:203-205`), so the app crashes on every launch until the file is removed.
- Separately, the `presets` getter is unlocked (`:19`) while the watcher mutates and sorts the array on a global queue (`:347-362`). The analysis queue reads it (`+Orchestrator.swift:420,457`).

**Fix direction:** build the default descriptor without JSON, and read `presets` under the lock.

---

## G10: The Screen Recording poll loop stacks up and bypasses the local-file guard

**Severity:** P3 · **Confidence:** PLAUSIBLE · **Effort:** S

**Where**
- Every `startAudio()` made while permission is denied starts a new, uncancellable loop (`VisualizerEngine+PublicAPI.swift:110-122`).
- On grant, each loop calls `startAudioCapture()` → `router.start(.systemAudio)` → `stopInternal()`, skipping `startAudio()`'s local-file guard (`:71-75`).

**Failure scenario:** a tester denies Screen Recording, switches to local files, and grants the permission later. Local-file playback is torn down, provided preflight flips without a relaunch.

**Fix direction:** keep one stored task, cancel it at session end, and re-check the source before starting.

---

## G11: Spotify scan start/stop race can leave window capture running

**Severity:** P3 · **Confidence:** PLAUSIBLE; the window is small · **Effort:** S

**Where**
- If `stop()` lands between `self.stream = stream` and `startCapture()` finishing (`SpotifyScanServices.swift:176-178`), the stream starts with no owner.
- Frames are still converted to CGImage before the continuation check (`:186-187`), and the screen-recording indicator stays on until the app quits.

**Fix direction:** re-check ownership after `startCapture` returns and stop the stream if it has been orphaned.

---

## G12: The Spotify scan parser divides by a row height that can be zero

**Severity:** P3 · **Confidence:** PLAUSIBLE · **Effort:** S

**Where**
- `rowHeight` is the median gap between duration-cell centres (`PlaylistFrameParser.swift:159-163`), with no `> 0` guard.
- `numbered()` then does:
  ```
  Int(((slotY - top) / rowHeight).rounded())
  ```
  (`:351`).
- If half the duration cells share an identical `midY` (duplicate OCR boxes), the result is `Int(NaN)`, which crashes the app mid-scan. This has not been observed.

**Fix direction:** guard `rowHeight > ε`.

---

## Reviewed and healthy

- **Traps.**
  - Metal init `fatalError` (hardware).
  - Fixed-size FFT-setup and alloc `fatalError`s.
  - `PlannedTrack` non-empty `precondition`: the planner throws `emptyCatalog` first, and every patch path preserves segments.
  - `prepareLocalFiles` urls/placeholders: built in the same call.
  - `EnergyCurve`: the builder emits equal lengths, and `Codable` bypasses init.
  - Lumen palette tables.
  - `UMABuffer` bounds: callers clamp.
- **Force operations.** No `try!`, `as!`, `unowned` or implicitly-unwrapped optionals in scope, and no `assert` / `assertionFailure`. The `swiftlint:disable force_unwrapping` sites are Metal / MPS graph constants or non-empty buffers.
- **BUG-030 class.** The only `Dictionary(uniqueKeysWithValues:)` left is over one directory's filenames, which are unique.
- **Planner.** `sorted.first!` is guarded by the empty-catalog throw.
- **Float→Int.** Clean:
  - ETA, the BPM label, the transport clock and `barPhase01` (NaN clamps to 1);
  - BeatDetector tempo (≥4 timestamps, `fps > 0`);
  - every band-bin range (`count > 0` guards);
  - Fireflies `dt` (NaN-safe clamp);
  - pacing and rate-limiter sleeps;
  - `EnergyScale` slices (`first < last`).
- **Localized `String(format:)`.** All 26 keys' specifiers match their argument types.
- **Continuations.** `SpotifyOAuthTokenProvider` resumes once and coalesces correctly.
- **Main-thread assertions.** `MainActor.assumeIsolated` appears only in `queue: .main` observers and `group.notify(queue: .main)`. Every caller of the `dispatchPrecondition(.onQueue(.main))` sites traces to main: `applyPreset`, NowPlaying and CaptureState. Note that `dispatchPrecondition` is a `precondition`, so it traps in Release too; the `+Presets.swift:152-161` comment says "Debug".
- **Locks.** No NSLock is taken re-entrantly. `PersistentStemCache` evicts outside its lock. The BUG-139 claim-then-destroy pattern is intact. The in-flight semaphore signals on every path. Zero-size drawables clamp to 1. The probe `nonisolated(unsafe)` statics are all lock-guarded.

## Could not verify

- **G1/G2 frequency.** This needs a ThreadSanitizer streaming run with Witchlight active, or tester `.ips` files.
- **G6 trigger:** whether the HAL ever reports a tap rate of 0.
- **G4 premise:** whether a 96 kHz output device yields a 96 kHz tap.
- **Lead for BUG-081/085:** Core Audio create/teardown runs on main in `router.start`/`stop`, so a wedged coreaudiod would beachball the app.
- **Long local files.** A whole-file local-file decode has no length cap: a 1-hour file allocates about 1.3 GB transiently (`SessionTypes.swift:230-240`). Whether that trips memory pressure on 8 GB Airs is unmeasured.
