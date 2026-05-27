import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

import 'demo_session.dart';
import 'output_paths.dart';

/// On-device timing suite — same operations as `vp_bench`, runnable on a phone.
class DeviceBenchmarkPage extends StatefulWidget {
  const DeviceBenchmarkPage({super.key, required this.session});

  final DemoSession session;

  @override
  State<DeviceBenchmarkPage> createState() => _DeviceBenchmarkPageState();
}

class _BenchRow {
  _BenchRow({
    required this.name,
    required this.ms,
    required this.ok,
    this.detail,
  });

  final String name;
  final int ms;
  final bool ok;
  final String? detail;
}

class _DeviceBenchmarkPageState extends State<DeviceBenchmarkPage> {
  final List<_BenchRow> _rows = [];
  bool _running = false;
  bool _includeNetworkNote = false;
  bool _benchHardware = true;
  /// LGPL mobile FFmpeg builds have HW encoders only (no libx264 on device).
  bool _benchSoftware = !Platform.isAndroid && !Platform.isIOS;

  DemoSession get _s => widget.session;

  Future<void> _runSuite() async {
    if (!_s.canProcess) return;
    final input = _s.selectedInput!;
    final outputs = _s.outputPaths ?? await OutputPaths.resolve();
    final benchDir = outputs.benchmarkWorkDir();
    await Directory(benchDir).create(recursive: true);

    setState(() {
      _running = true;
      _rows.clear();
      _includeNetworkNote = _s.inputIsNetwork;
    });

    Future<_BenchRow> timed(String name, Future<String?> Function() fn) async {
      final sw = Stopwatch()..start();
      try {
        final detail = await fn();
        sw.stop();
        return _BenchRow(name: name, ms: sw.elapsedMilliseconds, ok: true, detail: detail);
      } catch (e) {
        sw.stop();
        return _BenchRow(
          name: name,
          ms: sw.elapsedMilliseconds,
          ok: false,
          detail: e.toString(),
        );
      }
    }

    Future<void> pushRow(_BenchRow row) async {
      if (!mounted) return;
      setState(() => _rows.add(row));
    }

    await pushRow(
      await timed('Probe metadata', () async {
        final info = await VideoProcessor.getMediaInfo(input);
        return '${info.width}×${info.height} · ${info.videoCodec}';
      }),
    );

    await pushRow(
      await timed('Thumbnail (1 frame @ 2s, 640px)', () async {
        // Fixed name under benchDir (writable); avoid writing beside picker tmp files.
        final out = p.join(benchDir, 'bench_thumb.jpg');
        final path = await VideoProcessor.thumbnail(
          input: input,
          output: out,
          position: const Duration(seconds: 2),
          width: 640,
        );
        final size = File(path).lengthSync();
        return '$path (${(size / 1024).round()} KB)';
      }),
    );

    await pushRow(
      await timed('Batch thumbnails (10 × 1s, 320px)', () async {
        final dir = p.join(benchDir, 'bench_frames');
        await Directory(dir).create(recursive: true);
        final result = await VideoProcessor.batchThumbnails(
          input: input,
          outputDir: dir,
          positions: List.generate(10, (i) => Duration(seconds: i)),
          width: 320,
        );
        return '${result.paths.length} files';
      }),
    );

    if (_benchSoftware) {
      await pushRow(
        await timed('Compress (medium, software)', () async {
          final out = '$benchDir/bench_sw.mp4';
          final result = await VideoProcessor.compress(
            input: input,
            output: out,
            quality: VideoQuality.medium,
            preferHardwareEncoder: false,
          );
          return '${result.encoderName} · ${result.pipelineMode} · HW=${result.usedHardwareAcceleration} · '
              '${(result.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB';
        }),
      );
    }

    if (_benchHardware) {
      await pushRow(
        await timed('Compress (medium, hardware preferred)', () async {
          final out = '$benchDir/bench_hw.mp4';
          final result = await VideoProcessor.compress(
            input: input,
            output: out,
            quality: VideoQuality.medium,
            preferHardwareEncoder: true,
          );
          return '${result.encoderName} · ${result.pipelineMode} · HW=${result.usedHardwareAcceleration} · '
              '${(result.fileSize.toInt() / (1024 * 1024)).toStringAsFixed(1)} MB';
        }),
      );
    }

    await pushRow(
      await timed('Compress (Instagram preset)', () async {
        final out = '$benchDir/bench_instagram.mp4';
        final result = await VideoProcessor.compressWithPreset(
          input: input,
          output: out,
          preset: CompressionPreset.instagram,
        );
        return '${result.encoderName} · ${result.pipelineMode} · HW=${result.usedHardwareAcceleration}';
      }),
    );

    if (!mounted) return;
    setState(() => _running = false);
  }

  String _markdownReport() {
    final b = StringBuffer()
      ..writeln('# Device benchmark (${_s.platformLabel})')
      ..writeln()
      ..writeln('Input: ${_s.selectedInput}')
      ..writeln('Network: ${_s.inputIsNetwork}')
      ..writeln();
    for (final r in _rows) {
      final status = r.ok ? '${r.ms} ms' : 'FAILED (${r.ms} ms)';
      b.writeln('- **${r.name}**: $status');
      if (r.detail != null) b.writeln('  - ${r.detail}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final canRun = _s.canProcess && !_running;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'On-device benchmark',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Runs the same operations as the desktop `vp_bench` tool '
                  '(probe, thumbnail, batch, compress). Use a local video on '
                  'phone for stable numbers; network adds CDN latency.\n\n'
                  'There is no `vp_bench` binary on mobile — this screen is '
                  'the phone equivalent.\n\n'
                  'Results appear step-by-step. Full 1080p compress can take '
                  'several minutes — wait for the spinner to stop.',
                ),
                if (_s.isMobile) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Compress should show vt_gpu_scale (downscale) or vt_zero_copy. '
                    'sw_decode+swscale means HW decode is off — rebuild FFmpeg then native: '
                    './tools/ffmpeg/apple-ios-device.sh && ./scripts/run-ios.sh',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!_s.hasVideo)
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Select a video on the Process tab first'),
            ),
          ),
        SwitchListTile(
          title: const Text('Include software compress'),
          subtitle: Platform.isAndroid
              ? const Text('Not available on Android (LGPL build uses MediaCodec only)')
              : null,
          value: _benchSoftware,
          onChanged: _running ? null : (v) => setState(() => _benchSoftware = v),
        ),
        SwitchListTile(
          title: const Text('Include hardware compress'),
          subtitle: Text(
            _s.isMobile
                ? 'VideoToolbox / MediaCodec when available'
                : 'NVENC / VAAPI / VideoToolbox on desktop',
          ),
          value: _benchHardware,
          onChanged: _running ? null : (v) => setState(() => _benchHardware = v),
        ),
        FilledButton.icon(
          onPressed: canRun ? _runSuite : null,
          icon: _running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.speed),
          label: Text(_running ? 'Running…' : 'Run full benchmark suite'),
        ),
        if (_includeNetworkNote) ...[
          const SizedBox(height: 8),
          Text(
            'Network input: times include streaming latency.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
          ),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Results', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._rows.map(
            (r) => Card(
              child: ListTile(
                leading: Icon(
                  r.ok ? Icons.check_circle : Icons.error,
                  color: r.ok ? Colors.green : Colors.red,
                ),
                title: Text(r.name),
                subtitle: r.detail != null ? Text(r.detail!) : null,
                trailing: Text(
                  '${r.ms} ms',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _markdownReport()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Results copied to clipboard')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy results as Markdown'),
          ),
        ],
      ],
    );
  }
}
