// Fireflies.metal — the dusk meadow the swarm flashes in. ⚠ PLACEHOLDER (FF.1).
//
// This is the FF.0 spike's `background()` (`docs/presets/fireflies_spike/fireflies_spike.py`)
// at the spike's fidelity, nothing more: a three-stop sky, a streaked meadow, a noise tree
// line on the horizon and one static mist band. It is DELIBERATELY the sketch Matt called
// "cheap … like a sketch vs. a detailed rendering" — FF.1 ports the behaviour only. FF.2
// replaces this whole file with the world the FF.R references ask for (layered ridges,
// afterglow, blades, drifting volumetric mist; `docs/VISUAL_REFERENCES/fireflies/README.md`).
// Do not polish it here.
//
// The swarm itself is `FirefliesGeometry` (`Renderer/Shaders/Fireflies.metal`), drawn
// additively over this fragment.
//
// Silence (D-037): the world is audio-independent and lit, so the frame is never black —
// near-silence dims only the swarm, to a few stragglers.
//
// Colours are the spike's linear values; the sRGB drawable encodes them.

static inline float ff_hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

/// 1-D value-noise fbm, the spike's `fbm1d` (3·2^o knots per octave, 1/2^o weights).
static inline float ff_fbm1d(float x, float seed, int octaves) {
    float out = 0.0;
    for (int o = 0; o < octaves; o++) {
        float f = 3.0 * exp2(float(o));
        float xs = x * f;
        float i = floor(xs);
        float a = ff_hash(i + seed * 101.0 + float(o) * 17.0);
        float b = ff_hash(i + 1.0 + seed * 101.0 + float(o) * 17.0);
        out += mix(a, b, fract(xs)) / exp2(float(o));
    }
    return out;
}

fragment float4 fireflies_world_fragment(VertexOut in [[stage_in]]) {
    // `fullscreen_vertex` emits TEXTURE-space uv: uv.y = 0 is the TOP of the frame.
    float y = in.uv.y, x = in.uv.x;
    const float horizon = 0.5;

    // Sky: deep indigo → a low dusk glow at the horizon.
    float s = clamp(y / horizon, 0.0, 1.0);
    float3 top = float3(0.018, 0.024, 0.065), mid = float3(0.055, 0.07, 0.15), low = float3(0.20, 0.17, 0.24);
    float3 col = s < 0.65 ? mix(top, mid, s / 0.65) : mix(mid, low, (s - 0.65) / 0.35);

    // Meadow: dark green-grey, darker toward the viewer; vertical strands that coarsen with
    // nearness.
    if (y > horizon) {
        float g = clamp((y - horizon) / (1.0 - horizon), 0.0, 1.0);
        float strands = mix(ff_fbm1d(x, 1.0, 8), ff_fbm1d(x, 2.0, 6), g);
        float n3 = (1.0 - g) * (1.0 - g) * (1.0 - g);
        float3 ground = float3(0.022, 0.03, 0.029) * n3
                      + float3(0.04, 0.055, 0.048) * (1.0 - n3) * (1.0 - g)
                      + float3(0.008, 0.014, 0.011) * g;
        col = ground * (0.75 + 0.5 * (strands - 0.9) * g * 2.0);
    }

    // Tree line: a ragged crown silhouette standing on the horizon (spike: 6–15 % of frame
    // height plus a leafy fbm edge). The spike's second edge term, `fbm1d(xs * 8 % 1)`, is
    // left out: its `% 1` restarts the noise every 1/8 of the width, which the spike's tall
    // crowns hid and this ridge renders as eight vertical notches (FF.1 motion-gate still).
    float crown = 0.06 + 0.09 * ff_fbm1d(x * 2.5, 3.0, 3) / 1.75 + 0.02 * ff_fbm1d(x, 4.0, 7);
    if (y > horizon - crown && y <= horizon) col = float3(0.012, 0.017, 0.022);

    // Depth fog: thin on the trees, a ground mist pooling just below the horizon.
    float dy = y - horizon;
    float fog = (dy < 0.0 ? exp(-pow(dy / 0.035, 2.0)) : exp(-pow(dy / 0.10, 2.0))) * 0.45;
    col = mix(col, float3(0.10, 0.11, 0.16), fog);

    return float4(max(col, 0.0), 1.0);
}
