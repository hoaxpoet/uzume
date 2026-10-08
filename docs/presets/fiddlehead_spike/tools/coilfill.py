# Coil packing: inside the coil's filled hull, the share of dark pixels (gaps between turns / between pinnae).
import sys, numpy as np
from scipy import ndimage as nd
from metrics import load
def coilfill(p, t=0.15):
    L = load(p).mean(2); m = L > t
    lab, n = nd.label(nd.binary_closing(m, structure=np.ones((9, 9))))
    big = lab == (np.argmax(np.bincount(lab.ravel())[1:]) + 1)
    hull = nd.binary_fill_holes(nd.binary_closing(big, structure=np.ones((41, 41))))
    return round(float((~m)[hull].mean()), 3), int(hull.sum())
if __name__ == "__main__":
    for p in sys.argv[1:]: print(f"{p:32s} dark-in-coil, hull px", coilfill(p))
