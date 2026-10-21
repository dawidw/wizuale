#!/usr/bin/env bash
# Builds a static libprojectM 4.x for tvOS (device + simulator) and packages
# ThirdParty/projectm-tvos.xcframework for the Wizuale Xcode target.
#
# Prerequisites (macOS):
#   xcode-select, cmake (>= 3.21), ninja, git
#   brew install cmake ninja
#
# Usage (from repo root):
#   ./scripts/build-projectm-tvos.sh
#   ./scripts/build-projectm-tvos.sh --tag v4.2.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/ThirdParty"
SRC="$VENDOR/projectm-src"
OUT="$VENDOR/projectm-tvos.xcframework"
HEADERS_DST="$VENDOR/projectm/include"
BUILD_ROOT="$VENDOR/projectm-build"
TAG="master"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--tag v4.2.0]"
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$VENDOR" "$BUILD_ROOT" "$HEADERS_DST"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 --branch "$TAG" https://github.com/projectM-visualizer/projectm.git "$SRC" 2>/dev/null \
    || git clone --depth 1 https://github.com/projectM-visualizer/projectm.git "$SRC"
else
  git -C "$SRC" fetch --depth 1 origin "$TAG" 2>/dev/null || true
  git -C "$SRC" checkout "$TAG" 2>/dev/null || git -C "$SRC" checkout master
fi

echo "==> Installing API headers to $HEADERS_DST"
rm -rf "$HEADERS_DST/projectM-4"
cp -R "$SRC/src/api/include/projectM-4" "$HEADERS_DST/"

build_one() {
  local SDK="$1"
  local PLATFORM="$2"
  local ARCH="$3"
  local BUILD_DIR="$BUILD_ROOT/$SDK-$ARCH"
  local SYSROOT
  SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"

  cmake -S "$SRC" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=tvOS \
    -DCMAKE_OSX_SYSROOT="$SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_PLAYLIST=OFF \
    -DENABLE_SDL_UI=OFF \
    -DENABLE_INSTALL=OFF \
    -DENABLE_GLES=ON \
    -DENABLE_SYSTEM_PROJECTM_EVAL=OFF \
    -DBUILD_TESTING=OFF

  cmake --build "$BUILD_DIR" --target projectM
  echo "$BUILD_DIR/src/libprojectM/libprojectM.a"
}

echo "==> Building for appletvos (device)"
LIB_DEVICE="$(build_one appletvos os arm64)"

echo "==> Building for appletvsimulator"
LIB_SIM="$(build_one appletvsimulator simulator arm64)"

STAGE="$BUILD_ROOT/xcframework-stage"
rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE/device" "$STAGE/simulator/lib" "$STAGE/simulator/Headers"

cp "$LIB_DEVICE" "$STAGE/device/libprojectM.a"
mkdir -p "$STAGE/device/Headers"
cp -R "$HEADERS_DST/projectM-4" "$STAGE/device/Headers/"

cp "$LIB_SIM" "$STAGE/simulator/lib/libprojectM.a"
cp -R "$HEADERS_DST/projectM-4" "$STAGE/simulator/Headers/"

# Xcode xcframework from static libs
xcodebuild -create-xcframework \
  -library "$STAGE/device/libprojectM.a" -headers "$STAGE/device/Headers" \
  -library "$STAGE/simulator/lib/libprojectM.a" -headers "$STAGE/simulator/Headers" \
  -output "$OUT"

echo ""
echo "Done: $OUT"
echo "Headers: $HEADERS_DST"
echo "Open Wizuale.xcodeproj and build scheme Wizuale for tvOS."
