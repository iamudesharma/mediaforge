#!/usr/bin/env bash
# Optional: download MediaPipe Tasks models for full 468-point face mesh (replaces Vision fallback).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/darwin/Resources/mediapipe"
mkdir -p "$DEST"

FACE_URL="https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
SEG_URL="https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.task"

echo "Downloading face_landmarker.task..."
curl -L "$FACE_URL" -o "$DEST/face_landmarker.task"
echo "Downloading selfie_segmenter.task..."
curl -L "$SEG_URL" -o "$DEST/selfie_segmenter.task"
echo "Done. Add darwin/Resources/mediapipe to podspec resource_bundles when enabling MediaPipe."
