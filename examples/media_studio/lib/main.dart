import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:rust_image_editor/rust_image_editor.dart';
import 'package:rust_media_runtime/rust_media_runtime.dart'
    as media_runtime show RustLib;

import 'home_hub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dual initialization of native engines
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
