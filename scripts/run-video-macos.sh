#!/usr/bin/env bash
# Build video_processor_core and run the full Flutter example on macOS.
# Run from anywhere: bash scripts/run-video-macos.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec "${REPO_ROOT}/rust video/scripts/run-macos.sh"
