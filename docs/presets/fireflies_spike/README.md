# Fireflies look-spike (FF.0, scratch, not engine code)

A throwaway concept spike for slate entry **D1 · Fireflies** (`docs/presets/BETA_SCENE_SLATE_2026-09-24.md`
§00 lane 1, §4 D1). It is Python and a headless browser, with no Metal, no Swift and no sidecar.
Everything it renders lives outside the repo, in `~/Documents/uzume_spikes/fireflies/`.

| File | What it is |
|---|---|
| `ncase_capture.js` | Runs Nicky Case's *Fireflies* headless in Playwright and captures frames plus the order parameter. |
| `fireflies_spike.py` | The look-spike: 600 pulse-coupled fireflies in a 2.5-D dusk meadow, driven by a recorded capture. |
| `plot_coherence.py` | Draws the coherence-vs-time small multiples and prints the luminance table. |

Requires numpy, pillow and matplotlib: `/usr/bin/python3` on this Mac has them, Homebrew `python3` does
not. Also ffmpeg, plus Playwright for the ncase capture (borrowed via `NODE_PATH`; see the script header).

```
/usr/bin/python3 docs/presets/fireflies_spike/fireflies_spike.py --help
```

## 0. Test material, and one shortfall

**No recorded local-file session exists for any beta playlist track.** The only playlist-track recording,
`beat-match-test-session` (2026-07-27), is a Spotify streaming session. So the captures were generated
with the existing, env-gated `FixtureSessionCaptureGenerator` (`UZUME_GEN_SESSION_AUDIO`, no code
change). It runs the real files from `/Volumes/Extreme SSD` through the production chain: Beat This!
grid install, `MIRPipeline`, `StemSeparator` and `StemAnalyzer`. That is local-file semantics with zero
lag, and nothing is synthesised (FA #27).

- **Location:** `~/Documents/uzume_spikes/fireflies/sessions/fixturegen-*`. They are deliberately not in
  `uzume_sessions`, so they don't arm other sessions' gates.
- **Chain verdict:** `ChainHealthAnalyzer` grades all 9 captures `verdict=clean`, with the note
  `no_raw_tap`.
- **Shortfall: 30 s, not 45 s.** The generator hard-caps a capture at 30 s (`maxSeconds = 30`,
  `FixtureSessionCaptureGenerator.swift`). Lifting it means editing Swift, which this spike may not do. So
  every film covers the first 30 s from the track start (cold start included). A second capture of
  Warszawa's **last** 30 s exercises near-silence: `near_silent01` never fires in the first 30 s of any
  of the six tracks.

| Kind | Track | Census `beat_irregular` → K stand-in |
|---|---|---|
| (a) regular 4/4 | LCD Soundsystem, "Dance Yrself Clean" (+ B.O.B. metrics) | false → **1** |
| (b) swung / rubato | Radiohead, "Pyramid Song" (+ Take Five metrics) | false → **1** |
| (c) near-beatless | David Bowie, "Warszawa" (first 30 s + last 30 s) | unknown (no drums-stem tempo) → **0.5** |
| control | Massive Attack, "Teardrop" (metrics only) | true → **0** |

## 1. Artifacts 1 + 2: the watched source, verified in motion

**Source.** Nicky Case, *Fireflies*: https://ncase.me/fireflies/ and https://github.com/ncase/fireflies
at `165d16c` (`LICENSE.txt` = **CC0 1.0**). The model, from `js/index.js:217-243`:

- a clock runs 0 → 1 at 0.3/s and the firefly flashes at 1;
- each flash nudges every neighbour within 200 px forward by `0.035 × its own clock`, capped at 1.

**Capture.** `ncase_capture.js` stops the PIXI ticker and steps the flies by hand at 30 fps, because rAF
does not fire headless. It uses ncase's defaults with *Nudge thy neighbor* ON, a seeded random start and
150 flies. A 150 s probe put the lock at 20–30 s: R = 0.07 at 0 s, 0.39 at 20 s, 0.87 at 25 s, 0.99 at 45 s.
The 20 s capture therefore starts at t = 10 s.

- `ncase_source.mp4`, `ncase_sheet.png`
- `Scripts/motion_gate.sh fireflies_ncase …`: 600 frames, mean 1.15, median 0.85, max 9.29, 30 spikes (the
  flash frames), 0 frozen.

**Verdict: it delivers the concept across the sequence, not just in one frame.** The eight samples run:

1. scattered random blinks;
2. clusters flashing together (the relay spreading);
3. sparse again;
4. one full-screen unison flash;
5. dark.

Two things do **not** port:

- **It is a black field with sprite bugs.** The meadow is ours to build.
- **At lock, ncase's whole frame flashes.** This is the D-157 risk, and it is the reason for small points
  on a lit dusk ground (see §3).

**Real footage (motion reference only).** Radim Schreiber / Discover Life in America, *Virtual Fireflies
Event*, https://www.youtube.com/watch?v=jneuOra3NvI (Great Smoky Mountains). I sampled its frames
through a canvas at 1500 s and 1800 s:

- **The look:** a dusk meadow with a dark tree line and a blue-grey sky, exactly slate option A.
- **Flash size:** each flash is a few pixels (≤ 10 px at 640×360).
- **Flash duration:** 0.25–0.35 s, from 5–6 consecutive frames at about 60 ms.
- **Dark between flashes:** the fireflies are invisible between flashes.
- **Frame mean:** it did not move with the flashes (44.9 → 44.1 over 24 s, which is dusk falling). One
  spectator's camera flash showed as a 43 → 70 frame-mean spike at 1820.8 s. That is exactly the global
  pulse D-157 forbids.

At this density the flashes were uncorrelated. The "wave" claim rests on Sarfati, Hayes and Peleg,
*Self-organization in natural swarms of Photinus carolinus*, Science Advances 2021
(https://www.science.org/doi/10.1126/sciadv.abg9259; bioRxiv 10.1101/2021.01.26.428319):

- flashes are uncorrelated at low density;
- at high density they arrive as synchronous bursts;
- bursts nucleate and propagate across the swarm in a relay.

**What makes the real thing magical** is that relay. The unison isn't imposed: it spreads, neighbour to
neighbour, before the lock. The spike reproduces it with a 60 ms reaction latency on the ncase nudge.

## 2. The engine fact: is there a GPU-visible "how clear is the beat" signal?

**No. The named infrastructure increment is required.**

| Candidate | Code | Measured on the 6 captures (DYC, B.O.B., Take Five, Pyramid, Teardrop, Warszawa) | Carrier? |
|---|---|---|---|
| `assessBeatIrregularity` → `beatIrregular` | `Session/BPMMismatchCheck.swift:210`; consumed only by the planner/scorer (`Orchestrator/PresetScorer.swift:246`, via `UzumeApp/VisualizerEngine+Stems.swift:624`) | CPU-only; no shader field | Right signal, wrong side of the bus |
| `pulse_amp01` | `DSP/BeatPulseClock.swift:26-29` (doc: "music-present gate"), `:328` (target = anchored AND silence run < 0.5 s; no beat input at all) | mean 0.91–0.99 on **all six**, including Warszawa (0.98) and flag-irregular Teardrop (0.99) | **No**: a silence gate |
| Grid presence | reactive fallback writes `beatsPerBar = 4`, `barPhase01 = 0` (`DSP/MIRPipeline.swift:450-458`) | a grid was installed on **all six**; Beat This! gives beatless Warszawa a 54.5 BPM grid (24 beats in 30 s) | **No**: every track has one |
| `beats_per_bar` decline (D-210) | a decline is `beatsPerBar = 1` (`Session/BeatGridAnalyzer.swift:238`), but only on the `UZUME_BARLINE=1` / windowed arms, both **off by default** (`:127`, `:329`); the default meter falls back to `(4, 0)` (`DSP/BeatGridResolver.swift:193`) | values 4, 3, 4, 2, 2, 4; **never 1** | **No**: and it is bar confidence, not beat clarity (D-210: "decline the bar, keep the beat") |
| `barConfidence` | `DSP/BeatGrid.swift:60` | not in `FeatureVector` | No (CPU-only, and it's about bars) |
| Drums-stem presence (extra check) | `StemFeatures.drums_energy` / onset rate | drums share 0.21–0.25 and onset rate 4.1–5.7/s on all six; Warszawa (0.253, 5.7/s) is indistinguishable from B.O.B. (0.314, 4.5/s) | **No** |

`FeatureVector` has no free floats: float 56 became `near_silent01` (`Common.metal:104-109`).
`StemFeatures` has spare slots `_pad14`–`_pad22` (`Common.metal:214-215`).

**The named increment (not built; Matt: built only if FF.0 passes):**

> One float in `StemFeatures` (a `_pad14` slot): 1 = steady, 0 = irregular, 0.5 = unknown. It is written at
> track change from `TrackProfile.beatIrregular` and cleared at session boundaries on every path (the
> `@Published` both-paths rule, BUG-024).

**What this spike adds to that spec (evidence, not a decision):**

- **Unknown half-entrains.** Warszawa's flag is *unknown*, because its drums stem has no tempo. At 0.5 the
  swarm half-entrains to Beat This!'s 54 BPM grid on a beatless track: R 0.49, on-beat wandering ±0.4
  (§3). For this scene, *unknown because there are no drums* wants to read as **free**. The scene can map
  0.5 → 0 itself, so the float's spec need not change.
- **The flag calls Pyramid Song steady.** The census gives a disagreement of 0.099, but in June the same
  flag condemned Pyramid at 47.7 % (D-154 amendment). With the flag as K, Pyramid entrains firmly (§3).
  D-154's own record says its 70 BPM grid really is right, so that may be correct. But the flag is a
  30 s-window estimate that flips on this track.

## 3. Artifact 4: the look-spike

**Model** (`fireflies_spike.py`):

- **Mutual coupling:** the ncase nudge, applied once per flashing neighbour, with an 80 px radius (about 20
  neighbours each).
- **Spread:** a 5 % natural-period spread.
- **Relay latency:** a nudged clock is capped 60 ms short of 1, so relays travel as visible sweeps.
- **Music coupling:** on each beat-grid tick (every m-th beat, with m ∈ {1, 2, 4} so the flash cycle sits
  near 1 s), each clock is pulled toward 0 by `K × 0.3` of its wrapped error. Each firefly also retunes its
  own period (`K × 0.05`, Ermentrout 1991, the *Pteroptyx malaccae* model). Without the retune, the swarm
  locks *early* of the beat and oscillates around it.
- **Near-silence:** from `near_silent01`, all but 5 % stragglers fade to 2 % visibility (τ 1.5 s). The dusk
  sky and meadow never go black (D-037).
- **Ticks:** from `beatPhase01` wraps in the capture, sub-hop interpolated.

**Tuning, stated honestly.** The two coupling gains were swept on DYC and then checked unchanged on
Pyramid Song, Take Five and B.O.B. The arc is slowest on DYC (the beat lands at about 15 s) and fastest on
Pyramid (about 6 s). The neighbour strength was set so that neighbours alone cannot lock a 30 s clip
(R stays about 0.12). This is a design choice: without it ncase's model syncs any meadow on its own, and
the music would not be what completes the unison.

**Films** (1280×720, 30 fps, 30 s from the track start, with the track's audio; in
`~/Documents/uzume_spikes/fireflies/`):

| Film | K |
|---|---|
| `a_dance_yrself_clean.mp4` (a) | 1, stand-in |
| `b_pyramid_song.mp4` (b) | 1, stand-in |
| `c_warszawa.mp4` (c) | 0.5, stand-in |
| `c_warszawa_K0.mp4` (c) | 0: what a beatless reading has to deliver |
| `c_warszawa_tail_near_silence.mp4` | 0.5: Warszawa's last 30 s; `near_silent01` from 25.1 s |
| `r1_true_left_vs_decoy_right.mp4` | 1: R1, side by side |

**Coherence** (`coherence_plots.png`, one panel per run). R = |mean e^{2πiθ}| (1 = unison). "On-beat" =
Re(mean e^{2πiψ}) of the flashes in the last 2 s, against the **true** grid at beat level: +1 means every
flash is on a beat, −1 means half a beat off, and the chance band is about ±0.03 for ~1,000 flashes.

| Run | K | R 0–5 s | R 25–30 s | on-beat 25–30 s | first on-beat > 0.6 |
|---|---|---|---|---|---|
| (a) Dance Yrself Clean | 1 | 0.63 | 0.97 | **+0.86** | 15.4 s |
| DYC, same audio | 0.5 | 0.42 | 0.85 | +0.61 | 26.4 s |
| DYC, same audio | 0 | 0.15 | 0.12 | +0.01 | never |
| R1 decoy (DYC, grid +½ beat) | 1 | 0.49 | 0.96 | **−0.85** | never |
| (b) Pyramid Song | 1 | 0.62 | 0.97 | +0.84 | 5.7 s |
| Take Five | 1 | 0.70 | 0.99 | +0.92 | 7.3 s |
| B.O.B. | 1 | 0.67 | 0.98 | +0.94 | 8.8 s |
| (c) Warszawa | 0.5 | 0.16 | 0.49 | +0.00 | 21.5 s (wanders) |
| (c) Warszawa | 0 | 0.15 | 0.11 | −0.04 | never |
| Teardrop | 0 | 0.15 | 0.11 | +0.03 | never |

**Entrainment on (a): yes. Not on (c): yes for the beat** (Warszawa's on-beat is +0.00 at the end).
**Only half-yes for the swarm under the stand-in's 0.5**: R reaches 0.49 against 0.11 at K = 0.
**Cold start is incoherent by construction:** R ≈ 0.04 at t = 0 on every run. At K = 1 the swarm coheres
within about 3 s and finds the *beat* 6–15 s later. That second step is the arc.

**Flash safety** (frame-mean Rec.709 luma of the encoded frame, 0–1; `plot_coherence.py` prints it):

| Film | Mean luma | Max per-second range | Max Δ / frame (D-157 gate < 0.05) |
|---|---|---|---|
| a_dance_yrself_clean | 0.192 | 0.0217 | 0.0095 |
| b_pyramid_song | 0.193 | 0.0226 | 0.0148 |
| c_warszawa | 0.192 | 0.0134 | 0.0037 |
| c_warszawa_K0 | 0.193 | 0.0063 | 0.0015 |
| c_warszawa_tail_near_silence | 0.194 | 0.0166 | 0.0052 |
| r1_decoy_dance_yrself_clean | 0.192 | 0.0216 | 0.0100 |

Every film passes the per-frame gate by 3.4× or more. The per-second range at full unison is about 0.02
(about 5/255 on a 0.19 ground). The frame does lift slightly when all 600 flash on the same beat. That
lift is the unison itself, spread over tiny points, and the build should re-measure it at 1080p with its
real point sprites.

**Motion gate** (`Scripts/motion_gate.sh fireflies <film>`; full output in `motion_gate_results.txt`,
samples in `gate_<film>/`):

| Film | Max inter-frame diff (/255) | Spike frames (> 3× median) | Frozen frames |
|---|---|---|---|
| a | 2.2 | 295 | 689 |
| b | 3.2 | 180 | 622 |
| c | 1.3 | 9 | 641 |
| c_K0 | 0.7 | 0 | 713 |
| tail | 1.6 | 42 | 521 |
| decoy | 2.3 | 251 | 689 |

**How to read it for this look.** "Frozen" is the static meadow, with no camera motion by design. The
"spikes" are the unison flash frames, which stand at 3× a near-zero median. The spike count tracks
entrainment: 295 on (a) against 0 on (c) at K = 0, so the gate reads the concept working. There is no
jitter. Every change is a point, and the largest whole-frame change is 3.2/255.

## 4. Rewatch checks

- **R1 decoy (`r1_true_left_vs_decoy_right.mp4`): distinguishable by measurement.** Against the true
  grid, the true film ends at **+0.86** on-beat and the half-beat decoy at **−0.85**, both far outside the
  ±0.03 chance band. Before about 12 s both films are still finding the beat and cannot be told apart,
  which is correct for a cold start. Whether it is distinguishable *by eye and ear* is Matt's call. With
  audio, the true swarm should flash with the kick-snare and the decoy between them.
- **R2 two-song sheet (`r2_two_song_sheet.png`, DYC | Warszawa, eight evenly spaced frames): different
  scenes.**
  - DYC is all-or-nothing: either the whole meadow is lit (8.6 s) or it is nearly empty.
  - Warszawa always shows a scattered handful.
  - Evenly spaced stills under-sample a 1.2 s flash cycle, so the coherence panels are the stronger R2
    evidence.
- **R3 arc (`coherence_plots.png`):**
  - K = 1: random, then a coherent swarm (about 3 s), then on the beat (6–15 s).
  - K = 0: flat.
  - The near-silence tail dims to a few stragglers over the last 5 s (`near_silence_sheet.png`).
- **R4 novelty:** emergent simulation. The lock time and phase path differ per track and per seed.
- **R5 restraint:** the flash-safety table above. Calm music keeps the swarm free and dim.

## 5. The story (See / Move / Music)

- **See:** a dusk meadow under a tree line, full of tiny yellow-green fireflies that are dark between
  flashes.
- **Move:** they blink at random at the top of the track. Neighbours nudge neighbours, so flashes relay
  across the meadow in sweeps. Then the whole meadow flashes as one, about once a second, and stays
  locked.
- **Music:** **the beat grid pulls the swarm into unison, as strongly as the beat is clear.** On a clear
  beat they lock onto it within about 15 s: DYC, Take Five, B.O.B. and Pyramid all end at +0.84 to +0.94.
  On an irregular or beatless track they stay free: Teardrop and Warszawa at K = 0, R ≈ 0.11. Near-silence
  leaves a few stragglers.

## 6. DECISION-NEEDED (Matt)

**Where do the fireflies live?**

- **A. A dusk meadow with a tree line.** Naturalistic and calm, with a horizon that gives scale. It is the
  second-screen look. It is also exactly what the real footage looks like, and its lit ground is what
  keeps a unison flash from pulsing the frame.
- **B. A pure black field.** Abstract and minimal, with the swarm as the only subject. This is ncase's
  look, and its unison lifts the whole frame from black: the D-157 risk.
- **C. A forest interior with fog.** More depth and mood, but darker and busier. Trunks would hide flashes,
  which breaks up the unison.

**Recommendation: A. Default if no reply: A.**

**Also flagged (default applies without a reply):** should a track whose beat clarity is *unknown*
(Warszawa: no drums, so no drums tempo) behave as **free**, like K = 0, or **half-coupled**, like 0.5?
Free keeps ambient music calm. Half-coupled makes the swarm half-lock to a grid the listener can't hear.
**Recommendation: free. Default if no reply: free.**
