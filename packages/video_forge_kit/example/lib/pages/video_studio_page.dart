import 'package:flutter/material.dart';
import 'package:video_forge_editor/video_forge_editor.dart';

import '../demo_session.dart';

/// Full video editor tab — delegates to [VideoForgeEditorWidget].
class VideoStudioPage extends StatelessWidget {
  const VideoStudioPage({super.key, required this.session});

  final DemoSession session;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final path = session.selectedInput;
        if (path == null || path.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Pick a video on Showcase or Process tab first.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => session.pickVideo(context: context),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('Pick video'),
                ),
              ],
            ),
          );
        }

        return VideoForgeEditorWidget(
          config: VideoForgeEditorConfig(
            title: session.selectedName ?? 'Studio',
            initialVideoPath: path,
            cacheSegment: 'video_forge_kit_example',
            onExport: (result) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exported to ${result.outputPath}')),
              );
            },
          ),
        );
      },
    );
  }
}
