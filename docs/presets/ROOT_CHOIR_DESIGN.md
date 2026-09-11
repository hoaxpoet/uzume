# Root Choir — Liquid Script design

## Concept

Root Choir writes luminous liquid arrows into a charcoal field. Each gesture has a readable
pointed leaf/arrow head, an enamel-hot inner body, a coloured rim, and one or more long fine
S-curves that curl behind it. Older writing keeps flowing and dissolving while new heads enter
at distributed loci. The psychedelic quality comes from persistent colour memory and continuous
non-radial deformation—not kaleidoscope symmetry or rotation.

## Musical role

Sustained `bassDev` controls how quickly the liquid field advects and curls, so existing
ribbons move continuously with the low end. `beatComposite` is accent-only: it increases the
opacity and reach of the newly written gesture without flashing or moving the whole frame.

## Layers

1. **Macro:** asynchronous luminous-arrow entrances distributed over the frame with generous but
   visible negative space.
2. **Meso:** each gesture has a pointed leaf head, a narrow body, and paired curling tendrils.
3. **Micro:** feedback resampling stretches and braids the fine ink boundary without inflating it
   into broad translucent bands.
4. **Highlight:** warm near-white enamel core inside a saturated amber/magenta/violet rim, capped
   below clipping.

## Render architecture

`direct + mv_warp`, linear `bgra8Unorm` feedback. The direct fragment writes a compact leaf head,
hot inner spine, saturated outer body, halo, and paired fine tails as one local gesture.
`mvWarpPerVertex` supplies directed wavy cross-shear with a persistent through-flow; weak local
curvature cannot overcome that directional bias and close into orbits or circular traces. The custom warp fragment applies
bounded decay and a small subtractive floor; the custom comp fragment uses a visible neutral-
charcoal ground and bounded filmic lift so negative space remains dark without becoming illegible.
No CPU state or private buffer is required.

## Inspiration and authorship discipline

Inspired by the motion of the butterchurn built-in `Martin - liquid arrows` (Martin), source
JSON SHA-256 `10c8ad8fe49bd58a9c0b2658df1677f1a001f53a2bc193434dcb91ba85066336`.
The implementation contains no transcribed source equations or shader logic. It preserves the
oracle's recognizable visual subject—luminous pointed heads pulling fine curled trails—while
diverging in palette character (jewel amber/magenta/violet), distributed composition, and the
absence of the source pentagon/central vortex.

## Review gates

- Production warp→compose→swap path over at least 96 frames.
- Non-black, no white-out, and changing frame hashes after warmup.
- Attached-session mean frame luma 0.18…0.38, clipped share <1%, near-white share <2%.
- Side-by-side reader verdict passes every required trait in the reference README.
- Real-session motion sequence inspected for rings, central convergence, stalling, and spin.
- Remains uncertified until Matt approves the live result.
