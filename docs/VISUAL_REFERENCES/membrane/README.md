# Membrane — Visual References

**Family:** `reaction` &nbsp;·&nbsp; **Passes:** `feedback` &nbsp;·&nbsp; **Rubric:** full (per D-064(a))
**Recurated:** 2026-09-14 (PR.28) — **for the drumskin concept.** The 2026-05-01 curation targeted a
*fluid marbling* preset with no strike at all; Matt chose the drumskin at PR.25 and that set is retired.
**Curation role:** fidelity + regression target for certification.

---

## The concept these images serve

**Musical role.** *The surface is the drumhead — a bass-weighted strike lands at a point and travels
outward as an expanding ring, so the listener sees each hit land and move; between hits the sheet is
quiet enough that the next strike reads as an event.*

**Temporal contract.** A ring is born on the beat (phase-locked to the cached `BeatGrid`), expands at
a constant rate, fades before the next beat, and is struck as hard as the metre and the bass say —
downbeat 1.00, mid-bar 0.52, off-beats 0.22, times that beat's bass. **Silence:** no strikes at all
(gated on `pulse_amp01`); the skin keeps breathing on its always-on FBM and the accumulator keeps
advecting. Membrane **coasts** at silence — it does not freeze, and it is never black (D-037).

**Why water, for a preset called a drumskin.** Matt's own word for it in the roster review is
*"puddle pulse"*, and a struck liquid surface is the photographable version of the behaviour: a point
impact, concentric rings, amplitude decaying outward, successive strikes overlapping. A photograph of
a drumhead at rest teaches nothing about any of that.

**Why soap film, for the palette.** Membrane's colour is three FBM "thickness" fields through
`hsv2rgb` — that *is* a thin-film interference model. The rainbow is not decoration and not an
arbitrary choice: it is what a thin film physically does, which is why `03` and `04` are the palette
authority. **PR.25 replaced this palette with a dark desaturated field, was told to put it back
(`06_anti_desaturated_field.png`), and the colour code is now byte-identical to its pre-PR.25 state.**

---

## Reference images

Per D-065(c) each annotation states three things: the **mandatory** traits, the **decorative** ones,
and the traits that must be **actively disregarded**.

| File | Slot | Mandatory — learn this | Decorative | **Actively disregard** |
|---|---|---|---|---|
| `01_macro_strike_ring_expansion.jpg` | macro / whole-frame | **The whole-frame behaviour, and the single best image in this folder.** Many independent point impacts, each a set of concentric rings at a *different age and amplitude* — some large and faint (old), some small and sharp (new), overlapping without merging into mush. This is exactly what a bar of beats should look like: strikes of different strengths at different stages of travel, on one continuous full-bleed surface. Note the generous quiet water between ring systems — the calm is what makes each ring legible. | The green-grey water colour; the pale sky reflection. | The **rain** reading — Membrane's strikes are not random and not uniform; they are metrical, and the downbeat is visibly the biggest. Also the flat overhead camera: Membrane has no camera. |
| `02_meso_single_strike_anatomy.jpg` | meso / one strike | **The anatomy of one impact, close up.** Alternating crest and trough as concentric bands, each crest catching light and each trough falling dark — a **light/dark edge pair**, which is the thing that makes a ripple read on a bright surface. Amplitude decays outward smoothly; the rings are soft-edged, never hard-bordered. Spacing widens slightly with radius. | The silver/blue cast; the vignetting at the frame corners. | The **single-subject composition** — Membrane is full-bleed and continuous, never one centred object on a ground. Also the near-monochrome: this image teaches ripple *structure*, not palette. |
| `03_micro_thin_film_grain.jpg` | micro / surface | **Thin-film interference at macro scale, and the palette authority.** The saturated spectral band at lower-left is a real hue sweep through film thickness — full spectrum, high saturation, continuous. That is the physical justification for Membrane's `fract(thickness)` hue. Also: fine surface grain at several scales at once, the detail cascade on a continuous film. | The specific hue ordering of the band; the grey midfield. | The **discrete bubble/cell structure** — the roughly circular cells and their hard bright borders. Membrane is one continuous sheet, not a bubble raft or a cell network. A session reading cell structure as a directive will build the wrong preset (this is the mistake the retired 2026-05-01 curation made). |
| `04_specular_thin_film_bands.jpg` | specular / material | **How thin-film colour flows.** Broad marbled bands of saturated warm and cool sweeping across the surface, with soft light/dark modulation riding on top — colour as a continuous *field* with structure, not as noise and not as a flat wash. The small bright speckles are the specular character: sparse glints on the film, not an all-over sheen. | The orange/teal bias of this particular film. | The **discrete sphere** — the bubble's round silhouette and the dark surround. Membrane is full-bleed; it never renders a discrete object on a background. (This was `anti_03` in the retired set and the caution still stands — read the *surface*, ignore the *object*.) |

## Anti-references (failure modes specific to this preset)

| File | Failure mode | Why it is tempting | **Actively disregard** |
|---|---|---|---|
| `05_anti_resolved_standing_pattern.jpg` | A **resolved, static, symmetric standing-wave mode** (Chladni sand figure). | It is a vibrating membrane responding to sound — superficially the exact subject — and the pattern is beautiful and legible. | *Every* trait. This is a **standing** mode: the pattern is fixed in space and the energy is where the sand is *not*. Membrane is a **travelling** ripple born at a point and moving outward. A session that reads this as a directive builds a symmetric modal pattern generator, which is a different preset and has no strike in it. |
| `06_anti_desaturated_field.png` | **The palette PR.25 substituted without being asked** — dark blue-purple sheet, muted, strike as an added coral glow. In-engine capture of the rejected build. | It makes a bright ring trivially easy to see, and it is defensible from the brand tokens and from an anti-reference annotation read as a licence. | *Every* trait. Matt, M7 2026-09-14: *"why did you eliminate the rainbow background and replace it with a drab-colored one?"* The palette is not the preset's to change. An anti-reference describes a failure mode; it is **not** authority to redesign the most visible property of a preset. |
| `07_anti_diagonal_seam_crease.png` | **Hard diagonal seams crossing as an X.** In-engine capture of the PR.26 build. | It looks like an intentional compositional device, and it is easy to stop seeing once you have looked at a hundred frames. | *Every* trait. It is a bug: edge tension used `min(edgeDist.x, edgeDist.y)`, and `min()` of two smooth fields has a **gradient discontinuity along the locus where they are equal** — the frame diagonals — which `membrane_D`'s finite difference amplifies ×28 into the normal. Fixed at PR.27 with the *product* of the two per-axis falloffs. **Any preset that shapes a field with `min()` of two distance terms and then differentiates it will show this.** |

---

## Mandatory traits (per SHADER_CRAFT.md §12.1 — 7/7 for certification)

- [x] **Detail cascade.** macro = whole-frame strike distribution and ring travel (`01`); meso = the
      crest/trough anatomy of one ring (`02`); micro = ≥4-octave film grain (`03`); specular = sparse
      glints on the crest (`04`).
- [x] **≥4 noise octaves.** `fbm8` (8 octaves, inter-octave rotation) in the colour path; the
      displacement path uses 4-octave `mb_fbm3` ×3 per fragment for the normal's finite difference.
- [x] **≥3 distinct zones.** Three independent FBM thickness fields with time-drifting weights.
- [x] **Deviation primitives (D-026).** 8 declared `audio_routes`, all green in `RouteCoverageTests`;
      no absolute-threshold reads remain (FA #31).
- [x] **Graceful silence.** Non-black, non-constant, bounded — accumulator meanLuma 0.196 at silence,
      no strikes. Matches the coasting design stated above.
- [x] **Performance.** `feedback` is the cheapest pass in the engine; not at risk at 1080p.
- [x] **Matt-approved reference frame match.** ✅ Two approvals, both recorded. Live M7 2026-09-14:
      *"Looks much better... read as real impacts... Music sync feels tighter overall."* Then the
      comparison sheet against THIS folder, same day: *"re: Matt-approved reference frame match -
      approved."* **7/7 mandatory.**

## Expected traits (per §12.2 — at least 2 of 4)

- [x] **Detail normals (adapted).** Treble stipple perturbs displacement, which is differenced into
      the normal — surface-grain normal variation. Cite `03_micro_thin_film_grain.jpg`.
- [x] **SSS / translucency (adapted).** Wrapped diffuse (`NdotL * 0.5 + 0.5`) plus the fresnel rim
      sampled from a second thickness reads as light passing *through* a stretched film.
      Cite `04_specular_thin_film_bands.jpg`.
- [ ] **Volumetric fog / aerial perspective** — N/A for a 2D full-bleed sheet.
- [ ] ~~Triplanar texturing~~ — N/A (no surface normals in world space).

**Score: 2 of 4.**

## Strongly preferred traits (per §12.3 — at least 1 of 4)

- [x] **Chromatic aberration / thin-film interference.** The entire colour model *is* thin-film
      interference — three FBM thickness fields through `hsv2rgb`. `03_micro_thin_film_grain.jpg` and
      `04_specular_thin_film_bands.jpg` are the authority. Strongly satisfied.
- [ ] ~~Hero specular highlight ≥60 % of frames~~ — N/A for non-PBR feedback.
- [ ] ~~Parallax occlusion mapping~~ — N/A.
- [ ] **Volumetric light shafts / dust motes** — not attempted.

**Score: 1 of 4.**

---

## Audio routing notes

The shipped manifest is `audio_routes` in `Membrane.json` — 8 routes, all green in
`RouteCoverageTests`. **That manifest is the authority; this section explains the intent.**

| Visual behaviour | Primitive | Kind | Why this one |
|---|---|---|---|
| Ring is born and expands | `beatPhase01` | accent | 0 at the beat, ramps to 1 at the next — the ring is on the beat *by construction*. Measured 100 % on-beat vs a 31 % chance level; the previous driver `beat_bass` scored 0.97× chance and the one before that 0.83×. |
| Downbeat ring is larger and slower | `barPhase01` | accent | Metric accent — downbeat 1.00, mid-bar 0.52, off-beats 0.22. This is what stops four identical hits per bar reading as a machine (`01_macro_strike_ring_expansion.jpg` shows the real thing: strikes of visibly different strengths). |
| How hard the strike lands | `bassDev` | continuous | Soft-saturated `bassDev/(bassDev + 0.12)` — **scale-free on purpose.** A linear normaliser fitted to one capture set starved the gate to impossibility when the live session's range turned out 4.3× smaller. |
| Strikes enabled at all | `pulseAmp01` | **gate** | 0 across sustained silence. Declared `gate`, never `continuous` — an enable sits pinned open through music and would clear a `continuous` floor vacuously (BUG-088). |
| Slow whole-sheet undulation | `bassAttRel` | continuous | The "hand pressing into the skin" between strikes. |
| Fine surface stipple | `trebAttRel` | continuous | Hi-hat grain. Gain calibrated to its real p99 (0.012), not to 1.0. |
| Impact point drift | `arousal`, `valence` | continuous | The strike wanders slowly so a long track does not hammer one spot. |

**Never use `beat_bass` / `beat_*` here.** They are constant-rate pulse clocks, not detectors —
132–138 rising edges/min on all five test tracks *including a drumless ambient instrumental*, where
the signal repeats `1.000 → 0.201 → 0.040` forever.

`requires_regular_beat: true` (D-154): the preset is grid-locked, so beat-irregular tracks exclude it
rather than being driven by a grid that does not fit.

---

## Provenance

Sourced by: **Claude, on Matt's explicit instruction** (2026-09-14: *"I want you to source the
reference images"*). This departs from `SHADER_CRAFT.md §2.3` (*"Matt owns the references"*) by his
direction, recorded here so the exception is visible and does not become precedent.

Every target-trait image is **real photography** under a free licence — no AI generation anywhere in
this folder, so the D-065 `_AIGEN` carve-out is not used and does not apply.

| File | Source | Author | Licence |
|---|---|---|---|
| `01_macro_strike_ring_expansion.jpg` | Wikimedia Commons, *Waterwaves raindrops on water surface.jpg* | Patrick.Nordmann | CC BY-SA 4.0 |
| `02_meso_single_strike_anatomy.jpg` | Wikimedia Commons, *2006-01-14 Surface waves.jpg* | Roger McLassus | CC BY-SA 3.0 |
| `03_micro_thin_film_grain.jpg` | Wikimedia Commons, *Soap Film.jpg* | KarlGaff | CC BY 4.0 |
| `04_specular_thin_film_bands.jpg` | Wikimedia Commons, *Thin Film Interference Soap Bubble.jpg* | Pksois23 | CC BY-SA 4.0 |
| `05_anti_resolved_standing_pattern.jpg` | Wikimedia Commons, *Quadratic Chladni plate cropped version.jpg* (cropped to the plate) | High Contrast | CC BY-SA 3.0 |
| `06_anti_desaturated_field.png` | In-engine capture, PR.25 build (rejected at M7) | Uzume | project-internal |
| `07_anti_diagonal_seam_crease.png` | In-engine capture, PR.26 build (defect, fixed at PR.27) | Uzume | project-internal |

All images resized to ≤1280 px and ≤500 KB per `_NAMING_CONVENTION.md`. Originals not retained.

**These files are gitignored repo-wide** (`docs/VISUAL_REFERENCES/**/*.jpg|png`, untracked since the
LFS cutover, D-211). They are committed with `git add -f`. **Do not "clean up" an untracked-file
warning here by deleting them** — that is how the previous set was lost, leaving only a README
describing images nobody could look at.

## First perception check against this folder (PR.28, 2026-09-14)

The folder's whole purpose is that this check can now run at all. It ran, and **it found two
mandatory-trait failures that Matt's live M7 did not** — a still sheet and a live watch catch
different things, which is exactly why the checklist requires both.

| trait | reference | verdict | what differed |
|---|---|---|---|
| Whole-frame strike distribution | `01` | **FAIL — partly unfixable, see below** | Reference shows many rings at different ages with *generous calm water between them*. The render has no calm anywhere: the field is saturated edge-to-edge, so a ring has nothing to read against. |
| Single-strike anatomy | `02` | **FAIL → fixed** | Reference is a *sequence* of concentric crests decaying outward; the render emitted ONE Gaussian annulus, which reads as a sweep rather than an impact. Fixed by emitting a three-crest wave train (`membrane_ring`). Re-checked: concentric structure now visible. |
| Thin-film grain | `03` | PARTIAL | Colour family correct; fine multi-scale grain does not survive the accumulator's per-frame resample (a measured paradigm ceiling — 12× emitted contrast returns 1.4×). |
| Thin-film colour flow | `04` | PASS | Saturated spectral bands, continuous, in-family. |
| does NOT resemble a resolved standing mode | `05` | PASS | Travelling, never static or symmetric. |
| does NOT resemble the drab field | `06` | PASS | Palette restored byte-identical. |
| does NOT show diagonal creases | `07` | PASS | Fixed at PR.27. |

**On the `01` failure, and why it is not simply a bug to fix.** The reference's legibility comes from
*negative space* — quiet water between ring systems. Membrane's palette is a full-value rainbow across
the entire frame, which Matt chose and which PR.25 was told to put back. **The two are in tension:
quiet ground is the mechanism the reference uses, and it is unavailable here by design.** That is a
real constraint, not an oversight, and it means the ring itself has to carry all the legibility.
Anyone tempted to "fix" this by calming the field should read `06_anti_desaturated_field.png` first.

## Open

- **✅ CERTIFIED 2026-09-14 (PR.29) — the 25th.** 7/7 mandatory, 2/4 expected, 1/4 preferred.
  Flash-safety measured for real rather than skipped: under a worst-case 4.5 accents/s beat train the
  single-pass gate reports **MEASURED (Δ0.109 — the largest response of any preset in that set),
  0.00 flashes/s, SAFE**. Membrane is deliberately NOT on the `multiPassMeasured` skip list: its
  strike is computed in the fragment from the FeatureVector, so this harness genuinely reaches it.
- Residual `01` gap (no negative space) is a standing constraint, not a defect — see the box above.
- Known-open and **not preset defects**: **BUG-134** (`beatPhase01` running +5.8 % fast against its own
  installed grid on some tracks) and **BUG-135** (bar position cannot be confirmed to be the true
  downbeat; Matt's call is to leave it). Both cap how tight the sync can read on affected tracks.
