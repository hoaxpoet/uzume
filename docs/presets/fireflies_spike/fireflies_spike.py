#!/usr/bin/env python3
"""FF.0 look-spike (throwaway, not engine code): pulse-coupled fireflies in a dusk meadow.

Model = Nicky Case, *Fireflies* (CC0, github.com/ncase/fireflies @ 165d16c, js/index.js):
each firefly runs a clock 0->1, flashes at 1, and a flash nudges every neighbour inside a
radius forward by  pull * clock  (capped at 1, so a nudge can trigger a flash: the relay
that makes waves). Two things are added for Uzume:

  * natural-period spread (sigma), so neighbour nudges alone form waves and clusters
    but do not lock the whole meadow inside a 30 s clip;
  * a MUSIC nudge: on every target tick of the recorded beat grid (every m-th beat,
    m chosen so the flash period sits near 1 s), each clock is pulled toward 0 by
    K * eps_beat of its wrapped distance, so flashes land on the tick.  K is the
    track's beat clarity.  NO GPU carrier for it exists yet (README section 2); the
    film uses the census D-154 `beat_irregular` flag as a LABELLED STAND-IN:
    steady=1, irregular=0, unknown=0.5.

Audio input = a session capture (features.csv) from the production analysis chain
(FixtureSessionCaptureGenerator on the real file); beat ticks come from `beatPhase01`
wraps and near-silence from `near_silent01`.  Nothing is synthesised (FA #27).

Writes <out>.mp4 (with the clip's audio), <out>_metrics.csv (per frame: R, beat lock,
frame-mean luma) and prints the per-second luminance range.  Requires numpy, pillow,
ffmpeg (on this Mac: /usr/bin/python3 has numpy+pillow; Homebrew python3 does not).
"""
import argparse
import csv
import subprocess
import sys

import numpy as np

W, H, FPS = 1280, 720, 30
HORIZON = 0.50 * H
SUB = 4  # simulation substeps per frame (tick timing at 8 ms)
TOP = 0.36     # highest firefly (fraction of frame height): just over the crowns
ETA = 0.05     # period adaptation per tick (Ermentrout 1991)
LATENCY = 0.06  # s, relay reaction delay (see simulate_frame)


# MARK: - Audio data (recorded capture)

def load_capture(session_dir):
    rows = list(csv.DictReader(open(f"{session_dir}/features.csv")))
    t = np.array([float(r["time"]) for r in rows])
    bp = np.array([float(r["beatPhase01"]) for r in rows])
    ns = np.array([float(r["near_silent01"] or 0) for r in rows])
    bpm = float(np.median([float(r["grid_bpm"]) for r in rows]))
    # Beat ticks = beatPhase01 wraps, interpolated inside the hop.
    ticks = []
    for i in np.where(np.diff(bp) < -0.5)[0]:
        span = bp[i + 1] + 1 - bp[i]
        ticks.append(t[i] + (1 - bp[i]) / span * (t[i + 1] - t[i]))
    return t, ns, np.array(ticks), bpm


def cycle_beats(bpm):
    """Beats per flash cycle: 1, 2 or 4, whichever puts the period nearest 1 s."""
    beat = 60.0 / bpm
    return min((1, 2, 4), key=lambda m: abs(np.log(m * beat)))


# MARK: - Scene (static dusk meadow)

def fbm1d(x, rng, octaves=5):
    out = np.zeros_like(x)
    for o in range(octaves):
        f = 3 * 2 ** o
        knots = rng.random(f + 2)
        out += np.interp(x * f, np.arange(f + 2), knots) / 2 ** o
    return out


def background(rng):
    y = np.arange(H)[:, None].astype(np.float32)
    xs = np.linspace(0, 1, W)
    img = np.zeros((H, W, 3), np.float32)
    # Sky: deep indigo -> a low dusk glow at the horizon.
    s = np.clip(y / HORIZON, 0, 1)[..., None]
    top, mid, low = np.array([.018, .024, .065]), np.array([.055, .07, .15]), np.array([.20, .17, .24])
    img[:] = np.where(s < .65, top + (mid - top) * (s / .65), mid + (low - mid) * ((s - .65) / .35))
    # Meadow: dark green-grey, darker toward the viewer; vertical grass strands that
    # coarsen with nearness (fine far, broad near).
    g = np.clip((y - HORIZON) / (H - HORIZON), 0, 1)[..., None]
    fine, broad = fbm1d(xs, rng, 8), fbm1d(xs, rng, 6)
    strands = (fine * (1 - g[..., 0]) + broad * g[..., 0])[..., None]
    ground = (np.array([.022, .03, .029]) * (1 - g) ** 3 + np.array([.04, .055, .048]) * (1 - (1 - g) ** 3) * (1 - g) + np.array([.008, .014, .011]) * g)
    ground = ground * (0.75 + 0.5 * (strands - 0.9) * g * 2)
    img = np.where(y[..., None] > HORIZON, ground, img)
    # Tree line: a row of rounded crowns (and the odd spire) standing on the horizon.
    crown = np.zeros(W)
    for cx in np.cumsum(rng.uniform(8, 26, 200)):
        if cx > W + 40:
            break
        w, hgt = rng.uniform(10, 55), rng.uniform(0.06, 0.15) * H
        dx = (np.arange(W) - cx) / w
        prof = np.sqrt(np.clip(1 - dx ** 2, 0, 1)) if rng.random() > .12 else np.clip(1 - np.abs(dx) * 1.2, 0, 1) * 1.35
        crown = np.maximum(crown, hgt * prof)
    crown += 0.02 * H * fbm1d(xs, rng, 7) + 0.012 * H * (fbm1d(xs * 8 % 1, rng, 5) - 0.9)  # leafy edge
    tree = (y > HORIZON - crown[None, :]) & (y <= HORIZON)
    img[tree] = np.array([.012, .017, .022])
    # Depth fog: thin on the trees, a ground mist pooling just below the horizon.
    dy = (y - HORIZON) / H
    fog = np.where(dy < 0, np.exp(-(dy / 0.035) ** 2), np.exp(-(dy / 0.10) ** 2))[..., None] * 0.45
    img = img * (1 - fog) + np.array([.10, .11, .16]) * fog
    return img.astype(np.float32)


# MARK: - Swarm

class Swarm:
    def __init__(self, n, period, sigma, rng):
        self.n = n
        self.rng = rng
        self.clock = rng.random(n)                      # random start (cold start)
        self.period = period * (1 + sigma * rng.standard_normal(n))
        # 2.5-D: fireflies sit on screen from just above the tree crowns to the foreground;
        # depth follows screen height (higher = farther), setting size, brightness and fog.
        self.u = rng.random(n)
        self.v = TOP + (1 - TOP) * rng.random(n) ** 0.8   # 0 top .. 1 bottom of frame
        self.vel = rng.standard_normal((n, 2)) * 0.004
        self.flash_t = np.full(n, -99.0)
        self.straggler = rng.random(n) < 0.05
        self.vis = np.ones(n)

    @property
    def d(self):
        return 1.0 + 8.0 * ((1 - self.v) / (1 - TOP)) ** 2

    def screen(self):
        return self.u * W, self.v * H

    def drift(self, dt):
        self.vel += self.rng.standard_normal((self.n, 2)) * 0.0015 * dt * 30
        self.vel *= 0.985
        self.u = (self.u + self.vel[:, 0] * dt * 2 / self.d) % 1.0
        self.v = np.clip(self.v + self.vel[:, 1] * dt / self.d, TOP, 0.98)


def simulate_frame(sw, t0, ticks_tgt, K, eps_m, eps_b, radius_px):
    """Advance one video frame in SUB substeps. Returns flashes this frame."""
    dt = 1.0 / FPS / SUB
    px, py = sw.screen()
    near = ((px[:, None] - px[None, :]) ** 2 + (py[:, None] - py[None, :]) ** 2) < radius_px ** 2
    np.fill_diagonal(near, False)
    flashed = []
    for s in range(SUB):
        t = t0 + s * dt
        sw.clock += dt / sw.period
        # Music nudge on each target tick inside this substep.
        if K > 0 and np.any((ticks_tgt >= t) & (ticks_tgt < t + dt)):
            wrap = np.where(sw.clock > 0.5, 1.0 - sw.clock, -sw.clock)
            sw.clock += K * eps_b * wrap
            # Ermentrout (1991) adaptive frequency, the Pteroptyx malaccae model: each
            # firefly also retunes its own period toward the stimulus, which removes the
            # steady lead the neighbour nudges would otherwise leave (late -> shorten).
            sw.period *= 1 - K * ETA * wrap
        # Flash + ncase neighbour nudge. ncase caps a nudged clock at 1 so it flashes on its
        # next update; here the cap sits LATENCY seconds short of 1, a reaction delay, so a
        # relay travels one neighbour radius per ~60 ms: the visible sweep before lock.
        fire = sw.clock >= 1.0
        if fire.any():
            sw.clock[fire] = 0.0
            sw.flash_t[fire] = t
            flashed.append((t, np.where(fire)[0]))
            # ncase applies pull once per flashing neighbour: clock *= (1+pull)^hits.
            hits = near[fire].sum(axis=0) * ~fire
            cap = 1.0 - LATENCY / sw.period
            nudged = hits > 0
            sw.clock[nudged] = np.maximum(sw.clock[nudged],
                                          np.minimum(cap[nudged], sw.clock[nudged] * (1 + eps_m) ** hits[nudged]))
    return flashed


# MARK: - Render

def stamp(sigma):
    r = int(np.ceil(3 * sigma))
    g = np.arange(-r, r + 1)
    k = np.exp(-(g[:, None] ** 2 + g[None, :] ** 2) / (2 * sigma ** 2))
    return r, k.astype(np.float32)


STAMPS = {}


def add_glow(img, x, y, sigma, amp, colour):
    key = round(sigma * 4) / 4
    if key not in STAMPS:
        STAMPS[key] = stamp(key)
    r, k = STAMPS[key]
    xi, yi = int(round(x)), int(round(y))
    x0, x1, y0, y1 = xi - r, xi + r + 1, yi - r, yi + r + 1
    if x1 <= 0 or y1 <= 0 or x0 >= W or y0 >= H:
        return
    kx0, ky0 = max(0, -x0), max(0, -y0)
    kx1, ky1 = k.shape[1] - max(0, x1 - W), k.shape[0] - max(0, y1 - H)
    img[max(0, y0):min(H, y1), max(0, x0):min(W, x1)] += (k[ky0:ky1, kx0:kx1, None] * amp) * colour


CORE = np.array([.95, 1.0, .55], np.float32)   # Photinus yellow-green
HALO = np.array([.55, .85, .20], np.float32)


def render(bg, sw, t):
    img = bg.copy()
    px, py = sw.screen()
    age = t - sw.flash_t
    env = np.where(age < 0.04, np.clip(age / 0.04, 0, 1), np.exp(-(age - 0.04) / 0.11))
    env = np.where(age < 0, 0, env)
    fogk = np.exp(-0.10 * sw.d)
    amp = env * sw.vis * fogk          # dark between flashes, as in the footage
    for i in np.where(amp > 0.004)[0]:
        near = 1.0 / sw.d[i]
        add_glow(img, px[i], py[i], 0.8 + 1.6 * near, amp[i] * 1.2, CORE)
        if env[i] > 0.05:
            add_glow(img, px[i], py[i], 2.5 + 7 * near, amp[i] * 0.06, HALO)
    return np.clip(img, 0, 1)


def luma(img):
    return float((img @ np.array([.2126, .7152, .0722], np.float32)).mean())


# MARK: - Metrics

def beat_lock(flash_times, ticks_tgt, t, window=2.0):
    """Re(mean e^{2πi ψ}) of flashes in the last `window` s, ψ = position inside the tick
    interval: +1 every flash on the tick, -1 every flash half a cycle off, 0 random
    (chance band ≈ ±1/sqrt(N flashes)). Signed, so a coherent swarm on the WRONG phase
    scores negative instead of looking locked."""
    ft = flash_times[(flash_times > t - window) & (flash_times <= t)]
    if len(ft) < 5 or len(ticks_tgt) < 2:
        return np.nan, len(ft)
    idx = np.clip(np.searchsorted(ticks_tgt, ft) - 1, 0, len(ticks_tgt) - 2)
    psi = (ft - ticks_tgt[idx]) / (ticks_tgt[idx + 1] - ticks_tgt[idx])
    return float(np.cos(2 * np.pi * psi).mean()), len(ft)


# MARK: - Main

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("session", help="capture dir holding features.csv")
    ap.add_argument("out", help="output path without extension")
    ap.add_argument("--audio", help="audio file muxed into the film (clip start = --audio-start)")
    ap.add_argument("--audio-start", type=float, default=0.0)
    ap.add_argument("--K", type=float, required=True, help="beat clarity 0..1 (stand-in: 1 steady, 0 irregular, .5 unknown)")
    ap.add_argument("--K-label", default="", help="caption for K's provenance")
    ap.add_argument("--n", type=int, default=600)
    ap.add_argument("--seconds", type=float, default=30.0)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--eps-mutual", type=float, default=0.02)
    ap.add_argument("--eps-beat", type=float, default=0.30)
    ap.add_argument("--sigma", type=float, default=0.05)
    ap.add_argument("--radius", type=float, default=80.0, help="neighbour radius, px")
    ap.add_argument("--tick-shift", type=float, default=0.0, help="shift the grid by this many beats (R1 decoy: 0.5)")
    ap.add_argument("--no-video", action="store_true", help="metrics only")
    a = ap.parse_args()

    rng = np.random.default_rng(a.seed)
    t_cap, ns_cap, ticks, bpm = load_capture(a.session)
    beat = 60.0 / bpm
    m = cycle_beats(bpm)
    true_beats = ticks.copy()            # unshifted grid, every beat: the R1 judge
    ticks = ticks + a.tick_shift * beat
    ticks_tgt = ticks[::m]
    sw = Swarm(a.n, m * beat, a.sigma, rng)
    bg = background(np.random.default_rng(3))
    frames = int(a.seconds * FPS)
    print(f"bpm {bpm:.1f}  cycle {m} beat(s) = {m * beat:.2f} s  ticks {len(ticks_tgt)}  K {a.K} {a.K_label}")

    ff = None
    if not a.no_video:
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
               "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
        if a.audio:
            cmd += ["-ss", str(a.audio_start), "-t", str(a.seconds), "-i", a.audio, "-map", "0:v", "-map", "1:a",
                    "-c:a", "aac", "-b:a", "160k"]
        cmd += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-shortest", a.out + ".mp4"]
        ff = subprocess.Popen(cmd, stdin=subprocess.PIPE)

    flash_times = []
    rows = []
    for f in range(frames):
        t = f / FPS
        silent = np.interp(t, t_cap, ns_cap) > 0.5
        target = np.where(sw.straggler, 1.0, 0.02) if silent else np.ones(a.n)
        sw.vis += (target - sw.vis) * (1 - np.exp(-1 / FPS / 1.5))
        for ft, idx in simulate_frame(sw, t, ticks_tgt, a.K, a.eps_mutual, a.eps_beat, a.radius):
            flash_times.extend([ft] * len(idx))
        sw.drift(1 / FPS)
        R = float(abs(np.exp(2j * np.pi * sw.clock).mean()))
        L, nfl = beat_lock(np.array(flash_times), ticks_tgt, t)
        Lt, _ = beat_lock(np.array(flash_times), true_beats, t)
        Y = np.nan
        if ff:
            out = np.sqrt(render(bg, sw, t))  # ~sRGB encode; luma measured on what is shown
            Y = luma(out)
            ff.stdin.write((out * 255).astype(np.uint8).tobytes())
        rows.append((t, R, L, nfl, int(silent), Y, Lt))
    if ff:
        ff.stdin.close()
        ff.wait()

    with open(a.out + "_metrics.csv", "w") as fh:
        fh.write("t,R_swarm,beat_lock,flashes_2s,near_silent,frame_luma,onbeat_true_grid\n")
        for r in rows:
            fh.write(",".join(f"{v:.4f}" if isinstance(v, float) else str(v) for v in r) + "\n")
    if not a.no_video:
        Y = np.array([r[5] for r in rows])
        per_s = [np.ptp(Y[i:i + FPS]) for i in range(0, len(Y) - FPS + 1, FPS)]
        print(f"frame-mean luma: mean {Y.mean():.4f}  per-second range max {max(per_s):.4f}  "
              f"max |Δ|/frame {np.abs(np.diff(Y)).max():.4f}   (D-157 gate: maxΔ/frame < 0.05)")
    R = np.array([r[1] for r in rows])
    L = np.array([r[2] for r in rows])
    print(f"R_swarm  0-5s {R[:150].mean():.2f}  last-5s {R[-150:].mean():.2f}   "
          f"beat_lock last-5s {np.nanmean(L[-150:]):.2f}   on-beat vs TRUE grid last-5s "
          f"{np.nanmean([r[6] for r in rows[-150:]]):+.2f}")


if __name__ == "__main__":
    sys.exit(main())
