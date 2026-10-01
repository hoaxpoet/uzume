# Visual References — Understory

**Family:** `fractal`
**Render pipeline:** `staged` — `fronds` (persistent feedback-IFS atlas) → `bed` → `present`
**Rubric:** lightweight — stylized 2D graphic (the Fractal Tree precedent; exempt from the full detail-cascade + material-count requirements)
**Last curated:** 2026-10-01 by Claude (UND.0). **Matt reviews the set** (plan UND.0 step 2) — not yet reviewed.

Design: [`docs/presets/UNDERSTORY_DESIGN.md`](../../presets/UNDERSTORY_DESIGN.md). Plan: [`UNDERSTORY_PLAN.md`](../../presets/UNDERSTORY_PLAN.md).

**Composition (Matt, 2026-10-01, design §10-3):** a *field* of ferns swaying in the wind, a mix of
open fronds and closed fiddleheads, with dark ground between them. Not a solid blanket of fronds.

## Reference images

Per D-065(c) each row states the mandatory traits, the decorative ones, and what to actively disregard.

| File | Mandatory — learn this | Decorative | **Actively disregard** |
|---|---|---|---|
| `01_macro_source_frond.png` | **The frond itself**, from the source oracle (Flexi, *fractal seafood*, rooted frond-only render on `so_what`; three moments 0.8 s / 1.9 s apart). A curved central stem of beads shrinking toward the tip, alternating leaflets that are themselves small fronds, and the round seed at the base. **Left:** open and leaning. **Middle:** the same frond curled into a crozier by a strong swing. **Right:** uncurling. The curl comes from the mechanism (the per-generation bend accumulates), so open ⇄ curled is one continuum, which is what makes the fiddlehead mix nearly free. | — | The grey-on-black presentation. Colour is UND.3. |
| `02_meso_fiddlehead_coil.jpg` | **The coil target for a closed fiddlehead** (κ in UND.5): a tight logarithmic spiral, more than one full turn, the leaflets packed inside the curl and the stem leaving it tangentially. The coil is the tip of the frond rolled inward, not a separate shape. | The fuzz and scales | Green, daylight, photographic texture. |
| `03_macro_fern_bed_from_below.jpg` | **The composition seen from low:** fronds rooted outside the frame, arching up and across, crossing each other at different depths. Each frond is still readable on its own. The nearest fronds are the largest and the darkest silhouettes against the brighter distance. | The canopy and sky behind | The density of the overlap. Matt chose a **field** (gaps of dark ground), not this near-solid wall. Also the green. |
| `04_palette_uv_fluorescent.jpg` | **The palette register:** fully saturated, self-luminous colours (acid green, hot orange, magenta, electric blue, red) glowing out of near-black, many different hues side by side, each patch its own colour. That is "psychedelic, not a realistic fern". | The rock shapes | The specimen-tray grid layout. |
| `05_anti_realistic_green_fern.jpg` | **NOT this:** a realistic green fern in daylight. Chlorophyll green, matte leaf, natural light. That register belongs to Goldengrove. | — | — |
| `06_anti_barnsley_fern.png` | **NOT this:** the textbook Barnsley fern, one static, symmetric, green fractal on a flat ground. Our frond is a different IFS (Flexi's three maps). It is never alone and never still, and it is never green-on-white. | — | — |

## Stylization contract

- [ ] **The frond is Flexi's frond** (ref 01): same mechanism and constants, judged side by side against the oracle in motion (UND.1).
- [ ] **Colour modulation:** hue runs along each frond's path length, base to tip and out into the leaflets. The palette rotates with harmony (`tonal_phase_fifths`), never on a timer (UND.3).
- [ ] **Audio coverage:** the wind (bass against treble, each over its own few-second average) moves every frond at all times while music plays. Each beat sends a shimmer up one frond, in a fixed order through the bar. Vocal phrases uncoil the fiddleheads.
- [ ] **Readability at silence:** the field is still there, fully drawn, upright and still (springs at rest), never black (D-037). No shimmers. Fiddleheads coiled.
- [ ] **Readability at peak energy:** fronds whip and curl into croziers and snap back, but each one stays readable as a frond. A curl is a frond curling, not a smear.

## Anti-references

- A realistic green fern (ref 05).
- The textbook Barnsley fern (ref 06).
- A colour-cycling wallpaper: hue moving on a timer while the music does something else.
- A beat strobe: a whole frond, or the whole field, flashing on the beat. The shimmer travels; it never pops.
- A single swimming creature. That was the source's concept, not ours.
- A solid blanket where individual fronds can't be followed (Matt's §10-3 field direction).

## Audio routing notes

- `bass` / `treble` (each over its own ~4 s average, Milkdrop's `AudioLevels`) → Flexi's two springs → bend (wind, whip, twitch). One balance, one layer.
- `BeatGrid` (`beat_phase01` / `bar_phase01` wraps, `beats_per_bar`) → one shimmer per beat on one frond (UND.4).
- Vocals stem energy, phrase-smoothed → fiddlehead uncoil (UND.5).
- `tonal_phase_fifths` → palette rotation. `arousal` → afterglow length (UND.3).

## Provenance

Curated by: Claude, UND.0 (2026-10-01). Matt's review pending.

| File | Source | Author | Licence |
|---|---|---|---|
| `01_macro_source_frond.png` | Our render of *flexi - fractal seafood* (butterchurn-presets@2.4.7 converted JSON, sha256 `d0ca386c…d9`), rooted frond-only variant, `tools/milkdrop-render/render-sequence.js` | Flexi (preset); render by Uzume | Render of a Milkdrop preset, used as a reference, the established Milkdrop-uplift practice |
| `02_meso_fiddlehead_coil.jpg` | [Unfurling Spiral Fiddlehead Fern Frond.JPG](https://commons.wikimedia.org/wiki/File:Unfurling_Spiral_Fiddlehead_Fern_Frond.JPG) | Wingchi Poon | CC BY-SA 3.0 |
| `03_macro_fern_bed_from_below.jpg` | [Thicket of ferns.jpg](https://commons.wikimedia.org/wiki/File:Thicket_of_ferns.jpg) | Александр Байдуков | CC BY-SA 4.0 |
| `04_palette_uv_fluorescent.jpg` | [Fluorescent minerals hg.jpg](https://commons.wikimedia.org/wiki/File:Fluorescent_minerals_hg.jpg) | Hannes Grobe / AWI | CC BY-SA 2.5 |
| `05_anti_realistic_green_fern.jpg` | [Ferns on forest floor.JPG](https://commons.wikimedia.org/wiki/File:Ferns_on_forest_floor.JPG) | Haanofonua | CC BY-SA 4.0 |
| `06_anti_barnsley_fern.png` | [Barnsley fern 1024x1024.png](https://commons.wikimedia.org/wiki/File:Barnsley_fern_1024x1024.png) | Farry | CC0 |

All Wikimedia images are downscaled to 1200 px wide (06: 600 px) and recompressed. None are AI-generated.
The source oracle films (12 s × 3 fixtures, full and rooted variants) live outside git at
`/Volumes/Extreme SSD/understory/oracle/` (D-211).
