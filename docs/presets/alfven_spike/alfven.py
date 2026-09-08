"""Alfven look-film: driven 2D incompressible MHD, coupled to a real track.

Physics: 2D incompressible MHD in vorticity / flux-function (reduced-MHD) form,
pseudo-spectral with 2/3 dealiasing, integrating-factor RK2, hyperdiffusion.
Real-FFT throughout (fields are real) -- ~2x the complex version, scipy.fft with
worker threads on top.

  omega = lap(phi),  u = (-phi_y, phi_x)     psi = flux fn,  B = (-psi_y, psi_x),  J = lap(psi)
  d_t omega = -{phi,omega} + {psi,J} - nu4 k^4 omega - alpha omega + f(bassDev)
  d_t psi   = -{phi,psi}              - eta4 k^4 psi

Audio coupling in this file is PHYSICS ONLY (one primitive):
  bassDev -> forcing amplitude  (stirring vigour -> seam density)
Render-side couplings (treble -> seam luminance, centroid -> hue) live in film.py,
so the two layers never share a primitive (FA #67).
"""
import os
import sys
import time

import numpy as np
from scipy import fft as sfft

WORKERS = 2


class Alfven:
    def __init__(self, N=256, nu4=2.5e-7, alpha=0.16, seed=3, kf=(2.0, 5.0)):
        self.N = N
        kx = np.fft.fftfreq(N) * N
        ky = np.fft.rfftfreq(N) * N
        self.KX, self.KY = np.meshgrid(kx, ky, indexing="ij")
        self.K2 = self.KX ** 2 + self.KY ** 2
        self.K4 = self.K2 ** 2
        self.K2inv = 1.0 / np.where(self.K2 == 0, 1.0, self.K2)
        self.K2inv[0, 0] = 0.0
        kmax = N / 2
        self.DA = (np.abs(self.KX) < 2 / 3 * kmax) & (np.abs(self.KY) < 2 / 3 * kmax)
        # Hou-Li smooth spectral filter -- the standard pseudo-spectral stabiliser;
        # kills the grid-scale energy pile-up that made the earlier spikes blow up.
        kr = np.sqrt(self.K2) / kmax
        self.FILT = np.exp(-36.0 * np.clip(kr, 0, 1) ** 36)
        self.nu4, self.alpha = nu4, alpha
        kk = np.sqrt(self.K2)
        self.SHELL = (kk >= kf[0]) & (kk <= kf[1])
        self.fnorm = N * N / np.sqrt(max(self.SHELL.sum(), 1))
        self.rng = np.random.default_rng(seed)
        self.fph = self.rng.uniform(0, 2 * np.pi, self.KX.shape)
        self.w = self._rand(1.2, 3)
        self.p = self._rand(0.9, 2)
        self.reseeds = 0
        # 2D MHD inverse-cascades <psi^2> to box scale and CONDENSATES there --
        # a static magnetic quilt with frozen flow. That is physics, not a bug
        # (Biskamp ch. 7), and it is why a steady driven state cannot be the look.
        # So the preset is a SEQUENCE OF TRANSIENTS: seed a fresh braid, let the
        # fold-to-filament arc run, dissolve into the next before the condensate forms.
        self.blend = None
        self.blend_t = 0.0

    # ---- helpers -----------------------------------------------------------
    def _f(self, a):
        return sfft.rfft2(a, workers=WORKERS)

    def _i(self, a):
        return sfft.irfft2(a, s=(self.N, self.N), workers=WORKERS)

    def _rand(self, amp, kmaxi):
        kk = np.sqrt(self.K2)
        h = np.zeros(self.KX.shape, complex)
        m = (kk >= 1) & (kk <= kmaxi)
        ph = self.rng.uniform(0, 2 * np.pi, self.KX.shape)
        h[m] = np.exp(1j * ph[m]) / (kk[m] ** 1.6)
        f = self._i(h)
        return self._f(f * (amp / (np.std(f) + 1e-9)))

    def _bracket(self, a_h, b_h):
        ax = self._i(1j * self.KX * a_h); ay = self._i(1j * self.KY * a_h)
        bx = self._i(1j * self.KX * b_h); by = self._i(1j * self.KY * b_h)
        return self._f(ax * by - ay * bx) * self.DA

    def _nl(self, w_h, p_h, f_h):
        phi = -w_h * self.K2inv
        J = -self.K2 * p_h
        return -self._bracket(phi, w_h) + self._bracket(p_h, J) + f_h, -self._bracket(phi, p_h)

    def cfl_speed(self):
        phi = -self.w * self.K2inv
        ux = self._i(-1j * self.KY * phi); uy = self._i(1j * self.KX * phi)
        bx = self._i(-1j * self.KY * self.p); by = self._i(1j * self.KX * self.p)
        return float(max(np.max(np.hypot(ux, uy)), np.max(np.hypot(bx, by))))

    # ---- integration -------------------------------------------------------
    def step(self, dt, drive):
        self.fph += self.rng.normal(0, 2.2, self.KX.shape) * np.sqrt(dt)
        f_h = np.where(self.SHELL, np.exp(1j * self.fph), 0) * (drive * self.fnorm)
        Ew = np.exp(-(self.nu4 * self.K4 + self.alpha) * dt)
        Ep = np.exp(-self.nu4 * self.K4 * dt)
        k1w, k1p = self._nl(self.w, self.p, f_h)
        w1 = (self.w + dt * k1w) * Ew
        p1 = (self.p + dt * k1p) * Ep
        k2w, k2p = self._nl(w1, p1, f_h * Ew)
        self.w = (self.w + 0.5 * dt * k1w) * Ew + 0.5 * dt * k2w
        self.p = (self.p + 0.5 * dt * k1p) * Ep + 0.5 * dt * k2p
        self.w *= self.FILT
        self.p *= self.FILT
        # watchdog: a NaN or a runaway on stage is a P0 black frame
        if not np.isfinite(self.w).all() or not np.isfinite(self.p).all():
            self.w = self._rand(1.2, 3); self.p = self._rand(0.9, 2); self.reseeds += 1

    def begin_reseed(self):
        self.blend = (self._rand(1.3, 3), self._rand(1.0, 2))
        self.blend_t = 0.0
        self.reseeds += 1

    def advance_blend(self, dt, tau=1.1):
        if self.blend is None:
            return
        self.blend_t += dt
        a = min(self.blend_t / tau, 1.0)
        # raised cosine so the dissolve has no visible in/out corner
        g = 0.5 - 0.5 * np.cos(np.pi * a)
        r = g * (dt / max(tau, 1e-6)) * np.pi  # per-step share of the crossfade
        self.w = (1 - r) * self.w + r * self.blend[0]
        self.p = (1 - r) * self.p + r * self.blend[1]
        if a >= 1.0:
            self.blend = None

    def fields(self):
        return self._i(self.w), self._i(-self.K2 * self.p)


if __name__ == "__main__":
    RESEED_FRAMES = int(os.environ.get("ALF_RESEED", 190))
    tag = sys.argv[1]                    # audio tag, e.g. so_what
    nframes = int(sys.argv[2])
    dt_out = float(sys.argv[3])
    out = "film_%s_%s" % (tag, os.environ.get("ALF_TAG", "v2"))
    os.makedirs(out, exist_ok=True)
    env = np.load(tag + "_env.npz")
    bassDev = env["bassDev"]
    s = Alfven(N=int(os.environ.get("ALF_N", 256)))
    dx = 2 * np.pi / s.N
    t = 0.0; nxt = 0.0; fi = 0; c = 1.0; nstep = 0; t0 = time.time()
    while fi < nframes:
        # one primitive, one layer: bassDev -> stirring vigour
        bd = float(bassDev[min(fi, len(bassDev) - 1)])
        drive = 0.020 * (0.60 + 0.80 * np.clip(bd + 0.55, 0.0, 2.2))
        if nstep % 8 == 0:
            c = s.cfl_speed()
        nstep += 1
        dt = min(0.005, 0.25 * dx / max(c, 1e-3))
        s.step(dt, drive); s.advance_blend(dt); t += dt
        if t >= nxt:
            W, J = s.fields()
            np.save("%s/J_%04d.npy" % (out, fi), J.astype(np.float32))
            np.save("%s/W_%04d.npy" % (out, fi), W.astype(np.float32))
            fi += 1; nxt += dt_out
            if fi % RESEED_FRAMES == 0:
                s.begin_reseed()
            if fi % 60 == 0:
                print(fi, "/", nframes, "t=%.1f drive=%.4f Jrms=%.2f (%.0fs, reseeds=%d)"
                      % (t, drive, J.std(), time.time() - t0, s.reseeds), flush=True)
    print("done", fi, "reseeds", s.reseeds, flush=True)
