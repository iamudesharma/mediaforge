import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../media_ingest.dart';
import '../output_paths.dart';
import '../video_input.dart';
import 'status_item.dart';

/// WhatsApp-style pipeline: prepare (metadata + preview assets) → post (trim + compress).
class StatusPipeline {
  StatusPipeline({
    void Function(StatusItem item)? onItemUpdated,
    this.maxConcurrent = 2,
  }) {
    this.onItemUpdated = onItemUpdated ?? _noop;
  }

  void Function(StatusItem item) onItemUpdated = _noop;

  static void _noop(StatusItem _) {}

  void _notify(StatusItem item) => onItemUpdated(item);
  final int maxConcurrent;

  VideoProcessorQueue? _queue;
  OutputPaths? _outputs;
  DateTime? _batchStartedAt;

  int get pendingCount => _queue?.pendingCount ?? 0;
  int get runningCount => _queue?.runningCount ?? 0;

  Future<void> ensureInitialized() async {
    await VideoProcessor.initialize();
    _queue ??= VideoProcessorQueue(maxConcurrent: maxConcurrent);
    _outputs ??= await OutputPaths.resolve();
  }

  DateTime? get batchStartedAt => _batchStartedAt;

  void dispose() {
    _queue?.dispose();
    _queue = null;
  }

  StatusItem createItem(String sourcePath) {
    final id = const Uuid().v4();
    return StatusItem(
      id: id,
      displayName: VideoInput.displayName(sourcePath),
      sourcePath: sourcePath,
      originalBytes: _fileSize(sourcePath),
    );
  }

  /// Ingest + probe + poster thumb only (no transcode — trim is metadata until post).
  Future<void> prepareDraft(StatusItem item) async {
    await ensureInitialized();

    var current = item.copyWith(
      phase: StatusItemPhase.preparing,
      statusMessage: 'Reading metadata…',
      progress: 0,
    );
    _notify(current);

    try {
      final ingest = await MediaIngest.ingestLocalVideo(
        item.sourcePath,
        onStatus: (s) {
          current = current.copyWith(statusMessage: s);
          _notify(current);
        },
      );

      if (ingest.phase != MediaIngestPhase.ready || ingest.stablePath == null) {
        _notify(
          current.copyWith(
            phase: StatusItemPhase.failed,
            error: ingest.error ?? 'Import failed',
            statusMessage: ingest.error ?? 'Import failed',
            finishedAt: DateTime.now(),
          ),
        );
        return;
      }

      final info = ingest.info!;
      final stablePath = ingest.stablePath!;
      final durSec = info.durationMs.toInt() / 1000.0;
      final outputPath = _outputs!.statusOutputFor(item.id);

      current = current.copyWith(
        stablePath: stablePath,
        outputPath: outputPath,
        statusMessage: 'Poster frame…',
        originalBytes: info.fileSize.toInt(),
        durationSec: durSec > 0 ? durSec : 1,
        trimStartSec: 0,
        trimEndSec: _initialTrimEnd(durSec),
        videoWidth: info.width,
        videoHeight: info.height,
        videoCodec: info.videoCodec,
        fps: info.fps,
      );
      _notify(current);

      String? thumbPath;
      try {
        thumbPath = await VideoProcessor.thumbnailPathCached(
          input: stablePath,
          width: 320,
        );
      } catch (_) {}

      _notify(
        current.copyWith(
          thumbPath: thumbPath,
          phase: StatusItemPhase.draft,
          statusMessage: 'Trim segment — compress runs when you post',
          progress: 0,
        ),
      );
    } catch (e) {
      _notify(
        current.copyWith(
          phase: StatusItemPhase.failed,
          error: e.toString(),
          statusMessage: 'Prepare failed: $e',
          finishedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Background transcode after user confirms trim (WhatsApp "send" step).
  Future<void> postItem(
    StatusItem item, {
    required double trimStartSec,
    required double trimEndSec,
  }) async {
    await ensureInitialized();
    _batchStartedAt ??= DateTime.now();
    final outputs = _outputs!;
    final queue = _queue!;

    final stablePath = item.stablePath;
    if (stablePath == null) {
      _notify(
        item.copyWith(
          phase: StatusItemPhase.failed,
          statusMessage: 'Missing stable path',
          error: 'Not prepared',
        ),
      );
      return;
    }

    final outputPath = item.outputPath ?? outputs.statusOutputFor(item.id);
    await Directory(p.dirname(outputPath)).create(recursive: true);

    final startMs = (trimStartSec * 1000).round();
    final endMs = (trimEndSec * 1000).round();

    var current = item.copyWith(
      trimStartSec: trimStartSec,
      trimEndSec: trimEndSec,
      outputPath: outputPath,
      phase: StatusItemPhase.queued,
      statusMessage: 'Queued for compress…',
      progress: 0,
    );
    _notify(current);

    final jobFuture = queue.enqueueCompress(
      input: stablePath,
      output: outputPath,
      preset: CompressionPreset.whatsapp,
      preferHardwareEncoder:
          !kIsWeb && (Platform.isIOS || Platform.isAndroid),
      startMs: startMs,
      endMs: endMs > startMs ? endMs : null,
      fastStart: true,
    );

    current = current.copyWith(
      phase: StatusItemPhase.compressing,
      statusMessage: 'Compressing (WhatsApp preset)…',
      startedAt: DateTime.now(),
    );
    _notify(current);

    try {
      final job = await jobFuture;
      final started = current.startedAt ?? DateTime.now();

      final progressSub = job.progress.listen((event) {
        _notify(
          current.copyWith(
            progress: event.percent,
            statusMessage: _phaseLabel(event.phase),
          ),
        );
      });

      try {
        final result = await job.result;
        await progressSub.cancel();
        await job.cleanup();

        var thumbPath = current.thumbPath;
        try {
          thumbPath = await VideoProcessor.thumbnailPathCached(
            input: result.outputPath,
            position: Duration(milliseconds: startMs),
            width: 200,
          );
        } catch (_) {}

        final compressedBytes = await File(result.outputPath).length();
        _notify(
          current.copyWith(
            thumbPath: thumbPath,
            phase: StatusItemPhase.ready,
            progress: 1,
            statusMessage: 'Posted · ${result.encoderName}',
            compressedBytes: compressedBytes,
            finishedAt: DateTime.now(),
            startedAt: started,
          ),
        );
      } catch (e) {
        await progressSub.cancel();
        _notify(
          current.copyWith(
            phase: StatusItemPhase.failed,
            error: e.toString(),
            statusMessage: 'Compress failed',
            finishedAt: DateTime.now(),
            startedAt: started,
          ),
        );
      }
    } catch (e) {
      _notify(
        current.copyWith(
          phase: StatusItemPhase.failed,
          error: e.toString(),
          statusMessage: 'Queue failed: $e',
          finishedAt: DateTime.now(),
        ),
      );
    }
  }

  static double _initialTrimEnd(double durationSec) {
    if (durationSec <= 0) return StatusComposerLimits.maxSegmentSec;
    return durationSec.clamp(0, StatusComposerLimits.maxSegmentSec);
  }

  static String _phaseLabel(ProcessingPhase phase) {
    return switch (phase) {
      ProcessingPhase.probing => 'Probing',
      ProcessingPhase.decoding => 'Decoding',
      ProcessingPhase.encoding => 'Encoding',
      ProcessingPhase.muxing => 'Muxing',
      ProcessingPhase.thumbnail => 'Thumbnail',
      ProcessingPhase.done => 'Done',
      ProcessingPhase.cancelled => 'Cancelled',
      ProcessingPhase.failed => 'Failed',
    };
  }

  int? _fileSize(String path) {
    try {
      if (File(path).existsSync()) return File(path).lengthSync();
    } catch (_) {}
    return null;
  }
}

/// WhatsApp status video segment cap (demo).
abstract final class StatusComposerLimits {
  static const maxSegmentSec = 30.0;
  static const filmstripFrames = 10;
  static const filmstripThumbWidth = 120;
}
