import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

import 'media_ingest.dart';
import 'output_paths.dart';
import 'video_input.dart';
import 'video_picker.dart';

/// Shared state for all demo tabs (process, queue, benchmark).
class DemoSession extends ChangeNotifier {
  String status = 'Tap Initialize, then pick a video or URL';
  double progress = 0;
  bool initialized = false;
  bool busy = false;
  String? selectedInput;
  String? selectedName;
  bool inputIsNetwork = false;
  MediaInfo? info;
  VideoJob? activeJob;
  OutputPaths? outputPaths;

  bool get hasVideo =>
      selectedInput != null && VideoInput.isValid(selectedInput!);

  bool get canProcess => initialized && hasVideo && !busy;

  int? get durationMs => info?.durationMs.toInt();

  double get durationSeconds =>
      (durationMs ?? 0) > 0 ? durationMs! / 1000.0 : 0;

  bool get isMobile => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  String get platformLabel {
    if (kIsWeb) return 'web';
    return Platform.operatingSystem;
  }

  Future<void> initialize() async {
    busy = true;
    status = 'Initializing native engine…';
    notifyListeners();
    try {
      await VideoProcessor.initialize();
      OutputPaths.clearCache();
      outputPaths = await OutputPaths.resolve();
      initialized = true;
      final outHint = outputPaths!.isProjectLocal
          ? 'Outputs → example/output/'
          : 'Outputs → app documents (see Output tab)';
      status = hasVideo
          ? 'Ready — ${selectedName ?? "video"}\n$outHint'
          : 'Ready — pick a video or URL\n$outHint';
    } catch (e) {
      status = 'Initialize failed: $e';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// Returns true when a local file was chosen and ingest succeeded.
  Future<bool> pickVideo({BuildContext? context}) async {
    final result = await pickVideoWithPlatformPicker(context: context);

    if (result == null || result.files.isEmpty) {
      status = 'No file selected';
      notifyListeners();
      return false;
    }

    final file = result.files.first;
    final path = file.path;
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      status = 'Could not read file path';
      notifyListeners();
      return false;
    }

    return ingestFromSource(
      path,
      displayName: file.name,
      isNetwork: false,
    );
  }

  Future<bool> useNetworkUrl(
    String raw, {
    bool cacheRemoteLocally = false,
  }) async {
    final url = VideoInput.normalizeUrl(raw);
    if (!VideoInput.isNetworkUrl(url)) {
      status = 'Enter a valid http(s):// video URL';
      notifyListeners();
      return false;
    }
    return ingestFromSource(
      url,
      displayName: VideoInput.displayName(url),
      isNetwork: !cacheRemoteLocally,
      cacheRemoteLocally: cacheRemoteLocally,
    );
  }

  /// Copy local picks to stable storage, probe, and set [selectedInput].
  Future<bool> ingestFromSource(
    String source, {
    required String displayName,
    required bool isNetwork,
    bool cacheRemoteLocally = false,
  }) async {
    final previous = selectedInput;
    if (previous != null && previous != source) {
      await VideoProcessor.evictThumbnailCacheForInput(previous);
    }

    busy = true;
    info = null;
    progress = 0;
    selectedName = displayName;
    inputIsNetwork = isNetwork;
    status = isNetwork ? 'Loading URL…' : 'Importing video…';
    notifyListeners();

    try {
      if (!initialized) {
        await VideoProcessor.initialize();
      }
      final result = await MediaIngest.ingestLocalVideo(
        source,
        cacheRemoteLocally: cacheRemoteLocally,
        onStatus: (s) {
          status = s;
          notifyListeners();
        },
      );

      if (result.phase != MediaIngestPhase.ready ||
          result.stablePath == null) {
        _clearVideoSelection();
        status = result.error ?? 'Import failed';
        notifyListeners();
        return false;
      }

      selectedInput = result.stablePath;
      info = result.info;
      OutputPaths.clearCache();
      outputPaths = await OutputPaths.resolve();

      final copyNote = result.skippedCopy ? '' : ' · copied locally';
      if (info != null) {
        status =
            '${formatDuration(info!.durationMs.toInt())} · ${info!.width}×${info!.height} · '
            '${info!.videoCodec}$copyNote';
      } else {
        status = initialized
            ? 'Ready — $displayName$copyNote'
            : 'Ready — $displayName (tap Initialize)$copyNote';
      }
      notifyListeners();
      return true;
    } catch (e) {
      _clearVideoSelection();
      status = 'Import failed: $e';
      notifyListeners();
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _clearVideoSelection() {
    selectedInput = null;
    selectedName = null;
    inputIsNetwork = false;
    info = null;
  }

  Future<MediaInfo> probe() async {
    final input = selectedInput;
    if (input == null || !hasVideo) {
      throw StateError('No video selected');
    }
    busy = true;
    status = 'Probing…';
    progress = 0;
    notifyListeners();
    try {
      final result = await VideoProcessor.getMediaInfo(input);
      info = result;
      status =
          '${formatDuration(result.durationMs.toInt())} · ${result.width}×${result.height} · '
          '${result.videoCodec} · ${(result.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB';
      return result;
    } catch (e) {
      status = 'Probe error: $e';
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static String formatDuration(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final h = m ~/ 60;
    if (h > 0) return '${h}h ${m % 60}m ${s % 60}s';
    if (m > 0) return '${m}m ${s % 60}s';
    return '${s}s';
  }

  void touch() => notifyListeners();

  void setBusy({String? status, double? progress}) {
    busy = true;
    if (status != null) this.status = status;
    if (progress != null) this.progress = progress;
    notifyListeners();
  }

  void setIdle({String? status, double? progress}) {
    busy = false;
    activeJob = null;
    if (status != null) this.status = status;
    if (progress != null) this.progress = progress;
    notifyListeners();
  }

  void updateProgress({required String status, required double progress}) {
    this.status = status;
    this.progress = progress;
    notifyListeners();
  }

  static String phaseLabel(ProcessingPhase phase) {
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
}
