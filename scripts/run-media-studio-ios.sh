#!/usr/bin/env bash
# Run Media Studio on a physical iOS device.
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${ROOT}/examples/media_studio"
DEVICE="${1:-}"

echo "==> Prebuild rust_image_core (iOS device)"
bash "${ROOT}/scripts/rebuild-rust-image-ios.sh"

if [[ -f "${ROOT}/tools/release/package-ios-framework.sh" ]]; then
  FFMPEG_DIST="${ROOT}/tools/ffmpeg/dist/apple/aarch64-apple-ios"
  if [[ -d "${FFMPEG_DIST}/lib" ]]; then
    echo "==> Package video_processor_core.framework"
    chmod +x "${ROOT}/tools/release/package-ios-framework.sh"
    "${ROOT}/tools/release/package-ios-framework.sh"
  else
    echo "==> Skip video framework (no iOS FFmpeg at ${FFMPEG_DIST})"
    echo "    Run: tools/ffmpeg/apple-ios-device.sh"
  fi
fi

echo "==> Clean stale iOS rust artifacts (macOS .a must not be reused)"
rm -rf "${APP}/build/ios"

cd "${APP}"
flutter pub get
(cd ios && pod install)

if [[ -n "${DEVICE}" ]]; then
  echo "==> flutter run -d ${DEVICE}"
  exec flutter run -d "${DEVICE}"
else
  echo "==> flutter run (first iOS device)"
  exec flutter run
fi
