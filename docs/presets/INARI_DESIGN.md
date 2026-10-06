# Inari — Design

**Status: ⛔ STOPPED 2026-10-06 (Matt: *"yes, wrap it up"*). This branch is not merged and the preset
does not ship.** INARI.1 was built into the app 2026-10-05; Matt's live look: *"not an impressive scene …
you can tell that it's a static background where only the illumination changes"*, and *"what we built
was a total compromise because you were unable to match the visual style of the original."* See §6.

## 1. The scene and what changes

A night shrine: a stone stair through ivy and mossy walls to a lantern-lit hall under a red torii,
two stone foxes in red capes on the walls, a pagoda on the hill, a thin moon. **The picture never
moves; only its light changes** (Matt, 2026-10-05: *"a 2D, illustrated scene where only the
illumination from the eyes of the foxes, the lanterns, and the moon changes"*). The look is the
artist's: Matt supplied the drawing twice (made in ChatGPT), once lit only by the moon
(`inari_unlit.webp`) and once with every light burning (`inari_lit.webp`).

## 2. Musical role

**The shrine's lights are the band: the lanterns are the bass, the shrine's lamps are the drums, and
the foxes' eyes are the singer.** (Matt's routing, 2026-10-05; he kept it over a bass↔drums swap.)

| Light | Stem / primitive | Behaviour |
|---|---|---|
| Lanterns (all but the shrine's) | `bassEnergyRel` | swell and fall with the bass (60 ms / 450 ms); a lantern higher up the stair reads the bass up to 0.35 s later, so a swell climbs toward the hall |
| The shrine — hall lamp clusters, pagoda windows | `drumsEnergyDev` | kick on each hit and fall back (15 ms / 220 ms) |
| Fox eyes | `vocalsEnergy` presence + `vocalsEnergyDev` | dark stone when no one sings; kindle with the voice, linger (120 ms / 900 ms) |
| Moon | — | as drawn (no route yet) |

Why bass → lanterns, not drums: the lanterns are most of the frame's light; following the bass's
swells they read as locked to the music, where per-hit drums over the whole frame would flicker
(Audio Data Hierarchy; D-157's bounded per-beat footprint). Drums sit on the small, distant shrine.
**All mappings are provisional** — INARI.2 tunes them; `vocalsEnergy` is an absolute AGC level
(FA #31 hazard) and its replacement is part of that tuning.

## 3. How the light is drawn

`tools/inari/prep.swift` derives `inari_lights.png` + `inari_lights.json` from the pair: the light
each pixel receives (lit − unlit luminance, blurred), the emitters (hot cores: lit paper, eyes, the
pagoda's windows; nearby cores merged into one lamp), each pixel's **owner** by geodesic growth from
the emitters through lit pixels (light the artist blocked stays blocked), and its **rank** down that
light's falloff. 26 sources at INARI.1: 3 eye sources, the pagoda's two window bands, the hall's two
lamp clusters, 19 lanterns. Sources are classified **by position** (`InariState.classify`) because
ids change whenever the drawings are regenerated.

The shader brightens the moonlit drawing per owner: luminance × g^L, g = the drawn light ratio
(lit / unlit luminance off mip 2.8 — blurred, because the two drawings' fine marks differ everywhere
and must never show), with the hue moving to the lit drawing's; hot cores crossfade between the
drawings. Level 0 is the moonlit drawing exactly; level 1 lands within 3 % of the lit drawing's
mean brightness over the owned area (`InariTests`).

**Rejected looks** (Matt, 2026-10-05): additive glow over the reference (*"it looks like you just
added illumination effects"*); a five-ink plate print where light spreads through a line screen
(*"admirable, but it does not look good"*); hashing in the eye (*"I do not want the hashing pattern
in the eye cavity"*) — the eyes only ever crossfade. Before those, a ray-marched 3D rebuild of the
scene was abandoned: it could not reach the drawing's detail.

## 4. Constraints

- **Silence:** the moonlit drawing — never black (D-037). Unbound harnesses get a still night-teal field.
- **Framing:** the 3:2 drawing fills the screen; a wide screen crops top and bottom, weighted to the
  bottom so the foxes' ears and the moon stay in.
- **Flash safety:** to measure at INARI.2 — the drums route is the per-hit one, and it is confined to
  the hall and pagoda.
- **Resolution:** the drawings are 1536 × 1024; on a 4K display they are upscaled ~2.5×.
- **Assets:** 1.3 MB (two WebP drawings + the light map). Regenerate the map after any redraw.

## 5. Increments

| ID | Delivers | Gate |
|---|---|---|
| INARI.1 | The preset in the app: drawings + light map, per-light levels from stems, `InariTests` | ✅ engine suite; Matt's first live look |
| INARI.2 | Music-sync tuning on real sessions (local + streaming); flash measurement | Matt's M7 |
| INARI.3 | Certification | NEW_PRESET_CHECKLIST §4 |

## 6. Why it stopped — the four attempts

Matt asked for a living scene in the style of his reference illustration. Every route hit the same
gap: the scene needs hand-made art with motion built in, and this setup can only write code that
draws.

1. **3D rebuild (ray-marched SDF, baked + relit).** Layout matched by landmark solve; the foxes reached
   a carved-stone read, but the illustration's density (fur, lichen, ivy) is hand-placed marks that
   procedural rules cannot produce — they came out as wood grain, cracked stone, camouflage.
2. **The drawing relit (INARI.1, this branch).** Matt's two drawings (moonlit / all lights), each light
   brightening its own area. Faithful to the art, but a static picture with lights.
3. **Layers with parallax** (Matt generated sky / hills / shrine / foreground with a #00FF00 key). The
   depth read, but the camera move had no reason (*"the camera movement is nonsensical to me"*).
4. **Layers, fixed camera, animated by warping** (cloud creep, leaf sway, mist). Bending a drawing
   smears its strokes (*"you can see smearing around the moon"*). Real motion needs every element
   (cloud bank, branch) as its own separate piece of art.

**Stem bleed (engine-wide, found here).** One light group ← one stem exposes the separator's
leakage directly — the eyes answer a guitar, the shrine a bass note. Scenes that blend several
primitives average it away; a scene that maps one element to one stem cannot.
