# Pinna separation: along vertical probes at 20/35/50 % of each half-width from the stalk, count dark gaps
# (>= 5 px of L < dark) between lit runs, and the dark fraction inside the probe's lit span. Wings → ~0 gaps.
import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
def pinnagap(p, dark=0.1):
    L = nd.gaussian_filter(load(p).mean(2), 1.5); m = L > dark
    ys, xs = np.nonzero(m); w = np.array([np.ptp(np.nonzero(r)[0]) if r.any() else 0 for r in m])
    rows = np.nonzero(w > 0.08 * w.max())[0]; cx = int(np.median([np.nonzero(m[y])[0].mean() for y in rows[-40:]]))   # stalk x from the base
    half = (xs.max() - xs.min()) / 2; gaps, darkf = [], []
    for f in (0.2, 0.35, 0.5):
        for s in (-1, 1):
            col = m[:, int(np.clip(cx + s * f * half, 0, m.shape[1] - 1))]; lit = np.nonzero(col)[0]
            if len(lit) < 2: continue
            seg = ~col[lit.min():lit.max() + 1]
            lab, n = nd.label(seg); sizes = nd.sum(seg, lab, range(1, n + 1))
            gaps.append(int((np.asarray(sizes) >= 5).sum())); darkf.append(seg.mean())
    return float(np.mean(gaps)), round(float(np.mean(darkf)), 2)
if __name__ == "__main__":
    for p in sys.argv[1:]: print(f"{p:40s} gaps/probe, dark-frac", pinnagap(p))
