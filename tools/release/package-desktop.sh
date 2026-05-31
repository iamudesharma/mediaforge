#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${ROOT}/platform-build/desktop"
mkdir -p "${OUT}"

cd "${ROOT}/native/rust_core"

if [[ "$(uname -s)" == "Linux" ]]; then
  cargo build --release --target x86_64-unknown-linux-gnu
  cp "${ROOT}/target/x86_64-unknown-linux-gnu/release/libvideo_forge.so" "${OUT}/"
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  cargo build --release --target x86_64-apple-darwin
  cargo build --release --target aarch64-apple-darwin
  cp "${ROOT}/target/x86_64-apple-darwin/release/libvideo_forge.dylib" "${OUT}/"
fi

tar -czf "${OUT}/desktop.tar.gz" -C "${OUT}" .
echo "Desktop artifact: ${OUT}/desktop.tar.gz"
