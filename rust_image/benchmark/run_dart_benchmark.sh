#!/usr/bin/env bash
# Flutter benchmark runner (Node/Bun-style script for this repo).
#
# Default: real Flutter app on macOS (plugin-linked native lib, like production).
#   BENCH_PIPELINE=direct|worker|both
#
# CI / headless:  ./run_dart_benchmark.sh test
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
EXAMPLE="$ROOT/../example"
RUST_DIR="$ROOT/../rust"

export BENCH_SYNTHETIC="${BENCH_SYNTHETIC:-1}"
export BENCH_ITERATIONS="${BENCH_ITERATIONS:-10}"
export BENCH_PIPELINE="${BENCH_PIPELINE:-direct}"
export BENCH_HEADLESS="${BENCH_HEADLESS:-1}"

MODE="${1:-flutter}"
shift || true

cd "$EXAMPLE"
flutter pub get

if [[ "$MODE" == "test" ]]; then
  echo "CI mode: flutter test (headless; loads release dylib manually)…"
  (cd "$RUST_DIR" && cargo build --release --features gpu)
  if [[ "$(uname -s)" == "Darwin" ]]; then
    for candidate in \
      "$RUST_DIR/target/release/librust_image_core.dylib" \
      "$RUST_DIR/target/release/deps/librust_image_core.dylib"; do
      if [[ -f "$candidate" ]]; then export RUST_IMAGE_DYLIB="$candidate"; break; fi
    done
  fi
  flutter test test/api_benchmark_test.dart "$@"
  exit 0
fi

if [[ "$MODE" == "rust" ]]; then
  exec cargo run --manifest-path "$RUST_DIR/Cargo.toml" --release --features gpu \
    --bin rust_image_benchmark -- --synthetic --iterations "$BENCH_ITERATIONS" "$@"
fi

DEVICE="${BENCH_DEVICE:-macos}"
echo "Flutter app benchmark (pipeline=$BENCH_PIPELINE, device=$DEVICE)…"
echo "  direct = RustImageEditor on main isolate (FRB)"
echo "  worker = RustWorker isolate (editor filters / preview)"
echo ""

# Unset manual dylib — use the plugin framework built into the Flutter app.
unset RUST_IMAGE_DYLIB

flutter run -d "$DEVICE" -t lib/benchmark_main.dart --release "$@"
