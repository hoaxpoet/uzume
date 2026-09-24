# Kagura — Design

**Status:** design written 2026-09-24 from the KAG.0 spike and Matt's calls on it. Implementation not
started.
**Family:** `dancer` (first member) · **Rubric:** `lightweight` · **Paradigm:** particles (a
`ParticleGeometry` conformer)
**Name:** from the mythic origin of *kagura*, Ame-no-Uzume's drummed dance
(`docs/planning/MYTH_RESEARCH.md`; slate entry A3).

Companion: `docs/presets/kagura_spike/README.md`. It holds the spike, every measurement quoted here (§ numbers
in brackets below refer to it), and the regenerable `kagura.py`. Films are in
`~/Documents/uzume_spikes/kagura/final*/` (outside git, D-211).

---

## 1. What it is

About fifteen points of light on near-black. The eye reads them at once as a person dancing (Johansson
biological motion). The dance is real motion capture, retimed so that its moves land on the song's beats,
and each joint leaves a short ribbon of light as it moves, so the dance draws itself into the air.

**Story (See / Move / Music):**
- **See:** fifteen points of light on near-black, at the head, neck, shoulders, elbows, wrists, pelvis, hips,
  knees and ankles of one human body. Each point drags a trail that fades out over 0.4 s.
- **Move:** the figure dances in place: twist, cabbage patch, chicken dance, macarena or Egyptian walk. It
  changes dance on a bar line with a one-beat crossfade. The camera never moves.
- **Music:** the dance's own pulse (a hip turn, the bottom of an arm circle, a move landing) falls on the
  cached grid's beats. The song's tempo and energy choose which three dances it gets, and the energy of the
  moment chooses between them.

## 2. Musical role (Part 2 gate — one sentence)

> **Each dance's own pulse (twist hip-turn, cabbage-patch arm circle, a move landing) is time-warped onto
> the cached beat grid, so the dancer's moves land on the song's beats; the song's arousal and tempo pick a
> three-dance repertoire, and the bar-level bass envelope picks, bar by bar, the calm, middle or vigorous one
> of those three.**

Measured in the spike [§5–§10]:
- Twist and cabbage patch pulse events land within ±⅛ beat of a grid beat **100 %** of the time.
- Five-dance films land **59–73 %** on the beat (chance 25 %), and energetic playlist songs **77–82 %**.
- The half-beat decoy moves the same events wholesale onto the "and".

## 3. Temporal contract

| Horizon | What happens |
|---|---|
| 0.4 s | Each joint's trail fades out (to 5 %) |
| per beat | A pulse event (twist hip-turn / arm-circle bottom / gesture landing) coincides with the grid beat |
| ~1.5 s | Arm reach swells and settles by at most ±25 % with the smoothed bass envelope |
| **1–4 bars (the cycle)** | **The dancer changes dance on a bar line: the moment's energy picks calm, middle or vigorous from the song's repertoire** |
| song | The repertoire of three is fixed at track start from the song's tempo and arousal |
| unsteady stretches | The dancer drops to an unwarped sway until the beat is steady again (§7) |

## 3a. Silence and cold start

- **Silence** (D-037, and the per-scene silence rule in `PRESET_SESSION_CHECKLIST.md`). When the bass
  envelope stays under its floor for a full bar, the dancer crossfades at the next bar line to the sway. The
  sway is slow and calm, and it never freezes: a frozen human reads as a dropped frame. The dancer returns to
  dancing at the first bar line after energy comes back. **This is a design assertion (grounding level 3,
  §12). The spike never exercised silence; it is an M7 item.**
- **Cold start** (Cold-Start Phase Contract, `BEAT_SYNC.md`). Scenes implement their own suppression.
  - *Local-file path:* the whole-track grid is known at t = 0, so the dancer dances from the first bar line.
  - *Streaming path:* the dancer sways until the live drift tracker reports lock (`currentLockState ≥ 1`),
    then joins at the next bar line.
  - Wrong-phase steps at track start are the failure this suppression prevents.

## 4. Motion data — what ships

**Source.** The CMU Graphics Lab Motion Capture Database. Its FAQ says: *"The motion capture data may be
copied, modified, or redistributed without permission."* It asks for this acknowledgement: "The data used in
this project was obtained from mocap.cs.cmu.edu. The database was created with funding from NSF
EIA-0196217." **KAG.1 adds that entry to `docs/CREDITS.md`.**

**The library** (Matt, 2026-09-24): five dances and a fallback. All clips are windows of 120 fps trials,
located by motion signature and confirmed in trail renders [§5, §7, §8].

| Dance | Clips (trial@seconds) | Pulse kind | Rate /min | Vigor m/s |
|---|---|---|---|---|
| Twist | `15_04@109.5-114`, `15_05@110-116` | hip-yaw extrema | 158–164 | 0.71 |
| Cabbage patch | `15_04@117-122.5`, `15_05@117-123` | arm-circle bottoms | 50–53 | 0.60 |
| Chicken dance | `18_15@1-12.8`, `20_01@0-10.7` | gesture landings | 93–94 | 0.45 |
| Macarena | `143_35@0.3-10.6` | gesture landings | 87 | 0.38 |
| Egyptian walk | `15_04@98-104.5`, `15_05@98-104.5` | gesture landings | 96–100 | 0.38 |
| Sway (fallback) | `05_12` | — (played unwarped, forward then backward) | — | — |

**What ships is the derived point-light tracks, not the capture files.** For each clip:
- 15 joints × xyz, resampled to 60 fps and stored as float16. Float16 is about 1 mm resolution at 1 m, which
  is well under a pixel.
- The pulse events (seconds), the pulse period, the allowed metrical levels and the vigor.

The clips are already turned to a common three-quarter facing (`face_camera`) and re-centred. That is about
**0.3 MB for all eleven clips**: one `kagura_clips.bin` plus a `kagura_clips.json` manifest.

**Where it lives.** Kagura would be the first preset that ships a non-shader data file [engine survey]. It
goes in a new `.copy` resource directory on the Presets target (`Presets/Data/Kagura/`) and loads through
`Bundle.module`. It is **tracked in git**: at 0.3 MB it is far from the ML-weights case (167 MB, delivered as
a Release asset), and the repo bans LFS for `*.bin` (CLEAN.5.8).

**Reproducibility.** The raw ASF/AMC files never enter git. `tools/kagura/bake_clips.py` (promoted from the
spike's loader) downloads the listed trials from CMU, verifies their checksums, cuts and turns the windows,
detects pulse events, and writes the `.bin` and `.json`. A checked-in `SHA256SUMS` pins the output.

**CMU frame-rate trap** [§6 erratum]. AMC files carry no rate. The salsa subjects 60 and 61 are 60 fps; the
subjects used here are 120. The bake script reads a per-subject rate table and refuses subjects it has no
entry for.

## 5. The warp — steps on the beat without speed jumps

For each clip the bake produces a **pulse-index map**: clip time as a monotone PCHIP through the pulse
events, sampled into a dense table (64 samples per pulse). At runtime:

```
musical position  p(t)  = beat index + fraction, from the cached grid at the render clock
pulse position    u(t)  = u0 + (p(t) - p0) / m        m in {0.5, 1, 2, 4} grid beats per pulse
clip time         c(t)  = table lookup of u(t)        (linear interpolation)
pose              X(t)  = clip sample at c(t)
```

- **`p(t)` must be continuous.** Raw `beatPhase01` updates at about 14.6 Hz in steps of about 0.11 beat
  (`DancePhase.swift:8-12`, the BUG-096 lesson). Compute `p` from the grid's beat times and the render
  clock, not from the stepped feature.
  - *Local-file path:* the playback clock is the only clock (BUG-087).
  - *Streaming path:* the drift tracker's grid-relative beat times.
- **Choosing the level `m`.** Pick the one whose playback rate `period / (m × beat)` is closest to 1,
  within the clip's allowed set. **Twist excludes ×½** (Matt: half-time twist on slow songs; never two turns
  per beat). The ×4 level exists so a cabbage-patch arm circle can span a bar at fast tempi.
- **Phase alignment is built in.** The pins put pulse events on integer beats, so the phase correction is
  spread across each beat and never jumps. At the spike's measured steadiness the local speed stays within
  about 0.7–1.3× of native [§5, §8].
- **Tempo changes need no special case.** The map is in beats, not seconds.

## 6. Choosing the dance

These are Matt's calls [§9–§11]:
- The song's tempo and energy pick three dances.
- The energy of the moment picks among them.
- **Follow the song's energy.** There is no anti-repeat or variety term.

1. **Song energy.** Take the song's arousal rank against the beta test playlist reference
   (`ENERGY_REFERENCE`, the ten playlist songs' median arousal over windows at 20 / 50 / 80 %), interpolated
   to 0–1.
2. **Repertoire, fixed at track start.** For each dance, `score = |log2(rate at its best level)| +
   |normalised vigor − song energy|`, and the three lowest-scoring dances make the repertoire.
3. **At each clip change** (a bar line, at most every 4 bars, sooner if the clip runs out): the song-relative
   percentile of the smoothed bass envelope over the next bar picks by tercile: the calmest, middle or most
   vigorous dance of the three. Each dance alternates between its clips.
4. **The handoff.** Crossfade over one beat. The incoming clip is placed so the midpoint of its ankles
   matches the outgoing clip's at the cut, and the camera stays fixed.

**Three things the build must settle, with measurements, not assumptions:**
- **The arousal source must match the reference.** `ENERGY_REFERENCE` was measured from the per-frame
  `FeatureVector.arousal` median in production-chain captures. The planner's per-track value is
  `TrackProfile.mood.arousal`. KAG.3 must show the two agree on the playlist, or re-derive the reference
  from `TrackProfile`. The CENSUS `arousal` column is on a different scale (library median 0.04) and must
  not be used [§10].
- **The within-song energy percentile needs the song's distribution.**
  - *Local-file path:* whole-track pre-analysis provides it.
  - *Streaming path:* a trailing running rank over the last ~60 s, primed with the preview.
- **The reference is ten songs.** Re-derive it if the playlist changes. It is a constant with provenance,
  not a tuned value.

## 7. Which songs Kagura dances to

This is Matt's call [§11]. Two layers:

1. **The planner excludes it.** The sidecar declares `"requires_regular_beat": true`. This is the existing
   D-154 path (`PresetScorer.swift:246`, `SessionPlanner+Selection.swift:155`,
   `ReactiveOrchestrator.swift:142`); Membrane already uses it. Beat-irregular tracks go to other scenes
   (the multi-preset-per-song paradigm).
2. **The scene has a safety net for what slips through.** While the grid's own recent beat spacing is uneven
   (the coefficient of variation of the last 16 grid inter-beat intervals above **0.08**), the dancer sways.
   - It re-enters dancing at a bar line once the spacing is steady again.
   - Measured on 61 production-chain captures: steady songs 0.010–0.075, Pyramid Song 0.105–0.395,
     Moonlight 0.129–0.533, Warszawa's last third 0.566, Dance Yrself Clean's near-silent intro 0.164.
   - The spike judged one 30 s window at a time. **The build evaluates it per section** (rolling, with
     hysteresis).
   - Known safe failures (the dancer sways when it could dance): Girl from Ipanema 0.122, Money 0.127,
     several lo-fi tracks.

A **declined bar is not a reason to sway** (D-210: "decline the bar, keep the beat"). With no bar
information (`beatsPerBar == 1`, empty `downbeats`), clip changes fall every 4 beats instead of on bar lines.
Take Five is the playlist case.

**Known flag errors, handled outside this scene:**
- The D-154 flag excludes **Superstition** (drums-stem tempo 138 against grid 98.5) even though its grid is
  steady. That is being investigated as its own beat-sync task. Kagura does not work around it.
- It lets through **Pyramid Song** (0.0987 against the 0.10 threshold) and **Warszawa** (no drums tempo, so
  `nil`, which is permissive). Layer 2 catches both.

## 8. The look

Look **B** (Matt, KAG.0): dots with light-painting trails.

- **Points:** a soft core (about 2.6 px at 1080p-equivalent scale) plus a wide dim halo, warm white
  (`255, 236, 214`), drawn as instanced quads (Witchlight's bead pattern, `WitchlightStroke.swift:198-231`).
- **Trails:** a ping-pong `rgba16Float` trail texture owned by the geometry (Ricercar's pattern,
  `RicercarEchoGeometry.swift:125-145`, `:195-232`).
  - Each frame: decay, then deposit **line segments** from each joint's previous to current position, in
    amber (`255, 170, 110`).
  - The decay factor is **per elapsed time, not per frame**: `0.05^(dt / 0.4 s)`. A per-frame constant ties
    the trail length to the frame rate (the render-clock lesson, BUG-097).
  - `render()` composites trail, then halo, then core, through a soft filmic shoulder.
- **Ground:** near-black (`4, 5, 9`). There is no environment and no floor.
- **Camera:** orthographic, three-quarter view (35° yaw), fixed. Every clip is pre-turned to the same
  facing (§4); without that the macarena is edge-on and unreadable [§7].
- **Arm reach:** elbow and wrist offsets about the shoulder scale by `1 + 0.25·tanh(...)` of the
  song-normalised bass envelope. **Legs are never scaled.** Scaling a planted foot's offset drags the foot
  [§3].
- **Joint set: 15** (the BML set). 13 loses the torso anchor; 17 clutters the feet [§1].

Why the particle path and not the mv_warp `point` primitive the slate named: that primitive has zero
consumers, and mv_warp's warp would displace the trails, whereas Kagura's trails must stay where the joint
actually was. The `ParticleGeometry` path (Witchlight plus Ricercar) is proven in this repo.

**Sidecar sketch:**
```json
{
  "name": "Kagura", "family": "dancer", "passes": ["feedback", "particles"],
  "rubric_profile": "lightweight", "requires_regular_beat": true,
  "fatigue_risk": "low", "transition_affordances": ["crossfade"],
  "audio_routes": "grid beat position -> warp; arousal+tempo -> repertoire; bass_att -> dance pick + arm reach"
}
```
The `audio_routes` value above is prose for this doc. The real manifest uses the QG.1 schema and is written
in KAG.3.

## 9. Audio routing (one primitive per layer — FA #67)

| Visual layer | Primitive | Kind | Timescale |
|---|---|---|---|
| **Moves on the beat** | cached `BeatGrid` beat times, giving continuous beat position `p(t)` | `grid` | per beat |
| Clip-change timing | grid downbeats; every 4 beats when the bar is declined | `grid` | 1–4 bars |
| Repertoire | `TrackProfile` arousal + grid BPM | `structural` | per song |
| Dance pick at each change | `bass_att` (smoothed), song-relative percentile over the next bar | `continuous` → sampled per bar | bars |
| Arm reach ±25 % | `bass_att`, 1.5 s EMA, song-normalised, soft-saturated | `continuous` | ~1.5 s |
| Sway fallback | grid inter-beat-interval CV over the last 16 beats; lock state (streaming) | `structural` | sections |

This follows the Audio Data Hierarchy:
- Beat-locked motion runs only on the cached grid, never on raw onsets.
- Beat-irregular tracks are excluded (D-154).
- The per-beat footprint is bounded: a pose, not a flash (D-157).
- Luminance stays steady: nothing brightens on the beat.

## 10. Rewatch bar

| # | Status |
|---|---|
| R1 legible | **Metric yes; eye unproven.** On the decoy, the true grid puts 100 % of twist and cabbage pulse events on the beat, and the half-beat shift puts 100 % on the "and". I could not tell the panels apart in stills. **This is the M7 question.** |
| R2 per-track identity | **Passes on tested pairs.** Calm against energetic songs get different repertoires and a visibly different density of trails (Olive Drab / Billie Jean). The contrast is milder for Teardrop / B.O.B. [§9, §10] |
| R3 arc | Energy-driven dance choice gives a song's quiet and loud stretches different dances. Not tested over whole tracks. |
| R4 novelty | Character (captured human motion). **Ceiling: eleven clips of 4.5–12 s.** Repetition within a long song is likely. |
| R5 restraint | The motion gate shows 0 spikes on the energetic films. Calm films show 30–44, all from the macarena's fast gestures against a near-still median, which is not a pop. There are no flashes. |

## 11. Increment plan

| ID | Type | Scope | Gate |
|---|---|---|---|
| **KAG.1** | infrastructure | `tools/kagura/bake_clips.py` (from the spike), the `Presets/Data/Kagura/` resource, `kagura_clips.bin` / `.json` / `SHA256SUMS`, a Swift loader, and the `docs/CREDITS.md` CMU entry. **No scene.** | A loader test decodes every clip and checks joint count, frame rate, pulse table and facing. The bake round-trips against `SHA256SUMS`. |
| **KAG.2** | preset | `KaguraDancer: ParticleGeometry`: warp (§5), render (§8), trail texture, a **single fixed dance (twist)**, the sway, and cold start. Registry and table entries. **No dance selection.** | Still sheet + motion gate. A replay-driven **pulse-lock test** on the checked-in route-coverage captures (love_rehab, so_what, there_there). Its threshold is set from KAG.2's own first measurement against the spike's ≥ 90 % twist figure, not assumed. |
| **KAG.3** | preset | Dance selection (§6), arm reach, the §7 safety net per section, the silence rest (§3a), the sidecar with `requires_regular_beat`, and the `audio_routes` manifest. The arousal-source check (§6) comes first. | `RouteCoverageTests` green. Pulse lock per dance. The repertoire table reproduced on the beta playlist. **M7 on the beta playlist (local), then the streaming pass.** |
| KAG.4 | certification | Rubric (lightweight), reference set, cert gates. | Cert. |

## 12. Grounding levels

| Mechanism | Level | Note |
|---|---|---|
| Point-light figure reads as a person | **1 — watched source + spike** | CMU clips, BML reference. Confirmed in every gated sample of the in-place dances. |
| Beat-grid time-warp via pulse pins | **1 — working spike** | Pulse lock 100 % twist/cabbage, 59–82 % mixed. |
| Pulse detectors (hip yaw, arm circle, gesture landing) | **1 — spike**, gesture weakest | Gesture landings are lattice-snapped; macarena skews about 0.1–0.2 beat early (undiagnosed). |
| Instanced sprites + a geometry-owned trail texture | **1 — working code in this repo** | Witchlight, Ricercar. |
| Energy-driven dance choice | **1 — spike**, calibrated on 10 songs | Reference constant with provenance. The arousal-source equivalence is not yet shown (§6). |
| Grid-CV safety net | **1 — spike**, 61 captures | Per-window in the spike; per-section is unbuilt. |
| Silence rest | **3 — design assertion** | Not exercised in the spike. M7. |
| Streaming path | **3 — unmeasured** | The spike was local-file-equivalent only. Drift-tracker lock and preview-based arousal are untested for this scene. |
| 60 fps at 1080p | **2 — trivially small, unmeasured** | 15 instances plus one trail texture. Measure in Release per CLAUDE.md. |

## 13. Open items for Matt (none block KAG.1)

- **Macarena's early arms.** Judge live whether they read as anticipation or as early (§12).
- **R1.** Whether the beat lock is visible live with audio. This is the M7 question the whole concept rests
  on.
- **Library size (R4).** Eleven clips will repeat within a long song. Growing the library means more CMU
  windows or a second source, and every one must be watched in motion before it ships.
