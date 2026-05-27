import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../status_item.dart';

/// Demo "send to chat" sheet (no real messaging).
Future<void> showSendToChatSheet(
  BuildContext context, {
  required StatusItem item,
}) {
  const recipients = [
    ('Aarav', Icons.person_outline),
    ('Family group', Icons.family_restroom_outlined),
    ('Work team', Icons.groups_outlined),
  ];

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final orig = item.originalBytes;
      final comp = item.compressedBytes;
      final saved = orig != null && comp != null && orig > comp ? orig - comp : null;
      final duration = item.jobDuration;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Send to chat (demo)',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              if (saved != null || duration != null) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (orig != null && comp != null)
                      '${_mb(orig)} → ${_mb(comp)}',
                    if (saved != null) 'saved ${_mb(saved)}',
                    if (duration != null) '${duration.inMilliseconds / 1000}s encode',
                  ].join(' · '),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              ...recipients.map(
                (r) => ListTile(
                  leading: Icon(r.$2),
                  title: Text(r.$1),
                  onTap: () {
                    Navigator.pop(ctx);
                    final path = item.outputPath ?? item.stablePath ?? '';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sent to ${r.$1} (demo) · ${item.displayName}'),
                        action: path.isNotEmpty
                            ? SnackBarAction(
                                label: 'Copy path',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: path));
                                },
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
