// Gossamer.metal — v4 — bioluminescent web as sonic resonator.
//
// v4 (PR.18) — the V.8 fidelity uplift. v3's geometry was correct and is UNTOUCHED:
// the 17 explicit spoke angles, the 7-turn spiral, the off-centre hub at (0.465, 0.32)
// all carry over verbatim. What v3 lacked was every surface property, which is why it
// read as a drafting diagram rather than an instrument — `SHADER_CRAFT.md §10.2` and
// `docs/VISUAL_REFERENCES/gossamer/README.md` specified all of the following and none
// of it had been built:
//
//   · MICRO — silk Marschner-lite material (`mat_silk_thread`, §4.3) at the README's own
//     coefficients (azimuthal_r 0.08, azimuthal_tt 0.5). Each strand now carries a
//     CYLINDRICAL cross-section normal, so a thread reads as a round lit filament rather
//     than a flat stroke. This is the single largest change.
//   · MESO — per-strand irregularity from `fbm4` (4 octaves, the §12 floor): width,
//     brightness, out-of-plane tilt and a small transverse waver all vary along every
//     thread and differ per strand. Real silk is not ruler gauge.
//   · SPECULAR — node glints where spoke crosses spiral, on the strands' HALOES rather
//     than on the ~1 px hard cores (v3's `spokeCov * spirCov` reached almost no pixels).
//     Chromatic aberration on the highest-amplitude wave peaks.
//   · ATMOSPHERE — a bioluminescent haze halo carrying the waves' own colour into the
//     air around the web, plus dust motes drifting inward at high vocal energy and
//     outward at silence.
//
// And the MESO item the reference set's anti-reference explicitly forbids:
//   · Waves now physically DISPLACE the silk. v3 multiplied a wave tint onto strands that
//     had already been drawn — `99_anti_reference.jpg` is annotated "NOT this — uniform
//     palette-shift waves with no perpendicular strand displacement". The wave field is
//     now resolved BEFORE the geometry and pushes the sample point radially.
//
// Two defects fixed on the way:
//   · `strandCov` was applied to the wave layer TWICE (v3 lines 211 and 226), attenuating
//     the preset's signature audio-visual layer by coverage SQUARED on every soft pixel.
//   · Brightness was driven by absolute `f.bass` at SIX TIMES the weight of its deviation
//     term, so the web's dynamics tracked mix density rather than musical events. The
//     ratio is now inverted — absolute for presence, deviation for dynamics (D-026). NB:
//     this is a ratio fault, not FA #31, which bans absolute THRESHOLDS; see the note at
//     the brightness site, and the gate that caught an over-literal first fix.
//
// Entry point: gossamer_fragment
// Buffer layout: unchanged from v1–v3 (see GossamerState.swift).
// D-026 deviation-first. D-019 warmup. D-037 invariants met.

// ── GPU wave types ─────────────────────────────────────────────────────────────

struct WaveGPU {
    float age;
    float hue;
    float saturation;
    float amplitude;
};

struct GossamerGPU {
    uint  wave_count;
    uint  _pad0, _pad1, _pad2;
    WaveGPU waves[32];
};

// ── Constants ─────────────────────────────────────────────────────────────────

constant float kWebRadius   = 0.44;   // outer capture zone (UV)
constant float kHubRadius   = 0.050;  // free zone near hub — no spiral threads
constant float kSpiralTurns = 7.0;
constant float kWaveSpeed   = 0.12;   // UV/sec — must match GossamerState.waveSpeed
constant float kMaxWaveLife = 6.0;    // seconds — must match GossamerState.maxWaveLifetime

// Ring width of a travelling wave, in UV. Shared by the displacement pass and the
// colour pass so the silk moves exactly where it lights up.
constant float kWaveRingSigma = 0.010;

// V.8 silk coefficients, verbatim from docs/VISUAL_REFERENCES/gossamer/README.md.
// (`absorption` is carried for completeness; `mat_silk_thread` does not read it —
// see the note in ENGINEERING_PLAN.md PR.18.)
constant float kSilkAzimuthalR  = 0.08;
constant float kSilkAzimuthalTT = 0.50;
constant float kSilkAbsorption  = 0.30;

// ── Explicit spoke angles ──────────────────────────────────────────────────────
//
// 17 angles in radians. 0 = right (+X), π/2 = down (+Y in UV space).
// Hub is at (0.465, 0.32) — upper-centre. Spokes radiate from there.
//
// Design: web built at a ceiling/wall junction.
//   • Upper-left cluster (-2.82, -2.48, -2.15): three tight ceiling anchors.
//   • Left wall (-1.78, -1.42, -1.08): regular wall anchors.
//   • Right-of-centre (-0.72 … 0.58): mixed upper-right anchors.
//   • OPEN SECTOR 0.58 → 1.35 (0.77 rad): lower-right has no surface to anchor.
//   • Lower arc (1.35 … 2.95): threads hang toward lower-left anchor.
//
// The irregular gaps (min 0.27, max 0.77 rad) produce visible clustering and
// absence — the web is a product of its anchoring, not a compass rose.

// ★ THE DIRECTIONS ARE PRECOMPUTED. `kSpokeAngles` is a `constant` array, but indexing
//   it in a loop defeats constant folding, so v3 evaluated 17 `cos` and 17 `sin` for
//   EVERY pixel of a fullscreen pass — 34 transcendentals to rebuild a table that never
//   changes. `kSpokeDirs` is that table, written out. The angles stay as the readable,
//   authoritative form (D-042 is expressed in radians); the vectors below are derived
//   from them and `spokeDirectionTableMatchesAngles` in GossamerStateTests holds the two
//   in agreement so a future edit to one cannot silently diverge from the other.
constant int   kSpokeCount   = 17;
constant float kSpokeAngles[17] = {
    -2.82f, -2.48f, -2.15f,   // upper-left cluster (tight, 0.34/0.33 rad)
    -1.78f, -1.42f, -1.08f,   // left wall (0.37/0.36/0.34 rad)
    -0.72f, -0.38f, -0.08f,   // right-of-centre (0.34/0.30 rad)
     0.25f,  0.58f,            // right side (0.33/0.33 rad)
    //                         ← gap: 0.77 rad, lower-right open sector
     1.35f,  1.65f,  1.92f,   // lower-left (0.30/0.27 rad — tight cluster)
     2.28f,  2.62f,  2.95f    // lower anchor threads (0.36/0.34/0.33 rad)
};

constant float2 kSpokeDirs[17] = {
    float2(-0.948733219f, -0.316077964f),
    float2(-0.789014747f, -0.614374258f),
    float2(-0.547357665f, -0.836898791f),
    float2(-0.207681002f, -0.978196607f),
    float2(+0.150225470f, -0.988651763f),
    float2(+0.471328364f, -0.881957807f),
    float2(+0.751805729f, -0.659384672f),
    float2(+0.928664636f, -0.370920469f),
    float2(+0.996801706f, -0.079914694f),
    float2(+0.968912422f, +0.247403959f),
    float2(+0.836462650f, +0.548023937f),
    float2(+0.219006687f, +0.975723358f),
    float2(-0.079120889f, +0.996865028f),
    float2(-0.342149651f, +0.939645474f),
    float2(-0.651229661f, +0.758880708f),
    float2(-0.867026721f, +0.498261642f),
    float2(-0.981702203f, +0.190422647f)
};

// ── Per-strand irregularity ───────────────────────────────────────────────────
//
// ONE `fbm4` evaluation per strand layer, gated on being anywhere near a thread.
// Four octaves is the §12 quality floor exactly; v3 had none at all.
//
// The three inputs are deliberate: `arc` runs ALONG the thread so the character
// varies down its length; `id` separates strands so no two are alike (the §2.3
// "no two strands identical in tension/sag" trait); `t` drifts slowly so silk
// breathes rather than reading as a frozen texture.

static float gossamerStrandNoise(float arc, float id, float t) {
    // ★ SCALED, because raw `fbm8` is the wrong AMPLITUDE for this job. Its output is a
    //   normalised octave sum in [-1, 1] whose mass sits near zero — typical |value| is
    //   ~0.2, so a "±35 % width variation" driven by it raw is ±7 %, which is under a
    //   pixel at 1080p and reads as no variation at all. The first cut of this shader had
    //   the noise wired correctly and invisible. 2.4x puts the common case near ±0.5 with
    //   occasional excursions to the rails, which is what "no two strands alike" needs.
    // `fbm4`, not `fbm8`. The §12 floor is FOUR octaves and this is a low-frequency
    // modulator on thread width, sag and tilt — octaves 5-8 land below a pixel at 1080p
    // and cannot be seen, while costing the same eight Perlin evaluations as the ones that
    // can. Measured: fbm8 put Gossamer at 1.5x the roster median against v3's 1.0x, which
    // is a real cost for no visible return.
    return clamp(fbm4(float3(arc * 5.5, id * 11.3, t * 0.06)) * 2.4, -1.0, 1.0);
}

// ── Spoke geometry ────────────────────────────────────────────────────────────
//
// v4 returns the SIGNED cross-track offset and the along-track arc for the nearest
// spoke, not just the absolute distance. The sign is what lets the strand be shaded
// as a cylinder (offset → cross-section normal) instead of as a flat stroke, and the
// arc is the coordinate the irregularity noise runs along.

struct GossamerStrandHit {
    float signedDist;   // signed cross-track offset, 0 on the thread's centre line
    float arc;          // distance along the thread from the hub
    float2 tangent;     // unit tangent in UV space
    float id;           // strand identity, for decorrelating the noise
    float scallop;      // 0 at a spoke anchor, 1 midway between two — see below
    float gap;          // angular width of the sector this pixel sits in, radians
};

// ── The scallop ───────────────────────────────────────────────────────────────
//
// THE single most web-like thing v3 was missing, and the reason its capture spiral
// read as a polar grid: a real orb-weaver's spiral is a CATENARY strung between
// consecutive spokes. It is pinned where it crosses each radial and sags outward in
// between, so the ring is a chain of shallow scallops rather than a circle — and the
// deeper the sector, the deeper the sag, which is why the lower-right open sector
// (0.77 rad, the widest gap in D-042's array) should visibly droop.
//
// `scallop` is sin(pi * u) over the fractional position between the two bracketing
// spokes, so it is exactly zero on every anchor and 1 at mid-span. `gap` carries the
// sector width so the amplitude scales with span rather than being uniform.

static GossamerStrandHit gossamerNearestSpoke(float2 pRel) {
    GossamerStrandHit hit;
    hit.signedDist = 1e6;
    hit.arc        = 0.0;
    hit.tangent    = float2(1.0, 0.0);
    hit.id         = 0.0;
    hit.scallop    = 0.0;
    hit.gap        = 0.35;

    float theta   = atan2(pRel.y, pRel.x);
    float best    = 1e6;
    float aheadCW = 1e6;   // smallest positive angular step to a spoke
    float behind  = 1e6;   // smallest negative step, as a magnitude

    for (int i = 0; i < kSpokeCount; i++) {
        float2 d = kSpokeDirs[i];
        float  s = pRel.x * d.y - pRel.y * d.x;   // signed perpendicular offset
        float  a = dot(pRel, d);                  // along-thread arc
        // A spoke is a RAY from the hub, not a line: behind the hub it does not exist.
        if (a >= 0.0 && abs(s) < best) {
            best           = abs(s);
            hit.signedDist = s;
            hit.arc        = a;
            hit.tangent    = d;
            hit.id         = float(i);
        }
        // Bracketing pair, for the scallop. Both operands are already in [-pi, pi],
        // so the wrap is two compares rather than an atan2.
        float dA = theta - kSpokeAngles[i];
        if (dA >  M_PI_F) dA -= 2.0 * M_PI_F;
        if (dA < -M_PI_F) dA += 2.0 * M_PI_F;
        if (dA >= 0.0) { aheadCW = min(aheadCW, dA); }
        else           { behind  = min(behind, -dA); }
    }

    float span = aheadCW + behind;
    if (span > 1e-4 && span < 2.0) {
        hit.gap     = span;
        hit.scallop = sin(saturate(behind / span) * M_PI_F);
    }
    return hit;
}

// ── Capture spiral ─────────────────────────────────────────────────────────────
// Radial ring-spacing formula: fold × kWebRadius / kSpiralTurns.
// All rings have equal radial width regardless of radius.
// Free zone r < kHubRadius and outer zone r > kWebRadius return 1e6.
//
// v4: signed, for the same cylindrical-normal reason as the spokes. `fold` in
// [0, 0.5] becomes `sf` in [-0.5, 0.5], zero on the thread.

static GossamerStrandHit gossamerSpiralHit(float2 pRel, float r) {
    GossamerStrandHit hit;
    hit.signedDist = 1e6;
    hit.arc        = 0.0;
    hit.tangent    = float2(0.0, 1.0);
    hit.id         = 0.0;
    hit.scallop    = 0.0;
    hit.gap        = 0.35;
    if (r < kHubRadius || r > kWebRadius) return hit;

    float theta = atan2(pRel.y, pRel.x);
    float coord = theta - (r / kWebRadius) * kSpiralTurns * 2.0 * M_PI_F;
    float f     = fract(coord / (2.0 * M_PI_F));
    float sf    = (f < 0.5) ? f : f - 1.0;        // signed fold, 0 ON thread

    hit.signedDist = sf * kWebRadius / kSpiralTurns;
    // ★ ARC RUNS ALONG THE RING, not radially. The first cut set this to `r`, which is
    //   CONSTANT around a ring — so every pixel of one ring drew the same noise value,
    //   each ring got a single uniform offset, and the spiral stayed a mathematically
    //   perfect ellipse with the irregularity wired up and doing nothing visible.
    hit.arc        = (theta + M_PI_F) * r;
    // The spiral runs nearly tangentially; the radial term is small at 7 turns.
    hit.tangent    = (r > 0.001) ? normalize(float2(-pRel.y, pRel.x) / r) : float2(0.0, 1.0);
    hit.id         = floor(coord / (2.0 * M_PI_F)) * 0.37 + 5.0;
    return hit;
}

// ── Hub stabilimentum ─────────────────────────────────────────────────────────
// Tight concentric rings in the free zone — dense and dark, not a spotlight.

static float gossamerHubDist(float r) {
    if (r > kHubRadius) return 1e6;
    float coord = r / kHubRadius * 3.0;
    float hf    = fract(coord);
    return min(hf, 1.0 - hf) * kHubRadius / 3.0;   // 0 ON ring, max in gap
}

// ── Silk shading ──────────────────────────────────────────────────────────────
//
// One strand layer → one lit colour. The cylindrical cross-section normal is the
// load-bearing part: `u` is the fractional offset across the thread's width, so
// `sqrt(1 - u²)` reconstructs the round profile a real filament presents to the
// camera, and the wrapped-lambert term against it is what stops the thread reading
// as a flat ribbon of constant colour.
//
// `tilt` lifts the fiber tangent out of the web's plane. Without it a perfectly
// planar web gives `dot(T, V) == 0` for every strand, which kills the TT lobe
// identically — the back-lit warmth would never fire anywhere. Real webs are not
// planar; this is faithful as well as necessary.

static float3 gossamerSilk(
    float2 tangent2, float u, float tilt, float grain, float3 tint, float3 L, float3 V
) {
    float2 perp2 = float2(-tangent2.y, tangent2.x);
    float  uc    = clamp(u, -1.0, 1.0);
    float3 nrm   = normalize(float3(perp2 * uc, sqrt(max(0.0, 1.0 - uc * uc))));

    FiberParams fp;
    fp.fiber_tangent = normalize(float3(tangent2, tilt));
    fp.fiber_normal  = nrm;
    fp.azimuthal_r   = kSilkAzimuthalR;
    fp.azimuthal_tt  = kSilkAzimuthalTT;
    fp.absorption    = kSilkAbsorption;
    fp.tint          = tint;

    MaterialResult m = mat_silk_thread(float3(0.0), fp, L, V);

    // ★ THE LOBES ARE A HIGHLIGHT, NOT THE WHOLE LIGHT. `azimuthal_r = 0.08` is a very
    //   narrow cuticle cone by design — `exp(-theta_h^2 / 2*0.0064)` is ~0 unless the
    //   light is nearly aligned with the thread — so returning `m.emission` alone leaves
    //   every non-highlighted strand at almost zero and the web reads ten times dimmer
    //   than v3. That is the correct behaviour for a specular lobe and the wrong thing to
    //   light a thread with. The BODY is a wrapped-lambert term against the cylindrical
    //   cross-section normal (which is what makes the thread read round), and the R and TT
    //   lobes ride on top of it — so the few strands the key light happens to align with
    //   flare, exactly as they do in `03_lighting_emission_filament_strands.jpg`.
    float ndl = saturate(dot(m.normal, L) * 0.5 + 0.5);

    // The THIRD lobe. §4.3 says Marschner-lite "fakes TRT as a secondary rim", and
    // `mat_silk_thread` does not — it returns R and TT only. `fiber_trt_lobe` is the
    // missing piece and it already exists in `Utilities/PBR/Fiber.metal` (FA #73: do not
    // write a second one). It places a soft highlight on the far-side rim, which is what
    // separates a lit cylinder from a lit ribbon when the key light swings past.
    float trt = fiber_trt_lobe(fp.fiber_tangent, L, V, 0.35);

    // MICRO grain: silk is not optically smooth at thread scale. Modulates the body only,
    // so it textures the filament without flickering the specular.
    float3 body = m.albedo * (0.56 + 0.44 * ndl) * (0.86 + 0.14 * grain);
    return body + m.emission + tint * trt * 0.18;
}

// ── Scene fragment ─────────────────────────────────────────────────────────────

fragment float4 gossamer_fragment(
    VertexOut               in     [[stage_in]],
    constant FeatureVector& f      [[buffer(0)]],
    constant float*         fft    [[buffer(1)]],
    constant float*         wv     [[buffer(2)]],
    constant StemFeatures&  stems  [[buffer(3)]],
    constant GossamerGPU&   gState [[buffer(6)]]
) {
    // Hub at upper portion of screen — proximity to top edge clips upper spiral
    // rings into asymmetric arcs, giving the web its natural hanging shape.
    float2 hub  = float2(0.465, 0.32);
    float2 uv   = in.uv;
    float2 pRel = uv - hub;
    float  r    = length(pRel);

    // ── D-019 warmup ─────────────────────────────────────────────────────────
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02, 0.06, totalStemEnergy);

    // ── Audio drivers (D-026 deviation-first) ────────────────────────────────
    float bassRel   = mix(f.bass_att_rel,   stems.bass_energy_rel,   stemMix);
    float midRel    = mix(f.mid_att_rel,    stems.vocals_energy_rel, stemMix);
    float vocalRel  = mix(f.mid_att_rel,    stems.vocals_energy_rel, stemMix);
    float beatPulse = max(f.beat_bass, max(f.beat_mid, f.beat_composite));

    // ── Motion: strand tremor ─────────────────────────────────────────────────
    // Standing-wave envelope: zero at hub and rim, peak at mid-radius.
    // Amplitude 0.018 UV ≈ 19px at 1080p — clearly visible.
    float vibEnv   = sin(saturate(r / kWebRadius) * M_PI_F);
    float vibPhase = f.beat_phase01 * 2.0 * M_PI_F;
    float radVib   = vibEnv * sin(vibPhase)        * max(-1.0, bassRel) * 0.018;
    float spirVib  = vibEnv * sin(vibPhase + 0.85) * max(-1.0, midRel)  * 0.012;

    float2 tangent = r > 0.001 ? float2(-pRel.y, pRel.x) / r : float2(0.0, 1.0);
    float2 tRel    = pRel + tangent * (radVib + spirVib);

    // ── MESO: the waves physically displace the silk ──────────────────────────
    //
    // Resolved BEFORE the geometry, which is the whole point — v3 tinted strands
    // that had already been drawn, and that is exactly what the curated
    // anti-reference forbids. Each live wave is a ring at `age × speed`; where the
    // ring crosses a strand it pushes the sample point radially, so the thread
    // itself bows outward as the front passes and returns behind it.
    float rPre        = length(tRel);
    float2 radialDir  = rPre > 0.001 ? tRel / rPre : float2(0.0, 1.0);
    float  wavePush   = 0.0;
    float  peakAmp    = 0.0;

    for (uint i = 0; i < gState.wave_count; i++) {
        WaveGPU wave = gState.waves[i];
        if (wave.age <= 0.0 || wave.age >= kMaxWaveLife) continue;

        float waveRadius = wave.age * kWaveSpeed;
        float dr         = rPre - waveRadius;
        float ring       = exp(-(dr * dr) / (kWaveRingSigma * kWaveRingSigma));
        float lifeFrac   = wave.age / kMaxWaveLife;
        float fade       = smoothstep(0.0, 0.05, lifeFrac) * smoothstep(1.0, 0.60, lifeFrac);
        float amp        = max(wave.amplitude, 0.40) * fade;

        // Signed by which side of the front we are on, so the strand is dragged
        // ahead of the crest and released behind it rather than swelling both ways.
        wavePush += ring * amp * 0.016 * -sign(dr);
        peakAmp   = max(peakAmp, ring * amp);
    }

    tRel += radialDir * wavePush;
    float rT = length(tRel);

    // ── Web geometry ──────────────────────────────────────────────────────────
    GossamerStrandHit spoke = gossamerNearestSpoke(tRel);

    // The capture spiral is strung BETWEEN spokes and sags outward in between (see
    // `gossamerNearestSpoke`). Evaluating the spiral at a radius pulled inward by the
    // scallop is what draws the thread outward there — the sign is the usual one for a
    // distance field: move the sample, and the surface appears to move the other way.
    // Amplitude scales with the sector's angular span, so D-042's 0.77 rad open sector
    // droops visibly more than the 0.27 rad clusters, which is the whole point of having
    // irregular anchors in the first place.
    // Amplitude is proportional to the CHORD the thread spans — 2*r*sin(gap/2), so
    // r * gap to first order. Without the radial term the tight inner rings sagged as
    // deeply as the outer ones and the web read as a doily of petals rather than as
    // silk under tension.
    float scallopSag         = spoke.scallop * spoke.gap * rT * 0.075;
    GossamerStrandHit spiral = gossamerSpiralHit(tRel, rT - scallopSag);
    float hubDist            = gossamerHubDist(rT);

    float taper = saturate(rT / kWebRadius);

    // ── MESO: per-strand irregularity ─────────────────────────────────────────
    //
    // Gated on being within a few thread widths of a strand — an ungated `fbm8`
    // over every pixel of a fullscreen pass is BUG-098's signature.
    float spokeAbs = abs(spoke.signedDist);
    float spirAbs  = abs(spiral.signedDist);
    float nearSpoke = step(spokeAbs, 0.010);
    float nearSpir  = step(spirAbs,  0.008);

    float spokeNoise = 0.0, spirNoise = 0.0, microGrain = 0.0;
    if (nearSpoke > 0.0) {
        spokeNoise = gossamerStrandNoise(spoke.arc, spoke.id, f.accumulated_audio_time);
    }
    if (nearSpir > 0.0) {
        spirNoise = gossamerStrandNoise(spiral.arc * 2.4, spiral.id, f.accumulated_audio_time);
    }
    // MICRO — surface grain along the thread, an order of magnitude finer than the
    // strand-character scale above. This is the third rung of the detail cascade
    // (§12 M1 wants three distinct noise scales, not three octaves of one).
    if (nearSpoke > 0.0 || nearSpir > 0.0) {
        float arc  = nearSpoke > 0.0 ? spoke.arc : spiral.arc;
        float band = nearSpoke > 0.0 ? spoke.id  : spiral.id;
        // ONE octave. At 48x scale octaves 2-4 are already sub-pixel at 1080p — they
        // alias rather than add detail, and cost four Perlin evaluations to do it.
        microGrain = perlin3d(float3(arc * 48.0, band * 3.1, 0.0));
    }

    // Width varies ±35 % along a thread and differs per strand; brightness follows
    // it, because a thinner section of real silk catches less light.
    float spokeWidth = mix(0.0028, 0.0016, taper) * (1.0 + spokeNoise * 0.45);
    float spirWidth  = 0.0015 * (1.0 + spirNoise * 0.45);
    float hubWidth   = 0.0012;
    float aaW        = 0.0007;

    // Transverse SAG. A dead-straight ray from hub to rim is most of what reads as
    // "drawn with a ruler", so each thread wanders off its ideal line — under an envelope
    // that is zero at both ends, because silk is anchored at the hub and at the rim and
    // can only depart from the straight line in between.
    float spokeSag = sin(saturate(spoke.arc / kWebRadius) * M_PI_F);
    // `spiral.arc` now runs AROUND the ring, so the radial envelope comes from rT.
    float spirSag  = sin(saturate((rT - kHubRadius)
                                  / max(kWebRadius - kHubRadius, 1e-4)) * M_PI_F);
    float spokeOff = spoke.signedDist  + spokeNoise * 0.0060 * spokeSag;
    float spirOff  = spiral.signedDist + spirNoise  * 0.0022 * spirSag;

    // ── Anti-aliased strand coverage ─────────────────────────────────────────
    // Spokes extend past kWebRadius with exponential fade — they're anchored.
    // The open sector on the lower-right will simply have no spoke there.
    float anchorFade = rT > kWebRadius ? exp(-(rT - kWebRadius) * 5.0) : 1.0;
    float spokeCov   = smoothstep(spokeWidth + aaW, spokeWidth - aaW, abs(spokeOff)) * anchorFade;
    // The hub is where all 17 spoke haloes overlap, so their sum there is ~17x what it is
    // anywhere else — and then the feedback accumulates it. Fading the HALO (not the core)
    // out of the hub keeps the stabilimentum readable instead of a white disc.
    float spokeHalo  = exp(-spokeOff * spokeOff / (0.006 * 0.006)) * 0.45 * anchorFade
                     * smoothstep(0.0, 0.040, rT);

    float inCapture  = (rT >= kHubRadius && rT <= kWebRadius) ? 1.0 : 0.0;
    float inHub      = (rT < kHubRadius)                      ? 1.0 : 0.0;
    float spirCov    = smoothstep(spirWidth + aaW, spirWidth - aaW, abs(spirOff)) * inCapture;
    float spirHalo   = exp(-spirOff * spirOff / (0.0042 * 0.0042)) * 0.30 * inCapture;
    float hubCov     = smoothstep(hubWidth + aaW, hubWidth - aaW, hubDist) * 0.65 * inHub;

    float strandCov  = max(max(spokeCov, spirCov), max(max(spokeHalo, spirHalo), hubCov));

    // ── Beat brightness flash ─────────────────────────────────────────────────
    float beatFlash = beatPulse * 0.18;

    // ── Slow hue drift ────────────────────────────────────────────────────────
    float hueDrift  = fract(f.accumulated_audio_time * 0.020 + f.mid_att_rel * 0.05);
    float3 driftTint = hsv2rgb(float3(hueDrift, 0.48, 0.80));

    // ── Base strand tint ──────────────────────────────────────────────────────
    //
    // ★ THE FAULT IN v3 WAS THE RATIO, NOT THE PRESENCE OF AN ABSOLUTE TERM — and
    //   PR.18's first cut got that wrong and broke a gate proving it.
    //
    //   v3 read `0.12 + f.bass * 0.76 + bassRel * 0.12`: an absolute AGC-normalised band
    //   carrying SIX TIMES the weight of its deviation term, so the web's dynamics tracked
    //   the AGC's running-average denominator — mix density — rather than musical events.
    //   That ratio is the defect. But FA #31 bans absolute THRESHOLDS
    //   (`smoothstep(0.22, 0.32, f.bass)`), whose breakpoint lands in a different place on
    //   every track; a smooth proportional term has no breakpoint to misplace, and D-037
    //   REQUIRES a silence state distinguishable from a playing one. The only signal that
    //   separates those two is absolute energy — every deviation primitive is ~0 in both.
    //
    //   Removing it entirely made silence and a steady mid-energy passage render
    //   IDENTICALLY, and `PresetAcceptanceTests` caught it: continuous motion collapsed to
    //   zero, so every scrap of motion the preset had left was beat response — an
    //   inversion of D-004, produced by an over-literal reading of FA #31.
    //
    //   So: an absolute term for PRESENCE (silent → dim, playing → lit), deviation for
    //   DYNAMICS, and the ratio inverted from v3's. The beat flash comes down with it,
    //   because beats are accents (D-004) and a 0.30 flash was sized against a brightness
    //   range that no longer exists.
    float3 nearColor  = float3(0.22, 0.70, 0.88);
    float3 rimColor   = float3(0.08, 0.28, 0.70);
    float3 baseColor  = mix(mix(nearColor, rimColor, taper), driftTint, 0.18);
    // ★ CALIBRATED AGAINST v3 THROUGH THE FEEDBACK PATH, not against the direct render.
    //   `mv_warp` at decay 0.955 has ~22x gain on anything that holds still, so a scene
    //   that looks right as a single frame arrives far hotter once it accumulates. The
    //   first cut of v4 measured meanLuma 0.300 against v3's 0.219 and clipped 3.2x as
    //   many pixels on the same 240-frame replay — brighter than a build Matt had already
    //   signed off on. These figures put the body back on v3's level and leave the
    //   saturation gain (0.288 -> 0.327) intact.
    // Whichever source is warm: the stem sum before the crossfade completes, the
    // FeatureVector bands after. Both are absolute, both are used proportionally.
    float  fvEnergy    = (f.bass + f.mid + f.treble) * (1.0 / 3.0);
    float  presence    = max(saturate(totalStemEnergy * 3.0), saturate(fvEnergy));
    float  brightness  = 0.11 + presence * 0.40
                       + max(0.0, bassRel) * 0.32 + max(0.0, midRel) * 0.14;

    // ── MICRO: silk material ──────────────────────────────────────────────────
    //
    // The V.8 headline. `mat_silk_thread` (§4.3) at the reference README's own
    // coefficients, evaluated per strand layer with that layer's own tangent and
    // cross-section offset. The key light orbits slowly and sits BEHIND the web
    // plane (negative z), so the TT lobe's back-lit warmth actually fires — a
    // front-lit key would only ever show the R lobe.
    float  lightAng = f.accumulated_audio_time * 0.11;
    float3 L        = normalize(float3(cos(lightAng) * 0.72, sin(lightAng) * 0.72, -0.42));
    float3 V        = float3(0.0, 0.0, 1.0);

    float3 tint       = baseColor * max(0.10, brightness) * (1.0 + beatFlash);

    // ★ GATED ON COVERAGE. `mat_silk_thread` costs an `acos`, a `pow` and two
    //   `normalize`s per call and this makes two of them; run unconditionally it paid
    //   that on every background pixel, whose result is then multiplied by a coverage of
    //   zero. That is BUG-098's exact shape — expensive per-pixel work on a fullscreen
    //   pass that is not gated by what consumes it.
    float3 baseStrand = float3(0.0);
    bool   onStrand   = strandCov > 0.0005;
    if (onStrand) {
        float3 spokeLit  = gossamerSilk(spoke.tangent,  spokeOff / max(spokeWidth, 1e-5),
                                        spokeNoise * 0.45, microGrain, tint, L, V);
        float3 spiralLit = gossamerSilk(spiral.tangent, spirOff / max(spirWidth, 1e-5),
                                        spirNoise * 0.45, microGrain, tint, L, V);
        // Blend the two layers by which one this pixel actually belongs to, so a
        // crossing does not average two unrelated fiber orientations into mush.
        float spokeShare = max(spokeCov, spokeHalo);
        float spirShare  = max(spirCov,  spirHalo);
        float shareSum   = max(spokeShare + spirShare, 1e-4);
        baseStrand = (spokeLit * spokeShare + spiralLit * spirShare) / shareSum;
        // The hub rings are not fiber-shaded — they are the stabilimentum, a dense pad.
        baseStrand = mix(baseStrand, tint * 0.85, saturate(hubCov * 1.4));
    }

    // ── Propagating colour waves, with chromatic aberration ───────────────────
    //
    // Sampled at three slightly offset radii so the highest-amplitude fronts fringe
    // cyan→magenta at their edges (`06_specular_chromatic_aberration.jpg`). The
    // offset scales with amplitude: quiet waves stay clean, loud ones prism.
    float3 waveContrib = float3(0.0);
    float3 waveField   = float3(0.0);   // the same energy WITHOUT coverage — see haze

    for (uint i = 0; i < gState.wave_count; i++) {
        WaveGPU wave = gState.waves[i];
        if (wave.age <= 0.0 || wave.age >= kMaxWaveLife) continue;

        float waveRadius = wave.age * kWaveSpeed;
        float lifeFrac   = wave.age / kMaxWaveLife;
        float fade       = smoothstep(0.0, 0.05, lifeFrac) * smoothstep(1.0, 0.60, lifeFrac);

        float wSat  = max(wave.saturation, 0.60);
        float wAmp  = max(wave.amplitude,  0.40);
        float3 wCol = hsv2rgb(float3(wave.hue, wSat, wAmp));

        // The centre tap is always needed — the haze reads the wave field everywhere.
        // The two aberration taps are only ever SEEN on a strand, because `waveContrib`
        // is multiplied by coverage at the composite, so off-strand they are two more
        // `exp` calls per wave per pixel for a result that is about to be zeroed.
        float  dr0  = rT - waveRadius;
        float  ring0 = exp(-(dr0 * dr0) / (kWaveRingSigma * kWaveRingSigma));
        waveField += wCol * ring0 * fade;
        if (!onStrand) { continue; }

        float ca = 0.0022 * wAmp;
        float3 ring = float3(ring0);
        for (int c = 0; c < 3; c += 2) {
            float rr = rT + (float(c) - 1.0) * ca;
            float dr = rr - waveRadius;
            ring[c]  = exp(-(dr * dr) / (kWaveRingSigma * kWaveRingSigma));
        }
        waveContrib += wCol * ring * fade;
    }

    // ★ v3 multiplied `waveContrib` by `strandCov` HERE and again at the composite,
    //   attenuating the wave layer by coverage SQUARED — at 0.3 coverage the wave
    //   arrived 3.3x dimmer than intended, and only the ~1 px hard cores were
    //   unaffected. The single multiply lives at the composite.

    // ── SPECULAR: node glints ─────────────────────────────────────────────────
    //
    // v3 used `spokeCov * spirCov` — the product of two ~1 px HARD cores, which
    // intersect on almost no pixels, so the trait was in the code and not on the
    // screen. Glints now ride the strands' proximity fields, so every crossing
    // carries one. Colour is deliberately NOT the strand's: slot 03 of the
    // reference set records a teal strand body with a yellow-white tip, and it is
    // that separation, not the brightness alone, that reads as wet silk.
    float glintNear = exp(-spokeOff * spokeOff / (0.0026 * 0.0026))
                    * exp(-spirOff  * spirOff  / (0.0022 * 0.0022)) * inCapture;
    // Modulated by the strands' own irregularity so only SOME crossings catch the light.
    // An equal bright dot at every node reads as beading, and the reference README is
    // explicit that dewdrops are an *Arachne* trait, "explicitly not Gossamer's".
    //
    // ★ AND IT HAS TO OUT-BRIGHTEN THE THREAD. The first cut set this gain against v3's
    //   near-black strands; once the silk body was lit correctly the glints sat BELOW the
    //   strands they are supposed to punctuate and vanished. A glint reads as a glint only
    //   when it is brighter than the filament it sits on.
    float glintVary = saturate(0.30 + (spokeNoise + spirNoise) * 0.55);
    float glintGain = (0.85 + max(0.0, f.treb_dev) * 1.5 + peakAmp * 1.0) * glintVary;
    float3 glint    = mix(float3(1.0, 0.96, 0.86), float3(0.86, 0.98, 1.0), taper)
                    * glintNear * glintGain;

    // ── ATMOSPHERE: bioluminescent haze + dust motes ──────────────────────────
    //
    // The README's `09_atmosphere_volumetric_halo_primary.jpg` trait: the air around
    // the web is itself luminous, not unlit black with a web on top. The haze carries
    // the WAVES' colour, so the web's own emission is what lights the medium — which
    // is also the SSGI fill of §10.2.6 in the form this 2D preset can express.
    // A shell, not a disc: the halo is the air AROUND the web, and peaking it at r = 0
    // stacks it on the one place that is already brightest.
    float  halo     = exp(-(r * r) / (0.30 * 0.30)) * smoothstep(0.0, 0.11, r);
    // MACRO — the medium itself has structure. `09_atmosphere_volumetric_halo_primary.jpg`
    // is annotated "the blue glow exists in the medium itself"; a perfectly smooth radial
    // falloff reads as a lens flare rather than as luminous air. Gated on the halo, so the
    // frame's dark majority never pays for it.
    //
    // ★ ONE OCTAVE, AND UNGATED ON PURPOSE. The first cut called `fbm4` behind
    //   `if (halo > 0.01)`, which sounds gated and is not: that threshold is true out to
    //   r = 0.64, i.e. most of the frame, so nearly every pixel paid four Perlin
    //   evaluations and Gossamer went from 1.2x the roster median to 1.8x. A smooth
    //   medium-density variation wants one low-frequency octave anyway — the branch was
    //   buying nothing and hiding the cost behind a condition that reads like a guard.
    float hazeGrain = 0.78 + 0.22 * (perlin3d(float3(pRel * 2.2,
                                     f.accumulated_audio_time * 0.03)) * 0.5 + 0.5);
    float3 hazeCol  = (waveField * 0.16 + baseColor * (0.05 + 0.10 * stemMix)) * hazeGrain;
    float3 haze     = hazeCol * halo * (0.34 + max(0.0, vocalRel) * 0.34);

    // Dust motes on a jittered lattice, drifting radially — INWARD at high vocal energy
    // and OUTWARD at silence (§10.2.5). The sign of the drift term does that directly,
    // so the behaviour is one expression rather than a branch.
    //
    // ★ THE LATTICE IS CARTESIAN, not polar. A polar lattice (angle, radius) has cells
    //   whose aspect ratio changes with radius, so the motes smeared into long tangential
    //   streaks at the frame edge instead of reading as dust. Drift is applied by sliding
    //   the sample point along the radial direction, which keeps the motion radial while
    //   the cells stay square.
    float2 outward   = r > 0.001 ? pRel / r : float2(0.0, 1.0);
    float  moteDrift = f.accumulated_audio_time * (max(0.0, vocalRel) * 0.055 - 0.012);
    float2 moteCoord = (pRel - outward * moteDrift) * 34.0;
    float2 cell      = floor(moteCoord);
    float2 within    = fract(moteCoord) - hash_f01_2x(cell);
    float  moteD     = dot(within, within);
    float  moteSeed  = hash_f01_2(cell + 3.7);
    // Cool white to neutral, never orange — a warm cast on a fine speckle reads as grit
    // on the lens rather than as lit dust, and the mv_warp echo smears each mote into a
    // short radial streak that makes the cast more obvious, not less.
    float3 motes     = mix(float3(0.62, 0.86, 1.0), float3(1.00, 0.97, 0.90), moteSeed)
                     * exp(-moteD * 90.0) * step(0.72, moteSeed)
                     * halo * (0.17 + max(0.0, vocalRel) * 0.34);

    // ── Background (dark night sky) ────────────────────────────────────────────
    float  gv    = saturate(f.valence * 0.5 + 0.5);
    float  ga    = saturate(f.arousal * 0.5 + 0.5);
    float3 bgLow  = mix(float3(0.004, 0.004, 0.016), float3(0.008, 0.014, 0.006), ga);
    float3 bgHigh = mix(float3(0.004, 0.008, 0.036), float3(0.014, 0.008, 0.022), ga);
    float3 bgColor = mix(bgLow, bgHigh, uv.y * gv);

    // ── Composite ─────────────────────────────────────────────────────────────
    float3 webColor   = strandCov * (baseStrand + waveContrib) + glint;
    float3 finalColor = webColor + haze + motes + bgColor;
    finalColor = min(finalColor, float3(0.95));

    return float4(finalColor, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// Required by preamble forward declarations (D-027). Both must be present.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
    pf.warp = 0.0;

    pf.zoom  = 1.0 + f.bass_att_rel * 0.010 + f.mid_att_rel * 0.006;
    pf.rot   = f.mid_att_rel * 0.003;
    pf.decay = 0.955;

    pf.q1 = f.bass_att_rel;
    pf.q2 = f.mid_att_rel;
    pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;

    float  zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed  = p * zoomAmt + centre;

    float wobble = (pf.q1 * 0.012 + pf.q2 * 0.008) * rad;
    return zoomed + p * wobble;
}
