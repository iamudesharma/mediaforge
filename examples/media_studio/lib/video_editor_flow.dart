import 'package:flutter/material.dart';
import 'package:video_forge_editor/video_forge_editor.dart';

/// Thin wrapper around [VideoForgeEditorWidget] for Media Studio navigation.
class VideoEditorFlow extends StatelessWidget {
  const VideoEditorFlow({
    super.key,
    required this.initialPath,
    this.displayName,
    this.initialPosition,
    this.cacheKey,
  });

  final String initialPath;
  final String? displayName;

  /// Resume position for cached remote sources (0/absent = start).
  final Duration? initialPosition;

  /// Cache key for persisting the playhead across opens.
  final String? cacheKey;

  @override
  Widget build(BuildContext context) {
    return VideoForgeEditorWidget(
      config: VideoForgeEditorConfig(
        title: displayName ?? 'Video Creator',
        initialVideoPath: initialPath,
        showDiagnostics: false,
        onExport: (result) => Navigator.pop(context, result),
        onCancel: () => Navigator.pop(context),
        initialPosition: initialPosition,
        cacheKey: cacheKey,
      ),
    );
  }
}
