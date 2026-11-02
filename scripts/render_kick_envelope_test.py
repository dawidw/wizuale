#!/usr/bin/env python3
"""Offline PNG check for kick-wave UV displacement at envelope 0 / 0.5 / 1.0 (Siła=100%)."""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

RING_FREQ = 18.0
PHASE_SPEED = 18.0
RING_FALLOFF = 0.85
MAX_DISP = 0.12
KICK_AGE = 0.08
STRENGTH = 1.0
SIZE = 256


def displacement(u: float, v: float, aspect: float, envelope: float) -> float:
    px = (u - 0.5) * aspect
    py = v - 0.5
    r = math.hypot(px, py)
    phase = KICK_AGE * PHASE_SPEED
    ring = math.sin(r * RING_FREQ - phase)
    ring *= math.exp(-r * RING_FALLOFF)
    ring *= envelope
    return ring * STRENGTH * MAX_DISP


def write_png(path: Path, envelope: float) -> None:
    aspect = 16 / 9
    rows = []
    for y in range(SIZE):
        row = bytearray([0])
        for x in range(SIZE):
            u = x / (SIZE - 1)
            v = y / (SIZE - 1)
            d = displacement(u, v, aspect, envelope)
            # Map signed displacement to grayscale around mid gray.
            g = int(max(0, min(255, 128 + d * 900)))
            row.extend([g, g, g])
        rows.append(bytes(row))
    raw = b"".join(rows)
    compressed = zlib.compress(raw, 9)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", compressed) + chunk(b"IEND", b"")
    path.write_bytes(png)


def main() -> None:
    out = Path(__file__).resolve().parent.parent / "docs" / "kick-envelope-test"
    out.mkdir(parents=True, exist_ok=True)
    for env in (0.0, 0.5, 1.0):
        write_png(out / f"envelope_{env:.1f}.png", env)
    print(f"Wrote PNGs to {out}")


if __name__ == "__main__":
    main()
