#!/usr/bin/env python3
"""KAG.1 — bake Kagura's dance clips into the Renderer resource.

Reads CMU Graphics Lab motion-capture trials (ASF/AMC), cuts the Kagura library's windows, detects each
clip's pulse events on the native 120 fps data, turns every clip to the common three-quarter facing, and
writes the derived 15-joint point-light tracks plus a pulse-index map per clip:

  kagura_clips.bin   joints float16 LE [frame][15][xyz] (metres, y up) per clip, then the float32 LE
                     pulse maps (clip seconds sampled at 64 samples per pulse; PCHIP through the events)
  kagura_clips.json  manifest: per-clip metadata + byte ranges; joint order, credit, CMU source SHA-256s
  SHA256SUMS         checksums of the two files above

Ported from the KAG.0 spike (docs/presets/kagura_spike/kagura.py): the ASF/AMC parsers, the FK, JOINTS15,
the pulse detectors, face_camera and the vigor measure are carried over verbatim apart from mechanical
changes (a cache argument, the per-subject frame-rate table, face_camera also returning its yaw). The
library is Matt's decided set (docs/presets/KAGURA_DESIGN.md §4): do not add or change clips, windows,
pulse detectors or level rules here.

Usage (numpy + scipy; never add Python dependencies to the repo):
  bake_clips.py --download <cache>   fetch the trials to <cache> (outside the repo) and verify them
  bake_clips.py [--cache C] [--out D]  bake into D (default: the Renderer resource directory)
  bake_clips.py --check              per-clip pulse rate / interval CV / vigor, and whether a fresh bake
                                     matches the checked-in SHA256SUMS
The raw ASF/AMC files never enter git; the cache defaults to $KAGURA_MOCAP or ~/.cache/uzume/kagura_mocap.
"""

import argparse
import functools
import hashlib
import json
import os
import sys
import urllib.request
try:
    import numpy as np
except ImportError:   # ponytail: lets `--help` run on a bare python3; every mode needs numpy
    np = None

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
RESOURCE_DIR = os.path.join(REPO, "UzumeEngine", "Sources", "Renderer", "Resources", "Kagura")
SOURCES_SHA = os.path.join(HERE, "cmu_sources.sha256")
CMU_URL = "http://mocap.cs.cmu.edu/subjects/{subj}/{name}"
DEFAULT_CACHE = os.path.expanduser(os.environ.get("KAGURA_MOCAP", "~/.cache/uzume/kagura_mocap"))

SCRIPT_VERSION = 1
UNIT_M = 0.0254 / 0.45     # CMU ASF length unit -> metres
MOCAP_FPS = 120.0
OUT_FPS = 60               # shipped frame rate; exactly every second 120 fps frame
MAP_SAMPLES_PER_PULSE = 64
# AMC files carry no frame rate. CMU captures most subjects at 120 fps but the salsa subjects 60/61 at
# 60 (the KAG.0 erratum: assuming 120 played them at double speed). Only subjects checked by hand are
# listed; the bake refuses any other subject rather than guess.
SUBJECT_FPS = {"05": 120.0, "15": 120.0, "18": 120.0, "20": 120.0, "143": 120.0}
CREDIT = ("The data used in this project was obtained from mocap.cs.cmu.edu. "
          "The database was created with funding from NSF EIA-0196217.")

# MARK: - ASF / AMC (verbatim from the spike)

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


def subject_fps(subj):
    if subj not in SUBJECT_FPS:
        sys.exit(f"bake_clips: subject {subj} has no entry in SUBJECT_FPS; check its capture rate on "
                 "mocap.cs.cmu.edu before adding it (AMC files carry no rate)")
    return SUBJECT_FPS[subj]


@functools.lru_cache(maxsize=None)
def load_trial(cache, trial):
    """-> dict joint -> (T,3) positions in metres, Y up, feet on the floor at y=0."""
    subj = trial.split("_")[0]
    src_fps = subject_fps(subj)
    bones, children = parse_asf(os.path.join(cache, f"{subj}.asf"))
    frames = parse_amc(os.path.join(cache, f"{trial}.amc"))
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
    if src_fps != MOCAP_FPS:   # resample to the common 120 fps timeline
        t_src = np.arange(T) / src_fps
        t_dst = np.arange(0, t_src[-1], 1 / MOCAP_FPS)
        out = {k: np.stack([np.interp(t_dst, t_src, v[:, c]) for c in range(3)], 1) for k, v in out.items()}
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


def point_lights(cache, trial):
    """`trial` is a CMU id ("05_12") or a sub-range of one ("15_04@109.5-114", seconds)."""
    tid, _, rng = trial.partition("@")
    raw = load_trial(cache, tid)
    names = list(JOINTS15)
    P = np.stack([raw[JOINTS15[k]] for k in names], axis=1)  # (T,J,3)
    if rng:
        a, b = (float(x) for x in rng.split("-"))
        P = P[int(a * MOCAP_FPS):int(b * MOCAP_FPS)]
    return names, P


# MARK: - Pulse detectors (verbatim from the spike's beat_events; the footfall default is unused here)

def _extrema(sig, fps):
    """Both local maxima and minima of a smoothed, detrended signal (15 % prominence), seconds."""
    from scipy.ndimage import gaussian_filter1d
    from scipy.signal import find_peaks
    x = sig - gaussian_filter1d(sig, fps * 1.0)
    x = gaussian_filter1d(x, fps * 0.03)
    kw = dict(distance=int(0.2 * fps), prominence=np.ptp(x) * 0.15)
    return np.sort(np.concatenate([find_peaks(x, **kw)[0], find_peaks(-x, **kw)[0]])) / fps


def beat_events(P, names, fps=MOCAP_FPS, pulse=None):
    """pulse="hipyaw": each extreme of the hip line's yaw (a twist to the left or right).
    pulse="wrists": each bottom of summed wrist height (one per arm circle; the tops are uneven).
    pulse="gesture": a regular lattice at the dancer's median move period, each point snapped to the
    nearest "gesture landing" (a minimum of arm speed relative to the pelvis) within ±20 %.
    Returns (events_s, step_period_s, source).
    """
    if pulse == "hipyaw":
        hip = P[:, names.index("lhip")] - P[:, names.index("rhip")]
        ev = _extrema(np.degrees(np.unwrap(np.arctan2(hip[:, 2], hip[:, 0]))), fps)
        return ev, float(np.median(np.diff(ev))), "hip-yaw extrema"
    if pulse == "gesture":
        from scipy.ndimage import gaussian_filter1d
        from scipy.signal import find_peaks
        pel = P[:, names.index("pelvis")]
        idx = [names.index(j) for j in ("lwrist", "rwrist", "lelbow", "relbow")]
        sp = np.linalg.norm(np.gradient(P[:, idx] - pel[:, None], axis=0), axis=2).sum(1) * fps
        sp = gaussian_filter1d(sp, fps * 0.06)
        land = find_peaks(-sp, distance=int(0.4 * fps), prominence=np.ptp(sp) * 0.05)[0] / fps
        per = float(np.median(np.diff(land)))
        ph = (np.angle(np.mean(np.exp(2j * np.pi * land / per))) / (2 * np.pi)) % 1 * per
        ev = []
        for t in np.arange(ph, len(P) / fps, per):
            near = land[np.abs(land - t) < 0.2 * per]
            ev.append(near[np.argmin(np.abs(near - t))] if len(near) else t)
        return np.array(ev), per, "gesture landings"
    if pulse == "wrists":
        from scipy.ndimage import gaussian_filter1d
        from scipy.signal import find_peaks
        wy = gaussian_filter1d(P[:, names.index("lwrist"), 1] + P[:, names.index("rwrist"), 1], fps * 0.03)
        ev = find_peaks(-wy, distance=int(0.2 * fps), prominence=np.ptp(wy) * 0.15)[0] / fps
        return ev, float(np.median(np.diff(ev))), "arm-circle bottoms"
    raise ValueError(f"unknown pulse {pulse!r}")


# MARK: - Facing (verbatim; also returns the yaw it applied)

FACING_TARGET_DEG = 35.0 + 35.0   # face_camera's a_want: camera yaw 35°, then a further 35° (three-quarter)


def face_camera(P, names, yaw_deg=35.0):
    """Rotate a clip about its mean pelvis so its mean hip line (right -> left hip) sits at a
    three-quarter angle to the fixed camera. Captures face arbitrary directions; a side-on
    macarena hides every gesture edge-on (KAG.0d). -> (rotated clip, yaw applied in degrees)."""
    hip = (P[:, names.index("lhip")] - P[:, names.index("rhip")]).mean(0)
    a_now = np.arctan2(hip[2], hip[0])
    cam = np.deg2rad(yaw_deg)
    # screen-right in world is (cos cam, 0, sin cam); three-quarter = screen-right turned a further 35 deg
    a_want = np.arctan2(np.sin(cam), np.cos(cam)) + np.deg2rad(35.0)
    d = a_want - a_now
    c, s_ = np.cos(d), np.sin(d)
    ctr = P[:, names.index("pelvis")].mean(0)
    Q = P - np.array([ctr[0], 0, ctr[2]])
    x, z = Q[..., 0].copy(), Q[..., 2].copy()
    Q[..., 0] = c * x - s_ * z
    Q[..., 2] = s_ * x + c * z
    return Q, float(np.degrees(d))


def vigor(P, names):
    """Mean speed of wrists, ankles and head relative to the pelvis, m/s (the spike's dance_profile)."""
    pel = P[:, names.index("pelvis")]
    idx = [names.index(j) for j in ("lwrist", "rwrist", "lankle", "rankle", "head")]
    return float(np.linalg.norm(np.gradient(P[:, idx] - pel[:, None], axis=0), axis=2).mean() * MOCAP_FPS)


# MARK: - Library (Matt's decided set, KAGURA_DESIGN §4 — the spike's constants, unchanged)

FAMILIES = {
    "twist": ["15_04@109.5-114", "15_05@110-116"],
    "cabbage": ["15_04@117-122.5", "15_05@117-123"],
    "chicken": ["18_15@1-12.8", "20_01@0-10.7"],
    "macarena": ["143_35@0.3-10.6"],
    "egyptian": ["15_04@98-104.5", "15_05@98-104.5"],
    "sway": ["05_12"],
}
# Twist never goes to two turns per beat (KAG.0c, Matt: "half-time twist on slow songs").
PULSE_LEVELS = {"hipyaw": (1, 2, 4)}
CLIP_PULSE = {
    "15_04@109.5-114": "hipyaw", "15_05@110-116": "hipyaw",
    "15_04@117-122.5": "wrists", "15_05@117-123": "wrists",
    "18_15@1-12.8": "gesture", "20_01@0-10.7": "gesture", "143_35@0.3-10.6": "gesture",
    "15_04@98-104.5": "gesture", "15_05@98-104.5": "gesture",
}

# MARK: - Bake

def _r(x):
    """Fixed float formatting for the manifest: 6 decimals (1 µs / 1 µm)."""
    return round(float(x), 6)


def bake_clip(cache, trial, dance):
    """-> (meta, joints float16 bytes, pulse map float32 bytes, check row)."""
    names, P = point_lights(cache, trial)                    # 1. the window, native 120 fps
    pulse = CLIP_PULSE.get(trial)
    if pulse:                                                # 2. pulse events on the native data
        ev, per, _ = beat_events(P, names, pulse=pulse)
    else:
        ev, per = np.array([]), None
    vig = vigor(P, names)                                    # 3. vigor, period, levels
    levels = PULSE_LEVELS.get(pulse, (0.5, 1, 2, 4)) if pulse else ()
    Q, yaw = face_camera(P, names)                           # 4. facing + centred on the mean pelvis
    Q = Q[::int(MOCAP_FPS) // OUT_FPS]                       # 5. 120 -> 60 fps: every second frame
    if len(ev):                                              # 6. pulse-index map, PCHIP through events
        from scipy.interpolate import PchipInterpolator
        u = np.arange((len(ev) - 1) * MAP_SAMPLES_PER_PULSE + 1) / MAP_SAMPLES_PER_PULSE
        pmap = PchipInterpolator(np.arange(len(ev)), ev)(u).astype("<f4")
    else:
        pmap = np.zeros(0, "<f4")
    meta = {
        "id": trial, "dance": dance, "fps": OUT_FPS, "frame_count": len(Q),
        "pulse_kind": pulse, "pulse_events_s": [_r(t) for t in ev],
        "pulse_period_s": _r(per) if per else None, "allowed_levels": [float(m) for m in levels],
        "vigor_mps": _r(vig), "facing_yaw_deg": _r(yaw),
    }
    ibi = np.diff(ev)
    row = (trial, dance, 60 / per if per else None, float(ibi.std() / ibi.mean()) if len(ibi) > 1 else None, vig)
    return meta, Q.astype("<f2").tobytes(), pmap.tobytes(), row


def read_sources():
    """cmu_sources.sha256 -> {filename: sha256}."""
    out = {}
    for line in open(SOURCES_SHA):
        digest, name = line.split()
        out[name] = digest
    return out


def sha256(path_or_bytes):
    if isinstance(path_or_bytes, bytes):
        return hashlib.sha256(path_or_bytes).hexdigest()
    with open(path_or_bytes, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def verify_cache(cache):
    sources = read_sources()
    for name, digest in sources.items():
        p = os.path.join(cache, name)
        if not os.path.exists(p):
            sys.exit(f"bake_clips: {p} missing — run `bake_clips.py --download {cache}` first")
        if sha256(p) != digest:
            sys.exit(f"bake_clips: {p} does not match cmu_sources.sha256")
    return sources


def bake(cache):
    """-> ({filename: bytes} for the .bin, .json and SHA256SUMS, per-clip check rows)."""
    sources = verify_cache(cache)
    clips, joints, maps, rows = [], [], [], []
    for dance, trials in FAMILIES.items():
        for tr in trials:
            meta, jb, mb, row = bake_clip(cache, tr, dance)
            clips.append(meta); joints.append(jb); maps.append(mb); rows.append(row)
    off = 0
    for meta, jb in zip(clips, joints):
        meta["joints_offset"], meta["joints_length"] = off, len(jb)
        off += len(jb)
    for meta, mb in zip(clips, maps):
        meta["pulse_map_offset"], meta["pulse_map_length"] = off, len(mb)
        off += len(mb)
    manifest = {
        "script_version": SCRIPT_VERSION,
        "joints": list(JOINTS15),
        "units": "metres, y up; joints float16 little-endian [frame][joint][xyz]; "
                 "pulse maps float32 little-endian, clip seconds",
        "pulse_map_samples_per_pulse": MAP_SAMPLES_PER_PULSE,
        "facing_target_deg": FACING_TARGET_DEG,
        "source": "CMU Graphics Lab Motion Capture Database (http://mocap.cs.cmu.edu/), derived 15-joint "
                  "point-light tracks baked by tools/kagura/bake_clips.py",
        "credit": CREDIT,
        "cmu_sources_sha256": sources,
        "clips": clips,
    }
    files = {
        "kagura_clips.bin": b"".join(joints + maps),
        "kagura_clips.json": (json.dumps(manifest, sort_keys=True, indent=1) + "\n").encode(),
    }
    files["SHA256SUMS"] = "".join(f"{sha256(files[n])}  {n}\n" for n in sorted(files)).encode()
    return files, rows


# MARK: - Modes

def cmd_download(cache):
    os.makedirs(cache, exist_ok=True)
    for name in read_sources():
        p = os.path.join(cache, name)
        if not os.path.exists(p):
            url = CMU_URL.format(subj=name.split("_")[0].split(".")[0], name=name)
            print(f"fetch {url}")
            with urllib.request.urlopen(url) as r, open(p, "wb") as f:
                f.write(r.read())
    verify_cache(cache)
    print(f"{len(read_sources())} CMU files verified in {cache}")


def cmd_check(cache):
    files, rows = bake(cache)
    print("| clip | dance | pulse /min | interval CV | vigor m/s |")
    print("|---|---|---|---|---|")
    for tr, dance, rate, cv, vig in rows:
        f = lambda x, fmt: "—" if x is None else format(x, fmt)
        print(f"| {tr} | {dance} | {f(rate, '.1f')} | {f(cv, '.3f')} | {vig:.3f} |")
    print("\n| dance | vigor m/s (mean of its clips) |\n|---|---|")
    for dance in FAMILIES:
        print(f"| {dance} | {np.mean([r[4] for r in rows if r[1] == dance]):.3f} |")
    print(f"\ntotal {sum(len(files[n]) for n in ('kagura_clips.bin', 'kagura_clips.json'))} bytes")
    sums = os.path.join(RESOURCE_DIR, "SHA256SUMS")
    if os.path.exists(sums):
        same = open(sums, "rb").read() == files["SHA256SUMS"]
        print(f"fresh bake {'MATCHES' if same else 'DIFFERS FROM'} the checked-in {os.path.relpath(sums, REPO)}")
        return 0 if same else 1
    print("no checked-in SHA256SUMS yet")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--download", metavar="CACHE", help="fetch + verify the CMU trials into CACHE, then exit")
    ap.add_argument("--check", action="store_true", help="print the per-clip table; compare against SHA256SUMS")
    ap.add_argument("--cache", default=DEFAULT_CACHE, help=f"CMU trial cache (default {DEFAULT_CACHE})")
    ap.add_argument("--out", default=RESOURCE_DIR, help="output directory (default: the Renderer resource)")
    a = ap.parse_args()
    if np is None:
        sys.exit("bake_clips.py needs numpy and scipy — use a venv outside the repo")
    if a.download:
        return cmd_download(os.path.expanduser(a.download))
    cache = os.path.expanduser(a.cache)
    if a.check:
        return cmd_check(cache)
    files, _ = bake(cache)
    os.makedirs(a.out, exist_ok=True)
    for name, data in files.items():
        with open(os.path.join(a.out, name), "wb") as f:
            f.write(data)
    print(f"wrote {', '.join(sorted(files))} to {a.out}")


if __name__ == "__main__":
    sys.exit(main())
