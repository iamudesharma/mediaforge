#!/usr/bin/env bash
# Build video_forge native libs, then run Media Studio on macOS.
# Run from anywhere: bash scripts/run-media-studio-macos.sh
# Skip the native rebuild (faster, may hit FRB hash mismatch): --no-rebuild
set -euo pipefail

# Homebrew rustc in PATH breaks cross-target macOS builds (missing std / FRB link).
if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${REPO_ROOT}/examples/media_studio"
REBUILD_SCRIPT="${REPO_ROOT}/scripts/rebuild-video-native-macos.sh"

SKIP_REBUILD=0
FLUTTER_ARGS=()
for arg in "$@"; do
  case "${arg}" in
    --no-rebuild) SKIP_REBUILD=1 ;;
    *) FLUTTER_ARGS+=("${arg}") ;;
  esac
done

if [[ ! -f "${APP}/lib/main.dart" ]]; then
  echo "ERROR: media_studio not found at:" >&2
  echo "  ${APP}/lib/main.dart" >&2
  exit 1
fi

if [[ "${SKIP_REBUILD}" -eq 0 ]]; then
  bash "${REBUILD_SCRIPT}"
else
  echo "==> Skipping native rebuild (--no-rebuild)"
fi

cd "${APP}"
if ((${#FLUTTER_ARGS[@]} > 0)); then
  exec flutter run -d macos "${FLUTTER_ARGS[@]}"
else
  exec flutter run -d macos
fi
