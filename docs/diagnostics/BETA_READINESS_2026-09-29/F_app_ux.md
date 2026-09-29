# Lane F — App-layer UX (flows, states, errors, copy, a11y, settings, windows)

Read-only review of `UzumeApp/**` against `docs/UX_SPEC.md`, deduped against KNOWN_ISSUES §Open Index. Every finding below was traced in code; "PLAUSIBLE" marks the one link I could not run.

## Findings (most severe first)

### F1 — Reduce Motion is never applied at launch; "Dim flashing lights" is ignored · P1 · VERIFIED
- **Where:** `UzumeApp/UzumeApp.swift:97-102` is the only caller of `engine.applyAccessibility`, and it is `.onChange(of: accessibilityState.reduceMotion) { _, reduce in … }` (fires on change only). `RenderPipeline.swift:546/548` default to `beatAmplitudeScale = 1.0`, `frameReduceMotion = false`. `AccessibilityState.swift:62-65` seeds `reduceMotion` from the system flag at init, so no change ever fires. `applyPreference(.matchSystem)` early-returns (line 83).
- **Failure:** A tester follows the photosensitivity notice and turns on macOS Reduce Motion. It works for that run, because the change notification fires. On every later launch the UI believes Reduce Motion is on (the chrome crossfades), but the visuals run full feedback trails and full beat amplitude. The same happens with in-app "Always on" when the system flag is also on. `MADimFlashingLightsEnabled` (macOS "Dim flashing lights") is read nowhere.
- **Fix:** Push the effective state into the engine at startup (`.onChange(…, initial: true)` or in engine init). Also honour Dim flashing lights. **Effort:** S

### F2 — Session recording is always on, the Off switch does nothing, and the copy says nothing is recorded · P1 (arguably P0 for a public beta) · VERIFIED (disk rate PLAUSIBLE)
- **Where:** `SettingsStore.swift:87` `sessionRecorderEnabled` has no consumer outside the Settings files. `VisualizerEngine.swift:996` calls `SessionRecorder()`, whose `enabled` defaults to true. `VisualizerEngine+Stems.swift:372` calls `recordStemSeparation` on every live separation (every 2 s over a 10 s chunk). `SessionRecorder+RawTap` writes the first 30 s of raw system audio. The copy contradicts this: the permission screen says *"It doesn't record your screen, your microphone, or anything else. Nothing ever leaves your Mac."*, and `Info.plist:17` says *"Nothing is recorded or sent anywhere."*
- **Failure:** In any streaming or "Start listening now" session, `~/Documents/uzume_sessions/<launch>/` collects the following:
  - four 10 s WAVs every ~2 s of non-silent audio (≈3.5 MB each time, on the order of GB per hour);
  - `raw_tap.wav`, which holds whatever the Mac played, calls included;
  - CSVs;
  - `session.log`, which includes track titles.

  Turning "Record sessions to disk" off changes nothing. Pruning runs only at the next launch. The first write can trigger macOS's "access your Documents folder" prompt mid-flow. If Documents syncs to iCloud, all of this uploads. Track titles and artists are also sent to itunes.apple.com and musicbrainz.org, so "Nothing ever leaves your Mac" is false as written.
- **Fix:** Honour the toggle (pass the stored value to `SessionRecorder(enabled:)`). Default it off for the beta, or at least stop the stem-WAV dumps in Release. Move output out of `~/Documents`. Rewrite both privacy lines. **Effort:** S–M

### F3 — The audio-stall card tells non-developers to run `sudo` in Terminal, and it fires in a normal situation · P1 · VERIFIED (extends BUG-055)
- **Where:** `AudioStallOverlayView.swift:7-8` carries the note *"Copy is developer-facing for now … soften before any public build."*
  - Step 1 renders `sudo killall coreaudiod` (line 42).
  - Step 2 says *"If you just rebuilt Uzume…"*.
  - `.allowsHitTesting(false)` (line 56) means the command cannot be selected or copied.

  In `PlaybackErrorBridge.swift:341-349`, pause-suppression requires `hasEverDetectedSignal`; without it, 10 silent 1 Hz ticks raise the card.
- **Failure:** A first-time tester clicks "Start listening now" (or "Begin now" on Ready) and goes off to open Spotify. About 10 s later a centred card says Uzume isn't hearing audio and to paste a sudo command into Terminal. BUG-055 covers the card's existence, not this false trigger or the unsoftened copy.
- **Fix:** Before first audio, show only the "Listening…" badge. Replace the Terminal step with a relaunch or self-heal action. **Effort:** S

### F4 — ⌘F, Esc-to-exit-fullscreen, ⌘⇧F and display handling are dead in the usual streaming session · P2 · VERIFIED in code, PLAUSIBLE at runtime
- **Where:** `PlaybackView.swift:233`: `if let window = NSApp.keyWindow { fullscreenObserver.attach(to: window); … DisplayManager … }` runs once, in `onAppear`, and is never retried.
- **Failure:** Ready says "Press play in Spotify". The tester clicks play in Spotify, which makes Spotify the active app. Uzume auto-advances to `.playing` while inactive, so `keyWindow` is nil and nothing gets attached.
  - Back in Uzume, ⌘F and ⌘⇧F do nothing.
  - After entering fullscreen with the green button, Esc shows "End this session?" instead of leaving fullscreen.
  - Display-disconnect relocation and its toast are never wired.
- **Fix:** Resolve the hosting window from the view (a window accessor), or attach on `didBecomeKey`. **Effort:** S

### F5 — Three Visuals settings do nothing · P2 · VERIFIED
- **Where:** `PresetScoringContextProvider` is the only builder that passes `excludedFamilies`, `qualityCeiling` and the tier override, and it is constructed only in tests (`UzumeAppTests/…ProviderTests`). Production contexts are built without those fields (`VisualizerEngine+Orchestrator.swift:562-574`, `SessionPlanner+Segments.swift:204-212`). Separately, `SettingsStore` stores `qualityCeiling` as JSON `Data`, but `VisualizerEngine.swift:1045-1048` reads it with `UserDefaults.string(forKey:)`, which is always nil, so even "Ultra" never applies.
- **Failure:** A tester hides the "Particles" family and still gets particle scenes. Choosing Performance or picking a device tier on an 8 GB Air has no effect. This breaks the UX rule that tooltips describe what a control does *now*.
- **Fix:** Wire the provider into the planner, live adaptation and reactive paths, or hide these controls for the beta. **Effort:** S–M

### F6 — Settings can only be opened mid-performance, so the photosensitivity advice can't be followed in the app · P2 · VERIFIED
- **Where:** The only presenter is `PlaybackView.swift:212-214`. There is no `Settings {}` scene or app-settings command, so ⌘, is absent. The gear on IdleView that §4.1 specifies is missing. In `PhotosensitivityNoticeView.swift:35-38`, "Enable Reduce motion" opens System Settings, whereas §3.3 says the button "flips the setting".
- **Failure:** A photosensitive tester reads "enable Reduce motion in Settings before starting". They can only change the system-wide flag, which Uzume then ignores on the next launch (F1). Copy debug info and the recorder toggle are also unreachable until a session is already playing.
- **Fix:** Add a Settings scene (⌘,) and the Idle gear. Make the notice's button set the in-app Reduced motion to Always on. **Effort:** S

### F7 — The photosensitivity notice is skipped when the first session starts from a local file · P2 · VERIFIED
- **Where:** `IdleView.swift:67-77` is the only place the notice is shown. `ContentView.swift:47-48` bypasses the gate, and IdleView, for local-file sources. The local-file entry points are `.onOpenURL` (`UzumeApp.swift:113-123`), window drop (158-164) and ⌘O (177-191).
- **Failure:** A new tester declines Screen Recording and uses File › Open Local File… from the permission screen, or Finder's "Open With › Uzume", or drops a folder on the window. The flow goes preparing → 3-2-1 → flashing visuals, with no warning.
- **Fix:** Require the acknowledgement before any playback starts, for example before the countdown. **Effort:** S

### F8 — Developer calibration keys ship in Release, clash with user keys, and "+" is dead on US keyboards · P2 · VERIFIED
- **Where:** `PlaybackShortcutRegistry.swift:96-155` appends these outside `#if DEBUG`: L (diagnostic hold), `[` `]` (beat phase ±10 ms), ⇧B (bar phase) and `,` `.` (output latency ±5 ms).
  - The ⇧? help lists them under "DEVELOPER" with labels such as "Audio output latency −5 ms (BUG-007.6)".
  - `.` is registered first as Reshuffle (line 274), so latency +5 is unreachable while `,` (−5) works. The change is silent and lasts until relaunch.
  - "+" is registered with `modifiers: []` (257-263), but `PlaybackKeyMonitor.swift:53-58` requires an exact modifier match. On a US/UK layout "+" is Shift+=, so it never matches.
  - The "Diagnostic hold ON/OFF" toast is hardcoded English.
- **Failure:** Testers see bug IDs in the help overlay. Pressing `,` a few times pulls the visuals off the beat for the rest of the run, with no undo. "More of this style" is dead on MacBook keyboards while "Less" works.
- **Fix:** Move the developer rows under `#if DEBUG`. Accept Shift for "+", or bind "=". **Effort:** S

### F9 — The playback key monitor hijacks Settings, the help overlay and dialogs · P2 · VERIFIED (dialog case PLAUSIBLE)
- **Where:** `PlaybackKeyMonitor.swift:32` installs an app-wide local monitor that stays until PlaybackView disappears, so `.onExitCommand` in `SettingsView.swift:48` never sees Esc. `ShortcutHelpOverlayView.swift:55` says "Press any key to dismiss", but only a tap dismisses it (line 23).
- **Failure:**
  - Esc in the mid-session Settings sheet brings up "End this session?".
  - With the help overlay open, keys don't dismiss it: Esc asks to end the session and Space toggles the chrome.
  - Esc on the end-session dialog likely re-requests the dialog instead of cancelling (PLAUSIBLE).
- **Fix:** Skip the monitor while a sheet, dialog or the help overlay is up, and let any key dismiss help. **Effort:** S

### F10 — Uzume says "Ready" when nothing was prepared · P2 · VERIFIED
- **Where:** `SessionManager.swift:224-231`: a connect failure goes to `.ready` with `.reactiveFallback` and no message. Lines 333-344: preparation completion goes to `.ready` even when every track is `.failed`. `ReadyView` never checks readiness. The §9.3 "Couldn't prepare any of this playlist" screen exists only while `.preparing`, so it is replaced within a frame.
- **Failure:** An offline tester, or a playlist whose previews all fail, sees "Ready. Press play in Spotify." The session is live-only, with no plan and no explanation.
- **Fix:** Stay on the §9.3 recovery screen, or show honest live-only copy on Ready. **Effort:** S–M

### F11 — Cancel during "Connecting" doesn't stick · P2 · VERIFIED
- **Where:** `SessionManager.swift:221-233`: after `try await connector.connect(...)` there is no cancel or generation check before `_beginPreparation`, and the error path sets `state = .ready`.
- **Failure:** The Apple Music read, a per-track AppleScript loop that runs twice (once in the picker VM, once in SessionManager), can take seconds. The tester clicks Cancel and returns to Idle, then the app jumps to Preparing, or to Ready if the read failed.
- **Fix:** After the await, check the same generation guard the preparation path already uses. **Effort:** S

### F12 — Denying Apple Music Automation leaves an endless "Checking every 2 seconds…" loop · P2 · VERIFIED
- **Where:** `PlaylistConnector.swift:247-255` returns nil for every AppleScript error, including −1743 (not permitted). `AppleMusicConnectionViewModel.swift:6-14` documents this. `.permissionDenied` is never assigned, so the ready-made permission screen (`AppleMusicConnectionView.swift:67`) is unreachable.
- **Failure:** A tester who clicks "Don't Allow" on "Uzume wants to control Music" is told to start a playlist, which is already playing, forever.
- **Fix:** Map −1743 to `.permissionDenied`. **Effort:** S

### F13 — Preparation escape routes are missing, and "You're offline" fires falsely for local files · P2 · VERIFIED
- **Where:**
  - `NoticeBanner` renders the headline only (`LocalizedCopy.string`), so the >90 s and >120 s banners never show their "start in reactive mode / try again" body, and neither has a button.
  - `ContentView.swift:178-186` never passes `onStartReactive` or `onPickAnotherPlaylist`. `RecoveryScreen` therefore hides "Start reactive mode", and its primary button reads "Pick another playlist" (which just cancels), even for "You're offline".
  - `PreparationErrorViewModel.swift:122-128` raises the full-screen offline error for any origin, local files included.
- **Failure:** When preparation is slow, the tester sees "This is taking longer than expected." with only Cancel. On an offline laptop, opening a local folder shows full-screen "You're offline. Uzume can't fetch previews." The only button cancels the local session, which would otherwise have prepared fine behind the screen.
- **Fix:** Wire the reactive-mode CTA, skip reachability checks for local-file origins, and give each error its own CTAs. **Effort:** S

### F14 — Closing the window doesn't stop the session · P2 · VERIFIED
- **Where:** There is no window-close or last-window handling (no app delegate). Capture and the stem pipeline stop only on `.ended` (`VisualizerEngine.swift:1149-1167`).
- **Failure:** A tester closes the window to stop. The macOS recording indicator stays on, stem separation keeps running every 2 s (battery, fans), and F2's WAVs keep being written. Reopening from the Dock drops them back into the running session.
- **Fix:** End the session, or quit, when the last window closes. **Effort:** S

### F15 — "Show uncertified scenes" exposes scenes that never passed the flash-safety gate · P2 · VERIFIED
- **Where:** `VisualsSettingsSection.swift:119-133` is visible in Release, with the hint *"Useful for testing work-in-progress scenes."* `PhotosensitivityCertificationTests.swift:123` has `guard preset.descriptor.certified else { return }`, so only certified scenes are flash-checked.
- **Failure:** A curious tester turns it on and their sessions start including scenes that were never checked for photosensitivity.
- **Fix:** Make it DEBUG-only for the beta. **Effort:** S

### F16 — Beta testers have no way to send feedback · P2 · VERIFIED
- **Where:**
  - The pbxproj pins `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1` in both configurations, so every build reports "1.0 (1)".
  - There is no Help or "Report a problem" command and no update mechanism.
  - "Copy debug info" is only reachable mid-session (F6) and copies only version, macOS and GPU.
  - Logs sit in `~/Documents/uzume_sessions` with no export.
  - The copyright reads "© 2024 Matt" in Info.plist but "© 2026 Uzume contributors" in About.
- **Failure:** Tester reports can't name the build they ran, and there is no one-click way to attach a log.
- **Fix:** Bump the build number per beta and add Help › Report a Problem, which zips the latest session log plus debug info. **Effort:** M

### F17 — Local-file-only users hit the permission wall after every session · P3 · VERIFIED
- **Where:** `SessionManager.endSession()` sets `currentSource = nil` (line 594), so the `ContentView` gate shows `PermissionOnboardingView` instead of `EndedView`, and "Play … again" is lost. The Local files tile is reachable only through IdleView, which is behind the gate. The permission copy never mentions that local files work without the permission.
- **Fix:** Gate only the streaming paths, and add "Play local files instead" to the permission screen. **Effort:** S

### F18 — Raw string keys and placeholders are visible, and some specified errors are never shown · P3 · VERIFIED
- **Raw keys in Settings:** these localization keys are missing, so the raw key text is shown:
  - `settings.about.app.title` (the About section header)
  - `settings.about.copy_debug_info.caption`
  - `settings.visuals.blocklist.caption`

  `check_user_strings.sh` doesn't check that keys exist.
- **EndedView:** duration is always "—", because `ContentView:86` passes nil. "%lld tracks" isn't pluralised ("1 tracks") and counts planned rather than played tracks.
- **Other copy:** ReadyView has a hardcoded `"\(n) tracks."`. The blocklist shows the internal "Transition" family via `rawValue.capitalized`. Shortcut labels and categories are hardcoded English.
- **Unwired errors:** three §9.4 errors have no emitter anywhere: tap reinstalls failed, sample-rate mismatch, analyzer failure.
- **Fix:** Add the keys, plus a test that every referenced key exists. **Effort:** S

### F19 — The cursor never hides during playback · P3 · VERIFIED
There is no `NSCursor.setHiddenUntilMouseMoves` or equivalent anywhere. The chrome fades as §7.2 specifies, but the arrow stays over the fullscreen visuals. **Fix:** Hide the cursor together with the chrome. **Effort:** S

## Reviewed and healthy
- All six `SessionState` cases are routed in `ContentView`, with no missing arms.
- The paste-a-link flow is DEBUG-only (`ConnectorPickerView.swift:148-152`). So are the missing-Spotify-Client-ID developer copy, the ⌘[ ⌘] scene cycle and the forced stall card.
- No user-visible "Phosphene" anywhere; no "AI" product claim in the strings or Info.plist.
- `SettingsMigrator` and `IdentityMigrator` are idempotent, never overwrite newer values and never fail launch.
- Permission onboarding: "Allow Access" calls `CGRequestScreenCaptureAccess` (BUG-111), with a deep-link fallback and an auto-refresh when the app becomes active.
- Forced dark appearance; text tokens meet contrast (for example #A4A8A2 on #0B0C10 ≈ 8:1).
- The Metal surface is hidden from VoiceOver. Chrome buttons carry labels and "what it does now" hints, and the countdown announces each number.
- The stall card correctly stays quiet when the tester pauses after audio has been heard.
- `LSMultipleInstancesProhibited` is set and File › New Window is removed.
- The local-file error surfaces (InlineNotice, PUB.5 toasts) are honest.
- Hot reload of user presets is a deliberate product decision (PUB.7), not a leak.

## Could not verify
- Whether SwiftUI opens a second window for Finder file-open events or `uzume://` events (a `WindowGroup` with no `handlesExternalEvents`), which would put two windows on one engine. Needs a live check.
- Whether `CGPreflightScreenCaptureAccess` flips to true without a relaunch on macOS 15/26, which the "auto-advance" promise in §3.2 depends on.
- `NSAudioCaptureUsageDescription` is absent from Info.plist. I can't tell whether process taps on fresh macOS 14.4+/15 installs need it (audio lane).
- Display sleep or the screensaver during long hands-off sessions. Uzume takes no power assertion itself; KNOWN_ISSUES shows coreaudiod holding one on Matt's Mac, which isn't guaranteed for every audio route.
- Apple Music "current playlist" when playing from the Songs view may enumerate the whole library.
- Release is signed "Apple Development" and isn't notarized, and the TCC grant churns on every build (BUG-055). That belongs to the release lane, but it will surface to testers as F3's card.
