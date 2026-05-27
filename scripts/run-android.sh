#!/usr/bin/env bash
# Build video_processor_core for Android and run the flutter_video_processor example.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="${ROOT}/packages/flutter_video_processor/example"
DEVICE="${1:-}"
BUILD_ALL_ABIS=0
if [[ "${1:-}" == "--all" ]]; then
  BUILD_ALL_ABIS=1
  DEVICE="${2:-}"
fi

echo "==> Building libvideo_processor_core.so (Android NDK + FFmpeg)"
if [[ "${BUILD_ALL_ABIS}" -eq 1 ]]; then
  "${ROOT}/scripts/package-video-android.sh" --all
else
  "${ROOT}/scripts/package-video-android.sh"
fi

echo "==> Clearing Flutter hook cache (not jniLibs — just rebuilt)"
rm -rf "${ROOT}/packages/video_processor_core/rust/target/rust_hook"

echo "==> flutter clean (example)"
cd "${EXAMPLE}"
flutter clean

export VFP_USE_PREBUILT_JNI=1

if [[ -n "${DEVICE}" ]]; then
  echo "==> flutter run -d ${DEVICE}"
  flutter run -d "${DEVICE}"
else
  echo "==> flutter run (first connected device)"
  flutter run
fi
