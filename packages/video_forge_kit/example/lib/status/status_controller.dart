import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/status_composer_page.dart';
import '../video_picker.dart';
import 'status_item.dart';
import 'status_pipeline.dart';

/// State for the WhatsApp-style Status tab (independent of [DemoSession]).
class StatusController extends ChangeNotifier {
  StatusController({this.maxPick = 8})
      : _pipeline = StatusPipeline(
          onItemUpdated: (item) {},
          maxConcurrent: 2,
        ) {
    _pipeline.onItemUpdated = _handleItemUpdated;
  }

  final int maxPick;
  final StatusPipeline _pipeline;

  final List<StatusItem> _items = [];
  bool _initialized = false;
  bool _busy = false;
  String? _error;

  List<StatusItem> get items => List.unmodifiable(_items);
  List<StatusItem> get readyItems =>
      _items.where((i) => i.isReady).toList(growable: false);
  List<StatusItem> get draftItems =>
      _items.where((i) => i.isDraft || i.isPreparing).toList(growable: false);
  List<StatusItem> get inFlightItems =>
      _items.where((i) => i.isInFlight).toList(growable: false);
  List<StatusItem> get failedItems =>
      _items.where((i) => i.isFailed).toList(growable: false);

  bool get initialized => _initialized;
  bool get busy => _busy;
  String? get error => _error;

  int get pendingCount => _pipeline.pendingCount;
  int get runningCount => _pipeline.runningCount;

  int get readyCount => readyItems.length;
  int get totalCount => _items.length;

  StatusItem? itemById(String id) {
    try {
      return _items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  int get savedBytes {
    var saved = 0;
    for (final item in readyItems) {
      final orig = item.originalBytes;
      final comp = item.compressedBytes;
      if (orig != null && comp != null && orig > comp) {
        saved += orig - comp;
      }
    }
    return saved;
  }

  int get sumJobMs {
    var sum = 0;
    for (final item in readyItems) {
      final d = item.jobDuration;
      if (d != null) sum += d.inMilliseconds;
    }
    return sum;
  }

  Duration? get batchWallClock {
    final start = _pipeline.batchStartedAt;
    if (start == null) return null;
    final done = _items.where((i) => i.finishedAt != null).toList();
    if (done.isEmpty) return null;
    final last = done
        .map((i) => i.finishedAt!)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return last.difference(start);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _pipeline.ensureInitialized();
      _initialized = true;
    } catch (e) {
      _error = 'Initialize failed: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _handleItemUpdated(StatusItem item) {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index >= 0) {
      _items[index] = item;
      notifyListeners();
    }
  }

  Future<void> ensureDraftReady(String id) async {
    final item = itemById(id);
    if (item == null || item.isDraft || item.isFailed) return;
    if (!item.isPreparing) return;
    await _pipeline.prepareDraft(item);
  }

  /// Pick videos → prepare drafts → open composer for the first clip.
  Future<void> addFromPicker({required BuildContext context}) async {
    if (!_initialized) await initialize();
    if (!context.mounted) return;

    final paths = await pickMultipleVideoPaths(context: context, max: maxPick);
    if (paths.isEmpty) return;
    if (!context.mounted) return;

    await addFromPaths(context, paths);
  }

  Future<void> addFromPaths(BuildContext context, List<String> paths) async {
    if (!_initialized) await initialize();
    if (!context.mounted) return;

    _busy = true;
    _error = null;
    notifyListeners();

    final newIds = <String>[];
    for (final path in paths) {
      final item = _pipeline.createItem(path);
      _items.insert(0, item);
      newIds.add(item.id);
      notifyListeners();
      unawaited(_pipeline.prepareDraft(item));
    }

    _busy = false;
    notifyListeners();

    if (newIds.isEmpty) return;
    if (!context.mounted) return;
    await openComposer(context, newIds.first);

    for (var i = 1; i < newIds.length; i++) {
      if (!context.mounted) break;
      final next = itemById(newIds[i]);
      if (next != null && (next.isDraft || next.isPreparing)) {
        final continueNext = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Another video'),
            content: Text(
              'Trim and post "${next.displayName}" (${i + 1} of ${newIds.length})?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (continueNext == true && context.mounted) {
          await openComposer(context, newIds[i]);
        }
      }
    }
  }

  Future<bool> openComposer(BuildContext context, String itemId) async {
    if (!_initialized) await initialize();
    if (!context.mounted) return false;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => StatusComposerPage(
          controller: this,
          itemId: itemId,
        ),
      ),
    );
    return result == true;
  }

  Future<bool> postDraft(
    String id, {
    required double trimStartSec,
    required double trimEndSec,
  }) async {
    final item = itemById(id);
    if (item == null || !item.isDraft) return false;
    unawaited(
      _pipeline.postItem(
        item,
        trimStartSec: trimStartSec,
        trimEndSec: trimEndSec,
      ),
    );
    return true;
  }

  void removeItem(String id) {
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _pipeline.dispose();
    super.dispose();
  }
}
