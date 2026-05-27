import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_video_processor/flutter_video_processor.dart';

import 'demo_session.dart';
import 'output_paths.dart';

/// Demonstrates [VideoProcessorQueue] for bounded concurrent compression.
class QueuePage extends StatefulWidget {
  const QueuePage({super.key, required this.session});

  final DemoSession session;

  @override
  State<QueuePage> createState() => _QueuePageState();
}

class _QueueJobUi {
  _QueueJobUi({
    required this.label,
    required this.preset,
    required this.jobFuture,
  });

  final String label;
  final CompressionPreset preset;
  final Future<VideoJob> jobFuture;
  VideoJob? job;
  String status = 'Queued';
  double progress = 0;
}

class _QueuePageState extends State<QueuePage> {
  VideoProcessorQueue? _queue;
  final List<_QueueJobUi> _jobs = [];
  CompressionPreset _preset = CompressionPreset.standard;
  int _jobCount = 2;

  DemoSession get _s => widget.session;

  @override
  void dispose() {
    _queue?.dispose();
    super.dispose();
  }

  void _ensureQueue() {
    _queue ??= VideoProcessorQueue(maxConcurrent: 2);
  }

  Future<void> _enqueueJobs() async {
    if (!_s.canProcess) return;
    _ensureQueue();
    final input = _s.selectedInput!;
    final outputs = _s.outputPaths ?? await OutputPaths.resolve();

    final presets = [
      _preset,
      CompressionPreset.telegram,
      CompressionPreset.whatsapp,
    ];

    setState(() {
      for (var i = 0; i < _jobCount; i++) {
        final preset = presets[i % presets.length];
        final label = '${preset.label} #${i + 1}';
        final out = outputs.compressOutputFor('${input}_queue_$i');
        final ui = _QueueJobUi(
          label: label,
          preset: preset,
          jobFuture: _queue!.enqueueCompress(
            input: input,
            output: out,
            preset: preset,
          ),
        );
        _jobs.add(ui);
        unawaited(_watchJob(ui));
      }
    });
  }

  Future<void> _watchJob(_QueueJobUi ui) async {
    try {
      final job = await ui.jobFuture;
      ui.job = job;
      ui.status = 'Running';
      if (mounted) setState(() {});

      job.progress.listen((e) {
        ui.progress = e.percent;
        ui.status = DemoSession.phaseLabel(e.phase);
        if (mounted) setState(() {});
      });

      final result = await job.result;
      ui.status = 'Done · ${result.encoderName} · '
          'HW ${result.usedHardwareAcceleration ? "yes" : "no"}';
      ui.progress = 1;
      await job.cleanup();
    } catch (e) {
      ui.status = 'Error: $e';
    }
    if (mounted) setState(() {});
  }

  void _clearFinished() {
    setState(_jobs.clear);
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Compress queue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enqueues multiple compress jobs with max 2 running at once '
                  '(native job semaphore). Good for upload + compress workflows.',
                ),
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
        DropdownButtonFormField<CompressionPreset>(
          initialValue: _preset,
          decoration: const InputDecoration(
            labelText: 'First job preset',
            border: OutlineInputBorder(),
          ),
          items: CompressionPreset.values
              .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
              .toList(),
          onChanged: _s.busy ? null : (v) => setState(() => _preset = v ?? _preset),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Jobs to enqueue:'),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _jobCount,
              items: const [
                DropdownMenuItem(value: 1, child: Text('1')),
                DropdownMenuItem(value: 2, child: Text('2')),
                DropdownMenuItem(value: 3, child: Text('3')),
              ],
              onChanged: _s.busy ? null : (v) => setState(() => _jobCount = v ?? 2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _s.canProcess ? _enqueueJobs : null,
          icon: const Icon(Icons.queue),
          label: const Text('Enqueue compress jobs'),
        ),
        if (queue != null) ...[
          const SizedBox(height: 8),
          Text(
            'Queue: ${queue.pendingCount} pending · ${queue.runningCount} running',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        OutlinedButton(
          onPressed: _jobs.isEmpty
              ? null
              : () {
                  queue?.clearPending();
                  _clearFinished();
                },
          child: const Text('Clear list'),
        ),
        if (_jobs.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Jobs', style: Theme.of(context).textTheme.titleMedium),
          ..._jobs.map(
            (j) => Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.label, style: Theme.of(context).textTheme.titleSmall),
                    Text(j.status, style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: j.progress > 0 ? j.progress.clamp(0.0, 1.0) : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
