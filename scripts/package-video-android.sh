#!/usr/bin/env bash
# Build video_forge for Android and install into the monorepo plugin jniLibs/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="${ROOT}/tools"
VP_PKG="${ROOT}/packages/video_forge"
PLUGIN_JNI="${VP_PKG}/android/src/main/jniLibs"
OUT="${ROOT}/platform-build/android"

# shellcheck source=/dev/null
source "${TOOLS}/release/android-env.sh"

mkdir -p "${PLUGIN_JNI}" "${OUT}/jniLibs"

# Wipe any stale .so from a previous package (pre-1.0 / pre-2.0 used
# `libvideo_processor_core.so`). Without this, an old stale .so can shadow
# the freshly built `libvideo_forge.so` and cause confusing runtime errors.
find "${PLUGIN_JNI}" -name 'libvideo_processor_core.so' -delete 2>/dev/null || true
find "${OUT}/jniLibs" -name 'libvideo_processor_core.so' -delete 2>/dev/null || true

# Default: device ABI only (faster). Pass --all for emulator + 32-bit.
ABIS=("aarch64-linux-android:arm64-v8a")
if [[ "${1:-}" == "--all" ]]; then
  ABIS=(
    "aarch64-linux-android:arm64-v8a"
    "armv7-linux-androideabi:armeabi-v7a"
    "x86_64-linux-android:x86_64"
  )
fi

export CARGO_TARGET_DIR="${VP_PKG}/rust/target"
target_dir="${CARGO_TARGET_DIR}"
manifest="${VP_PKG}/rust/Cargo.toml"

cd "${VP_PKG}/rust"

for entry in "${ABIS[@]}"; do
  triple="${entry%%:*}"
  abi="${entry##*:}"
  ffmpeg_dir="${TOOLS}/ffmpeg/dist/android/${abi}"

  if [[ ! -d "${ffmpeg_dir}/lib" ]]; then
    echo "Missing FFmpeg for ${abi} at ${ffmpeg_dir}" >&2
    echo "From repo root:" >&2
    echo "  ./tools/ffmpeg/android.sh" >&2
    exit 1
  fi

  configure_android_cargo_target "${triple}"

  echo "==> cargo build --target ${triple} (FFMPEG_DIR=${ffmpeg_dir})"
  FFMPEG_DIR="${ffmpeg_dir}" \
    PKG_CONFIG_PATH="${ffmpeg_dir}/lib/pkgconfig" \
    BINDGEN_EXTRA_CLANG_ARGS="${BINDGEN_EXTRA_CLANG_ARGS} -I${ffmpeg_dir}/include" \
    "${CARGO}" build --release \
      --manifest-path "${manifest}" \
      -p video_forge \
      --lib \
      --target "${triple}"

  so="${target_dir}/${triple}/release/libvideo_forge.so"
  if [[ ! -f "${so}" ]]; then
    so="${target_dir}/${triple}/release/deps/libvideo_forge.so"
  fi
  if [[ ! -f "${so}" ]]; then
    echo "Build did not produce libvideo_forge.so for ${triple}" >&2
    exit 1
  fi

  mkdir -p "${PLUGIN_JNI}/${abi}" "${OUT}/jniLibs/${abi}"
  cp "${so}" "${PLUGIN_JNI}/${abi}/"
  cp "${so}" "${OUT}/jniLibs/${abi}/"
  echo "    → ${PLUGIN_JNI}/${abi}/libvideo_forge.so"
done

tar -czf "${OUT}/android.tar.gz" -C "${OUT}" jniLibs 2>/dev/null || true
echo "Done. Plugin jniLibs: ${PLUGIN_JNI}"
