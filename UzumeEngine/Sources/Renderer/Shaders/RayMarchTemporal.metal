// RayMarchTemporal.metal — the ray-march path's motion pass for MetalFX temporal reconstruction (VQ.3).
//
// Runs after the G-buffer pass of a scene that reconstructs (`RayMarchTemporal`). From `gbuf0`'s
// normalized depth it rebuilds each pixel's world point along the SAME jittered ray the G-buffer
// marched (`rm_rayDir` on the jittered uniforms — RayMarch.metal sorts first in the combined
// library), then projects that point with the current and the previous UNJITTERED cameras:
//   • motion = previous pixel − current pixel, render pixels (MetalFX's convention, as MFX.2);
//   • depth  = gbuf0's normalized depth (0 = camera, 1 = background; D-263: the convention made no
//     measurable difference), kept as next frame's `prevDepth`;
//   • reactive = 1 where the surface the previous frame saw at the reprojected pixel is not this one
//     — geometry the audio moved (a swell, a fold), which camera reprojection cannot explain.
// The camera bases need not be orthonormal: the CPU hands the inverse of each [fwd rt up] matrix.

#include <metal_stdlib>
using namespace metal;

/// Mirrors `RayMarchTemporalUniforms` in RayMarchTemporal.swift (160 bytes).
struct RayMarchTemporalUniforms {
    float3x3 currentInverse;   // inverse of [fwd rt up], current camera, unjittered
    float3x3 previousInverse;  // the same, previous frame
    float4   currentPosition;  // xyz = camera position, w = far plane
    float4   previousPosition; // xyz = previous camera position
    float4   fov;              // x, y = current tan half-angles (x includes aspect); z, w = previous
    float4   params;           // xy = render size, z = 1 when the previous frame is valid, w = tolerance
};

struct RayMarchTemporalOut {
    float  depth    [[color(0)]];
    float2 motion   [[color(1)]];
    float  reactive [[color(2)]];
};

/// Render-pixel position of camera-space coefficients c = inverse([fwd rt up]) · (p − pos).
static float2 rmt_pixel(float3 c, float2 tanHalf, float2 size) {
    float2 ndc = float2(c.y / (c.x * tanHalf.x), -c.z / (c.x * tanHalf.y));
    return (ndc * 0.5 + 0.5) * size;
}

fragment RayMarchTemporalOut raymarch_temporal_fragment(
    VertexOut                          in       [[stage_in]],
    constant RayMarchTemporalUniforms& tu       [[buffer(0)]],
    constant SceneUniforms&            scene    [[buffer(4)]],
    texture2d<float>                   gbuf0    [[texture(0)]],
    texture2d<float>                   prevDepth [[texture(1)]]
) {
    RayMarchTemporalOut out;
    float depthNorm = gbuf0.read(uint2(in.position.xy)).r;
    bool background = depthNorm >= 0.999;
    float far = tu.currentPosition.w;
    float3 rd = rm_rayDir(in.uv, scene);
    // The background is a direction: a far point moves only with the camera's turn.
    float3 p = tu.currentPosition.xyz + rd * ((background ? 1.0 : depthNorm) * far);
    float2 size = tu.params.xy;
    float3 cc = tu.currentInverse * (p - tu.currentPosition.xyz);
    float3 cp = tu.previousInverse * (p - tu.previousPosition.xyz);

    out.depth = background ? 1.0 : depthNorm;
    out.motion = float2(0.0);
    out.reactive = 0.0;
    if (cc.x <= 1.0e-5 || cp.x <= 1.0e-5) {            // behind a camera: nothing to reproject
        out.reactive = 1.0;
        return out;
    }
    float2 previous = rmt_pixel(cp, tu.fov.zw, size);
    out.motion = previous - rmt_pixel(cc, tu.fov.xy, size);
    if (background || tu.params.z < 0.5) return out;
    if (any(previous < 0.0) || any(previous >= size)) return out;   // came from off screen

    // Did the previous frame see THIS surface there? Best match over the 3×3 around the
    // reprojected pixel, so a silhouette's sub-pixel (jitter) misregistration does not count.
    float expected = length(p - tu.previousPosition.xyz) / far;
    int2 centre = int2(floor(previous));
    int2 last = int2(size) - 1;
    float best = 1.0e9;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            uint2 q = uint2(clamp(centre + int2(dx, dy), int2(0), last));
            best = min(best, abs(prevDepth.read(q).r - expected));
        }
    }
    float tolerance = tu.params.w;
    out.reactive = smoothstep(tolerance, 2.0 * tolerance, best / max(expected, 1.0e-4));
    return out;
}
