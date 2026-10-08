# Per-frame (30 fps) drive for the Fiddlehead spike film, from a mono f32 22.05 kHz decode. Columns:
#   u      unfurl = the music's INTENSITY, slow (~6 s), clip-normalised into 0.15…0.9 — a background state, not the main action
#   sway   bass push on the whole frond (bass vs its 4 s average, ~0.2 s smoothing)
#   spark  sparkle density (onset envelope)
#   onset  1 on a beat (spectral-flux peaks, ≥ 0.3 s apart) — launches a light pulse up the frond
#   energy 0…1 loudness (~1 s) — how hard the sway wave bends
import sys, numpy as np
x = np.fromfile(sys.argv[1], dtype=np.float32); sr = 22050; hop = sr // 30; n = 1024
frames = (len(x) - n) // hop
win = np.hanning(n); f = np.fft.rfftfreq(n, 1 / sr)
mags = np.array([np.abs(np.fft.rfft(x[i * hop:i * hop + n] * win)) for i in range(frames)])
db = 20 * np.log10(np.sqrt((mags ** 2).mean(1)) + 1e-6)
def ema(v, k):
    o = v.copy()
    for i in range(1, len(v)): o[i] = o[i - 1] + (v[i] - o[i - 1]) * k
    return o
e1 = ema(db, 1 / 30); en = np.clip((e1 - np.percentile(e1, 10)) / (np.percentile(e1, 90) - np.percentile(e1, 10)), 0, 1)
slow = ema(db, 1 / 180); u = 0.0 + 0.9 * np.clip((slow - np.percentile(slow, 10)) / (np.percentile(slow, 90) - np.percentile(slow, 10) + 1e-6), 0, 1)
bass = mags[:, (f > 20) & (f < 150)].mean(1); avg = np.convolve(bass, np.ones(120) / 120, mode="same")
sway = ema(np.clip(bass / (avg + 1e-6) - 1, -1, 2) * 0.06, 0.15)
flux = np.maximum(np.diff(mags, axis=0, prepend=mags[:1]), 0).sum(1); flux /= np.percentile(flux, 95) + 1e-9
onset = np.zeros(frames); last = -99
for i in range(1, frames - 1):
    if flux[i] > 1.0 and flux[i] >= flux[i - 1] and flux[i] >= flux[i + 1] and i - last >= 9: onset[i] = 1; last = i
spark = np.zeros(frames); acc = 0
for i in range(frames): acc = max(acc * 0.8, flux[i] if flux[i] > 1.0 else 0); spark[i] = 0.001 + 0.006 * min(acc, 2)
np.savetxt(sys.argv[2], np.c_[u, sway, spark, onset, en], fmt="%.5f", delimiter=",")
print(f"{frames} frames; u range {u.min():.2f}..{u.max():.2f}; onsets {int(onset.sum())} ({onset.sum() / (frames / 30):.1f}/s)")
