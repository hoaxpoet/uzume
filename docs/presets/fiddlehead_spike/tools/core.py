import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
for p in sys.argv[1:]:
    a = load(p); L = a.mean(2); c = L[350:450, 930:1030]; E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0))[350:450, 930:1030]
    print(f"{p.split('/')[-1]:14s} core mean {c.mean():.2f} p10 {np.percentile(c,10):.2f} dark(<0.1) {(c<0.1).mean():.2f} edge {(E>0.25).mean():.2f}")
