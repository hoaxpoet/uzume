# Uzume — Audio Contract

**What a shader actually receives at render time, where it comes from, and how it differs
between the local-file and system-audio paths.**

Written at increment AUDIO.1 (2026-09-22) as a *verification* pass: no engine behaviour,
shader code, or preset sidecar was changed. Every claim below is cited to a file and line
in this repository at commit `84a5f889`.

**Amended 2026-09-22, same day**, after reading the live site rather than the increment prompt's
description of it. The site had moved: the homepage now makes an accurate stem-separation claim
(the prompt said it had been removed), the Nimbus caption had already been corrected, Nacre is no
longer published, and four captions this document never adjudicated were live. §4 reflects
**uzume.io as read on 2026-09-22**, not the prompt's snapshot. Verdicts against the code are
unchanged.

This document is the source of truth for audio claims made about Uzume anywhere — including
the public site (`hoaxpoet/uzume-site`), which owns its own copy and wording. Where this
document and a caption disagree, this document describes what the engine does.

---

## The one-line answer

**Yes — stem-separated audio reaches shader parameters at render time, on both paths.**

Per-stem features are a first-class GPU binding (`StemFeatures`, fragment `buffer(3)`, 64
floats), uploaded on every frame by every encoder that draws a preset. They are not a
planning-only signal.

The paths differ in *how* the stems get there, not *whether*:

- **Local file** — the whole file is separated during preparation; the renderer samples a
  pre-analysed series at the current playback second. **Time-aligned**, 43 Hz grid.
- **System audio (streaming)** — Open-Unmix runs live on the process tap every 2 s; the
  renderer reads a sliding window through the most recent separation. **≈2.5 s behind the
  music**, by construction.

Streaming's latency is structural, not a tuning choice: a system-audio tap only ever carries
audio that has already played ([StemFeatureSeries.swift:10](../UzumeEngine/Sources/Shared/StemFeatureSeries.swift#L10)).

---

## 1. The render-time contract

### 1.1 What is bound, per frame

Four constant structs plus three buffers and a texture set. Slot map:
[docs/ARCHITECTURE.md §GPU Contract Details](ARCHITECTURE.md#gpu-contract-details).

| Slot | Contents | Size | Struct definition (MSL / Swift) |
|---|---|---|---|
| `buffer(0)` | `FeatureVector` — full-mix analysis | 56 floats / 224 B | [Common.metal:17](../UzumeEngine/Sources/Renderer/Shaders/Common.metal#L17) / [AudioFeatures+Analyzed.swift:32](../UzumeEngine/Sources/Shared/AudioFeatures+Analyzed.swift#L32) |
| `buffer(1)` | FFT magnitudes | 512 floats | — |
| `buffer(2)` | Waveform samples | 1024 floats | — |
| `buffer(3)` | **`StemFeatures` — per-stem analysis** | 64 floats / 256 B | [Common.metal:129](../UzumeEngine/Sources/Renderer/Shaders/Common.metal#L129) / [StemFeatures.swift:27](../UzumeEngine/Sources/Shared/StemFeatures.swift#L27) |
| `buffer(4)` | `SceneUniforms` (ray-march) — camera/lights, no audio | 15 × float4 / 240 B | [Common.metal:234](../UzumeEngine/Sources/Renderer/Shaders/Common.metal#L234) / [AudioFeatures+SceneUniforms.swift:56](../UzumeEngine/Sources/Shared/AudioFeatures+SceneUniforms.swift#L56) |
| `buffer(5)` | `SpectralHistory` — 4096-float trail ring | 16 KB | — |
| `buffer(1)` (feedback pass) | `FeedbackParams` — warp/decay, not audio-derived except `beat_value` | 8 floats / 32 B | [Common.metal:114](../UzumeEngine/Sources/Renderer/Shaders/Common.metal#L114) / [AudioFeatures+Analyzed.swift:274](../UzumeEngine/Sources/Shared/AudioFeatures+Analyzed.swift#L274) |

Upload call sites (the lines that hand the bytes to Metal):

- Ray-march G-buffer pass — [RayMarchPipeline+Passes.swift:72–77](../UzumeEngine/Sources/Renderer/RayMarchPipeline+Passes.swift#L72)
- Ray-march lighting pass — [RayMarchPipeline+Passes.swift:131–134](../UzumeEngine/Sources/Renderer/RayMarchPipeline+Passes.swift#L131)
- Direct / feedback fragment pass — [RenderPipeline+FeedbackDraw.swift:97–102](../UzumeEngine/Sources/Renderer/RenderPipeline+FeedbackDraw.swift#L97) and [:128–133](../UzumeEngine/Sources/Renderer/RenderPipeline+FeedbackDraw.swift#L128)
- Mesh pass — [RenderPipeline+MeshDraw.swift:60](../UzumeEngine/Sources/Renderer/RenderPipeline+MeshDraw.swift#L60)
- `mv_warp` vertex stage — [RenderPipeline+MVWarpEncoders.swift:66–68](../UzumeEngine/Sources/Renderer/RenderPipeline+MVWarpEncoders.swift#L66)

`StemFeatures` is pushed into the pipeline by [`RenderPipeline.setStemFeatures(_:live:)`](../UzumeEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift#L223)
and snapshotted per frame from `latestStemFeatures` ([RenderPipeline.swift:236](../UzumeEngine/Sources/Renderer/RenderPipeline.swift#L236)).

### 1.2 `FeatureVector` — 56 floats, ALL full-mix

`MIRPipeline` never sees a stem: its only audio input is the FFT magnitude array from the
active source ([MIRPipeline.swift:235–250](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L235)).
**No field of `FeatureVector` is stem-derived.**

| Floats | Fields | Populated by |
|---|---|---|
| 1–12 | `bass mid treble`, `bass_att mid_att treb_att`, `sub_bass low_bass low_mid mid_high high_mid high_freq` | `BandEnergyProcessor` (AGC-normalised full-mix bands) |
| 13–16 | `beat_bass beat_mid beat_treble beat_composite` | `BeatDetector` onset pulses. **Clocks, not instrument detectors** — they fire at 132–138/min on drumless material; do not read them as "drums" |
| 17–18 | `spectral_centroid spectral_flux` | `SpectralAnalyzer` |
| 19–20 | `valence arousal` | `MoodClassifier`, pushed via `setMood` ([RenderPipeline+PresetSwitching.swift:181](../UzumeEngine/Sources/Renderer/RenderPipeline+PresetSwitching.swift#L181)) |
| 21–22 | `time delta_time` | Render loop |
| 23 | `waveform_occupancy` | `RenderPipeline` ([RenderPipeline.swift:806](../UzumeEngine/Sources/Renderer/RenderPipeline.swift#L806)) |
| 24 | `aspect_ratio` | `RenderPipeline` ([:795](../UzumeEngine/Sources/Renderer/RenderPipeline.swift#L795)) |
| 25 | `accumulated_audio_time` | `RenderPipeline` ([:811](../UzumeEngine/Sources/Renderer/RenderPipeline.swift#L811)) |
| 26–34 | `bass_rel bass_dev mid_rel mid_dev treb_rel treb_dev bass_att_rel mid_att_rel treb_att_rel` | D-026 deviation primitives, `MIRPipeline` |
| 35–38 | `beat_phase01 beats_until_next bar_phase01 beats_per_bar` | Cached `BeatGrid` + `LiveBeatDriftTracker` |
| 39 | `track_elapsed_s` | `MIRPipeline` ([:431](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L431)) |
| 40–43 | `pulse_phase01 pulse_amp01 pulse_beat_index pulse_regional_blend01` | `BeatPulseClock` (grid-anchored), `MIRPipeline` ([:603–606](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L603)) |
| 44–48 | `tonal_phase_fifths tonal_phase_thirds tonal_consonance tonal_tension harmonic_flux` | `TonalAnalyzer` over the **full-mix** chroma fold ([MIRPipeline.swift:247](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L247)) |
| 49–52 | `spectral_density spectral_density_slow spectral_surge spectral_section_ratio` | `SpectralAnalyzer` (pre-AGC ratios) |
| 53–56 | `spectral_level_rise track_hue_anchor01 transient_rise near_silent01` | `MIRPipeline` ([:432](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L432), [:479](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L479)) |

### 1.3 `StemFeatures` — 64 floats, per-stem

Four stems (`vocals`, `drums`, `bass`, `other`), from Open-Unmix.

| Floats | Fields | Source |
|---|---|---|
| 1–16 | `{vocals,drums,bass,other}_{energy,band0,band1,beat}` | `StemAnalyzer`. **Only `drums_beat` is populated** — the other three `*_beat` slots are reserved-zero |
| 17–24 | `{…}_energy_rel`, `{…}_energy_dev` | D-026 deviation primitives — the routing default |
| 25–40 | `{…}_{onset_rate,centroid,attack_ratio,energy_slope}` | `StemAnalyzer+RichMetadata` (MV-3a) |
| 41–42 | `vocals_pitch_hz`, `vocals_pitch_confidence` | YIN on the vocals stem. `0` = unvoiced or confidence < 0.6 |
| 43 | `drums_energy_dev_smoothed` | **CPU-patched per frame** — 150 ms EMA ([RenderPipeline+RayMarch.swift:243](../UzumeEngine/Sources/Renderer/RenderPipeline+RayMarch.swift#L243)) |
| 44 | `cached_bass_proportion` | **Track-scoped constant** from the preview snapshot; frozen for the track ([VisualizerEngine+Stems.swift:686](../UzumeApp/VisualizerEngine+Stems.swift#L686)) |
| 45 | `aurora_palette_phase` | **CPU-patched** — τ≈3 s EMA of a pitch/valence composite ([RenderPipeline+AudioDrivers.swift:99](../UzumeEngine/Sources/Renderer/RenderPipeline+AudioDrivers.swift#L99)) |
| 46 | `total_energy_smoothed` | **CPU-patched** — symmetric τ 2.5 s EMA of the four stem energies ([RenderPipeline+RayMarch.swift:261](../UzumeEngine/Sources/Renderer/RenderPipeline+RayMarch.swift#L261)) |
| 47 | `aurora_orbit_azimuth` | **CPU-patched** — integrated azimuth (BUG-047) |
| 48–55 | `{strings,brass,woodwinds,percussion}_activity{,_dev}` | PANNs family sweep of the preview clip, sampled by playback position (D-177). Zero when uncached |
| 56–64 | `_pad14…_pad22` | Padding to 256 B |

Floats 43, 45, 46 and 47 are **derived on the CPU in the render path and written into the
snapshot**, identically on both audio paths, regardless of where floats 1–42 came from.

**Warmup contract:** all of floats 1–42 are zero for the first ~10 s of live separation.
Presets are required to blend with `smoothstep(0.02, 0.06, totalStemEnergy)` (D-019) before
consuming any of them ([Common.metal:125](../UzumeEngine/Sources/Renderer/Shaders/Common.metal#L125)).

---

## 2. Where stem separation happens, and who consumes it

**Answer: partial — stems are consumed by BOTH the planner and the shaders, and the two
consume different products of the same separator.**

### 2.1 The separator

`StemSeparator` wraps an exported Open-Unmix model run through MPSGraph
([UzumeEngine/Sources/ML/StemSeparator.swift](../UzumeEngine/Sources/ML/StemSeparator.swift)).
Its window is fixed by the export at 440,320 mono samples ≈ 10 s; inference is measured and
logged per call (`STEM_SEPARATION` in `session.log`). There is no CoreML (D-009).

### 2.2 The three consumers

1. **Planning (offline).** `SessionPreparer.analyzePreview` separates the 30 s preview (or,
   for a local file, the decoded track), and derives a single `StemFeatures` *snapshot* plus
   a `TrackProfile.stemEnergyBalance` used by the Orchestrator's stem-affinity scoring
   ([SessionPreparer+Analysis.swift:61–148](../UzumeEngine/Sources/Session/SessionPreparer+Analysis.swift#L61)).
   It also runs a beat grid over the isolated **drums** stem.
2. **Render time, local file.** `SessionPreparer.analyzeStemSeries` sweeps the whole decoded
   file and produces a dense `StemFeatureSeries` — a full `StemFeatures` every 1024 samples
   (≈23 ms, 43 Hz) — cached to disk
   ([SessionPreparer+StemSeries.swift:61](../UzumeEngine/Sources/Session/SessionPreparer+StemSeries.swift#L61),
   called only from [LocalFilePreparationPipeline.swift:189](../UzumeEngine/Sources/Session/LocalFilePreparationPipeline.swift#L189)).
   At playback, `publishStemSeriesFrame` samples it at the current playback second **once per
   rendered frame** and calls `setStemFeatures`
   ([VisualizerEngine+Audio.swift:390–404](../UzumeApp/VisualizerEngine+Audio.swift#L390)).
3. **Render time, live.** A `DispatchSourceTimer` runs the separator on the last 10 s of
   captured audio every 2 s ([VisualizerEngine+Stems.swift:43](../UzumeApp/VisualizerEngine+Stems.swift#L43)).
   `runPerFrameStemAnalysis` then slides a 1024-sample window through that chunk at real-time
   rate and calls `setStemFeatures` ([VisualizerEngine+Audio.swift:406–464](../UzumeApp/VisualizerEngine+Audio.swift#L406)).

Consumers 2 and 3 are mutually exclusive per track. When a series is installed, live
separation is suppressed entirely (LFSTEM.2,
[VisualizerEngine+Stems.swift:218](../UzumeApp/VisualizerEngine+Stems.swift#L218)) and the
per-frame analyser stands down ([VisualizerEngine+Audio.swift:413](../UzumeApp/VisualizerEngine+Audio.swift#L413)).
The switch is *"a series exists for this track"*, never *"the source is a local file"* — a
cache miss or schema mismatch falls back to live separation on either path.

### 2.3 Latency arithmetic (live path)

Four interlocking constants ([VisualizerEngine+Stems.swift:76–122](../UzumeApp/VisualizerEngine+Stems.swift#L76)):

```
chunk          = 10.0 s   (fixed by the model export — not a lever)
period         =  2.0 s   (separation cadence)
margin         =  0.5 s
readStart      = chunk − period − margin = 7.5 s
nominal latency = chunk − readStart      = 2.5 s
```

Latency ≥ period by construction. Reducing it means more inference duty on the same GPU the
renderer draws with. This was 5.4 s until BUG-086 (2026-08-11).

---

## 3. Per-audio-path comparison

The analysis pipeline is deliberately source-agnostic: both providers call the same
`onAudioSamples` callback with the same contract
([AudioInputRouter.swift:197](../UzumeEngine/Sources/Audio/AudioInputRouter.swift#L197) for the
process tap, [:300](../UzumeEngine/Sources/Audio/AudioInputRouter.swift#L300) for local files),
and that callback feeds both the FFT and the stem sample buffer
([VisualizerEngine+Audio.swift:112–146](../UzumeApp/VisualizerEngine+Audio.swift#L112)).

| | **Local file** (`.localFilePlayback`) | **System audio** (`.systemAudio` / `.application`) |
|---|---|---|
| Audio source | `PlayheadAnalysisClock` reads the decoded file at the smoothed playhead. **No tap** since BUG087.5 ([LocalFilePlaybackProvider.swift:12](../UzumeEngine/Sources/Audio/LocalFilePlaybackProvider.swift#L12)) | `AudioHardwareCreateProcessTap` process tap |
| Preparation input | The **whole decoded track** (`wholeTrackAudio: true`) | The **30 s preview clip** |
| `FeatureVector` (all 56 floats) | Identical machinery, identical fields | Identical machinery, identical fields |
| `StemFeatures` source | **Pre-analysed `StemFeatureSeries`**, sampled by playback second | **Live Open-Unmix** on captured audio, every 2 s |
| Stem latency | **0** — the frame describes the second being heard | **≈2.5 s** |
| Stem update rate | 43 Hz grid, sampled **once per rendered frame** (~60 Hz) | Analysis-frame rate; measured at **12.8 Hz** in session `2026-08-27T16-53-29Z` (BUG-109) |
| First ~10 s of a track | Series is correct from second 0 | Stems are **zero** until the first separation lands, then the per-stem deviation EMA overswings 1.2–3.3× for ~10 s (BUG-041) |
| `cached_bass_proportion` (float 44) | From the whole-track preview snapshot | From the 30 s preview clip |
| Instrument-family floats 48–55 | From the preview PANNs sweep | From the preview PANNs sweep (identical) |
| Beat grid | Built across the whole track | Built across the 30 s preview only |
| `loudnessProfile` (drives `spectral_surge`) | Track's own distribution | Fixed band (DYN.1c) |
| GPU binding | **Identical.** Same struct, same slot, same encoders | **Identical** |

**The code that branches.** There is no `if isLocalFile` in the render path. The branch is
data-driven and sits in one place: `currentStemSeries.isEmpty`
([VisualizerEngine+Stems.swift:218](../UzumeApp/VisualizerEngine+Stems.swift#L218),
[VisualizerEngine+Audio.swift:413](../UzumeApp/VisualizerEngine+Audio.swift#L413)). The series
is installed on the cache-hit branch at
[VisualizerEngine+Stems.swift:700](../UzumeApp/VisualizerEngine+Stems.swift#L700) and is
`.empty` for every non-local path and for cache entries written before schema v10.

**Consequence for the site.** A visitor on the streaming path *does* get per-instrument
visual response. It is not absent and it is not cheap — it costs a full MPSGraph inference
every 2 s during playback. What it is, is **late**: stem-driven behaviour follows the music
by about a bar, where full-mix band energy and the beat grid are ≈0.3 s. That is a claim
about *timing*, not about *capability*.

---

## 4. Adjudication of five published captions

Verdicts are against the engine at `84a5f889`. "Needs rewording" means the visual effect is
real but the named cause is wrong.

### 4.1 Ferrofluid Ocean

> "Bass raises the spikes, the music's intensity sets the swell beneath them, and the vocal
> line moves the aurora's colour."

**Verdict: needs rewording** — clause 1 is **false**, clauses 2 and 3 are supportable.

- **"Bass raises the spikes" — FALSE.** Spike height is
  `baseline + head × pulse_amp01 × env(pulse_phase01) × mask × height(total_energy_smoothed)`
  ([FerrofluidOcean.metal:169–259](../UzumeEngine/Sources/Presets/Shaders/FerrofluidOcean.metal#L169)).
  The per-moment motion is a **four-beat grid-anchored pulse** (D-153/D-154) scaled by **total
  stem energy**, not bass. The `bass_energy_dev` term the caption describes was removed at
  FBS Stage 1 and the shader comment says so explicitly: it *"REPLACES the CSP.3.2/3.3
  `0.8 × clamp(f.bass)` term"*, whose diagnosis was that AGC-levelled bass *"barely moved"*
  (motion std 0.09 — Matt's "frozen"). Bass survives only as `cached_bass_proportion`, a
  **per-track constant** worth **≈+3 % height on Get Lucky and ≈+1 % on Superstition**
  (measured, session `2026-05-27T19-38-32Z`). That is not a bass response; it is a per-song
  posture offset. The sidecar's own machine-checked `audio_routes` block agrees — it lists no
  bass primitive at all.
  **What it actually responds to:** the beat grid (timing) and overall loudness (size).
- **"the music's intensity sets the swell" — supportable.**
  `fo_swell_scale = 0.4 + 0.6 × smoothstep(−0.5, 0.5, arousal)`
  ([FerrofluidOcean.metal:295–300](../UzumeEngine/Sources/Presets/Shaders/FerrofluidOcean.metal#L295)).
  `arousal` is the ML mood classifier's energy axis — a fair reading of "the music's intensity".
- **"the vocal line moves the aurora's colour" — supportable.** The curtain hue is
  `auroraHueStep(pitchHz: vocals_pitch_hz, pitchConfidence: vocals_pitch_confidence, valence:)`
  ([RenderPipeline+AudioDrivers.swift:99–120](../UzumeEngine/Sources/Renderer/RenderPipeline+AudioDrivers.swift#L99)).
  A confident vocal (confidence ≥ 0.7) drives hue from log-scale pitch over 80 Hz–1 kHz;
  below 0.5 it falls back to `valence`. The glide is τ≈3 s (~9 s to complete) — deliberate,
  and the reason the caption should not promise a *quick* colour response.

### 4.2 Skein

> "Each instrument in the mix owns a colour — the one carrying the moment pours the line
> while the others flick splatters across it."

**Verdict: supportable as written.** This is the most literally accurate of the five.

Four paint materials, *"one stable, well-separated colour per stem"*
([SkeinState.swift:35](../UzumeEngine/Sources/Presets/Skein/SkeinState.swift#L35)). The poured
line takes the **dominant stem's** colour by discrete argmax over smoothed per-stem energy
(`lineColR`, [:97](../UzumeEngine/Sources/Presets/Skein/SkeinState.swift#L97)), with a new
breakpoint pushed on each dominant-stem switch. Splatters fire when a stem's `*_energy_dev`
crosses its deviation threshold, rate-limited by a refractory so a busier stem flicks more
(`onsetRefractory`, [:219](../UzumeEngine/Sources/Presets/Skein/SkeinState.swift#L219)), and
each burst freezes its stem's colour at spawn. 28 declared `audio_routes`, 16 of them per-stem.

One honest caveat: "each instrument" is four Open-Unmix stems — vocals, drums, bass, other —
not individual instruments. Everything outside those three named stems lands in `other`.

### 4.3 Nimbus

**The caption below is superseded.** The live gallery now reads:

> "The beat punches through it, the music's overall energy brightens the whole body, and bass, lead
> and the rest of the mix heave it down, up and sideways."

**Verdict on the LIVE caption: supportable, with one residual mis-split.** Both faults identified
below are fixed — it says *beat*, not drums, and it names three stems for three directions in the
right order (bass→down, lead→up, the rest→sideways). The residual: it assigns brightening solely to
overall energy, but the beat is the **larger** brightness event. The shader computes
`bright = f(bloom) × (1.0 + kNimbusKickBright × kickPunch)` with `kNimbusKickBright = 0.72`
([Nimbus.metal:194](../UzumeEngine/Sources/Presets/Shaders/Nimbus.metal#L194),
[:391](../UzumeEngine/Sources/Presets/Shaders/Nimbus.metal#L391)) — a 72 % pop on top of the slow
bloom swell, and the shader calls it *"the hero beat moment"*. Accurate wording would be *"The beat
punches through it and pops its brightness, the music's overall energy blooms the whole body…"*.
Minor; the current sentence under-claims rather than over-claims.

**The superseded caption, and why it needed the change** (retained — it is the evidence trail for
BUG-138's family of drift):

> "Drums punch through it and brighten the whole body, bass and lead heave it up, down and
> sideways."

**Verdict: needed rewording** — clause 2 was close, clause 1 named the wrong signal.

- **"Drums punch through it" — wrong cause.** `kickPunch` is
  `max(smoothstep(0.82, 1.0, beat_phase01), max(beat_bass, beat_composite))`
  ([NimbusState.swift:266–269](../UzumeEngine/Sources/Presets/Nimbus/NimbusState.swift#L266)) —
  the **beat grid's anticipation ramp** with **full-mix band onsets** as the ungridded
  fallback. The drums stem is not read. `beat_*` fields are pulse clocks: they fire at
  132–138/min on every track measured, including a drumless one. On drum-led music the visual
  effect reads as a kick; on a drumless track it fires anyway.
  **Honest wording:** "the beat punches through it".
- **"bass and lead heave it up, down and sideways" — needs a third name.** Three stem
  deviations drive three directions:
  `bass_energy_dev` → **down**, `vocals_energy_dev` (lead) → **up**, `other_energy_dev` →
  **sideways** ([NimbusState.swift:277–282](../UzumeEngine/Sources/Presets/Nimbus/NimbusState.swift#L277)).
  The caption names two stems for three axes; sideways belongs to *other*.
  Also: the lobes are gated by `stemMix`, a time-since-track-start ramp that reaches full
  strength only at ~9–13 s, so on the streaming path the heave is absent for the first bars.

### 4.4 Murmuration

> "the vocal line breathes in its density."

**Verdict: supportable, with one nuance.** `vocalEnv` is a 0.5 s EMA of
`stems.vocals_energy` blended in by the D-019 warmup gate
([Murmuration3DGeometry.swift:221–225](../UzumeEngine/Sources/Renderer/Geometry/Murmuration3DGeometry.swift#L221)),
and the shader computes `density = 1.0 − vocalEnv × 0.24 − beatEnv × 0.10`, which scales the
flock's half-length, half-width and half-depth
([Murmuration3D.metal:132–135](../UzumeEngine/Sources/Renderer/Shaders/Murmuration3D.metal#L132)).

The nuance: vocals **compress** the flock (a 24 % squash at full envelope), so the breathing
is an inward tightening as the voice enters, not an expansion. "Breathes" reads either way;
if the site wants precision, "the vocal line draws it tighter" is what happens.

### 4.5 Nacre

**No longer published.** Nacre is absent from the gallery as read on 2026-09-22 — the eight scenes
listed are Cymatic Resonance, Ferrofluid Ocean, Fractal Tree, Skein, Nimbus, Nebula, Aurora Veil and
Murmuration. The verdict is retained because the caption is accurate and the preset is certified, so
it can be published as-is if Nacre returns to the page.

> "the hue is positioned on the circle of fifths, so it holds through a vamp and drifts on a
> modulation."

**Verdict: supportable as written.** `hue ← tonal_phase_fifths`, the arg of the Tonal
Interval Vector's T(5) component, consumed as a unit vector
([RenderPipeline+Nacre.swift:128](../UzumeEngine/Sources/Renderer/RenderPipeline+Nacre.swift#L128)).
Saturation is gated by `tonal_consonance`. The "holds/drifts" behaviour follows from the
representation: a vamp keeps the same chroma centroid, so the phase is stationary; a
modulation moves it by the interval's distance on the circle.

This route is **full-mix**, not stem-derived
([MIRPipeline.swift:247](../UzumeEngine/Sources/DSP/MIRPipeline.swift#L247)), which means it
is one of the few per-moment musical claims on the site that is **identical and
zero-latency on both paths** — no separator, no warmup, no 2.5 s lag.

### 4.7 The four captions this increment was not asked about

Live on the gallery on 2026-09-22, checked against each sidecar's `audio_routes` and its shader.
**All four are supportable as written.** Recorded so the site has a verdict on every published
audio claim rather than on five of nine.

| Scene | Claim | Backed by |
|---|---|---|
| **Cymatic Resonance** | *"Loudness drives how hard the plate vibrates, a beat makes the sand jump, and a shift in brightness selects a new figure — so the grains scatter and re-form on it."* | `vibration_energy ← bass, mid`; `beat_burst ← bassDev, drumsEnergyDev`; `mode_select ← spectralCentroid`. Exact. The caption *omits* a real route — `palette_hue ← tonalPhaseFifths` — which is an omission, not an error |
| **Fractal Tree** | *"It bounces on every beat and sways across the bar… Underneath it holds one size and steps to a new one when a sound lands — small in a sparse passage, full in a dense one."* | `dance_bounce ← beatPhase01`; `dance_sway ← barPhase01`; `growth_commit ← spectralLevelRise`; `growth_tier ← spectralSectionRatio`. The most precisely-worded caption on the page: *"when a sound lands"* is exactly what `spectral_level_rise` is for, and *"sparse / dense"* is exactly the density ratio |
| **Nebula** | *"The ring tightens and blooms wide as the music fills out, and the spokes flare where the frequencies land."* | `ring_reach ← bassDev, midDev, trebDev`; `core_glow ← bass, mid, treble`; `sparkle_gain ← trebDev`. ⚠ This would **not** have been supportable before PR.19, which fixed a linear bin→angle map that put **27 % of the energy in 2 % of the circle** — the spokes did not flare where the frequencies landed. Certified 2026-09-11 |
| **Aurora Veil** | *"The stars keep the beat on the downbeat, while the veil breathes with the music's intensity and its color warms with the mood."* | `star_beat_twinkle ← barPhase01 + pulseAmp01` (barPhase01 *is* the downbeat); `veil_breathe ← arousal + bassAttRel`; `mood_colour ← valence`. Reads **no stems at all** — `AuroraVeil.metal:182` is `(void)stems; // unused` — so like Nacre it is identical and zero-latency on streaming |

### 4.8 The homepage's own audio claims

Also checked, since they are the broadest claims the site makes:

- *"It pulls the music apart — drums, bass, voice, everything else — and follows each one separately,
  along with where the beats fall and how the harmony moves."* — **accurate**, and the four names
  match Open-Unmix's four stems exactly.
- *"On a local file that starts immediately; from a streaming app it takes ten or fifteen seconds,
  and works from the mix until then."* — **accurate and well-calibrated.** Live separation's timer
  first fires at +10 s and needs 10 s buffered; Nimbus's `stemMix` ramps to full over ~9–13 s; FFO's
  cold-start crossfade runs 0.5 → 14 s. *"works from the mix until then"* is exactly what the
  warmup fallbacks do (`bassAttRel` proxies, the D-019 blend).
- *"With local files, Uzume hears the whole playlist before it plays a note."* — **accurate**; the
  local path decodes and analyses the whole file, which is what makes the zero-latency series
  possible.
- Gallery: *"Every scene here is tested for steady luminance: a bounded change in brightness from
  frame to frame, with beat-locked motion confined to parts of the frame rather than thrown across
  all of it."* — **accurate, and carefully worded.** All eight published scenes are in
  `FidelityRubricTests.certifiedPresets`, and every certified preset is driven against a worst-case
  beat train and measured to the Harding / WCAG 2.3.1 limit by `PhotosensitivityCertificationTests`
  plus `MultiPassFlashHarnessTests`; the gate **fails loud** if a newly certified preset renders
  static rather than silently passing. The second clause is D-157, which is the real regional
  constraint — the one blind spot the gate documents (full-frame mean only, so a sub-region flash
  under 10 % of the mean passes) is what that clause speaks to.

### 4.6 Summary

| Caption | Verdict | Stem-dependent? | Same on streaming? |
|---|---|---|---|
| Ferrofluid Ocean | **Needs rewording** (bass clause false) | Partly (aurora hue, total energy) | Yes, +2.5 s on the stem legs |
| Skein | **Supportable** | Fully | Yes, +2.5 s |
| Nimbus (live wording) | **Supportable**; residual — the beat also brightens (+72 %) | Partly (the three lobes) | Yes, +2.5 s, and absent for the first ~10 s |
| Murmuration | **Supportable** (nuance: it tightens) | Yes | Yes, +2.5 s |
| Nacre (*not currently published*) | **Supportable** | No — full-mix | **Yes, identically** |

---

## 5. Could not be determined

Stated plainly rather than guessed:

1. **Whether the 2.5 s stem latency is perceptible to a listener in each of these five
   presets.** The arithmetic is exact and the code is unambiguous, but this increment ran no
   live session and captured no artifact. For continuous routes (Skein's line colour,
   Murmuration's density, Nimbus's lobes) a bar of lag is plausibly unnoticeable; for anything
   paired against the beat grid it is a known problem (the BUG-086 finding). **This needs a
   live A/B, not more reading.**
2. **Real-world separation quality** — how cleanly Open-Unmix isolates a given track's vocal
   or bass, and therefore how honestly "each instrument owns a colour" reads on a dense mix.
   Nothing in this repository measures it; the `stems/` WAV dump exists to be listened to, and
   note that it is **not written on the local-file path** when a series is installed
   ([VisualizerEngine+Stems.swift:174](../UzumeApp/VisualizerEngine+Stems.swift#L174)).
3. **The live path's actual stem update rate today.** The 12.8 Hz figure is from session
   `2026-08-27T16-53-29Z` (BUG-109) and predates LFSTEM.1e, which moved *series* sampling to
   the render thread. The live path was not moved with it, so 12.8 Hz is presumed still to
   apply — but it has not been re-measured since.
4. **Whether any certified preset reads a stem field that the preparation path can never
   populate.** `AudioRoutePrimitives` documents five CPU-derived `StemFeatures` fields the
   route-coverage fixture cannot exercise ([AudioRoutePrimitives.swift:14](../UzumeEngine/Sources/Presets/AudioRoutePrimitives.swift#L14));
   that gap is tracked in `QG1_REPLAY_AUDIT.md` and was not re-audited here.

---

## 6. Defect found in this repository

Investigating task 4 surfaced documentation in *this* repo asserting engine behaviour that
does not exist. Filed as **BUG-138** (`documentation-drift`, P2) in
[docs/QUALITY/KNOWN_ISSUES.md](QUALITY/KNOWN_ISSUES.md). Two instances:

1. ✅ **RESOLVED 2026-09-22 (BUG138.1).** **`FerrofluidOcean.json` `description`** claimed
   *"bass_energy_dev → spike height"*. It also carried two further retired mechanisms found while
   fixing it: the `accumulated_audio_time × arousal` aurora-drift product (removed at BUG-047) and
   the raw `vocals_pitch_hz` palette read (replaced at D-158). The field is now a description of the
   LOOK that defers to `audio_routes` and the shader header, so it is no longer a second routing
   table. Original finding: removed
   from the shader at D-153 (2026-06-09). The same sidecar's `audio_routes` block — the
   machine-checked one — is correct, so the two halves of one file disagree. This is very
   likely the origin of the published caption.
2. ⏳ **STILL OPEN.** **`ARCHITECTURE.md` §Buffer Binding Layout** and **`Common.metal:11`** both state
   `FeatureVector` is *"48 floats / 192 bytes"*. It is **56 floats / 224 bytes** (verified by
   parsing the struct). `CommonLayoutTest` gates the *layout*, not the prose describing it.

AUDIO.1 itself was read-only by design and fixed neither; **(1) was fixed the same day at
BUG138.1** on Matt's instruction. (2) and the gate that would stop this class recurring remain open —
and the obvious form of that gate is blocked: `VolumetricLithograph.json`'s description correctly
names `drums_beat` and `drums_attack_ratio` while its `audio_routes` declares neither, so a
*"named in prose ⇒ declared in routes"* rule would go red on VL immediately. See the BUG-138 entry
for the read-set-based rule that passes VL and still catches (1).
