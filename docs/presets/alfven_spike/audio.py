"""Band envelopes + D-026-style deviation primitives from a real track.

Not the Uzume pipeline -- a stand-in that mimics its shape: AGC-normalised band
energies turned into deviation primitives (value relative to a running mean),
because absolute thresholds on AGC-normalised energy are FA #31.
"""
import sys
import wave
import numpy as np


def envelopes(path, fps=24.0, hop_ms=None):
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    n_hop = int(round(sr / fps))
    n_fft = 2048
    win = np.hanning(n_fft).astype(np.float32)
    nfr = (len(x) - n_fft) // n_hop
    freqs = np.fft.rfftfreq(n_fft, 1.0 / sr)
    bands = {"bass": (30, 160), "mid": (160, 2000), "treb": (2000, 8000)}
    masks = {k: (freqs >= lo) & (freqs < hi) for k, (lo, hi) in bands.items()}
    out = {k: np.zeros(nfr, np.float32) for k in bands}
    for i in range(nfr):
        seg = x[i * n_hop:i * n_hop + n_fft] * win
        mag = np.abs(np.fft.rfft(seg))
        for k, m in masks.items():
            out[k][i] = float(np.sqrt(np.mean(mag[m] ** 2)))
    return out, nfr, fps


def deviation(e, tau_frames=90):
    """value / running-mean - 1, clipped -- the shape of bassDev (D-026)."""
    a = np.exp(-1.0 / tau_frames)
    run = np.zeros_like(e)
    acc = float(np.mean(e[:tau_frames])) + 1e-9
    for i, v in enumerate(e):
        acc = a * acc + (1 - a) * v
        run[i] = acc
    rel = e / np.maximum(run, 1e-9)
    return np.clip(rel - 1.0, -1.0, 3.0), rel


if __name__ == "__main__":
    tag = sys.argv[1]
    env, nfr, fps = envelopes(tag + ".wav")
    np.savez(tag + "_env.npz",
             bassDev=deviation(env["bass"])[0], bassRel=deviation(env["bass"])[1],
             midDev=deviation(env["mid"])[0],
             trebDev=deviation(env["treb"])[0], trebRel=deviation(env["treb"])[1],
             fps=fps, nframes=nfr)
    bd = deviation(env["bass"])[0]
    print(tag, "frames", nfr, "fps", fps,
          "bassDev p5/p50/p95 %.2f/%.2f/%.2f" % tuple(np.percentile(bd, [5, 50, 95])))
