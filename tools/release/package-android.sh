#!/usr/bin/env bash
# Build video_forge for Android ABIs and install into the plugin jniLibs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# shellcheck source=android-env.sh
source "${ROOT}/tools/release/android-env.sh"

PLUGIN_JNI="${ROOT}/packages/video_forge_kit/android/src/main/jniLibs"
OUT="${ROOT}/platform-build/android"
mkdir -p "${PLUGIN_JNI}" "${OUT}/jniLibs"

# Default: device ABI only (faster). Pass --all for emulator + 32-bit.
ABIS=("aarch64-linux-android:arm64-v8a")
if [[ "${1:-}" == "--all" ]]; then
  ABIS=(
    "aarch64-linux-android:arm64-v8a"
    "armv7-linux-androideabi:armeabi-v7a"
    "x86_64-linux-android:x86_64"
  )
fi

cd "${ROOT}"

# Keep artifacts in-repo (predictable path for jniLibs copy).
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${ROOT}/target}"
target_dir="${CARGO_TARGET_DIR}"

for entry in "${ABIS[@]}"; do
  triple="${entry%%:*}"
  abi="${entry##*:}"
  ffmpeg_dir="${ROOT}/tools/ffmpeg/dist/android/${abi}"

  if [[ ! -d "${ffmpeg_dir}/lib" ]]; then
    echo "Missing FFmpeg for ${abi} at ${ffmpeg_dir}" >&2
    echo "Build with: ./tools/ffmpeg/android.sh" >&2
    exit 1
  fi

  configure_android_cargo_target "${triple}"

  echo "==> cargo build --target ${triple} (FFMPEG_DIR=${ffmpeg_dir})"
  FFMPEG_DIR="${ffmpeg_dir}" \
    PKG_CONFIG_PATH="${ffmpeg_dir}/lib/pkgconfig" \
    BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS} -I${ffmpeg_dir}/include" \
    "${CARGO}" build --release -p video_forge --lib --target "${triple}"

  so="${target_dir}/${triple}/release/libvideo_forge.so"
  if [[ ! -f "${so}" ]]; then
    so="${target_dir}/${triple}/release/deps/libvideo_forge.so"
  fi
  if [[ ! -f "${so}" ]]; then
    echo "Build did not produce ${so}" >&2
    exit 1
  fi

  mkdir -p "${PLUGIN_JNI}/${abi}" "${OUT}/jniLibs/${abi}"
  cp "${so}" "${PLUGIN_JNI}/${abi}/"
  cp "${so}" "${OUT}/jniLibs/${abi}/"
  echo "    → ${PLUGIN_JNI}/${abi}/libvideo_forge.so"
done

tar -czf "${OUT}/android.tar.gz" -C "${OUT}" jniLibs
echo "Done. Plugin jniLibs: ${PLUGIN_JNI}"
