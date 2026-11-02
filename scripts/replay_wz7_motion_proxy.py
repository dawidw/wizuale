#!/usr/bin/env python3
"""Offline replay: ffmpeg PCM → simplified BandAnalyzer bass + motion proxy vs recording.

Usage:
  ffmpeg -y -i wz7.mp4 -vn -ac 1 -ar 48000 -f f32le /tmp/wz7.raw
  python3 scripts/replay_wz7_motion_proxy.py /tmp/wz7.raw [--plot docs/wz7-motion-proxy.png]

Mirrors phone-side bass shaping (mean-energy normalizer + 110 Hz LP) and TV continuous
projectM boost (MicSceneModulation @ default Intensywność 20×).
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

import numpy as np

SAMPLE_RATE = 48_000
HOP = 512
CONT_BASE = 0.88
INTENSITY = 20.0  # 2000 permille
BASS_CAP = 2.8
PRESET_JUMP_S = 32.0  # Dawid timeline: auto-advance flash ~0:32


class MeanEnergyNormalizer:
    def __init__(self) -> None:
        self.mean = 1e-4

    def normalize(self, energy: float, dt: float) -> float:
        coef = 1 - math.exp(-dt / 3.8)
        self.mean += (energy - self.mean) * coef
        self.mean = max(self.mean, 1e-8)
        scaled = math.sqrt(max(energy, 0) / self.mean)
        return min(max(scaled, 0), 1.85)


def one_pole_lowpass(x: np.ndarray, cutoff: float, sr: float) -> np.ndarray:
    """Simple RC lowpass — good enough for offline bass energy."""
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / sr
    alpha = dt / (rc + dt)
    y = np.empty_like(x)
    state = 0.0
    for i, sample in enumerate(x):
        state = state + alpha * (sample - state)
        y[i] = state
    return y


def adaptive_continuous_scale(live: float, slow: float) -> float:
    reference = max(slow, 0.10)
    ratio = reference / max(live, 0.06)
    return min(max(0.75 + ratio * 0.35, 0.85), 2.35)


def motion_proxy(bass: float, slow: float) -> float:
    b = min(max(bass, 0), BASS_CAP)
    adapt = adaptive_continuous_scale(b, slow)
    cont = b * CONT_BASE * INTENSITY * adapt
    ceiling = 10.0
    return ceiling * math.tanh(cont / ceiling)


def replay(pcm: np.ndarray, sr: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    bass_f = one_pole_lowpass(pcm, 110.0, sr)
    norm = MeanEnergyNormalizer()
    bass_out: list[float] = []
    proxy_out: list[float] = []
    slow_out: list[float] = []
    t_out: list[float] = []
    bass_slow = 0.0
    for start in range(0, len(pcm) - HOP, HOP):
        chunk = bass_f[start : start + HOP]
        energy = float(np.mean(chunk * chunk))
        dt = len(chunk) / sr
        shaped = norm.normalize(energy, dt)
        slow_coef = 1 - math.exp(-dt / 4.0)
        bass_slow += (shaped - bass_slow) * slow_coef
        t = start / sr
        bass_out.append(shaped)
        slow_out.append(bass_slow)
        proxy_out.append(motion_proxy(shaped, bass_slow))
        t_out.append(t)
    return (
        np.asarray(t_out),
        np.asarray(bass_out),
        np.asarray(proxy_out),
        np.asarray(slow_out),
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("f32le_path", type=Path)
    parser.add_argument("--plot", type=Path, default=None)
    args = parser.parse_args()
    raw = args.f32le_path.read_bytes()
    count = len(raw) // 4
    samples = struct.unpack(f"<{count}f", raw[: count * 4])
    pcm = np.asarray(samples, dtype=np.float64)
    for i in range(len(pcm)):
        peak = 0.92
        pcm[i] = peak * math.tanh(pcm[i] / peak)

    t, bass, proxy, slow = replay(pcm, SAMPLE_RATE)
    active = bass > 0.12
    pct_active = 100.0 * np.mean(active)
    mean_proxy = float(np.mean(proxy[active])) if np.any(active) else 0.0
    idx_jump = int(np.argmin(np.abs(t - PRESET_JUMP_S)))
    print(f"replay_wz7_motion_proxy: {args.f32le_path.name}")
    print(f"  duration {t[-1]:.1f}s  hops {len(t)}")
    print(f"  bass>0.12 for {pct_active:.1f}% of hops (expect high with loud track)")
    print(f"  mean motion proxy (active) = {mean_proxy:.2f} / 10")
    print(f"  @ t≈{PRESET_JUMP_S}s: bass={bass[idx_jump]:.2f} proxy={proxy[idx_jump]:.2f} (preset jump — proxy must not collapse)")

    if pct_active < 25:
        print("  WARN: low bass duty — check mic gain / band sliders / calibration", file=sys.stderr)

    if args.plot:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        fig, axes = plt.subplots(2, 1, figsize=(12, 6), sharex=True)
        axes[0].plot(t, bass, label="shaped bass (mean-energy)", linewidth=0.8)
        axes[0].plot(t, slow, label="bass slow EMA 4s", alpha=0.7, linewidth=0.8)
        axes[0].axvline(PRESET_JUMP_S, color="red", linestyle="--", alpha=0.5, label="~preset auto-advance")
        axes[0].set_ylabel("feature")
        axes[0].legend(loc="upper right", fontsize=8)
        axes[0].set_title("Offline BandAnalyzer bass vs Dawid wz7 audio")

        axes[1].plot(t, proxy, color="orange", label="continuous motion proxy (projectM sens)", linewidth=0.9)
        axes[1].axvline(PRESET_JUMP_S, color="red", linestyle="--", alpha=0.5)
        axes[1].set_xlabel("time (s)")
        axes[1].set_ylabel("proxy")
        axes[1].legend(loc="upper right", fontsize=8)
        fig.tight_layout()
        args.plot.parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(args.plot, dpi=120)
        print(f"  wrote {args.plot}")


if __name__ == "__main__":
    main()
