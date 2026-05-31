import 'dart:async';

import 'package:video_forge/video_forge.dart';

/// Handle to a background video processing job with progress and cancellation.
class VideoJob {
  const VideoJob._({
    required this.id,
    required this.progress,
    required this.result,
  });

  /// Unique job identifier (matches progress events).
  final String id;

  /// Throttled progress stream (~4 Hz) from the Rust worker.
  final Stream<ProgressEvent> progress;

  /// Completes when the job finishes, is cancelled, or fails.
  final Future<CompressResult> result;

  /// Request cancellation. Always prefer this over cancelling the progress subscription.
  Future<void> cancel() => cancelJob(jobId: id);

  /// Remove job state from the native registry after completion.
  Future<void> cleanup() => cleanupJob(jobId: id);

  /// Creates a [VideoJob] with known id and streams.
  factory VideoJob({
    required String id,
    required Stream<ProgressEvent> progress,
    required Future<CompressResult> result,
  }) =>
      VideoJob._(id: id, progress: progress, result: result);
}

/// Resolved job id helper when id is not known upfront.
extension VideoJobId on VideoJob {
  Future<String> get resolvedId async {
    if (id.isNotEmpty) return id;
    final first = await progress.first;
    return first.jobId;
  }
}
