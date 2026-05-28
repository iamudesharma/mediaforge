#!/usr/bin/env bash
# Prebuild rust_image_core for iOS device (aarch64-apple-ios).
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIC="${REPO_ROOT}/packages/rust_image_core"
RUST="${RIC}/rust"
PREBUILT_DIR="${RIC}/ios/Prebuilt"
TARGET="aarch64-apple-ios"

rustup target add "${TARGET}" 2>/dev/null || true

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
if command -v xcrun >/dev/null 2>&1; then
  export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
fi

echo "==> cargo build (rust_image_core, ${TARGET}, release, blurhash+gpu)"
mkdir -p "${PREBUILT_DIR}"
(cd "${RUST}" && cargo build --release -p rust_image_core --target "${TARGET}" \
  --no-default-features --features blurhash,gpu)

LIB="${RUST}/target/${TARGET}/release/librust_image_core.a"
if [[ ! -f "${LIB}" ]]; then
  echo "ERROR: librust_image_core.a not found after build" >&2
  exit 1
fi

cp "${LIB}" "${PREBUILT_DIR}/librust_image_core.a"
echo "    → ${PREBUILT_DIR}/librust_image_core.a"
echo "Done."
