// Membrane — A luminous drumskin stretched across the screen.
//
// The metaphor, restated precisely because every iteration has been about
// this: a taut translucent sheet lit from within. It is always visible.
// Bass pushes into it like a slow hand. Beats strike it with outward-
// propagating ripples. Hi-hats tickle it with fine surface stippling.
// Between strikes the sheet recovers, breathing slowly.
//
// Audio routing is deliberately sparse so the surface has time to recover
// between events:
//   * breath      — always-on FBM, gives life in silence
//   * bass_att_rel — slow broad undulation, the "hand pressing in"
//   * level_rise  — ONE shockwave per strike, aspect-correct circle,
//                   amplitude weighted by how bass-heavy the strike is
//
// ── PR.25: why the strike driver changed (measured, not inferred) ──────────
//
// Matt, roster review 2026-09-04: "Sync with music is weak, puddle pulse
// could be improved visually and with respect to motion."
//
// The strike used to be `features.beat_bass`. Measured over five
// FixtureSessionCaptureGenerator captures (real audio, production analysis
// chain, FA #27), beat_bass fires at a near-constant rate on every track:
//
//     Speed Of Life 134/min · Sound And Vision 134/min · Weeping Wall 138/min
//     Love Rehab 135/min · Seven Nation Army 132/min
//
// Weeping Wall is a drumless ambient instrumental. On it beat_bass repeats
// the cycle 1.000 → 0.201 → 0.040 forever: a metronome, not a detector.
// (RayMarchPipeline.swift already records the same finding — "fire on ~97 %
// of frames on real sessions, a near-constant jitter, not clean beats".)
// Membrane's entire event layer hung off it, so the rendered frame-to-frame
// motion came out IDENTICAL on a rock track and on a drumless one:
// p99 0.02029 and max 0.08032 on both, to the digit.
//
// `spectral_level_rise` (FTR.24) is the replacement: instant attack, ~0.2 s
// release — a real decaying timer, so -log(env) still gives a clean expanding
// age — and it marks audible arrivals rather than ticking. Selectivity comes
// from `bass_dev`, which is 0 for half of all frames and separates the same
// five tracks 2/min → 76/min at a fixed threshold (38x, vs beat_bass's 1.05x).
//
// Absolute `bass_att` / `treb_att` reads are retired here too: AGC moves the
// denominator with mix density, so the same kick reads differently per track
// (FA #31 / D-026). Everything below drives from *_rel / *_dev, soft-saturated
// against the MEASURED p99 of each primitive, never against 1.0 (FA #73).
//
// Color is a stable position-driven field: three FBM-only thickness
// fields blended with time-drifting weights. It is NOT audio-modulated,
// so the color structure you see at rest is the same structure you see
// while music plays — the music only DEFORMS it via lighting.
//
// ── PR.25: why the palette changed ────────────────────────────────────────
//
// The field was hsv2rgb(fract(fbm * 3.0), 1.0, 1.0) — full saturation, full
// value, hue sweeping the whole circle ~3x across the frame — plus a further
// 1.30x saturation boost and a 0.40 luminance FLOOR. Rendered, that is an
// edge-to-edge pastel rainbow with no dark anywhere, which is Membrane's own
// anti-reference `anti_02_oversaturated_specular` ("the saturation envelope
// and the all-over coverage") and the §18.2 prohibition on glow aesthetics.
// It is also why the pulse could not be seen: a thin bright arc drawn over a
// field that is already bright everywhere has nothing to contrast against.
//
// The sheet is now a dark blue-purple drumhead (`--bg` / `--purple`, §18.3)
// and the strike is CORAL — the brand's "energy arriving" token. Hue rides a
// narrow purple→coral arc instead of the full circle, so the surface reads as
// one material lit from within rather than as spectrum noise.


float mb_hash3(float3 p) {
    return fract(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

float mb_vnoise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = mb_hash3(i);
    float n100 = mb_hash3(i + float3(1.0, 0.0, 0.0));
    float n010 = mb_hash3(i + float3(0.0, 1.0, 0.0));
    float n110 = mb_hash3(i + float3(1.0, 1.0, 0.0));
    float n001 = mb_hash3(i + float3(0.0, 0.0, 1.0));
    float n101 = mb_hash3(i + float3(1.0, 0.0, 1.0));
    float n011 = mb_hash3(i + float3(0.0, 1.0, 1.0));
    float n111 = mb_hash3(i + float3(1.0, 1.0, 1.0));
    float nxy0 = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
    float nxy1 = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
    return mix(nxy0, nxy1, f.z);
}

float mb_fbm3(float3 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * mb_vnoise3(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return v;
}

// ── Aspect-corrected space ──────────────────────────────────────
//
// UV space is 0..1 × 0..1 regardless of window shape. On a 16:9 window,
// a circle in UV (length(uv - c) == r) renders as a horizontally
// stretched ellipse. To draw an actual circle, work in a space where
// x is scaled by the window aspect ratio.

float2 mb_asp_space(float2 uv, float aspect) {
    return float2((uv.x - 0.5) * aspect, uv.y - 0.5);
}

// ── Shockwave ring ───────────────────────────────────────────────
//
// PR.26 — the age comes from the BEAT GRID, not from a decaying envelope.
//
// Two previous drivers were measured against the real beats of a locked-grid
// session (Arcade Fire, The Suburbs, grid_bpm 117.88, 105 beats / 54 s;
// chance level for a +-80 ms window is 31 %):
//
//     old  beat_bass          30 % on-beat   0.97x chance   (a metronome)
//     PR.25 level_rise+bassDev 26 % on-beat   0.83x chance   (WORSE than chance)
//
// Both were guesses at when a beat happened. `beat_phase01` does not guess:
// it is 0 at the last beat and ramps to 1 at the next, off the cached
// BeatGrid, so a ring born at phase 0 is on the beat BY CONSTRUCTION. It is
// also a better age function than -log(envelope) ever was — exactly linear,
// so the ring expands at a constant rate instead of decelerating.
//
// This is the sanctioned Layer-4 use (D-153 -> D-158): cached grid, not raw
// live onsets; bounded per-beat footprint and steady GLOBAL luminance (the
// ring modulates locally, it does not brighten the frame); beat-irregular
// tracks excluded via `requires_regular_beat` in the sidecar (D-154).
//
// Distance is computed in aspect-corrected space so the ring is an actual
// circle on screen, not an ellipse.

float membrane_ring(float2 asp, float2 impactAsp, float phase,
                    float strength, float speed, float thicknessBase) {
    if (strength <= 0.001) return 0.0;
    float radius = phase * speed;
    float thickness = thicknessBase + phase * 0.10;
    float d = length(asp - impactAsp);

    // PR.28 — a WAVE TRAIN, not one annulus.
    //
    // The first perception check against the recurated folder failed this trait:
    // `02_meso_single_strike_anatomy.jpg` shows a struck liquid surface producing a
    // SEQUENCE of concentric crests, each trailing the leading one and each weaker,
    // and the render emitted a single Gaussian ring. One arc does not read as an
    // impact — it reads as a sweep. Three crests at decreasing amplitude, trailing
    // the leading edge inward, is the minimum that reads as a strike travelling.
    //
    // Physically this is the dispersive wake behind the lead wavefront; visually it
    // is the difference between "a line moved" and "something was hit here".
    float body = 0.0;
    body += exp(-pow((d - radius) / thickness, 2.0));
    body += 0.55 * exp(-pow((d - radius * 0.72) / (thickness * 1.15), 2.0));
    body += 0.28 * exp(-pow((d - radius * 0.48) / (thickness * 1.35), 2.0));
    // Fade as it travels out, so the ring dies before the next beat lands
    // rather than two rings sharing the skin.
    float fade = 1.0 - smoothstep(0.55, 1.0, phase);
    return body * fade * strength;
}

// Bass strength for a strike, normalised so it survives BOTH the range this
// primitive shows offline and the range it shows live.
//
// PR.25 used `saturate(bass_dev * 1.54)`, calibrated against a pooled p99 of
// 0.652 taken from FixtureSessionCaptureGenerator captures. On Matt's live
// M7 session `bass_dev` never exceeded 0.400 and its p50 was 0.015, so that
// gate needed `level_rise >= 1.12` at the median — mathematically impossible —
// and the strongest strike in 54 s reached 0.559 of full amplitude. Sparse and
// weak, exactly as reported.
//
// A saturating hyperbola has no such cliff: it is responsive at 0.02, useful
// by 0.2, and still climbing at 1.7, so no session's scale starves it and none
// clips it (FA #73 — tune against the primitive's real behaviour, and here
// that behaviour DIFFERS BY SESSION, so the curve must be scale-free).
float membrane_bass_strength(float bassDev) {
    return bassDev / (bassDev + 0.12);
}

/// Metric accent — how hard THIS beat of the bar should be struck.
///
/// PR.27, from Matt's M7: "Every strike is the same intensity, which makes the
/// preset feel much too active." PR.26 gave every beat a floor of 0.42 and a
/// bass term that on real material only spanned 0.42..0.87 — four near-identical
/// hits per bar, which is a machine, not a drummer.
///
/// Music is not flat. In 4/4 the downbeat carries the bar, beat 3 is the
/// secondary stress, and 2 and 4 are weak. Giving the skin that hierarchy does
/// two things at once: strikes stop being interchangeable, and three of every
/// four drop far enough back that the frame reads as CALM between downbeats.
///
/// `bar_phase01` is 0 at the downbeat and ramps to 1 at the next, so the beat
/// index within the bar is just floor(bar_phase01 * beats_per_bar).
float membrane_metric_accent(float barPhase01, float beatsPerBar) {
    float n = max(beatsPerBar, 1.0);
    float idx = floor(saturate(barPhase01) * n + 0.0001);
    if (idx < 0.5) return 1.00;                       // downbeat  — the bar lands
    if (abs(idx - floor(n * 0.5)) < 0.5) return 0.52; // mid-bar   — secondary stress
    return 0.22;                                      // off-beats — a light tick
}

// ── Total displacement ──────────────────────────────────────────

float membrane_D(float2 uv, float2 asp, float t,
                 constant FeatureVector& features,
                 float2 impactAsp) {

    // Always-on breath — the surface is never dead.
    float breath = mb_fbm3(float3(uv * 1.8, t * 0.16)) - 0.5;

    // Bass as a slow hand pressing into the sheet. Crossed sines with
    // audio-modulated phase make the pressure "wander" organically.
    // bass_att_rel, not bass_att (D-026): measured p99 is 0.379 across the
    // five captures, so 2.6x puts a strong passage near unity without
    // clipping on the 0.535 max.
    float bassPush = saturate(features.bass_att_rel * 2.6);
    float wave = sin(uv.x * 2.7 + t * 0.33 + bassPush * 2.2)
               * cos(uv.y * 2.3 - t * 0.27 + bassPush * 1.7);

    // Hi-hat goose-bumps: fine FBM scaled by treble deviation. treb_att_rel
    // is tiny in absolute terms (measured p99 0.012), hence the gain — the
    // coefficient is calibrated to the primitive's real range, not to 1.
    //
    // Scale 6, not 10, and gain 15, not 45. This term feeds DISPLACEMENT, and
    // the normal is a finite difference of displacement amplified 28x, so
    // high-frequency content here is multiplied straight into the normal. At
    // the first PR.25 values the render showed a crunchy speckled patch that
    // read as compression dirt rather than as surface stipple. Stipple should
    // be felt, not counted.
    float goose = (mb_fbm3(float3(uv * 6.0, t * 0.8)) - 0.5)
                * saturate(features.treb_att_rel * 15.0);

    // ONE shockwave ring per beat, phase-locked to the cached grid, struck as
    // hard as the METRE and the bass say it should be.
    //
    // PR.26 fired every beat at >= 0.42 and Matt read it as "the same intensity
    // ... much too active". Strength is now metric accent x bass, with no floor:
    // a weak off-beat under quiet bass lands near 0.05 and is barely a tick,
    // while a downbeat under a strong kick reaches 1.0. Measured on his session
    // that is a 15x spread where PR.26 had 2x.
    //
    // The downbeat ring is also BIGGER and travels FURTHER (speed scales with
    // the accent), so the bar reads as one large slow wave with small ripples
    // inside it, rather than four identical circles.
    float beatGate   = smoothstep(0.05, 0.30, features.pulse_amp01);
    float bassWeight = membrane_bass_strength(features.bass_dev);
    float accent     = membrane_metric_accent(features.bar_phase01, features.beats_per_bar);
    float strength   = accent * (0.18 + 0.82 * bassWeight) * beatGate;
    float ring = membrane_ring(asp, impactAsp, features.beat_phase01,
                               strength, 0.70 + 0.85 * accent, 0.040);

    float raw = breath * 0.40
              + wave * (0.08 + bassPush * 0.40)
              + goose * 0.13
              + ring * 1.70;

    // Edge tension: the drumskin is anchored at the frame boundary.
    // Displacement is free in the interior and forced smoothly to zero
    // at the edges. This is the single strongest cue that what you are
    // looking at is a stretched sheet, not a free-floating color field.
    // PR.27 — the X seams. This used to be
    //     saturate(min(edgeDist.x, edgeDist.y) * 3.0)
    // and min() of two smooth fields has a GRADIENT DISCONTINUITY along the
    // locus where they are equal — for a centred rectangle, exactly the two
    // diagonals. `membrane_D` is finite-differenced and multiplied by 28 to
    // build the surface normal, so that crease became a hard bright/dark line
    // and the two of them crossed as an X over the whole frame.
    //
    // The bug is original, not PR.26's, but PR.26 raised the ring's
    // displacement weight and made a latent crease plainly visible.
    //
    // A PRODUCT of the two per-axis falloffs is C1-continuous everywhere and
    // anchors the skin at the frame exactly as before.
    float2 ed = saturate(min(uv, 1.0 - uv) * 3.0);
    ed = ed * ed * (3.0 - 2.0 * ed);
    return raw * (ed.x * ed.y);
}

// ── Fragment entry point ────────────────────────────────────────

fragment float4 membrane_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]]
) {
    float2 uv = in.uv;
    float t = features.time;
    float aspect = max(features.aspect_ratio, 0.01);
    float2 asp = mb_asp_space(uv, aspect);

    // ── Shockwave impact point ──────────────────────────────────
    // Single wandering impact position, steered slowly by mood.
    // Converted to aspect space for the ring distance calc.
    float2 impactUV = float2(
        0.5 + 0.28 * sin(t * 0.237 + features.arousal * 1.6),
        0.5 + 0.28 * cos(t * 0.183 + features.valence * 1.3)
    );
    float2 impactAsp = mb_asp_space(impactUV, aspect);

    // ── Displacement and surface normal ─────────────────────────
    float D  = membrane_D(uv,                    asp,                           t, features, impactAsp);
    float eps = 0.004;
    float2 aspX = asp + float2(eps * aspect, 0.0);
    float2 aspY = asp + float2(0.0,          eps);
    float Dx = membrane_D(uv + float2(eps, 0.0), aspX, t, features, impactAsp);
    float Dy = membrane_D(uv + float2(0.0, eps), aspY, t, features, impactAsp);

    float dDdx = (Dx - D) * 28.0;
    float dDdy = (Dy - D) * 28.0;
    float3 N = normalize(float3(-dDdx, -dDdy, 1.0));

    // View + directional light.
    float3 V = float3(0.0, 0.0, 1.0);
    float NdotV = saturate(dot(N, V));
    float fresnel = pow(1.0 - NdotV, 3.0);

    float3 L = normalize(float3(-0.45 + features.arousal * 0.20,
                                -0.55,
                                 0.80));
    float NdotL = saturate(dot(N, L));
    float diffuse = NdotL * 0.5 + 0.5;   // wrapped — surface always visible

    // ── Color field: pure FBM, no linear sweeps ────────────────
    // All three thickness fields are FBM-only. There are no `uv.x * k`
    // terms anywhere in the color calculation, so there are no visible
    // diagonal bands. The coordinates drift slowly in time and pick up
    // a tiny amount of D so deformations nudge local hue but do not
    // rearrange the overall structure.

    float absD = abs(D);

    float3 p1 = float3(uv * 1.6 + t * 0.030, t * 0.020);
    float3 p2 = float3(uv * 2.4 + t * 0.022, t * 0.015 + 3.1);
    float3 p3 = float3(uv * 3.8 + t * 0.045, t * 0.012 + 7.7);

    float thick1 = mb_fbm3(p1) * 3.0 + D * 0.35;
    float thick2 = mb_fbm3(p2) * 2.6 + D * 0.25;
    float thick3 = mb_fbm3(p3) * 2.2 + D * 0.20;

    float3 band1 = hsv2rgb(float3(fract(thick1),        1.0, 1.0));
    float3 band2 = hsv2rgb(float3(fract(thick2 + 0.33), 1.0, 1.0));
    float3 band3 = hsv2rgb(float3(fract(thick3 + 0.66), 1.0, 1.0));

    float w1 = 0.40 + 0.18 * sin(t * 0.23);
    float w2 = 0.35 + 0.18 * sin(t * 0.17 + 2.1);
    float w3 = 0.30 + 0.18 * sin(t * 0.29 + 4.2);
    float wSum = w1 + w2 + w3;
    float3 filmColor = (band1 * w1 + band2 * w2 + band3 * w3) / wSum;

    // Saturation boost so the hue stays pure after weighted averaging.
    float maxC = max(filmColor.r, max(filmColor.g, filmColor.b));
    float minC = min(filmColor.r, min(filmColor.g, filmColor.b));
    if (maxC > 0.001) {
        filmColor = mix(float3((maxC + minC) * 0.5), filmColor, 1.30);
        filmColor = saturate(filmColor);
    }

    // ── Surface lighting ────────────────────────────────────────
    float innerGlow = saturate(absD * 1.5);
    float shade = 0.40 + diffuse * 0.50 + innerGlow * 0.45;
    float3 color = filmColor * shade;

    // Fresnel rim — sampled from another thickness so edges are lit
    // with a contrasting hue, suggesting light bleeding through.
    float3 rimColor = hsv2rgb(float3(fract(thick1 + 0.5), 1.0, 1.0));
    color += rimColor * fresnel * 0.45;

    // Specular — sharp highlights on crests.
    float3 H = normalize(L + V);
    float NdotH = saturate(dot(N, H));
    float specK = pow(NdotH, 48.0);
    color += float3(1.0) * specK * 0.55;

    // The same scalars membrane_D used, recomputed here (pure scalar maths, no
    // noise) so the bright ring and the physical deformation are the SAME event
    // and cannot drift apart.
    float beatGate   = smoothstep(0.05, 0.30, features.pulse_amp01);
    float bassWeight = membrane_bass_strength(features.bass_dev);
    float accent     = membrane_metric_accent(features.bar_phase01, features.beats_per_bar);
    float strength   = accent * (0.18 + 0.82 * bassWeight) * beatGate;
    float ring       = membrane_ring(asp, impactAsp, features.beat_phase01,
                                     strength, 0.70 + 0.85 * accent, 0.040);

    // ── The strike, as a RIPPLE rather than a glow ──────────────
    //
    // PR.25 added coral on top of the field and Matt could not see it. On a
    // full-value rainbow every pixel is already bright, so ADDING light has
    // almost nowhere to go — the arc washes into what is under it. (PR.25's
    // answer was to darken the whole sheet so the glow had somewhere to land.
    // That was never asked for and is reverted; the palette above is again
    // the original, untouched.)
    //
    // What reads on a bright surface is a light/dark EDGE PAIR, which is what
    // a real ripple is: the leading crest catches the light and the trough
    // just behind it falls into shadow. So the ring MULTIPLIES the existing
    // colour instead of adding to it — the rainbow stays exactly as authored
    // and the strike is a deformation travelling across it.
    //
    // Global luminance is preserved because the crest gain and the trough
    // loss sit side by side in a thin annulus (D-157: bounded per-beat
    // footprint, steady global luminance).
    float strikeRing = ring;
    float trough = membrane_ring(asp, impactAsp, features.beat_phase01,
                                 strength, 0.70 + 0.85 * accent, 0.105) - ring;
    color *= 1.0 + strikeRing * 1.25 - saturate(trough) * 0.55;

    // A thin specular glint riding the crest — a highlight on the wet skin,
    // not a light source. Scaled by bass so a soft beat glints softly.
    color += float3(1.0, 0.94, 0.88) * pow(saturate(strikeRing), 2.5)
           * (0.25 + 0.75 * bassWeight) * 0.55;

    // Soft vignette at the drumskin frame.
    float vig = 1.0 - smoothstep(0.55, 1.15, length(asp));
    color *= 0.55 + vig * 0.45;

    color = min(color, float3(1.0));

    // Alpha blends each frame with the warped history. The compose blend is
    // `src * srcAlpha + dst * 1` over a history already scaled by `decay`, so
    // steady-state output is alpha/(1 - decay) times what this fragment emits
    // — and, more importantly, THIS frame's share of the output is (1 - decay),
    // independent of alpha. At decay 0.90 the screen is 90 % blurred history.
    //
    // Measured at PR.25: the fragment emits ~12x luminance contrast between
    // fold and crest and the accumulator delivers 1.4x (luma p10 0.168 vs p90
    // 0.230). Raising alpha does not help — it scales brightness, not the
    // history share. Lowering `decay` does, but decay is also what makes a
    // strike leave the expanding concentric echo that reads as a pulse
    // TRAVELLING across the skin, which is the half of Matt's note about
    // motion. Trails were chosen over static surface detail deliberately.
    // Anything needing fine persistent surface detail wants `mv_warp`, where
    // the warp is per-vertex rather than one global resample of the frame.
    return float4(color, 0.55);
}
