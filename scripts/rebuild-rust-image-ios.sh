#!/usr/bin/env bash
# Prebuild image_forge for iOS device (aarch64-apple-ios).
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIC="${REPO_ROOT}/packages/image_forge"
RUST="${RIC}/rust"
PREBUILT_DIR="${RIC}/ios/Prebuilt"
TARGET="aarch64-apple-ios"

rustup target add "${TARGET}" 2>/dev/null || true

export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
if command -v xcrun >/dev/null 2>&1; then
  export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
fi

echo "==> cargo build (image_forge, ${TARGET}, release, blurhash+gpu)"
mkdir -p "${PREBUILT_DIR}"
(cd "${RUST}" && cargo build --release -p image_forge --target "${TARGET}" \
  --no-default-features --features blurhash,gpu)

LIB="${RUST}/target/${TARGET}/release/libimage_forge.a"
if [[ ! -f "${LIB}" ]]; then
  echo "ERROR: libimage_forge.a not found after build" >&2
  exit 1
fi

cp "${LIB}" "${PREBUILT_DIR}/libimage_forge.a"
echo "    → ${PREBUILT_DIR}/libimage_forge.a"
echo "Done."
