#!/usr/bin/env python3
"""Rasterize Study of Space generator SVGs into Mic preset thumbnails (480x270 JPEG)."""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
GEN = pathlib.Path("/tmp/studyofspace/poster-bg/scripts/gen.js")
THUMBS = ROOT / "Wizuale/Resources/Presets/thumbs"
SOS = ROOT / "Wizuale/Resources/Presets/sos-manifest.json"

# motif + palette per new preset (matches studyofspace.gallery generator)
NEW = {
    "Study of Space - Mosaic": ("mosaic", "roger"),
    "Study of Space - Halo Blob": ("blob", "anima"),
    "Study of Space - Triangles": ("diagonals", "bauhaus"),
    "Study of Space - Steps": ("steps", "cyrk"),
    "Study of Space - Constructivist": ("construct", "konstruktywizm"),
    "Study of Space - Paper Cutout": ("cutout", "lenica"),
    "Study of Space - Organic Rhythm": ("jarema", "jarema"),
    "Study of Space - Wooden Relief": ("relief", "golkowska"),
    "Study of Space - Woven Strips": ("weave", "abakan"),
}

EXISTING = {
    "Study of Space - Fangor Rings": ("fangor", "fangor"),
    "Study of Space - Soft Ring": ("ring", "soft_orchid"),
    "Study of Space - Soft Squares Orchid": ("squares", "soft_orchid"),
    "Study of Space - Soft Squares Sunset": ("squares", "soft_sunset"),
    "Study of Space - Dream": ("dream", "dream_sunset"),
    "Study of Space - Oscillogram": ("scope", "zamecznik"),
    "Study of Space - Stripes and Disc": ("stripedisc", "stanczak"),
    "Study of Space - Neon Multiply and Rotate": ("rotor", "neon"),
    "Study of Space - Wavy Stripes": ("stripewave", "stanczak"),
    "Study of Space - Block Letters": ("letters", "blok"),
    "Study of Space - Unism": ("unism", "konstruktywizm"),
    "Study of Space - Election Constructivism": ("blok", "blok"),
    "Study of Space - Spatial Planes": ("planes", "kobro"),
    "Study of Space - Outlined Stains": ("outline", "mlodozeniec"),
    "Study of Space - Rhythm Bars": ("bars", "jazz"),
    "Study of Space - Sunburst and Rings": ("sunburst", "cyrk"),
    "Study of Space - Halftone": ("halftone", "mono"),
    "Study of Space - Moire": ("moire", "kobalt"),
    "Study of Space - Stripes Baron": ("stripes", "baron"),
    "Study of Space - Split Rings": ("rings", "brasilia"),
}


def render(name: str, motif: str, palette: str) -> None:
    out_svg = THUMBS / f"{name}.svg"
    out_jpg = THUMBS / f"{name}.jpg"
    subprocess.run(
        [
            "node",
            str(GEN),
            "--motif",
            motif,
            "--palette",
            palette,
            "--seed",
            "7",
            "--size",
            "480x270",
            "--out",
            str(out_svg),
        ],
        check=True,
        capture_output=True,
    )
    png = out_jpg.with_suffix(".png")
    subprocess.run(
        ["rsvg-convert", "-w", "480", "-h", "270", "-f", "png", str(out_svg), "-o", str(png)],
        check=True,
        capture_output=True,
    )
    from PIL import Image

    Image.open(png).convert("RGB").save(out_jpg, "JPEG", quality=88)
    png.unlink(missing_ok=True)
    out_svg.unlink(missing_ok=True)
    print("thumb", out_jpg.name)


def main() -> None:
    if not GEN.is_file():
        raise SystemExit(f"Clone studyofspace first; missing {GEN}")
    THUMBS.mkdir(parents=True, exist_ok=True)
    targets = {**EXISTING, **NEW}
    with open(SOS, encoding="utf-8") as f:
        manifest = json.load(f)
    for row in manifest["presets"]:
        title = row["name"].removesuffix(".milk")
        if title not in targets:
            continue
        out_jpg = THUMBS / f"{title}.jpg"
        if title not in NEW and out_jpg.is_file():
            continue
        render(title, *targets[title])


if __name__ == "__main__":
    main()
