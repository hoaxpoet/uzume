# Lane A: Security, privacy and distribution readiness (2026-09-29)

Baseline was `docs/SECURITY_POSTURE.md`. Several of its claims no longer hold, and it missed four things: the session recorder is on in every Release build, the Settings switch that is supposed to turn it off does nothing, it saves the audio it hears to disk, and track names go to MusicBrainz. Everything below was traced in code on `main` (`efb3eed3`) and checked against real build products where possible. Nothing here duplicates an open KNOWN_ISSUES entry. BUG-055 is related to A5, but A5 is a different mechanism.

---

## A1 — P0 — Every tester session saves the Mac's audio to disk, the switch to stop it does nothing, and the permission prompt says the opposite
**Confidence:** VERIFIED
**Where:**
- `UzumeApp/VisualizerEngine.swift:996`: `self.sessionRecorder = SessionRecorder()`. There is no argument, and the default is `enabled: Bool = true` (`SessionRecorder.swift:271`).
- `UzumeApp/Services/SettingsStore.swift:87`: `@Published var sessionRecorderEnabled: Bool = true`. Nothing in the app or the engine reads it. A whole-repo grep finds only the store, the view model, the Settings view, the migrator and tests. `docs/CAPABILITY_REGISTRY/APP.md:469` wrongly lists it as "production-active".
- `VisualizerEngine+Stems.swift:372`: `sessionRecorder?.recordStemSeparation(...)` runs after every live separation. The cadence is `stemSeparationPeriodSeconds = 2.0` (line 105) and each chunk is 10 s.
- `VisualizerEngine+Audio.swift:119`: `recordRawTapSamples` is called on every tap callback.
- `Info.plist`, `NSScreenCaptureUsageDescription`: *"…Nothing is recorded or sent anywhere."* Onboarding (`Localizable.strings:104`): *"It doesn't record your screen, your microphone, or anything else. Nothing ever leaves your Mac."*

**What happens to a tester:** One recorder is created per app launch and is always on in Release. The Diagnostics tab is visible in Release and has a **"Record sessions to disk"** switch; turning it off changes nothing.

For a streaming session (Spotify scan, Apple Music or ad-hoc), the tap starts at `.ready` (`startListeningForFirstAudio`). From then on, `~/Documents/uzume_sessions/<stamp>/` receives:
- `raw_tap.wav`: the first 30 s of **everything the Mac outputs** after Ready. That can be a Zoom or FaceTime call, a YouTube video or a notification, not only music.
- Every ~2 s while audio is non-silent: `stems/NNNN_<title>/{drums,bass,vocals,other}.wav`, four 10-second chunks of 16-bit audio. `vocals.wav` isolates **voices**. The 10-second chunks overlap 5×, so a whole streamed song can be rebuilt from the stem files. That amounts to ripping streamed audio, which is a Spotify and Apple Music terms-of-service exposure for a public release.
- `session.log`: every track title and artist, local file names, the playlist name, the machine hostname (for example `janes-macbook-air.local`) and the home-folder path.

Local-file sessions with a cached series skip the stem dump but still write `raw_tap.wav`, the CSVs and the log.

The permission text the tester agreed to is false. If Documents is synced to iCloud ("Desktop & Documents Folders"), "nothing leaves your Mac" is false as well. There is a likely further first-session prompt, *"Uzume would like to access files in your Documents folder"*. I have not observed it (see Could not verify).

**Fix direction:** Make Release default to no recording, or honour the switch at recorder construction with a default of off for testers. Never write raw or stem audio outside DEBUG or an explicit opt-in. Move diagnostics to `~/Library/Logs/Uzume` (no Documents prompt, no iCloud sync). Rewrite the TCC and onboarding copy to match. **Effort:** S (gate plus default) to M (relocate, opt-in UX, copy).

## A2 — P1 — Nothing limits how much the recorder writes, so a streaming session can fill the tester's disk (and then crash the app)
**Confidence:** VERIFIED that there is no cap. The fill rate is PLAUSIBLE: it is computed from code because no streaming session folder survives on this Mac.
**Where:** `SessionRecorder+Stems.swift` writes 4 × 880,640 bytes (440,320 mono Int16 samples) ≈ **3.5 MB per separation**. `SessionRecorder+DiskGuard.swift` has no budget, only a warning under 200 MB free and a halt at ENOSPC. The CSVs add about 1 KB per rendered frame, so ~0.2 GB/h at 60 fps (measured: `2026-09-28T22-22-30Z`, 8,889 rows = 9 MB).
**What happens to a tester:** Streaming playback writes about **3–6 GB per hour** into `~/Documents`.
- Retention runs only at launch (`UzumeApp.swift:51`) and counts **app launches**, not sessions. "Keep last 10" can therefore mean 10 × tens of GB.
- A tester with 20 GB free on an 8 GB/256 GB Air fills the disk in an evening. At that point the recorder halts cleanly, but two legacy non-throwing `FileHandle.write` calls raise uncatchable exceptions on ENOSPC: `~/uzume_diag.log` (`VisualizerEngine+Audio.swift:641`, about once a second) and `raw_tap.wav` (`SessionRecorder+RawTap.swift:76`). Result: the Mac is out of space and Uzume crashes.
- With iCloud-synced Documents, a free 5 GB iCloud tier fills in about an hour.

**Fix direction:** Resolving A1 removes the stem dump. Also add a per-folder byte budget, prune by size, and switch the two remaining writers to `write(contentsOf:)`. **Effort:** S–M.

## A3 — P0 — There is no Developer ID signing or notarization yet, and the script meant to do it has never run
**Confidence:** VERIFIED
**Where:**
- `project.pbxproj:1385`: `CODE_SIGN_IDENTITY = "Apple Development"` with `DEVELOPMENT_TEAM = 2LBTN9PB4Z`, which the staged commit describes as "the free personal team, which cannot issue a Developer ID cert".
- The latest Release product's signature (`codesign -d`): `Authority=Apple Development: <personal Apple ID, redacted>`, entitlements include `com.apple.security.get-task-allow => true`.
- `Scripts/release_notarize.sh` exists only in commit `ea559d23`, on **local branch `clean-2.5b-notarize-staged`**. That branch is not on `main` or on any remote. Its commit message says: *"EVERYTHING AFTER THE PRECONDITIONS HAS NEVER EXECUTED"*, and that the Apple Developer Program organization enrollment (Plait & Pattern LLC) was *"submitted 2026-09-24, in review"*.

**What happens to a tester:** On macOS 15 and 26, a downloaded dev-signed app cannot be opened with Control-click. The tester has to go to System Settings → Privacy & Security → "Open Anyway" and enter an admin password ([Apple: runtime protection in Sequoia](https://developer.apple.com/news/?id=saqachfa)). `get-task-allow` also defeats the hardened runtime.

There is no fallback channel. TestFlight and the Mac App Store both require the App Sandbox, which the global tap rules out (SECURITY_POSTURE §2).

The first real run of the script may also surface problems it has never been tested against:
- ownership of bundle ID `io.uzume.mac` moving from the personal team to the organization team, under automatic signing at export;
- whether the archive includes an Intel slice.

Finally, the staged script can be lost, because it exists only on a local branch.

**Fix direction:** Push the staged branch now. Track the enrollment daily. Budget a full dry run (archive → notarize → staple → a clean account on macOS 14, 15 and 26) at least a week before Oct 15. Decide now what happens if enrollment is late. **Effort:** M, and blocked on Apple.

## A4 — P1 — A build made outside Matt's main checkout ships without the ML models, and nothing warns
**Confidence:** VERIFIED on the artifacts. The runtime effect is PLAUSIBLE.
**Where:** `Package.swift:69` has `resources: [.copy("Weights")]`. The weights (~167 MB) are fetched by hand with `Scripts/fetch_weights.sh`. No build phase checks for them, and neither does the staged notarize script.
**Evidence:** Five Release `Uzume.app` builds under DerivedData made from worktrees have a **188 KB** `UzumeEngine_ML.bundle`. The one built from the main checkout has **167 MB**. All of them built successfully.
**What happens to a tester:** If the beta is archived from a worktree, CI or a fresh clone:
- `StemSeparator` fails to load, and the log only says "Stem pipeline skipped".
- Beat-grid, mood and instrument analysis degrade quietly.

The app launches and looks broken ("visuals don't follow the music") with no error.
**Fix direction:** Add a build-phase or release-script gate that runs `shasum -c SHA256SUMS` on the weights (or checks the ML bundle size) and fails when they are missing. **Effort:** S.

## A5 — P1 — The Info.plist lacks the key Apple documents for capturing system audio
**Confidence:** PLAUSIBLE. The requirement is documented by Apple; behaviour on 14.x and 15.x has never been tested.
**Where:** `UzumeApp/Info.plist` has no `NSAudioCaptureUsageDescription`, and a repo-wide grep finds zero mentions of it. Apple states: *"To capture audio with a tap, you need to include the NSAudioCaptureUsageDescription key"* ([Apple sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps); [key reference, macOS 14.2+](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription)). When permission is missing or denied the tap returns silence with no error ([Apple forums 771864](https://developer.apple.com/forums/thread/771864); [2,000 Buffers of Nothing](https://dev.to/nickdelv/2000-buffers-of-nothing-3i8)).
**What happens to a tester:** On Matt's macOS 26 machine the tap works through the "Screen & System Audio Recording" grant (BUG-055 history). On Sonoma 14.2–14.7 the pane is "Screen Recording" only, and there is no evidence that granting it covers a tap. Nothing in the repo shows a test on 14.x or 15.x. If it doesn't cover it, a Sonoma tester gets:
- a correct grant and a visualizer that stays flat;
- the audio-stall card (A9), whose advice cannot fix the problem.

The "why" copy (*"permission to capture system audio is bundled with screen recording… Apple groups them together"*) is out of date.
**Fix direction:** Add the key; it is free. Test on a 14.x Mac and a 15.x Mac. Consider an audio-only permission for listening, and ask for Screen Recording only when a scan starts (see A8). **Effort:** S for the key, M for the permission split.

## A6 — P1 — If a tester clicks "Don't Allow" on the Apple Events prompt, Uzume never says so
**Confidence:** VERIFIED
**Where:**
- `PlaylistConnector.swift:185`: `guard let output, !output.isEmpty else { return [] }`. Error −1743 (automation denied) returns nil, which becomes an empty list.
- `AppleMusicConnectionViewModel.swift:113`: `state = .noCurrentPlaylist` followed by a 2 s auto-retry.
- `.permissionDenied` (`AppleMusicConnectionView.swift:67`) and `UserFacingError.appleScriptPermissionDenied` are never assigned anywhere; a TODO in the view model admits it.
- `StreamingMetadata` (AppleScript is the only now-playing source) also turns −1743 into nil.

**What happens to a tester:** The macOS prompt reads *"Uzume wants access to control 'Music'… to perform actions within that app"*, and cautious users decline it. Two outcomes:
- **Apple Music:** "Start a playlist in Apple Music, then come back. Checking every 2 seconds…" forever. macOS never asks again.
- **Spotify scan session:** now-playing polling fails silently, so Uzume cannot see track changes and the plan never follows the music.

**Fix direction:** Detect −1743 in both AppleScript paths and route it to the existing permission-denied UI, which has the Automation deep link. **Effort:** S.

## A7 — P2 — Track titles go to Apple and MusicBrainz, which the privacy copy denies and SECURITY_POSTURE doesn't list
**Confidence:** VERIFIED
**Where:**
- `VisualizerEngine+Audio.swift:86–96`: `buildFetcherList()` always includes `ITunesSearchFetcher` and `MusicBrainzFetcher`.
- `kickoffPreFetch` (`VisualizerEngine+Capture.swift:259`) runs on every track change.
- `SessionPreparer.swift:633` runs during preparation.
- `MusicBrainzFetcher.swift:26` sends to `musicbrainz.org` with a User-Agent naming the repo.
- SECURITY_POSTURE §7 lists only "Spotify / Apple Music / iTunes lookup".

**What happens to a tester:** Every played track's title and artist leaves the Mac, including the tester's local-library files, played during streaming sessions. It goes to Apple and to a third party (the MetaBrainz Foundation). "Nothing ever leaves your Mac" is inaccurate.

Separately, MusicBrainz has no 1 request/second limiter, so preparing a 40-track playlist bursts past their policy and gets 503s. The metadata then quietly disappears.
**Fix direction:** Correct the copy ("only song names are looked up, never audio"). List MusicBrainz in SECURITY_POSTURE, or drop it. Add a rate limiter. **Effort:** S.

## A8 — P2 — Screen Recording permission blocks the whole app, local files included, and the screen offers no way to skip it
**Confidence:** VERIFIED
**Where:** `ContentView.swift:47`: `if permissionMonitor.isScreenCaptureGranted || …currentSource?.isLocalFile == true`. Local-file playback uses no tap, yet the only escape is the File menu. The onboarding card has no "Play my own files instead" path.
**What happens to a tester:** A tester who only wants local files, or who declines Screen Recording on principle, is stuck on the permission card.
**Fix direction:** Offer a local-files route on the card. With A5's split, Screen Recording would only be asked for when scanning. **Effort:** S–M.

## A9 — P2 — The "no audio" card asks non-developer testers to run a `sudo` command in Terminal
**Confidence:** VERIFIED
**Where:**
- `AudioStallOverlayView.swift:41–42`: `command: "sudo killall coreaudiod"`. It is shown in Release; only the forcing shortcut is `#if DEBUG`.
- `playback.audioStall.step2`: *"If you just rebuilt Uzume, re-grant…"*

**What happens to a tester:** Being told to paste an admin command into Terminal is a security anti-pattern, and it contradicts Matt's own doctrine (DECISIONS: "must not make a user run Terminal commands"). The "rebuilt" wording is developer copy.
**Fix direction:** In Release, show only the output-device and permission steps, with non-developer wording; keep the `sudo` line for DEBUG. **Effort:** S.

## A10 — P2 — Preview lookups always search the US store, so region-only songs get no preview
**Confidence:** PLAUSIBLE (the effect abroad is untested)
**Where:** `PreviewResolver.swift:196–201` sends only `term/media/entity/limit` with no `country`; `ITunesSearchFetcher.swift:39` does the same. The default storefront is US.
**What happens to a tester:** For a tester outside the US, songs available only in their country resolve to no preview or the wrong song (compare BUG-152), and those tracks fail preparation.
**Fix direction:** Pass `country=` from the Mac's region, with US as a fallback. **Effort:** S.

## A11 — P3 — The app installs on macOS 14.0/14.1 but has no audio there, with no explanation
**Confidence:** VERIFIED
**Where:** `LSMinimumSystemVersion` is 14.0 (pbxproj and built Info.plist). The tap, `AudioInputRouter` and the local-file router are all `@available(macOS 14.2)`. `VisualizerEngine+LocalFilePlayback.swift:203` logs "BAILED — macOS < 14.2".
**What happens to a tester:** The app launches and prepares, then no source produces any audio. It does not crash, which is good.
**Fix direction:** Raise the deployment target to 14.2. AudioCap and others use 14.4 for the tap permission prompt. **Effort:** S.

## A12 — P3 — A stray `~/uzume_diag.log` appears in every tester's home folder
**Confidence:** VERIFIED
**Where:** `VisualizerEngine+Audio.swift:80`: `NSHomeDirectory() + "/uzume_diag.log"`. It is truncated and reopened at every launch during `setupAudioRouting`, and appended to during analysis. The file exists on this Mac.
**Fix direction:** Remove it, or make it DEBUG-only, or move it to `~/Library/Logs`. **Effort:** S.

## A13 — P3 — The user preset folder is live in Release, and a dropped-in preset can mark itself "certified"
**Confidence:** VERIFIED on the code path. Impact needs a user to install a file.
**Where:** `VisualizerEngine.swift:919–927` watches `~/Library/Application Support/Uzume/Presets`. `PresetLoader.loadFromDirectory` (`:303`) compiles any `.metal` file and uses the sidecar exactly as written.
**What happens to a tester:** A preset shared between testers can claim `certified: true` and enter the planner without the flash-safety and fidelity gates. A bad shader can also hang the GPU. The OS contains the damage; the photosensitivity gate is what's bypassed.
**Fix direction:** Ignore `certified` for directory presets, or turn the watcher off for the beta. **Effort:** S.

## A14 — P3 — Local file names and paths are logged publicly in the macOS unified log
**Confidence:** VERIFIED
**Where:** For example `LocalFileMenuCommands.swift:146`, `VisualizerEngine+LocalFilePlayback.swift:296/369`, `LocalFilePlaybackProvider.swift:413` and `UzumeApp.swift:144` use `privacy: .public` for file names and paths.
**What happens to a tester:** Their listening history appears in any sysdiagnose they send.
**Fix direction:** Use `.private(mask: .hash)`. **Effort:** S.

## A15 — P3 — A timing race when stopping a scan can leave a screen capture running with nothing reading it
**Confidence:** PLAUSIBLE; the window is narrow.
**Where:** `SpotifyScanServices.swift:176–177`. The code checks `continuation != nil` and stores `self.stream` in two separate lock acquisitions. A `stop()` that lands between them leaves an `SCStream` running with no consumer.
**What happens to a tester:** Frames are captured and dropped, and the purple recording indicator stays on until the next stop.
**Fix direction:** Do the check and the assignment in one critical section. **Effort:** S.

---

## Reviewed and healthy
- **AppleScript:** all three scripts are static literals with no interpolation, so there is no injection path. `isAppRunning` guards stop them from launching or prompting for an app that isn't running.
- **`uzume://` callback:** scheme, host and `state` checks plus PKCE hold. The OAuth and paste-link UI is `#if DEBUG` only in Release (`ConnectorPickerView.swift:148`).
- **Keychain:** a generic-password item with the default (when-unlocked) accessibility. No token is logged, and the token-endpoint error body uses default private redaction.
- **Secrets:** nothing leaked. `SPOTIFY_CLIENT_SECRET` has only ever appeared as an empty placeholder in git history. The built Info.plist carries only the public client ID.
- **Network basics:**
  - no App Transport Security exceptions, and every endpoint is https;
  - HTTP status codes are checked;
  - all JSON decoding is `try`-guarded with no force-unwraps;
  - preview temp files use UUID names and are deleted with `defer`.
- **Disk caches:** the artwork cache uses SHA-256 file names with a byte cap and eviction. The stem cache has a 500 MB LRU cap.
- **m3u parsing:** the BUG-051 allow-list and canonicalisation hold at the parser boundary.
- **SCAN:** it captures one window only (`desktopIndependentWindow:`), with `onScreenWindowsOnly`, no audio and no cursor. Frames stay in memory. A minimized window or one on another Space gives `windowUnavailable`, and a Spotify quit gives `spotifyClosed`.
- **Hardened runtime:** on in Release. The `apple-events` entitlement is present, library validation is not disabled, and runtime Metal compilation is compatible.
- **Tap API:** everything is behind `@available/#available(macOS 14.2)`, so there is no launch crash on 14.0.
- **Apple Music:** the path does not depend on MusicKit. `MusicKitFetcher` is never instantiated, so no MusicKit App-ID service is needed. The linked MusicKit framework and `NSAppleMusicUsageDescription` are dead weight.
- **Other:** `LSMultipleInstancesProhibited` is set. A privacy manifest is not required for Developer ID distribution. Written files sit under per-user directories.

## Could not verify
1. Whether a Screen Recording grant covers the tap on Sonoma 14.2–14.7 and on 15.x without the key (A5). Needs a real run on a 14.x Mac and a 15.x Mac.
2. When the Documents-folder prompt appears on a clean account, and the real size per hour of a streaming session folder. No streaming session with `stems/` survives on this Mac; retention pruned them.
3. Whether `release_notarize.sh` exports under the organization team with automatic signing (bundle-ID ownership), and whether a generic-platform archive adds an Intel slice. The current Release binary is arm64-only; Intel-Mac behaviour is unknown.
4. macOS 15+ periodic "bypass the private window picker" re-prompts triggered by SCAN's ScreenCaptureKit use.
5. Whether any tester has iCloud "Desktop & Documents" enabled. This amplifies A1 and A2.

**SECURITY_POSTURE claims that no longer hold:**
- §1/§7 "session recordings… local" hides that raw and stem **audio** of arbitrary system output is written by default.
- §7 omits MusicBrainz.
- The TCC string "Nothing is recorded" is false.
- §3 is still accurate: Developer ID is deferred.
