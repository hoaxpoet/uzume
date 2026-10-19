"""v3 drivers: what changes, not what repeats.
  beat  : big burst on each downbeat, small echo on beat 3, nothing on 2 and 4
  hue   : the glow's colour steps on every downbeat (eased over 0.25 s)
  glowBase, travel: brightness floor and flight speed follow the song's energy (spectral flux, 0.6 s smoothing)
  spin  : sphere spin rate follows the bass
  roll  : quarter-turn bank on every second downbeat (eased over 1 s), alternating direction
"""
import csv, json, math, sys
import numpy as np
src, out, fps, t_end = sys.argv[1], sys.argv[2], 30.0, float(sys.argv[3])
rows = list(csv.DictReader(open(src)))
T = [float(r["time"]) for r in rows]
flux_all = np.array([float(r["spectralFlux"]) for r in rows]); lo, hi = np.percentile(flux_all, 5), np.percentile(flux_all, 95)
def at(t):
    lo_, hi_ = 0, len(T) - 1
    while lo_ < hi_:
        m = (lo_ + hi_ + 1) // 2
        if T[m] <= t: lo_ = m
        else: hi_ = m - 1
    return rows[lo_]
beats, prev = [], None
for r in rows:
    ph, t = float(r["beatPhase01"]), float(r["time"]); bpm = float(r["grid_bpm"]) or 120.0
    if prev is not None and ph < prev - 0.5: beats.append((t - ph * 60.0 / bpm, int(r["beat_in_bar"])))
    prev = ph
downs = [bt for bt, k in beats if k == 1]
def ease(x): x = min(max(x, 0), 1); return x * x * (3 - 2 * x)
dt = 1.0 / fps; travel = spin = bass = 0.0; energy = 0.5; frames = []
for i in range(int(t_end * fps)):
    t = i * dt; r = at(t)
    past = [b for b in beats if b[0] <= t]
    beat = 0.0
    for (bt, bib) in past[-4:]:
        if bib == 1: beat = max(beat, math.exp(-(t - bt) / 0.35))
        elif bib == 3: beat = max(beat, 0.35 * math.exp(-(t - bt) / 0.20))
    hue = sum(0.7 * ease((t - bt) / 0.25) for bt in downs if bt <= t)
    e = min(max((float(r["spectralFlux"]) - lo) / (hi - lo + 1e-9), 0), 1)
    energy += (e - energy) * (1 - math.exp(-dt / 0.6))
    travel += (0.65 + 0.8 * energy) * dt
    b = min(max(0.0, float(r["bassDev"])) / 0.35, 1.2)
    bass += (b - bass) * (1 - math.exp(-dt / (0.03 if b > bass else 0.30)))
    spin += (1.0 + 3.0 * bass) * dt
    roll = sum((math.pi / 2) * ease((t - bt) / 1.0) * (1 if k % 2 == 0 else -1) for k, bt in enumerate(downs[::2]) if bt <= t)
    frames.append(dict(t=t, itime=t, beat=beat, hue=hue, glowBase=0.45 + 0.5 * energy, travel=travel, spin=spin, roll=roll))
json.dump(dict(fps=fps, beats=beats, frames=frames), open(out, "w"))
print(len(frames), "frames; downbeats", [round(d, 2) for d in downs[:5]])
