#!/bin/bash
# Run media_studio with all engine flags enabled.
# Usage: bash scripts/run-media-studio-engine.sh [device]
#   device defaults to "macos"

set -euo pipefail

DEVICE="${1:-macos}"

export VFP_ENGINE_VT_POOL=1
export VFP_ENGINE_RECOVERY=1
export VFP_ENGINE_PACER=1
export VFP_ENGINE_LIFECYCLE=1
export VFP_ENGINE_REFILL=1
export VFP_ENGINE_TELEMETRY=1
export VFP_ENGINE_TELEMETRY_INTERVAL_MS=2000

echo "[run] Engine flags enabled: VT_POOL RECOVERY PACER LIFECYCLE REFILL TELEMETRY"
echo "[run] Target device: $DEVICE"

cd "$(dirname "$0")/examples/media_studio"
flutter run -d "$DEVICE"
