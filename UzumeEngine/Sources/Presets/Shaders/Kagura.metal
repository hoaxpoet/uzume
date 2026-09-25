// Kagura.metal — backdrop for the Kagura point-light dancer (KAG.2; KAGURA_DESIGN §8).
//
// Kagura renders entirely through its `ParticleGeometry` (`KaguraDancer` composites ground, trail
// and points and draws them fullscreen in the particles pass — `Renderer/Shaders/Kagura.metal`).
// This backdrop is the particle-mode preset triangle drawn BEFORE that and fully covered by it, so
// it only needs to be the same near-black ground the geometry shows where nothing is drawn: the
// spike's `4, 5, 9` through the same soft shoulder and sRGB decode, so a dropped geometry frame is
// invisible. It reads no audio. `VertexOut` comes from the preset preamble.

fragment float4 kagura_ground_fragment(VertexOut in [[stage_in]]) {
    float3 ground = float3(4.0, 5.0, 9.0) / 255.0;
    float3 shouldered = 1.0 - exp(-1.6 * ground);
    float3 lin = select(pow((shouldered + 0.055) / 1.055, 2.4), shouldered / 12.92, shouldered <= 0.04045);
    return float4(lin, 1.0);
}
