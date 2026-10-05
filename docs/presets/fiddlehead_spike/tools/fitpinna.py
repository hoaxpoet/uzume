# Fit pinna knobs so the stalk pinnae's tip croziers land where the reference's do.
import numpy as np, subprocess, os, sys
from scipy.optimize import minimize
L = np.array([(615,230),(580,310),(555,390),(540,490),(500,610),(410,770)], float)
R = np.array([(770,430),(790,550),(830,660),(860,830)], float)
DL, DR = 30.0, 42.0                      # tip crozier diameters (left column, lower right)
KEYS = ["SIGS", "ALPHA", "PINF", "PRAMP", "ALT", "RAMPP"]
def pinnae(env):
    pf = env['PINF']
    e = dict(os.environ, W="1672", H="941", **{k: str(v) for k, v in env.items()})
    out = subprocess.run(["./fh5", "dump", "0"], env=e, capture_output=True, text=True).stdout.split("\n")
    ch = {}
    for ln in out:
        v = ln.split()
        if len(v) == 5 and v[0] == "1": ch.setdefault(v[1], []).append((float(v[2]), float(v[3]), float(v[4])))
    res = []
    for pts in ch.values():
        P = np.array(pts)
        if len(P) < 4 or P[0, 1] < 200 or P[0, 0] > 700: continue          # stalk pinnae only
        seg = P[:, 2]; s = np.concatenate([[0], np.cumsum(seg[:-1])]); tot = seg.sum()
        k = np.arange(len(P)); tip = P[1 - 0.9568 ** k > pf, :2]
        if len(tip) < 2: continue
        side = -1 if tip[:, 0].mean() < P[0, 0] else 1
        res.append((side, P[0, :2], tip.mean(0), np.ptp(tip, 0).max(), tot))
    return res
def cost(x, verbose=False):
    env = dict(zip(KEYS, x)); ps = pinnae(env); c = 0
    for side, ref, D in [(-1, L, DL), (1, R, DR)]:
        cand = [p for p in ps if p[0] == side]
        if not cand: return 1e4
        C = np.array([p[2] for p in cand])
        for t in ref:
            j = np.argmin(np.linalg.norm(C - t, axis=1)); d = np.linalg.norm(C[j] - t)
            c += d ** 2 + (0.5 * (cand[j][3] - D)) ** 2
            if verbose: print(side, t, "→", C[j].round(), "diam", round(cand[j][3]), "len", round(cand[j][4]))
    return np.sqrt(c / 10)
x0 = [float(a) for a in sys.argv[1:]] or [0.093, 0.95, 0.75, 0.06, 0.5]
print("start", round(cost(x0), 1))
r = minimize(cost, x0, method="Nelder-Mead", options=dict(maxiter=400, xatol=1e-3, fatol=0.1, initial_simplex=None))
print("fit", round(r.fun, 1), dict(zip(KEYS, np.round(r.x, 4)))); cost(r.x, True)
