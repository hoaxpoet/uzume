"""Cheap spikes for three PDE candidates. Same discipline as the Alfven work:
no pitching prose, look at frames.

All three are single-field, local-stencil (or one FFT convolution) systems that
would run on the `persistent` staged surface ALFVEN.1 builds -- no Poisson solve,
no new engine work beyond what Alfven already needs.

  A) Complex Ginzburg-Landau, defect-turbulence regime
  B) Barkley excitable medium, spiral-breakup regime
  C) Kuramoto-Battogtokh nonlocally coupled phase oscillators (chimera)
"""
import os
import sys

import numpy as np

N = 256


def lap(f, dx):
    return (np.roll(f, 1, 0) + np.roll(f, -1, 0) + np.roll(f, 1, 1) + np.roll(f, -1, 1)
            - 4.0 * f) / (dx * dx)


# --- A) Complex Ginzburg-Landau -------------------------------------------
# dA/dt = A + (1 + i c1) lap A - (1 + i c2) |A|^2 A
# c1 c2 > 1 is Benjamin-Feir unstable -> defect turbulence: NEVER settles.
def cgle(steps, c1=2.0, c2=-1.0, dx=0.6, dt=0.005, every=None, out=None, seed=1):
    rng = np.random.default_rng(seed)
    A = 0.1 * (rng.standard_normal((N, N)) + 1j * rng.standard_normal((N, N)))
    k = 0
    for n in range(steps):
        A2 = np.abs(A) ** 2
        A = A + dt * (A + (1 + 1j * c1) * lap(A, dx) - (1 + 1j * c2) * A2 * A)
        if every and n % every == 0:
            np.save("%s/f_%04d.npy" % (out, k), np.stack([np.angle(A), np.abs(A)]).astype(np.float32))
            k += 1
    return A


# --- B) Barkley excitable medium ------------------------------------------
# du/dt = (1/eps) u (1-u) (u - (v+b)/a) + lap u ;  dv/dt = u - v
# Low `a` puts it in the spiral-BREAKUP regime -> sustained spatiotemporal chaos.
def barkley(steps, a=0.75, b=0.06, eps=0.02, dx=0.5, dt=0.004, every=None, out=None, seed=2):
    rng = np.random.default_rng(seed)
    u = np.zeros((N, N)); v = np.zeros((N, N))
    u[:, : N // 2] = 1.0                    # broken wavefront -> seeds spirals
    v[: N // 2, :] = 0.5
    u += 0.01 * rng.standard_normal((N, N))
    k = 0
    for n in range(steps):
        du = (1.0 / eps) * u * (1 - u) * (u - (v + b) / a) + lap(u, dx)
        dv = u - v
        u = np.clip(u + dt * du, -0.2, 1.2)
        v = v + dt * dv
        if every and n % every == 0:
            np.save("%s/f_%04d.npy" % (out, k), np.stack([u, v]).astype(np.float32))
            k += 1
    return u, v


# --- C) Kuramoto-Battogtokh nonlocal phase oscillators ---------------------
# dtheta/dt = omega - Int G(x-x') sin(theta(x) - theta(x') + alpha) dx'
# alpha just under pi/2 with an exponential kernel -> CHIMERA: a coherent
# domain and an incoherent domain coexisting in the same field.
def kuramoto(steps, alpha=1.457, kappa=4.0, dt=0.02, every=None, out=None, seed=3):
    rng = np.random.default_rng(seed)
    x = np.linspace(-0.5, 0.5, N, endpoint=False)
    X, Y = np.meshgrid(x, x, indexing="ij")
    R = np.sqrt(np.minimum(np.abs(X), 1 - np.abs(X)) ** 2 + np.minimum(np.abs(Y), 1 - np.abs(Y)) ** 2)
    G = np.exp(-kappa * R); G /= G.sum()
    Gh = np.fft.fft2(np.fft.ifftshift(G))
    th = 2 * np.pi * rng.random((N, N))
    th += 3.0 * np.exp(-((X * 6) ** 2 + (Y * 6) ** 2))     # a coherent seed patch
    k = 0
    for n in range(steps):
        z = np.exp(1j * th)
        conv = np.fft.ifft2(np.fft.fft2(z) * Gh)
        th = th + dt * (-np.imag(conv * np.exp(-1j * (th + alpha))))
        if every and n % every == 0:
            zc = np.fft.ifft2(np.fft.fft2(np.exp(1j * th)) * Gh)
            np.save("%s/f_%04d.npy" % (out, k), np.stack([th % (2 * np.pi), np.abs(zc)]).astype(np.float32))
            k += 1
    return th


if __name__ == "__main__":
    which = sys.argv[1]
    steps, every = int(sys.argv[2]), int(sys.argv[3])
    out = "out_" + which
    os.makedirs(out, exist_ok=True)
    {"cgle": cgle, "barkley": barkley, "kuramoto": kuramoto}[which](
        steps, every=every, out=out)
    print("done", which, len(os.listdir(out)), "frames", flush=True)
