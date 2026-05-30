#!/usr/bin/env bash
# Copy locally built Rust cdylib into plugin paths for development.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROFILE="${1:-debug}"

case "$(uname -s)" in
  Darwin)
    LIB="${ROOT}/target/release/libvideo_processor_core.dylib"
    mkdir -p "${ROOT}/packages/flutter_video_processor/macos"
    cp "${LIB}" "${ROOT}/packages/flutter_video_processor/macos/" 2>/dev/null || true
    ;;
  Linux)
    LIB="${ROOT}/target/release/libvideo_processor_core.so"
    mkdir -p "${ROOT}/packages/flutter_video_processor/linux"
    cp "${LIB}" "${ROOT}/packages/flutter_video_processor/linux/"
    ;;
esac

echo "Copied ${LIB} for local development. Run: cargo build --release -p video_processor_core"
