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
// at native 2560×1440 is p50 56 / p95 73 ms on an M2 Pro. Two changes, each marked `EFB (cost)`: ONE sphere
// system instead of three (his flanking pp ± .7 systems are dropped), and an adaptive step — up to 2× his
// in open space, exactly his near any surface — with the per-step glow weighted by the same factor. His
// 200-step budget and 5.0 depth are kept: cutting them (and a uniform 2× step) lost thin shells, holes and
// mirrored cells (Matt, live: "blurry and pixelated areas"). At his glow level it matches his frames to
// mean |Δ| 0.018–0.075 at 1440p (the remainder is the two dropped sphere systems).
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

// TEMPORAL RECONSTRUCTION (EFB.4, MFX.2 contract — SHADER_CRAFT §17 `temporal_reconstruction`). Plumbing
// only; the colour is computed exactly as before (FA #65), and with jitter zero it is byte-identical:
//   • jitter: the ray goes through `in.uv + jitter / render_size` (buffer 9; zeroed on every other path)
//   • depth: Metal NDC of the surface the pixel shows, from the declared camera (90° fov, near .05, far 20)
//   • motion: each surface point carried back to the previous frame in closed form — the tunnel point through
//     the inverse of Kali's domain warp at the previous `time`, a sphere point through the previous spin and
//     cluster position — and projected with the previous camera (path, roll, view sway). No hit: the ray's
//     direction, rotation only
//   • reactive: the glow whose colour the downbeat turns, while it turns, and the rods' own glow

// MARK: - State (EnergeticFlybyState.swift, fragment buffer 6)

/// 64 bytes; must match `EnergeticFlybyStateGPU` in EnergeticFlybyState.swift byte-for-byte.
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
    // EFB.4: the previous frame's values, for the motion vectors and the reactive mask
    float prevTime, prevTravel, prevCamT, prevSpin, prevRoll, prevHue;
    float cameraOnlyMotion;   // test only: 1 = every surface held static (the comparison the motion test runs)
};

// MARK: - Kali's globals

struct EFBMarch {
    float br, tub, hit;
    float3 pos, sphpos;
    float time, spin;
};

constant float kEFBDet = .001;
/// EFB (cost): in open space a march step goes up to this many times Kali's (he steps 0.3 of the
/// distance bound); near a surface (d below kEFBNear) it is exactly his, so thin shell layers, holes and
/// mirrored cells are found where he finds them. A uniform 2× step (and a 3.3 depth cut-off) skipped them:
/// Matt, live, "some blurry and pixelated areas". The glow is a per-step sum, so each step's glow is
/// weighted by the same factor to keep Kali's brightness.
constant float kEFBFarStep = 2.;
constant float2 kEFBNear = float2(.01, .05);
/// EFB (white-out fix): ray length over which rod glow fades in while a rod is at the camera.
constant float kEFBCamFade = .3;
/// EFB.4: the camera the depth is written with (sidecar `fov` / `near` / `far`). Kali's ray is
/// (uv, .5) with uv.y in ±.5: a 90° vertical field of view.
constant float kEFBNearZ = .05;
constant float kEFBFarZ = 20.;
/// EFB.4 reactive mask: a glow colour turn of this many radians in one frame ignores history fully.
constant float kEFBHueReactive = .05;

/// EFB.4: where the march ended and what it saw, for depth and motion (never read by the colour).
struct EFBHit {
    float3 p;        // the surface the pixel shows: the mirror point after a reflection
    float surface;   // 1 = a surface (Kali's `d < .01`), 0 = no hit
    float rod;       // share of the final glow that is the rods' own (above the tunnel floor)
    float glow;      // share of the pixel's light that is the glow (the part the colour turn rotates)
};

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
    return d * .3;
}

static float3 efb_march(float3 from, float3 dir, thread EFBMarch& k,
                        constant EnergeticFlybyStateGPU& st, thread EFBHit& h) {
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
    float adv = 0.;   // EFB (cost): the advance, Kali's d scaled by the open-space factor
    for (int i = 0; i < 200; i++) {
        p += dir * adv;
        d = efb_de(p, k);
        if (d < kEFBDet && ref == 0. && k.hit == 1.) {
            float2 e = float2(0., .1);
            float3 n = normalize(float3(efb_de(p + e.yxx, k), efb_de(p + e.xyx, k), efb_de(p + e.xxy, k)) - efb_de(p, k));
            h.p = p;   // EFB.4: the mirror is the surface this pixel shows
            p -= dir * d * 2.;
            dir = reflect(dir, n);
            ref = 1.;
            td = 0.;
            ltd = td;
            adv = d;
            continue;
        }
        if (d < kEFBDet || td > 5.) break;
        float sc = mix(1., kEFBFarStep, smoothstep(kEFBNear.x, kEFBNear.y, d));   // EFB (cost)
        adv = d * sc;
        td += adv;
        // EFB (white-out fix): with a rod at the camera every ray starts inside it, and the rod glow
        // gathered in the first steps whites out the frame (05_anti_whole_frame_whiteout). Fade in only
        // that near-camera glow, only while a rod is there (camGlow < 1) — no whole-frame dimming, which
        // measured as its own flash.
        g += .1 / (.1 + k.br * 13.) * sc * mix(smoothstep(0., kEFBCamFade, td), 1., max(camGlow, st.faithful));   // faithful: no fix
        li += .1 / (.1 + k.tub * 5.) * sc;
    }
    // EFB: Kali scaled the whole glow by (.5 + so*1.5), a per-frame strobe. The shipped glow is steady at
    // st.glowBase (energy-driven, 1.25 at a typical passage — his average); the downbeat turns its colour.
    // EFB.4: what the march saw, for depth and motion (the reactive mask reads the rods' share)
    h.rod = g > li * .15 ? 1. - li * .15 / g : 0.;
    if (ref == 0.) h.p = p;
    h.surface = (ref == 1. || d < .01) ? 1. : 0.;
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
    h.glow = saturate(dot(max(glo, 0.), 1.) / max(dot(max(col, 0.), 1.), 1e-4));   // EFB.4
    col *= float3(.8, .7, .7);
    col = mix(col, float3(1.), ref * .3);
    return col;
}

static inline float3 efb_srgb_to_linear(float3 c) {
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

// MARK: - Temporal reconstruction (EFB.4)

/// Kali's camera for one frame: the fragment's own setup, as a value (it builds the ray with
/// `M · normalize((uv · rot(roll), .5)) + sway`).
struct EFBCamera {
    float3 from;
    float3x3 m;      // efb_lookat: orthonormal columns (right, up, forward)
    float3 sway;     // Kali's view sway, added to the ray after the rotation
    float roll;
};

static EFBCamera efb_camera(float travel, float camT, float time, float roll) {
    EFBCamera c;
    c.from = efb_path(camT);
    c.from.x += .2;
    float3 fw = normalize(efb_path(travel + .5) - c.from);
    c.m = efb_lookat(fw, float3(fw.x * 2., 1., 0.));
    float sw = sin(time) * .3;
    c.sway = float3(sw, 0., sw);
    c.roll = roll;
    return c;
}

/// The render pixel whose ray runs along `v` (world, from the camera; any length). The ray is
/// `M n + w` with n a unit vector, so `μv − w` must be unit length: one positive root, |w| < 1.
static float2 efb_project(float3 v, EFBCamera c, float aspect, float2 size) {
    float vv = max(dot(v, v), 1e-12), vw = dot(v, c.sway), ww = dot(c.sway, c.sway);
    float mu = (vw + sqrt(max(vw * vw - vv * (ww - 1.), 0.))) / vv;
    float3 n = transpose(c.m) * (mu * v - c.sway);
    float2 uv = (n.xy * (.5 / max(n.z, 1e-4))) * efb_rot(-c.roll);   // undo `uv * rot(roll)`
    return float2((uv.x / aspect + .5) * size.x, (.5 - uv.y) * size.y);
}

/// Kali's tunnel warp at `time`, applied to x/y (z is unchanged): the domain the shells are fixed in.
static float2 efb_warp(float3 p, float time) {
    float2 q = (p.xy - efb_path(p.z).xy) * efb_rot(p.z + time * .5);
    float s = sin(p.z * .5 + time * .5);
    return q * (1.3 - s * s * .7);
}

/// The world point that held tunnel surface point `p` (seen at `time`) at `prevTime`: the inverse warp.
static float3 efb_tunnel_prev(float3 p, float time, float prevTime) {
    float s = sin(p.z * .5 + prevTime * .5);
    float2 q = efb_warp(p, time) / (1.3 - s * s * .7);
    return float3(efb_path(p.z).xy + q * efb_rot(-(p.z + prevTime * .5)), p.z);
}

/// Sphere-local point of world `p` (efb_coso's transform), and back for another spin / cluster position.
static float3 efb_sphere_local(float3 p, float3 sphpos, float spin) {
    float3 pp = (p - sphpos) * .7;
    pp.xy = pp.xy * efb_rot(pp.z * 2.);
    pp.xz = pp.xz * efb_rot(spin * 2.);
    pp.yz = pp.yz * efb_rot(spin);
    return pp;
}

static float3 efb_sphere_world(float3 pp, float3 sphpos, float spin) {
    pp.yz = pp.yz * efb_rot(-spin);
    pp.xz = pp.xz * efb_rot(-spin * 2.);
    pp.xy = pp.xy * efb_rot(-pp.z * 2.);
    return pp / .7 + sphpos;
}

// MARK: - Fragment

fragment TemporalFragmentOutReactive energetic_flyby_fragment(VertexOut in [[stage_in]],
                                                              constant FeatureVector& features [[buffer(0)]],
                                                              constant EnergeticFlybyStateGPU& st [[buffer(6)]],
                                                              constant TemporalFrame& tf [[buffer(9)]]) {
    EFBMarch k;
    k.br = 0.; k.tub = 0.; k.hit = 0.;
    k.pos = float3(0.); k.sphpos = float3(0.);
    k.time = st.time;
    k.spin = st.spin;

    // EFB.4: the jittered sample point. Zero jitter (every non-reconstructing path) adds exactly 0.
    float2 jit = tf.render_size.x > 0. ? tf.jitter / tf.render_size : float2(0.);
    float2 suv = in.uv + jit;
    float2 uv = float2(suv.x - .5, .5 - suv.y);        // Kali: gl_FragCoord/resolution - .5, y up
    float aspect = max(features.aspect_ratio, 1e-4);
    uv.x *= aspect;                                    // Kali: uv /= vec2(res.y/res.x, 1)
    float t = st.travel;                               // EFB: Kali's t = time → the flight position
    float3 from = efb_path(st.camT);                   // EFB: no park on the shipped path (camT == t)
    k.sphpos = efb_path(t + .5);
    from.x += .2;
    float3 fw = normalize(efb_path(t + .5) - from);
    float3 dir = normalize(float3(uv * efb_rot(st.roll), .5));   // EFB: + roll, the bank
    dir = efb_lookat(fw, float3(fw.x * 2., 1., 0.)) * dir;
    dir.xz += sin(k.time) * .3;
    EFBHit h;
    h.p = from; h.surface = 0.; h.rod = 0.; h.glow = 0.;
    float3 sphpos = k.sphpos;
    float3 col = efb_march(from, dir, k, st, h);
    col = mix(float3(.5) * length(col), col, .8);

    TemporalFragmentOutReactive o;
    o.color = float4(efb_srgb_to_linear(saturate(col)), 1.);

    // EFB.4: depth, motion and reactive — only on the reconstruct path (render_size is zero everywhere else).
    o.depth = 1.;
    o.motion = float2(0.);
    o.reactive = 0.;
    if (tf.render_size.x <= 0.) return o;
    EFBCamera prev = efb_camera(st.prevTravel, st.prevCamT, st.prevTime, st.prevRoll);
    float2 size = tf.render_size;
    float2 s = in.position.xy + tf.jitter;
    if (h.surface > .5) {
        EFBMarch kc = k;
        float dd = efb_de(h.p, kc);
        float3 pPrev = st.cameraOnlyMotion > .5 ? h.p : kc.tub * .3 <= dd
            ? efb_tunnel_prev(h.p, st.time, st.prevTime)
            : efb_sphere_world(efb_sphere_local(h.p, sphpos, st.spin), efb_path(st.prevTravel + .5), st.prevSpin);
        float z = max(dot(h.p - from, fw), kEFBNearZ);
        o.depth = saturate(kEFBFarZ * (z - kEFBNearZ) / (z * (kEFBFarZ - kEFBNearZ)));
        o.motion = efb_project(pPrev - prev.from, prev, aspect, size) - s;
    } else {
        o.motion = efb_project(dir, prev, aspect, size) - s;   // a direction: camera rotation only
    }
    float turn = saturate(abs(st.hue - st.prevHue) / kEFBHueReactive);
    o.reactive = h.glow * max(turn, h.rod);
    return o;
}
