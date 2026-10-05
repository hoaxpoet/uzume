# Fractal-depth instrument: count curl centres (whorls) per scale octave via the Poincaré index of the
# structure-tensor orientation field. Same pipeline on reference and render; compare the profile.
import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
BOX = (380, 30, 1260, 941)
def whorls(L, s):
    g = nd.gaussian_filter(L, s * 0.5)
    gx, gy = nd.sobel(g, 1), nd.sobel(g, 0)
    jxx, jyy, jxy = (nd.gaussian_filter(v, s) for v in (gx * gx, gy * gy, gx * gy))
    phi = np.arctan2(2 * jxy, jxx - jyy)                         # doubled orientation angle
    coh = np.sqrt((jxx - jyy) ** 2 + 4 * jxy ** 2) / (jxx + jyy + 1e-9)
    st = max(1, int(s)); P = phi[::st, ::st]; C = coh[::st, ::st]; I = g[::st, ::st]
    def d(a, b): return (b - a + np.pi) % (2 * np.pi) - np.pi
    h = 2                                                         # loop half-size in cells
    ring = [(-h, x) for x in range(-h, h)] + [(y, h) for y in range(-h, h)] + [(h, x) for x in range(h, -h, -1)] + [(y, -h) for y in range(h, -h, -1)]
    w = np.zeros_like(P)
    for (y0, x0), (y1, x1) in zip(ring, ring[1:] + ring[:1]):
        w += d(np.roll(P, (-y0, -x0), (0, 1)), np.roll(P, (-y1, -x1), (0, 1)))
    w /= 2 * np.pi
    ok = (C > 0.15) & (I > 0.10)
    core = (w > 1.5) & ok                                         # index ≥ +1: a full whorl (curl), not an endpoint
    lab, n = nd.label(nd.binary_dilation(core, iterations=1))     # one count per curl, not per cell
    return int(n)
def profile(p):
    a = load(p); L = a.mean(2)[BOX[1]:BOX[3], BOX[0]:BOX[2]]
    return [whorls(L, s) for s in [1.5, 3, 6, 12, 24]]
if __name__ == "__main__":
    for p in sys.argv[1:]: print(f"{p:14s} curls per scale (1.5, 3, 6, 12, 24 px):", profile(p))
REG = dict(pinna=(600, 560, 900, 760), rim=(1080, 120, 1240, 330), coil=(860, 250, 1100, 480), left=(480, 180, 660, 640))
def regional(p):
    a = load(p); L = a.mean(2)
    return {k: [whorls(L[y0:y1, x0:x1], s) for s in [3, 6, 12]] for k, (x0, y0, x1, y1) in REG.items()}
