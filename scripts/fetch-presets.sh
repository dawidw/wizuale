#!/usr/bin/env bash
# Installs Dawid's curated 50 MilkDrop presets (selected.json) plus texture pack,
# and refreshes manifest.json (MilkDrop group). Study of Space .milk files stay in-repo.
#
#   ./scripts/fetch-presets.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Wizuale/Resources/Presets"
FILES="$DEST/files"
TEX="$DEST/textures"
THUMBS="$DEST/thumbs"
MANIFEST="$DEST/manifest.json"
SELECTED_JSON="$DEST/selected.json"
SOS_MANIFEST="$DEST/sos-manifest.json"

if [[ ! -f "$SELECTED_JSON" ]]; then
  echo "Missing $SELECTED_JSON (curated list with paths into cream-of-the-crop)."
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Cloning preset packs (shallow)"
git clone --depth 1 https://github.com/projectM-visualizer/presets-cream-of-the-crop.git "$TMP/cream"
git clone --depth 1 https://github.com/projectM-visualizer/presets-milkdrop-texture-pack.git "$TMP/textures"

mkdir -p "$FILES" "$TEX" "$THUMBS"

echo "==> Removing old bundled .milk (keeping Study of Space originals)"
find "$FILES" -maxdepth 1 -name '*.milk' ! -name 'Study of Space - *.milk' -delete 2>/dev/null || true

echo "==> Copying 50 curated presets (byte-for-byte from cream-of-the-crop)"
python3 - "$TMP/cream" "$FILES" "$THUMBS" "$SELECTED_JSON" <<'PY'
import json, os, shutil, sys
cream, files_dir, thumbs_dir, selected_path = sys.argv[1:5]
with open(selected_path, encoding="utf-8") as f:
    entries = json.load(f)
for row in entries:
    rel = row["path"]
    src = os.path.join(cream, rel)
    if not os.path.isfile(src):
        raise SystemExit(f"missing preset in cream-of-the-crop: {rel}")
    base = os.path.basename(rel)
    shutil.copy2(src, os.path.join(files_dir, base))
    thumb_src = row.get("thumb")
    if thumb_src:
        # thumb paths in selected.json are relative to the zip root (selected/NN.png)
        zip_thumb = os.path.join(os.path.dirname(selected_path), thumb_src)
        if os.path.isfile(zip_thumb):
            stem = os.path.splitext(base)[0]
            shutil.copy2(zip_thumb, os.path.join(thumbs_dir, stem + ".png"))
print(len(entries), "presets copied")
PY

echo "==> Copying texture pack"
rm -rf "$TMP/textures/.git"
cp -R "$TMP/textures"/. "$TEX/"

echo "==> Writing manifest.json (50 MilkDrop + Study of Space group)"
python3 - "$FILES" "$THUMBS" "$MANIFEST" "$SOS_MANIFEST" "$SELECTED_JSON" <<'PY'
import json, os, sys
files_dir, thumbs_dir, manifest_path, sos_manifest_path, selected_path = sys.argv[1:6]
with open(selected_path, encoding="utf-8") as f:
    selected = json.load(f)

presets = []
idx = 0
for row in selected:
    base = os.path.basename(row["path"])
    stem = os.path.splitext(base)[0]
    thumb_png = os.path.join(thumbs_dir, stem + ".png")
    thumb_jpg = os.path.join(thumbs_dir, stem + ".jpg")
    thumb_field = None
    if os.path.isfile(thumb_png):
        thumb_field = f"thumbs/{stem}.png"
    elif os.path.isfile(thumb_jpg):
        thumb_field = f"thumbs/{stem}.jpg"
    entry = {"id": idx, "name": stem, "file": f"files/{base}", "group": "MilkDrop"}
    if thumb_field:
        entry["thumb"] = thumb_field
    presets.append(entry)
    idx += 1

sos = []
if os.path.isfile(sos_manifest_path):
    with open(sos_manifest_path, encoding="utf-8") as f:
        sos = json.load(f).get("presets", [])

for row in sos:
    entry = dict(row)
    entry["id"] = idx
    entry.setdefault("group", "Study of Space")
    presets.append(entry)
    idx += 1

doc = {
    "source": "presets-cream-of-the-crop (curated 50) + Study of Space",
    "count": len(presets),
    "presets": presets,
}
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print(len(presets), "entries in manifest")
PY

echo "Presets installed under $DEST"
