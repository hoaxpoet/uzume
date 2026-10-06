# Music drive for the FH.15 descent fern, from a mono f32 22.05 kHz decode. Follows the audio hierarchy:
# continuous energy is the primary driver; beat-locked pulses ride a steady GRID (tempo + phase fitted to the whole
# clip, like the cached BeatGrid), never raw onsets.
#   <out>.csv   per 30 fps frame: bass, treble, energy — bass/treble are DEVIATIONS from their own ~4 s average,
#               squashed x/(x+k) into 0..1; energy is loudness (~1 s), percentile-normalised 0..1
#   <out>.beats one line per grid beat: time (s), accent 0..1 (flux at the beat, downbeats boosted)
#   usage: python fern_drive.py in.f32 out
import sys, numpy as np
x = np.fromfile(sys.argv[1], dtype=np.float32); sr = 22050; fps = 30; hop = sr // fps; n = 2048
frames = (len(x) - n) // hop
win = np.hanning(n); f = np.fft.rfftfreq(n, 1 / sr)
mags = np.array([np.abs(np.fft.rfft(x[i * hop:i * hop + n] * win)) for i in range(frames)])

def ema(v, k):
    o = v.copy()
    for i in range(1, len(v)): o[i] = o[i - 1] + (v[i] - o[i - 1]) * k
    return o
def dev(band):                                   # deviation from its own ~4 s running mean, squashed (never absolute)
    avg = np.convolve(band, np.ones(120) / 120, mode="same")
    d = np.maximum(band / (avg + 1e-9) - 1, 0)
    return d / (d + 0.6)

bass = ema(mags[:, (f > 30) & (f < 160)].mean(1), 0.5)
treb = ema(mags[:, (f > 4000) & (f < 10000)].mean(1), 0.5)
db = 20 * np.log10(np.sqrt((mags ** 2).mean(1)) + 1e-6); e1 = ema(db, 1 / 30)
energy = np.clip((e1 - np.percentile(e1, 5)) / (np.percentile(e1, 95) - np.percentile(e1, 5) + 1e-6), 0, 1)

# beat grid: onset flux → tempo by autocorrelation (90–180 BPM), phase by best alignment, accent per beat
flux = np.maximum(np.diff(np.log1p(mags), axis=0, prepend=np.log1p(mags[:1])), 0).sum(1)
flux = flux - np.convolve(flux, np.ones(15) / 15, mode="same"); flux = np.maximum(flux, 0)
ac = np.correlate(flux, flux, mode="full")[len(flux) - 1:]
lags = np.arange(len(ac)); bpm = 60 * fps / np.maximum(lags, 1)
ok = (bpm >= 90) & (bpm <= 180)
lag = lags[ok][np.argmax(ac[ok])]
# refine the period to sub-frame precision by scanning around the integer lag
best = (-1, 0, 0)
for period in np.linspace(lag - 0.6, lag + 0.6, 61):
    for ph in np.linspace(0, period, 40, endpoint=False):
        idx = np.round(np.arange(ph, frames, period)).astype(int); idx = idx[idx < frames]
        sc = flux[idx].mean()
        if sc > best[0]: best = (sc, period, ph)
_, period, ph = best
beats = np.arange(ph, frames, period)
acc = np.array([flux[max(int(round(b)) - 1, 0):int(round(b)) + 2].max() for b in beats])
acc = acc / (np.percentile(acc, 95) + 1e-9)
bar = max(range(4), key=lambda o: acc[o::4].sum())               # downbeats: the strongest of the four bar phases
acc[bar::4] *= 1.4
acc = np.clip(acc, 0.15, 1.0)
np.savetxt(sys.argv[2] + ".csv", np.c_[dev(bass), dev(treb), energy], fmt="%.5f", delimiter=",")
np.savetxt(sys.argv[2] + ".beats", np.c_[beats / fps + n / 2 / sr, acc], fmt="%.5f", delimiter=",")   # + window centre: frame i's FFT is centred n/2 samples later
assert dev(bass).max() <= 1 and dev(treb).max() <= 1   # deviations, squashed (raw magnitudes once leaked through: 60× light)
print(f"{frames} frames  tempo {60 * fps / period:.1f} BPM  beats {len(beats)}  energy p50 {np.median(energy):.2f}")
