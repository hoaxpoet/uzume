"""Physically-based thin-film iridescence LUT.

Two-beam interference reflectance integrated against the CIE 1931 colour matching
functions, tabulated against optical path difference. In a Metal shader this is a
single 1D texture fetch indexed by OPD — the standard iridescence technique.

CIE x-bar/y-bar/z-bar use Wyman, Sloan & Shirley (2013) multi-lobe Gaussian fits.
"""
import numpy as np

_XYZ_TO_SRGB = np.array([
    [3.2406, -1.5372, -0.4986],
    [-0.9689, 1.8758, 0.0415],
    [0.0557, -0.2040, 1.0570]])


def _g(x, mu, s1, s2):
    s = np.where(x < mu, s1, s2)
    return np.exp(-0.5 * ((x - mu) / s) ** 2)


def cie(lam):
    x = 1.056 * _g(lam, 599.8, 37.9, 31.0) + 0.362 * _g(lam, 442.0, 16.0, 26.7) \
        - 0.065 * _g(lam, 501.1, 20.4, 26.2)
    y = 0.821 * _g(lam, 568.8, 46.9, 40.5) + 0.286 * _g(lam, 530.9, 16.3, 31.1)
    z = 1.217 * _g(lam, 437.0, 11.8, 36.0) + 0.681 * _g(lam, 459.0, 26.0, 13.8)
    return x, y, z


def build_lut(n=1024, opd_max=3200.0, nlam=48, sat=1.25):
    lam = np.linspace(380.0, 730.0, nlam)
    xb, yb, zb = cie(lam)
    norm = yb.sum()
    opd = np.linspace(0.0, opd_max, n)
    # R(opd, lam); pi is the half-wave shift at the front surface
    ph = 2 * np.pi * opd[:, None] / lam[None, :] + np.pi
    R = 0.5 - 0.5 * np.cos(ph)
    X = (R * xb).sum(1) / norm
    Y = (R * yb).sum(1) / norm
    Z = (R * zb).sum(1) / norm
    rgb = np.stack([X, Y, Z], 1) @ _XYZ_TO_SRGB.T
    rgb = np.clip(rgb, 0, None)
    # push saturation about the luminance axis, then normalise and gamma
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    rgb = np.clip(lum[:, None] + sat * (rgb - lum[:, None]), 0, None)
    rgb = rgb / (rgb.max() + 1e-9)
    return np.clip(rgb, 0, 1) ** (1 / 2.2), opd_max


LUT, OPD_MAX = build_lut()


def lookup(opd):
    i = np.clip(opd / OPD_MAX, 0, 1) * (LUT.shape[0] - 1)
    i0 = np.floor(i).astype(int)
    i1 = np.minimum(i0 + 1, LUT.shape[0] - 1)
    f = (i - i0)[..., None]
    return LUT[i0] * (1 - f) + LUT[i1] * f
