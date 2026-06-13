#!/usr/bin/env bash
# Build video_forge + media_forge native libs, then run video_forge_editor example on macOS.
#
# Usage (from repo root):
#   bash scripts/run-video-editor-macos.sh
#   bash scripts/run-video-editor-macos.sh --no-rebuild   # flutter only
#
# First-time (no VT FFmpeg yet):
#   bash scripts/build-ffmpeg-macos-vt.sh
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${REPO_ROOT}/packages/video_forge_editor/example"
REBUILD_SCRIPT="${REPO_ROOT}/scripts/rebuild-video-native-macos.sh"
MEDIA_SCRIPT="${REPO_ROOT}/scripts/run-rust-media-macos.sh"

SKIP_REBUILD=0
FLUTTER_ARGS=()
for arg in "$@"; do
  case "${arg}" in
    --no-rebuild) SKIP_REBUILD=1 ;;
    *) FLUTTER_ARGS+=("${arg}") ;;
  esac
done

if [[ ! -f "${APP}/lib/main.dart" ]]; then
  echo "ERROR: video_forge_editor example not found at ${APP}/lib/main.dart" >&2
  exit 1
fi

if [[ "${SKIP_REBUILD}" -eq 0 ]]; then
  echo "==> Rebuilding video_forge native libs"
  bash "${REBUILD_SCRIPT}"

  echo "==> Rebuilding media_forge (playback + overlay audio)"
  # run-rust-media-macos.sh ends with flutter run — extract build steps only.
  TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"
  PKG="${REPO_ROOT}/packages/media_forge"
  FFMPEG_DIR="${FFMPEG_DIR:-${HOME}/.cache/rust_image/ffmpeg-macos-vt}"
  if [[ ! -f "${FFMPEG_DIR}/include/libavutil/avutil.h" ]]; then
    if command -v brew >/dev/null 2>&1 && [[ -f "$(brew --prefix ffmpeg 2>/dev/null)/include/libavutil/avutil.h" ]]; then
      FFMPEG_DIR="$(brew --prefix ffmpeg)"
      echo "==> WARN: Using Homebrew FFmpeg at ${FFMPEG_DIR}"
    else
      echo "ERROR: Set FFMPEG_DIR or run: bash scripts/build-ffmpeg-macos-vt.sh" >&2
      exit 1
    fi
  fi
  export FFMPEG_DIR
  export PKG_CONFIG_PATH="${FFMPEG_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
  (
    cd "${PKG}/rust"
    cargo build --release --target "${TRIPLE}"
  )
  rm -rf "${APP}/build" "${APP}/.dart_tool/flutter_build"
else
  echo "==> Skipping native rebuild (--no-rebuild)"
fi

echo "==> CocoaPods"
(cd "${APP}/macos" && pod install)

cd "${APP}"
if ((${#FLUTTER_ARGS[@]} > 0)); then
  exec flutter run -d macos "${FLUTTER_ARGS[@]}"
else
  exec flutter run -d macos
fi
