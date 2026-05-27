import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:path/path.dart' as p;

import '../demo_session.dart';
import '../output_paths.dart';
import '../widgets/filmstrip_trimmer.dart';

/// Live-style editor: filmstrip selection (our batch thumbnails) + compress export.
///
/// UX inspired by [video_trimmer](https://github.com/sbis04/video_trimmer); processing
/// uses [VideoProcessor] only (no FFmpeg CLI / third-party trimmer).
class VideoStudioPage extends StatefulWidget {
  const VideoStudioPage({super.key, required this.session});

  final DemoSession session;

  @override
  State<VideoStudioPage> createState() => _VideoStudioPageState();
}

class _VideoStudioPageState extends State<VideoStudioPage> {
  static const _filmstripFrames = 12;
  static const _filmstripThumbWidth = 160;

  StreamSubscription<ProgressEvent>? _progressSub;
  MediaRuntime? _runtime;

  List<String> _filmstripPaths = [];
  List<VideoOverlayItem> _overlays = [];
  bool _loadingFilmstrip = false;
  bool _showTitleOverlay = true;

  double _startSec = 0;
  double _endSec = 0;
  double _playheadSec = 0;

  CompressionPreset _exportPreset = CompressionPreset.instagram;
  late bool _preferHw = widget.session.isMobile;

  DemoSession get _s => widget.session;

  @override
  void dispose() {
    _progressSub?.cancel();
    unawaited(_tearDownRuntime());
    super.dispose();
  }

  Future<void> _tearDownRuntime() async {
    final runtime = _runtime;
    if (runtime == null) return;
    runtime.removeListener(_onRuntimeUpdated);
    _runtime = null;
    runtime.pause();
    await runtime.close();
    runtime.dispose();
  }

  void _onRuntimeUpdated() {
    final runtime = _runtime;
    if (runtime == null || !mounted) return;
    final sec = runtime.ptsMs / 1000.0;
    if ((sec - _playheadSec).abs() > 0.001 || runtime.isPlaying) {
      setState(() {
        _playheadSec = _safeClamp(sec, _startSec, _endSec);
      });
    }
    if (runtime.isPlaying && runtime.metrics.playbackFramesPresented % 30 == 0) {
      _s.status = runtime.metricsSnapshot.toStatusLine();
      _s.touch();
    }
  }

  int? _thumbCacheWidth(BuildContext context, int logicalWidth) {
    final dpr = MediaQuery.devicePixelRatioOf(context).round();
    return logicalWidth * dpr;
  }

  Future<void> _pickVideo() async {
    final picked = await _s.pickVideo(context: context);
    if (!picked || _s.selectedInput == null) return;

    OutputPaths.clearCache();
    _filmstripPaths = [];
    await _tearDownRuntime();

    if (!_s.initialized) {
      await _s.initialize();
    } else {
      _s.outputPaths = await OutputPaths.resolve();
      _s.touch();
    }
    await _loadVideo(_s.selectedInput!);
  }

  Future<void> _loadVideo(String path) async {
    _s.setBusy(status: 'Loading video…');
    try {
      await _tearDownRuntime();
      _runtime = MediaRuntime(previewMaxEdge: 720, targetPreviewFps: 30);
      _runtime!.addListener(_onRuntimeUpdated);
      await _runtime!.open(path);

      // Authoritative duration for trim/filmstrip (fixes short fast-probe on phone MOV).
      final info = _runtime!.mediaInfo ?? await VideoProcessor.getMediaInfo(path);
      _s.info = info;
      final dur = info.durationMs.toInt() / 1000.0;
      _startSec = 0;
      _endSec = dur > 0 ? dur : 1;
      _playheadSec = _startSec;

      _runtime!.setTrimRange(
        startMs: (_startSec * 1000).round(),
        endMs: (_endSec * 1000).round(),
      );
      await _runtime!.seekTo(
        Duration(milliseconds: (_playheadSec * 1000).round()),
      );

      await _buildFilmstrip();
      _rebuildDemoOverlays(_endSec - _startSec);
      final metrics = _runtime!.metricsSnapshot.toStatusLine();
      _s.setIdle(
        status:
            'Ready · ${info.width}×${info.height} · ${info.videoCodec} · overlays:${_overlays.length}\n$metrics',
      );
    } catch (e) {
      _s.setIdle(status: 'Load failed: $e');
    }
  }

  List<Duration> _evenlySpacedPositions(int count, double durationSec) {
    if (count <= 1 || durationSec <= 0) {
      return [Duration.zero];
    }
    return List.generate(count, (i) {
      final sec = durationSec * i / (count - 1);
      return Duration(milliseconds: (sec * 1000).round());
    });
  }

  Future<void> _buildFilmstrip() async {
    final input = _s.selectedInput;
    if (input == null) return;

    setState(() => _loadingFilmstrip = true);
    try {
      final positions = _evenlySpacedPositions(_filmstripFrames, _s.durationSeconds);
      final paths = await VideoProcessor.batchThumbnailPathsCached(
        input: input,
        positions: positions,
        width: _filmstripThumbWidth,
      );
      if (!mounted) return;
      setState(() => _filmstripPaths = paths);
    } catch (e) {
      _s.setIdle(status: 'Filmstrip error: $e');
    } finally {
      if (mounted) setState(() => _loadingFilmstrip = false);
    }
  }

  void _schedulePreviewSync(double seconds) {
    if (_runtime?.isPlaying ?? false) return;
    _runtime?.scheduleScrub(
      Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  static double _safeClamp(double value, double lower, double upper) {
    if (lower > upper) return lower;
    return value.clamp(lower, upper);
  }

  void _onRangeChanged(double start, double end) {
    final dur = _s.durationSeconds;
    final gap = dur > 0 ? (dur * 0.05).clamp(0.01, 0.25) : 0.01;
    var s = start.clamp(0.0, dur);
    var e = end.clamp(0.0, dur);
    if (e < s + gap) {
      e = (s + gap).clamp(0.0, dur);
      if (e - gap < s) s = (e - gap).clamp(0.0, dur);
    }
    setState(() {
      _startSec = s;
      _endSec = e;
      _playheadSec = _safeClamp(_playheadSec, s, e);
      _rebuildDemoOverlays(_endSec - _startSec);
    });
    _runtime?.setTrimRange(
      startMs: (_startSec * 1000).round(),
      endMs: (_endSec * 1000).round(),
    );
    _schedulePreviewSync(_playheadSec);
  }

  void _rebuildDemoOverlays(double trimDurationSec) {
    final durMs = (trimDurationSec * 1000).round().clamp(1, 1 << 30);
    final midStart = (durMs * 0.25).round();
    final midEnd = (durMs * 0.75).round();
    _overlays = [
      if (_showTitleOverlay)
        VideoOverlayItem.text(
          id: 'title',
          startMs: 0,
          endMs: durMs,
          anchor: const Offset(0.12, 0.88),
          label: 'Video Studio',
        ),
      VideoOverlayItem.emoji(
        id: 'mid',
        startMs: midStart,
        endMs: midEnd,
        anchor: const Offset(0.82, 0.18),
        emoji: '✨',
      ),
    ];
  }

  Future<void> _togglePlayback() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.isOpen || _s.busy) return;
    if (runtime.isPlaying) {
      runtime.pause();
    } else {
      runtime.setTrimRange(
        startMs: (_startSec * 1000).round(),
        endMs: (_endSec * 1000).round(),
      );
      await runtime.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _exportCompress() async {
    final input = _s.selectedInput;
    var outputs = _s.outputPaths;
    if (input == null) return;
    outputs ??= await OutputPaths.resolve();
    _s.outputPaths = outputs;

    final out = p.join(
      outputs.compressVideoDir,
      '${outputs.safeStem(input)}_${_exportPreset.name}_export.mp4',
    );
    await Directory(outputs.compressVideoDir).create(recursive: true);

    _s.setBusy(status: 'Compressing (${_exportPreset.label})…', progress: 0);

    try {
      await _progressSub?.cancel();
      final startMs = (_startSec * 1000).round();
      final endMs = (_endSec * 1000).round();
      final job = await VideoProcessor.compressJob(
        input: input,
        output: out,
        quality: _exportPreset.quality,
        preferHardwareEncoder: _preferHw,
        startMs: startMs,
        endMs: endMs > startMs ? endMs : null,
      );
      _s.activeJob = job;
      _progressSub = job.progress.listen((event) {
        _s.updateProgress(
          status:
              '${DemoSession.phaseLabel(event.phase)} ${(event.percent * 100).toStringAsFixed(0)}%',
          progress: event.percent,
        );
      });

      final result = await job.result;
      final clipLen = (_endSec - _startSec).clamp(0, _s.durationSeconds);
      _s.setIdle(
        status: 'Export saved\n${result.outputPath}\n'
            '${(result.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB · '
            '${result.encoderName} · HW ${result.usedHardwareAcceleration}\n'
            'Trimmed ${DemoSession.formatDuration((clipLen * 1000).round())}',
        progress: 1,
      );
      await job.cleanup();
    } catch (e) {
      _s.setIdle(status: 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_s.hasVideo) {
      return _buildPicker(context);
    }
    return _buildStudio(context);
  }

  Widget _buildPicker(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Video studio',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a clip for a cached filmstrip timeline and export a compressed MP4 '
              'with your app presets.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _s.busy ? null : _pickVideo,
              icon: const Icon(Icons.video_library_outlined),
              label: const Text('Load video'),
            ),
            const SizedBox(height: 12),
            if (!_s.initialized)
              OutlinedButton(
                onPressed: _s.busy ? null : _s.initialize,
                child: const Text('Initialize engine'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudio(BuildContext context) {
    final theme = Theme.of(context);
    final selectionLabel =
        '${DemoSession.formatDuration((_startSec * 1000).round())} → '
        '${DemoSession.formatDuration((_endSec * 1000).round())}';

    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _s.busy
                        ? null
                        : () {
                            final previous = _s.selectedInput;
                            unawaited(_tearDownRuntime());
                            _s.selectedInput = null;
                            _s.selectedName = null;
                            _s.info = null;
                            _filmstripPaths = [];
                            if (previous != null) {
                              unawaited(
                                VideoProcessor.evictThumbnailCacheForInput(previous),
                              );
                            }
                            _s.setIdle(status: 'Pick a video to start');
                          },
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      _s.selectedName ?? 'Video',
                      style: theme.textTheme.titleMedium?.copyWith(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_s.busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildPreview(context)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectionLabel,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  FilterChip(
                    label: const Text('Title', style: TextStyle(fontSize: 11)),
                    selected: _showTitleOverlay,
                    onSelected: _s.busy
                        ? null
                        : (v) {
                            setState(() {
                              _showTitleOverlay = v;
                              _rebuildDemoOverlays(_endSec - _startSec);
                            });
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _loadingFilmstrip
                  ? const LinearProgressIndicator(minHeight: 2)
                  : FilmstripTrimmer(
                      thumbPaths: _filmstripPaths,
                      durationSeconds: _s.durationSeconds,
                      startSeconds: _startSec,
                      endSeconds: _endSec,
                      onRangeChanged: _onRangeChanged,
                      cacheWidth: _thumbCacheWidth(context, _filmstripThumbWidth),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Builder(
                builder: (context) {
                  final minP = _startSec;
                  final maxP = _endSec > minP ? _endSec : minP + 0.01;
                  return Slider(
                    value: _safeClamp(_playheadSec, minP, maxP),
                    min: minP,
                    max: maxP,
                    onChanged: _s.busy
                        ? null
                        : (v) {
                            _runtime?.pause();
                            setState(() => _playheadSec = v);
                            _schedulePreviewSync(v);
                          },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ListenableBuilder(
                listenable: _runtime ?? Listenable.merge(const []),
                builder: (context, _) {
                  final playing = _runtime?.isPlaying ?? false;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton.filled(
                        onPressed: _s.busy ? null : _togglePlayback,
                        tooltip: playing ? 'Pause' : 'Play',
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          size: 36,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.outlined(
                        onPressed: _s.busy || _loadingFilmstrip ? null : _buildFilmstrip,
                        icon: const Icon(Icons.refresh),
                        color: Colors.white,
                        tooltip: 'Regenerate filmstrip',
                      ),
                    ],
                  );
                },
              ),
            ),
            _buildExportPanel(context),
            if (_s.progress > 0 && _s.busy)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: LinearProgressIndicator(value: _s.progress.clamp(0.0, 1.0)),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _s.status,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final runtime = _runtime;
    if (runtime != null && runtime.isOpen) {
      return VideoCompositorCanvas(
        runtime: runtime,
        overlays: _overlays,
      );
    }
    return const Center(
      child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
    );
  }

  Widget _buildExportPanel(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Export with VideoProcessor',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: CompressionPreset.values.map((preset) {
                final selected = _exportPreset == preset;
                return ChoiceChip(
                  label: Text(preset.label),
                  selected: selected,
                  onSelected: _s.busy
                      ? null
                      : (v) {
                          if (v) setState(() => _exportPreset = preset);
                        },
                );
              }).toList(),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hardware encoder', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'VideoToolbox / MediaCodec',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              value: _preferHw,
              onChanged: _s.busy ? null : (v) => setState(() => _preferHw = v),
            ),
            FilledButton.icon(
              onPressed: _s.canProcess ? _exportCompress : null,
              icon: const Icon(Icons.upload_file),
              label: const Text('Compress & save MP4'),
            ),
          ],
        ),
      ),
    );
  }
}
