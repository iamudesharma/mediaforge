import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:path/path.dart' as p;

import '../demo_session.dart';
import '../output_paths.dart';

/// Product-style demo: one screen that shows *why* to use [VideoProcessor].
///
/// Highlights from the package review: Rust/FFmpeg core, network inputs, social
/// presets, cached disk thumbnails, trim export, hardware encode, cancellable jobs.
class ShowcasePage extends StatefulWidget {
  const ShowcasePage({super.key, required this.session});

  final DemoSession session;

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  static const _sampleUrl =
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/360/Big_Buck_Bunny_360_10s_1MB.mp4';
  static const _filmstripCount = 8;

  List<String> _filmstripPaths = [];
  CompressionPreset _preset = CompressionPreset.instagram;
  double _trimStartSec = 0;
  double _trimEndSec = 0;
  CompressResult? _exportResult;
  int? _inputBytes;
  StreamSubscription<ProgressEvent>? _progressSub;

  DemoSession get _s => widget.session;

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  Future<void> _ensureInit() async {
    if (!_s.initialized) await _s.initialize();
  }

  Future<void> _pickLocal() async {
    await _ensureInit();
    if (!mounted) return;
    await _s.pickVideo(context: context);
    if (!mounted) return;
    _resetLocalPreview();
    if (_s.hasVideo) await _autoProbe();
  }

  Future<void> _loadNetworkSample() async {
    await _ensureInit();
    _resetLocalPreview();
    final ok = await _s.useNetworkUrl(_sampleUrl);
    if (ok && mounted) {
      setState(() {
        _trimEndSec = _s.durationSeconds > 0 ? _s.durationSeconds : 1;
        _inputBytes = _s.info?.fileSize.toInt();
      });
    }
  }

  void _resetLocalPreview() {
    setState(() {
      _filmstripPaths = [];
      _exportResult = null;
      _inputBytes = null;
      _trimStartSec = 0;
      _trimEndSec = _s.durationSeconds > 0 ? _s.durationSeconds : 1;
    });
  }

  Future<void> _autoProbe() async {
    if (!_s.hasVideo) return;
    try {
      final info = await _s.probe();
      _inputBytes = info.fileSize.toInt();
      setState(() {
        _trimEndSec = _s.durationSeconds > 0 ? _s.durationSeconds : 1;
      });
    } catch (_) {}
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

  Future<void> _runFilmstripDemo() async {
    final input = _s.selectedInput;
    if (input == null || !_s.canProcess) return;

    _s.setBusy(
      status: 'Filmstrip: cached disk thumbnails ($_filmstripCount frames)…',
    );
    try {
      final positions = _evenlySpacedPositions(
        _filmstripCount,
        _s.durationSeconds,
      );
      final paths = await VideoProcessor.batchThumbnailPathsCached(
        input: input,
        positions: positions,
        width: 200,
      );
      final existing = <String>[];
      for (final path in paths) {
        if (await File(path).exists()) {
          existing.add(path);
        }
      }
      if (existing.length != paths.length) {
        throw StateError(
          'Only ${existing.length} of ${paths.length} thumbnails were written to disk',
        );
      }
      if (!mounted) return;
      setState(() => _filmstripPaths = existing);
      _s.setIdle(
        status: 'Filmstrip ready · ${existing.length} cached JPEGs on disk',
      );
    } catch (e) {
      _s.setIdle(status: 'Filmstrip failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Filmstrip failed: $e')),
        );
      }
    }
  }

  Future<void> _exportClip() async {
    final input = _s.selectedInput;
    if (input == null || !_s.canProcess) return;

    var outputs = _s.outputPaths;
    outputs ??= await OutputPaths.resolve();
    _s.outputPaths = outputs;

    final out = p.join(
      outputs.compressVideoDir,
      '${outputs.safeStem(input)}_showcase_${_preset.name}.mp4',
    );
    await Directory(outputs.compressVideoDir).create(recursive: true);

    final startMs = (_trimStartSec * 1000).round();
    final endMs = (_trimEndSec * 1000).round();

    _s.setBusy(status: 'Exporting (${_preset.label})…', progress: 0);
    setState(() => _exportResult = null);

    try {
      await _progressSub?.cancel();
      final job = await VideoProcessor.compressJob(
        input: input,
        output: out,
        quality: _preset.quality,
        preferHardwareEncoder: _preset.preferHardwareEncoder && _s.isMobile,
        fastStart: true,
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
      final outBytes = await File(result.outputPath).length();
      final saved = _inputBytes != null && _inputBytes! > 0
          ? (100 - (outBytes / _inputBytes! * 100)).clamp(0, 99)
          : null;

      setState(() => _exportResult = result);
      _s.setIdle(
        status: 'Export done · ${result.encoderName}'
            '${result.usedHardwareAcceleration ? ' · HW' : ''}'
            '${saved != null ? ' · ~${saved.toStringAsFixed(0)}% smaller' : ''}',
        progress: 1,
      );
    } catch (e) {
      if (e.toString().contains('cancelled') ||
          e.toString().contains('Cancelled')) {
        _s.setIdle(status: 'Export cancelled');
      } else {
        _s.setIdle(status: 'Export failed: $e');
      }
    }
  }

  Future<void> _cancelExport() async {
    final job = _s.activeJob;
    if (job == null) return;
    try {
      await job.cancel();
    } catch (e) {
      _s.setIdle(status: 'Cancel failed: $e');
    }
  }

  Future<void> _runFullWalkthrough() async {
    if (!_s.hasVideo) {
      await _pickLocal();
      if (!_s.hasVideo) return;
    }
    await _runFilmstripDemo();
    if (!mounted || !_s.canProcess) return;
    await _exportClip();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s,
      builder: (context, _) {
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHero(context)),
            SliverToBoxAdapter(child: _buildWhySection(context)),
            SliverToBoxAdapter(child: _buildInputSection(context)),
            if (_s.info != null)
              SliverToBoxAdapter(child: _buildMetadataCard(context)),
            if (_s.info != null && _filmstripPaths.isEmpty)
              SliverToBoxAdapter(child: _buildFilmstripPlaceholder(context)),
            if (_filmstripPaths.isNotEmpty)
              SliverToBoxAdapter(child: _buildFilmstripSection(context)),
            SliverToBoxAdapter(child: _buildTrimAndExport(context)),
            if (_exportResult != null)
              SliverToBoxAdapter(child: _buildResultCard(context)),
            SliverToBoxAdapter(child: _buildComparison(context)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  Widget _buildHero(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.secondaryContainer,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'video_forge_kit',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'One LGPL FFmpeg engine in Rust — compress, trim, probe, and batch '
            'thumbnails on device or from HTTPS. No shelling out to ffmpeg CLI.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _s.busy ? null : _runFullWalkthrough,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Run full demo'),
              ),
              OutlinedButton.icon(
                onPressed: _s.busy ? null : _ensureInit,
                icon: Icon(_s.initialized ? Icons.check_circle : Icons.power),
                label: Text(_s.initialized ? 'Engine ready' : 'Initialize'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWhySection(BuildContext context) {
    const features = [
      (
        Icons.hub_outlined,
        'Network + local',
        'Probe and transcode https:// URLs (mobile FFmpeg with TLS).',
      ),
      (
        Icons.photo_library_outlined,
        'Cached thumbnails',
        'batchThumbnailPathsCached — filmstrip on disk, low RAM in the UI.',
      ),
      (
        Icons.content_cut_outlined,
        'Trim export',
        'startMs / endMs on compress — export only the selected range.',
      ),
      (
        Icons.phone_android_outlined,
        'Hardware encode',
        'VideoToolbox (iOS) & MediaCodec (Android) when available.',
      ),
      (
        Icons.tune_outlined,
        'Social presets',
        'Instagram, WhatsApp, Telegram, YouTube quality mappings.',
      ),
      (
        Icons.cancel_outlined,
        'Cancellable jobs',
        'compressJob + progress stream; cancel without freezing UI.',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Why this package?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...features.map(
            (f) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(f.$1, color: Theme.of(context).colorScheme.primary),
                title: Text(f.$2),
                subtitle: Text(f.$3),
                dense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1 · Choose input', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _s.busy ? null : _pickLocal,
                icon: Icon(
                  Platform.isIOS
                      ? Icons.photo_library_outlined
                      : Icons.folder_open,
                ),
                label: Text(
                  Platform.isIOS ? 'Pick from Photos' : 'Pick video',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _s.busy ? null : _loadNetworkSample,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('HTTPS sample'),
              ),
            ],
          ),
          if (_s.selectedName != null) ...[
            const SizedBox(height: 8),
            Text(
              _s.inputIsNetwork ? 'URL: ${_s.selectedName}' : 'File: ${_s.selectedName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _s.status,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (_s.busy && _s.progress > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(value: _s.progress.clamp(0.0, 1.0)),
            ),
        ],
      ),
    );
  }

  Widget _buildMetadataCard(BuildContext context) {
    final info = _s.info;
    if (info == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('2 · Probe (getMediaInfo)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _StatRow(
                label: 'Resolution',
                value: '${info.width}×${info.height}',
              ),
              _StatRow(label: 'Codec', value: info.videoCodec),
              _StatRow(
                label: 'Duration',
                value: DemoSession.formatDuration(info.durationMs.toInt()),
              ),
              _StatRow(
                label: 'Size',
                value: '${(info.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(2)} MB',
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _s.busy ? null : _autoProbe,
                icon: const Icon(Icons.refresh),
                label: const Text('Re-probe'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilmstripPlaceholder(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('3 · Batch thumbnails (disk cache)'),
          subtitle: const Text(
            'One decode pass — JPEGs cached on disk for fast reload and low RAM.',
          ),
          trailing: FilledButton(
            onPressed: _s.canProcess ? _runFilmstripDemo : null,
            child: const Text('Generate'),
          ),
        ),
      ),
    );
  }

  Widget _buildFilmstripSection(BuildContext context) {
    final cacheWidth = 200 * MediaQuery.devicePixelRatioOf(context).round();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3 · Batch thumbnails (disk cache)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${_filmstripPaths.length} frames · cached under app temp',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _filmstripPaths.length,
              separatorBuilder: (context, index) => const SizedBox(width: 4),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(_filmstripPaths[i]),
                  width: 56,
                  height: 72,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  cacheWidth: cacheWidth,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _s.canProcess ? _runFilmstripDemo : null,
            icon: const Icon(Icons.grid_on_outlined),
            label: const Text('Regenerate filmstrip'),
          ),
        ],
      ),
    );
  }

  Widget _buildTrimAndExport(BuildContext context) {
    final dur = _s.durationSeconds;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('4 · Trim & export (compressJob)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (dur > 0) ...[
                Text(
                  'Range ${DemoSession.formatDuration((_trimStartSec * 1000).round())}'
                  ' → ${DemoSession.formatDuration((_trimEndSec * 1000).round())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                RangeSlider(
                  values: RangeValues(
                    _trimStartSec.clamp(0.0, dur),
                    _trimEndSec.clamp(_trimStartSec, dur),
                  ),
                  min: 0,
                  max: dur,
                  onChanged: _s.busy
                      ? null
                      : (v) => setState(() {
                            _trimStartSec = v.start;
                            _trimEndSec = v.end;
                          }),
                ),
              ],
              Text('Preset', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: CompressionPreset.values.map((preset) {
                  final selected = _preset == preset;
                  return FilterChip(
                    label: Text(preset.label),
                    selected: selected,
                    onSelected: _s.busy
                        ? null
                        : (v) {
                            if (v) setState(() => _preset = preset);
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _s.canProcess ? _exportClip : null,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Export trimmed MP4'),
                    ),
                  ),
                  if (_s.busy && _s.activeJob != null) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: _cancelExport,
                      icon: const Icon(Icons.stop_circle_outlined),
                      tooltip: 'Cancel job',
                    ),
                  ],
                ],
              ),
              if (_filmstripPaths.isEmpty && _s.canProcess)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _runFilmstripDemo,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Generate filmstrip first'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context) {
    final r = _exportResult;
    if (r == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Export result', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(r.outputPath, style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 8),
              _StatRow(
                label: 'Output size',
                value:
                    '${(r.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(2)} MB',
              ),
              _StatRow(label: 'Encoder', value: r.encoderName),
              _StatRow(
                label: 'Hardware',
                value: r.usedHardwareAcceleration ? 'Yes' : 'No',
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.outputPath));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Path copied')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy output path'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparison(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('vs typical Flutter compress plugins',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.1),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
            },
            border: TableBorder.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
            ),
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('Capability', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('This package', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('OS-only plugins', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              _cmpRow('HTTPS / RTMP input', '✓', 'Usually local only'),
              _cmpRow('Batch thumbnails (1 pass)', '✓', 'Often N seeks'),
              _cmpRow('Trim + compress', '✓', 'Rare'),
              _cmpRow('Social quality presets', '✓', 'Generic quality'),
              _cmpRow('Rust + cancel jobs', '✓', 'Varies'),
              _cmpRow('Max simplicity', 'More API surface', '✓'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Use Studio for a full editor UI, Process for low-level knobs, '
            'Queue for concurrent jobs, Benchmark for timings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  TableRow _cmpRow(String feature, String us, String them) {
    return TableRow(
      children: [
        Padding(padding: const EdgeInsets.all(8), child: Text(feature)),
        Padding(padding: const EdgeInsets.all(8), child: Text(us)),
        Padding(padding: const EdgeInsets.all(8), child: Text(them)),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
