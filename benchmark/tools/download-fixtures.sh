#!/usr/bin/env bash
# Download local benchmark fixtures into benchmark-results/fixtures/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURES_DIR="${ROOT}/benchmark-results/fixtures"
CONFIG="${ROOT}/tools/benchmark/fixtures.json"

mkdir -p "${FIXTURES_DIR}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required (brew install jq)"
  exit 1
fi

echo "==> Downloading benchmark fixtures to ${FIXTURES_DIR}"

# Video tiers
while IFS= read -r url; do
  file="${FIXTURES_DIR}/$(basename "${url}")"
  if [[ -f "${file}" && -s "${file}" ]]; then
    echo "  skip (exists): $(basename "${file}")"
    continue
  fi
  echo "  download: ${url}"
  curl -fL --retry 3 --connect-timeout 30 -A "video_forge_kit-benchmark/1.0" \
    -o "${file}" "${url}"
done < <(jq -r '.tiers[].network_url' "${CONFIG}")

# Audio tracks (overlay mixing benchmarks)
while IFS= read -r url; do
  file="${FIXTURES_DIR}/$(basename "${url}")"
  if [[ -f "${file}" && -s "${file}" ]]; then
    echo "  skip (exists): $(basename "${file}")"
    continue
  fi
  echo "  download: ${url}"
  curl -fL --retry 3 --connect-timeout 30 -A "video_forge_kit-benchmark/1.0" \
    -o "${file}" "${url}"
done < <(jq -r '.audio_tracks[]?.network_url // empty' "${CONFIG}")

echo "==> Done. Files:"
ls -lh "${FIXTURES_DIR}"
