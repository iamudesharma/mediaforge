#!/usr/bin/env bash
# Build video_processor_core for Android and run the media_studio example.
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="${ROOT}/examples/media_studio"
DEVICE="${1:-}"
BUILD_ALL_ABIS=0
if [[ "${1:-}" == "--all" ]]; then
  BUILD_ALL_ABIS=1
  DEVICE="${2:-}"
fi

echo "==> Prebuild rust_image_core (arm64, avoids Gradle OOM)"
bash "${ROOT}/scripts/rebuild-rust-image-android.sh"

echo "==> Building libvideo_processor_core.so (Android NDK + FFmpeg)"
if [[ "${BUILD_ALL_ABIS}" -eq 1 ]]; then
  "${ROOT}/scripts/package-video-android.sh" --all
else
  "${ROOT}/scripts/package-video-android.sh"
fi

echo "==> Clearing Flutter hook cache (not jniLibs — just rebuilt)"
rm -rf "${ROOT}/packages/video_processor_core/rust/target/rust_hook"
# Stale x86_64 rust_image_core artifacts break rebuilds after ABI narrowing.
rm -rf "${EXAMPLE}/build/rust_image_core"

echo "==> flutter clean (example)"
cd "${EXAMPLE}"
flutter clean

export VFP_USE_PREBUILT_JNI=1

FLUTTER_ARGS=(--target-platform android-arm64)
if [[ -n "${DEVICE}" ]]; then
  echo "==> flutter run -d ${DEVICE} (arm64 only)"
  flutter run -d "${DEVICE}" "${FLUTTER_ARGS[@]}"
else
  echo "==> flutter run (first connected device, arm64 only)"
  flutter run "${FLUTTER_ARGS[@]}"
fi
