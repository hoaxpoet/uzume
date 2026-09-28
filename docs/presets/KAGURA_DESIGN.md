# Kagura — Design

**Status:** ✅ **CERTIFIED at KAG.4 (2026-09-28), the 26th.** Design written 2026-09-24 from the KAG.0 spike
and Matt's calls on it. KAG.1 (clip resource) shipped 2026-09-25; KAG.2 (the twist, the sway, cold start, look
B) 2026-09-25; KAG.3 (selection, arm reach, safety nets, then the Charleston and ballet) M7 PASSED 2026-09-28.
What the builds settled is in §14 (KAG.2) and §15 (KAG.3, KAG.4).
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
**0.46 MB for all ten clips** (KAG.1 measured 459 KB; the sway clip is the longest): one `kagura_clips.bin` plus a `kagura_clips.json` manifest.

**Where it lives.** Kagura would be the first scene that ships a non-shader data file [engine survey]. It
goes in the **Renderer** target, as `Sources/Renderer/Resources/Kagura/` with a `.copy("Resources/Kagura")`
entry beside the existing `Resources/Fonts`, and loads through Renderer's `Bundle.module`. It belongs there
because the consumer, `KaguraDancer: ParticleGeometry`, lives in `Renderer/Geometry`, and Renderer and
Presets are sibling targets (both depend only on `Shared`), so Renderer cannot read a Presets resource. The
file is **tracked in git**: at about 0.46 MB it is far from the ML-weights case (167 MB, shipped as a Release
asset), and the repo bans LFS for `*.bin` (CLEAN.5.8).

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

1. **Song energy (KAG.5, D-259).** The measured 1–10 energy level of the stretch of the song playing, on the
   library scale: energy = (level − 1) / 9. A stretch runs between two of the song's energy changes (NRG.4)
   and is judged by its loud end, its 90th-percentile section level (Matt, 2026-09-28). A streaming preview
   is one stretch; with no curve the energy is the middle (0.5). *Before KAG.5: the song's arousal rank
   against the ten beta-playlist songs (`energyReference`), retired with the mood classifier (D-259 §4).*
2. **Repertoire, per stretch (KAG.5; fixed at track start before).** The Charleston by tempo (Matt,
   2026-09-28, B): in its band it always takes one of the three, the vigorous third, whatever the energy.
   Otherwise, for each dance, `score = |log2(rate at its best level)| +
   |normalised vigor − song energy|`, and the three lowest-scoring dances make the repertoire.
3. **At each clip change** (a bar line, at most every 4 bars, sooner if the clip runs out): the song-relative
   percentile of the smoothed bass envelope over the next bar picks by tercile: the calmest, middle or most
   vigorous dance of the three. Each dance alternates between its clips.
4. **The handoff.** Crossfade over one beat. The incoming clip is placed so the midpoint of its ankles
   matches the outgoing clip's at the cut, and the camera stays fixed.

**Three things the build must settle, with measurements, not assumptions** (the first and last are
superseded by KAG.5's measured energy, §16):
- **The arousal source must match the reference.** `ENERGY_REFERENCE` was measured from the per-frame
  `FeatureVector.arousal` median in production-chain captures. The planner's per-track value is
  `TrackProfile.mood.arousal`. KAG.3 must show the two agree on the playlist, or re-derive the reference
  from `TrackProfile`. The CENSUS `arousal` column is on a different scale (library median 0.04) and must
  not be used [§10].
- **The within-song energy percentile needs the song's distribution.**
  - *Local-file path:* whole-track pre-analysis provides it.
  - *Streaming path:* a trailing running rank over the last ~60 s, primed with the preview.
  - **Correction (2026-09-25, KAG.3 pre-read — verified in the tree).** No whole-track distribution of
    `bass_att` exists on either path. What the local-file pre-analysis does carry is `LoudnessProfile` (full-band
    loudness quantiles, `Shared/LoudnessProfile.swift`) and the pre-analysed stem series (the bass STEM, 43 Hz,
    whole track). Neither is the spike's signal, so KAG.3 uses a trailing running rank of the smoothed
    `bass_att` on both paths unless it measures a local-file source that reproduces the spike's picks.
- **The spike's pick looked one bar AHEAD.** `build_dancer` ranks the smoothed bass envelope over the bar
  *after* the change (`t0 … t0 + bar`). The streaming path cannot see the future, and on the local-file path
  no `bass_att` exists ahead of the playhead. **Matt, 2026-09-25 (option A): the pick reads the bar just
  played, identically on both paths.** A louder stretch gets the vigorous dance at most one bar late; local
  files and streaming behave the same, so the local M7 previews streaming. No read-ahead.
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
- ~~The D-154 flag excludes **Superstition**~~ — **resolved by BUG-140 (BUG140.2, 2026-09-25):** the gate now
  compares octave-folded median tempos, and Matt's live check passed (*"Membrane is locked on Superstition"*).
  Superstition now pairs with `requires_regular_beat` scenes, Kagura included.
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
| Repertoire | `TrackProfile.energySections` (each stretch's loud-end 1–10 level) + grid BPM (KAG.5) | `structural` | per energy section |
| Dance pick at each change | `bass_att` (smoothed), song-relative percentile over the next bar | `continuous` → sampled per bar | bars |
| Arm reach ±25 % | `bass_att`, 1.5 s EMA, song-normalised, soft-saturated | `continuous` | ~1.5 s |
| Sway fallback | grid inter-beat-interval CV over the last 16 beats; lock state (streaming) | `structural` | sections |

**Schema note (KAG.2; settled KAG.3).** The QG.1 route schema (`PresetDescriptor` `audio_routes` kinds) has
**no `grid` kind** — only `continuous`, `accent`, `structural` and `gate`. The grid-driven rows are not
declared and are gated by `KaguraPulseLockReplayTests`; the `bassAtt` rows are declared (§15).

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
| R4 novelty | Character (captured human motion). **Ceiling: ten clips of 4.5–12 s.** Repetition within a long song is likely. |
| R5 restraint | The motion gate shows 0 spikes on the energetic films. Calm films show 30–44, all from the macarena's fast gestures against a near-still median, which is not a pop. There are no flashes. |

## 11. Increment plan

| ID | Type | Scope | Gate |
|---|---|---|---|
| **KAG.1** | infrastructure | `tools/kagura/bake_clips.py` (from the spike), the `Renderer/Resources/Kagura/` resource, `kagura_clips.bin` / `.json` / `SHA256SUMS`, a Swift loader, and the `docs/CREDITS.md` CMU entry. **No scene.** | A loader test decodes every clip and checks joint count, frame rate, pulse table and facing. The bake round-trips against `SHA256SUMS`. |
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
| Energy-driven dance choice | **1 — spike**, calibrated on 10 songs | The spike's rule ported and reproduced (README §9, §10); the reference re-derived from `songArousal` (§15). The bar-just-played pick (option A) is **2 — measured offline**: 42 % agreement with the spike's lookahead picks; M7 judges whether it reads as following the music. |
| Grid-CV safety net | **1 — spike + build**, 61 + 31 captures | Per-section with hysteresis (§15): sways on every irregular beta window, dances on every steady one. |
| Silence rest | **3 — design assertion** | Built with a measured floor and a stopped-clock fallback (§15); tested on real rows. Not exercised in the spike. M7. |
| Arm reach rate limit + band floor | **2 — measured bounds** | Outside anything 80 real captures reach (§15); they only act on flat stretches and silence. |
| Streaming path | **3 — unmeasured** | The spike was local-file-equivalent only. Drift-tracker lock and preview-based arousal are untested for this scene. |
| 60 fps at 1080p | **1 — measured (KAG.2)** | Release (`swift build -c release`), 1920×1080, no readback: 0.216 ms GPU median, p95 0.297; 0.018 ms CPU. Debug harness with readback: 2.94 ms, 0.5× the roster median. |

## 13. Open items for Matt (none block KAG.1)

- **Macarena's early arms.** Judge live whether they read as anticipation or as early (§12).
- **R1.** Whether the beat lock is visible live with audio. This is the M7 question the whole concept rests
  on.
- **Library size (R4).** Ten clips will repeat within a long song. Growing the library means more CMU
  windows or a second source, and every one must be watched in motion before it ships.

## 14. What the build settled (KAG.2)

**How `p(t)` is sourced** (`KaguraBeatClock`). The app copies the grid in as plain data (`KaguraGrid`) at
every `setBeatGrid` site on both paths, and a stateful tick pushes the playback clock every frame.
- *Local file:* `MIRPipeline.elapsedSeconds` alone (BUG-087). `PlaybackClockSmoother` was **not** live on this
  path without a stem series (`publishStemSeriesFrame` returns before sampling it), so Kagura runs its own.
- *Streaming:* `elapsedSeconds + drift`, the same sum the drift tracker's relative beat times use; the
  dancer sways until `lockState ≥ 1` (§3a).
- The push goes through the smoother and then a render-rate phase lock (advance 1 s per render second,
  correct 10 % toward the smoothed reading per frame). The smoother alone first sees each coarse tick up
  to a frame late: on the 43 Hz captures its per-frame steps ranged 0.38–1.5× nominal. With the lock:
  0.89–1.10×.
- **The one-frame lag.** The tick runs after `particles.update`, so each push is stamped with the render
  clock and extrapolated in `update`. Measured lag against the true playback position: 6.9 ms mean,
  8.6 ms max (half a frame is the discovery delay of the coarse clock, not the tick order).

**The causal leash.** The spike's leash is a zero-phase Gaussian (σ 2 s) of the pelvis floor path, which
needs the future. The clips are already centred on their mean pelvis (KAG.1), so the only drift is the
handoff offsets accumulating. Each offset decays to zero with τ = 2 s. Foot-slide against the spike on
the same three captures (the spike's own `foot_slide`, 30 fps):

| Capture | Build overall / outside / inside crossfades (cm/s) | Spike overall / outside / inside |
|---|---|---|
| love_rehab | 21.9 / 21.8 / 22.6 | 21.3 / 21.0 / 22.0 |
| so_what | 25.2 / 25.1 / 26.3 | 32.2 / 29.2 / 38.9 |
| there_there | 23.1 / 23.3 / 21.4 | 26.0 / 25.4 / 28.8 |

The pelvis wanders more than under the spike's leash: x reaches 0.17–0.18 m (0.27 m on one decoy run)
against ±0.09 m, because a causal decay recentres after the handoff rather than before it. Over five
minutes at 120 BPM it stays inside ±0.23 m.

**Pulse lock** (`KaguraPulseLockReplayTests`, the spike's detector on the dancer's output): 100 % within
±⅛ beat on love_rehab / so_what / there_there (n 44 / 51 / 48, chance 25 %); the +½-beat decoy 0 % on
the beat, 100 % on the "and". The spike on the same captures: 100 % (n 40 / 43 / 43) and the same decoy
split. The assertion is 95 %.

**Two trail defects the frame-rate test found** (`KaguraTrailDecayTests`), both fixed before the look was
judged:
- A frame's segment lands after that frame's decay, so it is under-decayed by half a frame (+6.6 % trail
  energy at 30 fps against 60, −3.6 % at 120). The deposit is scaled by the frame's own `1 − decay` and
  normalised to the spike's 30 fps frame, which keeps the spike's brightness.
- Joint positions in a shared per-frame buffer handed every in-flight frame the newest segment, so the
  trail was one dash per joint. They go through `setVertexBytes`.

**Frame cost.** Release (`swift build -c release`, a throwaway timing package: `swift test -c release` does not
run in this package — see the KAG.2 closeout), 1920×1080, no readback: 0.216 ms GPU median (p95 0.297),
0.018 ms CPU encode; Ricercar through the same loop 0.480 ms.

**Grid changes mid-dance** (a streaming live analysis replacing the grid, or a track change) fade to the
sway over one nominal beat, and the dancer rejoins at the new grid's next bar line. Clip changes with the
bar declined fall on a 4-beat lattice, at most 4 such "bars" apart (the spike's `beats[::bpb]` rule).


## 15. What the build settled (KAG.3)

**The arousal source (§6).** `TrackProfile.mood.arousal` is the mood classifier's state at the LAST frame of
the analysed audio (0.7 s output window), so it is a song's final second or two. On the beta playlist it
ranks against the spike's `ENERGY_REFERENCE` at Spearman ρ 0.59, and re-deriving would move 5 of 10
repertoires, over the prompt's limit of 3. **Matt, 2026-09-25 (option A):** preparation measures
`TrackProfile.songArousal`, the median per-frame arousal after the first sixth (the spike's own rule), and
the reference is re-derived from it: ρ 0.85, **2 songs move** (Take Five and Teardrop, both to macarena /
chicken / cabbage). `KaguraRepertoire.energyReference` is those ten values (shipping local-file
preparation, Release, `PrepTimingRunner`). Cache schema v16. BUG-143, in another session, makes `mood`
itself this median; once it lands, Kagura reads `mood.arousal` and the field goes.

| Song | README §10 median | `mood.arousal` (final) | `songArousal` | Ranks (§10 / final / song) |
|---|---|---|---|---|
| Dance Yrself Clean | 0.69 | 0.428 | 0.609 | 10 / 8 / 10 |
| B.O.B. | 0.67 | 0.554 | 0.569 | 9 / 9 / 8 |
| Smells Like Teen Spirit | 0.54 | 0.605 | 0.597 | 8 / 10 / 9 |
| Superstition | 0.51 | 0.243 | 0.206 | 7 / 7 / 4 |
| Take Five | 0.48 | −0.376 | 0.327 | 6 / 2 / 5 |
| Pyramid Song | 0.45 | −0.291 | 0.334 | 5 / 4 / 6 |
| Teardrop | 0.43 | −0.424 | 0.479 | 4 / 1 / 7 |
| Warszawa | 0.19 | −0.294 | 0.040 | 3 / 3 / 3 |
| Penny Lane | −0.04 | −0.114 | −0.426 | 2 / 5 / 1 |
| Moonlight I | −0.28 | −0.013 | −0.355 | 1 / 6 / 2 |

The absolute scales differ (offline Superstition 0.21 against the production-chain 0.51), which is why the
reference is re-derived rather than reused.

**The pick (§6 item 3).** The 1.5 s `bass_att` EMA, per elapsed time, sampled at a fixed 20 Hz into a
trailing 60 s window; at each clip change the mean rank of the bar just played picks calm / middle /
vigorous (Matt's option A — no read-ahead, both paths alike). A track opens with nothing to rank against,
so its first pick is the middle dance. A long steady loud stretch becomes the window's norm after about
20 s and its rank drifts toward the middle; the spike's whole-window rank had the same property.
**Agreement with the spike's `--family auto` picks** on the 30 beta captures is 41 % (64 / 155; 35 % before the twist and cabbage patch returned to KAG.2's entry). This is a
report, not a gate, and most of it is option A: the spike's own rule, changed only to read the bar just
played, agrees with its original picks 42 % of the time, because a bar's energy tercile rarely predicts the
next bar's. The trailing window on 30 s captures (always in its first half-minute) accounts for most of the
rest.

**Clip entry and the cut rule.** A gesture dance (chicken, macarena, Egyptian) enters its clip as the spike's
did, 1 + 2/m pulses in, and clip changes follow the spike's rule (the last bar line within 4 bars at least ½
beat before the last pulse, else the next bar line). KAG.2's entry on the first pulse left those dances up to
13 points off the spike's lock. The twist and cabbage patch keep KAG.2's entry (**Matt: split by dance**):
their lock is 100 % either way, and the spike's entry raised the twist's foot-slide to 29.0 / 33.9 / 31.5
cm/s. The spike's own pre-roll was 1 or 2 beats by float rounding of `beats >= t0 − 2·gp` (love_rehab: 1 on
every cut; so_what mostly 2); the build takes the intended 2.

**Pulse lock per dance** (`KaguraPulseLockReplayTests`, the spike's detectors on the dancer's output, ±⅛
beat, chance 25 %). Build on-beat / half-beat %, with the spike at k = 0 and the lowest of its five
whole-beat cuts (on-beat, on + half):

| Capture | Dance | Build | Decoy | Spike k=0 | Spike lowest cut |
|---|---|---|---|---|---|
| love_rehab | twist | 100 / 0 (n 44) | 0 / 100 | 100 / 0 | — |
| love_rehab | cabbage | 100 / 0 (n 14) | 0 / 100 | 100 / 0 | 93 / 93 |
| love_rehab | chicken | 48 / 26 (n 42) | 27 / 54 | 49 / 32 | 41 / 67 |
| love_rehab | macarena | 60 / 0 (n 40) | 0 / 60 | 51 / 0 | 41 / 44 |
| love_rehab | Egyptian | 38 / 62 (n 34) | 50 / 50 | 39 / 61 | 36 / 100 |
| so_what | twist | 100 / 0 (n 51) | 0 / 100 | 100 / 0 | — |
| so_what | cabbage | 100 / 0 (n 16) | 0 / 100 | 94 / 0 | 94 / 94 |
| so_what | chicken | 44 / 29 (n 45) | 28 / 46 | 49 / 24 | 45 / 68 |
| so_what | macarena | 43 / 30 (n 44) | 32 / 41 | 38 / 47 | 36 / 75 |
| so_what | Egyptian | 85 / 15 (n 47) | 18 / 82 | 42 / 56 | 40 / 95 |
| there_there | twist | 100 / 0 (n 48) | 0 / 100 | 100 / 0 | — |
| there_there | cabbage | 100 / 0 (n 15) | 0 / 100 | 100 / 0 | 94 / 94 |
| there_there | chicken | 45 / 30 (n 44) | 23 / 50 | 51 / 31 | 31 / 59 |
| there_there | macarena | 40 / 36 (n 42) | 36 / 40 | 38 / 45 | 33 / 76 |
| there_there | Egyptian | 44 / 56 (n 45) | 51 / 47 | 29 / 71 | 29 / 97 |

The gate is 10 points under the spike's lowest cut: a whole-beat grid shift keeps the true phase and only
moves where clips start, and the spike's figure moves by up to 20 points from that alone (there_there
chicken 51 → 31 on the beat). Against the k = 0 figure alone, one pair misses by 12: so_what macarena, on +
half 73 against 85 (its cuts read 75–80). The decoy must move (on − half) at least 5 points toward the
other side; the macarena's landings sit between beats (its early skew), so its decoy moves least (8).

**Arm reach (§8).** `1 + 0.25·tanh((e − mid) / (p90 − p10) · 2)` over the trailing window, faded in over the
first 4 s. Two guards the spike never needed, both outside anything real music reaches: the p10–p90 width is
floored at 0.01 (narrowest of 80 captures 0.0117), and reach changes by at most 1.0 / s (the spike's formula
peaks at 0.84 / s on the same 80). Without the rate limit a drop into silence moved a wrist 0.108 m in one
frame. Wrist-to-shoulder ratio 0.76–1.20 on a varying synthetic bass; legs bit-identical with and without.
Foot-slide on the route-coverage captures 21.9 / 25.2 / 23.1 cm/s, KAG.2's figures.

**The safety net (§7).** CV of the last 16 grid intervals, evaluated per beat. Sway above 0.08; rejoin once
under 0.06 for 8 beats. On the 30 beta captures (grids from their own `beatPhase01`, as the spike built them),
steady windows peak at 0.062 (Take Five 50 %) and irregular ones never drop under 0.102 (Moonlight 80 %):

| Song (20 / 50 / 80 %) | Max rolling CV | Safety net held | Spike (README §11) |
|---|---|---|---|
| Dance Yrself Clean | 0.016 / 0.023 / 0.021 | 0 / 0 / 0 % | steady |
| B.O.B. | 0.032 / 0.034 / 0.037 | 0 / 0 / 0 % | steady |
| Superstition | 0.022 / 0.027 / 0.030 | 0 / 0 / 0 % | steady |
| Smells Like Teen Spirit | 0.024 / 0.029 / 0.028 | 0 / 0 / 0 % | steady |
| Penny Lane | 0.033 / 0.028 / 0.030 | 0 / 0 / 0 % | steady |
| Take Five | 0.046 / 0.062 / 0.039 | 0 / 0 / 0 % | steady |
| Pyramid Song | 0.281 / 0.371 / 0.452 | 100 / 100 / 100 % | sways (0.105–0.395) |
| Teardrop | 0.020 / 0.017 / 0.013 | 0 / 0 / 0 % | steady |
| Moonlight I | 0.601 / 0.319 / 0.134 | 100 / 100 / 100 % | sways (0.129–0.533) |
| Warszawa | 0.043 / 0.025 / 0.643 | 0 / 0 / 100 % | dances, dances, sways (0.566) |

Steady windows dance 88–98 % of their 30 s (the rest is the opening sway to the first bar line). Dance
Yrself Clean's first 30 s (spike session) sways through the hush and dances from 17.2 s; Girl from Ipanema
and Money, which the spike swayed whole, now sway about half their window — the per-section evaluation.

**The silence rest (§3a).** The same envelope under **0.02** for a full bar (or for all of a younger window —
a track that opens silent has no music to leave). Measured: the quietest beat-bearing bar on the 30 beta
captures peaks at 0.065 (B.O.B. 80 %; Penny Lane's quietest 0.166); a real track end (Warszawa's tail,
production chain) reads 0.0047 at its first silent row and 0.001 after. On a paused or ended local file the
playback clock holds (BUG-130 bounds it at 1.5 s), so no bar line comes: a beat advancing at under a quarter
of the tempo for 0.5 s fades the dance to the sway in render time. **Grounding level 3 — M7 judges it.**

**The routes (§9).** `audio_routes`: `bassAtt` × `arm_reach`, `dance_pick`, `silence_rest`, all `continuous`
(`RouteCoverageTests` green). The silence rest is an enable, but `gate` asserts the primitive is itself an
enable (peak ≥ 0.9), which `bassAtt` is not, so it is declared on the primitive it reads. The grid-driven rows
(the moves on the beat, the clip-change timing) have **no schema kind** and are not declared; they are gated
by `KaguraPulseLockReplayTests`. The repertoire reads `TrackProfile`, not a `FeatureVector` field, and is not
declarable either. `requires_regular_beat: true`; no golden plan moved (`certified: false` keeps Kagura out of
the planner).

**Frame cost.** Release (`KAGURA_PERF=1 swift test -c release --enable-testable-imports`, TESTREL.1), 1920×1080,
no readback, auto mode on love_rehab, `KaguraFrameCostTests`: GPU median 0.096–0.291 ms and p95 0.136–0.307 ms
over two quiet runs (the spread is GPU clock state; a third run under another session's test load read p95
5.7 ms with 1 frame in 1731 over 1 ms); CPU `update` median 0.014–0.042 ms. The selection code costs nothing
visible; KAG.2 measured 0.216 ms.

**The chicken dance is out of the pick (Matt, 2026-09-28, after the three live sessions of that day).** Live,
on the beta playlist: the twist "synced beautifully", the cabbage patch works but is "a little slow" on
energetic songs (one circle per 2 beats on Smells Like Teen Spirit, per 4 on B.O.B.), the chicken dance
"doesn't really work" and "should be used sparingly, if at all". It locks at ~45 % on the beat (the spike's
figure too) and was in every one of the ten repertoires. `KaguraRepertoire.dances` is now twist, cabbage,
macarena, Egyptian; `spikeDances` keeps the spike's five for the README reproductions, and the chicken's clips
stay in the KAG.1 resource. On the beta playlist that leaves two repertoires: Egyptian / cabbage / twist
(Dance Yrself Clean, Smells Like Teen Spirit; B.O.B. gets macarena for Egyptian) and Egyptian / macarena /
cabbage (the other seven). The cabbage patch is now in every repertoire.

**The bar is ranked against bars (Matt, 2026-09-28, step 2).** The spike's `erank[w].mean()` averaged the
per-sample ranks of the bar's moments, and an average of ranks crowds toward ½: live, 49 of 79 picks (62 %)
fell in the middle third, and on energetic songs the cabbage patch took 17 of 21 changes (Dance Yrself Clean)
with the twist at 1. `KaguraEnergy.rank(ofLast:)` now ranks the bar's mean envelope among the means of every
bar-long stretch in the trailing window. On 90 s of real music (the route-coverage captures back to back),
bars split calm 23 / middle 26 / vigorous 51 % (the per-sample rule, by pick: 8 / 60 / 32); the vigorous share
there is the captures getting louder one after another, which a trailing window rightly calls loud. A loud
stretch still keeps the vigorous dance; there is no rotation term.

**The Charleston and ballet join (Matt, 2026-09-28: "add the Charleston and ballet").** From the CMU survey
(`kagura_spike/README.md` context; films on the Extreme SSD, `uzume_spikes/kagura/charleston/` and `cmu2/`):
- **Charleston** (`93_04`, `93_05`, whole trials, footfall pulse — the spike's default `beat_events` branch, now
  in the bake). A fast-song dance: in its films one step per beat puts 86 % / 94 % of footfalls on the beat on
  B.O.B. / Take Five, but at 98–117 BPM the level rule halves it and the 4 s clip runs out mid-bar. So the bake
  excludes ×½ (as for the twist) and the pick admits it only at one step per beat within 0.8–1.25× natural
  speed (≈ 137–214 BPM). Its vigor (1.25 m/s, the twist's 0.71) is capped at the top of the others' scale;
  uncapped it stretched the scale, gave Dance Yrself Clean a 0.56× Charleston in place of the twist and kept it
  off Take Five. On the beta playlist it joins B.O.B. (cabbage, twist, Charleston) and Take Five (macarena,
  cabbage, Charleston); every other repertoire is unchanged. Pulse lock (forced, route captures at 118–135 BPM,
  0.67× speed): 63–76 % on the beat against the spike's 47–56 %, decoy swaps.
- **Ballet** (`49_09`, `49_12`, `49_22`, unwarped). Matt's pick: **the calm songs' rest** — wherever the dancer
  would rest (no grid, unlocked, uneven beat, silence, stopped clock) on a song whose energy is in the calm
  third, it does ballet, rotating the three clips with 1.5 s crossfades after each clip's forward-and-back
  cycle; Pyramid Song (middle energy, whose sway Matt liked) and energetic or unknown songs keep the sway. On
  the beta playlist: Moonlight I, Penny Lane, Warszawa. Its feet slide 1.2 cm/s (the sway 3.4). Grounding level
  3 for the look: M7 judges whether its held poses read as dance or as a freeze.
- Survey leftovers, not added: Indian dance (subject 94; mostly travels, and its in-place windows lock like the
  gesture dances), jumping jacks (every CMU run is ≤ 3 jacks), side twists (exercise), moonwalk (travels).

**Main merged in (2026-09-28).** BUG-144 on main makes `TrackProfile.mood` the song's median after the first
sixth, the same rule and values as KAG.3's `songArousal` (confirmed by that session to three decimals), so
the field is gone: Kagura reads `mood.arousal`, `energyReference` is unchanged, and the cache is main's v17
(KAG.3's v18 entries re-analyse once). Main's D-259 energy curve (`TrackProfile.energyCurve`) is not yet
Kagura's input — moving the song energy onto it changes which songs get which dances, a call for Matt.

**M7 PASSED (Matt, 2026-09-28, beta playlist, local files; session `2026-09-28T16-18-10Z`):** *"looks much
better, happy with it overall. macarena is a little heavy in this set, but it's ok."* Next: certification
(KAG.4). The session, from its `KAGURA_SONG` / `KAGURA_PICK` lines: every song got its intended repertoire;
ballet rests on Penny Lane, Moonlight I and Warszawa; the Charleston on B.O.B. and Take Five; 190 picks split
calm 65 / middle 60 / vigorous 65 (twist 38, cabbage 55, Egyptian 52, macarena 30, Charleston 15). Chain health
`degraded` (`signal_health_band_low`), as in every local session that day.

**The reference keeps one pre-BUG-146 point.** After the main merge, BUG-146 (MIR at 44.1 kHz whatever the
file's rate) moved Superstition's song arousal from 0.206 to 0.494; the other nine are unchanged. Re-deriving
`energyReference` would move Take Five to energy 0.333 — off the Charleston and onto the calm-rest boundary —
which is not what Matt approved at M7, so the constant stays as approved (Superstition's repertoire is the same
either way). It is re-derived when the song energy moves to D-259's energy curve.

**Library growth (Matt, at M7):** "the preset will ultimately benefit from more dances, like the tango, salsa,
fox trot, lindy hop, etc. i'd also love to see the cha-cha slide." Constraint from the spike: CMU's salsa and
lambada travel (they smear under look B), its Lindy/Charleston trials are 2–4.5 s, and it has no tango, fox trot
or cha-cha slide — these need another motion source or in-place re-cuts, each watched in motion before it ships.

**KAG.4 — certified, the 26th (2026-09-28).** On the KAG.3 M7 above (Matt: *"we can move to certification!"*).
Gates: `FidelityRubricTests.certifiedPresets` (lightweight; `expectedAutomatedGate` stays `false` — the dance is
CPU-side, the Filigree precedent), `PhotosensitivityCertificationTests.multiPassMeasured` with three real
`MultiPassFlashHarnessTests` measurements (the dance, the Charleston, the ballet rest: 0.00 flashes/s each),
`RouteCoverageTests` (three `bassAtt` routes green), `OrchestratorCertifiedFilterTests`, and every golden session
plan unchanged with Kagura in the planner. The reference README's four-item contract is scored with evidence.
The external curated reference set planned for KAG.4 was not made (outside imagery; Matt's curation) —
certified on the first-party anchors, the Nebula precedent.

## 16. What the build settled (KAG.5)

**Song energy is measured, per stretch (D-259 §4 amendment; Matt, 2026-09-28: "the next Kagura increment:
song energy").** The mood classifier's arousal left Kagura, with `energyReference`. Each clip change reads the
energy section playing (`TrackProfile.energySections`, pushed by the app at track start and read at the
playback position); a new section's repertoire takes effect at the next clip change, a bar line. The calm rest
reads the same section (ballet at level ≤ 3); a silence reads the section it interrupts.

**Matt's two calls (2026-09-28).**
- **A stretch is judged by its loud end** (B, after task 1): its 90th-percentile level, the readout's `high`.
  The median put Dance Yrself Clean's drop at 8, and at its ~97 BPM the twist needs 9, so the drop would have
  danced the hush's three. Costs, accepted: Teardrop's body gains the twist; a song-ending fade is judged by how
  loud it starts (Teen Spirit's last 19 s keep the twist; Pyramid Song's and Teardrop's final stretches lose ballet).
- **Tempo earns the Charleston** (B): any song in its band (~137–214 BPM) keeps it, whatever the energy.

**Task 1's table** (`KAGURA_ENERGY_TABLE=1 … KaguraBetaPlaylistReportTests`, Matt's v17 cache entries; the
dancer's tempo is the grid's median beat interval). Before = KAG.4 (arousal), as live at the KAG.3 M7.

| Song | Tempo | Energy | Before (KAG.4) | Stretch: loud end → repertoire, rest (shipped) |
|---|---|---|---|---|
| Dance Yrself Clean | 96.8 | 2 → 9, typical 5 | egy / cab / twist, sway | 0:00 **2** egy / mac / cab, ballet · 3:08 **9** egy / cab / twist · 5:57 **3** calm three, ballet · 6:35 **9** twist trio · 8:18 **3** calm three, ballet |
| B.O.B. | 150.0 | 8 → 10, 10 | cab / twist / chs, sway | 10: cab / twist / chs, sway |
| Superstition | 100.0 | 4 → 6, 6 | egy / mac / cab, sway | 6: same |
| Smells Like Teen Spirit | 115.4 | 5 → 8, 7 | egy / cab / twist, sway | 0:00 8 and 4:42 8: same |
| Penny Lane | 115.4 | 5 (4 → 5) | egy / mac / cab, **ballet** | 5: same, **sway** |
| Take Five | 176.5 | 2 (2 → 3) | mac / cab / chs, **sway** | 3: **egy** / mac / chs, **ballet** |
| Pyramid Song | 107.1 | 4 → 10, 8 | egy / mac / cab, sway | 0:00 4 calm three · 0:22 7, 1:56 10, 4:28 10: egy / cab / twist |
| Teardrop | 76.9 | 5 → 9, 8 | egy / mac / cab, sway | 0:00 5 same · 0:44 **9**: mac / cab / **twist** · 5:11 6 same |
| Moonlight I | 46.9 | 1 | egy / mac / cab, ballet | 1: same |
| Warszawa | 76.9 | 3 → 6, 5 | egy / mac / cab, **ballet** | 0:00 2: ballet · 0:23 6: **sway** |

Bar shares over the playlist (1,475 bars; the bar pick splits each three in thirds): before twist 12 %, cabbage
33 %, macarena 21 %, Egyptian 24 %, Charleston 10 %; shipped twist 16 %, cabbage 28 %, macarena **20 %**,
Egyptian 27 %, Charleston 10 %. (The median rule would have given twist 9 %, macarena 24 %.) The typical-level
column reproduces NRG.2's readouts exactly. The table is `KaguraRepertoireTests.build`, one row per section.

**Found:** the `KAGURA_SONG` line printed the grid's trimmed-mean BPM (98.0 for Dance Yrself Clean) while the
pick reads the median beat interval (96.8). No repertoire differed at the KAG.3 M7; the line now prints the
tempo the pick reads.

**Streaming** uses the preview's loud end as its one section (the same rule as a whole-track stretch), not the
typical level the prompt named: B makes a stretch's loud end the measure, and a preview is one stretch.

**M7 round 1 (Matt, 2026-09-28, session `2026-09-28T21-31-31Z`):** *"Penny Lane does not sway - it plays the
macarena. In fact, I saw the macarena for everything I played. Otherwise, looks good."* Penny Lane dancing is
correct: the sway is its rest, and its three dances are unchanged since KAG.3. The macarena was real. Excluding
the seek burst (BUG-155) it took 23 of 68 picks, against 30 of 190 at the KAG.3 M7. Two causes:
- Every song opened on its middle dance, because the pick has no history in its first bars and the rank read ½.
- KAG.5 made the macarena the middle of more stretches (Dance Yrself Clean's calm sections, Take Five).

**Matt's call (option A): a song opens on its calm dance for its first 4 bars** (`warmUpBars`); the bar pick
ranks after that. Rejected: leaving it, and more calm dances (the long-term fix; the library-growth increment).
Take Five's early run of Charleston picks (7 of its first 8, ranks at 1.00) is only partly a warm-up effect: its
intro builds, so each new bar out-ranks the last. The warm-up covers its first two clip changes.

**Status:** pending Matt's live M7 round 2 on the beta playlist (local files).

