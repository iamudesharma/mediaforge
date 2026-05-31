import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class StatusPreviewPage extends StatefulWidget {
  const StatusPreviewPage({super.key, required this.videoPath, this.title});

  final String videoPath;
  final String? title;

  @override
  State<StatusPreviewPage> createState() => _StatusPreviewPageState();
}

class _StatusPreviewPageState extends State<StatusPreviewPage> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!File(widget.videoPath).existsSync()) return;
    final c = VideoPlayerController.file(File(widget.videoPath));
    await c.initialize();
    await c.setLooping(true);
    await c.play();
    if (mounted) setState(() => _controller = c);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title ?? 'Status preview'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: c == null || !c.value.isInitialized
            ? const CircularProgressIndicator()
            : AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
      ),
    );
  }
}
