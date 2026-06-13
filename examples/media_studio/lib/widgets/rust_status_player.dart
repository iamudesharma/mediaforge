import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_forge/media_forge.dart';
import 'package:video_forge_editor/video_forge_editor.dart';

/// Minimal Rust-backed status preview player.
///
/// Owns a single [RustPlaybackBackend] + [MediaPlaybackPresenter] tied to a unique GPU
/// texture handle. Autoplays on open, loops at end of stream, and releases
/// all resources in [dispose].
class RustStatusPlayer extends StatefulWidget {
  const RustStatusPlayer({super.key, required this.path});

  final String path;

  @override
  State<RustStatusPlayer> createState() => _RustStatusPlayerState();
}

class _RustStatusPlayerState extends State<RustStatusPlayer> {
  static int _handleCounter = 0x40000000;

  RustPlaybackBackend? _backend;
  bool _failed = false;
  String? _error;
  bool _initialPlay = true;
  int _lastLoopCheckMs = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final handle = ++_handleCounter;
    final backend = RustPlaybackBackend(
      textureHandle: handle,
      previewMaxEdge: 720,
    );
    _backend = backend;
    backend.addListener(_onBackendUpdated);

    try {
      await backend.open(widget.path);
      if (!mounted) return;
      await backend.play();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = e.toString();
      });
    }
  }

  void _onBackendUpdated() {
    final backend = _backend;
    if (backend == null || !mounted) return;

    if (_initialPlay && backend.isOpen) {
      _initialPlay = false;
      setState(() {});
    }

    if (!backend.isPlaying) return;

    final pos = backend.positionMs;
    final dur = backend.durationMs;
    if (dur <= 0) return;

    if (pos >= dur - 200 && pos - _lastLoopCheckMs > 500) {
      _lastLoopCheckMs = pos;
      unawaited(backend.seekTo(Duration.zero));
      unawaited(backend.play());
    }
  }

  @override
  void dispose() {
    _backend?.removeListener(_onBackendUpdated);
    _backend?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Text(
          _error ?? 'Playback failed',
          style: const TextStyle(color: Colors.white70),
          textAlign: TextAlign.center,
        ),
      );
    }

    final backend = _backend;
    if (backend == null || !backend.isOpen) {
      return const Center(child: CircularProgressIndicator());
    }

    return RustVideoCanvas(backend: backend);
  }
}
