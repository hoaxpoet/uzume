# Energetic Flyby — look-spike record (EFB.0, design seat, 2026-10-19)

Throwaway evidence for the design doc (`docs/presets/ENERGETIC_FLYBY_DESIGN.md`). No engine code. Renders were
made in a cloud container with Mesa llvmpipe (OpenGL 4.5, CPU) at 640×360, 30 fps, so absolute look is softer
than the GPU; motion, timing and luminance numbers are what this record carries.

## Files

| File | What |
|---|---|
| `energetic_flyby_kali.glsl` | Kali's shader, transcribed verbatim from Shadertoy `csjGDD` (2026-10-19). CC BY-NC-SA 3.0 |
| `energetic_flyby_music_v3.glsl` | The round-3 music build: Kali's code plus the drivers (`uBeat`, `uTravel`, `uSpin`, `uRoll`, `uHue`, `uGlowBase`) and the white-out fix. Every change is marked `// MUSIC:` or `// FIX:` |
| `prep_flyby3.py` | Turns a route-coverage `features.csv` into per-frame driver values (beat grid + full mix only) |
| `st_render.py` | The headless renderer (moderngl + EGL); `python3 st_render.py shader.glsl outdir W H t0 t1 fps [params.json]` |

## 1. The source

Single image pass, ~3.2 KB, no textures, no buffers. `path(t)` is a sine-wobbled line along z; the tunnel is a
6-fold `abs(p)-.4` fold of a rotating, breathing domain (`tub`); three `coso` sphere systems (a spiked shell plus
three axis rods each) ride 0.5 ahead of the camera; the march accumulates glow from the rods (`g`) and the tunnel
(`li`); hits get Kali's `fractal()` texture; one reflection bounce on `hit` cells. Kali's `so` is a pseudo-random
per-frame value that scales the glow, i.e. a per-frame flicker. The camera parks every 5 s.

## 2. The look in motion

The verbatim transcription renders the same image as Shadertoy (checked against the live page in Matt's Chrome).
Reference frames 01–04 in `docs/VISUAL_REFERENCES/energetic_flyby/` are from this transcription.

## 3. Three music rounds, shown to Matt

Each round: 20 s, 640×360, rendered twice with sound, once in sync and once with the audio shifted half a beat
(visuals lead). Labels shuffled; Matt picks the in-sync one blind.

| Round | Song | Drivers | Matt | Result |
|---|---|---|---|---|
| 1 | Love Rehab (118 BPM) | glow pulse every beat, forward surge every beat, bass → spin, Kali's camera park on the bar | *"I don't like the hard cuts … the camera / fly-through resets a few times over 20 seconds."* | Cuts removed |
| 2 | Love Rehab | same, no parks; quarter-turn bank on every second downbeat; white-out fix | *"Both appear to be in sync, but it looks like A is a better match?"* | **Failed**: A was the shifted clip |
| 3 | There There (126 BPM) | **downbeat** burst + colour turn, 0.35× echo on beat 3, nothing on 2/4; energy (spectral flux) → speed + glow floor; bass → spin; bank on every second downbeat | *"I think B is a little slower than the beat and A is better synced."* | **Passed**: A was in sync |

Why round 2 failed: everything was per-beat. On four-on-the-floor music, half a beat lands on the off-beat
hi-hats, which still looks rhythmic. Round 3 made the bar line the event. Matt's "a little" means the connection
reads but is not yet strong; the live app on the beta playlist is the next test, not more clips.

Grid alignment was checked against the audio both times: the grid's beat times vs full-band onsets of the clip
peak at lag 0.000 s (There There) and −0.012 s against kick onsets (Love Rehab).

## 4. Measured, round 3 (There There, 600 frames)

- Continuity: frame-to-frame structural difference (160×90 grey) median 0.077, max 0.197, **0 frames above 3×
  median** (no cuts, no resets).
- Luminance: mean 0.209; max Δ frame-mean luma per frame **0.168**; 7 frames above 0.1. The downbeat burst moves
  the whole frame: **fails D-157 as built**, which is why the design bounds the burst to the sphere light (§5).
- Round 2 found the white-out (one frame at 0.706 frame-mean vs neighbours ≈ 0.31–0.39). The `camGlow` fix took
  it to ≈ 0.40 vs 0.27–0.34.
