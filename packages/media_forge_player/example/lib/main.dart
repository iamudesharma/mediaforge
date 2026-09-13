import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_forge/media_forge.dart' show RustLib;
import 'package:media_forge_player/media_forge_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const PlayerExampleApp());
}

class PlayerExampleApp extends StatelessWidget {
  const PlayerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'media_forge_player',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4EDEA3),
          brightness: Brightness.dark,
        ),
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final MediaForgePlayerController _controller =
      MediaForgePlayerController();
  final _url = TextEditingController(
    text: 'http://127.0.0.1:8080/stream',
  );
  String _fileName = '';

  Future<void> _pickFile() async {
    final r =
        await FilePicker.platform.pickFiles(type: FileType.video);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() => _fileName = r?.files.single.name ?? path);
    await _controller.open(MediaForgeMedia.file(path), play: true);
  }

  Future<void> _openUrl() async {
    final url = _url.text.trim();
    setState(() => _fileName = url);
    await _controller.open(
      MediaForgeMedia.network(url, reconnect: true),
      play: true,
    );
  }

  Future<Uri?> _pickSubtitle() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa'],
    );
    final path = r?.files.single.path;
    if (path == null) return null;
    return Uri.file(path);
  }

  @override
  void dispose() {
    _controller.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('media_forge_player'),
        actions: [
          IconButton(
            icon: const Icon(Icons.link_outlined),
            tooltip: 'Open stream URL',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Open network stream'),
                content: TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    hintText: 'http://127.0.0.1:8080/stream',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _openUrl();
                    },
                    child: const Text('Open'),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.video_library_outlined),
            tooltip: 'Open file',
            onPressed: _pickFile,
          ),
        ],
      ),
      body: MediaPlayerScreen(
        controller: _controller,
        title: _fileName.isEmpty ? 'No media' : _fileName,
        subtitle: _fileName.isEmpty
            ? 'Open a file or stream to start'
            : null,
        onPickExternalSubtitle: _pickSubtitle,
      ),
    );
  }
}
