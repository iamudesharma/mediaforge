import 'package:flutter/material.dart';
import 'package:video_forge_editor/video_forge_editor.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

import 'home_hub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await VideoForgeEditor.ensureInitialized();
    await RustImageEditor.ensureInitialized();
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
