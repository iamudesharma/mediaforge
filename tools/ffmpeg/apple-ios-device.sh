#!/usr/bin/env bash
# Minimal LGPL FFmpeg for physical iOS devices (arm64, VideoToolbox).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${ROOT}/tools/ffmpeg/build/apple"
DIST_DIR="${ROOT}/tools/ffmpeg/dist/apple/aarch64-apple-ios"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"
RUST_TRIPLE="aarch64-apple-ios"
SDK="iphoneos"
ARCH="arm64"

COMMON_FLAGS=(
  --disable-everything
  --disable-programs
  --disable-doc
  --disable-debug
  --enable-pic
  --enable-avcodec
  --enable-avformat
  --enable-avutil
  --enable-swscale
  --enable-swresample
  --enable-zlib
  --enable-protocol=file,http,https,tcp,tls
  --enable-demuxer=mov,mp4,m4v,matroska,hls
  --enable-securetransport
  --enable-muxer=mp4
  --enable-decoder=h264,hevc,aac
  --enable-encoder=h264_videotoolbox,hevc_videotoolbox,aac
  --enable-videotoolbox
  # FFmpeg 8: per-codec hwaccels (bare "videotoolbox" is ignored — breaks HW decode + P3).
  --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
  --enable-small
)

PREFIX="${BUILD_DIR}/${RUST_TRIPLE}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

if [[ ! -d "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  echo "==> Downloading FFmpeg ${FFMPEG_VERSION}..."
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o "${BUILD_DIR}/ffmpeg.tar.xz"
  tar -xf "${BUILD_DIR}/ffmpeg.tar.xz" -C "${BUILD_DIR}"
fi

echo "==> Configuring FFmpeg for ${RUST_TRIPLE}..."
cd "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}"
if [[ -f Makefile ]]; then
  make distclean >/dev/null 2>&1 || true
fi

SDK_PATH="$(xcrun --sdk "${SDK}" --show-sdk-path)"
CLANG="xcrun -sdk ${SDK} clang -arch ${ARCH} -miphoneos-version-min=13.0 -isysroot ${SDK_PATH}"

xcrun ./configure \
  --prefix="${PREFIX}" \
  --enable-cross-compile \
  --target-os=darwin \
  --arch="${ARCH}" \
  --cc="${CLANG}" \
  --as="${CLANG}" \
  --extra-cflags="-arch ${ARCH} -miphoneos-version-min=13.0 -isysroot ${SDK_PATH}" \
  --extra-ldflags="-arch ${ARCH} -miphoneos-version-min=13.0 -isysroot ${SDK_PATH}" \
  "${COMMON_FLAGS[@]}"

make -j"$(sysctl -n hw.ncpu)"
make install
cp -R "${PREFIX}/lib" "${DIST_DIR}/"
cp -R "${PREFIX}/include" "${DIST_DIR}/" 2>/dev/null || true
echo "h264_videotoolbox_hwaccel hevc_videotoolbox_hwaccel" > "${DIST_DIR}/HWACCEL_FEATURES"
echo "iOS device FFmpeg → ${DIST_DIR}"
