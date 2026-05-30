#!/usr/bin/env bash
# Source from package-android.sh / run-android.sh — NDK linker + Rust Android targets.
set -euo pipefail

resolve_ndk() {
  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
    echo "${ANDROID_NDK_HOME}"
    return
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  local ndk_root="${sdk}/ndk"
  if [[ ! -d "${ndk_root}" ]]; then
    echo "Android NDK not found. Set ANDROID_NDK_HOME or install via SDK Manager." >&2
    exit 1
  fi
  echo "${ndk_root}/$(ls -1 "${ndk_root}" | sort -V | tail -1)"
}

resolve_ndk_prebuilt() {
  local ndk="$1"
  local host_os
  host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local dir
  for dir in \
    "${ndk}/toolchains/llvm/prebuilt/${host_os}-aarch64" \
    "${ndk}/toolchains/llvm/prebuilt/${host_os}-x86_64"; do
    if [[ -d "${dir}/bin" ]]; then
      echo "${dir}"
      return
    fi
  done
  echo "NDK prebuilt toolchain not found under ${ndk}" >&2
  exit 1
}

ensure_android_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    echo "Install Rust via https://rustup.rs" >&2
    exit 1
  fi

  # Homebrew rustc/cargo on PATH ignores rust-toolchain.toml and Android std libs.
  export PATH="${HOME}/.cargo/bin:${PATH}"
  export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-1.88.0}"

  local channel="${RUSTUP_TOOLCHAIN}"
  echo "==> Rust toolchain ${channel} + Android targets..."
  rustup toolchain install "${channel}"
  rustup target add --toolchain "${channel}" \
    aarch64-linux-android \
    armv7-linux-androideabi \
    x86_64-linux-android

  local rustc_path cargo_path
  rustc_path="$(rustup which rustc --toolchain "${channel}")"
  cargo_path="$(rustup which cargo --toolchain "${channel}")"
  if [[ -z "${rustc_path}" || -z "${cargo_path}" ]]; then
    echo "rustup toolchain ${channel} is missing rustc/cargo" >&2
    exit 1
  fi
  if [[ "${rustc_path}" == *"/opt/homebrew/"* ]] || [[ "${rustc_path}" == *"/usr/local/"* ]]; then
    echo "Homebrew rustc is on PATH; use rustup (https://rustup.rs). Got: ${rustc_path}" >&2
    exit 1
  fi
  export RUSTC="${rustc_path}"
  export CARGO="${cargo_path}"
}

export_android_linkers() {
  local api="${ANDROID_API_LEVEL:-24}"
  local ndk prebuilt bin
  ndk="$(resolve_ndk)"
  prebuilt="$(resolve_ndk_prebuilt "${ndk}")"
  bin="${prebuilt}/bin"

  export ANDROID_NDK_HOME="${ndk}"
  export ANDROID_NDK_PREBUILT="${prebuilt}"
  export ANDROID_NDK_BIN="${bin}"
  export ANDROID_NDK_SYSROOT="${prebuilt}/sysroot"
  export CLANG_PATH="${bin}/clang"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${bin}/aarch64-linux-android${api}-clang"
  export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="${bin}/armv7a-linux-androideabi${api}-clang"
  export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="${bin}/x86_64-linux-android${api}-clang"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_AR="${bin}/llvm-ar"
  export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_AR="${bin}/llvm-ar"
  export CARGO_TARGET_X86_64_LINUX_ANDROID_AR="${bin}/llvm-ar"

  for tool in \
    "${CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER}" \
    "${CARGO_TARGET_AARCH64_LINUX_ANDROID_AR}"; do
    if [[ ! -x "${tool}" ]]; then
      echo "Missing NDK tool: ${tool}" >&2
      exit 1
    fi
  done

  echo "==> NDK linkers: ${ndk} (API ${api})"
}

# Per-target CC/CXX/bindgen flags for build-scripts (e.g. ffmpeg-sys-next).
configure_android_cargo_target() {
  local triple="$1"
  local api="${ANDROID_API_LEVEL:-24}"
  local sysroot="${ANDROID_NDK_SYSROOT}"
  local clang="" llvm_target="" gnu_triple=""

  case "${triple}" in
    aarch64-linux-android)
      clang="${CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER}"
      llvm_target="aarch64-linux-android${api}"
      gnu_triple="aarch64-linux-android"
      ;;
    armv7-linux-androideabi)
      clang="${CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER}"
      llvm_target="armv7a-linux-androideabi${api}"
      gnu_triple="arm-linux-androideabi"
      ;;
    x86_64-linux-android)
      clang="${CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER}"
      llvm_target="x86_64-linux-android${api}"
      gnu_triple="x86_64-linux-android"
      ;;
    *)
      echo "Unsupported Rust triple: ${triple}" >&2
      exit 1
      ;;
  esac

  local cargo_triple="${triple//-/_}"
  local sysroot_flags="--sysroot=${sysroot} -I${sysroot}/usr/include -I${sysroot}/usr/include/${gnu_triple}"

  export "CC_${cargo_triple}=${clang}"
  export "CXX_${cargo_triple}=${clang}++"
  export "CFLAGS_${cargo_triple}=${sysroot_flags}"
  export "CXXFLAGS_${cargo_triple}=${sysroot_flags}"
  export "LDFLAGS_${cargo_triple}=--sysroot=${sysroot}"
  export "AR_${cargo_triple}=${ANDROID_NDK_BIN}/llvm-ar"
  export "RANLIB_${cargo_triple}=${ANDROID_NDK_BIN}/llvm-ranlib"
  export BINDGEN_EXTRA_CLANG_ARGS="${sysroot_flags} --target=${llvm_target}"

  # FFmpeg MediaCodec/JNI objects need NDK platform libs at link time.
  export "RUSTFLAGS_${cargo_triple}=-C link-arg=-landroid -C link-arg=-lmediandk -C link-arg=-llog -C link-arg=-ljnigraphics"
}

ensure_android_rust
export_android_linkers
