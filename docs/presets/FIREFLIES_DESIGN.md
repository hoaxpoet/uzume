# Fireflies — Design

**Status:** FF.0 (spike) ✅ · FF.R / FF.R2 (references) ✅ · FF.1 (behaviour port) ✅ merged #273 ·
FF.2 (the world) ✅ 2026-09-25 (look still accepted by Matt: *"accept … looks good overall"*) ·
**FF.3 (the light) next** · FF.4 (M7 + certification). `certified: false`,
`exclude_from_cycling: true` until FF.3.

This document consolidates what is already decided; it adds no decision Matt has not made. (The one
question it first left open, §4.3, Matt answered: "B".) Sources:
the FF.0 spike README (`docs/presets/fireflies_spike/README.md`, the behaviour), D-257 (beat clarity,
setting A), D-258 (the look), and `docs/VISUAL_REFERENCES/fireflies/README.md` (§FF.R2 is the style,
the FF.R photographs are composition only).

---

## 1. The concept and its musical role

**Musical role (the sentence):** *the beat grid pulls a meadow of fireflies into unison, as strongly as
the beat is clear.*

A dusk-to-night meadow under a tree line, full of small fireflies that are dark between flashes. They
blink at random at the top of a track; neighbours nudge neighbours, so flashes relay across the meadow
in sweeps; on a clear beat the whole meadow comes to flash as one on the beat within about 15 s. On an
irregular beat, or one whose clarity is unknown, they stay free (D-257).

## 2. Temporal contract

| Moment | What the listener sees |
|---|---|
| Track start | Incoherent random blinks, by design (the swarm restarts on every track change). |
| First seconds (clear beat) | Clusters, then sweeps relaying across the meadow; the swarm coheres in ~3 s. |
| ~6–15 s (clear beat) | The unison finds the beat and stays on it: hundreds of points flash together, once per 1, 2 or 4 beats (the cycle nearest 1 s). |
| Irregular / unknown beat | Free for the whole track: neighbour relay only, scattered clusters, no unison on a beat. |
| Near-silence (`near_silent01`) | All but ~5 % stragglers fade out over ~1.5 s; the world stays lit and its ambient motion continues (a meadow at night does not freeze; see §4.3). |
| Any unison | Many tiny points, never a frame-wide lift: max Δ frame-mean luma < 0.05 (D-157). |

The behaviour is built and gated (FF.1): `FirefliesSwarm` reproduces the spike's 20-seed coherence and
on-beat distributions on the four parity captures. **It is not a tuning surface in FF.2.**

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

## 5. Audio routing (one primitive per layer, FA #67)

| Visual layer | Primitive | Timescale | Status |
|---|---|---|---|
| Swarm entrainment (the music nudge) | `beatPhase01` wraps (grid ticks) × K, K = clamp(2·`stems.beatClarity01` − 1, 0, 1); tempo from the installed grid's BPM (`SpectralHistoryBuffer` slot 2418) | beat | Built (FF.1). Declared route `swarm_beat_nudge`. |
| Swarm visibility | `near_silent01` | ~1.5 s | Built (FF.1). Gated in `FirefliesSwarmTests`. |
| World breath (wind in grass and trees, mist drift) | `bassAttRel` → 4 s EMA → 0.5 + 0.5·tanh(4x) (`FirefliesWorld.advance`); sets wind speed and sway (∝ breath²) and mist speed, all integrated so nothing lurches — never beat-rate | several seconds | Built (FF.2); route `world_breath`, green in `RouteCoverageTests`. Chosen over `midAttRel`/`trebAttRel`: the only one of the three whose slow average moves on all four parity captures. Visible, measured with the camera held still (`FirefliesRenderTests.breathIsVisible`): tree-crown motion 3.4× (DYC) / 1.7× (Pyramid) in full vs quiet passages. Matt, at the FF.2 still: *"might want to consider having the trees move based on musical input"* — the trees sway on this route. |

The beat belongs to the fireflies alone; the world listens only on a much slower timescale, so the two
never fight — and a free track (irregular or unknown beat) still has a visible connection to the music.

## 6. Constraints
- **One paradigm (D-029):** a world pass plus the `particles` swarm, as today; FF.2 does not bolt a
  second motion system onto it.
- **Flash safety (D-157):** re-measure through the real draw path whenever the look changes.
- **Performance:** 60 fps at 1080p in Release. The Debug-built `PresetFrameBudgetTests` also times any
  CPU-side model at `-Onone` (FF.1 lesson), so CPU work must be cheap in both configurations.
- **Silence:** never black (D-037); the world coasts (§4.3).
- **Rotation:** stays `certified: false` + `exclude_from_cycling: true` until FF.3.

## 7. Increments
| ID | Delivers | Gate |
|---|---|---|
| FF.2 | The 3D world in the screenprint style; the swarm placed in depth through the shared camera; ambient motion | One still beside `07` accepted by Matt **first**; then films, motion gate, flash, frame budget, FF.1 parity still green |
| FF.3 | The light: near-white core + coloured bloom, fireflies lighting the grass and mist around them, occlusion by grass/trees | Side-by-side against `09`/`07`; flash re-measured; 60 fps 1080p Release |
| FF.4 | M7 on the beta playlist; certification; remove `exclude_from_cycling` | Matt's M7 |

If FF.2/FF.3 do not reach the bar by the October 11 cutoff, Fireflies ships after the beta, never as a
sketch.

## 8. Known risks
- **Line-work quality:** intricate branching and grass edges are reachable; a hand-cut screenprint
  quality is not promised (D-258).
- **Rubric fit:** the sidecar's `rubric_profile: full` expects PBR-cookbook materials and ≥ 4 noise
  octaves per surface; a screenprint look may meet some of that differently. Report the rubric honestly;
  never change the profile to pass it.
- **Reference tooling:** `Scripts/compare_render.sh` reads only the repo folder, so it cannot see the
  local-only `07`; FF.2 solves that locally, never by committing the prints.
