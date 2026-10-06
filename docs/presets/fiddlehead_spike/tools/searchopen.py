# Open-state pinnule search: two-sided match to Matt's open reference per region — edge density (thin vs full),
# dark-gap fraction (fused vs separate pinnae), curl profile, frame cost. Skeleton (fitted) held fixed.
import numpy as np, subprocess, os, re, json
from scipy import ndimage as nd
from metrics import load
from curls import whorls
R = dict(left=(200, 300, 700, 780), right=(1000, 300, 1450, 780), top=(800, 30, 1250, 300), centre=(650, 300, 1000, 941))
def meas(p):
    a = load(p); L = a.mean(2); E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0)) > 0.25
    ed = {k: float(E[y0:y1, x0:x1].mean()) for k, (x0, y0, x1, y1) in R.items()}
    dk = {k: float((L[y0:y1, x0:x1] < 0.08).mean()) for k, (x0, y0, x1, y1) in R.items()}
    return ed, dk, np.array([whorls(L[30:941, 200:1450], s) for s in [3, 6, 12, 24]], float)
RE, RK, RC = meas("ref_open.png")
BASE = dict(CURLON_O=1.1, RAMPP_O=0.15, HOOKR_O=0.3, TURN1_O=0.3, HAIRP_O=0.0, PINF_O=0.5)
SP = dict(LEAFLEN_O=(1.0, 2.0), LEAFW_O=(0.2, 0.45), PROF_O=(0.45, 1.5), PEXP1_O=(0.6, 1.6), SIGS1_O=(0.07, 0.14),
          ALPHA1_O=(0.8, 1.1), LEAFPX_O=(40, 140), IMM1_O=(0.5, 1.0))
def score(x):
    e = dict(os.environ, W="1672", H="941", **{k: str(v) for k, v in dict(BASE, **x).items()})
    r = subprocess.run(["./fh5", "still", "1", "so.png"], env=e, capture_output=True, text=True).stderr
    m = re.search(r"build ([\d.]+) ms, gpu ([\d.]+) ms", r); cost = float(m[1]) + float(m[2])
    ed, dk, c = meas("so.png")
    t = dict(dens=sum(abs(np.log(ed[k] / RE[k])) for k in R), gaps=sum(abs(dk[k] - RK[k]) * 4 for k in R),
             curl=float(np.abs(np.log((c + 5) / (RC + 5))) @ np.array([0.6, 1.0, 0.6, 0.3])), cost=max(0, cost - 16) * 0.1)
    return sum(t.values()), t, cost, ed, dk
if __name__ != "__main__": raise ImportError("library use: import meas only")
rng = np.random.default_rng(3); res = []
N, M = int(os.environ.get("N", 60)), int(os.environ.get("M", 70))
for i in range(N + M):
    if i < N: x = {k: round(float(rng.uniform(*v)), 3) for k, v in SP.items()}
    else:
        b = min(res, key=lambda t: t[0])[1]; sc = 0.15 if i < N + M // 2 else 0.07
        x = {k: round(float(np.clip(b[k] + rng.normal(0, sc) * (SP[k][1] - SP[k][0]), *SP[k])), 3) for k in SP}
    s, t, cost, ed, dk = score(x); res.append((s, x, {k: round(v, 3) for k, v in t.items()}, cost))
    print(i, round(s, 3), res[-1][2], round(cost, 1), flush=True)
res.sort(key=lambda t: t[0]); json.dump([dict(r[1], **BASE) for r in res[:5]], open("searchopen.json", "w"), indent=1)
print("REF dens", {k: round(v, 2) for k, v in RE.items()}, "dark", {k: round(v, 2) for k, v in RK.items()}, RC)
for r in res[:3]: print("BEST", round(r[0], 3), r[2], round(r[3], 1), json.dumps(r[1]))
