# Kagura concept look-spike (KAG.0 — scratch, not engine code)

A point-light dancer built from CMU motion capture and time-warped onto real Uzume beat grids, written to
answer three concept questions with frames: does it read as dancing *to* the song, which dance families
survive warping, and how bad is foot-slide. `kagura.py` imports nothing from Uzume; it is not a porting
source for the engine. This is `preset-concept` gate artifacts 1, 2 and 4, plus the story (artifact 3).

**Status: stopped for Matt's go / no-go (2026-09-24).** Films are in `~/Documents/uzume_spikes/kagura/final/`
(never in git, D-211).

## Story (See / Move / Music)

- **See:** fifteen points of light on near-black, one each at the head, neck, shoulders, elbows, wrists, pelvis,
  hips, knees and ankles of one human body. Each point drags a trail that fades out over 0.4 s.
- **Move:** over 30 s the figure performs captured salsa (or Lindy) steps. It switches to a different capture
  on a bar line every 1–4 bars, with a one-beat crossfade. The camera never moves.
- **Music:** each beat of the cached grid coincides with a foot touching the floor. At the ×1 metrical level
  80 % of footfalls fall within ±⅛ beat of a grid beat (chance is 25 %). Bass energy (`bass_att`, 1.5 s
  smoothing) widens or narrows arm reach by at most ±25 %.

## Three-part concept bar (PRESET_SESSION_CHECKLIST Part 2)

| Bar | Result |
|---|---|
| Iconic subject at fidelity | **Partial.** The figure reads as a human in every still where it dances in place (native clips, Pyramid sway, Lindy). It **stops reading** while the salsa dancer travels: every joint draws the same horizontal streak and the figure becomes a stack of lines (gate samples 3 and 7 of the fast salsa film). |
| Clear musical role | **Yes, measured; not yet seen.** Footfalls on the grid beat (above), and the decoy moves them to the off-beat (R1). I could not see the difference in stills (R1 below). |
| Infra-feasible | **Yes for rendering** (15 `point`s plus trails is cheap). **The cost is data:** an offline mocap → clip-library pipeline, and the library is the limit (below). D-154 / D-210 fallback works through existing signals. |

## Rewatch bar (R1–R5)

| # | Answer |
|---|---|
| R1 legible | **Metric: yes. My eye, from frames: no.** True grid: 48 of 114 footfalls in the on-beat eighth. Grid shifted by half a beat: 47 of 118 in the half-beat eighth. The strip + frames at the ticks did not let me tell which panel was correct (§4). Whether it is legible *with the audio* is the question for Matt's look. |
| R2 per-track identity | **Fails in this spike.** Olive Drab (86 BPM) and Wild Rose (166 BPM) use the same three salsa captures. Their sheets differ only in streak length (§4). Identity would have to come from choosing clips by tempo and mood, and the CMU library is too small to do that. |
| R3 arc | **Not tested.** 30 s preview grids; the spike has no arc mechanism, only the clip cycle. |
| R4 source of novelty | **Character** (captured human motion). The ceiling is the library: about 30 usable CMU dance trials, 2–30 s each, so repetition within one song is likely. |
| R5 restraint | **Passes.** Motion gate shows 0 spikes on all four beat films. The irregular fallback is near-still (851/899 frozen frames) with no flash. |

---

## §0 Provenance and deviations from the prompt

- **Mocap:** CMU Graphics Lab Motion Capture Database, ASF/AMC at 120 fps, downloaded to
  `~/Documents/uzume_spikes/kagura/mocap/`. The FAQ reads *"may be copied, modified, or redistributed without
  permission"*. Nothing goes in git. **`103_03`–`103_08` as served are byte-identical to `93_03`–`93_08`**
  (md5 match), so "Lindy" here is subject 93 only.
- **Beat grids:** there were **no two clean local-file recorded sessions** in `~/Documents/uzume_sessions/`
  (only `fixturegen-love_rehab` carries a `chain_health.json`). Instead of TempoDumpRunner, I ran the audio
  through `FixtureSessionCaptureGenerator` (env `UZUME_GEN_SESSION_AUDIO`). It is the full production chain
  (Beat This! grid → MIRPipeline → SessionRecorder schema, 30 s preview clamp) and writes a real
  `features.csv` with `beatPhase01` / `grid_bpm` / `barPhase01_permille`, so no grid is synthesised (FA #27).
  Output went to `~/Documents/uzume_spikes/kagura/sessions*/`, *not* `uzume_sessions/`, so it arms no cert
  gate. Audio: the BeatBench corpus (`~/uzume_beatbench_fixtures/`) plus the Cindy Lee *Diamond Jubilee*
  album in `~/Downloads`, used for the slow and fast tracks because the corpus has no regular track ≤ 95 BPM.
- **Python:** system python has no numpy, so a venv was created at `~/Documents/uzume_spikes/kagura/.venv`
  with numpy, scipy and pillow.
- **Branch:** `spike/kag-0`, created in the session's existing worktree (at `main` e49d3bec) rather than a new
  worktree.

| Film | Track | Grid (production chain) | Why |
|---|---|---|---|
| slow | Cindy Lee — *Olive Drab* | 85.77 BPM, 4/4, IBI CV 0.019 | regular, ≤ 95 |
| mid | *Billie Jean* | 116.88 BPM, 4/4, IBI CV 0.021 | ~120 |
| fast | Cindy Lee — *Wild Rose* | 166.10 BPM, 4/4, IBI CV 0.029 | ≥ 160, regular 4/4 (*Take Five*, 169 BPM, reads as bpb 2) |
| irregular | *Pyramid Song* | 65.08 BPM, **bar declined** (0 bars) | the D-154 calibration catch (17.4 % folded grid-vs-drums disagreement); D-210 bar decline |

## §1 Sources in motion: verdict and joint set

I rendered three clips as plain point-lights at native speed, with no trails or audio (`kagura.py native`,
`~/Documents/uzume_spikes/kagura/native/`), ran `motion_gate.sh kagura` on each and read the samples. I view
motion as frame sequences (2–10 fps sheets plus gate samples), not as playback.

| Clip | Gate (mean / spikes / frozen) | Reads as a person at a glance? |
|---|---|---|
| 60_03 salsa | 0.65 / 0 / 70 of 299 | **Yes.** Upright body, arms working, weight shifting foot to foot. It travels out of a fixed frame within 10 s. |
| 93_05 Charleston/Lindy | 0.51 / 0 / 54 of 135 | **Yes.** Knees and ankles swing clearly. Only 4.5 s long. |
| 05_02 modern | 0.27 / 7 / 244 of 279 | **Yes.** Arms-out poses read at once. The 7 spikes are the pirouette arm sweep (frames 136–172), real motion rather than a pop. |

**Joint set: 15** (the BML/Johansson set: head, neck, pelvis, and shoulders, elbows, wrists, hips, knees and
ankles on each side). 13 (no neck or pelvis) was indistinguishable from 15 in the sheets but loses the torso
anchor. 17 (adding toes) duplicates the ankles as close pairs in a still and adds clutter.

## §2 Clip tempo, stability and foot-slide at native speed

`kagura.py tempo` gives the autocorrelation BPM (pelvis vertical velocity combined with a footfall train).
The **step rate** is the median footfall interval that the warp actually uses. Footfalls are debounced ankle
contacts (ankle within 4 cm of its floor, vertical speed < 0.35 m/s, gaps and blips < 80 ms removed). Foot-slide
is the median horizontal ankle speed during contact.

| Clip | Family | Length s | AC BPM | Step rate /min | Footfall IOI CV | Foot-slide cm/s |
|---|---|---|---|---|---|---|
| 60_01 | salsa | 18.7 | 76.9 | 185 | 0.69 | 12.6 |
| 60_03 | salsa | 15.2 | 41.1 | 203 | 0.63 | 12.1 |
| 60_08 | salsa | 28.5 | 102.7 | 195 | 0.58 | 13.1 |
| 61_02 | salsa (partner) | 17.5 | 217.7 | 195 | 0.74 | 18.4 |
| 93_04 | Charleston/Lindy | 4.2 | 177.8 | 171 | 0.34 | 11.1 |
| 93_05 | Charleston/Lindy | 4.5 | 193.6 | 176 | 0.30 | 9.1 |
| 93_07 | Charleston/Lindy | 2.0 | 107.6 | 203 | 0.21 | 15.3 |
| 93_08 | Charleston/Lindy | 4.6 | 201.4 | 195 | 0.51 | 26.2 |
| 05_02 | modern | 9.4 | 66.5 | — (pelvis-downs; AC peak 0.11) | 0.27 | 5.0 |
| 05_11 | modern | 4.9 | 90.7 | 90 (5 steps) | 0.15 | 5.5 |
| 05_12 | modern (sway) | 11.3 | 71.4 | — (pelvis-downs) | 0.22 | 3.4 |
| 15_05 | twist / cabbage patch (mixed trial) | 191.2 | 164.2 | — (IOI CV 3.97) | — | 2.9 |
| 55_02 | lambada | 18.2 | 88.9 | 136 | 0.54 | 8.9 |
| 143_35 | macarena | 10.7 | 112.5 | — (5 steps) | 1.01 | 2.0 |

Full autocorrelation table: `~/Documents/uzume_spikes/kagura/tempo_table.md`.

**Reading.** No clip has a stable pulse by a single autocorrelation: AC BPM swings 41–218 across salsa trials
of the same dance. Footfalls carry the tempo far better. Salsa steps are dense (185–203 per minute, matching
salsa's 180–200 BPM music) but uneven (IOI CV ≈ 0.6–0.7, from quick-quick-slow plus pivots). **Salsa's
native foot-slide (12–18 cm/s) is pivoting on the ball of the foot**, which the ankle marker records as slide;
it looks natural at native speed.

## §3 The look spike

`kagura.py film <session> <audio> <out.mp4> [--family …] [--shift-beats …] [--irregular] [--strip]`

- **Time-warp:** clip beat events = the dancer's own footfalls (feet landing within 40 % of a step are merged).
  The metrical level m ∈ {×½, ×1, ×2} grid beats per step is chosen for the nominal rate closest to 1.
- **Phase-align:** grid beat k is pinned to footfall `1 + k/m`, and a PCHIP (monotone, C¹) map runs render time
  → clip time through the pins. The phase correction is spread across each beat interval and never jumps.
  Because the capture's steps are uneven, the **local playback rate varies within a beat**: p10 / p50 / p90 of
  0.60 / 0.99 / 1.47 on the slow film and 0.88 / 1.20 / 1.84 on the mid film.
- **Energy chooses scale:** smoothed `bass_att`, normalised to its own p10–p90, `tanh` soft-saturated, scales
  **arm** excursion (elbow and wrist about the shoulder) by at most ±25 %. *Deviation from the prompt's "about
  the pelvis":* scaling a planted foot's offset while the pelvis moves drags the foot, which measured as a
  large rise in slide, so the legs are left alone.
- **Look:** soft-glow points (2.6 px core, 9 px halo), 0.4 s trails (6 sub-samples per frame, decay to 5 % at
  0.4 s), filmic shoulder, near-black ground. Orthographic three-quarter view (35° yaw), fixed camera.
- **Clip changes:** on bar lines (every 4 bars, or sooner if the capture runs out), crossfaded over one beat.
  The incoming clip is placed so the midpoint of its ankles matches the outgoing clip's at the cut. A 2 s
  zero-phase leash (Gaussian of the pelvis floor path) keeps travelling dancers in frame.
- **Irregular / bar-declined** (D-154 / D-210): an unwarped modern sway (05_12) plays forward then backward.
  The first render used a plain modulo loop and **popped** at the wrap (frame 339, gate max diff 2.05). The
  ping-pong fix brought the max to 0.78.
- Two look passes were used: pass 1 as above, pass 2 made the figure larger (255 px/m), made trails 2.2×
  brighter and tightened the leash from 3 s to 2 s.

| Film (30 s, 30 fps, audio muxed) | Clip level / local rate p10–p90 | Footfalls ±⅛ beat of a grid beat (chance 25 %) | Gate mean / spikes / frozen | Foot-slide cm/s (outside / inside crossfades) |
|---|---|---|---|---|
| slow Olive Drab — salsa | ×½ / 0.60–1.47 | 41 of 91 = 45 % (the other half land near the "and") | 0.74 / 0 / 203 | 18.5 / 39.5 |
| mid Billie Jean — salsa | ×½ / 0.88–1.84 | 52 of 114 = 46 % (the other half land near the "and") | 0.90 / 0 / 125 | 20.7 / 80.3 |
| fast Wild Rose — salsa | ×1 / 0.58–1.67 | 70 of 87 = **80 %** | 0.79 / 0 / 171 | 20.5 / 74.1 |
| fast Wild Rose — Lindy | ×1 / 0.61–1.60 | 63 of 80 = **79 %** | 0.81 / 0 / 92 | 47.2 / 71.1 † |
| irregular Pyramid Song — sway fallback | unwarped | n/a (4 footfalls) | 0.16 / 185 ‡ / 851 | 4.6 / — |

† Unexplained. Lindy in-place kicks may be mislabelled as contacts by the ankle-height test; not investigated.
‡ The spikes are relative to a near-zero median (0.09): ordinary arm moves of an almost-still figure. Max 0.78.

**Motion verdict (read from gate samples and 10 fps sheets):**
- **Smooth everywhere.** No pops after the ping-pong fix.
- **In-place dancing reads as a person** (Lindy, sway). The Lindy trails draw looping kick arcs at the feet,
  which is look B working.
- **Travelling salsa does not read.** In about a third of the samples the body is a stack of horizontal
  streaks.
- **Lindy repeats.** The 2–5 s captures repeat every bar (1.4–2 s), which is visible as a loop.

**Dance families that survived warping:**
- **Salsa:** survives the warp (it locks at ×1 and ×½ and plays at 0.6–1.8× local rate) but **fails the look**
  whenever it travels.
- **Lindy / Charleston:** has the best lock and the best trail look, but **fails on material**: the CMU trials
  are too short to hold a phrase.
- **Modern:** **does not survive as a stepping dance.** It has no footfall pulse, so the warp pins
  pelvis-downs. The pass-1 films (`films/*_modern.log`) have only 13–21 footfalls in 30 s. Footfall lock is at
  chance on mid and fast (R 0.24 and 0.26 against chance 0.25 and 0.19) and R 0.69 on slow (n = 15, chance
  0.23). Pelvis-downs reach R 0.17–0.36 against chance 0.11. There is too little stepping to show a beat. It
  works as the calm fallback.
- **Twist / cabbage patch (15_04, 15_05; 190 s, in place, 2–3 cm/s slide) and macarena: untested.** They are
  mixed with non-dance actions and need segmenting first. They are the obvious next candidates, since in-place
  motion fixes the streak problem.

## §4 Rewatch checks

**R1 decoy.** `decoy_A` is Billie Jean, salsa, grid shifted +½ beat. `decoy_B` is the true grid. Both carry a
strip of the *true* beat ticks scrolling past a centre playhead. They are side by side, unlabelled, in
`final/r1_decoy_side_by_side.mp4` / `.gif`. I built them, so I was not blind to the order. Looking at frames
100 ms before, at, and 100 ms after six consecutive ticks (`final/r1_feet_at_beats.png`), I **could not tell
which panel is correct**: each ankle carries its trail through the step, so a landing is not visible in a
still. The measurement separates them cleanly: true grid 48 of 114 footfalls in the on-beat eighth, decoy 47
of 118 in the half-beat eighth. **Result: the lock is real in data and not legible in stills.** Whether it is
legible live with the audio is what Matt's look decides.

**R2 two-song sheet** (`final/r2_two_song_sheet.png`, Olive Drab top, Wild Rose bottom, 8 frames each). The
rows are **interchangeable** apart from longer horizontal streaks in the fast song. Same clips, same dancer:
**R2 fails** at this spike.

**Foot-slide vs warp ratio** (`kagura.py slide`: constant-rate resample, measured at 30 fps, cm/s):

| Clip | ×0.5 | ×0.67 | ×0.8 | ×1.0 | ×1.25 | ×1.5 | ×2.0 |
|---|---|---|---|---|---|---|---|
| 60_03 salsa | 6.5 | 7.9 | 9.0 | 10.1 | 11.8 | 12.4 | 16.7 |
| 60_08 salsa | 7.0 | 8.4 | 9.3 | 11.0 | 12.0 | 13.2 | 15.2 |
| 61_02 salsa | 9.9 | 12.7 | 14.3 | 16.8 | 19.3 | 23.5 | 28.9 |
| 93_04 Lindy | 6.3 | 7.2 | 8.8 | 9.2 | 11.1 | 12.0 | 13.5 |
| 93_05 Lindy | 4.4 | 5.6 | 5.7 | 6.9 | 8.2 | 9.4 | 9.6 |
| 93_08 Lindy | 14.7 | 17.2 | 20.6 | 21.6 | 31.7 | 26.3 | 63.6 |
| 05_02 modern | 2.0 | 2.3 | 2.6 | 3.1 | 3.3 | 4.1 | 4.5 |
| 05_11 modern | 2.8 | 3.5 | 3.9 | 4.8 | 5.1 | 5.1 | 5.8 |
| 15_05 twist | 1.1 | 1.2 | 1.4 | 1.6 | 1.8 | 2.0 | 2.4 |
| 143_35 macarena | 0.8 | 0.9 | 1.0 | 1.2 | 1.3 | 1.6 | 1.7 |

**Visibility criterion used:** a planted ankle moving more than 1 px per frame at the film's render scale
(255 px/m at 30 fps = 11.8 cm/s). This is a render-space criterion, not a perceptual study.

**The ratio beyond which sliding is visible:**
- **In-place material** (Lindy 93_04/05, modern, twist, macarena): the warp itself stays under the line up to
  ×1.25. 93_04 crosses at about **×1.3**. 93_05, modern, twist and macarena never cross by ×2.
- **Salsa** is at or over the line at ×1.0, because of the pivots.

Warping cannot create slide by itself: a planted foot has zero speed at any playback rate. What grows is the
capture's own residual, replayed faster, roughly in proportion to the rate. **The slide the pipeline adds is
the crossfade:** 36–80 cm/s inside the one-beat crossfades against 18–21 outside. This is the fix target for
a build, whatever the warp ratio.

## Files

- `kagura.py`: ASF/AMC loader and FK, point-light sets, clip tempo and footfalls, session grid reader, PCHIP
  warp, renderer (ffmpeg pipe), and the subcommands `native`, `tempo`, `slide`, `film`, `sheet`.
- Outside git, under `~/Documents/uzume_spikes/kagura/`: `mocap/` (CMU), `sessions*/` (production-chain
  captures), `native/`, `films/` (pass 1), `final/` (pass 2 films, GIFs, R1 and R2 artifacts, `gate_*/`
  samples).

Regenerate one film:

    ~/Documents/uzume_spikes/kagura/.venv/bin/python kagura.py film \
        ~/Documents/uzume_spikes/kagura/sessions/fixturegen-billie_jean \
        ~/uzume_beatbench_fixtures/billie_jean.mp3 out.mp4 --family salsa
