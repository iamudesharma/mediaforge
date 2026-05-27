import 'dart:async';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:video_processor_core/video_processor_core.dart';
import 'package:video_processor_core/video_processor_core.dart' as core;
import 'package:video_thumbnail_cache/video_thumbnail_cache.dart';

import 'job_handle.dart';
import 'models/compress_options.dart';
import 'models/compression_preset.dart';

export 'package:video_processor_core/video_processor_core.dart'
    show
        MediaInfo,
        PreviewFrameRgba,
        PreviewFramePixelBuffer,
        ProgressEvent,
        ProcessingPhase,
        VideoCodec,
        VideoQuality,
        ThumbnailFormat,
        CompressResult,
        BatchThumbnailResult,
        BatchThumbnailOptions,
        BatchThumbnailBytesResult,
        BatchThumbnailBytesOptions,
        ThumbnailBytesOptions,
        ThumbnailOptions,
        JobResult_Compress,
        JobResult_Empty;

/// High-performance video processing powered by Rust + FFmpeg.
abstract final class VideoProcessor {
  /// True when [input] is an HTTP(S) or other remote URL the native FFmpeg layer can open.
  static bool isNetworkInput(String input) =>
      ThumbnailCache.isNetworkInput(input);

  /// Initialize native bindings. Call once before any other API.
  static Future<void> initialize() => core.NativeBindings.ensureInitialized();

  /// Probe media metadata (mp4parse fast path, FFmpeg fallback).
  static Future<MediaInfo> getMediaInfo(String path) async {
    await initialize();
    return core.getMediaInfo(path: path);
  }

  /// Stream-copy a remote URL to a local file under [destDir].
  static Future<String> prefetchRemoteInput({
    required String url,
    required String destDir,
  }) async {
    await initialize();
    return core.prefetchRemoteInput(url: url, destDir: destDir);
  }

  /// Compress using an app-style [CompressionPreset] (Instagram, WhatsApp, etc.).
  static Future<CompressResult> compressWithPreset({
    required String input,
    CompressionPreset preset = CompressionPreset.standard,
    String? output,
    void Function(ProgressEvent progress)? onProgress,
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
    return compress(
      input: input,
      output: output,
      quality: preset.quality,
      onProgress: onProgress,
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
    );
  }

  /// Compress video with a quality preset.
  static Future<CompressResult> compress({
    required String input,
    VideoQuality quality = VideoQuality.medium,
    String? output,
    void Function(ProgressEvent progress)? onProgress,
    VideoCodec codec = VideoCodec.h264,
    int? crf,
    int? targetBitrate,
    int? maxWidth,
    int? maxHeight,
    double? maxFps,
    bool includeAudio = true,
    bool fastStart = true,
    bool fragmentedMp4 = false,
    bool preferHardwareEncoder = true,
    int? startMs,
    int? endMs,
  }) async {
    final job = await compressJob(
      input: input,
      output: output,
      quality: quality,
      codec: codec,
      crf: crf,
      targetBitrate: targetBitrate,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxFps: maxFps,
      includeAudio: includeAudio,
      fastStart: fastStart,
      fragmentedMp4: fragmentedMp4,
      preferHardwareEncoder: preferHardwareEncoder,
      startMs: startMs,
      endMs: endMs,
    );

    StreamSubscription<ProgressEvent>? sub;
    if (onProgress != null) {
      sub = job.progress.listen(onProgress);
    }

    try {
      return await job.result;
    } finally {
      await sub?.cancel();
      final id = await job.resolvedId;
      await core.cleanupJob(jobId: id);
    }
  }

  /// Start compression and receive a [VideoJob] for progress/cancel control.
  static Future<VideoJob> compressJob({
    required String input,
    String? output,
    VideoQuality quality = VideoQuality.medium,
    VideoCodec codec = VideoCodec.h264,
    int? crf,
    int? targetBitrate,
    int? maxWidth,
    int? maxHeight,
    double? maxFps,
    bool includeAudio = true,
    bool fastStart = true,
    bool fragmentedMp4 = false,
    bool preferHardwareEncoder = true,
    int? startMs,
    int? endMs,
  }) async {
    await initialize();

    final options = CompressOptionsBuilder(
      inputPath: input,
      outputPath: output,
      quality: quality,
      codec: codec,
      crf: crf,
      targetBitrate: targetBitrate,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxFps: maxFps,
      includeAudio: includeAudio,
      fastStart: fastStart,
      fragmentedMp4: fragmentedMp4,
      preferHardwareEncoder: preferHardwareEncoder,
      startMs: startMs,
      endMs: endMs,
    ).build();

    final progressStream = core.startCompress(options: options);
    final controller = StreamController<ProgressEvent>();
    late String jobId;
    final completer = Completer<String>();

    progressStream.listen(
      (event) {
        if (!completer.isCompleted) {
          jobId = event.jobId;
          completer.complete(jobId);
        }
        controller.add(event);
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    await completer.future;

    final resultFuture = core.waitForJob(jobId: jobId).then((jobResult) {
      return switch (jobResult) {
        JobResult_Compress(:final field0) => field0,
        JobResult_Empty() => throw StateError('Job completed without result'),
      };
    });

    return VideoJob(
      id: jobId,
      progress: controller.stream,
      result: resultFuture,
    );
  }

  /// Decode one preview frame as RGBA8888 (texture scrub — no JPEG on disk).
  static Future<PreviewFrameRgba> decodePreviewFrameRgba({
    required String inputPath,
    required int positionMs,
    int? maxEdge,
  }) async {
    await initialize();
    return core.decodePreviewFrameRgba(
      inputPath: inputPath,
      positionMs: BigInt.from(positionMs),
      maxEdge: maxEdge,
    );
  }

  /// Apple VideoToolbox → BGRA `CVPixelBuffer` for zero-copy texture (V1.4).
  static Future<PreviewFramePixelBuffer> decodePreviewFramePixelBuffer({
    required String inputPath,
    required int positionMs,
    int? maxEdge,
  }) async {
    await initialize();
    return core.decodePreviewFramePixelBuffer(
      inputPath: inputPath,
      positionMs: BigInt.from(positionMs),
      maxEdge: maxEdge,
    );
  }

  /// Release a native buffer when texture present did not run.
  static void releasePreviewPixelBuffer(int pixelBufferPtr) {
    if (pixelBufferPtr == 0) return;
    core.releasePreviewPixelBuffer(
      pixelBufferPtr: BigInt.from(pixelBufferPtr),
    );
  }

  /// JPEG/WebP bytes for a single frame — no file write (UI previews).
  static Future<Uint8List> thumbnailBytes({
    required String input,
    Duration position = Duration.zero,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
  }) async {
    await initialize();
    return core.thumbnailBytes(
      options: ThumbnailBytesOptions(
        inputPath: input,
        positionMs: BigInt.from(position.inMilliseconds),
        width: width,
        height: height,
        format: format,
      ),
    );
  }

  /// Multiple frames as encoded image bytes — no file write.
  static Future<List<Uint8List>> batchThumbnailBytes({
    required String input,
    required List<Duration> positions,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
  }) async {
    await initialize();
    final result = await core.batchThumbnailBytes(
      options: BatchThumbnailBytesOptions(
        inputPath: input,
        positionsMs: Uint64List.fromList(
          positions.map((d) => d.inMilliseconds).toList(),
        ),
        width: width,
        height: height,
        format: format,
      ),
    );
    return result.frames;
  }

  /// Extract a single thumbnail at [position].
  static Future<String> thumbnail({
    required String input,
    Duration position = Duration.zero,
    String? output,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
  }) async {
    await initialize();
    return core.thumbnail(
      options: ThumbnailOptions(
        inputPath: input,
        outputPath: output,
        positionMs: BigInt.from(position.inMilliseconds),
        width: width,
        height: height,
        format: format,
      ),
    );
  }

  /// Extract thumbnails at multiple timestamps in one job.
  static Future<BatchThumbnailResult> batchThumbnails({
    required String input,
    required List<Duration> positions,
    required String outputDir,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
  }) async {
    await initialize();
    return core.batchThumbnails(
      options: BatchThumbnailOptions(
        inputPath: input,
        outputDir: outputDir,
        outputPaths: null,
        positionsMs: Uint64List.fromList(
          positions.map((d) => d.inMilliseconds).toList(),
        ),
        width: width,
        height: height,
        format: format,
      ),
    );
  }

  /// Returns active native job count.
  static Future<int> activeJobCount() async {
    await initialize();
    return core.activeJobCount();
  }

  /// Cached thumbnail on disk (JPEG/WebP).
  static Future<String> thumbnailPathCached({
    required String input,
    Duration position = Duration.zero,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
  }) async {
    await initialize();
    final file = await ThumbnailCache.getOrCreate(
      input: input,
      position: position,
      format: format,
      width: width,
      height: height,
    );
    return file.path;
  }

  /// Cached batch thumbnails on disk — one file per [positions] entry, same order.
  static Future<List<String>> batchThumbnailPathsCached({
    required String input,
    required List<Duration> positions,
    ThumbnailFormat format = ThumbnailFormat.jpeg,
    int? width,
    int? height,
    int missConcurrency = ThumbnailCache.defaultMissConcurrency,
  }) async {
    await initialize();
    final files = await ThumbnailCache.batchGetOrCreate(
      input: input,
      positions: positions,
      format: format,
      width: width,
      height: height,
      missConcurrency: missConcurrency,
    );
    return files.map((f) => f.path).toList();
  }

  /// Evict disk cache for one input.
  static Future<void> evictThumbnailCacheForInput(String input) {
    return ThumbnailCache.evictForInput(input);
  }

  /// Clear all cached thumbnails.
  static Future<void> evictAllThumbnailCache() {
    return ThumbnailCache.evictAll();
  }
}
