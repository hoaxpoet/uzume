#!/usr/bin/env python3
"""FF.0: coherence-vs-time small multiples + the luminance table, from *_metrics.csv.

    /usr/bin/python3 plot_coherence.py ~/Documents/uzume_spikes/fireflies
"""
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

D = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Documents/uzume_spikes/fireflies")
PANELS = [  # (metrics stem, title)
    ("a_dance_yrself_clean", "(a) Dance Yrself Clean · K=1 (census: steady)"),
    ("m_dyc_K0.5", "Dance Yrself Clean · K=0.5 (same audio)"),
    ("m_dyc_K0", "Dance Yrself Clean · K=0 (same audio)"),
    ("r1_decoy_dance_yrself_clean", "R1 decoy · DYC, grid shifted ½ beat · K=1"),
    ("b_pyramid_song", "(b) Pyramid Song · K=1 (census: steady)"),
    ("c_warszawa", "(c) Warszawa · K=0.5 (census: unknown)"),
    ("c_warszawa_K0", "(c) Warszawa · K=0 (what a beatless reading needs)"),
    ("m_teardrop", "Teardrop · K=0 (census: irregular)"),
    ("c_warszawa_tail_near_silence", "Warszawa last 30 s · K=0.5 · near-silence shaded"),
]
BLUE, ORANGE, INK, MUTED = "#2a78d6", "#eb6834", "#1f1f1e", "#8a897f"

fig, axes = plt.subplots(len(PANELS), 1, figsize=(9, 1.55 * len(PANELS)), sharex=True)
for ax, (stem, title) in zip(axes, PANELS):
    d = np.genfromtxt(f"{D}/{stem}_metrics.csv", delimiter=",", names=True)
    t = d["t"]
    if d["near_silent"].any():
        ax.fill_between(t, -1, 1, where=d["near_silent"] > 0, color="#d9d8d0", lw=0)
    ax.axhline(0, color="#e6e5de", lw=1, zorder=0)
    ax.plot(t, d["R_swarm"], color=BLUE, lw=2, label="swarm coherence R")
    ax.plot(t, d["onbeat_true_grid"], color=ORANGE, lw=2, label="on the true beat (+1) / off (−1)")
    ax.set_ylim(-1.05, 1.05)
    ax.set_yticks([-1, 0, 1])
    ax.set_title(title, loc="left", fontsize=9, color=INK, pad=3)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.tick_params(colors=MUTED, labelsize=8)
axes[0].legend(loc="lower right", fontsize=8, frameon=False, ncol=2)
axes[-1].set_xlabel("seconds from the start of the clip", fontsize=9, color=INK)
fig.suptitle("Fireflies FF.0 — does the swarm find the beat?  (chance band for the orange line ≈ ±0.03)",
             x=0.01, ha="left", fontsize=10, color=INK)
fig.tight_layout()
fig.savefig(f"{D}/coherence_plots.png", dpi=130)

print("| film | K | mean luma | max per-second luma range | max Δ luma / frame (D-157 gate 0.05) |")
print("|---|---|---|---|---|")
for stem in ("a_dance_yrself_clean", "b_pyramid_song", "c_warszawa", "c_warszawa_K0",
             "c_warszawa_tail_near_silence", "r1_decoy_dance_yrself_clean"):
    d = np.genfromtxt(f"{D}/{stem}_metrics.csv", delimiter=",", names=True)
    Y = d["frame_luma"]
    rng = max(np.ptp(Y[i:i + 30]) for i in range(0, len(Y) - 29, 30))
    print(f"| {stem} | | {Y.mean():.3f} | {rng:.4f} | {np.abs(np.diff(Y)).max():.4f} |")
