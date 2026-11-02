#!/usr/bin/env python3
"""
Offline replay: ffmpeg mono f32le → BandAnalyzer (+ optional TV follow / BeatPunch).

Mirrors Shared/MicAnalyzer.swift, Wizuale/MicReceiver.swift follow(), MicTuning kick gate.
Use for wz7 (and other) captures to align bass/kick onsets vs expected TV reaction.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

import numpy as np

# --- MicTuning (subset) -------------------------------------------------------

SENS_MIN, SENS_MAX, SENS_DEFAULT = 0.25, 3.0, 1.0
REFRACTORY_PUNCH = 0.12


def kick_onset_trigger_threshold(sensitivity: float) -> float:
    s = max(SENS_MIN, min(SENS_MAX, sensitivity))
    norm = (s - SENS_MIN) / (SENS_MAX - SENS_MIN) if SENS_MAX > SENS_MIN else 0.5
    high, low = 0.44, 0.13
    return high - norm * (high - low)


def kick_onset_rearm_threshold(sensitivity: float) -> float:
    return kick_onset_trigger_threshold(sensitivity) * 0.48


def kick_peak_magnitude(onset: float, threshold: float, bass: float) -> float:
    excess = max(0.0, min(onset - threshold, 1.35))
    if excess <= 0.02:
        return 0.0
    bass_w = max(0.0, min(bass, 1.6))
    bass_mix = 0.42 + 0.58 * min(bass_w, 1.0)
    return min(1.0, excess * bass_mix)


# --- Biquad (direct form I, Float coefficients) -------------------------------

@dataclass
class Biquad:
    b0: float = 0.0
    b1: float = 0.0
    b2: float = 0.0
    a1: float = 0.0
    a2: float = 0.0
    x1: float = 0.0
    x2: float = 0.0
    y1: float = 0.0
    y2: float = 0.0

    def process(self, x: float) -> float:
        y = self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2, self.x1 = self.x1, x
        self.y2, self.y1 = self.y1, y
        if abs(y) < 1e-20:
            return 0.0
        return y

    @staticmethod
    def _coefficients(kind: int, cutoff: float, sample_rate: float, q: float) -> Biquad:
        rate = max(sample_rate, 8000.0)
        fc = min(max(cutoff, 20.0), rate * 0.45)
        resonance = max(q, 0.2)
        w0 = 2.0 * math.pi * fc / rate
        cosine = math.cos(w0)
        sine = math.sin(w0)
        alpha = sine / (2.0 * resonance)
        if kind == 1:
            b0, b1, b2 = alpha, 0.0, -alpha
        elif kind == 2:
            b0 = b2 = (1.0 + cosine) / 2.0
            b1 = -(1.0 + cosine)
        else:
            b0 = b2 = (1.0 - cosine) / 2.0
            b1 = 1.0 - cosine
        a0 = 1.0 + alpha
        return Biquad(
            b0=b0 / a0,
            b1=b1 / a0,
            b2=b2 / a0,
            a1=(-2.0 * cosine) / a0,
            a2=(1.0 - alpha) / a0,
        )

    @classmethod
    def lowpass(cls, cutoff: float, sample_rate: float, q: float = 0.707) -> Biquad:
        return cls._coefficients(0, cutoff, sample_rate, q)

    @classmethod
    def bandpass(cls, cutoff: float, sample_rate: float, q: float = 0.85) -> Biquad:
        return cls._coefficients(1, cutoff, sample_rate, q)

    @classmethod
    def highpass(cls, cutoff: float, sample_rate: float, q: float = 0.707) -> Biquad:
        return cls._coefficients(2, cutoff, sample_rate, q)


@dataclass
class NormalizerProfile:
    peak_attack: float = 0.45
    peak_release: float = 5.5
    floor_attack: float = 0.35
    floor_release: float = 8.0
    slow_mean_tau: float = 0.0  # 0 = legacy (no slow mean)
    slow_mean_span_scale: float = 0.18
    bass_peak_attack_scale: float = 1.0  # <1 → faster bass attack on peak tracker


@dataclass
class Normalizer:
    peak: float = 1e-4
    floor: float = 1e-6
    slow_mean: float = 1e-4
    profile: NormalizerProfile = field(default_factory=NormalizerProfile)

    def seed(self, noise: float) -> None:
        base = max(noise, 0.0)
        self.floor = 0.0
        self.peak = max(base * 8.0, 1e-5)
        self.slow_mean = self.peak

    def normalize(self, energy: float, dt: float) -> float:
        dt_safe = max(dt, 0.0001)
        p = self.profile
        attack_tau = p.peak_attack * p.bass_peak_attack_scale
        if energy > self.peak:
            self.peak += (energy - self.peak) * (1.0 - math.exp(-dt_safe / attack_tau))
        else:
            self.peak += (energy - self.peak) * (1.0 - math.exp(-dt_safe / p.peak_release))
        self.peak = max(self.peak, 1e-8)

        if energy < self.floor:
            self.floor += (energy - self.floor) * (1.0 - math.exp(-dt_safe / p.floor_attack))
        else:
            self.floor += (energy - self.floor) * (1.0 - math.exp(-dt_safe / p.floor_release))
        self.floor = min(self.floor, self.peak * 0.5)

        if p.slow_mean_tau > 0:
            slow_coef = 1.0 - math.exp(-dt_safe / p.slow_mean_tau)
            self.slow_mean += (energy - self.slow_mean) * slow_coef
            self.slow_mean = max(self.slow_mean, 1e-8)
            adaptive_floor = min(self.floor, self.slow_mean * 0.55)
            adaptive_peak = max(self.peak, self.slow_mean * 1.35)
            span = max(
                adaptive_peak - adaptive_floor,
                self.slow_mean * p.slow_mean_span_scale,
                self.peak * 0.22,
                1e-8,
            )
        else:
            span = max(self.peak - self.floor, self.peak * 0.22, 1e-8)

        return min(max((energy - self.floor) / span, 0.0), 1.8)


@dataclass
class AnalyzerProfile:
    onset_adaptive_window_s: float = 1.0
    onset_adaptive_k: float = 1.12
    onset_refractory_s: float = 0.12
    onset_release_tau: float = 0.038
    onset_bass_level_min: float = 0.20
    onset_loudness_min: float = 0.10
    onset_gate_floor: float = 0.00006
    onset_flux_margin: float = 1.18
    silence_loudness_max: float = 0.055
    silence_bass_max: float = 0.07
    normalizer: NormalizerProfile = field(default_factory=NormalizerProfile)


@dataclass
class TVFollowProfile:
    bass_attack: float = 0.006
    bass_release: float = 0.24
    onset_attack: float = 0.002
    onset_release: float = 0.052
    high_attack: float = 0.012
    high_release: float = 0.075
    shaped_pow: float = 0.85
    hit_cap: float = 3.5
    sensitivity: float = SENS_DEFAULT
    strength_pct: int = 85


PROFILE_BEFORE = AnalyzerProfile(
    normalizer=NormalizerProfile(slow_mean_tau=0.0),
)
PROFILE_AFTER = AnalyzerProfile(
    onset_adaptive_k=1.06,
    onset_bass_level_min=0.15,
    onset_loudness_min=0.065,
    onset_flux_margin=1.10,
    onset_release_tau=0.032,
    normalizer=NormalizerProfile(
        slow_mean_tau=4.0,
        slow_mean_span_scale=0.14,
        bass_peak_attack_scale=0.55,
    ),
)
TV_BEFORE = TVFollowProfile(bass_attack=0.006, high_attack=0.012, sensitivity=3.0)
TV_AFTER = TVFollowProfile(bass_attack=0.0025, high_attack=0.0075, sensitivity=3.0)


def follow(current: float, target: float, dt: float, attack: float, release: float) -> float:
    tau = max(attack if target > current else release, 0.0001)
    mix_amt = 1.0 - math.exp(-dt / tau)
    return current + (target - current) * mix_amt


def shaped(value: float, pow_exp: float = 0.85, ceiling: float = 1.8) -> float:
    v = min(max(value, 0.0), ceiling)
    return v**pow_exp


def hit(value: float, sensitivity: float, cap: float = 3.5, pow_exp: float = 0.85) -> float:
    return min(shaped(value, pow_exp) * max(sensitivity, 0.0), cap)


@dataclass
class BandAnalyzer:
    profile: AnalyzerProfile = field(default_factory=AnalyzerProfile)
    built_rate: float = 0.0
    filters: list[Biquad] = field(default_factory=list)
    kick_high: Biquad = field(default_factory=Biquad)
    kick_low: Biquad = field(default_factory=Biquad)
    gains: list[Normalizer] = field(default_factory=list)
    loud_gain: Normalizer = field(default_factory=Normalizer)
    flux_gain: Normalizer = field(default_factory=Normalizer)
    previous_energy: list[float] = field(default_factory=lambda: [0.0] * 4)
    previous_kick_energy: float = 0.0
    kick_flux_mean: float = 0.0
    kick_flux_mean_sq: float = 0.0
    onset: float = 0.0
    refractory: float = 0.0
    have_previous: bool = False
    have_previous_kick: bool = False
    noise_bass: float = 0.0

    def _ensure_filters(self, rate: float) -> None:
        if len(self.filters) == 4 and abs(rate - self.built_rate) <= 1.0:
            return
        self.filters = [
            Biquad.lowpass(110, rate, 0.707),
            Biquad.bandpass(300, rate, 0.85),
            Biquad.bandpass(1400, rate, 0.8),
            Biquad.highpass(5000, rate, 0.707),
        ]
        self.kick_high = Biquad.highpass(40, rate, 0.707)
        self.kick_low = Biquad.lowpass(120, rate, 0.707)
        self.built_rate = rate
        np_profile = self.profile.normalizer
        self.gains = [
            Normalizer(profile=np_profile if i == 0 else NormalizerProfile(slow_mean_tau=np_profile.slow_mean_tau))
            for i in range(4)
        ]
        if np_profile.slow_mean_tau > 0:
            for g in self.gains:
                g.profile = NormalizerProfile(
                    slow_mean_tau=np_profile.slow_mean_tau,
                    slow_mean_span_scale=np_profile.slow_mean_span_scale,
                    bass_peak_attack_scale=np_profile.bass_peak_attack_scale if g is self.gains[0] else 1.0,
                )
        self.loud_gain = Normalizer(profile=NormalizerProfile(slow_mean_tau=np_profile.slow_mean_tau))
        self.flux_gain = Normalizer()
        self.have_previous = False
        self.have_previous_kick = False

    def consume_block(self, samples: np.ndarray, sample_rate: float) -> dict[str, float]:
        count = len(samples)
        if count == 0:
            return _zero_features()
        rate = max(sample_rate, 8000.0)
        self._ensure_filters(rate)
        p = self.profile

        energy = [0.0] * 4
        kick_energy = 0.0
        loud_sum = 0.0
        for sample in samples:
            loud_sum += sample * sample
            ks = self.kick_low.process(self.kick_high.process(float(sample)))
            kick_energy += ks * ks
            for band in range(4):
                shaped_s = self.filters[band].process(float(sample))
                energy[band] += shaped_s * shaped_s

        inv = 1.0 / count
        energy = [e * inv for e in energy]
        kick_energy *= inv
        loud_raw = loud_sum * inv
        dt = count / rate

        flux_raw = 0.0
        if self.have_previous:
            for band in range(4):
                flux_raw += max(0.0, energy[band] - self.previous_energy[band])
        self.previous_energy = energy[:]
        self.have_previous = True

        kick_flux = 0.0
        if self.have_previous_kick:
            kick_flux = max(0.0, kick_energy - self.previous_kick_energy)
        self.previous_kick_energy = kick_energy
        self.have_previous_kick = True

        energy[0] = max(0.0, energy[0] - self.noise_bass)
        loud_clean = max(0.0, loud_raw)

        shaped_bands = [self.gains[i].normalize(energy[i], dt) for i in range(4)]
        loudness = self.loud_gain.normalize(loud_clean, dt)
        flux = self.flux_gain.normalize(flux_raw, dt)

        adapt_coef = 1.0 - math.exp(-dt / p.onset_adaptive_window_s)
        self.kick_flux_mean += (kick_flux - self.kick_flux_mean) * adapt_coef
        self.kick_flux_mean_sq += (kick_flux * kick_flux - self.kick_flux_mean_sq) * adapt_coef
        variance = max(self.kick_flux_mean_sq - self.kick_flux_mean**2, 1e-12)
        gate = self.kick_flux_mean + p.onset_adaptive_k * math.sqrt(variance)
        threshold = max(gate, p.onset_gate_floor)
        silent = loudness < p.silence_loudness_max and shaped_bands[0] < p.silence_bass_max

        if silent:
            self.onset *= math.exp(-dt / (p.onset_release_tau * 0.65))
            self.refractory = max(0.0, self.refractory - dt)
        elif (
            kick_flux > threshold * p.onset_flux_margin
            and shaped_bands[0] > p.onset_bass_level_min
            and loudness > p.onset_loudness_min
            and self.refractory <= 0
        ):
            over = min(kick_flux / threshold, 3.5)
            self.onset = min(1.7, 0.72 + 0.32 * over)
            self.refractory = p.onset_refractory_s
        else:
            self.onset *= math.exp(-dt / p.onset_release_tau)
            self.refractory = max(0.0, self.refractory - dt)

        return {
            "bass": shaped_bands[0],
            "lowMid": shaped_bands[1],
            "mid": shaped_bands[2],
            "high": shaped_bands[3],
            "loudness": loudness,
            "onset": min(max(self.onset, 0.0), 1.7),
            "flux": flux,
            "kick_flux": kick_flux,
            "kick_gate": threshold,
        }


def _zero_features() -> dict[str, float]:
    return {k: 0.0 for k in ("bass", "lowMid", "mid", "high", "loudness", "onset", "flux", "kick_flux", "kick_gate")}


def read_f32le(path: Path, max_seconds: float | None = None) -> tuple[np.ndarray, float]:
    raw = path.read_bytes()
    samples = np.frombuffer(raw, dtype="<f4")
    rate = 48000.0
    if max_seconds is not None:
        samples = samples[: int(rate * max_seconds)]
    return samples, rate


def replay(
    samples: np.ndarray,
    sample_rate: float,
    hop: int,
    analyzer_profile: AnalyzerProfile,
    tv_profile: TVFollowProfile,
) -> dict[str, np.ndarray]:
    analyzer = BandAnalyzer(profile=analyzer_profile)
    n = len(samples)
    frames = (n + hop - 1) // hop
    t = np.zeros(frames)
    bass = np.zeros(frames)
    high = np.zeros(frames)
    onset_phone = np.zeros(frames)
    onset_tv = np.zeros(frames)
    bass_tv = np.zeros(frames)
    punch = np.zeros(frames)
    kick_flux = np.zeros(frames)

    o_smooth = 0.0
    b_smooth = 0.0
    h_smooth = 0.0
    last_seq_onset = 0.0
    armed = True
    last_trigger_t = -1e9
    threshold = kick_onset_trigger_threshold(tv_profile.sensitivity)
    rearm = kick_onset_rearm_threshold(tv_profile.sensitivity)
    strength = tv_profile.strength_pct / 100.0
    time_acc = 0.0

    for i in range(frames):
        start = i * hop
        block = samples[start : start + hop]
        dt = len(block) / sample_rate
        time_acc += dt
        t[i] = time_acc
        feats = analyzer.consume_block(block, sample_rate)
        bass[i] = feats["bass"]
        high[i] = feats["high"]
        onset_phone[i] = feats["onset"]
        kick_flux[i] = feats["kick_flux"]

        target_onset = feats["onset"]
        o_smooth = follow(o_smooth, target_onset, dt, tv_profile.onset_attack, tv_profile.onset_release)
        if target_onset > o_smooth:
            o_smooth = target_onset
        last_seq_onset = target_onset
        b_smooth = follow(b_smooth, feats["bass"], dt, tv_profile.bass_attack, tv_profile.bass_release)
        h_smooth = follow(h_smooth, feats["high"], dt, tv_profile.high_attack, tv_profile.high_release)

        drive_onset = hit(o_smooth, tv_profile.sensitivity, tv_profile.hit_cap, tv_profile.shaped_pow)
        drive_bass = hit(b_smooth, tv_profile.sensitivity, tv_profile.hit_cap, tv_profile.shaped_pow)
        drive_high = hit(h_smooth, tv_profile.sensitivity, tv_profile.hit_cap, tv_profile.shaped_pow)
        onset_tv[i] = drive_onset
        bass_tv[i] = drive_bass

        room_live = feats["loudness"] > 0.07 or feats["bass"] > 0.1
        peak = 0.0
        if strength > 0 and armed and room_live and drive_onset > threshold:
            if time_acc - last_trigger_t >= REFRACTORY_PUNCH:
                mag = kick_peak_magnitude(drive_onset, threshold, drive_bass) * strength
                if mag > 0.04:
                    peak = mag
                    last_trigger_t = time_acc
                    armed = False
        if drive_onset < rearm:
            armed = True
        punch[i] = peak

    return {
        "t": t,
        "bass": bass,
        "high": high,
        "onset_phone": onset_phone,
        "onset_tv": onset_tv,
        "bass_tv": bass_tv,
        "punch": punch,
        "kick_flux": kick_flux,
    }


def detect_onset_peaks(onset: np.ndarray, t: np.ndarray, min_height: float = 0.45, min_distance_s: float = 0.09) -> list[float]:
    peaks: list[float] = []
    last = -1e9
    for i in range(1, len(onset) - 1):
        if onset[i] >= min_height and onset[i] >= onset[i - 1] and onset[i] > onset[i + 1]:
            if t[i] - last >= min_distance_s:
                peaks.append(t[i])
                last = t[i]
    return peaks


def detect_punch_times(punch: np.ndarray, t: np.ndarray, min_val: float = 0.04) -> list[float]:
    times: list[float] = []
    for i in range(len(punch)):
        if punch[i] >= min_val and (i == 0 or punch[i - 1] < min_val):
            times.append(t[i])
    return times


def align_delays(onset_times: list[float], punch_times: list[float], window: float = 0.18) -> tuple[list[float], list[float], int]:
    """Returns (delays ms), (unmatched onset times), missed count."""
    delays: list[float] = []
    used: set[int] = set()
    unmatched: list[float] = []
    for ot in onset_times:
        best_j = -1
        best_d = window
        for j, pt in enumerate(punch_times):
            if j in used:
                continue
            d = pt - ot
            if 0 <= d <= window and d < best_d:
                best_d = d
                best_j = j
        if best_j >= 0:
            used.add(best_j)
            delays.append(best_d * 1000.0)
        else:
            unmatched.append(ot)
    missed = len(unmatched)
    return delays, unmatched, missed


def summarize(name: str, data: dict[str, np.ndarray]) -> dict:
    onset_peaks = detect_onset_peaks(data["onset_phone"], data["t"])
    punch_times = detect_punch_times(data["punch"], data["t"])
    delays, unmatched, missed = align_delays(onset_peaks, punch_times)
    mean_delay = float(np.mean(delays)) if delays else float("nan")
    quiet_bass = float(np.percentile(data["bass_tv"], 50))
    quiet_motion = float(np.percentile(data["bass_tv"], 90) - np.percentile(data["bass_tv"], 10))
    quiet_mask = data["bass"] < 0.55
    quiet_mean_bass_tv = float(np.mean(data["bass_tv"][quiet_mask])) if np.any(quiet_mask) else 0.0
    return {
        "label": name,
        "onset_peaks": len(onset_peaks),
        "punch_triggers": len(punch_times),
        "matched": len(delays),
        "missed_onsets": missed,
        "mean_delay_ms": mean_delay,
        "median_bass_tv": quiet_bass,
        "bass_tv_p90_p10": quiet_motion,
        "quiet_bass_tv_mean": quiet_mean_bass_tv,
        "unmatched_onset_times_s": unmatched[:12],
    }


def plot_before_after(
    out_png: Path,
    before: dict[str, np.ndarray],
    after: dict[str, np.ndarray],
    t_max: float = 12.0,
) -> None:
    import matplotlib.pyplot as plt

    mask_b = before["t"] <= t_max
    mask_a = after["t"] <= t_max
    fig, axes = plt.subplots(3, 1, figsize=(12, 8), sharex=True)
    ax0, ax1, ax2 = axes
    ax0.plot(before["t"][mask_b], before["bass_tv"][mask_b], label="bass TV (przed)", alpha=0.7, color="#c44")
    ax0.plot(after["t"][mask_a], after["bass_tv"][mask_a], label="bass TV (po)", alpha=0.9, color="#2a8")
    ax0.set_ylabel("bass (TV drive)")
    ax0.legend(loc="upper right")
    ax0.set_title("wz7 — replay offline BandAnalyzer + MicReceiver follow")

    ax1.plot(before["t"][mask_b], before["onset_phone"][mask_b], label="onset phone (przed)", alpha=0.6)
    ax1.plot(after["t"][mask_a], after["onset_phone"][mask_a], label="onset phone (po)", alpha=0.9)
    ax1.plot(before["t"][mask_b], before["punch"][mask_b], label="punch TV (przed)", color="#c44", alpha=0.5)
    ax1.plot(after["t"][mask_a], after["punch"][mask_a], label="punch TV (po)", color="#2a8", alpha=0.8)
    ax1.set_ylabel("onset / punch")

    ax2.plot(before["t"][mask_b], before["kick_flux"][mask_b], label="kick flux (przed)", alpha=0.5)
    ax2.plot(after["t"][mask_a], after["kick_flux"][mask_a], label="kick flux (po)", alpha=0.8)
    ax2.set_ylabel("kick flux")
    ax2.set_xlabel("czas [s]")
    ax2.legend(loc="upper right")
    fig.tight_layout()
    out_png.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_png, dpi=140)
    plt.close(fig)


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--audio",
        type=Path,
        default=Path("/tmp/wz7_mono.f32"),
        help="mono f32le @ 48 kHz (ffmpeg -f f32le)",
    )
    parser.add_argument("--hop", type=int, default=512, help="tap buffer size (phone default 512)")
    parser.add_argument("--plot-seconds", type=float, default=14.0, help="window for PNG")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path("docs/wz7-replay"),
    )
    parser.add_argument("--extract-from", type=Path, help="mp4/m4a → f32le via ffmpeg")
    args = parser.parse_args(list(argv) if argv is not None else None)

    audio_path = args.audio
    if args.extract_from:
        audio_path = args.out_dir / "wz7_mono.f32"
        args.out_dir.mkdir(parents=True, exist_ok=True)
        import subprocess

        subprocess.run(
            [
                "ffmpeg",
                "-y",
                "-i",
                str(args.extract_from),
                "-vn",
                "-ac",
                "1",
                "-ar",
                "48000",
                "-f",
                "f32le",
                str(audio_path),
            ],
            check=True,
            capture_output=True,
        )

    if not audio_path.is_file():
        print(f"missing audio: {audio_path}", file=sys.stderr)
        return 1

    samples, rate = read_f32le(audio_path)
    before = replay(samples, rate, args.hop, PROFILE_BEFORE, TV_BEFORE)
    after = replay(samples, rate, args.hop, PROFILE_AFTER, TV_AFTER)
    summary_before = summarize("before", before)
    summary_after = summarize("after", after)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    report = {
        "audio": str(audio_path),
        "hop": args.hop,
        "duration_s": len(samples) / rate,
        "before": summary_before,
        "after": summary_after,
        "root_causes": [
            "TV follow bass attack ~6 ms + release 240 ms → ruch basu za telefonem przy spokojnej muzyce.",
            "Normalizer bez wolnej średniej 3–5 s → cichsze partie nie podnoszą bass_tv mimo max Sensitivity.",
            "Bramka onset μ+k·σ + bass/loudness min + refractory 120 ms → część kicków w wz7 poniżej progu (miss).",
            "Onset TV: follow 2 ms + max() na nowym pakiecie OK; opóźnienie punch ≈ follow + próg BeatPunch, nie UDP.",
            "AGC PCM (τ~280 ms) nie wpływa na cechy UDP — lag obrazu z continuous bass to głównie follow + AGC na ścieżce PCM.",
        ],
    }
    json_path = args.out_dir / "wz7_report.json"
    json_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    plot_before_after(args.out_dir / "wz7_before_after.png", before, after, t_max=args.plot_seconds)

    print(json.dumps(report, indent=2))
    print(f"\nWrote {json_path} and {args.out_dir / 'wz7_before_after.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
