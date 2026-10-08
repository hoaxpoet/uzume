// Fiddlehead.metal — FH.16. The fern itself is drawn by the compute renderer `FiddleheadFern`
// (Renderer/Geometry/FiddleheadFern*.swift + Renderer/Shaders/FiddleheadFern.metal), which the particles path calls
// after this fragment. This ground is what shows while the fern's curl-state fields bake on first use (a fraction of a
// second), and the D-037 non-black floor: the deep cobalt of the stained-glass palette's darkest anchor, drifting.

fragment float4 fiddlehead_ground_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]]
) {
    float2 uv = in.uv;
    float fog = 0.5 + 0.5 * sin(uv.x * 2.3 + f.time * 0.21) * sin(uv.y * 1.7 - f.time * 0.17);
    return float4(float3(0.010, 0.012, 0.050) * (0.7 + 0.6 * fog), 1.0);
}
