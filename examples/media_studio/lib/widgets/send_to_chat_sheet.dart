import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Demo "send to chat" sheet (no real messaging).
Future<void> showSendToChatSheet(
  BuildContext context, {
  required String displayName,
  required String path,
  int? originalBytes,
  int? compressedBytes,
  Duration? encodeDuration,
}) {
  const recipients = [
    ('Aarav', Icons.person_outline),
    ('Family group', Icons.family_restroom_outlined),
    ('Work team', Icons.groups_outlined),
  ];

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: const Color(0xFF1C1C1E),
    builder: (ctx) {
      final saved = originalBytes != null && compressedBytes != null && originalBytes > compressedBytes 
          ? originalBytes - compressedBytes 
          : null;

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Send to chat (demo)',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: Colors.white),
              ),
              if (originalBytes != null || compressedBytes != null || saved != null || encodeDuration != null) ...[
                const SizedBox(height: 8),
                Text(
                  [
                    if (originalBytes != null && compressedBytes != null)
                      '${_mb(originalBytes)} → ${_mb(compressedBytes)}',
                    if (saved != null) 'saved ${_mb(saved)}',
                    if (encodeDuration != null) '${(encodeDuration.inMilliseconds / 1000).toStringAsFixed(1)}s encode',
                  ].join(' · '),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.white54),
                ),
              ],
              const SizedBox(height: 16),
              ...recipients.map(
                (r) => ListTile(
                  leading: Icon(r.$2, color: Colors.white70),
                  title: Text(r.$1, style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sent to ${r.$1} (demo) · $displayName'),
                        behavior: SnackBarBehavior.floating,
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
