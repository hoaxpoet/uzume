# Stalk read: along the frond's central axis, the bright-run width and brightness vs the median leaf brightness.
import sys, numpy as np
from metrics import load
def spine(p):
    L = load(p).mean(2); m = L > 0.1; ys = np.nonzero(m.any(1))[0]; y0, y1 = ys.min(), ys.max()
    out = []
    for f in (0.9, 0.7, 0.5, 0.3, 0.15):
        y = int(y0 + f * (y1 - y0)); row = L[y]; lit = np.nonzero(row > 0.1)[0]
        cx = int(np.median(lit)); win = row[cx - 40:cx + 40]; pk = int(np.argmax(win)) + cx - 40
        thr = 0.5 * row[pk]; l = pk; r = pk
        while l > 0 and row[l - 1] > thr: l -= 1
        while r < len(row) - 1 and row[r + 1] > thr: r += 1
        out.append((round(f, 2), r - l + 1, round(float(row[pk]), 2)))
    return out, round(float(np.median(L[m])), 2)
if __name__ == "__main__":
    for p in sys.argv[1:]: print(p, "(height-frac, stalk px, stalk L) / leaf median L:", *spine(p))
