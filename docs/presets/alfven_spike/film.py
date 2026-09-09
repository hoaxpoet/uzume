"""Alfven render pass — the CPU stand-in for the Metal fragment shader.

Render-side audio couplings, one primitive per layer (FA #67), none shared with
the physics layer (which owns bassDev):
    trebRel     -> seam bloom / sizzle          (fast, ~30 ms)
    centroid01  -> palette hue centre           (slow, seconds)
Physics layer (alfven.py) owns bassDev -> stirring vigour.

Exposure is percentile-based, i.e. it tracks the field's own distribution rather
than an absolute threshold — the same reasoning as FA #31.
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter


def autoexp(a, lo=2.0, hi=99.6):
    p1, p2 = np.percentile(a, lo), np.percentile(a, hi)
    return np.clip((a - p1) / max(p2 - p1, 1e-9), 0, 1)


def filmic(x):
    a, b, c, d, e = 2.51, 0.03, 2.43, 0.59, 0.14
    return np.clip((x * (a * x + b)) / (x * (c * x + d) + e), 0, 1)


def hsv2rgb(h, s, v):
    import matplotlib.colors as mc
    return mc.hsv_to_rgb(np.stack([h % 1.0, np.clip(s, 0, 1), np.clip(v, 0, 1)], -1))


def render(J, W, hue_centre=0.52, sizzle=0.0):
    aJ = autoexp(np.abs(J))
    sJ = np.tanh(J / (np.std(J) * 1.2 + 1e-9))          # current-sheet polarity
    # opponent hue about a slowly-drifting centre
    h = hue_centre + 0.30 * sJ
    v = filmic(1.9 * aJ ** 0.85)
    s = 0.32 + 0.58 * (1.0 - aJ ** 2)                   # hot cores desaturate to white
    rgb = hsv2rgb(h, s, v)

    # seam bloom: the brightest decile of |J|, blurred back in, treble-scaled.
    core = np.clip((aJ - 0.72) / 0.28, 0, 1) ** 1.5
    amt = 0.30 + 0.85 * float(np.clip(sizzle, 0, 1.6))
    b0 = gaussian_filter(core, 2.0)
    b1 = gaussian_filter(core, 7.0)
    glow = (0.75 * b0 + 0.55 * b1)[..., None]
    # slight chromatic split on the bloom, house-style
    tintA = np.array([1.00, 0.72, 0.42])
    tintB = np.array([0.45, 0.72, 1.00])
    split = (0.5 + 0.5 * sJ)[..., None]
    rgb = rgb + amt * glow * (tintA * split + tintB * (1 - split))

    # gentle ground so silence is never black (D-037)
    ground = np.array([0.035, 0.045, 0.075])
    return np.clip(rgb + ground * (1.0 - v[..., None]), 0, 1)


if __name__ == "__main__":
    src, tag, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
    out = "png_%s" % tag
    os.makedirs(out, exist_ok=True)
    env = np.load(tag + "_env.npz")
    treb, cen = env["trebRel"], env["centroid01"]
    n = len([f for f in os.listdir(src) if f.startswith("J_")])
    for i in range(n):
        J = np.load("%s/J_%04d.npy" % (src, i))
        W = np.load("%s/W_%04d.npy" % (src, i))
        k = min(i, len(treb) - 1)
        hue = 0.46 + 0.26 * float(cen[min(i, len(cen) - 1)])   # teal -> violet with brightness
        rgb = render(J, W, hue_centre=hue, sizzle=float(treb[k]) - 0.6)
        im = Image.fromarray((np.transpose(rgb, (1, 0, 2))[::-1] * 255).astype(np.uint8))
        im.resize((size, size), Image.LANCZOS).save("%s/f_%05d.png" % (out, i + 1))
        if (i + 1) % 100 == 0:
            print("rendered", i + 1, "/", n, flush=True)
    print("done", n, "->", out)
