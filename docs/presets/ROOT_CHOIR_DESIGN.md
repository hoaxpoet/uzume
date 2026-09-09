# Root Choir — Liquid Script design

## Concept

Root Choir writes tapered ribbons of coloured light into a dark liquid field. Each ribbon
enters as a crisp local gesture, stretches into an S-curve, braids with older writing, and
dissolves before the canvas congeals. The psychedelic quality comes from persistent colour
memory and continuous non-radial deformation—not kaleidoscope symmetry or rotation.

## Musical role

Sustained `bassDev` controls how quickly the liquid field advects and curls, so existing
ribbons move continuously with the low end. `beatComposite` is accent-only: it increases the
opacity and reach of the newly written gesture without flashing or moving the whole frame.

## Layers

1. **Macro:** three asynchronous writing loci distributed over the frame.
2. **Meso:** each gesture has a tapered head, broad body, and curling tail.
3. **Micro:** feedback resampling stretches and braids the ink boundary.
4. **Highlight:** display-only chromatic edge pickup, capped below white.

## Render architecture

`direct + mv_warp`, linear `bgra8Unorm` feedback. The direct fragment writes transparent
seed strokes. `mvWarpPerVertex` supplies a cross-coupled sinusoidal shear field with no
radial coordinate and no rotation. The custom warp fragment applies bounded decay and a
small subtractive floor; the custom comp fragment adds edge colour over a charcoal ground.
No CPU state or private buffer is required.

## Inspiration and authorship discipline

Inspired by the motion of the butterchurn built-in `Martin - liquid arrows` (Martin), source
JSON SHA-256 `10c8ad8fe49bd58a9c0b2658df1677f1a001f53a2bc193434dcb91ba85066336`.
The implementation contains no transcribed source equations or shader logic. Divergence is
load-bearing: distributed three-hand composition, jewel palette, tapered calligraphic seed,
and no source pentagon/central vortex.

## Review gates

- Production warp→compose→swap path over at least 96 frames.
- Non-black, no white-out, and changing frame hashes after warmup.
- Real-session motion sequence inspected for rings, central convergence, stalling, and spin.
- Remains uncertified until Matt approves the live result.
