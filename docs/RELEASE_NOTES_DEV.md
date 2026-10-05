# Uzume — Developer Release Notes

Internal release notes for the `main` branch. Audience: Matt and Claude Code. Each entry covers one session or a logical batch of increments. These notes complement `docs/ENGINEERING_PLAN.md` (authoritative for what's planned) and `docs/QUALITY/KNOWN_ISSUES.md` (authoritative for open defects).

User-visible release notes for the beta build: [`TESTER_RELEASE_NOTES.md`](TESTER_RELEASE_NOTES.md) (BR.4).

Older entries: `RELEASE_NOTES_DEV_YYYY-MM.md` (one file per month).

**Entry ids are `[dev-YYYY-MM-DD-HHMMSS]`** (UTC time-of-day the entry is written — e.g. `date -u +%Y-%m-%d-%H%M%S`). They are unique by construction, so **never hand-assign sequential `-a`/`-b`/`-c` letters** — parallel sessions independently picking the next letter was a recurring merge-renumbering tax (DOC.8). Older `-a/-b/-c` entries are grandfathered; `rotate_docs.sh` / `DocIntegrityTests` key only on the `YYYY-MM-DD` date, so the suffix format is free. This file is also **`merge=union`** (`.gitattributes`): concurrent appends from two sessions auto-combine instead of conflicting — so keep it **prepend-only prose**, never edit an existing entry in place (union would duplicate it).

---

### [dev-2026-10-01-221600] NACRE.7 — Nacre's colour no longer jumps when the key is unclear (BUG-179)

- **Nacre's colour could jump by up to a third of the colour wheel in one frame** when a song's key was hazy. love_rehab did it 289 times in 30 s. The same recipe caused Understory's colour pop. Nacre now follows the key only when it reads clearly, and its colour moves at most a quarter-turn a second.
- **Clear-key songs keep their colours:** a held key lands within ~5° of where it did before. Saturation is unchanged.
- Nacre is certified, so this waits on Matt's live M7 before it ships.
### [dev-2026-10-01-204615] BUG149.1 — the key readout names the song's key, not F♯ minor (BUG-149)

- **Most songs read F♯ minor; now they read their key.** The old estimate came from a spectrum too coarse to tell neighbouring notes apart, so the music's overall tilt decided it — pink noise read F♯ minor too. On clean chord progressions it was right in 3 of 24 keys; the new one is right in all 24.
- On a thousand songs from Matt's library the readout now spreads the way keys in popular music do (D, G, C, A, E major most often) instead of piling a third of them on F♯ minor. Speech, comedy and noise-based tracks show no key rather than a guess.
- Only the stored key (the preparation readout) changes. The live tonal visuals and mood are untouched.
- Cached songs re-prepare once (cache v18) so they pick up the new key.

### [dev-2026-10-01-195907] BUG178.1 — skipping ahead in a local playlist keeps the track bar and seek (BUG-178)

- **Seek works on every song.** A song preparation had not reached showed a zero-length track bar and ignored seek. The bar now takes the length from the file itself, prepared or not.
- **Preparation follows the listener.** Skip to a song that isn't prepared and it is prepared next, then the songs after it; anything skipped over is picked up afterwards. Until it is ready the visuals stay live-reactive, as before. A listener no longer waits out the paced gap between songs (up to half a song's length) for it to start.
- The plan stays in playlist order, so each song still gets its own scenes and beat grid.
- Matt's re-run of the skip-ahead is pending.

### [dev-2026-10-01-000246] PREP.3 — local playlists prepare almost three times faster (BUG-177 follow-through)

- **Preparing a local playlist is ~2.9× faster.** Bowie's *Low* (11 tracks) took 166.6 s on the Mac mini and now takes 58.5 s (Release, nothing cached). A 40-track playlist of 4-minute songs should now be fully prepared in about four minutes, inside the 5-minute target. "Start now" appears after ~11 s instead of ~31 s. Not yet confirmed in a live session.
- **What scenes see does not change.** Stem values match what they were before the change to float rounding, checked on every frame of three songs, including a 48 kHz file and a 6-minute one.
- **Memory stays flat however long the song** (about 1.2 GB for one track), building on BR.MEM's BUG-177 fix. Four songs at once, which used to run the Mac out of memory, now peak at 3.1 GB.
- Live stem separation during playback got slightly faster (~5 %), not slower.

### [dev-2026-09-30-221341] BR.MEM — long local songs no longer run the Mac out of memory (BUG-177)

- **Found in Matt's first listening session.** Preparing a long local song used memory in proportion to its length — 23 GB for a 9-minute song — so a playlist of long songs made the app stutter, hang and run the Mac out of memory. It now peaks at about 1.5 GB, however long the songs, and prepares slightly faster. What Uzume learns about each song is exactly the same.
- The diagnostic log no longer floods during preparation.

### [dev-2026-09-30-204133] BR.20 — the flash check looks at every part of the screen, and at red (BUG-176)

- **A stricter photosensitivity check.** It used to judge only the whole screen's average brightness. It now also judges every ninth of the screen (WCAG's small-area rule) and saturated-red flashing.
- **Two scenes were over the limit at fast tempos, and are fixed.** Membrane's strike ripple is about 20 % softer (same colours, same ripple). Waveform's bars now fall back over half a second instead of snapping down, a peak-meter look. Both on Matt's call.
- Every other scene passes all three checks.

### [dev-2026-09-30-170203] PROMO.1 — the LinkedIn launch video

- **A 32-second square video is ready to post:** Kagura doing the twist, Ferrofluid Ocean, Cymatic Resonance, Fractal Tree (zoomed out so the whole tree shows) and Fireflies, cut on the song's bars, scored with the first 32 s of *Sherman's March to the Sea*, ending on "Uzume / uzume.io". It's at `~/Documents/uzume_promo/linkedin-2026-10/uzume-linkedin-2026-10.mp4`, with three cover stills to pick a thumbnail from.
- **One command rebuilds it** (`tools/promo/cut_promo.py --edit tools/promo/edit.json`), so a reshot scene or a moved cut doesn't need another session.
- **Kagura's opening is an edit:** live, Kagura only sways through this song's intro, so its twist from later in the same song is moved 12 bars earlier and stays on the beat.

### [dev-2026-09-30-162430] REC.2 — record one scene for a whole song

- **`UZUME_PIN_SCENE=<scene>` keeps Uzume on one scene.** The session opens on the named scene and stays there. The plan, live switching and scene-completion events leave it alone. A misspelt name is logged with the valid names and nothing starts, so a take never records the wrong scene by accident. Dev launch switch only; no UI.
- **The `L` hold now holds sessions without a plan too.** Before, a system-audio session with no playlist plan could still switch scenes while held.
- **Five promo takes recorded** of Sherman's March to the Sea (Kagura, Ferrofluid Ocean, Cymatic Resonance, Fractal Tree, Fireflies). Each is trimmed to the song's first 34 s, with a frame-to-song-time map, in `~/Documents/uzume_promo/linkedin-2026-10/`. Each clip starts at its first recorded frame, about half a second into the song.
### [dev-2026-09-30-171610] BR.18 — streaming scenes ease into each song

- **No lurch at the start of a streamed song.** On Spotify and Apple Music, the instrument-driven motion used to start at nothing and then overshoot for about ten seconds as Uzume learned each song, and only Ferrofluid Ocean was protected. Every scene now eases in over those seconds. Local files are unchanged.
- **Fireflies and Kagura on streaming** still use one energy level per song, from its preview: the meadow doesn't thin in quiet parts, as it does with local files (Matt's call for the beta).
- Waiting on Matt's streaming review of the top ten scenes.
### [dev-2026-09-30-165358] BR.19 — the right song, reliably (BUG-152)

- **Uzume no longer prepares the wrong song.** For about 1 song in 12, the preview it analysed was a different song (an underscore or accent in a name, or a song the catalog lacks). Every song is now checked — title, artist and length must agree — and skipped if nothing matches. On four real playlists: 11 wrong songs → 0, and 4 more songs found.
- **A network blip is no longer final.** A busy or failing lookup is retried a few seconds later, and a Wi-Fi login page is never remembered as "this song has no preview".
- **Your country's catalog.** Lookups ask the store for your Mac's region instead of always the US.

### [dev-2026-09-30-153337] BR.17 — AirPods, and high-sample-rate output

- **Beat accents wait for Bluetooth.** Uzume now reads how late your output device plays and holds the beat-timed accents back to match. With AirPods, Kagura's steps, Fireflies' flashes and Membrane's strikes were landing early. Built-in and wired speakers keep exactly the timing they had.
- **Scenes that follow instruments work at 88.2 kHz and above.** At those output rates, the live instrument separation silently never ran.
- **Bass stays precise at 96 and 192 kHz.** The live analysis now works at the usual resolution whatever rate the output runs at.
- Pending an AirPods check in listening session 2.

### [dev-2026-09-30-151115] BR.16 — honest privacy copy and credits

- **The privacy promise is now accurate.** Every permission screen said nothing ever leaves your Mac, but each song's title and artist are looked up online. They now say: "Your audio never leaves your Mac. Uzume looks up song details on Apple's iTunes and MusicBrainz."
- **MusicBrainz is asked at most once a second**, as its rules require.
- **Settings › About › Acknowledgements** credits the models, shaders, motion capture and Milkdrop presets Uzume builds on, each with a link. The licence line no longer claims MIT for all of it (Aurora Veil's shader is non-commercial).
- **One copyright holder:** Plait & Pattern, in the licence file and the About box.

### [dev-2026-09-30-144510] BR.15 — the tester build hides controls that don't work yet

- **Settings:** "Device tier", "Quality ceiling", "Hidden scene families" and the adaptation-message toggle are gone from the tester build. None of them changed which scenes play.
- **Keys:** − + . ← → and ⌘R are gone from the tester build and its ? overlay. They didn't do what their messages said (− pinned the scene you disliked). ⇧← ⇧→ (cut to another scene) and ⌘Z stay.
- The developer build keeps all of them, to be wired after the beta.
- **Adaptation messages are off until you turn them on** (Settings › Visuals, developer build) — before, they showed while the toggle said off.
### [dev-2026-09-30-142354] BR.14 — the window, keys and Settings behave

- **Fullscreen and Esc work when Spotify was in front.** Uzume used to attach its fullscreen and display handling to whatever window was active when playback began — usually Spotify's — so ⌘F did nothing and Esc in fullscreen asked to end the session.
- **Esc in Settings or over the shortcut help no longer asks to end the session.** It closes what's in front.
- **Closing the window ends the session.** Listening, the recording indicator and analysis stop instead of running on with no window.
- **The pointer hides** along with the playback controls.
- **Settings from anywhere:** Uzume › Settings… (⌘,) and a gear on the start screen.
- **"Move to primary display" works from the second display.**
- Pending live checks in listening session 2.

### [dev-2026-09-30-015424] BR.13 — local files keep their place

- **Switching speakers or AirPods no longer restarts the song.** A local file carries on from where it was, and a paused song stays paused, instead of starting over out loud while the screen says paused.
- **Opening something new stops the old song.** Opening another file, folder or playlist, or cancelling, used to leave the previous song playing, and its ending could start the new queue before it was ready.
- **Mono files are heard at the right pitch.** They were analysed an octave too high.
- Pending live checks in listening session 1.
### [dev-2026-09-30-013733] BR.12 — audio capture stays in one piece through device swaps and Core Audio restarts

- **Starting, stopping and re-creating the audio tap happen one at a time.** Ending a session while AirPods connect could leave a stray tap feeding the analysis, so the analysis could run twice as fast and beat sync go wrong. Each step now waits for the one before it, and a re-create that was queued before the session ended does nothing.
- **A failed recovery no longer gives up for good.** If re-creating the tap after a device change failed, Uzume stopped watching for device changes. It now keeps watching and tries again on the next one.
- **Restarting Core Audio no longer leaves Uzume silent.** Uzume notices the restart and re-creates its tap.
- **Ready no longer re-creates a working tap while you get the music going.** A Retry on the Ready screen re-creates it on demand instead.
- **A tap that reports an impossible sample rate is refused** instead of crashing the level meter.
- Pending live checks in listening session 2 (AirPods swap while ending, `killall coreaudiod` mid-session).
### [dev-2026-09-30-011211] BR.11 — Uzume keeps up with how people actually listen (BUG-173)

- **Pausing is just pausing.** Pausing Spotify or Music and resuming no longer restarts the song's visuals from scratch.
- **Songs outside the playlist** (Spotify's autoplay afterwards, ads, podcasts) now get scenes that change with the music, instead of the last scene held forever.
- **A looping song keeps changing scenes** on every loop, and a local file's visuals stay in time through pauses.
- **"Start listening now" after a session starts fresh.**
- **One bad file in a local playlist** no longer puts every later song on the wrong scenes.
- **Slow lookups** can no longer attach the previous song's tempo or key to the next song.
### [dev-2026-09-30-004428] BR.10 — saying no to "control Spotify / Music" no longer breaks the session (BUG-172)

- **Spotify or Music, permission declined:** Uzume says what's happening and where to allow it, and keeps choosing scenes by listening, instead of showing one scene for the whole playlist.
- **Apple Music, permission declined:** the "allow Uzume in System Settings" screen appears, instead of "Checking every 2 seconds…" forever.
- **Fewer permission prompts.** A Spotify session no longer asks to control Music, and local-file sessions don't ask about either.
- The macOS prompt now says what declining costs.
### [dev-2026-09-30-001436] BR.9 — preparing the next songs no longer disturbs the visuals (BUG-171)

- **The visuals no longer twitch while Uzume prepares songs in the background.** Preparation shared the live analysers, so each prepared song briefly pulled the energy and mood readings toward a different song. It now uses its own.
### [dev-2026-09-30-000123] BR.8 — long playlists keep their preparation (BUG-170)

- **Playlists over about 64 songs no longer lose their preparation.** Uzume used to drop prepared songs from memory before they played, so most of a long playlist played without its planned scenes. It now keeps only what playback needs, which is small, and keeps all of it.
### [dev-2026-09-29-234710] BR.7 — preparation never strands the tester (BUG-169)

- **"Start now" appears even if one of the first songs has no preview.** Before, a single missing preview among the first three songs (about one Spotify scan in five) kept testers waiting for the whole playlist, with only Cancel.
- **No "Ready" when nothing could be prepared.** A failed connection or a playlist with no usable previews now shows the "couldn't prepare" screen, whose "Start reactive mode" button now works.
- **Cancel while connecting stays cancelled.**
- **No false "You're offline" for local files.**
- **If Uzume's analysis files are missing, it says so** instead of quietly preparing nothing.
### [dev-2026-09-29-231449] BR.4 — the tester build shows only tester things

- **The "Uzume isn't hearing any audio" card no longer tells testers to use Terminal**, and no longer appears while they're still opening Spotify. A frozen audio connection still shows it.
- **No developer keys in the tester build.** The help overlay lists no bug IDs, and the keys that could pull the visuals off the beat are gone. `+` ("more of this style") now works on US and UK keyboards.
- **Settings shows words, not string keys,** and a test now catches any missing string.
- **The Ended screen says how long the session played,** and "1 track" rather than "1 tracks".
- **No log file in the tester's home folder.**
- **A one-page note for testers:** [`TESTER_RELEASE_NOTES.md`](TESTER_RELEASE_NOTES.md).
### [dev-2026-09-30-003403] BR.6b — M1/M2-class Macs render at a size they can hold (BUG-168)

- **A ceiling on render size for tier-1 Macs** (M1, M2, M2 Pro by the current detection). The visuals draw at most about 2560×1440 and macOS scales them to the screen. On the M2 Pro, that keeps every measured scene but one under the 60 fps budget; at native 4K, 13 of 23 miss it.
- **Alfvén is left out on those Macs** for the beta: it measured about 4× its declared cost.
- Visible on the Mac mini: its 4K display now shows the scenes upscaled from 2560×1440.
- Still to measure: the M4 MacBook Pro and the 4K display (Matt's sessions).

### [dev-2026-09-29-222958] BR.6a — CI compiles every shader and builds the Release app (BUG-167)

- **A broken shader can no longer reach a tester unnoticed.** Every pull request now compiles every shader the app compiles at launch, the same way the app does. It also builds the Release configuration that ships. Before, a shader error first showed up on a tester's Mac, as a crash on every launch or a scene silently missing.
- Proven red on a deliberately broken shader, then green after the revert.
- Still open: launching the notarized build on macOS 15 (BR.6b).

### [dev-2026-09-29-215718] BR.5 — testers can send Matt evidence (BUG-166)

- **Help › Report a Problem.** Uzume asks first, then saves a zip of its recent log messages, any Uzume crash or freeze reports, and the Mac's model, macOS and graphics chip, with the build number and commit. No audio, nothing sent. The zip opens in Finder and a pre-filled GitHub issue opens for the tester to attach it.
- **After a crash or force-quit,** the tester build offers the same report the next time it opens.
- **Freezes leave evidence.** A new watchdog notices when the app stops responding, even in the tester build, and records where it is stuck.
- The hang-capture script works again (it was looking for the app's old name).

### [dev-2026-09-29-213501] BR.3 — a Spotify / Apple Music song change no longer risks corrupting memory (BUG-165)

- **Song changes are handled on the right threads.** When the streaming app moved to the next song, Uzume reset its scene and analysis state from a background thread while the visuals were still drawing, a crash or memory-corruption risk on every song change. Each reset now runs where that state lives.
- Verified with ThreadSanitizer: the old way produced 100 race reports in the stress test; the new way produces none.

### [dev-2026-09-29-204543] BR.1 — photosensitivity promises the app now keeps (BUG-163, BUG-164)

- **Reduce Motion works from launch (BUG-163).** With macOS Reduce Motion on, the visuals start reduced instead of waiting for the setting to change. macOS "Dim flashing lights" now counts the same way.
- **The flashing-lights notice can't be skipped.** Opening a file, Finder's "Open With" or a drop now waits for the notice first. Its "Enable Reduce motion" button turns on Uzume's own Reduced motion setting instead of sending you to System Settings.
- **No Fractal Tree on M1-family Macs (BUG-164).** Those GPUs draw a flashing colour field instead of the tree, so Uzume never picks it there.
- **The tester build shows only checked scenes.** Shift+→ skips test patterns, diagnostics and uncertified scenes; "Show uncertified scenes" and the user-preset folder are developer-only.
- **Flash testing covers three more scenes**, all under the limit: Fractal Tree, Ferrofluid Ocean's real lit picture, and Waveform. The check now refuses to "measure" a scene's depth buffer instead of its light.
- Pending Matt's live checks in listening session 1.
### [dev-2026-09-29-200841] BR.2 — the screen stays on while Uzume plays (BUG-162)

- **The display no longer sleeps mid-song.** From Ready through the visuals, Uzume keeps the display awake and the Mac from locking; ending the session, returning to Idle or closing the window lets normal sleep resume.
- Pending Matt's live check on the M4 MacBook Pro on battery (`pmset -g assertions` mid-session).

### [dev-2026-09-29-182455] CLEAN.2.5b — Uzume installs on a stranger's Mac: signed by Plait & Pattern, notarized, one-command DMG

- **A DMG anyone can open.** `Scripts/release.sh` builds a Developer ID–signed, notarized, stapled `Uzume-<version>-<build>.dmg` and checks it 15 ways before calling it done. Opening it shows only macOS's normal "downloaded from the internet" confirmation. Nothing is published; that is a separate call.
- **Who it runs on.** macOS 15 Sequoia and later, Apple Silicon only. Version 0.9.0; the About box reads "Copyright © 2026 Plait & Pattern."
- **Hearing the music on a new Mac.** A new user is now asked "record your system audio" with Uzume's own explanation. Without it, a tester's Uzume would have heard silence. The question comes on the Ready screen, next to "press play" (Matt's call).
- **Ready no longer waits forever (BUG-160).** Pressing play soon after Ready used to leave Ready waiting even with the music loud; it now moves to visuals within about a second, however long you wait first.
- **No crash on Continue (BUG-161).** Continuing from the Spotify scan's review could crash Uzume; it now closes the list before preparing.
- **The public build keeps no session records (BUG-158)**, so it never asks for your Documents folder. Developer builds record as before.
- Verified on a fresh account on the Mac mini: Matt, *"Passes all steps."*
### [dev-2026-09-29-174949] TESTFLAKE.3 — the chrome and Ready tests wait for the timer, not the clock

Seven app tests failed once each during CLEAN.2.5b's full-suite runs and passed on rerun: the playback chrome's auto-hide and first-show timer tests, and the Ready screen's first-audio tests. Each slept a fixed 50 ms to 1.5 s and then checked that a timer had fired, which a busy main actor can make late. They now wait for the event itself: the chrome going hidden, the Ready screen hearing audio, or the chrome's timer being armed. The check that the first track does not restart the chrome's timer now waits until the track has been handled. A test whose event never arrives fails at one minute instead of hanging. The two suites run in about 0.01 s, down from several seconds. Test-only change; no product behaviour changed and no wait widened.

---

### [dev-2026-09-29-135111] BUG-156 — the local-file end-of-track tests wait for the music, not the clock

`SessionLifecycleChurnTests.onFileEnded_queueAdvanceChurn_neverHangs` failed once in a full engine run. The end-of-track callback it waits for is delivered by AVFAudio through a thread pool the rest of the test suite keeps busy, so under full load it arrived 15–20 s late instead of in 0.3 s. It was late, never lost. The test and its sibling in `LocalFileSeekTests` now tell late from lost by what the pool has done, not by elapsed time. No timeout was widened, and a callback that never comes still fails. Test-only; playback is unchanged. KNOWN_ISSUES BUG-156 records an open, unobserved product risk from the same mechanism: a busy app could advance local-file tracks late.
### [dev-2026-09-29-140357] BUG-157 — the StemSeparator concurrency test no longer waits behind the rest of the suite

`StemSeparatorConcurrencyTests.concurrentSeparations_returnPerCallerOwnStems` timed out once in a full engine run. Its eight separations sat in a thread pool that the rest of the suite keeps busy, the same mechanism as BUG-156, and never started within the 180 s wait. They now run on their own threads and start at once, even with that pool saturated. No timeout was widened, and the test still catches the BUG-031 contamination it guards. Test-only; `StemSeparator` is unchanged.

---

### [dev-2026-09-28-215128] KAG.5 — songs open on the calm dance; a seek no longer flickers (BUG-155) (M7 passed)

From Matt's first KAG.5 check (*"I saw the macarena for everything I played"*):
- **Songs open calm.** For its first four bars a song now dances its calm dance. Before, with no history to judge against, it chose the middle dance, which on calm songs is the macarena, so most songs opened on it.
- **Seeks settle (BUG-155).** Jumping within a song made the dancer flick through dozens of dances in half a second, or hold a pose after a jump back. It now eases into its rest and picks the dance up again at the next bar line.

---

### [dev-2026-09-28-193210] KAG.5 — Kagura's dances follow the song's measured energy (M7 passed 2026-09-28)

Kagura no longer asks the mood classifier how energetic a song is. It reads the measured energy of the part of the song playing. On local files, its three dances change at the song's energy changes: Dance Yrself Clean dances the calm three (Egyptian walk, macarena, cabbage patch) through its hush and breakdown and brings the twist in at the drop. Each stretch is judged by its loudest tenth (Matt's call). The switch waits for the next clip change, so a dance is never cut mid-move. Rests follow the same energy: ballet in calm stretches (Take Five, the openings of Warszawa and Dance Yrself Clean), the sway elsewhere (Penny Lane and the body of Warszawa now sway). The Charleston stays on any song fast enough for it, whatever the energy (Matt's call), so Take Five keeps it. On streaming the 30 s preview stands for the whole song.

---
### [dev-2026-09-28-220809] FF.5 — Fireflies certified (the 27th): patches take turns, a smooth glow, a meadow that thins with the music

Fireflies is certified on Matt's M7 of the beta playlist (*"Fireflies is a strong pass - I love it (and more importantly my wife loves it)"*). On a clear beat the meadow now settles into 2 to 4 patches that take turns, so a flash walks across the meadow one patch per beat instead of the whole meadow flashing at once (the FF.4 M7 note: *"everyone at once"*). Each firefly's glow is a smooth yellow-green light instead of a one-pixel stipple (*"fireflies look pixelated"*). Quiet stretches show a sparse meadow and it fills as the song builds, following the same 1–10 energy curve the planner uses (Matt's "A"): Dance Yrself Clean is sparse until the drop at 3:08. An irregular or unknown beat still leaves the swarm free. New engine surface: `StemFeatures.energyLevel` (float 57), the song's measured energy at the playhead, available to every scene. Known: on streaming the patches land only as close to the beat as the streaming beat grid does (Billie Jean: close, not locked — BUG-065), and a streaming song holds one density because only its preview is measured. Flash-safe (0.00 flashes/s); no golden session plan changed.

### [dev-2026-09-28-210158] BUG-154 — the network-recovery tests wait for the debounce, not the clock

`NetworkRecoveryCoordinatorTests` failed once in a full app-suite run (`0 == 1`, `2 == 3`): the tests slept 3 s for a 2 s debounce and asserted while the debounce task was still waiting to get back onto a busy main actor. They now await the coordinator's own `debounceTask`, so they pass however slow the machine is. A probe that adds 1.5 s to the debounce failed 4 of 7 tests before the fix and passes all 7 after. Test-only change; no budget widened.
### [dev-2026-09-28-201200] SCAN — Spotify playlists are scanned from the screen (pending Matt's live check)

The Spotify tile now scans a playlist instead of asking for a link: click **Start scan**, Spotify comes forward with a small panel beside it, scroll the playlist once, and Uzume reads each row's title, artist and length from Spotify's window, on the Mac. It finishes by itself at the header's song count; skipped rows are named ("Missed 14–16. Scroll back up a little."), a scan started mid-list asks to scroll to the top, and a review list (always shown) lets you fix or remove a row before **Continue**. Screenshots dropped on the Spotify view go through the same reader. No Spotify login and no request to Spotify: the Web API's new rules limit the link connector to five people, so it survives only in developer builds (D-260). Measured on four real playlists (144 songs): every row read, 99.2 % identified, no wrong songs; two live scans in the Release build took 8–10 s for 32–38 songs. Matt's live check found one wrong artist in 38 (the first, half-visible reading of a row stuck — BUG-153); a row's text is now voted across every frame that saw it, and his re-scan of that playlist read all 38 rows correctly (5.3 s). Screen-read rows use a stricter catalog lookup (title, artist and length must agree, or the song is left out rather than guessed). The same measurement found the existing first-hit lookup landing on the wrong song for 8 % of those playlists (BUG-152, open). The screen-recording permission text now says the scan reads track names in the Spotify window.

### [dev-2026-09-28-174700] KAG.4 — Kagura certified (the 26th)

Kagura, the point-light dancer, is certified on Matt's M7 of the beta playlist (*"looks much better, happy with it overall"*). It now enters planned sessions like the other certified scenes, kept off beat-irregular songs by `requires_regular_beat`. Flash-safe in all three measured cases (the dance, the Charleston, the ballet rest: 0.00 flashes/s); no golden session plan changed. Known: the macarena runs a little heavy on calm songs.

### [dev-2026-09-28-153357] KAG.3 — Kagura after the first live sessions: new dances, fairer picks (pending live M7)

After three live sessions (Matt, 2026-09-28): the chicken dance is out of the pick; the Charleston joins for fast songs (one step per beat, only where that is within ±25 % of its natural speed — B.O.B. and Take Five on the beta playlist); calm songs rest in slow ballet poses instead of the sway (Moonlight, Penny Lane, Warszawa; Pyramid Song keeps its sway); and each bar is ranked against the song's other bars, so calm, middle and vigorous each get their share (live, 62 % of picks had been the middle dance). Local files re-analyse once more (stem cache v18: v16 collided with BUG-144's entries). New session-log lines: `KAGURA_SONG` and `KAGURA_PICK`. Not certified.

### [dev-2026-09-26-015632] KAG.3 — Kagura dances five dances and picks them from the song (pending live M7)

Kagura now chooses between the twist, cabbage patch, chicken dance, macarena and Egyptian walk. The song's energy and tempo pick three at track start. At each bar-line clip change, the bass of the bar just played picks the calm, middle or vigorous one (Matt's option A; the local file and streaming behave the same). The arms swell by up to 25 % with the bass. The dancer sways through beat-irregular stretches, through silence, and when playback stops. The song's energy is a new song-level arousal measured in preparation, because the existing `TrackProfile.mood` is the last second or two of the track (BUG-143 handles that separately). **Local files re-analyse once** (stem cache schema v16). The sidecar now declares `requires_regular_beat`, so the planner keeps Kagura off beat-irregular songs when uncertified scenes are shown. Not certified (KAG.4).
### [dev-2026-09-28-162542] FLASHOFF.1 — the flash-safety tests no longer block the rest of the suite

Test infrastructure only; nothing in the app changes. The photosensitivity tests for the multi-pass scenes ran on the main thread for about four and a half minutes of every full engine run, and the session-preparation tests that also need it were close to timing out behind them. Adding one more scene's test (Fireflies, FF.4) pushed nine of them over. Those renders now run off the main thread, and the few scenes that still need it borrow it a frame at a time, so its longest wait during the suite is 0.05 s. Every scene's flash measurement is exactly what it was, and the full engine suite passes (2040 tests).

---

### [dev-2026-09-28-151022] FF.4 — Fireflies' M7: not yet; patches and a smooth glow next

Matt reviewed Fireflies live on the beta playlist and did not pass it. Testers found the whole meadow flashing at once overwhelming and wanted a coordinated rhythm across the swarm; Matt also saw the fireflies as pixelated. The next increment (FF.5) makes patches of the meadow take turns flashing on the beat and draws each firefly's glow smooth instead of stippled. Fireflies stays uncertified, so sessions don't plan it, but the arrow keys now reach it (`exclude_from_cycling` removed) so it can be reviewed. New tests: a WCAG flash measurement through the real draw path with the swarm locked in unison (0.00 flashes/s), and a check that the swarm follows the real beat and not a half-beat decoy.
### [dev-2026-09-28-135038] LFSEEK.1 — jump within a local-file track

Local-file sessions had no way to move within a song. The transport bar now has a track bar above its buttons, showing the current track's elapsed and total time. Click or drag to jump; the audio restarts once, where you let go. The scenes, the beat and the stems jump with it, and the new position's planned scene comes up right away. If you were paused, you stay paused. Streaming sessions don't show it, because the streaming app owns its player. Also fixed (BUG-151): in a multi-song local session the next song started about a second early, cutting each song's last second. It now starts when the last audio has played. Still to do: Matt's live check.

### [dev-2026-09-27-220250] NRG.4 — scenes change when the music does

Scene changes used to land on fixed intervals, so in Dance Yrself Clean the drop at 3:08 got its dense scene at 3:21. Preparation now finds where each song's energy steps up or down and holds (a drop, a breakdown, a re-entry), and the planner changes scene there. Dance Yrself Clean now changes at 3:08, 5:57 and 6:35, within a second of the music. A dip shorter than about 20 seconds doesn't trigger a change. Scene length is otherwise the same as before, and a stretch no longer ends on a stub of a scene just before a change. Streaming previews, whose place in the song is unknown, keep the fixed intervals. The M key ("Toggle mood lock"), which did nothing, is gone (NRG.3). Still to do: Matt's live listen.

### [dev-2026-09-27-182327] NRG.3 — scenes follow the song's energy as it moves

Scene choice now reads each song's measured energy for the stretch a scene will play over, instead of the mood model's single guess. A quiet opening gets a sparse scene and the drop after it a dense one. In Dance Yrself Clean on the beta playlist, the hush gets Witchlight, Skein and Aurora Veil; from 3:21 the drop gets Cymatic Resonance, Nebula and Filigree; the 6:09 breakdown returns to Witchlight. Transitions follow energy too: calm stretches crossfade longer, and only the most energetic moments (level 10) cut. The live re-planning that fired when the mood model's reading drifted is removed, because it was re-planning on noise. The certified scenes' own use of mood is unchanged for now. Still to do: Matt's live listen.

### [dev-2026-09-26-231257] NRG.1–2 — songs get a measured energy curve and a 1–10 energy readout instead of a mood word

The mood word in the preparation view ("restless", "wistful", …) came from a model that turned out to be no better than chance on songs it hadn't seen (BUG-148). Preparation now measures each song's energy over time instead, one point per second of loudness and activity. The view shows it on a 1–10 scale calibrated across the library: one number for a steady song ("energy 5"), or the low → high range for one that moves ("energy 2 → 9", Dance Yrself Clean's quiet opening and its drop). Across a 1,000-song sample of the library, the typical level runs from classical 2 to hip-hop 9. Scene choice doesn't use it yet; that's NRG.3. **Local files re-analyse once** (stem cache schema v17).
### [dev-2026-09-26-224055] BUG-150 — the Spotify connection tests wait for the connect, not the clock

`connectLoginRequiredUnauthenticated` failed once when the app tests ran right after the engine suite: it slept 400 ms after `connect()` and asserted while the connect was still running. Every wait in the two Spotify view-model suites was a fixed sleep. They now await the view model's own debounce and connect tasks, so they pass however slow the machine is. A probe that adds 500 ms of connector latency failed 3 of 4 OAuth tests before the fix and passes all 16 after. Test-only change; no budget widened, and the suites run about 15 s faster.

### [dev-2026-09-25-214737] BUG-147 — a planner seed reproduces its plan in any process

The seeded planner noise (D-047) hashed preset ids with `String.hashValue`, which Swift randomizes per launch, so the same seed planned differently in every process. Users never saw it, because the app picks a fresh random seed for each plan and each Regenerate. It did mean a logged seed could not be replayed and seeded offline measurements (BUG-144) were not reproducible. The noise now uses FNV-1a over the id's UTF-8 bytes, and the scorer sums stem affinities in sorted order instead of `Set` order. `NearTieSamplingTests.pinnedAcrossProcesses` pins a seeded plan in source. Every nonzero-seed plan changes once; seed 0 is unchanged.
### [dev-2026-09-26-131209] BUG-146 — high-sample-rate files get the mood their music has

Preparation measured mood at the file's own sample rate, so 48 kHz and 96 kHz files read differently from the same music at 44.1 kHz. Superstition's 96 kHz FLAC read arousal 0.21, against 0.52 for the same audio at 44.1 kHz. The fixed-size analysis window halved the brightness measure and blurred the key detection. Preparation now analyses mood, key and brightness at 44.1 kHz (the rate the stems already use) whatever the file's rate. Superstition now reads 0.49. 44.1 kHz files are unchanged; about 16 % of the pilot corpus is at other rates (BUG-141). **Local files re-analyse once** (schema v16, shared with BUG-144/145).

### [dev-2026-09-26-130233] BUG-145 — each song gets its real BPM; songs without a steady beat get none

Every song was stored at 130–143 BPM, and that number both appeared in the preparation view and steered 27 % of the scene choice. The value came from a sub-bass onset detector that fires as soon as its 400 ms cooldown allows, on every song, so it measured the cooldown rather than the music. The stored BPM is now the beat tracker's tempo, which preparation already computes (octave-folded, so a stretch tracked at half time doesn't drag it). Songs Uzume judges to have no steady beat store no BPM, so they show none and tempo doesn't steer their scenes (Matt's call). On the beta playlist the BPMs now run from 77 to 172 and match the songs; Pyramid Song and Moonlight I show none. Scene choices shift on most songs as a result. The live beat path is unchanged. **Local files re-analyse once** (schema v16, shared with BUG-144). Still to do: Matt's look at the preparation view.

### [dev-2026-09-25-220217] BUG-144 — a song is planned with its own mood, not its last two seconds

Each song's stored mood was the mood classifier's reading at the very end of the analysed audio: the fade-out on local files, and the last seconds of the 30 s preview on streaming. Mood is 40 % of how a scene is chosen, so songs were planned from their endings. On the beta playlist, Teardrop, Take Five and Pyramid Song were planned as calm, and Moonlight I as warm. The stored mood is now the song's median after its first sixth (Matt's option A). Its rank agreement with the full production-chain analysis on the beta playlist rose from 0.59 to 0.86. With no plan history, the top-scored opening scene changes on 8 of 10 beta songs. **Local files re-analyse once** (stem cache schema v16). The preparation view's mood word can change on those songs. The live mood path is unchanged. Still to do: Matt's listen on the beta playlist.
### [dev-2026-09-26-014709] BUG-143 — the app tests no longer crash their host after the engine suite

When `xcodebuild … test` ran straight after `swift test`, the app's test host sometimes crashed (exit 65, "0 tests" on the retry) in `objc_autoreleasePoolPop`. Three DS.6 tests built an `NSWindow` in code and closed it. A window made that way has `isReleasedWhenClosed` set, so `close()` released it once more than ARC owned. When that freed memory was reused, the host crashed, which happened more often on a machine the engine suite had just loaded. The tests now build their windows through `NSWindow.offscreen(_:)`, which clears the flag. A new test crashed the host 3/3 without the fix and passes with it. A source scan stops new tests from copying the old pattern. No product code changed and no timeout was widened.

### [dev-2026-09-25-170143] BUG-142 — no track-change event after streaming metadata stops

A Now Playing poll that was still waiting on Music/Spotify when observation stopped fired a track-change event (with no previous track) afterwards, and set `currentTrack` again. This showed up as an intermittent CI failure (3 events where the test expected 2). A generation counter bumped under the lock at stop now makes a stale poll drop its result. A deterministic test parks the reader across a stop; it failed every time before the fix. Test sleep budgets are unchanged.

### [dev-2026-09-25-140918] BUG140.2 — the beat-irregularity gate stops flagging steady songs

Songs like Superstition and Penny Lane were marked "no steady beat", which hard-excludes `requires_regular_beat` scenes (Membrane; Kagura planned) and sets `beat_clarity01` to 0 for Fireflies. The gate compared a drums-stem tempo that `computeBPM` averaged across eighth- and quarter-note levels, and on local files that tempo was also scaled by the file's sample rate (48 kHz ×1.088). The gate now compares the octave-folded median beat interval of each grid, with the drums grid at 44.1 kHz. The 10 % rule is unchanged (Matt's option A). Estimated share of the library flagged: 25.2 % → 12.0 %. Duplicate recordings whose two copies disagree: 34/150 → 6/150. Pyramid Song is still excluded. **Local files re-analyse once** (stem cache schema v15). No change to beat sync: `BeatGrid.bpm` and the full-mix grid are untouched. Live check passed: Matt, *"Membrane is locked on Superstition … looks great!"*
### [dev-2026-09-25-140658] BUG-141 — stems on 48/96 kHz local files analysed at the right rate

The stem separator always returns 44.1 kHz stems, but two analyzers read them at the file's rate. The local-file stem series (what shaders receive) reported every frequency ×1.088 on 48 kHz files and ×2.18 on 96 kHz: vocal pitch sharp by ~1.5 semitones or an octave, and per-stem band splits drawn in the wrong place. The prepared `stemEnergyBalance` was also warmed at the wrong frame rate. Both now use the separator's rate. 44.1 kHz files are bit-identical. On 48 kHz files the scorer input moves ≤ 0.01. Cache schema v14 re-analyses affected entries.

### [dev-2026-09-24-205001] GOLDEN.1 — golden sessions plan against the shipped roster

`GoldenSessionTests` now loads the real scene sidecars instead of a hand-copied May-2026 subset (which still carried Arachne and was missing about 20 scenes). Sessions A–D were regenerated with scoring traces. The `[VL, Membrane ×4]` run BETA.0 recorded was a fixture artifact: on the real roster Membrane never appears. The BUG-133 monopoly does not come back on the seeded production path (7–11 distinct scenes per Session A over 24 seeds). Test-only.

### [dev-2026-09-24-202938] BETA.0 — Plasma removed (D-253)

Plasma is removed from the roster on Matt's call (*"Remove Plasma, keep Waveform"*): shader, sidecar, reference folder and every test enumeration; production count 31 → 30. Waveform stays, uncertified, as the launch default.

### [dev-2026-09-23-162630] BUG-139 — the tap teardown deadlock that hung the suite forever

`SystemAudioCapture.teardownTapResources()` held `stateLock` across `AudioDeviceStop`, which blocks
until the CoreAudio IO proc drains — while the IO proc itself took `stateLock` in `probeInstallRMS`.
Teardown waited for the IO proc, the IO proc waited for the lock, and `AudioDeviceStop` never
returned. The presentation was the worst kind: **no timeout, no failing test, no crash report** — a
wedged run, where BUG-103's SIGABRT at least left an `.ips`.

**Now:** teardown is split in two halves that cannot recombine. `claimTapResourcesForTeardown()`
takes the handles and zeroes the fields in one locked step and returns; `destroyTapResources(_:)`
does the blocking HAL work with no lock held, and is `nonisolated static` over a value type **on
purpose** — it cannot reach `stateLock` even by accident, so the compiler enforces the property
instead of a comment asking nicely. Zeroing inside the lock also makes teardown idempotent: a racing
`stopCapture()` and `deinit` can no longer double-destroy a handle.

This is BUG-021's lesson in a second place — that one was "no AVFoundation teardown under the
provider lock", this is CoreAudio teardown under `stateLock` in the tap path. The doc comment above
`probeInstallRMS` called that lock *"uncontended"*; it is uncontended per buffer and fatally
contended at teardown.

`SystemAudioCaptureTeardownTests` (4 tests). The gate pins the claim-then-destroy structure rather
than reproducing the deadlock, which needs a real aggregate device — but the **negative control was
run**: reintroducing the lock-held return wedged the suite, exactly as the defect does.

⚠ **Manual validation outstanding.** This is the shipped streaming path and no automated test can
reach a real aggregate device. One app-level streaming session plus an output-device change still
needs to run before this is called live-validated.


### [dev-2026-09-23-143429] BUG138.3 — VolumetricLithograph declares what it reads, and `FeatureVector` is not at buffer(2)

The two items BUG138.2 recorded and left open.

**VL's routes: 6 → 13.** It read eight audio fields it declared none of —
`drums/bass/vocals/otherOnsetRate` (peak density), `midDev` and `midAttRel` (their D-019 warmup
fallbacks), `pulseBeatIndex` (bar position, with the already-declared `pulsePhase01`) and `valence`
(hue offset). Each new route is anchored to an executable line with comments stripped, and
`RouteCoverageTests` proves every one fires: **236 → 243 routes, 0 red**.

**A dead route removed, which is the same defect inverted.** VL also declared
`camera_dolly_speed ← bass`. The shader reads no `f.bass` anywhere and has no audio-driven dolly —
the flight is free-running on `f.time`. That declaration stood for three months and route coverage
never objected, because **it proves a declared primitive has activity in the session, not that the
shader reads it.** Under- and over-declaration are both invisible to it. Worth remembering before
citing a green route-coverage run as proof that a scene's routing is right.

**`FeatureVector` is fragment `buffer(0)`** — and `buffer(1)` on the particle compute kernels.
`buffer(2)` is the waveform. Both `ARCHITECTURE.md` lines that said `buffer(2)` now say so.

**And a correction to my own work.** BUG138.2 rewrote VL's `description` and carried over two claims
from the table it was replacing without checking them: a vocal-stem terrain depth, and the camera
dolly scaling with bass. Both false. The increment whose entire subject was ungated prose
reintroduced ungated prose one file later. The description now states only what an executable line
supports.

**Method note.** `grep '"bassOnsetRate"'` said the primitive was missing from
`AudioRoutePrimitives.map`. It is not — the map composes those keys in a loop as `stem + suffix`. A
literal grep cannot see a constructed identifier, the same failure shape as grepping a `.metal`
without stripping comments. Derive the set and compare; never grep for the spelling.

---

### [dev-2026-09-22-234846] BUG138.2 — the prose that restates a gated fact is now itself gated

BUG-138's second half, plus the two gates. The `48 floats / 192 bytes` claim about `FeatureVector`
was not in two places, it was in **eight**: `Common.metal`, `AnalyzedFrame.swift`,
`SpectralCartograph.metal`, four lines of `ARCHITECTURE.md`, and — with its own wrong number,
`52 floats / 208 bytes` — the doc comment on `FeatureVector` itself. It is 56 / 224.

**That doc comment is the point of this increment.** It carries FTR.6's lecture about exactly this
failure: *"it had drifted to '48 floats = 192 bytes' … nothing caught it, because no gate reads
prose."* FTR.6 diagnosed the class correctly and chose to DELETE that copy rather than gate the
pattern. The prose grew back in eight places, including inside the lecture. Deleting one copy does
not stop copies.

**Two gates, both with negative controls, both proven red against the real shipped strings:**

- `CommonLayoutTest.proseSizeClaims_agreeWithMemoryLayout` — scans `UzumeEngine/Sources/**` and
  `ARCHITECTURE.md` for `N floats / M bytes` claims, attributes each to its nearest preceding struct
  name, and checks it against `MemoryLayout`. **Expected values are derived, not written down**, so
  the gate moves with the struct instead of becoming the ninth stale copy. Double-quoted numbers are
  treated as citations, not claims, so the two comments that correctly *quote* the old wrong value
  stay legal.
- `SidecarDescriptionDriftTests` — a field named in a sidecar `description` must be declared in that
  preset's `audio_routes` or read by its own `.metal` **with comments stripped**.

**A correction this turned up.** The previous entry recorded that `VolumetricLithograph.json` had the
*opposite* drift — prose right, routes incomplete — based on a grep that found `stems.drums_beat` in
its shader. That grep did not strip comments, and all eight occurrences are comments. VL reads
neither `drums_beat` nor `drums_attack_ratio` in any executable line; its peaks ride
`pulse_beat_index + pulse_phase01` with per-stem onset rates for polish. Same drift as FFO, fixed the
same way. The gate's comment-stripping exists because that mistake survived a first pass of this very
investigation, and its negative control now asserts a commented-out read does not count.

**Recorded, not fixed:** VL's routes *are* under-declared (eight read-but-undeclared fields), a
separate route-coverage matter. And two `ARCHITECTURE.md` lines call `FeatureVector` "GPU buffer(2)"
when every encoder binds it at buffer(0) — noticed while editing those lines for the size claim,
deliberately left alone rather than silently widened.

---

### [dev-2026-09-22-231122] BUG138.1 — Ferrofluid Ocean's sidecar stops being a second routing table

`FerrofluidOcean.json`'s `description` had been asserting audio routes the shader does not have. It
named `bass_energy_dev → spike height`, removed at **D-153** three months earlier because AGC-levelled
bass barely moved the spikes (motion std 0.09 — Matt's "frozen"); the `accumulated_audio_time × arousal`
aurora-drift product, which **BUG-047** removed for retroactively rescaling history; and a raw
`vocals_pitch_hz` palette read that **D-158** replaced with the CPU-smoothed composite after the raw
one strobed. Three retired mechanisms, stated as current.

The same file's `audio_routes` block was correct the whole time. That is the actual defect: **one file
described the same shader twice, and only one half was gated** — `AudioRouteSchemaTests` and
`RouteCoverageTests` read the declarations; nothing read the prose. It is the half a human reads first,
and it is the most plausible origin of the live uzume.io caption *"Bass raises the spikes"*.

**Now:** the description says what the preset LOOKS like and points at `audio_routes` and the
`FerrofluidOcean.metal` header for the primitives, with a short tombstone recording why it is no longer
a routing table. No engine, shader or route change — Ferrofluid Ocean renders identically and stays
certified.

**Still open (BUG-138).** The `48 floats / 192 bytes` claim in `ARCHITECTURE.md` §Buffer Binding Layout
and `Common.metal:11` (it is **56 / 224**), and the gate that would stop this class recurring. The
naive form of that gate — *a primitive named in a description must be declared in `audio_routes`* —
would go red on `VolumetricLithograph.json` on day one, whose description correctly names
`drums_beat` and `drums_attack_ratio` while its routes declare neither. That is route
**under-declaration**, a different defect needing its own QG.1 evidence, and shipping a gate that needs
an exemption the day it lands is worse than shipping none.

---
### [dev-2026-09-23-145657] BUG-103 — a raising `play()` can no longer kill the process

The parallel engine suite died intermittently with SIGABRT and **no failing test line** — fourteen
crash reports in one day on 2026-08-25. The cause was not a test bug: `AVAudioPlayerNode.play()`
reports some failures by **raising an Objective-C NSException**, Swift cannot catch one, and an
NSException unwinding past a Swift frame calls `abort()`. The same throw site ships in the
local-file start path, so the app-facing form was a hard crash when playback starts.

**Now:** both `play()` call sites route through a new Objective-C shim
(`Sources/ObjCShim/UZExceptionCatch.{h,m}` — the repo's only ObjC target, and the only way to catch
an NSException from Swift) that converts a raise into a Swift error carrying the exception's name,
reason and call stack. `start()` surfaces it as a thrown error and tears the half-built engine down
after unlocking; `resume()` logs and carries on.

**★ The obvious fix was falsified before it was written.** BUG-103 proposed checking
`engine.isRunning` after `engine.start()`. Nine engine states were probed against AVFoundation
first, and **every `isRunning == false` state returned from `play()` normally** — that guard would
have covered a condition that never raises, and would have shipped looking like a fix. Only a
detached player raises deterministically, which is what the new gate uses.

The production trigger (`'player did not see an IO cycle'`) is a race against the HAL IO thread and
is **still** unreproduced synchronously — deliberately so. This fix removes the trigger's ability to
kill the process rather than claiming to explain it; if it fires in the wild it now arrives as a
logged Swift error with a call stack.

`PlayerNodeExceptionContractTests` (3 tests, deterministic, no sleeps). Full engine suite 4/5 exit 0 with **no new crash reports across all five** — the one red run was a GPU wall-clock budget test this diff cannot reach, not a regression.
`KNOWN_ISSUES.md` BUG-103 resolved; BUG-117's stale index row corrected in passing.

### [dev-2026-09-16-215311] BUG-137 — capture mode waits for a busy encoder instead of dropping frames

A capture recording made while the Mac was busy silently lost frames. Under CPU load the ProRes
writer input reports not ready in bursts, and capture mode discarded the frame there — logging one in
120. Found through the capture-mode recorder test, which failed 14 of 20 runs under full load.

**Now:** capture waits up to 1 s for the writer, within a 512 MB backlog (≈ 1 s of 1080p60), and logs
**every** frame it still loses with the reason; the session summary ends `capture dropped N`.
Diagnostic mode is unchanged.

**Verified.** Loaded test runs: 6/20 → 20/20, then 19/20 (one failure of unknown cause) and 30/30.
Live under full CPU load (`2026-09-16T21-40-11Z`, 3½ min): **12,613 of 12,613 frames after the lock
written, capture dropped 0**, render 59.97 fps.

---

### [dev-2026-09-16-170000] REC.1 — capture-grade session video: every frame, ProRes

`UZUME_RECORD_VIDEO=capture` writes every rendered frame as ProRes 422 in `video.mov`, for the
website's footage capture (W.3a). Screen recording drops 4–9 % and burns in the pointer; the built-in
recorder was capped. `=1` stays the diagnostic H.264 recorder and now actually delivers 30 fps.

**BUG-136 fixed.** The "30 fps" recorder delivered 23.4: its throttle compared a two-frame gap
(≈ 33.4 ms) against 33.3 ms with no tolerance, so jitter turned half the gaps into three frames. The
keep decision now allows half a render frame. Live: **30.00 fps**, histogram all two-frame.

**Every buffer carries its own frame.** Frames used to blit into one shared texture read later on the
recorder queue — at 60 fps the next blit could overwrite it first. Each frame now blits into its own
IOSurface pixel buffer the encoder appends directly: no race, no CPU copy.

**Live, capture `2026-09-16T16-04-13Z`** (LG 1080p, Cymatic Resonance, 109 s): 6,550 of 6,552 frames
written (two dropped as the encoder started, logged), **0 duplicates**, render **59.99 fps** against
a 59.99 baseline. ≈ 1.1 GB per minute.

An earlier capture run (`15-05-41Z`) still applied the keep decision in capture mode and skipped two
catch-up frames after a late render; capture now takes every frame the renderer hands it (Matt's call).

---

### [dev-2026-09-15-010000] BUG133.2 — near-tie sampling: the ranking's precision exceeded its accuracy

Matt, after BUG133.1 failed its live check: *"do the near-tie sampling."*

The planner took `max(by:)` over scores whose whole eligible catalog spans **0.612 → 0.459**, with
the **top twelve inside 0.05**. A 0.003 gap between Cytokinesis (0.612) and Dragon Bloom (0.611) was
deciding every segment. `selectPreset` now samples **uniformly among presets within 0.05 of the
best** — uniform on purpose, because inside that band the differences are precisely what is being
called noise, and weighting by them would re-import the precision being discarded.

**Measured on Matt's own cached profile** (*The Suburbs*, production scorer): planner first pick over
12 seeds, **4 distinct → 10 distinct**. Cytokinesis 5/12 → 3/12.

Three properties keep it safe rather than merely different: it is **deterministic** on
`(seed, trackIndex, elapsedSessionTime)` so plan extension stays byte-identical (PREP.2 extends live
plans and `PartialPlanTests` pins it); **`seed == 0` stays pure argmax** so the unseeded goldens
still pin the scorer; and it is **a band, not a lottery** — a preset 0.15 below the best still never
plays, because that gap is a real preference.

★ **The first regression test passed with the fix removed.** Its fixture presets sat within 0.016 of
each other — inside the scorer's own ±0.02 seeded noise — so the noise already shuffled them and the
test proved nothing. The fixture now carries `MidBand`, placed ~0.04 below the best from *measured*
scores: outside the noise, inside the band. 0 of 24 seeds without sampling, reliably with it.

**That is twice in one session that an existing source of variety made a new gate look green** —
BUG132.1's wire test matched its own declaration, and this one matched noise. The check that caught
both is the same and costs one minute: remove the fix, re-run, confirm red.

`SessionPlanner+Selection.swift` split out (400-line budget); Module Map row added.

Live check owed. Baselines: 10 distinct in 59 selections, 13 in 50.

---

### [dev-2026-09-14-233000] BUG133.1 correction — a filtered test run is not evidence about the suite

The BUG133.1 entry below claims *"nothing in the existing suite caught the change — 45
scorer/planner tests passed against both scopings."* **That is wrong.** It was measured with
`--filter "PresetScorer|SessionPlanner"`, and the suite that catches the change is named
`GoldenSessionFixtures` — the filter never ran it. The full closeout run failed on
`GoldenSessionTests` "Session A: preset IDs match golden sequence", which pins the planner's output
sequence exactly.

★ **And that golden contained BUG-133, described accurately, four months before it was filed.** Its
expectation was `[VL, Membrane, Membrane, Membrane, Membrane]`, and the comment above it (2026-05-13)
reads: *"Membrane is the only `reaction` preset in the catalog, so once selected it has no
family-repeat competitor and gets picked across remaining slots… This reveals a real catalog
clustering symptom… the orchestrator's behavior is correct given the inputs."* Someone saw the
mechanism, wrote it down, called the behaviour correct, and froze it as the expected output. Matt
found the same thing from the other end by getting tired of Cytokinesis.

Regenerated to `[VL, VL, Fractal Tree, Fractal Tree, Ferrofluid Ocean]` — 3 distinct, the
four-in-a-row monopoly gone — with the justification trace the file demands. Sessions B, C and D
unchanged.

The general lesson is the cheaper one: **run the full suite before asserting what the suite does or
does not cover.** The filtered run cost nothing and bought a false claim in three documents.

---

### [dev-2026-09-14-220000] BUG133.1 — the cooldown was rationing the roster by family size

Matt, on a second session in a row: *"still seeing many of the same presets across tracks (getting
REALLY tired of cytokinesis)."* 59 selections, **10 distinct**, Cytokinesis ×14.

★ **`PresetScorer` had two levers against repetition and neither was per-preset.** Both keyed on the
family, so a family behaved as ONE rotation slot and its highest-scoring member held that slot
permanently — its siblings were not competing with the catalog, they were competing with each other
for a single turn, and losing it every time. The per-family data is unambiguous: the six-member
`particles` family produced exactly **one** preset across 59 selections (Cytokinesis ×14 — Nebula,
Witchlight, Murmuration, Mitosis and Filigree never appeared at all), the nine-member `hypnotic`
family produced three of nine, and the SINGLETON families produced their one member 7–8 times each.
**A singleton was a guaranteed private slot; a nine-member family hid eight presets.** Selection
frequency was set by family size, not by fit — which is how Alfvén, certified four days earlier, had
never once been chosen.

Cytokinesis specifically because `fatigue_risk: low` is a 60 s window against ~20 s segments:
eligible again after ~3 segments, and as the particles argmax it took the slot every time.

Matt's call — *"cool down the preset, not the family"* — so `fatigueMultiplier` now matches
`recentHistory` on `presetID`. `familyRepeatMultiplier` is untouched and still stops two similar
looks landing back to back; the rest of the family becomes reachable a segment later instead of
never. Splitting the two was the point, and it is the opposite of adding a repetition penalty: the
*existing* same-concept penalty was the thing suppressing variety, by treating nine distinct
certified presets as one.

★ **The A/B reproduces the complaint in a unit test.** Four consecutive picks from a six-member
family, identical material: shipped code returns `Set(chosen).count == 1` — the same preset four
times. The fix returns four. And **nothing in the existing 45 scorer/planner tests could tell the
two scopings apart**, which is exactly how the behaviour survived to a live session.

Budget was never involved: only Volumetric Lithograph exceeds the 16.6 ms tier budget.

Live check owed — the baseline to beat is 10 distinct in 59.

---

### [dev-2026-09-14-200000] BUG132.1 — a plan rebuild no longer clobbers the playing track's grid

Found in PREP.2's own validation session by reading the log, not by watching it. Every `_buildPlan`
rebuild ends by pre-firing **the plan's first track** into the live pipeline — `resetStemPipeline` →
`StemCache.loadForPlayback` → `BeatGrid installed`. On `2026-09-14T13-49-57Z`, **five of nine
rebuilds installed track 1's 164.4 BPM grid over a different playing track**, and `grid_bpm` stayed
wrong until the next track change: 13,190 frames inside a 175.0 BPM track and 13,928 inside a
108.0 BPM track **in 3/4**. Essentially both whole tracks ran beat-locked motion on the wrong clock,
with track 1's stem series loaded alongside.

The pre-fire is right before a session starts — it is how Spectral Cartograph shows
"PLANNED · UNLOCKED" straight after plan-build (DSP.3.2). It is wrong once one is playing, because a
rebuild decides what plays NEXT. `shouldPreFirePlan(sessionState:)` is now `!= .playing`; every
other state still primes.

★ **PREP.2 did not create this, but it is why it matters now.** The pre-fire has behaved this way
for as long as the plan has existed; the plan was built once, so it fired once, before playback.
PREP.2 rebuilds it once per PREPARED track, which turned a latent race into every local session with
an early start. PREP.2 anticipated this exact shape one path over — *"a walk finishing behind a
playing session must not drag it back to `.ready`"* — and guarded readiness, not this.

★ **The regression test passed against the reverted guard on its first attempt**, because it
searched for `shouldPreFirePlan(sessionState:` and the `static func` declaration satisfies that by
itself: a green gate over dead code, which is BUG-015's shape exactly. It only surfaced because the
fix was reverted and the suite re-run. The assertion now matches the CALL over comment-stripped
source, and the A/B is on the record — red on the exact pre-fix code, green on the fix. **A
source-presence gate that has not been run against the bug is not yet a gate.**

Also worth stating: Matt reviewed this session against the criteria he was given — playback starts,
nothing stutters — and reported them accurately. A wrong tempo grid does not stutter, and most of
the presets that session selected are continuous-energy driven. The defect was invisible to the
check he was asked to make, which is a fact about the check.

---

### [dev-2026-09-13-000500] BUG129.1 — the peak was right, and that was the finding

BUG-129 was filed on a reasonable suspicion: `chain_health.json` reporting `peakDBFS` exactly 0 with
a `clean` verdict, on three consecutive sessions, where an earlier one read −6.03. Both hypotheses
in the entry said the number was untrustworthy — either unmeasured and defaulting, or measured and
un-checked.

★ **Read straight out of the float WAVs, the number is correct.** The peak really is
`1.00000000` — reached by **exactly one sample out of 2,880,000**, sitting among neighbours of
−0.74/−0.79/−0.93, with the programme's second-highest sample at −0.24 dBFS. An ordinary heavily
limited master. `dbfs(peak: 1.0)` is exactly 0, so `peakDBFS: 0` was the truth all along.

**And it appeared exactly when the tap went.** The earlier ≈ −6 dBFS readings were *tap* captures;
BUG087.5 retired the tap on the local-file path the same day, so from `19:58:15Z` onward
`raw_tap.wav` is the decoded file at unity gain — the master's own level. Nothing broke; the capture
stopped being attenuated. Two same-day changes, one of which looked like a defect caused by the
other.

**The real defect was the missing half of the check.** `analyze` tested `critical_peak` and
`low_peak` — both floors — and nothing at the ceiling, so no capture could ever be graded on being
too hot. Now `clipped(run=N,samples=M)` and `over_full_scale(…)`.

★ **One verification criterion had to be reinterpreted, and it is worth saying why.** "A session
whose `raw_tap.wav` is genuinely full-scale must NOT grade `clean`" was written believing full scale
implied clipping. These captures are genuinely full-scale and healthy, so obeying it literally would
mark every loud track `degraded` and hollow out the verdict exactly where D-184 needs it to mean
something. The guard is gated on **flat-topping** instead — 4 consecutive samples at the rail, which
a clipped chain produces and a limiter's output does not.

**The part that actually closes the complaint is a reported field, not a check.** `maxFullScaleRun`
now ships on every capture, including when it is 0 or 1 — because `peakDBFS: 0` is indistinguishable
from an unset default *by eye*, and that ambiguity is what cost an M7 closeout its confidence. The
three sessions now read `peakDBFS 0, maxFullScaleRun 1`: measured, one sample at the rail.

All four regraded verdicts are unchanged and now defensible. VL.2's and WL.11's `clean` citations
were sound; their caveats can be read as resolved.

---

### [dev-2026-09-12-203000] BUG130.1 M7 PASSED — and silence turns out not to be one look

Matt, on the canonical build from `a376f875`: *"silence pauses correctly now."* Session
`2026-09-12T20-19-59Z`, Alfvén, one 34.1 s stop: `bass` decays 0.0558 → 0.0022 in **0.25 s**,
`near_silent01` fires at +0.25 s and holds **1.0 for all 2046 frames**, the floor sits at exactly
`0.000000` on all three bands for 1646 frames, and resume returns real audio **within one frame**.
The elapsed clock advanced **1.11 s** and then flat-lined — the 1.5 s flush budget, inside its
documented ceiling, measured rather than assumed. BUG-130 RESOLVED.

★ **The frozen run is still in the capture, and that is the fix working.** 1646 identical frames,
the same shape as the defect's 1617, at the opposite value. Frozen at `0.000000` is the correct
reading of stopped playback; frozen at `0.27158` was the bug. A future search for constant runs will
find one here — the value is the discriminator, not the run.

★ **And the first thing the fix revealed was a design question, not a defect.** Matt, watching it
live: *"motion is continuous despite pausing, but the visual gets less complex when the sound is
paused."* That is Alfvén being a driven MHD simulation — `alf_force` scales entirely by `p.drive`,
so at zero energy the stirring stops injecting structure while the field it holds keeps advecting.
It coasts. His call: *"coasting is right"*, and the general rule — ***"silence will read as different
things depending on the preset's design."*** A hard freeze on a fluid sim reads as a dropped frame,
not as quiet; a particle preset may want the opposite. Recorded in
`docs/PRESET_SESSION_CHECKLIST.md` so a future session does not file coasting as a bug.

Worth noting what this means for every silence behaviour recorded on the local-file path before
today: the feature vector never reached silence there, so none of it was ever actually exercised.

---

### [dev-2026-09-11-214733] BUG130.1 — a stopped local file is silence again

Matt, correcting my reading of his Alfvén M7: *"I stopped and started playback of a local file a
couple times during the session and had silence for more than 20 seconds."* The engine did not see
any of it. With the tap retired (BUG087.5) `PlayheadAnalysisClock` is the only analysis source on the
local-file path, and every one of its guards **returned** when the playhead stopped — so the last
`FeatureVector` re-published forever. Session `2026-09-11T21-00-42Z`: 1617 frames (26.9 s) of
byte-identical `bass/mid/treble` at `0.27158/0.02265/0.00522`, `near_silent01` zero throughout, while
`playback_time_s` moved 0.01 s. Blast radius was **every preset**, not Alfvén: stopped playback was
indistinguishable from playing, which is exactly the symptom Matt reported three times.

★ **Fix the input, not the publisher.** The obvious fix — clear or decay the published feature
vector on the pause path — adds a second, parallel definition of what silence looks like, one that
has to be kept in step with the chain's own. Feeding a tick's worth of **zeros** in at the top of the
funnel instead means silence is produced by the same AGC, the same band smoothers and the same
`nearSilent01` that produce it for real musical silence on the streaming path. Nothing downstream
knows the transport stopped, and nothing has to.

The silence is **bounded at 1.5 s**, and the reason is the one thing feeding zeros does cost:
`MIRPipeline.elapsedSeconds` accumulates each analysis frame's `dt`, and the live drift tracker
indexes the cached `BeatGrid` by it. Unbounded, a 27 s pause would walk the grid 27 s forward;
bounded, it costs ≤ 1.5 s of phase and the tracker recovers it. 1.5 s is well past the FFT window
and the band smoothers, so what stays frozen after the flush is frozen at silence — the correct
value. Zero cost would need the analysis callback to carry "this frame has no playhead", which
changes the four-argument contract shared with `SystemAudioCapture`; that upgrade path is named in
the code.

Two other things fell out of doing it in `tick()`. A stall now also resets `PlaybackClockSmoother` and
re-seeds the cursor — the smoother is entitled to dead reckon 0.25 s past the last distinct clock
value, and left sitting there a resume would read as a further quarter-second of silence while the
playhead caught up. And the cursor-seeding tick delivers silence rather than returning: no audio has
passed the playhead at a seed, and it keeps the cadence flat while a stall alternates seed → stall.
The same re-seed incidentally fixes a backward seek larger than the smoother's band, which used to
deliver nothing at all until playback caught back up to the stale cursor.

Streaming was checked and does not have the gap: its process tap keeps delivering buffers whatever
the transport does, so a stopped stream already arrives as real zeros.

`LoopingFileReader` now has its own file — this fix and BUG-131's teardown barrier landed in
`PlayheadAnalysisClock.swift` minutes apart and crossed the 400-line budget together; neither did
alone. Nothing moved but the type.

Gate: `PlayheadAnalysisClockTests` drives `tick()` directly through playing → stopped → paused →
resumed. **Live M7 outstanding** — Alfvén's silence state stays recorded as unvalidated until Matt
stops a local file mid-session and sees the visuals settle.

---

### [dev-2026-09-11-223000] Nine stale plan rows closed, one that was not stale, and a diagnostic defect

Matt: *"WL.4 is stale. Witchlight is tuned and certified."* Correct — and it was **eight** Witchlight
rows, not one. WL.4, .5, .6, .7, .8, .9, .9b and .10 all read *"pending live M7"* while WL.CERT had
certified Witchlight on 2026-08-07.

★ **WL.11 was the exception, and dates could not have found it.** WL.10, WL.CERT and WL.11 are all
dated 2026-08-07; only the commit times separate them — WL.10 at 11:00:55, the M7 session at 11:08,
WL.CERT at 11:37:17, **WL.11 at 12:01:19**. `git merge-base --is-ancestor` confirms WL.11 was not in
the certified build, so a CERTIFIED preset was shipping a beat-timing change nobody had reviewed.
**Establish supersession from commit order, never from dates.**

It has now been reviewed — Matt, session `2026-09-11T20-19-03Z`: *"Looks good."* And the numbers
corroborate rather than merely accompany: **|drift_ms| median 7 ms / p90 12 ms**, against the 25/63/91 ms
grid drift WL.11 was built to compensate.

★ **Whether WL.11 survived the rebrand had to be CHECKED, not assumed.** Its commit's paths are
`PhospheneEngine/…`, so a path-wise diff against main reads as "changed" from the rename alone and
proves nothing either way. Grepping for the symbols it introduced settles it: `ingestBeatDrift`,
`driftCompensationCapMs`, `beatDriftSeconds` all live on main.

Also closed on Matt's call, and recorded as **"closed as reviewed", not "M7 PASSED on session X"**,
because no review session existed for either: **PR.22** (supported indirectly by Nebula's certification,
explicitly not by a streaming session) and **SKEIN.OVERLAP.1** (whose row now states plainly that
nothing automated covers it — BUG-108's rendered-overlap check was never built and the Skein goldens
are green only because the harness paints nothing).

Three further stale-row classes fixed: **PR.19/.20/.21** were still "M7 owed" a day after Matt
certified the Nebula build containing them; **FD.2** was a ghost header under a preset's old name,
retired at FLY.14; and **VL.1** was an ID collision I created by grepping `^### VL` when those rows
are prefixed `### Increment ` — renumbered to **VL.2**, recorded rather than applied silently.

⚠ **New: BUG-129.** `chain_health.json` reported `peakDBFS` **exactly 0** on the two most recent
sessions while still grading `clean`, with empty reasons and `raw_tap.wav` present. It matters because
D-184 makes a `clean` verdict the precondition for judging fidelity at all — and two M7s closed today
cite `clean` over a 0 peak. Filed, not diagnosed.

### [dev-2026-09-11-213000] VL.1 — Volumetric Lithograph's notch was on a sixteen-beat cycle

A units error found while censusing BUG-117's consumers, and not BUG-117. `vl_foldRotation` divided
`pulse_beat_index` — which counts completed PULSE CYCLES, four beats each (D-154) — by the grid's beat
meter. On a healthy 4/4 grid that is one notch step every **sixteen** beats; only the declined grid's
`beats_per_bar = 1` produced the intended four.

★ The first census said the opposite — that a declined grid ratcheted four times too FAST. That came
from reading the expression's shape rather than tracing what `pulse_beat_index` counts, and the same
error hit two other sites in the same sitting (Witchlight and MeshGenerator, both actually protected by
the 2026-09-08 `barPhase01 = 0` hold). Tracing inputs is the step that was skipped, three times.

Matt's call: the meter leaves the arithmetic. One pulse cycle is the bar this ratchet wants, so a grid
with no bar information cannot mislead it because it is no longer asked.

**M7 PASSED** the same day on `2026-09-11T19-58-15Z` — Matt: *"I like the faster speed and it's synced
well with the music."* So the 4× motion change on a certified preset is accepted rather than merely
shipped. ⚠ **The golden gate cannot see it**: the
acceptance harness does not drive the pulse clock, so both arms compute an identical frame. Flash-safety
re-measured and unchanged.

### [dev-2026-09-11-200000] BUG-116 and BUG-119 closed on one Ferrofluid session

Both were fixed-pending-live-confirm and both surface in Ferrofluid Ocean, so one sitting closed the
pair. Session `2026-09-11T19-12-34Z`: **48 kHz** (the rate BUG-116 depends on — a 44.1 kHz file would
have tested nothing, because the defective branch does not fire there), chain health **clean**, peak
−6.03 dBFS, 180 s at 59.9 fps.

**BUG-116** — *"On any local file that is not 44.1 kHz, the pre-analysed stem series is DEAD for ~0.4 s
out of every 2 s."* Measured on this capture: **0 of 10,789 frames** with all four stems at zero,
against the pre-fix signature of **279 of 1,875 (14.9 %)**. Matt: *"No periodic darkening. Visuals are
steady."*

**BUG-119** — the beat pulse held one whole-track average BPM, so a wrong average put every
pulse-driven preset off the music. Measured: **|drift_ms| median 13.9 / p90 42.7**, **|onset_residual_ms|
median 17.6 / p90 25.3** — sub-20 ms is the pulse landing on the beat. (For contrast, the Nebula session
on a track whose grid was genuinely bad read |drift_ms| median 634.) Matt: *"No visible grain observed.
Spike punches land with the music."*

⚠ **A metric was built, measured, and DISCARDED here rather than reported.** An attempt to show the
pulse now follows the grid's LOCAL period — by differencing `pulse_beat_index` over 5 s windows —
returned a 1231 % spread, then 62–187 % after excluding gated frames. Neither figure means anything:
`pulse_beat_index` steps in integers, so over a 5 s window the estimator quantises into buckets
(5s/13, 5s/8, 5s/5) and is measuring the window arithmetic rather than the pulse. `drift_ms` and
`onset_residual_ms` answer the question directly and are what the closure rests on.

### [dev-2026-09-11-172000] Nebula certified — the 23rd, and the first reviewed on a fixed clock

Matt's M7 on `2026-09-11T16-47-03Z`: *"It's close enough ... we should leave Nebula alone and move to
certification."* Chain health **clean**, 202 s, and the first Nebula review with BUG-087's rate ceiling
gone — bass changed at 59.41 Hz against a 60.00 fps render, where every prior review of this preset ran
on a ~10 Hz bus. `certified: true`, added to `FidelityRubricTests.certifiedPresets`, and the
automated-gate comment that asserted the opposite was corrected rather than left to rot.

★ **Certifying enrolled Nebula in the Harding/WCAG 2.3.1 photosensitivity gate, which covers the
certified set only — and it failed immediately.** Not on flashing: it rendered *static*, because its
ring reads the slot-6 `NebulaState` buffer and the single-pass harness binds a zeroed placeholder
there. The gate refuses to call a static frame safe, which is the vacuous-pass rule doing its job on a
safety check. Nebula joined the multi-pass harness, where a live `NebulaState` is bound at fragment
index 6: **peak 0.00 flashes/s, 0 transitions, SAFE, Δluma 0.031** (~6× the responsiveness floor).
Certifying a preset is not a flag flip — it enrols it in every gate scoped to the certified set.

**PR.23 was scoped and declined in the same session, and the decline was correct.** Matt reported *"the
core activates with a delay"*; the scope found the obvious fix already shipped (`core_pulse ←
transientRise` is live) and located the real lateness in the core's BODY — the smoothed instant bands at
+85 ms against the accent's +55 ms. But its own analysis said a follower downstream of τ 77 ms smoothing
makes the response asymmetric rather than early, leaving only a balance shift between body and accent.
Matt: *"risky, not necessarily a fix."* Against a preset he had just called close enough, that is risk
without a guaranteed return. The scope is kept — the measurement is durable even though the fix was not
taken.

⚠ **Two gaps certified WITH, recorded so neither reads later as an undiscovered defect:** the core's
delay above, and a reference set that is still an unfilled template. Nebula is `rubric_profile:
lightweight`, so its stylization contract IS the rubric substitute — and **nothing mechanically gates
it**; no test reads the README. Nebula therefore has no recorded definition of what it should look like,
so a future visual regression has nothing to fail against. That curation is a product call and a
separate increment.

### [dev-2026-09-11-145807] DOC.12 — scheduled documentation rotation

The DOC.6 UTC age gate crossed its next boundary during PR #222 reconciliation. The canonical
rotation script moved 16 completed August 27 engineering-plan narratives and four resolved issue
entries verbatim into their history files, retaining plan status headers and searchable issue
history. Release notes and artifact/skill hygiene required no further moves. This is documentation
maintenance only; no product or rendering behavior changed.

### [dev-2026-09-11-root-choir-retired] ROOTCHOIR-RETIRE.1 / BUG-128 — retire Root Choir

Matt rejected the merged Root Choir live build because it read as Ricercar with warp added and
looked nothing like the selected `Martin - liquid arrows` animated oracle. The technical gates
proved a visible, moving feedback pipeline but did not preserve the defining moving subject:
pointed heads drawing long fine S-curves. Root Choir is removed from the production catalog,
including its shader, sidecar, dedicated tests, visual references, and design document.

The generic sidecar-owned `mv_warp` feedback-format resolver and its regression coverage remain;
that renderer capability is independent of the retired preset. Production preset count drops
from 32 to 31, and Root Choir cannot be selected even when uncertified presets are enabled.

### [dev-2026-09-10-165626] ROOTCHOIR.3.2 / BUG-125 — restore live feedback-format parity

Matt's next review found ROOTCHOIR.3.1 completely black in the live app. The attached clean
session ruled out audio starvation and frame delivery: all 2,406 drawables were presented, both
declared routes fired, and an exact 900-frame production replay remained visible at 0.202 mean
luma. The divergence was app-only: Root Choir's pipelines were compiled for its declared linear
`bgra8Unorm` feedback, but live setup ignored that declaration and allocated the default
`bgra8Unorm_srgb` textures because Root Choir was absent from a preset-name switch.

Live mv-warp setup now resolves `feedback_pixel_format` directly from the sidecar, matching the
loader and replay harness for linear BGRA, HDR RGBA, and the drawable-format default. Focused app
tests pin all three cases and remove the need to remember another display name when a preset
declares an override. No shader, audio route, or visual tuning changed; Root Choir remains
uncertified pending Matt's live Liquid Script verdict.

### [dev-2026-09-10-143900] ROOTCHOIR.3.1 / BUG-125 — rebuild Liquid Script around its selected motion oracle

Matt's first Liquid Script review found the replacement **VERY dark**, impossible to read, and
unlike the reference he selected. The attached clean “Combat Baby” session reproduced the problem:
a 900-frame production replay averaged 0.068 frame luma, only 27% of the 12-second oracle's 0.251
average. The shader had deliberately removed the oracle's primary feature stack and stamped a
moving broad ribbon for most of each writer lifetime, producing dim translucent bands.

Root Choir now writes compact pointed leaf/arrow heads with enamel-hot spines, saturated
amber/coral/violet rims, and paired fine S-curves from fixed local seeds. Feedback provides the
movement instead of smearing a moving seed; the composite uses a visible charcoal field and
bounded filmic lift. The same 900-frame session now averages 0.203 luma (0.190…0.218 trajectory),
with zero clipped and zero near-white pixels. The focused visibility gate was raised from the
meaningless 0.012 floor that admitted the defect to 0.14. Root Choir remains uncertified pending
Matt's live visual and musical verdict.

### [dev-2026-09-10-133622] ROOTCHOIR.3 / BUG-125 — replace the failed Newton flower with Liquid Script

Root Choir is rebuilt as an uncertified `direct+mv_warp` preset. Three asynchronous tapered
amber, magenta, and violet gestures write across a dark-violet field; persistent feedback bends
them through distributed counter-rotating eddies without global spin. `bassDev` continuously
changes advection and `beatComposite` accents new ink. The old Newton roots, circular tonal CPU
state, radial seam mechanism, flower centre, and white ring artifacts are removed.

The final 600-frame real-music replay was bounded and alive (mean saturation 0.532, mean luma
0.083, zero clipped/near-white area); its sampled motion gate reported zero spikes and zero frozen
transitions. The preset remains uncertified pending Matt's live review.
### [dev-2026-09-11-020000] BUG087.5 — the tap is gone from the local-file path

Follow-up Matt asked for after BUG-087 closed. `LocalFilePlaybackProvider` no longer installs a tap
on the player node at all: `PlayheadAnalysisClock` is the sole analysis source on this path.

The tap's only job was carrying audio to `onAudioSamples`, and on this path it was the thing capping
the whole MIR chain at 10 Hz — AVAudioEngine hands it ~0.1 s buffers whatever `installTap(bufferSize:)`
asks for. With the clock measured at 59.77 Hz on Matt's M7 capture, a real-time callback firing ten
times a second to be discarded is cost with no consumer.

Deleted with it: `handleTapBuffer`, `deliverSliced`, `interleavedScratch`, `requestedTapFrames`, the
requested-vs-delivered diagnostic, the `removeTap` teardown step, and **`TapBufferSlicing` plus its
test suite** — BUG087.3's slicing arithmetic, whose only production consumer was the slicing loop.
The provider drops 615 → 500 lines.

**Two things became errors that used to be quiet fallbacks, deliberately.** `PlayheadAnalysisClock.make`
now THROWS instead of returning nil: while the tap still forwarded, a clock that could not be built
degraded to it, and now there is nothing to degrade to — analysing nothing would render a dead
visualizer against audible music, so the provider refuses to start and the app's existing local-file
error path shows it. And `UZUME_LF_ANALYSIS_CLOCK` was removed: with no tap to return to, `=0` could
only have produced silence, and a flag that cannot do the thing it names is worse than no flag.

Streaming is untouched — it runs through `AudioHardwareCreateProcessTap`, a different capture path
this increment never reaches.

### [dev-2026-09-11-012500] BUG-087 RESOLVED — the local analysis clock is default-on after M7

Matt, watching `2026-09-11T01-22-10Z` live: *"I like it. It's punchy. Not exact, but close."* Measured
on that capture: bass **10.01 → 59.77 Hz**, mid 59.61, treble 59.20, centroid 59.66, flux 59.34,
against a 59.83 fps render. **5.97×**, and the slowest continuous column now changes on 99 % of
rendered frames. The local path matches streaming's 58.8 Hz; the arrival ceiling is gone.

`PlayheadAnalysisClock.isEnabled` inverted to default-on. `UZUME_LF_ANALYSIS_CLOCK=0` still forces
the tap back — kept because this replaces the audio source of the whole MIR chain on the path all
development runs on, and an escape hatch that needs no rebuild is worth one line for now.

**The option-A golden question turned out to be moot, which is worth recording rather than quietly
dropping.** `PresetRegressionTests` renders from fixtures through the harness, which never constructs
`LocalFilePlaybackProvider` — the clock is not in the golden path at all. The full suite run with it
default-on moved nothing: 1956 tests, 315 suites, 1 known issue, zero goldens regenerated.

⚠ **And VisualAudioOffset can no longer measure transport on this path.** `recordRawTapSamples` sits
inside the funnel, so with the clock driving, `raw_tap.wav` is the clock's OWN INPUT rather than the
tap's output — the test now measures analysis→row, not capture→row. Every band column also reads
below the correlation floor on both sessions, and the only readable one moved +45 → +50 ms on
different material, inside the noise. The rate is what carries this fix; the ear is what confirmed it.
Anyone quoting that table as a local-path transport number must re-derive its reference first.

*"Not exact, but close"* is the band-smoothing term — τ 77 ms bass / 116 ms mid-treble in
`BandEnergyProcessor`, which Matt declined at the design stage and this increment did not touch. That
is the next lever, and it is a D-004 trade rather than a defect.

### [dev-2026-09-10-234500] BUG087.4 — the local-file analysis clock, decoupled from tap arrival (flagged)

Local-file playback ran the whole MIR chain at **10.01 Hz** against a 59.8 fps render. Streaming runs
it at 58.8 Hz. Since essentially all development and all preset review happens on local FLAC, every
preset on that path was driven by a bus updating ~6x slower than the renderer.

**The defect is CADENCE, not staleness**, and that correction is what made this fixable. `FFTProcessor`
already fills its window from the newest frames of whatever it is handed, so audio is not old when it
arrives — nothing simply happens between arrivals. AVAudioEngine delivers a tap buffer every 0.1 s
whatever `installTap(bufferSize:)` asks for, so every `FeatureVector` field froze for ~100 ms: ~50 ms
of added lag on average, plus a visible staircase. Slicing the buffer was already measured and does not
help — all slices land in the same instant (BUG087.2/.3).

So the clock stops waiting for audio to arrive. On this path the whole file is already decoded, and a
read at the playhead is an array lookup bounded by nothing. `PlayheadAnalysisClock` ticks at 80 Hz on
its own queue, reads the span the smoothed playhead has just passed out of a bounded read-ahead, and
calls the same `onAudioSamples` funnel — so the MIR chain, and every consumer downstream of it, is
untouched. This is the advantage LFSTEM.1 created for stems and had not yet spent for MIR.

Measured through the real provider against a 59.8 fps render: produced 80.6 Hz, **observed 59.2 Hz**,
delivery gap median 12.1 ms, and **0 of 237 deliveries bunched** — the property BUG087.3 lacked.
Observed, not produced: BUG087.3's gate asserted `hz >= 40` from slice count and passed while the live
rate was 16.4 Hz, so both new gates measure how many distinct values a renderer could actually tell
apart. The session gate fails at 10.01 Hz on the pre-fix reference capture, as a real gate must.

Position accuracy was gated before anything was built on it, because a drifting read position
desynchronises analysis — worse than being uniformly late. Across 3.32 laps of a looping file:
backwards 0, behind-player 0, beyond-band 0, max lead 10.7 ms.

Behind `UZUME_LF_ANALYSIS_CLOCK=1` and **off by default**. The tap stays installed and keeps reporting
what AVAudioEngine delivers; retiring it is a separate decision. Honest ceiling unchanged: this
recovers the cadence term, not the τ 77–116 ms of band smoothing Matt declined to touch. BUG-087 stays
OPEN pending Matt's M7 — a ~6x change in what every preset on this path sees is not a silent change.

### [dev-2026-09-09-205204] ROOTCHOIR.2 / BUG-125 — remove the particle ring and make harmony reshape instead of spin

Matt's first live review rejected Root Choir: *“There is still white particles in a circular ring pattern,” “the center … looks like a muddle,” “not understanding the connection to the music,”* and *“the spin is odd and somewhat disorienting.”* The attached “Combat Baby” capture is clean and all five declared inputs fire, so this was the preset—not the audio or renderer.

The causes were authored and measurable. A radial orbit trap (`abs(length(z) - radius)`) was promoted into near-white highlights, directly drawing the ring. Live `tonal_tension` topped out at 0.091 while the aperture expected 0…1, leaving the centre nearly closed. Fifths/thirds changed by about 0.86/0.89 rad per analysis update, yet fifths was mapped directly to the whole organism's angle, making rotation the dominant response.

ROOTCHOIR.2 deletes the radial trap and white seam colour, uses dark leadwork with sparse amber light, maps the real tension/consonance ranges across their visual spans, grows a clean five-sided aperture, and bounds fifths orientation to ±0.34 rad. Thirds and tension now rotate/deepen a complex quadratic/cubic fold of the Newton starting domain, so harmony reorganizes basin topology rather than turning the frame. The preset remains uncertified and BUG-125 remains pending M7.

Evidence: clean session `2026-09-09T20-25-49Z`; route replay at `/private/tmp/root-choir-session-review/replay_report.md`; before sheet `/tmp/uzume_visual/20260909T203906/root_choir_compare.png`; after frames `/tmp/uzume_visual/20260909T204953/`; motion sequence `/tmp/uzume_visual/20260909T205058/` (430 frames). Focused tests, performance, lint, and app build are recorded in the closeout.
