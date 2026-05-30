#!/usr/bin/env bash
# Package libvideo_processor_core for iOS device (physical iPhone).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_PKG="${REPO_ROOT}/packages/video_processor_core"
TRIPLE="aarch64-apple-ios"
FFMPEG_DIR="${REPO_ROOT}/tools/ffmpeg/dist/apple/${TRIPLE}"

export PATH="${HOME}/.cargo/bin:${PATH}"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export CARGO_TARGET_AARCH64_APPLE_IOS_LINKER="${REPO_ROOT}/tools/release/ios-clang-linker.sh"
chmod +x "${CARGO_TARGET_AARCH64_APPLE_IOS_LINKER}"
export CC_aarch64_apple_ios="xcrun -sdk iphoneos clang"
export CXX_aarch64_apple_ios="xcrun -sdk iphoneos clang++"
export AR_aarch64_apple_ios="xcrun -sdk iphoneos ar"
export CFLAGS_aarch64_apple_ios="-arch arm64 -miphoneos-version-min=16.0 -isysroot ${SDK_PATH}"
export LDFLAGS_aarch64_apple_ios="-arch arm64 -miphoneos-version-min=16.0 -isysroot ${SDK_PATH}"
export RUSTFLAGS_aarch64_apple_ios="-C link-arg=-miphoneos-version-min=16.0 -C link-arg=-isysroot -C link-arg=${SDK_PATH} -C link-arg=-Wl,-install_name,@rpath/video_processor_core.framework/video_processor_core"
export BINDGEN_EXTRA_CLANG_ARGS="-arch arm64 -miphoneos-version-min=16.0 -isysroot ${SDK_PATH} -I${FFMPEG_DIR}/include"
export RUSTUP_TOOLCHAIN="${RUSTUP_TOOLCHAIN:-1.88.0}"

FRAMEWORK_NAME="video_processor_core"
FRAMEWORK_DIR="${CORE_PKG}/ios/Frameworks/${FRAMEWORK_NAME}.framework"
MANIFEST="${CORE_PKG}/rust/Cargo.toml"

if [[ ! -f "${MANIFEST}" ]]; then
  echo "Missing ${MANIFEST} — run from rust_image monorepo." >&2
  exit 1
fi

if [[ ! -d "${FFMPEG_DIR}/lib" ]]; then
  echo "Missing FFmpeg for iOS at ${FFMPEG_DIR}" >&2
  echo "Build with: ./tools/ffmpeg/apple-ios-device.sh" >&2
  exit 1
fi

rustup toolchain install "${RUSTUP_TOOLCHAIN}"
rustup target add --toolchain "${RUSTUP_TOOLCHAIN}" "${TRIPLE}"

CARGO="$(rustup which cargo --toolchain "${RUSTUP_TOOLCHAIN}")"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-${CORE_PKG}/rust/target}"

echo "==> cargo build --target ${TRIPLE} (manifest ${MANIFEST})"
FFMPEG_DIR="${FFMPEG_DIR}" \
  PKG_CONFIG_PATH="${FFMPEG_DIR}/lib/pkgconfig" \
  PKG_CONFIG_ALLOW_CROSS=1 \
  "${CARGO}" build --release \
    --manifest-path "${MANIFEST}" \
    -p video_processor_core \
    --lib \
    --target "${TRIPLE}"

# iOS cdylib is often a .dylib or static; prefer dylib then static.
DYLIB="${CARGO_TARGET_DIR}/${TRIPLE}/release/lib${FRAMEWORK_NAME}.dylib"
STATIC="${CARGO_TARGET_DIR}/${TRIPLE}/release/lib${FRAMEWORK_NAME}.a"
if [[ -f "${DYLIB}" ]]; then
  BINARY="${DYLIB}"
elif [[ -f "${STATIC}" ]]; then
  BINARY="${STATIC}"
else
  echo "No iOS library artifact under ${CARGO_TARGET_DIR}/${TRIPLE}/release/" >&2
  exit 1
fi

rm -rf "${FRAMEWORK_DIR}"
mkdir -p "${FRAMEWORK_DIR}"

cp "${BINARY}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"
chmod +x "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

# Dylibs must not reference the Mac build path (causes white screen / dyld crash on device).
RPATH_ID="@rpath/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"
install_name_tool -id "${RPATH_ID}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" 2>/dev/null || true
if [[ -f "${DYLIB}" ]]; then
  # Rewrite cargo output paths only — never -change the dylib's own install_name onto itself.
  while IFS= read -r dep; do
    [[ -z "${dep}" ]] && continue
    [[ "${dep}" == "${RPATH_ID}" ]] && continue
    case "${dep}" in
      "${CARGO_TARGET_DIR}"/*|/var/*|/tmp/*|/Users/*|/Volumes/*)
        install_name_tool -change "${dep}" "${RPATH_ID}" \
          "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" 2>/dev/null || true
        ;;
    esac
  done < <(otool -L "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$' || true)
fi

cat > "${FRAMEWORK_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>dev.fluttervideoprocessor.core</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
  <key>MinimumOSVersion</key>
  <string>16.0</string>
</dict>
</plist>
EOF

echo "Created ${FRAMEWORK_DIR}"
