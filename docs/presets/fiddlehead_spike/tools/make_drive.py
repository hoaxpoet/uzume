# Per-frame (30 fps) drive for the Fiddlehead spike film from a mono f32 22.05 kHz decode:
#   u     = unfurl: section energy (RMS dB, ~3 s smoothing), clip-normalised p5..p95 → 0..1 (tight when quiet)
#   sway  = bass deviation (20–150 Hz energy vs its 4 s average), small
#   spark = sparkle density, spectral-flux onsets (decays over ~0.15 s)
import sys, numpy as np
x = np.fromfile(sys.argv[1], dtype=np.float32); sr = 22050; hop = sr // 30; n = 1024
frames = (len(x) - n) // hop
win = np.hanning(n); f = np.fft.rfftfreq(n, 1 / sr)
mags = np.array([np.abs(np.fft.rfft(x[i * hop:i * hop + n] * win)) for i in range(frames)])
db = 20 * np.log10(np.sqrt((mags ** 2).mean(1)) + 1e-6)
sec = np.convolve(db, np.ones(90) / 90, mode="same")
lo, hi = np.percentile(sec, 15), np.percentile(sec, 85)   # quietest ~15 % fully coiled, loudest ~15 % fully open
u = np.clip((sec - lo) / (hi - lo), 0, 1)
u = 0.5 - 0.5 * np.cos(np.pi * u)                                      # ease
bass = mags[:, (f > 20) & (f < 150)].mean(1); avg = np.convolve(bass, np.ones(120) / 120, mode="same")
sway = np.clip(bass / (avg + 1e-6) - 1, -1, 2) * 0.02
for i in range(1, frames): sway[i] = sway[i - 1] + (sway[i] - sway[i - 1]) * 0.15   # ~0.2 s: raw per-frame bass jittered
flux = np.maximum(np.diff(mags, axis=0, prepend=mags[:1]), 0).sum(1); flux /= np.percentile(flux, 95) + 1e-9
spark = np.zeros(frames); acc = 0
for i in range(frames): acc = max(acc * 0.8, flux[i] if flux[i] > 1.0 else 0); spark[i] = 0.001 + 0.006 * min(acc, 2)
np.savetxt(sys.argv[2], np.c_[u, sway, spark], fmt="%.5f", delimiter=",")
print(f"{frames} frames; u p5/p50/p95 = {np.percentile(u,5):.2f}/{np.percentile(u,50):.2f}/{np.percentile(u,95):.2f}")
