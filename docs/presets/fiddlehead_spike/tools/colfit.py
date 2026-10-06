# Lit-pixel colour stats vs the coil reference: 6-bin hue area share, median V, median S (v > 0.2).
import sys, numpy as np
from metrics import load, hsv
def stats(p):
    h, s, v = hsv(load(p)); m = v > 0.2
    return np.histogram(h[m], bins=6, range=(0, 1))[0] / max(m.sum(), 1), float(np.median(v[m])), float(np.median(s[m]))
REF = stats("ref.png")
def dist(p):
    hb, v, s = stats(p); return float(np.abs(hb - REF[0]).sum() + 2 * abs(v - REF[1]) + 2 * abs(s - REF[2])), hb.round(2).tolist(), round(v, 2), round(s, 2)
if __name__ == "__main__":
    print("ref", REF[0].round(2).tolist(), round(REF[1], 2), round(REF[2], 2))
    for p in sys.argv[1:]: print(p, *dist(p))
