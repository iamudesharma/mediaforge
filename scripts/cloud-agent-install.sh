#!/usr/bin/env bash
# Idempotent Cloud Agent bootstrap for the MediaForge monorepo.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter}"
export PATH="${FLUTTER_ROOT}/bin:${HOME}/.cargo/bin:${PATH}"

install_flutter() {
  if [[ -x "${FLUTTER_ROOT}/bin/flutter" ]]; then
    echo "[cloud-agent-install] Flutter already present at ${FLUTTER_ROOT}"
    return 0
  fi
  echo "[cloud-agent-install] Installing Flutter stable to ${FLUTTER_ROOT}"
  git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "${FLUTTER_ROOT}"
}

configure_rust() {
  if ! command -v rustup >/dev/null 2>&1; then
    echo "[cloud-agent-install] rustup not found; install Rust in the base image" >&2
    exit 1
  fi
  rustup default stable
  rustup target add \
    aarch64-linux-android \
    armv7-linux-androideabi \
    x86_64-linux-android \
    i686-linux-android
  rustup component add rustfmt clippy
}

bootstrap_workspace() {
  cd "${REPO_ROOT}"
  echo "[cloud-agent-install] dart pub get + melos bootstrap"
  dart pub get
  dart run melos bootstrap
  echo "[cloud-agent-install] precaching Flutter Linux artifacts"
  flutter config --no-analytics
  flutter precache --linux
}

prefetch_rust_artifacts() {
  # Linux CI validates video_forge Rust; image_forge defaults include Apple-only GPU.
  echo "[cloud-agent-install] Prefetching video_forge + image_forge_core Rust artifacts"
  (
    cd "${REPO_ROOT}/packages/video_forge"
    cargo fetch
    cargo test -p video_forge --no-run
  )
  (
    cd "${REPO_ROOT}/packages/image_forge_core/rust"
    cargo fetch
    cargo test --features blurhash --no-default-features --no-run
  )
}

install_flutter
configure_rust
bootstrap_workspace
prefetch_rust_artifacts

echo "[cloud-agent-install] done flutter=$(flutter --version | head -1) rustc=$(rustc --version)"
