# Dark fraction INSIDE the frond hull by distance from the stalk (0 = stalk, 1 = outer edge). A bare central
# ladder of petioles shows as a high first bin; the reference is roughly flat.
import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
def radial(p):
    L = nd.gaussian_filter(load(p).mean(2), 1.5); m = L > 0.1
    hull = nd.binary_fill_holes(nd.binary_closing(nd.gaussian_filter(m.astype(float), 3) > 0.2, structure=np.ones((61, 61))))
    ys, xs = np.nonzero(hull); w = np.array([np.ptp(np.nonzero(r)[0]) if r.any() else 0 for r in hull])
    rows = np.nonzero(w > 0.08 * w.max())[0]; cx = np.median([np.nonzero(m[y])[0].mean() for y in rows[-40:] if m[y].any()])
    d = np.abs(np.arange(L.shape[1])[None, :] - cx) / (np.ptp(xs) / 2); d = np.broadcast_to(d, L.shape)
    return [round(float((~m)[hull & (d >= a) & (d < a + 0.2)].mean()), 2) for a in np.arange(0, 1, 0.2)]
if __name__ == "__main__":
    for p in sys.argv[1:]: print(f"{p:40s} dark-in-hull by |x| bin (stalk→edge)", radial(p))
