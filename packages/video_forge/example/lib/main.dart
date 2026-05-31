import 'package:flutter/material.dart';
import 'package:video_forge/video_forge.dart';

/// Minimal example: initialize FRB and show API surface (no sample file bundled).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NativeBindings.ensureInitialized();
  runApp(const VideoCoreExampleApp());
}

class VideoCoreExampleApp extends StatelessWidget {
  const VideoCoreExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('video_forge')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Engine ready. Call getMediaInfo(path:) or startCompress from '
            'package:video_forge after adding a video path.',
          ),
        ),
      ),
    );
  }
}
