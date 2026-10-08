# Fit the OPEN-frond parameters (KEY_O) to Matt's open reference: stalk path + 12 pinna-tip croziers.
import numpy as np, subprocess, os, sys, json
from scipy.optimize import minimize
RACH = np.array([(800, 941), (820, 820), (840, 700), (880, 500), (920, 350), (960, 230), (1000, 150), (1050, 90)], float)
TOP, TOPD = np.array([1145, 80.0]), 70.0
L = np.array([(320, 700), (440, 505), (555, 345), (680, 255), (775, 185), (860, 125), (945, 85)], float); LD = np.array([70, 65, 55, 45, 40, 35, 30.0])
R = np.array([(1340, 705), (1280, 490), (1200, 335), (1135, 235), (1095, 160)], float); RD = np.array([80, 65, 55, 45, 40.0])
KEYS = ["SIG_O", "SIGS_O", "ALPHA_O", "BT_O", "BT1_O", "PINF_O", "TURN_O", "LEAN_O", "SEG_O", "FMAX", "TURN1_O"]
FIXED = dict(SIG1_O=0.97, SIGS1_O=0.12, ALPHA1_O=0.9, CURLON_O=1.1, KAPMIN_O=1.0, ABSANG_O=1.0, IMM1_O=0.8, RAMPP_O=0.15, HOOKR_O=0.3, HAIRP_O=0.0, LEAFLEN_O=2.0, LEAFW_O=0.25, PROF_O=1.0, LEAFPX_O=50, PEXP1_O=1.0, TAP0_O=0.7, PINCAP_O=0.3)
BOUND = dict(SIG_O=(0.78, 0.95), SIG1_O=(0.90, 0.975), SIGS_O=(0.2, 1.2), SIGS1_O=(0.1, 0.5), ALPHA_O=(0.5, 0.95), ALPHA1_O=(0.5, 1.3), BT_O=(-0.08, 0.08), BT1_O=(-0.05, 0.25),
             PINF_O=(0.4, 0.85), TURN_O=(0.15, 0.6), TURN1_O=(0.2, 0.45), LEAN_O=(-0.4, 0.4), SEG_O=(0.1, 3.0), FMAX=(0.85, 0.98))
X0 = [0.8635, 0.7418, 1.2141, 0.0, 0.078, 0.6896, 0.2983, 0.0, 0.6586, 0.86]
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
    x = [min(max(v, BOUND[k][0]), BOUND[k][1]) for k, v in zip(KEYS, x)]
    env = dict(zip(KEYS, x)); env.update(FIXED)

    try: P0, ch = skel(env)
    except Exception: return 1e4
    if len(P0) < 5: return 1e4
    Pd = np.concatenate([np.linspace(P0[i, :2], P0[i + 1, :2], 4, endpoint=False) for i in range(len(P0) - 1)])
    c = np.mean([np.min(np.linalg.norm(Pd - r, axis=1)) ** 2 for r in RACH])
    k = np.arange(len(P0)); T0 = P0[1 - env["SIG_O"] ** k > env["FMAX"], :2]
    if len(T0) >= 2: c += np.sum((T0.mean(0) - TOP) ** 2) + (0.5 * (np.ptp(T0, 0).max() - TOPD)) ** 2
    else: c += 300 ** 2
    tp = tips(ch, FIXED["SIG1_O"], env["PINF_O"])
    for side, ref, D in [(-1, L, LD), (1, R, RD)]:
        cand = [t for t in tp if t[0] == side]
        if not cand: return 1e4
        C = np.array([t[1] for t in cand]); used = set()
        vis = sum(1 for t in cand if 0 < t[1][0] < 1672 and 0 < t[1][1] < 941 and t[2] > 12)
        c += (max(0, vis - 9) ** 2 + max(0, 7 - vis) ** 2) * 4000          # ~7–9 pinnae a side in frame, not 15
        for t, dd in zip(ref, D):                                            # one model pinna per reference tip
            order = np.argsort(np.linalg.norm(C - t, axis=1)); j = next((q for q in order if q not in used), order[0]); used.add(j)
            c += np.sum((C[j] - t) ** 2) + (1.0 * (cand[j][2] - dd)) ** 2
            if verbose: print(side, t, "->", C[j].round(), "diam", round(cand[j][2]), "ref", dd)
        if verbose: print("side", side, "visible pinnae", vis)
    if not verbose and os.environ.get("DENS", "1") == "1":
        e = dict(os.environ, W="1672", H="941", **{k: str(v) for k, v in env.items()})
        subprocess.run(["./fh5", "still", "1", "fo.png"], env=e, capture_output=True)
        from metrics import load
        from scipy import ndimage as nd
        Lm = load("fo.png").mean(2)[30:941, 200:1450]; ed = (np.hypot(nd.sobel(Lm, 1), nd.sobel(Lm, 0)) > 0.25).mean()
        c += (max(0, 0.36 - ed) * 800) ** 2
    kopen = np.log(max(1 - env["PINF_O"], 1e-3)) / np.log(FIXED["SIG1_O"]); arch = env["BT1_O"] * kopen
    c += (max(0, arch - 0.6) * 400) ** 2                                # tips stay near the rising angle, then curl into the gap                                  # pinnae arch ~1.2 rad, they don't droop 110°
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
json.dump(dict({k: float(min(max(v, BOUND[k][0]), BOUND[k][1])) for k, v in zip(KEYS, best.x)}, **FIXED), open("open_fit10.json", "w"))
