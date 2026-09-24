#!/usr/bin/env python3
"""KAG.0 — Kagura look spike (throwaway; not engine code, imports nothing from Uzume).

A point-light dancer from CMU motion capture, time-warped onto a real Uzume beat grid.

Subcommands:
  native  <trial> <out.mp4>                 plain point-lights at native speed, no audio
  tempo   <trial> [<trial> ...]             clip BPM / stability / foot-slide table
  film    <session_dir> <audio> <out.mp4>   the look: warped dancer on the session grid
          [--family F] [--shift-beats X] [--seconds N] [--irregular]
  sheet   <film.mp4> [<film.mp4> ...] <out.png>   contact sheet (R2)
  slide   <trial> [<trial> ...]             foot-slide (cm/s) at constant warp ratios

Data: CMU Graphics Lab Motion Capture Database (http://mocap.cs.cmu.edu/), ASF/AMC,
downloaded to $KAGURA_MOCAP (default ~/Documents/uzume_spikes/kagura/mocap). Never in git.
Grids: features.csv from FixtureSessionCaptureGenerator (production chain; FA #27).
Requires numpy, scipy, pillow, ffmpeg.
"""

import argparse
import csv
import os
import subprocess
import sys
try:
    import numpy as np
except ImportError:   # ponytail: lets `--help` run on a bare python3; every command needs numpy
    np = None

MOCAP = os.path.expanduser(os.environ.get("KAGURA_MOCAP", "~/Documents/uzume_spikes/kagura/mocap"))
UNIT_M = 0.0254 / 0.45     # CMU ASF length unit -> metres
MOCAP_FPS = 120.0

# MARK: - ASF / AMC

def _euler_xyz(rx, ry, rz):
    """CMU convention: R = Rz @ Ry @ Rx (angles in radians). Vectorised over frames."""
    cx, sx, cy, sy, cz, sz = np.cos(rx), np.sin(rx), np.cos(ry), np.sin(ry), np.cos(rz), np.sin(rz)
    n = np.shape(rx)
    R = np.zeros(n + (3, 3))
    R[..., 0, 0] = cy * cz; R[..., 0, 1] = sx * sy * cz - cx * sz; R[..., 0, 2] = cx * sy * cz + sx * sz
    R[..., 1, 0] = cy * sz; R[..., 1, 1] = sx * sy * sz + cx * cz; R[..., 1, 2] = cx * sy * sz - sx * cz
    R[..., 2, 0] = -sy;     R[..., 2, 1] = sx * cy;                R[..., 2, 2] = cx * cy
    return R


def parse_asf(path):
    bones, children, section, cur = {}, {}, None, None
    for raw in open(path):
        line = raw.strip()
        if line.startswith(":"):
            section = line.split()[0]
            continue
        tok = line.split()
        if section == ":bonedata":
            if tok[0] == "begin":
                cur = {"dof": []}
            elif tok[0] == "end":
                bones[cur["name"]] = cur
            elif tok[0] == "name":
                cur["name"] = tok[1]
            elif tok[0] == "direction":
                cur["dir"] = np.array(tok[1:4], float)
            elif tok[0] == "length":
                cur["len"] = float(tok[1])
            elif tok[0] == "axis":
                cur["C"] = _euler_xyz(*np.deg2rad(np.array(tok[1:4], float)))
            elif tok[0] == "dof":
                cur["dof"] = tok[1:]
        elif section == ":hierarchy" and tok and tok[0] not in ("begin", "end"):
            children[tok[0]] = tok[1:]
    return bones, children


def parse_amc(path):
    frames, cur = [], None
    for raw in open(path):
        line = raw.strip()
        if not line or line[0] in "#:":
            continue
        if line.isdigit():
            cur = {}
            frames.append(cur)
        else:
            tok = line.split()
            cur[tok[0]] = np.array(tok[1:], float)
    return frames


def load_trial(trial):
    """-> dict joint -> (T,3) positions in metres, Y up, feet on the floor at y=0."""
    subj = trial.split("_")[0]
    bones, children = parse_asf(os.path.join(MOCAP, f"{subj}.asf"))
    frames = parse_amc(os.path.join(MOCAP, f"{trial}.amc"))
    T = len(frames)
    root = np.stack([f["root"] for f in frames])
    pos = {"root": root[:, :3].copy()}
    rot = {"root": _euler_xyz(*np.deg2rad(root[:, 3:6]).T)}

    def walk(parent):
        for name in children.get(parent, []):
            b = bones[name]
            ang = np.zeros((T, 3))
            if b["dof"]:
                vals = np.stack([f.get(name, np.zeros(len(b["dof"]))) for f in frames])
                for i, d in enumerate(b["dof"]):
                    ang[:, "xyz".index(d[1])] = vals[:, i]
            local = _euler_xyz(*np.deg2rad(ang).T)
            M = rot[parent] @ b["C"] @ local @ b["C"].T
            rot[name] = M
            pos[name] = pos[parent] + b["len"] * (M @ b["dir"])
            walk(name)
    walk("root")
    out = {k: v * UNIT_M for k, v in pos.items()}
    floor = np.percentile(np.minimum(out["ltibia"][:, 1], out["rtibia"][:, 1]), 2)
    for v in out.values():
        v[:, 1] -= floor
    return out


# The 15-point Johansson / BML set, mapped to CMU bone END points.
JOINTS15 = {
    "head": "head", "neck": "lowerneck", "pelvis": "root",
    "lshoulder": "lclavicle", "lelbow": "lhumerus", "lwrist": "lradius",
    "rshoulder": "rclavicle", "relbow": "rhumerus", "rwrist": "rradius",
    "lhip": "lhipjoint", "lknee": "lfemur", "lankle": "ltibia",
    "rhip": "rhipjoint", "rknee": "rfemur", "rankle": "rtibia",
}
JOINTS13 = {k: v for k, v in JOINTS15.items() if k not in ("neck", "pelvis")}
JOINTS17 = dict(JOINTS15, ltoe="lfoot", rtoe="rfoot")
JOINT_SETS = {13: JOINTS13, 15: JOINTS15, 17: JOINTS17}


def point_lights(trial, n=15):
    raw = load_trial(trial)
    names = list(JOINT_SETS[n])
    return names, np.stack([raw[JOINT_SETS[n][k]] for k in names], axis=1)  # (T,J,3)


# MARK: - Clip tempo, beat phase, foot-slide

def _contacts(P, names, fps):
    """Per-ankle contact mask: ankle within 4 cm of its floor and moving < 0.35 m/s vertically."""
    out = {}
    for side in "lr":
        a = P[:, names.index(side + "ankle")]
        h = a[:, 1] - np.percentile(a[:, 1], 5)
        vy = np.gradient(a[:, 1]) * fps
        raw = (h < 0.04) & (np.abs(vy) < 0.35)
        # debounce: close gaps < 80 ms, then drop contacts shorter than 80 ms
        from scipy.ndimage import binary_closing, binary_opening
        w = np.ones(max(1, int(round(0.08 * fps))), bool)
        out[side] = binary_opening(binary_closing(raw, w), w)
    return out


def footfalls(P, names, fps):
    """Contact-onset times (either foot), seconds."""
    c = _contacts(P, names, fps)
    ev = []
    for side in "lr":
        ev.extend((np.flatnonzero(np.diff(c[side].astype(int)) == 1) + 1) / fps)
    return np.sort(np.array(ev))


def foot_slide(P, names, fps):
    """Median horizontal ankle speed during contact, cm/s (0 = perfectly planted)."""
    c = _contacts(P, names, fps)
    speeds = []
    for side in "lr":
        a = P[:, names.index(side + "ankle")]
        v = np.hypot(np.gradient(a[:, 0]), np.gradient(a[:, 2])) * fps
        speeds.append(v[c[side]])
    s = np.concatenate(speeds)
    return float(np.median(s) * 100) if len(s) else float("nan"), float(np.mean([c[k].mean() for k in c]))


def clip_tempo(P, names, fps=MOCAP_FPS):
    """Beat period from the autocorrelation of pelvis vertical velocity (40-200 BPM)."""
    from scipy.signal import find_peaks
    from scipy.ndimage import gaussian_filter1d
    y = P[:, names.index("pelvis"), 1]
    vy = np.gradient(y) * fps
    vy = vy - vy.mean()
    ac = np.correlate(vy, vy, "full")[len(vy) - 1:]
    ac /= ac[0]
    ff = footfalls(P, names, fps)
    train = np.zeros(len(P)); train[np.clip((ff * fps).astype(int), 0, len(P) - 1)] = 1
    train = gaussian_filter1d(train, 0.03 * fps); train -= train.mean()
    if train.any():
        acf = np.correlate(train, train, "full")[len(train) - 1:]
        ac = 0.5 * ac + 0.5 * acf / acf[0]
    lo, hi = int(fps * 60 / 220), int(fps * 60 / 40)
    pk, _ = find_peaks(ac[lo:hi])
    if not len(pk):
        return None
    pk = pk + lo
    best = pk[np.argmax(ac[pk])]
    # prefer the shortest lag with >= 80 % of the best peak (the beat, not the bar)
    for p in pk:
        if ac[p] >= 0.8 * ac[best]:
            best = p
            break
    # parabolic refinement
    a, b, c = ac[best - 1], ac[best], ac[best + 1]
    lag = best + 0.5 * (a - c) / (a - 2 * b + c)
    period = lag / fps
    # beat phase: pelvis-height minima (the "down" of each step) snapped near the lattice
    mins, _ = find_peaks(-y, distance=max(1, int(0.6 * lag)))
    ibi = np.diff(mins) / fps
    good = ibi[(ibi > 0.6 * period) & (ibi < 1.4 * period)]
    stability = float(np.std(good) / np.mean(good)) if len(good) > 3 else float("nan")
    return {"bpm": 60 / period, "period": period, "ac": float(b), "cv": stability,
            "downs": mins / fps, "falls": ff}


def beat_events(P, names, fps=MOCAP_FPS):
    """Clip beat events = the dancer's own footfalls (feet landing within 40 % of a step merged).

    Returns (events_s, step_period_s, source). Falls back to pelvis-down minima when the clip has
    too few footfalls to carry a pulse (standing / arm-led material).
    """
    info = clip_tempo(P, names, fps)
    ff = info["falls"] if info else np.array([])
    if len(ff) >= 6:
        med = np.median(np.diff(ff))
        keep = [ff[0]]
        for t in ff[1:]:
            if t - keep[-1] > 0.4 * med:
                keep.append(t)
        ev = np.array(keep)
        return ev, float(np.median(np.diff(ev))), "footfalls"
    downs = info["downs"] if info else np.array([0.0, len(P) / fps])
    return downs, float(info["period"] if info else 1.0), "pelvis-downs"


# MARK: - Session grid

def load_session(session_dir):
    rows = list(csv.DictReader(open(os.path.join(session_dir, "features.csv"))))
    t = np.array([float(r["time"]) for r in rows])
    bp = np.array([float(r["beatPhase01"]) for r in rows])
    bar = np.array([float(r["barPhase01_permille"]) for r in rows]) / 1000
    bass = np.array([float(r["bass_att"]) for r in rows])
    bpb = int(float(rows[len(rows) // 2]["beatsPerBar"]))
    bpm = float(rows[len(rows) // 2]["grid_bpm"])

    def wraps(ph):
        out = []
        for i in range(1, len(ph)):
            if ph[i - 1] - ph[i] > 0.5:                       # phase wrapped to a new cycle
                a, b = ph[i - 1], ph[i] + 1
                out.append(t[i - 1] + (1 - a) / (b - a) * (t[i] - t[i - 1]))
        return np.array(out)
    beats, bars = wraps(bp), wraps(bar)
    return {"t": t, "beats": beats, "bars": bars, "bass": bass, "bpb": bpb, "bpm": bpm,
            "bar_declined": len(bars) < 2}


# MARK: - Time-warp

def choose_level(clip_period, grid_period):
    """Grid beats per clip beat in {0.5, 1, 2}: the one whose playback rate is closest to 1."""
    best = min((0.5, 1, 2), key=lambda m: abs(np.log(clip_period / (m * grid_period))))
    return best, clip_period / (best * grid_period)


def warp_map(grid_beats, clip_events, m, start_event=0):
    """Monotone smooth map render-time -> clip-time pinning clip beat events to grid beats.

    Grid beat k lands on clip event start_event + k/m. PCHIP through the pins: continuous,
    monotone, no jumps; the phase correction is spread across each beat interval.
    """
    from scipy.interpolate import PchipInterpolator
    tt, cc = [], []
    for k, tb in enumerate(grid_beats):
        j = start_event + k / m
        if j > len(clip_events) - 1:
            break
        j0 = int(np.floor(j))
        f = j - j0
        c = clip_events[j0] if f == 0 else clip_events[j0] + f * (clip_events[j0 + 1] - clip_events[j0])
        tt.append(tb); cc.append(c)
    if len(tt) < 2:   # clip exhausted: continue at the nominal rate (clamped in sample())
        tt, cc = [grid_beats[0], grid_beats[0] + 1.0], [clip_events[-1], clip_events[-1] + 1.0]
    return np.array(tt), np.array(cc), PchipInterpolator(tt, cc, extrapolate=True)


def sample(P, clip_t, fps=MOCAP_FPS):
    """Linear-interpolate clip positions at arbitrary clip times (clamped)."""
    x = np.clip(np.asarray(clip_t) * fps, 0, len(P) - 1.001)
    i = x.astype(int)
    f = (x - i)[..., None, None]
    return P[i] * (1 - f) + P[i + 1] * f


# MARK: - Render

W, H = 720, 720
if np is not None:
    BG = np.array([4, 5, 9], float) / 255
    DOT = np.array([255, 236, 214], float) / 255
    TRAIL = np.array([255, 170, 110], float) / 255


def project(X, yaw_deg=35.0, scale=255.0, cy=0.88):
    """Orthographic three-quarter view: yaw about Y, then drop Z. Fixed camera."""
    a = np.deg2rad(yaw_deg)
    x = X[..., 0] * np.cos(a) + X[..., 2] * np.sin(a)
    y = X[..., 1]
    return np.stack([W / 2 + scale * x, H * cy - scale * y], -1)


def _splat(img, pts, sigma, color, amp):
    r = int(3 * sigma) + 1
    g = np.arange(-r, r + 1)
    for px, py in pts:
        ix, iy = int(round(px)), int(round(py))
        if ix < -r or iy < -r or ix >= W + r or iy >= H + r:
            continue
        fx, fy = px - ix, py - iy
        k = np.exp(-(((g[None, :] - fx) ** 2) + ((g[:, None] - fy) ** 2)) / (2 * sigma ** 2)) * amp
        x0, x1, y0, y1 = max(ix - r, 0), min(ix + r + 1, W), max(iy - r, 0), min(iy + r + 1, H)
        kk = k[y0 - (iy - r):y1 - (iy - r), x0 - (ix - r):x1 - (ix - r)]
        img[y0:y1, x0:x1] += kk[..., None] * color


def render(frames_fn, n_frames, fps, out, audio=None, audio_start=0.0, trails=True, strip=None):
    """frames_fn(t_array) -> (len, J, 3) world positions. Streams PNG-free raw RGB to ffmpeg."""
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{W}x{H if strip is None else H + 60}", "-r", str(fps), "-i", "-"]
    if audio:
        cmd += ["-ss", str(audio_start), "-t", str(n_frames / fps), "-i", audio, "-c:a", "aac", "-shortest"]
    cmd += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", out]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    trail = np.zeros((H, W, 3))
    decay = 0.05 ** (1 / (0.4 * fps))              # a trail point fades to 5 % in 0.4 s
    sub = 6
    for f in range(n_frames):
        t0 = f / fps
        ts = t0 - (np.arange(sub)[::-1] / sub) / fps
        pts = project(frames_fn(ts))                # (sub, J, 2)
        trail *= decay
        if trails:
            for s in range(sub):
                _splat(trail, pts[s], 2.4, TRAIL, 0.22)
        img = BG + trail
        halo = np.zeros((H, W, 3)); core = np.zeros((H, W, 3))
        _splat(halo, pts[-1], 9.0, DOT, 0.22)
        _splat(core, pts[-1], 2.6, DOT, 1.0)
        img = img + halo + core
        img = 1 - np.exp(-1.6 * img)                # soft filmic shoulder
        frame = (np.clip(img, 0, 1) * 255).astype(np.uint8)
        if strip is not None:
            frame = np.concatenate([frame, strip(t0)], 0)
        proc.stdin.write(frame.tobytes())
    proc.stdin.close()
    proc.wait()


def beat_strip(beats, window=2.0):
    """A 60 px strip: beat ticks scroll past a fixed centre playhead (tick at centre = on the beat)."""
    def draw(t):
        s = np.zeros((60, W, 3), np.uint8); s[:] = (12, 12, 16)
        s[:, W // 2 - 1:W // 2 + 1] = (90, 90, 110)
        for b in beats:
            dx = (b - t) / window * (W / 2)
            x = int(W / 2 + dx)
            if 0 <= x < W - 3:
                s[10:50, x:x + 3] = (240, 200, 80)
        return s
    return draw


# MARK: - Commands

def cmd_native(a):
    names, P = point_lights(a.trial, a.joints)
    c = P[0, [names.index("lhip"), names.index("rhip")]].mean(0)
    P = P - np.array([c[0], 0, c[2]])
    n = int(min(a.seconds, len(P) / MOCAP_FPS) * 30)
    render(lambda ts: sample(P, ts + a.start), n, 30, a.out, trails=False)


def cmd_tempo(a):
    print("| clip | seconds | clip BPM | autocorr peak | pelvis-down interval CV | footfall R vs own lattice (chance) | foot-slide cm/s | contact % |")
    print("|---|---|---|---|---|---|---|---|")
    for tr in a.trials:
        names, P = point_lights(tr)
        info = clip_tempo(P, names)
        fs, cf = foot_slide(P, names, MOCAP_FPS)
        if info:
            d = info["falls"] if len(info["falls"]) > 3 else info["downs"]; per = info["period"]
            ph0 = (np.angle(np.mean(np.exp(2j * np.pi * d / per))) / (2 * np.pi)) % 1 * per
            lat = np.arange(ph0, len(P) / MOCAP_FPS, per)
            rf, _, nf, _, _, _ = beat_lock(P, names, MOCAP_FPS, lat) if len(lat) > 2 else (0, 0, 0, 0, 0, 0)
            print(f"| {tr} | {len(P)/MOCAP_FPS:.1f} | {info['bpm']:.1f} | {info['ac']:.2f} | {info['cv']:.2f} | "
                  f"{rf:.2f} ({0.89/np.sqrt(max(nf,1)):.2f}, n={nf}) | {fs:.1f} | {cf*100:.0f} |")
        else:
            print(f"| {tr} | {len(P)/MOCAP_FPS:.1f} | — | — | — | — | {fs:.1f} | {cf*100:.0f} |")


FAMILIES = {   # clip list per family; the film cycles through them on bar boundaries
    "salsa": ["60_03", "61_02", "60_08"],
    "lindy": ["93_05", "103_05", "93_07"],
    "modern": ["05_02", "05_11"],
    "sway": ["05_12"],
}


def build_dancer(sess, family, shift_beats=0.0, seconds=30.0, irregular=False, bars_per_clip=4):
    """-> (frames_fn, log). frames_fn(t) gives warped, energy-scaled world positions."""
    fps_r = 30
    beats = sess["beats"] + shift_beats * 60 / sess["bpm"]
    grid_period = 60 / sess["bpm"]
    t = sess["t"]
    # energy envelope: bass_att, 1.5 s EMA, per-track percentile normalised, soft-saturated
    e = np.copy(sess["bass"])
    k = 1 - np.exp(-(t[1] - t[0]) / 1.5)
    for i in range(1, len(e)):
        e[i] = e[i - 1] + k * (e[i] - e[i - 1])
    lo, hi = np.percentile(e, 10), np.percentile(e, 90)
    en = np.tanh((e - (lo + hi) / 2) / max(hi - lo, 1e-6) * 2)
    scale_of = lambda tq: 1 + 0.25 * np.interp(tq, t, en)    # at most ±25 %

    clips, log = [], []
    if irregular or len(beats) < 8:
        names, P = point_lights(FAMILIES["sway"][0])
        dur = len(P) / MOCAP_FPS
        # ping-pong loop (forward, then backward): a plain modulo wrap teleports the figure (a pop)
        segs = [(0.0, seconds + 1, P, lambda tq, d=dur - 0.02: d - np.abs(np.mod(tq, 2 * d) - d), 1.0)]
        log.append(f"fallback: unwarped sway clip {FAMILIES['sway'][0]} (beat-irregular / bar-declined)")
    else:
        # clip changes on bar boundaries: each clip runs up to bars_per_clip bars, or fewer
        # if its capture runs out first (the Lindy trials are 2-5 s long)
        bpb = sess["bpb"] if sess["bpb"] > 1 else 4
        bar_times = sess["bars"] + shift_beats * grid_period if not sess["bar_declined"] \
            else beats[::bpb]
        bar_times = bar_times[bar_times < seconds]
        t0, si, segs, rates = 0.0, 0, [], []
        while t0 < seconds:
            tr = FAMILIES[family][si % len(FAMILIES[family])]
            names, P = point_lights(tr)
            ev, step, src = beat_events(P, names)
            m, ratio = choose_level(step, grid_period)
            seg_beats = beats[beats >= t0 - 2 * grid_period]
            tt, cc, fmap = warp_map(seg_beats, ev, m, start_event=1)
            loc = np.diff(cc) / np.diff(tt)                   # local playback rate per beat
            cover = tt[-1] - 0.5 * grid_period
            limit = min(cover, t0 + bars_per_clip * bpb * grid_period + 0.5 * grid_period)
            ok = bar_times[(bar_times > t0 + 0.5 * grid_period) & (bar_times <= limit)]
            nxt = bar_times[bar_times > t0 + 0.5 * grid_period]
            t1 = ok[-1] if len(ok) else (nxt[0] if len(nxt) else seconds + 1)
            segs.append((t0, t1, P, fmap, ratio))
            inseg = (tt[:-1] >= t0) & (tt[:-1] < min(t1, seconds))
            lr = loc[inseg] if inseg.any() else loc
            log.append(f"{t0:6.2f}-{min(t1, seconds):6.2f}s  {tr}  steps {60/step:.1f}/min ({src})  "
                       f"level x{m}  nominal warp {ratio:.3f}  local rate p10/50/90 "
                       f"{np.percentile(lr,10):.2f}/{np.median(lr):.2f}/{np.percentile(lr,90):.2f}")
            rates.extend(lr.tolist())
            t0, si = t1, si + 1
        r = np.array(rates)
        log.append(f"ALL local playback rate p10/50/90 {np.percentile(r,10):.2f}/{np.median(r):.2f}/"
                   f"{np.percentile(r,90):.2f}  (1.00 = native speed)")
    names_ = names
    pel = names_.index("pelvis")
    xfade = grid_period                                   # crossfade over one beat

    def seg_pose(s, tq):
        _, _, P, fmap, _ = s
        X = sample(P, fmap(tq))
        return X

    # position-continuous handoff: each new clip is placed so the midpoint of its ankles at the
    # cut coincides with the outgoing clip's (the first clip starts at the origin). The camera never moves.
    la, ra = names_.index("lankle"), names_.index("rankle")
    feet = lambda X: np.array([(X[la, 0] + X[ra, 0]) / 2, 0, (X[la, 2] + X[ra, 2]) / 2])
    offs = []
    for i, s in enumerate(segs):
        X0 = seg_pose(s, np.array([s[0]]))[0]
        if i == 0:
            offs.append(np.array([X0[pel, 0], 0, X0[pel, 2]]))
        else:
            Xp = seg_pose(segs[i - 1], np.array([s[0]]))[0] - offs[i - 1]
            offs.append(feet(X0) - feet(Xp))

    def frames_raw(ts):
        ts = np.asarray(ts, float)
        out = np.zeros((len(ts), len(names_), 3))
        for i, tq in enumerate(ts):
            si = max(j for j, s in enumerate(segs) if s[0] <= max(tq, 0) or j == 0)
            X = seg_pose(segs[si], np.array([tq]))[0] - offs[si]
            if si > 0 and tq < segs[si][0] + xfade:
                w = (tq - segs[si][0]) / xfade
                w = w * w * (3 - 2 * w)
                Xp = seg_pose(segs[si - 1], np.array([tq]))[0] - offs[si - 1]
                X = Xp * (1 - w) + X * w
            # energy scales ARM excursion about each shoulder (the legs are left alone: scaling a
            # planted foot's offset while the pelvis moves drags the foot — measured +50 % slide)
            s_ = scale_of(tq)
            for side in "lr":
                sh = X[names_.index(side + "shoulder")]
                for j in ("elbow", "wrist"):
                    ji = names_.index(side + j)
                    X[ji] = sh + s_ * (X[ji] - sh)
            out[i] = X
        return out

    # leash: subtract a slow zero-phase low-pass (Gaussian, sigma 2 s) of the pelvis's floor path so
    # a travelling dancer stays in the fixed frame. Costs slide equal to the leash's own speed.
    from scipy.ndimage import gaussian_filter1d
    grid_t = np.arange(-1, seconds + 2, 1 / 30)
    ph = np.concatenate([frames_raw(grid_t[i:i + 90])[:, pel] for i in range(0, len(grid_t), 90)])
    lx = gaussian_filter1d(ph[:, 0], 2 * 30, mode="nearest")
    lz = gaussian_filter1d(ph[:, 2], 2 * 30, mode="nearest")

    def frames_fn(ts):
        X = frames_raw(ts)
        X[..., 0] -= np.interp(ts, grid_t, lx)[:, None]
        X[..., 2] -= np.interp(ts, grid_t, lz)[:, None]
        return X
    return frames_fn, names_, segs, log


def beat_lock(Y, names, fps, beats):
    """Where do footfalls (contact onsets) and pelvis-downs land in the beat? Circular stats.

    Returns (R_foot, phase_foot, n_foot, R_pelvis, phase_pelvis, n_pelvis). R = 1 means every event
    at the same beat phase; a uniform (unlocked) process gives R ~ 0.89/sqrt(n) (the chance level).
    """
    from scipy.signal import find_peaks
    ev = footfalls(Y, names, fps)
    y = Y[:, names.index("pelvis"), 1]
    downs = find_peaks(-y, distance=int(0.2 * fps))[0] / fps

    def stats(times):
        times = np.asarray([t for t in times if beats[0] <= t < beats[-1]])
        if not len(times):
            return 0.0, 0.0, 0
        k = np.searchsorted(beats, times, side="right") - 1
        ph = (times - beats[k]) / (beats[k + 1] - beats[k])
        z = np.mean(np.exp(2j * np.pi * ph))
        stats.hist = np.histogram(ph, bins=8, range=(0, 1))[0]
        stats.r2 = float(abs(np.mean(np.exp(4j * np.pi * ph))))      # half-beat level
        return float(abs(z)), float((np.angle(z) / (2 * np.pi)) % 1), len(times)
    out = stats(ev)
    beat_lock.foot_hist, beat_lock.foot_r2 = stats.hist, stats.r2
    return out + stats(downs)


def cmd_film(a):
    sess = load_session(a.session)
    fn, names, segs, log = build_dancer(sess, a.family, a.shift_beats, a.seconds, a.irregular)
    print(f"grid {sess['bpm']:.2f} BPM, {len(sess['beats'])} beats, {len(sess['bars'])} bars, "
          f"bpb {sess['bpb']}, bar_declined={sess['bar_declined']}")
    for line in log:
        print("  " + line)
    n = int(a.seconds * 30)
    strip = beat_strip(sess["beats"]) if a.strip else None
    render(fn, n, 30, a.out, audio=None if a.mute else a.audio, strip=strip)
    # measured foot-slide + footfall-to-beat alignment on the rendered motion
    ts = np.arange(n) / 30.0
    Y = np.concatenate([fn(ts[i:i + 60]) for i in range(0, n, 60)])
    fs, cf = foot_slide(Y, names, 30)
    xf = np.zeros(n, bool)
    for sg in segs[1:]:
        xf |= (ts >= sg[0]) & (ts < sg[0] + 60 / sess["bpm"])
    c = _contacts(Y, names, 30)
    sp = {sd: np.hypot(*np.gradient(Y[:, names.index(sd + "ankle")][:, [0, 2]], axis=0).T) * 30 for sd in "lr"}
    def med(mask):
        v = np.concatenate([sp[sd][c[sd] & mask] for sd in "lr"])
        return np.median(v) * 100 if len(v) else float("nan")
    pel = names.index("pelvis")
    print(f"  pelvis horizontal extent x [{Y[:, pel, 0].min():.2f}, {Y[:, pel, 0].max():.2f}] m, "
          f"z [{Y[:, pel, 2].min():.2f}, {Y[:, pel, 2].max():.2f}] m")
    print(f"  output foot-slide {fs:.1f} cm/s (contact {cf*100:.0f} %) — outside crossfades {med(~xf):.1f}, "
          f"inside crossfades {med(xf):.1f}")
    rf, pf, nf, rp, pp, npv = beat_lock(Y, names, 30, sess["beats"])
    print(f"  vs TRUE grid: footfalls R={rf:.2f} phase={pf:.2f} n={nf} (chance {0.89/np.sqrt(max(nf,1)):.2f}); "
          f"pelvis-downs R={rp:.2f} phase={pp:.2f} n={npv} (chance {0.89/np.sqrt(max(npv,1)):.2f})")
    print(f"  footfall beat-phase histogram (8 bins from the beat): {beat_lock.foot_hist.tolist()}  "
          f"R at half-beat level {beat_lock.foot_r2:.2f}")


def cmd_slide(a):
    """Foot-slide at constant warp ratios: resample the clip at rate r, measure at 30 fps."""
    ratios = [0.5, 0.67, 0.8, 1.0, 1.25, 1.5, 2.0]
    print("| clip | " + " | ".join(f"x{r}" for r in ratios) + " |")
    print("|---|" + "---|" * len(ratios))
    for tr in a.trials:
        names, P = point_lights(tr)
        dur = len(P) / MOCAP_FPS
        row = []
        for r in ratios:
            ts = np.arange(0, dur / r, 1 / 30)
            Y = sample(P, ts * r)
            fs, _ = foot_slide(Y, names, 30)
            row.append(f"{fs:.1f}")
        print(f"| {tr} | " + " | ".join(row) + " |")


def cmd_sheet(a):
    from PIL import Image
    rows = []
    for f in a.films:
        tiles = []
        for s in np.linspace(1, a.seconds - 1, 8):
            p = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", f"{s:.2f}", "-i", f, "-frames:v", "1",
                                "-vf", "scale=240:-1", "-f", "image2pipe", "-vcodec", "png", "-"],
                               capture_output=True).stdout
            import io
            tiles.append(Image.open(io.BytesIO(p)).convert("RGB"))
        w, h = tiles[0].size
        row = Image.new("RGB", (w * len(tiles), h))
        for i, im in enumerate(tiles):
            row.paste(im, (i * w, 0))
        rows.append(row)
    sheet = Image.new("RGB", (rows[0].width, sum(r.height for r in rows)))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y)); y += r.height
    sheet.save(a.out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    p = sp.add_parser("native"); p.add_argument("trial"); p.add_argument("out")
    p.add_argument("--seconds", type=float, default=10); p.add_argument("--start", type=float, default=2)
    p.add_argument("--joints", type=int, default=15, choices=(13, 15, 17))
    p = sp.add_parser("tempo"); p.add_argument("trials", nargs="+")
    p = sp.add_parser("film"); p.add_argument("session"); p.add_argument("audio"); p.add_argument("out")
    p.add_argument("--family", default="salsa", choices=sorted(FAMILIES))
    p.add_argument("--shift-beats", type=float, default=0.0)
    p.add_argument("--seconds", type=float, default=30)
    p.add_argument("--irregular", action="store_true")
    p.add_argument("--strip", action="store_true"); p.add_argument("--mute", action="store_true")
    p = sp.add_parser("slide"); p.add_argument("trials", nargs="+")
    p = sp.add_parser("sheet"); p.add_argument("films", nargs="+"); p.add_argument("out")
    p.add_argument("--seconds", type=float, default=30)
    a = ap.parse_args()
    if np is None:
        sys.exit("kagura.py needs numpy, scipy and pillow (see the README's venv)")
    {"native": cmd_native, "tempo": cmd_tempo, "film": cmd_film, "sheet": cmd_sheet, "slide": cmd_slide}[a.cmd](a)


if __name__ == "__main__":
    main()
