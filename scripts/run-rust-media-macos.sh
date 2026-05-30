#!/usr/bin/env bash
# Phase 0: rebuild rust_media_runtime with VT-capable FFmpeg and run the dashboard example.
#
# Usage (from repo root):
#   bash scripts/run-rust-media-macos.sh
#
# First-time (no VT FFmpeg yet):
#   bash scripts/build-ffmpeg-macos-vt.sh
#   bash scripts/run-rust-media-macos.sh
#
# Optional env:
#   FFMPEG_DIR  — FFmpeg prefix with hevc_videotoolbox (see below)
#   VFP_DISABLE_HW_DECODE=1  — force software decode (debug)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${REPO_ROOT}/packages/rust_media_runtime"
EXAMPLE="${PKG}/example"
RUST_VIDEO="${REPO_ROOT}/rust video"
TRIPLE="$(rustc -vV | sed -n 's/^host: //p')"

echo "==> Host triple: ${TRIPLE}"

ffmpeg_prefix_valid() {
  local dir="$1"
  [[ -n "${dir}" ]] \
    && [[ -f "${dir}/include/libavutil/avutil.h" ]] \
    && { [[ -f "${dir}/lib/libavcodec.dylib" ]] || [[ -f "${dir}/lib/libavcodec.a" ]]; }
}

probe_vt_in_prefix() {
  local dir="$1"
  local libav
  libav="$(find "${dir}/lib" -maxdepth 1 \( -name 'libavcodec*.dylib' -o -name 'libavcodec*.so' \) 2>/dev/null | head -1)"
  if [[ -n "${libav}" && -f "${libav}" ]] \
    && strings "${libav}" 2>/dev/null | grep -q hevc_videotoolbox; then
    return 0
  fi
  return 1
}

if [[ -z "${FFMPEG_DIR:-}" ]]; then
  for candidate in \
    "${HOME}/.cache/rust_image/ffmpeg-macos-vt" \
    "${RUST_VIDEO}/tools/ffmpeg/dist/macos-vt" \
    "${RUST_VIDEO}/tools/ffmpeg/dist/apple/${TRIPLE}" \
    "${RUST_VIDEO}/tools/ffmpeg/build/apple/${TRIPLE}" \
    "${RUST_VIDEO}/tools/ffmpeg/dist/macos/${TRIPLE}"; do
    if ffmpeg_prefix_valid "${candidate}"; then
      export FFMPEG_DIR="${candidate}"
      break
    fi
  done
fi

if ffmpeg_prefix_valid "${FFMPEG_DIR:-}"; then
  export PKG_CONFIG_PATH="${FFMPEG_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
  echo "==> FFMPEG_DIR=${FFMPEG_DIR}"
  if probe_vt_in_prefix "${FFMPEG_DIR}"; then
    echo "==> hevc_videotoolbox hwaccel found under ${FFMPEG_DIR}"
  else
    echo "==> WARN: ${FFMPEG_DIR} libavcodec missing hevc_videotoolbox hwaccel"
    echo "    Run: bash scripts/build-ffmpeg-macos-vt.sh"
  fi
else
  if command -v brew >/dev/null 2>&1 && ffmpeg_prefix_valid "$(brew --prefix ffmpeg 2>/dev/null)"; then
    export FFMPEG_DIR="$(brew --prefix ffmpeg)"
    export PKG_CONFIG_PATH="${FFMPEG_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"
    echo "==> WARN: Using Homebrew FFmpeg at ${FFMPEG_DIR}"
    echo "    Homebrew usually lacks hevc_videotoolbox — SW DECODE only."
    echo "    Build VT FFmpeg: bash scripts/build-ffmpeg-macos-vt.sh"
  else
    echo "ERROR: No valid FFMPEG_DIR (need include/libavutil/avutil.h and lib/libavcodec)" >&2
    echo "  Run: bash scripts/build-ffmpeg-macos-vt.sh" >&2
    echo "  Then: export FFMPEG_DIR=\"\${HOME}/.cache/rust_image/ffmpeg-macos-vt\"" >&2
    exit 1
  fi
fi

if command -v pkg-config >/dev/null 2>&1; then
  echo "==> pkg-config libavcodec: $(PKG_CONFIG_PATH="${PKG_CONFIG_PATH}" pkg-config --modversion libavcodec 2>/dev/null || echo '?')"
fi

echo "==> flutter_rust_bridge_codegen"
(cd "${PKG}" && flutter_rust_bridge_codegen generate)

echo "==> cargo build (release, ${TRIPLE})"
(
  cd "${PKG}/rust"
  export FFMPEG_DIR
  export PKG_CONFIG_PATH
  export CFLAGS="-I${FFMPEG_DIR}/include ${CFLAGS:-}"
  export CXXFLAGS="-I${FFMPEG_DIR}/include ${CXXFLAGS:-}"
  cargo build --release --target "${TRIPLE}"
  cargo test test_probe_decode_capabilities -- --nocapture 2>&1 | tail -8
)

echo "==> melos bootstrap (if available)"
(cd "${REPO_ROOT}" && dart pub get >/dev/null 2>&1 && dart run melos bootstrap >/dev/null 2>&1) || true

echo "==> flutter clean + run example"
(cd "${EXAMPLE}" && flutter clean && flutter pub get)
(cd "${EXAMPLE}/macos" && pod install)
(cd "${EXAMPLE}" && flutter run -d macos)

echo ""
echo "==> Phase 0 success checklist in app console:"
echo "    [Phase0] hevc_videotoolbox=true ready_for_hevc_hw=true"
echo "    Header badge: HW HEVC OK (not SW DECODE)"
echo "    [VideoDecoder] Hardware decoder 'hevc_videotoolbox' opened: ..."
echo "    [Status] drift < 500ms  VQ > 0 during playback"
