// HDRProof.metal — VQ.2's developer proof (`UZUME_HDR_PROOF=1`, RenderPipeline+HDRProof): a test
// pattern shown in place of the scenes, so the HDR highlight cap can be judged on an HDR display.
// Writes LINEAR scene light into a cinematic frame target; the cinematic finish (bloom, display
// transform, headroom, regional cap) turns it into the picture, exactly as an opted-in scene's.
//
// Scene values: mid-grey 0.18 maps to 0.267 on every display; 8 maps to the display's peak (SDR
// white on SDR, up to 4× it on HDR). Sizes are in frame heights, centred, edges anti-aliased.
//   - a mid-grey field darkening to the edges;
//   - five glints, scene 1 / 2 / 4 / 8 / 16 (left → right): the ramp into the highlights;
//   - a soft glow with a hot core (bloom halo);
//   - a small bright dot sweeping slowly left ↔ right (8 s period, no strobe);
//   - a large bright square (about a ninth of the screen): the regional cap holds it to an
//     average of SDR white, so it never glares however bright the scene says it is.

struct HDRProofParams {
    float time;     // seconds since the proof started
    float aspect;   // width / height
};

static inline float hdr_proof_disc(float2 q, float2 centre, float radius, float pixel) {
    return saturate((radius - length(q - centre)) / pixel + 0.5);
}

fragment float4 hdr_proof_fragment(
    VertexOut in                    [[stage_in]],
    constant HDRProofParams& p      [[buffer(0)]]
) {
    float2 q = (in.uv - 0.5) * float2(p.aspect, 1.0);
    float pixel = max(fwidth(q.y), 1e-5);
    float3 c = float3(0.18) * (1.0 - 0.7 * saturate(length(q) / 0.9));

    const float glints[5] = { 1.0, 2.0, 4.0, 8.0, 16.0 };
    for (int i = 0; i < 5; i++) {
        c += glints[i] * hdr_proof_disc(q, float2(-0.5 + 0.18 * float(i), -0.25), 0.008, pixel);
    }

    float d = length(q - float2(-0.35, 0.12));
    c += 16.0 * exp(-d * d / (2.0 * 0.012 * 0.012)) + 0.2 * exp(-d * d / (2.0 * 0.06 * 0.06));

    float sweep = 0.55 * sin(p.time * (2.0 * M_PI_F / 8.0));
    c += 16.0 * hdr_proof_disc(q, float2(sweep, 0.33), 0.01, pixel);

    float2 box = abs(q - float2(0.45, 0.05)) - float2(0.17, 0.17);
    c += 16.0 * saturate(-max(box.x, box.y) / pixel + 0.5);

    return float4(c, 1.0);
}
