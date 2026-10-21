#!/usr/bin/env bash
# Downloads a curated subset of stock projectM presets + Milkdrop textures into the TV app bundle.
#
#   ./scripts/fetch-presets.sh              # ~100 presets from cream-of-the-crop
#   ./scripts/fetch-presets.sh --count 120
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Wizuale/Resources/Presets"
FILES="$DEST/files"
TEX="$DEST/textures"
MANIFEST="$DEST/manifest.json"
COUNT=100

while [[ $# -gt 0 ]]; do
  case "$1" in
    --count) COUNT="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--count N]"; exit 0 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Cloning preset packs (shallow)"
git clone --depth 1 https://github.com/projectM-visualizer/presets-cream-of-the-crop.git "$TMP/cream"
git clone --depth 1 https://github.com/projectM-visualizer/presets-milkdrop-texture-pack.git "$TMP/textures"

mkdir -p "$FILES" "$TEX"
rm -f "$FILES"/*.milk "$FILES"/*.milk2 2>/dev/null || true

echo "==> Selecting $COUNT .milk files (sorted, stable order)"
find "$TMP/cream" -iname '*.milk' | LC_ALL=C sort | head -n "$COUNT" | while read -r path; do
  base="$(basename "$path")"
  cp "$path" "$FILES/$base"
done

echo "==> Copying texture pack"
cp -R "$TMP/textures"/. "$TEX/" 2>/dev/null || cp -R "$TMP/textures"/* "$TEX/" || true

echo "==> Writing manifest.json"
python3 - <<PY
import json, os
files_dir = "$FILES"
entries = []
for i, name in enumerate(sorted(f for f in os.listdir(files_dir) if f.lower().endswith(('.milk', '.milk2')))):
    stem = os.path.splitext(name)[0]
    entries.append({"id": i, "name": stem, "file": f"files/{name}"})
with open("$MANIFEST", "w", encoding="utf-8") as f:
    json.dump({"source": "presets-cream-of-the-crop", "count": len(entries), "presets": entries}, f, indent=2)
print(len(entries), "presets")
PY

echo "Presets installed under $DEST"
