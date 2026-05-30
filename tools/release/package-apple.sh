#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ROOT}/platform-build"
APPLE_BUILD="${ROOT}/tools/ffmpeg/build/apple"
mkdir -p "${OUT}"

# Package prebuilt slices into XCFramework (requires lipo/xcodebuild on macOS)
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Apple packaging requires macOS" >&2
  exit 1
fi

FRAMEWORK="${OUT}/VideoProcessorCore.xcframework"
LIB_NAME="libvideo_processor_core.a"

# Build Rust static libs for Apple targets
cd "${ROOT}/native/rust_core"
for triple in aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin; do
  cargo build --release --target "${triple}"
done

echo "Rust Apple artifacts built. Merge with FFmpeg slices and create XCFramework manually or via xcodebuild."
echo "Output directory: ${OUT}"
