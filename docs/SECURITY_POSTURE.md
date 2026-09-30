# Uzume — Security Posture & Local Threat Model

> CLEAN.2.4 / audit GAP-10 (`docs/diagnostics/CODE_AUDIT_2026-06-13.md` Part B G10, Part C row).
> Review + document increment — **no security build settings were flipped here**; fixes are filed, not applied blind (each needs a build + real run). Posture below verified against source 2026-06-15.
>
> **Update (CLEAN.2.5a, 2026-06-15):** the hardened-runtime half of GAP-10 is now applied — `ENABLE_HARDENED_RUNTIME=YES` + the `com.apple.security.automation.apple-events` entitlement (§3, §4, summary row 3 updated). Developer ID signing + notarization (CLEAN.2.5b) remain deferred — **blocked on a paid Apple Developer Program membership**.
>
> **Update (CLEAN.2.5b, 2026-09-29):** done. Tester builds are Developer ID–signed by Plait & Pattern, LLC (`TYK3BXQ5D4`), notarized and stapled, as a DMG from `Scripts/release.sh` (§3, summary rows 1 and 3, D-261). `NSAudioCaptureUsageDescription` is declared (§1). The public build keeps no session records, so it never asks for Documents access (BUG-158).

## What this is

The security posture and a local threat model for Uzume. It states, for each surface, the **verified current state**, the **threat/rationale**, and the **decision or filed follow-up**. It is the reference for "is surface X a problem, and what did we decide about it."

## Governing context (CLAUDE.md §Development Constraints)

Uzume is **macOS-only**, single-user, **on-device only — no cloud, no telemetry**, MIT-licensed. The Mac mini is the primary dev/deploy target. There is **no public build yet** (`RELEASE_NOTES_DEV.md` preamble).

**Distribution intent (Matt, 2026-06-15):** *eventual distribution is on the roadmap* (sharing a notarized build / a possible public release). This does not change what 2.4 does — it still only documents and files — but it makes hardened-runtime + notarization (§3) a **near-term filed follow-up (CLEAN.2.5)** rather than indefinitely deferred. The actual enablement is its own increment because it touches the signing pipeline and needs a real Gatekeeper + tap test.

**The exfiltration posture is the headline strength.** No telemetry, no analytics, no cloud sync; on-device ML; the only outbound network is to Spotify / Apple Music (the user's own connection), and to the iTunes Search and MusicBrainz APIs, which receive **each track's title and artist, and the Mac's two-letter region** (BR.19 / C8), to look up previews, genre and length (MusicBrainz held to its 1 request/s rule, BR.16). The app says so: *"Your audio never leaves your Mac. Uzume looks up song details on Apple's iTunes and MusicBrainz."* (decision 9). Audio is tapped but never uploaded. Session recordings are written to local disk only. For a privacy-sensitive surface (a system-wide audio tap) the data simply has nowhere to go. The playlist scan (SCAN, §8) keeps this shape: it reads Spotify's window on device, in memory, and contacts no Spotify server.

## Summary (verified 2026-06-15)

| # | Aspect | Current state | Verdict |
|---|---|---|---|
| 1 | System-audio tap | `.systemAudio` = global tap, excludes nothing (production always uses this); `.application` = single-PID path retained in engine code but not user-selectable (CLEAN.2.3.5). TCC-gated on Screen & System Audio Recording; `NSAudioCaptureUsageDescription` declared (CLEAN.2.5b); the tap itself is audio-only (the one pixel-reading surface is row 8). | Document — core mechanism, consent-gated. |
| 2 | App sandbox | **Off** — `app-sandbox = false` is the only entitlement. | Document — incompatible with the tap; partial sandbox not viable. |
| 3 | Hardened runtime + notarization | **Hardened runtime ON** (CLEAN.2.5a — `ENABLE_HARDENED_RUNTIME=YES` on the app target **Release** config; Debug left unhardened so XCTest injection works; signs `-o runtime`; `automation.apple-events` entitlement added). Tester builds: **Developer ID Application: Plait & Pattern, LLC (TYK3BXQ5D4)**, notarized + stapled app and DMG (`Scripts/release.sh`); everyday builds stay "Apple Development" under the same team. | **CLEAN.2.5a done + verified** (HR; runtime gates verified 2026-06-15). **CLEAN.2.5b done + verified 2026-09-29** — all 13 artifact checks pass (§3); Gatekeeper: `accepted, source=Notarized Developer ID`. |
| 4 | Library validation | Not declared. Links Apple frameworks + SPM static libs only. | Document — not required; keep ON under hardened runtime. |
| 5 | `uzume://` OAuth callback | scheme + host + `state` (CSRF/replay) + nil-pending rejection; double-checked at `.onOpenURL`. | Document — mitigated (CLEAN.2.2). |
| 6 | Local-file open path | Defensive m3u parser + AVFoundation decoders; resolved entries canonicalized + filtered to an audio extension allow-list. | **BUG-051 fixed 2026-08-07** (BUG051.1) — allow-list applied at the parser boundary. |
| 7 | Secrets at rest + no-telemetry | OAuth tokens in Keychain; only the public client ID is checked in; no telemetry. | Document — posture strength. |
| 8 | Spotify window reading (SCAN, D-260) | During a user-started playlist scan, ScreenCaptureKit reads **Spotify's window only** (a single-window content filter, never a display), frames processed in memory and dropped, only while the scan panel is open; stops on Done / Cancel / Esc / Spotify quitting. Nothing persisted or sent; no Spotify server contacted; no Accessibility API or synthetic input. Dropped screenshots are read in memory the same way. Permission re-checked at scan start. | Document — consent-gated, user-initiated, narrowest filter. |

---

## 1. Global system-audio tap

**Current posture (verified — `UzumeEngine/Sources/Audio/SystemAudioCapture.swift` `buildTapDescription`).** Two modes:
- `.systemAudio` → `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` — a **global tap that excludes nothing**, i.e. it captures the entire system audio mix (every app). (The empty-exclude variant is load-bearing — the seemingly-equivalent `stereoMixdownOfProcesses: []` delivers silence; see the code comment + Failed Approaches #21/#22 at the tap-install site / `docs/RUNBOOK.md`.)
- `.application(bundleID)` → `CATapDescription(stereoMixdownOfProcesses: [pid])` — narrows to a **single process**. This case remains in the engine, but is **not currently user-selectable**: the Settings per-app picker and the `switchMode`/`availableApplications` plumbing were removed as inert (CLEAN.2.3.5/2.3.6), so production always uses `.systemAudio`.

The tap is **TCC-gated**: macOS requires the user to grant screen-recording permission before `AudioHardwareCreateProcessTap` will install. That grant is the consent boundary.

**Audio-capture declaration (CLEAN.2.5b, 2026-09-29).** `Info.plist` now carries `NSAudioCaptureUsageDescription` (*"Uzume listens to the music playing on your Mac to create its visuals. Nothing is recorded or sent anywhere."*), which Apple documents for Core Audio process taps. Without a grant the tap installs and delivers silence with no error, so this is load-bearing for testers, who have none of Matt's earlier grants. On Matt's account after `tccutil reset` of ScreenCapture + AudioCapture, the notarized build asked only for Screen & System Audio Recording; playing music produced `Signal` green at −7.7 dBFS with no separate audio-capture question (the TCC log shows no `kTCCServiceAudioCapture` request).

**`NSScreenCaptureUsageDescription` honesty (re-verified at SCAN, 2026-09-28).** The string now reads *"Uzume listens to your Mac's audio to create visuals and, when you scan a playlist, reads the track names in your Spotify window. Nothing is recorded or sent anywhere."* The earlier claim here — that the permission was purely the OS gate for the audio tap and **no screen pixels are ever read** — stopped being true at SCAN: the playlist scan reads Spotify's window (§8). The tap itself still reads no pixels. `SessionRecorder` (`UzumeEngine/Sources/Shared/SessionRecorder+Video.swift`) does write video, but it encodes the app's **own rendered Metal texture** (`appendVideoFrame(from tex: MTLTexture …)`) — Uzume's generated visuals, not the user's screen — to local disk (`~/Documents/uzume_sessions/<stamp>/`, `SessionRecorder.swift:210-238`). "No video is recorded" is true of *screen/user content*; the only video recorded is Uzume's own output, on-device.

**Threat / rationale.** A global audio tap is a real privacy surface: while active it can observe audio from any app. Mitigations: (a) the OS consent gate (user must explicitly grant screen-recording); (b) **audio-only** — no screen content; (c) **no exfiltration** — tapped audio is analyzed on-device and never uploaded (see §7); (d) the engine retains an `.application` (single-PID) tap path in code, though it is not currently user-selectable (CLEAN.2.3.5).

**Decision.** Document — no fix. The global tap is the product's core mechanism and is consent-gated. No change.

## 2. App sandbox = off

**Current posture (verified — `UzumeApp/UzumeApp.entitlements`).** `com.apple.security.app-sandbox = false` is the **only** entitlement declared.

**Threat / rationale.** An un-sandboxed app has the user's full file/IPC reach; a compromise (e.g. via a decoder bug, §6) is not contained by the sandbox. But the App Sandbox is **fundamentally incompatible** with Uzume's three core mechanisms:
- the **global Core Audio process tap** needs to see all processes' audio — the sandbox cannot grant that;
- **Apple Events** to arbitrary music apps (Apple Music / Spotify, for now-playing metadata) need per-target temporary-exception entitlements the sandbox discourages;
- **arbitrary local-file open** (LF.4–LF.6: any `.m4a/.mp3/.flac/.m3u` the user picks) works today via direct paths; under the sandbox it would require user-selected-file scope + security-scoped bookmarks throughout.

**Partial sandboxing?** Not viable as a quick win: the global tap alone defeats it, and the file/Apple-Events paths would each need a non-trivial rework for marginal benefit on a single-user local app. Revisit only if a future model drops the global tap.

**Decision.** Document the rationale. **No follow-up filed** (partial sandboxing does not look viable). If distribution hardening (§3) later wants defense-in-depth, the tradeoff can be re-opened then.

## 3. Hardened runtime + notarization

**Current posture (CLEAN.2.5a, 2026-06-15 — `UzumeApp.xcodeproj/project.pbxproj` + `UzumeApp/UzumeApp.entitlements`).** Hardened runtime is **ON for the app target's Release config** — `ENABLE_HARDENED_RUNTIME = YES` (verified: `codesign -dv` on the Release product shows `flags=0x10000(runtime)`, `Runtime Version` present). **The Debug config is deliberately left unhardened.** HR enables library validation, and a hardened *test host* refuses to `dlopen` the injected `UzumeAppTests.xctest` bundle — `mapping process and mapped file (non-platform) have different Team IDs` — so HR-on-Debug breaks `xcodebuild test`. HR is a distribution/Release property; scoping it to Release keeps the test suite green and hardens the config that actually ships + notarizes. (Durable learning: the first attempt set HR in `Uzume.xcconfig`, which applies to both configs, and the app-test bundle-load failure forced the Release-only scope.) The outbound-Apple-Events entitlement `com.apple.security.automation.apple-events` was added (entitlements apply to both configs) — the `StreamingMetadata` now-playing bridge (`NSAppleScript` → Apple Music / Spotify) needs it under HR. Signing is still `CODE_SIGN_IDENTITY = "Apple Development"` / `Automatic` / team `2LBTN9PB4Z` — **dev-signed, not yet Developer ID, not yet notarized** (the deferred CLEAN.2.5b half); the dev-signed Release build still carries `get-task-allow` (auto-injected for development certs — it drops out under Developer ID signing in 2.5b, which notarization requires). No `com.apple.security.cs.*` entitlement was added — the tap is TCC-gated and expected to survive HR; one is added only if a real run shows a break.

**Threat / rationale.** Without the hardened runtime + a Developer ID signature + notarization, a build cannot pass Gatekeeper cleanly on a machine other than the dev machine — it blocks the distribution Matt now has on the roadmap. Enabling the hardened runtime is **not** a one-line flip: it restricts code-injection/JIT/loading and **may break the audio tap or the Apple Events bridge**, so it needs a real run (tap still installs, music apps still reachable) plus a Gatekeeper test of a notarized artifact.

**CLEAN.2.5b result (2026-09-29).** Signing team → Plait & Pattern, LLC (`TYK3BXQ5D4`), automatic signing; Developer ID applies at export (`Scripts/ExportOptions.plist`, `method = developer-id`). `Scripts/release.sh` archives (Release, arm64), exports, notarizes and staples the app, builds a DMG, and signs, notarizes and staples the DMG (RUNBOOK §Release build). Verified on `Uzume-0.9.0-4.dmg` (notarization: app `8daff427-95a9-4d94-b3ee-f66c7f7a5cef`, DMG `6805e154-805c-42da-8792-df906b4942d1`, both Accepted):
`codesign --verify --deep --strict` valid and satisfies its Designated Requirement; `Authority=Developer ID Application: Plait & Pattern, LLC (TYK3BXQ5D4)`; `TeamIdentifier=TYK3BXQ5D4`; `flags=0x10000(runtime)`; entitlements exactly `app-sandbox = false` + `automation.apple-events` (**no `get-task-allow`**); `spctl -t exec` → `accepted, source=Notarized Developer ID`; `spctl -t open --context context:primary-signature` on the DMG → `accepted`; `stapler validate` passes on both; `lipo -archs` → `arm64`; `UzumeBuildFlavor = public`. No hardened-runtime exception and no `com.apple.security.cs.*` entitlement was needed; library validation stays on (§4). Verified on the notarized build **0.9.0 (5)** (`Uzume-0.9.0-5.dmg`, notarization app `1dd66074-96dd-46a0-afd6-1968ea612b5d`, DMG `8e3ab065-fecf-4688-a830-a76500c8110c`, all 13 checks PASS) on a fresh standard account with every Uzume permission reset: onboarding → screen access → Quit & Reopen → Spotify scan → Continue → Ready → system-audio question → visuals; Apple Music playlist; local file; relaunch asks nothing. Matt: *"Passes all steps."* Two defects the run surfaced were fixed on the way (BUG-160 Ready never told of the music, BUG-161 crash on Continue), plus BUG-158 (Documents question). The observed permission sequence is UX_SPEC §3.3a.

**Decision — CLEAN.2.5 SPLIT (Matt, 2026-06-15).** Split because Developer ID signing + notarization require a **paid Apple Developer Program membership** the project does not currently have.
- **CLEAN.2.5a (done + verified, this increment):** enable the hardened runtime (Release config) + add the Apple Events entitlement; Release build + sign verified green (`-o runtime`, entitlement present on the binary); Debug `xcodebuild test` suite stays green. **Manual runtime gates VERIFIED 2026-06-15** (Matt, Mac mini, hardened Release build, session `2026-06-15T22-45-34Z`): (i) launches under HR ✅; (ii) `.systemAudio` tap installs + delivers audio under HR ✅ — green @ **−6 dBFS**, 11,425 live-energy frames in `features.csv` (the brief startup "red/silent" is the documented pre-playback artifact, not a fault); (iii) Apple Events ✅ **accepted** — the now-playing AppleScript poller ran under HR without fault and the entitlement is verified on the binary, but this Spotify-prefetched session did not independently isolate it (displayed metadata came from the Spotify Web-API plan; per-poll AppleScript results aren't persisted), so it's accepted as satisfied-by-construction per Matt's call. Spotify connection also confirmed working on the primary-dir build (the worktree build had an empty `SPOTIFY_CLIENT_ID` — gitignored `Uzume.local.xcconfig` absent in worktrees).
- **CLEAN.2.5b (deferred, blocked on paid membership):** switch `CODE_SIGN_IDENTITY` → `Developer ID Application`, notarize (`xcrun notarytool submit --wait` + `xcrun stapler staple`), and Gatekeeper-test on a clean machine/account (`spctl --assess` + a real first launch). Mechanical once the cert + notarization key exist. Keep library validation **on** (§4).

## 4. Library validation

**Current posture (verified — entitlements + pbxproj).** No `com.apple.security.cs.disable-library-validation` declared. Uzume links Apple frameworks (Metal, AVFoundation, Accelerate, MPSGraph, MusicKit, …) and SPM **static** libraries — it does **not** load third-party or unsigned dylibs at runtime.

**Threat / rationale.** `disable-library-validation` is only needed when an app loads code signed by a different team (plugins, unsigned dylibs); disabling it weakens the binary. Uzume loads none, so it should never disable it.

**Decision.** Document — **not required, no fix**. Verified under hardened runtime (CLEAN.2.5a): library validation is on by default and was **left on** — no `disable-library-validation` declared, confirmed on the signed binary (`codesign -d --entitlements`).

## 5. `uzume://` OAuth callback

**Current posture (verified — `UzumeApp/Services/SpotifyOAuthTokenProvider.swift` `handleCallback`, `UzumeApp/UzumeApp.swift:104` `.onOpenURL`).** The custom URL scheme `uzume://spotify-callback` is the OAuth redirect target. The callback is validated at two layers:
- `.onOpenURL` dispatches only when `url.scheme == "uzume"` **and** `url.host == "spotify-callback"`;
- `handleCallback` re-checks scheme + host, then enforces the **`state` CSRF/replay guard** — the returned `state` must equal the `pendingState` sent in the authorize URL; a nil `pendingState` (no login in flight) is rejected as possible CSRF/replay (CLEAN.2.2.3a). Missing-code / denied-auth paths fail closed.

**Threat / rationale.** Custom URL schemes can be invoked by any app, so a callback handler is an injection surface: a malicious `uzume://spotify-callback?code=…` could try to inject an auth code or replay an old one. The `state` round-trip + nil-pending rejection close the CSRF/replay class; PKCE (CLEAN.2.1) means an injected code is useless without the matching verifier.

**Decision.** Document — **mitigated by CLEAN.2.2**. No gap found, no fix filed.

## 6. Local-file open path

**Current posture (verified — `UzumeEngine/Sources/Session/M3UParser.swift`, `UzumeApp/UzumeApp.swift:215` `dispatchFileURL`, `LocalFilePlaybackProvider`).** Opening a file (Finder double-click / `open -a` / drag / Recents) routes by extension to the local-file or m3u or folder entry point. The `.m3u`/`.m3u8` parser is **defensive**: maps the file (`mappedIfSafe`), strips a UTF-8 BOM, decodes UTF-8 or **throws** `malformedUTF8`, normalizes CRLF, skips comments, resolves each entry, **readability-checks** each (`isReadableFile`), silently skips unreadable entries, and **throws** `noEntriesResolved` if none resolve. Audio bytes are decoded by **AVFoundation** (`AVAudioFile`), Apple's framework decoders.

**Threat / rationale.** Two surfaces: (a) **malformed media** fed to AVFoundation decoders (mp3/m4a/flac) — the standard audio-decoder attack surface, mitigated by Apple's hardened decoders and the fact that the file came from the user's own disk; (b) **arbitrary path resolution in `.m3u` entries** — a hostile playlist naming `/Users/you/.ssh/id_rsa` or `../../etc/passwd`.

The consequence of (b) was always bounded, which is why it was P3 not higher: the local-file path has **no network egress** (§7), so even a successfully-opened file's contents have nowhere to go.

**Decision — FIXED 2026-08-07 (BUG051.1).** `M3UParser` canonicalizes every resolved entry (`standardizedFileURL` on all three branches, `file://` strings that aren't file URLs rejected) and filters against `allowedAudioExtensions` = `m4a`/`mp3`/`flac` **at the parser boundary**, so a hostile entry is never stat'd or handed onward and the playlist throws `noEntriesResolved`. `LocalFileMenuCommands.allowedExtensions` aliases that constant so the app- and engine-side lists cannot drift. **No containment-to-root guard was added** — absolute and `../`-relative entries pointing outside the playlist's directory are how real exported playlists address a music library; the extension allow-list closes both attack examples without breaking them. Regression: `M3UParserTests.parse_rejectsNonAudioAndTraversalEntries` + `…_allowsTraversalToRealAudioOutsidePlaylistDir`.

## 7. Secrets at rest + no-telemetry

**Current posture (verified — `UzumeApp/Services/SpotifyOAuthTokenProvider.swift`, `UzumeApp/Uzume.xcconfig`, `UzumeApp/Info.plist`).**
- **OAuth tokens** (Spotify access + rotating refresh) live in the **Keychain** (CLEAN.2.1/2.2). Keychain save failures are logged, not swallowed (CLEAN.2.2.3c).
- **No client secret anywhere** — PKCE uses only the public `SPOTIFY_CLIENT_ID`, injected from the **gitignored** `Uzume.local.xcconfig`; the checked-in `Uzume.xcconfig` holds an empty value and a comment forbidding a real one (CLEAN.2.1's whole point — do not regress).
- **No telemetry / no cloud.** On-device ML; the only outbound traffic is metadata: Spotify / Apple Music, and each track's title + artist to the iTunes Search and MusicBrainz APIs (BR.16). Tapped audio and session recordings (`~/Documents/uzume_sessions/`) are **never uploaded** — `SessionRecorder` has no `URLSession`/network path (verified).

**Threat / rationale.** Token theft (Keychain is the right at-rest store, ACL-scoped to the app); secret leakage from a shipped binary (eliminated — none is embedded); and data exfiltration (structurally minimal — there is no telemetry channel for tap audio or recordings to escape through).

**Decision.** Document — **posture strength, no fix**. The invariant to protect: never check a secret into `Uzume.xcconfig`; never add a telemetry/upload path for tap audio or session recordings.

---

## 8. Spotify window reading (SCAN, D-260)

**Current posture (verified — `UzumeApp/Services/SpotifyScanServices.swift`).** A playlist scan is started by the user (**Start scan**) and runs only while the floating scan panel is open. `SpotifyWindowFrameSource` builds its `SCStream` with `SCContentFilter(desktopIndependentWindow:)` on the largest on-screen window owned by `com.spotify.client` — **one window, never a display** — at up to 4 frames a second, cursor hidden, no audio. Each frame is converted to a `CGImage`, read by `PlaylistScreenReader` (Apple Vision, on device), and released when the handler returns; **nothing is written to disk or sent anywhere**. The stream stops on Done, Cancel, Esc, when the scan completes, or when Spotify quits. Permission is re-checked with `CGPreflightScreenCaptureAccess()` at scan start. Screenshots dropped on the Spotify view are read in memory the same way and never copied.

**What it does not do.** No request to any Spotify server (the scan replaces the Web API path precisely to avoid it); no Accessibility API, no synthetic scrolling or key presses, no AppleScript UI scripting — the user scrolls. The only network traffic the scan causes is the existing iTunes Search lookup for previews (§7, `ITunesRateLimiter`); MusicBrainz is asked only while a song plays (the live metadata pre-fetch).

**Threat / rationale.** Reading pixels is a real privacy surface: another window, a notification, or a private playlist name can be in frame. Mitigations: the single-window filter (other apps' windows are never captured, even when overlapping), user initiation, the visible panel for the whole duration, in-memory only, and on-device recognition. What is read from the Spotify window — track titles, artists, durations, the playlist name — goes into the session exactly as a pasted link's tracks did.

**Decision.** Document — consent-gated, user-initiated, narrowest filter ScreenCaptureKit offers.

## Filed follow-ups

| ID | Sev | What | Why filed, not applied here |
|---|---|---|---|
| **CLEAN.2.5a** | — | **Done (2026-06-15)** — hardened runtime enabled (app-target-scoped) + `automation.apple-events` entitlement; build + sign verified (`-o runtime`). Runtime gates (tap + Apple Events under HR) pending Matt's Mac-mini run. | The deliberate flip 2.4 deferred — applied here with a build behind it (§3). |
| **CLEAN.2.5b** | — | **Done (2026-09-29)** — Developer ID signing + notarization + stapled DMG via `Scripts/release.sh`; library validation on (§3, D-261). | Unblocked by the Plait & Pattern membership. |
| **BUG-051** | P3 | **Done (2026-08-07, BUG051.1)** — extension allow-list + path canonicalization on resolved playlist entries, applied at the parser boundary. | Filed here as defense-in-depth; fixed in its own small increment (§6). |

No fix was filed for §2 (partial sandbox — not viable), §4 (library validation — not required), §5 (OAuth — mitigated), §1/§7 (core mechanism / posture strength).

## How each claim was verified (2026-06-15)

- Sandbox / entitlements — read `UzumeApp/UzumeApp.entitlements` (only `app-sandbox = false`).
- Hardened runtime / signing — `grep` for `ENABLE_HARDENED_RUNTIME` / `disable-library-validation` across pbxproj + entitlements + xcconfig (zero hits); read signing keys in `project.pbxproj`.
- Tap scope — read `SystemAudioCapture.buildTapDescription`.
- Recorder honesty — read `SessionRecorder+Video.swift` (`MTLTexture` source) + `SessionRecorder.swift` output dir; confirmed no network in `SessionRecorder*.swift`.
- OAuth callback — read `SpotifyOAuthTokenProvider.handleCallback` + `UzumeApp.swift` `.onOpenURL`.
- Local-file path — read `M3UParser.swift` + `dispatchFileURL`.
- Secrets — read `Uzume.xcconfig` (empty client ID, no secret) + `Info.plist`.
