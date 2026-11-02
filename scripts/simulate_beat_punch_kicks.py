#!/usr/bin/env python3
"""Offline check: proportional kick peaks + sensitivity threshold (mirrors MicTuning)."""

from __future__ import annotations

SENS_MIN = 0.25
SENS_MAX = 3.0
REFRACTORY_S = 0.12


def trigger_threshold(sensitivity: float) -> float:
    s = max(SENS_MIN, min(SENS_MAX, sensitivity))
    norm = (s - SENS_MIN) / (SENS_MAX - SENS_MIN)
    high, low = 0.44, 0.13
    return high - norm * (high - low)


def peak_magnitude(onset: float, threshold: float, bass: float) -> float:
    excess = max(0.0, min(onset - threshold, 1.35))
    if excess <= 0.02:
        return 0.0
    bass_w = max(0.0, min(bass, 1.6))
    bass_mix = 0.42 + 0.58 * min(bass_w, 1.0)
    return min(1.0, excess * bass_mix)


def simulate_kicks(
    frames: list[tuple[float, float, float, float]],
    sensitivity: float,
    strength_pct: int = 85,
) -> list[float]:
    """frames: (dt, onset, bass, presence+loudness proxy). Returns peak envelope per frame."""
    threshold = trigger_threshold(sensitivity)
    strength = strength_pct / 100.0
    armed = True
    last_trigger = -1e9
    peaks: list[float] = []
    for t_acc, (dt, onset, bass, live) in enumerate(frames):
        now = sum(f[0] for f in frames[: t_acc + 1])
        peak = 0.0
        if strength > 0 and armed and live > 0.5 and onset > threshold:
            if now - last_trigger >= REFRACTORY_S:
                mag = peak_magnitude(onset, threshold, bass) * strength
                if mag > 0.04:
                    peak = mag
                    last_trigger = now
                    armed = False
        if onset < threshold * 0.48:
            armed = True
        peaks.append(peak)
    return peaks


def main() -> None:
    # Irregular kicks: 0.35s, 0.62s, 0.28s gaps — not 500 ms metronome.
    timeline: list[tuple[float, float, float, float]] = []
    t = 0.0
    for _ in range(400):
        timeline.append((1 / 60.0, 0.02, 0.05, 0.0))  # silence
        t += 1 / 60.0
    kick_times = [0.5, 0.85, 1.47, 2.05, 2.33]
    for kt in kick_times:
        idx = int(kt * 60)
        if idx < len(timeline):
            timeline[idx] = (1 / 60.0, 0.72, 0.95, 1.0)
            if idx + 1 < len(timeline):
                timeline[idx + 1] = (1 / 60.0, 0.38, 0.6, 1.0)

    low_sens = simulate_kicks(timeline, sensitivity=0.5)
    high_sens = simulate_kicks(timeline, sensitivity=2.5)
    low_hits = sum(1 for p in low_sens if p > 0.04)
    high_hits = sum(1 for p in high_sens if p > 0.04)
    assert low_hits >= 3, f"expected irregular kicks detected, got {low_hits}"
    assert high_hits >= low_hits, "higher sensitivity should not reduce kick count"

    silent_peaks = simulate_kicks([(1 / 60.0, 0.25, 0.04, 0.0)] * 120, sensitivity=2.5)
    assert max(silent_peaks) < 0.04, "silence must not produce tsunami peaks"

    weak = peak_magnitude(0.35, trigger_threshold(1.0), 0.2)
    strong = peak_magnitude(0.85, trigger_threshold(1.0), 0.9)
    assert strong > weak * 1.5, "strong kick must dominate weak"

    print("simulate_beat_punch_kicks: OK")
    print(f"  threshold@1.0× = {trigger_threshold(1.0):.2f}")
    print(f"  kicks low_sens={low_hits} high_sens={high_hits}")
    print(f"  weak={weak:.3f} strong={strong:.3f}")


if __name__ == "__main__":
    main()
