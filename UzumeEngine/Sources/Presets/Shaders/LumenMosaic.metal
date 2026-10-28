// LumenMosaic.metal — Ray march preset: vibrant backlit pattern-glass panel.
//
// The energetic-dance-partner preset: a single planar glass panel fills the
// camera frame and bleeds 50% past it on every side, so the viewer sees
// only a field of vivid stained-glass cells dancing to the music.
//
// LM.4.7 — Curated 18-palette library; per-song palette selection.
// The Orchestrator picks one of 18 hand-authored 12-colour palettes per
// song via a mood-biased Gaussian-over-distance draw (with the immediately
// previous song's palette excluded). `LumenMosaicPaletteLibrary.swift`
// holds the 18 palettes + the selection function; `LumenPatternEngine.
// setPalette(_:)` writes the drawn 12-entry payload into slot 8 at each
// track change. `lm_cell_palette` indexes into that payload via
// `idx = hash(cellHash, step, trackSeed, sectionSalt) % 12`. Replaces
// LM.4.6's uniform random RGB + LM.7's chromatic-projected per-track
// tint (both retired with this increment); closes BUG-014. The LM.3.2
// team/period beat-step ratchet upstream of the palette lookup is
// preserved verbatim. See D-LM-palette-library + D-LM-cream-rescission.
//
// LMG (2026-10-28) — stained hammered glass. Each piece is its own sheet of coloured hammered cathedral glass,
// backlit, set in slim dark-grey lead with a sheen (Matt). Inside every piece, ~10 dimples across act as small
// lenses: a dark crescent on the side facing away from the backlight, glass deepening where it is thick, glints
// in the glass's own hue so near-black glass still shows points of light. Retires LM.3.2's white frost seam and
// LM.6's per-piece dome + centre hot-spot (one big dimple per piece = painted tiles). Albedo-only, like LM.6:
// the SDF stays flat and the matID == 1 emission contract is unchanged.
//
// LM.4.6 history (superseded by LM.4.7): pure uniform random RGB per
// cell. Per Matt 2026-05-12 ("I'm giving up the fight on colors"), the
// LM.4.6 / LM.7 baseline produced statistically identical panel
// aggregates across tracks — BUG-014. LM.4.7's palette library closes
// that gap. The LM.4.5.x card-model iterations and the original LM.3.2
// IQ-cosine palette are also retired; see `git log` for the chain.
//
// Band-routed beat-driven dance (LM.3.2, preserved verbatim). Each cell is
// assigned to one of four "teams" by `hash(cell_id ^ trackSeedHash) % 100`:
//
//   - 30% bass team    — advances palette step on each bass beat
//   - 35% mid team     — advances palette step on each mid beat (the typical
//                        carrier of melody on real-music playback)
//   - 25% treble team  — advances palette step on each treble beat
//   - 10% static team  — never advances; holds its base palette colour
//                        (cells in the static team are different on each
//                        track because the team hash is XOR'd with the
//                        per-track seed)
//
// Each cell's `period ∈ {1, 2, 4, 8}` is also hashed — fast cells advance
// every team beat, slow cells hold their step for many beats. Pareto-shaped
// distribution (~37.5% period=1, 25% period=2, 25% period=4, 12.5% period=8)
// targets ~50–60% of cells visibly stepping in any given second of energetic
// music — Matt's "bubbling cauldron" register.
//
// Materials:
//   matID 1 — Pattern glass (single material, panel-wide). Albedo carries
//             backlight intensity; the lighting fragment dispatches on
//             matID == 1 (gbuf0.g) and renders an emission-dominated path
//             (gain × albedo + IBL ambient floor) instead of full
//             Cook-Torrance dielectric. See RayMarch.metal §matID dispatch.
//
// Detail cascade (LMG):
//   Macro      : sd_box panel oversized to bleed past frame (Decision G.1); a broad
//                fbm4 backlight drift across it.
//   Meso       : the pieces (Voronoi, kCellDensity) set in lead came with a sheen.
//   Micro      : hammer dimples, kDimplesPerPiece across each piece, per-piece offset.
//   Specular   : glints — focused backlight in the glass's own hue (albedo, not
//                Cook-Torrance; the matID == 1 path stays emission-dominated).
//
// Audio routing (LM.3.2):
//   - Per-cell PALETTE STEP advances on rising-edge of the cell's team's
//     beat counter (`lumen.bassCounter` / `midCounter` / `trebleCounter`).
//     Each counter is incremented by the engine on rising-edges of
//     `f.beatBass` / `f.beatMid` / `f.beatTreble`, scaled by `beatStrength`
//     (energy modulation). The shader does `step = floor(counter / period)`
//     to pin each cell to a discrete palette index that ratchets forward.
//   - Per-cell INTENSITY is uniform with a small hash-driven jitter
//     `[0.85, 1.0]` so the panel reads as vivid throughout (no dim
//     backlight gradient). A bar pulse (`f.barPhase01 ^ 8`) adds a brief
//     +30% brightness flash at each downbeat; falls back to no-pulse
//     gracefully when no BeatGrid is installed (`barPhase01` stays at 0).
//   - The four light agents (slot 8 buffer, LM.2 contract §P.4) are still
//     ticked CPU-side for ABI continuity but the `lights[i].intensity` /
//     `lights[i].colorR/G/B` fields are unused by the LM.3.2 shader. The
//     agent loop is retained as zeroed scaffolding.
//   - **LM.4 pattern engine RETIRED at LM.4.4.** The ripple/sweep accent
//     layer was deleted after the third M7 review (Matt 2026-05-11:
//     "barely noticeable ... what value is it really adding?"). The
//     wavefronts were invisible at execution-time-feasible boost levels —
//     they competed with the simultaneous bar pulse for the downbeat
//     moment and lost by area. The LM.3.2 cell-color dance (driven by
//     LM.4.3 grid-wrap counters) + the bar pulse are the entire visual
//     story now. The `LumenPattern` / `LumenPatternKind` /
//     `LumenLightAgent` structs and the `state.patterns[4]` tuple stay
//     in `LumenPatternState` for GPU ABI continuity; the shader doesn't
//     read those slots.
//
// References:
//   docs/presets/LUMEN_MOSAIC_DESIGN.md          — design intent + open decisions.
//   docs/presets/Lumen_Mosaic_Rendering_Architecture_Contract.md
//                                                — pass structure + buffer layout
//                                                  + panel sizing + matID == 1.
//   docs/SHADER_CRAFT.md §4.5b                   — mat_pattern_glass cookbook
//                                                  recipe (height-gradient
//                                                  domed cell + sharp ridge).
//   docs/VISUAL_REFERENCES/lumen_mosaic/         — mandatory / decorative /
//                                                  actively-disregard traits +
//                                                  rubric.
//
// Pipeline: ray_march → post_process (G-buffer deferred + bloom/ACES).
// SSGI is intentionally NOT in the pass list — emission dominates, SSGI's
// contribution is invisible against bright cells, the saved budget keeps
// Tier 2 headroom for the LM.4 pattern engine.

// ── Constants ──────────────────────────────────────────────────────────────

/// Panel SDF half-extents, expressed as a multiple of the frame's
/// world-space half-extents at the panel z-plane. 1.50 = panel bleeds
/// 50% past the visible frame on every side; the viewer never sees a
/// panel boundary or void corner. Per Decision G.1 (design doc §3) +
/// contract §P.1 (frame-edge invariant).
constant float kPanelOversize = 1.50f;

/// Panel z half-thickness. Small (0.02 world units) — primary rays only
/// hit the front face, the back face is for SDF closure.
constant float kPanelThickness = 0.02f;

/// Camera-to-panel distance along the camera forward axis. Matches
/// `scene_camera.position = (0, 0, -3)` + `target = (0, 0, 0)` in
/// LumenMosaic.json. Hardcoded for LM.1 (Decision G.1 fixed camera);
/// if the camera ever moves (G.2/G.3 deferred), recompute from
/// `length(camera_position - target)`.
constant float kFocalDist = 3.0f;

/// Voronoi cell density — passed directly as the inner scale argument
/// to voronoi_f1f2(panel_uv, kCellDensity). 15 cells per uv unit gives
/// ≈ 30 cells across the visible frame (uv ∈ [-1, +1]) at 16:9 — fewer,
/// larger cells per Matt 2026-05-09 LM.3.2 review ("the camera can zoom
/// in a little, 50 → 30 cells across"). Cells are large enough that each
/// cell's distinct palette colour reads as a stained-glass tile rather
/// than as confetti. This constant is the source of truth: the sidecar's
/// `lumen_mosaic.cell_density` was never decoded and, by the time it was
/// deleted (LM.CLEAN / CA-Presets-FU-2), still read 30.0 against the 15.0
/// below — dead AND wrong. Lipschitz-safe relief + frost amplitudes
/// are unchanged — halving density only halves the SDF gradient, which
/// adds Lipschitz headroom.
constant float kCellDensity = 15.0f;

/// The panel's surface is FLAT (LM.10 removed LM.3.2's relief + frost displacement, both at amplitude 0 since round
/// 7, 2026-05-10 — "Why is there a dot in every colored cell?" — yet still evaluated, voronoi + fbm8, on every
/// near-surface SDF tap). All surface character is albedo, baked once (`preset_bake_fragment`).

/// LM.3.2 — uniform-cell-intensity baseline. Replaces LM.3.1's agent-static-
/// field model after Matt's 2026-05-09 rejection ("fixed-color cells with
/// brightness modulation; the bright pools dominated the visual story").
/// Cells are uniformly bright with a small per-cell hash jitter so the panel
/// reads as a flat field of vivid colours rather than a backlit gradient.
/// The dance signal lives in *colour change*, not in *brightness change*.
constant float kCellIntensityBase   = 0.85f;
constant float kCellIntensityJitter = 0.15f;   // adds [0, 0.15] from hash

/// LM.3.2 — bar-pulse magnitude. A brief +30% panel-wide brightness flash
/// at each downbeat (driven by `f.barPhase01 ^ 8`) gives the dance a
/// structural pulse on top of the per-cell team-counter advance. When no
/// BeatGrid is installed (`f.barPhase01` stays at 0) the term collapses
/// to 1.0 and there is no pulse — the team-counter dance still fires
/// because the engine increments `barCounter` every 4 bass beats as a
/// fallback (see LumenPatternEngine `_tick` bar-fallback path).
/// **LM.4.1 (2026-05-11):** lowered from 0.30 → 0.20 as part of the
/// bleach-out fix. The bar pulse and LM.4 pattern boost stack on the
/// same downbeat frame; cutting both halves the combined peak
/// `cell_intensity` from 1.70 → ~1.20 (cell baseline × 1.20 bar pulse +
/// 1.0 × 0.20 pattern). Still touches the rgba8Unorm 1.0 ceiling on the
/// brightest channel of saturated cells, but stops short of the
/// every-channel-near-white bleach that destroyed cell colour identity
/// at LM.4. Bar pulse remains visible as a panel-wide brightness
/// flash on each downbeat; just less aggressive.
constant float kBarPulseMagnitude = 0.20f;
constant float kBarPulseShape     = 8.0f;

/// LM.4.5.3 — uncapped per-cell palette + per-track hue bias +
/// per-cell brightness variation + section-driven mutation.
///
/// **No card cap.** Each cell on each beat on each track on each
/// section gets a unique colour from the full 32-bit hash space
/// (~4 billion possibilities, ~16 M distinct after display
/// quantization). 1500 cells × ~480 beats per song × N sections
/// = potentially millions of distinct cell-colour events per song.
///
/// Colour hash:
///   `lm_hash_u32(cellHash ^ uint(step) ^ trackSeed ^ sectionSalt)`
///
/// Decoded as three uniform [0, 1] HSV samples mapped to HSV via:
///   - **Hue**: full wheel uniform, then per-track hue rotation
///     (a track-derived offset shifts the whole wheel) so the same
///     cellHash on different tracks lands at completely different
///     hues. Distribution stays full-range.
///   - **Saturation**: full range [0, 1] uniform.
///   - **Value**: full range mapped to [`kCardValMin`, `kCardValMax`]
///     with arousal-driven gamma bias (calm darker, energetic brighter).
///   - **Coupling rule**: `val ≤ sat + kValSatCouplingMargin (0.05)`.
///     Tightened at LM.4.5.3 from 0.20 — the previous margin admitted
///     borderline pale cells (sat=0.4 + val=0.6). At 0.05 every weak
///     cell is also dark; pale family unreachable by construction.
///
/// **Per-cell brightness variation.** A separate hash byte drives a
/// wide brightness multiplier (`kCellBrightnessMin` to
/// `kCellBrightnessMax` = 0.30 to 1.60), so some cells are dim
/// shadows and some are HDR-bright (over-exposing into bloom via
/// `kLumenEmissionGain = 1.5`). Real stained-glass character —
/// dramatic brightness diversity within a single panel.
///
/// **Section-driven mutation.** `sectionSalt` is derived from
/// `f.accumulated_audio_time` quantized into ~`kSectionPeriodSeconds`
/// (25 s) buckets, hashed with a constant. Each section bucket gives
/// every cell a completely different colour assignment — the
/// palette visibly shifts on each section boundary. (This is a time-
/// quantized proxy for true `StructuralPrediction.sectionIndex`;
/// follow-up may plumb the real section index through `LumenPatternState`.)
constant float kCardValMin              = 0.08f;
constant float kCardValMax              = 0.95f;
/// Coupling margin: maximum amount that value may exceed saturation.
/// 0.05 (LM.4.5.3, tightened from 0.20 at LM.4.5.2) gives effectively
/// `val ≲ sat` — every weak cell is also dark. At sat=0.3, val caps
/// at 0.35 (deep charcoal-pink). At sat=0.5, val caps at 0.55 (mid
/// muted). At sat=0.9, val caps at 0.95 (full bright jewel). The
/// "pale family" (sat=0.3 + val=0.6 cells) is unreachable by
/// construction.
constant float kValSatCouplingMargin    = 0.05f;
/// Per-cell brightness multiplier range. A separate hash byte gives
/// each cell a brightness multiplier in [`kCellBrightnessMin`,
/// `kCellBrightnessMax`]. Cells below 1.0 are dim shadows; cells
/// above 1.0 are over-exposed bright (the bloom kick comes from
/// values > 1.0 in linear space being tonemapped through ACES).
/// 0.30 → 1.60 gives ~5× brightness ratio, the kind of dramatic
/// variation real backlit stained glass exhibits.
/// LM.4.6: tightened from [0.30, 1.60] to [0.85, 1.15]. The wide
/// [0.30, 1.60] range produced ~30% dim/gray cells (intensity 0.3 ×
/// any anchor colour = dark grayish). Within-anchor variety now
/// comes from the kAnchorJitterMagnitude per-RGB jitter (gives
/// hue/sat/val variation around the anchor, not just brightness).
/// The intensity multiplier stays narrow so every cell reads as
/// "lit" rather than "in shadow."
constant float kCellBrightnessMin       = 0.85f;
constant float kCellBrightnessMax       = 1.15f;
/// Section bucket size in beats. `lumen.bassCounter` quantised into
/// integer buckets of this length drives the section salt — palette
/// resets on each bucket boundary. 64 beats ≈ 32 s at 120 BPM, ≈ 38 s
/// at 100 BPM — roughly verse/chorus duration in pop music. The
/// bassCounter resets on track change, so each new track starts at
/// section 0. Replaces the LM.4.5.3 `accumulatedAudioTime / 25`
/// proxy which never advanced (audio-energy accumulator, not time).
/// Follow-up: plumb real `StructuralPrediction.sectionIndex` for
/// music-accurate section boundaries (verse/chorus/bridge alignment).
constant float kSectionBeatLength       = 64.0f;
// LM.4.6: anchor-distribution model retired — the kAnchorJitterMagnitude
// constant lived here. Per Matt 2026-05-11 it added unwanted structure;
// the palette is back to pure uniform random RGB per cell.

// LM.7 — kTintMagnitude (per-track chromatic-projection tint magnitude)
// retired at LM.4.7. The palette-table lookup makes a per-track tint
// redundant — every drawn palette is already character-distinct. The
// chromatic-projection math (mean-subtract along the achromatic axis)
// is gone with it; the LM.7 / LM.4.6 `test_achromaticAlignedSeed_doesNotWash`
// regression no longer applies (cells sample from a curated 12-entry
// table, which avoids the achromatic-axis wash by construction).
/// Gamma endpoints for arousal-driven VALUE-only distribution bias.
/// arousal = -1 → gamma 1.8 (concave: biases toward darker cells —
/// deep cobalts, deep wines, ruby shadows); arousal = +1 → gamma 0.55
/// (convex: biases toward brighter cells — emeralds, citrines, bright
/// sapphires); arousal = 0 → gamma 1.0 (uniform). Picked so the
/// expected-value gap between calm and energetic moods is large enough
/// to read (≈ ±0.13 on the [`kCardValMin`, `kCardValMax`] range) while
/// both extremes still have ~28 % of samples in the opposite half —
/// neither extreme empties the bright nor dim tail. Saturation is
/// NOT gamma-biased at LM.4.5.1; it's uniform within [`kSatFloor`,
/// 1.00] regardless of mood (saturation should always read as
/// "stained glass", and gamma bias on a [0.7, 1.0] band is
/// imperceptible). Verified by `LumenPaletteSpectrumTests`.
constant float kMoodGammaLowArousal  = 1.80f;
constant float kMoodGammaHighArousal = 0.55f;

/// LMG — stained hammered glass (Matt, 2026-10-28: "STAINED hammered glass"). Each piece is cut from its own
/// sheet of coloured hammered cathedral glass, backlit, and set in lead. Two scales: the pieces (the Voronoi
/// cells above — colour, the beat dance) and, inside every piece, a much finer field of hammer dimples. The
/// references are local-only supplier photos (`~/.uzume/lm_refs/01–09`, README there; never committed).
/// Retires LM.3.2's white frost seam and LM.6's per-piece dome + centre hot-spot: those made each piece ONE
/// big dimple, which is why it read as a painted tile.
///
/// Dimples across one piece (refs 01, 02, 04: ~10–20 across a hand-sized area).
constant float kDimplesPerPiece = 10.0f;
/// Dimple radius in dimple units (centres ~1 apart): large enough that dimples touch and cover the whole sheet
/// (ref 02 has no flat glass between them), small enough that the seam where they meet stays shallow.
constant float kDimpleRadius = 0.72f;
/// Lens: a dimple's slope bends the backlight — the side facing away falls into a dark crescent (refs 02, 04),
/// the side facing the light lifts a little.
constant float kCrescentDepth = 0.65f;
constant float kLensStrength  = 0.25f;
/// Glass thickness range (Beer–Lambert exponent on the transmittance): thin at a dimple's centre, thick on the
/// ridges between dimples — colour deepens where the glass is thick (refs 05, 06).
constant float kThinGlass  = 0.80f;
constant float kThickGlass = 1.12f;
/// Glint: light focused by a dimple, in the glass's own hue at full brightness — so near-black glass still
/// shows points of light (refs 05, 09; Matt: dark glass must glint).
constant float kGlintThreshold = 0.65f;
constant float kGlintStrength  = 0.35f;
/// The backlight is not even: a soft, broad dimming drift across the panel (refs 01, 07, 09) — fbm4 at
/// ~1.2 features across the frame, up to kBacklightDrift darker (only darker: bright glass is already at 1).
constant float kBacklightDrift = 0.30f;
/// Backlight direction in the panel plane (upper left, behind the glass).
constant float2 kBacklightDir = float2(-0.60f, 0.80f);
/// Lead came between pieces, in Voronoi `f2 − f1` units (cell spacing = 1): slim, dark grey, front-lit only
/// (it blocks the backlight), with a thin sheen down its rounded middle so a line still reads against
/// near-black glass (Matt: "sheened dark-grey lines").
constant float kCameWidth     = 0.045f;
constant float kCameSoftness  = 0.012f;
constant float kCameGrey      = 0.030f;
constant float kCameSheen     = 0.11f;
constant float kCameSheenShape = 6.0f;

/// LM.3.2 — team assignment percentages. Buckets summed left-to-right so
/// `bucket = h % 100`:
///   bucket  ∈ [0,  30) → bass team   (30%)
///   bucket  ∈ [30, 65) → mid team    (35%)
///   bucket  ∈ [65, 90) → treble team (25%)
///   bucket  ∈ [90,100) → static team (10%)
constant uint kBassTeamCutoff   = 30u;
constant uint kMidTeamCutoff    = 65u;
constant uint kTrebleTeamCutoff = 90u;

// ── LM.4.5 — IQ palette constants retired ─────────────────────────────────
//
// The eight IQ palette endpoints (`kPalette[A,B,C,D][Cool/Warm/Subdued/
// Vivid/Unison/Offset/Complementary/Analogous]`), the
// `kPaletteMoodPhaseShift` rotation magnitude, and the four
// `kSeedMagnitude{A,B,C,D}` per-track perturbation magnitudes were all
// deleted at LM.4.5. The IQ cosine palette form `a + b * cos(2π * (c*t +
// d))` was structurally narrow-scope — every cell on a given track sat
// inside a ~5 % slice of the HSV cube, with hue floored ±0.20 around a
// mood-driven centre and saturation/value floored at 0.78 / 0.80. Matt's
// 2026-05-11 review ("I am asking you for VARIETY... Where are the dark
// hues? Where are the regal purples? What about browns and grays?") made
// the breadth limit conclusive. LM.4.5 replaces the entire `lm_cell_palette`
// body with the full-spectrum card model (see `kCardSize` block above).
// Constants gone; the per-track seed plumbing on `LumenPatternState`
// (`trackPaletteSeed{A,B,C,D}`) is preserved — it now flows through
// `lm_track_seed_hash` into the card-slot colour hash unchanged.

/// Default attenuation coefficient for the slot-8 placeholder state
/// (`LumenPatternState.activeLightCount == 0`). The fragment never
/// dereferences a non-existent agent — but kept here so future code
/// changes have the centroid's expected falloff value to compare against.
constant float kLumenDefaultFalloffK = 6.0f;

// ── LM.4.4 — pattern engine constants retired ──────────────────────────────
//
// `kPatternBoost / kPatternMaxSum / kRippleMaxRadius / kRippleSigmaBase /
// kSweepSigma` were deleted at LM.4.4 along with their evaluator helpers
// (`lm_pattern_radial_ripple / lm_pattern_sweep / lm_evaluate_active_patterns`).
// Reason: the ripple/sweep wavefronts were invisible against the
// simultaneous bar pulse — see the LM.4.4 landed-work entry in
// `CLAUDE.md` for the full diagnosis. The slot-8 `LumenPatternState`
// buffer keeps its `patterns[4]` tuple as zeroed scaffolding for GPU
// ABI continuity, but the shader does not read those slots anywhere.

// ── Helpers ────────────────────────────────────────────────────────────────

/// Visible-frame half-extents at the panel z-plane, derived from the
/// SceneUniforms FOV + aspect ratio + the hardcoded kFocalDist. Returns
/// (half-width-x, half-height-y) in world units. The cell-uv coordinate
/// system uses these as its [-1, +1] basis so cell density is independent
/// of FOV / aspect drift across hardware.
static inline float2 lm_camera_tangents(constant SceneUniforms& s) {
    float yFovTan = tan(s.cameraOriginAndFov.w * 0.5f);
    float aspect  = s.sceneParamsA.y;
    return float2(yFovTan * aspect, yFovTan) * kFocalDist;
}

/// LM.3.2 — integer hash. Mixes a single uint into a uint with good
/// avalanche so adjacent cell ids produce well-separated team and period
/// assignments. (Murmur-style xor-shift mixer; same scheme as Arachne's
/// `arachHashU32`, kept lexically distinct so future shader-utility work
/// can promote one of them into a shared helper without import order
/// drift.)
static inline uint lm_hash_u32(uint x) {
    x ^= 61u;
    x ^= (x >> 16);
    x *= 0x7feb352du;
    x ^= (x >> 15);
    x *= 0x846ca68bu;
    x ^= (x >> 16);
    return x;
}

/// LM.3.2 — derive a single 32-bit hash from the four `trackPaletteSeed`
/// components on `LumenPatternState`. Each seed component is in `[-1, +1]`;
/// we map to a 16-bit integer and concatenate. This is the value XOR'd
/// with `cell_id` to scramble the per-cell team / period assignment per
/// track (different tracks → different cells in the static team, different
/// cells on each band team).
static inline uint lm_track_seed_hash(constant LumenPatternState& lumen) {
    uint a = uint((lumen.trackPaletteSeedA * 0.5f + 0.5f) * 65535.0f);
    uint b = uint((lumen.trackPaletteSeedB * 0.5f + 0.5f) * 65535.0f);
    uint c = uint((lumen.trackPaletteSeedC * 0.5f + 0.5f) * 65535.0f);
    uint d = uint((lumen.trackPaletteSeedD * 0.5f + 0.5f) * 65535.0f);
    return lm_hash_u32((a & 0xFFu)
                     | ((b & 0xFFu) << 8u)
                     | ((c & 0xFFu) << 16u)
                     | ((d & 0xFFu) << 24u));
}

/// LM.3.2 — uniform cell intensity with hash-driven jitter and a global
/// bar pulse. Replaces the LM.3.1 agent-driven static field after Matt's
/// 2026-05-09 rejection ("the bright pools dominated the visual story").
///
/// `cellHash` is the same hash used for team / period assignment in
/// `sceneMaterial` (so the jitter pattern is stable per-track).
/// `barPhase01 ∈ [0, 1)` is `f.barPhase01` from the FeatureVector; when
/// no BeatGrid is installed it stays at 0 and the bar pulse term collapses
/// to 1.0. The team-counter dance still fires because the engine maintains
/// `barCounter` via the "every 4 bass beats" fallback.
///
/// The four light agents on `LumenPatternState` are still ticked CPU-side
/// for ABI continuity but their `intensity` / `colorR/G/B` fields are
/// unused here. `LM.4` may revisit per-cell pattern bursts that read the
/// agent positions.
static inline float lm_cell_intensity(uint cellHash, float barPhase01) {
    // LM.4.5.3: per-cell brightness varies WIDELY (0.30 to 1.60) so
    // some cells are dim shadows and some over-expose into bloom —
    // dramatic stained-glass brightness diversity. Replaces the
    // narrow [0.85, 1.15] LM.3.2 jitter range. The brightness byte
    // is hashed separately from the colour-hash bytes (uses cellHash
    // bits 24..31 + a mixing constant) so brightness and colour
    // vary independently per cell.
    uint brightnessHash = lm_hash_u32(cellHash ^ 0xB7E15163u);
    float jitterNorm = float((brightnessHash >> 24u) & 0xFFu) * (1.0f / 255.0f);
    float baseIntensity = mix(kCellBrightnessMin, kCellBrightnessMax, jitterNorm);
    float barShape = pow(saturate(barPhase01), kBarPulseShape);
    float barFactor = 1.0f + kBarPulseMagnitude * barShape;
    return baseIntensity * barFactor;
}

/// LM.4.7 — Palette-table lookup. Replaces LM.4.6 (uniform random RGB
/// per cell) + LM.7 (per-track chromatic-projection tint).
///
/// The Orchestrator selects one of 18 hand-authored 12-colour palettes
/// per song and writes the drawn 12 entries into `lumen.palette[0..11]`
/// via `LumenPatternEngine.setPalette(_:)` at each track change. Each
/// cell's palette index for the current beat / section is the lower
/// 4 bits of an avalanche hash of (cellHash, step, trackSeed, sectionSalt)
/// taken modulo 12 — so the index walks the palette deterministically
/// on each beat step + section boundary, but every cell's colour at any
/// given moment is one of the 12 curated palette entries (D-LM-palette-library).
///
/// The team / period / step / sectionSalt computation upstream is
/// preserved verbatim from LM.3.2 / LM.4.6 — only the final
/// `hash → RGB` body changes to `hash → idx % 12 → palette[idx]`.
///
/// Per-cell brightness variation lives separately in `lm_cell_intensity`
/// (multiplies the colour by [0.85, 1.15] × bar pulse) — gives
/// stained-glass brightness diversity without restricting which palette
/// entries appear.
///
/// **Section salt:** `lumen.bassCounter / kSectionBeatLength` quantised
/// into integer buckets — every ~32 s at 120 BPM the palette-index walk
/// reshuffles. `bassCounter` resets on track change via
/// `LumenPatternEngine.setTrackSeed(_:)`, so each track starts fresh
/// from section 0.
///
/// **Regression-harness path:** when slot 8 is bound to the zero-filled
/// `lumenPlaceholderBuffer` (e.g. unit tests that don't bind a real
/// palette), every entry of `lumen.palette` reads as (0,0,0,0) and the
/// shader returns pure black. Production fixtures must bind an explicit
/// palette payload via `setPalette(_:)` to receive coloured output —
/// see `PresetRegressionTests` for the Autumnal-bound fixture.
static inline float3 lm_cell_palette(uint cellHash,
                                     constant LumenPatternState& lumen) {
    // Team selection — drives the beat-step ratchet (per-cell palette
    // index advances on each team's beat).
    uint teamBucket = cellHash % 100u;
    float teamCounter = 0.0f;
    if (teamBucket < kBassTeamCutoff) {
        teamCounter = lumen.bassCounter;
    } else if (teamBucket < kMidTeamCutoff) {
        teamCounter = lumen.midCounter;
    } else if (teamBucket < kTrebleTeamCutoff) {
        teamCounter = lumen.trebleCounter;
    }

    uint periodBucket = (cellHash >> 8u) & 0x7u;
    float period = 1.0f;
    if (periodBucket >= 7u) { period = 8.0f; }
    else if (periodBucket >= 5u) { period = 4.0f; }
    else if (periodBucket >= 3u) { period = 2.0f; }
    float step = floor(teamCounter / period);

    // Section salt — bassCounter quantised into 64-beat buckets.
    // Resets on track change (bassCounter is reset by setTrackSeed).
    uint sectionSalt = uint(floor(lumen.bassCounter / kSectionBeatLength));
    uint trackSeed   = lm_track_seed_hash(lumen);

    // Avalanche hash → 12-bucket palette index. The four inputs (cell,
    // step, track, section) are XOR'd into one hash so every tuple gets
    // its own palette slot. Mod 12 collapses the 32-bit hash space onto
    // the 12-entry palette; the slight bias from `2^32 % 12 != 0` is
    // ≈ 2 × 10⁻¹⁰ per slot, far below any perceptible threshold.
    uint h = lm_hash_u32(cellHash
                       ^ (uint(step) * 0x9E3779B9u)
                       ^ trackSeed
                       ^ (sectionSalt * 0xCC9E2D51u));
    uint idx = h % 12u;
    return float3(lumen.palette[idx].r,
                  lumen.palette[idx].g,
                  lumen.palette[idx].b);
}

// ── Scene SDF ──────────────────────────────────────────────────────────────

/// Static glass panel — one `sd_box` at z = 0, sized 1.50 × the visible
/// frame's world-space half-extents at the panel plane (so panel edges
/// are never visible). Flat (LM.10: the relief + frost displacements, at
/// amplitude 0 since LM.3.2 round 7, are gone).
///
/// `f` and `stems` are accepted for D-021 conformance but unused here —
/// LM.1 has zero audio reactivity per Decision G.1 + design doc §3.
float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)f;
    (void)stems;
    (void)ferrofluidHeight;  // V.9 Session 4.5b slot-10; Ferrofluid Ocean only.

    // Panel half-extents: oversized so the box bleeds past the visible
    // frame on every side. Per contract §P.1.
    float2 cam_t = lm_camera_tangents(s);
    float3 panel_size = float3(cam_t * kPanelOversize, kPanelThickness);
    return sd_box(p, panel_size);
}

// ── LMG hammer dimples ─────────────────────────────────────────────────────

/// Height of the hammered surface at `uv` (dimple units): a smooth round bump per dimple, 1 at its centre,
/// fading to flat before it reaches its neighbours — so there is no crease between dimples (a V-shaped ridge
/// read as cracked leather, not glass).
static inline float lm_dimple_height(float2 uv) {
    float r = voronoi_f1f2(uv, 1.0f).f1 / kDimpleRadius;
    return r < 1.0f ? (1.0f - r * r) * (1.0f - r * r) : 0.0f;
}

/// The hammered glass at `panel_uv`, independent of colour and time (LM.10: baked once at full size by
/// `preset_bake_fragment`, else evaluated inline): x = dimple height (→ thickness), y = brightness multiplier
/// (crescent × lift × backlight drift), z = glint² × drift. Dimples run at kDimplesPerPiece × the piece density,
/// offset per piece by its UNSEEDED id hash, so the pattern breaks at every lead line like separately cut glass
/// and is the same on every track. Slope by central differences.
static inline float3 lm_glass_terms(float2 panel_uv, uint cell_id) {
    uint pieceHash = lm_hash_u32(cell_id);
    float2 sheetOffset = float2(float(pieceHash & 0xFFFFu), float(pieceHash >> 16)) * (1.0f / 4096.0f);
    float2 duv = panel_uv * (kCellDensity * kDimplesPerPiece) + sheetOffset;
    const float e = 0.08f;
    float h = lm_dimple_height(duv);
    float2 slope = float2(lm_dimple_height(duv + float2(e, 0)) - lm_dimple_height(duv - float2(e, 0)),
                          lm_dimple_height(duv + float2(0, e)) - lm_dimple_height(duv - float2(0, e))) / (2.0f * e);
    float facing = dot(slope, kBacklightDir);   // > 0: the slope bends the backlight toward the viewer
    // The far side of each dimple falls into a dark crescent (ref 02's signature); the lit side lifts a little.
    float lens = (1.0f - kCrescentDepth * smoothstep(0.45f, 0.95f, -facing)) * (1.0f + kLensStrength * saturate(facing));
    float glint = saturate((facing - kGlintThreshold) / (1.0f - kGlintThreshold));
    float drift = 1.0f - kBacklightDrift * saturate(0.5f + fbm4(float3(panel_uv * 0.6f, 0.37f)));
    return float3(h, lens * drift, glint * glint * drift);
}

/// Bake encoding (rgba8Unorm): the brightness multiplier peaks at 1.25 (lift), so it is stored ÷ this.
constant float kGlassBakeMulScale = 1.5f;

/// Screen uv (0,0 = top left) of world point `p`: the inverse of the G-buffer's ray, exact wherever along the
/// ray the march stopped.
static inline float2 lm_screen_uv(float3 p, constant SceneUniforms& s) {
    float3 d = p - s.cameraOriginAndFov.xyz;
    float z = dot(d, s.cameraForward.xyz);
    float yFov = tan(s.cameraOriginAndFov.w * 0.5f);
    float2 ndc = float2(dot(d, s.cameraRight.xyz) / (z * yFov * s.sceneParamsA.y), -dot(d, s.cameraUp.xyz) / (z * yFov));
    return ndc * 0.5f + 0.5f;
}

/// LM.10 — the glass, baked once at the march size (the engine runs this when a ray-march scene defines it; see
/// `RenderPipeline.setRayMarchBake`). Each texel takes its pixel's own ray to the panel's front face — where the
/// march lands — so texel and G-buffer pixel see the same panel_uv; sceneMaterial finds the texel by
/// `lm_screen_uv`.
fragment float4 preset_bake_fragment(VertexOut in [[stage_in]], constant SceneUniforms& s [[buffer(4)]]) {
    float2 ndc = in.uv * 2.0f - 1.0f;
    float yFov = tan(s.cameraOriginAndFov.w * 0.5f);
    float3 ray = s.cameraForward.xyz + ndc.x * yFov * s.sceneParamsA.y * s.cameraRight.xyz
               - ndc.y * yFov * s.cameraUp.xyz;
    float3 cam = s.cameraOriginAndFov.xyz;
    float3 p = cam + ray * ((-kPanelThickness - cam.z) / ray.z);
    float2 panel_uv = p.xy / lm_camera_tangents(s);
    float3 t = lm_glass_terms(panel_uv, uint(voronoi_f1f2(panel_uv, kCellDensity).id));
    return float4(t.x, t.y / kGlassBakeMulScale, t.z, 1.0f);
}

// ── Scene Material ─────────────────────────────────────────────────────────

/// LM.3.2 sceneMaterial — band-routed beat-driven dance.
///
/// Each cell is hashed (with the per-track seed mixed in) and assigned to
/// one of four teams (bass / mid / treble / static). The cell's palette
/// phase is its hash-derived base offset plus `floor(team_counter /
/// period) * kPaletteStepSize` — the cell ratchets one palette step
/// forward each time its team's beat counter crosses a period boundary.
/// Static cells never advance; they're rotated per track because the
/// team hash is XOR'd with the per-track seed.
///
/// Per-cell intensity is uniform with a small hash-driven jitter
/// (`[0.85, 1.0]`) plus a global bar-pulse `1.0 + 0.30 × barPhase01^8`.
/// Replaces the LM.3.1 agent-driven static-light field after Matt's
/// 2026-05-09 rejection — brightness modulation is no longer the visual
/// story; *colour change synchronised to the beat* is.
///
/// All pixels within a Voronoi cell sample the same `cell_id` → the same
/// palette + the same intensity → exactly one colour per piece of glass, which
/// LMG then shades as hammered glass (dimples, thickness, glints) set in lead. Adjacent cells get well-separated
/// palette samples (cell hashes differ → palette phases differ → cells
/// can be on opposite sides of the hue wheel).
///
/// `roughness` / `metallic` are stored in the G-buffer's packed material
/// byte but only affect output when `matID == 0`; for `matID == 1` (this
/// preset) the lighting fragment skips Cook-Torrance entirely so they're
/// cosmetic placeholders.
///
/// `outMatID = 1` flags this hit pixel as emission-dominated dielectric
/// (D-LM-matid). The G-buffer fragment encodes the value into gbuf0.g;
/// the lighting fragment dispatches on it.
void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen,
                   texture2d<float> presetTexture) {
    (void)matID;
    (void)stems;

    // Project hit position into the panel-face uv frame (`[-1, +1]`
    // exactly at the visible frame edges; `[-1.5, +1.5]` at the SDF
    // edges per kPanelOversize). Cell-density is decoupled from the
    // oversize factor by dividing through `cameraTangents` only —
    // contract §P.1 frame-edge invariant.
    float2 cam_t   = lm_camera_tangents(s);
    // LM.10: on the panel's exact front face along this pixel's ray — the march stops up to 0.001·t short, which
    // would shift the pieces and dimples by a pixel at the frame edges relative to the bake (and frame to frame).
    float3 cam = s.cameraOriginAndFov.xyz;
    float3 face = cam + (p - cam) * ((-kPanelThickness - cam.z) / (p.z - cam.z));
    float2 panel_uv = face.xy / cam_t;

    // Voronoi cell membership. `v.id` is the deterministic per-cell hash
    // (`voronoi_f1f2.id` is `int`; we cast to uint for the bit-mixing
    // pipeline below). `v.pos` is the cell-centre uv but unused at LM.3.2
    // — the new uniform-with-jitter intensity model doesn't need a per-
    // cell spatial coordinate.
    VoronoiResult cellV = voronoi_f1f2(panel_uv, kCellDensity);
    uint cell_id = uint(cellV.id);

    // Mix the Voronoi cell id with the per-track seed and run a cheap
    // avalanche hash. The output drives team / period / base-phase /
    // jitter assignments — same hash for all four so the cell's identity
    // is one stable bit-pattern.
    uint cellHash = lm_hash_u32(cell_id ^ lm_track_seed_hash(lumen));

    // Per-cell colour from the procedural palette + team-counter step.
    float3 cell_hue = lm_cell_palette(cellHash, lumen);

    // Per-cell scalar intensity (uniform jitter + bar pulse) — the backlight's strength this frame.
    float cell_intensity = lm_cell_intensity(cellHash, f.bar_phase01);

    // ── LMG — the piece's own sheet of hammered glass ───────────────────────────
    //
    // The glass terms come from the bake when the engine made one (LM.10: full-size, once), else inline —
    // identical up to the bake's 8-bit encoding (`LumenGlassBakeTests`).
    float3 terms;
    if (presetTexture.get_width() > 1) {
        constexpr sampler nearest(coord::normalized, filter::nearest, address::clamp_to_edge);
        float4 baked = presetTexture.sample(nearest, lm_screen_uv(p, s));
        terms = float3(baked.x, baked.y * kGlassBakeMulScale, baked.z);
    } else {
        terms = lm_glass_terms(panel_uv, cell_id);
    }
    // Thickness (Beer–Lambert): thin at the dimple centre, thick on the ridges → colour deepens there.
    float3 glass = pow(max(cell_hue, float3(1e-4f)), float3(mix(kThickGlass, kThinGlass, terms.x))) * terms.y;
    // Glint: focused light in the glass's own hue at full brightness (near-black glass still glints).
    float3 hue = cell_hue / max(max3(cell_hue.r, cell_hue.g, cell_hue.b), 0.02f);
    glass += terms.z * kGlintStrength * hue;
    glass *= cell_intensity;

    // ── LMG — lead came between pieces ─────────────────────────────────────────
    //
    // Opaque to the backlight, lit from the front only: dark grey with a thin sheen down its rounded middle
    // (profile x = 0 on the centre line, 1 at the came's edge). Not modulated by the bar pulse — the pulse is
    // the backlight.
    float edge = cellV.f2 - cellV.f1;
    float came = 1.0f - smoothstep(kCameWidth, kCameWidth + kCameSoftness, edge);
    float x = saturate(edge / kCameWidth);
    float3 lead = float3(kCameGrey + kCameSheen * pow(1.0f - x, kCameSheenShape));

    albedo = clamp(mix(glass, lead, came), 0.0f, 1.0f);

    // Pattern-glass material aesthetic from SHADER_CRAFT.md §4.5b.
    roughness = 0.40f;
    metallic  = 0.0f;

    // Flag this pixel as emission-dominated dielectric (D-LM-matid).
    outMatID  = 1;
}
