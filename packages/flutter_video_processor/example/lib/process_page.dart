import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

import 'demo_session.dart';
import 'output_paths.dart';
enum ThumbnailMode { single, entireVideo }

class _CompressSettings {
  CompressionPreset preset = CompressionPreset.standard;
  VideoQuality get quality => preset.quality;
  VideoCodec codec = VideoCodec.h264;
  int? crf;
  int? maxWidth;
  int? maxHeight;
  bool includeAudio = true;
  bool preferHardwareEncoder = true;
  bool fastStart = true;
}

class _ThumbnailSettings {
  ThumbnailMode mode = ThumbnailMode.single;
  double positionSeconds = 2;
  double intervalSeconds = 1;
  int maxFrames = 60;
  ThumbnailFormat format = ThumbnailFormat.jpeg;
  int? width;
  int? height;
}

/// Main processing UI: pick video, compress, thumbnails, network URL.
class ProcessPage extends StatefulWidget {
  const ProcessPage({super.key, required this.session});

  final DemoSession session;

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

class _ProcessPageState extends State<ProcessPage> {
  final _compressSettings = _CompressSettings();
  final _thumbnail = _ThumbnailSettings();
  final _positionController = TextEditingController(text: '2');
  final _intervalController = TextEditingController(text: '1');
  final _maxFramesController = TextEditingController(text: '60');
  final _crfController = TextEditingController();
  final _maxWidthController = TextEditingController();
  final _maxHeightController = TextEditingController();
  final _thumbWidthController = TextEditingController();
  final _thumbHeightController = TextEditingController();
  final _urlController = TextEditingController();
  bool _cacheRemoteLocally = false;

  StreamSubscription<ProgressEvent>? _progressSub;

  DemoSession get _s => widget.session;

  static const _sampleUrls = [
    (
      '360p sample (~1 MB)',
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4',
    ),
    (
      '720p sample (~5 MB)',
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_5MB.mp4',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _compressSettings.preferHardwareEncoder = _s.isMobile;
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    _positionController.dispose();
    _intervalController.dispose();
    _maxFramesController.dispose();
    _crfController.dispose();
    _maxWidthController.dispose();
    _maxHeightController.dispose();
    _thumbWidthController.dispose();
    _thumbHeightController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _syncFields() {
    _thumbnail.positionSeconds =
        double.tryParse(_positionController.text) ?? _thumbnail.positionSeconds;
    _thumbnail.intervalSeconds =
        double.tryParse(_intervalController.text) ?? _thumbnail.intervalSeconds;
    _thumbnail.maxFrames =
        int.tryParse(_maxFramesController.text) ?? _thumbnail.maxFrames;
    _compressSettings.crf = int.tryParse(_crfController.text);
    _compressSettings.maxWidth = int.tryParse(_maxWidthController.text);
    _compressSettings.maxHeight = int.tryParse(_maxHeightController.text);
    _thumbnail.width = int.tryParse(_thumbWidthController.text);
    _thumbnail.height = int.tryParse(_thumbHeightController.text);
  }

  Future<void> _probe() async {
    try {
      final info = await _s.probe();
      final durationSec = info.durationMs.toInt() / 1000.0;
      if (_positionController.text == '2' && durationSec > 0) {
        final mid = (durationSec / 2).clamp(0.0, durationSec).toDouble();
        _positionController.text = mid.toStringAsFixed(1);
        _thumbnail.positionSeconds = mid;
      }
    } catch (_) {}
  }

  Future<void> _runCompress() async {
    _syncFields();
    final path = _s.selectedInput!;
    final outputs = _s.outputPaths ?? await OutputPaths.resolve();
    final outputFile = outputs.compressOutputFor(path);

    _s.setBusy(
      status: 'Compressing (${_compressSettings.preset.label}) →\n$outputFile',
      progress: 0,
    );

    try {
      await _progressSub?.cancel();
      final job = await VideoProcessor.compressJob(
        input: path,
        output: outputFile,
        quality: _compressSettings.quality,
        codec: _compressSettings.codec,
        crf: _compressSettings.crf,
        maxWidth: _compressSettings.maxWidth,
        maxHeight: _compressSettings.maxHeight,
        includeAudio: _compressSettings.includeAudio,
        fastStart: _compressSettings.fastStart,
        preferHardwareEncoder: _compressSettings.preferHardwareEncoder,
      );
      _s.activeJob = job;
      _progressSub = job.progress.listen((event) {
        _s.updateProgress(
          status:
              '${DemoSession.phaseLabel(event.phase)} ${(event.percent * 100).toStringAsFixed(1)}%',
          progress: event.percent,
        );
      });

      final result = await job.result;
      _s.setIdle(
        status: 'Saved: ${result.outputPath}\n'
            '${(result.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB · '
            '${result.encoderName} · HW: ${result.usedHardwareAcceleration ? "yes" : "no"}',
        progress: 1,
      );
      await job.cleanup();
    } catch (e) {
      _s.setIdle(status: 'Compress error: $e');
    }
  }

  List<Duration> _buildThumbnailPositions() {
    final durationMs = _s.durationMs ?? 0;
    if (durationMs <= 0) {
      return [Duration(milliseconds: (_thumbnail.positionSeconds * 1000).round())];
    }
    if (_thumbnail.mode == ThumbnailMode.single) {
      final sec = _thumbnail.positionSeconds.clamp(0, _s.durationSeconds);
      return [Duration(milliseconds: (sec * 1000).round())];
    }
    final rawIntervalMs = (_thumbnail.intervalSeconds * 1000).round();
    final intervalMs = rawIntervalMs <= 0
        ? 1
        : rawIntervalMs.clamp(1, durationMs > 0 ? durationMs : rawIntervalMs);
    final positions = <Duration>[];
    for (var ms = 0; ms < durationMs && positions.length < _thumbnail.maxFrames; ms += intervalMs) {
      positions.add(Duration(milliseconds: ms));
    }
    if (positions.isEmpty) positions.add(Duration.zero);
    return positions;
  }

  Future<void> _runThumbnail() async {
    _syncFields();
    final path = _s.selectedInput!;
    final outputs = _s.outputPaths ?? await OutputPaths.resolve();
    final ext = _thumbnail.format == ThumbnailFormat.webp ? 'webp' : 'jpg';

    _s.setBusy(status: 'Thumbnail…');

    try {
      if (_thumbnail.mode == ThumbnailMode.single) {
        final outputFile = outputs.thumbnailOutputFor(path, ext: ext);
        _s.status = 'Thumbnail @ ${_thumbnail.positionSeconds}s →\n$outputFile';
        _s.touch();
        final out = await VideoProcessor.thumbnail(
          input: path,
          output: outputFile,
          position: Duration(
            milliseconds: (_thumbnail.positionSeconds * 1000).round(),
          ),
          format: _thumbnail.format,
          width: _thumbnail.width,
          height: _thumbnail.height,
        );
        _s.setIdle(status: 'Thumbnail saved: $out');
      } else {
        final positions = _buildThumbnailPositions();
        final outDir = outputs.batchThumbnailDirFor(path);
        await Directory(outDir).create(recursive: true);
        _s.setBusy(
          status: 'Extracting ${positions.length} thumbnails (parallel)…\n$outDir',
        );
        final result = await VideoProcessor.batchThumbnails(
          input: path,
          outputDir: outDir,
          positions: positions,
          format: _thumbnail.format,
          width: _thumbnail.width,
          height: _thumbnail.height,
        );
        _s.setIdle(status: 'Saved ${result.paths.length} thumbnails to:\n$outDir');
      }
    } catch (e) {
      _s.setIdle(status: 'Thumbnail error: $e');
    }
  }

  Future<void> _cancelJob() async {
    await _s.activeJob?.cancel();
    await _progressSub?.cancel();
    _s.setIdle(status: 'Cancelled', progress: 0);
  }

  Widget _numberField({
    required String label,
    required TextEditingController controller,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      enabled: !_s.busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = _s.info;
    final outputs = _s.outputPaths;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: Icon(
              _s.isMobile ? Icons.smartphone : Icons.computer,
            ),
            title: Text('Platform: ${_s.platformLabel}'),
            subtitle: Text(
              _s.isMobile
                  ? 'Hardware encoder recommended on device'
                  : 'Desktop demo — use Benchmark tab or `vp_bench` CLI',
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_s.status),
                if (_s.hasVideo && _s.selectedInput != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _s.inputIsNetwork ? 'Network URL' : 'Local file',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                  Text(
                    _s.selectedInput!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _s.progress > 0 ? _s.progress.clamp(0.0, 1.0) : null,
                ),
              ],
            ),
          ),
        ),
        if (outputs != null)
          Card(
            child: ListTile(
              title: const Text('Output folders'),
              subtitle: Text(
                'Compress: ${outputs.compressVideoDir}\n'
                'Thumbnails: ${outputs.thumbnailDir}',
              ),
              isThreeLine: true,
            ),
          ),
        if (info != null)
          Card(
            child: ListTile(
              title: const Text('Media info'),
              subtitle: Text(
                'Codec: ${info.videoCodec} @ ${info.fps.toStringAsFixed(1)} fps\n'
                'Bitrate: ${(info.bitrate.toInt() / 1000).round()} kbps · '
                'Audio: ${info.audioCodec ?? "none"}',
              ),
            ),
          ),
        Card(child: _buildCompressOptions()),
        Card(child: _buildThumbnailOptions()),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Network URL', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Tap a sample or paste a URL. Requires internet on device. '
                  'Some hosts (e.g. file-examples.com) return HTTP 403 for direct download.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _sampleUrls
                      .map(
                        (s) => ActionChip(
                          label: Text(s.$1),
                          onPressed: _s.busy
                              ? null
                              : () async {
                                  _urlController.text = s.$2;
                                  final ok = await _s.useNetworkUrl(
                                    s.$2,
                                    cacheRemoteLocally: _cacheRemoteLocally,
                                  );
                                  if (!context.mounted) return;
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(_s.status)),
                                    );
                                  }
                                },
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  enabled: !_s.busy,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.link),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cache remote locally'),
                  subtitle: const Text(
                    'Download once to app storage (faster filmstrip + compress on same URL)',
                  ),
                  value: _cacheRemoteLocally,
                  onChanged: _s.busy
                      ? null
                      : (v) => setState(() => _cacheRemoteLocally = v),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _s.busy
                      ? null
                      : () async {
                          final ok = await _s.useNetworkUrl(
                            _urlController.text,
                            cacheRemoteLocally: _cacheRemoteLocally,
                          );
                          if (!context.mounted) return;
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_s.status)),
                            );
                          }
                        },
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('Use URL'),
                ),
              ],
            ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _s.busy
              ? null
              : () async => _s.pickVideo(context: context),
          icon: Icon(
            Platform.isIOS ? Icons.photo_library_outlined : Icons.folder_open,
          ),
          label: Text(Platform.isIOS ? 'Pick from Photos' : 'Pick local video'),
        ),
        FilledButton(
          onPressed: _s.busy ? null : _s.initialize,
          child: Text(_s.initialized ? 'Re-initialize' : 'Initialize engine'),
        ),
        FilledButton(
          onPressed: _s.canProcess ? _probe : null,
          child: const Text('Probe metadata'),
        ),
        FilledButton(
          onPressed: _s.canProcess ? _runCompress : null,
          child: Text('Compress (${_compressSettings.preset.label})'),
        ),
        FilledButton(
          onPressed: _s.canProcess ? _runThumbnail : null,
          child: Text(
            _thumbnail.mode == ThumbnailMode.single
                ? 'Create thumbnail'
                : 'Batch thumbnails (one decode pass)',
          ),
        ),
        OutlinedButton(
          onPressed: _s.activeJob != null ? _cancelJob : null,
          child: const Text('Cancel compress job'),
        ),
      ],
    );
  }

  Widget _buildCompressOptions() {
    return ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Compress options'),
      subtitle: Text(
        '${_compressSettings.preset.label} · ${_compressSettings.codec.name} · '
        'HW: ${_compressSettings.preferHardwareEncoder ? "on" : "off"}',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              DropdownButtonFormField<CompressionPreset>(
                initialValue: _compressSettings.preset,
                decoration: const InputDecoration(
                  labelText: 'App preset',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: CompressionPreset.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                    .toList(),
                onChanged: _s.busy
                    ? null
                    : (v) => setState(() {
                          if (v == null) return;
                          _compressSettings.preset = v;
                          _compressSettings.preferHardwareEncoder = v.preferHardwareEncoder;
                        }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<VideoCodec>(
                initialValue: _compressSettings.codec,
                decoration: const InputDecoration(
                  labelText: 'Video codec',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: VideoCodec.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                    .toList(),
                onChanged: _s.busy
                    ? null
                    : (v) => setState(
                          () => _compressSettings.codec = v ?? _compressSettings.codec,
                        ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _numberField(label: 'CRF', controller: _crfController, hint: '23')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _numberField(label: 'Max width', controller: _maxWidthController),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Prefer hardware encoder'),
                subtitle: const Text('VideoToolbox / MediaCodec on mobile'),
                value: _compressSettings.preferHardwareEncoder,
                onChanged: _s.busy
                    ? null
                    : (v) => setState(() => _compressSettings.preferHardwareEncoder = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include audio'),
                value: _compressSettings.includeAudio,
                onChanged: _s.busy ? null : (v) => setState(() => _compressSettings.includeAudio = v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnailOptions() {
    final hasDuration = _s.durationSeconds > 0;
    return ExpansionTile(
      initiallyExpanded: false,
      title: const Text('Thumbnail options'),
      subtitle: Text(
        _thumbnail.mode == ThumbnailMode.single
            ? 'Single @ ${_positionController.text}s'
            : 'Batch every ${_intervalController.text}s',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              SegmentedButton<ThumbnailMode>(
                segments: const [
                  ButtonSegment(
                    value: ThumbnailMode.single,
                    label: Text('Single'),
                    icon: Icon(Icons.image_outlined),
                  ),
                  ButtonSegment(
                    value: ThumbnailMode.entireVideo,
                    label: Text('Batch'),
                    icon: Icon(Icons.collections_outlined),
                  ),
                ],
                selected: {_thumbnail.mode},
                onSelectionChanged: _s.busy ? null : (s) => setState(() => _thumbnail.mode = s.first),
              ),
              const SizedBox(height: 12),
              if (_thumbnail.mode == ThumbnailMode.single) ...[
                _numberField(label: 'Position (s)', controller: _positionController),
                if (hasDuration)
                  Slider(
                    value: _thumbnail.positionSeconds.clamp(0, _s.durationSeconds),
                    min: 0,
                    max: _s.durationSeconds,
                    onChanged: _s.busy
                        ? null
                        : (v) => setState(() {
                              _thumbnail.positionSeconds = v;
                              _positionController.text = v.toStringAsFixed(1);
                            }),
                  ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _numberField(
                        label: 'Interval (s)',
                        controller: _intervalController,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _numberField(
                        label: 'Max frames',
                        controller: _maxFramesController,
                      ),
                    ),
                  ],
                ),
                if (hasDuration)
                  Text('≈ ${_buildThumbnailPositions().length} frames'),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
