# Fireflies — Design

**Status:** FF.0 (spike) ✅ · FF.R / FF.R2 (references) ✅ · FF.1 (behaviour port) ✅ merged #273 ·
FF.2 (the world) ✅ 2026-09-25 (look still accepted by Matt: *"accept … looks good overall"*) ·
FF.3 (the light) ✅ 2026-09-26, branch `ff-3` (look still accepted by Matt: *"This light clears the bar."*) ·
FF.4 (M7) closed 2026-09-28: **M7 not passed** (Matt: *"It's everyone at once — go with option A"*; §1a) ·
**FF.5 (orchestration + smooth glow, then M7 + certification) next** — prompt `prompts/FF.5-prompt.md`.
Reachable by the arrow keys (`exclude_from_cycling` removed at FF.4); `certified: false`, so no session
plans it yet.

This document consolidates what is already decided; it adds no decision Matt has not made. (The one
question it first left open, §4.3, Matt answered: "B".) Sources:
the FF.0 spike README (`docs/presets/fireflies_spike/README.md`, the behaviour), D-257 (beat clarity,
setting A), D-258 (the look), and `docs/VISUAL_REFERENCES/fireflies/README.md` (§FF.R2 is the style,
the FF.R photographs are composition only).

---

## 1. The concept and its musical role

**Musical role (the sentence, since FF.4's M7):** *the beat grid organises a meadow of fireflies into
patches that take turns flashing on the beat, as strongly as the beat is clear.*

(Until FF.4 it read *"… pulls a meadow of fireflies into unison …"*; §1a records why it changed.)

A dusk-to-night meadow under a tree line, full of small fireflies that are dark between flashes. They
blink at random at the top of a track; neighbours nudge neighbours, so flashes relay in sweeps; on a
clear beat the meadow organises within about 15 s into 2–4 patches, each flashing together on its own
beat, so a flash walks across the meadow beat by beat — every beat lights a patch, and no beat lights
the whole meadow. On an irregular beat, or one whose clarity is unknown, they stay free (D-257).

### 1a. Decided at FF.4's M7 (Matt, 2026-09-28)

- **Orchestration, not unison.** Tester feedback, via Matt: *"all fireflies blinking in unison is
  overwhelming; they would prefer some level of orchestration across the firefly swarm, so it looks
  like a coordinated rhythm."* Asked whether the brightness or everyone-at-once was the problem: *"It's
  everyone at once — go with option A."* Option A as put to him: *the meadow settles into 2 to 4
  patches, each flashing together on its own beat, so a flash walks across the meadow beat by beat.
  Every beat lights something, and each firefly still blinks about once a second. It keeps what makes
  it fireflies: it starts random, organises itself over about 15 s, and stays free when the beat isn't
  clear.* Rejected: a fresh patch per beat chosen by the grid (Ferrofluid Ocean's D-157 regions, taken
  literally), because the grid would decide who flashes and the self-organising would be gone; and a
  whole-meadow flash on beat 1, which needs a reliable bar start (BUG-065 / D-206, parked).
- **The glow is smooth.** Matt: *"fireflies look pixelated."* Measured: FF.3 printed each halo and
  starburst as one-screen-pixel stipple against an interleaved-gradient grain, a regular per-pixel
  dither that reads as digital pixels rather than ink (6× crops of the 1080p still,
  `~/Documents/uzume_spikes/fireflies/ff4/pixel_crop_*_x6.png`). His pick, *"A"*: the halo and starburst
  become a soft continuous yellow-green light around the white core; **the world keeps its print
  texture**.

- **The meadow thins with the music** (Matt, 2026-09-28, the FF.5 look check: *"A"*). Option A as
  put to him: *quiet stretches show a sparse meadow, a few patches of a few lights, and it fills as
  the song builds. DYC opens as the design first promised, with a few lights waiting, and the drop
  fills the meadow.* Rejected: B, the full swarm whenever the beat is clear.

## 2. Temporal contract

| Moment | What the listener sees |
|---|---|
| Track start | Incoherent random blinks, by design (the swarm restarts on every track change). |
| First seconds (clear beat) | Clusters, then sweeps relaying across the meadow; the swarm coheres in ~3 s. |
| ~6–15 s (clear beat) | The meadow organises into 2–4 patches that take turns: each beat, one patch flashes together and the flash walks across the meadow beat by beat. Every beat lights a patch; no beat lights them all. Each firefly still blinks every 1–2 s. (Until FF.5: the whole meadow in unison once per 1, 2 or 4 beats — rejected at FF.4's M7, §1a.) |
| Quiet but not silent (FF.5) | The meadow thins with the song's measured energy: about a tenth of the fireflies at energy ≤ 2 (a few lights in every patch), filling to all of them by energy 8. DYC's opening is sparse and its drop at 3:08 fills the meadow within a few seconds. Hidden fireflies keep their rhythm, so the patches carry on unseen. |
| Irregular / unknown beat | Free for the whole track: neighbour relay only, scattered clusters, no patch on a beat. |
| Near-silence (`near_silent01`) | All but ~5 % stragglers fade out over ~1.5 s; the world stays lit and its ambient motion continues (a meadow at night does not freeze; see §4.3). ⚠ **Near-silence means silence, not quiet music:** in FF.4's M7 capture (`2026-09-28T14-43-46Z`) `near_silent01` never fired over DYC's first 106 s, its quiet opening, so the full swarm flashed there — quiet music is the row above (FF.5). |
| Any patch flash | Many tiny points, never a frame-wide lift: max Δ frame-mean luma < 0.05 (D-157). |

The behaviour is built and gated (FF.1): `FirefliesSwarm` reproduces the spike's 20-seed coherence and
on-beat distributions on the four parity captures. **It is not a tuning surface in FF.2.**
FF.5 changes it on clear beats (patches, §1a); a free swarm (irregular or unknown beat) keeps the
FF.1 behaviour and its parity gate.

## 3. The look (D-258)

A **stylized screenprint rendered from a real 3D scene** — Matt: *"not looking for photographic… more
stylized but still 3D. it's not enough to put fireflies over a static painting"*; anchored on Daniel
Danger's screenprints. **Blue palette, hero FF.R2 `07`.** The nine prints are local-only
(`~/Documents/uzume_spikes/fireflies/references_danger/`), never committed, never reproduced or traced.

The style, as rules (verbatim from the references README):
- **Ink, not paint:** one blue ink family plus near-black, a screenprint's few inks.
- **Line, not fill:** texture comes from the density of fine hatched lines; almost nothing is flat.
- **Value is depth:** the far distance and the sky are lightest, the foreground silhouette darkest.
- **Lights are the event:** each light is the brightest thing in the frame — near-white core, coloured
  bloom, light only on what is right around it. **The fireflies are the scene's only warm colour.**

Anti-references: photographic anything; fireflies over a static painting (the FF.0/FF.1 placeholder);
too bright to see the fireflies; too dark to see nature.

## 4. The world in 3D (FF.2)

### 4.1 Composition (from the FF.R photographs, composition role only)
Meadow in the lower part of the frame, textured to the horizon; a continuous, ragged tree line on the
horizon in 2–3 depth layers, each lighter toward the sky (`03` for the branching, `05` for the layers);
the sky brightest just above the trees; mist pooling in the low ground in the distance; foreground grass
and seed heads in silhouette at the bottom edge.

### 4.2 What "real 3D" must deliver (product requirements, not a technique)
- **Parallax:** a slow camera drift makes near and far visibly separate. Never so much that the
  composition in §4.1 breaks.
- **Fireflies placed in depth:** near ones larger and brighter, far ones smaller and dimmer, drifting
  past each other; they live *in* the meadow and among the trees, not on a layer in front of it.
- **One camera for everything:** the world and the fireflies must project through the same camera, or
  the parallax contradicts itself.
- Occlusion of fireflies by grass and trees, and fireflies lighting their surroundings, are FF.3.

The technique (ray-marched terrain, layered 3D cards, mesh-shader branches, or a combination) is an
engineering choice for FF.2, made after desk research and grounded per the preset-session checklist
(working code reference > paper > nothing — level 3 is surfaced, not built). The first artifact of
FF.2 is one still beside `07`, and Matt accepts or rejects the direction there.

### 4.3 The world is alive
Ambient motion independent of the swarm: wind moving through the grass, mist drifting, the camera
drift. At near-silence it **coasts** (continues, calmer), per the per-preset silence doctrine; it never
freezes and never goes black (D-037).

**Decided (Matt, 2026-09-25: "B"; D-258 addendum):** the world motion also **breathes with the
music's slow energy** — the wind stirs the grass and the mist moves more in louder, fuller passages,
swelling over several seconds, never pulsing on the beat (§5 row 3).

### 4.4 The light (FF.3) — product requirements
Restated from §3, §4.2 and D-157; nothing here is newly decided.
- **Each firefly is a light:** a near-white core and a coloured bloom, the brightest thing in the frame
  (`09`), and the scene's only warm colour. **The bloom is yellow-green**, the swarm's own
  colour (Matt, 2026-09-26: "A").
- **Light only on what is right around it** (`07`, `04`): grass strokes, mist and nearby branches
  brighten within a short radius of a lit firefly; the rest of the print is untouched.
- **Occlusion:** a firefly behind a tree trunk, a branch or a foreground grass stalk is hidden by it.
- **Depth of field:** the nearest fireflies read as soft, out-of-focus discs.
- **Timing:** the light rises and falls with the flash (40 ms rise, 0.11 s decay) — it never lingers.
- **Never a frame-wide lift (D-157):** a unison flash is hundreds of small lights; max Δ frame-mean luma
  stays < 0.05 at 1080p through the real draw path. If a bloom breaks that, the bloom shrinks.
- The world's composition, inks, camera and breath (FF.2) and the swarm's behaviour (FF.1) do not change.

**Superseded at FF.4's M7 (§1a): the halo and starburst become a smooth glow in FF.5.** The rest of
this paragraph stays true.

**As built (FF.3).** Each lit firefly is a flat near-white printed dot, a yellow-green halo and a
four-point starburst printed as grain coverage, and a light pool that multiplies the print around it
(pale strokes and mist brighten toward green; the dark between strokes stays dark). The nearest
fireflies (≲ 6 m) are soft discs of the thin-lens circle of confusion. Occlusion is painter's order in
0.5 m depth bands. Known limit: a light cannot brighten the **near-black** ink of the nearest trunks
(multiplying near-black stays near-black), so those trunks stay silhouettes beside a light, as in
`07`; the mid and far trees, the grass and the mist do catch it. The pools' screen reach is capped so
a unison cannot tile the foreground — the flash budget (D-157) is what limits how far the light
reaches, and FF.3 spends about three times FF.2's per-frame step (see ENGINEERING_PLAN FF.3).

## 5. Audio routing (one primitive per layer, FA #67)

| Visual layer | Primitive | Timescale | Status |
|---|---|---|---|
| Swarm entrainment (the music nudge) | `beatPhase01` wraps (grid ticks) × K, K = clamp(2·`stems.beatClarity01` − 1, 0, 1); tempo from the installed grid's BPM (`SpectralHistoryBuffer` slot 2418) | beat | Built (FF.1). Declared route `swarm_beat_nudge`. FF.5: on a clear beat, tick n pulls strip n mod P only, so the strips take turns (§1a; the patches note below). |
| Swarm visibility | `near_silent01` | ~1.5 s | Built (FF.1). Gated in `FirefliesSwarmTests`. |
| Swarm density (how many fireflies show) | `stems.energyLevel`: the track's measured 1–10 section energy (NRG curve, D-259) over the 10 s centred on the playhead; the preview's typical level on streaming; 0 unknown → all shown | section (10 s windows; each firefly fades on the 1.5 s visibility fade) | Built (FF.5, Matt's "A"). 10 % shown at ≤ 2, all at ≥ 8, linear between; a fixed per-firefly rank chooses who hides. Visibility only: clocks and relay unchanged (`quietMusicThinsTheMeadow`). A different primitive from the breath and a slower timescale (FA #67). Not a declared route: `energyLevel` is not in `AudioRoutePrimitives`' recordable map (as `beatClarity01`). |
| World breath (wind in grass and trees, mist drift) | `bassAttRel` → 4 s EMA → 0.5 + 0.5·tanh(4x) (`FirefliesWorld.advance`); sets wind speed and sway (∝ breath²) and mist speed, all integrated so nothing lurches — never beat-rate | several seconds | Built (FF.2); route `world_breath`, green in `RouteCoverageTests`. Chosen over `midAttRel`/`trebAttRel`: the only one of the three whose slow average moves on all four parity captures. Visible, measured with the camera held still (`FirefliesRenderTests.breathIsVisible`): tree-crown motion 3.4× (DYC) / 1.7× (Pyramid) in full vs quiet passages. Matt, at the FF.2 still: *"might want to consider having the trees move based on musical input"* — the trees sway on this route. |

The beat belongs to the fireflies alone; the world listens only on a much slower timescale, so the two
never fight — and a free track (irregular or unknown beat) still has a visible connection to the music.

**The patches (FF.5, as built in `FirefliesSwarm`).**
- **How they form.** While K > 0 and a grid is installed, the meadow is P upright strips across the
  frame, left to right, their edges waving with height (±5 % of the width) so a lit strip reads as a
  patch, not a ruled column. A firefly belongs to the strip it is drifting through. Grid tick n pulls
  only strip n mod P toward its flash (the same K·0.30 phase pull and K·0.05 period retune as FF.1),
  so the flash walks left to right, one strip per beat, and every beat lights a strip. The grid never
  chooses who flashes (option B stays rejected): every firefly starts random, and each strip
  organises itself through neighbour relay and its own tick.
- **The boundary rule.** A flash nudges only neighbours in its own strip; relay does not cross a strip
  edge. **Grounding (level 1):** the P strips are then P disjoint copies of the FF.0/FF.1 model, each on
  the fireflies in its strip (density inside a strip is unchanged) and each driven on its own grid tick.
  The one new event is a firefly drifting across an edge: it arrives out of phase and is pulled in by
  its new neighbours and its strip's tick, the model's own cold-start mechanism at the scale of one
  firefly. The whole-meadow attractor (§8) exists only through relay across an edge, so the rule
  removes it rather than resisting it. Measured once without the rule (not built): the strips still
  separated over 30 s, but the lock took 12.1–16.0 s instead of 9.4–13.3 s and the turn share fell.
- **The cycle rule.** A firefly's cycle is P beats, with P the most strips (2–4) whose cycle stays
  ≤ 2 s: 98 BPM (DYC) → 3 strips, 1.84 s; 118 → 3, 1.52 s; 126–136 → 4, 1.8–1.9 s; 270 → 4, 0.89 s.
  Below 60 BPM, 2 strips run longer than 2 s (no clear-beat song in the beta set is that slow).
- **Unclear beat (K = 0).** Nothing changes: one meadow, relay everywhere, the 1/2/4-beat cycle nearest
  1 s, the same random draws. Unknown clarity still equals irregular, number for number.

## 6. Constraints
- **One paradigm (D-029):** a world pass plus the `particles` swarm, as today; FF.2 does not bolt a
  second motion system onto it.
- **Flash safety (D-157):** re-measure through the real draw path whenever the look changes.
- **Performance:** 60 fps at 1080p in Release. The Debug-built `PresetFrameBudgetTests` also times any
  CPU-side model at `-Onone` (FF.1 lesson), so CPU work must be cheap in both configurations.
- **Silence:** never black (D-037); the world coasts (§4.3).
- **Rotation:** reachable by the arrow keys since FF.4 Task 2 (`exclude_from_cycling` removed so Matt's
  build can show it for the M7); `certified: false` until the M7 and the streaming pass, so the planner,
  the reactive picker and Shift+→ skip it unless "Show uncertified scenes" is on.

## 7. Increments
| ID | Delivers | Gate |
|---|---|---|
| FF.2 | The 3D world in the screenprint style; the swarm placed in depth through the shared camera; ambient motion | One still beside `07` accepted by Matt **first**; then films, motion gate, flash, frame budget, FF.1 parity still green |
| FF.3 | The light: near-white core + coloured bloom, fireflies lighting the grass and mist around them, occlusion by grass/trees | Side-by-side against `09`/`07`; flash re-measured; 60 fps 1080p Release |
| FF.4 | M7 on the beta playlist; certification; remove `exclude_from_cycling` | Matt's M7 — **not passed 2026-09-28** (§1a). Delivered the pre-M7 packet, the WCAG flash test and reachability; not certified |
| FF.5 | Patches take turns on the beat (§1, §2); the smooth glow (§1a); then M7 + certification (FF.4's Tasks 3–7) | Matt's look check on a film, then his M7 and one streaming pass |

If FF.2/FF.3 do not reach the bar by the October 11 cutoff, Fireflies ships after the beta, never as a
sketch.

## 8. Known risks
- **Line-work quality:** intricate branching and grass edges are reachable; a hand-cut screenprint
  quality is not promised (D-258).
- **Rubric fit:** the sidecar's `rubric_profile: full` expects PBR-cookbook materials and ≥ 4 noise
  octaves per surface; a screenprint look may meet some of that differently. Report the rubric honestly;
  never change the profile to pass it.
- **Patches collapsing back into unison:** neighbour relay that crosses a patch boundary pulls
  neighbouring patches together, and the whole meadow is the model's natural attractor. Each patch has
  to self-organise on its own beat without the relay undoing the separation. Grounding: a patch is the
  existing model (the FF.0 spike, gated at FF.1) driven on its own grid tick, so the combination to
  prove is only what happens at the boundaries.
- **Reference tooling:** `Scripts/compare_render.sh` reads only the repo folder, so it cannot see the
  local-only `07`; FF.2 solves that locally, never by committing the prints.
