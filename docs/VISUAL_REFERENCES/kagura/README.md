# Visual References — Kagura

**Family:** dancer
**Render pipeline:** feedback, particles (a `ParticleGeometry` conformer; KAGURA_DESIGN §8)
**Rubric:** lightweight — stylized point-light figure (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-09-25, port anchors from the KAG.0 spike films whose look (B) Matt chose

## Reference images

These are **source-render anchors, not the certification set.** Kagura is a port of the spike's look B,
which Matt picked from these films (KAG.0, README §3–§5). KAG.2's still sheet compares the build against
them for faithfulness to the approved look. The curated external set (point-light displays, light painting)
lands at KAG.4 per KAGURA_DESIGN §11.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_twist_point_light_trails.png` | The approved look: 15 warm-white points on near-black, each dragging a short amber trail; arms swing wide, feet stay planted, the figure reads as a person at once. Twist on Billie Jean (117 BPM), spike `final_b/mid_billie_jean_117bpm_twist.mp4` at 24 s. |
| `02_macro_sway_fallback.png` | The sway fallback (irregular grid / cold start): the same figure, near-still, trails barely visible. Calm, not frozen. Spike `final/irregular_pyramid_song_sway.mp4` at 8 s. |
| `03_anti_travelling_streak_smear.png` | NOT this — a travelling dance (salsa) under the same trails: trails tangle into a vertical streak and the body stops reading. Why the library is in-place dances only. Spike `final_c/mid_billie_jean_117bpm_salsa_fpsfixed.mp4` at 8 s. |

## Stylization contract

- [ ] **Color modulation:** none on the beat. Points warm white (`255, 236, 214`), trails amber (`255, 170, 110`), ground `4, 5, 9`. Luminance stays steady (D-157): the beat moves the pose, it never flashes.
- [ ] **Audio coverage:** the dance's pulse (for the twist, each hip-turn extreme) lands on the cached grid's beats; the figure is always moving while the music plays.
- [ ] **Readability at silence:** the sway — slow, calm, never frozen (a frozen human reads as a dropped frame).
- [ ] **Readability at peak energy:** still one legible human figure; trails fade in 0.4 s, so the body never dissolves into streaks.

## Anti-references

- Trails that smear the body into streaks (a travelling dancer, or trails that fade per frame instead of per second).
- A figure that freezes.
- Anything that brightens or flashes on the beat.
- An edge-on figure (the macarena side-on, before `face_camera`).

## Audio routing notes

- Grid beat position → the time-warp (the twist's hip-turns pinned to beats), KAGURA_DESIGN §5.
- Irregular grid or no lock yet (streaming cold start) → the sway, §3a / §7.

## Provenance

Curated by: Claude, from the Matt-approved KAG.0 spike films (look B, 2026-09-24).
Image sources: first-party renders of CMU Graphics Lab Motion Capture Database trials (docs/CREDITS.md); spike films in `~/Documents/uzume_spikes/kagura/` (outside git, D-211).
