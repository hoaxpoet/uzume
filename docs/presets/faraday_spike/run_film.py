import numpy as np, os, sys, time; sys.path.insert(0,'.')
from faraday import Faraday
from audio_ratio import RATIOS, RATIO_NAMES

tag=sys.argv[1]; NF=int(sys.argv[2]); DT_OUT=float(sys.argv[3])
out="film_"+tag; os.makedirs(out,exist_ok=True)
a=np.load(tag+"_far.npz"); bassRel=a["bassRel"]; trebRel=a["trebRel"]; ratio=a["ratio"]; cen=a["cen"]
s=Faraday(N=256, nu=0.0012, k0=8.0, lam=0.22, rms_cap=1.35); s.h*=30.0
dt=0.008
cur=int(ratio[0]); pend=cur; pend_since=0; last_change=-999
log=open("film_%s.csv"%tag,"w"); log.write("frame,amp,ratio,ratio_name\n")
t0=time.time()
for fi in range(NF):
    k=min(fi,len(bassRel)-1)
    # symmetry channel: structural, with dwell so it reads as a change, not a strobe
    want=int(ratio[k])
    if want!=pend: pend=want; pend_since=fi
    if want!=cur and (fi-pend_since)>=36 and (fi-last_change)>=96:
        cur=want; last_change=fi
    # drive amplitude: below threshold -> flat film (D-037 silence state)
    # Cap the total forcing below 1: with mix=0.28 the two tones sum to
    # 1.33*amp, and once |F| > 1 the restoring force INVERTS, the field is
    # scrambled and the pattern reads as RGB noise (measured at frames 80/165).
    amp=0.26+0.34*float(np.clip(bassRel[k]-0.55,0,1.7))/1.7
    log.write("%d,%.3f,%d,%s\n"%(fi,amp,cur,RATIO_NAMES[cur].replace(",","")))
    nst=int(round(DT_OUT/dt))
    for _ in range(nst):
        if not s.step(dt, amp, ratio=RATIOS[cur], mix=0.28):
            print("RESEED at",fi,flush=True)
    hx,hy=s.envelope_slopes()
    np.save("%s/f_%04d.npy"%(out,fi), np.stack([s.envelope(),hx,hy]).astype(np.float32))
    if fi%60==0: print(fi,"/",NF,"amp %.2f %s hrms %.2f (%.0fs)"%(amp,RATIO_NAMES[cur],s.envelope().std(),time.time()-t0),flush=True)
log.close(); print("done",NF,flush=True)
