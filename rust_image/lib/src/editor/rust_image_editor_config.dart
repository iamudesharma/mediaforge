import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;

import '../rust_image_editor.dart';
import 'editor_session.dart';
import 'layout/editor_layout.dart';
import 'panels/tool_panels.dart';

/// Configuration for [RustImageEditorWidget] — tools, theme, callbacks, and pickers.
class RustImageEditorConfig {
  const RustImageEditorConfig({
    this.title = 'Lumina',
    this.theme,
    this.enabledTools = const [
      EditorTool.import,
      EditorTool.transform,
      EditorTool.filters,
      EditorTool.beauty,
      EditorTool.adjust,
      EditorTool.draw,
      EditorTool.layers,
      EditorTool.overlay,
      EditorTool.paint,
      EditorTool.stickers,
      EditorTool.advanced,
      EditorTool.export_,
    ],
    this.initialImageBytes,
    this.pickImage,
    this.pickFromCamera,
    this.onImageChanged,
    this.onExport,
    this.onCompareHoldStart,
    this.onCompareHoldEnd,
    this.showCompare = true,
    this.allowBlankCanvas = true,
    this.defaultBackend = ProcessingBackend.auto,
    this.liveEditMaxEdge = EditorPipelineDefaults.liveEditMaxEdge,
    this.previewMaxEdge = EditorPipelineDefaults.previewMaxEdge,
    this.showPerformanceInStatus = true,
    this.useRgbaPreview = true,
    this.useGpuTexturePreview = false,
    this.layoutMode = EditorLayoutMode.auto,
    this.toolBarPlacement = EditorToolBarPlacement.auto,
    this.showMobileMetaOverlay = true,
    this.showCanvasFloatingChrome = true,
    this.enableSwipeMoodFilters = true,
    this.swipeMoodFilterStrength = 1.0,
    this.enableSwipeBeautyLooks = true,
    this.enableLiveCameraBeauty = true,
    this.showDebugFaceLandmarks = false,
    this.liveCameraMaxEdge = 720,
    this.liveCameraAnalyzeEveryNFrames = 3,
    this.enableMediaPipeDownloadPrompt = true,
    this.session,
  });

  /// App bar / studio title shown on wide layouts.
  final String title;

  /// Editor chrome theme. Defaults to dark studio theme when null.
  final ThemeData? theme;

  /// Which tool tabs appear in the rail / tab strip.
  final List<EditorTool> enabledTools;

  /// Load this image when the editor opens (after Rust init).
  final Uint8List? initialImageBytes;

  /// Custom image picker (gallery/files). When null, uses platform file_selector / image_picker.
  final Future<Uint8List?> Function()? pickImage;

  /// Custom camera capture. When null, uses image_picker on mobile only.
  final Future<Uint8List?> Function()? pickFromCamera;

  /// Called when the working image bytes change (after edits).
  final void Function(EditorSession session, Uint8List bytes)? onImageChanged;

  /// Optional custom export handler. When null, **Export image** saves to
  /// Photos/gallery (mobile), Downloads (Windows/Linux), or app Documents/Exports
  /// (macOS sandbox) via [ImageExportSaver].
  final void Function(Uint8List bytes, ImageInfo info)? onExport;

  /// Example / host apps: snackbars or analytics when the user holds compare.
  final VoidCallback? onCompareHoldStart;

  /// Called when compare hold / hover ends.
  final VoidCallback? onCompareHoldEnd;

  final bool showCompare;

  /// Sprint 8 — show "Create blank canvas" on the Import tool.
  final bool allowBlankCanvas;
  final ProcessingBackend defaultBackend;

  /// Max edge for live slider / preview filters (Phase 1).
  final int liveEditMaxEdge;

  /// Max edge for JPEG preview shown in the canvas.
  final int previewMaxEdge;

  /// Append filter path and stage timings to the status line (Phase 0).
  final bool showPerformanceInStatus;

  /// Sprint 4 — show preview via [decodeImageFromPixels] (no per-frame JPEG).
  final bool useRgbaPreview;

  /// Sprint 11b.2 — Flutter [Texture] preview via GPU surface (macOS first).
  /// Falls back to [useRgbaPreview] when unavailable.
  final bool useGpuTexturePreview;

  /// [EditorLayoutMode.auto]: sidebar ≥900px wide, immersive stack on phones.
  final EditorLayoutMode layoutMode;

  /// Tool icon rail on immersive layout ([EditorToolBarPlacement.auto] = bottom).
  final EditorToolBarPlacement toolBarPlacement;

  /// Small dimensions pill over the canvas on mobile (immersive layout).
  final bool showMobileMetaOverlay;

  /// Flip + compact layers popover on the canvas (mobile); layers omitted from bottom nav.
  final bool showCanvasFloatingChrome;

  /// Sprint 11 — swipe left/right on preview for mood filters (Rose, Clarendon, …).
  final bool enableSwipeMoodFilters;

  /// Strength for swipe mood filters (0–1, default full like Instagram).
  final double swipeMoodFilterStrength;

  /// Nexus C — swipe left/right on preview for beauty looks (Beauty tool only).
  final bool enableSwipeBeautyLooks;

  /// Nexus A — front-camera live beauty preview (mobile).
  final bool enableLiveCameraBeauty;

  /// Nexus A — draw landmark dots on preview (dev / debug).
  final bool showDebugFaceLandmarks;

  /// Max long edge for live camera beauty processing.
  final int liveCameraMaxEdge;

  /// Run native face analysis every N camera frames (temporal smooth between).
  final int liveCameraAnalyzeEveryNFrames;

  /// Nexus D — offer optional MediaPipe model download in Beauty panel.
  final bool enableMediaPipeDownloadPrompt;

  /// Optional external session (you manage [EditorSession.dispose]).
  final EditorSession? session;
}

/// Default pipeline limits (see [ROADMAP.md] at repo root).
abstract final class EditorPipelineDefaults {
  static const liveEditMaxEdge = 1280;
  static const previewMaxEdge = 1280;
  static const previewQuality = 82;
}
