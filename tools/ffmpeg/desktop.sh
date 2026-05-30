#!/usr/bin/env bash
# Minimal LGPL FFmpeg build for Linux/Windows desktop.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${ROOT}/tools/ffmpeg/build/desktop"
DIST_DIR="${ROOT}/tools/ffmpeg/dist/desktop"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"
TARGET_OS="${1:-$(uname -s | tr '[:upper:]' '[:lower:]')}"

COMMON_FLAGS=(
  --disable-everything
  --disable-programs
  --disable-doc
  --disable-debug
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-swresample
  --enable-zlib
  --enable-protocol=file
  --enable-demuxer=mov,mp4,m4v,matroska,mp3,wav,ogg,flac,aac
  --enable-muxer=mp4
  --enable-decoder=h264,hevc,aac,mp3,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_f32le
  --enable-parser=h264,hevc,aac,flac,vorbis,opus
  --enable-encoder=h264_vaapi,hevc_vaapi,h264_nvenc,hevc_nvenc,aac
  --enable-vaapi
  --enable-nvenc
  --enable-small
)

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

if [[ ! -d "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o "${BUILD_DIR}/ffmpeg.tar.xz"
  tar -xf "${BUILD_DIR}/ffmpeg.tar.xz" -C "${BUILD_DIR}"
fi

cd "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}"

case "${TARGET_OS}" in
  linux)
    ./configure --prefix="${DIST_DIR}/linux" "${COMMON_FLAGS[@]}"
    ;;
  darwin|macos)
    ./configure --prefix="${DIST_DIR}/macos" --enable-videotoolbox "${COMMON_FLAGS[@]}"
    ;;
  mingw*|windows|msys)
    ./configure --prefix="${DIST_DIR}/windows" --target-os=mingw32 "${COMMON_FLAGS[@]}"
    ;;
  *)
    echo "Unsupported OS: ${TARGET_OS}" >&2
    exit 1
    ;;
esac

make -j"$(sysctl -n hw.ncpu 2>/dev/null || nproc)" install
echo "Desktop FFmpeg installed to ${DIST_DIR}"
