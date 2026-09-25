#!/usr/bin/env python3
"""FF.1: engine vs spike coherence overlay, one panel per parity track.

Reads the spike's `<stem>_metrics.csv` (FF.0) and the engine's `engine_<stem>.csv`, written by
`FirefliesSpikeParityProbe` with FIREFLIES_PARITY=1 FIREFLIES_PARITY_OUT=<dir>.

    /usr/bin/python3 plot_parity.py ~/Documents/uzume_spikes/fireflies ~/Documents/uzume_spikes/fireflies/ff1
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

SPIKE = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Documents/uzume_spikes/fireflies")
ENGINE = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else f"{SPIKE}/ff1")
PANELS = [  # (stem, title)
    ("a_dance_yrself_clean", "Dance Yrself Clean · clarity 1 → K 1"),
    ("b_pyramid_song", "Pyramid Song · clarity 1 → K 1"),
    ("c_warszawa_K0", "Warszawa · clarity 0.5 (unknown) → K 0"),
    ("m_teardrop", "Teardrop · clarity 0 → K 0"),
]
BLUE, ORANGE, INK, MUTED = "#2a78d6", "#eb6834", "#1f1f1e", "#8a897f"

fig, axes = plt.subplots(len(PANELS), 1, figsize=(9, 1.9 * len(PANELS)), sharex=True)
print("| track | R 25–30 s spike | engine | Δ | on-beat 25–30 s spike | engine | Δ |")
print("|---|---|---|---|---|---|---|")
for ax, (stem, title) in zip(axes, PANELS):
    s = np.genfromtxt(f"{SPIKE}/{stem}_metrics.csv", delimiter=",", names=True)
    e = np.genfromtxt(f"{ENGINE}/engine_{stem}.csv", delimiter=",", names=True)
    ax.axvspan(25, 30, color="#eeede6", lw=0, zorder=0)
    ax.axhline(0, color="#e6e5de", lw=1, zorder=0)
    ax.plot(s["t"], s["R_swarm"], color=BLUE, lw=1.2, ls="--", label="R · spike")
    ax.plot(e["t"], e["R_swarm"], color=BLUE, lw=2, label="R · engine")
    ax.plot(s["t"], s["onbeat_true_grid"], color=ORANGE, lw=1.2, ls="--", label="on-beat · spike")
    ax.plot(e["t"], e["onbeat_true_grid"], color=ORANGE, lw=2, label="on-beat · engine")
    ax.set_ylim(-1.05, 1.05)
    ax.set_yticks([-1, 0, 1])
    ax.set_title(title, loc="left", fontsize=9, color=INK, pad=3)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    ax.tick_params(colors=MUTED, labelsize=8)

    def win(d, col):
        m = (d["t"] >= 25) & (d["t"] < 30)
        return np.nanmean(d[col][m])
    rs, re_ = win(s, "R_swarm"), win(e, "R_swarm")
    bs, be = win(s, "onbeat_true_grid"), win(e, "onbeat_true_grid")
    print(f"| {stem} | {rs:.3f} | {re_:.3f} | {re_ - rs:+.3f} | {bs:+.3f} | {be:+.3f} | {be - bs:+.3f} |")
axes[0].legend(loc="lower right", fontsize=7, frameon=False, ncol=4)
axes[-1].set_xlabel("seconds from the start of the clip (shaded: the 25–30 s parity window)", fontsize=9, color=INK)
fig.suptitle("Fireflies FF.1 — engine (solid) vs FF.0 spike (dashed)", x=0.01, ha="left", fontsize=10, color=INK)
fig.tight_layout()
fig.savefig(f"{ENGINE}/parity_overlay.png", dpi=130)
print(f"wrote {ENGINE}/parity_overlay.png")
