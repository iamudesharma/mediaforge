import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;

import '../image_forge_editor.dart';
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
    this.enableSwipeLooks = true,
    this.swipeLookStrength = 1.0,
    this.enableSwipeBeautyLooks = false,
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

  /// Whether to show the compare button (allowing users to hold down to see the original image).
  final bool showCompare;

  /// Whether to show "Create blank canvas" option on the Import tool.
  final bool allowBlankCanvas;

  /// Default processing backend (CPU, GPU, or Auto).
  final ProcessingBackend defaultBackend;

  /// Max edge for live slider / preview filters (reduces latency during adjustments).
  final int liveEditMaxEdge;

  /// Max edge for the main JPEG preview shown in the canvas.
  final int previewMaxEdge;

  /// Append filter path and stage timings to the status line (helpful for debugging).
  final bool showPerformanceInStatus;

  /// Show preview using Dart's Rgba pixel buffer display (skipping per-frame JPEG encoding).
  final bool useRgbaPreview;

  /// Flutter [Texture] preview via GPU surface (macOS/iOS). Beauty **compute**
  /// uses wgpu on any platform where available (Sprint 22); this flag only
  /// selects Texture **display**. Falls back to [useRgbaPreview] when unavailable.
  final bool useGpuTexturePreview;

  /// The UI layout mode to adopt. Choose immersive stack for phone or sidebar on desktop.
  final EditorLayoutMode layoutMode;

  /// Placement of the bottom tool bar (only applicable on mobile immersive layout).
  final EditorToolBarPlacement toolBarPlacement;

  /// Whether to display a small dimensions and performance pill over the canvas on mobile.
  final bool showMobileMetaOverlay;

  /// Whether to display flip + compact layers popover buttons directly on the canvas (mobile).
  final bool showCanvasFloatingChrome;

  /// Swipe left/right on the canvas preview to apply combo grades (Glass Skin, Golden Hour, etc.).
  final bool enableSwipeLooks;

  /// Strength multiplier for the swipe combo looks (0.0 to 1.0).
  final double swipeLookStrength;

  @Deprecated('Use enableSwipeLooks')
  bool get enableSwipeMoodFilters => enableSwipeLooks;

  @Deprecated('Use swipeLookStrength')
  double get swipeMoodFilterStrength => swipeLookStrength;

  /// Swipe left/right inside the beauty tab for tap looks.
  final bool enableSwipeBeautyLooks;

  /// Front-camera live beauty filter preview.
  final bool enableLiveCameraBeauty;

  /// Draw face landmark dots on preview (for developers and debug visibility).
  final bool showDebugFaceLandmarks;

  /// Max long edge size for live camera frames before face analysis.
  final int liveCameraMaxEdge;

  /// Analyze face landmark updates every N frames (with EMA smoothing in between).
  final int liveCameraAnalyzeEveryNFrames;

  /// Prompts users to download optional MediaPipe models for higher precision face tracking.
  final bool enableMediaPipeDownloadPrompt;

  /// Optional external session manager if you want to reuse or control [EditorSession] lifecycles.
  final EditorSession? session;
}

/// Default pipeline limits (see [ROADMAP.md] at repo root).
abstract final class EditorPipelineDefaults {
  static const liveEditMaxEdge = 1280;
  static const previewMaxEdge = 1280;
  static const previewQuality = 82;
}
