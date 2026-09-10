"""Faraday diagnostic pass — metrics defined BEFORE the runs.

Three questions, each answered by a number:

  Q1  Does a coarser k0 restore composition?
      metric: PEAK_K = peak of the radial power spectrum of the envelope field.
      Because the envelope of a standing wave cos(kx)cos(wt) is |cos(kx)|, the
      envelope's spatial frequency is 2*k0 -- so PEAK_K is literally the number
      of visible wavelengths across the frame. Target: 6-9.

  Q2  Does the pattern anneal into single-domain rolls, and do the symmetry
      switches reset it?
      metric: NEMATIC ORDER S in the dominant shell.
        S = |sum P(k) e^{2i theta_k}| / sum P(k),  |k| near PEAK_K
      Rolls are headless, hence 2*theta. S ~ 0 = polycrystalline/cellular (good).
      S -> 1 = one roll orientation has won (the failure). Rising S over time IS
      the annealing.

  Q3  If it anneals regardless, does a slow large-scale perturbation hold it open?
      metric: the same S, with and without the perturbation.

Never report mean wavenumber. It drifts as a launch transient decays and says
nothing about the pattern (see FARADAY_SPIKE_2026-09-09.md, CORRECTION).
"""
import sys
import numpy as np

sys.path.insert(0, ".")
from faraday import Faraday  # noqa: E402

_EDGES = np.arange(0.0, 96.0, 1.0)


def spectrum(A, K):
    P = np.abs(np.fft.rfft2(A)) ** 2
    P[0, 0] = 0.0
    return P


def peak_k(P, K):
    idx = np.digitize(K.ravel(), _EDGES) - 1
    rad = np.bincount(idx, weights=P.ravel(), minlength=len(_EDGES))[:70]
    return float(_EDGES[int(np.argmax(rad))])


def nematic_S(P, KX, KY, K, kp, halfwidth=3.0):
    m = (np.abs(K - kp) <= halfwidth) & (K > 0.5)
    if not m.any():
        return 0.0
    th = np.arctan2(KY[m], KX[m])
    w = P[m]
    tot = w.sum()
    if tot <= 0:
        return 0.0
    return float(np.abs((w * np.exp(2j * th)).sum()) / tot)


def run(label, k0, steps, ratio_seq=None, perturb=0.0, N=192, nu=0.0012,
        amp=0.34, mix=0.28, dt=0.008, every=400, seed=5):
    """ratio_seq: None = fixed (3,4); else a list of (p,q) swapped every `switch` steps."""
    s = Faraday(N=N, nu=nu, k0=k0, lam=0.22, rms_cap=1.35, seed=seed)
    s.h *= 30.0
    kx = np.fft.fftfreq(N) * N
    ky = np.fft.rfftfreq(N) * N
    KX, KY = np.meshgrid(kx, ky, indexing="ij")
    K = np.sqrt(KX ** 2 + KY ** 2)
    x = np.linspace(0, 2 * np.pi, N, endpoint=False)
    X, Y = np.meshgrid(x, x, indexing="ij")
    rows = []
    ratio = (3, 4)
    for n in range(steps):
        if ratio_seq:
            ratio = ratio_seq[(n // (steps // len(ratio_seq))) % len(ratio_seq)]
        if perturb > 0.0:
            # slow, large-scale, drifting perturbation of the LOCAL drive:
            # a spatial gradient in forcing keeps injecting orientational defects
            ph = 0.0007 * n
            g = perturb * np.sin(2 * X + 0.8 * np.sin(ph)) * np.sin(Y + 0.9 * np.cos(ph))
            s.h = s.h + np.fft.rfft2(g * 3e-3)
        s.step(dt, amp, ratio=ratio, mix=mix)
        if n % every == 0:
            A = s.envelope()
            P = spectrum(A, K)
            kp = peak_k(P, K)
            rows.append((n, kp, nematic_S(P, KX, KY, K, kp), float(A.std())))
    return s, rows


if __name__ == "__main__":
    what = sys.argv[1]
    if what == "q1":
        print("Q1  k0 sweep — PEAK_K is the visible wavelength count across the frame")
        print("  k0   peak_k   S_final   Astd")
        for k0 in (2.5, 3.0, 4.0, 6.0, 8.0):
            s, r = run("k%s" % k0, k0, 6000, every=5999)
            n, kp, S, a = r[-1]
            print("%5.1f   %5.1f    %.3f    %.3f" % (k0, kp, S, a), flush=True)
    elif what == "q2":
        k0 = float(sys.argv[2])
        print("Q2  annealing at k0=%.1f — S over time (S->1 = single-domain rolls)" % k0)
        for label, seq in (("fixed symmetry", None),
                           ("switching symmetry", [(3, 4), (4, 5), (2, 3), (5, 6)])):
            s, r = run(label, k0, 16000, ratio_seq=seq, every=2000)
            print(" %-20s" % label,
                  " ".join("n=%d k=%.0f S=%.2f" % (n, kp, S) for n, kp, S, a in r), flush=True)
    elif what == "q3":
        k0 = float(sys.argv[2])
        print("Q3  does a large-scale perturbation hold it polycrystalline? (k0=%.1f)" % k0)
        for label, pert in (("no perturbation", 0.0), ("perturbed", 1.0)):
            s, r = run(label, k0, 16000, ratio_seq=[(3, 4), (4, 5), (2, 3), (5, 6)],
                       perturb=pert, every=2000)
            print(" %-18s" % label,
                  " ".join("S=%.2f" % S for n, kp, S, a in r), flush=True)
