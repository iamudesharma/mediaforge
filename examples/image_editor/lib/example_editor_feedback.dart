import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide ImageInfo;
import 'package:image_forge_editor/image_forge_editor.dart';

/// Example host: snackbars for export and compare without changing editor UI.
class ExampleEditorPage extends StatefulWidget {
  const ExampleEditorPage({super.key});

  @override
  State<ExampleEditorPage> createState() => _ExampleEditorPageState();
}

class _ExampleEditorPageState extends State<ExampleEditorPage> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  late final EditorSession _session;

  @override
  void initState() {
    super.initState();
    _session = EditorSession();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool error = false}) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: error ? const Color(0xFFB3261E) : null,
      ),
    );
  }

  static String _friendlyExportMessage(String status) {
    if (status.startsWith('Saved to Photos')) {
      return 'Export complete — saved to Photos';
    }
    if (status.startsWith('Saved to gallery')) {
      return 'Export complete — saved to gallery';
    }
    if (status.startsWith('Saved to Exports')) {
      return 'Export complete — $status';
    }
    if (status.startsWith('Saved to ')) {
      return 'Export complete — $status';
    }
    return 'Export complete';
  }

  void _onExport(Uint8List bytes, ImageInfo info) {
    unawaited(_saveExport(bytes));
  }

  Future<void> _saveExport(Uint8List bytes) async {
    try {
      final msg = await ImageExportSaver.save(bytes: bytes, format: _session.outputFormat);
      if (!mounted) return;
      _showSnack(_friendlyExportMessage(msg));
    } catch (e) {
      if (!mounted) return;
      _showSnack('Export failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: AppTheme.dark(),
      home: RustImageEditorWidget(
        config: RustImageEditorConfig(
          useRgbaPreview: true,
          showPerformanceInStatus: true,
          useGpuTexturePreview: true,
          title: 'Lumina',
          session: _session,
          onExport: _onExport,
          onCompareHoldStart: () => _showSnack('Showing original'),
          onCompareHoldEnd: () => _showSnack('Back to edited image'),
        ),
      ),
    );
  }
}
