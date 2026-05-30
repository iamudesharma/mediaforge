#!/usr/bin/env bash
# Minimal LGPL FFmpeg build for iOS/macOS (VideoToolbox).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${ROOT}/tools/ffmpeg/build/apple"
DIST_DIR="${ROOT}/tools/ffmpeg/dist/apple"
FFMPEG_VERSION="${FFMPEG_VERSION:-8.0}"

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
  --enable-encoder=h264_videotoolbox,hevc_videotoolbox,aac
  --enable-videotoolbox
  --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox
  --enable-small
)

PLATFORMS=(
  "aarch64-apple-ios:iphoneos:arm64"
  "aarch64-apple-ios-sim:iphonesimulator:arm64"
  "x86_64-apple-ios:iphonesimulator:x86_64"
  "aarch64-apple-darwin:macosx:arm64"
  "x86_64-apple-darwin:macosx:x86_64"
)

mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

if [[ ! -d "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}" ]]; then
  curl -L "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o "${BUILD_DIR}/ffmpeg.tar.xz"
  tar -xf "${BUILD_DIR}/ffmpeg.tar.xz" -C "${BUILD_DIR}"
fi

for entry in "${PLATFORMS[@]}"; do
  IFS=: read -r RUST_TRIPLE SDK ARCH <<< "${entry}"
  PREFIX="${BUILD_DIR}/${RUST_TRIPLE}"
  mkdir -p "${PREFIX}"

  cd "${BUILD_DIR}/ffmpeg-${FFMPEG_VERSION}"

  xcrun ./configure \
    --prefix="${PREFIX}" \
    --enable-cross-compile \
    --target-os=darwin \
    --arch="${ARCH}" \
    --cc="xcrun -sdk ${SDK} clang" \
    --as="gas-preprocessor.pl $(xcrun -sdk ${SDK} --find clang)" \
    --extra-cflags="-arch ${ARCH} -mios-version-min=13.0" \
    --extra-ldflags="-arch ${ARCH} -mios-version-min=13.0" \
    "${COMMON_FLAGS[@]}"

  make -j"$(sysctl -n hw.ncpu)" install
  echo "Built FFmpeg for ${RUST_TRIPLE}"
done

echo "Apple FFmpeg slices in ${BUILD_DIR}. Run tools/release/package-apple.sh to create XCFramework."
