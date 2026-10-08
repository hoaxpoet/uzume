# Joint search on the opaque model: colour layout + hue + lum, density floor, curl ladder, coil-core structure, cost.
import numpy as np, subprocess, os, re, json, sys
sys.path.insert(0, "."); from curls import profile; from density import dens, REG; from fitmat import cells, huehist, lumpct
from scipy import ndimage as nd
from metrics import load
ref = load("ref.png"); RC, RH, RL = cells(ref), huehist(ref), lumpct(ref)
RP = np.array(profile("ref.png"), float); RD = dens("ref.png")
def core(a):
    L = a.mean(2); c = L[350:450, 930:1030]; E = np.hypot(nd.sobel(L, 1), nd.sobel(L, 0))[350:450, 930:1030]
    return c.mean(), (E > 0.25).mean()
RCM, RCE = core(ref)
from metrics import hsv
BX = (380, 30, 1260, 941)
def satp(a):
    c = a[BX[1]:BX[3], BX[0]:BX[2]]; h, sa, v = hsv(c); m = v > 0.15
    return sa[m].mean(), np.percentile(c.mean(2), 99.5)
RS, RP99 = satp(ref)
from regionhue import area
RA = area(ref)
SP = dict(LCG=(0.35, 0.75), LCB=(0.1, 0.4), GLCELL=(40, 140), GLFRAC=(0.2, 0.9), CFRES=(0.0, 0.6), VARY=(0.0, 0.6), RIMCW=(0.0, 1.0), TEAL=(0.0, 0.4), SATB=(1.0, 2.2), LIME=(0.0, 1.0), HUEA=(0.2, 0.8), HUEB=(0.5, 1.0), CBEAD=(0.5, 6), CULLBEAD=(0.0, 1.0), OUTS=(0.5, 0.9), WALL=(0.3, 0.9),
          TRANS=(0.5, 2.5), RIMG=(0.6, 2.0), WARMK=(0.2, 1.0), TALB=(0.0, 0.8), LI=(0.8, 3.5), LR=(0.1, 0.25), BODY=(0.3, 1.5),
          IRID=(0.5, 2.5), BEAD=(3, 12), GA=(0.2, 0.9), CURLA=(0.4, 1.0), FILMB=(0.0, 0.8), RIMPX=(1.0, 3.0), GLINT=(0.3, 2.0),
          BLOOM1=(0.0, 0.2), BLOOM2=(0.0, 0.2), BLOOMW=(0.0, 1.0), EXPO=(0.8, 3.5), CORECAP=(0.3, 2.0), LINE=(0.3, 2.0))
def score(x, out):
    e = dict(os.environ, W="1672", H="941", **{k: str(v) for k, v in x.items()})
    r = subprocess.run(["./fh5_joint", "still", "0", out], env=e, capture_output=True, text=True).stderr
    m = re.search(r"build ([\d.]+) ms, gpu ([\d.]+) ms", r); cost = float(m[1]) + float(m[2])
    a = load(out); D = dens(out); c = np.array(profile(out), float); cm, ce = core(a)
    t = dict(cell=np.abs(cells(a) - RC).mean() * 4, hue=np.abs(huehist(a) - RH).sum(), lum=np.abs(lumpct(a) - RL).sum(),
             thin=sum(max(0, 1 - D[k][1] / RD[k][1]) * 4 for k in REG),
             curl=float(np.abs(np.log((c + 5) / (RP + 5))) @ np.array([0.3, 0.6, 1.0, 0.6, 0.3])),
             core=abs(cm - RCM) * 2 + max(0, RCE - ce) * 4, sat=abs(satp(a)[0] - RS) * 4 + abs(satp(a)[1] - RP99) * 2,
             place=sum(np.abs(A[0] - RA[k][0]).sum() + abs(A[1] - RA[k][1]) * 3 for k, A in area(a).items()), cost=max(0, cost - 16) * 0.15)
    return sum(t.values()), t, cost
rng = np.random.default_rng(int(os.environ.get("SEED", 5)))
X0 = json.load(open(sys.argv[1])) if len(sys.argv) > 1 else None
res = []
N, M = int(os.environ.get("N", 120)), int(os.environ.get("M", 140))
for i in range(N + M):
    if i < N and not (X0 and i == 0): x = {k: round(float(rng.uniform(*v)), 3) for k, v in SP.items()}
    elif X0 and i == 0: x = X0
    else:
        b = min(res, key=lambda t: t[0])[1]; sc = 0.15 if i < N + M // 2 else 0.07
        x = {k: round(float(np.clip(b[k] + rng.normal(0, sc) * (SP[k][1] - SP[k][0]), *SP[k])), 3) for k in SP}
    x["HUEB"] = max(x["HUEB"], x["HUEA"] + 0.05)
    s, t, cost = score(x, "sj.png"); res.append((s, x, {k: round(float(v), 3) for k, v in t.items()}, cost))
    print(i, round(s, 3), res[-1][2], round(cost, 1), flush=True)
res.sort(key=lambda t: t[0]); json.dump(res[:6], open("searchmat7.json", "w"), indent=1)
for b in res[:3]: print("BEST", round(b[0], 3), b[2], round(b[3], 1), json.dumps(b[1]))
