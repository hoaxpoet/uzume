# Fine-structure contrast: fraction of in-silhouette pixels with a strong 1-px gradient. Fog (uniform fill) scores low.
import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
def edgefine(p):
    L = load(p).mean(2); lit = nd.binary_closing(nd.gaussian_filter((L > 0.1).astype(float), 3) > 0.2, structure=np.ones((31, 31)))
    E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0)) / 8
    return round(float((E > 0.03)[lit].mean()), 3), round(float(lit.mean()), 3)
if __name__ == "__main__":
    for p in sys.argv[1:]: print(f"{p:40s} fine-edge, lit-frac", edgefine(p))
