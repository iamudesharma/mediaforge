#!/usr/bin/env bash
# Rebuild video_processor_core Rust + FRB bindings, then refresh the macOS Flutter app.
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VP="${REPO_ROOT}/packages/video_processor_core"
RIC="${REPO_ROOT}/packages/rust_image_core"
RUST="${VP}/rust"
MACOS_TARGET="$(rustc -vV | sed -n 's/^host: //p')"
PREBUILT_DIR="${RIC}/macos/Prebuilt"

echo "==> cargo build --release (rust_image_core, target=${MACOS_TARGET})"
mkdir -p "${PREBUILT_DIR}"
(cd "${RIC}/rust" && cargo build --release --target "${MACOS_TARGET}")
RIC_LIB="${RIC}/rust/target/${MACOS_TARGET}/release/librust_image_core.a"
if [[ ! -f "${RIC_LIB}" ]]; then
  RIC_LIB="${RIC}/rust/target/release/librust_image_core.a"
fi
if [[ ! -f "${RIC_LIB}" ]]; then
  echo "ERROR: librust_image_core.a not found after cargo build" >&2
  exit 1
fi
cp "${RIC_LIB}" "${PREBUILT_DIR}/librust_image_core.a"

echo "==> flutter_rust_bridge_codegen (video_processor_core)"
(cd "${VP}" && flutter_rust_bridge_codegen generate)

echo "==> Remove stale native copies (FRB content-hash mismatches)"
rm -rf "${RUST}/target/rust_hook"
rm -rf "${REPO_ROOT}/examples/media_studio/build"
rm -rf "${REPO_ROOT}/examples/media_studio/.dart_tool/flutter_build"
# Clean shared hooks_runner and package .dart_tools to force native assets recompilation
rm -rf "${REPO_ROOT}/.dart_tool/hooks_runner"
rm -rf "${REPO_ROOT}/packages/video_processor_core/.dart_tool"
rm -rf "${REPO_ROOT}/packages/flutter_video_processor/.dart_tool"
rm -rf "${REPO_ROOT}/examples/media_studio/.dart_tool"
# Legacy nested tree: old dylibs here shadow packages/video_processor_core (wrong FRB hash).
rm -f "${REPO_ROOT}/rust video/target/release/libvideo_processor_core.dylib" \
  "${REPO_ROOT}/rust video/target/release/deps/libvideo_processor_core.dylib"

echo "==> cargo clean + build --release (video_processor_core, target=${MACOS_TARGET})"
(cd "${RUST}" && cargo clean && cargo build --release --target "${MACOS_TARGET}")

echo "==> Copy newly built dylib to macOS Frameworks and update install name"
DYLIB="${REPO_ROOT}/packages/video_processor_core/rust/target/${MACOS_TARGET}/release/libvideo_processor_core.dylib"
if [[ ! -f "${DYLIB}" ]]; then
  DYLIB="${REPO_ROOT}/packages/video_processor_core/target/release/libvideo_processor_core.dylib"
fi
cp "${DYLIB}" "${REPO_ROOT}/packages/video_processor_core/macos/Frameworks/video_processor_core.framework/Versions/A/video_processor_core"
install_name_tool -id "@rpath/video_processor_core.framework/video_processor_core" "${REPO_ROOT}/packages/video_processor_core/macos/Frameworks/video_processor_core.framework/Versions/A/video_processor_core"

echo "==> Verify FRB content hash in source"
DART_HASH=$(grep -m1 'rustContentHash =>' "${VP}/lib/src/frb_generated/frb_generated.dart" | sed -E 's/.*=> *(-?[0-9]+).*/\1/')
RUST_HASH=$(grep -m1 'FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH' "${RUST}/src/frb_generated.rs" | sed -E 's/.*= *(-?[0-9]+);.*/\1/')
echo "    Dart: ${DART_HASH}  Rust source: ${RUST_HASH}"
if [[ "${DART_HASH}" != "${RUST_HASH}" ]]; then
  echo "ERROR: Dart/Rust FRB hashes differ — re-run codegen from packages/video_processor_core" >&2
  exit 1
fi

echo "==> flutter clean (media_studio)"
(cd "${REPO_ROOT}/examples/media_studio" && flutter clean && flutter pub get)

echo ""
echo "Done. Native video libs are ready."
echo "  bash \"${REPO_ROOT}/scripts/run-media-studio-macos.sh\" --no-rebuild   # flutter only"
echo "  bash \"${REPO_ROOT}/scripts/run-media-studio-macos.sh\"               # rebuild + run"
