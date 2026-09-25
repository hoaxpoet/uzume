// Fireflies.metal — the firefly sprites for the Fireflies preset (FF.1, spike fidelity).
//
// One instanced quad per visible firefly, drawn additively over the preset's world fragment
// by `FirefliesGeometry`. The profile is the FF.0 spike's two Gaussian stamps — a bright
// yellow-green core plus a faint wide halo (`docs/VISUAL_REFERENCES/fireflies/
// 04_meso_lantern_glow.jpg`: bright core, soft falloff, the dark around it untouched).
// Sizes arrive in FRAME HEIGHTS so a flash covers the same frame fraction at any drawable
// size (Witchlight WL.2-g; the D-157 budget is an area rule).
//
// Layout: `FFSprite` mirrors `FFSpriteGPU` in `FirefliesGeometry.swift`, scalar floats only.

#include <metal_stdlib>
using namespace metal;

struct FFSprite {
    float x, y;            // centre, NDC
    float coreSigma;       // frame heights
    float haloSigma;       // frame heights
    float coreAmp;
    float haloAmp;
    float pad0, pad1;
};

struct FFSpriteOut {
    float4 position [[position]];
    float2 local;          // offset from centre, frame heights
    float  coreSigma;
    float  haloSigma;
    float  coreAmp;
    float  haloAmp;
};

vertex FFSpriteOut fireflies_sprite_vertex(
    uint                 vid     [[vertex_id]],
    uint                 iid     [[instance_id]],
    constant FFSprite*   sprites [[buffer(0)]],
    constant float&      aspect  [[buffer(1)]])
{
    FFSprite s = sprites[iid];
    // 3σ of the wider lobe; a core-only sprite gets a core-sized quad.
    float extent = 3.0 * (s.haloAmp > 0.0 ? max(s.haloSigma, s.coreSigma) : s.coreSigma);
    float2 corner = float2((vid & 1) ? 1.0 : -1.0, (vid & 2) ? 1.0 : -1.0);
    float2 local = corner * extent;
    FFSpriteOut out;
    // Frame height = 2 NDC units; x shrinks by the aspect so the sprite stays round.
    out.position = float4(s.x + 2.0 * local.x / aspect, s.y + 2.0 * local.y, 0.0, 1.0);
    out.local = local;
    out.coreSigma = s.coreSigma;
    out.haloSigma = s.haloSigma;
    out.coreAmp = s.coreAmp;
    out.haloAmp = s.haloAmp;
    return out;
}

fragment float4 fireflies_sprite_fragment(FFSpriteOut in [[stage_in]])
{
    // Photinus yellow-green (spike CORE / HALO), linear light.
    const float3 core = float3(0.95, 1.0, 0.55);
    const float3 halo = float3(0.55, 0.85, 0.20);
    float r2 = dot(in.local, in.local);
    float3 light = core * in.coreAmp * exp(-r2 / (2.0 * in.coreSigma * in.coreSigma))
                 + halo * in.haloAmp * exp(-r2 / (2.0 * in.haloSigma * in.haloSigma));
    return float4(light, 0.0);
}

// MARK: - Branches (FF.2)
//
// The tree skeletons of `FirefliesWorld` as 3D segments, projected through the SAME camera as
// the world fragment and the fireflies (`FFCam` mirrors `FFWorldGPU`; the projection mirrors
// `FFCamera.project`). One instanced quad per segment, drawn in painter's order (far → near)
// over the world fragment and under the swarm.
//
// Thin lines: a segment narrower than one pixel is drawn one pixel wide with its coverage
// scaled by its true width — Persson's "phone-wire AA" (GPU Pro 4 / humus.name) — so a far
// crown of sub-pixel twigs reads as the fine grey lace of `03`, not as aliased dashes.
//
// Colour is the ink ladder at the segment's depth (value is depth, D-258): near branches are
// the near-black ink, far rows step up the blue inks. `ff_ink` / `ff_depth_tone` are shared
// in spirit with `Presets/Shaders/Fireflies.metal` — keep the two in step.

struct FFCam {
    float4 cam_pos;        // xyz, w = tan(half vertical FOV)
    float4 right;          // xyz, w = aspect
    float4 up;             // xyz, w = world time (s)
    float4 fwd;            // xyz, w = world breath 0…1
    float4 motion;         // x wind phase (s), y mist drift (m)
};

struct FFBranch {
    float4 p0r0;           // start xyz, radius (m)
    float4 p1r1;           // end xyz, radius (m)
    float4 sway;           // x start weight, y end weight, z ink (0 = by depth)
};

struct FFBranchOut {
    float4 position [[position]];
    float2 local;          // px: x along the axis from its midpoint, y across it
    float  half_len;       // px, half the axis length
    float  half_w;         // px
    float  alpha;
    float3 color;
};

/// The ink ladder sampled from the hero print (`07`, k-means over its pixels), sRGB → linear.
/// 0 near-black … 4 the pale sky above the trees; 5 (the glow) is reserved for the light, FF.3.
static inline float3 ff_ink(int i) {
    const float3 inks[6] = { float3(2, 7, 22), float3(4, 16, 47), float3(9, 26, 73),
                             float3(18, 49, 114), float3(28, 80, 173), float3(79, 154, 233) };
    return pow(inks[clamp(i, 0, 5)] / 255.0, 2.2);
}

/// Value is depth: tone on the 0…5 ink ladder of a silhouette `dist` metres away.
static inline float ff_depth_tone(float dist) { return 3.4 * (1.0 - exp(-dist / 90.0)); }

/// Wind: a slow travelling sway plus a faster flutter, scaled by the segment's sway weight
/// (0 at the trunk base, 1 at the twigs) and by the breath. `t` is the integrated wind phase.
static inline float3 ff_wind(float3 p, float weight, float t, float breath) {
    float gust = sin(0.55 * t + 0.045 * p.x + 0.03 * p.z) * 0.6 + sin(1.7 * t + 0.21 * p.x) * 0.25;
    // Squared, so the swell reads: breath 0.1 (silence) → 0.03 m, 0.5 → 0.14 m, 0.9 → 0.39 m.
    return float3(gust, 0.0, 0.35 * gust) * weight * (0.03 + 0.45 * breath * breath);
}

vertex FFBranchOut fireflies_branch_vertex(
    uint                 vid      [[vertex_id]],
    uint                 iid      [[instance_id]],
    constant FFBranch*   branches [[buffer(0)]],
    constant FFCam&      cam      [[buffer(1)]],
    constant float2&     viewport [[buffer(2)]])
{
    FFBranch b = branches[iid];
    float t = cam.motion.x, breath = cam.fwd.w;
    float tan_y = cam.cam_pos.w, aspect = cam.right.w;
    float3 p0 = b.p0r0.xyz + ff_wind(b.p0r0.xyz, b.sway.x, t, breath);
    float3 p1 = b.p1r1.xyz + ff_wind(b.p1r1.xyz, b.sway.y, t, breath);
    float3 d0 = p0 - cam.cam_pos.xyz, d1 = p1 - cam.cam_pos.xyz;
    float z0 = dot(d0, cam.fwd.xyz), z1 = dot(d1, cam.fwd.xyz);

    FFBranchOut out;
    out.local = 0; out.half_len = 0; out.half_w = 0; out.alpha = 0; out.color = 0;
    if (z0 < 0.2 || z1 < 0.2) { out.position = float4(2, 2, 0, 1); return out; }

    float2 half_vp = viewport * 0.5;
    float2 s0 = float2(dot(d0, cam.right.xyz) / (z0 * tan_y * aspect), dot(d0, cam.up.xyz) / (z0 * tan_y)) * half_vp;
    float2 s1 = float2(dot(d1, cam.right.xyz) / (z1 * tan_y * aspect), dot(d1, cam.up.xyz) / (z1 * tan_y)) * half_vp;
    float fpx = half_vp.y / tan_y;                        // px per metre at 1 m
    float w0 = b.p0r0.w * fpx / z0, w1 = b.p1r1.w * fpx / z1;
    float a0 = saturate(w0 / 0.5), a1 = saturate(w1 / 0.5);
    w0 = max(w0, 0.5); w1 = max(w1, 0.5);

    // A capsule of the mean width: round caps close every joint of a bent branch.
    float2 axis = s1 - s0;
    float len = length(axis);
    float2 dir = len > 1e-4 ? axis / len : float2(0, 1);
    float2 normal = float2(-dir.y, dir.x);
    bool at_end = (vid & 1) != 0;
    float side = (vid & 2) ? 1.0 : -1.0;
    float w = 0.5 * (w0 + w1);
    float reach = 0.5 * len + w + 1.0;
    float2 local = float2(at_end ? reach : -reach, side * (w + 1.0));
    float2 pos = 0.5 * (s0 + s1) + dir * local.x + normal * local.y;
    out.position = float4(pos / half_vp, 0, 1);
    out.local = local;
    out.half_len = 0.5 * len;
    out.half_w = w;
    out.alpha = at_end ? a1 : a0;
    float tone = ff_depth_tone(at_end ? z1 : z0);
    out.color = ff_ink(b.sway.z > 0.0 ? int(b.sway.z) : int(floor(tone + 0.5)));
    return out;
}

fragment float4 fireflies_branch_fragment(FFBranchOut in [[stage_in]])
{
    float d = length(float2(max(abs(in.local.x) - in.half_len, 0.0), in.local.y));
    float cov = saturate(in.half_w + 0.5 - d) * in.alpha;
    return float4(in.color * cov, cov);   // premultiplied: ink laid over the world
}
