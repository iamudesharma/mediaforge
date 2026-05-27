import 'dart:io';

import 'package:flutter/material.dart';

import '../status_item.dart';
import 'send_to_chat_sheet.dart';

class StatusItemTile extends StatelessWidget {
  const StatusItemTile({
    super.key,
    required this.item,
    required this.onPreview,
    required this.onRemove,
    this.onTrimAndPost,
  });

  final StatusItem item;
  final VoidCallback onPreview;
  final VoidCallback onRemove;
  final VoidCallback? onTrimAndPost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = item.thumbPath;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumb(
              path: thumb,
              progress: item.progress,
              phase: item.phase,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.statusMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: item.isFailed
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (item.isDraft && item.durationSec > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Draft · trim up to ${item.trimLengthSec.toStringAsFixed(1)}s selected',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  if (item.originalBytes != null && item.compressedBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_mb(item.originalBytes!)} → ${_mb(item.compressedBytes!)}'
                        '${item.jobDuration != null ? ' · ${(item.jobDuration!.inMilliseconds / 1000).toStringAsFixed(1)}s' : ''}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  if (item.isDraft && onTrimAndPost != null) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: onTrimAndPost,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.content_cut, size: 18),
                      label: const Text('Trim & post'),
                    ),
                  ],
                  if (item.isReady) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: onPreview,
                          icon: const Icon(Icons.play_circle_outline, size: 18),
                          label: const Text('Preview'),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => showSendToChatSheet(context, item: item),
                          icon: const Icon(Icons.send_outlined, size: 18),
                          label: const Text('Send to chat'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: onRemove,
              tooltip: 'Remove',
            ),
          ],
        ),
      ),
    );
  }

  String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.path,
    required this.progress,
    required this.phase,
  });

  final String? path;
  final double progress;
  final StatusItemPhase phase;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    Widget child;
    if (path != null && File(path!).existsSync()) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path!),
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    } else {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          phase == StatusItemPhase.failed
              ? Icons.error_outline
              : phase == StatusItemPhase.preparing
                  ? Icons.hourglass_top
                  : Icons.movie_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (phase == StatusItemPhase.ready ||
        phase == StatusItemPhase.failed ||
        phase == StatusItemPhase.draft) {
      return child;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
              strokeWidth: 2,
            ),
          ),
        ],
      ),
    );
  }
}
