import 'dart:async';
import 'dart:collection';

import 'job_handle.dart';
import 'models/compression_preset.dart';
import 'video_processor.dart';

/// Queued compress jobs with bounded concurrency (uses native job semaphore).
class VideoProcessorQueue {
  VideoProcessorQueue({this.maxConcurrent = 2});

  final int maxConcurrent;
  final Queue<_QueuedCompress> _pending = Queue();
  int _running = 0;
  bool _disposed = false;

  /// Number of jobs waiting (not including in-flight).
  int get pendingCount => _pending.length;

  int get runningCount => _running;

  /// Enqueue compression. Returns a [VideoJob] when the job starts (may wait in queue).
  Future<VideoJob> enqueueCompress({
    required String input,
    String? output,
    CompressionPreset preset = CompressionPreset.standard,
    VideoCodec codec = VideoCodec.h264,
    int? crf,
    int? targetBitrate,
    int? maxWidth,
    int? maxHeight,
    double? maxFps,
    bool includeAudio = true,
    bool fastStart = true,
    bool fragmentedMp4 = false,
    bool? preferHardwareEncoder,
    int? startMs,
    int? endMs,
  }) {
    final completer = Completer<VideoJob>();
    _pending.add(
      _QueuedCompress(
        completer: completer,
        input: input,
        output: output,
        quality: preset.quality,
        codec: codec,
        crf: crf,
        targetBitrate: targetBitrate,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        maxFps: maxFps,
        includeAudio: includeAudio,
        fastStart: fastStart,
        fragmentedMp4: fragmentedMp4,
        preferHardwareEncoder:
            preferHardwareEncoder ?? preset.preferHardwareEncoder,
        startMs: startMs,
        endMs: endMs,
      ),
    );
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_disposed) return;
    while (_running < maxConcurrent && _pending.isNotEmpty) {
      final item = _pending.removeFirst();
      _running++;
      unawaited(_run(item));
    }
  }

  Future<void> _run(_QueuedCompress item) async {
    try {
      final job = await VideoProcessor.compressJob(
        input: item.input,
        output: item.output,
        quality: item.quality,
        codec: item.codec,
        crf: item.crf,
        targetBitrate: item.targetBitrate,
        maxWidth: item.maxWidth,
        maxHeight: item.maxHeight,
        maxFps: item.maxFps,
        includeAudio: item.includeAudio,
        fastStart: item.fastStart,
        fragmentedMp4: item.fragmentedMp4,
        preferHardwareEncoder: item.preferHardwareEncoder,
        startMs: item.startMs,
        endMs: item.endMs,
      );
      if (!item.completer.isCompleted) {
        item.completer.complete(job);
      }
    } catch (e, st) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(e, st);
      }
    } finally {
      _running--;
      _pump();
    }
  }

  /// Drop queued (not started) jobs. In-flight jobs are not cancelled.
  void clearPending() {
    while (_pending.isNotEmpty) {
      final item = _pending.removeFirst();
      if (!item.completer.isCompleted) {
        item.completer.completeError(
          StateError('Queue cleared before job started'),
        );
      }
    }
  }

  void dispose() {
    _disposed = true;
    clearPending();
  }
}

class _QueuedCompress {
  _QueuedCompress({
    required this.completer,
    required this.input,
    required this.quality,
    required this.codec,
    required this.preferHardwareEncoder,
    this.output,
    this.crf,
    this.targetBitrate,
    this.maxWidth,
    this.maxHeight,
    this.maxFps,
    this.includeAudio = true,
    this.fastStart = true,
    this.fragmentedMp4 = false,
    this.startMs,
    this.endMs,
  });

  final Completer<VideoJob> completer;
  final String input;
  final String? output;
  final VideoQuality quality;
  final VideoCodec codec;
  final int? crf;
  final int? targetBitrate;
  final int? maxWidth;
  final int? maxHeight;
  final double? maxFps;
  final bool includeAudio;
  final bool fastStart;
  final bool fragmentedMp4;
  final bool preferHardwareEncoder;
  final int? startMs;
  final int? endMs;
}
