import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/services/coalesce_tracker.dart';

void main() {
  test('supersedes stale in-flight operation', () async {
    final tracker = CoalesceTracker();

    final first = tracker.execute('preview', (id) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return 'first-$id';
    });

    await Future<void>.delayed(const Duration(milliseconds: 5));

    final second = tracker.execute('preview', (id) async {
      return 'second-$id';
    });

    expect(await second, startsWith('second-'));
    await expectLater(first, throwsA(isA<CoalesceCancelledException>()));
  });

  test('tracks independent op types', () async {
    final tracker = CoalesceTracker();
    final a = tracker.execute('a', (_) async => 1);
    final b = tracker.execute('b', (_) async => 2);
    expect(await a, 1);
    expect(await b, 2);
  });

  test('isCurrent reflects latest generation', () async {
    final tracker = CoalesceTracker();
    final id1 = tracker.nextRequestId('x');
    expect(tracker.isCurrent('x', id1), isTrue);
    final id2 = tracker.nextRequestId('x');
    expect(tracker.isCurrent('x', id1), isFalse);
    expect(tracker.isCurrent('x', id2), isTrue);
  });
}
