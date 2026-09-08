"""Driven 2D incompressible MHD in vorticity / flux-function (reduced-MHD) form.

Pseudo-spectral, 2/3 dealiasing, integrating-factor RK2, hyperdiffusion.
Physics: standard 2D incompressible MHD (Biskamp, *Magnetohydrodynamic
Turbulence*, ch. 7). Initial condition is the Orszag-Tang braid
(Orszag & Tang 1979) -- the canonical 2D MHD test problem.

    omega = lap(phi),  u = (-phi_y,  phi_x)
    psi   flux fn,     B = (-psi_y,  psi_x),   J = lap(psi)

    d_t omega = -{phi,omega} + {psi,J} - nu4 k^4 omega + f
    d_t psi   = -{phi,psi}              - eta4 k^4 psi

Look-spike only: this is the CPU stand-in for what would become a GPU
ping-pong sim. No Uzume code, no audio pipeline.
"""

import numpy as np


class RMHD:
    def __init__(self, N=256, nu4=3e-9, eta4=3e-9, seed=11, kf=(3.0, 6.0), nmodes=6):
        self.N = N
        k = np.fft.fftfreq(N) * N  # integer wavenumbers for a 2*pi-periodic box
        self.KX, self.KY = np.meshgrid(k, k, indexing="ij")
        self.K2 = self.KX ** 2 + self.KY ** 2
        self.K4 = self.K2 ** 2
        self.K2inv = 1.0 / np.where(self.K2 == 0, 1.0, self.K2)
        self.K2inv[0, 0] = 0.0
        kmax = np.max(np.abs(k))
        self.dealias = (np.abs(self.KX) < 2 / 3 * kmax) & (np.abs(self.KY) < 2 / 3 * kmax)
        self.nu4, self.eta4 = nu4, eta4
        self.alpha = 0.08  # large-scale drag -> statistical steady state

        rng = np.random.default_rng(seed)
        self.rng = rng
        x = np.linspace(0, 2 * np.pi, N, endpoint=False)
        self.X, self.Y = np.meshgrid(x, x, indexing="ij")

        # Orszag-Tang initial condition
        self.w = np.fft.fft2(-2.0 * np.sin(self.X) * np.cos(self.Y))
        self.p = np.fft.fft2(0.6 * (np.cos(2 * self.X) / 2.0 + np.cos(self.Y)))

        # forcing: a few large-scale physical-space modes with drifting phase
        ang = rng.uniform(0, 2 * np.pi, nmodes)
        mag = rng.uniform(kf[0], kf[1], nmodes)
        self.fk = np.stack([np.round(mag * np.cos(ang)), np.round(mag * np.sin(ang))], 1)
        self.fphase = rng.uniform(0, 2 * np.pi, nmodes)
        self.fdrift = rng.uniform(-0.7, 0.7, nmodes)

    def _bracket(self, a_h, b_h):
        ax = np.real(np.fft.ifft2(1j * self.KX * a_h))
        ay = np.real(np.fft.ifft2(1j * self.KY * a_h))
        bx = np.real(np.fft.ifft2(1j * self.KX * b_h))
        by = np.real(np.fft.ifft2(1j * self.KY * b_h))
        return np.fft.fft2(ax * by - ay * bx) * self.dealias

    def _nl(self, w_h, p_h, f_h):
        phi_h = -w_h * self.K2inv
        J_h = -self.K2 * p_h
        dw = -self._bracket(phi_h, w_h) + self._bracket(p_h, J_h) + f_h
        dp = -self._bracket(phi_h, p_h)
        return dw, dp

    def _forcing(self, dt, drive):
        if drive <= 0.0:
            return np.zeros_like(self.w)
        self.fphase = self.fphase + self.fdrift * dt
        f = np.zeros_like(self.X)
        for m in range(len(self.fphase)):
            f += np.sin(self.fk[m, 0] * self.X + self.fk[m, 1] * self.Y + self.fphase[m])
        return np.fft.fft2(f * (drive / len(self.fphase))) * self.dealias

    def step(self, dt, drive=0.0):
        f_h = self._forcing(dt, drive)
        Ew = np.exp(-(self.nu4 * self.K4 + self.alpha) * dt)
        Ep = np.exp(-self.eta4 * self.K4 * dt)
        k1w, k1p = self._nl(self.w, self.p, f_h)
        w1 = (self.w + dt * k1w) * Ew
        p1 = (self.p + dt * k1p) * Ep
        k2w, k2p = self._nl(w1, p1, f_h * Ew)
        self.w = (self.w + 0.5 * dt * k1w) * Ew + 0.5 * dt * k2w
        self.p = (self.p + 0.5 * dt * k1p) * Ep + 0.5 * dt * k2p

    def fields(self):
        J = np.real(np.fft.ifft2(-self.K2 * self.p))
        w = np.real(np.fft.ifft2(self.w))
        return w, J

    def cfl_speed(self):
        phi_h = -self.w * self.K2inv
        ux = np.real(np.fft.ifft2(-1j * self.KY * phi_h))
        uy = np.real(np.fft.ifft2(1j * self.KX * phi_h))
        bx = np.real(np.fft.ifft2(-1j * self.KY * self.p))
        by = np.real(np.fft.ifft2(1j * self.KX * self.p))
        return float(max(np.max(np.hypot(ux, uy)), np.max(np.hypot(bx, by))))
