import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import 'demo_session.dart';

/// Sprint V1.7 — ROADMAP perf matrix scenarios I / J / K on device.
class MediaRuntimePerfPage extends StatefulWidget {
  const MediaRuntimePerfPage({super.key, required this.session});

  final DemoSession session;

  @override
  State<MediaRuntimePerfPage> createState() => _MediaRuntimePerfPageState();
}

class _MediaRuntimePerfPageState extends State<MediaRuntimePerfPage> {
  final List<MediaRuntimePerfResult> _results = [];
  bool _running = false;
  String? _liveStatus;
  MediaRuntime? _studioRuntime;

  DemoSession get _s => widget.session;

  @override
  void dispose() {
    _studioRuntime?.dispose();
    super.dispose();
  }

  Future<void> _runAll() async {
    final path = _s.selectedInput;
    if (path == null || !_s.canProcess) return;

    setState(() {
      _running = true;
      _results.clear();
      _liveStatus = 'Opening…';
    });

    _studioRuntime?.dispose();
    _studioRuntime = MediaRuntime(
      previewMaxEdge: 720,
      targetPreviewFps: 30,
      scrubDebounce: const Duration(milliseconds: 280),
    );

    try {
      await _studioRuntime!.open(path);
      if (!mounted) return;

      setState(() => _liveStatus = 'Scenario I — scrub 5s…');
      _results.add(await MediaRuntimePerf.runScenarioI(_studioRuntime!));
      if (!mounted) return;
      setState(() {});

      setState(() => _liveStatus = 'Scenario J — play 10s…');
      _results.add(await MediaRuntimePerf.runScenarioJ(_studioRuntime!));
      if (!mounted) return;
      setState(() {});

      _studioRuntime!.dispose();
      _studioRuntime = null;

      setState(() => _liveStatus = 'Scenario K — open/dispose ×10…');
      _results.add(await MediaRuntimePerf.runScenarioK(path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Perf matrix failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _liveStatus = _studioRuntime?.metricsSnapshot.toStatusLine();
        });
      }
    }
  }

  String _markdown() {
    final b = StringBuffer()
      ..writeln('# MediaRuntime perf matrix (${_s.platformLabel})')
      ..writeln()
      ..writeln('| ID | Scenario | Pass | Time | Summary |')
      ..writeln('|----|----------|------|------|---------|');
    for (final r in _results) {
      b.writeln(
        '| ${r.id} | ${r.title} | ${r.passed ? "✓" : "✗"} | ${r.elapsedMs} ms | ${r.summary} |',
      );
    }
    b.writeln();
    b.writeln(
      'Targets: I p95 ≤ ${MediaRuntimePerfTargets.scrubP95Ms} ms, '
      'J ≥ ${MediaRuntimePerfTargets.playbackMinFps} fps, '
      'K 0 texture leaks / ${MediaRuntimePerfTargets.openDisposeCycles} cycles.',
    );
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final canRun = _s.canProcess && !_running;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview perf matrix (V1.7)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  '**I** — 720p scrub 5 s: debounced frame ≤ 300 ms p95, no disk JPEG on hot path.\n'
                  '**J** — Play 10 s in trim: ≥ 24 fps at previewMaxEdge 720.\n'
                  '**K** — Open/close ×10: no texture handle leaks after [close].\n\n'
                  'Use a local 720p–1080p clip. Full rebuild after Rust changes: '
                  './scripts/run-android.sh',
                ),
                if (_liveStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _liveStatus!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
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
              title: Text('Pick a video on Process or Studio first'),
            ),
          ),
        FilledButton.icon(
          onPressed: canRun ? _runAll : null,
          icon: _running
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_circle_outline),
          label: Text(_running ? 'Running I → J → K…' : 'Run perf matrix (I, J, K)'),
        ),
        if (_results.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Results', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._results.map(
            (r) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(r.id),
                ),
                title: Text(r.title),
                subtitle: Text(r.summary),
                trailing: Icon(
                  r.passed ? Icons.check_circle : Icons.cancel,
                  color: r.passed ? Colors.green : Colors.red,
                ),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _markdown()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Perf matrix copied')),
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
