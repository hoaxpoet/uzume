# Fit look/texture knobs: element-crop texture stats + frame colour layout + dark background. Off-screen.
import numpy as np, subprocess, os, sys, json
from scipy.optimize import minimize
from scipy import ndimage as nd
sys.path.insert(0, "."); from metrics import load, hsv
from fitmat import cells, huehist, lumpct, BOX
EL = dict(pinna=(600, 560, 900, 760), rim=(1080, 120, 1240, 330), coil=(860, 250, 1100, 480), left=(480, 180, 660, 640))
def tex(a):
    out = []
    for b in EL.values():
        c = a[b[1]:b[3], b[0]:b[2]]; L = c.mean(2); m = L > 0.08
        if m.sum() < 50: out += [0] * 9; continue
        p50, p95 = np.percentile(L[m], [50, 95])
        line = ((L - nd.grey_opening(L, size=(4, 4))) > 0.12)[m].mean()           # thin bright lines/dots
        bands, prev = [], L
        for s in [0.7, 1.4, 2.8, 5.6, 11.2]:
            g = nd.gaussian_filter(L, s); bands.append(((prev - g) ** 2)[m].mean()); prev = g
        bands = np.array(bands) / (sum(bands) + 1e-9)
        out += [p95 / (p50 + 0.02) / 4, line * 3, m.mean()] + list(bands * 2)
        h, s, v = hsv(c); w = s * v * m
    return np.array(out)
ref = load("ref.png"); R = dict(C=cells(ref), H=huehist(ref), L=lumpct(ref), T=tex(ref))
BG = (ref[BOX[1]:BOX[3], BOX[0]:BOX[2]].mean(2) < 0.06)
KEYS = ["TRANS", "RIMG", "WARMK", "TALB", "LI", "LR", "BODY", "IRID", "BEAD", "KEY", "BACK", "SCAL", "FIB", "HAIRG", "LINE", "HAIRP", "LEAFW"]
X0 = [1.0, 1.04, 0.42, 0.32, 1.81, 0.32, 0.75, 2.0, 6.5, 0.44, 1.49, 4, 0.35, 2.0, 1.5, 0.25, 0.40]
def run(x, out="fitt.png"):
    e = dict(os.environ, W="1672", H="941", **{k: str(abs(v)) for k, v in zip(KEYS, x)})
    subprocess.run(["./fh5", "still", "0", out], env=e, capture_output=True); return load(out)
def terms(a):
    bg = a[BOX[1]:BOX[3], BOX[0]:BOX[2]].mean(2)[BG].mean()
    return dict(cell=np.abs(cells(a) - R["C"]).mean() * 4, hue=np.abs(huehist(a) - R["H"]).sum(),
                lum=np.abs(lumpct(a) - R["L"]).sum(), tex=np.abs(tex(a) - R["T"]).mean() * 4, bg=max(0, bg - 0.03) * 10)
def cost(x, verbose=False):
    t = terms(run(x))
    if verbose: print({k: round(float(v), 3) for k, v in t.items()})
    return sum(t.values())
if __name__ == "__main__":
    x0 = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else X0
    print("start", round(cost(x0, True), 3))
    r = minimize(cost, x0, method="Nelder-Mead", options=dict(maxiter=int(os.environ.get("IT", 400)), xatol=1e-3, fatol=1e-3, adaptive=True))
    print("fit", round(r.fun, 3), {k: round(abs(v), 3) for k, v in zip(KEYS, r.x)}); cost(r.x, True)
    print("tex ref", R["T"].round(2)); print("tex got", tex(run(r.x)).round(2))
    json.dump([abs(v) for v in r.x], open("tex.json", "w"))
