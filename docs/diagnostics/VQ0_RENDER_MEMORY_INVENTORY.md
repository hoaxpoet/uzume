# VQ.0 render-memory inventory (2026-10-22)

**Build:** Release. **Machine:** Apple M2 Pro Mac mini, 16 GPU cores, 16 GB, `recommendedMaxWorkingSetSize`
12,124 MB. **How:** the app's real `applyPreset` (developer env `UZUME_RENDER_INVENTORY`, `RenderSoakDriver`):
every certified scene this GPU can run (tier exclusions ignored, so Alfvén — tier-2 only — is measured), each at
1920×1080, 2560×1440, 3840×2160 with this Mac's BR.6b cap (2560×1440 render canvas) and 3840×2160 uncapped (what an
M3/M4 allocates); 120 frames per size; GPU idle; then the budget's live labelled targets + reservations and
`device.currentAllocatedSize`. Scene-major (a scene's four sizes back to back). Track: *Dance Yrself Clean* from
the stem cache.

**Gate (done-when): labelled sum matches Metal's own delta within 10 % per scene — met, all 29 within ±2 %.** The
check compares growth from 1080p to uncapped 4K, where fixed-size allocations cancel. "Charged" includes the
drawable pool (3 drawables, estimated with `heapTextureSizeAndAlign`): 24.3 MB at 1080p, 43.9 MB at 1440p, 97.1 MB
at 4K — the floor every scene shows.

**Ceiling (D-264).** Largest set at 4K uncapped: **Ferrofluid Ocean and Lumen Mosaic, 354.9 MB** →
`largestCertified4KSetBytes = 372,113,408`. **A reconstructing scene is larger:** MFX.2's path at 4K out (internal
2560×1440) holds 572 MiB — the MetalFX temporal scaler alone 322–356 MB (its `currentAllocatedSize` delta), plus its
targets and the pool (`reconstructing4KSetBytes`; no certified scene reconstructs yet — EFB.4 is first). Ceiling =
min(572 × 1.5 = 858 MiB, 15 % RAM, 25 % working set) = **858 MiB on
every Mac from 8 GB** (15 % RAM / 25 % working set: 8 GB 1,229 / ~1,370–1,520 MiB; 16 GB 2,458 / 3,031 MiB;
36 GB 5,530 / ~6,820 MiB — working sets other than this Mac's estimated at 0.67–0.74 × RAM; the measured set binds
everywhere).

## What the first runs found (fixed in this increment)

1. **~350 MB of dead targets at 4K.** The app caches the Kagura, Ricercar and Fiddlehead geometries across scenes;
   they kept their display-size targets after their scene left (Kagura 193 MB, Ricercar 128 MB, Fiddlehead 27 MB
   at 4K), and the direct half-res target outlived its scene (8 MB). The first inventory charged 447 MB to scenes
   with no targets of their own (Fractal Tree, Fireflies) and 704.8 MB to Ferrofluid Ocean. Now
   `ParticleGeometry.releaseRenderTargets()` runs on detach and the half-res target goes when the scale returns to 1.
2. **Storage.** Before: the feedback pair, the post-process scene/bloom and the ray-march G-buffer + lit were
   `.shared` (23 targets in the first run's 4K list). After: every GPU-only target is `.private` (Apple GPUs compress
   private render targets losslessly). **Left `.shared`, and why:** persistent staged state (the non-finite watchdog
   reads it on the CPU — no certified scene uses it at 4K today); under XCTest, every target the suites read back
   (`RenderTargetBudget.cpuReadableTargets`; `UZUME_PRIVATE_TARGETS=1` forces production storage). Not size-scaled,
   so outside the budget and unchanged: `AlfvenSolver` grids (CPU readback), `DynamicTextOverlay`, noise / IBL
   textures. **`.memoryless`:** no target qualifies — every one is sampled by a later pass.
3. **The BR.6b cap.** A cap change now re-commits the size-scaled set like a resize (the inventory flips it; in
   production it is set once).

## Inventory

| Scene | Charged MB @ 1920×1080 | Charged MB @ 2560×1440 | Charged MB @ 3840×2160 (this Mac, BR.6b cap) | Charged MB @ 3840×2160 (uncapped, M3/M4) | Metal Δ MB | Labelled Δ MB | Gap | GPU p50 ms @ 3840×2160 (uncapped, M3/M4) |
|---|---|---|---|---|---|---|---|---|
| Alfvén | 24.3 | 43.9 | 111.8 | 97.1 | 71.1 | 72.8 | -2 % | 11.42 |
| Aurora Veil | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 109.95 |
| Cymatic Resonance | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 0.94 |
| Cytokinesis | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 31.89 |
| Dragon Bloom | 48.6 | 87.8 | 155.6 | 194.2 | 144.0 | 145.7 | -1 % | 1.41 |
| Energetic Flyby | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 86.00 |
| Fata Morgana | 49.2 | 88.7 | 156.6 | 196.4 | 145.5 | 147.2 | -1 % | 3.10 |
| Ferrofluid Ocean | 88.7 | 159.0 | 226.9 | 354.9 | 264.5 | 266.2 | -1 % | 54.29 |
| Fiddlehead | 44.8 | 64.4 | 132.3 | 117.7 | 71.2 | 72.8 | -2 % | 14.45 |
| Filigree | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 1.18 |
| Fireflies | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 14.65 |
| Floret | 72.5 | 129.0 | 196.9 | 289.9 | 215.7 | 217.4 | -1 % | 6.42 |
| Fractal Tree | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 0.42 |
| Glaze | 74.0 | 131.5 | 199.4 | 295.4 | 219.6 | 221.3 | -1 % | 4.65 |
| Gossamer | 48.6 | 87.8 | 155.6 | 194.2 | 144.0 | 145.7 | -1 % | 14.59 |
| Kagura | 72.5 | 129.0 | 196.9 | 289.9 | 215.7 | 217.4 | -1 % | 1.08 |
| Lumen Mosaic | 88.7 | 159.0 | 226.9 | 354.9 | 264.5 | 266.2 | -1 % | 10.66 |
| Membrane | 40.5 | 73.1 | 141.0 | 161.9 | 119.7 | 121.4 | -1 % | 38.86 |
| Meniscus | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 0.53 |
| Mitosis | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 1.41 |
| Murmuration | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 8.81 |
| Nacre | 72.5 | 129.0 | 196.9 | 289.9 | 215.7 | 217.4 | -1 % | 4.13 |
| Nebula | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 1.78 |
| Nimbus | 26.4 | 47.7 | 115.6 | 105.2 | 77.1 | 78.8 | -2 % | 11.11 |
| Ricercar | 56.4 | 100.6 | 168.5 | 225.6 | 167.5 | 169.2 | -1 % | 6.35 |
| Skein | 48.6 | 87.8 | 155.6 | 194.2 | 144.0 | 145.7 | -1 % | 13.30 |
| Stave | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 5.39 |
| Volumetric Lithograph | 43.2 | 73.6 | 141.5 | 138.7 | 93.9 | 95.6 | -2 % | 15.93 |
| Witchlight | 24.3 | 43.9 | 111.8 | 97.1 | 71.2 | 72.8 | -2 % | 11.92 |

Largest set @ 3840×2160 (uncapped, M3/M4): **Ferrofluid Ocean**, 354.9 MB (`largestScene4KSetBytes = 372113408`).

## Targets @ 3840×2160 (uncapped, M3/M4)

| Scene | Owner | Label | Size | Format | Storage | MB |
|---|---|---|---|---|---|---|
| Dragon Bloom | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Dragon Bloom | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Dragon Bloom | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Fata Morgana | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | bgra8Unorm | private | 32.4 |
| Fata Morgana | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | bgra8Unorm | private | 32.4 |
| Fata Morgana | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | bgra8Unorm | private | 32.4 |
| Fata Morgana | mvWarp | mv_warp blur1 960×540 | 960×540 | bgra8Unorm | private | 2.1 |
| Ferrofluid Ocean | rayMarch | ray-march lit 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Ferrofluid Ocean | postProcess | post-process scene 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Ferrofluid Ocean | rayMarch | ray-march gbuffer2 albedo 3840×2160 | 3840×2160 | rgba8Unorm | private | 32.4 |
| Ferrofluid Ocean | rayMarch | ray-march gbuffer1 normal+AO 3840×2160 | 3840×2160 | rgba8Snorm | private | 32.4 |
| Ferrofluid Ocean | rayMarch | ray-march gbuffer0 depth 3840×2160 | 3840×2160 | rg16Float | private | 32.4 |
| Ferrofluid Ocean | postProcess | post-process bloom A 1920×1080 | 1920×1080 | rgba16Float | private | 16.1 |
| Ferrofluid Ocean | postProcess | post-process bloom B 1920×1080 | 1920×1080 | rgba16Float | private | 16.1 |
| Fiddlehead | particles.Fiddlehead | Fiddlehead history 1 1214×683 | 1214×683 | rgba16Float | private | 6.5 |
| Fiddlehead | particles.Fiddlehead | Fiddlehead history 0 1214×683 | 1214×683 | rgba16Float | private | 6.5 |
| Fiddlehead | particles.Fiddlehead | Fiddlehead hdr 1214×683 | 1214×683 | rgba16Float | private | 6.5 |
| Fiddlehead | particles.Fiddlehead | Fiddlehead bloom B 303×170 | 303×170 | rgba16Float | private | 0.5 |
| Fiddlehead | particles.Fiddlehead | Fiddlehead bloom A 303×170 | 303×170 | rgba16Float | private | 0.5 |
| Floret | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Floret | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Floret | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Glaze | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Glaze | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Glaze | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Glaze | mvWarp | mv_warp blur1 960×540 | 960×540 | rgba16Float | private | 4.0 |
| Glaze | mvWarp | mv_warp blur2 480×270 | 480×270 | rgba16Float | private | 1.1 |
| Glaze | mvWarp | mv_warp blur3 240×135 | 240×135 | rgba16Float | private | 0.3 |
| Gossamer | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Gossamer | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Gossamer | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Kagura | particles.Kagura | Kagura trail 0 | 3840×2160 | rgba16Float | private | 64.2 |
| Kagura | particles.Kagura | Kagura trail 1 | 3840×2160 | rgba16Float | private | 64.2 |
| Kagura | particles.Kagura | Kagura composite | 3840×2160 | rgba16Float | private | 64.2 |
| Lumen Mosaic | rayMarch | ray-march lit 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Lumen Mosaic | postProcess | post-process scene 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Lumen Mosaic | rayMarch | ray-march gbuffer1 normal+AO 3840×2160 | 3840×2160 | rgba8Snorm | private | 32.4 |
| Lumen Mosaic | rayMarch | ray-march gbuffer2 albedo 3840×2160 | 3840×2160 | rgba8Unorm | private | 32.4 |
| Lumen Mosaic | rayMarch | ray-march gbuffer0 depth 3840×2160 | 3840×2160 | rg16Float | private | 32.4 |
| Lumen Mosaic | postProcess | post-process bloom B 1920×1080 | 1920×1080 | rgba16Float | private | 16.1 |
| Lumen Mosaic | postProcess | post-process bloom A 1920×1080 | 1920×1080 | rgba16Float | private | 16.1 |
| Membrane | feedback | feedback pong 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Membrane | feedback | feedback ping 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Nacre | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Nacre | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Nacre | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Nimbus | directHalfRes | direct half-res 1920×1080 | 1920×1080 | bgra8Unorm_srgb | private | 8.1 |
| Ricercar | particles.Ricercar | Ricercar trail 0 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Ricercar | particles.Ricercar | Ricercar trail 1 3840×2160 | 3840×2160 | rgba16Float | private | 64.2 |
| Skein | mvWarp | mv_warp warp 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Skein | mvWarp | mv_warp scene 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Skein | mvWarp | mv_warp compose 3840×2160 | 3840×2160 | bgra8Unorm_srgb | private | 32.4 |
| Volumetric Lithograph | rayMarch | ray-march lit 1536×864 | 1536×864 | rgba16Float | private | 10.2 |
| Volumetric Lithograph | postProcess | post-process scene 1536×864 | 1536×864 | rgba16Float | private | 10.2 |
| Volumetric Lithograph | rayMarch | ray-march gbuffer0 depth 1536×864 | 1536×864 | rg16Float | private | 5.3 |
| Volumetric Lithograph | rayMarch | ray-march gbuffer1 normal+AO 1536×864 | 1536×864 | rgba8Snorm | private | 5.3 |
| Volumetric Lithograph | rayMarch | ray-march gbuffer2 albedo 1536×864 | 1536×864 | rgba8Unorm | private | 5.3 |
| Volumetric Lithograph | postProcess | post-process bloom B 768×432 | 768×432 | rgba16Float | private | 2.6 |
| Volumetric Lithograph | postProcess | post-process bloom A 768×432 | 768×432 | rgba16Float | private | 2.6 |
