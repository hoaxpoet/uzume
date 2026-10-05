# Density instrument: per-region structure coverage + edge fraction (the "thinned detail" failure).
import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
REG = dict(pinna=(600, 560, 900, 760), rim=(1080, 120, 1240, 330), coil=(860, 250, 1100, 480), left=(480, 180, 660, 640), whole=(380, 30, 1260, 941))
def dens(p):
    a = load(p); L = a.mean(2); out = {}
    E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0)) > 0.25
    for k, (x0, y0, x1, y1) in REG.items():
        out[k] = (float((L[y0:y1, x0:x1] > 0.10).mean()), float(E[y0:y1, x0:x1].mean()))
    return out
if __name__ == "__main__":
    R = dens("ref.png")
    for p in sys.argv[1:]:
        D = dens(p); print(p, " ".join(f"{k}: cov {D[k][0]:.2f}/{R[k][0]:.2f} edge {D[k][1]:.2f}/{R[k][1]:.2f}" for k in REG))
