# Spatial colour: hue histogram per region (core vs fronds) — whole-image histograms let orange flood everything.
import numpy as np
from metrics import load, hsv
RG = dict(core=(880, 290, 1080, 520), coilring=(700, 40, 1240, 620), fronds=(380, 450, 900, 941), left=(480, 150, 680, 640))
def rh(a):
    out = {}
    for k, (x0, y0, x1, y1) in RG.items():
        c = a[y0:y1, x0:x1]; h, s, v = hsv(c); w = s * v * (v > 0.2)
        hb = np.histogram(h, bins=6, range=(0, 1), weights=w)[0]; out[k] = hb / (hb.sum() + 1e-9)
    return out
if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        r = rh(load(p)); print(p, {k: v.round(2).tolist() for k, v in r.items()})
def area(a):
    # area-weighted: hue share among visibly coloured pixels (v>0.2, s>0.25), plus the body value of green pixels
    out = {}
    for k, (x0, y0, x1, y1) in RG.items():
        c = a[y0:y1, x0:x1]; h, s, v = hsv(c); m = (v > 0.2) & (s > 0.25)
        hb = np.histogram(h[m], bins=6, range=(0, 1))[0]; hb = hb / (hb.sum() + 1e-9)
        g = m & (h > 1 / 6) & (h < 0.5)
        out[k] = (hb, float(v[g].mean()) if g.any() else 0.0, float(m.mean()))
    return out
