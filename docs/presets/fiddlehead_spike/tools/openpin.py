import numpy as np, subprocess, os, re, itertools
from scipy import ndimage as nd
from metrics import load
from curls import whorls
R = dict(left=(200, 300, 700, 780), right=(1000, 300, 1450, 780), top=(800, 30, 1250, 300), centre=(650, 300, 1000, 941), whole=(200, 30, 1450, 941))
def meas(p):
    a = load(p); L = a.mean(2); E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0)) > 0.25
    return {k: float(E[y0:y1, x0:x1].mean()) for k, (x0, y0, x1, y1) in R.items()}, [whorls(L[30:941, 200:1450], s) for s in [1.5, 3, 6, 12, 24]]
RD, RC = meas("ref_open.png")
rows = []
for con, s1, sg1, kap in itertools.product([-1.0, 0.3], [0.12, 0.2], [0.95, 0.97], [0.4, 1.0]):
    if con > 0 and kap == 1.0: continue
    env = dict(os.environ, W="1672", H="941", CURLON_O=str(con), SIGS1_O=str(s1), SIG1_O=str(sg1), KAPMIN_O=str(kap))
    r = subprocess.run(["./fh5", "still", "1", "op.png"], env=env, capture_output=True, text=True).stderr
    m = re.search(r"build ([\d.]+) ms, gpu ([\d.]+) ms", r); cost = float(m[1]) + float(m[2])
    D, C = meas("op.png")
    thin = sum(max(0, 1 - D[k] / RD[k]) for k in R)
    curl = float(np.abs(np.log((np.array(C) + 5) / (np.array(RC) + 5))) @ np.array([0.3, 0.6, 1.0, 0.6, 0.3]))
    rows.append((thin + curl, con, s1, sg1, kap, {k: round(v, 2) for k, v in D.items()}, C, round(cost, 1)))
rows.sort(key=lambda r: r[0])
print("ref", {k: round(v, 2) for k, v in RD.items()}, RC)
for r in rows: print(round(r[0], 2), "CURLON", r[1], "SIGS1", r[2], "SIG1", r[3], "KAPMIN", r[4], r[5], r[6], r[7], "ms")
