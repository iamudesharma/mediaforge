import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_forge_editor/video_forge_editor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VideoEditorExampleApp());
}

class VideoEditorExampleApp extends StatelessWidget {
  const VideoEditorExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Forge Editor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key});

  Future<void> _pickAndEdit(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowCompression: false,
    );
    final path = result?.files.single.path;
    if (path == null || !context.mounted) return;

    final export = await Navigator.push<VideoExportResult?>(
      context,
      MaterialPageRoute(
        builder: (_) => VideoForgeEditorWidget(
          config: VideoForgeEditorConfig(
            title: VideoInput.displayName(path),
            initialVideoPath: path,
            onExport: (r) => Navigator.pop(context, r),
          ),
        ),
      ),
    );

    if (export != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported to ${export.outputPath}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Forge Editor')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              onPressed: () => _pickAndEdit(context),
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Pick video to edit'),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'macOS: run from repo root:\n'
                'bash scripts/run-video-editor-macos.sh',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
