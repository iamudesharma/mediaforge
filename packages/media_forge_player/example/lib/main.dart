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
      theme: ThemeData.dark(),
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
  String _diag = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onValue);
    _controller.diagnostics.listen((d) {
      if (mounted) setState(() => _diag = d.toString());
    });
  }

  void _onValue() {
    if (mounted) setState(() {});
  }

  Future<void> _pickFile() async {
    final r =
        await FilePicker.platform.pickFiles(type: FileType.video);
    final path = r?.files.single.path;
    if (path == null) return;
    await _controller.open(MediaForgeMedia.file(path), play: true);
  }

  Future<void> _openUrl() async {
    await _controller.open(
      MediaForgeMedia.network(_url.text.trim()),
      play: true,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onValue);
    _controller.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;
    return Scaffold(
      appBar: AppBar(title: const Text('media_forge_player')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: v.aspectRatio,
            child: MediaForgeVideo(controller: _controller),
          ),
          Slider(
            min: 0,
            max: v.duration.inMilliseconds.toDouble().clamp(1, 1e12),
            value: v.position.inMilliseconds
                .toDouble()
                .clamp(0, v.duration.inMilliseconds.toDouble().clamp(1, 1e12)),
            onChanged: (ms) =>
                _controller.seek(Duration(milliseconds: ms.round())),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(
                    v.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () =>
                    v.isPlaying ? _controller.pause() : _controller.play(),
              ),
              IconButton(
                icon: const Icon(Icons.stop),
                onPressed: _controller.stop,
              ),
              IconButton(
                icon: Icon(v.isMuted ? Icons.volume_off : Icons.volume_up),
                onPressed: () => _controller.setMuted(!v.isMuted),
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 1,
                  value: v.volume,
                  onChanged: (x) => _controller.setVolume(x),
                ),
              ),
            ],
          ),
          if (v.audioTracks.isNotEmpty || v.subtitleTracks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (v.audioTracks.isNotEmpty)
                    Expanded(
                      child: DropdownButton<int?>(
                        value: v.selectedAudioTrackId,
                        hint: const Text('Audio'),
                        isExpanded: true,
                        items: v.audioTracks
                            .map((t) => DropdownMenuItem<int?>(
                                  value: t.id,
                                  child: Text(
                                      t.label ?? t.language ?? 'Track ${t.id}'),
                                ))
                            .toList(),
                        onChanged: (id) => _controller.selectAudioTrack(id),
                      ),
                    ),
                  if (v.subtitleTracks.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<int?>(
                        value: v.selectedSubtitleTrackId,
                        hint: const Text('Subtitles off'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('Off')),
                          ...v.subtitleTracks.map((t) =>
                              DropdownMenuItem<int?>(
                                value: t.id,
                                child: Text(t.label ??
                                    t.language ??
                                    'Track ${t.id}'),
                              )),
                        ],
                        onChanged: (id) =>
                            _controller.selectSubtitleTrack(id),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _url)),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _openUrl, child: const Text('Open URL')),
                const SizedBox(width: 8),
                ElevatedButton(
                    onPressed: _pickFile, child: const Text('File')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_diag, style: const TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
