import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../rust_image_editor.dart';
import 'editor_screen.dart';
import 'editor_session.dart';
import 'rust_image_editor_config.dart';
import 'services/image_source_picker.dart';
import 'state/editor_providers.dart';
import 'theme/app_theme.dart';

/// A drop-in, full-featured image editor widget powered by the high-performance
/// Rust [RustImageEditor] core and FFI bridge.
///
/// It supports cropping, rotating, applying color presets and mood swipes,
/// face beauty touch-ups, drawing strokes, and compositing layers.
///
/// Example usage:
/// ```dart
/// RustImageEditorWidget(
///   config: RustImageEditorConfig(
///     title: 'Lumina Studio',
///     initialImageBytes: imageBytes,
///     onExport: (bytes, info) {
///       // Handle exported JPEG/PNG bytes here
///     },
///   ),
/// )
/// ```
class RustImageEditorWidget extends StatefulWidget {
  const RustImageEditorWidget({
    super.key,
    required this.config,
  });

  /// The configuration settings for customizing the editor's behavior and layout.
  final RustImageEditorConfig config;

  @override
  State<RustImageEditorWidget> createState() => _RustImageEditorWidgetState();
}

class _RustImageEditorWidgetState extends State<RustImageEditorWidget> {
  /// The active [EditorSession] holding the image pipelines and graph.
  late final EditorSession _session;
  
  /// True if this widget instance created and manages the lifecycle of [_session].
  late final bool _ownsSession;
  
  /// True when the native Rust libraries and GPU features are fully bootstrapped.
  bool _ready = false;
  
  /// Contains the bootstrapping error if native initialization failed.
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
      final inTest = !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';
      if (kDebugMode && !inTest) {
        debugPrint('RustImageEditorWidget init failed: $e');
        debugPrint('$st');
      } else if (inTest) {
        debugPrint('RustImageEditorWidget init failed (test): $e');
      }
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

    return ProviderScope(
      overrides: [
        editorSessionProvider.overrideWithValue(_session),
      ],
      child: Theme(
        data: theme,
        child: RustImageEditorView(
          config: widget.config,
          session: _session,
        ),
      ),
    );
  }
}
