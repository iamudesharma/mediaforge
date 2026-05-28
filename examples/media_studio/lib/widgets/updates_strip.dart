import 'dart:io';

import 'package:flutter/material.dart';

class MockStatus {
  final String id;
  final String label;
  final String? imagePath; // Path to output image/video thumbnail
  final String? mediaPath; // Path to output video or photo
  final bool isVideo;
  final Color ringColor;

  const MockStatus({
    required this.id,
    required this.label,
    this.imagePath,
    this.mediaPath,
    required this.isVideo,
    this.ringColor = const Color(0xFF00FF7F),
  });
}

/// Horizontal updates bar for the Home Hub.
class UpdatesStrip extends StatelessWidget {
  const UpdatesStrip({
    super.key,
    required this.contacts,
    required this.onTapStatus,
  });

  final List<MockStatus> contacts;
  final void Function(MockStatus status) onTapStatus;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: Text(
          'No stories posted yet. Create and export a video or photo to post your first update!',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white38),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SizedBox(
      height: 108,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: contacts.length,
        itemBuilder: (context, i) {
          final c = contacts[i];
          return _Bubble(
            label: c.label,
            ringColor: c.ringColor,
            imagePath: c.imagePath,
            onTap: () => onTapStatus(c),
          );
        },
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.label,
    required this.ringColor,
    this.imagePath,
    this.onTap,
  });

  final String label;
  final Color ringColor;
  final String? imagePath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    Widget avatar;
    final path = imagePath;
    if (path != null && File(path).existsSync()) {
      avatar = ClipOval(
        child: Image.file(
          File(path),
          width: size - 6,
          height: size - 6,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CircleAvatar(
            radius: (size - 6) / 2,
            backgroundColor: Colors.grey[800],
            child: const Icon(Icons.broken_image, color: Colors.white54, size: 20),
          ),
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: (size - 6) / 2,
        backgroundColor: Colors.grey[800],
        child: const Icon(
          Icons.person,
          color: Colors.white60,
          size: 24,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 2.5),
              ),
              child: avatar,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 76,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
