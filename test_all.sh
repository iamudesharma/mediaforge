#!/usr/bin/env bash
#
# rust_image — run every layer of the test suite.
#
# Usage:
#   ./test_all.sh                          # rust + dart unit tests
#   RUN_INTEGRATION=1 ./test_all.sh        # also run on-device integration tests
#   TEST_DEVICE=macos ./test_all.sh        # pick a Flutter device id for integration
#   TEST_RUST_FEATURES="gpu,blurhash,avif" ./test_all.sh   # override cargo features
#
# Environment knobs:
#   TEST_RUST_FEATURES   cargo --features list for the Rust crate.
#                        Default: "gpu,blurhash". On hosts without NASM the
#                        AVIF encoder fails to build, so AVIF is opt-in via
#                        TEST_RUST_FEATURES=gpu,blurhash,avif.
#   TEST_DEVICE          Flutter device id passed to `flutter test -d`.
#                        Default: "macos". Requires a connected device/simulator.
#   RUN_INTEGRATION      Set to "1" to run on-device integration tests.
#                        Default: skipped (they need a device).
#
# One-time:
#   chmod +x test_all.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TEST_RUST_FEATURES="${TEST_RUST_FEATURES:-gpu,blurhash}"
TEST_DEVICE="${TEST_DEVICE:-macos}"
RUN_INTEGRATION="${RUN_INTEGRATION:-0}"

section() {
  echo
  echo "=============================================================="
  echo "  $1"
  echo "=============================================================="
}

section "Rust: cargo test --features ${TEST_RUST_FEATURES}"
(
  cd "${SCRIPT_DIR}/rust_image/rust"
  cargo test --features "${TEST_RUST_FEATURES}"
)

section "Dart unit tests: flutter test test/editor/"
(
  cd "${SCRIPT_DIR}/rust_image"
  flutter test test/editor/
)

if [[ "${RUN_INTEGRATION}" == "1" ]]; then
  section "Integration tests on device: ${TEST_DEVICE}"
  echo "  (requires a connected device/simulator; will build native code)"
  (
    cd "${SCRIPT_DIR}/rust_image/example"
    flutter test integration_test/ -d "${TEST_DEVICE}"
  )
else
  section "Integration tests: SKIPPED"
  echo "  Set RUN_INTEGRATION=1 (and TEST_DEVICE=<id>) to run them."
fi

section "All requested test layers passed."
