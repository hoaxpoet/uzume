# Understory — Design

**Status:** 🔨 **UND.1 GO; UND.2 field built; UND.3 colour + forest backdrop first pass — fidelity push in progress (Matt: "the fidelity of the background is low overall").** Written
2026-10-01 from Matt's direction (same day) and a desk port-survey of the source preset. Concept-gate
artifacts 1–3 exist (§2); artifact 4, the running look-spike, is built and motion-gated (§2, §12).
**Family:** `fractal` · **Rubric:** `lightweight` (stylized 2D graphic, the Fractal Tree precedent) ·
**Paradigm:** `staged` (one paradigm, D-029)
**Name:** *Understory* is a **working name**. Final naming is owned by `hoaxpoet/uzume-site`
(`BRAND.md`; the myth slate in `docs/planning/`). Increment prefix `UND.` (unused in
`ENGINEERING_PLAN.md` / `DECISIONS.md` as of this writing).
**Inspired by:** Flexi — *"flexi - fractal seafood"* (Milkdrop 2 original pack). §3.

Companion: `docs/presets/UNDERSTORY_PLAN.md` (increments, gates, cut-lines).

---

## 1. What it is

A bed of luminous, psychedelically coloured fern fronds fills the frame, overlapping in three depth
layers. They are rooted below the bottom edge and arch up and across the screen. The bed sways as
if wind blows through it, and every frond whips and twitches toward its tip. On each beat a shimmer
runs from the base of one frond up to its tip and out through its leaflets. The shimmers step across
the bed in the same order every bar, so the listener learns the pattern. In the foreground, two or
three fiddleheads (coiled young fronds) uncurl while the singer sings and slowly re-coil when the
voice drops out.

**Story (See / Move / Music):**
- **See:** 12–16 fern fronds in a dense bed on a dark ground. Each is a self-similar fractal: a curved
  central stem with alternating leaflets, and each leaflet is itself a small frond. Colour runs in
  saturated rainbow bands from base to tip, not leaf-green.
- **Move:** across a ~30 s window the whole bed sways left and right in gusts that visibly travel
  across the frame. Each frond bends hardest near the tip and overshoots, which is Flexi's
  two-spring whip. Fiddleheads in the foreground open and close over several seconds.
- **Music:** each beat of the cached `BeatGrid` sends one shimmer from base to tip of one frond
  (downbeat = the large lead frond, beats 2…N = a fixed set stepping across the bed). The balance of
  bass against treble is the wind. Vocal phrases unfurl the fiddleheads.

**Musical-role sentence (PRESET_SESSION_CHECKLIST Part 2):** *Understory is the band's
percussionist-with-a-light: every beat of the bar sends a shimmer racing up one frond, in the same
left-to-right order each bar with the downbeat on the lead frond. Meanwhile the bass-versus-treble
balance blows through the bed as wind, and the singer's phrases uncoil the fiddleheads.*

---

## 2. Concept gate (`preset-concept` skill) — status

| Artifact | Status | Evidence |
|---|---|---|
| 1. Watched moving source | ✅ | *flexi - fractal seafood*, rendered through butterchurn on 2026-10-01 against `love_rehab` (fixture). Matt confirmed it is the fern he remembers. |
| 2. Look verified across the sequence | ✅ | UND.0: deterministic 60 fps oracle renders (`tools/milkdrop-render/render-sequence.js`, audio injected per frame) of 12 s × 3 tempo fixtures, full preset and a rooted frond-only variant. `motion_gate.sh`: 0 spikes / 719 on all six. Read as a sequence: the bend accumulates along the frond, a strong swing curls it into a crozier, it snaps straight and whips the other way, tip leading (§12). |
| 3. Three-sentence story | ✅ | §1. Each sentence is checkable: frond count and structure, travelling gusts plus tip whip, one shimmer per grid beat in a fixed order. |
| 4. Running motion-gated look-spike | ✅ built / ⏳ Matt | UND.1: one frond, ported verbatim, in the production staged path. Side-by-side films vs the oracle on the same audio; `motion_gate.sh` 0 spikes on all three; bend statistics within the source's range per fixture (§12). **Go/no-go for everything after.** |

**Three-part concept bar:**
1. *Iconic subject at fidelity:* **one frond is proven** (the source renders it). **A bed of independent
   fronds is not proven by any reference.** That is the main fidelity risk, and UND.2 exists to
   answer it before colour or audio work starts. Recall Matt's Fractal Tree verdict ("probably as good
   as we're gonna get"). A recursive plant is a known hard subject here, so the spike decides, not
   this doc.
2. *Clear musical role:* ✅, the sentence above, with three layers on three distinct timescales (§6).
3. *Infrastructure-feasible:* ✅ with one caveat. Every surface exists (`staged` +
   `persistent` stages + slot-6 CPU state, §5), but **no shipped scene uses a persistent stage
   yet.** Only the diagnostic `PoissonSandbox` declares `"persistent": true`. Understory would be its
   first production consumer.

---

## 3. The source: what Flexi built, and what we port verbatim

`flexi - fractal seafood` draws a single fern with a **feedback IFS** (iterated function system) in
the warp shader. Each frame, the red channel is rebuilt as the max of the previous frame sampled
through three affine maps. Flexi's own comments: `// main arm of the fern`, `// the fractals left
arm`, `// the right arm`. A small additive circle (shape 0, radius 0.058, red) is the seed at the
base. The fern is the attractor of those three maps, re-derived every frame from the last.

```
main arm : uv1 = 0.5 + R(ww)·(uv−0.5)·1.12 + 0.042·(sin w, cos w)      // shrink 1/1.12 toward the tip
left arm : uv2 = 0.5 + R(+π/4)·(uv−0.5)·3.3  + 0.08·(cos(π/2−w), sin(π/2−w))·aspect
right arm: uv3 = 0.5 + R(−π/4)·(uv−0.5)·3.3  + same offset
ret.x    = max(prev(uv1), prev(uv2), prev(uv3)) − 0.015                 // per-frame fade
```

**The sway is a two-spring system**, driven by bass minus treble (per-frame, Milkdrop units):

```
bb  = 0.97·bb + 0.04·bass ;  tt = 0.97·tt + 0.04·treb ;  drive = (bb − tt)·0.2
v1  = 0.95·v1 − (y1 − drive)·0.1 ;  y1 += 0.1·v1          // slow spring: the gust
v2  = 0.99·v2 − (y2 − y1)·0.2   ;  y2 += 0.2·v2           // fast, lightly damped: the twitch
ww  = −(y1 − y2)·(1 + (70/fps − 1)·2) − 0.8·y1            // "bending indication"
w   = heading − 5·ww                                       // the base swings too
```

`ww` is applied **once per IFS generation**, so the bend accumulates along the frond. The tip bends
most, and because the IFS re-derives the frond from last frame's frond, a change at the base
reaches the tip several frames later. **That lag is the whip and the twitch Matt remembers.** It
falls out of the mechanism; nothing is animated by hand.

**Port verbatim (FA #64/#65/#73):** the three maps and their constants (1.12, 3.3, ±π/4, 0.042,
0.08, −0.015), the seed, and the two-spring system with its coefficients. The springs run on the CPU
at a fixed 60 Hz substep so their character does not depend on render rate. Flexi's own
`70/fps` correction becomes a constant.

**Adapt (context only):** ~~the drive input becomes `bass_dev − treb_dev`~~ **Superseded at UND.1
by measurement:** the drive is Milkdrop's own band level, ported from butterchurn's `AudioLevels`
(`val = imm / longAvg`, long average at 0.992 per 30 fps frame ≈ 4 s), applied to Uzume's `bass` and
`treble`. The ratio to the band's own recent average is scale-free (the AGC cancels), so it is a
deviation form, not an absolute threshold (FA #31). Flexi's 0.2 gain is kept: the re-fit on the bend
`ww` against the oracle landed at 0.188 / 0.189. Two unit constants are adapted: the average seeds
from the first sample instead of 1.0, and the silence floor is 1e-5 instead of 0.001, because
butterchurn's `imm` is a sum of FFT bins while Uzume's AGC'd treble sits near 0.002. Two candidates
were measured on the three fixtures and rejected:
- `bassDev − trebDev`: `trebDev` runs ~100× below `bassDev` (additive deviations of a band that
  sits at ~0.005 after AGC), so the drive collapses to bass-only and the frond bends one way only.
- `band / (band − rel/2)` (the ratio recovered from `BandDeviationTracker`'s ~21 s average):
  lopsided. On so_what the bend's p02 was −0.08 against the source's −0.25.
Heading, position and scale per frond come from the layout (§4.1).

**Drop:** the swimming. Flexi's `w1`/`vx`/`vy` move the creature around the screen through the comp
shader (`uv_swimmer`); our fronds are rooted. Also dropped: the embossed orange-to-magenta "goo"
background and the green Julia set (`ret.y`, `u → u² + c`) that feeds it.

**Provenance (MILKDROP_STRATEGY §13.3).** The artifact actually read was the **pre-converted
butterchurn JSON** in `butterchurn-presets@2.4.7`, `presets/converted/flexi - fractal seafood.json`,
sha256 `d0ca386c74a4be1ebacfc451cf48e3e7c6a3aac94ddf705d116ad5ebccd627d9`. Note that this preset is
**not one of the 100 built-ins** `tools/milkdrop-render/README.md` vouches for. It is from the package's
larger converted set, and it rendered with its expected structure (seed, three-map frond, sway). The
`.milk` (projectM `presets-milkdrop-original`) was read for comments only. Neither file is committed
(D-116 bullet 4).

---

## 4. Creative architecture

### 4.1 The bed: layout and depth

> **Decided 2026-10-01 (Matt, §10-3): a FIELD, not a blanket.** *"Show a field of ferns swaying in
> the wind and have a combination of open and closed fiddleheads."* Default adopted: ~8 open fronds
> spread across the frame at two depths, plus 4 fiddleheads at different resting coil stages, with
> dark ground between them so each frond's whip is followable. The voice still uncoils the
> fiddleheads (§4.4, locked), each from its own resting curl. Evidence that the mix is nearly free:
> the oracle's frond curls into a crozier on its own under a strong swing (ref `01`), so open and
> closed are one mechanism at different bend. The bullets below are the superseded blanket layout,
> kept for the depth/painter's-order rules that still apply; UND.2 re-lays it as a field.

- ~~**12 simulated fronds** in three depth layers~~: back 5 (small, dimmer, lower saturation), middle 4,
  front 3 (large). The front layer holds the **lead frond** (the downbeat's) and **2 fiddleheads**
  (§4.4). Back-layer fronds may be drawn twice, mirrored and re-hued, to reach ~16 visible. Decided
  in UND.2 on renders: a mirrored twin sways in lock-step with its original, which may read as a
  copy.
- Roots sit below the bottom edge (a few at the lower-left and lower-right corners). Headings fan
  from about −50° to +50° from vertical, so the bed arches up and across and overlaps through the
  middle of the frame. Placement is a seeded layout with per-frond jitter (FA #44: no mirror
  symmetry, no uniform sizes). The layout is fixed for a track and re-seeded at track change.
- Painter's order back → front. No depth buffer is needed (the Fireflies depth-band precedent).

### 4.2 Wind: one gust field, many fronds

Every frond runs Flexi's two springs on the same drive signal, with two differences per frond:
- **The gust travels.** Frond *i* reads the drive delayed by `x_i / v_wind` (a ring buffer of drive
  history; `v_wind` ≈ 0.6 screen-widths/s, tuned in UND.2). A bass swell visibly crosses the bed left
  to right instead of moving every frond at once.
- **Stiffness jitter** of ±15% on both springs, so neighbours drift out of phase and the bed never
  moves as one block.

### 4.3 Shimmer: one frond per beat, a pattern the ear can learn

- Every frond carries a per-pixel **path length from its seed** (§5.3). A shimmer is a bright band at
  path position `p_front = (t − t_beat)·speed`. It rises from the base through the stem, branches out
  into each leaflet as it passes, and fades at the tip. Base to tip takes ~0.35 s at the starting
  speed, tunable and independent of frame rate.
- **The sequence.** Beat 1 (downbeat) goes to the lead frond. Beats 2…N (`beats_per_bar`) go to a
  **set** of N−1 middle-layer fronds ordered left to right. The same set repeats for 4 bars, then the
  set rotates to the next group. The repetition is the point: by the second bar the eye anticipates
  where the next shimmer lands.
- **Footprint (D-157):** one frond per beat, a travelling band and not a whole-frond flash. Global
  luminance stays steady. The photosensitivity gate (`MultiPassFlashHarnessTests`) must measure 0.00
  flashes/s.
- **Look:** the band is a white-hot core with a hue shift (rotating the palette half a turn under the
  band) and a short afterglow. Exact look tuned in UND.4.

### 4.4 Fiddleheads: what the voice does (deliberately not Gossamer)

Fern fronds unfurl from tight coils (fiddleheads). In the IFS this is one extra constant: a **curl
bias κ** added to `ww` on every generation. κ = 0 is an open frond; κ ≈ 0.2–0.3 rad/generation
coils it into a spiral (the value is confirmed in UND.5).
- The two foreground fiddleheads take `κ = κ_max·(1 − unfurl)`, where **`unfurl` is the vocal
  phrase envelope**: vocals-stem energy, attack ~1.5 s, release ~5 s. A sung line uncoils them; an
  instrumental break lets them coil back.
- **Why this and not Gossamer's routes:** Gossamer maps vocal *pitch* to wave colour and vocal
  *energy* to strand displacement on a beat-free timescale. Here the voice owns a **phrase-scale shape
  change** with no colour and no waves. It is fern-specific botany and sits on its own timescale
  (seconds), clear of the beat (shimmer) and the gust (sway).
- On instrumental tracks the fiddleheads stay coiled. They still read as part of the bed. Open
  decision §10-4.

### 4.5 Colour: psychedelic, harmonic, not on a timer

- **Hue runs along path length.** Saturated bands march from base to tip and out into every leaflet,
  so the self-similarity reads as colour. Each frond gets its own hue offset; the back layer is darker
  and less saturated so depth survives the saturation.
- **The palette rotates with harmony** (`tonal_phase_fifths`, the Fractal Tree / Nacre precedent). A
  chord change moves the whole bed's colour. Nothing drifts on a wall clock (anti-reference).
- **Ground:** dark, never black (D-037). A deep tone tied to the palette's complement, with a
  slight vignette.
- **Afterglow trails:** a persistent echo stage holds a decayed copy of the bed, so the sway smears
  into Milkdrop-style ghost trails. Trail length follows `arousal` (calm → short and clean, intense
  → long and smeared).

### 4.6 What it must not look like (anti-references, carried to `VISUAL_REFERENCES/understory/`)

- **A realistic green fern** (bark, chlorophyll, daylight, botanical illustration). That register is
  Goldengrove's.
- **The textbook Barnsley fern**: one static, symmetric, green fractal centred on black.
- **A colour-cycling wallpaper**: hue moving on a timer while the music does something else.
- **A beat strobe**: a whole frond or the whole bed flashing on the beat. The shimmer travels; it never
  pops.
- **A single swimming creature.** That was the source's concept, not ours.

---

## 5. Rendering architecture

### 5.1 Paradigm and passes (`passes: ["staged"]`)

| Stage | Persistent | Format | Samples | Does |
|---|---|---|---|---|
| `fronds` | ✅ | `rgba16Float` | — (own prev at `texture(20)`) | **The frond atlas.** The drawable-sized target is split into 12 tiles. Each tile runs Flexi's three-map feedback IFS with *its own* frond's bend (`ww_i + κ_i`), heading and seed, sampling clamped to its own tile. One full-screen pass is all 12 IFS steps. |
| `bed` | ✅ | `rgba16Float` | `fronds` | **Composite + afterglow.** For each pixel, loop the fronds back → front (bounding-box reject), inverse-transform into the frond's tile, read density and path length, colour it (§4.5), add the shimmer (§4.3), and alpha-over. Then `max(bed, prev·decay)` for trails. |
| `present` | — (final) | drawable | `bed` | Ground, vignette, a cheap glow from a few wide taps, tone map. |

Why a tiled feedback atlas rather than drawing fronds analytically: the **whip is the feedback lag**
(§3). A direct SDF frond would need that lag re-created by hand, which is exactly the kind of
re-invention FA #73 forbids when a working source exists. The atlas keeps Flexi's mechanism verbatim
and multiplies it. **Fallback if UND.2 fails** (tiles too coarse, or seams): an analytic frond in
`bed` with an explicit per-generation delay line on the CPU. That is a level-3 design (§7), so it
only gets built if the atlas is disproven.

### 5.2 State model: CPU `UnderstoryField` → `buffer(6)`

A Swift state object (the `GossamerState` pattern), bound at fragment `buffer(6)`; `RenderPipeline+StagedEncode`
already binds slots 6–8 for staged passes. Per frond: tile rect, root position, heading, scale,
mirror, layer, hue offset, `ww_i`, `κ_i`, and last shimmer onset `t_beat_i`. Plus globals: frame
stamp, palette rotation, trail decay, gate flags. It is updated once per frame before encode, with
springs integrated at 60 Hz substeps. Registered through `StatefulRuntimeRegistry` / `applyPreset` per
NEW_PRESET_CHECKLIST §5. Size is about 12 × 64 B; `setFragmentBytes` would do, but a buffer matches
the precedent.

### 5.3 Path length for free: the frame stamp

The atlas's **G channel carries a frame stamp.** Each frame the seed writes the current frame index
(mod 1024, exact in fp16), and each map copies the stamp from whichever map won the max on R. At
equilibrium every pixel holds `frameNow − (generations from the seed along its path)`. So
`p = (frameNow − G) mod 1024` **is the path length in generations**: stem plus leaflets, exactly
the "base to tip and out through the leaflets" coordinate the shimmer and the colour bands need. It
costs one extra channel and no geometry. **No reference uses this** (level 3, §7); UND.3 verifies it
on a still and a sequence before the shimmer depends on it.

### 5.4 Resolution

Tiles are drawable-sized ÷ (4×3): 480×360 at 1080p. ~~In the source render the whole frond spans
~120 px of a 640×480 frame, so a tile holds the frond at ~3× the source's native size.~~
**Corrected at UND.0 (measured):** the frond spans ~230 px of the 640×480 frame, seed at the centre to
near the top edge, so a 480×360 tile holds it at **0.75×** the source's resolution, not 3×. A front
frond at ~60% of screen height would upscale ~3.8×. Two levers for UND.2, decided on renders: (a) the
frond occupies only the top half of its frame (seed at centre). The maps are affine about the frame
centre, so conjugating them by a translation puts the seed near the tile's bottom edge and doubles
the usable height with the mechanism unchanged. (b) Larger tiles for the front fronds (non-uniform
packing). **If that reads soft in UND.2**, give the front fronds larger tiles. Stages have no fixed-size
option today, so a dedicated off-drawable atlas size would be an engine addition. Avoid unless
forced.

---

## 6. Audio routing: one primitive per layer (FA #67), all deviation-normalised (D-026)

| Visual layer | Primitive | Timescale | Notes |
|---|---|---|---|
| Wind: sway, gust front, tip whip and twitch | `bass` vs `treble`, each over its own ~4 s average (Milkdrop `AudioLevels`, §3) → Flexi's two springs | 0.2–2 s, continuous | Layer 1, the default primary driver. The twitch is the fast spring, not a second route. Sidecar routes `wind_bass` / `wind_treble`. |
| Shimmer | `BeatGrid`: `beat_phase01` wrap = beat, `bar_phase01` wrap = downbeat, `beats_per_bar` = set size | per beat | Layer 4 on the cached grid (D-153…D-158). One frond per beat (D-157). |
| Fiddlehead unfurl | `vocals_energy_rel` (stems), phrase-smoothed | 2–8 s | D-019 gate on total stem energy. ~2.5 s live-path lag is tolerable at phrase scale. |
| Palette rotation | `tonal_phase_fifths` | harmonic / section | No wall-clock hue. |
| Afterglow length | `arousal` | 10 s + | Section-scale intensity. |

No two layers share a primitive, and no two primitives drive one layer at the same timescale. Every
route goes into the sidecar's `audio_routes` manifest and must fire in `RouteCoverageTests` on the
committed fixtures. A red route is the gate working.

### 6.1 Grid trust, cold start, irregular beats

- **Shimmer is gated on grid trust**, following Witchlight's precedent: `bar_phase01` is 0 whenever
  no grid is installed, so "has `bar_phase01` wrapped at least once and `track_elapsed_s` > 4 s"
  is the gate. That covers cold start (no wrong-phase shimmers in the first seconds; the scene
  implements its own suppression per the Cold-Start Phase Contract) and D-154 beat-irregular tracks
  (`beat_clarity01` = 0 → no grid → no sequence).
- **Without a grid** (default, open decision §10-2): shimmers fire from `drums_energy_dev` peaks,
  at least 0.35 s apart, on a random middle-layer frond. Sway and fiddleheads carry the track as
  usual.

### 6.2 Silence (D-037; silence is a per-scene decision)

What silence *looks like* here: the bed is still present and fully coloured at ~60% brightness. The
springs coast to rest with a tiny idle-breeze floor, so it reads as still air, not a frozen frame. No
shimmers, fiddleheads coiled, trails decayed. Never black. The M7 judge should hold silence to this
description, not to a global stillness bar.

---

## 7. Grounding (PRESET_SESSION_CHECKLIST: design is upstream of testing)

| Mechanism | Level | Grounding / risk |
|---|---|---|
| Frond geometry (three-map feedback IFS) | **1** | Flexi's warp shader, ported verbatim. |
| Sway, tip whip, twitch (two springs + per-generation bend) | **1** | Flexi's per-frame equations, ported verbatim. |
| Many independent feedback IFS in one tiled persistent stage | **3** | **No reference.** Seam bleed at tile edges and per-tile resolution are the risks. Proven or killed in UND.2. |
| Frame-stamp path length (§5.3) | **3** | **No reference.** Ambiguity where maps overlap may speckle the coordinate. Verified in UND.3 before the shimmer depends on it. |
| Travelling gust (delayed drive per frond) | 3, trivial | A delay line; low risk. |
| Fiddlehead coil via constant per-generation rotation | 2 | The IFS maths (a constant rotation per contraction gives a logarithmic spiral). κ value from UND.5 renders. |
| Psychedelic palette along path length | 3, look | Judged by eye at M7 against the anti-references. |
| **Combination:** atlas + stamp + composite in one staged chain on a persistent stage | **3** | First production consumer of persistent stages. The harness comes first (UND.0). |

**The level-3 items are surfaced here for Matt to accept or descope**, as the checklist requires.
The plan orders the increments so each one is retired by a render before anything is built on top
of it.

---

## 8. Acceptance (certification preview)

- **Look:** reads at a glance as *a bed of fern fronds* (not a tree, not a texture, not one creature),
  psychedelically coloured; meets the anti-references in §4.6.
- **Motion:** the sway, the tip whip and the twitch match the source's temporal character
  (`Scripts/motion_gate.sh` verdict against the source frames). No jitter or pop spikes.
- **Music:** the shimmer lands on the beat in the declared order (the per-beat frond index is
  logged and checked against `beat_phase01` wraps in a replay); the gust tracks the bass/treble swing;
  the fiddleheads open on sung phrases (fixture with vocals) and stay coiled on an instrumental.
- **Gates:** `RouteCoverageTests` green; photosensitivity 0.00 flashes/s; non-black silence; the
  persistent-staged multi-frame harness (`PersistentStagedPathHarnessTemplate` adapted) green;
  non-finite watchdog never fires in a 10-minute soak.
- **Matt's live M7** on real music, on a `clean` chain-health capture.

## 9. Performance (estimates, to be measured in Release)

`fronds`: one full-screen pass with ~3 taps per pixel. `bed`: per pixel, typically 3–5 overlapping
fronds after bounding-box reject, ~1 tap each plus the stamp. `present`: a handful of taps. **Estimate
≤ 3 ms at 1080p on the Mac mini, Release**, well inside 16.6 ms. Measured and recorded in the sidecar's
`complexity_cost` at UND.2 and again at certification. Any figure quoted says Release.

## 10. Open decisions for Matt (each has a default; accept or change)

1. **Name:** *Understory* (working). Final name comes from BRAND.md / the myth slate.
2. **Tracks with no steady beat:** *default* shimmers follow drum hits on a random frond (no
   sequence). *Alternative:* no shimmers at all; the wind and fiddleheads carry the track.
3. ~~**Density:** *default* a dense bed (~12–16 fronds, ground mostly covered in the middle of the
   frame). *Alternative:* sparser (6–8 fronds, more dark ground, each frond easier to follow).~~
   **Decided (Matt, 2026-10-01): a field** of open fronds and fiddleheads at mixed coil stages, dark
   ground between them (§4.1).
4. **Instrumental tracks:** *default* the fiddleheads stay coiled. *Alternative:* they unfurl to the
   melodic instruments instead (the `other` stem) when no voice is present.

## 11. Doc write-backs when built

`docs/ENGINEERING_PLAN.md` (UND rows), `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` (first production
persistent stage; tiled multi-IFS atlas; frame-stamp path length), `docs/ARCHITECTURE.md` §Module
Map (one line per new Swift file, D-168 gate), `docs/CREDITS.md` §Milkdrop-inspired attribution
(Flexi), the sidecar `inspired_by` block (§3 provenance), `docs/VISUAL_REFERENCES/understory/`.

---

## 12. Build log

### UND.0 — reference lock + harness (2026-10-01)

- **Source oracle.** `tools/milkdrop-render/render-sequence.js` (new): `render({audioLevels,
  elapsedTime})` with the audio window and the frame time injected per frame, so frame *i* is exactly
  t = 8 + i/60 s of the clip at exactly 60 fps, every run. `LOG_VARS=` dumps frame-equation variables
  (`bass treb bb tt q16 y1 y2 ww fps`) per frame, the spring state the port is fitted against. Films
  are outside git at `/Volumes/Extreme SSD/understory/oracle/` (D-211). A **rooted** variant (only two
  edits to the converted JSON: the swim heading update `w1 +=` removed, and comp shows the red
  channel alone) is the like-for-like target for the port.
- **Motion gate on the source:** 0 spikes / 719 on all three fixtures, both variants. The rooted
  variant's "frozen" counts (598 / 387 / 696) are an artifact of a whole-frame mean on a thin subject
  over black, not stillness. The sequence read shows continuous motion.
- **Measured, not assumed:** the frond is ~230 px tall in a 640×480 frame (§5.4 corrected).
- **Harness first:** `UnderstoryStagedHarnessTests` (copy-adapted from
  `PersistentStagedPathHarnessTemplate`): the production `encodeOffscreenStages` → `encodeStage`
  path with a real `UnderstoryField` at slot 6. At silence the frond's mass is 28 at frame 1, 291 at
  frame 30 and 295 at frame 60 (grows, then settles). The watchdog never trips, and the composite is
  non-black.
- **Harness defect fixed on the way:** `SessionReplayHarness` read `trebRel` from a column named
  `"trebRel"`; the CSVs spell it `treb_rel`, so every replay fed it ZERO while
  `ReplayHarnessRouteCoverageTests` listed it as carried. No shipped preset routes on it today.

### UND.1 — look-spike (2026-10-01)

- One frond, Flexi's maps verbatim, in a centred 4:3 tile (the source's frame) of the persistent
  `fronds` stage; `bed` is an identity composite, `present` a flat pale colour on a dark ground.
- **Drive:** see §3. One fix round was used, and it was a port, not a tune: Milkdrop's band
  normalisation replaced the `BandDeviationTracker` ratio.
- **Bend `ww` against the oracle, frames 2–12 s of each window:**

  | Fixture | Source mean / sd / p02 / p98 | Uzume mean / sd / p02 / p98 |
  |---|---|---|
  | love_rehab | +0.021 / 0.060 / −0.059 / +0.201 | +0.051 / 0.085 / −0.068 / +0.300 |
  | so_what | −0.035 / 0.117 / −0.246 / +0.248 | −0.001 / 0.093 / −0.177 / +0.226 |
  | there_there | +0.048 / 0.055 / −0.029 / +0.193 | +0.033 / 0.075 / −0.055 / +0.240 |

- **Motion gate on Uzume:** 0 spikes / 719 on all three. Paired strip (source above, Uzume below,
  same audio, 267 ms apart): the crozier curls land on the same frames, and between them the frond
  straightens and whips the same way. Uzume holds the faint outer leaflets slightly fuller (fp16
  against the source's 8-bit target).
- **Films for the GO/NO-GO:** `/Volumes/Extreme SSD/understory/und1/side_by_side_<fixture>.mp4`
  (left: source, rooted; right: Uzume).

### UND.2 — the field: atlas, layout, wind (2026-10-01)

- **Matt's GO on UND.1** (2026-10-01): *"yes, looks great - keep going"*.
- **Layout** (`UnderstoryLayout`): 14 fronds, 10 open + 4 fiddleheads (near 2 incl. the lead frond,
  mid 6, far 6), seeded per track; roots, scales, leans, stiffness and which slots are fiddleheads
  all come from the seed; drawn far → near. Fiddleheads carry a provisional resting curl
  (0.22–0.30 rad/generation, added to `ww`), which UND.5 fits against ref `02` and uncoils with
  the voice. No mirrored twins: the field direction needs none, and a twin would sway in lock-step.
- **Atlas** (§5.4 decided): depth rows, near 2 / mid 3 + 3 / far 6. Each tile holds a crop of
  Flexi's frame (full width, frame y up to 0.60) at square texels, so the frond keeps its source
  geometry at any drawable aspect. At 1080p: near tiles 960×405 (1.5× source), mid 640×270
  (1.0×), far 320×135 (0.5×); with the chosen sizes every depth is upscaled ~2.4× to the screen.
  It reads soft at native 1080p. `bed` reads the atlas with a Catmull-Rom filter (A/B on a crop:
  leaflet edges defined, not smeared), which narrows it but does not close it. **The softness is
  for Matt's eye at the colour review**, since colour and glow change how it reads. The levers
  if it stays: bigger near tiles (fewer or smaller far fronds), or an off-drawable atlas, which is
  an engine addition and his call.
- **Defect found and fixed:** the first crop clamped samples to the crop edge. A fiddlehead's coil
  touching the edge below the seed smeared back through the maps until its whole tile filled with
  a grey ring pattern (frames 521–637 of so_what, +17 luma). Flexi clamps to the *frame* edge,
  which is empty. Now frame uv outside the crop reads black, and the crop runs to 0.60 instead
  of 0.56. Peak frame luma is now within 0.6–1.3 of the median on all three fixtures.
- **Wind:** one drive history; each frond reads it `root.x / 0.6` s late (≈1.7 s across the
  screen) with its own ±15 % stiffness. Tested: the gust reaches the rightmost frond exactly its
  delay after the leftmost (±2 substeps), and a bass swell and a treble swell lean every frond
  in opposite directions. **Idle breeze** at silence: peak sway < 0.02 rad/generation, never
  frozen (§6.2).
- **Per track:** `resetPerTrackPresetState` re-seeds the layout and zeroes the persistent atlas,
  so a new song's field regrows from its seeds (~1 s) rather than jumping.
- **Release GPU cost** (`UNDERSTORY_PERF=1 swift test -c release --enable-testable-imports`,
  Mac mini M2 Pro, full staged frame, no readback, median of 180): **1.447 ms at 1080p,
  5.735 ms at 4K.** Sidecar `complexity_cost` tier1 3.0 / tier2 1.5 (the Kagura convention:
  measured on this machine, scaled up for base M1/M2, tier2 half).
- **Motion gate** (1080p, three fixtures): 0 spikes / 719, 0 frozen. Films:
  `/Volumes/Extreme SSD/understory/und2/field_<fixture>_1080p.mp4`.

### UND.3 — colour, path-length stamp, trails, and the forest (2026-10-01)

- **Path length (§5.3), built as AGE, verified before use.** G = R · age: each map copies the
  winning tap's age + 1; the seed is age 0; premultiplied so bilinear reads ignore empty texels.
  Same quantity as the design's frame stamp without the mod-1024 wrap. Measured on the near and
  a mid tile (raw atlas, so_what): mean age rises with distance from the seed in **100 %** of
  distance bins; spatial speckle (> 4 generations from the 3×3 median) **0.22–0.35 %**; frame to
  frame |Δage| > 3 on 1.2–5.5 % of pixels — the frond moving, highest on the curled fiddlehead.
  **Age is a generation count, not a length:** the main arm contracts 1/1.12, so the bright
  frond spans only ~12 generations and the tip piles up the rest.
- **Colour.** Colouring by full age gave every leaflet its own rainbow, which read as speckle and
  hid the fern. A second stamp, **B = R · stem**, counts only the main-arm generations outside the
  first branch (main arm wins: +1; a side arm wins: reset to 0), so a leaflet carries the stem
  position it grows from: clean bands up the stem and across its leaflets, one hue turn per ~12
  generations, each frond at its own place on the wheel, smooth HSV. Full age (G) is kept for
  UND.4's shimmer, which should run out into the leaflets.
- **Harmony:** palette rotation = Nacre's circular EMA of `tonalPhaseFifths` (~0.8 s), gated by
  `tonalConsonance`, holding when atonal/silent. Never a clock.
- **Trails:** `bed` persistent, `max(new, prev · decay^(dt·60))`. The first range (0.80–0.94 per
  1/60 s from arousal) smeared every leaflet into motion blur on so_what; now **0.50–0.82**.
- **The forest (Matt).** *"We need a beautiful background for these ferns - they are just floating
  in space."* He picked a moonlit forest floor from four options, then sent reference photos —
  *"The first image would be close to what I'm envisioning. A fallen tree, covered in moss with a
  bunch of ferns in the foreground, not all of which are moving - only a subset would move to the
  beat."* — and chose **psychedelic movers** in a **dim green daylight** forest. Built as a
  `backdrop` stage: four depths of furrowed redwood-scale trunks with lichen and moss fading into
  green haze, a loam floor, six depth rows of still sword-fern clumps (a different, simply pinnate
  species, drawn analytically), and a fallen log with Worley-plate bark and cushion moss. Each
  moving frond's light pools around its root. **Cached:** the stage is persistent and computes
  each pixel in one frame of 16 (a ¼ s dissolve-in, no hitch), then only carries itself; one
  forest for every track, so a track change clears only the frond atlas (`clear_fronds`), no
  longer every persistent stage.
- **Cost (Release, M2 Pro):** drawn every frame the forest cost **23 ms at 1080p** (over budget);
  cached, the whole frame is **2.57 ms @1080p, 10.3 ms @4K**.
- **Matt's verdict on the forest:** *"This is a good first pass, but the fidelity of the
  background is low overall."* Offered a photographic plate (a CC0 candidate was found); he chose
  **keep it drawn, push detail**, and keep searching for references closer to his photo. The
  honest ceiling was stated: drawn reads as illustration, not photograph.
