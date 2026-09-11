// Root Choir — Liquid Script.
// Uzume-native response to Martin's butterchurn built-in `liquid arrows`.
// Luminous pointed heads pull enamel-bright spines and fine curled tendrils through
// a persistent non-radial liquid flow. No random pentagon, central vortex, global
// rotation, particles, rings, or CPU state.

constant float3 kRCAmber    = float3(1.00, 0.38, 0.018);
constant float3 kRCMagenta  = float3(1.00, 0.045, 0.18);
constant float3 kRCViolet   = float3(0.48, 0.030, 1.00);
constant float3 kRCHotCore  = float3(1.00, 0.76, 0.24);
constant float3 kRCGround   = float3(0.029, 0.023, 0.043);

static inline float rcHash(float n) { return fract(sin(n * 91.3458) * 47453.5453); }

static inline float rcSegmentDistance(float2 p, float2 a, float2 b, thread float& along) {
    float2 ab = b - a;
    along = saturate(dot(p - a, ab) / max(dot(ab, ab), 1.0e-6));
    return length(p - (a + along * ab));
}

static inline float2 rcStrokePoint(float t, float curl) {
    return float2(-0.62 + 1.14 * t,
        0.15 * sin((t * 1.30 + 0.04) * M_PI_F)
        + curl * 0.255 * sin(t * 3.15 * M_PI_F) * pow(1.0 - t, 0.52));
}

static inline float2 rcSecondTendrilPoint(float t, float curl) {
    float2 q = rcStrokePoint(t, curl);
    float branch = sin(t * M_PI_F) * sin((t * 1.42 + 0.16) * M_PI_F);
    q.y += branch * (0.105 + 0.035 * curl);
    return q;
}

// x=halo, y=saturated body, z=hot enamel core. A narrow curled tail widens into
// a pointed leaf/arrow head; keeping those masks separate preserves local contrast.
static inline float3 rcScriptStroke(float2 p, float2 origin, float angle, float scale,
                                    float curl, thread float& strokeT) {
    float cs = cos(angle), sn = sin(angle);
    float2 q = p - origin;
    q = float2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y) / scale;
    float best = 1.0e4, bestT = 0.0;
    float bestSecond = 1.0e4, bestSecondT = 0.0;
    float2 previous = rcStrokePoint(0.0, curl);
    float2 previousSecond = rcSecondTendrilPoint(0.0, curl);
    for (int i = 1; i <= 24; ++i) {
        float t = float(i) / 24.0;
        float2 current = rcStrokePoint(t, curl);
        float2 currentSecond = rcSecondTendrilPoint(t, curl);
        float localT = 0.0;
        float d = rcSegmentDistance(q, previous, current, localT);
        if (d < best) { best = d; bestT = (float(i - 1) + localT) / 24.0; }
        float localSecondT = 0.0;
        float dSecond = rcSegmentDistance(q, previousSecond, currentSecond, localSecondT);
        if (dSecond < bestSecond) {
            bestSecond = dSecond;
            bestSecondT = (float(i - 1) + localSecondT) / 24.0;
        }
        previous = current;
        previousSecond = currentSecond;
    }
    if (bestSecond < best) { best = bestSecond; bestT = bestSecondT; }
    strokeT = bestT;
    float tailWidth = mix(0.004, 0.011, smoothstep(0.02, 0.76, bestT));
    float tailEnds = smoothstep(0.0, 0.045, bestT)
        * (1.0 - smoothstep(0.79, 0.91, bestT));
    float tailHalo = (1.0 - smoothstep(tailWidth + 0.006, tailWidth + 0.030, best)) * tailEnds;
    float tailBody = (1.0 - smoothstep(tailWidth, tailWidth + 0.005, best)) * tailEnds;
    float tailCore = (1.0 - smoothstep(tailWidth * 0.30, tailWidth * 0.30 + 0.0035, best))
        * tailEnds;

    float2 headCentre = rcStrokePoint(0.84, curl);
    float2 tangent = normalize(rcStrokePoint(0.87, curl) - rcStrokePoint(0.81, curl));
    float2 normal = float2(-tangent.y, tangent.x);
    float2 rel = q - headCentre;
    float hx = dot(rel, tangent);
    float hy = dot(rel, normal);
    float headU = saturate((hx + 0.115) / 0.285);
    float rearRise = saturate((hx + 0.115) / 0.145);
    float frontFall = saturate((0.170 - hx) / 0.140);
    float headWidth = 0.108 * max(0.0, min(rearRise, frontFall))
        * mix(0.78, 1.0, headU);
    float headEnds = step(-0.115, hx) * step(hx, 0.170);
    float headBody = (1.0 - smoothstep(headWidth, headWidth + 0.006, abs(hy))) * headEnds;
    float headHalo = (1.0 - smoothstep(headWidth + 0.012, headWidth + 0.040, abs(hy)))
        * headEnds;
    float coreWidth = headWidth * (0.18 + 0.22 * headU);
    float headCore = (1.0 - smoothstep(coreWidth, coreWidth + 0.005, abs(hy)))
        * smoothstep(-0.09, -0.015, hx) * (1.0 - smoothstep(0.105, 0.168, hx));

    return float3(max(tailHalo, headHalo), max(tailBody, headBody),
                  max(tailCore, headCore));
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
    // Four asynchronous hands keep the reference's all-over living-script density
    // while avoiding its central pentagon/vortex composition.
    for (int hand = 0; hand < 5; ++hand) {
        float h = float(hand);
        float handClock = f.time * (0.39 + h * 0.031) + h * 0.29;
        float seed = floor(handClock) + h * 17.0;
        float phase = seed * 1.71 + h * 2.17;
        float2 origin = float2(
            0.43 * sin(phase * 1.31 + rcHash(seed) * 5.0),
            0.34 * sin(phase * 0.83 + 1.7 + rcHash(seed + 4.0) * 3.0));
        float angle = -1.0 + 2.0 * rcHash(seed + 9.0) + 0.18 * sin(phase);
        float localAge = fract(handClock);
        float write = smoothstep(0.01, 0.10, localAge)
            * (1.0 - smoothstep(0.22, 0.40, localAge));
        float t = 0.0;
        float3 stroke = rcScriptStroke(p, origin, angle,
            0.43 + 0.075 * rcHash(seed + 2.0), mix(-1.0, 1.0, rcHash(seed + 7.0)), t);
        float revealHead = saturate(localAge / 0.235);
        float reveal = 1.0 - smoothstep(revealHead, revealHead + 0.075, t);
        float strength = write * (0.88 + 0.18 * pulse) * reveal;
        stroke *= strength;
        float3 col = hand == 0 ? kRCAmber
            : (hand == 1 ? kRCMagenta : (hand == 2 ? kRCViolet : mix(kRCAmber, kRCMagenta, 0.34)));
        ink += col * stroke.x * 0.34;
        ink += col * stroke.y * 2.15;
        ink += mix(col, kRCHotCore, 0.38) * stroke.z * 3.10;
        coverage = max(coverage, stroke.x);
    }
    return float4(ink, saturate(coverage));
}

MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                              constant StemFeatures& stems,
                              constant SceneUniforms& scene) {
    (void)stems; (void)scene;
    MVWarpPerFrame pf;
    float drive = tanh(max(0.0, f.bass_dev));
    pf.zoom = 1.0; pf.rot = 0.0; pf.decay = 0.991;
    pf.warp = 0.0060 + 0.0070 * drive;
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
    // Directed cross-shear: every streamline has a persistent through-flow, so
    // the weak local curvature below cannot close into an orbit or ring trace.
    float2 flow = float2(
        0.34 + 0.16 * sin(p.y * 5.7 + p.x * 1.1 + pf.q1 * 0.19),
        0.36 * sin(p.x * 4.8 - p.y * 1.3 - pf.q1 * 0.16)
            + 0.10 * cos(p.y * 6.2 + pf.q1 * 0.11));
    const float2 centres[3] = {
        float2(-0.25, 0.16), float2(0.27, 0.10), float2(0.01, -0.25)
    };
    for (int i = 0; i < 3; ++i) {
        float2 d = p - centres[i];
        float falloff = exp(-dot(d, d) * 8.5);
        float direction = i == 1 ? -1.0 : 1.0;
        flow += direction * float2(-d.y, d.x) * falloff * 0.20;
    }
    float2 drift = float2(0.00024 * sin(pf.q1 * 0.17), 0.00020 * cos(pf.q1 * 0.13));
    return clamp(uv - flow * pf.warp + drift, float2(0.002), float2(0.998));
}

fragment float4 root_choir_warp_fragment(
    WarpVertexOut in [[stage_in]], texture2d<float> previous [[texture(0)]],
    constant float& chromaticMix [[buffer(0)]]) {
    (void)chromaticMix;
    float3 carried = previous.sample(warpSampler, in.warped_uv).rgb;
    carried = max(carried * in.decay - 0.00015, float3(0.0));
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
    float3 filmicInk = 1.0 - exp(-max(c, float3(0.0)) * 2.42);
    float inkLuma = dot(filmicInk, lw);
    filmicInk = max(float3(0.0), inkLuma + (filmicInk - inkLuma) * 1.34);
    float groundShape = 0.66 + 0.72 * (1.0 - saturate(length(in.uv - 0.5) * 1.32));
    float3 color = kRCGround * groundShape + filmicInk + edgeHue * edge * 0.27;
    color *= 1.0 - 0.07 * smoothstep(0.62, 0.86,
        length((in.uv - 0.5) * float2(1.0, 0.8)));
    return float4(min(color, float3(0.965)), 1.0);
}
