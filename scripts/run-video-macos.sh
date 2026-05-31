#!/usr/bin/env bash
# Build native libs and run the video_forge_kit example on macOS.
# Run from repo root: ./scripts/run-video-macos.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="${REPO_ROOT}/packages/video_forge"
EXAMPLE="${REPO_ROOT}/packages/video_forge_kit/example"

if [[ ! -d "${EXAMPLE}" ]]; then
  echo "Example app not found at ${EXAMPLE}" >&2
  exit 1
fi

echo "==> Building Rust core (release)..."
(cd "${CORE}" && cargo build --release -p video_forge)

echo "==> Flutter pub get (workspace)..."
(cd "${REPO_ROOT}" && dart pub get && dart run melos bootstrap)

echo "==> Flutter pub get (example)..."
cd "${EXAMPLE}"
flutter pub get

echo "==> CocoaPods install..."
(cd macos && pod install)

echo "==> Running on macOS..."
flutter run -d macos
