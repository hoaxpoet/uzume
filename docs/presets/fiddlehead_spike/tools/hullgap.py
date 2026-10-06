# Dark gaps INSIDE the frond's outline (gaps outside the silhouette let a search win with a narrow solid shape).
import numpy as np
from scipy import ndimage as nd
from metrics import load
R = dict(left=(200, 300, 700, 780), right=(1000, 300, 1450, 780), top=(800, 30, 1250, 300), centre=(650, 300, 1000, 941))
def hullgap(p):
    L = load(p).mean(2); lit = nd.gaussian_filter((L > 0.12).astype(float), 3) > 0.2
    hull = nd.binary_fill_holes(nd.binary_closing(lit, structure=np.ones((61, 61))))
    E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0)) > 0.25
    out = {}
    for k, (x0, y0, x1, y1) in R.items():
        h = hull[y0:y1, x0:x1]
        out[k] = (round(float((L[y0:y1, x0:x1] < 0.08)[h].mean()), 2) if h.any() else 0, round(float(E[y0:y1, x0:x1].mean()), 2), round(float(h.mean()), 2))
    return out
if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]: print(p.split("/")[-1], "(inner-dark, edge, hull-cover)", hullgap(p))
