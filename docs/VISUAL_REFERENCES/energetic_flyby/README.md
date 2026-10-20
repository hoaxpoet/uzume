# Visual References — Energetic Flyby (working name)

**Family:** fractal
**Render pipeline:** direct_fragment (single-pass ray march) + slot-6 CPU state
**Rubric:** full (gated by V.6 certification)
**Last curated:** 2026-10-19 — source chosen by Matt (*"only energetic flyby has high-definition graphics and
vibrant colors"*); frames rendered by the design seat from the verbatim source.

## Reference images

The source **is** the reference: frames 01–04 are renders of Kali's shader, transcribed verbatim
(`docs/presets/energetic_flyby_spike/energetic_flyby_kali.glsl`), at 1280×720 with Mesa llvmpipe. They are
in-engine-equivalent captures of the working reference, not photographs, and not interpretations.

| File | Annotation (what to learn from this image) |
|---|---|
| `01_macro_shell_tunnel.jpg` (**HERO**, t = 3.0 s) | The macro read: a tunnel of curved, glassy, perforated shells receding to a lit core, the spiked sphere cluster at the centre, shells overlapping at many depths at once |
| `02_meso_sphere_cluster.jpg` (t = 7.0 s) | The sphere cluster: dark spiked shells over a bright core, light rods radiating from it, neon streaks crossing the frame |
| `03_lighting_neon_glow.jpg` (t = 12.5 s) | The light: saturated pink/violet/orange glow, a white-hot centre that does **not** clip the whole frame, perforation holes carrying Kali's fractal texture in gold/teal |
| `04_palette_jewel_spectrum.jpg` (t = 18.0 s) | The palette range: deep blue/violet shells, red-orange edges, small jewel-coloured holes; contrast between dark shell interiors and lit rims |
| `05_anti_whole_frame_whiteout.jpg` | **NOT this.** A spike frame (round 2, frame 487) where a spinning light rod passed through the camera and the glow saturated every pixel for one frame. A one-frame white-out is a photosensitivity failure and a visible pop |

## Mandatory traits

- [ ] **Faithful to the source:** at matched time and with music frozen to the source's behaviour (EFB.1 task 1's
      faithful mode), a still matches 01–04 in composition, palette and light. Kali's algorithm and constants are
      kept; adaptations are bindings only (time, resolution, y-flip, aspect) plus the music drivers and the
      photosensitivity fix in the design doc §3–§5.
- [ ] **Detail cascade:** macro = shell tunnel and the sphere cluster; meso = shell curvature, overlapping depth,
      rods; micro = perforations and Kali's fractal texture inside them; specular = lit rims and the white-hot core.
- [ ] **Audio reactivity:** downbeat burst + colour turn from the sphere cluster (barPhase01 wrap), energy →
      speed + glow floor (spectralFlux, self-normalised), bass → sphere spin (bassDev, self-normalised). No stems.
- [ ] **Silence fallback:** the flight continues at its floor speed; the frame is never black (D-037).
- [ ] **Continuous camera:** no holds, no cuts, no resets (Matt, 2026-10-19).
- [ ] **Performance ceiling:** set from EFB.1's Release measurement at 1080p (design doc §7).
- [ ] **Hero reference image:** `01_macro_shell_tunnel.jpg`.

## Anti-references (failure modes specific to this scene)

- A whole-frame brightness pulse on the beat (spike rounds 1–3 had one; D-157).
- A one-frame white-out when a light rod passes through the camera (`05`).
- Camera holds, jump cuts or resets (Kali's 5-second park; Matt rejected it).
- Pulses on every beat (the round-1/2 blind A/B failure: on steady music a half-beat slip looked equally "in sync").
- Anything added to the look: extra fog, bloom, colour grading or geometry Kali did not write (FA #65, the Aurora
  Veil lesson).

## Audio routing notes

- The downbeat is the event; between downbeats, energy and bass move continuously (design doc §2–§3).
- Deviation/self-normalised primitives only (D-026, FA #31).

## Provenance

Curated by: Matt chose the source (Shadertoy `csjGDD`, Kali, 2022); the design seat rendered 01–04 from the
verbatim transcription and 05 from spike round 2.
Licence of the source: CC BY-NC-SA 3.0 (Shadertoy default; no header in the source). These frames are renders of
that work and carry the same terms.
