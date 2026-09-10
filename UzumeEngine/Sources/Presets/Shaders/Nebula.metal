// Nebula — v2 — radial spectrum as a nebula: log-frequency ring, core, haze, sparkles.
//
// v2 (PR.19) answers Matt's roster note — *"Needs better sync with music. Spikes are
// too sporadic. Should look more activated."* — with five measured mechanisms, not
// a re-tune. Every number below came from `NebulaSpectrumDiagnosticTests` run against
// real `raw_tap.wav` captures through the production FFT (FA #27).
//
//  1. THE RING WAS A LOPSIDED FAN, and no gain could have fixed it. v1 mapped bin
//     index to angle LINEARLY — `bin = normalizedAngle * 256` — but musical energy is
//     distributed logarithmically and concentrated at the bottom. Measured: the first
//     EIGHTH of the circle carried 63.8 % of ring energy, and everything below 250 Hz
//     (27.2 % of the energy) was crammed into 2.0 % of the circle. Three quarters of
//     the ring was drawing bins with nothing in them. Angle is now LOG frequency.
//
//  2. THE BAND WAS PINNED AT ITS FLOOR. `saturate(mag * 8.0)` sat under 0.02 on 58 %
//     of samples (75 % on a quieter track) and exceeded 0.5 on 2.8 %. `bandRadius`
//     measured p50 = 0.0848 against a floor of 0.08 — half the ring within 0.5 % of
//     its minimum. One linear gain cannot serve a distribution whose p50→p99 spans
//     ~100x: lift the median and the peaks clip; keep the peaks and the median is
//     invisible. The response is now LOGARITHMIC, which is what a spectrum display
//     uses and what measurement independently picked (3 % at floor, 1 % saturated,
//     against linear-x8's 31 % saturated on the same aggregated input).
//
//  3. THE RING WAS SPATIALLY NOISY. Neighbour-to-neighbour |Δmag| measured 0.60x the
//     mean magnitude — on BOTH test tracks, so it is a property of raw FFT bins, not
//     of the material. That is the "sporadic spikes" complaint at one instant, with
//     no motion involved. Aggregating each angular position over the bins its
//     log-spaced band actually covers takes it to **0.09x** — a 6.7x reduction, for
//     free, because averaging N independent noisy bins cuts variance by sqrt(N).
//
//  4. IT WAS LEVEL-DEPENDENT. Raw magnitudes carry no AGC, so activation tracked
//     absolute mix level: the quieter of two tracks sat at the floor 75 % of the time
//     against 58 %. Overall reach is now driven from D-026 deviation primitives.
//
//  5. NOTHING WAS DECLARED. The sidecar had no `audio_routes`, so QG.1 gated none of
//     this. Nine routes are declared now.
//
// Entry point: preset_fragment (direct pass, no per-preset state).

// ── Spectrum mapping ──────────────────────────────────────────────────────────
//
// 40 Hz – 8 kHz chosen by sweep, not by taste: it is the flattest energy spread that
// still leaves bass meaningful. Measured share per eighth of the circle —
//   linear (v1):  63.8  10.6   7.1   5.8   4.3   3.3   2.8   2.3   spread 27.7x
//   40-8k, tilt 0.5:  6.5  24.7  31.1  12.4  10.4   6.9   4.2   3.8   spread  8.2x
// A steeper tilt flattens further but starves the bass (tilt 0.75 puts the first
// eighth at 4.2 %), and bass is the part a listener feels.

constant float kFreqLo   = 40.0;     // Hz at angle 0
constant float kFreqHi   = 8000.0;   // Hz at angle 2*pi
constant float kTilt     = 0.5;      // amplitude ∝ sqrt(f) — the +3 dB/octave pink slope
constant float kLogGain  = 90.0;     // response knee, chosen from the measured distribution
constant int   kFFTBins  = 512;
constant float kBinHz    = 46.875;   // 48 kHz / 1024-point FFT

// Window width in angular positions. 5 was picked from the continuity sweep: it takes
// broken steps from 18.9 % to 6.8 % (4.0 % with the wider band below) while each
// position still resolves about 1/51 of the frequency range. 8 smooths further and
// starts flattening the peaks that make a spectrum worth looking at.
constant float kOverlap = 5.0;

// ★ THE FLOOR MUST CLEAR THE CORE, or the ring is not a ring. A quiet angular sector
//   draws its band at `kRadiusFloor`; at 0.10 that sat on top of the core glow (which
//   reaches ~0.08) and was swallowed by it, so the quiet part of the circle simply
//   vanished and what survived read as a fan. Raising the floor clear of the core means
//   even a silent sector still draws a visible arc, and the ring reads as a closed
//   circle whose RADIUS undulates — which is the thing a spectrum ring is supposed to
//   be. The outer reach is unchanged at 0.42.
constant float kRadiusFloor = 0.16;
constant float kRadiusSpan  = 0.26;

/// Mean magnitude across the FFT bins one angular position covers, tilt-compensated.
///
/// The aggregation is the load-bearing part — see mechanism 3. At the top of the range
/// one angular position spans many bins and averaging them removes the bin-to-bin
/// noise; at the bottom one bin spans many positions and the ring reads smooth because
/// it genuinely is. v1 read a single bin per position and lerped to its neighbour,
/// which smooths nothing: two adjacent noisy samples are still noise.
static float nebulaBand(constant float* fft, float angle01) {
    // ★ THE WINDOW OVERLAPS ITS NEIGHBOURS, and that is what makes this read as a RING
    //   rather than a starburst. With disjoint windows nothing couples adjacent angular
    //   positions, so the radius is free to jump between them: measured, **18.9 % of
    //   neighbouring positions stepped further than the band was thick**, with a p99
    //   step 3.7x the mean width — a band that cannot connect to its neighbour draws a
    //   spoke. Widening each window to span `kOverlap` positions makes neighbours share
    //   most of their bins, which smooths the RADIUS directly instead of hiding the
    //   problem by blurring the drawn band. Measured: 18.9 % -> 4.0 % broken.
    //
    //   Note this is a different quantity from mechanism 3's magnitude smoothing, and
    //   measuring that one was not enough: the log response' slope is steepest near
    //   zero, so a spectrum that is smooth in MAGNITUDE can still be jagged in RADIUS.
    // NOT named `half` — that is an MSL type and shadowing it is Failed Approach #44,
    // which the preamble warns about by name and which this shader hit anyway. The
    // symptom is `presetNotFound` at load, not a compile message in the test output.
    float halfSpan = kOverlap * 0.5 / 256.0;
    float a0 = max(0.0, angle01 - halfSpan);
    float a1 = min(1.0, angle01 + halfSpan);
    float h0 = kFreqLo * pow(kFreqHi / kFreqLo, a0);
    float h1 = kFreqLo * pow(kFreqHi / kFreqLo, a1);

    int b0 = clamp(int(h0 / kBinHz), 0, kFFTBins - 1);
    int b1 = clamp(int(h1 / kBinHz) + 1, b0 + 1, kFFTBins);

    float acc = 0.0;
    for (int b = b0; b < b1; b++) { acc += fft[b]; }
    float mean = acc / float(b1 - b0);

    // Pink-slope compensation: natural spectra fall ~1/f, so without this the top of
    // the circle is permanently dark however the gain is set.
    return mean * pow(h0 / kFreqLo, kTilt);
}

/// Logarithmic response. Measured against the alternatives on the same aggregated
/// input: linear x8 saturated 31 % of samples, sqrt 43 %, pow-0.4 60 %; this one sits
/// at 3 % floored and 1 % saturated with p50 mid-range. A visualiser wants the whole
/// range used, which is exactly what a dB-like curve does to a heavy-tailed signal.
static float nebulaResponse(float x) {
    return saturate(log(1.0 + max(x, 0.0) * kLogGain) / log(1.0 + kLogGain));
}

// ── Scene fragment ─────────────────────────────────────────────────────────────

fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    float t = features.time;
    float3 color = float3(0.0);

    // Centered coordinates. Aspect-corrected so the ring is a CIRCLE on a 16:9
    // display — v1 worked in raw UV, which stretched it into the ellipse visible in
    // every capture.
    float2 center = uv - 0.5;
    center.x *= max(features.aspect_ratio, 0.0001);
    float radius = length(center);
    float angle = atan2(center.y, center.x);
    float angle01 = (angle + M_PI_F) / (2.0 * M_PI_F);

    // ── Audio drivers ─────────────────────────────────────────────────────────
    //
    // D-026: the SHAPE of the ring comes from the spectrum, its REACH from deviation
    // primitives. That split is what makes the preset behave the same on a quiet
    // mix and a loud one — mechanism 4. `bass`/`mid`/`treble` are AGC-smoothed, so
    // they also give the envelope a temporal steadiness the raw bins do not have
    // (measured temporal volatility 0.40x mean even after aggregation).
    float activity = saturate(0.35
                            + max(0.0, features.bass_att_rel) * 0.40
                            + max(0.0, features.mid_att_rel) * 0.30
                            + max(0.0, features.treb_dev) * 0.20);
    float presence = saturate((features.bass + features.mid + features.treble) * 0.5);
    float beatPulse = max(features.beat_bass, features.beat_composite);

    // ── Radial spectrum band ──────────────────────────────────────────────────
    float band = nebulaResponse(nebulaBand(fftMagnitudes, angle01));

    float bandRadius = kRadiusFloor + band * kRadiusSpan * (0.55 + activity * 0.45);
    // x1.4 on the measured width: with the overlap above it takes broken steps from
    // 6.8 % to 4.0 %, and a slightly thicker filament is what closes a ring visually.
    float bandWidth  = (0.012 + band * 0.024) * 1.4;

    float bandDist = radius - bandRadius;
    float bandMask = exp(-bandDist * bandDist / (2.0 * bandWidth * bandWidth));

    // ── Colour: hue follows FREQUENCY, which is now angle ─────────────────────
    // Deep blue/violet at the bass end through cyan to hot pink at the top, so the
    // hue sweep and the frequency sweep agree — in v1 the hue tracked bin index,
    // which was the same thing, but the circle only ever showed one end of it.
    // ★ THE DRIFT WAS A FULL PALETTE ROTATION. v1 carried `t * 0.02`, which is three
    //   complete trips around the hue circle over a 200 s track — it went unnoticed
    //   because v1's ring occupied a sliver and only ever showed one hue at a time.
    //   With the circle now filled, that drift walks the whole preset through green,
    //   yellow and orange, outside its stated description ("deep purples and blues for
    //   low frequencies, hot pinks for highs"). The sweep is now bounded: blue at the
    //   bass end through violet to magenta at the top, with a slow wobble.
    //
    //   ⚠ AN EARLIER VERSION OF THIS NOTE ALSO CITED `color_temperature_range`, AND THAT
    //     WAS WRONG. That sidecar field is a PLANNER hint — `PresetScorer.moodSubScore`
    //     reads its midpoint to match a preset against a track's valence (warm for happy,
    //     cool for sad). It constrains which SONGS reach this preset, not which hues the
    //     shader may draw. Nothing structural bounds the palette; the bound below is a
    //     choice, made from the description, and is Matt's to widen.
    // Matt, 2026-09-10, after seeing three candidates rendered on his own session:
    // the WIDER sweep. 0.45 -> 1.00 spans teal and green at the bass end, through blue
    // and violet, to magenta and a warm accent at the top — roughly 200 degrees of hue
    // against v2's first cut at 115. It keeps the cool anchor that puts this preset in
    // the ambient/comedown slot while answering "are there colours beyond purples and
    // magentas". The full visible spectrum (red at the bass) was the third candidate and
    // was NOT chosen: it starts to read as a rainbow analyser, and "rainbow layer cake"
    // is an explicit anti-reference in Stave's set.
    // PR.20 — the whole band rotates by the TRACK. Any single moment stays coherent (one
    // song is teals and blues, the next ambers and golds), so the playlist gets variety
    // without any one frame being a rainbow. This is why the full-spectrum candidate was
    // not needed: the variety comes from the track axis, not from widening the instant.
    float hue = fract(0.45 + features.track_hue_anchor01
                      + angle01 * 0.55 + sin(t * 0.035) * 0.02);
    float sat = 0.62 + band * 0.28;
    float val = bandMask * (0.35 + band * 0.65) * (0.6 + activity * 0.4);
    color += hsv2rgb(float3(hue, sat, val));

    // ── Inner core glow ───────────────────────────────────────────────────────
    // Driven by presence + the beat accent rather than a raw 64-bin sum (v1's
    // `totalEnergy` measured p50 0.148 / p99 0.439 — it never reached the top third
    // of its own range, so the core was permanently dim).
    float coreRadius = 0.045 + presence * 0.035 + beatPulse * 0.012;
    float coreDist = radius / coreRadius;
    float coreGlow = exp(-coreDist * coreDist * 2.0) * (0.30 + presence * 0.55);
    color += float3(0.55, 0.40, 1.0) * coreGlow;

    // ── Outer nebula haze ─────────────────────────────────────────────────────
    // Slow counter-rotation against the ring so the two layers read as separate
    // depths rather than one rigid object.
    float hazeAngle = angle - t * 0.09;
    float haze = sin(hazeAngle * 3.0 + t * 0.11) * 0.5 + 0.5;
    haze *= sin(hazeAngle * 7.0 - t * 0.23) * 0.5 + 0.5;
    // FA #67 — the haze does NOT share the core's primitive. Both layers were driven by
    // `presence` in the first cut, which is the one-primitive-per-layer trap: the same
    // information pushed through two visual channels reads as the preset fighting
    // itself. The haze is the slow outer layer, so it takes the slow signal (arousal),
    // leaving the band's energy to the core.
    float mood = saturate(features.arousal * 0.5 + 0.5);
    float hazeFade = exp(-radius * 2.4) * (0.08 + mood * 0.26);
    color += float3(0.32, 0.16, 0.52) * haze * hazeFade;

    // ── Sparkles at spectral peaks ────────────────────────────────────────────
    // Gated on the band being genuinely strong HERE, so sparkles mark peaks instead
    // of dusting the whole ring. v1 multiplied by `smoothMag`, which was at the floor
    // 58 % of the time — the sparkles were effectively invisible.
    float sparkleAngle = angle01 * 96.0;
    float sparkleFrac = fract(sparkleAngle);
    float sparkleMask = smoothstep(0.42, 0.5, sparkleFrac) * smoothstep(0.58, 0.5, sparkleFrac);
    float peakness = smoothstep(0.45, 0.85, band);
    sparkleMask *= exp(-bandDist * bandDist / 0.00035) * peakness;
    color += float3(1.0, 0.92, 1.0) * sparkleMask * (0.45 + max(0.0, features.treb_dev) * 0.8);

    // ── Vignette ──────────────────────────────────────────────────────────────
    float vignette = 1.0 - radius * 0.7;
    color *= max(vignette, 0.0);

    // D-037: silence must not render black — the core and haze hold a dim floor.
    color = min(color, float3(1.0));
    return float4(color, 1.0);
}
