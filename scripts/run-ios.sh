#!/usr/bin/env bash
# Build video_forge for iOS and run the video_forge_kit example.
# Run from repo root: ./scripts/run-ios.sh [optional flutter device id]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${ROOT}/tools"
EXAMPLE="${ROOT}/packages/video_forge_kit/example"
DEVICE_ID="${IOS_DEVICE_ID:-${1:-}}"

if [[ ! -d "${EXAMPLE}" ]]; then
  echo "Example app not found at ${EXAMPLE}" >&2
  exit 1
fi

export PATH="${HOME}/.cargo/bin:${PATH}"

if [[ -z "${DEVICE_ID}" ]]; then
  DEVICE_ID="$(cd "${EXAMPLE}" && flutter devices 2>/dev/null | grep 'ios' | grep -v simulator | head -1 | awk '{print $NF}' | tr -d '•' || true)"
fi

FFMPEG_DIST="${TOOLS}/ffmpeg/dist/apple/aarch64-apple-ios"
if [[ ! -d "${FFMPEG_DIST}/lib" ]] || [[ "${FORCE_FFMPEG_IOS_REBUILD:-}" == "1" ]]; then
  echo "==> Building FFmpeg for iOS device (~10–20 min)..."
  chmod +x "${TOOLS}/ffmpeg/apple-ios-device.sh"
  "${TOOLS}/ffmpeg/apple-ios-device.sh"
elif [[ ! -f "${FFMPEG_DIST}/HWACCEL_FEATURES" ]]; then
  echo "==> iOS FFmpeg predates h264_videotoolbox hwaccel fix; rebuilding..."
  "${TOOLS}/ffmpeg/apple-ios-device.sh"
fi

echo "==> Packaging iOS framework..."
chmod +x "${TOOLS}/release/package-ios-framework.sh"
"${TOOLS}/release/package-ios-framework.sh"

# Make the packaged framework binary's install name match the loader
# expectations (@rpath/video_forge.framework/video_forge). Without this,
# prebuilt framework binaries that were built on a different host can
# carry an absolute / wrong @rpath and the iOS loader will fail with
# "image not found" at app launch.
FRAMEWORK_BIN="${ROOT}/packages/video_forge/ios/Frameworks/video_forge.framework/video_forge"
if [[ -f "${FRAMEWORK_BIN}" ]]; then
  echo "==> Setting framework install name to @rpath/video_forge.framework/video_forge"
  install_name_tool -id "@rpath/video_forge.framework/video_forge" "${FRAMEWORK_BIN}"
fi

echo "==> Flutter pub get (workspace)..."
(cd "${ROOT}" && dart pub get && dart run melos bootstrap)

echo "==> Flutter pub get (example)..."
cd "${EXAMPLE}"
flutter pub get

echo "==> CocoaPods install..."
(cd ios && pod install)

echo "==> Clean iOS build (drops stale CodeAsset dylibs with Mac paths)..."
flutter clean

echo "==> Running on iOS device..."
if [[ -n "${DEVICE_ID}" ]]; then
  flutter run -d "${DEVICE_ID}" --release
else
  flutter run -d ios --release
fi
