import 'package:flutter/material.dart';

import '../services/editor_output_paths.dart';
import '../services/media_ingest.dart';
import '../theme/app_theme.dart';
import '../video_forge_editor.dart';
import 'video_editor_screen.dart';
import 'video_editor_session.dart';
import 'video_forge_editor_config.dart';

/// Drop-in CapCut-style video editor powered by [VideoForgeEditor].
class VideoForgeEditorWidget extends StatefulWidget {
  const VideoForgeEditorWidget({
    super.key,
    required this.config,
  });

  final VideoForgeEditorConfig config;

  @override
  State<VideoForgeEditorWidget> createState() => _VideoForgeEditorWidgetState();
}

class _VideoForgeEditorWidgetState extends State<VideoForgeEditorWidget> {
  late final VideoEditorSession _session;
  late final bool _ownsSession;
  bool _ready = false;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.config.session == null;
    _session = widget.config.session ?? VideoEditorSession();
    EditorOutputPaths.configure(cacheSegment: widget.config.cacheSegment);
    MediaIngest.configure(ingestSegment: '${widget.config.cacheSegment}/ingest');
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await VideoForgeEditor.ensureInitialized();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e, st) {
      debugPrint('[VideoEditor] init failed: $e\n$st');
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Video editor failed to initialize:\n$_initError',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final theme = widget.config.theme ?? AppTheme.dark();
    return Theme(
      data: theme,
      child: VideoEditorScreen(config: widget.config),
    );
  }
}
