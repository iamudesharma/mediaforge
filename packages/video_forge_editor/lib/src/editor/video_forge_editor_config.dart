import 'package:flutter/material.dart';

import '../models/video_export_result.dart';
import 'video_editor_session.dart';

/// Configuration for [VideoForgeEditorWidget].
class VideoForgeEditorConfig {
  const VideoForgeEditorConfig({
    this.title = 'Video Studio',
    this.theme,
    this.initialVideoPath,
    this.session,
    this.showDiagnostics = false,
    this.previewMaxEdge = 1080,
    this.onExport,
    this.onCancel,
    this.cacheSegment = 'video_forge_editor',
  });

  /// App bar title.
  final String title;

  /// Editor chrome theme. Defaults to Lumina dark when null.
  final ThemeData? theme;

  /// Local or remote video path to open on launch.
  final String? initialVideoPath;

  /// Optional shared session (for advanced embeds). Created internally when null.
  final VideoEditorSession? session;

  /// Show Rust runtime diagnostics overlay by default.
  final bool showDiagnostics;

  /// Max decode edge for GPU preview.
  final int previewMaxEdge;

  /// Called when export completes successfully.
  final void Function(VideoExportResult result)? onExport;

  /// Called when the user taps back without exporting.
  final VoidCallback? onCancel;

  /// Documents subdirectory for ingest/export cache.
  final String cacheSegment;
}
