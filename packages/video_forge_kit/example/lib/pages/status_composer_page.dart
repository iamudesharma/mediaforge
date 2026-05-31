import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:video_player/video_player.dart';

import '../demo_session.dart';
import '../status/status_controller.dart';
import '../status/status_item.dart';
import '../status/status_pipeline.dart';
import '../widgets/filmstrip_trimmer.dart';

/// WhatsApp-style composer: metadata → preview → trim (metadata only) → post → compress.
class StatusComposerPage extends StatefulWidget {
  const StatusComposerPage({
    super.key,
    required this.controller,
    required this.itemId,
  });

  final StatusController controller;
  final String itemId;

  @override
  State<StatusComposerPage> createState() => _StatusComposerPageState();
}

class _StatusComposerPageState extends State<StatusComposerPage> {
  VideoPlayerController? _player;
  List<String> _filmstripPaths = [];
  bool _loadingFilmstrip = false;
  bool _posting = false;

  double _startSec = 0;
  double _endSec = 0;
  double _playheadSec = 0;
  bool _playerReady = false;

  StatusItem? get _item {
    try {
      return widget.controller.items.firstWhere((i) => i.id == widget.itemId);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _player?.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    final item = _item;
    if (item == null) return;

    if (item.isPreparing) {
      await widget.controller.ensureDraftReady(item.id);
    }

    final ready = _item;
    if (ready == null || !ready.isDraft) return;

    _startSec = ready.trimStartSec;
    _endSec = ready.trimEndSec;
    _playheadSec = _startSec;

    await _initPlayer(ready.stablePath!);
    unawaited(_buildFilmstrip(ready));
    if (mounted) setState(() {});
  }

  Future<void> _initPlayer(String path) async {
    _playerReady = false;
    await _player?.dispose();
    _player = null;

    if (!File(path).existsSync()) return;

    try {
      _player = VideoPlayerController.file(File(path));
      await _player!.initialize();
      await _player!.setLooping(false);
      _playerReady = true;
      await _player!.seekTo(Duration(milliseconds: (_playheadSec * 1000).round()));
      await _player!.play();
    } catch (e) {
      debugPrint('status player failed: $e');
      await _player?.dispose();
      _player = null;
    }
  }

  List<Duration> _evenlySpacedPositions(double durationSec) {
    final count = StatusComposerLimits.filmstripFrames;
    if (count <= 1 || durationSec <= 0) return [Duration.zero];
    return List.generate(count, (i) {
      final sec = durationSec * i / (count - 1);
      return Duration(milliseconds: (sec * 1000).round());
    });
  }

  Future<void> _buildFilmstrip(StatusItem item) async {
    final input = item.stablePath;
    if (input == null) return;

    setState(() => _loadingFilmstrip = true);
    try {
      final paths = await VideoProcessor.batchThumbnailPathsCached(
        input: input,
        positions: _evenlySpacedPositions(item.durationSec),
        width: StatusComposerLimits.filmstripThumbWidth,
      );
      if (mounted) setState(() => _filmstripPaths = paths);
    } catch (e) {
      debugPrint('filmstrip failed: $e');
    } finally {
      if (mounted) setState(() => _loadingFilmstrip = false);
    }
  }

  void _onRangeChanged(double start, double end) {
    setState(() {
      _startSec = start;
      _endSec = end;
      _playheadSec = start;
    });
    if (_playerReady && _player != null) {
      unawaited(
        _player!.seekTo(Duration(milliseconds: (start * 1000).round())),
      );
    }
  }

  double _clampSegmentEnd(double start, double end, double duration) {
    final maxEnd = (start + StatusComposerLimits.maxSegmentSec)
        .clamp(0.0, duration)
        .toDouble();
    return end.clamp(start + 0.1, maxEnd).toDouble();
  }

  Future<void> _postStatus() async {
    if (_posting) return;
    setState(() => _posting = true);
    final ok = await widget.controller.postDraft(
      widget.itemId,
      trimStartSec: _startSec,
      trimEndSec: _endSec,
    );
    if (!mounted) return;
    setState(() => _posting = false);
    if (ok) Navigator.of(context).pop(true);
  }

  int? _thumbCacheWidth(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context).round();
    return StatusComposerLimits.filmstripThumbWidth * dpr;
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('New status'),
        actions: [
          if (item?.isDraft == true)
            TextButton(
              onPressed: _posting ? null : _postStatus,
              child: _posting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Post'),
            ),
        ],
      ),
      body: item == null
          ? const Center(child: Text('Status not found', style: TextStyle(color: Colors.white)))
          : _buildBody(context, item),
    );
  }

  Widget _buildBody(BuildContext context, StatusItem item) {
    if (item.isFailed) {
      return Center(
        child: Text(
          item.error ?? item.statusMessage,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    if (item.isPreparing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              item.statusMessage,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            _PipelineSteps(current: 0),
          ],
        ),
      );
    }

    final dur = item.durationSec;
    final segmentLen = (_endSec - _startSec).clamp(0, dur);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: _PipelineSteps(current: item.isDraft ? 3 : 5),
        ),
        if (item.videoWidth != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              '${item.videoWidth}×${item.videoHeight} · ${item.videoCodec ?? "?"}'
              '${item.fps != null ? " @ ${item.fps!.toStringAsFixed(0)} fps" : ""}'
              ' · ${DemoSession.formatDuration((dur * 1000).round())}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white70,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(child: _buildPlayerArea(item)),
        Container(
          color: const Color(0xFF1F2C34),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Trim · ${DemoSession.formatDuration((segmentLen * 1000).round())}'
                ' / max ${StatusComposerLimits.maxSegmentSec.toInt()}s status',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Segment ${_startSec.toStringAsFixed(1)}s → ${_endSec.toStringAsFixed(1)}s'
                ' (not cut until you tap Post)',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (_loadingFilmstrip || _filmstripPaths.isEmpty)
                const SizedBox(
                  height: 56,
                  child: Center(
                    child: Text(
                      'Timeline thumbnails loading…',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                )
              else
                FilmstripTrimmer(
                  thumbPaths: _filmstripPaths,
                  durationSeconds: dur,
                  startSeconds: _startSec,
                  endSeconds: _endSec,
                  onRangeChanged: (s, e) {
                    final clampedEnd = _clampSegmentEnd(s, e, dur);
                    final clampedStart = s.clamp(0.0, dur - 0.1).toDouble();
                    _onRangeChanged(clampedStart, clampedEnd);
                  },
                  height: 56,
                  cacheWidth: _thumbCacheWidth(context),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _posting ? null : _postStatus,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send_rounded),
                label: Text(_posting ? 'Posting…' : 'Post status (compress in background)'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlayerArea(StatusItem item) {
    if (_playerReady && _player != null && _player!.value.isInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: _player!.value.aspectRatio,
          child: VideoPlayer(_player!),
        ),
      );
    }

    final thumb = item.thumbPath;
    if (thumb != null && File(thumb).existsSync()) {
      return Center(
        child: Image.file(File(thumb), fit: BoxFit.contain),
      );
    }

    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}

class _PipelineSteps extends StatelessWidget {
  const _PipelineSteps({required this.current});

  final int current;

  static const _steps = [
    'Metadata',
    'Poster frame',
    'Playback',
    'Timeline thumbs',
    'Trim (metadata)',
    'Post → compress',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: List.generate(_steps.length, (i) {
        final done = i < current;
        final active = i == current;
        return Chip(
          visualDensity: VisualDensity.compact,
          label: Text(
            _steps[i],
            style: TextStyle(
              fontSize: 11,
              color: done || active ? Colors.white : Colors.white54,
            ),
          ),
          backgroundColor: active
              ? const Color(0xFF25D366)
              : done
                  ? Colors.white24
                  : const Color(0x1AFFFFFF),
        );
      }),
    );
  }
}
