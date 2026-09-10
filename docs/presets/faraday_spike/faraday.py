"""Faraday instability spike — parametrically driven gravity-capillary surface.

Each Fourier mode of the surface height obeys a damped MATHIEU equation:

    h_k'' + 2 gamma_k h_k' + omega_k^2 (1 + F(t)) h_k = NL_k
    omega_k^2 = g k + sigma k^3          (gravity-capillary dispersion)
    gamma_k   = nu k^2                   (viscous damping)
    NL        = -lambda h^3              (saturation -> pattern selection)

A mode goes unstable when its natural frequency sits at HALF a drive frequency
(the subharmonic Faraday resonance). That is the whole idea:

    the drive's frequency content selects WHICH WAVENUMBERS appear,
    so the music does not brighten the picture -- it re-scales and re-symmetrises it.

Two-frequency forcing (Edwards & Fauve 1994) is the classic route to squares,
hexagons, superlattices and 12-fold quasipatterns. Here the RATIO of the two
drive frequencies is the knob, and in the audio-driven version that ratio comes
from the music's two strongest partials.
"""
import numpy as np


class Faraday:
    def __init__(self, N=256, g=1.0, sigma=0.02, nu=0.0035, lam=1.0,
                 k0=11.0, seed=5, hmax=3.0, rms_cap=2.2):
        self.N = N
        k = np.fft.fftfreq(N) * N
        kx = np.fft.fftfreq(N) * N
        ky = np.fft.rfftfreq(N) * N
        self.KX, self.KY = np.meshgrid(kx, ky, indexing="ij")
        self.K = np.sqrt(self.KX ** 2 + self.KY ** 2)
        self.W2 = g * self.K + sigma * self.K ** 3          # omega_k^2
        self.GAM = nu * self.K ** 2                          # damping
        kmax = N / 2
        self.FILT = np.exp(-36.0 * np.clip(self.K / kmax, 0, 1) ** 36)
        self.lam = lam
        self.hmax = hmax
        self.rms_cap = rms_cap
        # drive frequency set so that k0 is the subharmonically resonant mode
        self.omega = 2.0 * float(np.sqrt(g * k0 + sigma * k0 ** 3))
        self.rng = np.random.default_rng(seed)
        self.h = np.fft.rfft2(1e-3 * self.rng.standard_normal((N, N)))
        self.hd = np.zeros_like(self.h)
        self.t = 0.0
        # Drive phases are INTEGRATED, never recomputed from absolute time.
        # Recomputing cos(p*w*t) after a ratio change steps the phase, which
        # dephases the parametric resonance and kills the pattern outright
        # (measured: hrms 0.53 -> 0.03 across one symmetry switch). Changing the
        # ratio must change the drive's RATE, never its phase.
        self.ph1 = 0.0
        self.ph2 = 0.4

    def advance_phase(self, dt, ratio):
        p, q = ratio
        w = self.omega / max(p, 1)
        self.ph1 += p * w * dt
        self.ph2 += q * w * dt

    def drive(self, amp, mix=0.0):
        a = np.cos(0.5 * np.pi * mix)
        b = np.sin(0.5 * np.pi * mix)
        return amp * (a * np.cos(self.ph1) + b * np.cos(self.ph2))

    def step(self, dt, amp, ratio=(1, 1), mix=0.0, phase=0.0):
        self.advance_phase(0.5 * dt, ratio)
        F = self.drive(amp, mix)
        self.advance_phase(0.5 * dt, ratio)
        # ambient noise floor: a real film is never perfectly flat, and without
        # one the field decays to exactly zero in a quiet passage and cannot
        # regrow when the music comes back.
        self.h = self.h + np.fft.rfft2(
            1.2e-4 * self.rng.standard_normal((self.N, self.N)))
        hr = np.fft.irfft2(self.h, s=(self.N, self.N))
        # SATURATING nonlinearity. A bare -lam*h^3 diverges the instant the drive
        # spikes (measured: blow-up at frame ~70 on a bass hit). Bounding the
        # restoring force is also the physically sensible limit -- a real film
        # cannot deform without bound.
        hrc = np.clip(hr, -8 * self.hmax, 8 * self.hmax)
        nl = -self.lam * np.fft.rfft2(hrc ** 3 / (1.0 + (hrc / self.hmax) ** 2))
        acc = -2 * self.GAM * self.hd - self.W2 * (1.0 + F) * self.h + nl
        self.hd = (self.hd + dt * acc) * self.FILT
        self.h = (self.h + dt * self.hd) * self.FILT
        # soft global amplitude limiter: the watchdog, not a tuning knob
        cur = float(np.std(np.fft.irfft2(self.h, s=(self.N, self.N))))
        if cur > self.rms_cap:
            f = self.rms_cap / cur
            self.h *= f
            self.hd *= f
        self.t += dt
        if not np.isfinite(self.h).all():
            self.h = np.fft.rfft2(1e-3 * np.random.standard_normal((self.N, self.N)))
            self.hd = np.zeros_like(self.h)
            return False
        return True

    def begin_reseed(self, amp=1.0):
        """Dissolve toward a fresh film. Triggered by the ORDER PARAMETER, not a timer:
        S is computed from the spectrum the solver already has, so the preset re-seeds
        when the picture is measurably going stale rather than on a fixed clock."""
        f = self.rng.standard_normal((self.N, self.N))
        fh = np.fft.rfft2(f)
        kk = self.K
        band = np.exp(-((kk - 2.0 * 3.0) / 4.0) ** 2)     # energy near the resonant shell
        fh = fh * band
        fr = np.fft.irfft2(fh, s=(self.N, self.N))
        self._blend = np.fft.rfft2(fr * (amp * 0.9 / (np.std(fr) + 1e-9)))
        self._blend_t = 0.0

    def advance_blend(self, dt, tau=1.2):
        if getattr(self, "_blend", None) is None:
            return
        self._blend_t += dt
        a = min(self._blend_t / tau, 1.0)
        g = 0.5 - 0.5 * np.cos(np.pi * a)
        r = g * (dt / max(tau, 1e-6)) * np.pi
        self.h = (1 - r) * self.h + r * self._blend
        self.hd = (1 - r) * self.hd
        if a >= 1.0:
            self._blend = None

    def surface(self):
        return np.fft.irfft2(self.h, s=(self.N, self.N))

    def envelope(self):
        """The standing wave's AMPLITUDE, not its instantaneous height.

        A subharmonic Faraday wave oscillates at omega/2 and therefore passes
        through FLAT twice per cycle -- render the raw height and the picture
        strobes to nothing (measured: hrms 1.35 -> 0.01 between sampled frames,
        which looked like a collapse and was not). The eye never sees that at a
        real drive frequency; it sees the envelope. So does this preset.

            A = sqrt(h^2 + (h_dot / omega_sub)^2)
        """
        ws = 0.5 * self.omega
        h = np.fft.irfft2(self.h, s=(self.N, self.N))
        v = np.fft.irfft2(self.hd, s=(self.N, self.N)) / ws
        a = np.sqrt(h * h + v * v)
        return a - a.mean()

    def envelope_slopes(self):
        ws = 0.5 * self.omega
        h = np.fft.irfft2(self.h, s=(self.N, self.N))
        v = np.fft.irfft2(self.hd, s=(self.N, self.N)) / ws
        hx = np.fft.irfft2(1j * self.KX * self.h, s=(self.N, self.N))
        hy = np.fft.irfft2(1j * self.KY * self.h, s=(self.N, self.N))
        vx = np.fft.irfft2(1j * self.KX * self.hd, s=(self.N, self.N)) / ws
        vy = np.fft.irfft2(1j * self.KY * self.hd, s=(self.N, self.N)) / ws
        a = np.sqrt(h * h + v * v) + 1e-9
        return (h * hx + v * vx) / a, (h * hy + v * vy) / a

    def slopes(self):
        """Surface gradient — what you actually SEE on water (refraction/specular),
        not the height itself. The Alfven lesson: render the derivative field."""
        hx = np.fft.irfft2(1j * self.KX * self.h, s=(self.N, self.N))
        hy = np.fft.irfft2(1j * self.KY * self.h, s=(self.N, self.N))
        return hx, hy
