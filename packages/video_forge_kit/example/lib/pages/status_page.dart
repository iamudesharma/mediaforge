import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../status/status_controller.dart';
import '../status/status_item.dart';
import '../status/status_preview_page.dart';
import '../status/widgets/status_add_button.dart';
import '../status/widgets/status_item_tile.dart';
import '../status/widgets/updates_strip.dart';

/// WhatsApp-style Status: multi-pick, parallel WhatsApp compress, mock Updates feed.
class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage>
    with SingleTickerProviderStateMixin {
  final _controller = StatusController();
  late final TabController _tabs;

  static const _mockContacts = [
    MockStatusContact(
      name: 'Aarav',
      ringColor: Color(0xFF25D366),
      hint: 'Tap after you add statuses in My Status',
    ),
    MockStatusContact(
      name: 'Family',
      ringColor: Color(0xFF128C7E),
      hint: 'Demo contact',
    ),
    MockStatusContact(
      name: 'Work',
      ringColor: Color(0xFF34B7F1),
      hint: 'Demo contact',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_controller.initialize());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _openPreview(String path, {String? title}) {
    if (path.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatusPreviewPage(videoPath: path, title: title),
      ),
    );
  }

  void _showMockHint(MockStatusContact contact) {
    final ready = _controller.readyItems;
    if (ready.isNotEmpty && ready.first.outputPath != null) {
      _openPreview(ready.first.outputPath!, title: contact.name);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          contact.hint ??
              'Add statuses in My Status first — then your compressed clip appears here.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: TabBar(
                controller: _tabs,
                tabs: const [
                  Tab(text: 'My Status'),
                  Tab(text: 'Updates'),
                ],
              ),
            ),
            if (_controller.inFlightItems.isNotEmpty ||
                _controller.readyCount > 0 ||
                _controller.runningCount > 0)
              _PerformanceCard(controller: _controller),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _MyStatusTab(
                    controller: _controller,
                    onAdd: () => _controller.addFromPicker(context: context),
                    onPreview: (item) {
                      final path = item.outputPath;
                      if (path != null) _openPreview(path, title: item.displayName);
                    },
                    onTrimAndPost: (id) =>
                        _controller.openComposer(context, id),
                    onRemove: (id) => _controller.removeItem(id),
                  ),
                  _UpdatesTab(
                    contacts: _mockContacts,
                    readyItems: _controller.readyItems,
                    onContactTap: _showMockHint,
                    onReadyTap: (item) {
                      final path = item.outputPath;
                      if (path != null) _openPreview(path, title: 'Your status');
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({required this.controller});

  final StatusController controller;

  @override
  Widget build(BuildContext context) {
    final wall = controller.batchWallClock;
    final sumMs = controller.sumJobMs;
    final saved = controller.savedBytes;
    final serialEst = sumMs > 0 && wall != null
        ? (sumMs / 1000).toStringAsFixed(1)
        : null;

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rust queue · ${controller.runningCount}/2 running · '
              '${controller.pendingCount} waiting',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${controller.readyCount}/${controller.totalCount} ready',
                if (saved > 0) 'saved ${(saved / (1024 * 1024)).toStringAsFixed(1)} MB',
                if (wall != null) 'wall ${(wall.inMilliseconds / 1000).toStringAsFixed(1)}s',
                if (serialEst != null && wall != null)
                  '~${serialEst}s if serial',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _MyStatusTab extends StatelessWidget {
  const _MyStatusTab({
    required this.controller,
    required this.onAdd,
    required this.onPreview,
    required this.onTrimAndPost,
    required this.onRemove,
  });

  final StatusController controller;
  final Future<void> Function() onAdd;
  final void Function(StatusItem item) onPreview;
  final void Function(String id) onTrimAndPost;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    final ready = controller.readyItems;
    final drafts = controller.draftItems;
    final inFlight = controller.inFlightItems;
    final failed = controller.failedItems;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Your status',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              StatusAddButton(
                onTap: controller.busy ? null : () => unawaited(onAdd()),
                enabled: !controller.busy && controller.initialized,
              ),
              const SizedBox(width: 12),
              ...ready.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _ReadyBubble(
                    item: item,
                    onTap: () => onPreview(item),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (controller.error != null) ...[
          const SizedBox(height: 8),
          Text(
            controller.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (drafts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Drafts', style: Theme.of(context).textTheme.titleSmall),
          ...drafts.map(
            (item) => StatusItemTile(
              item: item,
              onPreview: () {},
              onRemove: () => onRemove(item.id),
              onTrimAndPost: item.isDraft
                  ? () => onTrimAndPost(item.id)
                  : null,
            ),
          ),
        ],
        if (inFlight.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Compressing', style: Theme.of(context).textTheme.titleSmall),
          ...inFlight.map(
            (item) => StatusItemTile(
              item: item,
              onPreview: () {},
              onRemove: () => onRemove(item.id),
            ),
          ),
        ],
        if (ready.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Ready', style: Theme.of(context).textTheme.titleSmall),
          ...ready.map(
            (item) => StatusItemTile(
              item: item,
              onPreview: () => onPreview(item),
              onRemove: () => onRemove(item.id),
            ),
          ),
        ],
        if (failed.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Failed', style: Theme.of(context).textTheme.titleSmall),
          ...failed.map(
            (item) => StatusItemTile(
              item: item,
              onPreview: () {},
              onRemove: () => onRemove(item.id),
            ),
          ),
        ],
        if (controller.items.isEmpty) ...[
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Tap Add status to pick videos from your gallery.\n'
              'Preview and trim first (like WhatsApp) — compress only runs '
              'when you tap Post (max 2 parallel jobs, WhatsApp preset).',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ReadyBubble extends StatelessWidget {
  const _ReadyBubble({required this.item, required this.onTap});

  final StatusItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = item.thumbPath;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: StatusAddButton.whatsAppGreen, width: 2.5),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundImage:
                  path != null ? FileImage(File(path)) : null,
              child: path == null ? const Icon(Icons.movie) : null,
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              item.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdatesTab extends StatelessWidget {
  const _UpdatesTab({
    required this.contacts,
    required this.readyItems,
    required this.onContactTap,
    required this.onReadyTap,
  });

  final List<MockStatusContact> contacts;
  final List<StatusItem> readyItems;
  final void Function(MockStatusContact contact) onContactTap;
  final void Function(StatusItem item) onReadyTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        Text(
          'Recent updates',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Demo contacts — tap to preview your compressed status when ready.',
          ),
        ),
        UpdatesStrip(
          contacts: contacts,
          onTapContact: onContactTap,
          readyItems: readyItems,
          onTapReady: onReadyTap,
        ),
        const SizedBox(height: 24),
        ...contacts.map(
          (c) => ListTile(
            leading: CircleAvatar(
              backgroundColor: c.ringColor.withValues(alpha: 0.2),
              child: Icon(Icons.person, color: c.ringColor),
            ),
            title: Text(c.name),
            subtitle: Text(c.hint ?? 'Status update'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onContactTap(c),
          ),
        ),
      ],
    );
  }
}
