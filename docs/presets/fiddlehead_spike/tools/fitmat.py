# Fit material/light gains so the render's colour layout matches the reference (off-screen).
import numpy as np, subprocess, os, sys, json
from scipy.optimize import minimize
from PIL import Image
sys.path.insert(0, "."); from metrics import load, hsv
BOX = (380, 30, 1260, 941)                          # the fern
def cells(a, nx=8, ny=8):
    x0, y0, x1, y1 = BOX; c = a[y0:y1, x0:x1]
    h, w = c.shape[0] // ny, c.shape[1] // nx
    return c[:h*ny, :w*nx].reshape(ny, h, nx, w, 3).mean((1, 3))
def huehist(a):
    x0, y0, x1, y1 = BOX; c = a[y0:y1, x0:x1]; h, s, v = hsv(c); wgt = (s * v) * (v > 0.25)
    hb = np.histogram(h, bins=12, range=(0, 1), weights=wgt)[0]; return hb / hb.sum()
def lumpct(a):
    x0, y0, x1, y1 = BOX; L = a[y0:y1, x0:x1].mean(2); return np.percentile(L, [50, 90, 99])
ref = load("ref.png"); RC, RH, RL = cells(ref), huehist(ref), lumpct(ref)
KEYS = ["TRANS", "RIMG", "WARMK", "TALB", "LI", "LR", "BODY", "IRID", "BEAD", "HAZE", "KEY", "BACK"]
X0 = [1.0, 1.0, 0.5, 0.5, 4.0, 0.40, 1.0, 1.0, 6.0, 0.25, 0.55, 1.1]
def run(x, out="fit.png", extra={}):
    e = dict(os.environ, W="1672", H="941", **{k: str(abs(v)) for k, v in zip(KEYS, x)}, **extra)
    subprocess.run(["./fh5", "still", "0", out], env=e, capture_output=True)
    return load(out)
def cost(x, verbose=False):
    a = run(x); C, Hh, Lp = cells(a), huehist(a), lumpct(a)
    c = np.abs(C - RC).mean() * 4 + np.abs(Hh - RH).sum() + np.abs(Lp - RL).sum()
    if verbose:
        print("cellRGB", round(float(np.abs(C - RC).mean()) * 255, 1), "/255  hueL1", round(float(np.abs(Hh - RH).sum()), 2),
              "lum p50/90/99 ref", RL.round(2), "got", Lp.round(2))
        print("hue ref", RH.round(2)); print("hue got", Hh.round(2))
    return c
if __name__ == '__main__':
    x0 = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else X0
    print("start", round(cost(x0, True), 3))
    r = minimize(cost, x0, method="Nelder-Mead", options=dict(maxiter=int(os.environ.get("IT", 250)), xatol=1e-3, fatol=1e-3))
    print("fit", round(r.fun, 3), {k: round(abs(v), 3) for k, v in zip(KEYS, r.x)}); cost(r.x, True)
    json.dump([abs(v) for v in r.x], open("mat.json", "w"))
