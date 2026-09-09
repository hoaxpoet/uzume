"""Audio -> Faraday drive.

The headline coupling: the RATIO of the track's two strongest partials becomes the
ratio of the two parametric drive frequencies, which selects the pattern's SYMMETRY.
Two-frequency Faraday forcing is the classic route to squares, hexagons, superlattices
and quasipatterns (Edwards & Fauve 1994) -- so the music's harmonic content chooses
the geometry on screen, not merely its brightness.

Ratios are quantised to a small set of small-integer rationals (only commensurate
forcing produces a locked pattern) and held for ~2 s, because re-symmetrising the
whole field every frame would read as strobe, not as music.
"""
import sys
import wave

import numpy as np

# drive-frequency ratios == musical intervals in just intonation.
# The interval between the track's two strongest PITCH CLASSES picks one.
RATIOS = [(1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7)]
RATIO_NAMES = ["octave 1:2", "fifth 2:3", "fourth 3:4",
               "maj third 4:5", "min third 5:6", "septimal 6:7"]
# semitone interval -> index into RATIOS
SEMI_TO_RATIO = {2: 5, 3: 4, 4: 3, 5: 2, 6: 5, 7: 1, 8: 4, 9: 3, 10: 2}


def analyse(path, fps=24.0, hold_s=3.0):
    w = wave.open(path)
    sr = w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32) / 32768.0
    hop = int(round(sr / fps))
    nfft = 4096
    win = np.hanning(nfft).astype(np.float32)
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    n = (len(x) - nfft) // hop
    bass = np.zeros(n, np.float32); treb = np.zeros(n, np.float32)
    cen = np.zeros(n, np.float32); ridx = np.zeros(n, np.int32)
    lo = (freqs >= 60) & (freqs < 1800)
    fb = freqs[lo]
    PCLASS = np.round(12 * np.log2(np.maximum(fb, 1e-6) / 440.0)).astype(int) % 12
    for i in range(n):
        mag = np.abs(np.fft.rfft(x[i * hop:i * hop + nfft] * win))
        bass[i] = np.sqrt(np.mean(mag[(freqs >= 30) & (freqs < 160)] ** 2))
        treb[i] = np.sqrt(np.mean(mag[(freqs >= 2000) & (freqs < 8000)] ** 2))
        cen[i] = float((freqs * mag).sum() / max(mag.sum(), 1e-9))
        m = mag[lo]
        if m.max() <= 1e-9:
            ridx[i] = 1; continue
        # 12-bin chroma: fold the spectrum onto pitch classes
        pc = np.zeros(12)
        np.add.at(pc, PCLASS, m ** 2)
        a = int(np.argmax(pc))
        # adjacent pitch classes are binning leakage, not harmony -- exclude them
        pc2 = pc.copy()
        for o in (-1, 0, 1):
            pc2[(a + o) % 12] = 0
        b = int(np.argmax(pc2))
        semi = (b - a) % 12
        ridx[i] = SEMI_TO_RATIO.get(semi, 1)
    # hold the symmetry: majority vote over a rolling window
    hold = max(int(hold_s * fps), 1)
    held = np.zeros(n, np.int32)
    for i in range(n):
        seg = ridx[max(0, i - hold):i + 1]
        held[i] = np.bincount(seg, minlength=len(RATIOS)).argmax()
    return dict(bass=bass, treb=treb, cen=cen, ratio=held, n=n, fps=fps)


def dev(e, tau=90):
    a = np.exp(-1.0 / tau); acc = float(np.mean(e[:tau])) + 1e-9
    out = np.zeros_like(e)
    for i, v in enumerate(e):
        acc = a * acc + (1 - a) * v
        out[i] = v / max(acc, 1e-9)
    return out


if __name__ == "__main__":
    tag = sys.argv[1]
    d = analyse(tag + ".wav")
    np.savez(tag + "_far.npz", bassRel=dev(d["bass"]), trebRel=dev(d["treb"]),
             cen=d["cen"], ratio=d["ratio"], fps=d["fps"])
    cnt = np.bincount(d["ratio"], minlength=len(RATIOS))
    tot = cnt.sum()
    print(tag, "frames", d["n"], "| symmetry occupancy:",
          {RATIO_NAMES[i]: "%d%%" % round(100 * c / tot) for i, c in enumerate(cnt) if c},
          "| switches:", int((np.diff(d["ratio"]) != 0).sum()))
