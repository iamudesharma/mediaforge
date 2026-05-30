#!/usr/bin/env bash
# Minimal LGPL FFmpeg build for Android ABIs.
# Adapted from FFmpegKit build scripts (retired 2025).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${ROOT}/tools/ffmpeg/build/android"
DIST_DIR="${ROOT}/tools/ffmpeg/dist/android"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"
API=24

resolve_ndk() {
  if [[ -n "${ANDROID_NDK_HOME:-}" && -d "${ANDROID_NDK_HOME}" ]]; then
    echo "${ANDROID_NDK_HOME}"
    return
  fi
  if [[ -n "${ANDROID_NDK_ROOT:-}" && -d "${ANDROID_NDK_ROOT}" ]]; then
    echo "${ANDROID_NDK_ROOT}"
    return
  fi

  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  local ndk_root="${sdk}/ndk"
  if [[ ! -d "${ndk_root}" ]]; then
    echo "Android NDK not found. Install via Android Studio → SDK Manager → NDK," >&2
    echo "or set ANDROID_NDK_HOME to your NDK folder (e.g." >&2
    echo "  export ANDROID_NDK_HOME=\"\$HOME/Library/Android/sdk/ndk/28.2.13676358\")" >&2
    exit 1
  fi

  local latest
  latest="$(ls -1 "${ndk_root}" 2>/dev/null | sort -V | tail -1)"
  if [[ -z "${latest}" ]]; then
    echo "No NDK versions under ${ndk_root}" >&2
    exit 1
  fi
  echo "${ndk_root}/${latest}"
}

resolve_ndk_prebuilt() {
  local ndk="$1"
  local host_os
  host_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  local candidates=(
    "${ndk}/toolchains/llvm/prebuilt/${host_os}-aarch64"
    "${ndk}/toolchains/llvm/prebuilt/${host_os}-x86_64"
  )
  for dir in "${candidates[@]}"; do
    if [[ -d "${dir}/bin" ]]; then
      echo "${dir}"
      return
    fi
  done
  echo "Could not find NDK prebuilt toolchain under ${ndk}/toolchains/llvm/prebuilt/" >&2
  exit 1
}

resolve_android_platform() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
  local platform_dir="${sdk}/platforms/android-${API}"
  if [[ -d "${platform_dir}" ]]; then
    echo "${platform_dir}"
    return
  fi
  local best=""
  local p
  for p in "${sdk}"/platforms/android-[0-9]*; do
    [[ -d "${p}" ]] || continue
    best="${p}"
  done
  if [[ -n "${best}" ]]; then
    echo "${best}"
    return
  fi
  echo "No Android platform SDK under ${sdk}/platforms/ (install android-${API} or newer)" >&2
  exit 1
}

join_quoted_flags() {
  local out=""
  local flag
  for flag in "$@"; do
    out+=" $(printf '%q' "${flag}")"
  done
  echo "${out# }"
}

NDK="$(resolve_ndk)"
PREBUILT="$(resolve_ndk_prebuilt "${NDK}")"
TOOLCHAIN_BIN="${PREBUILT}/bin"
SYSROOT="${PREBUILT}/sysroot"
PLATFORM_DIR="$(resolve_android_platform)"

echo "Using NDK: ${NDK}"
echo "Using prebuilt: ${PREBUILT}"
echo "Using platform: ${PLATFORM_DIR}"

# Override with: FFMPEG_ANDROID_ABIS="arm64-v8a" for device-only (faster).
if [[ -n "${FFMPEG_ANDROID_ABIS:-}" ]]; then
  # shellcheck disable=SC2206
  ABIS=(${FFMPEG_ANDROID_ABIS})
else
  ABIS=("arm64-v8a" "armeabi-v7a" "x86_64")
fi

COMMON_FLAGS=(
  --disable-everything
  --disable-programs
  --disable-doc
  --disable-debug
  --enable-pic
  --enable-jni
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-swresample
  --enable-zlib
  # No OpenSSL by default (avoids host openssl when cross-compiling). HTTPS needs
  # VFP_FFMPEG_OPENSSL=1 and per-ABI libs under tools/ffmpeg/dist/android/<abi>/openssl/.
  --enable-protocol=file,http,tcp
  --enable-demuxer=mov,mp4,m4v,matroska,hls,mp3,wav,ogg,flac,aac
  --enable-muxer=mp4
  --enable-decoder=h264,hevc,aac,mp3,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_f32le
  --enable-parser=h264,hevc,aac,flac,vorbis,opus
  --enable-mediacodec
  --enable-hwaccel=mediacodec,h264_mediacodec,hevc_mediacodec
  --enable-encoder=h264_mediacodec,hevc_mediacodec,aac
  --enable-small
)

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

if [[ ! -d "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  echo "==> Downloading FFmpeg ${FFMPEG_VERSION}..."
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o "${BUILD_DIR}/ffmpeg.tar.xz"
  tar -xf "${BUILD_DIR}/ffmpeg.tar.xz" -C "${BUILD_DIR}"
fi

for ABI in "${ABIS[@]}"; do
  case "${ABI}" in
    arm64-v8a)
      TARGET=aarch64
      CLANG_PREFIX=aarch64-linux-android
      ;;
    armeabi-v7a)
      TARGET=arm
      CLANG_PREFIX=armv7a-linux-androideabi
      ;;
    x86_64)
      TARGET=x86_64
      CLANG_PREFIX=x86_64-linux-android
      ;;
    *)
      echo "Unknown ABI: ${ABI}" >&2
      exit 1
      ;;
  esac

  PREFIX="${BUILD_DIR}/${ABI}"
  mkdir -p "${PREFIX}" "${DIST_DIR}/${ABI}"

  CC="${TOOLCHAIN_BIN}/${CLANG_PREFIX}${API}-clang"
  CXX="${CC}++"
  AR="${TOOLCHAIN_BIN}/llvm-ar"
  NM="${TOOLCHAIN_BIN}/llvm-nm"
  RANLIB="${TOOLCHAIN_BIN}/llvm-ranlib"
  STRIP="${TOOLCHAIN_BIN}/llvm-strip"

  for tool in "${CC}" "${AR}" "${NM}"; do
    if [[ ! -x "${tool}" ]]; then
      echo "Missing toolchain tool: ${tool}" >&2
      exit 1
    fi
  done

  # MediaCodec + JNI (headers from NDK sysroot; no Java compile needed for --enable-jni).
  EXTRA_CFLAGS=(
    "--sysroot=${SYSROOT}"
    "-I${SYSROOT}/usr/include"
    "-I${SYSROOT}/usr/include/${CLANG_PREFIX}"
  )
  EXTRA_LDFLAGS=(
    "--sysroot=${SYSROOT}"
    "-L${SYSROOT}/usr/lib/${CLANG_PREFIX}/${API}"
    "-landroid"
    "-lmediandk"
    "-llog"
    "-ljnigraphics"
    "-lm"
    "-lz"
  )

  echo "==> Configuring FFmpeg for ${ABI}..."
  cd "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}"

  if [[ -f Makefile ]]; then
    make distclean >/dev/null 2>&1 || true
  fi

  extra_cflags="$(join_quoted_flags "${EXTRA_CFLAGS[@]}")"
  extra_ldflags="$(join_quoted_flags "${EXTRA_LDFLAGS[@]}")"

  if [[ "${VFP_FFMPEG_OPENSSL:-0}" == "1" ]]; then
    local ssl_dir="${DIST_DIR}/${ABI}/openssl"
    if [[ ! -f "${ssl_dir}/lib/libssl.a" ]]; then
      echo "VFP_FFMPEG_OPENSSL=1 but missing ${ssl_dir}/lib/libssl.a" >&2
      echo "Build OpenSSL for Android first, or omit VFP_FFMPEG_OPENSSL (file + http only)." >&2
      exit 1
    fi
    extra_cflags="${extra_cflags} -I${ssl_dir}/include"
    extra_ldflags="${extra_ldflags} -L${ssl_dir}/lib"
    PROTOCOL_FLAGS=(--enable-protocol=file,http,https,tcp,tls --enable-openssl)
  else
    PROTOCOL_FLAGS=(--enable-protocol=file,http,tcp)
  fi

  # macOS bash 3.2 + `set -u`: expanding empty "${ABI_FLAGS[@]}" errors; branch instead.
  if [[ "${TARGET}" == "x86_64" ]]; then
    ./configure \
      --prefix="${PREFIX}" \
      --target-os=android \
      --arch="${TARGET}" \
      --cc="${CC}" \
      --cxx="${CXX}" \
      --ar="${AR}" \
      --nm="${NM}" \
      --ranlib="${RANLIB}" \
      --strip="${STRIP}" \
      --ld="${CC}" \
      --enable-cross-compile \
      --sysroot="${SYSROOT}" \
      --extra-cflags="${extra_cflags}" \
      --extra-ldflags="${extra_ldflags}" \
      --disable-x86asm \
      "${COMMON_FLAGS[@]}" \
      "${PROTOCOL_FLAGS[@]}"
  else
    ./configure \
      --prefix="${PREFIX}" \
      --target-os=android \
      --arch="${TARGET}" \
      --cc="${CC}" \
      --cxx="${CXX}" \
      --ar="${AR}" \
      --nm="${NM}" \
      --ranlib="${RANLIB}" \
      --strip="${STRIP}" \
      --ld="${CC}" \
      --enable-cross-compile \
      --sysroot="${SYSROOT}" \
      --extra-cflags="${extra_cflags}" \
      --extra-ldflags="${extra_ldflags}" \
      "${COMMON_FLAGS[@]}" \
      "${PROTOCOL_FLAGS[@]}"
  fi

  make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)"
  make install
  cp -R "${PREFIX}/lib" "${DIST_DIR}/${ABI}/"
  cp -R "${PREFIX}/include" "${DIST_DIR}/${ABI}/" 2>/dev/null || true
  echo "Built FFmpeg for ${ABI} -> ${DIST_DIR}/${ABI}"
done

echo "Android FFmpeg artifacts in ${DIST_DIR}"
