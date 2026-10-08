# Reference-vs-render metrics for the fiddlehead spike. Off-screen judging only.
import sys, numpy as np
from PIL import Image
from scipy import ndimage as nd

def load(p, size=(1672, 941)):
    im = Image.open(p).convert("RGB")
    if im.size != size: im = im.resize(size, Image.LANCZOS)
    return np.asarray(im, np.float32) / 255.0

def lum(a): return a @ np.array([0.2126, 0.7152, 0.0722], np.float32)

def hsv(a):
    mx, mn = a.max(2), a.min(2); d = mx - mn + 1e-6
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) / 6
    return h, d / (mx + 1e-6), mx

def detail_mask(L):
    # sharp structure: local gradient energy, blurred (bokeh is soft so it drops out)
    gx, gy = nd.sobel(L, 1), nd.sobel(L, 0)
    e = nd.gaussian_filter(np.hypot(gx, gy), 6)
    return e > 0.10, e

def bands(L, m):
    # band-pass energy at octave scales inside mask, normalised: the "level of fractal detail"
    out, prev = [], L
    for s in [0.7, 1.4, 2.8, 5.6, 11.2, 22.4]:
        g = nd.gaussian_filter(L, s); out.append(float(((prev - g) ** 2)[m].mean())); prev = g
    out = np.array(out); return out / out.sum()

def boxdim(E):
    ys, xs = np.nonzero(E); n = []
    sizes = [2, 4, 8, 16, 32, 64]
    for s in sizes: n.append(len(set(zip(ys // s, xs // s))))
    k = np.polyfit(np.log(sizes), np.log(n), 1)[0]; return -k

def sparkles(L):
    th = L - nd.grey_opening(L, size=(9, 9))
    pk = (th > 0.25) & (L == nd.maximum_filter(L, 5))
    return int(pk.sum())

def stats(p):
    a = load(p); L = lum(a); h, s, v = hsv(a)
    m, e = detail_mask(L)
    gx, gy = nd.sobel(L, 1), nd.sobel(L, 0)
    E = (np.hypot(gx, gy) > 0.35) & m
    w = L[m]
    hb = np.histogram(h[m], bins=12, range=(0, 1), weights=(s * v)[m])[0]; hb = hb / hb.sum()
    ys, xs = np.nonzero(m)
    return dict(cover=float(m.mean()), cx=float(xs.mean() / a.shape[1]), cy=float(ys.mean() / a.shape[0]),
                lum_p50=float(np.percentile(w, 50)), lum_p95=float(np.percentile(w, 95)),
                sat=float(s[m & (v > 0.15)].mean()), edge_den=float(E.sum() / m.sum()),
                boxdim=float(boxdim(E)), sparkles=sparkles(L), bands=bands(L, m), hue=hb,
                grid=nd.zoom(L, (36 / a.shape[0], 64 / a.shape[1]), order=1), mask=m)

if __name__ == "__main__":
    R = stats(sys.argv[1])
    for p in sys.argv[2:]:
        X = stats(p)
        iou = (R["mask"] & X["mask"]).sum() / (R["mask"] | X["mask"]).sum()
        corr = np.corrcoef(R["grid"].ravel(), X["grid"].ravel())[0, 1]
        print(f"== {p.split('/')[-1]}  maskIoU {iou:.2f}  lumCorr {corr:.2f}")
        for k in ["cover", "cx", "cy", "lum_p50", "lum_p95", "sat", "edge_den", "boxdim", "sparkles"]:
            print(f"  {k:9s} ref {R[k]:8.3f}  got {X[k]:8.3f}")
        print("  bands ref", np.round(R["bands"], 3), "\n        got", np.round(X["bands"], 3))
        print("  hue   ref", np.round(R["hue"], 2), "\n        got", np.round(X["hue"], 2))
