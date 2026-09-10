import numpy as np
from irid import lookup

def norm01(a, lo=1.0, hi=99.0):
    p,q=np.percentile(a,lo),np.percentile(a,hi); return np.clip((a-p)/max(q-p,1e-9),0,1)
def _lap(f):
    return np.roll(f,1,0)+np.roll(f,-1,0)+np.roll(f,1,1)+np.roll(f,-1,1)-4*f

def render(h,hx,hy, base=340.0, swing=520.0, spec=0.55, caus_gain=1.0, bloom=0.0):
    h = h/(np.std(h)+1e-9)
    gs = 1.0/(2.2*np.std(np.hypot(hx,hy))+1e-9)   # slopes normalised on their OWN scale
    hx, hy = hx*gs, hy*gs
    nz=1.0/np.sqrt(1+hx*hx+hy*hy); nx,ny=-hx*nz,-hy*nz
    d = base + swing*np.clip(h/2.2, -1, 1)          # film thickness, nm (linear in the coloured band)
    opd = 2.0*1.34*d*nz                             # view-angle dependent
    rgb = lookup(opd)
    caus=np.clip(1.0/(1.0+0.30*_lap(h)),0,5)**1.3
    caus=0.55+0.70*norm01(caus,2,99.0)
    rgb = rgb*(caus_gain*caus)[...,None]
    L=np.array([0.40,0.34,0.85]); L/=np.linalg.norm(L)
    Hv=L+np.array([0,0,1.0]); Hv/=np.linalg.norm(Hv)
    nd=np.clip(nx*Hv[0]+ny*Hv[1]+nz*Hv[2],0,1)
    rgb=rgb+spec*(nd**300.0)[...,None]*np.array([1.0,0.98,0.92])
    return np.clip(rgb,0,1)
