#!/usr/bin/env python3
"""Offline check: bass-dominant continuous vs weaker kick accent (mirrors MicSceneModulation)."""

from __future__ import annotations

import math

CONT_BASE = 0.88
KICK_SENS_BASE = 0.20
KICK_PCM_BASE = 0.16
KICK_UV_MAX = 0.058
CONT_CEIL = 10.0
KICK_CEIL = 2.4


def soft_saturate(value: float, ceiling: float) -> float:
    if value <= 0:
        return 0.0
    return ceiling * math.tanh(value / ceiling)


def scene_sensitivity(base: float, kick_boost: float, cont_boost: float) -> float:
    combined = base + soft_saturate(cont_boost, CONT_CEIL) + soft_saturate(kick_boost, KICK_CEIL)
    return max(0.25, min(combined, CONT_CEIL))


def modulation(
    *,
    bass: float,
    env: float,
    strength: float,
    intensity: float,
    base: float = 1.0,
) -> tuple[float, float, float, float]:
    kick_boost = env * KICK_SENS_BASE * strength * intensity
    cont_boost = min(max(bass, 0), 2.8) * CONT_BASE * intensity
    sens = scene_sensitivity(base, kick_boost, cont_boost)
    pcm = env * KICK_PCM_BASE * strength * intensity
    uv = env * strength * KICK_UV_MAX
    return sens, cont_boost, kick_boost, pcm, uv


def main() -> None:
    intensity = 20.0  # 2000 ‰
    strength = 0.85
    bass_room = 0.75
    env_kick = 0.55

    _, cont_boost, kick_boost, pcm, uv = modulation(
        bass=bass_room, env=0.0, strength=strength, intensity=intensity
    )
    assert cont_boost > 10, "continuous boost should be strong at 20×"
    assert kick_boost == 0

    sens_idle, _, _, _, _ = modulation(
        bass=bass_room, env=0.0, strength=strength, intensity=intensity
    )
    sens_hit, _, kick_hit, pcm_hit, uv_hit = modulation(
        bass=bass_room, env=env_kick, strength=strength, intensity=intensity
    )
    assert sens_hit >= sens_idle * 0.85, "kick must not erase continuous sensitivity"
    ratio = cont_boost / max(kick_hit, 1e-6)
    assert ratio > 4.0, f"bass path should dominate kick sensitivity ({ratio:.1f})"
    assert pcm_hit < cont_boost * 0.35, "PCM kick accent smaller than continuous boost"
    assert uv_hit < 0.04, "tsunami UV stays subordinate to preset zoom"

    print(
        f"OK @20× intensity, bass={bass_room:.2f}, kick env={env_kick:.2f}: "
        f"cont boost {cont_boost:.2f}, kick boost {kick_hit:.2f}, "
        f"ratio {ratio:.1f}×, sens idle→hit {sens_idle:.2f}→{sens_hit:.2f}, "
        f"PCM {pcm_hit:.3f}, UV {uv_hit:.3f}"
    )


if __name__ == "__main__":
    main()
