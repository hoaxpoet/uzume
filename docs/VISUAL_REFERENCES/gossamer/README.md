# Visual References — Gossamer

**Family:** instrument (sparkle family in the sidecar)
**Render pipeline:** direct_fragment + mv_warp
**Rubric:** full (gated by V.6 certification)
**Last curated:** 2026-09-09 by Claude (PR.18), sources below for Matt's review

Bioluminescent hero-web acting as a sonic resonator. A single irregular
orb-weaver web (17 explicit spoke angles per D-042, off-center hub at
UV (0.465, 0.32), Archimedean capture spiral, catenary scallop between spoke
anchors) drawn against a near-black scene. Vocal-pitch-keyed color waves
propagate outward from the hub, physically displacing silk strands as they
pass; `mv_warp` accumulates decaying echoes (decay 0.955).

---

## ⚠ Recuration note — this set was rebuilt from scratch

**The original set's images never existed in the repository.**
raster images under `docs/VISUAL_REFERENCES/` have been gitignored since `33cebe25`, and the
curation step that would have force-added them (`git add -f`) was only written
into the process on 2026-08-25 — after this set was annotated. So for the whole
of V.8's life the README described eleven images that no session could open.
PR.18 sourced replacements; **every annotation below was rewritten against the
image that is actually in the folder**, not carried over.

Two consequences worth knowing:

- **Slot 02 (thread fineness) is covered, on a rule change.** It was first
  recorded as a gap: every usable candidate was dew-beaded, and the set excluded
  beading because it was *Arachne's* trait. Matt retired that exclusion the same
  day — Arachne was removed at D-246, so there is no longer a preset to stay
  distinct from.
- **Slot 07 was renamed.** It was named `07_temporal_mv_warp_echo` with a jpg extension, and `temporal`
  is not one of the eight scales `_NAMING_CONVENTION.md` permits — the file could
  never have passed `CheckVisualReferences`. It is now
  `07_meso_ring_echo_accumulation.jpg`.

## Reference images

Files in this folder, in priority order; per-image annotations are in
§Per-image annotations below. Sources and licences:

Every image is from Wikimedia Commons. Attribution is required for the CC BY /
CC BY-SA files if any of these are ever reproduced outside the repository.

| File | Source | Author | Licence |
|---|---|---|---|
| `01_macro_orb_geometry.jpg` | [Spider cross web in dark](https://commons.wikimedia.org/wiki/File:Spider_cross_web_in_dark.jpg) | Grauvision | CC BY 4.0 |
| `02_macro_thread_fineness.jpg` | [Spider web Luc Viatour](https://commons.wikimedia.org/wiki/File:Spider_web_Luc_Viatour.jpg) | Luc Viatour | CC BY-SA 3.0 |
| `03_lighting_emission_filament_strands.jpg` | [Fibreoptic](https://commons.wikimedia.org/wiki/File:Fibreoptic.jpg) | BigRiz | CC BY-SA 3.0 |
| `04_lighting_ssgi_environmental_fill.jpg` | [Mycena chlorophos](https://commons.wikimedia.org/wiki/File:Mycena_chlorophos.jpg) | Uploader (self) | CC BY-SA 3.0 |
| `05_meso_wave_propagation.jpg` | [Lissajous-Figur 2020 7766](https://commons.wikimedia.org/wiki/File:Lissajous-Figur_--_2020_--_7766.jpg) | Dietmar Rabich | CC BY-SA 4.0 |
| `06_specular_chromatic_aberration.jpg` | [Chromatic aberration with detail](https://commons.wikimedia.org/wiki/File:Chromatic_aberration_with_detail.jpg) | Jkk | CC BY-SA 3.0 |
| `07_meso_ring_echo_accumulation.jpg` | [Two-point interference ripple tank](https://commons.wikimedia.org/wiki/File:Two-point-interference-ripple-tank.JPG) | RenamedUser2 (en.wikipedia) | BSD |
| `08_micro_silk_material.jpg` | [Satin bedding](https://commons.wikimedia.org/wiki/File:Satin_bedding.jpg) | Jwrusa & Kjoonlee | Public domain |
| `09_atmosphere_volumetric_halo_primary.jpg` | [Meeresleuchten auf Norderney 02](https://commons.wikimedia.org/wiki/File:Meeresleuchten_auf_Norderney_02.jpg) | Stephan Sprinz | CC BY 4.0 |
| `10_atmosphere_volumetric_halo_secondary.jpg` | [Multicolored aurora borealis over Brastad 4](https://commons.wikimedia.org/wiki/File:Multicolored_aurora_borealis_over_Brastad_4.jpg) | W.carter | CC BY-SA 4.0 |
| `11_meso_interference_bloom.jpg` | [A study of the propagation… of ripple waves (1914)](https://commons.wikimedia.org/wiki/File:A_study_of_the_propagation,_refraction,_reflection,_interference_and_diffraction_of_ripple_waves_(1914)_(14596074950).jpg) | Internet Archive Book Images | No known restrictions |
| `99_anti_flat_palette_grid.jpg` | Uzume's own v3 render, `PresetVisualReviewTests` 2026-09-09 | — | project |

---

## V.8 target (`SHADER_CRAFT.md §10.2`) — status after PR.18

- **Macro** — 17 irregular spokes (D-042); off-center hub clipping upper rings
  into arcs; high spiral turn count so the web reads as an instrument body,
  not a geometry study. ✅ v3, unchanged. PR.18 added the **catenary scallop**:
  the capture spiral is pinned at each spoke and sags outward in between, with
  amplitude scaling as `r × gap`. This is the single change that stopped the
  web reading as a polar grid.
- **Meso** — physical wave displacement: each active wave offsets silk strand
  positions. No pure palette shifts. ✅ PR.18 — the wave field is resolved
  before the geometry and pushes the sample point radially. (Displacement is
  RADIAL, not yet perpendicular-to-local-tangent; the difference is small on a
  radial wave and is the remaining half of this item.)
- **Micro** — silk Marschner-lite material
  (`azimuthal_r = 0.08, azimuthal_tt = 0.5, absorption = 0.3`). ✅ PR.18 via
  `mat_silk_thread` + `fiber_trt_lobe`, with a cylindrical cross-section normal
  so a thread reads round. ⚠ `mat_silk_thread` never reads `absorption`.
- **Specular** — fine glints at thread intersections; chromatic aberration on
  the highest-amplitude wave peaks. ✅ PR.18 (glints ride the strands' proximity
  fields; v3's `spokeCov * spirCov` reached almost no pixels).
- **Atmosphere** — bioluminescent ambient haze in a ~0.5-radius halo; dust motes
  drawn inward at high vocal energy, outward at silence. ✅ PR.18.
- **Lighting** — nearly-black scene; web emission is the primary light source;
  SSGI projects soft fill onto the background. ◐ PR.18 — the haze carries the
  waves' own colour into the air, which is the fill this 2D preset can express.
  True screen-space GI is not available on the `mv_warp` path.
- **Temporal** — `mv_warp` accumulates outward-propagating wave fronts as
  decaying echoes (decay 0.955); the hub-centered ring signature is a defining
  trait, not a side effect. ✅ v3, unchanged.
- **Audio** — waves vocal-pitch-keyed; wave amplitude drives displacement
  magnitude; dust drift from vocal energy. ✅ — 14 routes declared in the
  sidecar and gated by QG.1. ⏳ Wave propagation VELOCITY is still the constant
  `kWaveSpeed`; `2.0 + vocals_energy_dev × 5.0` is not implemented.

---

## Mandatory traits (per SHADER_CRAFT.md §12.1)

- [x] **Detail cascade:** macro = haze density (`perlin3d`, scale 2.2); meso = per-strand
      character driving width / sag / tilt (`fbm4`, scale 5.5); micro = surface grain along
      the thread (`perlin3d`, scale 48.0); specular = R + TT + TRT fiber lobes and node glints.
- [x] **Hero noise function(s):** `fbm4` (strand character) + `perlin3d` (grain, haze).
      Four octaves is the §12 floor exactly; `fbm8`'s extra four are sub-pixel here and were
      measured to cost without showing (PR.18).
- [ ] **Material count and recipes:** `mat_silk_thread` + `fiber_trt_lobe`. **One cookbook
      material — M3 wants three and this FAILS it.** Gossamer draws a single substance; two
      more `mat_*` calls would be decoration for a gate. Recorded, not worked around.
- [x] **Audio reactivity:** 14 routes declared in `Gossamer.json` and gated by QG.1 —
      `vocalsPitchHz` (wave hue), `vocalsPitchConfidence` (emission gate), `vocalsEnergyDev`
      (displacement), `vocalsEnergyRel` (haze, dust drift), `otherEnergyDev` (emission rate),
      `bassEnergyRel` / `bassAttRel` (tautness), `drumsEnergy` (tremor), `trebDev` (glints),
      `midAttRel` (breathe). All D-026 deviation primitives.
- [x] **Silence fallback:** the drift floor holds ≥ 2 waves alive (D-037 invariant 4,
      `GossamerStateTests` test 8); `presence` floors the strand tint at 0.22 so the web is
      dim but lit, and the haze persists. Never black.
- [ ] **Performance ceiling:** **~10.0 ms at 1080p** against v3's ~6.6 ms — `complexity_cost`
      updated to `tier1 10.0 / tier2 5.8`. Inside the 16.6 ms budget but 4th of 22 rather than
      18th; the increase is real and is reported rather than smoothed.
- [x] **Hero reference image:** `01_macro_orb_geometry.jpg`.

## Expected traits (per §12.2 — at least 2 of 4)

- [ ] Triplanar texturing — **n/a**: there are no non-planar surfaces; the web is drawn in UV space.
- [ ] Detail normals — **n/a** for the same reason. The cylindrical cross-section normal is
      computed analytically from the signed offset across each thread, not sampled from a map.
- [ ] Volumetric fog / aerial perspective — **applicable but unmet by the rubric's test.** The
      haze halo is a genuine luminous medium, but `vol_density_height_fog` is a 3D
      ray-march utility and does not fit a 2D radial halo, so no named call exists to detect.
- [x] SSS / fiber BRDF / anisotropic specular — **yes**: `mat_silk_thread` (R + TT) plus
      `fiber_trt_lobe` for the far-side rim.

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [x] Hero specular highlight in ≥60% of frames — **yes**: node glints at every spoke/spiral
      crossing, plus the R-lobe axial highlight on strands the orbiting key light aligns with.
- [ ] Parallax occlusion mapping — **n/a**, no surfaces.
- [x] Volumetric light shafts or dust motes — **yes**: dust motes on a jittered lattice,
      drifting inward at high vocal energy and outward at silence.
- [ ] Chromatic aberration or thin-film — **implemented but undetected.** The three-tap
      per-wave sampling is genuine CA; `chromatic_aberration_radial` is a texture
      post-process and cannot express aberration on an analytic ring, so it is not called.

## Per-image annotations

### `01_macro_orb_geometry.jpg` — orb web, silver filament on black

> *Reference for: macro web geometry reading against a dim scene
> (`SHADER_CRAFT.md §10.2.1`).*

- A complete orb web shot at night against a near-black field, spider at the
  hub. **This is the hero geometry reference.**
- Radials are individually resolvable across the whole frame and read as
  *silver-white hairlines*, not as chunky strokes — the thread-width target.
- Spoke spacing is visibly irregular and the capture spiral **scallops between
  consecutive radials** rather than running as true circles. Cite this for the
  catenary: it is what D-042's irregular anchor array is supposed to produce.
- The hub is off-centre and the outer spiral is clipped by the frame.
- **Caveat:** the spider is present and Gossamer draws none. Ignore it; the
  Arachnid-trilogy spider is *Arachne's* trait (`SHADER_CRAFT.md §10.1`).

### `02_macro_thread_fineness.jpg` — dew-beaded orb web, thread spacing

> *Reference for: spiral fineness and turn density (`§10.2.1`).*

- Every thread of the capture spiral is **individually resolvable** — no aliased
  blobs, no merged bands. Spacing is small relative to thread width, so the
  spiral reads as a continuous instrument body rather than a coarse skeleton.
  This is the trait v3 got right and must not lose.
- The scallop is visible again here, independently of `01`: each span between
  radials bows outward. Two references agreeing on it is why PR.18 treats the
  catenary as a defining trait rather than a flourish.
- Beading picks out the threads and makes the spacing legible — read *through*
  the drops to the thread geometry underneath.
- **Caveat, and it changed on 2026-09-09:** the older version of this set
  excluded beaded webs because dewdrops were *Arachne's* trait
  (`SHADER_CRAFT.md §10.1.3`) and the two presets had to stay distinct.
  **Arachne was retired at D-246**, so that exclusion no longer applies (Matt,
  2026-09-09) and beaded macros are admissible. Beading is still not a trait
  Gossamer must *implement* — cite this image for thread spacing and fineness.

### `03_lighting_emission_filament_strands.jpg` — fibre-optic fan with bright tips

> *Reference for: silk emission as the primary light source against
> near-zero ambient (`§10.2.6`); also the node/endpoint glint reference (`§10.2.4`).*

- A fan of fine optical fibres against pure black, each strand individually
  resolvable, each tip a small intense pinpoint.
- **Body-vs-tip separation is the trait**: the strand body is a dim continuous
  line and the tip is *brighter and a different colour*. That separation, not
  brightness alone, is what makes a glint read as a glint. PR.18's node glints
  are keyed to this: warm-white points on a teal filament.
- Frame falls to near-zero away from the strands; the halo is tight.
- **Caveat:** fibres are fanned from a single base, roughly parallel, not
  radial-from-hub, and the emission is white rather than teal. Cite for the
  emission *regime* and the body/tip colour split. D-042 governs layout.

### `04_lighting_ssgi_environmental_fill.jpg` — bioluminescent Mycena

> *Reference for: emission as the only light in the scene (`§10.2.6`).*

- Glowing green fungi against a black ground, lighting themselves and nothing
  else. Everything visible is visible *because of* the emission.
- The falloff is the trait: bright at source, gone within a short radius, no
  ambient anywhere in frame. Gossamer's background must behave this way — dark
  except where the web's own light reaches.
- **Caveat, and it is a real one:** the original slot wanted fungi projecting
  fill onto *surrounding foliage*, and this image has almost no surroundings to
  catch it. It carries the zero-ambient emission regime and **not** the
  fill-onto-a-surface half. That half is uncovered — see §Gaps.

### `05_meso_wave_propagation.jpg` — light-painted Lissajous figure

> *Reference for: overlapping sinusoidal traces (`§10.2.2`).*

- Many overlapping smooth sinusoidal traces against pure black, drawn as thin
  bright filaments. This is what a strand following a propagating transverse
  wave looks like integrated over time.
- Trace density varies — where paths bunch, the light sums and brightens. That
  summation is the behaviour wanted where multiple vocal-pitch-keyed waves stack
  along one radial.
- **Caveat:** the figure is a closed harmonic curve, not a travelling front, and
  it is unconstrained where Gossamer's silk is pinned at hub and rim. The
  *filament-trace character* carries; the topology does not.

### `06_specular_chromatic_aberration.jpg` — CA fringe with inset detail

> *Reference for: chromatic aberration on wave peaks (`§10.2.4`).*

- A high-contrast edge with the inset showing the cyan/blue fringe that appears
  where channels do not converge. That fringe is the target signature for
  PR.18's three-tap wave sampling.
- Fringing appears **only at the highest-contrast boundary** and is absent
  elsewhere — which is why the shader scales the channel offset with wave
  amplitude rather than applying it uniformly.
- **Caveat:** this is a demonstrative photograph with a magnified inset, not an
  aesthetic target. Cite the *fringe* only; nothing about the composition.

### `07_meso_ring_echo_accumulation.jpg` — ripple-tank concentric rings

> *Reference for: `mv_warp` feedback decay (0.955) and the hub-centred ring
> signature.*

- Concentric wavefronts radiating from a point source, each successive ring
  slightly wider and fainter — the visual signature of exponential decay, and
  what one frame of accumulated `mv_warp` output should look like under steady
  vocal input.
- Ring spacing is even; the *brightness* falls off, not the geometry.
- **Caveat:** a ripple tank is a shadowgram of surface waves, so the rings are
  dark-on-light where Gossamer's are light-on-dark. The decay character and the
  spacing carry; the polarity does not.

### `08_micro_silk_material.jpg` — folded satin

> *Reference for: silk Marschner-lite material (`§4.3`, `§10.2.3`).*

- Satin is woven silk, and the broad band of sheen running along each fold is
  **the Marschner R-lobe signature** — a specular line oriented along the fibre
  direction, perpendicular to the surface's curvature.
- Soft falloff at the fold edges shows the TT (transmission) lobe: light
  entering the silk and re-emerging at a shifted angle. This is what
  `azimuthal_tt = 0.5` reproduces.
- The gradient between sheen band and shadow is smooth — silk is glossy, never
  mirror-like. A hard specular cut is wrong for this material.
- **Caveat:** the palette is incidental (this print is violet; the original slot
  was gold) — V.8 silk is keyed to vocal-pitch hue. And Gossamer's silk is
  filament-thin, not sheet-woven: the *reflectance signature* carries, not the
  surface area.

### `09_atmosphere_volumetric_halo_primary.jpg` — bioluminescent surf, Norderney

> *Reference for: bioluminescent ambient haze around the web (`§10.2.5`).*

- **The single most important atmosphere reference.** The blue glow exists *in
  the medium itself*, not on a surface — the trait PR.18's haze layer exists to
  produce. Air within ~0.5 UV of the hub should be perceptibly luminous rather
  than unlit black with a web drawn on top.
- Falloff is smooth inside the luminous water and sharp at its edge; the sky
  above stays near-black. This **bounds the halo radius** — Gossamer's haze must
  not bleed to the frame edge.
- The glow is not uniform: it has internal structure and density variation. That
  is why the shader modulates haze with a low-frequency noise octave; a perfectly
  smooth radial falloff reads as a lens flare, not as luminous air.
- **Caveat:** the glow is distributed along a shoreline (horizontal); Gossamer's
  is radial-from-hub. Cite the medium's character and falloff, not the layout.

### `10_atmosphere_volumetric_halo_secondary.jpg` — aurora over Brastad

> *Reference for: hue-graded volumetric falloff at the halo perimeter (`§10.2.5`).*

- The green-to-violet shift across the volume shows emission colour changing
  across a luminous medium without breaking the read of a single source. Useful
  for the halo perimeter, where haze hue may drift toward the complement.
- Smooth fade to black at the perimeter — no hard cutoff between glow and sky.
- **Caveat:** the aurora has a directional curtain sweep Gossamer's halo does
  not, and the foreground town lights are not a trait. Cite the gradient and the
  fade only.

### `11_meso_interference_bloom.jpg` — two-source ripple interference

> *Reference for: brightening where wave fronts overlap
> (`saturate(totalRingWeight - 1.0) × 0.45 × strandCov`).*

- Two ripple sets from separate sources, with a clear interference field where
  they meet. Along the constructive lines the fronts reinforce and read stronger
  than either set alone; along the nulls they cancel.
- **The crossing-point behaviour is the trait** — where two of Gossamer's waves
  overlap on a strand, the result must be *more* than either, not an average.
- **Caveat:** plate figures from a 1914 monograph, monochrome and dark-on-light.
  Cite the interference structure only; nothing about tone or palette.

---

## Anti-references

### `99_anti_flat_palette_grid.jpg` — Gossamer v3, captured at PR.18 kickoff

Frame-grab from the v3 build, the state Matt described as *"a child's drawing of
a spider web, or a basic computer program from 30 years ago"* (2026-09-09).

> **NOT this** — uniform-width strokes with no material; every strand identical;
> the capture spiral running as mathematically perfect concentric ellipses with
> no scallop between anchors; waves applied as a flat palette tint over strands
> that were already drawn, rather than displacing them; node glints present in
> code but reaching no pixels; and a flat unlit background with no luminous
> medium around the web.

Compare any candidate render against this first. If it is closer to this than to
`01`, the fidelity work has regressed.

---

## Gaps still uncovered

*(Thread fineness was listed here on first pass and is now **covered** by slot 02.
It was recorded as a gap because every usable candidate was dew-beaded and the
set excluded beading as an *Arachne* trait — an exclusion **Matt retired on
2026-09-09**, Arachne having been removed at D-246. The gap was a stale
constraint, not a missing image.)*

**Emission fill onto a surface (`§10.2.6`)** — `04` covers zero-ambient emission
but has no surroundings for the light to fall on. Wanted: a small emissive source
lighting a nearby textured surface, with visible falloff and no other light.

**Inward/outward dust drift (`§10.2.5`)** — motes drawn inward at high vocal
energy, outward at silence. Still uncaptured, and it wants a short loop rather
than a still: incense smoke under a slowly oscillating fan is the canonical
capture. Lowest priority — dust is a secondary atmospheric layer.

---

## Audio routing notes

All routes are D-026 deviation primitives behind the D-019 stem warmup (`stemMix`), and all
14 are declared in `Gossamer.json` where QG.1's `RouteCoverageTests` holds them honest —
a route that stops firing on the canonical fixtures goes red.

- **Wave hue ← `stems.vocals_pitch_hz`**, gated by `vocals_pitch_confidence > 0.35`, mapped
  `log2(pitch/80) / log2(10)` so 80–800 Hz spans the hue circle. ⚠ Note BUG-124's finding:
  the pitch tracker recovers PERIODICITY, not vocals — an instrumental track's "vocals" stem
  can read as confidently pitched. The hue will key to that.
- **Wave emission rate ← `stems.other_energy_dev`** — guitar/keys strike the web.
- **Wave displacement + amplitude ← `stems.vocals_energy_dev` / `_rel`.**
- **Strand tautness ← `bass_energy_rel` + `bass_att_rel`**, into the tremor amplitude.
- **Strand tremor ← `drums_energy`**, on the beat grid phase, never raw live onsets.
- **Node glints ← `f.treb_dev`** (continuous, not accent — it does not reach the 0.9 peak an
  accent route must, and declaring it as one failed QG.1 correctly).
- **Haze + dust drift ← `vocals_energy_rel`.** Drift sign flips: inward when vocals are
  above their running average, outward at silence.
- **Web breathe ← `mid_att_rel`** via the `mv_warp` per-frame zoom.

**Anti-pattern to keep out:** absolute AGC-normalised bands. v3 drove brightness from
`f.bass` at six times the weight of its deviation term (FA #31) — how bright the web looked
tracked mix density, so the same kick read differently across tracks. Fixed at PR.18.

## Provenance

**Curated by:** Claude (PR.18, 2026-09-09) — **pending Matt's review.** The process doc says
image sources are Matt's choice; these were sourced on his instruction to "recurate the
reference images" and every one should be treated as a proposal he can swap.

**Image sources:** Wikimedia Commons, licences and authors in §Reference images above. Nine
CC BY / CC BY-SA / BSD / public-domain photographs plus one 1914 plate figure with no known
restrictions. `99_anti_flat_palette_grid.jpg` is Uzume's own v3 render.

**The previous set had no images at all** — see the recuration note at the top.

## Cross-references

- `SHADER_CRAFT.md §10.2` — Gossamer V.8 uplift plan
- `SHADER_CRAFT.md §4.3` — silk thread Marschner-lite recipe
- `SHADER_CRAFT.md §2.3` — reference-image discipline
- `DECISIONS.md D-042` — explicit spoke-angle array, off-center hub
- `DECISIONS.md D-026` — deviation-primitive audio routing
- `DECISIONS.md D-027` — `mv_warp` constraints
- `ENGINEERING_PLAN.md PR.18` — the fidelity uplift and this recuration
- `ENGINEERING_PLAN.md Increment V.8` — original implementation scope
