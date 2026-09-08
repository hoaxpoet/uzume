# Visual References — Alfvén

**Family:** hypnotic
**Render pipeline:** staged (persistent + iterated stages — new engine surface, ALFVEN.1)
**Rubric:** lightweight — 2D field preset, Plasma / Waveform class (Matt's call, 2026-09-08).
Detail cascade, 3-material count and triplanar are inapplicable by design: the flatness
of the field *is* the concept, per the oil-wheel target.
**Last curated:** 2026-09-08 by Matt (concept + look approved from the `so_what.m4a` film)

---

## PROVENANCE CAVEAT — read this before trusting any image below

These references are **not** curated photographs or third-party art. They are frames from
the CPU look-spike built during concept work (`docs/presets/alfven_spike/`), a
**pseudo-spectral** 2D MHD solver. The shipping preset will use a **GPU Jacobi projection**,
which is a *different numerical scheme* and materially more diffusive.

**What that means for every trait below:** the references are a **target for composition,
palette, contrast and motion character**. They are NOT a fidelity target for filament
*sharpness*. A GPU render whose seams are softer than these frames is not automatically a
FAIL — it is the expected difference between the schemes, and the ALFVEN.1 closeout is where
that gap gets measured and either accepted or escalated. Do not spend tuning rounds chasing
spectral sharpness on a projection solver (that is the FA #64 trap).

Source track for every frame: `UzumeEngine/Tests/Fixtures/tempo/so_what.m4a` (Miles Davis,
"So What"), 24 s, 24 fps, N=256. Chain health: n/a — this is not a capture-path render.

## Reference images

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_braided_lobes.png` | **Composition.** Broad opposed-colour lobes filling the frame, 3–6 across the short side, separated by thin bright seams. Never a regular grid; never radially symmetric. This is the whole-frame read. |
| `02_meso_reconnection_seam.png` | **The subject.** Where two lobes press together the seam thins to a bright filament and pinches. This — not the lobes — is what the eye should land on. Seam width ≈ 2–5 px at 1080p; it must stay a *line*, not a glow blob. |
| `03_micro_seam_bloom.png` | **Seam core.** The hot core desaturates toward white while the shoulder keeps full chroma. TRUST the value falloff; do NOT trust the exact hue here — hue drifts with the track (see 04). |
| `04_palette_opponent_drift.png` | **Palette.** Left = early (acid green ↔ violet), right = late (magenta ↔ teal). Two hues in opposition about a centre that drifts slowly with spectral centroid. Chroma stays high throughout — this is a saturated preset by design. |
| `05_atmosphere_relaxed_state.png` | **Silence / low-drive state (D-037).** Two or three broad slow lobes, still fully coloured, seams soft and few. This is what silence must look like: calm, never black, never flat grey. |
| `06_anti_static_quilt.png` | **NOT this.** The condensate failure: a regular quilted lattice of near-identical cells with frozen flow. 2D MHD inverse-cascades ⟨ψ²⟩ to box scale and ends here if left to run. If a render looks like this, the re-seed cycle is not working. |
| `07_anti_grid_speckle.png` | **NOT this.** Grid-scale hash and concentric ringing from under-resolution / insufficient spectral damping. Any fine speckle inside a lobe is a numerics bug, not detail. |
| `target_animated.gif` | **Motion target** (200 frames, 20 fps). Continuous advection; lobes stretch, shear and re-braid. No pop, no strobe, no freeze. `Scripts/motion_gate.sh` on the source sequence: 575 diffs, median 8.15, **0 spikes >3× median, 0 frozen frames**. |

## Mandatory traits checklist

- [ ] **Composition:** 3–6 opposed-colour lobes across the short side, irregular and asymmetric.
- [ ] **Seam:** a thin, bright, continuous filament at every lobe boundary; reads as a line.
- [ ] **Seam core:** desaturates toward white at peak; shoulder retains chroma.
- [ ] **Palette:** two opposed hues, high chroma, centre drifting on a seconds timescale.
- [ ] **Silence:** broad, slow, coloured, non-black (D-037).
- [ ] **Motion:** continuous advection, no pop/strobe/freeze; structure never recurs.
- [ ] **does NOT resemble** `06_anti_static_quilt` — no regular lattice, no frozen flow.
- [ ] **does NOT resemble** `07_anti_grid_speckle` — no grid hash, no concentric ringing.

## Stylization contract (substitute for the full rubric)

- **Color modulation:** hue centre from spectral centroid (seconds); luminance from |J|
  through a filmic curve with **percentile** auto-exposure, never an absolute threshold on
  AGC-normalised energy (FA #31).
- **Audio coverage:** at all times the frame must show *something* the low end is doing —
  seam density is the always-on channel. Treble adds bloom; neither may go to zero coverage.
- **Readability at silence:** `05_atmosphere_relaxed_state.png`.
- **Readability at peak energy:** `01_macro_braided_lobes.png` — dense braiding, but lobes
  must remain individually readable. If peak energy fills the frame with undifferentiated
  filament, the drive ceiling is too high.

## Anti-references

- The box-scale condensate quilt (`06`) — the known end state of any sustained drive.
- Grid-scale speckle / ringing (`07`) — numerics, never detail.
- A "scientific visualisation" read: false-colour ramps, legends, anything that looks like a
  plot. This is an oil wheel, not a figure.
- The existing `Plasma` preset's sine-interference look — Alfvén exists because that is a hack.

## Audio routing notes

- `bassDev` → forcing amplitude → seam density. The always-on channel.
- `trebRel` → seam bloom / sizzle. Render-side only.
- spectral centroid → palette hue centre. Slow.
- `barPhase01` → reconnection flash, bounded spatial footprint (D-157).
- section boundary → **re-seed**: the field dissolves and re-braids. The structural channel.

## Provenance

Curated by: Matt (2026-09-08)
Image sources: frames from the concept look-spike, `docs/presets/alfven_spike/`.
Not AI-generated; the D-065 `_AIGEN` carve-out does not apply.
Watched reference that seeded the concept: Orszag–Tang vortex via
`pmocz/constrainedtransport-python` (GPL-3, **watch-only — no code ported**).
