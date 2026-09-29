# Lane H: Build, CI, test health, release engineering (beta readiness, 2026-09-29)

**Read this first.** Another session is doing the release work right now. It is on branch **`clean-2-5b`**, checked out in worktree `.claude/worktrees/clean-2-5b-prompt-bf3356`. The branch is **local only (not on origin) and not in `main`**. It has `Scripts/release.sh` + `ExportOptions.plist`, the CLEAN.2.5b decision (Developer ID DMG, **macOS 15+, Apple silicon only**, team Plait & Pattern `TYK3BXQ5D4`), version 0.9.0, `NSAudioCaptureUsageDescription`, BUG-157/158 and DIST-LIM. It also has an uncommitted `BuildFlavor` ("public" build: no session recording). It has already produced notarized DMGs: builds 2–3 show `status: Accepted` for both the app and the DMG, and build 4 was being made while I read. My findings cover `main` **and** that branch. I only read it and changed nothing.

## Direct answers

1. **Release procedure.** `main` has none. It is still `MARKETING_VERSION 1.0`, build 1, "Apple Development", team 2LBTN9PB4Z, with no ARCHS. The branch has one working command: archive → Developer ID export → notarize + staple the app → DMG → sign, notarize and staple the DMG → verify. The paid membership **is** in place now (the CLEAN.2.5b decision: Plait & Pattern, LLC). Still missing: the upload to GitHub Releases (the script says so and leaves it manual), any link between a build and its commit (**no git SHA is embedded anywhere**), a durable copy of the dSYMs, and any tests or launch check on the artifact before it ships (H2, H5, H6).
2. **Updates.** No Sparkle, no version check, no expiry, and the Help menu has nothing in it. Testers get fixes only by going back to the download page (H4).
3. **Crash and diagnostic reporting.** There is none. The public flavor switches the session recorder off, and nothing replaces it (H3).
4. **Bundle contents.** Measured on the notarized build 3: app **180 MB**, DMG **164 MB**. The ML weights are **167 MB (93 %)**: exactly the 482-file manifest plus `SHA256SUMS`, with `panns_mobilenetv1` 23 MB, `beat_this` 8.4 MB and Open-Unmix most of the rest. Shaders and sidecars are about 2 MB, all shipped as `.metal` source. Kagura's CMU clips are 0.7 MB, the binary 7.7 MB. **Not in the bundle:** test fixtures, reference images, FF.R2 prints (none appear anywhere in git history), dev CLIs, or the `Diagnostics` module. Two things are missing that should ship: the third-party license notices (H9). `SPOTIFY_CLIENT_ID`: in Release, paste-a-link is compiled out (`ConnectorPickerView.swift:148–152`, `#if DEBUG`), so a build without `Uzume.local.xcconfig` loses nothing for testers. The notarized build still embeds the builder's client ID, and the OAuth actor and `uzume://` scheme are still live (H13).
5. **Architecture and OS.**
   - On `main`, ARCHS is the default, so a Release archive would be universal. That fails, because `Float16` does not exist on x86_64 (it is used in ML and the renderer).
   - The branch sets `ARCHS=arm64`. macOS then refuses the app cleanly on Intel with the system's "not supported on this type of Mac" message.
   - Availability is healthy. There are only `#available(macOS 14.2)` guards and no macOS 26-only APIs, and Swift enforces availability at compile time. The runtime risk is outside the compiler's reach: shaders are compiled from source by the tester's own OS (H1).
   - **Nothing has run on macOS 14 or 15.** DIST-LIM: "only macOS 26 has been run". No doc records a Sonoma or Sequoia test.
6. **CI.**
   - The fast gate runs about **220 of about 2,700 engine tests (~8 %)** and **0 of about 625 app tests**.
   - It never runs: Release config, Metal/GPU (including the shader-compile gate), licensed fixtures, perf, TSan, or `check_blocking_calls_under_lock.sh`.
   - `main` is protected: `fast-gate` required, `strict: true`, `enforce_admins: false` (checked with `gh api`).
   - The flakes follow one pattern (H12).
7. **Hygiene.**
   - No LFS at build time: zero `filter=lfs` rules, and the weights come from the pinned `ml-weights-v1` tag with checksums.
   - Personal paths appear only in dev scripts (`ftr12_guitar_channel.sh`, `beatbench_copy_fixtures.sh`) and 6 probe tests. None are in production code or `release.sh`.
   - The licensed tempo fixtures are gitignored, so outside contributors cannot run the full suite.
   - 294 branches and 17 worktrees (noted only). Two scripts use the wrong process name (H7).

## Findings (most severe first)

### H1 — Every shader is compiled on the tester's Mac by an OS compiler that has only ever been tried on macOS 26; a failure crashes the app at launch
- **Severity:** P1 (the check is cheap; if it fails, every tester on that OS/GPU is affected) · **Confidence:** PLAUSIBLE. The code path is verified; whether the macOS 15 compiler actually rejects anything is unconfirmed.
- **Where:**
  - `ShaderLibrary.swift:65–69` builds `MTLCompileOptions` and calls `device.makeLibrary(source: combinedSource, …)` on 20 concatenated renderer files.
  - `VisualizerEngine.swift:906–911`: `let lib = try? ShaderLibrary(context: ctx) else { fatalError("Metal initialization failed — …") }`.
  - Presets: `PresetLoader.swift:303–325` compiles every `.metal` it finds. One that fails is simply absent (the file's own comment says so).
  - CI builds no Metal. `PresetLoaderCompileFailureTest` (count 32) runs only in the manual closeout.
- **Failure scenario:** a tester on macOS 15.x, or on a GPU family never compiled against, launches the app. If the OS compiler rejects or chokes on any of the 20 core files, the app hits `fatalError` on **every launch**, with no dialog. If it fails on a scene, that scene silently disappears. First-launch compile time on an 8 GB M1 (65 presets, some 800–2,000 lines) is also unmeasured.
- **Fix direction:** Before Oct 15, launch the notarized DMG in a macOS 15 VM (Virtualization.framework guests have Metal) and on the oldest hardware available. Longer term, precompile a `.metallib` at build time (`-std=metal3.1`, min 15.0), which moves errors to build time and removes the per-OS variance.
- **Effort:** S (VM run) / M (metallib).

### H2 — The release-critical build changes exist only on an unpushed local branch
- **Severity:** P1 (it becomes a P0 if it is not merged before the Oct 12–14 soak) · **Confidence:** VERIFIED
- **Where:**
  - `git branch -r` has no `clean-2-5b`, and `merge-base` says its commits are not in `origin/main`.
  - `main` lacks `NSAudioCaptureUsageDescription`. The branch's own comment on it: "without this key a fresh user's tap installs but delivers silence".
  - `main` also lacks `ARCHS=arm64` (so it cannot archive, see §5), the 15.0 floor, the Developer ID export, `Version.xcconfig`, and the public flavor.
- **Failure scenario:**
  - Any tester build cut from `main` streams silence for new users and cannot even be archived.
  - The branch touches 53 files, and 11 scene lanes are merging before Oct 11.
  - Until it is pushed, one worktree cleanup loses the only copy.
- **Fix direction:** Push the branch and open the PR now. Merge it before the new-scene cutoff so the soak runs on the real release configuration. (This is the owning session's work; flag it to them.)
- **Effort:** S

### H3 — A tester's crash, hang or bug report has no way to reach Matt
- **Severity:** P1 · **Confidence:** VERIFIED
- **Where:**
  - No crash or diagnostic code in the app or engine: no MetricKit, no `NSSetUncaughtExceptionHandler`, no `OSLogStore`, no "report a problem", no `mailto:` or issue link, no Help-menu content.
  - "Copy debug info" (`SettingsViewModel.swift:38–44`) produces three lines: version (build), macOS, GPU.
  - The in-flight `BuildFlavor.recordsSessions` is false for the public build, so no `session.log`, `features.csv` or other session files are written.
  - Developer ID apps get no Apple-forwarded crash reports. Xcode Organizer crash reports come from App Store and TestFlight only.
- **Failure scenario:**
  - BUG-085 (P1, open, hard hang in `nextDrawable`) and BUG-081/060 hit a tester, who force-quits. A force-quit leaves no `.ips` (KNOWN_ISSUES BUG-081).
  - The report reads "it froze" plus three lines.
  - A crash leaves a `.ips` in `~/Library/Logs/DiagnosticReports` that the tester will never find.
  - The beta finds defects and cannot diagnose any of them.
- **Fix direction:** Add a local, consent-first "Report a problem…" that gathers into a zip for the tester to attach:
  - version, build and SHA;
  - Mac model, RAM, displays and audio source;
  - the recent `io.uzume` log lines;
  - `Uzume*.ips` files from DiagnosticReports;
  - optionally, MetricKit hang/crash payloads (on-device, no network; check that MetricKit delivers on macOS).
  Link it from the Help menu and the error cards.
- **Effort:** M

### H4 — No update path: testers stay on old builds and report bugs that are already fixed
- **Severity:** P2 · **Confidence:** VERIFIED
- **Where:** `Package.swift` has 4 Apple dependencies (no Sparkle). The app has no version check or `releases/latest` lookup. `UzumeApp.swift:210–219` adds only "Clear local-file cache" to the app menu.
- **Failure scenario:** 0.9.0 (4) ships on Oct 15 with known issues, and fixes land on Oct 17. Testers never find out, keep filing duplicates against the old build, and bug reports come from a mix of builds.
- **Fix direction:** Pick one:
  - **Minimum:** a "Check for updates…" item that opens the Releases page (no network call by the app), plus the build number shown on the Ended screen.
  - **Better:** Sparkle 2 with an EdDSA-signed appcast, set to ask before checking. This is a product call against the no-telemetry posture.
- **Effort:** S / M

### H5 — Builds cannot be traced back to source, and crash logs cannot be symbolicated
- **Severity:** P2 · **Confidence:** VERIFIED
- **Where:**
  - No SHA in `Info.plist` or in "Copy debug info".
  - `release.sh` (branch) line 73 commits the build-number bump **on local `main`**. CLAUDE.md forbids pushing to `main` directly, and nothing then gets that commit to origin. So far it has been used 3 times, on an unpushed branch.
  - The script checks only the branch name (line 48), not that HEAD equals `origin/main`. It can therefore package local, never-CI'd commits.
  - The dSYMs (51 MB) live only in `build/release/<name>/Uzume.xcarchive` inside whichever checkout ran the script; the rehearsals ran in an ephemeral worktree.
  - Release strips symbols (dwarf-with-dsym).
- **Failure scenario:** A tester sends a `.ips` from 0.9.0 (5). Matt cannot tell which commit it was built from, and the dSYM went with a deleted worktree. The stack is unreadable.
- **Fix direction:**
  - `git fetch`, then refuse unless HEAD equals `origin/main`, or build on a `release/x.y.z-N` branch that gets pushed.
  - Stamp `UzumeGitCommit` into `Info.plist` the same way as `UZUME_BUILD_FLAVOR`, and show it in debug info.
  - Tag the release, and attach the zipped dSYM to a private or draft release, or copy it to a durable folder.
  - Alternatively, derive the build number from `git rev-list --count origin/main`.
- **Effort:** S

### H6 — `release.sh`'s "clean tree" check misses files the engine build picks up anyway
- **Severity:** P2 · **Confidence:** VERIFIED (code path)
- **Where:**
  - `release.sh:46` runs `git status --porcelain --untracked-files=no`. Its comment says "only tracked, pbxproj-registered sources build".
  - That is false for the engine. SwiftPM targets compile every file in their directory, and `.copy("Shaders")`, `.copy("Weights")` and `.copy("Resources/Fonts")` copy whole directories.
  - `PresetLoader.loadFromDirectory` turns **any** `.metal` in that folder into a scene (default descriptor if there is no sidecar).
  - `ShaderLibrary` concatenates **every** renderer `.metal`.
  - Gitignored files are invisible to `git status` altogether.
- **Failure scenario:** the primary checkout is shared by parallel sessions. One of them leaves an untracked WIP `Foo.metal` in `Presets/Shaders`, which ships to testers as a live, uncertified scene. A broken untracked file in `Renderer/Shaders` would instead crash every launch through H1's `fatalError`.
- **Fix direction:** Archive from a fresh `git worktree add --detach <origin/main sha>`, with weights fetched there. That also settles H5's "which commit".
- **Effort:** S

### H7 — The hang-capture script and the closeout's BUG-072 check look for the wrong process name
- **Severity:** P2 (it disables the evidence path for P1 BUG-085 during the beta) · **Confidence:** VERIFIED
- **Where:**
  - `Scripts/capture_hang.sh:18`: `PID=$(pgrep -x UzumeApp | head -1)`.
  - `Scripts/closeout_evidence.sh:207`: `pgrep -x UzumeApp`.
  - The executable is `Uzume`: `CFBundleExecutable => "Uzume"` in the notarized build, and `PRODUCT_NAME = Uzume` since RN.1.
  - RUNBOOK:87–92 documents exactly this trap for `PhospheneApp`.
- **Failure scenario:** On the next freeze, Matt runs `capture_hang.sh` before force-quitting, as KNOWN_ISSUES instructs. It prints "UzumeApp is not running — nothing to sample" and the only stack is lost. The closeout also mislabels a BUG-072 launch failure as a new regression.
- **Fix direction:** Match with `pgrep -x Uzume` or by bundle id.
- **Effort:** S

### H8 — CI never compiles the configuration, architecture or shaders that ship
- **Severity:** P2 · **Confidence:** VERIFIED
- **Where:**
  - `ci.yml` builds with `xcodebuild -scheme UzumeApp … build` (the scheme's Debug) and `swift build` (debug). No script builds Release.
  - Release-only branches (`#else` arms) exist at:
    - `ConnectorPickerView.swift:150`
    - `SpotifyConnectionViewModel.swift:115`
    - `PlaybackView.swift:285`
    - `PlaybackShortcutRegistry.swift:156`
    - `ToastManager.swift:84`
  - Release builds use whole-module optimization with warnings-as-errors.
  - Coverage: 21 `--filter`s plus DocIntegrity, about 220 tests; no app tests; no Metal.
- **Failure scenario:** One of the 11 lanes merges a Release-only compile error, or a `.metal` error that CI cannot see. It surfaces on Oct 14 as a failed `release.sh`, or a scene silently missing from the DMG.
- **Fix direction:** Add a CI step, `xcodebuild -configuration Release ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build` (a few minutes). Before archiving, `release.sh` should run `PresetLoaderCompileFailureTest` + `test_fast.sh`, plus a launch smoke test of the exported app.
- **Effort:** S

### H9 — The DMG ships third-party weights and mocap data without their license notices
- **Severity:** P2 · **Confidence:** VERIFIED
- **Where:**
  - The bundle has no `LICENSE`, `CREDITS` or `Credits.rtf`: I searched the built `.app`.
  - Settings → About shows `"MIT License. © 2026 Uzume contributors."` (`Localizable.strings:363`), while the Finder copyright is now "© 2026 Plait & Pattern."
  - `docs/CREDITS.md:362–376` sets the obligations when shipping: keep the Beat This! MIT notice, the **PANNs CC-BY-4.0** attribution and the CMU acknowledgement, and make CREDITS reachable "from a user-visible surface — e.g. an About panel". The DMG is the first binary distribution, so these obligations are now live.
- **Fix direction:** Generate `Credits.rtf` from CREDITS.md into the app resources (the standard About panel shows it automatically). Bundle `LICENSE`. Reconcile the two copyright lines, which the CLEAN.2.5b decision left to Matt.
- **Effort:** S

### H10 — The macOS 15 / Apple silicon floor does not match the recruited tester population, and 15 has never been run
- **Severity:** P2 · **Confidence:** VERIFIED. This partly duplicates DIST-LIM (untested 15); the recruitment mismatch is new.
- **Where:** The CLEAN.2.5b decision, item 3, sets `LSMinimumSystemVersion` 15.0. The beta brief recruits "macOS 14.x through 26".
- **Failure scenario:** Sonoma testers download 164 MB and get "requires macOS 15.0 or later". Intel owners get "not supported on this type of Mac". Both churn out of the beta.
- **Fix direction:** State "macOS 15+, Apple silicon" in the invite and on the download page. Run at least one macOS 15 session (VM) before Oct 15 (see H1).
- **Effort:** S

### H11 — The public build still writes `~/uzume_diag.log` in the tester's home folder
- **Severity:** P3 · **Confidence:** VERIFIED
- **Where:** `VisualizerEngine+Audio.swift:79–83` (`NSHomeDirectory() + "/uzume_diag.log"`) is opened from `setupAudioRouting` (line 31), which runs in `init` (`VisualizerEngine.swift:1077–1078`), and written once per second. The in-flight `BuildFlavor` gates only the session recorder.
- **Failure scenario:** Every tester finds an unexplained `uzume_diag.log` at the top of their home folder, even though Matt ruled that the public build keeps no diagnostic record. The file is truncated each launch.
- **Fix direction:** Gate it on the flavor, or move it into `~/Library/Logs/Uzume` and include it in H3's report bundle.
- **Effort:** S

### H12 — Test flakes: one repeated pattern, which will recur during the merge crunch
- **Severity:** P3 (not seen by testers) · **Confidence:** VERIFIED (the counts are rough greps)
- **Where:** BUG-137, 143, 150, 154 and 156 are all FIXED.
  - Each surfaced only in the manual full suite, under full-suite load or with a peer session's suite running.
  - Each was a wall-clock wait, or an NSWindow lifetime race, on a saturated main-actor or default-QoS pool.
  - Each was fixed deterministically by awaiting the task.
  - About 135 sleep-based waits remain: 36 `Task.sleep` in engine tests, 79 in app tests, and 20 `Thread.sleep`/`usleep`.
- **Failure scenario:** red closeouts during the Oct 8–14 merge window cost triage time. BUG-156 also records an open product risk: late `.dataPlayedBack` delivery under load.
- **Fix direction:** Sweep the remaining sleeps in the suites that run in closeout, and prefer await-the-task.
- **Effort:** M

### H13 — Developer-only machinery is still live in the public build
- **Severity:** P3 · **Confidence:** VERIFIED
- **Where:**
  - `UzumeApp.swift:38` builds `SpotifyOAuthTokenProvider.makeLive()` on every launch; its init reads the Keychain.
  - `Info.plist` registers the `uzume://` scheme and `SpotifyClientID`. The notarized build embeds the builder's ID from the local xcconfig.
  - `VisualizerEngine.swift:919–924` creates `~/Library/Application Support/Uzume/Presets` for shader hot-reload.
  - Paste-a-link is Debug-only, so none of these are reachable features in Release.
- **Fix direction:** Gate them on `BuildFlavor` along with H11.
- **Effort:** S

### H14 — The GitHub "Latest" release is the ML-weights tarball
- **Severity:** P3 · **Confidence:** VERIFIED (`gh release list`: `ML weights v1  Latest`)
- **Failure scenario:** The DMG name is versioned (`Uzume-0.9.0-N.dmg`), so `/releases/latest/download/…` cannot be a stable link. A pre-release beta never becomes Latest, so a download page pointing at `/releases/latest` lands on the weights page.
- **Fix direction:** Publish the beta as a full release with a stable extra asset name (`Uzume.dmg`), or link the page to the specific tag.
- **Effort:** S

## Reviewed and healthy
- **Notarization pipeline (branch):**
  - notarytool status `Accepted` for app and DMG on builds 2–3; stapled; hardened runtime on.
  - Entitlements are exactly sandbox=false + apple-events, with no `get-task-allow`.
  - The script verifies with `spctl`, `stapler validate` and `lipo`.
  - Credentials live in a Keychain profile and never enter the repo.
- **Bundle hygiene:** the weights match the manifest exactly. No fixtures, reference art, FF.R2 prints, CLIs, `Diagnostics` module or `UZUME_FULL_RAW_TAP` (that is scheme-only env) in the app. The FF.R photos in git are Wikimedia CC and documented.
- **Metal language:** pinned to 3.1 in both compile paths, so it is not an OS-floor risk in itself.
- **Availability:** compile-enforced. Only 14.2 guards; no macOS 26-only API use.
- **CI supply chain:** SHA-pinned actions; pinned Xcode 26.5 and SwiftLint 0.63.2; builds from the resolved files; weights cached on `SHA256SUMS`.
- **Branch protection:** on (`fast-gate`, strict).
- **LFS:** fully out of the build path.

## Could not verify
- macOS 15 runtime behaviour: Metal compile, the Core Audio tap and its permission prompt, SCK window capture for the scan, Sequoia's periodic screen-recording re-confirmation, and the pre-Liquid-Glass look of the DS-phase UI. All of this needs a macOS 15 VM run.
- First-launch shader compile time on an 8 GB M1.
- Whether the `macos-26` runner exposes a Metal device (the CLEAN.5.1 Option-B question).
- Whether MetricKit diagnostics are delivered on macOS for a Developer ID app.
- That Apple does not forward crash reports for Developer ID apps. This comes from Apple's documentation as I know it, not from the repo.
- Behaviour when a tester runs straight from the mounted DMG: there is no translocation or "Move to Applications" handling (grep found none), and the impact is untested.
