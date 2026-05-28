import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'services/output_paths.dart';
import 'widgets/filmstrip_trimmer.dart';
import 'widgets/send_to_chat_sheet.dart';
import 'photo_editor_flow.dart';

class VideoExportResult {
  final String outputPath;
  final String? thumbPath;
  final int originalBytes;
  final int compressedBytes;
  final Duration encodeDuration;

  VideoExportResult({
    required this.outputPath,
    required this.thumbPath,
    required this.originalBytes,
    required this.compressedBytes,
    required this.encodeDuration,
  });
}

class VideoCreatorFlow extends StatefulWidget {
  const VideoCreatorFlow({
    super.key,
    required this.initialPath,
    this.displayName,
  });

  final String initialPath;
  final String? displayName;

  @override
  State<VideoCreatorFlow> createState() => _VideoCreatorFlowState();
}

class _VideoCreatorFlowState extends State<VideoCreatorFlow> {
  static const _filmstripFrames = 10;
  static const _filmstripThumbWidth = 160;

  MediaRuntime? _runtime;
  StreamSubscription<ProgressEvent>? _progressSub;

  List<String> _filmstripPaths = [];
  final TimelineController _timeline = TimelineController();
  VideoPlayerController? _audioPreview;
  bool _loadingFilmstrip = false;
  bool _busy = false;
  String _statusLine = 'Initializing player…';
  String _metricsLine = '';

  double _startSec = 0;
  double _endSec = 0;
  double _playheadSec = 0;
  final _playheadNotifier = ValueNotifier<double>(0.0);
  DateTime? _lastTimelineRebuild;

  CompressionPreset _exportPreset = CompressionPreset.instagram;
  bool _preferHw = true;
  bool _toolsExpanded = false;
  final _textOverlayController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _timeline.addListener(_onTimelineUpdated);
    _loadVideo(widget.initialPath);
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _timeline.removeListener(_onTimelineUpdated);
    _playheadNotifier.dispose();
    _textOverlayController.dispose();
    _stopAudioPreview();
    _tearDownRuntime();
    super.dispose();
  }

  void _onTimelineUpdated() {
    if (mounted) setState(() {});
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
    // During playback the wall-clock drives [mediaTimeMs]; [ptsMs] only updates per decode (~12–15 fps).
    final sourceMs =
        runtime.isPlaying ? runtime.mediaTimeMs : runtime.ptsMs;
    final timelineSec = _timelineSecFromSourcePts(sourceMs);
    final clampedSec = _safeClamp(
      timelineSec,
      0,
      _timelineDurationSec > 0 ? _timelineDurationSec : _endSec,
    );

    // Update playhead notifier instantly for the smooth scrubber slider
    _playheadSec = clampedSec;
    _playheadNotifier.value = clampedSec;

    if (runtime.isPlaying) {
      unawaited(_advancePastClipEndIfNeeded(sourceMs));
    }

    // Throttle heavy full-screen rebuilds (Timeline, overlays, tools panel) during playback
    final now = DateTime.now();
    final lastRebuild = _lastTimelineRebuild;
    final shouldRebuild = !runtime.isPlaying ||
        lastRebuild == null ||
        now.difference(lastRebuild).inMilliseconds >= 120; // ~8 fps timeline updates save 85% CPU load

    if (shouldRebuild) {
      _lastTimelineRebuild = now;
      setState(() {
        if (runtime.isPlaying) {
          _metricsLine = runtime.metricsSnapshot.toStatusLine();
        }
      });
    }
  }

  Future<void> _loadVideo(String path) async {
    setState(() {
      _busy = true;
      _statusLine = 'Loading video…';
    });

    try {
      await _tearDownRuntime();
      _runtime = MediaRuntime(
        previewMaxEdge: 480,
        targetPreviewFps: 24,
        loopPlayback: false,
      );
      _runtime!.addListener(_onRuntimeUpdated);
      await _runtime!.open(path);

      final info = _runtime!.mediaInfo ?? await VideoProcessor.getMediaInfo(path);
      final dur = info.durationMs.toInt() / 1000.0;
      
      final durationMs = info.durationMs.toInt();
      _timeline.loadPrimaryVideo(
        sourcePath: path,
        durationMs: durationMs > 0 ? durationMs : 1000,
      );

      setState(() {
        _startSec = 0;
        _endSec = dur > 0 ? dur : 1;
        _playheadSec = 0;
        _statusLine = 'Ready · ${info.width}×${info.height} · ${info.videoCodec}';
        _busy = false;
      });

      _runtime!.setTrimRange(
        startMs: (_startSec * 1000).round(),
        endMs: (_endSec * 1000).round(),
      );
      await _applySeekFromTimelineMs(0);

      await _buildFilmstrip();
    } catch (e) {
      setState(() {
        _statusLine = 'Load failed: $e';
        _busy = false;
      });
    }
  }

  Future<void> _buildFilmstrip() async {
    setState(() => _loadingFilmstrip = true);
    try {
      final duration = _runtime?.mediaInfo?.durationMs.toInt() ?? 0;
      final durationSeconds = duration / 1000.0;
      final positions = _evenlySpacedPositions(_filmstripFrames, durationSeconds);
      
      final paths = await VideoProcessor.batchThumbnailPathsCached(
        input: widget.initialPath,
        positions: positions,
        width: _filmstripThumbWidth,
      );
      
      if (mounted) {
        setState(() {
          _filmstripPaths = paths;
        });
      }
    } catch (e) {
      debugPrint('Filmstrip error: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingFilmstrip = false);
      }
    }
  }

  List<Duration> _evenlySpacedPositions(int count, double durationSec) {
    if (count <= 1 || durationSec <= 0) {
      return [Duration.zero];
    }
    final totalMs = (durationSec * 1000).round();
    // Cap the end slightly before the actual duration to avoid seeking past EOF
    final maxSeekMs = totalMs > 200 ? totalMs - 200 : (totalMs > 50 ? totalMs - 50 : 0);
    return List.generate(count, (i) {
      final ms = (maxSeekMs * i / (count - 1)).round();
      return Duration(milliseconds: ms);
    });
  }

  static double _safeClamp(double value, double lower, double upper) {
    if (lower > upper) return lower;
    return value.clamp(lower, upper);
  }

  double get _timelineDurationSec =>
      _timeline.durationMs > 0 ? _timeline.durationMs / 1000.0 : _endSec;

  int get _playheadTimelineMs => (_playheadSec * 1000).round();

  double _timelineSecFromSourcePts(int sourcePtsMs) {
    for (final clip in _timeline.videoClips) {
      if (clip.sourcePath != widget.initialPath) continue;
      if (sourcePtsMs >= clip.sourceStartMs && sourcePtsMs < clip.sourceEndMs) {
        return (clip.timelineStartMs + (sourcePtsMs - clip.sourceStartMs)) /
            1000.0;
      }
    }
    return sourcePtsMs / 1000.0;
  }

  void _syncFilmstripToSingleClip() {
    if (_timeline.videoClips.length != 1) return;
    final clip = _timeline.videoClips.first;
    _timeline.updateVideoClip(
      clip.copyWith(
        sourceStartMs: (_startSec * 1000).round(),
        sourceEndMs: (_endSec * 1000).round(),
      ),
    );
  }

  Future<void> _applySeekFromTimelineMs(int timelineMs) async {
    final runtime = _runtime;
    final target = _timeline.seekTargetAt(timelineMs);
    if (runtime == null || target == null) return;

    final clip = _timeline.clipById(target.clipId);
    if (clip != null) {
      runtime.setTrimRange(
        startMs: clip.sourceStartMs,
        endMs: clip.sourceEndMs,
      );
    }
    await runtime.seekTo(Duration(milliseconds: target.sourceMs));
  }

  Future<void> _advancePastClipEndIfNeeded(int sourcePtsMs) async {
    final runtime = _runtime;
    if (runtime == null || !runtime.isPlaying) return;

    final clip = _timeline.clipAtTimelineMs(_playheadTimelineMs);
    if (clip == null) return;
    if (sourcePtsMs < clip.sourceEndMs - 80) return;

    final index = _timeline.videoClips.indexWhere((c) => c.id == clip.id);
    if (index < 0 || index >= _timeline.videoClips.length - 1) {
      runtime.pause();
      return;
    }
    final next = _timeline.videoClips[index + 1];
    setState(() => _playheadSec = next.timelineStartMs / 1000.0);
    await _applySeekFromTimelineMs(next.timelineStartMs);
    if (runtime.isOpen && !runtime.isPlaying) {
      await runtime.play();
    }
  }

  (int startMs, int endMs) _exportTrimMs() {
    final range = _timeline.exportRangeForPrimarySource();
    var startMs = (_startSec * 1000).round();
    var endMs = (_endSec * 1000).round();
    if (range != null) {
      startMs = math.max(startMs, range.startMs);
      endMs = math.min(endMs, range.endMs);
    }
    if (endMs <= startMs) {
      endMs = startMs + 1;
    }
    return (startMs, endMs);
  }

  Future<void> _pickAudioTrack() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || !File(path).existsSync()) return;

    try {
      final info = await VideoProcessor.getMediaInfo(path);
      final durationMs = info.durationMs.toInt();
      _timeline.addAudioClip(
        sourcePath: path,
        durationMs: durationMs > 0 ? durationMs : 1000,
        timelineStartMs: _playheadTimelineMs,
      );
      if (mounted) {
        setState(() {
          _statusLine =
              'Audio track added · ${p.basename(path)} (${_formatDuration(durationMs)})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusLine = 'Audio import failed: $e');
      }
    }
  }

  Future<void> _stopAudioPreview() async {
    final controller = _audioPreview;
    _audioPreview = null;
    if (controller == null) return;
    await controller.pause();
    await controller.dispose();
  }

  Future<void> _syncAudioPreview(bool videoPlaying) async {
    final tracks = _timeline.audioClips.where((c) => !c.muted);
    if (!videoPlaying || tracks.isEmpty) {
      await _stopAudioPreview();
      return;
    }
    final track = tracks.first;
    if (_audioPreview?.dataSource != track.sourcePath) {
      await _stopAudioPreview();
      _audioPreview = VideoPlayerController.file(File(track.sourcePath));
      await _audioPreview!.initialize();
      await _audioPreview!.setVolume(track.volume);
    }
    final offsetMs = _playheadTimelineMs - track.timelineStartMs;
    if (offsetMs >= 0 && offsetMs < track.durationMs) {
      await _audioPreview!.seekTo(
        Duration(milliseconds: track.sourceStartMs + offsetMs),
      );
      await _audioPreview!.play();
    }
  }

  void _splitAtPlayhead() {
    final ok = _timeline.splitVideoAt(_playheadTimelineMs);
    setState(() {
      _statusLine = ok
          ? 'Split clip at ${_formatDuration(_playheadTimelineMs)}'
          : 'Cannot split here (move playhead inside a clip)';
    });
  }

  void _onRangeChanged(double start, double end) {
    final dur = (_runtime?.mediaInfo?.durationMs.toInt() ?? 0) / 1000.0;
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
    });
    _syncFilmstripToSingleClip();
    _runtime?.setTrimRange(
      startMs: (_startSec * 1000).round(),
      endMs: (_endSec * 1000).round(),
    );
    _schedulePreviewSync(_playheadSec);
  }

  void _schedulePreviewSync(double timelineSeconds) {
    if (_runtime?.isPlaying ?? false) return;
    unawaited(_applySeekFromTimelineMs((timelineSeconds * 1000).round()));
  }

  Future<void> _togglePlayback() async {
    final runtime = _runtime;
    if (runtime == null || !runtime.isOpen || _busy) return;
    if (runtime.isPlaying) {
      runtime.pause();
      await _stopAudioPreview();
    } else {
      await _applySeekFromTimelineMs(_playheadTimelineMs);
      await runtime.play();
      await _syncAudioPreview(true);
    }
    if (mounted) setState(() {});
  }

  void _addTextOverlay() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Add Text Overlay', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Enter overlay text',
              hintStyle: TextStyle(color: Colors.white30),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final label = controller.text.trim();
                if (label.isNotEmpty) {
                  final duration = _timeline.durationMs;
                  final startMs = _playheadTimelineMs;
                  final endMs = (startMs + 5000).clamp(0, duration);
                  
                  final overlay = VideoOverlayItem.text(
                    id: 'text:$label:${DateTime.now().millisecondsSinceEpoch}',
                    startMs: startMs,
                    endMs: endMs,
                    anchor: const Offset(0.3, 0.4),
                    label: label,
                  );
                  
                  _timeline.addOverlay(overlay);
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _addEmojiOverlay() {
    final emojis = ['✨', '🔥', '😂', '❤️', '👍', '🍕', '🎉', '✈️'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Choose Emoji Overlay',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: emojis.length,
                itemBuilder: (context, i) {
                  return InkWell(
                    onTap: () {
                      final duration = _timeline.durationMs;
                      final startMs = _playheadTimelineMs;
                      final endMs = (startMs + 5000).clamp(0, duration);
                      
                      final overlay = VideoOverlayItem.emoji(
                        id: 'emoji:${emojis[i]}:${DateTime.now().millisecondsSinceEpoch}',
                        startMs: startMs,
                        endMs: endMs,
                        anchor: const Offset(0.7, 0.2),
                        emoji: emojis[i],
                      );
                      
                      _timeline.addOverlay(overlay);
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    child: Center(
                      child: Text(emojis[i], style: const TextStyle(fontSize: 40)),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runPosterFrameBridge() async {
    if (_busy) return;
    
    setState(() {
      _busy = true;
      _statusLine = 'Extracting frame at playhead…';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final outPath = p.join(tempDir.path, 'bridge_${DateTime.now().millisecondsSinceEpoch}.jpg');
      
      final duration = _runtime?.mediaInfo?.durationMs.toInt() ?? 0;
      final requestedMs = (_playheadSec * 1000).round();
      final seekMs = duration > 100
          ? requestedMs.clamp(0, duration - 100)
          : requestedMs;

      // Extract high quality thumbnail at playhead
      final thumbPath = await VideoProcessor.thumbnail(
        input: widget.initialPath,
        position: Duration(milliseconds: seekMs),
        output: outPath,
        width: 1080,
      );

      final bytes = await File(thumbPath).readAsBytes();
      
      if (!mounted) return;
      setState(() {
        _busy = false;
        _statusLine = 'Opening Photo Editor…';
      });

      final editedPath = await Navigator.push<String?>(
        context,
        MaterialPageRoute(
          builder: (context) => PhotoEditorFlow(
            initialBytes: bytes,
            title: 'Edit Frame',
          ),
        ),
      );

      if (editedPath != null && File(editedPath).existsSync()) {
        final duration = _runtime?.mediaInfo?.durationMs.toInt() ?? 1000;
        final startMs = (_playheadSec * 1000).round();
        final endMs = (startMs + 6000).clamp(0, duration);

        final overlay = VideoOverlayItem(
          id: 'poster:Edited Frame:${DateTime.now().millisecondsSinceEpoch}',
          startMs: startMs,
          endMs: endMs,
          anchor: const Offset(0.5, 0.5),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(8),
              color: Colors.black38,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(editedPath),
                width: 150,
                height: 150,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );

        _timeline.addOverlay(overlay);
        setState(() {
          _statusLine = 'Poster frame overlay added!';
        });
      } else {
        setState(() {
          _statusLine = 'Frame editing cancelled.';
        });
      }
    } catch (e) {
      setState(() {
        _statusLine = 'Poster frame failed: $e';
        _busy = false;
      });
    }
  }

  void _clearOverlays() {
    _timeline.clearOverlays();
    setState(() => _statusLine = 'Cleared all overlays');
  }

  Future<void> _exportVideo() async {
    final runtime = _runtime;
    if (runtime == null || _busy) return;

    // Pause playback before exporting
    if (runtime.isPlaying) {
      runtime.pause();
    }

    setState(() {
      _busy = true;
      _statusLine = _timeline.overlays.isEmpty
          ? 'Preparing export…'
          : 'Baking overlays for export…';
    });

    List<BurnInOverlay> burnInOverlays = const [];
    try {
      if (_timeline.overlays.isNotEmpty) {
        final info = runtime.mediaInfo ??
            await VideoProcessor.getMediaInfo(widget.initialPath);
        burnInOverlays = await OverlayRasterExporter.rasterizeForExport(
          overlays: _timeline.overlays,
          sourceWidth: info.width,
          sourceHeight: info.height,
          preset: _exportPreset,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusLine = 'Overlay bake failed: $e';
        });
      }
      return;
    }

    if (!mounted) return;

    final outputs = await OutputPaths.resolve();
    final outPath = p.join(
      outputs.compressVideoDir,
      '${outputs.safeStem(widget.initialPath)}_${_exportPreset.name}_export.mp4',
    );
    await Directory(outputs.compressVideoDir).create(recursive: true);

    final (startMs, endMs) = _exportTrimMs();

    setState(() {
      _busy = false;
      _statusLine = 'Encoding video…';
    });

    double exportProgress = 0;
    String exportStatus = 'Preparing job…';
    VideoJob? activeJob;
    bool exportCancelled = false;

    if (!mounted) return;

    showModalBottomSheet<VideoExportResult?>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: const Color(0xFF1C1C1E),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            if (activeJob == null && !exportCancelled) {
              // Initiate compressJob
              final sw = Stopwatch()..start();
              VideoProcessor.compressJob(
                input: widget.initialPath,
                output: outPath,
                quality: _exportPreset.quality,
                preferHardwareEncoder: _preferHw,
                startMs: startMs,
                endMs: endMs > startMs ? endMs : null,
                burnInOverlays: burnInOverlays,
              ).then((job) {
                activeJob = job;
                _progressSub = job.progress.listen((event) {
                  setBottomSheetState(() {
                    exportProgress = event.percent;
                    exportStatus = '${_phaseLabel(event.phase)} ${(event.percent * 100).toStringAsFixed(0)}%';
                  });
                }, onError: (e) {
                  setBottomSheetState(() {
                    exportStatus = 'Failed: $e';
                  });
                });

                job.result.then((result) async {
                  final duration = sw.elapsed;
                  final outBytes = await File(result.outputPath).length();
                  final originalBytes = await File(widget.initialPath).length();
                  
                  // Extract a thumbnail from the compressed output
                  String? thumbPath;
                  try {
                    thumbPath = await VideoProcessor.thumbnailPathCached(
                      input: result.outputPath,
                      position: Duration(milliseconds: startMs),
                      width: 200,
                    );
                  } catch (_) {}

                  final exportResult = VideoExportResult(
                    outputPath: result.outputPath,
                    thumbPath: thumbPath,
                    originalBytes: originalBytes,
                    compressedBytes: outBytes,
                    encodeDuration: duration,
                  );

                  if (context.mounted) {
                    Navigator.pop(context, exportResult);
                  }
                }).catchError((e) {
                  if (!exportCancelled) {
                    setBottomSheetState(() {
                      exportStatus = 'Failed: $e';
                    });
                  }
                });
              }).catchError((e) {
                setBottomSheetState(() {
                  exportStatus = 'Launch failed: $e';
                });
              });
            }

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Exporting Video',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (burnInOverlays.isNotEmpty)
                    Text(
                      'Burning in ${burnInOverlays.length} overlay(s) with trim and compression.',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: exportProgress),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          exportStatus,
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${(exportProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            exportCancelled = true;
                            if (activeJob != null) {
                              await activeJob!.cancel();
                            }
                            await _progressSub?.cancel();
                            if (context.mounted) {
                              Navigator.pop(context, null);
                            }
                          },
                          child: const Text('Cancel Export'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((exportResult) {
      if (exportResult != null) {
        _showExportSuccessDialog(exportResult, overlayCount: burnInOverlays.length);
      }
    });
  }

  void _showExportSuccessDialog(VideoExportResult result, {int overlayCount = 0}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final originalMB = result.originalBytes / (1024 * 1024);
        final compressedMB = result.compressedBytes / (1024 * 1024);
        final savedPercent = (100 - (result.compressedBytes / result.originalBytes * 100)).clamp(0.0, 99.0);

        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Export Complete', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                overlayCount == 0
                    ? 'Trim and compression are saved.'
                    : 'Trim, compression, and $overlayCount overlay(s) are saved.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              _StatLine(label: 'Output Path', value: p.basename(result.outputPath)),
              _StatLine(label: 'Original Size', value: '${originalMB.toStringAsFixed(1)} MB'),
              _StatLine(label: 'Compressed Size', value: '${compressedMB.toStringAsFixed(1)} MB (~${savedPercent.toStringAsFixed(0)}% smaller)'),
              _StatLine(label: 'Encode Time', value: '${(result.encodeDuration.inMilliseconds / 1000).toStringAsFixed(1)}s'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                showSendToChatSheet(
                  context,
                  displayName: widget.displayName ?? 'Video',
                  path: result.outputPath,
                  originalBytes: result.originalBytes,
                  compressedBytes: result.compressedBytes,
                  encodeDuration: result.encodeDuration,
                );
              },
              child: const Text('Share to Chat'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx); // Pop success dialog
                Navigator.pop(context, result); // Pop creator flow back to HomeHub with result
              },
              child: const Text('Post to Updates'),
            ),
          ],
        );
      },
    );
  }

  String _phaseLabel(ProcessingPhase phase) {
    return switch (phase) {
      ProcessingPhase.probing => 'Probing',
      ProcessingPhase.decoding => 'Decoding',
      ProcessingPhase.encoding => 'Encoding',
      ProcessingPhase.muxing => 'Muxing',
      ProcessingPhase.thumbnail => 'Thumbnailing',
      ProcessingPhase.done => 'Done',
      ProcessingPhase.cancelled => 'Cancelled',
      ProcessingPhase.failed => 'Failed',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoaded = _runtime != null && _runtime!.isOpen;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.displayName ?? 'Video Creator', style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (isLoaded) ...[
            TextButton.icon(
              onPressed: _runPosterFrameBridge,
              icon: const Icon(Icons.portrait, color: Colors.white),
              label: const Text('Edit Frame', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _exportVideo,
              icon: const Icon(Icons.save_alt, color: Colors.white),
              label: const Text('Export', style: TextStyle(color: Colors.white)),
            ),
          ],
        ],
      ),
      body: DefaultTabController(
        length: 3,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Upper half: Video player canvas (fills all remaining room)
              Expanded(
                child: Container(
                  color: Colors.black,
                  alignment: Alignment.center,
                  child: isLoaded
                      ? Stack(
                          children: [
                            ValueListenableBuilder<double>(
                              valueListenable: _playheadNotifier,
                              builder: (context, playheadSec, _) {
                                return VideoCompositorCanvas(
                                  runtime: _runtime!,
                                  overlays: _timeline.overlays,
                                  timelinePlayheadMs: (playheadSec * 1000).round(),
                                );
                              },
                            ),
                            if (_metricsLine.isNotEmpty)
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _metricsLine,
                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ),
                              ),
                          ],
                        )
                      : const Center(
                          child: CircularProgressIndicator(),
                        ),
                ),
              ),

              if (isLoaded) ...[
                _buildScrubberRow(theme),
                
                if (_toolsExpanded) ...[
                  Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          dividerColor: Colors.transparent,
                          indicatorColor: theme.colorScheme.primary,
                          labelColor: Colors.white,
                          unselectedLabelColor: Colors.white38,
                          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          tabs: const [
                            Tab(icon: Icon(Icons.cut, size: 16), text: 'Trim & Export'),
                            Tab(icon: Icon(Icons.linear_scale, size: 16), text: 'Tracks'),
                            Tab(icon: Icon(Icons.title, size: 16), text: 'Add Overlays'),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
                        onPressed: () => setState(() => _toolsExpanded = false),
                        tooltip: 'Collapse Tools',
                      ),
                    ],
                  ),
                  
                  SizedBox(
                    height: 180,
                    child: TabBarView(
                      children: [
                        // Tab 1: Trim & Settings
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildTrimmerRow(),
                              _buildPlaybackControls(),
                              _buildSettingsRow(theme),
                            ],
                          ),
                        ),
                        // Tab 2: Tracks
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TimelineEditorPanel(
                                controller: _timeline,
                                playheadMs: _playheadTimelineMs,
                                onAddAudio: _pickAudioTrack,
                                onAddText: _addTextOverlay,
                                onAddEmoji: _addEmojiOverlay,
                                onSplitAtPlayhead: _splitAtPlayhead,
                              ),
                            ],
                          ),
                        ),
                        // Tab 3: Add Overlays (Inline widgets, no blocking dialogs)
                        SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: _buildOverlaysTab(theme),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => setState(() => _toolsExpanded = true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1E1E),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                          label: const Text('Show Editing Tools', style: TextStyle(fontSize: 12)),
                        ),
                        _buildCompactPlaybackButton(),
                        if (_timeline.overlays.isNotEmpty)
                          TextButton.icon(
                            onPressed: _clearOverlays,
                            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                            icon: const Icon(Icons.layers_clear, size: 14),
                            label: Text('Clear (${_timeline.overlays.length})', style: const TextStyle(fontSize: 11)),
                          )
                        else
                          const SizedBox(width: 80),
                      ],
                    ),
                  ),
                ],
              ],
              _buildStatusLine(),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildPlaybackControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ListenableBuilder(
        listenable: _runtime!,
        builder: (context, _) {
          final playing = _runtime?.isPlaying ?? false;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: _buildFilmstrip,
                tooltip: 'Regenerate Filmstrip',
              ),
              const SizedBox(width: 16),
              IconButton.filled(
                onPressed: _togglePlayback,
                iconSize: 32,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.layers_clear_outlined, color: Colors.white),
                onPressed: _timeline.overlays.isEmpty ? null : _clearOverlays,
                tooltip: 'Clear Overlays',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCompactPlaybackButton() {
    return ListenableBuilder(
      listenable: _runtime!,
      builder: (context, _) {
        final playing = _runtime?.isPlaying ?? false;
        return IconButton.filled(
          onPressed: _togglePlayback,
          iconSize: 28,
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        );
      },
    );
  }

  Widget _buildScrubberRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _playheadNotifier,
            builder: (context, val, _) {
              final ms = (val * 1000).round();
              return Text(_formatDuration(ms), style: const TextStyle(color: Colors.white70, fontSize: 11));
            },
          ),
          Expanded(
            child: ValueListenableBuilder<double>(
              valueListenable: _playheadNotifier,
              builder: (context, val, _) {
                return Slider(
                  value: _safeClamp(val, 0, _timelineDurationSec),
                  min: 0,
                  max: _timelineDurationSec > 0 ? _timelineDurationSec : 0.01,
                  activeColor: theme.colorScheme.primary,
                  inactiveColor: Colors.white24,
                  onChanged: (v) {
                    _runtime?.pause();
                    _playheadSec = v;
                    _playheadNotifier.value = v;
                    _schedulePreviewSync(v);
                  },
                );
              },
            ),
          ),
          Text(_formatDuration(_timeline.durationMs), style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Text('Export Preset:', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 8),
          DropdownButton<CompressionPreset>(
            dropdownColor: const Color(0xFF1E1E1E),
            value: _exportPreset,
            style: const TextStyle(color: Colors.white, fontSize: 11),
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _exportPreset = v;
                });
              }
            },
            items: CompressionPreset.values.map((preset) {
              return DropdownMenuItem<CompressionPreset>(
                value: preset,
                child: Text(preset.label),
              );
            }).toList(),
          ),
          const Spacer(),
          const Text('HW Encode', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(width: 4),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: _preferHw,
              onChanged: (v) {
                setState(() {
                  _preferHw = v;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlaysTab(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Add Text row
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _textOverlayController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Type text overlay...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: const Color(0xFF1E1E1E),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final label = _textOverlayController.text.trim();
                    if (label.isNotEmpty) {
                      final duration = _timeline.durationMs;
                      final startMs = _playheadTimelineMs;
                      final endMs = (startMs + 5000).clamp(0, duration);
                      final overlay = VideoOverlayItem.text(
                        id: 'text:$label:${DateTime.now().millisecondsSinceEpoch}',
                        startMs: startMs,
                        endMs: endMs,
                        anchor: const Offset(0.3, 0.4),
                        label: label,
                      );
                      _timeline.addOverlay(overlay);
                      _textOverlayController.clear();
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Emoji quick grid
          const Text('Tap Emoji to Insert:', style: TextStyle(color: Colors.white70, fontSize: 11)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['✨', '🔥', '😂', '❤️', '👍', '🎉', '💡', '🍕'].map((emoji) {
              return InkWell(
                onTap: () {
                  final duration = _timeline.durationMs;
                  final startMs = _playheadTimelineMs;
                  final endMs = (startMs + 5000).clamp(0, duration);
                  final overlay = VideoOverlayItem.emoji(
                    id: 'emoji:$emoji:${DateTime.now().millisecondsSinceEpoch}',
                    startMs: startMs,
                    endMs: endMs,
                    anchor: const Offset(0.7, 0.2),
                    emoji: emoji,
                  );
                  _timeline.addOverlay(overlay);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(emoji, style: const TextStyle(fontSize: 16)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Active overlays list with delete buttons
          if (_timeline.overlays.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Active Overlays:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                TextButton(
                  onPressed: _clearOverlays,
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                  child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ..._timeline.overlays.map((o) {
              final parts = o.id.split(':');
              final type = parts.isNotEmpty ? parts[0] : '';
              final content = parts.length > 1 ? parts[1] : '';

              final isText = type == 'text';
              final isEmoji = type == 'emoji';

              IconData icon;
              if (isText) {
                icon = Icons.title;
              } else if (isEmoji) {
                icon = Icons.emoji_emotions;
              } else {
                icon = Icons.portrait;
              }

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: Colors.white54),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        content,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${_formatDuration(o.startMs)} - ${_formatDuration(o.endMs)}',
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                      onPressed: () {
                        _timeline.removeOverlay(o.id);
                        setState(() {});
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTrimmerRow() {
    final selectionLabel =
        '${_formatDuration((_startSec * 1000).round())} → '
        '${_formatDuration((_endSec * 1000).round())}';
    final durationSec = (_runtime?.mediaInfo?.durationMs.toInt() ?? 0) / 1000.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Trim Duration: $selectionLabel', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              if (_loadingFilmstrip)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            ],
          ),
          const SizedBox(height: 8),
          FilmstripTrimmer(
            thumbPaths: _filmstripPaths,
            durationSeconds: durationSec,
            startSeconds: _startSec,
            endSeconds: _endSec,
            onRangeChanged: _onRangeChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLine() {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        _statusLine,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static String _formatDuration(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
}



class _StatLine extends StatelessWidget {
  const _StatLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
