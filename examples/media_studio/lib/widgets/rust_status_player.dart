import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_forge/media_forge.dart';

import '../services/rust_backend.dart';

/// Minimal Rust-backed status preview player.
///
/// Owns a single [RustBackend] + [MediaPlaybackPresenter] tied to a unique GPU
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

  RustBackend? _backend;
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
    final backend = RustBackend(
      textureHandle: handle,
      previewMaxEdge: 720,
    );
    try {
      await backend.open(widget.path);
      // Start engine so first frame is presented, then pause for the
      // user-controlled playback loop.
      await backend.play();
      backend.pause();
      await backend.seekTo(Duration.zero);
      if (!mounted) return;
      setState(() => _backend = backend);
      backend.addListener(_onBackendTick);
    } catch (e) {
      debugPrint('[RustStatusPlayer] open failed: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = e.toString();
      });
    }
  }

  void _onBackendTick() {
    final backend = _backend;
    if (backend == null || !mounted) return;
    // Looping: when paused, the very first play() call must explicitly
    // resume the engine. After that the engine runs naturally; when we get
    // close to the end, rewind to 0.
    if (_initialPlay) {
      _initialPlay = false;
      unawaited(backend.play());
      return;
    }
    final pos = backend.positionMs;
    final dur = backend.durationMs;
    if (dur > 500 && pos >= dur - 250) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastLoopCheckMs > 500) {
        _lastLoopCheckMs = now;
        unawaited(backend.seekTo(Duration.zero));
        if (!backend.isPlaying) {
          unawaited(backend.play());
        }
      }
    }
  }

  @override
  void dispose() {
    final backend = _backend;
    _backend = null;
    if (backend != null) {
      backend.removeListener(_onBackendTick);
      unawaited(backend.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error ?? 'Unable to open video',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      );
    }
    final backend = _backend;
    final presenter = backend?.presenter;
    if (backend == null || presenter == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return MediaVideoSurface(presenter: presenter, fit: BoxFit.contain);
  }
}
