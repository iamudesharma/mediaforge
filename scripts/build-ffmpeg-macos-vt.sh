#!/usr/bin/env bash
# Build a native macOS FFmpeg with VideoToolbox HEVC/H.264 hwaccels for media_forge.
#
# FFmpeg 8 registers VideoToolbox as hwaccel (hevc decoder + hevc_videotoolbox hwaccel),
# not as standalone decoders named hevc_videotoolbox.
#
# Linkage (important for sandboxed/distributed apps): macOS App Sandbox blocks
# loading dylibs by absolute dev-machine path, so a `--enable-shared` FFmpeg
# can NEVER ship inside an app bundle. Default here is a STATIC build
# (`--enable-static --disable-shared --enable-pic`) whose archives link
# directly into libmedia_forge.dylib — no runtime dylib dependency at all
# (verify with `otool -L`). Only system libs (/usr/lib) remain dynamic.
#
#   bash scripts/build-ffmpeg-macos-vt.sh            # static (default, shippable)
#   FFMPEG_SHARED=1 bash scripts/build-ffmpeg-macos-vt.sh   # shared (fast dev iteration only)
#   bash scripts/run-rust-media-macos.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"
if [[ "${FFMPEG_SHARED:-0}" == "1" ]]; then
  INSTALL_PREFIX="${FFMPEG_INSTALL_PREFIX:-${HOME}/.cache/rust_image/ffmpeg-macos-vt}"
  SHARED_FLAGS=(--enable-shared --disable-static)
  VARIANT="shared (dev only — NOT shippable in sandboxed apps)"
else
  INSTALL_PREFIX="${FFMPEG_INSTALL_PREFIX:-${HOME}/.cache/rust_image/ffmpeg-macos-vt-static}"
  SHARED_FLAGS=(--disable-shared --enable-static --enable-pic)
  VARIANT="static (shippable)"
fi
BUILD_DIR="${FFMPEG_BUILD_DIR:-${HOME}/.cache/rust_image/ffmpeg-macos-vt-build}"

echo "==> Building FFmpeg ${FFMPEG_VERSION} with VideoToolbox hwaccels [${VARIANT}]"
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

# Rebuild from scratch when the install prefix OR the configure flags
# changed — incremental make does not reliably pick up deselected/
# newly-selected demuxers, protocols, or static/shared flips.
CONFIGURE_STAMP_ARGS="prefix=${INSTALL_PREFIX} shared=${FFMPEG_SHARED:-0} v=3"
if [[ -f config.mak ]]; then
  old_prefix="$(sed -n 's/^prefix=//p' config.mak | head -1)"
  old_stamp="$(cat .rust_image_configure_stamp 2>/dev/null || true)"
  if [[ "${old_prefix}" != "${INSTALL_PREFIX}" || "${old_stamp}" != "${CONFIGURE_STAMP_ARGS}" ]]; then
    echo "==> prefix/flags changed; make distclean"
    make distclean 2>/dev/null || true
  fi
fi

./configure \
  --prefix="${INSTALL_PREFIX}" \
  "${SHARED_FLAGS[@]}" \
  --disable-everything \
  --enable-ffmpeg \
  --disable-ffplay \
  --disable-ffprobe \
  --disable-doc \
  --enable-pthreads \
  --enable-network \
  --enable-avcodec \
  --enable-avformat \
  --enable-avutil \
  --enable-swscale \
  --enable-swresample \
  --enable-zlib \
  --enable-securetransport \
  --enable-protocol=file,http,https,tcp,tls,httpproxy,crypto \
  --enable-demuxer=mov,mp4,m4v,matroska,mp3,wav,ogg,flac,aac,hls,mpegts \
  --enable-muxer=mp4 \
  --enable-decoder=h264,hevc,aac,mp3,flac,vorbis,opus,pcm_s16le,pcm_s24le,pcm_f32le,mpeg4,msmpeg4v2,msmpeg4v3,h263,h263i,h263p \
  --enable-parser=h264,hevc,aac,mpeg4video,h263,mpegaudio,mpegvideo \
  --enable-videotoolbox \
  --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox \
  --enable-small

echo "${CONFIGURE_STAMP_ARGS}" > .rust_image_configure_stamp

make -j"$(sysctl -n hw.ncpu)"
make install

CONFIG_H="${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}/config.h"
if [[ "${FFMPEG_SHARED:-0}" == "1" ]]; then
  LIBAVCODEC="$(ls "${INSTALL_PREFIX}"/lib/libavcodec.*.dylib 2>/dev/null | head -1)"
else
  LIBAVCODEC="${INSTALL_PREFIX}/lib/libavcodec.a"
fi
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
# Fail fast on what Rust actually links: the static archives (+ component
# defines), NOT the ffmpeg CLI (its link line may resolve shared system
# libs and is not what ships). A miss here used to surface at app
# runtime as "Protocol not found" (see PeerStream localhost streaming).
if [[ "${FFMPEG_SHARED:-0}" != "1" ]]; then
  for obj in http.o tcp.o tls.o crypto.o file.o hls.o mpegts.o; do
    if ! ar t "${INSTALL_PREFIX}/lib/libavformat.a" 2>/dev/null | grep -qx "${obj}"; then
      echo "ERROR: ${obj} missing from ${INSTALL_PREFIX}/lib/libavformat.a" >&2
      exit 1
    fi
  done
  for def in CONFIG_HTTP_PROTOCOL CONFIG_TCP_PROTOCOL CONFIG_TLS_PROTOCOL CONFIG_HLS_DEMUXER CONFIG_MPEGTS_DEMUXER; do
    if ! grep -q "define ${def} 1" "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}/config_components.h"; then
      echo "ERROR: ${def} not enabled in config_components.h" >&2
      exit 1
    fi
  done
  echo "==> archives carry http/tcp/tls/crypto/file + hls/mpegts; component defines present"
fi

if [[ "${verify_ok}" -eq 0 ]]; then
  echo "ERROR: VideoToolbox HEVC hwaccel not found in ${LIBAVCODEC} — check ${CONFIG_H}" >&2
  exit 1
fi

REPO_LINK="${REPO_ROOT}/tools/ffmpeg/dist/macos-vt"
if [[ "${FFMPEG_SHARED:-0}" != "1" ]]; then
  REPO_LINK="${REPO_ROOT}/tools/ffmpeg/dist/macos-vt-static"
fi
mkdir -p "$(dirname "${REPO_LINK}")"
ln -sfn "${INSTALL_PREFIX}" "${REPO_LINK}"

echo ""
echo "==> Installed to: ${INSTALL_PREFIX}"
echo "    Next: bash scripts/run-rust-media-macos.sh"
