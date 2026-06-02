import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:image_forge_editor/image_forge_editor.dart';
import 'package:media_forge/media_forge.dart'
    as media_runtime show RustLib;

import 'home_hub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize all native engines: image editor + the Rust media runtime
  // (single playback path for both timeline preview and the home status player).
  try {
    await VideoProcessor.initialize();
    await RustImageEditor.ensureInitialized();
    await media_runtime.RustLib.init();
  } catch (e) {
    debugPrint('Native engine initialization warning: $e');
  }

  runApp(const MediaStudioApp());
}

class MediaStudioApp extends StatelessWidget {
  const MediaStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6200EE),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFBB86FC),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: 'Outfit', // A premium typography feel
      ),
      home: const HomeHub(),
    );
  }
}
