# VQ.0 shader loop audit (2026-10-22)

**Why.** A single command buffer that runs for seconds freezes the whole desktop through the shared
WindowServer, and no governor can interrupt it (the governor sees GPU time 3–5 frames late). So every
loop in every shader must have a trip count bounded at compile time: a constant, `min(uniform, CONST)`,
or a bound the loop's own annotation names (`// loop-bound: <bound> — <why>`). Prevention, not reaction
(D-264; program plan §4 "Stability").

**Rule and gate.** `Scripts/check_shader_loop_bounds.sh` (CI fast-gate + `closeout_evidence.sh` step 4b)
strips comments, finds every `for` / `while`, and fails on any loop whose condition does not compare against
an integer literal, a compile-time constant (`constant` / `constexpr` / `#define` / file-scope `const`, or a
function-local `const` whose initialiser is itself constant) or `min(x, CONST)` — unless annotated. A
function-local `const int n = u.count` does NOT count (negative control: a probe with that loop and a
`u.count` loop fails the script). `--list` prints this table's raw form.

**What VQ.0 changed.** Only bounds that cannot change the image: each cap sits above the largest value
the loop ever reaches (all callers of the noise/volume helpers pass literals ≤ 6; Gossamer's `waves[32]`;
Alfvén's `kAlfvenMaxFFT` threadgroup buffer and `seedK` ≤ 3 / blur radius ≤ 21; Fiddlehead's 768 spine
samples, ≤ 2 × 127 children per state, 20 states, 32 pulses; Ferrofluid's 16 cell slots; Stave's 8 bands).
`PresetRegressionTests` (105 cases) and `GoldenSessionTests` are unchanged.

**Left for VQ.5: 0 unbounded loops.** `Presets/Shaders/Understory.metal` (uncertified; the UND.* programme
owns it, so VQ.0 does not touch it) is exempt from the script by name. Its loops are all bounded — the
three that the script cannot prove (lines 107, 209, 582) loop to `count = min(field.header.frond_count,
kUnderstoryMaxFronds)` — but carry no annotation; whoever next edits that file should add
`// loop-bound: kUnderstoryMaxFronds` to each and drop the exemption.

## Every loop

Totals: **121 loops** in 43 files (Understory.metal excluded, below) — 108 constant-bound, 13 annotated, **0 unbounded**. VQ.0 changed 23 loop conditions (a cap above the largest value reached) and annotated 13.

### `Presets/Shaders/AuroraVeil.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 103 | `for (int i = 0; i < 5; i++)` | `i < 5` | — |
| 134 | `for (int i = 0; i < 50; i++)` | `i < 50` | — |
| 159 | `for (int i = 0; i < 4; i++)` | `i < 4` | — |

### `Presets/Shaders/DragonBloom.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 78 | `for (int i = 0; i < kSamples; i++)` | `i < kSamples` | — |

### `Presets/Shaders/EnergeticFlyby.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 100 | `for (int i = 0; i < 7; i++)` | `i < 7` | — |
| 136 | `for (int i = 0; i < 6; i++)` | `i < 6` | — |
| 163 | `for (int i = 0; i < 200; i++)` | `i < 200` | — |

### `Presets/Shaders/FataMorgana.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 377 | `for (int dy = -2; dy <= 2; dy++)` | `dy <= 2` | — |
| 378 | `for (int dx = -2; dx <= 2; dx++)` | `dx <= 2` | — |

### `Presets/Shaders/FerrofluidOcean.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 391 | `for (int i = 0; i < 4; i++)` | `i < 4` | — |

### `Presets/Shaders/Fireflies.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 88 | `for (int o = 0; o < min(octaves, 8); o++)` | `o < min(octaves, 8)` | fixed |
| 133 | `for (int n = -1; n <= 1; n++)` | `n <= 1` | — |
| 199 | `for (int k = 0; k < 3; k++)` | `k < 3` | — |

### `Presets/Shaders/Floret.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 237 | `for (int k = 0; k < 4; ++k)` | `k < 4` | — |

### `Presets/Shaders/FractalTree.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 822 | `while (cur > 0u && leaf_depth < 6)` | 6 — leaf_depth < 6 | annotated |
| 941 | `for (int k = leaf_depth - 1; k >= 0; k--)` | 6 — leaf_depth ≤ 6 (the ancestry walk above) | annotated |

### `Presets/Shaders/Gossamer.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 198 | `for (int i = 0; i < kSpokeCount; i++)` | `i < kSpokeCount` | — |
| 377 | `for (uint i = 0; i < min(gState.wave_count, 32u); i++)` | `i < min(gState.wave_count, 32u)` | fixed |
| 571 | `for (uint i = 0; i < min(gState.wave_count, 32u); i++)` | `i < min(gState.wave_count, 32u)` | fixed |
| 594 | `for (int c = 0; c < 3; c += 2)` | `c < 3` | — |

### `Presets/Shaders/Membrane.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 93 | `for (int i = 0; i < 4; i++)` | `i < 4` | — |

### `Presets/Shaders/Murmuration.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 32 | `for (int i = 0; i < min(octaves, 8); i++)` | `i < min(octaves, 8)` | fixed |

### `Presets/Shaders/Nacre.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 339 | `for (int k = 0; k < 4; ++k)` | `k < 4` | — |

### `Presets/Shaders/Nimbus.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 466 | `for (int i = 0; i < kNimbusSteps; i++)` | `i < kNimbusSteps` | — |
| 478 | `for (int j = 1; j <= kNimbusShadowN; j++)` | `j <= kNimbusShadowN` | — |

### `Presets/Shaders/ShaderUtilities.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 105 | `for (int i = 0; i < min(octaves, 8); i++)` | `i < min(octaves, 8)` | fixed |

### `Presets/Shaders/Skein.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 157 | `for (int i = 0; i < 4; ++i)` | `i < 4` | — |
| 265 | `for (int i = 1; i < n; ++i)` | kSkeinMaxBreaks — n = min(breakCount, kSkeinMaxBreaks) | annotated |
| 471 | `for (int k = 1; k <= kSkeinTailFrames; ++k)` | `k <= kSkeinTailFrames` | — |
| 513 | `for (int b = 0; b < nB; ++b)` | kSkeinMaxBursts — nB = min(burstCount, kSkeinMaxBursts) | annotated |
| 576 | `for (int l = 0; l < 3; ++l)` | `l < 3` | — |
| 594 | `for (int sIdx = 0; sIdx < nStreak; ++sIdx)` | 3 — nStreak = 1 + two bools | annotated |
| 629 | `for (int n = 0; n < nDrop; ++n)` | 46 — nDrop = int(mix(46, 13, visc)), visc clamped to [0, 1] | annotated |

### `Presets/Shaders/SpectralCartograph.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 200 | `for (int age = 0; age < kHistLen; ++age)` | `age < kHistLen` | — |
| 285 | `for (int ti = 0; ti < kBeatTimesCount; ++ti)` | `ti < kBeatTimesCount` | — |
| 297 | `for (int di = 0; di < kDownbeatTimesCount; ++di)` | `di < kDownbeatTimesCount` | — |

### `Presets/Shaders/StagedSandbox.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 50 | `for (int i = 0; i < 3; i++)` | `i < 3` | — |

### `Presets/Shaders/Utilities/Geometry/RayMarch.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 78 | `for (int i = 0; i < min(maxSteps, 512) && t < tMax; i++)` | `i < min(maxSteps, 512) && t < tMax` | fixed |
| 128 | `for (int i = 0; i < 32 && t < tMax; i++)` | `i < 32 && t < tMax` | — |
| 144 | `for (int i = 1; i <= 5; i++)` | `i <= 5` | — |

### `Presets/Shaders/Utilities/Geometry/SDFPrimitives.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 397 | `for (int i = 0; i < n; i++)` | 8 — n = min(iters, 8) above | annotated |

### `Presets/Shaders/Utilities/Noise/FBM.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 28 | `for (int i = 0; i < 4; ++i)` | `i < 4` | — |
| 51 | `for (int i = 0; i < 8; ++i)` | `i < 8` | — |
| 73 | `for (int i = 0; i < 12; ++i)` | `i < 12` | — |

### `Presets/Shaders/Utilities/Noise/RidgedMultifractal.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 19 | `for (int i = 0; i < 6; ++i)` | `i < 6` | — |

### `Presets/Shaders/Utilities/Noise/Worley.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 25 | `for (int y = -1; y <= 1; y++)` | `y <= 1` | — |
| 26 | `for (int x = -1; x <= 1; x++)` | `x <= 1` | — |
| 52 | `for (int z = -1; z <= 1; z++)` | `z <= 1` | — |
| 53 | `for (int y = -1; y <= 1; y++)` | `y <= 1` | — |
| 54 | `for (int x = -1; x <= 1; x++)` | `x <= 1` | — |

### `Presets/Shaders/Utilities/PBR/POM.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 51 | `for (int i = 0; i < linear_steps; i++)` | `i < linear_steps` | — |
| 66 | `for (int i = 0; i < binary_steps; i++)` | `i < binary_steps` | — |
| 110 | `for (int i = 1; i <= shadow_steps; i++)` | `i <= shadow_steps` | — |

### `Presets/Shaders/Utilities/Texture/Voronoi.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 61 | `for (int dy = -1; dy <= 1; dy++)` | `dy <= 1` | — |
| 62 | `for (int dx = -1; dx <= 1; dx++)` | `dx <= 1` | — |
| 105 | `for (int dy = -1; dy <= 1; dy++)` | `dy <= 1` | — |
| 106 | `for (int dx = -1; dx <= 1; dx++)` | `dx <= 1` | — |
| 126 | `for (int dz = -1; dz <= 1; dz++)` | `dz <= 1` | — |
| 127 | `for (int dy = -1; dy <= 1; dy++)` | `dy <= 1` | — |
| 128 | `for (int dx = -1; dx <= 1; dx++)` | `dx <= 1` | — |

### `Presets/Shaders/Utilities/Volume/Caustics.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 29 | `for (int dy = -1; dy <= 1; dy++)` | `dy <= 1` | — |
| 30 | `for (int dx = -1; dx <= 1; dx++)` | `dx <= 1` | — |

### `Presets/Shaders/Utilities/Volume/Clouds.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 81 | `for (int i = 1; i <= 3; i++)` | `i <= 3` | — |
| 105 | `for (int i = 0; i < min(steps, 128); i++)` | `i < min(steps, 128)` | fixed |

### `Presets/Shaders/Utilities/Volume/LightShafts.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 72 | `for (int i = 0; i < min(steps, 64); i++)` | `i < min(steps, 64)` | fixed |

### `Presets/Shaders/Utilities/Volume/ParticipatingMedia.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 59 | `for (int i = 0; i < min(octaves, 8); i++)` | `i < min(octaves, 8)` | fixed |

### `Presets/Shaders/Waveform.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 15 | `for (int i = 0; i < FFT_BIN_COUNT; i++)` | `i < FFT_BIN_COUNT` | — |
| 37 | `for (int i = 0; i < BINS_PER_BAR; i++)` | `i < BINS_PER_BAR` | — |

### `Renderer/Shaders/AlfvenSolver.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 46 | `for (uint i = tid; i < min(n, kAlfvenMaxFFT); i += tcount)` | `i < min(n, kAlfvenMaxFFT)` | fixed |
| 57 | `for (uint len = 2; len <= min(n, kAlfvenMaxFFT); len <<= 1)` | `len <= min(n, kAlfvenMaxFFT)` | fixed |
| 90 | `for (uint i = tid; i < min(n, kAlfvenMaxFFT); i += tcount)` | `i < min(n, kAlfvenMaxFFT)` | fixed |
| 98 | `for (uint i = tid; i < min(n, kAlfvenMaxFFT); i += tcount)` | `i < min(n, kAlfvenMaxFFT)` | fixed |
| 115 | `for (uint i = tid; i < min(n, kAlfvenMaxFFT); i += tcount)` | `i < min(n, kAlfvenMaxFFT)` | fixed |
| 123 | `for (uint i = tid; i < min(n, kAlfvenMaxFFT); i += tcount)` | `i < min(n, kAlfvenMaxFFT)` | fixed |
| 181 | `for (int m = -km; m <= km; ++m)` | 129 — km = min(kmax, 64) | annotated |
| 182 | `for (int nn = 0; nn <= km; ++nn)` | 129 — km = min(kmax, 64) | annotated |
| 548 | `for (int i = -radius; i <= radius; ++i)` | 65 — radius = min(…, 32) | annotated |

### `Renderer/Shaders/CymaticSand.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 160 | `for (int dy = -1; dy <= 1; ++dy)` | `dy <= 1` | — |
| 161 | `for (int dx = -1; dx <= 1; ++dx)` | `dx <= 1` | — |

### `Renderer/Shaders/FerrofluidParticles.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 176 | `for (int dy = -1; dy <= 1; dy++)` | `dy <= 1` | — |
| 179 | `for (int dx = -1; dx <= 1; dx++)` | `dx <= 1` | — |
| 184 | `for (uint i = 0; i < min(count, 64u); i++)` | `i < min(count, 64u)` | fixed |

### `Renderer/Shaders/FiddleheadFern.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 68 | `for (int i = 0; i < min(ns, 1024) - 1; i++)` | `i < min(ns, 1024) - 1` | fixed |
| 92 | `for (int j = (st == 0 ? 0 : j0); j <= min(j1, 63); j++)` | `j <= min(j1, 63)` | fixed |
| 105 | `for (int k = 0; k < min(nch, 256); k++)` | `k < min(nch, 256)` | fixed |
| 120 | `for (int k = 0; k < min(nch, 256); k++)` | `k < min(nch, 256)` | fixed |
| 164 | `while (sp > 0 && budget-- > 0)` | kFernBudget — budget = kFernBudget | annotated |
| 199 | `for (int kk = lo; kk <= min(hi, 255); kk++)` | `kk <= min(hi, 255)` | fixed |
| 264 | `for (int i = 0; i < min(np, 32); i++)` | `i < min(np, 32)` | fixed |
| 304 | `for (int j = -1; j <= 1; j++)` | `j <= 1` | — |
| 304 | `for (int i = -1; i <= 1; i++)` | `i <= 1` | — |
| 318 | `for (int j = -1; j <= 1; j++)` | `j <= 1` | — |
| 318 | `for (int i = -1; i <= 1; i++)` | `i <= 1` | — |
| 331 | `for (int j = 0; j < 4; j++)` | `j < 4` | — |
| 331 | `for (int i = 0; i < 4; i++)` | `i < 4` | — |
| 342 | `for (int k = -24; k <= 24; k++)` | `k <= 24` | — |

### `Renderer/Shaders/IBL.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 175 | `for (uint i = 0u; i < SAMPLES; i++)` | `i < SAMPLES` | — |
| 225 | `for (uint i = 0u; i < SAMPLES; i++)` | `i < SAMPLES` | — |
| 270 | `for (uint i = 0u; i < SAMPLES; i++)` | `i < SAMPLES` | — |

### `Renderer/Shaders/MeniscusSurface.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 244 | `for (int i = 0; i < 4; ++i)` | `i < 4` | — |

### `Renderer/Shaders/MitosisGen2.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 57 | `for (int i = 0; i < 5; i++)` | `i < 5` | — |
| 62 | `for (int i = 0; i < 4; i++)` | `i < 4` | — |
| 160 | `for (uint i = 0; i < n; i++)` | 96 — n = min(cellCount, 96u) | annotated |

### `Renderer/Shaders/NoiseGen.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 77 | `for (int y = -1; y <= 1; y++)` | `y <= 1` | — |
| 78 | `for (int x = -1; x <= 1; x++)` | `x <= 1` | — |
| 100 | `for (int z = -1; z <= 1; z++)` | `z <= 1` | — |
| 101 | `for (int y = -1; y <= 1; y++)` | `y <= 1` | — |
| 102 | `for (int x = -1; x <= 1; x++)` | `x <= 1` | — |
| 128 | `for (int i = 0; i < 4; i++)` | `i < 4` | — |
| 140 | `for (int i = 0; i < 3; i++)` | `i < 3` | — |

### `Renderer/Shaders/Physarum.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 161 | `for (int dy = -1; dy <= 1; ++dy)` | `dy <= 1` | — |
| 162 | `for (int dx = -1; dx <= 1; ++dx)` | `dx <= 1` | — |

### `Renderer/Shaders/PostProcess.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 57 | `for (int i = 1; i < 5; i++)` | `i < 5` | — |
| 76 | `for (int i = 1; i < 5; i++)` | `i < 5` | — |

### `Renderer/Shaders/RayMarch.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 952 | `for (int i = 1; i <= kSteps; i++)` | `i <= kSteps` | — |
| 1240 | `for (int li = 0; li < lightCount; ++li)` | 4 — lightCount = clamp(…, 1, 4) | annotated |

### `Renderer/Shaders/RicercarEcho.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 164 | `for (int o = 0; o < 4; ++o)` | `o < 4` | — |
| 194 | `for (int i = 0; i < 4; ++i)` | `i < 4` | — |

### `Renderer/Shaders/StaveTrace.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 52 | `for (int b = 0; b < min(u.bandCount, 16); ++b)` | `b < min(u.bandCount, 16)` | fixed |

### `Renderer/Shaders/Waveform.metal`

| Line | Loop | Bound | VQ.0 |
|---|---|---|---|
| 18 | `for (int i = 0; i < FFT_BIN_COUNT; i++)` | `i < FFT_BIN_COUNT` | — |
| 41 | `for (int i = 0; i < BINS_PER_BAR; i++)` | `i < BINS_PER_BAR` | — |
