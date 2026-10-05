# Fiddlehead (FH) — handoff brief for a fresh session (2026-10-05)

A new scene, separate from Understory (Matt's pick): one glowing fractal fern fiddlehead that matches
Matt's reference image, unfurls with the music's section energy, sways, and shimmers on beats.

**Reference:** `docs/VISUAL_REFERENCES/fiddlehead/01_reference_matt_2026-10-05.webp`. It is an
AI/"HDR fractal art" still: a crozier whose leaflets are croziers, translucent glassy green, violet/
blue/cyan/gold iridescent rims, hundreds of bead sparkles, a warm orange glow inside the coil, a
dark bokeh garden behind.

## Matt's hard constraints (his words, this session)

- "match the image EXACTLY" — and the defining feature is **"the level of FRACTAL detail"**.
- It must render **LIVE**. A pre-rendered sequence "will NOT work, especially for streaming media".
- "Impossible" is not accepted: HDR fractal-art videos show this fidelity.
- Do research on ferns for the look and the motion (done; summary below).
- Matt's earlier answers: new scene (not Understory); unfurl **breathes with song sections** (tight in
  quiet passages, open as it builds); background = **blurred glowing ferns / bokeh**.

## Process rule (memory: feedback_dont_iterate_renders_in_view)

Matt sees and judges every render opened in the transcript. This session failed by tuning ~30
rounds in view. **Measure the reference, fit numbers, check off-screen (crops/metrics), and show
Matt exactly one side-by-side when it is a real candidate.**

## What was tried, and why it failed

| Spike | What | Matt's verdict / cause |
|---|---|---|
| FH.0–FH.1 `fiddlehead_ifs.swift` | Flexi feedback IFS (Understory's port) with curl control | First "go". Fine levels smear (resampled every frame); every copy shares one curl, so coil and open branches can't both be right |
| FH.2 (deleted) | 2D explicit recursive frond, 3 levels | "cartoon tree" |
| FH.3 `fiddlehead.swift` | Same rule; per-pixel tree walk, then 2D raster to pixel depth | Per-pixel walk hit the GPU watchdog. 2D raster: crisp, but flat, pale or mint |
| Image warp idea | Animate Matt's image via conformal spiral unroll | Not built; superseded |
| Blender pre-render | Offline path-traced sequence | **Rejected**: must be live. (Blender 5.2.2 got installed; Matt may want `brew uninstall --cask blender`.) |
| FH.4 `fiddlehead3d.swift` | **Live 3D**: botanical rule builds tube stems, cupped serrated leaf blades and bead sprites every frame; coil point light, back/key lights, thin-film iridescence, HDR bloom, 4× MSAA | Reads as a real fern. 4–20 ms GPU at 1080p. Fixed-depth recursion "killed the fractal detail". Screen-adaptive recursion (`LEAFPX` 30–60: branch until a chain is < N px, then a leaf) brought it back. Thinning the pinnae afterwards was "SO MUCH WORSE" |

**Starting point:** FH.4 with screen-adaptive recursion and the DENSE look (approx. `SIG 0.955 TURN 0.31
SIGS 0.30 LEAFPX 30 IMM 0.6 PINOPEN 0.35 VIEWH 1.4 CY 0.3 BX -0.30 BY -0.80`). Never trade density away
for legibility. Open problems:
- **Lower pinnae.** With σ = 0.955 they grow too long. Fix the ratio without thinning the detail.
- **Material.** Still matte/pale against the reference's saturated glass. It needs stronger saturation, rim iridescence on large leaves, and a hotter orange transmission inside the coil.
- **Inner coil.** It should hold broad orange-lit leaves, plus a visible spiral rachis.

## Reference measurements (frame height H)

| Feature | Measurement |
|---|---|
| Coil outer radius | ≈ 0.29 H, centred upper middle-right, about 2.5 visible turns |
| Croziers on the outer turn | about 20, so ≈ 0.31 rad of turn per link |
| Coil growth | ≈ 2.5× per turn, so σ ≈ 0.955 at that turn |
| Lower pinna length ÷ spacing | ≈ 4.5 |
| Coil-rim croziers | ≈ ⅓ the open-rule size (immature tissue) |
| Stalk below the coil | ≈ 0.6 H, thick, an S-curve rising from bottom-centre-left |
| Lower pinnae | 0.25–0.3 H long, about 15 leaflets a side, tips curled |

## Research summary (agent reports, 2026-10-05)

**Fern botany and motion**
- **Every level is a crozier.** "Just as the whole leaf is coiled in bud, so too are its subdivisions" (Vasco, Moran & Ambrose 2013, Frontiers in Plant Science 4:345). Each pinna "at first appears as its own minute fiddlehead".
- **Coil direction.** The coil curls toward the upper (adaxial) face. Pinnae flank it in two rows, curl the same way, and pack tightest at the centre. Popularly a log spiral, so curvature ∝ 1/remaining length.
- **Unfurl order.** The base straightens first and the front travels to the tip (acroscopic maturation). Each pinna starts only after the front passes its junction, as in the ABOP §5.3 delay rule `A(0)→F[+A(D)][−A(D)]FA(0)`, where young lobes have the shape the whole leaf had earlier. The coil rises as the stalk lengthens beneath it. The shape sequence is crozier → shepherd's crook → arching frond.
- **Smooth growth.** Use logistic or cubic easing (Prusinkiewicz, Hammel & Mjolsness, SIGGRAPH 93).
- **Sway.** The rachis is a tapered cantilever, stiffest at the base, so bend ∝ arc length² with a tip lag of about 0.1–0.2 s and primary sway of about 0.3–1 Hz. Add out-of-phase pinna flutter, and use 1/f noise rather than sines (Crysis vegetation, GPU Gems 3 ch. 16).
- **Colour by age.** Young tissue is pale yellow-green or bronze and most translucent; opened tissue is deeper green. Hairs and scales catch rim light on the outer coil.

**HDR fractal-art technique**
- **Escape-time fractals give spirals of spirals.** Mandelbrot Seahorse Valley at −0.7453+0.1127i (width 0.006) shows a single crozier with side croziers; Julia sets with c in the valley give similar shapes (iq "Julia – Distance" Mss3R8, MIT).
- **But they read as filigree, not a fern.** There is no stem or leaf, and changing c rearranges the shape instead of unrolling it.
- **The look recipe:** distance-estimate rims, glow 1/(1+k·d), cosine palettes on the normal angle, x/(1+x) or ACES tone mapping, 2–3× supersampling.
- **Bokeh:** knarkowicz "Bokeh Paralax" (4s2yW1) is the background technique. It was written fresh, not copied: Shadertoy's default licence is CC BY-NC-SA.

## Files (spike only — throwaway, not engine code)

- `fiddlehead3d.swift`: FH.4 live 3D (start here). `swiftc -O -swift-version 5 fiddlehead3d.swift -o fh3d; ./fh3d still <unfurl 0…1> out.png`, with environment variables as the tuning knobs.
- `fiddlehead.swift`: FH.3 2D raster. `fiddlehead_ifs.swift`: FH.1 IFS.
- Films and renders: `~/Documents/uzume_spikes/fiddlehead/`.
- The branch is cut from LOCAL `main`, which includes the unpushed Understory merge. Rebase onto `origin/main` before any engine work.
