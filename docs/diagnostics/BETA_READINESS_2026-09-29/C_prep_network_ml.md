# Lane C: session preparation, networking, caching, ML inference

Read-only review of the worktree at `efb3eed3`. Every finding below comes from reading the code path end to end. Where a number comes from a doc measurement, the doc is named. The paths are release-reachable: the Spotify flow in Release is screen scan only (`ConnectorPickerView.swift:146-151`), and Apple Music goes through AppleScript, not MusicKit.

## Findings (most severe first)

### C1: On a playlist longer than about 64 tracks, prepared tracks are evicted from memory before they play
- **Severity:** P1 · **Confidence:** VERIFIED · **Effort:** S–M
- **Where:** `StemCache.swift:176`: `public static let defaultMaxEntries = 64`. Stores are evicted in LRU order at `:281-286`. `VisualizerEngine+Orchestrator.swift:83-89` builds the plan only from tracks that are still cached: `guard var profile = cache.trackProfile(for: identity) else { return nil }`.
- **Scenario:** The tester runs a 120-track Spotify playlist and presses Start now. Streaming preparation is never paced (`paceIfPlaying` only runs on the local walk), so it runs about 30× faster than playback. By the time the tester reaches track 5, tracks 5–56 have been evicted. Those 52 tracks, about 3 hours of listening, then play:
  - with no pre-separated stems and no BeatGrid at track start (`resetStemPipeline` misses the cache and falls back to live, reactive analysis);
  - without a planned scene, because every `extendPlan()` rebuild drops them;
  - with "52 tracks not yet prepared" shown, although they were prepared.

  The track currently playing also drops out of the plan once 64 more tracks have been stored after it. The CLEAN.3.5 notes say evicted tracks get "re-prepared on next demand". No code does that: `prepare(tracks:` is only called from `SessionManager.swift:295`.
- **Fix direction:** The 7 MB-per-track `stemWaveforms`, which is what forces the cap, has no reader at playback. The cache-hit branch in `VisualizerEngine+Stems.swift:681-726` reads the stem features, grids, series and profile, never the waveforms. Drop the waveforms from the in-memory entry (and from disk) and remove the cap, or cap by bytes and never evict tracks that have not played yet.

### C2: If any of the first three tracks fails, "Start now" never appears until the whole playlist is prepared
- **Severity:** P1 · **Confidence:** VERIFIED · **Effort:** S
- **Where:** `SessionManager+Readiness.swift:64`: `if case .ready = status { countsForPrefix = true } else { countsForPrefix = false }`. A single failed or partial track breaks the three-track prefix. The only escape banner needs zero tracks ready: `PreparationErrorViewModel.swift:159` `if firstTrackReadyDate == nil, elapsed > 120`.
- **Scenario:** On the four SCAN bench playlists, about 8 % of rows get no verified preview (`SCAN_FEASIBILITY_2026-09-28.md`: 92.0 % identification). That gives roughly a 22 % chance, per Spotify session, that one of rows 1–3 fails. The tester then sees "37 heard", no Start button and only Cancel until every track finishes: about 3.5 min for 40 tracks (DS.4 TIMING), about 10 min for 100, and 25–30 min for 300 (see C5). Nothing on screen explains the wait.
- **Fix direction:** Count the first three **usable** tracks and skip failed ones. Or let the timeout banner and its "start reactive" hatch also fire when some tracks are ready but the prefix is not.

### C3: Background preparation corrupts live stem analysis and live mood during playback (BUG-031 class, not covered by that fix)
- **Severity:** P1 · **Confidence:** VERIFIED for the mechanism; how visible it is has not been measured · **Effort:** S
- **Where:**
  - `VisualizerEngine+InitHelpers.swift:313-314` passes the engine's live `StemAnalyzer` and `MoodClassifier` into `SessionPreparer`. The doc comment at `:277` says it shares them "to avoid double-loading the ML weights"; neither object has weights.
  - `SessionPreparer+Analysis.swift:90-96` runs about 430 `analyzer.analyze` frames per prepared track on that shared analyzer, with no reset. `:330` runs about 1,300 `classify` calls per track on the shared classifier.
  - The live path uses the same two instances: `VisualizerEngine+Audio.swift:458` and `:513`.
  - The team already recognised the hazard in `LocalFilePreparationPipeline.swift:210-211`: *"A FRESH `StemAnalyzer`, never the session's… the shared instance is live-playback state."* That fix was applied only to the stem-series sweep.
- **Scenario:** A streaming session starts early, which is the normal case, and preparation continues behind playback, landing a track every few seconds for minutes.
  - Each landing pushes 430 frames of another song through the live AGC. At `agcRateModerate = 0.992` per frame (`BandEnergyProcessor.swift:162`), about 97 % of the AGC's level is replaced. The deviation EMA, with a time constant of about 10 s, moves about 38 %.
  - Live `bass`/`drums` energy and `*Dev` values, the product's primary visual drivers, therefore jump or go flat for about 1–2 s after every background landing, unrelated to the music. Live valence/arousal (`setMood`) snaps to the other song's mood.
  - In the other direction, each cached `stemFeatures` snapshot and `stemEnergyBalance` starts from whatever state the live analyzer was in.
- **Fix direction:** Give the preparer its own `StemAnalyzer` and `MoodClassifier`. Both are cheap, and the classifier's weights are static. Confirm with one replay that compares stem traces with preparation running and not running.

### C4: The iTunes rate limiter busy-spins when its task is cancelled, and steals slots
- **Severity:** P2 · **Confidence:** VERIFIED · **Effort:** S
- **Where:**
  - `ITunesRateLimiter.swift:46-63` loops `while true { … try? await Task.sleep(…) }`. Once the task is cancelled, `Task.sleep` throws at once, `try?` swallows the error, and the loop spins until a slot frees, which can take up to 60 s.
  - The metadata fetch hits this routinely: `MetadataPreFetcher.swift:185-193` has a 3 s timeout and then calls `group.cancelAll()`, while `ITunesSearchFetcher.swift:35` waits on the shared limiter.
- **Scenario:** Every streaming preparation longer than about 10 tracks saturates the 20-requests-per-minute window. From then on, most metadata fetches time out after 3 s while queued, and each one spins a CPU core; up to 4 run at once because of the prefetch window. This matters on an 8 GB M1 Air (heat, battery, a starved cooperative pool).
  - The cancelled fetch still takes a slot and fires a cancelled request, so the "best-effort 3 s" metadata still costs a full slot per track.
  - `withTaskGroup` waits for the spinning child to finish, so the track's fetch stays blocked until then.
  - The same spin happens for up to 4 prefetch lookups when the tester cancels mid-preparation, and those stolen slots slow the next session's first tracks.
- **Fix direction:** Check `Task.isCancelled` and return or throw from `acquire()` without recording a slot. Make the sleep cancellation-aware.

### C5: Preparation throughput is capped at about 7–10 tracks per minute by the iTunes window, and there is no cap on track count
- **Severity:** P2 · **Confidence:** VERIFIED; the arithmetic matches the DS.4 measured mean of 5.56 s per track · **Effort:** S
- **Where:**
  - The preview lookup costs 1 request per track, or 2 for scanned rows that need the title-only retry (`PreviewResolver.swift:143-144`).
  - The metadata lookup costs 1 more (`ITunesSearchFetcher`) and asks for the same catalog data the preview lookup already fetched (`primaryGenreName`, `trackTimeMillis`).
  - Neither the streaming path nor Apple Music limits the track count. Apple Music's "current playlist" can be the whole Library.
- **Scenario:** A 300-track playlist needs about 30–45 min to prepare fully. An Apple Music tester playing from Songs (the whole Library) gets thousands of tracks queued and a limiter kept saturated for hours. Combined with C2, the wait is the whole playlist.
- **Fix direction:**
  - Take genre and duration from the preview-lookup response and drop the iTunes metadata call, which halves traffic.
  - Cap or window the tracks queued for preparation, for example the next N tracks.
  - Pace streaming preparation after playback starts, as the local path already does.

### C6: Apple Music with Automation permission denied is a dead end with the wrong message
- **Severity:** P2 (P1 for testers who use Apple Music first) · **Confidence:** VERIFIED · **Effort:** S
- **Where:**
  - `PlaylistConnector.swift:246-253` swallows every AppleScript error except `-600` and `-1728`, logs it at debug level and returns `nil`. That includes `-1743` (Automation denied).
  - `nil` becomes `[]`. `AppleMusicConnectionViewModel.swift:112` maps an empty list to `.noCurrentPlaylist` and retries every 2 s forever.
  - The `.permissionDenied` view, which has an "Open System Settings" button (`AppleMusicConnectionView.swift:134`), is never set. The view model's own header records this as a TODO.
- **Scenario:** The tester clicks "Don't Allow" on the macOS prompt. macOS never asks again. From then on they see "Start a playlist in Apple Music, then come back. Checking every 2 seconds…" while a playlist is playing, with no way to recover from inside the app.
- **Fix direction:** Map `-1743` to a thrown `.permissionDenied` and route it to the view that already exists.

### C7: A transient iTunes failure permanently marks a track "Preview not available"
- **Severity:** P2 · **Confidence:** VERIFIED · **Effort:** S–M
- **Where:**
  - `PreviewResolver.swift:185`: a non-200 response or a thrown error returns `nil`. It is uncached, but `SessionPreparer.swift:552-555` still turns it into a terminal `.failed("Preview not available")`.
  - The only retry is `resumeFailedNetworkTracks`, which runs only on an offline-to-online flip while the session is still `.preparing` (`NetworkRecoveryCoordinator`). No retry happens after Start now, and none for 429, 403, 5xx or a 10 s timeout on a slow link.
  - A captive portal (HTTP 200 with an HTML body) goes through `parseMatch` as `nil` and is **cached** as "no preview", so even the recovery path cannot fix it.
- **Scenario:** On hotel or café Wi-Fi, or during an iTunes hiccup, scattered tracks fail for the rest of the session. One of those failures in rows 1–3 triggers C2.
- **Fix direction:** Retry with bounded backoff inside the resolver for 429, 5xx and timeouts. Treat a 200 response that is not JSON as transient. Allow a retry after `.ready`.

### C8: Non-US testers are matched against the US catalog only
- **Severity:** P2 · **Confidence:** VERIFIED that no country parameter is sent; the miss rate is PLAUSIBLE · **Effort:** S
- **Where:** No `country` parameter is sent anywhere. `PreviewResolver.swift:197-201`, `ITunesSearchFetcher.swift:39` and `StreamingArtworkURLResolver.buildITunesRequest` all omit it, and iTunes Search defaults to `US`.
- **Scenario:** A UK, JP or DE tester's regional releases, local-language titles and region-exclusive versions are missing or differently titled in the US storefront. More rows fail the verified scan match, which means more reactive tracks and more C2 dead-waits.
- **Fix direction:** Send `country` from `Locale.current.region`, falling back to US on a miss.

### C9: Long local files: memory scales with file length, with no cap
- **Severity:** P2 · **Confidence:** VERIFIED that no cap exists; the peak figures are PLAUSIBLE arithmetic · **Effort:** M
- **Where:**
  - `SessionTypes.swift:230-239` decodes the whole file into one full-length `AVAudioPCMBuffer` plus a mono copy.
  - Whole-file analysis then makes further resampled copies: Beat This! at 22.05 kHz, PANNs at 32 kHz, and MIR or the stem series whenever the file is not 44.1 kHz.
- **Scenario:** Dropping in a 1-hour DJ mix at 44.1 kHz stereo costs about 1.3 GB for the decode buffer plus 0.64 GB mono, before the analysis copies. A 96 kHz file costs about twice that. On an 8 GB Mac this means heavy swap during preparation.
- **Fix direction:** Decode in chunks for the stem-series sweep, or cap whole-file analysis by duration and fall back to preview-length analysis past the cap.

### C10: Missing or corrupt ML weights degrade silently
- **Severity:** P2 · **Confidence:** VERIFIED · **Effort:** S (overlaps the release/build lane)
- **Where:**
  - Weights are gitignored and fetched only by `Scripts/fetch_weights.sh`. CI runs that script, but the Xcode project has no script phase (none in `project.pbxproj`), so an Archive made from a checkout without weights still builds.
  - At runtime, `loadStemSeparator` returns `nil` and `NullStemSeparator` throws on every call. `DefaultBeatGridAnalyzer` also becomes `nil`.
- **Scenario:** Every streaming track ends up `.partial("Stems unavailable")`, so the prefix never qualifies and Start now never appears (C2). After the whole playlist, the session reaches `.ready` with nothing cached and plays fully reactive. The tester is never told why.
- **Fix direction:** Add a build-phase gate that fails when a weight file is missing. Surface a one-time "analysis unavailable" notice.

### C11: The "all tracks failed" recovery screen is effectively unreachable
- **Severity:** P3 · **Confidence:** PLAUSIBLE; the ordering is inferred · **Effort:** S
- **Where:** When the last track fails, `SessionManager.swift:332` sets `state = .ready` unconditionally, including at `.reactiveFallback`. `ContentView` swaps `PreparationProgressView`, which hosts the `RecoveryScreen`, for `ReadyView` in the same tick.
- **Scenario:** Behind a captive portal, with iTunes blocked, or with every lookup failing, the tester lands on a normal "Ready" screen instead of "couldn't prepare, pick another playlist or start reactive".
- **Fix direction:** Hold `.preparing` or show the recovery screen when readiness is `.reactiveFallback`.

### C12: Local-file track changes read the whole cache entry from disk on the main thread just to get the artwork
- **Severity:** P3 · **Confidence:** VERIFIED · **Effort:** S
- **Where:** `VisualizerEngine+LocalFilePlayback.swift:599`, a `@MainActor` method, calls `cache.load(hash:)`. That reads all four stem files (about 7 MB), the stem series and the JSON, while holding the `PersistentStemCache` lock. The background walk holds the same lock through each `store` (tens of MB of writes) and `evictToMaxBytes`, which enumerates every entry. `refreshLocalFileCacheBytes()`, also on main, enumerates the cache too.
- **Scenario:** A track advance during the background walk stalls the main thread for tens of ms, and longer on a slow or nearly full disk. This is the only main-thread disk I/O I found anywhere near preparation. Its bounded cost makes it a weak BUG-081 candidate at best.
- **Fix direction:** Add an artwork-only accessor and call it off the main thread. With C1's fix, stop persisting the unused waveforms.

### C13: Other iTunes and MusicBrainz traffic ignores rate limits
- **Severity:** P3 · **Confidence:** VERIFIED · **Effort:** S
- **Where:**
  - `StreamingArtworkURLResolver` calls iTunes Search outside `ITunesRateLimiter.shared`. That contradicts the PUB.6 claim that "one shared window covers all itunes.apple.com callers". It also caches 429s and network errors as "no artwork" for the session, and it takes the first result (`limit=1`, the BUG-152 class), so wrong cover art is possible.
  - `MusicBrainzFetcher.swift:3` claims "Rate limit: 1 request/second", but no throttle exists. The prefetch window of 4 bursts requests, and MusicBrainz answers bursts with 503 and IP throttling. The metadata is best-effort, so this only loses the time-signature override.
  - `ITunesSearchFetcher.swift:38` encodes queries with `.urlQueryAllowed`, which leaves `&` and `+` unescaped. "Simon & Garfunkel" is truncated at the `&`.
- **Fix direction:** Route artwork through the shared limiter and reuse the preview match's catalog names. Add a 1 req/s gate for MusicBrainz. Build the metadata query with `URLComponents`.

### C14: Cancellation leaves work running into the next session
- **Severity:** P3 · **Confidence:** VERIFIED · **Effort:** S
- **Where:**
  - `resumeFailedNetworkTracks` (`SessionPreparer.swift:735-742`) awaits the original loop and then **starts a new loop even if the session was cancelled in the meantime**. `prepare(tracks:)`, unlike `prepareLocalFiles`, does not cancel an existing `preparationTask`.
  - On cancel, the in-flight detached analysis finishes and writes `.ready` for the old track into the new session's `trackStatuses`. That inflates `preparedTrackCount`, sets `firstTrackReadyDate`, and suppresses the all-failed rule.
  - Retries run in `Set` order, not playlist order ("sortedCandidates" is not sorted).
- **Fix direction:** Guard writes by session generation. Cancel any existing `preparationTask` in `prepare(tracks:)`. Sort the candidates by playlist index.

### C15: Apple Music track durations may be lost in comma-decimal locales
- **Severity:** P3 · **Confidence:** PLAUSIBLE · **Effort:** S
- **Where:** `PlaylistConnector.swift:173` converts with `((get duration of t) as text)` and reads it back with `Double(durStr)`. If AppleScript formats the number with the system decimal separator ("243,5"), every duration becomes `nil`. The duration feeds plan timing and energy-curve mapping (`energyLevelsPerSecond(trackDuration:)`).
- **Fix direction:** Return the duration as an integer number of seconds from AppleScript, or parse with a locale-independent formatter. Needs a one-minute check on a German-locale Mac.

## Reviewed and healthy
- The BUG-031 fix holds. `StemSeparator.separate` locks the whole input→predict→output section and returns stems by value. The warm-up, live and preparation separations are serialised by that lock, and `StemSeparatorConcurrencyTests` is still in place.
- Beat This! and PANNs inference are lock-guarded. Preparation and live use separate Beat This! instances, except on the local path, where the shared one is locked.
- The generation guards (`streamingSessionGen`, `localFileSessionGen`) stop a stale preparation completion from hijacking a new session's plan or state (BUG-032).
- Duplicate tracks (BUG-030) are tolerated.
- `PreviewDownloader` deletes its temp files with `defer`. Container sniffing is by magic bytes.
- `PersistentStemCache`:
  - a schema mismatch counts as a miss and is overwritten at the same hash;
  - metadata is written last, atomically, and partial entries are rejected;
  - the 500 MB LRU cap also bounds stale-schema (pre-v17) entries, so version bumps do not grow the disk without limit.
- `StreamingArtworkDiskCache` is an actor, capped at 100 MB in `Caches/`, with mtime-based LRU.
- Weight integrity is checked with SHA-256 at load, so corrupt weights fail loudly rather than giving silently bad stems. The UX of that failure is C10.
- Offline during preparation shows a full-screen RecoveryScreen. Recovery is debounced (1 s + 2 s) and capped at 3 attempts.
- The key-correlation Pearson calculation is guarded against zero variance. The silence path is exercised by the preparation warm-up.
- The work on the main thread during streaming preparation is bounded: status publishes are O(N), and the planner is a linear walk over at most 64 tracks.

## Could not verify
- **BUG-081:** I found no main-thread-blocking candidate in the streaming preparation path. C12 is local-file only and costs tens of ms. C4's spin burns pool CPU, not the main thread. A `sample` taken during the hang is still the missing evidence.
- **C3:** the visible size of the effect. It needs one replay or live A/B with preparation running and not running.
- **C8:** the real miss rate for UK, JP and DE catalogs, and whether US preview URLs play everywhere. This needs a non-US tester.
- **iTunes enforcement:** what iTunes actually returns over the limit (403 or 429), and how strictly it enforces 20 per minute.
- **NSAppleScript threading:** whether running `NSAppleScript` on a detached task, concurrently with the now-playing AppleScript bridge, is thread-safe.
- **C9:** peak memory numbers. They need an Instruments run with a long file.
- **C15:** AppleScript's real-to-text locale behaviour.
- **C10:** whether the beta release build actually contains the weights. That belongs to the release/build lane.
