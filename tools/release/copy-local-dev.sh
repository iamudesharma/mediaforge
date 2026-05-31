#!/usr/bin/env bash
# Copy locally built Rust cdylib into plugin paths for development.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILE="${1:-debug}"

case "$(uname -s)" in
  Darwin)
    LIB="${ROOT}/target/release/libvideo_forge.dylib"
    mkdir -p "${ROOT}/packages/video_forge_kit/macos"
    cp "${LIB}" "${ROOT}/packages/video_forge_kit/macos/" 2>/dev/null || true
    ;;
  Linux)
    LIB="${ROOT}/target/release/libvideo_forge.so"
    mkdir -p "${ROOT}/packages/video_forge_kit/linux"
    cp "${LIB}" "${ROOT}/packages/video_forge_kit/linux/"
    ;;
esac

echo "Copied ${LIB} for local development. Run: cargo build --release -p video_forge"
