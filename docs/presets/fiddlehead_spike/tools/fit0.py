# Fit the level-0 rachis of the fern rule (2D, z=0 plane) to the traced reference centreline.
import numpy as np
from scipy.optimize import minimize
H, W = 941, 1672
T = np.array([(555,941),(575,860),(590,780),(600,700),(607,620),(612,540),(617,460),(625,380),(640,300),
              (668,220),(712,150),(775,100),(850,75),(930,68),(1010,80),(1085,115),(1145,170),(1185,240),(1203,320),
              (1200,400),(1180,470),(1140,530),(1080,575),(1010,595),(940,585),(880,550),(848,500),(829,458),
              (862,333),(937,296),(1050,354),(1067,425),(1008,510)], float)
def dense(P, n=8):
    return np.concatenate([np.linspace(P[i], P[i+1], n, endpoint=False) for i in range(len(P)-1)] + [P[-1:]])
Td = dense(T)
def sm(e0, e1, x): t = np.clip((x-e0)/(e1-e0), 0, 1); return t*t*(3-2*t)
def chain(p):
    seg, lean, front, ramp, maxT, sig, bt, bx = p
    pos = np.array([bx, 0.0]); a = lean; pts = [pos.copy()]   # a = angle from vertical, +right
    S = seg; k = 0
    while S > 0.6 and k < 300:
        f = 1 - sig**k; c = sm(front, front+ramp, f)
        pos = pos + S*np.array([np.sin(a), np.cos(a)]); pts.append(pos.copy())
        a += bt*(1-c) + maxT*c; S *= sig; k += 1
    P = np.array(pts); return np.stack([P[:,0], H - P[:,1]], 1)   # world px → image px (y down)
def cost(p):
    P = chain(p); Pd = dense(P, 4)
    d1 = np.min(np.linalg.norm(Td[:,None]-Pd[None], axis=2), 1)          # traced → model
    rmin = np.linalg.norm(T[-6:] - [970,400], axis=1).min()
    keep = np.linalg.norm(Pd - [970,400], axis=1) > rmin                  # model outside innermost trace
    d2 = np.min(np.linalg.norm(Pd[keep][:,None]-Td[None], axis=2), 1)
    return np.sqrt(np.mean(d1**2)) + np.sqrt(np.mean(d2**2))
best = None
for seg in [111]:
    for front in [0.1]:
        x0 = [seg, 0.03, front, 0.1, 0.31, 0.955, -0.01, 555]
        r = minimize(cost, x0, method="Nelder-Mead", options=dict(maxiter=6000, xatol=1e-4, fatol=1e-3))
        if best is None or r.fun < best.fun: best = r
p = best.x
print("cost px", round(best.fun, 1)); print("seg lean front ramp maxT sig bt bx =", np.round(p, 4))
sig, maxT = p[5], p[4]; print("growth/turn", sig**(-2*np.pi/maxT))
np.save("fit0.npy", p)
P = chain(p); Pd = dense(P, 4)
print("per-point traced→model px:", [int(v) for v in np.min(np.linalg.norm(T[:,None]-Pd[None], axis=2), 1)])
print("model pts:", [tuple(int(v) for v in q) for q in P[:40:2]])
