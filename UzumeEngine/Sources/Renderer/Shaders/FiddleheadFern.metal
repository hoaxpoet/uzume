// FiddleheadFern.metal — the self-similar fern, drawn by per-pixel descent (FH.16, ported from the FH.15 spike
// `docs/presets/fiddlehead_spike/fern_descent.swift`, which is the reference implementation and test bed).
//
// ONE element — a frond: a stem that runs gently curved, then rolls into a log-spiral crozier, lined on both sides
// with children that are the SAME frond, scaled to the local width. Each pixel walks down the tree (a bounded
// depth-first search over every child that could hold it) until the children are smaller than a few pixels; there
// the subtree's silhouette is drawn. Cost grows by one step per level, so detail holds at any zoom.
//
// UNFURL: a frond's curl is a function of its ON-SCREEN size (tiny = rolled, filling the view = open), so the dive
// loops seamlessly. Fields are precomputed per curl state ("state") into texture arrays:
//   F  (rg16Float)  .x = side · distance to the spine, .y = arc position s of the nearest spine point
//   T  (r16Float)   the TRUE distance to the state's whole infinite tree (iterated from its own definition)
//   C  (r16Float)   the index of the child whose subtree is nearest (the descent's starting candidate)
// Every name is `fh_`-prefixed: the engine concatenates all Renderer/Shaders into ONE library.

#include <metal_stdlib>
using namespace metal;

// MARK: - Layout (mirrors `FernParams` / `FernChild` in FiddleheadFern+Layout.swift — GPU contract)

struct FernParams {
    float4 box;      // bmin.xy, bmax.xy of every state's field (frond units)
    float4 shape;    // W0 (rachis half-width), CS (child scale), SINF (spiral eye), prune slack (texels)
    float4 grid;     // children per state, states, field resolution, spine samples
    float4 curl;     // LOPEN, LCURL (log on-screen size of fully open / rolled), max levels, colour-unit size
    float4 lift;     // level-0 → lifted-ancestor frame: offset x, y, rotation, scale
    float4 zc;       // dive centre x, y (level-0 frame), view half-height, view rotation
    float4 tm;       // time, phi of the lifted ancestor's root, colour flow speed, pulse count
    float4 au;       // bass, treble, hue base, hue spread along the impulse path
    float4 look;     // palette luminance target, candidate window, LOD pixels, normals-from-lanes (1/0)
    float4 prev;     // the PREVIOUS frame's camera in this frame's level-0 coordinates: centre x, y, half-height, rotation
    float4 taa;      // sub-pixel jitter x, y (pixels), history weight, history valid (1/0)
};
struct FernChild { float2 root; float ang; float scale; float mirror; float s; float shift; float pad; };

// MARK: - Helpers

constexpr sampler fh_lin(filter::linear, address::clamp_to_edge);

static float fh_width(float s, constant FernParams& P) { return P.shape.x * (1.0 - 0.85 * s); }
static float fh_sigma(float s, constant FernParams& P) { return P.shape.y * (P.shape.z - s) / P.shape.z; }
static float2 fh_rot(float2 v, float a) { float c = cos(a), s = sin(a); return float2(c * v.x - s * v.y, s * v.x + c * v.y); }
static float2 fh_toChild(float2 q, constant FernChild& c) {
    float2 r = fh_rot(q - c.root, -c.ang) / c.scale;
    return c.mirror > 0.5 ? float2(r.x, -r.y) : r;
}
static float2 fh_uv(float2 q, constant FernParams& P) { return (q - P.box.xy) / (P.box.zw - P.box.xy); }
static float fh_outside(float2 q, constant FernParams& P) { return length(max(max(P.box.xy - q, q - P.box.zw), 0.0)); }
static float2 fh_texelPos(uint2 gid, constant FernParams& P) {
    return P.box.xy + (float2(gid) + 0.5) / P.grid.z * (P.box.zw - P.box.xy);
}
static float fh_sampleT(texture2d_array<float> T, float2 q, int st, constant FernParams& P) {
    return T.sample(fh_lin, fh_uv(q, P), uint(st)).x + fh_outside(q, P);
}

// MARK: - Precompute (once, at first use)

/// Per state, per texel: signed distance to the spine and the arc position of its nearest point.
kernel void fh_spine_field(constant float2* spines [[buffer(0)]], constant FernParams& P [[buffer(1)]],
                           constant int& st [[buffer(2)]], texture2d_array<float, access::write> F [[texture(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
    int tr = int(P.grid.z), ns = int(P.grid.w);
    if (int(gid.x) >= tr || int(gid.y) >= tr) { return; }
    float2 q = fh_texelPos(gid, P);
    constant float2* sp = spines + st * ns;
    float best = 1e9, bs = 0.0, side = 1.0;
    for (int i = 0; i < ns - 1; i++) {
        float2 a = sp[i], b = sp[i + 1], ab = b - a;
        float u = clamp(dot(q - a, ab) / dot(ab, ab), 0.0, 1.0);
        float d = length(q - a - ab * u);
        if (d < best) { best = d; bs = (float(i) + u) / float(ns - 1); side = (ab.x * (q - a).y - ab.y * (q - a).x) >= 0.0 ? 1.0 : -1.0; }
    }
    F.write(float4(side * best, bs, 0.0, 0.0), gid, uint(st));
}

/// T starts as each state's own stem.
kernel void fh_tree_seed(texture2d_array<float> F [[texture(0)]], texture2d_array<float, access::write> T [[texture(1)]],
                         constant FernParams& P [[buffer(1)]], constant int& st [[buffer(2)]], uint2 gid [[thread_position_in_grid]]) {
    if (int(gid.x) >= int(P.grid.z) || int(gid.y) >= int(P.grid.z)) { return; }
    float2 f = F.read(gid, uint(st)).xy;
    T.write(float4(abs(f.x) - fh_width(f.y, P)), gid, uint(st));
}

// The child state range the renderer can put a child in: round(x + shift) where its parent is round(x), i.e.
// st + floor(shift) or + ceil(shift); state 0 is CLAMPED (fronds larger than the screen are all "open"), so its
// children can be in ANY state up to that. T must bound every one, or the descent prunes real tips (FH.15).
static float fh_childT(texture2d_array<float> T, float2 qc, int st, constant FernChild& c, constant FernParams& P) {
    int nst = int(P.grid.y);
    int j0 = min(st + int(floor(c.shift)), nst - 1), j1 = min(j0 + 1, nst - 1);
    float tc = 1e9;
    for (int j = (st == 0 ? 0 : j0); j <= j1; j++) { tc = min(tc, fh_sampleT(T, qc, j, P)); }
    return tc;
}

/// One level more of state `st`'s tree: T(q) = min(stem, min_k σ_k · T(child frame of q)), into a 2-D scratch.
kernel void fh_tree_step(texture2d_array<float> F [[texture(0)]], texture2d_array<float> T [[texture(1)]],
                         texture2d<float, access::write> out [[texture(2)]], constant FernChild* ch [[buffer(0)]],
                         constant FernParams& P [[buffer(1)]], constant int& st [[buffer(2)]], uint2 gid [[thread_position_in_grid]]) {
    if (int(gid.x) >= int(P.grid.z) || int(gid.y) >= int(P.grid.z)) { return; }
    float2 q = fh_texelPos(gid, P);
    float2 f = F.read(gid, uint(st)).xy;
    float best = abs(f.x) - fh_width(f.y, P);
    int nch = int(P.grid.x);
    for (int k = 0; k < nch; k++) {
        constant FernChild& c = ch[st * nch + k];
        best = min(best, fh_childT(T, fh_toChild(q, c), st, c, P) * c.scale);
    }
    out.write(float4(best), gid);
}

/// Per state, per texel: the child whose subtree is nearest.
kernel void fh_child_field(texture2d_array<float> T [[texture(0)]], texture2d_array<float, access::write> C [[texture(1)]],
                           constant FernChild* ch [[buffer(0)]], constant FernParams& P [[buffer(1)]], constant int& st [[buffer(2)]],
                           uint2 gid [[thread_position_in_grid]]) {
    if (int(gid.x) >= int(P.grid.z) || int(gid.y) >= int(P.grid.z)) { return; }
    float2 q = fh_texelPos(gid, P);
    float best = 1e9; int bi = 0;
    int nch = int(P.grid.x);
    for (int k = 0; k < nch; k++) {
        constant FernChild& c = ch[st * nch + k];
        float d = fh_childT(T, fh_toChild(q, c), st, c, P) * c.scale;
        if (d < best) { best = d; bi = k; }
    }
    C.write(float4(float(bi)), gid, uint(st));
}

// MARK: - The descent

/// On-screen size → curl state (0 open … NST-1 rolled).
static int fh_state(float len, float viewH, constant FernParams& P) {
    float l = log(max(len / viewH, 1e-6));
    return clamp(int((P.curl.x - l) / (P.curl.x - P.curl.y) * (P.grid.y - 1.0) + 0.5), 0, int(P.grid.y) - 1);
}

/// What a pixel hit. phi = the nerve-impulse path coordinate (Σ arc fractions down the tree); phiC / scaleC = the
/// frond that is a visible UNIT on screen (colour comes from it; sub-pixel hue mixing read grey).
struct FernHit { float d; float lvl; float s; float vein; float across; float h; float id; float phi; float phiC; float scaleC; };
struct FernFrame { float2 q; float scale; float phi; float id; float phiC; float scaleC; int L; };

constant constexpr int kFernStack = 64;
constant constexpr int kFernBudget = 64;

static FernFrame fh_push(FernFrame fr, constant FernChild& c, int k, float phiC, float scaleC) {
    FernFrame n; n.q = fh_toChild(fr.q, c); n.scale = fr.scale * c.scale; n.phi = fr.phi + c.s;
    n.id = fract(fr.id * 7.31 + float(k) * 0.1373 + 0.17); n.phiC = phiC; n.scaleC = scaleC; n.L = fr.L + 1;
    return n;
}

/// Bounded depth-first search: every child whose subtree could still hold the point (tree distance under a pixel,
/// allowing for the field's texel error) is explored, nearest surface wins. One path plus a runner-up clipped
/// overlapping siblings along hard edges ("cut-off tips", FH.15).
static FernHit fh_descend(float2 q0, float scale0, float phi0, float viewH, texture2d_array<float> F, texture2d_array<float> T,
                          texture2d_array<float> C, constant FernChild* ch, constant FernParams& P, float pix) {
    FernHit r; r.d = 1e9; r.lvl = -1.0; r.s = 0.0; r.vein = 0.0; r.across = 0.0; r.h = 0.0; r.id = 0.0; r.phi = phi0;
    r.phiC = phi0; r.scaleC = scale0;
    float sure = 1e9, surePhi = phi0, sureS = 0.0, sureL = 0.0, sureId = 0.0, surePhiC = phi0, sureScaleC = scale0;
    float texel = 2.5 * (P.box.z - P.box.x) / P.grid.z, slack = texel * P.shape.w;
    int maxL = int(P.curl.z), wn = int(P.look.y), nch = int(P.grid.x), tr = int(P.grid.z);
    FernFrame stack[kFernStack]; int sp = 0;
    FernFrame root; root.q = q0; root.scale = scale0; root.phi = phi0; root.id = 0.0; root.phiC = phi0; root.scaleC = scale0; root.L = 0;
    stack[sp++] = root;
    int budget = kFernBudget;
    while (sp > 0 && budget-- > 0) {
        FernFrame fr = stack[--sp];
        float2 q = fr.q; float scale = fr.scale;
        int st = fh_state(scale, viewH, P);
        float2 uv = fh_uv(q, P); float o = fh_outside(q, P);
        float tq = T.sample(fh_lin, uv, uint(st)).x + o;
        if ((tq - slack) * scale > min(r.d, pix * 1.5)) { continue; }
        float2 f2 = F.sample(fh_lin, uv, uint(st)).xy;
        float fx = abs(f2.x) + o, fs = f2.y, fside = f2.x >= 0.0 ? 1.0 : -1.0;
        float fw = fx - fh_width(fs, P);
        float phiC = fr.phiC, scaleC = fr.scaleC;
        if (scale >= viewH * P.curl.w) { phiC = fr.phi + fs; scaleC = scale; }
        bool fine = texel * scale < pix * 1.5;
        if (fine && tq < -texel && tq * scale < sure) {
            sure = tq * scale; surePhi = fr.phi + fs; sureS = fs; sureL = float(fr.L) + 0.5; sureId = fr.id; surePhiC = phiC; sureScaleC = scaleC;
        }
        float rach = fw * scale;
        r.vein = max(r.vein, smoothstep(pix * 1.2, -pix * 0.5, rach) * (1.0 - 0.12 * float(fr.L)));
        if (rach < r.d) { r.d = rach; r.lvl = float(fr.L); r.s = fs; r.across = 0.0; r.phi = fr.phi + fs; r.id = fr.id; r.phiC = phiC; r.scaleC = scaleC; }
        { float wr = fh_width(fs, P); r.h = max(r.h, sqrt(max(wr * wr - fx * fx, 0.0)) * scale * 1.2); }
        bool last = (fr.L == maxL) || (scale * fh_sigma(fs, P) < pix * P.look.z) || o > 0.0;
        if (last) {
            float blade = tq * scale;
            if (blade < r.d) {
                r.d = blade; r.lvl = float(fr.L) + 0.5; r.s = fs; r.phi = fr.phi + fs; r.id = fr.id; r.phiC = phiC; r.scaleC = scaleC;
                float lw = fh_sigma(fs, P) * 0.5 + fh_width(fs, P); r.across = clamp(fx / lw, 0.0, 1.0) * fside;
            }
            float ub = clamp(-tq / max(fh_sigma(fs, P) * 0.15, 1e-4), 0.0, 1.0);
            r.h = max(r.h, fh_sigma(fs, P) * 0.12 * sqrt(ub) * scale);
            continue;
        }
        int k0 = int(C.read(uint2(clamp(uv, 0.0, 0.9999) * float(tr)), uint(st)).x + 0.5);
        int lo = max((k0 & ~1) - wn, 0), hi = min((k0 & ~1) + wn + 1, nch - 1);
        // the nearest candidate is pushed LAST, so it is explored first (tightens the bound for the rest)
        int kb = -1; float db = 1e9;
        for (int kk = lo; kk <= hi; kk++) {
            constant FernChild& cc = ch[st * nch + kk];
            float2 qc = fh_toChild(q, cc);
            float dk = fh_sampleT(T, qc, fh_state(scale * cc.scale, viewH, P), P) * scale * cc.scale;
            if (dk - slack * scale * cc.scale > min(r.d, pix * 1.5)) { continue; }
            if (dk < db) {
                if (kb >= 0 && sp < kFernStack) { stack[sp++] = fh_push(fr, ch[st * nch + kb], kb, phiC, scaleC); }
                kb = kk; db = dk;
            } else if (sp < kFernStack) {
                stack[sp++] = fh_push(fr, cc, kk, phiC, scaleC);
            }
        }
        if (kb >= 0 && sp < kFernStack) {
            stack[sp++] = fh_push(fr, ch[st * nch + kb], kb, phiC, scaleC);
        } else if (kb < 0 && tq < 0.0 && fine) {                          // no candidate holds the point, yet this outline does
            float blade = tq * scale;
            if (blade < r.d) { r.d = blade; r.lvl = float(fr.L) + 0.5; r.s = fs; r.phi = fr.phi + fs; r.across = 0.0; r.id = fr.id; r.phiC = phiC; r.scaleC = scaleC; }
        }
    }
    // a sharp level was sure the point is inside but every path fell into a texel-scale gap: trust that level
    if (r.d > 0.0 && sure < 0.0) { r.d = sure; r.phi = surePhi; r.s = sureS; r.lvl = sureL; r.id = sureId; r.phiC = surePhiC; r.scaleC = sureScaleC; }
    return r;
}

// MARK: - Colour

// The palette: 6 sRGB anchors walked as a PING-PONG gradient (no hard wrap), in linear, luminance-evened (gold and
// emerald ran 2–3× brighter than cobalt).
static float3 fh_pal(float x, constant float4* PL, float lum) {
    float u = abs(fract(x * 0.5) * 2.0 - 1.0) * 5.0; int i = min(int(u), 4); float f = smoothstep(0.0, 1.0, u - float(i));
    float3 c = pow(mix(PL[i].rgb, PL[i + 1].rgb, f), float3(2.2));
    float Y = dot(c, float3(0.2126, 0.7152, 0.0722));
    return c * clamp(lum / max(Y, 1e-3), 0.3, 1.3);
}
static float fh_hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

/// The fern in HDR at the internal resolution. Dispatched in WHOLE 16×16 threadgroups: the relief normal reads the
/// neighbouring pixels' heights across SIMD lanes (lane^1 = right/left, lane^16 = row below/above), which needs every
/// lane to reach the shuffle — out-of-range threads compute and skip only the write.
kernel void fh_render(texture2d_array<float> F [[texture(0)]], texture2d_array<float> T [[texture(1)]],
                      texture2d_array<float> C [[texture(2)]], texture2d<float, access::write> out [[texture(3)]],
                      constant FernChild* ch [[buffer(0)]], constant FernParams& P [[buffer(1)]],
                      constant float2* pulses [[buffer(2)]], constant float4* PL [[buffer(3)]],
                      uint2 gid [[thread_position_in_grid]], ushort lane [[thread_index_in_simdgroup]]) {
    float2 res = float2(out.get_width(), out.get_height());
    float t = P.tm.x, hue0 = P.au.z, flow = P.tm.z, spread = P.au.w, lum = P.look.x;
    float2 uv = (float2(gid) + 0.5 + P.taa.xy - 0.5 * res) / res.y * float2(1.0, -1.0);   // jittered: TAA integrates it
    float half_ = P.zc.z, pix = 2.0 * half_ / res.y, viewH = 2.0 * half_;
    float2 q = P.lift.xy + fh_rot((P.zc.xy + fh_rot(uv * 2.0 * half_, P.zc.w)) * P.lift.w, P.lift.z);
    FernHit r = fh_descend(q, 1.0 / P.lift.w, P.tm.y, viewH, F, T, C, ch, P, pix);

    float3 n = float3(0.0, 0.0, 1.0);
    if (P.look.w > 0.5) {
        float hn = simd_shuffle_xor(r.h, ushort(1)), hv = simd_shuffle_xor(r.h, ushort(16));
        float dhx = (lane & 1) ? r.h - hn : hn - r.h, dhy = (lane & 16) ? hv - r.h : r.h - hv;   // +x right, +y up
        n = normalize(float3(-dhx / pix, -dhy / pix, 1.0));
    }
    float3 Ld = normalize(float3(-0.5, 0.55, 0.65));
    float dif = clamp(dot(n, Ld), 0.0, 1.0);
    float spec = pow(clamp(dot(reflect(-Ld, n), float3(0.0, 0.0, 1.0)), 0.0, 1.0), 30.0);
    float cov = smoothstep(pix * 0.7, -pix * 0.7, r.d);

    // NERVE IMPULSES: each pulse a front moving down PHI (trunk → branches → leaflet tips): sharp head, short tail
    float pulse = 0.0;
    int np = int(P.tm.w);
    for (int i = 0; i < np; i++) {
        float dphi = pulses[i].x - r.phi;
        // a WAVE, not a line: a thin head lit only a few big stems (FH.16 round 2); this band sweeps the leaflets
        float head = exp(-dphi * dphi / 0.012), tail = dphi > 0.0 ? exp(-dphi / 0.35) : 0.0;
        pulse += pulses[i].y * (head + tail * 0.45);
    }
    float ripple = 0.5 + 0.5 * sin(6.2831853 * (r.phiC * spread * 2.0 - flow * t * 2.0));   // light rides the colour bands (decorative)
    // treble: a SMOOTH per-leaflet twinkle (a per-frame random sparkle read as grain at fullscreen, FH.16 round 2)
    float tw = 0.5 + 0.5 * sin(t * 5.0 + 6.2831853 * fh_hash(float2(r.id * 97.0 + floor(r.s * 9.0), 3.0)));
    float shimmer = P.au.y * smoothstep(0.6, 1.0, tw);

    // COLOUR BATH: the fern glows (emissive). Hue runs along the impulse path of the visible unit and with its on-screen
    // size (continuous: the loop stays seamless and colour shifts as each frond grows), flowing outward over time.
    float hue = hue0 + spread * r.phiC - 0.17 * log(r.scaleC / viewH) - flow * t;
    float mid = 1.0 - abs(r.across);
    float3 c0 = fh_pal(hue, PL, lum), c1 = fh_pal(hue + 0.12, PL, lum), cv = mix(fh_pal(hue + 0.06, PL, lum), float3(1.0), 0.2);
    float relief = 0.25 + 0.75 * dif;
    // bass glow (P.au.x): every bass hit swells the WHOLE fern's light at once — zero lag, no grid needed
    float3 tissue = c0 * relief * (0.18 + 0.45 * mid * mid) * (0.6 + 0.6 * ripple) * (0.8 + 1.1 * P.au.x);
    float3 glow = cv * r.vein * (0.7 + 0.6 * ripple + 2.4 * P.au.x + 7.0 * pulse);
    float rim = smoothstep(-pix * 2.5, -pix * 0.2, r.d) * cov;
    float3 edge = c1 * rim * (1.1 + 0.8 * P.au.x + 3.0 * pulse + 1.6 * shimmer);
    float3 col = tissue * (1.0 + 3.5 * pulse) + glow + edge + float3(1.0, 0.95, 0.9) * spec * 0.4;
    // the bath behind: a slow drifting fog of palette light (black read as a void, not a bath)
    float fog = 0.5 + 0.5 * sin(uv.x * 2.3 + t * 0.21) * sin(uv.y * 1.7 - t * 0.17 + 1.3 * sin(uv.x * 1.1 + t * 0.09));
    float3 bg = fh_pal(hue0 + 0.35 * uv.x + 0.25 * fog - flow * t, PL, lum) * (0.012 + 0.05 * fog * fog);
    if (gid.x < uint(res.x) && gid.y < uint(res.y)) { out.write(float4(mix(bg, col, cov), 1.0), gid); }
}

// MARK: - Temporal resolve

/// TAA: this frame's jittered sample blended into the realigned history. The dive's camera is known exactly, so the
/// previous frame is found by mapping this pixel's level-0 point through the previous camera; the history is clamped
/// to this frame's 3×3 neighbourhood (unfurl and impulses change the picture; clamping stops them smearing).
kernel void fh_resolve(texture2d<float> cur [[texture(0)]], texture2d<float> hist [[texture(1)]],
                       texture2d<float, access::write> out [[texture(2)]], constant FernParams& P [[buffer(1)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
    float2 res = float2(out.get_width(), out.get_height());
    float3 c = cur.read(gid).rgb, mn = c, mx = c, cm = 0.0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float3 n = cur.read(uint2(clamp(int2(gid) + int2(i, j), int2(0), int2(res) - 1))).rgb;
        mn = min(mn, n); mx = max(mx, n); cm += n / 9.0;
    }
    if (P.taa.w < 0.5) { out.write(float4(c, 1.0), gid); return; }
    float2 uv = (float2(gid) + 0.5 - 0.5 * res) / res.y * float2(1.0, -1.0);
    float2 q0 = P.zc.xy + fh_rot(uv * 2.0 * P.zc.z, P.zc.w);
    float2 uvp = fh_rot(q0 - P.prev.xy, -P.prev.w) / (2.0 * P.prev.z);
    float2 pp = uvp * float2(1.0, -1.0) * res.y + 0.5 * res;
    if (any(pp < 0.0) || any(pp >= res)) { out.write(float4(c, 1.0), gid); return; }
    float3 h = clamp(hist.sample(fh_lin, pp / res).rgb, mn, mx);
    // follow LIGHT changes (bass glow, impulses) within a frame or two; keep integrating the fine detail
    // compared on 3×3 MEANS: per-pixel speckle must not count as a light change (it re-admitted the grain)
    float3 hm = 0.0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) { hm += hist.sample(fh_lin, (pp + float2(i, j)) / res).rgb / 9.0; }
    float lc = dot(cm, float3(0.2126, 0.7152, 0.0722)), lh = dot(hm, float3(0.2126, 0.7152, 0.0722));
    float a = mix(P.taa.z, 0.75, smoothstep(0.15, 0.5, abs(lc - lh) / (lh + 0.05)));
    out.write(float4(mix(h, c, a), 1.0), gid);
}

// MARK: - Bloom + display

/// Bright parts → quarter resolution (the light spills into the gaps: a bath; only the brighter half blooms).
kernel void fh_bright(texture2d<float> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]],
                      uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float3 a = 0.0;
    for (int j = 0; j < 4; j++) for (int i = 0; i < 4; i++) {
        a += src.read(min(gid * 4u + uint2(i, j), uint2(src.get_width() - 1, src.get_height() - 1))).rgb;
    }
    dst.write(float4(max(a / 16.0 - 0.25, 0.0), 1.0), gid);
}

/// Separable wide Gaussian (σ ≈ 9 quarter-res texels).
kernel void fh_blur(texture2d<float> src [[texture(0)]], texture2d<float, access::write> dst [[texture(1)]],
                    constant int2& dir [[buffer(0)]], uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
    float3 a = 0.0; float ws = 0.0;
    for (int k = -24; k <= 24; k++) {
        int2 c = clamp(int2(gid) + dir * k, int2(0), int2(dst.get_width() - 1, dst.get_height() - 1));
        float w = exp(-float(k * k) / 160.0); a += src.read(uint2(c)).rgb * w; ws += w;
    }
    dst.write(float4(a / ws, 1.0), gid);
}

struct FernDisplayParams { float bloom; float white; float exposure; float pad; };
struct FernDisplayOut { float4 position [[position]]; float2 uv; };

vertex FernDisplayOut fh_display_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FernDisplayOut o; o.position = float4(p * 2.0 - 1.0, 0.0, 1.0); o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

/// Upscale the internal HDR + bloom to the drawable and tone-map on the MAX channel (hues stay saturated; per-channel
/// curves desaturated the palette). Output is linear: the drawable is sRGB.
fragment float4 fh_display_fragment(FernDisplayOut in [[stage_in]], texture2d<float> hdr [[texture(0)]],
                                    texture2d<float> bl [[texture(1)]], constant FernDisplayParams& g [[buffer(0)]]) {
    float3 c = hdr.sample(fh_lin, in.uv).rgb * g.exposure + bl.sample(fh_lin, in.uv).rgb * g.bloom;
    float m = max(c.r, max(c.g, c.b));
    c *= (1.0 + m / (g.white * g.white)) / (1.0 + m);
    return float4(clamp(c, 0.0, 1.0), 1.0);
}
