// EnergeticFlyby.metal — Faithful MSL port of Kali's "Energetic Flyby" (working name).
//
// Source: Kali, "[Inércia 2022] Energetic Flyby", Shadertoy csjGDD
// (https://www.shadertoy.com/view/csjGDD), live-coded at Inércia Shader Royale 2022 (4th place).
// Kali's algorithm and constants are kept verbatim except the cost changes listed below. Design of record: docs/presets/ENERGETIC_FLYBY_DESIGN.md.
//
// BINDINGS (the only adaptations; EFB.1 task 1):
//   • `time`             → st.time, the state's wall clock (EnergeticFlybyState: ∫ dt)
//   • `t` in mainImage   → st.travel (the flight position, ∫ speed dt); `from` uses st.camT
//   • `time` in coso     → st.spin (Kali spun the spheres at `time`)
//   • `so`               → st.flicker, faithful mode only (Kali: fract(sin(time)*123.456), a per-frame
//                          strobe — 15.5 flashes/s on the flash train, so the shipped path drops it)
//   • iResolution / gl_FragCoord → in.uv + features.aspect_ratio; y flipped (Uzume uv.y = 0 is top)
//   • GLSL globals (br, tub, hit, pos, sphpos) → a thread struct passed by reference (MSL has no
//     mutable globals); functions prefixed `efb_` (the preamble shares one namespace)
//   • output → sRGB-decoded before the store: Shadertoy writes display values straight to 8 bits,
//     the drawable is `_srgb` (the Kagura precedent), so the displayed bytes equal Kali's
//   • the 200-step loop as written
//
// COST (Matt, 2026-10-19: native resolution, no upscaling; 30 fps accepted on a Tier-1 Mac). Kali's march
// at native 2560×1440 is p50 56 / p95 73 ms on an M2 Pro. Four changes, each marked `EFB (cost)`, bring it
// to p50 ~16 / p95 ~21 ms: ONE sphere system instead of three (his flanking pp ± .7 systems are dropped),
// steps of 0.6 of the distance bound instead of 0.3 with the per-step glow weighted ×2 to keep his
// brightness, a 100-step cap, and a 3.3 depth cut-off (his geometry is black past 3). At Kali's own glow
// level the result matches his mean colour within 0.01 and his saturation within 0.01 (EFB.1 side-by-side).
//
// MUSIC + PHOTOSENSITIVITY (design doc §3–§5; every change is marked `EFB:`):
//   • Kali's flicker is replaced by a steady glow level (st.glowBase, his 1.25 average at a typical passage)
//   • glow colour turn (`hue`) on the downbeat; quarter-turn bank (`roll`) every second downbeat
//   • energy → flight speed (st.travel) and glow floor (st.glowBase); bass → st.spin
//   • the one-frame white-out fix: the rods are probed at the camera, glow × mix(.3, 1, …)
//   • no camera park: Kali's `if (mod(time,10.)>5.)` hold is gone; st.camT == st.travel on the
//     shipped path. EFB_FAITHFUL=1 (EnergeticFlybyState) feeds Kali's own behaviour back in through
//     these same fields for the reference comparison — the only shader branch is `st.faithful`.
//
// ── LICENCE — THIS FILE IS NOT MIT ────────────────────────────────────────────
// The code in this file is adapted from "[Inércia 2022] Energetic Flyby" by Kali,
// https://www.shadertoy.com/view/csjGDD. The source carries no licence header, so Shadertoy's
// default terms apply: the Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported
// License (CC BY-NC-SA 3.0), https://creativecommons.org/licenses/by-nc-sa/3.0/. Under ShareAlike
// this adaptation is distributed under the same CC BY-NC-SA 3.0 licence; it is NOT covered by
// Uzume's MIT licence and may not be used commercially. See docs/CREDITS.md and D-252.

// MARK: - State (EnergeticFlybyState.swift, fragment buffer 6)

/// 48 bytes; must match `EnergeticFlybyStateGPU` in EnergeticFlybyState.swift byte-for-byte.
struct EnergeticFlybyStateGPU {
    float time;       // Kali's `time`: tunnel twist + breathing, fractal texture, view sway
    float travel;     // flight position on path(): the sphere cluster and the look-at
    float camT;       // camera position on path(): == travel (faithful mode: Kali's 5 s park)
    float spin;       // sphere spin phase (bass)
    float flicker;    // faithful mode only: Kali's `so`
    float glowBase;   // glow floor (energy)
    float hue;        // glow colour turn, radians (downbeat)
    float roll;       // camera bank, radians (every second downbeat)
    float faithful;   // 1 = Kali's glow + no white-out fix (reference comparison only)
    float pad0, pad1, pad2;
};

// MARK: - Kali's globals

struct EFBMarch {
    float br, tub, hit;
    float3 pos, sphpos;
    float time, spin;
};

constant float kEFBDet = .001;
/// EFB (cost, Matt 2026-10-19): Kali steps 0.3 of the distance bound; 0.6 halves the steps. The glow
/// is a per-step sum, so each step's glow is weighted by the same ratio to keep Kali's brightness.
constant float kEFBStep = .6;
/// EFB (white-out fix): ray length over which rod glow fades in while a rod is at the camera.
constant float kEFBCamFade = .3;
constant float kEFBGlowPerStep = kEFBStep / .3;

// MARK: - Kali's functions (verbatim)

static float3x3 efb_lookat(float3 dir, float3 up) {
    float3 rt = normalize(cross(dir, up));
    return float3x3(rt, cross(rt, dir), dir);
}

static float3 efb_path(float t) {
    return float3(sin(t + cos(t) * .5) * .5, cos(t * .5), t);
}

static float2x2 efb_rot(float a) {
    float s = sin(a);
    float c = cos(a);
    return float2x2(float2(c, s), float2(-s, c));
}

static float3 efb_fractal(float2 p, float time) {
    p = fract(p * .1);
    float m = 1000.;
    for (int i = 0; i < 7; i++) {
        p = abs(p) / clamp(abs(p.x * p.y), .25, 2.) - 1.2;
        m = min(m, abs(p.y) + fract(p.x * .3 + time * .5 + float(i) * .25));
    }
    m = exp(-6. * m);
    return m * float3(abs(p.x), m, abs(p.y));
}

static float efb_coso(float3 pp, thread EFBMarch& k) {
    pp *= .7;
    pp.xy = pp.xy * efb_rot(pp.z * 2.);
    pp.xz = pp.xz * efb_rot(k.spin * 2.);   // EFB: Kali's `time` → spin (bass)
    pp.yz = pp.yz * efb_rot(k.spin);
    float sph = length(pp) - .04;
    sph -= length(sin(pp * 40.)) * .05;
    sph = max(sph, -length(pp) + .11);
    float br2 = length(pp) - .03;
    br2 = min(br2, length(pp.xy) + .005);
    br2 = min(br2, length(pp.xz) + .005);
    br2 = min(br2, length(pp.yz) + .005);
    br2 = max(br2, length(pp) - 1.);
    k.br = min(br2, k.br);
    float d = min(k.br, sph);
    return d;
}

static float efb_de(float3 p, thread EFBMarch& k) {
    float time = k.time;
    k.hit = 0.;
    k.br = 1000.;
    float3 pp = p - k.sphpos;
    p.xy -= efb_path(p.z).xy;
    p.xy = p.xy * efb_rot(p.z + time * .5);
    float s = sin(p.z * .5 + time * .5);
    p.xy *= 1.3 - s * s * .7;

    for (int i = 0; i < 6; i++) {
        p = abs(p) - .4;
    }
    k.pos = p;
    k.tub = -length(p.xy) + .45 + sin(p.z * 10.) * .1 * smoothstep(.4, .5, abs(.5 - fract(p.z * .05)) * 2.);
    float co = efb_coso(pp, k);   // EFB (cost): Kali's two flanking sphere systems (pp ± .7) are dropped
    float d = min(k.tub, co);
    if (d == k.tub) k.hit = step(fract(.1 * length(sin(p * 10.))), .05);
    return d * kEFBStep;   // EFB (cost): Kali .3
}

static float3 efb_march(float3 from, float3 dir, thread EFBMarch& k,
                        constant EnergeticFlybyStateGPU& st) {
    float time = k.time;
    float2 uv = float2(atan2(dir.x, dir.y) + time * .5, length(dir.xy) + sin(time * .2));
    float3 col = efb_fractal(uv, time);
    float d = 0., td = 0., g = 0., ref = 0., ltd = 0., li = 0.;
    float3 p = from;
    // EFB (design §5, the white-out fix): when a spinning rod sweeps through the camera every ray
    // starts inside it and `g` saturates the whole frame for one frame (05_anti_whole_frame_whiteout).
    // Probe the rods at the camera and pull the glow down while one is there.
    k.br = 1000.;
    {
        efb_coso(from - k.sphpos, k);
    }
    float camGlow = smoothstep(.0, .2, k.br);
    for (int i = 0; i < 100; i++) {   // EFB (cost): Kali 200; with 2× steps 100 covers the same depth
        p += dir * d;
        d = efb_de(p, k);
        if (d < kEFBDet && ref == 0. && k.hit == 1.) {
            float2 e = float2(0., .1);
            float3 n = normalize(float3(efb_de(p + e.yxx, k), efb_de(p + e.xyx, k), efb_de(p + e.xxy, k)) - efb_de(p, k));
            p -= dir * d * 2.;
            dir = reflect(dir, n);
            ref = 1.;
            td = 0.;
            ltd = td;
            continue;
        }
        if (d < kEFBDet || td > 3.3) break;   // EFB (cost): Kali 5; geometry fades to black at 3 (f = 1 - td/3)
        td += d;
        // EFB (white-out fix): with a rod at the camera every ray starts inside it, and the rod glow
        // gathered in the first steps whites out the frame (05_anti_whole_frame_whiteout). Fade in only
        // that near-camera glow, only while a rod is there (camGlow < 1) — no whole-frame dimming, which
        // measured as its own flash.
        g += .1 / (.1 + k.br * 13.) * kEFBGlowPerStep * mix(smoothstep(0., kEFBCamFade, td), 1., max(camGlow, st.faithful));   // faithful: no fix
        li += .1 / (.1 + k.tub * 5.) * kEFBGlowPerStep;
    }
    // EFB: Kali scaled the whole glow by (.5 + so*1.5), a per-frame strobe. The shipped glow is steady at
    // st.glowBase (energy-driven, 1.25 at a typical passage — his average); the downbeat turns its colour.
    float glowScale;
    if (st.faithful > .5) {
        g = max(g, li * .15);
        glowScale = st.glowBase + st.flicker * 1.5;
    } else {
        g = max(g, li * .15) * st.glowBase;
        glowScale = 1.;
    }
    float f = 1. - td / 3.;
    if (ref == 1.) f = 1. - ltd / 3.;
    if (d < .01) {
        col = float3(1.);
        float2 e = float2(0., kEFBDet);
        float3 n = normalize(float3(efb_de(p + e.yxx, k), efb_de(p + e.xyx, k), efb_de(p + e.xxy, k)) - efb_de(p, k));
        col = float3(n.x) * .7;
        col += fract(k.pos.z * 5.) * float3(.2, .1, .5);
        col += efb_fractal(k.pos.xz * 2., time);
        if (k.tub > .01) col = float3(0.);
    }
    col *= f;
    float3 glo = g * .1 * float3(2., 1., 2.) * glowScale * .5;
    glo.rb = glo.rb * efb_rot(dir.y * 1.5 + st.hue);   // EFB: + hue, the downbeat colour turn
    col += glo;
    col *= float3(.8, .7, .7);
    col = mix(col, float3(1.), ref * .3);
    return col;
}

static inline float3 efb_srgb_to_linear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// MARK: - Fragment

fragment float4 energetic_flyby_fragment(VertexOut in [[stage_in]],
                                         constant FeatureVector& features [[buffer(0)]],
                                         constant EnergeticFlybyStateGPU& st [[buffer(6)]]) {
    EFBMarch k;
    k.br = 0.; k.tub = 0.; k.hit = 0.;
    k.pos = float3(0.); k.sphpos = float3(0.);
    k.time = st.time;
    k.spin = st.spin;

    float2 uv = float2(in.uv.x - .5, .5 - in.uv.y);   // Kali: gl_FragCoord/resolution - .5, y up
    uv.x *= max(features.aspect_ratio, 1e-4);          // Kali: uv /= vec2(res.y/res.x, 1)
    float t = st.travel;                               // EFB: Kali's t = time → the flight position
    float3 from = efb_path(st.camT);                   // EFB: no park on the shipped path (camT == t)
    k.sphpos = efb_path(t + .5);
    from.x += .2;
    float3 fw = normalize(efb_path(t + .5) - from);
    float3 dir = normalize(float3(uv * efb_rot(st.roll), .5));   // EFB: + roll, the bank
    dir = efb_lookat(fw, float3(fw.x * 2., 1., 0.)) * dir;
    dir.xz += sin(k.time) * .3;
    float3 col = efb_march(from, dir, k, st);
    col = mix(float3(.5) * length(col), col, .8);
    return float4(efb_srgb_to_linear(saturate(col)), 1.);
}
