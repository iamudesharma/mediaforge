import 'dart:io';

import 'package:flutter/material.dart';

import '../status_item.dart';

class MockStatusContact {
  const MockStatusContact({
    required this.name,
    required this.ringColor,
    this.previewPath,
    this.hint,
  });

  final String name;
  final Color ringColor;
  final String? previewPath;
  final String? hint;
}

/// Mock friends row for the Updates tab.
class UpdatesStrip extends StatelessWidget {
  const UpdatesStrip({
    super.key,
    required this.contacts,
    required this.onTapContact,
    this.readyItems = const [],
    this.onTapReady,
  });

  final List<MockStatusContact> contacts;
  final void Function(MockStatusContact contact) onTapContact;
  final List<StatusItem> readyItems;
  final void Function(StatusItem item)? onTapReady;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          ...contacts.map(
            (c) => _Bubble(
              label: c.name,
              ringColor: c.ringColor,
              imagePath: c.previewPath,
              onTap: () => onTapContact(c),
            ),
          ),
          if (readyItems.isNotEmpty) ...[
            const SizedBox(width: 8),
            VerticalDivider(
              width: 24,
              color: Theme.of(context).dividerColor,
            ),
            ...readyItems.take(3).map(
              (item) => _Bubble(
                label: 'You',
                ringColor: const Color(0xFF25D366),
                imagePath: item.thumbPath,
                onTap: onTapReady != null ? () => onTapReady!(item) : null,
              ),
            ),
          ],
        ],
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
        ),
      );
    } else {
      avatar = CircleAvatar(
        radius: (size - 6) / 2,
        child: Icon(
          Icons.person,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
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
              width: 72,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
