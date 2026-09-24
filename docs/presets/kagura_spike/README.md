# Kagura concept look-spike (KAG.0 — scratch, not engine code)

A point-light dancer built from CMU motion capture and time-warped onto real Uzume beat grids, written to
answer three concept questions with frames: does it read as dancing *to* the song, which dance families
survive warping, and how bad is foot-slide. `kagura.py` imports nothing from Uzume; it is not a porting
source for the engine. This is `preset-concept` gate artifacts 1, 2 and 4, plus the story (artifact 3).

> **ERRATUM (KAG.0c).** CMU lists the salsa subjects 60 and 61 at **60 fps**. KAG.0 assumed 120 fps
> everywhere, so **every salsa number and film in §2–§4 is at double speed**: step rates, local rates,
> travel speed and foot-slide are all about 2× too high. The loader now resamples those subjects (§6),
> and one salsa film was re-rendered at the correct speed for comparison. Lindy (93), modern (05) and the
> §5 twist and cabbage-patch clips (15) are 120 fps and unaffected.

**Status (2026-09-24, latest):** five dances (§7, §8). The song's tempo and energy now pick a three-dance
repertoire, and the moment's energy picks the dance at each bar line (§9). R2 passes on the calm-vs-energetic
pairs tested.
Energy bands calibrated on the beta test playlist (§10).

**Earlier status:** Matt chose **look B** (dots with light-painting trails) and asked for the twist and
cabbage-patch clips next. That pass is §5. It fixes the look problem, since the dancer stays in place, and
the beat lock is much tighter. It leaves the library problem (R2 / R4). Pass-1 films are in
`~/Documents/uzume_spikes/kagura/final/`; §5 films are in `.../final_b/` (never in git, D-211).

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

## §5 KAG.0b — twist and cabbage patch (Matt: "B, try the twist and cabbage patch clips next")

**Finding the dances.** CMU 15_04 and 15_05 are mixed trials of about 190 s (wash windows, hand signals,
Egyptian walk, the Dive, the Twist, the Cabbage Patch, boxing), and nothing records where each action sits in
time. I located the windows by motion signature in 2 s and then 1 s windows:
- the twist as hips turning against the shoulders by 20–33°;
- the cabbage patch as both wrists circling at about 1.1 m/s in front of the chest with the feet planted.

I confirmed each window in trail renders (`survey/clips/*.tile.png`); the sequence matches the order CMU
lists for the trial. **15_12 has no usable dance.** Its 26–34 s shows overhead wind-ups, and in 44–72 s only
the arms move. The windows used:

| Clip | Dance | Length | Pulse the warp pins | Rate /min | Interval CV |
|---|---|---|---|---|---|
| `15_04@109.5-114` | twist | 4.5 s | each hip-turn extreme (left, right) | 158 | 0.08 |
| `15_05@110-116` | twist | 6.0 s | each hip-turn extreme | 164 | 0.05 |
| `15_04@117-122.5` | cabbage patch | 5.5 s | the bottom of each arm circle | 50 | 0.04 |
| `15_05@117-123` | cabbage patch | 6.0 s | the bottom of each arm circle | 53 | 0.04 |

Neither dance's beat is in the feet, because both keep the feet planted. That is why `beat_events` gained a
per-clip pulse (`CLIP_PULSE`). Both pulses are **8–15× steadier** than salsa footfalls (CV 0.6–0.7). The
cabbage-patch arm-circle *tops* were uneven (CV 0.12–0.25), so only the bottoms are pinned. The metrical-level
set gained **×4** so that a circle can span a whole bar at fast tempi.

**Films** (look B unchanged from pass 2; 30 s, 30 fps, audio muxed; `final_b/`). Pulse lock counts the pulse
events detected in the *rendered output* that sit within ±⅛ beat of a grid beat; chance is 25 %. Because the
warp pins those events by construction, this checks the pipeline end to end (crossfades, arm scaling); it is
not evidence of perception.

| Film | Local rate p10–p90 | Pulse lock | Dancer's range | Foot-slide out / in crossfade cm/s | Gate mean / spikes |
|---|---|---|---|---|---|
| slow Olive Drab 86 — twist | 1.02–1.11 | 39 % on the beat + 61 % on the "and" (level ×½: two twists per beat) | ±0.14 m | 28.0 / 42.3 | — |
| slow Olive Drab 86 — cabbage | 0.78–0.92 | 100 % (n = 10) | ±0.14 m | 5.7 / 11.1 | — |
| slow Olive Drab 86 — twist+cabbage | 0.80–1.10 | 50 % beat + 50 % "and" | ±0.16 m | 9.8 / 22.2 | 0.39 / 0 |
| mid Billie Jean 117 — twist | 0.67–0.77 | 100 % (n = 39) | ±0.16 m | 22.9 / 27.5 | 0.39 / 0 |
| mid Billie Jean 117 — cabbage | 1.05–1.17 | 100 % (n = 16) | ±0.14 m | 7.5 / 11.6 | 0.43 / 0 |
| mid Billie Jean 117 — twist+cabbage | 0.67–1.10 | 100 % (n = 34) | ±0.18 m | 12.1 / 22.7 | 0.41 / 0 |
| fast Wild Rose 166 — twist | 0.95–1.11 | 100 % (n = 57) | ±0.20 m | 33.8 / 42.8 | — |
| fast Wild Rose 166 — cabbage | 0.75–0.90 | 100 % (n = 19) | ±0.12 m | 6.8 / 14.2 | — |
| fast Wild Rose 166 — twist+cabbage | 0.77–1.06 | 100 % (n = 41) | ±0.18 m | 12.4 / 30.8 | 0.45 / 0 |

Compare salsa: local rate 0.6–1.8, dancer range ±1.7 m, crossfade slide 36–80 cm/s.

The twist's 23–34 cm/s is **the dance itself**: the heels grind, so the ankles swivel on the floor. The
native clips already measure 24–37 cm/s.

**Motion verdict** (gate samples of five films plus 6 fps sheets; `final_b/gates_all.png`):
- **Smooth.** 0 spikes on every film gated.
- **Reads as a person in every sample.** None of the salsa streak-smear.
- **The trails do what look B promised.** The cabbage patch draws sweeping arcs in front of the chest. The
  twist draws small arcs at the knees and ankles and swings the arms.
- **One flaw.** In two samples an ankle lifts to knee height. The 15_04 twist window starts at 109.5 s, where
  the dancer is probably still getting up from the Dive; starting it at 110 s would likely remove this.

**Rewatch:**
- **R1 decoy** (`final_b/r1_decoy_side_by_side.mp4`; the key is in `r1_KEY.txt`: left = grid shifted +½
  beat, right = true grid). The data is fully separated: 100 % of pulse events on the beat against 100 % on
  the half-beat. From stills 125 ms around five ticks (`r1_frames_at_beats.png`) **I still could not honestly
  call it**, and I also knew the key. Legibility with audio remains the open question for Matt's look.
- **R2** (`final_b/r2_two_song_sheet.png`): **still fails.** The same four captures play under both songs,
  so the sheets are interchangeable.
- **R4:** the library is now four captures of 4.5–6 s, and each one repeats 2–3 times per 30 s.

**Product-level observation (not decided).** The "rate closest to native" rule sends a **slow song to
double-time twisting**: on Olive Drab at 86 BPM the twist runs at 171 per minute, faster than on Billie Jean
at 117 BPM (117 per minute). A half-time twist on slow songs (one twist per beat, played at 0.54×) may read
more musically. That is a look-and-feel question for Matt, not something the spike can settle.

## §6 KAG.0c: half-time twist on slow songs, the salsa frame-rate fix, and more dances

**Half-time twist** (Matt: *"yes, try half-time twist on slow songs"*). Twist clips may no longer use the
×½ level (two turns per beat); see `PULSE_LEVELS`. On a slow song the dancer makes one turn per beat below
native speed. Films are in `final_c/`.

| Film | Twist rate | Local rate p10–p90 | Pulse lock | Gate mean / spikes / near-frozen |
|---|---|---|---|---|
| Olive Drab 86 — twist (before: double time, `final_b/`) | 171/min | 1.02–1.11 | 39 % beat + 61 % "and" | — |
| Olive Drab 86 — twist (half time) | 86/min | 0.49–0.56 | 100 % (n = 29) | 0.28 / 0 / 886 of 899 |
| Olive Drab 86 — twist+cabbage | — | 0.49–0.83 | 100 % (n = 24) | 0.30 / 0 / 885 of 899 |
| Dracula 97 — twist | 97/min | 0.56–0.65 | 100 % (n = 34) | — |
| Dracula 97 — twist+cabbage | — | 0.56–0.92 | 100 % (n = 26) | 0.35 / 0 / 826 of 899 |
| Billie Jean 117 — twist and twist+cabbage | unchanged | unchanged | unchanged | regression check: identical to §5 |

The twist rate now follows the song (86, 97, 117 and 166 turns per minute) instead of doubling on slow songs.
In stills (`final_c/before_after.png`) the arm trails are shorter and the figure reads more clearly.
**Risk:** at about 0.5× the capture may read as slow motion rather than as a slower dance. The gate flags
nearly every frame as near-still (886 of 899, against 697 at double time). Only a live look can settle
that.

**Salsa at the correct speed** (`final_c/mid_billie_jean_117bpm_salsa_fpsfixed.*`):
- The clips are **30–57 s** (not 15–28), step at **100–111 per minute**, and travel at 1.0–1.4 m/s.
  Native foot-slide is 7–10 cm/s.
- On Billie Jean the warp now picks ×1, and **86 % of footfalls land within ±⅛ beat** (49 of 57). The
  double-speed pass managed about 46 %.
- Foot-slide is 15.8 cm/s outside crossfades (was 20.6). Local rate p90 is 2.3, because the steps are still
  uneven.
- **It still travels (±1.3 m) and still streaks while travelling.** The look verdict stands, but it was
  overstated by the double speed. The long clips are an advantage the double speed hid.

**Candidates for a five-dance library** (Matt asked for up to 5). Surveyed from CMU's own index (search
"dance"), downloaded, and measured for length, travel and pulse steadiness. None has been rendered yet.

| Dance | CMU clips | Length | Stays in place? | Best pulse candidate (rate, CV) | What it needs |
|---|---|---|---|---|---|
| Twist | 15_04, 15_05 windows; **141_12** "Dance, Twist" | 4.5–6 s each | yes (0.6 m for 141_12) | hip turns (158–164/min, 0.05–0.08; 141_12 reads 360/min, which is probably a hip wiggle and needs a look) | nothing, working |
| Cabbage patch | 15_04, 15_05 windows | 5.5–6 s | yes | arm-circle bottoms (50–53/min, 0.04) | nothing, working |
| Chicken dance | **143_34**, **18_15**, **20_01** (18–21 are partner captures) | 6.5–12.8 s | yes (≤ 0.23 m) | pelvis-downs 41–61/min, CV 0.19–0.23 | a section-aware pulse: the dance cycles beak, wings, wiggle and clap, so no single joint carries the beat throughout |
| Macarena | **143_35** | 10.7 s | yes (0.22 m) | none found yet (feet barely move) | a "gesture landing" pulse (a wrist arriving at the arm, head or hip) |
| Russian squat-kick | **90_30**, **90_31** | 8–12 s | travels 1.2–1.4 m; head drops 0.75 m | arm-circle bottoms 103–104/min, CV 0.06–0.13 | the leash for its travel, and a check that the deep squats read |
| (rejected) Mickey Dance | 120_05–07 | 9–12 s | travels 1–2.7 m | — | too much travel |

## §7 KAG.0d — five dances (Matt: "yes, go ahead with all 5 dances")

**The library.** Nine clips, cut from CMU and all 120 fps. Films are in `final_e/` (the first attempt,
without the facing fix, is in `final_d/`).

| Dance | Clips (window, s) | Pulse the warp pins | Rate /min, CV | Reads as a person? |
|---|---|---|---|---|
| Twist | `15_04@109.5-114`, `15_05@110-116` | each hip-turn extreme | 158–164, 0.05–0.08 | **Yes.** |
| Cabbage patch | `15_04@117-122.5`, `15_05@117-123` | the bottom of each arm circle | 50–53, 0.04 | **Yes.** |
| Chicken dance | `18_15@1-12.8`, `20_01@0-10.7` | gesture landings (new) | 93–94, 0.14–0.15 | **Yes, and the best trail look.** The beak, then the wing flaps (elbow arcs), then the tail-wiggle down (vertical "flame" trails), then the clap. |
| Macarena | `143_35@0.3-10.6` | gesture landings | 87, 0.07 | **Yes, after the facing fix.** The capture faces side-on, so every gesture was edge-on until each clip was turned to a common three-quarter facing (below). |
| Russian squat-kick | `90_30@3.2-9` | the bottom of each arm circle | 103, 0.06 | **No, in stills.** The whole body hops, so every joint draws the same parallel arch, and the deep squat packs the figure into two clusters. It is the weakest of the five. |

Dropped: `90_31` (travels 1.44 m and kick-slides its feet inside the window); `141_12` "Dance, Twist" (a
small sideways hip wiggle); `143_34` chicken dance (pulse CV 0.21 at best).

**What was added to `kagura.py`:**
- **Gesture-landing pulse** (`pulse="gesture"`). The chicken dance and macarena have no single repeating
  joint motion; each move ends in a held pose. A landing is a minimum of arm speed relative to the pelvis.
  The raw landings are noisy (CV 0.4–0.6), because the beak snaps subdivide the beat, so the warp pins a
  regular lattice at the median move period and snaps each lattice point to a landing within ±20 %.
- **Facing normalisation** (`face_camera`, on by default; `--raw-facing` reproduces every earlier film).
  Each clip is turned about its mean pelvis so its hip line sits at the same three-quarter angle to the
  fixed camera. The camera still never moves.
- **Output check for gesture dances.** It uses the raw landings detected in the rendered motion, not a
  re-fitted lattice, because a re-fit can pick a different phase and under-report the lock.
- `five` family: twist → cabbage → chicken → macarena → Russian → twist → cabbage → chicken, changing
  on bar lines.

**Films** (look B, 30 s, audio muxed). Pulse lock counts pulse events in the rendered output within ±⅛
beat of a grid beat; chance is 25 %.

| Film | Local rate p10–p90 | Pulse lock | Dancer's range (x) | Foot-slide out / in crossfade | Gate mean / spikes |
|---|---|---|---|---|---|
| Olive Drab 86 — five | 0.50–1.03 | 73 % (n = 30) | −0.35 to 0.58 m | 5.7 / 10.7 | 0.35 / 56 |
| Dracula 97 — five | 0.58–1.16 | 71 % (n = 31) | −0.43 to 0.72 m | 7.5 / 12.3 | 0.39 / 47 |
| Billie Jean 117 — five | 0.69–1.39 | 62 % (n = 39) | −0.42 to 0.78 m | 9.0 / 15.0 | 0.46 / 26 |
| Wild Rose 166 — five | 0.75–1.06 | 67 % + 22 % on the "and" (n = 46) | −0.28 to 0.58 m | 5.4 / 17.7 | 0.40 / 21 |
| Billie Jean — chicken | 1.06–1.47 | 42 % on the beat + 38 % on the "and" (n = 40) | ±0.1 m | 2.3 / 8.2 | 0.38 / 9 |
| Billie Jean — macarena | 1.16–1.46 | 55 %, **skewed early** (28 of 42 in the quarter-beat before the beat) | ±0.07 m | 2.4 / 38.2 | 0.30 / 59 |
| Billie Jean — Russian | 1.04–1.18 | n/a | ±0.3 m | n/a (no floor contacts detected) | 1.07 / 0 |

**Reading the gate spikes** (twist and cabbage patch had none):
- **Macarena.** It holds near-still poses between fast gestures (764 of 899 frames near-frozen), so its real
  gestures exceed 3× the median. That is the dance, not a defect.
- **Five-dance films.** The spikes cluster at the one-beat crossfade **into and out of the Russian squat**:
  the standing figure visibly "melts" down into a squat over half a second (`final_e/spikes.png`, bottom
  row). It is continuous, but it is an unnatural morph and the Russian clip's second weakness.

**Motion verdict** (gate samples and 1–4 fps sheets):
- Twist, cabbage patch and chicken dance read at once and stay in place.
- Macarena reads once it faces the camera.
- The Russian squat-kick does not read in stills, and its crossfades morph visibly. Replacing it is the
  obvious fix. Candidates: the Egyptian walk (15_04/15_05 at about 98–104 s; it turns and travels), or
  lambada (55_02; travels).

**R2 (per-song identity).** The two-song sheet (`final_e/r2_two_song_sheet.png`) now differs frame by frame,
but only because dance changes fall at different moments at different tempi. Both songs get the same five
dances in the same order. **R2 is still structurally unsolved.** It needs the song to choose the dances
(for example by tempo, energy or mood), and nothing does that yet.

**Macarena's early skew** (the arm stops about 0.1–0.2 beat before the beat) comes either from the snapped
lattice or from the check's detector; not diagnosed. It may read as anticipation or as early. It is part of
the live look.

## §8 KAG.0e — Egyptian walk replaces the Russian squat-kick (Matt: "go with Egyptian walk")

Options surveyed first (CMU, measured and seen in trail sheets): the Egyptian walk; Charleston kicks (93_04
and 93_05, in place but only 4 s); freestyle dancing (111_05 and 113_04, not a named dance); salsa and
lambada (they travel); breakdance (90_28 and 85_10, where a point-light figure on the floor stops reading).

- **Correction to §7:** the Egyptian walk barely travels (0.14 m in its window). It turns on the spot.
- **Clips:** `15_04@98-104.5` and `15_05@98-104.5`, 6.5 s each, gesture-landing pulse at 96–100 per minute.
- **The `five` family** is now twist → cabbage → chicken → macarena → Egyptian walk → twist → cabbage →
  chicken → Egyptian walk. `russian` stays defined but is out of the mix. Films are in `final_f/`.

| Film | Local rate p10–p90 | Pulse lock (±⅛ beat, chance 25 %) | Dancer's range (x) | Foot-slide out / in crossfade | Gate mean / spikes (§7 with the Russian clip) |
|---|---|---|---|---|---|
| Olive Drab 86 — five | 0.50–1.03 | 68 % (n = 31) | −0.06 to 0.11 m | 4.1 / 11.0 | 0.28 / **11** (56) |
| Dracula 97 — five | 0.58–1.16 | 66 % (n = 32) | −0.07 to 0.12 m | 5.3 / 13.2 | 0.33 / **8** (47) |
| Billie Jean 117 — five | 0.69–1.39 | 59 % (n = 39) | −0.07 to 0.12 m | 6.0 / 15.7 | 0.39 / **5** (26) |
| Wild Rose 166 — five | 0.74–1.06 | 72 % + 16 % on the "and" (n = 50) | −0.08 to 0.09 m | 4.2 / 17.0 | 0.33 / **7** (21) |
| Billie Jean — Egyptian walk | 1.02–1.28 | 47 % on the beat + 53 % on the "and" (n = 36) | ±0.05 m | 10.6 / 20.2 | 0.39 / 0 |

**Motion verdict:**
- The figure reads as a person in all 40 frames of the Billie Jean overview (`final_f/mid_five_overview.png`).
- The squat "melt" is gone. The remaining 5–11 gate spikes fall in the macarena's fast gestures.
- The Egyptian walk shows its signature pose (one arm raised and bent, the other pointing down) and every
  move lands on a beat or a half-beat.
- The dancer now stays within about ±0.12 m for all 30 s.

**Still open:** R2 per-song identity (§7), macarena's early skew (§7), and a live look with audio for R1.

## §9 KAG.0f — the song's tempo and energy pick the dances (Matt: "have the song's tempo and energy pick the dances")

**The rule** (`--family auto`; `pick_repertoire`, `dance_profile`). It is deterministic, and every input is
measured.

1. **Dance profile**, from each dance's own clips at native speed:
   - *vigor* is the mean speed of the wrists, ankles and head relative to the pelvis;
   - *pulse period* comes from the warp's own pulse.

   | Dance | Vigor (m/s) |
   |---|---|
   | twist | 0.71 |
   | cabbage patch | 0.60 |
   | chicken dance | 0.45 |
   | macarena | 0.38 |
   | Egyptian walk | 0.38 |

2. **Song energy** is MoodClassifier `arousal` (the median after the first sixth), mapped from [0.1, 0.6]
   to [0, 1]. The range is the span of the nine spike songs, not a corpus fit. `bass_att` is not used here
   because it is AGC-normalised and reads about 0.2 on every song (FA #31).

3. **Repertoire:** each dance is scored on tempo cost plus energy cost, and the best three are kept.
   - *Tempo cost* is |log₂ playback rate| at the dance's best metrical level, so a twist that must run at
     0.5× on a slow song costs 1.
   - *Energy cost* is |dance vigor, normalised 0–1 across the library − song energy|.

4. **Within the song**, at each bar-line clip change, the song-relative percentile of the smoothed bass
   envelope over the next bar picks by tercile: the calmest, middle or most vigorous dance in the repertoire.
   Each dance alternates between its clips.

**What it picks** (nine songs; `--metrics-only`). Films for six of them are in `final_g/`.

| Song | BPM | Arousal → energy | Repertoire | Dance sequence (one per clip change) | Pulse lock (±⅛, chance 25 %) |
|---|---|---|---|---|---|
| Dreams of You | 123 | 0.10 → 0.00 | Egyptian, macarena, chicken | eg ma ma ch ma ma eg eg eg | 48 % |
| Olive Drab | 86 | 0.16 → 0.13 | Egyptian, macarena, chicken | eg ch eg eg ma ma eg | 44 % + 37 % on the "and" |
| Dracula | 97 | 0.31 → 0.43 | Egyptian, chicken, cabbage | eg cb eg ch cb cb ch ch eg | 39 % + 39 % on the "and" |
| Superstition | 99 | 0.42 → 0.63 | Egyptian, chicken, cabbage | eg eg eg ch cb ch cb ch | 52 % |
| Around the World | 126 | 0.43 → 0.67 | chicken, cabbage, twist | ch ch cb tw tw tw tw cb | 78 % |
| GAYBLEVISION | 143 | 0.43 → 0.66 | chicken, cabbage, twist | ch cb cb cb ch cb cb cb tw cb tw tw | 70 % |
| Wild Rose | 166 | 0.49 → 0.78 | chicken, cabbage, twist | ch ch cb tw tw cb cb cb tw tw tw | 72 % |
| Stayin' Alive | 104 | 0.54 → 0.88 | chicken, cabbage, twist | ch cb cb tw cb cb ch cb | 57 % |
| Billie Jean | 117 | 0.59 → 0.98 | chicken, cabbage, twist | ch ch tw tw cb tw tw tw | 75 % |

**Reading it:**
- **Three distinct repertoires across nine songs:** calm songs get the gesture dances, energetic songs get
  twist and cabbage patch, and the middle songs mix them.
- **Energy does most of the choosing.** Tempo mainly keeps the twist off slow songs. Dreams of You is 123 BPM
  but calm, and it gets the calm set, which shows tempo alone does not decide.
- **The within-song energy envelope** orders the dances. Billie Jean's loud bars go to the twist.
- **Pulse lock is lower on calm songs** (39–52 % on the beat, plus the "and"), because the gesture dances'
  pulse is noisier than the twist's and cabbage patch's.

**R2 two-song sheet** (`final_g/r2_calm_vs_energetic.png`, Olive Drab over Billie Jean): the rows now differ
**in character**, not just in timing. The calm row is sparse poses with few trails. The energetic row is
dense trails: wing flaps, twisting knees, arm circles. `final_g/r2_same_tempo_band.png` compares Dreams of
You (123 BPM, calm) with Billie Jean (117 BPM, energetic): similar tempo, different dances. **R2 moves from
fail to pass on these pairs.** A decoy-style check of R2 across a real playlist has not been done.

**Gate:**
- Energetic films: 0 spikes.
- Middle films: 7–9.
- Calm films: 30–44, all from the macarena's fast gestures against a near-still median (§7). This is not a
  pop.

**Open:**
- **The energy mapping is fitted to nine songs.** A real playlist could put most songs in one band. The
  mapping should be calibrated on the beta test playlist before any build.
- **Repetition follows the song, by design.** **Matt, 2026-09-24: "follow the song's energy."** The pick is
  not rotated to avoid repeats. If a song stays loud, the vigorous dance stays (Billie Jean: five of eight
  changes are twist). Do not add a variety or anti-repeat term.
- **Macarena's early skew** (§7) is still undiagnosed.

## §10 KAG.0g — energy bands calibrated on the beta test playlist (Matt: "calibrate the energy bands on the beta test playlist")

**Data.** The ten songs in `tools/data/beta_test_playlist.m3u`, from `/Volumes/Extreme SSD`. For each
track, three 30 s windows centred at 20 %, 50 % and 80 % of its length were cut with ffmpeg
(`~/Documents/uzume_spikes/kagura/beta_windows/`) and run through the production chain
(`FixtureSessionCaptureGenerator`, `sessions_beta/`). One window from the start would mislead: Dance Yrself
Clean's arousal is −0.28 in its hush and 0.69 after the drop.

| # | Track | Arousal 20 / 50 / 80 % | Song (median) | Grid BPM |
|---|---|---|---|---|
| 1 | Dance Yrself Clean | −0.28 / 0.69 / 0.72 | 0.69 | 98 |
| 2 | B.O.B. | 0.67 / 0.63 / 0.68 | 0.67 | 154 |
| 3 | Superstition | 0.47 / 0.53 / 0.51 | 0.51 | 100–103 |
| 4 | Smells Like Teen Spirit | 0.47 / 0.61 / 0.54 | 0.54 | 117–118 |
| 5 | Penny Lane | −0.04 / 0.07 / −0.05 | −0.04 | 113 |
| 6 | Take Five | 0.51 / 0.10 / 0.48 | 0.48 | 167–174 (0 bars: bar declined) |
| 7 | Pyramid Song | −0.13 / 0.45 / 0.46 | 0.45 | 67 / 146 / 156 (the grid jumps levels) |
| 8 | Teardrop | 0.43 / 0.53 / 0.36 | 0.43 | 77 |
| 9 | Moonlight I | −0.28 / −0.17 / −0.42 | −0.28 | 40–58 (0 bars) |
| 10 | Warszawa | 0.13 / 0.19 / 0.39 | 0.19 | 77–83 |

**What calibration changed.** The KAG.0f range [0.1, 0.6] put almost every beat-bearing playlist song at
energy ≥ 0.66, because they cluster at arousal 0.43–0.69. Song energy is now the song's **interpolated rank
among the ten playlist medians** (`ENERGY_REFERENCE`, `song_energy`). "Calm" now means calmer than most of
the beta playlist.

| Song | Energy old → new | Repertoire before | Repertoire after |
|---|---|---|---|
| Moonlight I, Penny Lane, Warszawa | ≤ 0.18 → ≤ 0.22 | Egyptian, macarena, chicken | unchanged |
| **Teardrop** | 0.66 → **0.33** | macarena, chicken, cabbage | **Egyptian, macarena, chicken** |
| Pyramid Song | 0.70 → 0.44 | macarena, chicken, cabbage | unchanged |
| Take Five | 0.76 → 0.56 | chicken, cabbage, twist | unchanged (its 170 BPM suits the twist) |
| **Superstition** | 0.82 → **0.67** | chicken, cabbage, twist | **Egyptian, chicken, cabbage** |
| Smells Like Teen Spirit, B.O.B., Dance Yrself Clean | 0.88–1.0 → 0.78–1.0 | chicken, cabbage, twist | unchanged |
| (spike) **Dracula** | 0.42 → **0.28** | Egyptian, chicken, cabbage | **Egyptian, macarena, chicken** |
| (spike) Olive Drab, Dreams of You, Wild Rose, Stayin' Alive, Billie Jean | — | — | unchanged |

On the playlist, four songs get the calm set, two a middle set and four the energetic set.

**Films** (`final_h/`, the 50 % window of each track, `--arousal` set to the song median):

| Film | Energy | Dances (one per clip change) | Pulse lock (±⅛, chance 25 %) | Gate spikes |
|---|---|---|---|---|
| Dance Yrself Clean (drop) | 1.00 | ch tw tw ch ca ca tw | 61 % + 23 % on the "and" | 0 |
| B.O.B. | 0.89 | ch tw tw ca tw ca tw ca ca ch ch | 82 % | 0 |
| Smells Like Teen Spirit | 0.78 | ch tw tw ca tw ca ca ca ch ca | 77 % | 0 |
| Superstition | 0.67 | eg ca ca ca ch eg eg eg ca ca | 57 % + 39 % | 3 |
| Teardrop | 0.33 | eg eg ma ch ch ch eg | 50 % + 21 % | 40 (macarena gestures) |
| Penny Lane | 0.11 | eg eg eg eg ma ma ch ma ch | 45 % + 25 % | 32 (macarena gestures) |

**R2** (`final_h/r2_teardrop_vs_bob.png`): the dances differ, but the contrast is milder than Olive Drab
against Billie Jean, because Teardrop's chicken-dance stretch also draws dense trails.

**Caveats:**
- The census cannot cross-check this. Its `arousal` column is on a different scale from runtime arousal
  (library median 0.04), its ranks agree only weakly with runtime (Spearman ρ = 0.32, n = 11), and several
  title matches were the wrong recording.
- Ten songs is a small reference. Two of them (Moonlight I, Warszawa) never dance but still anchor the low
  end, which is deliberate: energy is about the music, not the beat.

**Found in passing — not decided (product call for Matt):** the prompt's fallback rule sends beat-irregular
**or** bar-declined songs to the sway. Applied to this playlist, only **3 of 10 would dance** (Dance Yrself
Clean, B.O.B., Smells Like Teen Spirit):
- Take Five is bar-declined in every window. D-210 says "decline the bar, keep the beat", so it could keep
  dancing with clip changes every 4 beats (the spike already does this when bars are declined).
- Superstition, Penny Lane and Teardrop carry the census's D-154 flag, which comes from a 30 s window.
  Superstition's grid is steady at 100–103 BPM in all three windows here, so its flag looks like the known
  drums-stem disagreement false positive (D-154 amendment).
- Pyramid Song, Moonlight I and Warszawa sway by design.

## Files

- `kagura.py`: ASF/AMC loader and FK, point-light sets, clip tempo and footfalls, session grid reader, PCHIP
  warp, renderer (ffmpeg pipe), and the subcommands `native`, `tempo`, `slide`, `film`, `sheet`. Clip
  sub-ranges (`15_04@109.5-114`) and per-clip pulses (`CLIP_PULSE`) were added at §5.
- Outside git, under `~/Documents/uzume_spikes/kagura/`: `mocap/` (CMU), `sessions*/` (production-chain
  captures), `native/`, `films/` (pass 1), `final/` (pass 2 films, GIFs, R1 and R2 artifacts, `gate_*/`
  samples), `survey/` (the twist and cabbage-patch search), `final_b/` (§5).

Regenerate one film:

    ~/Documents/uzume_spikes/kagura/.venv/bin/python kagura.py film \
        ~/Documents/uzume_spikes/kagura/sessions/fixturegen-billie_jean \
        ~/uzume_beatbench_fixtures/billie_jean.mp3 out.mp4 --family salsa
