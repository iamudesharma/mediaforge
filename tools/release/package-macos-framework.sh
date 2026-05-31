#!/usr/bin/env bash
# Package libvideo_forge.dylib as a macOS framework for CocoaPods / FRB.
set -euo pipefail

# tools/release -> repo root
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_PKG="${REPO_ROOT}/packages/video_forge"
FRAMEWORK_NAME="video_forge"
FRAMEWORK_DIR="${CORE_PKG}/macos/Frameworks/${FRAMEWORK_NAME}.framework"
DYLIB_SRC="${CORE_PKG}/target/release/lib${FRAMEWORK_NAME}.dylib"

if [[ ! -f "${DYLIB_SRC}" ]]; then
  echo "Building Rust core..."
  (cd "${CORE_PKG}" && cargo build --release -p video_forge)
fi

if [[ ! -f "${DYLIB_SRC}" ]]; then
  echo "Missing ${DYLIB_SRC}" >&2
  exit 1
fi

VERSIONS="${FRAMEWORK_DIR}/Versions/A"
mkdir -p "${VERSIONS}/Resources"

cp "${DYLIB_SRC}" "${VERSIONS}/${FRAMEWORK_NAME}"
chmod +x "${VERSIONS}/${FRAMEWORK_NAME}"

install_name_tool -id "@rpath/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}" \
  "${VERSIONS}/${FRAMEWORK_NAME}" 2>/dev/null || true

ln -sfh A "${FRAMEWORK_DIR}/Versions/Current"
ln -sfh "Versions/Current/${FRAMEWORK_NAME}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"
ln -sfh Versions/Current/Resources "${FRAMEWORK_DIR}/Resources"

cat > "${VERSIONS}/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>dev.video_forge.${FRAMEWORK_NAME}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${FRAMEWORK_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>0.2.0</string>
</dict>
</plist>
EOF

echo "Created ${FRAMEWORK_DIR}"
