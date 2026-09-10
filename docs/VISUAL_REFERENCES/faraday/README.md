# Visual References — Faraday (working name Tacoma)

**Family:** hypnotic
**Render pipeline:** compute solver (spectral) — `TacomaSolver`, on the spine extracted from
`AlfvenSolver` in FARADAY.1
**Rubric:** lightweight — a 2D field preset, Plasma / Alfvén class. Detail cascade, 3-material
count and triplanar are inapplicable by design.
**Last curated:** 2026-09-09 by Matt

---

## PROVENANCE CAVEAT — read before trusting any image

These are frames from the CPU look-spike (`docs/presets/faraday_spike/`), a pseudo-spectral
solver stepped with explicit Euler. The shipping preset uses the **same spectral formulation**
— unlike Alfvén, where the reference set came from a different numerical scheme — so these are
a closer target than Alfvén's were. What still differs: the shipping version uses an **exact
propagator** for the linear part rather than explicit Euler, at a larger timestep. Expect the
same shapes and scale; expect small differences in how sharp the fringe cores read.

Every frame here is at the **shipping configuration**: `k0 = 3` (six visible wavelengths),
`nu = 0.0012`, `lambda = 0.22`, `mix = 0.28`, drive capped below the inversion point, closed-loop
re-seed on the order parameter. Source track `so_what.m4a` from the tempo fixtures.

## Reference images

| File | Annotation |
|---|---|
| `01_macro_cellular_lattice.png` | **The hero.** Six-ish iridescent cells across the short side, irregular and polycrystalline, each ringed by interference contours. This is the frame with the lowest measured orientational order in the run (S = 0.015) and it is what the preset should look like most of the time. |
| `02_meso_iridescent_contour.png` | **Contour structure.** Bands run parallel to the cell walls and compress where the surface steepens. TRUST the band spacing and the way bands crowd at cell boundaries; do not trust absolute hue — it drifts with spectral centroid. |
| `03_micro_fringe_core.png` | **Fringe core.** Inside one cell: a smooth continuous sweep through the interference orders, not a stepped or posterised ramp. If the shipped render shows banding staircases here, the OPD lookup is under-resolved. |
| `04_palette_interference_bands.png` | **Palette.** Left = thin film (base 380 nm), right = thick (475 nm). The same geometry re-coloured. Keep the optical path in roughly 500–1400 nm; past that, fringe orders desaturate to grey. |
| `05_atmosphere_quiescent_film.png` | **Silence / low-drive state (D-037).** The lowest-drive frame in the run: few, large, slow cells, still fully coloured. Never black, never flat grey. |
| `06_anti_single_domain_rolls.png` | **NOT this.** The annealed state — one roll orientation has won, S = 0.976. If the render looks like this, the closed-loop re-seed is not working. This is the single most important image in the folder. |
| `07_anti_fine_stripe_fabric.png` | **NOT this.** `k0` too high: sixteen wavelengths across the frame reads as fabric, not composition. The spike's first film shipped at this setting and it was wrong. |
| `08_anti_drive_inversion_noise.png` | **NOT this.** Drive pushed past the inversion point, so `(1 + F)` goes negative for part of the cycle: heavy speckle over every cell. The audio-to-drive map must be **capped**, not scaled. |
| `target_animated.gif` | **Motion target** (160 frames, 20 fps). Cells breathe, re-order, and dissolve into fresh fields. No pop, no strobe, no freeze. |

## Mandatory traits checklist

- [ ] **Scale:** 5–8 visible wavelengths across the short side (`PEAK_K` in 5–8, and `PEAK_K = 2*k0`).
- [ ] **Order:** polycrystalline — cells in several orientations, not one. Median `S` below ~0.35 over a full-length soak.
- [ ] **Contours:** continuous interference bands ringing each cell, crowding where the surface steepens.
- [ ] **Colour:** saturated across the frame, not confined to edges over a grey ground.
- [ ] **Silence:** few, large, slow, fully coloured cells (D-037).
- [ ] **Motion:** continuous; dissolves are crossfades, never cuts.
- [ ] **does NOT resemble** `06_anti_single_domain_rolls` — no single-orientation stripe field.
- [ ] **does NOT resemble** `07_anti_fine_stripe_fabric` — no sixteen-wavelength texture.
- [ ] **does NOT resemble** `08_anti_drive_inversion_noise` — no speckle over the cells.

## Stylization contract (substitute for the full rubric)

- **Colour modulation:** thin-film interference through a CIE-integrated LUT indexed by optical
  path difference; film thickness from spectral centroid. Never an absolute threshold on
  AGC-normalised energy (FA #31) — exposure is percentile-based.
- **Audio coverage:** the pattern's symmetry always reflects the current harmony and its
  amplitude always reflects the low end; neither channel may go to zero coverage.
- **Readability at silence:** `05_atmosphere_quiescent_film.png`.
- **Readability at peak energy:** cells stay individually readable. If loud passages fill the
  frame with undifferentiated speckle, the drive cap is wrong — compare `08`.

## Two standing diagnostics (report both, every session)

- **`PEAK_K`** — peak of the radial power spectrum of the envelope field. Equals the visible
  wavelength count. Target 5–8.
- **`S`** — nematic order in the dominant shell, `|sum P e^{2i.theta}| / sum P`. Target median
  below ~0.35 with under ~15% of frames above 0.5 over a full-length soak.

**Do not report mean wavenumber.** It drifts as a launch transient decays and says nothing
about the pattern; it produced a false "scale ratchet" finding during the spike.

Measured on the spike at the shipping configuration: median S 0.31, p90 0.50, max 0.71, 11% of
frames above 0.5. With a looser re-seed: median 0.37, max 0.98, 37% above 0.5. Unmitigated: S
climbs monotonically to 0.99 and stays.

## Audio routing notes

- chroma interval (two strongest pitch classes, adjacent excluded) → drive frequency ratio → pattern symmetry. Structural, with dwell.
- `bassRel` → drive amplitude → instability threshold. Capped, not scaled.
- `trebRel` → specular glint gain. Render-side.
- spectral centroid → film thickness → interference colour centre.

## Provenance

Curated by: Matt (2026-09-09). Frames from `docs/presets/faraday_spike/`, shipping
configuration. Not AI-generated; the D-065 `_AIGEN` carve-out does not apply.
Physics reference: Edwards & Fauve (1994) for the two-frequency route to superlattices and
quasipatterns.
