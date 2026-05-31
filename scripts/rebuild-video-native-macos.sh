#!/usr/bin/env bash
# Rebuild video_forge Rust + FRB bindings, then refresh the macOS Flutter app.
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VP="${REPO_ROOT}/packages/video_forge"
RIC="${REPO_ROOT}/packages/image_forge"
RUST="${VP}/rust"
MACOS_TARGET="$(rustc -vV | sed -n 's/^host: //p')"
PREBUILT_DIR="${RIC}/macos/Prebuilt"

echo "==> cargo build --release (image_forge, target=${MACOS_TARGET})"
mkdir -p "${PREBUILT_DIR}"
(cd "${RIC}/rust" && cargo build --release --target "${MACOS_TARGET}")
RIC_LIB="${RIC}/rust/target/${MACOS_TARGET}/release/libimage_forge.a"
if [[ ! -f "${RIC_LIB}" ]]; then
  RIC_LIB="${RIC}/rust/target/release/libimage_forge.a"
fi
if [[ ! -f "${RIC_LIB}" ]]; then
  echo "ERROR: libimage_forge.a not found after cargo build" >&2
  exit 1
fi
cp "${RIC_LIB}" "${PREBUILT_DIR}/libimage_forge.a"

echo "==> flutter_rust_bridge_codegen (video_forge)"
(cd "${VP}" && flutter_rust_bridge_codegen generate)

echo "==> Remove stale native copies (FRB content-hash mismatches)"
rm -rf "${RUST}/target/rust_hook"
rm -rf "${REPO_ROOT}/examples/media_studio/build"
rm -rf "${REPO_ROOT}/examples/media_studio/.dart_tool/flutter_build"
# Clean shared hooks_runner and package .dart_tools to force native assets recompilation
rm -rf "${REPO_ROOT}/.dart_tool/hooks_runner"
rm -rf "${REPO_ROOT}/packages/video_forge/.dart_tool"
rm -rf "${REPO_ROOT}/packages/video_forge_kit/.dart_tool"
rm -rf "${REPO_ROOT}/examples/media_studio/.dart_tool"

echo "==> cargo clean + build --release (video_forge, target=${MACOS_TARGET})"
(cd "${RUST}" && cargo clean && cargo build --release --target "${MACOS_TARGET}")

echo "==> Copy newly built dylib to macOS Frameworks and update install name"
DYLIB=""
for candidate in \
  "${VP}/target/${MACOS_TARGET}/release/libvideo_forge.dylib" \
  "${RUST}/target/${MACOS_TARGET}/release/libvideo_forge.dylib" \
  "${VP}/target/release/libvideo_forge.dylib" \
  "${RUST}/target/release/libvideo_forge.dylib"; do
  if [[ -f "${candidate}" ]]; then
    DYLIB="${candidate}"
    break
  fi
done
if [[ -z "${DYLIB}" ]]; then
  echo "ERROR: libvideo_forge.dylib not found under ${VP}/target or ${RUST}/target" >&2
  exit 1
fi
echo "    Using ${DYLIB}"
FRAMEWORK_BIN="${VP}/macos/Frameworks/video_forge.framework/Versions/A/video_forge"
cp "${DYLIB}" "${FRAMEWORK_BIN}"
install_name_tool -id "@rpath/video_forge.framework/video_forge" "${FRAMEWORK_BIN}"

echo "==> Verify FRB content hash in source"
DART_HASH=$(grep -m1 'rustContentHash =>' "${VP}/lib/src/frb_generated/frb_generated.dart" | sed -E 's/.*=> *(-?[0-9]+).*/\1/')
RUST_HASH=$(grep -m1 'FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH' "${RUST}/src/frb_generated.rs" | sed -E 's/.*= *(-?[0-9]+);.*/\1/')
echo "    Dart: ${DART_HASH}  Rust source: ${RUST_HASH}"
if [[ "${DART_HASH}" != "${RUST_HASH}" ]]; then
  echo "ERROR: Dart/Rust FRB hashes differ — re-run codegen from packages/video_forge" >&2
  exit 1
fi

echo "==> Seed hooks_runner with the same dylib (avoids stale FRB dispatch in app bundle)"
HOOK_OUT="${REPO_ROOT}/.dart_tool/hooks_runner/shared/video_forge/build/rust_hook/${MACOS_TARGET}/release"
mkdir -p "${HOOK_OUT}"
cp -f "${DYLIB}" "${HOOK_OUT}/libvideo_forge.dylib"
install_name_tool -id "@rpath/libvideo_forge.dylib" "${HOOK_OUT}/libvideo_forge.dylib" 2>/dev/null || true

echo "==> flutter clean (media_studio)"
(cd "${REPO_ROOT}/examples/media_studio" && flutter clean && flutter pub get)

echo ""
echo "Done. Native video libs are ready."
echo "  bash \"${REPO_ROOT}/scripts/run-media-studio-macos.sh\" --no-rebuild   # flutter only"
echo "  bash \"${REPO_ROOT}/scripts/run-media-studio-macos.sh\"               # rebuild + run"
