#!/usr/bin/env bash
# Build a native macOS FFmpeg with VideoToolbox HEVC/H.264 hwaccels for rust_media_runtime.
#
# FFmpeg 8 registers VideoToolbox as hwaccel (hevc decoder + hevc_videotoolbox hwaccel),
# not as standalone decoders named hevc_videotoolbox.
#
#   bash scripts/build-ffmpeg-macos-vt.sh
#   bash scripts/run-rust-media-macos.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"
INSTALL_PREFIX="${FFMPEG_INSTALL_PREFIX:-${HOME}/.cache/rust_image/ffmpeg-macos-vt}"
BUILD_DIR="${FFMPEG_BUILD_DIR:-${HOME}/.cache/rust_image/ffmpeg-macos-vt-build}"

echo "==> Building FFmpeg ${FFMPEG_VERSION} with VideoToolbox hwaccels"
echo "    install prefix=${INSTALL_PREFIX}"
echo "    build dir=${BUILD_DIR}"

mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

if [[ ! -d "ffmpeg-${FFMPEG_VERSION}" ]]; then
  echo "==> Downloading ffmpeg-${FFMPEG_VERSION}..."
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o ffmpeg.tar.xz
  tar -xf ffmpeg.tar.xz
fi

cd "ffmpeg-${FFMPEG_VERSION}"

if [[ -f config.mak ]]; then
  old_prefix="$(sed -n 's/^prefix=//p' config.mak | head -1)"
  if [[ "${old_prefix}" != "${INSTALL_PREFIX}" ]]; then
    echo "==> prefix changed; make distclean"
    make distclean 2>/dev/null || true
  fi
fi

./configure \
  --prefix="${INSTALL_PREFIX}" \
  --enable-shared \
  --disable-static \
  --disable-everything \
  --enable-ffmpeg \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-doc \
  --enable-pthreads \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-zlib \
  --enable-protocol=file \
  --enable-demuxer=mov,mp4,m4v,matroska,mp3,wav,ogg,flac,aac \
  --enable-muxer=mp4 \
  --enable-decoder=h264,hevc,aac,mp3,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_f32le \
  --enable-parser=h264,hevc,aac \
  --enable-videotoolbox \
  --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox \
  --enable-small

make -j"$(sysctl -n hw.ncpu)"
make install

CONFIG_H="${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}/config.h"
LIBAVCODEC="$(echo "${INSTALL_PREFIX}"/lib/libavcodec.*)"
verify_ok=0

# FFmpeg 8: -hwaccels lists the device ("videotoolbox"), not per-codec names.
# Per-codec hwaccels (hevc_videotoolbox) live in libavcodec — check the dylib.
if [[ -f "${CONFIG_H}" ]] && grep -q 'define CONFIG_VIDEOTOOLBOX 1' "${CONFIG_H}"; then
  echo "==> config.h: CONFIG_VIDEOTOOLBOX=1"
  verify_ok=1
fi

if [[ -f "${LIBAVCODEC}" ]] && strings "${LIBAVCODEC}" | grep -q hevc_videotoolbox; then
  echo "==> libavcodec: hevc_videotoolbox hwaccel present"
  verify_ok=1
fi

if [[ -x "${INSTALL_PREFIX}/bin/ffmpeg" ]]; then
  echo "==> ffmpeg -hwaccels:"
  "${INSTALL_PREFIX}/bin/ffmpeg" -hide_banner -hwaccels 2>/dev/null | sed 's/^/    /'
fi

if [[ "${verify_ok}" -eq 0 ]]; then
  echo "ERROR: VideoToolbox HEVC hwaccel not found in ${LIBAVCODEC} — check ${CONFIG_H}" >&2
  exit 1
fi

REPO_LINK="${REPO_ROOT}/tools/ffmpeg/dist/macos-vt"
mkdir -p "$(dirname "${REPO_LINK}")"
ln -sfn "${INSTALL_PREFIX}" "${REPO_LINK}"

echo ""
echo "==> Installed to: ${INSTALL_PREFIX}"
echo "    Next: bash scripts/run-rust-media-macos.sh"
