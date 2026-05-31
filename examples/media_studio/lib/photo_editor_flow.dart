import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide ImageInfo;
import 'package:image_forge_editor/image_forge_editor.dart';
import 'package:path_provider/path_provider.dart';

class PhotoEditorFlow extends StatefulWidget {
  const PhotoEditorFlow({
    super.key,
    required this.initialBytes,
    required this.title,
  });

  final Uint8List initialBytes;
  final String title;

  @override
  State<PhotoEditorFlow> createState() => _PhotoEditorFlowState();
}

class _PhotoEditorFlowState extends State<PhotoEditorFlow> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

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

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: RustImageEditorWidget(
          config: RustImageEditorConfig(
            title: widget.title,
            initialImageBytes: widget.initialBytes,
            useRgbaPreview: true,
            showPerformanceInStatus: true,
            useGpuTexturePreview: true,
            enableMediaPipeDownloadPrompt: false, // Avoid downloading face landmark models automatically to reduce first-open delay
            onExport: (bytes, info) async {
              _showSnack('Saving export…');
              String path = '';
              try {
                // 1. Try to save to system photos / downloads
                final msg = await ImageExportSaver.save(
                  bytes: bytes,
                  format: OutputFormat.jpeg,
                );
                _showSnack(_friendlyExportMessage(msg));
              } catch (e) {
                _showSnack('Gallery save failed: $e', error: true);
              }

              try {
                // 2. Save a local temp copy so the Home Hub has a file path to preview
                final tempDir = await getTemporaryDirectory();
                final file = File('${tempDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg');
                await file.writeAsBytes(bytes);
                path = file.path;
              } catch (e) {
                debugPrint('Temp save failed: $e');
              }

              // Return the path to Home Hub or Poster Bridge
              if (context.mounted) {
                Navigator.pop(context, path);
              }
            },
            onCompareHoldStart: () => _showSnack('Showing original'),
            onCompareHoldEnd: () => _showSnack('Back to edited image'),
          ),
        ),
      ),
    );
  }
}
