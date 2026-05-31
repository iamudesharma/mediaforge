import 'package:flutter/foundation.dart';

enum StatusItemPhase {
  /// Ingest + probe (no transcode yet).
  preparing,
  /// Trim UI — metadata only until user posts.
  draft,
  queued,
  compressing,
  ready,
  failed,
}

@immutable
class StatusItem {
  const StatusItem({
    required this.id,
    required this.displayName,
    required this.sourcePath,
    this.stablePath,
    this.outputPath,
    this.thumbPath,
    this.phase = StatusItemPhase.preparing,
    this.progress = 0,
    this.statusMessage = 'Reading metadata…',
    this.originalBytes,
    this.compressedBytes,
    this.durationSec = 0,
    this.trimStartSec = 0,
    this.trimEndSec = 0,
    this.videoWidth,
    this.videoHeight,
    this.videoCodec,
    this.fps,
    this.startedAt,
    this.finishedAt,
    this.error,
  });

  final String id;
  final String displayName;
  final String sourcePath;
  final String? stablePath;
  final String? outputPath;
  final String? thumbPath;
  final StatusItemPhase phase;
  final double progress;
  final String statusMessage;
  final int? originalBytes;
  final int? compressedBytes;
  final double durationSec;
  final double trimStartSec;
  final double trimEndSec;
  final int? videoWidth;
  final int? videoHeight;
  final String? videoCodec;
  final double? fps;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? error;

  bool get isReady => phase == StatusItemPhase.ready;
  bool get isFailed => phase == StatusItemPhase.failed;
  bool get isDraft => phase == StatusItemPhase.draft;
  bool get isPreparing => phase == StatusItemPhase.preparing;
  bool get isInFlight =>
      phase == StatusItemPhase.queued || phase == StatusItemPhase.compressing;

  double get trimLengthSec =>
      (trimEndSec - trimStartSec).clamp(0, durationSec > 0 ? durationSec : 0);

  Duration? get jobDuration {
    if (startedAt == null || finishedAt == null) return null;
    return finishedAt!.difference(startedAt!);
  }

  StatusItem copyWith({
    String? stablePath,
    String? outputPath,
    String? thumbPath,
    StatusItemPhase? phase,
    double? progress,
    String? statusMessage,
    int? originalBytes,
    int? compressedBytes,
    double? durationSec,
    double? trimStartSec,
    double? trimEndSec,
    int? videoWidth,
    int? videoHeight,
    String? videoCodec,
    double? fps,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
  }) {
    return StatusItem(
      id: id,
      displayName: displayName,
      sourcePath: sourcePath,
      stablePath: stablePath ?? this.stablePath,
      outputPath: outputPath ?? this.outputPath,
      thumbPath: thumbPath ?? this.thumbPath,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      originalBytes: originalBytes ?? this.originalBytes,
      compressedBytes: compressedBytes ?? this.compressedBytes,
      durationSec: durationSec ?? this.durationSec,
      trimStartSec: trimStartSec ?? this.trimStartSec,
      trimEndSec: trimEndSec ?? this.trimEndSec,
      videoWidth: videoWidth ?? this.videoWidth,
      videoHeight: videoHeight ?? this.videoHeight,
      videoCodec: videoCodec ?? this.videoCodec,
      fps: fps ?? this.fps,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      error: error ?? this.error,
    );
  }
}
