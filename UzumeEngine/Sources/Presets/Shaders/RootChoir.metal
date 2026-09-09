// Root Choir — Liquid Script.
// Uzume-native response to Martin's butterchurn built-in `liquid arrows`.
// Tapered jewel-ink gestures enter locally, braid through a persistent non-radial
// liquid flow, and dissolve. No random pentagon, central vortex, global rotation,
// particles, rings, or CPU state.

constant float3 kRCAmber   = float3(0.98, 0.30, 0.045);
constant float3 kRCMagenta = float3(0.91, 0.035, 0.39);
constant float3 kRCViolet  = float3(0.35, 0.055, 0.92);
constant float3 kRCGround  = float3(0.006, 0.003, 0.020);

static inline float rcHash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

static inline float rcSegmentDistance(float2 p, float2 a, float2 b, thread float& along) {
    float2 ab = b - a;
    along = saturate(dot(p - a, ab) / max(dot(ab, ab), 1.0e-6));
    return length(p - (a + along * ab));
}

// Sampled calligraphic centreline with a tapered body and trailing curl.
static inline float rcScriptStroke(float2 p, float2 origin, float angle, float scale,
                                   float curl, thread float& strokeT) {
    float cs = cos(angle), sn = sin(angle);
    float2 q = p - origin;
    q = float2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y) / scale;
    float best = 1.0e4, bestT = 0.0;
    float2 previous = float2(-0.58, 0.0);
    for (int i = 1; i <= 18; ++i) {
        float t = float(i) / 18.0;
        float2 current = float2(-0.58 + 1.16 * t,
            0.22 * sin((t * 1.42 + 0.05) * M_PI_F)
            + curl * 0.31 * sin(t * 2.15 * M_PI_F) * pow(t, 1.25));
        float localT = 0.0;
        float d = rcSegmentDistance(q, previous, current, localT);
        if (d < best) { best = d; bestT = (float(i - 1) + localT) / 18.0; }
        previous = current;
    }
    strokeT = bestT;
    float pressure = 0.78 + 0.22 * sin(bestT * M_PI_F);
    float taper = mix(0.032, 0.0055, pow(bestT, 1.55)) * pressure;
    float ends = smoothstep(0.0, 0.035, bestT)
        * (1.0 - smoothstep(0.90, 1.0, bestT));
    return (1.0 - smoothstep(taper, taper + 0.005, best)) * ends;
}

fragment float4 root_choir_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant float* fft [[buffer(1)]],
    constant float* waveform [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    (void)fft; (void)waveform; (void)stems;
    float2 p = (in.uv - 0.5) * float2(max(f.aspect_ratio, 1.0), 1.0);
    float pulse = smoothstep(0.68, 0.98, saturate(f.beat_composite));
    float coverage = 0.0;
    float3 ink = float3(0.0);
    // Three asynchronous writing hands form a distributed Lissajous composition.
    for (int hand = 0; hand < 3; ++hand) {
        float h = float(hand);
        float handClock = f.time * (0.47 + h * 0.035) + h * 0.37;
        float seed = floor(handClock) + h * 17.0;
        float phase = f.time * (0.19 + h * 0.027) + h * 2.17;
        float2 origin = float2(
            0.34 * sin(phase * 1.31 + rcHash(seed) * 5.0),
            0.23 * sin(phase * 0.83 + 1.7 + rcHash(seed + 4.0) * 3.0));
        float angle = -0.75 + 1.5 * rcHash(seed + 9.0) + 0.24 * sin(phase);
        float localAge = fract(handClock);
        float write = smoothstep(0.01, 0.07, localAge)
            * (1.0 - smoothstep(0.76, 0.99, localAge));
        float t = 0.0;
        float stroke = rcScriptStroke(p, origin, angle,
            0.52 + 0.08 * rcHash(seed + 2.0), mix(-1.0, 1.0, rcHash(seed + 7.0)), t);
        float reveal = 1.0 - smoothstep(localAge, localAge + 0.075, t);
        stroke *= write * (0.86 + 0.14 * pulse) * reveal;
        float3 col = hand == 0 ? kRCAmber : (hand == 1 ? kRCMagenta : kRCViolet);
        ink += col * stroke;
        coverage = max(coverage, stroke);
    }
    return float4(ink, saturate(coverage));
}

MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                              constant StemFeatures& stems,
                              constant SceneUniforms& scene) {
    (void)stems; (void)scene;
    MVWarpPerFrame pf;
    float drive = tanh(max(0.0, f.bass_dev));
    pf.zoom = 1.0; pf.rot = 0.0; pf.decay = 0.982;
    pf.warp = 0.0014 + 0.0046 * drive;
    pf.cx = 0.0; pf.cy = 0.0; pf.dx = 0.0; pf.dy = 0.0; pf.sx = 1.0; pf.sy = 1.0;
    pf.q1 = f.time; pf.q2 = drive; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(float2 uv, float rad, float ang,
                       thread const MVWarpPerFrame& pf,
                       constant FeatureVector& f,
                       constant StemFeatures& stems) {
    (void)rad; (void)ang; (void)f; (void)stems;
    float2 p = uv - 0.5;
    float2 flow = float2(0.0);
    const float2 centres[3] = {
        float2(-0.25, 0.16), float2(0.27, 0.10), float2(0.01, -0.25)
    };
    for (int i = 0; i < 3; ++i) {
        float2 centre = centres[i] + 0.035 * float2(
            sin(pf.q1 * (0.13 + 0.02 * float(i)) + float(i)),
            cos(pf.q1 * (0.11 + 0.015 * float(i)) + float(i) * 1.7));
        float2 d = p - centre;
        float falloff = exp(-dot(d, d) * 7.5);
        float direction = i == 1 ? -1.0 : 1.0;
        flow += direction * float2(-d.y, d.x) * falloff * 3.2;
    }
    flow += 0.20 * float2(sin(p.y * 7.0 + pf.q1 * 0.19),
                          sin(p.x * 6.0 - pf.q1 * 0.16));
    float2 drift = float2(0.00024 * sin(pf.q1 * 0.17), 0.00020 * cos(pf.q1 * 0.13));
    return clamp(uv - flow * pf.warp + drift, float2(0.002), float2(0.998));
}

fragment float4 root_choir_warp_fragment(
    WarpVertexOut in [[stage_in]], texture2d<float> previous [[texture(0)]],
    constant float& chromaticMix [[buffer(0)]]) {
    (void)chromaticMix;
    float3 carried = previous.sample(warpSampler, in.warped_uv).rgb;
    carried = max(carried * in.decay - 0.00045, float3(0.0));
    return float4(carried, 1.0);
}

fragment float4 root_choir_comp_fragment(
    VertexOut in [[stage_in]], texture2d<float> canvas [[texture(0)]],
    constant float4& post [[buffer(0)]]) {
    (void)post;
    float2 texel = 1.0 / float2(canvas.get_width(), canvas.get_height());
    float3 c = canvas.sample(warpSampler, in.uv).rgb;
    float3 lw = float3(0.2126, 0.7152, 0.0722);
    float lx = dot(canvas.sample(warpSampler, in.uv + float2(texel.x, 0)).rgb, lw)
             - dot(canvas.sample(warpSampler, in.uv - float2(texel.x, 0)).rgb, lw);
    float ly = dot(canvas.sample(warpSampler, in.uv + float2(0, texel.y)).rgb, lw)
             - dot(canvas.sample(warpSampler, in.uv - float2(0, texel.y)).rgb, lw);
    float edge = saturate(length(float2(lx, ly)) * 4.2);
    float3 edgeHue = mix(kRCViolet, kRCAmber, saturate(in.uv.x * 0.7 + in.uv.y * 0.3));
    float3 color = kRCGround + pow(saturate(c), float3(0.82)) * 1.15 + edgeHue * edge * 0.30;
    color *= 1.0 - 0.18 * smoothstep(0.55, 0.82,
        length((in.uv - 0.5) * float2(1.0, 0.8)));
    return float4(min(color, float3(0.96)), 1.0);
}
