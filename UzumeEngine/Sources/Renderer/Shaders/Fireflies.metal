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
