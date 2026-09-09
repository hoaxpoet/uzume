import numpy as np, os, sys, time; sys.path.insert(0,'.')
from faraday import Faraday
from audio_ratio import RATIOS, RATIO_NAMES
from diag import spectrum, peak_k, nematic_S

tag=sys.argv[1]; NF=int(sys.argv[2]); DT_OUT=float(sys.argv[3])
out="v2_"+tag; os.makedirs(out,exist_ok=True)
a=np.load(tag+"_far.npz"); bassRel=a["bassRel"]; ratio=a["ratio"]
N=256
s=Faraday(N=N, nu=0.0012, k0=3.0, lam=0.22, rms_cap=1.35, seed=5); s.h*=30.
kx=np.fft.fftfreq(N)*N; ky=np.fft.rfftfreq(N)*N
KX,KY=np.meshgrid(kx,ky,indexing="ij"); K=np.sqrt(KX**2+KY**2)
dt=0.008
# pre-warm so frame 0 is already a formed pattern, not a launch transient
for _ in range(9000): s.step(dt, 0.42, ratio=(3,4), mix=0.28)
print("prewarm done Astd %.3f"%s.envelope().std(), flush=True)

cur=int(ratio[0]); pend=cur; pend_since=0; last_change=-999
last_seed=-999; S_TRIGGER=0.26; SEED_GAP=42
log=open("v2_%s.csv"%tag,"w"); log.write("frame,amp,ratio_name,peak_k,S\n")
t0=time.time()
for fi in range(NF):
    k=min(fi,len(bassRel)-1)
    want=int(ratio[k])
    if want!=pend: pend=want; pend_since=fi
    if want!=cur and (fi-pend_since)>=36 and (fi-last_change)>=96:
        cur=want; last_change=fi
    amp=0.32+0.30*float(np.clip(bassRel[k]-0.55,0,1.7))/1.7
    for _ in range(int(round(DT_OUT/dt))):
        if not s.step(dt, amp, ratio=RATIOS[cur], mix=0.28): print("WATCHDOG",fi,flush=True)
        s.advance_blend(dt)
    A=s.envelope(); hx,hy=s.envelope_slopes()
    P=spectrum(A,K); kp=peak_k(P,K); S=nematic_S(P,KX,KY,K,kp)
    # closed-loop re-seed: the order parameter decides, not a clock
    if S > S_TRIGGER and (fi - last_seed) >= SEED_GAP:
        s.begin_reseed(amp=A.std()); last_seed = fi
        print("RESEED at f%d (S=%.2f)"%(fi,S), flush=True)
    np.save("%s/f_%04d.npy"%(out,fi), np.stack([A,hx,hy]).astype(np.float32))
    log.write("%d,%.3f,%s,%.0f,%.3f\n"%(fi,amp,RATIO_NAMES[cur].replace(",",""),kp,S)); log.flush()
    if fi%60==0: print(fi,"/",NF,"amp %.2f %s peak_k %.0f S %.2f Astd %.2f (%.0fs)"%(amp,RATIO_NAMES[cur],kp,S,A.std(),time.time()-t0),flush=True)
print("done",NF,flush=True)
