#!/usr/bin/env bash
# Prebuild rust_image_core for arm64 Android (avoids OOM during Gradle / cargokit).
set -euo pipefail

if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-2}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RIC="${REPO_ROOT}/packages/rust_image_core"
RUST="${RIC}/rust"
EXAMPLE="${REPO_ROOT}/examples/media_studio"
JNI_DIR="${RIC}/android/src/main/jniLibs/arm64-v8a"
TARGET="aarch64-linux-android"
MIN_SDK=21

setup_ndk_env() {
  local props="${EXAMPLE}/android/local.properties"
  if [[ ! -f "${props}" ]]; then
    echo "==> Generating local.properties (flutter pub get)"
    (cd "${EXAMPLE}" && flutter pub get >/dev/null)
  fi
  if [[ ! -f "${props}" ]]; then
    echo "ERROR: ${props} missing. Set ANDROID_HOME or run flutter once in media_studio." >&2
    exit 1
  fi
  local sdk
  sdk="$(grep '^sdk.dir=' "${props}" | cut -d= -f2- | tr -d '\r' | sed 's/\\:/:/g')"
  if [[ -z "${sdk}" || ! -d "${sdk}" ]]; then
    echo "ERROR: Invalid sdk.dir in ${props}" >&2
    exit 1
  fi
  local ndk_root="${sdk}/ndk"
  if [[ ! -d "${ndk_root}" ]]; then
    echo "ERROR: No NDK under ${ndk_root}. Install via Android Studio SDK Manager." >&2
    exit 1
  fi
  local ndk_ver
  ndk_ver="$(ls -1 "${ndk_root}" 2>/dev/null | sort -V | tail -1)"
  local prebuilt="${ndk_root}/${ndk_ver}/toolchains/llvm/prebuilt"
  local host=""
  for candidate in darwin-arm64 darwin-x86_64 linux-x86_64; do
    if [[ -d "${prebuilt}/${candidate}" ]]; then
      host="${candidate}"
      break
    fi
  done
  if [[ -z "${host}" ]]; then
    echo "ERROR: No LLVM prebuilt under ${prebuilt}" >&2
    exit 1
  fi
  local bin="${prebuilt}/${host}/bin"
  local target_arg="--target=${TARGET}${MIN_SDK}"
  export CC_aarch64_linux_android="${bin}/clang"
  export CXX_aarch64_linux_android="${bin}/clang++"
  export AR_aarch64_linux_android="${bin}/llvm-ar"
  export CFLAGS_aarch64_linux_android="${target_arg}"
  export CXXFLAGS_aarch64_linux_android="${target_arg}"
  # Route rustc through cargokit linker wrapper (plain clang picks macOS ld64).
  export CARGOKIT_TOOL_TEMP_DIR="${CARGOKIT_TOOL_TEMP_DIR:-/tmp/cargokit-rust-image-android}"
  export _CARGOKIT_NDK_LINK_CLANG="${bin}/clang"
  export _CARGOKIT_NDK_LINK_TARGET="${target_arg}"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${REPO_ROOT}/packages/rust_image_core/cargokit/run_build_tool.sh"
  echo "    NDK ${ndk_ver} (${host})"
}

echo "==> cargo build (rust_image_core, ${TARGET}, release, blurhash+gpu)"
mkdir -p "${JNI_DIR}"
setup_ndk_env
(cd "${RUST}" && cargo build --release -p rust_image_core --target "${TARGET}" \
  --no-default-features --features blurhash,gpu)

LIB="${RUST}/target/${TARGET}/release/librust_image_core.so"
if [[ ! -f "${LIB}" ]]; then
  LIB="${RIC}/target/${TARGET}/release/librust_image_core.so"
fi
if [[ ! -f "${LIB}" ]]; then
  echo "ERROR: librust_image_core.so not found after build" >&2
  exit 1
fi

cp "${LIB}" "${JNI_DIR}/librust_image_core.so"
echo "    → ${JNI_DIR}/librust_image_core.so"
echo "Done."
