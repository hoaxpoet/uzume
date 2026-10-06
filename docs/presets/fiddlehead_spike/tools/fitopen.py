# Fit the OPEN-frond parameters (KEY_O) to Matt's open reference: stalk path + 12 pinna-tip croziers.
import numpy as np, subprocess, os, sys, json
from scipy.optimize import minimize
RACH = np.array([(800, 941), (820, 820), (840, 700), (880, 500), (920, 350), (960, 230), (1000, 150), (1050, 90)], float)
TOP, TOPD = np.array([1145, 80.0]), 70.0
L = np.array([(320, 700), (440, 505), (555, 345), (680, 255), (775, 185), (860, 125), (945, 85)], float); LD = np.array([70, 65, 55, 45, 40, 35, 30.0])
R = np.array([(1340, 705), (1280, 490), (1200, 335), (1135, 235), (1095, 160)], float); RD = np.array([80, 65, 55, 45, 40.0])
KEYS = ["SIG_O", "SIGS_O", "ALPHA_O", "BT_O", "BT1_O", "PINF_O", "RAMPP_O", "LEAN_O", "SEG_O", "FMAX", "TURN_O"]
X0 = [0.93, 0.35, 1.0, 0.0, 0.10, 0.6, 0.6, -0.15, 0.25, 0.85, 0.276]
SIGMA = 0.9568
def skel(env):
    e = dict(os.environ, W="1672", H="941", **{k: str(v) for k, v in env.items()})
    out = subprocess.run(["./fh5", "dump", "1"], env=e, capture_output=True, text=True).stdout.split("\n")
    lv0, ch = [], {}
    for ln in out:
        v = ln.split()
        if len(v) != 5: continue
        q = (float(v[2]), float(v[3]), float(v[4]))
        if v[0] == "0": lv0.append(q)
        else: ch.setdefault(v[1], []).append(q)
    return np.array(lv0), ch
def tips(ch, sig, pinf):
    res = []
    for pts in ch.values():
        P = np.array(pts)
        if len(P) < 4: continue
        k = np.arange(len(P)); T = P[1 - sig ** k > pinf, :2]
        if len(T) < 2: continue
        res.append((-1 if T[:, 0].mean() < P[0, 0] else 1, T.mean(0), np.ptp(T, 0).max()))
    return res
def cost(x, verbose=False):
    env = dict(zip(KEYS, x)); 
    try: P0, ch = skel(env)
    except Exception: return 1e4
    if len(P0) < 5: return 1e4
    Pd = np.concatenate([np.linspace(P0[i, :2], P0[i + 1, :2], 4, endpoint=False) for i in range(len(P0) - 1)])
    c = np.mean([np.min(np.linalg.norm(Pd - r, axis=1)) ** 2 for r in RACH])
    k = np.arange(len(P0)); T0 = P0[1 - env["SIG_O"] ** k > env["FMAX"], :2]
    if len(T0) >= 2: c += np.sum((T0.mean(0) - TOP) ** 2) + (0.5 * (np.ptp(T0, 0).max() - TOPD)) ** 2
    else: c += 300 ** 2
    tp = tips(ch, env["SIG_O"], env["PINF_O"])
    for side, ref, D in [(-1, L, LD), (1, R, RD)]:
        cand = [t for t in tp if t[0] == side]
        if not cand: return 1e4
        C = np.array([t[1] for t in cand])
        for t, dd in zip(ref, D):
            j = np.argmin(np.linalg.norm(C - t, axis=1))
            c += np.sum((C[j] - t) ** 2) + (0.5 * (cand[j][2] - dd)) ** 2
            if verbose: print(side, t, "->", C[j].round(), "diam", round(cand[j][2]), "ref", dd)
    return np.sqrt(c / 14)
x0 = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else X0
print("start", round(cost(x0), 1))
best = None
for trial in range(int(os.environ.get("STARTS", 4))):
    xs = np.array(x0) * (1 + (0 if trial == 0 else 0.15) * np.random.default_rng(trial).normal(size=len(x0)))
    r = minimize(cost, xs, method="Nelder-Mead", options=dict(maxiter=int(os.environ.get("IT", 500)), xatol=1e-3, fatol=0.1, adaptive=True))
    print("trial", trial, round(r.fun, 1), flush=True)
    if best is None or r.fun < best.fun: best = r
print("fit", round(best.fun, 1), dict(zip(KEYS, np.round(best.x, 4)))); cost(best.x, True)
json.dump(list(map(float, best.x)), open("open_fit.json", "w"))
