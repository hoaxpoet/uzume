# Fireflies — Visual References

**Family:** `particles` &nbsp;·&nbsp; **Passes:** `direct` world + `particles` swarm (planned, FF.1–FF.3) &nbsp;·&nbsp; **Rubric:** full
**Last curated:** 2026-09-24 (FF.R), Matt's pick: *"keep the 9"*.
**Curation role:** the fidelity target for FF.2 (the world) and FF.3 (the light). No look work starts
before this set (FF.0 README §7.3).

---

## The concept these images serve

**Musical role.** *The beat grid pulls a meadow of fireflies into unison, as strongly as the beat is
clear.* They blink at random at the top of a track, relay flashes neighbour to neighbour, and lock
onto the beat within about 15 s on a clear beat. They stay free on an irregular or unknown one
(`stems.beat_clarity01`, D-257, where unknown maps to free).

**Setting: A, the dusk meadow with a tree line** (Matt, 2026-09-24). **The bar** (FF.0 §7.2): a
matte-painting-quality dusk, not photoreal grass.

**Why these images, not the spike.** FF.0 passed on condition. Matt: *"the scene looked cheap and
quickly produced, like a sketch vs. a detailed rendering."* Every row below names a specific way the
spike fell short of the photograph.

---

## Reference images

Per D-065(c) each annotation states three things: the **mandatory** traits, the **decorative** ones,
and the traits that must be **actively disregarded**.

| File | Slot | Mandatory — learn this | Decorative | **Actively disregard** |
|---|---|---|---|---|
| `01_macro_afterglow_meadow_treeline.jpg` | **HERO** | The composition: meadow in the lower third, a continuous dark tree line on the horizon, and a lit afterglow sky above it. The tree line is **ragged and slightly irregular in height**, not a row of bumps. The sky is **brightest just above the trees** and cools upward. The meadow is textured to the horizon. | The cloud field | Daylight exposure. Our scene sits later in dusk: darker ground, and the sky carries the light. |
| `02_macro_fireflies_over_meadow.jpg` | macro | How fireflies read **over grass at night**: small yellow-green points and short dotted strokes, **dense near the ground**, thinning upward. Grass stays visible as texture, lit only faintly. | The lupines | The long-exposure dotted **lines**: we draw each flash at one instant, not a trail. |
| `03_macro_synchronous_display.jpg` | macro | Density and colour of a synchronous display: **hundreds of points at once**, a saturated yellow-green, with near fireflies larger and brighter than far ones. Points sit **in front of and among** foliage, never floating on a flat backdrop. | The forest trunks | The streaks, which are exposure length again |
| `04_meso_lantern_glow.jpg` | meso | **One flash up close:** a bright green core with a soft falloff, a faint halo, and the dark around it untouched. This is the per-point profile, a core plus a halo, as in Witchlight WL.2-g. | — | The leaf |
| `05_atmosphere_evening_mist.jpg` | atmosphere | **Mist pooling in the low ground in the distance**, as a band that is thicker far away and absent in the foreground, with the horizon softened behind it | The warm pink sky | The flat moor. Our meadow keeps the tree line. |
| `06_atmosphere_ridges_aerial_perspective.jpg` | atmosphere | **Aerial perspective:** successive ridges, each lighter and bluer than the last. The tree line should be 2–3 layers doing exactly this, not one flat silhouette. | The sunset | The snow and the mountain scale |
| `07_atmosphere_canopy_edge_silhouette.jpg` | atmosphere | **Tree silhouettes** with ragged, leafy, fractal edges, gaps with sky showing through, and individual crowns of different shapes and sizes | The trees' spacing | **The dramatic cloud sky:** our sky is a calm gradient (`01`) |
| `08_micro_grass_seedheads_silhouette.jpg` | micro | **Foreground grass:** thin blades and branching seed heads in silhouette against a lighter sky. These go at the bottom edge, in front of the mist. | The bush at the right | The daylight blue sky |
| `09_anti_composite_light_pollution.jpg` | **anti** | NOT this: a stacked composite. Flashlight streaks, artificial light, busy colour, and trails everywhere. | — | — |

**Hero:** `01`. Put the render next to it first, as gate zero ([`SHADER_CRAFT.md` §2.3]).

**Known gaps in the set:**
- **Out-of-focus firefly blur discs:** no free-licensed photograph exists. Use the motion reference
  in the FF.0 README §1 (Radim Schreiber's footage) for near-firefly softness.
- **A first-stars sky:** the candidate (a moon-dominated mountain sky) was dropped. If the optional
  deepening-dusk arc is ever chosen, it needs its own reference.

---

## Mandatory traits (per SHADER_CRAFT.md §12.1)

- [ ] **Detail cascade:**
  - **Macro:** the horizon composition (`01`).
  - **Meso:** tree-crown and ridge layering (`06`, `07`) and the mist band (`05`).
  - **Micro:** grass strands and seed heads (`08`) and the canopy edge.
  - **Specular / emissive:** the firefly core plus its halo (`04`).
- [ ] **Hero noise:** fbm with ≥ 4 octaves on the canopy edge and the grass. Domain-warped fbm on the mist.
- [ ] **Materials (≥ 3):** foliage silhouette, grass, mist (participating medium, Nimbus precedent), sky gradient, firefly emissive
- [ ] **Audio reactivity:** beat-grid nudge × `stems.beat_clarity01` (unknown → 0). Mutual relay is internal. `near_silent01` fades the swarm to stragglers.
- [ ] **Silence fallback:** the dusk world stays lit, with a few stragglers. Never black (D-037).
- [ ] **Performance ceiling:** 60 fps at 1080p in Release, measured at FF.3
- [ ] **Hero reference image:** `01_macro_afterglow_meadow_treeline.jpg`

## Expected traits (per §12.2)

- [ ] Volumetric fog / aerial perspective — **yes** (`05`, `06`): this is what separates it from the spike
- [ ] Detail normals — n/a (a 2.5-D silhouette world)
- [ ] Triplanar texturing — n/a
- [ ] SSS / fiber BRDF — n/a

## Strongly preferred traits (per §12.3)

- [ ] Volumetric light: each flash scatters into the mist (FF.3)
- [ ] Hero emissive highlight in ≥ 60 % of frames: the fireflies

## Anti-references (failure modes specific to this preset)

- **The FF.0 sketch itself:** a one-tone semicircle tree line, a three-stop CSS-style sky, a flat
  streaked meadow, identical Gaussian dots. FF.0 README §7.1 lists each.
- **A frame that flashes:** the unison must be many tiny points, never a frame-wide lift (D-157).
- **Long-exposure trails**, as in `02`, `03` and `09`. Photographs integrate over seconds; the scene
  draws one instant.

## Audio routing notes

- The per-beat nudge couples on the cached `BeatGrid`, scaled by `stems.beat_clarity01`, with unknown
  mapped to 0 (Matt, D-257). The relay between neighbours runs whatever the audio.
- `near_silent01` dims the swarm to about 5 % stragglers over ~1.5 s. The world stays lit.

---

## Provenance

Sourced by: **Claude, on Matt's instruction** (2026-09-24: *"go, start the references"*; downloads
approved; set picked by Matt: *"keep the 9"*). This follows the Membrane precedent. Every image is
**real photography** under a free licence, with no AI generation, so the D-065 `_AIGEN` carve-out
does not apply. Each is Wikimedia Commons' 1280-px-wide rendition (≤ 500 KB); originals not retained.

| File | Source (Wikimedia Commons) | Author | Licence |
|---|---|---|---|
| `01_macro_afterglow_meadow_treeline.jpg` | *Ehrenbach, afterglow over fields.jpg* | Gerda Arendt | CC0 |
| `02_macro_fireflies_over_meadow.jpg` | *Lupines and Fireflies No. 4 (14505155544).jpg* | Mike Lewinski | CC BY 2.0 |
| `03_macro_synchronous_display.jpg` | *Photinus carolinus Great Smoky Mountains.jpg* | Niemand für Polyphemus | CC BY 2.0 |
| `04_meso_lantern_glow.jpg` | *Firefly glowing on a leaf.jpg* | Kyu3a | CC BY-SA 4.0 |
| `05_atmosphere_evening_mist.jpg` | *Evening mist rolling in - geograph.org.uk - 7039032.jpg* | Neil Owen | CC BY-SA 2.0 |
| `06_atmosphere_ridges_aerial_perspective.jpg` | *Clifftops4-7-07.jpg* | Aviator31 | Public domain |
| `07_atmosphere_canopy_edge_silhouette.jpg` | *Afterglow, Ehrenbach, tree silhouttes.jpg* | Gerda Arendt | CC0 |
| `08_micro_grass_seedheads_silhouette.jpg` | *Grass silhouette.JPG* | Justin417 | CC BY-SA 3.0 |
| `09_anti_composite_light_pollution.jpg` | *The overlay images of 5 firefly place photos as light art photography, that firefly place from Hengshan, Hsinchu County.jpg* | Junyu-K | CC BY-SA 4.0 |

**These files are gitignored repo-wide** (`docs/VISUAL_REFERENCES/**/*.jpg`) and are committed
with `git add -f`. Do not "clean up" an untracked-file warning by deleting them.
