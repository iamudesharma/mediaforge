import 'package:flutter/material.dart';

import '../rust_image_editor.dart';
import 'editor_screen.dart';
import 'editor_session.dart';
import 'rust_image_editor_config.dart';
import 'services/image_source_picker.dart';
import 'theme/app_theme.dart';

/// Drop-in image editor powered by the Rust [RustImageEditor] core.
///
/// ```dart
/// RustImageEditorWidget(
///   config: RustImageEditorConfig(
///     title: 'Edit photo',
///     onExport: (bytes, info) => saveToGallery(bytes),
///   ),
/// )
/// ```
class RustImageEditorWidget extends StatefulWidget {
  const RustImageEditorWidget({
    super.key,
    required this.config,
  });

  final RustImageEditorConfig config;

  @override
  State<RustImageEditorWidget> createState() => _RustImageEditorWidgetState();
}

class _RustImageEditorWidgetState extends State<RustImageEditorWidget> {
  late final EditorSession _session;
  late final bool _ownsSession;
  bool _ready = false;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.config.session == null;
    _session = widget.config.session ?? EditorSession();
    _session
      ..backend = widget.config.defaultBackend
      ..liveEditMaxEdge = widget.config.liveEditMaxEdge
      ..previewMaxEdge = widget.config.previewMaxEdge
      ..showPerformanceInStatus = widget.config.showPerformanceInStatus
      ..useRgbaPreview = widget.config.useRgbaPreview
      ..useGpuTexturePreview = widget.config.useGpuTexturePreview
      ..showDebugFaceLandmarks = widget.config.showDebugFaceLandmarks
      ..enableLiveCameraBeauty = widget.config.enableLiveCameraBeauty
      ..liveCameraMaxEdge = widget.config.liveCameraMaxEdge
      ..liveCameraAnalyzeEveryNFrames =
          widget.config.liveCameraAnalyzeEveryNFrames
      ..enableMediaPipeDownloadPrompt =
          widget.config.enableMediaPipeDownloadPrompt;

    ImageSourcePicker.configure(
      pickImage: widget.config.pickImage,
      pickFromCamera: widget.config.pickFromCamera,
    );

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await RustImageEditor.ensureInitialized();
      await _session.refreshGpuInfo();
      final initial = widget.config.initialImageBytes;
      if (initial != null) {
        await _session.loadSource(initial);
      }
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e, st) {
      debugPrint('RustImageEditorWidget init failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _initError = e;
        _ready = true;
      });
    }
  }

  @override
  void dispose() {
    ImageSourcePicker.reset();
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme ?? AppTheme.dark();

    if (!_ready) {
      return Theme(
        data: theme,
        child: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_initError != null) {
      return Theme(
        data: theme,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not start image editor:\n$_initError',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    return Theme(
      data: theme,
      child: RustImageEditorView(
        config: widget.config,
        session: _session,
      ),
    );
  }
}
