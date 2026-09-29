# Lane B — Audio capture, local-file playback, RT safety, device changes

Read-only review of `UzumeEngine/Sources/Audio/**`, the audio-facing DSP (`FFTProcessor`, `AudioBuffer`, `BandEnergyProcessor`, `StemSampleBuffer`), `UzumeApp/VisualizerEngine+Audio/+LocalFilePlayback/+Capture/+PublicAPI.swift`, and the session and stall wiring they depend on. Checked against KNOWN_ISSUES (index and entry bodies). Nothing was built or run.

## Findings (most severe first)

### B1 — Nothing stops the display sleeping or the Mac locking during a session
**P1 · VERIFIED (the code has no assertion; the macOS behaviour is standard)**
- **Where:** nothing in `UzumeApp/` or `UzumeEngine/Sources/` calls `IOPMAssertionCreateWithName`, `ProcessInfo.beginActivity`, `performActivity` or `.idleDisplaySleepDisabled`, and nothing imports IOKit. The session-state observer (`VisualizerEngine.swift:1113–1175`) is the natural place to add one.
- **Scenario:** A tester starts a session and watches without touching the keyboard or mouse. Playing audio and Metal rendering do not hold off display sleep. After the idle timeout (a few minutes on a laptop on battery, about 10 minutes on AC or a desktop by default), the screen goes black. If "require password after display off" is set, the Mac also locks. The music keeps playing. For a visualizer, this breaks the core use: leaving it running.
- **Fix:** Hold a `.idleDisplaySleepDisabled` activity (or a `PreventUserIdleDisplaySleep` assertion) from `.ready` through `.playing`, and release it on `.ended` and `.idle`. **Effort S.**

### B2 — The local-file track clock counts delivered audio instead of following the playhead
**P2 · VERIFIED**
- **Where:** On the local-file path, the clock the scenes use is `mir.elapsedSeconds += dt` (`MIRPipeline.swift:310`). The stem series reads it at `VisualizerEngine+Audio.swift:283` (`latestRawPlaybackSeconds = mir.elapsedSeconds`), and so do the energy curve (`RenderPipeline+Draw.swift:107`), the plan (`VisualizerEngine+Orchestrator.swift:392`) and the beat grid. Past the end of the song, both lookups hold their last value: `frames[min(idx, frames.count - 1)]` (`StemFeatureSeries.swift:66`) and `second < levels.count ? levels[second] : last` (`RenderPipeline+PresetSwitching.swift:308`).
- **Three events break it:**
  1. **A single file loops** (the provider re-arms at end of file; `onLocalFilePlaybackEnded = nil`). The clock never wraps. From the second play-through onward, the stems freeze on the song's last frame (usually the fade-out), the energy level locks at the ending's value, and the plan stops moving. The track bar hides this: it wraps for display only (`+LocalFilePlayback.swift:501`, `truncatingRemainder`).
  2. **Each pause adds up to 1.5 s.** The pause flush delivers `stallFlushSeconds = 1.5` of silent ticks (`PlayheadAnalysisClock.swift:63, 214–220`), each with a real `dt`, and nothing pulls the clock back on resume. BUG-130 records this only as grid phase that "the drift tracker recovers". The stem series and energy curve have no drift tracker, so after N pauses the stems lead the music by up to N × 1.5 s for the rest of the track. This undoes the "zero-lag stems" advantage of local files.
  3. **An output-device restart** (B3) sends the audio back to 0 while the clock keeps running, so stems, grid, plan and track bar are offset by the whole elapsed time.
- **Fix:** Drive the local-file track clock from the player's playhead. `PlayheadAnalysisClock` already computes it: wrap it modulo the file length and publish it instead of accumulating `dt`. **Effort M.**

### B3 — Changing the output device during local-file playback un-pauses and plays aloud; a failed restart is silent (extends BUG-056)
**P2 · VERIFIED in code; how often it triggers is PLAUSIBLE**
- **Where:** `LocalFilePlaybackProvider.swift:584–603`:
  ```
  self.lock.withLock { self.startSeconds = 0 }
  self.stop()
  do { try self.start() } catch { logger.error("[LF.1] Failed to restart engine …") }
  ```
  `start()` always ends in `player.play()` (`:383`), and nothing tells the app layer.
- **Scenario:** A tester pauses a local track, then puts their AirPods back in the case (or unplugs headphones, or an HDMI display sleeps). macOS switches output to the MacBook speakers. The engine's configuration-change handler restarts the track **from the top and starts playing out loud**, while the transport still shows "paused" (`isLocalFilePaused` stays true, which also turns off the stall detector). A Bluetooth headset switching into call mode, and plausibly sleep/wake, trigger the same path.
- **Failed restart:** If `start()` throws (for example, the new device is not ready yet), the error goes to `os_log` only. The session stays "playing" with no audio. After about 10 s the stall card appears with Screen Recording and `killall coreaudiod` advice, which is the wrong remedy for a local file.
- **Relation to BUG-056:** BUG-056 records only "restarts from the top". The un-pause, the lost paused state, the swallowed failure and B2's clock offset are new.
- **Fix:** Keep the paused state and resume position across the restart (the playhead is known). On failure, route through the existing `localFilePlaybackFailed` toast plus skip or end. **Effort S–M.**

### B4 — Opening a new local source while one is playing leaves the old audio running, even after Cancel
**P2 · VERIFIED**
- **Where:** `startLocalFiles` calls `cancel()` when replacing an active session (`SessionManager.swift:443–446`), and `cancel()` goes to `.idle` (`:573`). The engine observer stops the audio router only on `.ended` (`VisualizerEngine.swift:1149–1166`). ⌘O, Open Folder, drop and Recents are always enabled (`UzumeApp.swift:177–190`).
- **Scenario 1:** While song A plays, the tester presses ⌘O and picks B. A keeps playing through B's preparation. If they press **Cancel**, they land on the Idle screen with A still playing and no Stop control. A single-file A loops forever until they quit.
- **Scenario 2 (multi-file A):** When A's track ends during B's preparation, `advanceLocalFileQueue` reads the *new* `currentSource`. The track index was cleared, so the next index is 0, and it starts **B's first file mid-preparation** with a placeholder identity. The countdown then restarts it from the top.
- **Fix:** Stop the router and stem pipeline on `.idle`, as on `.ended` (or use end-session semantics when replacing). Gate the end-of-file advance on the session generation. **Effort S.**

### B5 — A tap that dies mid-session has no automatic recovery, and the stall card's first step guarantees that
**P2 · VERIFIED (code plus SDK header)**
- **Where:**
  - `DefaultOutputDeviceMonitor.swift:34–40` watches only `kAudioHardwarePropertyDefaultOutputDevice`. Nothing listens for `kAudioHardwarePropertyServiceRestarted`. `AudioHardware.h:573` says that after a restart "added listeners must be re-established by the client".
  - The router's recovery ladder runs off the IO callback (`SilenceDetector.update`) and is skipped once the session has had audio (`AudioInputRouter+SignalState.swift:88`).
  - The stall card's step 1 is `sudo killall coreaudiod` (`AudioStallOverlayView.swift:40–42`). Its hint says "clears itself as soon as audio comes back".
- **Scenario:** The card appears (a BUG-058 freeze, a dead tap from B6, and plausibly wake from sleep). The tester runs step 1. coreaudiod restarts, Uzume's tap, aggregate device and device listener are gone, and no callback arrives to drive any recovery. The card never clears; only ending the session and starting a new one works. Step 1 also needs `sudo` and can't be copied, because the card has `allowsHitTesting(false)`.
- **Fix:** Add an engine-side watchdog. When the frame count stops advancing while playing, or on `ServiceRestarted`, reinstall the tap and re-register the listener. Remove the Terminal step for the beta. **Effort M.**

### B6 — The Ready screen churns the tap reinstall BUG-057 removed (regression from DS.5)
**P2 · code VERIFIED; the dead-tap outcome PLAUSIBLE**
- **Where:**
  - DS.5 brings the tap up at `.ready` (`VisualizerEngine.swift:1147` → `startListeningForFirstAudio`).
  - With nothing playing yet, `hasEverDetectedSignal == false`, so the cold-install ladder (`reinstallDelays = [3, 10, 30]`, `AudioInputRouter.swift:85`) tears down and recreates a *working* tap at about 6 s, 16 s and 46 s into a normal Ready wait.
  - BUG-057's own diagnosis names this reinstall-of-a-working-tap as the "recreate lottery" that landed a dead tap (`16-59-43Z`, KNOWN_ISSUES_HISTORY §BUG-057 step 2).
- **Scenario:** A tester waits more than 6 s on Ready and a reinstall lands dead. They press play in Spotify and Ready never advances; the 90 s timeout's Retry does not reinstall the tap. "Begin now" leads to the stall card, and then to B5.
- **Fix:** Don't run the ladder while in `.ready` before any audio has played. Instead, reinstall on Retry or the timeout. **Effort S.**

### B7 — Bluetooth and AirPods output latency is not compensated
**P2 · VERIFIED that no device latency is read; the size of the lag is PLAUSIBLE**
- **Where:** `VisualizerEngine.swift:956` sets `audioOutputLatencyMs = 50.0` whatever the device. Nothing reads `kAudioDevicePropertyLatency` or `presentationLatency`. The only adjustment is a developer shortcut (`PlaybackView.swift:376–379`). `ENGINEERING_PLAN.md:7657` lists "AirPods / Bluetooth compensation" as a future phase; it is not tracked as a defect.
- **Scenario:** Both paths analyse audio before the device plays it: the tap captures before output, and the local-file clock reads `lastRenderTime`. On AirPods (typically 150–250 ms), every scene, including beat-locked accents, runs about 0.1–0.2 s ahead of what the tester hears. That will read as "not in sync" to a large share of testers.
- **Fix:** Query the output device's total latency (device plus stream plus safety offset plus buffer), set it on device change, and delay the render head, or at least the grid shift, by it. **Effort M.**

### B8 — Long local mixes are decoded whole into memory
**P2 · VERIFIED allocation size; the effect on the Mac is PLAUSIBLE**
- **Where:** `SessionTypes.swift:230–259`:
  ```
  AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)  // whole file
  samples = [Float](repeating: 0, count: actualFrames)              // + mono copy
  ```
  There is no duration cap anywhere on the local-file path.
- **Scenario:** A 2-hour DJ mix at 44.1 kHz peaks at about 3.8 GB just to decode (the stereo float buffer plus the mono copy), and a 3-hour set at about 5.7 GB, before whole-track Beat This!, the instrument analyser and the stem sweep. On an 8 GB M1 Air this means heavy swapping, a beachballing system, or the "out of application memory" dialog during preparation.
- **Fix:** Stream the decode in blocks: the hash is already mapped, and the stem sweep is already windowed. Or cap and warn above about 60 minutes. **Effort M.**

### B9 — Live analysis at 88.2/96/176.4/192 kHz starves the bass bands
**P2 · VERIFIED arithmetic; the felt impact is PLAUSIBLE**
- **Where:** `FFTProcessor.fftSize = 1024` at the native rate (`FFTProcessor.swift:35`). Band bins are computed as `floor(low/binRes)…ceil(high/binRes)` (`BandEnergyProcessor.swift:232–240`). BUG-146 moved *preparation* to 44.1 kHz; the live paths (the tap on a hi-res output device, or `PlayheadAnalysisClock` on a hi-res local file) still run at the native rate.
- **Effect:** At 96 kHz the window is 10.7 ms (shorter than one cycle of a 60 Hz kick) and "bass" has 3 bins. `subBass` is the DC bin alone at both 96 and 192 kHz; at 192 kHz "bass" has 2 bins. Bass is the primary driver in the audio data hierarchy.
- **Scenario:** An audiophile tester with a DAC set to 96 or 192 kHz, or with hi-res FLACs (about 2 % of the corpus), gets weak, jittery bass response. `sampleRateMismatch` is shown only in the debug overlay.
- **Fix:** Decimate to 44.1 or 48 kHz before the live FFT, as preparation already does. **Effort M.**

### B10 — Mono local files are analysed as if they were stereo
**P2 (narrow) · VERIFIED**
- **Where:**
  - `LoopingFileReader.swift:65` emits 1 channel for mono files.
  - `makeAudioSampleCallback` ignores `channels` for the FFT: `buf.latestSamples(into:)` then `fft.processStereo(interleaved:)` (`VisualizerEngine+Audio.swift:150–159`).
  - `processStereo` averages sample pairs as L/R (`FFTProcessor.swift:169–174`).
- **Effect:** Each FFT "frame" is two mono samples averaged, so the effective rate is half the file's rate while bins are labelled at the full rate. Every live band reads one octave high, and content above rate/4 aliases. Bass energy lands in "mid". The waveform texture is also misread. Mono FLACs exist in Matt's own corpus (Penny Lane, KNOWN_ISSUES:757).
- **Fix:** Upmix mono to stereo in `LoopingFileReader`, or pass `channels` to the FFT. **Effort S.**

### B11 — Every session records 30 s of whatever the Mac is playing to disk, while the permission prompt says "Nothing is recorded" (cross-lane: privacy)
**P2 · VERIFIED**
- **Where:**
  - `SessionRecorder()` is always constructed with `enabled` defaulting to true (`VisualizerEngine.swift:996`).
  - The IO callback calls `recordRawTapSamples` (`VisualizerEngine+Audio.swift:119`), which writes `raw_tap.wav` (30 s) plus `session.log` to `~/Documents/uzume_sessions/`, keeping the last 10 sessions by default.
  - `Info.plist:17` says: "Nothing is recorded or sent anywhere."
  - Separately, `~/uzume_diag.log` is created in the tester's home folder (`VisualizerEngine+Audio.swift:80`).
- **Scenario:** The global tap captures every app, so a tester on a FaceTime or Zoom call, or watching a video, while a streaming session starts gets that audio saved to Documents. Writing to ~/Documents may also trigger a TCC prompt for this non-sandboxed app.
- **Fix:** Turn raw-tap capture off by default for beta builds (or make it opt-in diagnostics), move logs to `~/Library/Application Support` or `Logs`, and align the prompt copy. **Effort S.**

### B12 — On macOS 14.0 and 14.1 the app launches but has no audio path
**P3 · VERIFIED**
- **Where:** `MACOSX_DEPLOYMENT_TARGET = 14.0` (`project.pbxproj:1252`), but the router exists only under `#available(macOS 14.2, *)` (`VisualizerEngine.swift:1077`).
- **Scenario:** On a local file, `handleLocalFileReady` bails with a log line only (`+LocalFilePlayback.swift:203–206`): the countdown reaches 0 and nothing happens, stuck at `.ready`. On streaming, Ready times out after 90 s.
- **Fix:** Raise the deployment target to 14.2 (or add a launch gate). **Effort S.**

### B13 — Real-time thread residuals not listed in BUG-036
**P3 · VERIFIED**
- **(a) Log line built on the audio thread.** `probeInstallRMS` → `onCaptureDiagnostic` → `SessionRecorder.log`, which constructs an `ISO8601DateFormatter()` plus a String and a `queue.async` **on the HAL IO thread** (`SystemAudioCapture.swift:529`; `SessionRecorder.swift:437`), about once a second for 10 s after every install.
- **(b) Priority-inversion window.** The IO callback takes about 8 NSLocks per buffer. One of them, `StemSampleBuffer.lock`, is held by the `.utility` stem queue while it allocates and zero-fills about 3.8 MB, copies it, and later runs an RMS over about 1 M samples (`StemSampleBuffer.swift:87–118, 128–156`) every separation cycle.
- **Impact:** Dropped tap buffers (analysis gaps) under load. Not audible.
- **Fix:** Pre-format off-thread or drop the probe; make the snapshot copy outside the lock (a double buffer). **Effort S.**

### B14 — Reinstall race leaks a running tap (= BUG-070 residual, with a consequence the entry doesn't state)
**P3 · PLAUSIBLE (narrow window)**
- **Where:** `performReinstall` runs on `reinstallQueue` while `stopCapture` and the ladder's `startCapture` run on main or `tapMgmtQueue`. `tapUUID` and `sampleRate` are unguarded (`SystemAudioCapture.swift:197, 329`).
- **Scenario:** A stop lands between `teardownTapResources()` and the re-create. The new tap then runs with `_isCapturing == false` and is never destroyed. It keeps feeding the analysis after End session, and the next session's tap double-feeds the same ring buffer, so visuals are garbled until the app quits.
- **Fix:** Serialize all install and teardown on one queue with a generation check. **Effort S–M.**

### B15 — Main-thread file I/O on the local-file path
**P3 · PLAUSIBLE**
- **Where:**
  - `expandFolder` walks the whole tree synchronously on the MainActor (`LocalFileMenuCommands.swift:216–238`) before truncating to 200.
  - Each track start opens `AVAudioFile` twice and starts the engine on main.
  - `PlayheadAnalysisClock.stop()` does `queue.sync {}` from main, which can wait on a 1 s block read.
- **Scenario:** Picking `~/Music` or a NAS share beachballs. A sleeping NAS stalls every track change.
- **Fix:** Enumerate off-main; open files off-main. **Effort S–M.**

### B16 — Local playback does not respond to media keys or AirPods controls
**P3 · VERIFIED (the absence)**
- **Where:** There is no `MPRemoteCommandCenter` or `MPNowPlayingInfoCenter` anywhere.
- **Scenario:** The play/pause key and AirPods taps don't pause Uzume's local playback. The key may instead start Music.app over it.
- **Fix:** Register remote commands for local sessions. **Effort S–M.**

### B17 — Capture failures never reach `session.log`
**P3 · VERIFIED**
- **Where:**
  - `startAudioCapture()` logs its thrown OSStatus to `os_log` only (`VisualizerEngine+PublicAPI.swift:126–135`).
  - `readTapFormat` failure silently assumes 48 kHz stereo (`SystemAudioCapture.swift:332–333`).
  - `deviceMonitor.start`'s `false` return is ignored (`:172`).
- **Impact:** A beta tester's shared session log can't explain a flatline.
- **Fix:** Log each to `sessionRecorder`. **Effort S.**

## BUG-091 (single local file, playback never starts)
No new root-cause candidate: the current start path logs, toasts and ends the session on every throw (`+LocalFilePlayback.swift:294–320`). Two observations for triage:
- The entry's "`createProcessTap` present, **twice**" is what one tap install plus the ladder's reinstall #1 would produce (never-had-audio → `.silent` → reinstall 3 s later). That fits the entry's candidate chain and does not point to a second cause.
- The only remaining *silent* local-file failure is B3's configuration-change restart. Its log signature is different: `provider.start INSTANCE` present, then a teardown, then nothing.

## Reviewed and healthy
- BUG-139 claim-then-destroy teardown: idempotent, and no CoreAudio call runs under `stateLock`.
- Aggregate device is private (`:216`): per the SDK it does not persist, so nothing is left in Audio MIDI Setup after quit or a crash.
- Local-file start and stop races (BUG-021/059/078/103): snapshot under the lock, AVFoundation teardown outside it, identity-checked re-arm, NSException catch.
- `PlayheadAnalysisClock.stop()` barrier (BUG-130/131): correct, and never called from its own queue.
- Zero-length, corrupt or unreadable files: preparation keeps a placeholder, playback toasts and skips. Queue index alignment holds (BUG-068).
- `.m4p` (DRM) is excluded by the extension allowlist. Files with more than 2 channels are downmixed. NaN/Inf input is sanitised at the FFT boundary.
- `SignalHealthMonitor.ingest` is real-time-safe. `StreamingMetadata` checks that the app is running before its AppleScript (no stray launches) and has the BUG-142 generation guard.
- Queue cap of 200 with an alert. The seek bar seeks on drag end only; seeking to the very end is safe.

## Could not verify
- **Same-device rate change** (AirPods entering call mode, or a DAC rate switch in Audio MIDI Setup, with no change of default device): the IO proc's rate is frozen at install (`let sr = self.sampleRate`, `:237`), and nothing listens for tap or device format changes. Whether the tap's delivered rate follows the device needs a live test.
- **Sleep/wake, fast user switching and screen lock:** no `NSWorkspace` sleep/wake observers exist anywhere. Whether the tap and aggregate survive wake, and whether the local-file engine posts a configuration change on wake (which would trigger B3's un-pause), needs a live test.
- **Process-tap lifetime after a crash:** `CATapDescription.privateTap` is never set. Worth setting regardless.
- **Analysis-queue backlog:** there is no backpressure on the per-callback `analysisQueue.async`. Whether a slow 8 GB Mac at high callback rates falls progressively behind needs a timing capture.
