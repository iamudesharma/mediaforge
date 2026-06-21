import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:video_forge/video_forge.dart';

import '../compositor/video_overlay_item.dart';
import '../job_handle.dart';
import '../models/clip_effects.dart';
import '../models/compression_preset.dart';
import '../timeline/timeline_models.dart';
import '../video_processor.dart';
import 'overlay_raster_exporter.dart';

/// Per-clip timeline export (Phase C): encode segments → concat.
abstract final class TimelineExportService {
  static bool needsSegmentedExport(List<VideoTimelineClip> clips) =>
      ClipEffectsKit.needsSegmentedExport(clips);

  /// Overlays visible during [clip], shifted to clip-local timeline ms.
  static List<VideoOverlayItem> overlaysForClip(
    List<VideoOverlayItem> all,
    VideoTimelineClip clip,
  ) {
    final out = <VideoOverlayItem>[];
    for (final o in all) {
      if (o.endMs <= clip.timelineStartMs || o.startMs >= clip.timelineEndMs) {
        continue;
      }
      final start =
          math.max(o.startMs, clip.timelineStartMs) - clip.timelineStartMs;
      final end = math.min(o.endMs, clip.timelineEndMs) - clip.timelineStartMs;
      if (end > start) {
        out.add(o.copyWith(startMs: start, endMs: end));
      }
    }
    return out;
  }

  static ClipEffects? exportEffectsFor(VideoTimelineClip clip) {
    final fx = ClipEffectsKit.forClip(clip);
    return ClipEffectsKit.isIdentity(fx) ? null : fx;
  }

  /// Encode each timeline clip, then stream-copy concat to [outputPath].
  static Future<VideoJob> compressTimeline({
    required List<VideoTimelineClip> clips,
    required String outputPath,
    required VideoQuality quality,
    required CompressionPreset preset,
    bool preferHardwareEncoder = true,
    List<VideoOverlayItem> overlays = const [],
    int sourceWidth = 1920,
    int sourceHeight = 1080,
    List<AudioTrackInput> audioTracks = const [],
    bool muteOriginalAudio = false,
    int? singleClipStartMs,
    int? singleClipEndMs,
  }) async {
    if (clips.isEmpty) {
      throw ArgumentError('compressTimeline: no clips');
    }
    if (!needsSegmentedExport(clips)) {
      final clip = clips.first;
      final burnIn = await _rasterizeOverlays(
        overlays: overlaysForClip(overlays, clip),
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        preset: preset,
      );
      final fx = exportEffectsFor(clip);
      return VideoProcessor.compressJob(
        input: clip.sourcePath,
        output: outputPath,
        quality: quality,
        preferHardwareEncoder:
            preferHardwareEncoder && burnIn.isEmpty && fx == null,
        startMs: singleClipStartMs ?? clip.sourceStartMs,
        endMs: singleClipEndMs ?? clip.sourceEndMs,
        burnInOverlays: burnIn,
        audioTracks: audioTracks,
        muteOriginalAudio: muteOriginalAudio,
        clipEffects: fx,
      );
    }

    if (audioTracks.isNotEmpty) {
      debugPrint(
        '[TimelineExport] multi-clip: external audio tracks skipped (source audio per segment)',
      );
    }

    final controller = StreamController<ProgressEvent>();
    final completer = Completer<CompressResult>();
    final tempDir = await Directory.systemTemp.createTemp('vfe_timeline_export_');
    final segmentPaths = <String>[];

    unawaited(() async {
      try {
        for (var i = 0; i < clips.length; i++) {
          final clip = clips[i];
          final segPath = '${tempDir.path}/seg_$i.mp4';
          segmentPaths.add(segPath);
          final burnIn = await _rasterizeOverlays(
            overlays: overlaysForClip(overlays, clip),
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            preset: preset,
          );
          final segJob = await VideoProcessor.compressJob(
            input: clip.sourcePath,
            output: segPath,
            quality: quality,
            preferHardwareEncoder: false,
            startMs: clip.sourceStartMs,
            endMs: clip.sourceEndMs,
            burnInOverlays: burnIn,
            muteOriginalAudio: muteOriginalAudio,
            clipEffects: exportEffectsFor(clip),
          );
          await for (final event in segJob.progress) {
            final slice = (i + event.percent) / clips.length;
            if (!controller.isClosed) {
              controller.add(
                ProgressEvent(
                  jobId: 'timeline_export',
                  phase: event.phase,
                  percent: slice.clamp(0.0, 0.99),
                  frame: event.frame,
                  fps: event.fps,
                  etaMs: event.etaMs,
                ),
              );
            }
          }
          final segResult = await segJob.result;
          await segJob.cleanup();
          debugPrint(
            '[TimelineExport] segment $i/${clips.length} done '
            'bytes=${segResult.fileSize}',
          );
        }

        if (!controller.isClosed) {
          controller.add(
            ProgressEvent(
              jobId: 'timeline_export',
              phase: ProcessingPhase.muxing,
              percent: 0.99,
              frame: BigInt.zero,
              fps: 0,
              etaMs: BigInt.zero,
            ),
          );
        }

        await VideoProcessor.concatVideoFiles(
          paths: segmentPaths,
          outputPath: outputPath,
        );

        final info = await VideoProcessor.getMediaInfo(outputPath);
        final fileSize = await File(outputPath).length();
        if (!controller.isClosed) {
          controller.add(
            ProgressEvent(
              jobId: 'timeline_export',
              phase: ProcessingPhase.done,
              percent: 1.0,
              frame: BigInt.zero,
              fps: 0,
              etaMs: BigInt.zero,
            ),
          );
        }
        completer.complete(
          CompressResult(
            outputPath: outputPath,
            durationMs: info.durationMs,
            fileSize: BigInt.from(fileSize),
            usedHardwareAcceleration: false,
            encoderName: 'concat',
            pipelineMode: 'timeline_segments',
          ),
        );
        debugPrint(
          '[TimelineExport] concat ready path=$outputPath '
          'durationMs=${info.durationMs} clips=${clips.length}',
        );
      } catch (e, st) {
        debugPrint('[TimelineExport] failed: $e');
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
        completer.completeError(e, st);
      } finally {
        for (final p in segmentPaths) {
          try {
            await File(p).delete();
          } catch (_) {}
        }
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
        await controller.close();
      }
    }());

    return VideoJob(
      id: 'timeline_export',
      progress: controller.stream,
      result: completer.future,
    );
  }

  static Future<List<BurnInOverlay>> _rasterizeOverlays({
    required List<VideoOverlayItem> overlays,
    required int sourceWidth,
    required int sourceHeight,
    required CompressionPreset preset,
  }) async {
    if (overlays.isEmpty) return const [];
    return OverlayRasterExporter.rasterizeForExport(
      overlays: overlays,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
      preset: preset,
    );
  }
}
