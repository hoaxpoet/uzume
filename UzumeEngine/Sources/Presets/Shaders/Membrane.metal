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
// The exponentially-decaying beat pulse is the implicit timer. At the
// moment of the strike pulse = 1.0, and the ring sits at radius 0. As
// the pulse decays, -log(pulse) grows and the ring expands outward.
// No frame-to-frame state is required: the ring is always perfectly
// phase-locked to the beat pulse, regardless of framerate.
//
// Distance is computed in aspect-corrected space so the ring is an
// actual circle on screen, not an ellipse.

float membrane_ring(float2 asp, float2 impactAsp, float pulse,
                    float speed, float ageScale, float thicknessBase) {
    // Gate at 0.30, not 0.05. At the old threshold the ring was on screen on
    // 62 % of frames (median beat_bass was 0.090) — a hovering arc rather than
    // a strike. The sheet has to be EMPTY between hits for a hit to register.
    if (pulse < 0.30) return 0.0;
    float age = -log(max(pulse, 0.01)) * ageScale;
    float radius = age * speed;
    float thickness = thicknessBase + age * 0.08;
    float d = length(asp - impactAsp);
    float body = exp(-pow((d - radius) / thickness, 2.0));
    return max(body * (1.0 - age * 0.9), 0.0);
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

    // ONE shockwave ring per strike. `strike` is the decaying timer AND the
    // amplitude; `bassWeight` is the selector that keeps a drumless passage
    // quiet. bass_dev p99 is 0.652 pooled, so 1/0.65 normalises against the
    // real ceiling (FA #73) rather than against 1.0.
    float bassWeight = saturate(features.bass_dev * 1.54);
    float strike = features.spectral_level_rise * mix(0.25, 1.0, bassWeight);
    float ring = membrane_ring(asp, impactAsp, strike, 1.10, 0.20, 0.045);

    float raw = breath * 0.40
              + wave * (0.08 + bassPush * 0.40)
              + goose * 0.13
              + ring * 0.85;

    // Edge tension: the drumskin is anchored at the frame boundary.
    // Displacement is free in the interior and forced smoothly to zero
    // at the edges. This is the single strongest cue that what you are
    // looking at is a stretched sheet, not a free-floating color field.
    float2 edgeDist = min(uv, 1.0 - uv);
    float edgeFactor = saturate(min(edgeDist.x, edgeDist.y) * 3.0);
    edgeFactor = edgeFactor * edgeFactor * (3.0 - 2.0 * edgeFactor);
    return raw * edgeFactor;
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

    // ── The sheet's own light and shade ─────────────────────────
    //
    // This is the part the first PR.25 pass got wrong and the render caught:
    // deleting the rainbow removed the ONLY thing that varied across the
    // frame, and the result was a flat pink wall. Hue was carrying all the
    // structure. It should never have been — a stretched translucent sheet
    // is read by where it is THICK and where it is THIN, i.e. by luminance.
    //
    // So `tone` is the primary structural channel and hue is a passenger.
    // smoothstep pushes it to genuine darks and genuine lights instead of
    // hovering around the mean, which is what gives the surface zones at all.
    // Detail cascade (SHADER_CRAFT §12 mandatory slot). `mb_fbm3` is 4 octaves
    // of value noise with no inter-octave rotation, and every field here was
    // evaluated at uv * 1.6 — one and a half cells across the whole frame. The
    // render showed the consequence: a smooth low-frequency gradient with no
    // surface at any scale a viewer can read. The accumulator's warp blurs
    // spatial detail every frame, so whatever structure the sheet has must be
    // emitted with real contrast at several scales or it washes out.
    //
    // `fbm8` (8 Perlin octaves, inter-octave rotation, Utilities/Noise/FBM.metal)
    // supplies macro / meso / micro in one family. Colour path only — the
    // displacement path still uses the cheap mb_fbm3 because membrane_D is
    // evaluated three times per fragment for the normal's finite difference.
    float macro = fbm8(float3(uv * 1.7, t * 0.035));            // whole-frame zoning
    float meso  = fbm8(float3(uv * 5.4, t * 0.055 + 11.0));     // fold structure
    float micro = fbm8(float3(uv * 15.0, t * 0.090 + 23.0));    // surface grain

    // fbm8 returns ~[-1,1]; fold to 0..1, then bias toward real darks and real
    // lights instead of clustering at the mean.
    float tone = saturate(macro * 0.5 + 0.5 + meso * 0.22 + micro * 0.085);
    tone = smoothstep(0.20, 0.80, tone);
    float toneFine = saturate(meso * 0.5 + 0.5 + micro * 0.30);

    // Hue rides a NARROW arc and is TIED TO TONE: the deep folds sit at
    // `--purple` (oklch 292 deg -> ~0.78 HSV) and the lit crests warm toward
    // `--coral` (~28 deg -> ~0.05), the short way round through 1.0. That is
    // how a backlit film behaves — the thin, bright places pass warm light.
    // Previously each band was `fract(fbm * 3.0)`, wrapping the full spectrum
    // ~3x per frame: that is where the rainbow came from.
    const float MB_HUE_BASE = 0.78;      // --purple, the sheet at rest
    const float MB_HUE_ARC  = 0.27;      // -> coral, through 1.0/0.0

    float warmth = saturate(tone * 0.62 + toneFine * 0.20) * 0.80;
    float hue = fract(MB_HUE_BASE + warmth * MB_HUE_ARC);

    // Saturation falls as the sheet lights up — deep folds hold the colour,
    // crests bleach toward the light. Flat 1.0 everywhere was poster paint.
    float sat = mix(0.80, 0.30, warmth);
    float3 filmColor = hsv2rgb(float3(hue, sat, 1.0));

    // A second, slower field breaks the surface into distinct regions so the
    // frame is not one continuous gradient (the >= 3 distinct zones the
    // fidelity rubric asks for, read here as zones of the same material).
    float zone = smoothstep(0.35, 0.65, macro * 0.35 + 0.5 + meso * 0.30);
    filmColor = mix(filmColor, filmColor * float3(0.72, 0.80, 1.08), zone * 0.55);
    // The 1.30x saturation boost that used to sit here is gone. It was
    // compensating for the hue averaging washing three OPPOSITE hues toward
    // grey; inside a narrow arc the average stays in-family on its own.

    // ── Surface lighting ────────────────────────────────────────
    // Ambient floor 0.07, not 0.40. The old floor meant no pixel was ever
    // darker than 40 % — there was no negative space anywhere on screen, so
    // nothing could read as bright BY CONTRAST. A drumhead in a dim room is
    // mostly dark; the light is what the strike brings. Still comfortably
    // above the D-037 non-black requirement (the breath FBM keeps `diffuse`
    // and `innerGlow` moving at silence, so the surface is visible and alive).
    // `tone` carries the structure; `diffuse` only modulates it. Ambient floor
    // 0.05, not 0.40 — the old floor meant no pixel was ever darker than 40 %,
    // so there was no negative space on screen and nothing could read as bright
    // BY CONTRAST. A drumhead in a dim room is mostly dark; the light is what
    // the strike brings. Still well above the D-037 non-black requirement: the
    // breath FBM keeps `tone`, `diffuse` and `innerGlow` moving at silence, so
    // the surface stays visible and alive with no audio at all.
    float innerGlow = saturate(absD * 1.5);
    float shade = 0.05 + tone * 0.46 + diffuse * 0.16 + innerGlow * 0.50;

    // ── MB_SHEET_LEVEL: the accumulator has gain, so the sheet must be dim ──
    //
    // The `feedback` composite is ADDITIVE over a decayed history, so the
    // steady-state brightness is roughly alpha/(1 - decay) times whatever this
    // fragment emits — about 5.5x at the sidecar's decay 0.90. Emitting a
    // mid-bright field therefore saturates the accumulator no matter how the
    // colour is authored, which is why the first two PR.25 passes still had a
    // p01 luma of 0.30: there was no dark left ANYWHERE for a strike to stand
    // out against. Measured, not reasoned — the harness prints luma percentiles.
    //
    // So the sheet is emitted dim and the accumulator does the lifting. The
    // strike below is emitted an order of magnitude hotter, so it survives the
    // same gain as a genuine highlight rather than as one more mid-tone.
    const float MB_SHEET_LEVEL = 0.135;
    float3 color = filmColor * shade * MB_SHEET_LEVEL;

    // Fresnel rim — light bleeding through the stretched sheet at grazing
    // angles. Sampled a short way along the SAME arc, not the opposite side
    // of the colour wheel, so the rim reads as thickness rather than as a
    // second unrelated material.
    float3 rimColor = hsv2rgb(float3(fract(MB_HUE_BASE + 0.12), 0.55, 1.0));
    color += rimColor * fresnel * 0.030;

    // Specular — sharp highlights on crests. Warm rather than pure white:
    // a white lobe on a purple sheet reads as a lighting bug (PR.18 —
    // "a specular lobe is a highlight, not the light").
    float3 H = normalize(L + V);
    float NdotH = saturate(dot(N, H));
    float specK = pow(NdotH, 48.0);
    color += float3(1.00, 0.86, 0.78) * specK * 0.075;

    // ── The strike ──────────────────────────────────────────────
    // Coral along the travelling ring — §18.3's "energy, action... should
    // feel like warmth arriving", which is exactly what a hit on a drumhead
    // is. Same `strike` envelope the displacement uses, so the bright ring
    // and the physical deformation are the same event, not two that drift.
    float bassWeight = saturate(features.bass_dev * 1.54);
    float strike = features.spectral_level_rise * mix(0.25, 1.0, bassWeight);
    float flash = membrane_ring(asp, impactAsp, strike, 1.10, 0.20, 0.045) * strike;
    const float3 MB_CORAL = float3(1.00, 0.48, 0.36);   // --coral
    color += MB_CORAL * flash * 1.30;

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
