# BUG-176 Understory live validation — 2026-10-09

## Verdict

The fresh-preparation/live-playback gate passes for the BUG-176 lifetime fix. A
fresh Debug build prepared LCD Soundsystem's nine-minute "Dance Yrself Clean"
under the checked-in 8 GB watchdog, reached ready, and rendered Understory for
five playback minutes. Process footprint peaked at **2,145 MB** during
preparation and remained between **752 and 795 MB** during playback. After the
first playback minute it remained between **784 and 795 MB**, an **11 MB** span
against the pre-written **±50 MB** limit.

This run does **not** close BUG-176. The separate 10-minute headless 1920×1080
soak, Release 1920×1080 frame-budget gate, complete allocation/lifetime audit,
and normal-speed manual visual/music-response check remain open.

## Identified inputs and build

- Source revision: `b54e065a` plus the preserved dirty Understory worktree.
- Dirty-worktree fingerprint: `c037f358871c424696d837a5770b8def96bc26858ea5784a7ac7d7f0b6cb892a`.
- Configuration: Debug.
- Named isolated build used for the run:
  `/private/tmp/uzume-understory-validation-b54e065a/Build/Products/Debug/Uzume.app`.
  The temporary build was removed after evidence capture.
- Executable SHA-256: `bf01fcf28ebc3f049f297387fb36aa057f651b2d5d32d130d41ebaf4670d1ba1`.
- Debug dylib SHA-256: `88d128a9a2544b16818db78a75233debb6f59ab8c847559b30b542870b7992e7`.
- Runtime PID: `41976`; `Scripts/memrepro.sh` confirmed that PID's command was
  the exact named bundle executable before sampling.
- Licensed local input:
  `/Users/Shared/memrepro/01 Dance Yrself Clean.mp3`, 21,526,859 bytes,
  SHA-256 `0e1dc8f765bf204b3e47cb5d60a335d8e20c0df15f371ddf8ed8b609d82312b7`.
- Understory resources were present in
  `Contents/Resources/UzumeEngine_Presets.bundle/Contents/Resources/Shaders/`.
- Watchdog command:
  `Scripts/memrepro.sh <named-app> bug176-validation-b54e065a 300`.
- The pre-existing persistent cache entry was restored on exit. The run used a
  fresh cache and therefore exercised full-file preparation.

## Footprint result

`ready_at=211 s`; watchdog stop condition was `ready + 300 s`. Raw two-second
samples are retained at
`docs/diagnostics/BUG176/bug176-validation-b54e065a.csv`.

| Playback interval | Samples | Minimum | Maximum | Mean |
|---|---:|---:|---:|---:|
| minute 1 | 29 | 752 MB | 841 MB | 782.4 MB |
| minute 2 | 29 | 784 MB | 784 MB | 784.0 MB |
| minute 3 | 29 | 789 MB | 794 MB | 791.9 MB |
| minute 4 | 29 | 794 MB | 795 MB | 794.4 MB |
| minute 5 | 29 | 791 MB | 795 MB | 793.4 MB |

Across all samples after playback minute 1: 117 samples, minimum 784 MB,
maximum 795 MB, mean 790.9 MB, span 11 MB. Preparation produced a bounded
temporary peak of 2,145 MB and then released to the playback plateau at ready.

## Session and renderer evidence

The retained session is
`/Users/braesidebandit/Documents/uzume_sessions/2026-10-09T14-36-34Z`.

- `features.csv`: 17,820 data rows.
- `stems.csv`: 17,820 data rows.
- `raw_tap.wav`: retained; output sample rate 48 kHz.
- `Scripts/analyze_session_chain.sh`: `CHAIN_HEALTH: verdict=clean reasons=[]`,
  peak −5.7 dBFS, no full-scale run.
- Stem routes were nonconstant: `drumsEnergyDev` 0…4.87819,
  `bassEnergyDev` 0…7.15293, `vocalsEnergyRel` −0.55610…2.76553,
  `vocalsEnergyDev` 0…2.76553, and `otherEnergyDev` 0…2.71660.
- Relevant feature routes were nonconstant: `bassDev` 0…3.71345,
  `treb_dev` 0…0.11466, `beatPhase01` 0…0.99977, and `beatComposite` 0…1.
- GPU allocation remained 359 MB (3% of the reported 12,124 MB budget).
- Final drawable heartbeat: 17,408 frames; descriptor 17,407/17,407;
  drawable 34,814/34,814; unique presented 17,407/17,407; command completed
  17,406/17,407; zero failures; zero unpresented; no pending frame.

This live Debug window rendered at 900×600. Its `frame_gpu_ms` values are not
evidence for the required Release 1920×1080 frame-budget threshold. No review
video was recorded, so the run also makes no claim about visual fidelity or
felt musical response.

## Gate accounting

- **Pass:** fresh preparation plus five playback minutes under the mandatory
  watchdog; peak below 3 GB; post-first-minute footprint flat within ±50 MB;
  exact binary and source state identified; full route/session capture present.
- **Supporting evidence only:** fixed 359 MB GPU allocation and balanced
  drawable lifecycle during this five-minute window. These do not replace the
  required allocation audit or deliberately slowed frame-in-flight test.
- **Still required:** 10-minute production-path headless soak at 1920×1080 with
  per-minute resident/GPU/lit-and-changing results and per-frame autorelease
  boundary; Release 1920×1080 `PresetFrameBudgetTests`; explicit resource and
  bounded-state audit; normal-speed manual visual and music-response check.
