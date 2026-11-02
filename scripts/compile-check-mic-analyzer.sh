#!/usr/bin/env bash
# Typecheck Mic tuning/analyzer paths on macOS (Float + Double literals).
# Linux CI: run the Python replay + float audit only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Python offline replays"
python3 scripts/simulate_beat_punch_kicks.py
python3 scripts/simulate_scene_modulation_mix.py
python3 scripts/replay_band_analyzer.py --extract-from "${WZ7_VIDEO:-/dev/null}" 2>/dev/null \
  || python3 scripts/replay_band_analyzer.py --audio /tmp/wz7_mono.f32 2>/dev/null \
  || true

if [[ -f /tmp/wz7_mono.f32 ]]; then
  echo "==> wz7 motion proxy (auto-advance @ ~32 s)"
  python3 scripts/replay_wz7_motion_proxy.py /tmp/wz7_mono.f32 --plot docs/wz7-motion-proxy.png
fi

echo "==> Float/Double assignment audit (MicTuning kick thresholds)"
python3 - <<'PY'
import re
import sys
from pathlib import Path

root = Path("Shared")
issues = []
pat = re.compile(
    r"return\s+high\s*-\s*norm\s*\*\s*\(\s*high\s*-\s*low\s*\)",
)
for path in (root / "MicTuning.swift", root / "MicAnalyzer.swift"):
    text = path.read_text(encoding="utf-8")
    if "kickOnsetTriggerThreshold" in text:
        block = text.split("kickOnsetTriggerThreshold", 1)[1].split("}", 1)[0]
        if "Double" in block and "Float" in block.split("return", 1)[0]:
            issues.append(f"{path}: mixed Double/Float in kick threshold block")
    for i, line in enumerate(text.splitlines(), 1):
        if ": Float" in line and re.search(r"=\s*0\.\d+\s*$", line):
            pass  # ok
        if re.search(r"let\s+\w+:\s*Float\s*=.*Double\(", line):
            issues.append(f"{path}:{i}: Float var from Double() without Float()")

if issues:
    print("\n".join(issues), file=sys.stderr)
    sys.exit(1)
print("Float/Double audit: OK")
PY

if command -v xcodebuild >/dev/null 2>&1; then
  echo "==> xcodebuild (tvOS + iOS Mic)"
  xcodebuild -scheme Wizuale -destination 'generic/platform=tvOS' -quiet build
  xcodebuild -scheme "Wizuale Mic" -destination 'generic/platform=iOS Simulator' -quiet build
  echo "xcodebuild: OK"
else
  echo "xcodebuild not found — skip native compile (see ThirdParty/README.md)"
fi
