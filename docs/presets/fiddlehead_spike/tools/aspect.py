# Frond-only aspect (wide:tall), bare stalk rows dropped. Reference open frond = 1.85.
import sys, numpy as np
from PIL import Image
def aspect(p, t=0.15):
    m = np.asarray(Image.open(p).convert("RGB")).astype(float).mean(2) / 255 > t
    w = np.array([np.ptp(np.nonzero(r)[0]) if r.any() else 0 for r in m])
    rows = np.nonzero(w > 0.08 * w.max())[0]; xs = np.nonzero(m[rows].any(0))[0]
    return round(np.ptp(xs) / np.ptp(rows), 2)
if __name__ == "__main__":
    for p in sys.argv[1:]: print(f"{p:42s} aspect", aspect(p))
